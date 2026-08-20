///|
const DEFAULT_ENDPOINT_PATH : String = "/orbit/v1/invoke"

///|
const MAX_IPC_MESSAGE_BYTES : Int = 262_144

///|
pub(all) suberror HttpAdapterError {
  InvalidAuthenticatedClient(String)
  InvalidAdapterConfiguration(String)
} derive(Debug)

///|
/// A principal identity produced by a host-owned authentication mechanism.
/// HTTP headers never become an Orbit principal without this value.
pub struct AuthenticatedHttpClient {
  priv identifier : String
}

///|
pub fn AuthenticatedHttpClient::new(
  identifier : String,
) -> AuthenticatedHttpClient raise HttpAdapterError {
  ignore(@ipc.InvocationContext::http_client(identifier)) catch {
    _ => raise InvalidAuthenticatedClient(identifier)
  }
  { identifier, }
}

///|
pub fn AuthenticatedHttpClient::identifier(
  self : AuthenticatedHttpClient,
) -> String {
  self.identifier
}

///|
/// Metadata supplied to the required host authentication callback.
/// Request bodies are deliberately excluded so authentication happens before
/// Orbit reads or parses attacker-controlled command payloads.
pub struct HttpRequestMetadata {
  priv path : String
  priv headers : @http.Headers
  priv remote_address : String
}

///|
pub fn HttpRequestMetadata::path(self : HttpRequestMetadata) -> String {
  self.path
}

///|
pub fn HttpRequestMetadata::header(
  self : HttpRequestMetadata,
  name : String,
) -> String? {
  self.headers.get(name)
}

///|
pub fn HttpRequestMetadata::remote_address(
  self : HttpRequestMetadata,
) -> String {
  self.remote_address
}

///|
priv struct PreparedRequest {
  client : AuthenticatedHttpClient
  origin : String?
}

///|
priv struct AdapterResponse {
  status : Int
  reason : String
  body : String
  headers : @http.Headers
}

///|
priv enum BodyReadError {
  TooLarge
  InvalidUtf8
}

///|
fn adapter_failure(
  status : Int,
  reason : String,
  code : String,
  message : String,
  headers? : @http.Headers = Map([]),
) -> AdapterResponse {
  {
    status,
    reason,
    body: @ipc.encode_command_failure(
      None,
      @ipc.CommandFailure::new(code~, message~),
    ),
    headers,
  }
}

///|
fn valid_endpoint_path(path : String) -> Bool {
  if path.is_empty() || path.length() > 256 || !path.has_prefix("/") {
    return false
  }
  for char in path {
    let code = char.to_int()
    if code <= 32 || code == 127 || char == '?' || char == '#' {
      return false
    }
  }
  true
}

///|
fn is_json_content_type(value : String) -> Bool {
  let media_type = match value.find(";") {
    Some(index) => value[:index]
    None => value
  }
  media_type.trim().to_lower() == "application/json"
}

///|
fn content_length(headers : @http.Headers) -> Int? raise {
  match headers.get("content-length") {
    None => None
    Some(value) => Some(@string.parse_int(value.trim(), base=10))
  }
}

///|
fn validate_body_headers(
  headers : @http.Headers,
  max_request_bytes : Int,
) -> Result[Int?, AdapterResponse] {
  if headers.contains("content-length") && headers.contains("transfer-encoding") {
    return Err(
      adapter_failure(
        400, "Bad Request", "ambiguous_body_framing", "Content-Length and Transfer-Encoding cannot be combined",
      ),
    )
  }
  let declared_length = content_length(headers) catch {
    _ =>
      return Err(
        adapter_failure(
          400, "Bad Request", "invalid_content_length", "invalid Content-Length",
        ),
      )
  }
  match declared_length {
    Some(length) if length < 0 =>
      Err(
        adapter_failure(
          400, "Bad Request", "invalid_content_length", "invalid Content-Length",
        ),
      )
    Some(length) if length > max_request_bytes =>
      Err(
        adapter_failure(
          413, "Content Too Large", "request_too_large", "HTTP invocation exceeds the configured request limit",
        ),
      )
    _ => Ok(declared_length)
  }
}

///|
async fn read_body_limited(
  body : &@io.Reader,
  limit : Int,
) -> Result[String, BodyReadError] {
  let chunks : Array[Bytes] = []
  let mut length = 0
  for ;; {
    let read_limit = @cmp.minimum(8_192, limit - length + 1)
    match body.read_some(max_len=read_limit) {
      None => break
      Some(chunk) => {
        length += chunk.length()
        if length > limit {
          return Err(TooLarge)
        }
        chunks.push(chunk)
      }
    }
  }
  let buffer = FixedArray::make(length, b'\x00')
  let mut offset = 0
  for chunk in chunks {
    buffer.blit_from_bytes(offset, chunk, 0, chunk.length())
    offset += chunk.length()
  }
  let source = @utf8.decode(buffer.unsafe_reinterpret_as_bytes()) catch {
    _ => return Err(InvalidUtf8)
  }
  Ok(source)
}

///|
pub struct HttpAdapter {
  priv registry : @ipc.CommandRegistry
  priv policy : @ipc.CommandPolicy
  priv authenticate : (HttpRequestMetadata) -> AuthenticatedHttpClient?
  priv endpoint_path : String
  priv max_request_bytes : Int
  priv max_response_chars : Int
}

///|
/// Creates an authenticated HTTP adapter without opening a listener.
///
/// The host must provide an authentication callback and owns listener, TLS,
/// shutdown and exposure policy. Returning `None` rejects the request before
/// its body is read. The callback should authenticate credentials or a trusted
/// upstream identity; it must not treat a caller-selected identifier as proof.
pub fn HttpAdapter::new(
  registry : @ipc.CommandRegistry,
  policy : @ipc.CommandPolicy,
  authenticate : (HttpRequestMetadata) -> AuthenticatedHttpClient?,
  endpoint_path? : String = DEFAULT_ENDPOINT_PATH,
  max_request_bytes? : Int = MAX_IPC_MESSAGE_BYTES,
  max_response_chars? : Int = MAX_IPC_MESSAGE_BYTES,
) -> HttpAdapter raise HttpAdapterError {
  if !valid_endpoint_path(endpoint_path) {
    raise InvalidAdapterConfiguration("invalid HTTP invocation endpoint path")
  }
  if max_request_bytes < 256 || max_request_bytes > MAX_IPC_MESSAGE_BYTES {
    raise InvalidAdapterConfiguration(
      "request limit must be between 256 and 262144 bytes",
    )
  }
  if max_response_chars < 256 || max_response_chars > MAX_IPC_MESSAGE_BYTES {
    raise InvalidAdapterConfiguration(
      "response limit must be between 256 and 262144 characters",
    )
  }
  {
    registry,
    policy,
    authenticate,
    endpoint_path,
    max_request_bytes,
    max_response_chars,
  }
}

///|
pub fn HttpAdapter::endpoint_path(self : HttpAdapter) -> String {
  self.endpoint_path
}

///|
fn HttpAdapter::prepare(
  self : HttpAdapter,
  request : @http.Request,
  remote_address : String,
) -> Result[PreparedRequest, AdapterResponse] {
  if request.path != self.endpoint_path {
    return Err(
      adapter_failure(404, "Not Found", "not_found", "endpoint not found"),
    )
  }
  if request.meth != Post {
    return Err(
      adapter_failure(
        405,
        "Method Not Allowed",
        "method_not_allowed",
        "HTTP invocation requires POST",
        headers={ "Allow": "POST" },
      ),
    )
  }
  match request.headers.get("content-type") {
    Some(value) if is_json_content_type(value) => ()
    _ =>
      return Err(
        adapter_failure(
          415, "Unsupported Media Type", "unsupported_media_type", "HTTP invocation requires application/json",
        ),
      )
  }
  let metadata = HttpRequestMetadata::{
    path: request.path,
    headers: request.headers,
    remote_address,
  }
  let client = match (self.authenticate)(metadata) {
    Some(client) => client
    None =>
      return Err(
        adapter_failure(
          401, "Unauthorized", "unauthorized", "authentication required",
        ),
      )
  }
  Ok({ client, origin: request.headers.get("origin") })
}

///|
async fn HttpAdapter::dispatch_source(
  self : HttpAdapter,
  prepared : PreparedRequest,
  source : String,
) -> AdapterResponse {
  let context = (match prepared.origin {
    Some(origin) =>
      @ipc.InvocationContext::http_client(prepared.client.identifier, origin~)
    None => @ipc.InvocationContext::http_client(prepared.client.identifier)
  }).with_response_limit(self.max_response_chars) catch {
    _ =>
      return adapter_failure(
        400, "Bad Request", "invalid_context", "invalid HTTP invocation context",
      )
  }
  let response = @ipc_async.dispatch_source_with_deadline(
    self.registry,
    self.policy,
    context,
    source,
  )
  { status: 200, reason: "OK", body: response, headers: Map([]) }
}

///|
async fn send_response(
  connection : @http.ServerConnection,
  response : AdapterResponse,
) -> Unit {
  let headers : @http.Headers = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  }
  for name, value in response.headers {
    headers[name] = value
  }
  connection.send_response(
    response.status,
    response.reason,
    extra_headers=headers,
  )
  connection.write_string(response.body)
  connection.end_response()
}

///|
/// Handles one request from `moonbitlang/async/http`.
pub async fn HttpAdapter::handle(
  self : HttpAdapter,
  request : @http.Request,
  body : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  let prepared = match
    self.prepare(request, connection.client_addr().to_string()) {
    Ok(prepared) => prepared
    Err(response) => {
      send_response(connection, response)
      return
    }
  }
  match validate_body_headers(request.headers, self.max_request_bytes) {
    Err(response) => {
      send_response(connection, response)
      return
    }
    Ok(_) => ()
  }
  let source = match read_body_limited(body, self.max_request_bytes) {
    Ok(source) => source
    Err(TooLarge) => {
      send_response(
        connection,
        adapter_failure(
          413, "Content Too Large", "request_too_large", "HTTP invocation exceeds the configured request limit",
        ),
      )
      return
    }
    Err(InvalidUtf8) => {
      send_response(
        connection,
        adapter_failure(
          400, "Bad Request", "invalid_encoding", "HTTP invocation body must be valid UTF-8",
        ),
      )
      return
    }
  }
  send_response(connection, self.dispatch_source(prepared, source))
}

///|
/// Serves the adapter on a host-created HTTP server. The caller retains the
/// server handle and can close it as part of structured shutdown.
pub async fn HttpAdapter::serve(
  self : HttpAdapter,
  server : @http.Server,
  max_connections? : Int,
) -> Unit {
  server.run_forever(allow_failure=true, max_connections?) <| ((
    request,
    body,
    connection,
  ) => self.handle(request, body, connection))
}

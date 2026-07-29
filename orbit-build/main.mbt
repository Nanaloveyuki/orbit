///|
fn[T] abort_build(message : String) -> T {
  abort("orbit-build: \{message}")
}

///|
fn normalized_path(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn parent_path(path : String) -> String {
  let chars = normalized_path(path).to_array()
  let mut separator = -1
  for index = 0; index < chars.length(); index = index + 1 {
    if chars[index] == '/' {
      separator = index
    }
  }
  if separator < 0 {
    "."
  } else if separator == 0 {
    "/"
  } else {
    String::from_array(chars[:separator])
  }
}

///|
fn join_path(left : String, right : String) -> String {
  if left.has_suffix("/") {
    "\{left}\{right}"
  } else {
    "\{left}/\{right}"
  }
}

///|
fn file_name(path : String) -> String {
  let chars = normalized_path(path).to_array()
  let mut separator = -1
  for index = 0; index < chars.length(); index = index + 1 {
    if chars[index] == '/' {
      separator = index
    }
  }
  if separator < 0 {
    path
  } else {
    String::from_array(chars[separator + 1:])
  }
}

///|
fn has_path_prefix(path : String, root : String) -> Bool {
  path == root || path.has_prefix("\{root}/")
}

///|
fn primary_window(config : @utils.OrbitConfig) -> @utils.WindowConfig {
  if config.windows.length() != 1 {
    abort_build("desktop generation currently requires exactly one window")
  }
  match config.windows.get(0) {
    Some(window) => window
    None => abort_build("configuration must contain one window")
  }
}

///|
struct Asset {
  path : String
  media_type : String
  bytes : Bytes
}

///|
fn media_type(path : String) -> String {
  if path.has_suffix(".html") || path.has_suffix(".htm") {
    "text/html; charset=utf-8"
  } else if path.has_suffix(".css") {
    "text/css; charset=utf-8"
  } else if path.has_suffix(".js") || path.has_suffix(".mjs") {
    "text/javascript; charset=utf-8"
  } else if path.has_suffix(".json") {
    "application/json; charset=utf-8"
  } else if path.has_suffix(".svg") {
    "image/svg+xml"
  } else if path.has_suffix(".png") {
    "image/png"
  } else if path.has_suffix(".jpg") || path.has_suffix(".jpeg") {
    "image/jpeg"
  } else if path.has_suffix(".gif") {
    "image/gif"
  } else if path.has_suffix(".webp") {
    "image/webp"
  } else if path.has_suffix(".ico") {
    "image/x-icon"
  } else if path.has_suffix(".woff2") {
    "font/woff2"
  } else if path.has_suffix(".woff") {
    "font/woff"
  } else if path.has_suffix(".wasm") {
    "application/wasm"
  } else {
    "application/octet-stream"
  }
}

///|
async fn collect_assets(
  directory : String,
  relative_directory : String,
  config_path : String,
  output_path : String,
  assets : Array[Asset],
) -> Unit {
  let names = @fs.readdir(directory, include_hidden=true, sort=true)
  for name in names {
    let path = join_path(directory, name)
    let relative_path = if relative_directory.is_empty() {
      name
    } else {
      join_path(relative_directory, name)
    }
    let normalized = normalized_path(path)
    if normalized != config_path && normalized != output_path {
      match @fs.kind(path, follow_symlink=false) {
        Regular => {
          let resource_path = match
            @utils.normalize_resource_path(relative_path) {
            Ok(value) => value
            Err(_) => {
              abort_build(
                "asset path must be a normalized relative resource path",
              )
              ""
            }
          }
          assets.push({
            path: resource_path,
            media_type: media_type(resource_path),
            bytes: @fs.read_file(path).binary(),
          })
        }
        Directory =>
          collect_assets(path, relative_path, config_path, output_path, assets)
        SymLink => abort_build("asset tree must not contain symbolic links")
        _ => ()
      }
    }
  }
}

///|
fn bytes_expression(bytes : Bytes) -> String {
  if bytes.length() == 0 {
    return "b\"\""
  }
  let lines = []
  let values = []
  for index = 0; index < bytes.length(); index = index + 1 {
    values.push("\{bytes[index]}")
    if values.length() == 8 {
      lines.push("            \{values.join(", ")},")
      values.clear()
    }
  }
  if !values.is_empty() {
    lines.push("            \{values.join(", ")},")
  }
  "Bytes::from_array([\n\{lines.join("\n")}\n          ])"
}

///|
fn generated_source(
  scheme : String,
  config : @utils.OrbitConfig,
  fingerprint : String,
  canonical_json : String,
  assets : Array[Asset],
) -> String {
  let cases = []
  for asset in assets {
    let uri = Json::string("\{scheme}://app/\{asset.path}").stringify()
    let media = Json::string(asset.media_type).stringify()
    cases.push(
      "    \{uri} =>\n      Some(\n        @runtime.RuntimeResourceResponse::new(\n          status=200,\n          media_type=\{media},\n          body=\{bytes_expression(asset.bytes)},\n        ),\n      )",
    )
  }
  let window = primary_window(config)
  let entry_url = Json::string("\{scheme}://app/\{file_name(window.entry)}").stringify()
  let scheme = Json::string(scheme).stringify()
  let app_identifier = Json::string(config.app.identifier).stringify()
  let app_name = Json::string(config.app.name).stringify()
  let app_version = Json::string(config.app.version).stringify()
  let window_label = Json::string(window.label).stringify()
  let window_title = Json::string(window.title).stringify()
  let canonical_json = Json::string(canonical_json).stringify()
  let fingerprint = Json::string(fingerprint).stringify()
  "// Generated by orbit-build. DO NOT EDIT.\n\n///|\npub let app_identifier = \{app_identifier}\n\n///|\npub let app_name = \{app_name}\n\n///|\npub let app_version = \{app_version}\n\n///|\npub let configuration_json = \{canonical_json}\n\n///|\npub let configuration_fingerprint = \{fingerprint}\n\n///|\npub let window_label = \{window_label}\n\n///|\npub let window_title = \{window_title}\n\n///|\npub let window_width = \{window.width}\n\n///|\npub let window_height = \{window.height}\n\n///|\npub let window_visible = \{window.visible}\n\n///|\npub let window_resizable = \{window.resizable}\n\n///|\npub let resource_scheme = \{scheme}\n\n///|\npub let entry_url = \{entry_url}\n\n///|\npub fn resource_response(uri : String) -> @runtime.RuntimeResourceResponse? {\n  match uri {\n\{cases.join("\n")}\n    _ => None\n  }\n}\n\n///|\npub fn handle_resource(\n  request : @runtime.RuntimeResourceRequest,\n) -> @runtime.RuntimeResourceResponse? {\n  resource_response(request.uri())\n}\n"
}

///|
async fn write_if_changed(output : String, content : String) -> Unit {
  let unchanged = if @fs.exists(output) {
    @fs.read_file(output).text() == content
  } else {
    false
  }
  if !unchanged {
    let temporary = "\{output}.tmp"
    @fs.write_file(temporary, content, create_mode=CreateOrTruncate)
    @fs.rename(temporary, output, replace=true)
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() != 3 {
    abort_build("usage: moon run orbit-build <orbit.conf.json> <generated.mbt>")
  }
  let config_path = args[1]
  let output_path = args[2]
  let config_path = @fs.realpath(config_path)
  let asset_root = parent_path(config_path)
  let output_parent = @fs.realpath(parent_path(output_path))
  let output_path = join_path(output_parent, file_name(output_path))
  let config_text = @fs.read_file(config_path).text()
  let config = match @strict_json.parse(config_text) {
    Ok(value) => value
    Err(_) => {
      abort_build("invalid strict JSON configuration")
      Null
    }
  }
  ignore(config)
  let compiled = @utils.compile_config(config_text) catch {
    _ => abort_build("configuration does not satisfy the Orbit schema")
  }
  let orbit_config = @utils.parse_config(config_text) catch {
    _ => abort_build("configuration does not satisfy the Orbit schema")
  }
  let window = primary_window(orbit_config)
  let entry = window.entry
  let entry_path = @fs.realpath(join_path(asset_root, entry))
  if !has_path_prefix(normalized_path(entry_path), normalized_path(asset_root)) {
    abort_build("entry escapes the asset root")
  }
  let resource_root = parent_path(entry_path)
  let entry = file_name(entry)
  if !entry.has_suffix(".html") && !entry.has_suffix(".htm") {
    abort_build("entry must be an HTML document for CSP injection")
  }
  let entry_html = @fs.read_file(entry_path).text()
  let entry_html = @utils.inject_csp(entry_html, orbit_config.security.csp) catch {
    _ =>
      abort_build("could not inject the configured CSP into the entry document")
  }
  let assets = []
  collect_assets(
    resource_root,
    "",
    normalized_path(config_path),
    normalized_path(output_path),
    assets,
  )
  let entry_is_embedded = assets.any(asset => asset.path == entry)
  if !entry_is_embedded {
    abort_build("entry must be a regular file below the asset root")
  }
  for index = 0; index < assets.length(); index = index + 1 {
    if assets[index].path == entry {
      assets[index] = {
        ..assets[index],
        bytes: @utf8.encode(entry_html[:], bom=false),
      }
    }
  }
  write_if_changed(
    output_path,
    generated_source(
      "orbit",
      orbit_config,
      compiled.fingerprint(),
      compiled.canonical_json(),
      assets,
    ),
  )
}

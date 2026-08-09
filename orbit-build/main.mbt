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
  match config.app.windows.get(0) {
    Some(window) => window
    None => abort_build("configuration must contain at least one window")
  }
}

///|
fn window_embedded_entry(
  config : @utils.OrbitConfig,
  window : @utils.WindowConfig,
) -> String {
  match config.web.remote {
    Some(remote) => remote.fallback_entry
    None => window.entry
  }
}

///|
fn window_resource_root(
  config : @utils.OrbitConfig,
  window : @utils.WindowConfig,
) -> String {
  parent_path(window_embedded_entry(config, window))
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
fn is_text_resource(path : String) -> Bool {
  path.has_suffix(".html") ||
  path.has_suffix(".htm") ||
  path.has_suffix(".css") ||
  path.has_suffix(".js") ||
  path.has_suffix(".mjs") ||
  path.has_suffix(".json") ||
  path.has_suffix(".svg")
}

///|
fn normalize_text_line_endings(source : String) -> String {
  source.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
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
          let bytes = if is_text_resource(resource_path) {
            @utf8.encode(
              normalize_text_line_endings(@fs.read_file(path).text()),
              bom=false,
            )
          } else {
            @fs.read_file(path).binary()
          }
          assets.push({
            path: resource_path,
            media_type: media_type(resource_path),
            bytes,
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
fn string_array_expression(values : Array[String]) -> String {
  let entries = values.map(value => Json::string(value).stringify())
  "[\{entries.join(", ")}]"
}

///|
fn principal_expression(principal : @utils.PrincipalConfig) -> String {
  let identifier = Json::string(principal.identifier).stringify()
  match principal.kind {
    "window" => "@ipc.PrincipalSelector::window(\{identifier})"
    "remote_page" => "@ipc.PrincipalSelector::remote_page(\{identifier})"
    "http_client" => "@ipc.PrincipalSelector::http_client(\{identifier})"
    "plugin" => "@ipc.PrincipalSelector::plugin(\{identifier})"
    "background_task" =>
      "@ipc.PrincipalSelector::background_task(\{identifier})"
    _ => abort_build("configuration contains an invalid principal")
  }
}

///|
fn scope_expression(scope : @utils.ScopeConfig) -> String {
  match scope.kind {
    "transport" => {
      let transport = match scope.value {
        "moonview" => "@ipc.InvocationTransport::moonview()"
        "http" => "@ipc.InvocationTransport::http()"
        "plugin" => "@ipc.InvocationTransport::plugin()"
        "background" => "@ipc.InvocationTransport::background()"
        _ => abort_build("configuration contains an invalid transport scope")
      }
      "@ipc.InvocationScope::transport(\{transport})"
    }
    "origin" =>
      "@ipc.InvocationScope::origin(\{Json::string(scope.value).stringify()})"
    _ => abort_build("configuration contains an invalid scope")
  }
}

///|
fn capabilities_expression(config : @utils.OrbitConfig) -> String {
  let declarations = []
  for capability in config.capabilities {
    let identifier = Json::string(capability.identifier).stringify()
    let effect = match capability.effect {
      "allow" => "@ipc.CapabilityEffect::allow()"
      "deny" => "@ipc.CapabilityEffect::deny()"
      _ => abort_build("configuration contains an invalid capability effect")
    }
    let principals = capability.principals.map(principal_expression).join(", ")
    let scopes = capability.scopes.map(scope_expression).join(", ")
    let commands = capability.commands.map(command => {
      "@ipc.CommandName::new(\{Json::string(command).stringify()})"
    })
    declarations.push(
      "  policy.add_grant(\n    @ipc.CommandGrant::new(\n      identifier=\{identifier},\n      effect=\{effect},\n      principals=[\{principals}],\n      scopes=[\{scopes}],\n      commands=[\{commands.join(", ")}],\n    ),\n  )",
    )
  }
  declarations.join("\n")
}

///|
fn plugins_expression(
  config : @utils.OrbitConfig,
  sidecars : Array[String],
) -> String {
  let declarations = []
  for index, plugin in config.plugins {
    let id = Json::string(plugin.id).stringify()
    let library = Json::string(plugin.library).stringify()
    let permissions = string_array_expression(plugin.permissions)
    let sidecar = match sidecars.get(index) {
      Some(source) => Json::string(source).stringify()
      None => abort_build("plugin sidecar source is missing")
    }
    declarations.push(
      "  @plugin.PluginDeclaration::new(\n    id=\{id},\n    library=\{library},\n    sidecar=match @plugin.parse_sidecar_manifest(\{sidecar}) {\n      Ok(value) => value\n      Err(_) => abort(\"invalid generated plugin sidecar\")\n    },\n    permissions=\{permissions},\n  ),",
    )
  }
  declarations.join("\n")
}

///|
fn indent_lines(source : String, prefix : String) -> String {
  source.split("\n").map(line => prefix + line.to_owned()).join("\n")
}

///|
fn windows_expression(
  config : @utils.OrbitConfig,
  scheme : String,
  development_url : String?,
) -> String {
  let declarations = []
  for index, window in config.app.windows {
    let label = Json::string(window.label).stringify()
    let title = Json::string(window.title).stringify()
    let entry = match development_url {
      Some(url) => Json::string(url).stringify()
      None =>
        match config.web.remote {
          Some(remote) => Json::string(remote.http_url).stringify()
          None =>
            Json::string("\{scheme}://app/\{file_name(window.entry)}").stringify()
        }
    }
    let external_navigation = match development_url {
      Some(url) => {
        let url = Json::string(url).stringify()
        "      external_navigation_handler=url => url == \{url} || url.has_prefix(\{url} + \"/\"),\n"
      }
      None => ""
    }
    let resource_provider = match development_url {
      Some(_) => ""
      None =>
        "      resource_provider=Some(\n        @runtime.RuntimeResourceProvider::new(\n          scheme=resource_scheme,\n          handler=handle_resource_\{index},\n        ),\n      ),\n"
    }
    let remote_navigation = match (development_url, config.web.remote) {
      (None, Some(remote)) => {
        let origins = string_array_expression(remote.allowed_origins)
        let fallback = Json::string(
          "\{scheme}://app/\{file_name(remote.fallback_entry)}",
        ).stringify()
        "      remote_navigation=Some(\n        @runtime.RemoteNavigation::new(\n          allowed_origins=\{origins},\n          fallback_url=\{fallback},\n        ),\n      ),\n"
      }
      _ => ""
    }
    let ipc_principal = match (development_url, config.web.remote) {
      (None, Some(_)) =>
        "    ipc_principal=@core.DesktopIpcPrincipal::remote_page(),\n"
      _ => ""
    }
    declarations.push(
      "  @core.DesktopWindowOptions::new(\n    \{title},\n    @runtime.RuntimeOptions::new(\n      label=\{label},\n      bounds=@runtime.RuntimeBounds::new(width=\{window.width}, height=\{window.height}),\n      initial_content=Url(\{entry}),\n      visible=\{window.visible},\n\{external_navigation}\{resource_provider}\{remote_navigation}    ) catch {\n      _ => abort(\"invalid generated runtime options\")\n    },\n    resizable=\{window.resizable},\n\{ipc_principal}  ) catch {\n    _ => abort(\"invalid generated window options\")\n  },",
    )
  }
  declarations.join(",\n")
}

///|
fn resource_handlers_expression(
  scheme : String,
  config : @utils.OrbitConfig,
  asset_bundles : Array[Array[Asset]],
) -> String {
  let handlers = []
  for index, _window in config.app.windows {
    let assets = match asset_bundles.get(index) {
      Some(assets) => assets
      None => []
    }
    let cases = []
    for asset in assets {
      let uri = Json::string("\{scheme}://app/\{asset.path}").stringify()
      let media = Json::string(asset.media_type).stringify()
      cases.push(
        "    \{uri} =>\n      Some(\n        @runtime.RuntimeResourceResponse::new(\n          status=200,\n          media_type=\{media},\n          body=\{bytes_expression(asset.bytes)},\n        ),\n      )",
      )
    }
    handlers.push(
      "///|\npub fn resource_response_\{index}(uri : String) -> @runtime.RuntimeResourceResponse? {\n  match uri {\n\{cases.join("\n")}\n    _ => None\n  }\n}\n\n///|\npub fn handle_resource_\{index}(\n  request : @runtime.RuntimeResourceRequest,\n) -> @runtime.RuntimeResourceResponse? {\n  resource_response_\{index}(request.uri())\n}",
    )
  }
  handlers.join("\n\n")
}

///|
fn generated_source(
  scheme : String,
  config : @utils.OrbitConfig,
  fingerprint : String,
  canonical_json : String,
  asset_bundles : Array[Array[Asset]],
  development_url : String?,
  sidecars : Array[String],
) -> String {
  let window = primary_window(config)
  let entry_url = match development_url {
    Some(url) => Json::string(url).stringify()
    None =>
      match config.web.remote {
        Some(remote) => Json::string(remote.http_url).stringify()
        None =>
          Json::string("\{scheme}://app/\{file_name(window.entry)}").stringify()
      }
  }
  let scheme = Json::string(scheme).stringify()
  let app_identifier = Json::string(config.app.identifier).stringify()
  let app_name = Json::string(config.app.name).stringify()
  let app_version = Json::string(config.app.version).stringify()
  let app_product_name = match config.app.product_name {
    Some(value) => "Some(\{Json::string(value).stringify()})"
    None => "None"
  }
  let app_publisher = match config.app.publisher {
    Some(value) => "Some(\{Json::string(value).stringify()})"
    None => "None"
  }
  let window_label = Json::string(window.label).stringify()
  let window_title = Json::string(window.title).stringify()
  let canonical_json = Json::string(canonical_json).stringify()
  let fingerprint = Json::string(fingerprint).stringify()
  let capabilities = capabilities_expression(config)
  let plugins = plugins_expression(config, sidecars)
  let plugins = if plugins.is_empty() { "[]" } else { "[\n\{plugins}\n  ]" }
  let windows = indent_lines(
    windows_expression(config, "orbit", development_url),
    "  ",
  )
  let resource_handlers = resource_handlers_expression(
    scheme, config, asset_bundles,
  )
  "// Generated by orbit-build. DO NOT EDIT.\n\n///|\npub let app_identifier = \{app_identifier}\n\n///|\npub let app_name = \{app_name}\n\n///|\npub let app_version = \{app_version}\n\n///|\npub let app_product_name : String? = \{app_product_name}\n\n///|\npub let app_publisher : String? = \{app_publisher}\n\n///|\npub let configuration_json = \{canonical_json}\n\n///|\npub let configuration_fingerprint = \{fingerprint}\n\n///|\npub let window_label = \{window_label}\n\n///|\npub let window_title = \{window_title}\n\n///|\npub let window_width = \{window.width}\n\n///|\npub let window_height = \{window.height}\n\n///|\npub let window_visible = \{window.visible}\n\n///|\npub let window_resizable = \{window.resizable}\n\n///|\npub let resource_scheme = \{scheme}\n\n///|\npub let entry_url = \{entry_url}\n\n///|\npub fn configured_ipc_policy() -> @ipc.CommandPolicy raise @ipc.IpcError {\n  let policy = @ipc.CommandPolicy::new()\n\{capabilities}\n  policy\n}\n\n///|\npub fn configured_plugins() -> Array[@plugin.PluginDeclaration] {\n  \{plugins}\n}\n\n///|\npub fn configured_windows() -> Array[@core.DesktopWindowOptions] {\n  [\n\{windows}\n  ]\n}\n\n\{resource_handlers}\n\n///|\npub fn resource_response(uri : String) -> @runtime.RuntimeResourceResponse? {\n  resource_response_0(uri)\n}\n\n///|\npub fn handle_resource(\n  request : @runtime.RuntimeResourceRequest,\n) -> @runtime.RuntimeResourceResponse? {\n  handle_resource_0(request)\n}\n"
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
async fn write_bytes_if_changed(output : String, content : Bytes) -> Unit {
  let unchanged = if @fs.exists(output) {
    @fs.read_file(output).binary() == content
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
fn icon_sizes() -> Array[Int] {
  [16, 32, 48, 64, 128, 256, 512, 1024]
}

///|
async fn generate_icons(
  source_path : String,
  output_directory : String,
  compression_level : Int,
) -> Unit {
  if compression_level < 0 || compression_level > 9 {
    abort_build("icon compression level must be between 0 and 9")
  }
  let source_path = @fs.realpath(source_path)
  let output_directory = @fs.realpath(output_directory)
  let source = @fs.read_file(source_path).binary()
  let image = @image.decode_png(source) catch {
    _ => abort_build("icon source must be a valid bounded PNG")
  }
  if image.width != 1024 || image.height != 1024 {
    abort_build("icon source must be exactly 1024x1024 pixels")
  }
  let variants = @image.encode_png_sizes(
    image,
    icon_sizes(),
    compression_level~,
  ) catch {
    _ => abort_build("could not generate PNG icon sizes")
  }
  for variant in variants {
    write_bytes_if_changed(
      join_path(output_directory, "\{variant.size}x\{variant.size}.png"),
      variant.png,
    )
  }
  let ico = @image.encode_ico(image, compression_level~) catch {
    _ => abort_build("could not generate ICO icon")
  }
  write_bytes_if_changed(join_path(output_directory, "icon.ico"), ico)
  let icns = @image.encode_icns(image, compression_level~) catch {
    _ => abort_build("could not generate ICNS icon")
  }
  write_bytes_if_changed(join_path(output_directory, "icon.icns"), icns)
  let svg = @image.png_data_uri_svg(source, 1024, 1024) catch {
    _ => abort_build("could not generate SVG icon wrapper")
  }
  write_if_changed(join_path(output_directory, "icon.svg"), svg)
}

///|
async fn read_plugin_sidecars(
  configuration_directory : String,
  config : @utils.OrbitConfig,
) -> Array[String] {
  let sidecars = []
  for plugin in config.plugins {
    let path = @fs.realpath(join_path(configuration_directory, plugin.manifest))
    if !has_path_prefix(
        normalized_path(path),
        normalized_path(configuration_directory),
      ) {
      abort_build("plugin sidecar escapes the configuration directory")
    }
    let source = @fs.read_file(path).text()
    match @plugin.parse_sidecar_manifest(source) {
      Ok(sidecar) if sidecar.id == plugin.id => sidecars.push(source)
      Ok(_) =>
        abort_build("plugin sidecar identity does not match configuration")
      Err(_) => abort_build("plugin sidecar does not satisfy schema version 2")
    }
  }
  sidecars
}

///|
async fn migrate_config(input_path : String, output_path : String) -> Unit {
  let input_path = @fs.realpath(input_path)
  let output_parent = @fs.realpath(parent_path(output_path))
  let output_path = join_path(output_parent, file_name(output_path))
  if normalized_path(input_path) == normalized_path(output_path) {
    abort_build("migration output must differ from the input configuration")
  }
  if @fs.exists(output_path) {
    abort_build("migration output already exists")
  }
  let migrated = @utils.migrate_config_v1(@fs.read_file(input_path).text()) catch {
    _ =>
      abort_build(
        "configuration is not a valid schema_version 1 Orbit configuration",
      )
  }
  @fs.write_file(output_path, migrated + "\n", create_mode=CreateOrTruncate)
}

///|
fn vite_workflow_json(config : @utils.OrbitConfig) -> String {
  match config.build.vite {
    None => "{\"vite\":null}"
    Some(vite) =>
      "{\"vite\":{\"dev_command\":\{Json::string(vite.dev_command).stringify()},\"dev_url\":\{Json::string(vite.dev_url).stringify()},\"build_command\":\{Json::string(vite.build_command).stringify()},\"dist_dir\":\{Json::string(vite.dist_dir).stringify()}}}"
  }
}

///|
fn optional_json_string(value : String?) -> String {
  match value {
    Some(value) => Json::string(value).stringify()
    None => "null"
  }
}

///|
fn webview_install_mode(config : @utils.OrbitConfig) -> String {
  match config.bundle.windows {
    Some(windows) => windows.webview_install_mode
    None => "embed_bootstrapper"
  }
}

///|
fn package_compatibility_json() -> String {
  "{\"orbit\":\"0.1.0-alpha.1\",\"orby\":\"0.1.0-beta.3\",\"moonview\":\"0.1.0-beta.5\",\"plugin_abi\":2,\"plugin_sidecar_schema\":2,\"configuration_schema\":2}"
}

///|
fn package_metadata_json(
  config : @utils.OrbitConfig,
  fingerprint : String,
) -> String {
  let plugins = config.plugins
    .map(plugin => {
      "{\"id\":\{Json::string(plugin.id).stringify()},\"library\":\{Json::string(plugin.library).stringify()},\"manifest\":\{Json::string(plugin.manifest).stringify()}}"
    })
    .join(",")
  "{\"schema_version\":\{config.schema_version},\"configuration_fingerprint\":\{Json::string(fingerprint).stringify()},\"compatibility\":\{package_compatibility_json()},\"application\":{\"identifier\":\{Json::string(config.app.identifier).stringify()},\"name\":\{Json::string(config.app.name).stringify()},\"version\":\{Json::string(config.app.version).stringify()},\"product_name\":\{optional_json_string(config.app.product_name)},\"publisher\":\{optional_json_string(config.app.publisher)}},\"windows\":{\"webview_install_mode\":\{Json::string(webview_install_mode(config)).stringify()}},\"plugins\":[\{plugins}]}"
}

///|
fn capability_matches_page(capability : @utils.CapabilityConfig) -> Bool {
  if !capability.principals.any(principal => {
      principal.kind == "window" || principal.kind == "remote_page"
    }) {
    return false
  }
  for scope in capability.scopes {
    if scope.kind != "transport" || scope.value != "moonview" {
      return false
    }
  }
  true
}

///|
fn page_command_names(config : @utils.OrbitConfig) -> Array[String] {
  let allowed : Map[String, Bool] = Map([])
  let denied : Map[String, Bool] = Map([])
  for capability in config.capabilities {
    if capability_matches_page(capability) {
      for command in capability.commands {
        match capability.effect {
          "allow" => allowed[command] = true
          "deny" => denied[command] = true
          _ => ()
        }
      }
    }
  }
  let commands = []
  for command, _ in allowed {
    if !denied.contains(command) {
      commands.push(command)
    }
  }
  commands.sort()
  commands
}

///|
fn bindings_source(config : @utils.OrbitConfig, fingerprint : String) -> String {
  let entries = page_command_names(config).map(command => {
    let quoted = Json::string(command).stringify()
    "  \{quoted}: (payload = null, options = undefined) => invoke(\{quoted}, payload, options),"
  })
  let fingerprint = Json::string(fingerprint).stringify()
  "// Generated by orbit-build. DO NOT EDIT.\n\nexport const configurationFingerprint = \{fingerprint};\n\nexport function invoke(command, payload = null, options = undefined) {\n  const bridge = globalThis.__ORBIT__;\n  if (!bridge || typeof bridge.invoke !== \"function\") {\n    return Promise.reject(new Error(\"Orbit IPC bridge is unavailable\"));\n  }\n  return bridge.invoke(command, payload, options);\n}\n\nexport const commands = Object.freeze({\n\{entries.join("\n")}\n});\n"
}

///|
async fn generate_bindings(config_path : String, output_path : String) -> Unit {
  let config_path = @fs.realpath(config_path)
  let output_parent = @fs.realpath(parent_path(output_path))
  let output_path = join_path(output_parent, file_name(output_path))
  let config_text = @fs.read_file(config_path).text()
  let compiled = @utils.compile_config(config_text) catch {
    _ => abort_build("configuration does not satisfy the Orbit schema")
  }
  let config = @utils.parse_config(config_text) catch {
    _ => abort_build("configuration does not satisfy the Orbit schema")
  }
  write_if_changed(output_path, bindings_source(config, compiled.fingerprint()))
}

///|
async fn print_vite_workflow(config_path : String) -> Unit {
  let config_path = @fs.realpath(config_path)
  let config_text = @fs.read_file(config_path).text()
  let config = @utils.parse_config(config_text) catch {
    _ => abort_build("configuration does not satisfy the Orbit schema")
  }
  println(vite_workflow_json(config))
}

///|
async fn print_package_metadata(config_path : String) -> Unit {
  let config_path = @fs.realpath(config_path)
  let config_text = @fs.read_file(config_path).text()
  let compiled = @utils.compile_config(config_text) catch {
    _ => abort_build("configuration does not satisfy the Orbit schema")
  }
  let config = @utils.parse_config(config_text) catch {
    _ => abort_build("configuration does not satisfy the Orbit schema")
  }
  println(package_metadata_json(config, compiled.fingerprint()))
}

///|
fn asset_root(
  configuration_directory : String,
  config : @utils.OrbitConfig,
  use_vite_dist : Bool,
) -> String {
  if use_vite_dist {
    match config.build.vite {
      Some(vite) => join_path(configuration_directory, vite.dist_dir)
      None => configuration_directory
    }
  } else {
    configuration_directory
  }
}

///|
async fn generate(
  config_path : String,
  output_path : String,
  development_url : String?,
) -> Unit {
  let config_path = @fs.realpath(config_path)
  let configuration_directory = parent_path(config_path)
  let output_parent = @fs.realpath(parent_path(output_path))
  let output_path = join_path(output_parent, file_name(output_path))
  let config_text = @fs.read_file(config_path).text()
  let compiled = @utils.compile_config(config_text) catch {
    _ => abort_build("configuration does not satisfy the Orbit schema")
  }
  let orbit_config = @utils.parse_config(config_text) catch {
    _ => abort_build("configuration does not satisfy the Orbit schema")
  }
  let sidecars = read_plugin_sidecars(configuration_directory, orbit_config)
  let asset_bundles : Array[Array[Asset]] = []
  if development_url is None {
    let asset_root = @fs.realpath(
      asset_root(configuration_directory, orbit_config, true),
    )
    for window in orbit_config.app.windows {
      let embedded_entry = window_embedded_entry(orbit_config, window)
      let entry_path = @fs.realpath(join_path(asset_root, embedded_entry))
      if !has_path_prefix(
          normalized_path(entry_path),
          normalized_path(asset_root),
        ) {
        abort_build("window entry escapes the asset root")
      }
      let resource_root = @fs.realpath(
        join_path(asset_root, window_resource_root(orbit_config, window)),
      )
      let entry = file_name(embedded_entry)
      if !entry.has_suffix(".html") && !entry.has_suffix(".htm") {
        abort_build("window entry must be an HTML document for CSP injection")
      }
      let entry_html = @fs.read_file(entry_path).text()
      let entry_html = @utils.inject_csp(
        entry_html,
        orbit_config.web.embedded.csp,
      ) catch {
        _ =>
          abort_build(
            "could not inject the configured CSP into the window entry document",
          )
      }
      let entry_html = normalize_text_line_endings(entry_html)
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
        abort_build("window entry must be a regular file below its asset root")
      }
      for index = 0; index < assets.length(); index = index + 1 {
        if assets[index].path == entry {
          assets[index] = {
            ..assets[index],
            bytes: @utf8.encode(entry_html[:], bom=false),
          }
        }
      }
      asset_bundles.push(assets)
    }
  } else {
    for _window in orbit_config.app.windows {
      asset_bundles.push([])
    }
  }
  write_if_changed(
    output_path,
    generated_source(
      "orbit",
      orbit_config,
      compiled.fingerprint(),
      compiled.canonical_json(),
      asset_bundles,
      development_url,
      sidecars,
    ),
  )
}

///|
async fn generate_development(
  config_path : String,
  output_path : String,
) -> Unit {
  let config_path = @fs.realpath(config_path)
  let config = @utils.parse_config(@fs.read_file(config_path).text()) catch {
    _ => abort_build("configuration does not satisfy the Orbit schema")
  }
  let development_url = match config.build.vite {
    Some(vite) => vite.dev_url
    None => abort_build("development generation requires build.vite")
  }
  generate(config_path, output_path, Some(development_url))
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 5 && args[1] == "icon" {
    let compression_level = @string.parse_int(args[4])
    generate_icons(args[2], args[3], compression_level)
    return
  }
  if args.length() == 3 && args[1] == "vite-workflow" {
    print_vite_workflow(args[2])
    return
  }
  if args.length() == 3 && args[1] == "package-metadata" {
    print_package_metadata(args[2])
    return
  }
  if args.length() == 4 && args[1] == "migrate-config" {
    migrate_config(args[2], args[3])
    return
  }
  if args.length() == 4 && args[1] == "bindings" {
    generate_bindings(args[2], args[3])
    return
  }
  if args.length() == 4 && args[1] == "dev" {
    generate_development(args[2], args[3])
    return
  }
  if args.length() != 3 {
    abort_build(
      "usage: moon run orbit-build icon <source.png> <output-dir> <compression-level> | moon run orbit-build <orbit.conf.json> <generated.mbt> | moon run orbit-build bindings <orbit.conf.json> <orbit-bindings.mjs> | moon run orbit-build vite-workflow <orbit.conf.json> | moon run orbit-build package-metadata <orbit.conf.json> | moon run orbit-build dev <orbit.conf.json> <generated.mbt> | moon run orbit-build migrate-config <v1-orbit.conf.json> <v2-orbit.conf.json>",
    )
  }
  generate(args[1], args[2], None)
}

///|
test "remote web generation uses the HTTPS entry and embedded fallback" {
  let config_source =
    #|{
    #|  "schema_version": 2,
    #|  "app": {
    #|    "identifier": "dev.orbit.remote",
    #|    "name": "Orbit Remote",
    #|    "version": "0.1.0",
    #|    "windows": [{
    #|      "label": "main",
    #|      "title": "Orbit Remote",
    #|      "width": 800,
    #|      "height": 600,
    #|      "entry": "assets/index.html",
    #|      "visible": true,
    #|      "resizable": true
    #|    }]
    #|  },
    #|  "bundle": { "icons": [] },
    #|  "web": {
    #|    "embedded": { "csp": "default-src 'self'" },
    #|    "remote": {
    #|      "http_url": "https://app.example/start",
    #|      "allowed_origins": ["https://app.example"],
    #|      "fallback_entry": "assets/fallback.html"
    #|    }
    #|  },
    #|  "build": {},
    #|  "capabilities": [{
    #|    "identifier": "remote-command",
    #|    "effect": "allow",
    #|    "principals": [{ "kind": "remote_page", "identifier": "main" }],
    #|    "scopes": [
    #|      { "kind": "transport", "value": "moonview" },
    #|      { "kind": "origin", "value": "https://app.example" }
    #|    ],
    #|    "commands": ["remote.ping"]
    #|  }],
    #|  "plugins": []
    #|}
  let config = @utils.parse_config(config_source)
  let source = generated_source(
    "orbit",
    config,
    "fingerprint",
    "{}",
    [],
    None,
    [],
  )
  assert_true(
    source.contains("initial_content=Url(\"https://app.example/start\")"),
  )
  assert_true(source.contains("fallback_url=\"orbit://app/fallback.html\""))
  assert_true(source.contains("DesktopIpcPrincipal::remote_page"))
  assert_true(source.contains("PrincipalSelector::remote_page"))
  assert_true(
    source.contains(
      "pub fn configured_plugins() -> Array[@plugin.PluginDeclaration] {\n  []\n}",
    ),
  )
}

///|
test "generated windows keep same-named entry documents in separate resource bundles" {
  let config_source =
    #|{
    #|  "schema_version": 2,
    #|  "app": {
    #|    "identifier": "dev.orbit.multiple",
    #|    "name": "Orbit Multiple",
    #|    "version": "0.1.0",
    #|    "windows": [
    #|      {"label":"main","title":"Main","width":800,"height":600,"entry":"main/index.html","visible":true,"resizable":true},
    #|      {"label":"settings","title":"Settings","width":600,"height":400,"entry":"settings/index.html","visible":true,"resizable":true}
    #|    ]
    #|  },
    #|  "bundle": { "icons": [] },
    #|  "web": { "embedded": { "csp": "default-src 'self'" } },
    #|  "build": {},
    #|  "capabilities": [],
    #|  "plugins": []
    #|}
  let config = @utils.parse_config(config_source)
  let source = generated_source(
    "orbit",
    config,
    "fingerprint",
    "{}",
    [
      [{ path: "index.html", media_type: "text/html", bytes: b"main" }],
      [{ path: "index.html", media_type: "text/html", bytes: b"settings" }],
    ],
    None,
    [],
  )
  assert_true(source.contains("handler=handle_resource_0"))
  assert_true(source.contains("handler=handle_resource_1"))
  assert_true(source.contains("pub fn resource_response_0"))
  assert_true(source.contains("pub fn resource_response_1"))
  assert_true(
    source.contains("initial_content=Url(\"orbit://app/index.html\")"),
  )
}

///|
test "icon generation targets deterministic desktop icon sizes" {
  debug_inspect(icon_sizes(), content="[16, 32, 48, 64, 128, 256, 512, 1024]")
}

///|
test "package metadata declares the compiled compatibility profile" {
  let profile = package_compatibility_json()
  assert_true(profile.contains("\"orbit\":\"0.1.0-alpha.1\""))
  assert_true(profile.contains("\"orby\":\"0.1.0-beta.3\""))
  assert_true(profile.contains("\"moonview\":\"0.1.0-beta.5\""))
  assert_true(profile.contains("\"plugin_abi\":2"))
  assert_true(profile.contains("\"plugin_sidecar_schema\":2"))
  assert_true(profile.contains("\"configuration_schema\":2"))
}

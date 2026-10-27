///|
using @core {trait DesktopExtension}

///|
const TEXT_LIMIT : Int32 = 65536

///|
fn invalid_payload() -> @ipc.CommandFailure {
  @ipc.CommandFailure::new(
    code="invalid_payload",
    message="desktop command payload is invalid",
  )
}

///|
fn unavailable(message : String) -> @ipc.CommandFailure {
  @ipc.CommandFailure::new(code="desktop_unavailable", message~)
}

///|
fn failed(message : String) -> @ipc.CommandFailure {
  @ipc.CommandFailure::new(code="desktop_failed", message~)
}

///|
fn command(
  name : String,
  handler : (@core.DesktopUiContext, Json) -> Result[Json, @ipc.CommandFailure],
) -> @core.DesktopCommand {
  @core.DesktopCommand::ui(name, handler) catch {
    _ => abort("invalid built-in desktop command")
  }
}

///|
fn object_field(payload : Json, field : String) -> Json? {
  match payload {
    Object(fields) => fields.get(field)
    _ => None
  }
}

///|
fn string_field(
  payload : Json,
  field : String,
) -> Result[String, @ipc.CommandFailure] {
  match object_field(payload, field) {
    Some(String(value)) => Ok(value)
    _ => Err(invalid_payload())
  }
}

///|
fn optional_string_field(
  payload : Json,
  field : String,
) -> Result[String?, @ipc.CommandFailure] {
  match object_field(payload, field) {
    None => Ok(None)
    Some(Null) => Ok(None)
    Some(String(value)) => Ok(Some(value))
    Some(_) => Err(invalid_payload())
  }
}

///|
fn bool_field(
  payload : Json,
  field : String,
  default : Bool,
) -> Result[Bool, @ipc.CommandFailure] {
  match object_field(payload, field) {
    None => Ok(default)
    Some(True) => Ok(true)
    Some(False) => Ok(false)
    Some(_) => Err(invalid_payload())
  }
}

///|
fn bounded_text(value : String) -> Result[String, @ipc.CommandFailure] {
  if value.length() > TEXT_LIMIT {
    Err(invalid_payload())
  } else {
    Ok(value)
  }
}

///|
fn safe_text(value : String) -> Result[String, @ipc.CommandFailure] {
  let text = value.trim().to_owned()
  if text.is_empty() || text.length() > 4096 || text.contains("\u{0000}") {
    Err(invalid_payload())
  } else {
    Ok(text)
  }
}

///|
fn shell_action(action : String, path : String) -> Result[Unit, String] {
  match action {
    "open" => @proton_shell.open(path)
    "reveal" => @proton_shell.reveal_item(path)
    "trash" => @proton_shell.trash_item(path)
    _ => Err("unsupported shell action")
  }
}

///|
fn scope_name(scope : @proton_keepawake.Scope) -> String {
  match scope {
    @proton_keepawake.PreventSystemSleep => "system"
    @proton_keepawake.PreventDisplaySleep => "display"
    @proton_keepawake.PreventSystemAndDisplaySleep => "system_and_display"
  }
}

///|
fn parse_scope(
  value : String?,
) -> Result[@proton_keepawake.Scope, @ipc.CommandFailure] {
  match value {
    None | Some("system") => Ok(@proton_keepawake.PreventSystemSleep)
    Some("display") => Ok(@proton_keepawake.PreventDisplaySleep)
    Some("system_and_display") =>
      Ok(@proton_keepawake.PreventSystemAndDisplaySleep)
    Some(_) => Err(invalid_payload())
  }
}

///|
fn json_string(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

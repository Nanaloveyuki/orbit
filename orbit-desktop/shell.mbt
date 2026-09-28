///|
pub struct DesktopShellExtension {}

///|
pub fn DesktopShellExtension::new() -> DesktopShellExtension {
  DesktopShellExtension::{ }
}

///|
pub fn DesktopShellExtension::as_extension(
  self : DesktopShellExtension,
) -> &@core.DesktopExtension {
  self as &@core.DesktopExtension
}

///|
fn base_directories() -> Json {
  match @directories.BaseDirs::new() {
    None => { "available": false }
    Some(base) =>
      {
        "available": true,
        "home_dir": base.home_dir(),
        "cache_dir": base.cache_dir(),
        "config_dir": base.config_dir(),
        "config_local_dir": base.config_local_dir(),
        "data_dir": base.data_dir(),
        "data_local_dir": base.data_local_dir(),
        "executable_dir": json_string(base.executable_dir()),
        "preference_dir": base.preference_dir(),
        "runtime_dir": json_string(base.runtime_dir()),
        "state_dir": json_string(base.state_dir()),
      }
  }
}

///|
fn user_directories() -> Json {
  match @directories.UserDirs::new() {
    None => { "available": false }
    Some(user) =>
      {
        "available": true,
        "home_dir": user.home_dir(),
        "audio_dir": json_string(user.audio_dir()),
        "desktop_dir": json_string(user.desktop_dir()),
        "document_dir": json_string(user.document_dir()),
        "download_dir": json_string(user.download_dir()),
        "font_dir": json_string(user.font_dir()),
        "picture_dir": json_string(user.picture_dir()),
        "public_dir": json_string(user.public_dir()),
        "template_dir": json_string(user.template_dir()),
        "video_dir": json_string(user.video_dir()),
      }
  }
}

///|
fn project_directory_json(
  qualifier : String,
  organization : String,
  application : String,
) -> Result[Json, @ipc.CommandFailure] {
  match @directories.ProjectDirs::from(qualifier, organization, application) {
    None => Ok({ "available": false })
    Some(project) =>
      Ok({
        "available": true,
        "project_path": project.project_path(),
        "cache_dir": project.cache_dir(),
        "config_dir": project.config_dir(),
        "config_local_dir": project.config_local_dir(),
        "data_dir": project.data_dir(),
        "data_local_dir": project.data_local_dir(),
        "preference_dir": project.preference_dir(),
        "runtime_dir": json_string(project.runtime_dir()),
        "state_dir": json_string(project.state_dir()),
      })
  }
}

///|
fn project_directories(payload : Json) -> Result[Json, @ipc.CommandFailure] {
  match string_field(payload, "qualifier").bind(safe_text) {
    Err(failure) => Err(failure)
    Ok(qualifier) =>
      match string_field(payload, "organization").bind(safe_text) {
        Err(failure) => Err(failure)
        Ok(organization) =>
          match string_field(payload, "application").bind(safe_text) {
            Err(failure) => Err(failure)
            Ok(application) =>
              project_directory_json(qualifier, organization, application)
          }
      }
  }
}

///|
impl DesktopExtension for DesktopShellExtension with fn identifier(self) {
  ignore(self)
  "orbit.desktop.shell"
}

///|
impl DesktopExtension for DesktopShellExtension with fn commands(_self) {
  [
    command("orbit.shell.supported", fn(_ui, _payload) {
      Ok({ "supported": @proton_shell.is_supported() })
    }),
    command("orbit.shell.open", fn(_ui, payload) {
      match string_field(payload, "path").bind(safe_text) {
        Err(failure) => Err(failure)
        Ok(path) => {
          let action = match optional_string_field(payload, "action") {
            Ok(None) => "open"
            Ok(Some(action)) => action
            Err(failure) => return Err(failure)
          }
          if !@proton_shell.is_supported() {
            return Err(unavailable("shell actions are unavailable"))
          }
          match shell_action(action, path) {
            Ok(_) => Ok({ "completed": true })
            Err(_) => Err(failed("shell action failed"))
          }
        }
      }
    }),
    command("orbit.paths.base", fn(_ui, _payload) { Ok(base_directories()) }),
    command("orbit.paths.user", fn(_ui, _payload) { Ok(user_directories()) }),
    command("orbit.paths.project", fn(_ui, payload) {
      project_directories(payload)
    }),
  ]
}

///|
impl DesktopExtension for DesktopShellExtension with fn start(
  _self,
  _controller,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopShellExtension with fn poll(_self, _controller) {
  Ok(())
}

///|
impl DesktopExtension for DesktopShellExtension with fn window_suspended(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopShellExtension with fn window_destroyed(
  _self,
  _label,
) {
  Ok(())
}

///|
impl DesktopExtension for DesktopShellExtension with fn shutdown(_self) {
  Ok(())
}

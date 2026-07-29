///|
pub struct CommandCapability {
  priv identifier : String
  priv windows : Array[String]
  priv commands : Array[CommandName]
}

///|
fn valid_capability_identifier(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  for char in value {
    if !valid_command_char(char) {
      return false
    }
  }
  true
}

///|
pub fn CommandCapability::new(
  identifier~ : String,
  windows~ : Array[String],
  commands~ : Array[CommandName],
) -> CommandCapability raise IpcError {
  if !valid_capability_identifier(identifier) ||
    windows.is_empty() ||
    commands.is_empty() {
    raise InvalidCapability(identifier)
  }
  for window in windows {
    if window.is_empty() {
      raise InvalidCapability(identifier)
    }
  }
  { identifier, windows, commands }
}

///|
pub fn CommandCapability::identifier(self : CommandCapability) -> String {
  self.identifier
}

///|
fn CommandCapability::applies_to(
  self : CommandCapability,
  window_label : String,
) -> Bool {
  self.windows.contains(window_label)
}

///|
fn CommandCapability::allows(
  self : CommandCapability,
  command : CommandName,
) -> Bool {
  self.commands.contains(command)
}

///|
pub struct CommandPolicy {
  priv capabilities : Map[String, CommandCapability]
}

///|
pub fn CommandPolicy::new() -> CommandPolicy {
  { capabilities: Map([]) }
}

///|
pub fn CommandPolicy::add(
  self : CommandPolicy,
  capability : CommandCapability,
) -> Unit raise IpcError {
  let identifier = capability.identifier()
  if self.capabilities.contains(identifier) {
    raise DuplicateCapability(identifier)
  }
  self.capabilities[identifier] = capability
}

///|
pub fn CommandPolicy::allows(
  self : CommandPolicy,
  window_label : String,
  command : CommandName,
) -> Bool {
  for _, capability in self.capabilities {
    if capability.applies_to(window_label) && capability.allows(command) {
      return true
    }
  }
  false
}

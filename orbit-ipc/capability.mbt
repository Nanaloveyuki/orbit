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
pub enum CapabilityEffect {
  Allow
  Deny
} derive(Eq, Debug)

///|
pub fn CapabilityEffect::allow() -> CapabilityEffect {
  Allow
}

///|
pub fn CapabilityEffect::deny() -> CapabilityEffect {
  Deny
}

///|
pub enum PrincipalSelector {
  Window(String)
  HttpClient(String)
  Plugin(String)
  BackgroundTask(String)
} derive(Eq, Debug)

///|
pub fn PrincipalSelector::window(
  label : String,
) -> PrincipalSelector raise IpcError {
  if !valid_invocation_identity(label) {
    raise InvalidPrincipal(label)
  }
  Window(label)
}

///|
pub fn PrincipalSelector::http_client(
  identifier : String,
) -> PrincipalSelector raise IpcError {
  if !valid_invocation_identity(identifier) {
    raise InvalidPrincipal(identifier)
  }
  HttpClient(identifier)
}

///|
pub fn PrincipalSelector::plugin(
  identifier : String,
) -> PrincipalSelector raise IpcError {
  if !valid_invocation_identity(identifier) {
    raise InvalidPrincipal(identifier)
  }
  Plugin(identifier)
}

///|
pub fn PrincipalSelector::background_task(
  identifier : String,
) -> PrincipalSelector raise IpcError {
  if !valid_invocation_identity(identifier) {
    raise InvalidPrincipal(identifier)
  }
  BackgroundTask(identifier)
}

///|
pub enum InvocationScope {
  Transport(InvocationTransport)
  Origin(String)
} derive(Eq, Debug)

///|
pub fn InvocationScope::transport(
  transport : InvocationTransport,
) -> InvocationScope {
  Transport(transport)
}

///|
pub fn InvocationScope::origin(
  origin : String,
) -> InvocationScope raise IpcError {
  if !valid_origin(origin) {
    raise InvalidContext(origin)
  }
  Origin(origin)
}

///|
pub struct CommandGrant {
  priv identifier : String
  priv effect : CapabilityEffect
  priv principals : Array[PrincipalSelector]
  priv scopes : Array[InvocationScope]
  priv commands : Array[CommandName]
}

///|
fn PrincipalSelector::valid(self : PrincipalSelector) -> Bool {
  match self {
    Window(value) | HttpClient(value) | Plugin(value) | BackgroundTask(value) =>
      valid_invocation_identity(value)
  }
}

///|
fn PrincipalSelector::matches(
  self : PrincipalSelector,
  principal : InvocationPrincipal,
) -> Bool {
  match (self, principal) {
    (Window(expected), Window(actual))
    | (HttpClient(expected), HttpClient(actual))
    | (Plugin(expected), Plugin(actual))
    | (BackgroundTask(expected), BackgroundTask(actual)) => expected == actual
    _ => false
  }
}

///|
fn InvocationScope::valid(self : InvocationScope) -> Bool {
  match self {
    Transport(_) => true
    Origin(origin) => valid_origin(origin)
  }
}

///|
fn InvocationScope::matches(
  self : InvocationScope,
  context : InvocationContext,
) -> Bool {
  match self {
    Transport(transport) => context.transport() == transport
    Origin(expected) =>
      match context.origin() {
        Some(actual) => actual == expected
        None => false
      }
  }
}

///|
pub fn CommandGrant::new(
  identifier~ : String,
  effect~ : CapabilityEffect,
  principals~ : Array[PrincipalSelector],
  scopes? : Array[InvocationScope] = [],
  commands~ : Array[CommandName],
) -> CommandGrant raise IpcError {
  if !valid_capability_identifier(identifier) ||
    principals.is_empty() ||
    commands.is_empty() {
    raise InvalidCapability(identifier)
  }
  for principal in principals {
    if !principal.valid() {
      raise InvalidCapability(identifier)
    }
  }
  for scope in scopes {
    if !scope.valid() {
      raise InvalidCapability(identifier)
    }
  }
  { identifier, effect, principals, scopes, commands }
}

///|
pub fn CommandGrant::identifier(self : CommandGrant) -> String {
  self.identifier
}

///|
fn CommandGrant::applies_to(
  self : CommandGrant,
  context : InvocationContext,
  command : CommandName,
) -> Bool {
  if !self.commands.contains(command) ||
    !self.principals.any(principal => principal.matches(context.principal())) {
    return false
  }
  self.scopes.all(scope => scope.matches(context))
}

///|
pub struct CommandPolicy {
  priv capabilities : Map[String, CommandCapability]
  priv grants : Map[String, CommandGrant]
}

///|
pub fn CommandPolicy::new() -> CommandPolicy {
  { capabilities: Map([]), grants: Map([]) }
}

///|
pub fn CommandPolicy::add(
  self : CommandPolicy,
  capability : CommandCapability,
) -> Unit raise IpcError {
  let identifier = capability.identifier()
  if self.capabilities.contains(identifier) || self.grants.contains(identifier) {
    raise DuplicateCapability(identifier)
  }
  self.capabilities[identifier] = capability
}

///|
pub fn CommandPolicy::add_grant(
  self : CommandPolicy,
  grant : CommandGrant,
) -> Unit raise IpcError {
  let identifier = grant.identifier()
  if self.capabilities.contains(identifier) || self.grants.contains(identifier) {
    raise DuplicateCapability(identifier)
  }
  self.grants[identifier] = grant
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

///|
pub fn CommandPolicy::allows_context(
  self : CommandPolicy,
  context : InvocationContext,
  command : CommandName,
) -> Bool {
  let mut allowed = match context.principal() {
    Window(label) => self.allows(label, command)
    _ => false
  }
  for _, grant in self.grants {
    if grant.applies_to(context, command) {
      match grant.effect {
        Deny => return false
        Allow => allowed = true
      }
    }
  }
  allowed
}

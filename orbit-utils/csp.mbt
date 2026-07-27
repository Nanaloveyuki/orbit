///|
pub(all) suberror CspError {
  EmptyPolicy
  MissingHeadElement
  ExistingPolicy
} derive(Debug)

///|
fn escape_html_attribute(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
}

///|
pub fn csp_meta_tag(policy : String) -> String raise CspError {
  let policy = policy.trim().to_owned()
  if policy.is_empty() {
    raise EmptyPolicy
  }
  "<meta http-equiv=\"Content-Security-Policy\" content=\"\{escape_html_attribute(policy)}\">"
}

///|
fn is_html_space(code : Int) -> Bool {
  code == 9 || code == 10 || code == 12 || code == 13 || code == 32
}

///|
fn find_head_start(html : StringView, offset : Int) -> Int? {
  if offset >= html.length() {
    return None
  }
  match html[offset:].find("<head") {
    None => None
    Some(relative) => {
      let start = offset + relative
      let after_name = start + 5
      if after_name >= html.length() {
        None
      } else {
        let next = html.unsafe_get(after_name).to_int()
        if next == 62 || is_html_space(next) {
          Some(start)
        } else {
          find_head_start(html, after_name)
        }
      }
    }
  }
}

///|
fn remove_html_space(value : StringView) -> String {
  let builder = StringBuilder()
  for char in value {
    if !is_html_space(char.to_int()) {
      builder.write_char(char)
    }
  }
  builder.to_string()
}

///|
pub fn inject_csp(html : String, policy : String) -> String raise CspError {
  let lower = html.to_lower()
  let compact = remove_html_space(lower)
  if compact.contains("http-equiv=\"content-security-policy\"") ||
    compact.contains("http-equiv='content-security-policy'") ||
    compact.contains("http-equiv=content-security-policy") {
    raise ExistingPolicy
  }
  let head_start = match find_head_start(lower, 0) {
    Some(index) => index
    None => raise MissingHeadElement
  }
  let rest = lower[head_start:]
  let relative_end = match rest.find(">") {
    Some(index) => index
    None => raise MissingHeadElement
  }
  let insert_at = head_start + relative_end + 1
  html[:insert_at].to_owned() +
  csp_meta_tag(policy) +
  html[insert_at:].to_owned()
}

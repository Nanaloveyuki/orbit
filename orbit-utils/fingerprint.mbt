///|
pub fn fingerprint_bytes(bytes : BytesView) -> String {
  let digest = @sha256.Digest::new()
  for byte in bytes {
    digest.write(byte)
  }
  digest.check_sum()
}

///|
pub fn fingerprint_string(value : StringView) -> String {
  fingerprint_bytes(@utf8.encode(value))
}

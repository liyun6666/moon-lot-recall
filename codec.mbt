///|
fn decode_json(text : String, kind : String) -> Result[Json, Diagnostic] {
  if text.length() > 16000000 {
    return Err(issue("error", "input-too-large", kind, "JSON input exceeds 16 million UTF-16 code units"))
  }
  let json = @json.parse(text, reject_duplicate_keys=true) catch {
    error => return Err(issue("error", "invalid-json", kind, "JSON parse failed: \{error}"))
  }
  Ok(json)
}

///|
/// Decode a versioned ledger. Duplicate JSON object keys are rejected rather
/// than silently letting the last value win.
pub fn decode_ledger(text : String) -> Result[Ledger, Diagnostic] {
  match decode_json(text, "ledger") {
    Err(error) => Err(error)
    Ok(json) => {
      let ledger : Ledger = @json.from_json(json) catch {
        error => return Err(issue("error", "invalid-ledger-shape", "ledger", "JSON shape failed: \{error}"))
      }
      Ok(ledger)
    }
  }
}

///|
pub fn decode_request(text : String) -> Result[RecallRequest, Diagnostic] {
  match decode_json(text, "recall") {
    Err(error) => Err(error)
    Ok(json) => {
      let request : RecallRequest = @json.from_json(json) catch {
        error => return Err(issue("error", "invalid-request-shape", "recall", "JSON shape failed: \{error}"))
      }
      Ok(request)
    }
  }
}

///|
pub fn encode_ledger(ledger : Ledger) -> String {
  @json.to_json(ledger).stringify(indent=2)
}

///|
pub fn encode_request(request : RecallRequest) -> String {
  @json.to_json(request).stringify(indent=2)
}

///|
pub fn encode_report(report : RecallReport) -> String {
  @json.to_json(report).stringify(indent=2)
}

///|
pub fn encode_validation(report : ValidationReport) -> String {
  @json.to_json(report).stringify(indent=2)
}

///|
/// A contact log event is entered by an operator after a real outreach step.
/// It records no email or phone number and does not dispatch a message.
pub(all) struct ResponseEvent {
  shipment_id : String
  status : String
  recorded_at : Int64
  reference : String
  note : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ResponseRow {
  shipment_id : String
  consignee : String
  lot_id : String
  quantity_g : Int64
  status : String
  history : Array[ResponseEvent]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ResponseReport {
  recall_id : String
  rows : Array[ResponseRow]
  pending_count : Int32
  attempted_count : Int32
  reached_count : Int32
  acknowledged_count : Int32
  failed_count : Int32
} derive(Eq, Debug, ToJson, FromJson)

///|
pub fn parse_response_events_csv(
  text : String,
) -> Result[Array[ResponseEvent], ValidationReport] {
  let table = match parse_csv(text) {
    Err(diagnostic) => return Err(report_from([diagnostic]))
    Ok(value) => value
  }
  if !table.has_exact_headers([
      "shipment_id", "status", "recorded_at", "reference", "note",
    ]) {
    return Err(
      report_from([
        issue(
          "error", "response-csv-schema", "responses.csv", "expected shipment_id,status,recorded_at,reference,note",
        ),
      ]),
    )
  }
  let events : Array[ResponseEvent] = []
  let findings : Array[Diagnostic] = []
  for row in table.rows {
    match
      csv_int(row.cells[2], "responses.csv", row.line, "recorded_at", findings) {
      None => ()
      Some(recorded_at) =>
        events.push({
          shipment_id: row.cells[0],
          status: row.cells[1],
          recorded_at,
          reference: row.cells[3],
          note: row.cells[4],
        })
    }
  }
  if findings.is_empty() {
    Ok(events)
  } else {
    Err(report_from(findings))
  }
}

///|
fn valid_response_status(status : String) -> Bool {
  status == "attempted" ||
  status == "reached" ||
  status == "acknowledged" ||
  status == "failed"
}

///|
fn response_transition(previous : String, next : String) -> Bool {
  match previous {
    "pending" => next == "attempted" || next == "reached" || next == "failed"
    "attempted" => next == "attempted" || next == "reached" || next == "failed"
    "failed" => next == "attempted" || next == "reached"
    "reached" => next == "reached" || next == "acknowledged" || next == "failed"
    "acknowledged" => next == "acknowledged"
    _ => false
  }
}

///|
/// Replay events in file order for each affected shipment. Acknowledgement
/// requires a prior reached event; all timestamps must be monotonic per
/// shipment. Unknown shipment IDs and future ledger shipments fail closed.
pub fn review_responses(
  ledger : Ledger,
  request : RecallRequest,
  events : Array[ResponseEvent],
) -> Result[ResponseReport, ValidationReport] {
  let impact = match analyze(ledger, request) {
    Err(validation) => return Err(validation)
    Ok(value) => value
  }
  let allowed : Map[String, Bool] = Map([])
  for shipment in impact.affected_shipments {
    allowed[shipment.shipment_id] = true
  }
  let history : Map[String, Array[ResponseEvent]] = Map([])
  let latest : Map[String, String] = Map([])
  let latest_time : Map[String, Int64] = Map([])
  let findings : Array[Diagnostic] = []
  if events.length() > 100000 {
    findings.push(
      issue(
        "error", "response-limit", "responses", "at most 100000 response events are supported",
      ),
    )
  }
  for event in events {
    if !allowed.contains(event.shipment_id) {
      findings.push(
        issue(
          "error",
          "unknown-response-shipment",
          event.shipment_id,
          "shipment is not affected at the recall cutoff",
        ),
      )
      continue
    }
    if !valid_response_status(event.status) {
      findings.push(
        issue(
          "error",
          "invalid-response-status",
          event.shipment_id,
          "status must be attempted, reached, acknowledged, or failed",
        ),
      )
      continue
    }
    if !valid_time(event.recorded_at) || event.recorded_at < request.as_of {
      findings.push(
        issue(
          "error",
          "invalid-response-time",
          event.shipment_id,
          "contact event must be at or after recall cutoff",
        ),
      )
      continue
    }
    if !valid_label(event.reference) {
      findings.push(
        issue(
          "error",
          "invalid-response-reference",
          event.shipment_id,
          "a source reference is required",
        ),
      )
      continue
    }
    if event.note.length() > 1024 ||
      event.note.contains("\n") ||
      event.note.contains("\r") {
      findings.push(
        issue(
          "error",
          "invalid-response-note",
          event.shipment_id,
          "note must be one line of at most 1024 characters",
        ),
      )
      continue
    }
    let previous = latest.get(event.shipment_id).unwrap_or("pending")
    if !response_transition(previous, event.status) {
      findings.push(
        issue(
          "error",
          "invalid-response-transition",
          event.shipment_id,
          "status cannot follow \{previous}",
        ),
      )
      continue
    }
    if event.recorded_at <
      latest_time.get(event.shipment_id).unwrap_or(request.as_of) {
      findings.push(
        issue(
          "error",
          "response-time-order",
          event.shipment_id,
          "events for one shipment must be chronological",
        ),
      )
      continue
    }
    let entries = history.get(event.shipment_id).unwrap_or([])
    entries.push(event)
    history[event.shipment_id] = entries
    latest[event.shipment_id] = event.status
    latest_time[event.shipment_id] = event.recorded_at
  }
  if !findings.is_empty() {
    return Err(report_from(findings))
  }
  let rows : Array[ResponseRow] = []
  let mut pending_count = 0
  let mut attempted_count = 0
  let mut reached_count = 0
  let mut acknowledged_count = 0
  let mut failed_count = 0
  for shipment in impact.affected_shipments {
    let status = latest.get(shipment.shipment_id).unwrap_or("pending")
    match status {
      "pending" => pending_count += 1
      "attempted" => attempted_count += 1
      "reached" => reached_count += 1
      "acknowledged" => acknowledged_count += 1
      "failed" => failed_count += 1
      _ => ()
    }
    rows.push({
      shipment_id: shipment.shipment_id,
      consignee: shipment.consignee,
      lot_id: shipment.lot_id,
      quantity_g: shipment.quantity_g,
      status,
      history: history.get(shipment.shipment_id).unwrap_or([]),
    })
  }
  Ok({
    recall_id: request.id,
    rows,
    pending_count,
    attempted_count,
    reached_count,
    acknowledged_count,
    failed_count,
  })
}

///|
pub fn render_responses_markdown(report : ResponseReport) -> String {
  let out = StringBuilder()
  out.write_string("# Contact progress: \{markdown_cell(report.recall_id)}\n\n")
  out.write_string(
    "These statuses summarize operator supplied evidence. No notice was sent by this tool.\n\n",
  )
  out.write_string(
    "| Shipment | Consignee | Lot | Quantity (g) | Status | Last reference |\n",
  )
  out.write_string("| --- | --- | --- | ---: | --- | --- |\n")
  for row in report.rows {
    let last = if row.history.is_empty() {
      ""
    } else {
      row.history[row.history.length() - 1].reference
    }
    out.write_string(
      "| \{markdown_cell(row.shipment_id)} | \{markdown_cell(row.consignee)} | \{markdown_cell(row.lot_id)} | \{row.quantity_g} | \{row.status} | \{markdown_cell(last)} |\n",
    )
  }
  out.write_string(
    "\nPending: \{report.pending_count}; attempted: \{report.attempted_count}; reached: \{report.reached_count}; acknowledged: \{report.acknowledged_count}; failed: \{report.failed_count}.\n",
  )
  out.to_string()
}

///|
fn response_request() -> @moon-lot-recall.RecallRequest {
  { id: "RESP-1", reason: "supplier alert", seed_lots: ["RAW-1"], as_of: 40L, }
}

///|
test "contact history advances from reached to acknowledged" {
  let events : Array[@moon-lot-recall.ResponseEvent] = [
    {
      shipment_id: "SHIP-1",
      status: "reached",
      recorded_at: 41L,
      reference: "CALL-1",
      note: "manager answered",
    },
    {
      shipment_id: "SHIP-1",
      status: "acknowledged",
      recorded_at: 42L,
      reference: "EMAIL-1",
      note: "written confirmation",
    },
  ]
  match
    @moon-lot-recall.review_responses(
      sample_ledger(),
      response_request(),
      events,
    ) {
    Err(_) => fail("valid history should replay")
    Ok(report) => {
      assert_eq(report.acknowledged_count, 1)
      assert_eq(report.rows[0].history.length(), 2)
      assert_eq(report.rows[0].history[1].reference, "EMAIL-1")
    }
  }
}

///|
test "missing contact evidence remains pending" {
  match
    @moon-lot-recall.review_responses(sample_ledger(), response_request(), []) {
    Err(_) => fail("empty evidence is a valid pending report")
    Ok(report) => {
      assert_eq(report.pending_count, 1)
      assert_eq(report.rows[0].status, "pending")
    }
  }
}

///|
test "acknowledgement without contact proof fails closed" {
  let events : Array[@moon-lot-recall.ResponseEvent] = [
    {
      shipment_id: "SHIP-1",
      status: "acknowledged",
      recorded_at: 41L,
      reference: "EMAIL-1",
      note: "",
    },
  ]
  match
    @moon-lot-recall.review_responses(
      sample_ledger(),
      response_request(),
      events,
    ) {
    Ok(_) => fail("acknowledged requires a reached event")
    Err(report) => assert_true(has_code(report, "invalid-response-transition"))
  }
}

///|
test "responses reject unknown shipment and backwards time" {
  let events : Array[@moon-lot-recall.ResponseEvent] = [
    {
      shipment_id: "SHIP-1",
      status: "attempted",
      recorded_at: 42L,
      reference: "CALL-1",
      note: "",
    },
    {
      shipment_id: "SHIP-1",
      status: "reached",
      recorded_at: 41L,
      reference: "CALL-2",
      note: "",
    },
    {
      shipment_id: "SHIP-X",
      status: "reached",
      recorded_at: 41L,
      reference: "CALL-X",
      note: "",
    },
  ]
  match
    @moon-lot-recall.review_responses(
      sample_ledger(),
      response_request(),
      events,
    ) {
    Ok(_) => fail("invalid evidence must fail")
    Err(report) => {
      assert_true(has_code(report, "response-time-order"))
      assert_true(has_code(report, "unknown-response-shipment"))
    }
  }
}

///|
test "response CSV parses quoted notes and rejects bad timestamp" {
  let good = "shipment_id,status,recorded_at,reference,note\nSHIP-1,reached,41,CALL-1,\"buyer, informed\"\n"
  match @moon-lot-recall.parse_response_events_csv(good) {
    Err(_) => fail("quoted CSV note should parse")
    Ok(events) => assert_eq(events[0].note, "buyer, informed")
  }
  let bad = "shipment_id,status,recorded_at,reference,note\nSHIP-1,reached,tomorrow,CALL-1,\n"
  match @moon-lot-recall.parse_response_events_csv(bad) {
    Ok(_) => fail("timestamp must be numeric")
    Err(report) => assert_true(has_code(report, "csv-invalid-integer"))
  }
}

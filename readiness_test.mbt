///|
fn readiness_request() -> @moon-lot-recall.RecallRequest {
  { id: "READY-1", reason: "supplier alert", seed_lots: ["RAW-1"], as_of: 40L, }
}

///|
fn full_counts() -> Array[@moon-lot-recall.StockCount] {
  [
    {
      lot_id: "RAW-1",
      facility: "Mill A",
      counted_g: 100L,
      counted_at: 40L,
      reference: "COUNT-R",
    },
    {
      lot_id: "CAKE-1",
      facility: "Mill A",
      counted_g: 400L,
      counted_at: 40L,
      reference: "COUNT-C",
    },
  ]
}

///|
test "missing physical counts and contact evidence are explicit" {
  match
    @moon-lot-recall.review_readiness(
      sample_ledger(),
      readiness_request(),
      [],
      [],
    ) {
    Err(_) => fail("missing evidence should appear as open items")
    Ok(report) => {
      assert_false(report.evidence_review_complete)
      assert_eq(report.affected_lot_count, 2)
      assert_eq(report.items.length(), 3)
      assert_eq(report.items[0].category, "missing-count")
      assert_eq(report.items[2].category, "contact-open")
    }
  }
}

///|
test "matched counts and written acknowledgement complete evidence checklist" {
  let events : Array[@moon-lot-recall.ResponseEvent] = [
    {
      shipment_id: "SHIP-1",
      status: "reached",
      recorded_at: 41L,
      reference: "CALL-1",
      note: "",
    },
    {
      shipment_id: "SHIP-1",
      status: "acknowledged",
      recorded_at: 42L,
      reference: "ACK-1",
      note: "",
    },
  ]
  match
    @moon-lot-recall.review_readiness(
      sample_ledger(),
      readiness_request(),
      full_counts(),
      events,
    ) {
    Err(_) => fail("complete evidence should be accepted")
    Ok(report) => {
      assert_true(report.evidence_review_complete)
      assert_eq(report.physical_count_count, 2)
      assert_eq(report.acknowledged_shipment_count, 1)
      assert_eq(report.items.length(), 0)
    }
  }
}

///|
test "a stock shortage and failed contact keep checklist open" {
  let counts = full_counts()
  counts[1] = { ..counts[1], counted_g: 350L, }
  let events : Array[@moon-lot-recall.ResponseEvent] = [
    {
      shipment_id: "SHIP-1",
      status: "failed",
      recorded_at: 41L,
      reference: "CALL-1",
      note: "no answer",
    },
  ]
  match
    @moon-lot-recall.review_readiness(
      sample_ledger(),
      readiness_request(),
      counts,
      events,
    ) {
    Err(_) => fail("valid but incomplete evidence should report findings")
    Ok(report) => {
      assert_false(report.evidence_review_complete)
      assert_eq(report.items[0].category, "stock-shortage")
      assert_eq(report.items[1].category, "contact-open")
      assert_true(report.items[0].detail.contains("50 g"))
    }
  }
}

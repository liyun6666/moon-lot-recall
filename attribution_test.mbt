///|
test "two suspect ingredients both appear on the mixed output" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "MULTI-1",
    reason: "supplier alert",
    seed_lots: ["RAW-1", "RAW-2"],
    as_of: 40L,
  }
  match @moon-lot-recall.attribute_sources(sample_ledger(), request) {
    Err(_) => fail("valid case expected")
    Ok(report) => {
      assert_eq(report.lots.length(), 3)
      assert_eq(report.lots[2].lot_id, "CAKE-1")
      assert_eq(report.lots[2].sources.length(), 2)
      assert_eq(report.lots[2].sources[0].seed_lot, "RAW-1")
      assert_eq(report.lots[2].sources[1].seed_lot, "RAW-2")
      assert_eq(report.shipments[0].sources.length(), 2)
    }
  }
}

///|
test "single suspect source has one attribution path" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "MULTI-2",
    reason: "supplier alert",
    seed_lots: ["RAW-1"],
    as_of: 40L,
  }
  match @moon-lot-recall.attribute_sources(sample_ledger(), request) {
    Err(_) => fail("valid case expected")
    Ok(report) => {
      assert_eq(report.lots.length(), 2)
      assert_eq(report.lots[1].sources.length(), 1)
      assert_eq(report.lots[1].sources[0].path.length(), 1)
    }
  }
}

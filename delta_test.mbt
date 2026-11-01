///|
test "later cutoff adds downstream lot and shipment" {
  let earlier : @moon-lot-recall.RecallRequest = {
    id: "DELTA-1",
    reason: "supplier notice",
    seed_lots: ["RAW-1"],
    as_of: 15L,
  }
  match @moon-lot-recall.compare_cutoffs(sample_ledger(), earlier, 40L) {
    Err(_) => fail("valid cutoffs should compare")
    Ok(delta) => {
      assert_eq(delta.previous_lot_count, 1)
      assert_eq(delta.current_lot_count, 2)
      assert_eq(delta.new_lots[0].lot_id, "CAKE-1")
      assert_eq(delta.new_shipments[0].shipment_id, "SHIP-1")
      assert_eq(delta.newly_shipped_g, 500L)
    }
  }
}

///|
test "same cutoff yields no additional exposure" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "DELTA-2",
    reason: "supplier notice",
    seed_lots: ["RAW-1"],
    as_of: 40L,
  }
  match @moon-lot-recall.compare_cutoffs(sample_ledger(), request, 40L) {
    Err(_) => fail("same cutoff is a useful empty diff")
    Ok(delta) => {
      assert_eq(delta.new_lots.length(), 0)
      assert_eq(delta.new_shipments.length(), 0)
      assert_eq(delta.newly_shipped_g, 0L)
    }
  }
}

///|
test "a backwards comparison is rejected" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "DELTA-3",
    reason: "supplier notice",
    seed_lots: ["RAW-1"],
    as_of: 40L,
  }
  match @moon-lot-recall.compare_cutoffs(sample_ledger(), request, 20L) {
    Ok(_) => fail("backwards cutoff must fail")
    Err(report) => assert_true(has_code(report, "invalid-delta-cutoff"))
  }
}

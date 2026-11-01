///|
test "seed flour reaches mixed cracker and its consignee" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "CASE-1", reason: "supplier notice", seed_lots: ["RAW-1"], as_of: 40L,
  }
  let outcome = @moon-lot-recall.analyze(sample_ledger(), request)
  match outcome {
    Err(_) => fail("valid fixture must be accepted")
    Ok(report) => {
      assert_eq(report.affected_lots.length(), 2)
      assert_eq(report.affected_shipments.length(), 1)
      assert_eq(report.affected_shipments[0].consignee, "Store A")
      assert_eq(report.affected_shipments[0].path.length(), 1)
      assert_eq(report.affected_shipments[0].path[0].transformation_id, "MIX-1")
    }
  }
}

///|
test "unrelated ingredient does not become an affected lot" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "CASE-2", reason: "supplier notice", seed_lots: ["RAW-1"], as_of: 40L,
  }
  match @moon-lot-recall.analyze(sample_ledger(), request) {
    Err(_) => fail("valid fixture must be accepted")
    Ok(report) => {
      assert_eq(report.affected_lots[0].lot_id, "CAKE-1")
      assert_eq(report.affected_lots[1].lot_id, "RAW-1")
    }
  }
}

///|
test "cutoff excludes future processing and shipments" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "CASE-3", reason: "supplier notice", seed_lots: ["RAW-1"], as_of: 15L,
  }
  match @moon-lot-recall.analyze(sample_ledger(), request) {
    Err(_) => fail("valid fixture must be accepted")
    Ok(report) => {
      assert_eq(report.affected_lots.length(), 1)
      assert_eq(report.affected_shipments.length(), 0)
    }
  }
}

///|
test "invalid ledger fails closed" {
  let ledger = sample_ledger()
  ledger.shipments[0] = { ..ledger.shipments[0], quantity_g: 2000L, }
  let request : @moon-lot-recall.RecallRequest = {
    id: "CASE-4", reason: "supplier notice", seed_lots: ["RAW-1"], as_of: 40L,
  }
  match @moon-lot-recall.analyze(ledger, request) {
    Err(report) => assert_false(report.valid)
    Ok(_) => fail("overallocated ledger must be rejected")
  }
}

///|
test "two-stage processing preserves the complete path" {
  let ledger = sample_ledger()
  ledger.lots.push({
    id: "PACK-1", product: "boxed cracker", facility: "Mill A",
    quantity_g: 800L, produced_at: 40L,
  })
  ledger.transformations.push({
    id: "PACKING-1", facility: "Mill A", occurred_at: 40L,
    inputs: [{ lot_id: "CAKE-1", quantity_g: 800L, }],
    outputs: [{ lot_id: "PACK-1", quantity_g: 800L, }],
  })
  ledger.shipments[0] = { ..ledger.shipments[0], quantity_g: 100L, }
  let request : @moon-lot-recall.RecallRequest = {
    id: "CASE-5", reason: "supplier notice", seed_lots: ["RAW-1"], as_of: 50L,
  }
  match @moon-lot-recall.analyze(ledger, request) {
    Err(_) => fail("valid fixture must be accepted")
    Ok(report) => {
      assert_eq(report.affected_lots.length(), 3)
      let packed = report.affected_lots[1]
      assert_eq(packed.lot_id, "PACK-1")
      assert_eq(packed.path.length(), 2)
      assert_eq(packed.path[0].transformation_id, "MIX-1")
      assert_eq(packed.path[1].transformation_id, "PACKING-1")
    }
  }
}

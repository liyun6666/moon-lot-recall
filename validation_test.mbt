///|
fn sample_ledger() -> @moon-lot-recall.Ledger {
  {
    schema_version: 1,
    lots: [
      {
        id: "RAW-1",
        product: "flour",
        facility: "Mill A",
        quantity_g: 1000L,
        produced_at: 10L,
      },
      {
        id: "RAW-2",
        product: "salt",
        facility: "Mill A",
        quantity_g: 100L,
        produced_at: 10L,
      },
      {
        id: "CAKE-1",
        product: "cracker",
        facility: "Mill A",
        quantity_g: 900L,
        produced_at: 20L,
      },
    ],
    transformations: [
      {
        id: "MIX-1",
        facility: "Mill A",
        occurred_at: 20L,
        inputs: [
          { lot_id: "RAW-1", quantity_g: 900L, },
          { lot_id: "RAW-2", quantity_g: 100L, },
        ],
        outputs: [{ lot_id: "CAKE-1", quantity_g: 900L, }],
      },
    ],
    shipments: [
      {
        id: "SHIP-1",
        lot_id: "CAKE-1",
        quantity_g: 500L,
        consignee: "Store A",
        shipped_at: 30L,
        reference: "INV-1",
      },
    ],
  }
}

///|
fn has_code(report : @moon-lot-recall.ValidationReport, code : String) -> Bool {
  for diagnostic in report.diagnostics {
    if diagnostic.code == code {
      return true
    }
  }
  false
}

///|
test "valid ledger passes structural and mass checks" {
  let result = @moon-lot-recall.validate_ledger(sample_ledger())
  assert_true(result.valid)
  assert_eq(result.diagnostics.length(), 0)
}

///|
test "unknown input lot is rejected" {
  let ledger = sample_ledger()
  ledger.transformations[0].inputs[0] = { lot_id: "MISSING", quantity_g: 900L, }
  let result = @moon-lot-recall.validate_ledger(ledger)
  assert_false(result.valid)
  assert_true(has_code(result, "unknown-input-lot"))
}

///|
test "overallocated lot is rejected" {
  let ledger = sample_ledger()
  ledger.shipments.push({
    id: "SHIP-RAW",
    lot_id: "RAW-1",
    quantity_g: 200L,
    consignee: "Store B",
    shipped_at: 21L,
    reference: "INV-2",
  })
  let result = @moon-lot-recall.validate_ledger(ledger)
  assert_false(result.valid)
  assert_true(has_code(result, "overallocated-lot"))
}

///|
test "future input is rejected independently of array order" {
  let ledger = sample_ledger()
  ledger.lots[0] = { ..ledger.lots[0], produced_at: 21L, }
  let result = @moon-lot-recall.validate_ledger(ledger)
  assert_false(result.valid)
  assert_true(has_code(result, "input-not-yet-produced"))
}

///|
test "output mass must not exceed input mass" {
  let ledger = sample_ledger()
  ledger.lots[2] = { ..ledger.lots[2], quantity_g: 1100L, }
  ledger.transformations[0].outputs[0] = {
    lot_id: "CAKE-1",
    quantity_g: 1100L,
  }
  let result = @moon-lot-recall.validate_ledger(ledger)
  assert_false(result.valid)
  assert_true(has_code(result, "mass-created"))
}

///|
test "seed must exist at cutoff" {
  let ledger = sample_ledger()
  let request : @moon-lot-recall.RecallRequest = {
    id: "R-1",
    reason: "lab signal",
    seed_lots: ["RAW-1"],
    as_of: 9L,
  }
  let result = @moon-lot-recall.validate_request(ledger, request)
  assert_false(result.valid)
  assert_true(has_code(result, "future-seed"))
}

///|
test "duplicate lot identifiers are rejected before traversal" {
  let ledger = sample_ledger()
  ledger.lots.push({
    id: "RAW-1",
    product: "different flour",
    facility: "Mill A",
    quantity_g: 10L,
    produced_at: 10L,
  })
  let result = @moon-lot-recall.validate_ledger(ledger)
  assert_true(has_code(result, "duplicate-lot"))
}

///|
test "two transformations cannot claim the same output lot" {
  let ledger = sample_ledger()
  ledger.transformations.push({
    id: "MIX-2",
    facility: "Mill A",
    occurred_at: 20L,
    inputs: [{ lot_id: "RAW-1", quantity_g: 50L, }],
    outputs: [{ lot_id: "CAKE-1", quantity_g: 900L, }],
  })
  let result = @moon-lot-recall.validate_ledger(ledger)
  assert_true(has_code(result, "multiple-producers"))
}

///|
test "output lot quantity must match the processing event" {
  let ledger = sample_ledger()
  ledger.lots[2] = { ..ledger.lots[2], quantity_g: 850L, }
  let result = @moon-lot-recall.validate_ledger(ledger)
  assert_true(has_code(result, "output-quantity-mismatch"))
}

///|
test "shipment before lot production is invalid" {
  let ledger = sample_ledger()
  ledger.shipments[0] = { ..ledger.shipments[0], shipped_at: 19L, }
  let result = @moon-lot-recall.validate_ledger(ledger)
  assert_true(has_code(result, "shipment-before-production"))
}

///|
test "unrecognized schema version must fail closed" {
  let ledger = { ..sample_ledger(), schema_version: 2, }
  let result = @moon-lot-recall.validate_ledger(ledger)
  assert_true(has_code(result, "unsupported-version"))
}

///|
test "duplicate suspect seeds are rejected" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "R-DUP",
    reason: "supplier alert",
    seed_lots: ["RAW-1", "RAW-1"],
    as_of: 40L,
  }
  let result = @moon-lot-recall.validate_request(sample_ledger(), request)
  assert_true(has_code(result, "duplicate-seed"))
}

///|
test "unknown suspect seed cannot create an empty-looking report" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "R-UNKNOWN",
    reason: "supplier alert",
    seed_lots: ["NONE"],
    as_of: 40L,
  }
  match @moon-lot-recall.analyze(sample_ledger(), request) {
    Ok(_) => fail("unknown seed must not be presented as zero impact")
    Err(result) => assert_true(has_code(result, "unknown-seed"))
  }
}

///|
test "ledger JSON round trips with exact integer grams" {
  let original = sample_ledger()
  match
    @moon-lot-recall.decode_ledger(@moon-lot-recall.encode_ledger(original)) {
    Err(_) => fail("encoded ledger should decode")
    Ok(decoded) => {
      assert_eq(decoded.lots.length(), 3)
      assert_eq(decoded.lots[0].quantity_g, 1000L)
      assert_true(@moon-lot-recall.validate_ledger(decoded).valid)
    }
  }
}

///|
test "duplicate JSON keys are rejected" {
  let input = "{\"schema_version\":1,\"schema_version\":2,\"lots\":[],\"transformations\":[],\"shipments\":[]}"
  match @moon-lot-recall.decode_ledger(input) {
    Ok(_) => fail("duplicate key must be rejected")
    Err(error) => assert_eq(error.code, "invalid-json")
  }
}

///|
test "missing required ledger field is rejected" {
  match @moon-lot-recall.decode_ledger("{\"schema_version\":1,\"lots\":[]}") {
    Ok(_) => fail("missing arrays must be rejected")
    Err(error) => assert_eq(error.code, "invalid-ledger-shape")
  }
}

///|
test "request JSON round trips" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "R-1",
    reason: "supplier notice",
    seed_lots: ["RAW-1"],
    as_of: 50L,
  }
  match
    @moon-lot-recall.decode_request(@moon-lot-recall.encode_request(request)) {
    Ok(decoded) => assert_eq(decoded.seed_lots[0], "RAW-1")
    Err(_) => fail("encoded request should decode")
  }
}

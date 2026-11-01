///|
test "Markdown report uses cautious language and evidence path" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "RECALL-1",
    reason: "supplier signal",
    seed_lots: ["RAW-1"],
    as_of: 40L,
  }
  match @moon-lot-recall.analyze(sample_ledger(), request) {
    Err(_) => fail("valid case expected")
    Ok(report) => {
      let text = @moon-lot-recall.render_markdown(report)
      assert_true(text.contains("may be affected"))
      assert_true(text.contains("MIX-1 -> CAKE-1"))
      assert_true(text.contains("Store A"))
    }
  }
}

///|
test "shipment CSV keeps comma inside consignee field" {
  let ledger = sample_ledger()
  ledger.shipments[0] = { ..ledger.shipments[0], consignee: "Store A, North", }
  let request : @moon-lot-recall.RecallRequest = {
    id: "RECALL-2",
    reason: "supplier signal",
    seed_lots: ["RAW-1"],
    as_of: 40L,
  }
  match @moon-lot-recall.analyze(ledger, request) {
    Err(_) => fail("valid case expected")
    Ok(report) => {
      let csv = @moon-lot-recall.render_shipments_csv(report)
      match @moon-lot-recall.parse_csv(csv) {
        Err(_) => fail("report CSV must parse")
        Ok(table) => assert_eq(table.rows[0].cells[3], "Store A, North")
      }
    }
  }
}

///|
test "shipment CSV neutralizes a spreadsheet formula in consignee" {
  let ledger = sample_ledger()
  ledger.shipments[0] = {
    ..ledger.shipments[0],
    consignee: "=HYPERLINK(\"https://example.test\")",
  }
  let request : @moon-lot-recall.RecallRequest = {
    id: "RECALL-CSV",
    reason: "supplier signal",
    seed_lots: ["RAW-1"],
    as_of: 40L,
  }
  match @moon-lot-recall.analyze(ledger, request) {
    Err(_) => fail("valid ledger should analyze")
    Ok(report) => {
      let csv = @moon-lot-recall.render_shipments_csv(report)
      match @moon-lot-recall.parse_csv(csv) {
        Err(_) => fail("safe CSV must remain parseable")
        Ok(table) => assert_true(table.rows[0].cells[3].has_prefix("'="))
      }
    }
  }
}

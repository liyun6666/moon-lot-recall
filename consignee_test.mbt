///|
test "two shipments to the same consignee form one packet" {
  let ledger = sample_ledger()
  ledger.shipments[0] = { ..ledger.shipments[0], quantity_g: 300L, }
  ledger.shipments.push({
    id: "SHIP-2",
    lot_id: "CAKE-1",
    quantity_g: 200L,
    consignee: "Store A",
    shipped_at: 35L,
    reference: "INV-2",
  })
  let request : @moon-lot-recall.RecallRequest = {
    id: "CASE-GROUP",
    reason: "supplier notice",
    seed_lots: ["RAW-1"],
    as_of: 40L,
  }
  match @moon-lot-recall.group_consignees(ledger, request) {
    Err(_) => fail("valid case must group")
    Ok(report) => {
      assert_eq(report.packets.length(), 1)
      assert_eq(report.shipment_count, 2)
      assert_eq(report.packets[0].total_quantity_g, 500L)
      assert_eq(report.packets[0].lot_ids, ["CAKE-1"])
      assert_eq(report.packets[0].references, ["INV-1", "INV-2"])
      assert_eq(report.packets[0].earliest_shipment_at, 30L)
      assert_eq(report.packets[0].latest_shipment_at, 35L)
    }
  }
}

///|
test "different recipients remain separate and later shipments are excluded" {
  let ledger = sample_ledger()
  ledger.shipments[0] = { ..ledger.shipments[0], quantity_g: 200L, }
  ledger.shipments.push({
    id: "SHIP-2",
    lot_id: "CAKE-1",
    quantity_g: 200L,
    consignee: "Store B",
    shipped_at: 35L,
    reference: "INV-2",
  })
  ledger.shipments.push({
    id: "SHIP-3",
    lot_id: "CAKE-1",
    quantity_g: 200L,
    consignee: "Store C",
    shipped_at: 45L,
    reference: "INV-3",
  })
  let request : @moon-lot-recall.RecallRequest = {
    id: "CASE-GROUP-2",
    reason: "supplier notice",
    seed_lots: ["RAW-1"],
    as_of: 40L,
  }
  match @moon-lot-recall.group_consignees(ledger, request) {
    Err(_) => fail("valid case must group")
    Ok(report) => {
      assert_eq(report.packets.length(), 2)
      assert_eq(report.total_quantity_g, 400L)
      assert_eq(report.packets[0].consignee, "Store A")
      assert_eq(report.packets[1].consignee, "Store B")
      let csv = @moon-lot-recall.render_consignees_csv(report)
      assert_false(csv.contains("Store C"))
    }
  }
}

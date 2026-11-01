///|
test "three CSV files produce an analyzable ledger" {
  let lots = (
    #|id,product,facility,quantity_g,produced_at
    #|RAW-1,flour,Mill A,1000,10
    #|RAW-2,salt,Mill A,100,10
    #|CAKE-1,cracker,Mill A,900,20
    #|
  )
  let transformations = (
    #|id,facility,occurred_at,direction,lot_id,quantity_g
    #|MIX-1,Mill A,20,input,RAW-1,900
    #|MIX-1,Mill A,20,input,RAW-2,100
    #|MIX-1,Mill A,20,output,CAKE-1,900
    #|
  )
  let shipments = (
    #|id,lot_id,quantity_g,consignee,shipped_at,reference
    #|SHIP-1,CAKE-1,500,Store A,30,INV-1
    #|
  )
  match @moon-lot-recall.import_csv(lots, transformations, shipments) {
    Err(_) => fail("valid operational CSV must import")
    Ok(ledger) => {
      assert_eq(ledger.lots.length(), 3)
      assert_eq(ledger.transformations[0].inputs.length(), 2)
      let request : @moon-lot-recall.RecallRequest = {
        id: "CASE-CSV", reason: "supplier notice", seed_lots: ["RAW-1"], as_of: 40L,
      }
      match @moon-lot-recall.analyze(ledger, request) {
        Err(_) => fail("imported ledger should analyze")
        Ok(report) => assert_eq(report.affected_shipments[0].consignee, "Store A")
      }
    }
  }
}

///|
test "CSV import catches conflicting event headers" {
  let lots = "id,product,facility,quantity_g,produced_at\nRAW-1,flour,Mill A,1000,10\nCAKE-1,cracker,Mill A,900,20\n"
  let transformations = "id,facility,occurred_at,direction,lot_id,quantity_g\nMIX-1,Mill A,20,input,RAW-1,900\nMIX-1,Mill B,20,output,CAKE-1,900\n"
  let shipments = "id,lot_id,quantity_g,consignee,shipped_at,reference\n"
  match @moon-lot-recall.import_csv(lots, transformations, shipments) {
    Ok(_) => fail("event conflict must fail")
    Err(report) => assert_true(has_code(report, "csv-event-conflict"))
  }
}

///|
test "CSV import rejects malformed integer quantity" {
  let lots = "id,product,facility,quantity_g,produced_at\nRAW-1,flour,Mill A,1.5,10\n"
  let transformations = "id,facility,occurred_at,direction,lot_id,quantity_g\n"
  let shipments = "id,lot_id,quantity_g,consignee,shipped_at,reference\n"
  match @moon-lot-recall.import_csv(lots, transformations, shipments) {
    Ok(_) => fail("fractional gram must fail")
    Err(report) => assert_true(has_code(report, "csv-invalid-integer"))
  }
}

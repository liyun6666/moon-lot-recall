///|
test "inventory reflects processing and shipments at cutoff" {
  match @moon-lot-recall.inventory_at(sample_ledger(), 40L) {
    Err(_) => fail("valid ledger must reconstruct inventory")
    Ok(inventory) => {
      match inventory.for_lot("RAW-1") {
        None => fail("raw lot should exist")
        Some(row) => assert_eq(row.on_hand_g, 100L)
      }
      match inventory.for_lot("CAKE-1") {
        None => fail("finished lot should exist")
        Some(row) => assert_eq(row.on_hand_g, 400L)
      }
    }
  }
}

///|
test "inventory cutoff excludes future output lot" {
  match @moon-lot-recall.inventory_at(sample_ledger(), 15L) {
    Err(_) => fail("valid cutoff must work")
    Ok(inventory) => {
      assert_eq(inventory.rows.length(), 2)
      assert_true(inventory.for_lot("CAKE-1") is None)
    }
  }
}

///|
test "action plan separates on-hand hold and shipment contact" {
  let request : @moon-lot-recall.RecallRequest = {
    id: "CASE-ACT", reason: "supplier notice", seed_lots: ["RAW-1"], as_of: 40L,
  }
  match @moon-lot-recall.plan_actions(sample_ledger(), request) {
    Err(_) => fail("valid case should produce actions")
    Ok(plan) => {
      assert_eq(plan.holds.length(), 2)
      assert_eq(plan.contacts.length(), 1)
      assert_eq(plan.estimated_hold_g, 500L)
      assert_eq(plan.shipped_for_review_g, 500L)
      assert_eq(plan.contacts[0].reference, "INV-1")
    }
  }
}

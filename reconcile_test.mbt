///|
test "physical count reports exact match, shortage, and missing count" {
  let counts : Array[@moon-lot-recall.StockCount] = [
    {
      lot_id: "RAW-1",
      facility: "Mill A",
      counted_g: 100L,
      counted_at: 40L,
      reference: "COUNT-1",
    },
    {
      lot_id: "CAKE-1",
      facility: "Mill A",
      counted_g: 350L,
      counted_at: 40L,
      reference: "COUNT-2",
    },
  ]
  match @moon-lot-recall.reconcile_stock(sample_ledger(), counts, 40L) {
    Err(_) => fail("valid physical counts should reconcile")
    Ok(report) => {
      assert_false(report.balanced)
      assert_eq(report.rows[0].status, "matched")
      assert_eq(report.rows[1].status, "shortage")
      assert_eq(report.rows[1].difference_g, -50L)
      assert_eq(report.missing_counts, ["RAW-2"])
    }
  }
}

///|
test "zero count is valid and marks a shortage" {
  let counts : Array[@moon-lot-recall.StockCount] = [
    {
      lot_id: "RAW-1",
      facility: "Mill A",
      counted_g: 0L,
      counted_at: 40L,
      reference: "COUNT-1",
    },
  ]
  match @moon-lot-recall.reconcile_stock(sample_ledger(), counts, 40L) {
    Err(_) => fail("zero physical stock is a legitimate observation")
    Ok(report) => assert_eq(report.rows[0].difference_g, -100L)
  }
}

///|
test "physical count rejects duplicate lot and wrong facility" {
  let counts : Array[@moon-lot-recall.StockCount] = [
    {
      lot_id: "RAW-1",
      facility: "Mill A",
      counted_g: 100L,
      counted_at: 40L,
      reference: "A",
    },
    {
      lot_id: "RAW-1",
      facility: "Other",
      counted_g: 100L,
      counted_at: 40L,
      reference: "B",
    },
  ]
  match @moon-lot-recall.reconcile_stock(sample_ledger(), counts, 40L) {
    Ok(_) => fail("ambiguous counts must fail closed")
    Err(report) => {
      assert_true(has_code(report, "duplicate-count"))
      assert_true(has_code(report, "count-facility-mismatch"))
    }
  }
}

///|
test "stock count CSV supports quoted facility and catches fractional grams" {
  let good = "lot_id,facility,counted_g,counted_at,reference\nRAW-1,\"Mill, A\",0,40,C-1\n"
  match @moon-lot-recall.parse_stock_counts_csv(good) {
    Err(_) => fail("quoted facility must parse")
    Ok(counts) => assert_eq(counts[0].facility, "Mill, A")
  }
  let bad = "lot_id,facility,counted_g,counted_at,reference\nRAW-1,Mill A,1.5,40,C-1\n"
  match @moon-lot-recall.parse_stock_counts_csv(bad) {
    Ok(_) => fail("fractional grams must fail")
    Err(report) => assert_true(has_code(report, "csv-invalid-integer"))
  }
}

///|
test "physical count must use the comparison cutoff" {
  let counts : Array[@moon-lot-recall.StockCount] = [
    {
      lot_id: "RAW-1",
      facility: "Mill A",
      counted_g: 100L,
      counted_at: 39L,
      reference: "OLD-COUNT",
    },
  ]
  match @moon-lot-recall.reconcile_stock(sample_ledger(), counts, 40L) {
    Ok(_) =>
      fail("stale physical count cannot be compared to current book stock")
    Err(report) => assert_true(has_code(report, "invalid-count-time"))
  }
}

///|
test "surplus count is reported with signed difference" {
  let counts : Array[@moon-lot-recall.StockCount] = [
    {
      lot_id: "RAW-1",
      facility: "Mill A",
      counted_g: 120L,
      counted_at: 40L,
      reference: "COUNT-1",
    },
  ]
  match @moon-lot-recall.reconcile_stock(sample_ledger(), counts, 40L) {
    Err(_) => fail("surplus is a finding, not invalid evidence")
    Ok(report) => {
      assert_eq(report.rows[0].difference_g, 20L)
      assert_eq(report.rows[0].status, "surplus")
      assert_false(report.balanced)
    }
  }
}

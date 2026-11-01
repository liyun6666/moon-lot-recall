///|
test "upstream trace finds both ingredients of a mixed lot" {
  match @moon-lot-recall.trace_upstream(sample_ledger(), "CAKE-1", 40L) {
    Err(_) => fail("valid target should trace")
    Ok(report) => {
      assert_eq(report.lots.length(), 3)
      assert_true(report.lots[0].is_source)
      assert_true(report.lots[1].is_source)
      assert_eq(report.lots[0].path_to_target[0].transformation_id, "MIX-1")
      assert_eq(report.lots[2].path_to_target.length(), 0)
    }
  }
}

///|
test "upstream trace rejects nonexistent target" {
  match @moon-lot-recall.trace_upstream(sample_ledger(), "MISSING", 40L) {
    Ok(_) => fail("unknown target must fail")
    Err(report) => assert_true(has_code(report, "unknown-target"))
  }
}

///|
test "upstream trace respects cutoff" {
  match @moon-lot-recall.trace_upstream(sample_ledger(), "CAKE-1", 19L) {
    Ok(_) => fail("future target must fail")
    Err(report) => assert_true(has_code(report, "invalid-target-cutoff"))
  }
}

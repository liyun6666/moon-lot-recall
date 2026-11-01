///|
test "CSV parser handles quoted commas, doubled quotes and multiline fields" {
  let input = "id,note\r\nA,\"one,two\"\r\nB,\"say \"\"yes\"\"\"\r\nC,\"line 1\r\nline 2\"\r\n"
  match @moon-lot-recall.parse_csv(input) {
    Err(_) => fail("valid CSV must parse")
    Ok(table) => {
      assert_eq(table.rows.length(), 3)
      assert_eq(table.rows[0].cells[1], "one,two")
      assert_eq(table.rows[1].cells[1], "say \"yes\"")
      assert_eq(table.rows[2].cells[1], "line 1\nline 2")
      assert_eq(table.rows[2].line, 4)
    }
  }
}

///|
test "CSV parser rejects bare quotes" {
  match @moon-lot-recall.parse_csv("id,note\nA,bad\"text\n") {
    Ok(_) => fail("bare quote must fail")
    Err(error) => assert_eq(error.code, "csv-bare-quote")
  }
}

///|
test "CSV parser rejects shifted rows" {
  match @moon-lot-recall.parse_csv("id,note\nA,one,extra\n") {
    Ok(_) => fail("unexpected column must fail")
    Err(error) => assert_eq(error.code, "csv-column-count")
  }
}

///|
test "CSV parser rejects duplicate headers" {
  match @moon-lot-recall.parse_csv("id,id\nA,B\n") {
    Ok(_) => fail("duplicate header must fail")
    Err(error) => assert_eq(error.code, "csv-duplicate-header")
  }
}

///|
test "CSV parser handles final row without newline" {
  match @moon-lot-recall.parse_csv("id,note\nA,hello") {
    Err(_) => fail("valid CSV must parse")
    Ok(table) => assert_eq(table.rows[0].cells[1], "hello")
  }
}

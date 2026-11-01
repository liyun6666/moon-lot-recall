///|
pub(all) struct CsvRecord {
  line : Int32
  cells : Array[String]
} derive(Debug)

///|
pub(all) struct CsvTable {
  headers : Array[String]
  rows : Array[CsvRecord]
} derive(Debug)

///|
fn csv_error(code : String, line : Int32, message : String) -> Diagnostic {
  issue("error", code, "csv:\{line}", message)
}

///|
fn finish_csv_row(
  rows : Array[CsvRecord],
  cells : Array[String],
  field : StringBuilder,
  line : Int32,
) -> Unit {
  cells.push(field.to_string())
  rows.push({ line, cells: cells.copy(), })
  cells.clear()
  field.reset()
}

///|
/// Parse RFC 4180-style CSV with doubled quotes and quoted newlines. CRLF
/// and CR are normalized to LF. A malformed quoted field is rejected with a
/// row number rather than silently shifting columns.
pub fn parse_csv(text : String) -> Result[CsvTable, Diagnostic] {
  if text.length() > 16000000 {
    return Err(
      csv_error("csv-too-large", 1, "CSV input exceeds 16 million code units"),
    )
  }
  let normalized = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let rows : Array[CsvRecord] = []
  let cells : Array[String] = []
  let field = StringBuilder()
  let mut line = 1
  let mut row_line = 1
  let mut quoted = false
  let mut after_quote = false
  let mut field_started = false
  let mut quote_pending = false
  for char in normalized {
    if quoted {
      if quote_pending {
        if char == '"' {
          field.write_char('"')
          quote_pending = false
          continue
        }
        quoted = false
        after_quote = true
        quote_pending = false
      } else if char == '"' {
        quote_pending = true
        continue
      } else {
        field.write_char(char)
        if char == '\n' {
          line += 1
        }
        continue
      }
    }
    if after_quote {
      if char == ',' {
        cells.push(field.to_string())
        field.reset()
        field_started = false
        after_quote = false
      } else if char == '\n' {
        finish_csv_row(rows, cells, field, row_line)
        field_started = false
        after_quote = false
        line += 1
        row_line = line
      } else {
        return Err(
          csv_error(
            "csv-trailing-character", line, "only a comma or newline may follow a closing quote",
          ),
        )
      }
      continue
    }
    if char == '"' {
      if field_started {
        return Err(
          csv_error("csv-bare-quote", line, "quote inside an unquoted field"),
        )
      }
      quoted = true
      field_started = true
    } else if char == ',' {
      cells.push(field.to_string())
      field.reset()
      field_started = false
    } else if char == '\n' {
      finish_csv_row(rows, cells, field, row_line)
      field_started = false
      line += 1
      row_line = line
    } else {
      field.write_char(char)
      field_started = true
    }
    if cells.length() > 64 || rows.length() > 100000 {
      return Err(
        csv_error("csv-limit", line, "CSV exceeds the row or column limit"),
      )
    }
  }
  if quoted && !quote_pending {
    return Err(
      csv_error("csv-unclosed-quote", line, "quoted field is not closed"),
    )
  }
  if quote_pending {
    quoted = false
    after_quote = true
  }
  if field_started || after_quote || !cells.is_empty() {
    finish_csv_row(rows, cells, field, row_line)
  }
  if rows.is_empty() {
    return Err(csv_error("csv-empty", 1, "CSV has no header row"))
  }
  let headers = rows[0].cells
  let seen : Map[String, Bool] = Map([])
  for header in headers {
    if header.trim().is_empty() {
      return Err(
        csv_error("csv-empty-header", 1, "header names cannot be empty"),
      )
    }
    if seen.contains(header) {
      return Err(
        csv_error(
          "csv-duplicate-header",
          1,
          "header name is repeated: \{header}",
        ),
      )
    }
    seen[header] = true
  }
  let records : Array[CsvRecord] = []
  for i in 1..<rows.length() {
    let row = rows[i]
    if row.cells.length() != headers.length() {
      return Err(
        csv_error(
          "csv-column-count",
          row.line,
          "row has \{row.cells.length()} cells; expected \{headers.length()}",
        ),
      )
    }
    records.push(row)
  }
  Ok({ headers, rows: records, })
}

///|
pub fn CsvTable::column(self : CsvTable, name : String) -> Int32? {
  for index, header in self.headers {
    if header == name {
      return Some(index)
    }
  }
  None
}

///|
pub fn CsvTable::has_exact_headers(
  self : CsvTable,
  expected : Array[String],
) -> Bool {
  if self.headers.length() != expected.length() {
    return false
  }
  for index, header in expected {
    if self.headers[index] != header {
      return false
    }
  }
  true
}

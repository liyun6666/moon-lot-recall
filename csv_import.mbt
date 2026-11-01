///|
fn table_error(table : String, code : String, message : String) -> Diagnostic {
  issue("error", code, table, message)
}

///|
fn expect_headers(table : CsvTable, name : String, headers : Array[String]) -> Diagnostic? {
  if table.has_exact_headers(headers) {
    None
  } else {
    Some(table_error(name, "csv-schema", "expected columns in order: \{headers.join(",")}"))
  }
}

///|
fn csv_int(cell : String, file : String, line : Int, field : String, findings : Array[Diagnostic]) -> Int64? {
  let value = @string.parse_int64(cell.trim()) catch {
    _ => {
      findings.push(issue("error", "csv-invalid-integer", "\{file}:\{line}", "\{field} must be an exact signed integer"))
      return None
    }
  }
  Some(value)
}

///|
fn parse_lots_csv(table : CsvTable, findings : Array[Diagnostic]) -> Array[Lot] {
  let lots : Array[Lot] = []
  for row in table.rows {
    match (
      csv_int(row.cells[3], "lots.csv", row.line, "quantity_g", findings),
      csv_int(row.cells[4], "lots.csv", row.line, "produced_at", findings),
    ) {
      (Some(quantity_g), Some(produced_at)) => lots.push({
        id: row.cells[0],
        product: row.cells[1],
        facility: row.cells[2],
        quantity_g,
        produced_at,
      })
      _ => ()
    }
  }
  lots
}

///|
fn parse_transformations_csv(
  table : CsvTable,
  findings : Array[Diagnostic],
) -> Array[Transformation] {
  let transformations : Array[Transformation] = []
  let positions : Map[String, Int] = Map([])
  for row in table.rows {
    let id = row.cells[0]
    let facility = row.cells[1]
    let time = csv_int(row.cells[2], "transformations.csv", row.line, "occurred_at", findings)
    let direction = row.cells[3]
    let lot_id = row.cells[4]
    let quantity = csv_int(row.cells[5], "transformations.csv", row.line, "quantity_g", findings)
    if direction != "input" && direction != "output" {
      findings.push(issue("error", "csv-invalid-direction", "transformations.csv:\{row.line}", "direction must be input or output"))
      continue
    }
    match (time, quantity) {
      (Some(occurred_at), Some(quantity_g)) => {
        let position = match positions.get(id) {
          Some(existing) => existing
          None => {
            let next = transformations.length()
            transformations.push({ id, facility, occurred_at, inputs: [], outputs: [], })
            positions[id] = next
            next
          }
        }
        let existing = transformations[position]
        if existing.facility != facility || existing.occurred_at != occurred_at {
          findings.push(issue("error", "csv-event-conflict", "transformations.csv:\{row.line}", "same event id has conflicting facility or time"))
          continue
        }
        let portion : Portion = { lot_id, quantity_g, }
        if direction == "input" {
          existing.inputs.push(portion)
        } else {
          existing.outputs.push(portion)
        }
      }
      _ => ()
    }
  }
  transformations
}

///|
fn parse_shipments_csv(table : CsvTable, findings : Array[Diagnostic]) -> Array[Shipment] {
  let shipments : Array[Shipment] = []
  for row in table.rows {
    match (
      csv_int(row.cells[2], "shipments.csv", row.line, "quantity_g", findings),
      csv_int(row.cells[4], "shipments.csv", row.line, "shipped_at", findings),
    ) {
      (Some(quantity_g), Some(shipped_at)) => shipments.push({
        id: row.cells[0],
        lot_id: row.cells[1],
        quantity_g,
        consignee: row.cells[3],
        shipped_at,
        reference: row.cells[5],
      })
      _ => ()
    }
  }
  shipments
}

///|
/// Import three small operational CSV tables into the same typed ledger used
/// by the JSON API. Every numeric value remains an exact integer.
pub fn import_csv(
  lots_csv : String,
  transformations_csv : String,
  shipments_csv : String,
) -> Result[Ledger, ValidationReport] {
  let findings : Array[Diagnostic] = []
  let lots_table = match parse_csv(lots_csv) {
    Ok(table) => Some(table)
    Err(error) => {
      findings.push(error)
      None
    }
  }
  let transformations_table = match parse_csv(transformations_csv) {
    Ok(table) => Some(table)
    Err(error) => {
      findings.push(error)
      None
    }
  }
  let shipments_table = match parse_csv(shipments_csv) {
    Ok(table) => Some(table)
    Err(error) => {
      findings.push(error)
      None
    }
  }
  if lots_table is Some(table) {
    if expect_headers(table, "lots.csv", ["id", "product", "facility", "quantity_g", "produced_at"]) is Some(error) {
      findings.push(error)
    }
  }
  if transformations_table is Some(table) {
    if expect_headers(table, "transformations.csv", ["id", "facility", "occurred_at", "direction", "lot_id", "quantity_g"]) is Some(error) {
      findings.push(error)
    }
  }
  if shipments_table is Some(table) {
    if expect_headers(table, "shipments.csv", ["id", "lot_id", "quantity_g", "consignee", "shipped_at", "reference"]) is Some(error) {
      findings.push(error)
    }
  }
  if !findings.is_empty() {
    return Err(report_from(findings))
  }
  let lots = match lots_table {
    Some(table) => parse_lots_csv(table, findings)
    None => []
  }
  let transformations = match transformations_table {
    Some(table) => parse_transformations_csv(table, findings)
    None => []
  }
  let shipments = match shipments_table {
    Some(table) => parse_shipments_csv(table, findings)
    None => []
  }
  if !findings.is_empty() {
    return Err(report_from(findings))
  }
  let ledger : Ledger = { schema_version: 1, lots, transformations, shipments, }
  let validation = validate_ledger(ledger)
  if validation.valid { Ok(ledger) } else { Err(validation) }
}

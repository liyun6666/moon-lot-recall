///|
/// A signed-off stock observation made at a physical location. The operator
/// supplies the count; this library never invents a measured quantity.
pub(all) struct StockCount {
  lot_id : String
  facility : String
  counted_g : Int64
  counted_at : Int64
  reference : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ReconciliationRow {
  lot_id : String
  facility : String
  expected_g : Int64
  counted_g : Int64
  difference_g : Int64
  status : String
  count_reference : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ReconciliationReport {
  as_of : Int64
  rows : Array[ReconciliationRow]
  missing_counts : Array[String]
  total_expected_g : Int64
  total_counted_g : Int64
  balanced : Bool
} derive(Eq, Debug, ToJson, FromJson)

///|
/// The CSV is deliberately strict: a wrong facility or duplicate lot could
/// otherwise make a shortage look like an exact count.
pub fn parse_stock_counts_csv(
  text : String,
) -> Result[Array[StockCount], ValidationReport] {
  let table = match parse_csv(text) {
    Err(diagnostic) => return Err(report_from([diagnostic]))
    Ok(value) => value
  }
  let expected = ["lot_id", "facility", "counted_g", "counted_at", "reference"]
  if !table.has_exact_headers(expected) {
    return Err(
      report_from([
        issue(
          "error", "count-csv-schema", "counts.csv", "expected lot_id,facility,counted_g,counted_at,reference",
        ),
      ]),
    )
  }
  let counts : Array[StockCount] = []
  let findings : Array[Diagnostic] = []
  for row in table.rows {
    let amount = csv_int(
      row.cells[2],
      "counts.csv",
      row.line,
      "counted_g",
      findings,
    )
    let time = csv_int(
      row.cells[3],
      "counts.csv",
      row.line,
      "counted_at",
      findings,
    )
    match (amount, time) {
      (Some(counted_g), Some(counted_at)) =>
        counts.push({
          lot_id: row.cells[0],
          facility: row.cells[1],
          counted_g,
          counted_at,
          reference: row.cells[4],
        })
      _ => ()
    }
  }
  if !findings.is_empty() {
    Err(report_from(findings))
  } else {
    Ok(counts)
  }
}

///|
fn validate_stock_counts(
  ledger : Ledger,
  counts : Array[StockCount],
  as_of : Int64,
) -> ValidationReport {
  let findings : Array[Diagnostic] = []
  let lots : Map[String, Lot] = Map([])
  let seen : Map[String, Bool] = Map([])
  for lot in ledger.lots {
    lots[lot.id] = lot
  }
  if counts.length() > 100000 {
    findings.push(
      issue(
        "error", "count-limit", "counts", "at most 100000 count rows are supported",
      ),
    )
  }
  for count in counts {
    if seen.contains(count.lot_id) {
      findings.push(
        issue(
          "error",
          "duplicate-count",
          count.lot_id,
          "lot has more than one physical count",
        ),
      )
    }
    seen[count.lot_id] = true
    if !valid_id(count.lot_id) {
      findings.push(
        issue(
          "error",
          "invalid-count-lot",
          count.lot_id,
          "lot id has an invalid shape",
        ),
      )
    }
    if !valid_label(count.facility) {
      findings.push(
        issue(
          "error",
          "invalid-count-facility",
          count.lot_id,
          "facility is required",
        ),
      )
    }
    if !valid_label(count.reference) {
      findings.push(
        issue(
          "error",
          "invalid-count-reference",
          count.lot_id,
          "a physical count reference is required",
        ),
      )
    }
    if count.counted_g < 0L || count.counted_g > 1000000000000L {
      findings.push(
        issue(
          "error",
          "invalid-count-quantity",
          count.lot_id,
          "counted_g must be 0..1e12",
        ),
      )
    }
    if !valid_time(count.counted_at) || count.counted_at != as_of {
      findings.push(
        issue(
          "error",
          "invalid-count-time",
          count.lot_id,
          "count timestamp must equal the comparison cutoff",
        ),
      )
    }
    match lots.get(count.lot_id) {
      None =>
        findings.push(
          issue(
            "error",
            "unknown-count-lot",
            count.lot_id,
            "counted lot is absent from ledger",
          ),
        )
      Some(lot) => {
        if lot.facility != count.facility {
          findings.push(
            issue(
              "error",
              "count-facility-mismatch",
              count.lot_id,
              "physical count belongs to a different facility",
            ),
          )
        }
        if lot.produced_at > count.counted_at {
          findings.push(
            issue(
              "error",
              "count-before-production",
              count.lot_id,
              "lot did not yet exist at count time",
            ),
          )
        }
      }
    }
  }
  report_from(findings)
}

///|
/// Compare a full physical count against reconstructed book stock at the
/// cutoff. Missing rows remain explicit; they never count as zero stock.
pub fn reconcile_stock(
  ledger : Ledger,
  counts : Array[StockCount],
  as_of : Int64,
) -> Result[ReconciliationReport, ValidationReport] {
  let book = match inventory_at(ledger, as_of) {
    Err(validation) => return Err(validation)
    Ok(value) => value
  }
  let validation = validate_stock_counts(ledger, counts, as_of)
  if !validation.valid {
    return Err(validation)
  }
  let by_lot : Map[String, StockCount] = Map([])
  for count in counts {
    by_lot[count.lot_id] = count
  }
  let rows : Array[ReconciliationRow] = []
  let missing_counts : Array[String] = []
  let mut expected_total = 0L
  let mut counted_total = 0L
  let mut balanced = true
  for expected in book.rows {
    expected_total += expected.on_hand_g
    match by_lot.get(expected.lot_id) {
      None => {
        missing_counts.push(expected.lot_id)
        balanced = false
      }
      Some(count) => {
        let delta = count.counted_g - expected.on_hand_g
        let status = if delta == 0L {
          "matched"
        } else if delta < 0L {
          "shortage"
        } else {
          "surplus"
        }
        if delta != 0L {
          balanced = false
        }
        counted_total += count.counted_g
        rows.push({
          lot_id: expected.lot_id,
          facility: expected.facility,
          expected_g: expected.on_hand_g,
          counted_g: count.counted_g,
          difference_g: delta,
          status,
          count_reference: count.reference,
        })
      }
    }
  }
  Ok({
    as_of,
    rows,
    missing_counts,
    total_expected_g: expected_total,
    total_counted_g: counted_total,
    balanced,
  })
}

///|
pub fn render_reconciliation_markdown(report : ReconciliationReport) -> String {
  let out = StringBuilder()
  out.write_string("# Physical stock reconciliation\n\n")
  out.write_string("Cutoff (Unix seconds): \{report.as_of}\n\n")
  out.write_string(
    "Counts and book stock use the same cutoff. Review each variance against the count sheet and event records.\n\n",
  )
  out.write_string(
    "| Lot | Facility | Book (g) | Counted (g) | Difference (g) | Status | Count reference |\n",
  )
  out.write_string("| --- | --- | ---: | ---: | ---: | --- | --- |\n")
  for row in report.rows {
    out.write_string(
      "| \{markdown_cell(row.lot_id)} | \{markdown_cell(row.facility)} | \{row.expected_g} | \{row.counted_g} | \{row.difference_g} | \{row.status} | \{markdown_cell(row.count_reference)} |\n",
    )
  }
  out.write_string(
    "\nMissing physical counts: \{report.missing_counts.join(", ")}\n",
  )
  out.write_string(
    "Book total: \{report.total_expected_g} g; counted total of supplied rows: \{report.total_counted_g} g.\n",
  )
  out.to_string()
}

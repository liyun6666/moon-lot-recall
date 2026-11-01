///|
/// One unresolved item that needs human investigation or recorded evidence.
pub(all) struct ReadinessItem {
  category : String
  entity_id : String
  detail : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ReadinessReport {
  recall_id : String
  as_of : Int64
  affected_lot_count : Int32
  affected_shipment_count : Int32
  physical_count_count : Int32
  acknowledged_shipment_count : Int32
  items : Array[ReadinessItem]
  evidence_review_complete : Bool
} derive(Eq, Debug, ToJson, FromJson)

///|
fn readiness_item(
  category : String,
  entity_id : String,
  detail : String,
) -> ReadinessItem {
  { category, entity_id, detail, }
}

///|
/// Combine physical count and outreach evidence for a single recall. This
/// intentionally makes no claim that product is safe, that a legal recall is
/// complete, or that a recipient actually quarantined stock.
pub fn review_readiness(
  ledger : Ledger,
  request : RecallRequest,
  counts : Array[StockCount],
  events : Array[ResponseEvent],
) -> Result[ReadinessReport, ValidationReport] {
  let impact = match analyze(ledger, request) {
    Err(validation) => return Err(validation)
    Ok(value) => value
  }
  let stock = match reconcile_stock(ledger, counts, request.as_of) {
    Err(validation) => return Err(validation)
    Ok(value) => value
  }
  let response = match review_responses(ledger, request, events) {
    Err(validation) => return Err(validation)
    Ok(value) => value
  }
  let counted : Map[String, ReconciliationRow] = Map([])
  let responded : Map[String, ResponseRow] = Map([])
  for row in stock.rows {
    counted[row.lot_id] = row
  }
  for row in response.rows {
    responded[row.shipment_id] = row
  }
  let items : Array[ReadinessItem] = []
  let mut physical_count_count = 0
  for lot in impact.affected_lots {
    match counted.get(lot.lot_id) {
      None =>
        items.push(
          readiness_item(
            "missing-count",
            lot.lot_id,
            "no physical count was supplied for an affected lot",
          ),
        )
      Some(row) => {
        physical_count_count += 1
        if row.difference_g < 0L {
          items.push(
            readiness_item(
              "stock-shortage",
              lot.lot_id,
              "physical count is \{0L - row.difference_g} g below book stock; check \{row.count_reference}",
            ),
          )
        } else if row.difference_g > 0L {
          items.push(
            readiness_item(
              "stock-surplus",
              lot.lot_id,
              "physical count is \{row.difference_g} g above book stock; check \{row.count_reference}",
            ),
          )
        }
      }
    }
  }
  let mut acknowledged_shipment_count = 0
  for shipment in impact.affected_shipments {
    match responded.get(shipment.shipment_id) {
      None =>
        items.push(
          readiness_item(
            "missing-response",
            shipment.shipment_id,
            "affected shipment has no response row",
          ),
        )
      Some(row) =>
        if row.status == "acknowledged" {
          acknowledged_shipment_count += 1
        } else {
          items.push(
            readiness_item(
              "contact-open",
              shipment.shipment_id,
              "latest contact status is \{row.status}; acknowledgement evidence is outstanding",
            ),
          )
        }
    }
  }
  Ok({
    recall_id: request.id,
    as_of: request.as_of,
    affected_lot_count: impact.affected_lots.length(),
    affected_shipment_count: impact.affected_shipments.length(),
    physical_count_count,
    acknowledged_shipment_count,
    items,
    evidence_review_complete: items.is_empty(),
  })
}

///|
pub fn render_readiness_markdown(report : ReadinessReport) -> String {
  let out = StringBuilder()
  out.write_string("# Evidence review: \{markdown_cell(report.recall_id)}\n\n")
  out.write_string("Cutoff (Unix seconds): \{report.as_of}\n\n")
  out.write_string(
    "This is an evidence checklist for human review, not a legal recall completion certificate.\n\n",
  )
  out.write_string(
    "Physical counts: \{report.physical_count_count}/\{report.affected_lot_count} affected lots.\n\n",
  )
  out.write_string(
    "Acknowledgements: \{report.acknowledged_shipment_count}/\{report.affected_shipment_count} affected shipments.\n\n",
  )
  out.write_string("| Category | Entity | Outstanding evidence |\n")
  out.write_string("| --- | --- | --- |\n")
  for item in report.items {
    out.write_string(
      "| \{markdown_cell(item.category)} | \{markdown_cell(item.entity_id)} | \{markdown_cell(item.detail)} |\n",
    )
  }
  if report.items.is_empty() {
    out.write_string("| none | — | No item remains in this checklist |\n")
  }
  out.to_string()
}

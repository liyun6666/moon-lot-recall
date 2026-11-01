///|
/// A new analysis at a later cutoff can reveal more processed lots and
/// shipments. Existing rows remain visible in the earlier report.
pub(all) struct ImpactDelta {
  recall_id : String
  previous_as_of : Int64
  current_as_of : Int64
  previous_lot_count : Int32
  current_lot_count : Int32
  previous_shipment_count : Int32
  current_shipment_count : Int32
  new_lots : Array[AffectedLot]
  new_shipments : Array[AffectedShipment]
  newly_shipped_g : Int64
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A cutoff comparison is monotone for one immutable ledger. This function
/// never treats a previously affected shipment as resolved or safe.
pub fn compare_cutoffs(
  ledger : Ledger,
  request : RecallRequest,
  current_as_of : Int64,
) -> Result[ImpactDelta, ValidationReport] {
  if !valid_time(current_as_of) || current_as_of < request.as_of {
    return Err(
      report_from([
        issue(
          "error",
          "invalid-delta-cutoff",
          request.id,
          "new cutoff must be valid and no earlier than previous cutoff",
        ),
      ]),
    )
  }
  let previous = match analyze(ledger, request) {
    Err(validation) => return Err(validation)
    Ok(value) => value
  }
  let current_request = { ..request, as_of: current_as_of, }
  let current = match analyze(ledger, current_request) {
    Err(validation) => return Err(validation)
    Ok(value) => value
  }
  let old_lots : Map[String, Bool] = Map([])
  let old_shipments : Map[String, Bool] = Map([])
  for lot in previous.affected_lots {
    old_lots[lot.lot_id] = true
  }
  for shipment in previous.affected_shipments {
    old_shipments[shipment.shipment_id] = true
  }
  let new_lots : Array[AffectedLot] = []
  let new_shipments : Array[AffectedShipment] = []
  let mut newly_shipped_g = 0L
  for lot in current.affected_lots {
    if !old_lots.contains(lot.lot_id) {
      new_lots.push(lot)
    }
  }
  for shipment in current.affected_shipments {
    if !old_shipments.contains(shipment.shipment_id) {
      new_shipments.push(shipment)
      newly_shipped_g += shipment.quantity_g
    }
  }
  Ok({
    recall_id: request.id,
    previous_as_of: request.as_of,
    current_as_of,
    previous_lot_count: previous.affected_lots.length(),
    current_lot_count: current.affected_lots.length(),
    previous_shipment_count: previous.affected_shipments.length(),
    current_shipment_count: current.affected_shipments.length(),
    new_lots,
    new_shipments,
    newly_shipped_g,
  })
}

///|
pub fn render_delta_markdown(delta : ImpactDelta) -> String {
  let out = StringBuilder()
  out.write_string(
    "# New recall exposure: \{markdown_cell(delta.recall_id)}\n\n",
  )
  out.write_string(
    "Previous cutoff: \{delta.previous_as_of}; current cutoff: \{delta.current_as_of}.\n\n",
  )
  out.write_string(
    "This report lists newly discovered scope only. Previously affected records remain in scope.\n\n",
  )
  out.write_string("## New lots\n\n")
  out.write_string("| Lot | Product | Facility | Evidence path |\n")
  out.write_string("| --- | --- | --- | --- |\n")
  for lot in delta.new_lots {
    out.write_string(
      "| \{markdown_cell(lot.lot_id)} | \{markdown_cell(lot.product)} | \{markdown_cell(lot.facility)} | \{markdown_cell(path_text(lot.path))} |\n",
    )
  }
  out.write_string("\n## New shipments\n\n")
  out.write_string(
    "| Shipment | Consignee | Lot | Quantity (g) | Evidence path |\n",
  )
  out.write_string("| --- | --- | --- | ---: | --- |\n")
  for shipment in delta.new_shipments {
    out.write_string(
      "| \{markdown_cell(shipment.shipment_id)} | \{markdown_cell(shipment.consignee)} | \{markdown_cell(shipment.lot_id)} | \{shipment.quantity_g} | \{markdown_cell(path_text(shipment.path))} |\n",
    )
  }
  out.write_string("\nNewly shipped for review: \{delta.newly_shipped_g} g.\n")
  out.to_string()
}

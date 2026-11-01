///|
/// A communication packet groups all affected shipments for one recipient.
/// It is a draft for human review, never an automatically sent notice.
pub(all) struct ConsigneePacket {
  consignee : String
  shipment_ids : Array[String]
  lot_ids : Array[String]
  references : Array[String]
  total_quantity_g : Int64
  earliest_shipment_at : Int64
  latest_shipment_at : Int64
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ConsigneeReport {
  recall_id : String
  as_of : Int64
  packets : Array[ConsigneePacket]
  shipment_count : Int32
  total_quantity_g : Int64
} derive(Eq, Debug, ToJson, FromJson)

///|
fn has_text(items : Array[String], value : String) -> Bool {
  for item in items {
    if item == value {
      return true
    }
  }
  false
}

///|
/// Produce one packet per consignee in first-shipment order. A repeated lot
/// or invoice is listed once, while the quantity sums every distinct shipment.
pub fn group_consignees(
  ledger : Ledger,
  request : RecallRequest,
) -> Result[ConsigneeReport, ValidationReport] {
  let impact = match analyze(ledger, request) {
    Err(validation) => return Err(validation)
    Ok(value) => value
  }
  let positions : Map[String, Int32] = Map([])
  let packets : Array[ConsigneePacket] = []
  let mut total_quantity_g = 0L
  for shipment in impact.affected_shipments {
    let position = match positions.get(shipment.consignee) {
      Some(index) => index
      None => {
        let index = packets.length()
        positions[shipment.consignee] = index
        packets.push({
          consignee: shipment.consignee,
          shipment_ids: [],
          lot_ids: [],
          references: [],
          total_quantity_g: 0L,
          earliest_shipment_at: shipment.shipped_at,
          latest_shipment_at: shipment.shipped_at,
        })
        index
      }
    }
    let packet = packets[position]
    packet.shipment_ids.push(shipment.shipment_id)
    if !has_text(packet.lot_ids, shipment.lot_id) {
      packet.lot_ids.push(shipment.lot_id)
    }
    if !has_text(packet.references, shipment.reference) {
      packet.references.push(shipment.reference)
    }
    let earliest = if shipment.shipped_at < packet.earliest_shipment_at {
      shipment.shipped_at
    } else {
      packet.earliest_shipment_at
    }
    let latest = if shipment.shipped_at > packet.latest_shipment_at {
      shipment.shipped_at
    } else {
      packet.latest_shipment_at
    }
    packets[position] = {
      ..packet,
      total_quantity_g: packet.total_quantity_g + shipment.quantity_g,
      earliest_shipment_at: earliest,
      latest_shipment_at: latest,
    }
    total_quantity_g += shipment.quantity_g
  }
  Ok({
    recall_id: request.id,
    as_of: request.as_of,
    packets,
    shipment_count: impact.affected_shipments.length(),
    total_quantity_g,
  })
}

///|
pub fn render_consignees_markdown(report : ConsigneeReport) -> String {
  let out = StringBuilder()
  out.write_string(
    "# Consignee review packets: \{markdown_cell(report.recall_id)}\n\n",
  )
  out.write_string("Cutoff (Unix seconds): \{report.as_of}\n\n")
  out.write_string(
    "One packet per consignee. Verify identity and contact details before sending any notice.\n\n",
  )
  out.write_string(
    "| Consignee | Shipments | Lots | References | Quantity (g) | First dispatch | Last dispatch |\n",
  )
  out.write_string("| --- | --- | --- | --- | ---: | ---: | ---: |\n")
  for packet in report.packets {
    out.write_string(
      "| \{markdown_cell(packet.consignee)} | \{markdown_cell(packet.shipment_ids.join(", "))} | \{markdown_cell(packet.lot_ids.join(", "))} | \{markdown_cell(packet.references.join(", "))} | \{packet.total_quantity_g} | \{packet.earliest_shipment_at} | \{packet.latest_shipment_at} |\n",
    )
  }
  out.write_string(
    "\n\{report.packets.length()} consignees, \{report.shipment_count} shipments, \{report.total_quantity_g} g for review.\n",
  )
  out.to_string()
}

///|
/// A quoted CSV can be joined to the operator's own contact directory.
pub fn render_consignees_csv(report : ConsigneeReport) -> String {
  let out = StringBuilder()
  out.write_string(
    "recall_id,consignee,shipment_ids,lot_ids,references,total_quantity_g,earliest_shipment_at,latest_shipment_at\n",
  )
  for packet in report.packets {
    out.write_string(
      "\{csv_cell(report.recall_id)},\{csv_cell(packet.consignee)},\{csv_cell(packet.shipment_ids.join(";"))},\{csv_cell(packet.lot_ids.join(";"))},\{csv_cell(packet.references.join(";"))},\{packet.total_quantity_g},\{packet.earliest_shipment_at},\{packet.latest_shipment_at}\n",
    )
  }
  out.to_string()
}

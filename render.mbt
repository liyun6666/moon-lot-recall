///|
fn markdown_cell(text : String) -> String {
  text.replace_all(old="|", new="\\|").replace_all(old="\n", new=" ").replace_all(old="\r", new=" ")
}

///|
fn csv_cell(text : String) -> String {
  "\"\{text.replace_all(old="\"", new="\"\"")}\""
}

///|
fn path_text(path : Array[ExposureStep]) -> String {
  if path.is_empty() {
    return "seed lot"
  }
  let parts : Array[String] = []
  parts.push(path[0].from_lot)
  for step in path {
    parts.push("\{step.transformation_id} -> \{step.to_lot}")
  }
  parts.join(" -> ")
}

///|
/// A human-readable review report. The conservative language is deliberate:
/// graph reachability establishes possible exposure, not contamination.
pub fn render_markdown(report : RecallReport) -> String {
  let out = StringBuilder()
  out.write_string("# Recall impact: \{markdown_cell(report.recall_id)}\n\n")
  out.write_string("Cutoff (Unix seconds): \{report.as_of}\n\n")
  out.write_string("**Interpretation:** These lots and shipments may be affected. A path records processing links, not laboratory proof of contamination. Quantities are maximum amounts requiring review.\n\n")
  out.write_string("## Lots requiring review\n\n")
  out.write_string("| Lot | Product | Facility | Quantity (g) | Class | Evidence path |\n")
  out.write_string("| --- | --- | --- | ---: | --- | --- |\n")
  for lot in report.affected_lots {
    out.write_string("| \{markdown_cell(lot.lot_id)} | \{markdown_cell(lot.product)} | \{markdown_cell(lot.facility)} | \{lot.quantity_g} | \{lot.classification} | \{markdown_cell(path_text(lot.path))} |\n")
  }
  if report.affected_lots.is_empty() {
    out.write_string("| — | — | — | 0 | — | — |\n")
  }
  out.write_string("\n## Shipments requiring review\n\n")
  out.write_string("| Shipment | Lot | Consignee | Quantity (g) | Reference | Evidence path |\n")
  out.write_string("| --- | --- | --- | ---: | --- | --- |\n")
  for shipment in report.affected_shipments {
    out.write_string("| \{markdown_cell(shipment.shipment_id)} | \{markdown_cell(shipment.lot_id)} | \{markdown_cell(shipment.consignee)} | \{shipment.quantity_g} | \{markdown_cell(shipment.reference)} | \{markdown_cell(path_text(shipment.path))} |\n")
  }
  if report.affected_shipments.is_empty() {
    out.write_string("| — | — | — | 0 | — | — |\n")
  }
  out.to_string()
}

///|
pub fn render_shipments_csv(report : RecallReport) -> String {
  let out = StringBuilder()
  out.write_string("recall_id,shipment_id,lot_id,consignee,quantity_g,shipped_at,reference,evidence_path\n")
  for shipment in report.affected_shipments {
    out.write_string("\{csv_cell(report.recall_id)},\{csv_cell(shipment.shipment_id)},\{csv_cell(shipment.lot_id)},\{csv_cell(shipment.consignee)},\{shipment.quantity_g},\{shipment.shipped_at},\{csv_cell(shipment.reference)},\{csv_cell(path_text(shipment.path))}\n")
  }
  out.to_string()
}

///|
pub fn render_validation(report : ValidationReport) -> String {
  let out = StringBuilder()
  out.write_string(if report.valid { "VALID\n" } else { "INVALID\n" })
  for diagnostic in report.diagnostics {
    out.write_string("\{diagnostic.severity}:\{diagnostic.code}:\{diagnostic.entity}: \{diagnostic.message}\n")
  }
  out.to_string()
}

///|
pub fn render_actions_markdown(plan : ActionPlan) -> String {
  let out = StringBuilder()
  out.write_string("# Review actions: \{markdown_cell(plan.recall_id)}\n\n")
  out.write_string("Cutoff (Unix seconds): \{plan.as_of}\n\n")
  out.write_string("Physical stock and legal recall scope require human confirmation. This list does not send notices or authorize disposal.\n\n")
  out.write_string("## Check and hold on-hand stock\n\n")
  out.write_string("| Lot | Facility | Product | Estimated on hand (g) | Class |\n")
  out.write_string("| --- | --- | --- | ---: | --- |\n")
  for hold in plan.holds {
    out.write_string("| \{markdown_cell(hold.lot_id)} | \{markdown_cell(hold.facility)} | \{markdown_cell(hold.product)} | \{hold.estimated_on_hand_g} | \{hold.classification} |\n")
  }
  out.write_string("\nEstimated hold: \{plan.estimated_hold_g} g\n\n")
  out.write_string("## Review shipment contacts\n\n")
  out.write_string("| Shipment | Consignee | Lot | Quantity (g) | Reference |\n")
  out.write_string("| --- | --- | --- | ---: | --- |\n")
  for contact in plan.contacts {
    out.write_string("| \{markdown_cell(contact.shipment_id)} | \{markdown_cell(contact.consignee)} | \{markdown_cell(contact.lot_id)} | \{contact.quantity_g} | \{markdown_cell(contact.reference)} |\n")
  }
  out.write_string("\nShipped for review: \{plan.shipped_for_review_g} g\n")
  out.to_string()
}

///|
pub fn render_upstream_markdown(report : UpstreamReport) -> String {
  let out = StringBuilder()
  out.write_string("# Upstream trace: \{markdown_cell(report.target_lot)}\n\n")
  out.write_string("Cutoff (Unix seconds): \{report.as_of}\n\n")
  out.write_string("| Lot | Product | Facility | Source lot | Path to target |\n")
  out.write_string("| --- | --- | --- | --- | --- |\n")
  for lot in report.lots {
    out.write_string("| \{markdown_cell(lot.lot_id)} | \{markdown_cell(lot.product)} | \{markdown_cell(lot.facility)} | \{if lot.is_source { "yes" } else { "no" }} | \{markdown_cell(path_text(lot.path_to_target))} |\n")
  }
  out.to_string()
}

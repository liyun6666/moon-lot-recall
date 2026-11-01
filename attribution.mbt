///|
pub(all) struct SourcePath {
  seed_lot : String
  path : Array[ExposureStep]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AttributionRow {
  lot_id : String
  product : String
  sources : Array[SourcePath]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ShipmentAttribution {
  shipment_id : String
  lot_id : String
  consignee : String
  sources : Array[SourcePath]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct AttributionReport {
  recall_id : String
  as_of : Int64
  lots : Array[AttributionRow]
  shipments : Array[ShipmentAttribution]
} derive(Debug, ToJson, FromJson)

///|
fn single_seed_paths(
  edges : Map[String, Array[ExposureStep]],
  seed : String,
) -> Map[String, Array[ExposureStep]] {
  let paths : Map[String, Array[ExposureStep]] = Map([])
  let queue : Array[String] = [seed]
  paths[seed] = []
  let mut head = 0
  while head < queue.length() {
    let current = queue[head]
    head += 1
    let base = paths.get(current).unwrap_or([])
    for edge in edges.get(current).unwrap_or([]) {
      if !paths.contains(edge.to_lot) {
        let path = base.copy()
        path.push(edge)
        paths[edge.to_lot] = path
        queue.push(edge.to_lot)
      }
    }
  }
  paths
}

///|
/// Show which suspect input lots can reach each downstream lot. Each seed
/// gets one shortest processing chain; an output may have several seed sources.
/// This prevents a single representative path from hiding another suspected
/// ingredient in the same product.
pub fn attribute_sources(
  ledger : Ledger,
  request : RecallRequest,
) -> Result[AttributionReport, ValidationReport] {
  let ledger_check = validate_ledger(ledger)
  let request_check = validate_request(ledger, request)
  let findings = ledger_check.diagnostics.copy()
  for diagnostic in request_check.diagnostics {
    findings.push(diagnostic)
  }
  if !ledger_check.valid || !request_check.valid {
    return Err(report_from(findings))
  }
  let edges = exposure_edges(ledger, request.as_of)
  let by_lot : Map[String, Array[SourcePath]] = Map([])
  for seed in request.seed_lots {
    let paths = single_seed_paths(edges, seed)
    for lot_id, path in paths {
      let sources = by_lot.get(lot_id).unwrap_or([])
      sources.push({ seed_lot: seed, path, })
      by_lot[lot_id] = sources
    }
  }
  let lots : Array[AttributionRow] = []
  for lot in ledger.lots {
    match by_lot.get(lot.id) {
      None => ()
      Some(sources) =>
        lots.push({ lot_id: lot.id, product: lot.product, sources, })
    }
  }
  let shipments : Array[ShipmentAttribution] = []
  for shipment in ledger.shipments {
    if shipment.shipped_at <= request.as_of {
      match by_lot.get(shipment.lot_id) {
        None => ()
        Some(sources) =>
          shipments.push({
            shipment_id: shipment.id,
            lot_id: shipment.lot_id,
            consignee: shipment.consignee,
            sources: sources.copy(),
          })
      }
    }
  }
  Ok({ recall_id: request.id, as_of: request.as_of, lots, shipments, })
}

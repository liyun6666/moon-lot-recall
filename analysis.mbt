///|
fn exposure_edges(
  ledger : Ledger,
  as_of : Int64,
) -> Map[String, Array[ExposureStep]] {
  let edges : Map[String, Array[ExposureStep]] = Map([])
  for transformation in ledger.transformations {
    if transformation.occurred_at > as_of {
      continue
    }
    for input in transformation.inputs {
      let adjacent = edges.get(input.lot_id).unwrap_or([])
      for output in transformation.outputs {
        adjacent.push({
          from_lot: input.lot_id,
          transformation_id: transformation.id,
          to_lot: output.lot_id,
          occurred_at: transformation.occurred_at,
        })
      }
      edges[input.lot_id] = adjacent
    }
  }
  edges
}

///|
fn path_to(
  lot_id : String,
  parents : Map[String, ExposureStep],
) -> Array[ExposureStep] {
  let backwards : Array[ExposureStep] = []
  let mut current = lot_id
  for _ in 0..<100001 {
    match parents.get(current) {
      None => break
      Some(step) => {
        backwards.push(step)
        current = step.from_lot
      }
    }
  }
  let path : Array[ExposureStep] = []
  for i = backwards.length() - 1; i >= 0; i = i - 1 {
    path.push(backwards[i])
  }
  path
}

///|
fn walk_exposure(
  ledger : Ledger,
  request : RecallRequest,
) -> (Map[String, Bool], Map[String, ExposureStep]) {
  let edges = exposure_edges(ledger, request.as_of)
  let visited : Map[String, Bool] = Map([])
  let parents : Map[String, ExposureStep] = Map([])
  let queue : Array[String] = []
  for seed in request.seed_lots {
    visited[seed] = true
    queue.push(seed)
  }
  let mut head = 0
  while head < queue.length() {
    let from = queue[head]
    head += 1
    for edge in edges.get(from).unwrap_or([]) {
      if !visited.contains(edge.to_lot) {
        visited[edge.to_lot] = true
        parents[edge.to_lot] = edge
        queue.push(edge.to_lot)
      }
    }
  }
  (visited, parents)
}

///|
/// Trace possible downstream exposure and list shipments at or before the
/// cutoff. Every affected shipment has a reproducible transformation path.
/// The algorithm deliberately does not estimate which grams are contaminated
/// in a mixed output. `quantity_g` is the upper bound requiring review.
pub fn analyze(
  ledger : Ledger,
  request : RecallRequest,
) -> Result[RecallReport, ValidationReport] {
  let ledger_check = validate_ledger(ledger)
  let request_check = validate_request(ledger, request)
  let all_issues = ledger_check.diagnostics.copy()
  for diagnostic in request_check.diagnostics {
    all_issues.push(diagnostic)
  }
  if !ledger_check.valid || !request_check.valid {
    return Err({ valid: false, diagnostics: all_issues, })
  }
  let (visited, parents) = walk_exposure(ledger, request)
  let seeds : Map[String, Bool] = Map([])
  for seed in request.seed_lots {
    seeds[seed] = true
  }
  let affected_lots : Array[AffectedLot] = []
  for lot in ledger.lots {
    if visited.contains(lot.id) {
      affected_lots.push({
        lot_id: lot.id,
        product: lot.product,
        facility: lot.facility,
        quantity_g: lot.quantity_g,
        classification: if seeds.contains(lot.id) {
          "seed"
        } else {
          "potential"
        },
        path: path_to(lot.id, parents),
      })
    }
  }
  // Preserve ledger order so report rows can be compared to source records.
  let affected_shipments : Array[AffectedShipment] = []
  for shipment in ledger.shipments {
    if shipment.shipped_at <= request.as_of && visited.contains(shipment.lot_id) {
      affected_shipments.push({
        shipment_id: shipment.id,
        lot_id: shipment.lot_id,
        consignee: shipment.consignee,
        quantity_g: shipment.quantity_g,
        shipped_at: shipment.shipped_at,
        reference: shipment.reference,
        path: path_to(shipment.lot_id, parents),
      })
    }
  }
  // Shipment order likewise follows the submitted evidence.
  Ok({
    recall_id: request.id,
    as_of: request.as_of,
    affected_lots,
    affected_shipments,
    diagnostics: all_issues,
  })
}

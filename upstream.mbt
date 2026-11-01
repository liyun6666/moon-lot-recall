///|
pub(all) struct UpstreamLot {
  lot_id : String
  product : String
  facility : String
  quantity_g : Int64
  is_source : Bool
  path_to_target : Array[ExposureStep]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct UpstreamReport {
  target_lot : String
  as_of : Int64
  lots : Array[UpstreamLot]
} derive(Debug, ToJson, FromJson)

///|
fn incoming_edges(
  ledger : Ledger,
  as_of : Int64,
) -> Map[String, Array[ExposureStep]] {
  let incoming : Map[String, Array[ExposureStep]] = Map([])
  for transformation in ledger.transformations {
    if transformation.occurred_at > as_of {
      continue
    }
    for output in transformation.outputs {
      let steps = incoming.get(output.lot_id).unwrap_or([])
      for input in transformation.inputs {
        steps.push({
          from_lot: input.lot_id,
          transformation_id: transformation.id,
          to_lot: output.lot_id,
          occurred_at: transformation.occurred_at,
        })
      }
      incoming[output.lot_id] = steps
    }
  }
  incoming
}

///|
fn upstream_path(
  start : String,
  next_step : Map[String, ExposureStep],
) -> Array[ExposureStep] {
  let path : Array[ExposureStep] = []
  let mut current = start
  for _ in 0..<100001 {
    match next_step.get(current) {
      None => break
      Some(step) => {
        path.push(step)
        current = step.to_lot
      }
    }
  }
  path
}

///|
/// Find all ingredient lots that can contribute to a finished lot. This is
/// useful when investigators start from a suspect finished product and need
/// to identify upstream supplier batches. Paths show one shortest processing
/// chain; the `lots` array includes every reached ancestor.
pub fn trace_upstream(
  ledger : Ledger,
  target_lot : String,
  as_of : Int64,
) -> Result[UpstreamReport, ValidationReport] {
  let check = validate_ledger(ledger)
  if !check.valid {
    return Err(check)
  }
  let mut target : Lot? = None
  for lot in ledger.lots {
    if lot.id == target_lot {
      target = Some(lot)
      break
    }
  }
  match target {
    None =>
      return Err(
        report_from([
          issue(
            "error", "unknown-target", target_lot, "target lot does not exist",
          ),
        ]),
      )
    Some(lot) =>
      if !valid_time(as_of) || lot.produced_at > as_of {
        return Err(
          report_from([
            issue(
              "error", "invalid-target-cutoff", target_lot, "target lot does not exist at cutoff",
            ),
          ]),
        )
      }
  }
  let incoming = incoming_edges(ledger, as_of)
  let visited : Map[String, Bool] = Map([])
  let next_step : Map[String, ExposureStep] = Map([])
  let queue : Array[String] = [target_lot]
  visited[target_lot] = true
  let mut head = 0
  while head < queue.length() {
    let current = queue[head]
    head += 1
    for edge in incoming.get(current).unwrap_or([]) {
      if !visited.contains(edge.from_lot) {
        visited[edge.from_lot] = true
        next_step[edge.from_lot] = edge
        queue.push(edge.from_lot)
      }
    }
  }
  let upstream : Array[UpstreamLot] = []
  for lot in ledger.lots {
    if visited.contains(lot.id) {
      upstream.push({
        lot_id: lot.id,
        product: lot.product,
        facility: lot.facility,
        quantity_g: lot.quantity_g,
        is_source: incoming.get(lot.id).unwrap_or([]).is_empty(),
        path_to_target: upstream_path(lot.id, next_step),
      })
    }
  }
  Ok({ target_lot, as_of, lots: upstream, })
}

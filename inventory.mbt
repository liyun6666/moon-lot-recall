///|
pub(all) struct InventoryRow {
  lot_id : String
  product : String
  facility : String
  produced_g : Int64
  processed_g : Int64
  shipped_g : Int64
  on_hand_g : Int64
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct InventoryReport {
  as_of : Int64
  rows : Array[InventoryRow]
} derive(Debug, ToJson, FromJson)

///|
fn used_by_processing(ledger : Ledger, as_of : Int64) -> Map[String, Int64] {
  let consumed : Map[String, Int64] = Map([])
  for event in ledger.transformations {
    if event.occurred_at <= as_of {
      for portion in event.inputs {
        consumed[portion.lot_id] = consumed.get(portion.lot_id).unwrap_or(0L) + portion.quantity_g
      }
    }
  }
  consumed
}

///|
fn used_by_shipments(ledger : Ledger, as_of : Int64) -> Map[String, Int64] {
  let shipped : Map[String, Int64] = Map([])
  for shipment in ledger.shipments {
    if shipment.shipped_at <= as_of {
      shipped[shipment.lot_id] = shipped.get(shipment.lot_id).unwrap_or(0L) + shipment.quantity_g
    }
  }
  shipped
}

///|
/// Reconstruct in-scope on-hand stock from immutable lot and event records.
/// This is a ledger calculation, not a sensor or warehouse count. Differences
/// from physical stock must be reconciled by the operator before action.
pub fn inventory_at(
  ledger : Ledger,
  as_of : Int64,
) -> Result[InventoryReport, ValidationReport] {
  let validation = validate_ledger(ledger)
  if !validation.valid {
    return Err(validation)
  }
  if !valid_time(as_of) {
    return Err(report_from([issue("error", "invalid-cutoff", "inventory", "as_of must be a valid Unix second")]))
  }
  let consumed = used_by_processing(ledger, as_of)
  let shipped = used_by_shipments(ledger, as_of)
  let rows : Array[InventoryRow] = []
  for lot in ledger.lots {
    if lot.produced_at <= as_of {
      let processed_g = consumed.get(lot.id).unwrap_or(0L)
      let shipped_g = shipped.get(lot.id).unwrap_or(0L)
      rows.push({
        lot_id: lot.id,
        product: lot.product,
        facility: lot.facility,
        produced_g: lot.quantity_g,
        processed_g,
        shipped_g,
        on_hand_g: lot.quantity_g - processed_g - shipped_g,
      })
    }
  }
  Ok({ as_of, rows, })
}

///|
pub fn InventoryReport::for_lot(self : InventoryReport, id : String) -> InventoryRow? {
  for row in self.rows {
    if row.lot_id == id {
      return Some(row)
    }
  }
  None
}

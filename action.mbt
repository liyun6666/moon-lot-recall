///|
pub(all) struct HoldAction {
  lot_id : String
  facility : String
  product : String
  estimated_on_hand_g : Int64
  classification : String
  path : Array[ExposureStep]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ContactAction {
  shipment_id : String
  consignee : String
  reference : String
  quantity_g : Int64
  lot_id : String
  path : Array[ExposureStep]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ActionPlan {
  recall_id : String
  as_of : Int64
  holds : Array[HoldAction]
  contacts : Array[ContactAction]
  estimated_hold_g : Int64
  shipped_for_review_g : Int64
} derive(Debug, ToJson, FromJson)

///|
/// Generate review tasks only after the ledger and recall request pass all
/// checks. `holds` are estimated from recorded events; a person must reconcile
/// actual stock and determine legal recall actions.
pub fn plan_actions(
  ledger : Ledger,
  request : RecallRequest,
) -> Result[ActionPlan, ValidationReport] {
  let impact = match analyze(ledger, request) {
    Err(report) => return Err(report)
    Ok(report) => report
  }
  let inventory = match inventory_at(ledger, request.as_of) {
    Err(report) => return Err(report)
    Ok(report) => report
  }
  let holds : Array[HoldAction] = []
  let contacts : Array[ContactAction] = []
  let mut estimated_hold_g = 0L
  let mut shipped_for_review_g = 0L
  for affected in impact.affected_lots {
    match inventory.for_lot(affected.lot_id) {
      Some(row) if row.on_hand_g > 0L => {
        holds.push({
          lot_id: affected.lot_id,
          facility: affected.facility,
          product: affected.product,
          estimated_on_hand_g: row.on_hand_g,
          classification: affected.classification,
          path: affected.path,
        })
        estimated_hold_g += row.on_hand_g
      }
      _ => ()
    }
  }
  for shipment in impact.affected_shipments {
    contacts.push({
      shipment_id: shipment.shipment_id,
      consignee: shipment.consignee,
      reference: shipment.reference,
      quantity_g: shipment.quantity_g,
      lot_id: shipment.lot_id,
      path: shipment.path,
    })
    shipped_for_review_g += shipment.quantity_g
  }
  Ok({
    recall_id: request.id,
    as_of: request.as_of,
    holds,
    contacts,
    estimated_hold_g,
    shipped_for_review_g,
  })
}

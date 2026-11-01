///|
/// Error and warning codes are stable for CI and downstream applications.
pub(all) struct Diagnostic {
  severity : String
  code : String
  entity : String
  message : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ValidationReport {
  valid : Bool
  diagnostics : Array[Diagnostic]
} derive(Eq, Debug, ToJson, FromJson)

///|
/// One processing step from an affected input to an affected output.
pub(all) struct ExposureStep {
  from_lot : String
  transformation_id : String
  to_lot : String
  occurred_at : Int64
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Classification is `seed` or `potential`. Neither proves contamination.
pub(all) struct AffectedLot {
  lot_id : String
  product : String
  facility : String
  quantity_g : Int64
  classification : String
  path : Array[ExposureStep]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct AffectedShipment {
  shipment_id : String
  lot_id : String
  consignee : String
  quantity_g : Int64
  shipped_at : Int64
  reference : String
  path : Array[ExposureStep]
} derive(Eq, Debug, ToJson, FromJson)

///|
/// This report is a conservative impact analysis, not a laboratory finding.
pub(all) struct RecallReport {
  recall_id : String
  as_of : Int64
  affected_lots : Array[AffectedLot]
  affected_shipments : Array[AffectedShipment]
  diagnostics : Array[Diagnostic]
} derive(Eq, Debug, ToJson, FromJson)

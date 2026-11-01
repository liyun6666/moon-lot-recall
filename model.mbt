///|
/// A lot represents one physical stock batch at one facility. Quantities use
/// integer grams, avoiding rounding during the recall traversal.
pub(all) struct Lot {
  id : String
  product : String
  facility : String
  quantity_g : Int64
  produced_at : Int64
} derive(Eq, Debug, ToJson, FromJson)

///|
/// One quantity of a lot consumed or produced in a processing event.
pub(all) struct Portion {
  lot_id : String
  quantity_g : Int64
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A transformation links ingredient lots to output lots. Every output is
/// conservatively considered exposed when any input lot is recalled.
pub(all) struct Transformation {
  id : String
  facility : String
  occurred_at : Int64
  inputs : Array[Portion]
  outputs : Array[Portion]
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A shipment sends some of a finished lot to an external consignee.
pub(all) struct Shipment {
  id : String
  lot_id : String
  quantity_g : Int64
  consignee : String
  shipped_at : Int64
  reference : String
} derive(Eq, Debug, ToJson, FromJson)

///|
/// The document contains only operational facts. Recall decisions live in a
/// separate request so the same ledger can be queried repeatedly.
pub(all) struct Ledger {
  schema_version : Int
  lots : Array[Lot]
  transformations : Array[Transformation]
  shipments : Array[Shipment]
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A recall request starts from known suspect lots, at an explicit cutoff.
pub(all) struct RecallRequest {
  id : String
  reason : String
  seed_lots : Array[String]
  as_of : Int64
} derive(Eq, Debug, ToJson, FromJson)

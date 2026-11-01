///|
fn issue(
  severity : String,
  code : String,
  entity : String,
  message : String,
) -> Diagnostic {
  { severity, code, entity, message, }
}

///|
fn valid_id(id : String) -> Bool {
  if id.is_empty() || id.length() > 128 {
    return false
  }
  for c in id {
    if !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '_' ||
      c == '.' ||
      c == ':') {
      return false
    }
  }
  true
}

///|
fn valid_label(label : String) -> Bool {
  !label.trim().is_empty() &&
  label.length() <= 256 &&
  !label.contains("\n") &&
  !label.contains("\r")
}

///|
fn valid_quantity(quantity : Int64) -> Bool {
  quantity > 0L && quantity <= 1000000000000L
}

///|
fn valid_time(instant : Int64) -> Bool {
  instant >= 0L && instant <= 253402300799L
}

///|
fn report_from(diagnostics : Array[Diagnostic]) -> ValidationReport {
  let mut valid = true
  for diagnostic in diagnostics {
    if diagnostic.severity == "error" {
      valid = false
    }
  }
  { valid, diagnostics, }
}

///|
/// Validate structure, references, mass accounting, and chronology before
/// interpreting any recall path. A rejected ledger never produces an impact
/// report, so malformed evidence cannot look like a clean result.
pub fn validate_ledger(ledger : Ledger) -> ValidationReport {
  let findings : Array[Diagnostic] = []
  if ledger.schema_version != 1 {
    findings.push(
      issue(
        "error", "unsupported-version", "ledger", "schema_version must be 1",
      ),
    )
  }
  if ledger.lots.length() > 100000 ||
    ledger.transformations.length() > 100000 ||
    ledger.shipments.length() > 100000 {
    findings.push(
      issue(
        "error", "record-limit", "ledger", "each record array is limited to 100000 entries",
      ),
    )
  }
  let lots : Map[String, Lot] = Map([])
  for lot in ledger.lots {
    if !valid_id(lot.id) {
      findings.push(
        issue(
          "error",
          "invalid-lot-id",
          lot.id,
          "lot id must be 1..128 ASCII letters, digits, '-', '_' , '.', or ':'",
        ),
      )
    }
    if lots.contains(lot.id) {
      findings.push(
        issue("error", "duplicate-lot", lot.id, "lot id is repeated"),
      )
    } else {
      lots[lot.id] = lot
    }
    if !valid_label(lot.product) {
      findings.push(
        issue(
          "error",
          "invalid-product",
          lot.id,
          "product must be a nonempty single-line label",
        ),
      )
    }
    if !valid_label(lot.facility) {
      findings.push(
        issue(
          "error",
          "invalid-facility",
          lot.id,
          "facility must be a nonempty single-line label",
        ),
      )
    }
    if !valid_quantity(lot.quantity_g) {
      findings.push(
        issue(
          "error",
          "invalid-lot-quantity",
          lot.id,
          "quantity_g must be 1..1e12 grams",
        ),
      )
    }
    if !valid_time(lot.produced_at) {
      findings.push(
        issue(
          "error",
          "invalid-produced-at",
          lot.id,
          "produced_at must be a valid nonnegative Unix second",
        ),
      )
    }
  }
  let transformations : Map[String, Bool] = Map([])
  let output_owner : Map[String, String] = Map([])
  let consumed : Map[String, Int64] = Map([])
  for transformation in ledger.transformations {
    if !valid_id(transformation.id) {
      findings.push(
        issue(
          "error",
          "invalid-transformation-id",
          transformation.id,
          "transformation id has an invalid shape",
        ),
      )
    }
    if transformations.contains(transformation.id) {
      findings.push(
        issue(
          "error",
          "duplicate-transformation",
          transformation.id,
          "transformation id is repeated",
        ),
      )
    } else {
      transformations[transformation.id] = true
    }
    if !valid_label(transformation.facility) {
      findings.push(
        issue(
          "error",
          "invalid-facility",
          transformation.id,
          "facility must be a nonempty single-line label",
        ),
      )
    }
    if !valid_time(transformation.occurred_at) {
      findings.push(
        issue(
          "error",
          "invalid-transformation-time",
          transformation.id,
          "occurred_at must be a valid Unix second",
        ),
      )
    }
    if transformation.inputs.is_empty() {
      findings.push(
        issue(
          "error",
          "empty-inputs",
          transformation.id,
          "transformation must consume at least one lot",
        ),
      )
    }
    if transformation.outputs.is_empty() {
      findings.push(
        issue(
          "error",
          "empty-outputs",
          transformation.id,
          "transformation must produce at least one lot",
        ),
      )
    }
    let input_ids : Map[String, Bool] = Map([])
    let output_ids : Map[String, Bool] = Map([])
    let mut input_g = 0L
    let mut output_g = 0L
    for input in transformation.inputs {
      if input_ids.contains(input.lot_id) {
        findings.push(
          issue(
            "error",
            "duplicate-input",
            transformation.id,
            "same input lot appears twice",
          ),
        )
      }
      input_ids[input.lot_id] = true
      if !valid_quantity(input.quantity_g) {
        findings.push(
          issue(
            "error",
            "invalid-input-quantity",
            transformation.id,
            "input quantity_g must be positive and bounded",
          ),
        )
      } else {
        input_g += input.quantity_g
        consumed[input.lot_id] = consumed.get(input.lot_id).unwrap_or(0L) +
          input.quantity_g
      }
      match lots.get(input.lot_id) {
        None =>
          findings.push(
            issue(
              "error",
              "unknown-input-lot",
              transformation.id,
              "input lot does not exist: \{input.lot_id}",
            ),
          )
        Some(lot) => {
          if lot.facility != transformation.facility {
            findings.push(
              issue(
                "error",
                "input-facility-mismatch",
                transformation.id,
                "input lot \{lot.id} belongs to another facility",
              ),
            )
          }
          if lot.produced_at >= transformation.occurred_at {
            findings.push(
              issue(
                "error",
                "input-not-yet-produced",
                transformation.id,
                "input lot \{lot.id} must exist before transformation",
              ),
            )
          }
        }
      }
    }
    for output in transformation.outputs {
      if output_ids.contains(output.lot_id) {
        findings.push(
          issue(
            "error",
            "duplicate-output",
            transformation.id,
            "same output lot appears twice",
          ),
        )
      }
      output_ids[output.lot_id] = true
      if input_ids.contains(output.lot_id) {
        findings.push(
          issue(
            "error",
            "self-output",
            transformation.id,
            "an input lot cannot also be an output lot",
          ),
        )
      }
      if output_owner.contains(output.lot_id) {
        findings.push(
          issue(
            "error",
            "multiple-producers",
            output.lot_id,
            "output lot has more than one producer",
          ),
        )
      } else {
        output_owner[output.lot_id] = transformation.id
      }
      if !valid_quantity(output.quantity_g) {
        findings.push(
          issue(
            "error",
            "invalid-output-quantity",
            transformation.id,
            "output quantity_g must be positive and bounded",
          ),
        )
      } else {
        output_g += output.quantity_g
      }
      match lots.get(output.lot_id) {
        None =>
          findings.push(
            issue(
              "error",
              "unknown-output-lot",
              transformation.id,
              "output lot does not exist: \{output.lot_id}",
            ),
          )
        Some(lot) => {
          if lot.facility != transformation.facility {
            findings.push(
              issue(
                "error",
                "output-facility-mismatch",
                transformation.id,
                "output lot \{lot.id} belongs to another facility",
              ),
            )
          }
          if lot.produced_at != transformation.occurred_at {
            findings.push(
              issue(
                "error",
                "output-time-mismatch",
                transformation.id,
                "output lot \{lot.id} must carry the transformation timestamp",
              ),
            )
          }
          if lot.quantity_g != output.quantity_g {
            findings.push(
              issue(
                "error",
                "output-quantity-mismatch",
                transformation.id,
                "output portion must equal declared lot quantity for \{lot.id}",
              ),
            )
          }
        }
      }
    }
    if input_g > 0L && output_g > input_g {
      findings.push(
        issue(
          "error",
          "mass-created",
          transformation.id,
          "output grams exceed input grams; include all material inputs",
        ),
      )
    }
  }
  let shipment_ids : Map[String, Bool] = Map([])
  let shipped : Map[String, Int64] = Map([])
  for shipment in ledger.shipments {
    if !valid_id(shipment.id) {
      findings.push(
        issue(
          "error",
          "invalid-shipment-id",
          shipment.id,
          "shipment id has an invalid shape",
        ),
      )
    }
    if shipment_ids.contains(shipment.id) {
      findings.push(
        issue(
          "error",
          "duplicate-shipment",
          shipment.id,
          "shipment id is repeated",
        ),
      )
    } else {
      shipment_ids[shipment.id] = true
    }
    if !valid_label(shipment.consignee) {
      findings.push(
        issue(
          "error",
          "invalid-consignee",
          shipment.id,
          "consignee must be a nonempty single-line label",
        ),
      )
    }
    if !valid_label(shipment.reference) {
      findings.push(
        issue(
          "error",
          "invalid-reference",
          shipment.id,
          "reference must be a nonempty single-line label",
        ),
      )
    }
    if !valid_time(shipment.shipped_at) {
      findings.push(
        issue(
          "error",
          "invalid-shipped-at",
          shipment.id,
          "shipped_at must be a valid Unix second",
        ),
      )
    }
    if !valid_quantity(shipment.quantity_g) {
      findings.push(
        issue(
          "error",
          "invalid-shipment-quantity",
          shipment.id,
          "shipment quantity_g must be positive and bounded",
        ),
      )
    } else {
      shipped[shipment.lot_id] = shipped.get(shipment.lot_id).unwrap_or(0L) +
        shipment.quantity_g
    }
    match lots.get(shipment.lot_id) {
      None =>
        findings.push(
          issue(
            "error",
            "unknown-shipment-lot",
            shipment.id,
            "shipped lot does not exist: \{shipment.lot_id}",
          ),
        )
      Some(lot) =>
        if shipment.shipped_at < lot.produced_at {
          findings.push(
            issue(
              "error",
              "shipment-before-production",
              shipment.id,
              "shipment predates lot production",
            ),
          )
        }
    }
  }
  for lot in ledger.lots {
    let used_g = consumed.get(lot.id).unwrap_or(0L) +
      shipped.get(lot.id).unwrap_or(0L)
    if used_g > lot.quantity_g {
      findings.push(
        issue(
          "error",
          "overallocated-lot",
          lot.id,
          "processing plus shipments exceed declared lot quantity",
        ),
      )
    }
  }
  report_from(findings)
}

///|
/// Request checks include existence and cutoff consistency. The ledger is
/// independently validated by `analyze` before this function is used.
pub fn validate_request(
  ledger : Ledger,
  request : RecallRequest,
) -> ValidationReport {
  let findings : Array[Diagnostic] = []
  if !valid_id(request.id) {
    findings.push(
      issue(
        "error",
        "invalid-recall-id",
        request.id,
        "recall id has an invalid shape",
      ),
    )
  }
  if !valid_label(request.reason) {
    findings.push(
      issue(
        "error",
        "invalid-reason",
        request.id,
        "reason must be a nonempty single-line label",
      ),
    )
  }
  if !valid_time(request.as_of) {
    findings.push(
      issue(
        "error",
        "invalid-cutoff",
        request.id,
        "as_of must be a valid Unix second",
      ),
    )
  }
  if request.seed_lots.is_empty() {
    findings.push(
      issue(
        "error",
        "empty-seeds",
        request.id,
        "at least one suspect lot is required",
      ),
    )
  }
  if request.seed_lots.length() > 128 {
    findings.push(
      issue(
        "error",
        "too-many-seeds",
        request.id,
        "a recall request is limited to 128 suspect lots",
      ),
    )
  }
  let lots : Map[String, Lot] = Map([])
  for lot in ledger.lots {
    lots[lot.id] = lot
  }
  let seen : Map[String, Bool] = Map([])
  for id in request.seed_lots {
    if seen.contains(id) {
      findings.push(
        issue("error", "duplicate-seed", id, "seed lot is repeated"),
      )
    }
    seen[id] = true
    match lots.get(id) {
      None =>
        findings.push(
          issue("error", "unknown-seed", id, "seed lot does not exist"),
        )
      Some(lot) =>
        if lot.produced_at > request.as_of {
          findings.push(
            issue(
              "error", "future-seed", id, "seed lot is newer than the cutoff",
            ),
          )
        }
    }
  }
  report_from(findings)
}

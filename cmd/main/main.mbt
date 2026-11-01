///|
fn usage() -> String {
  (
    #|moon-lot-recall: offline food-lot recall impact tracing
    #|
    #|Usage:
    #|  moon run cmd/main --target js -- validate LEDGER.json
    #|  moon run cmd/main --target js -- analyze LEDGER.json RECALL.json [json|markdown|csv]
    #|  moon run cmd/main --target js -- actions LEDGER.json RECALL.json
    #|  moon run cmd/main --target js -- inventory LEDGER.json AS_OF
    #|  moon run cmd/main --target js -- upstream LEDGER.json LOT_ID AS_OF
    #|  moon run cmd/main --target js -- import-csv LOTS.csv TRANSFORMATIONS.csv SHIPMENTS.csv OUT.json
    #|
    #|All timestamps are Unix seconds; all quantities are integer grams.
    #|An impact path indicates possible exposure, not proven contamination.
    #|
  )
}

///|
fn fail_cli(message : String) -> Unit {
  println("ERROR: \{message}")
  @sys.exit(2)
}

///|
fn read_text(path : String) -> String? {
  let text = @fs.read_file_to_string(path) catch {
    error => {
      fail_cli("cannot read \{path}: \{Repr(error)}")
      return None
    }
  }
  Some(text)
}

///|
fn read_ledger(path : String) -> @lib.Ledger? {
  let text = match read_text(path) {
    None => return None
    Some(value) => value
  }
  match @lib.decode_ledger(text) {
    Ok(ledger) => Some(ledger)
    Err(error) => {
      fail_cli("\{error.code}: \{error.message}")
      None
    }
  }
}

///|
fn read_request(path : String) -> @lib.RecallRequest? {
  let text = match read_text(path) {
    None => return None
    Some(value) => value
  }
  match @lib.decode_request(text) {
    Ok(request) => Some(request)
    Err(error) => {
      fail_cli("\{error.code}: \{error.message}")
      None
    }
  }
}

///|
fn parse_time(text : String) -> Int64? {
  let value = @string.parse_int64(text) catch {
    _ => {
      fail_cli("AS_OF must be an integer Unix timestamp")
      return None
    }
  }
  Some(value)
}

///|
fn run_validate(args : Array[String]) -> Unit {
  if args.length() != 2 {
    fail_cli("validate requires LEDGER.json")
    return
  }
  match read_ledger(args[1]) {
    None => ()
    Some(ledger) => {
      let validation = @lib.validate_ledger(ledger)
      println(@lib.render_validation(validation))
      if !validation.valid {
        @sys.exit(2)
      }
    }
  }
}

///|
fn run_analyze(args : Array[String]) -> Unit {
  if args.length() < 3 || args.length() > 4 {
    fail_cli("analyze requires LEDGER.json RECALL.json [json|markdown|csv]")
    return
  }
  let ledger = match read_ledger(args[1]) {
    None => return
    Some(value) => value
  }
  let request = match read_request(args[2]) {
    None => return
    Some(value) => value
  }
  let format = if args.length() == 4 { args[3] } else { "markdown" }
  match @lib.analyze(ledger, request) {
    Err(validation) => {
      println(@lib.render_validation(validation))
      @sys.exit(2)
    }
    Ok(report) => match format {
      "json" => println(@lib.encode_report(report))
      "markdown" => println(@lib.render_markdown(report))
      "csv" => println(@lib.render_shipments_csv(report))
      _ => fail_cli("format must be json, markdown, or csv")
    }
  }
}

///|
fn run_actions(args : Array[String]) -> Unit {
  if args.length() != 3 {
    fail_cli("actions requires LEDGER.json RECALL.json")
    return
  }
  let ledger = match read_ledger(args[1]) {
    None => return
    Some(value) => value
  }
  let request = match read_request(args[2]) {
    None => return
    Some(value) => value
  }
  match @lib.plan_actions(ledger, request) {
    Err(validation) => {
      println(@lib.render_validation(validation))
      @sys.exit(2)
    }
    Ok(plan) => println(@lib.render_actions_markdown(plan))
  }
}

///|
fn run_inventory(args : Array[String]) -> Unit {
  if args.length() != 3 {
    fail_cli("inventory requires LEDGER.json AS_OF")
    return
  }
  let ledger = match read_ledger(args[1]) {
    None => return
    Some(value) => value
  }
  let as_of = match parse_time(args[2]) {
    None => return
    Some(value) => value
  }
  match @lib.inventory_at(ledger, as_of) {
    Err(validation) => {
      println(@lib.render_validation(validation))
      @sys.exit(2)
    }
    Ok(report) => println(@json.to_json(report).stringify(indent=2))
  }
}

///|
fn run_upstream(args : Array[String]) -> Unit {
  if args.length() != 4 {
    fail_cli("upstream requires LEDGER.json LOT_ID AS_OF")
    return
  }
  let ledger = match read_ledger(args[1]) {
    None => return
    Some(value) => value
  }
  let as_of = match parse_time(args[3]) {
    None => return
    Some(value) => value
  }
  match @lib.trace_upstream(ledger, args[2], as_of) {
    Err(validation) => {
      println(@lib.render_validation(validation))
      @sys.exit(2)
    }
    Ok(report) => println(@lib.render_upstream_markdown(report))
  }
}

///|
fn run_import_csv(args : Array[String]) -> Unit {
  if args.length() != 5 {
    fail_cli("import-csv requires LOTS.csv TRANSFORMATIONS.csv SHIPMENTS.csv OUT.json")
    return
  }
  let lots = match read_text(args[1]) {
    None => return
    Some(value) => value
  }
  let transformations = match read_text(args[2]) {
    None => return
    Some(value) => value
  }
  let shipments = match read_text(args[3]) {
    None => return
    Some(value) => value
  }
  match @lib.import_csv(lots, transformations, shipments) {
    Err(validation) => {
      println(@lib.render_validation(validation))
      @sys.exit(2)
    }
    Ok(ledger) => {
      @fs.write_string_to_file(args[4], @lib.encode_ledger(ledger)) catch {
        error => fail_cli("cannot write \{args[4]}: \{Repr(error)}")
      }
      println("Wrote validated ledger to \{args[4]}")
    }
  }
}

///|
fn main {
  // The Node.js backend exposes [node, compiled-script, user-arguments...].
  let raw = @env.args()
  let args = raw[2:].to_owned()
  if args.is_empty() || args[0] == "--help" || args[0] == "help" {
    println(usage())
    return
  }
  match args[0] {
    "validate" => run_validate(args)
    "analyze" => run_analyze(args)
    "actions" => run_actions(args)
    "inventory" => run_inventory(args)
    "upstream" => run_upstream(args)
    "import-csv" => run_import_csv(args)
    _ => {
      println(usage())
      @sys.exit(2)
    }
  }
}

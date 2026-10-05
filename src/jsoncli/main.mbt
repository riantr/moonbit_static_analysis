// JSON bridge entry: the DeepSeek Harness plugin (dsh-plugin-moonbit-static-analysis)
// spawns this program under Node, passes ONE argument — a JSON request — and
// reads a JSON reply from stdout. Two request kinds:
//   { "kind": "program", "source": "...", "filename": "main.mbt" }
//   { "kind": "machine", "spec": { MachineSpec fields } }
// The bridge keeps the plugin a pure spawner: all analyzer semantics stay in
// MoonBit, versioned and gated with the module itself.

///|
/// one finding, flattened for JSON
struct Finding {
  line : Int
  col : Int
  severity : String
  message : String
  family : String
  lenses : Array[String]
  vst : Array[FrameRep]
} derive(ToJson)

///|
/// one virtual-stack frame
struct FrameRep {
  func : String
  file : String
  line : Int
} derive(ToJson)

///|
/// the reply envelope
struct Reply {
  ok : Bool
  error : String?
  count : Int
  findings : Array[Finding]
  rendered : String
} derive(ToJson)

///|
/// machine tables, mirroring @statecheck.MachineSpec in wire form; every
/// field is optional and defaulted at conversion
struct SpecReq {
  name : String?
  states : Array[String]?
  initial : String?
  terminal : String?
  transitions : Array[(String, String, String)]?
  trigger_slots : Array[(String, String)]?
  slot_names : Array[String]?
  blocks : Array[(String, String, String)]?
  course : Array[String]?
} derive(FromJson)

///|
struct Request {
  kind : String?
  source : String?
  filename : String?
  spec : SpecReq?
} derive(FromJson)

///|
fn to_finding(rep : @report.Report) -> Finding {
  let severity = match rep.family.severity() {
    @core.Error => "error"
    @core.Warning => "warning"
    @core.Hint => "hint"
  }
  let vst = rep.vst.map(frame => {
    func: frame.func,
    file: frame.file,
    line: frame.line,
  })
  {
    line: rep.span.start.line,
    col: rep.span.start.col,
    severity,
    message: rep.message,
    family: rep.family.name(),
    lenses: rep.lenses.map(lens => lens.name()),
    vst,
  }
}

///|
fn ok_reply(findings : Array[@report.Report], rendered : String) -> Reply {
  let items = findings.map(to_finding)
  { ok: true, error: None, count: items.length(), findings: items, rendered, }
}

///|
fn err_reply(msg : String) -> Reply {
  { ok: false, error: Some(msg), count: 0, findings: [], rendered: "", }
}

///|
fn reply_string(reply : Reply) -> String {
  @json.to_json(reply).stringify()
}

///|
/// the request JSON is the argument that starts with '{' (runner args before
/// it are ignored)
fn find_request_arg(args : Array[String]) -> String? {
  for s in args {
    if s.trim_start().has_prefix("{") {
      return Some(s)
    }
  }
  None
}

///|
fn to_spec(req : SpecReq) -> @statecheck.MachineSpec {
  let name = req.name.unwrap_or("machine")
  let states = req.states.unwrap_or([])
  let initial = req.initial.unwrap_or("")
  let terminal = req.terminal.unwrap_or("")
  let transitions = req.transitions.unwrap_or([])
  let trigger_slots = req.trigger_slots.unwrap_or([])
  let slot_names = req.slot_names.unwrap_or([])
  let blocks = req.blocks.unwrap_or([])
  let course = req.course.unwrap_or([])
  {
    name,
    states,
    initial,
    terminal,
    transitions,
    trigger_slots,
    slot_names,
    blocks,
    course,
  }
}

///|
fn run_machine(req : SpecReq) -> Reply {
  let spec = to_spec(req)
  ok_reply(@statecheck.audit(spec), @statecheck.render(spec))
}

///|
fn run_program(source : String, filename : String) -> Reply {
  let result = @pipeline.run(source, filename)
  ok_reply(result.reports, @pipeline.render_result(result))
}

///|
fn handle(raw : String) -> Reply {
  try {
    let request : Request = @json.from_json(@json.parse(raw))
    let kind = request.kind.unwrap_or("program")
    match kind {
      "program" =>
        run_program(
          request.source.unwrap_or(""),
          request.filename.unwrap_or("main.mbt"),
        )
      "machine" =>
        match request.spec {
          None => err_reply("machine request needs a spec object")
          Some(spec) => run_machine(spec)
        }
      other => err_reply("unknown request kind '\{other}'")
    }
  } catch {
    err => err_reply("bad request: \{err.to_string()}")
  }
}

///|
fn main {
  let args : Array[String] = @env.args()
  match find_request_arg(args) {
    None =>
      println(
        reply_string(err_reply("missing request argument (a JSON object)")),
      )
    Some(raw) => println(reply_string(handle(raw)))
  }
}

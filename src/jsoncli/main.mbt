// JSON bridge entry: the DeepSeek Harness plugin (dsh-plugin-moonbit-static-analysis)
// spawns this program under Node, passes ONE argument — a JSON request — and
// reads a JSON reply from stdout. Request kinds:
//   { "kind": "program", "source": "...", "filename": "main.mbt" }
//   { "kind": "file",    "source": "...", "filename": "doc.mbt.md" }   (extension dispatch)
//   { "kind": "machine", "spec": { MachineSpec fields } }
// The bridge keeps the plugin a pure spawner: all analyzer semantics stay in
// MoonBit, versioned and gated with the module itself.

///|
/// 0523. One argument of a checkable assertion, as a key/value pair so a
/// consumer reads it BY NAME. Positional arguments would make every check's
/// arity part of the wire format, and adding one would silently renumber the
/// rest.
#derive(ToJson)
struct ParamRep {
  k : String
  v : String
}

///|
/// 0523. THE ASSERTION a finding makes, in a form a program can switch on: which
/// question the analyzer answered (`check`) and about what (`params`).
///
/// Absent when the finding makes no machine-checkable claim -- see
/// `src/report/predicate.mbt`, where each absence is a stated decision. An absent
/// predicate is honest; a predicate over an empty name is not, so the projection
/// refuses that case instead of emitting one.
#derive(ToJson)
struct PredicateRep {
  check : String
  params : Array[ParamRep]
}

///|
/// one finding, flattened for JSON
///
/// 0507. Two fields beside `severity`:
///   * `confidence` -- how much the lens CHECKED. The severity says how bad the
///     finding is if it is real; the confidence says how sure the analyzer is
///     that it is real, and the two are independent.
///   * `family_id` -- the family's STABLE id. `family` is the public NAME, and
///     a name is a second vocabulary that can be renamed without anybody
///     noticing; the id cannot be renumbered, so a consumer can pin it.
#derive(ToJson)
struct Finding {
  line : Int32
  col : Int32
  severity : String
  confidence : String
  message : String
  family : String
  family_id : String
  lenses : Array[String]
  vst : Array[FrameRep]
  /// 0523. `null` when the family makes no machine-checkable claim.
  predicate : PredicateRep?
}

///|
/// one virtual-stack frame
#derive(ToJson)
struct FrameRep {
  func : String
  file : String
  line : Int32
}

///|
/// 0523. The report's own projection, converted to wire form. The check and its
/// arguments come from `Report::predicate` and are NOT re-derived here: a second
/// derivation would be a second answer to "what was asserted".
fn to_predicate(rep : @report.Report) -> PredicateRep? {
  match rep.predicate() {
    Some(p) => {
      let ps : Array[ParamRep] = []
      for pair in p.params {
        ps.push({ k: pair.0, v: pair.1, })
      }
      Some({ check: p.check, params: ps, })
    }
    None => None
  }
}

///|
/// 0521. The ADEQUACY block, as JSON: how much did the analyzer actually
/// CHECK, beside what it found.
///
/// Present only when a type lens ran, and OMITTED (the derive drops a `None`)
/// for the `machine` and iface/proof request kinds, which have no call sites to
/// check. An absent record says "this channel has no adequacy statement to
/// make"; an all-zero record would say "it checked nothing", which is a
/// different and false claim.
#derive(ToJson)
struct MetricsRep {
  /// Did the frontend understand the whole source? The same question the
  /// text report's PARSED line answers, so the two channels cannot disagree
  /// about whether a finding is a statement about the code or about the reader.
  understood : Bool
  /// Every distinct call SITE the type lens reached.
  calls : Int32
  /// The ones whose signature it read and whose arguments it matched.
  checked : Int32
  /// The ones it is a real call but whose signature was never read.
  unchecked : Int32
  /// `checked / calls`. "n/a" when no call site was visited: 0 of 0 is not 0%.
  checked_share : String
  /// Findings with confidence `undecided` -- the declared scope limits, i.e.
  /// constructs the analyzer read and did not analyse.
  scope_limits : Int32
}

///|
/// the reply envelope
#derive(ToJson)
struct Reply {
  ok : Bool
  error : String?
  count : Int32
  findings : Array[Finding]
  rendered : String
  /// 0521. `null` unless a type lens ran; see `MetricsRep`.
  metrics : MetricsRep?
}

///|
/// machine tables, mirroring @statecheck.MachineSpec in wire form; every
/// field is optional and defaulted at conversion
#derive(FromJson)
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
}

///|
#derive(FromJson)
struct Request {
  kind : String?
  source : String?
  filename : String?
  spec : SpecReq?
}

///|
fn to_finding(rep : @report.Report) -> Finding {
  // The SAME label the text renderer uses. A JSON consumer that reads
  // `severity: "error"` for a declared scope limit is being told the opposite
  // of what the text report told the same reader, and a machine-readable
  // channel that disagrees with the human one is the worse of the two.
  let severity = rep.severity_label()
  let vst = rep.vst.map(frame => {
    func: frame.func,
    file: frame.file,
    line: frame.line,
  })
  {
    line: rep.span.start.line,
    col: rep.span.start.col,
    severity,
    confidence: rep.confidence().name(),
    message: rep.message,
    family: rep.family.name(),
    family_id: rep.family.id(),
    lenses: rep.lenses.map(lens => lens.name()),
    vst,
    predicate: to_predicate(rep),
  }
}

///|
/// 0521. The same adequacy arithmetic the text report's METRICS block does, on
/// one source. Computed HERE and nowhere else, from the pipeline's own
/// counters, so the two channels cannot drift into two definitions of
/// "checked".
fn metrics_of(result : @pipeline.PipelineResult) -> MetricsRep {
  let mut scope_limits = 0
  for rep in result.reports {
    if rep.confidence() == @core.Undecided {
      scope_limits += 1
    }
  }
  let checked_share = if result.n_calls == 0 {
    "n/a"
  } else {
    let t = result.n_checked * 1000 / result.n_calls
    "\{t / 10}.\{t % 10}%"
  }
  {
    understood: result.first_error_line == 0,
    calls: result.n_calls,
    checked: result.n_checked,
    unchecked: result.n_unchecked,
    checked_share,
    scope_limits,
  }
}

///|
fn ok_reply(
  findings : Array[@report.Report],
  rendered : String,
  metrics : MetricsRep?,
) -> Reply {
  let items = findings.map(to_finding)
  {
    ok: true,
    error: None,
    count: items.length(),
    findings: items,
    rendered,
    metrics,
  }
}

///|
fn err_reply(msg : String) -> Reply {
  {
    ok: false,
    error: Some(msg),
    count: 0,
    findings: [],
    rendered: "",
    metrics: None,
  }
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
  ok_reply(@statecheck.audit(spec), @statecheck.render(spec), None)
}

///|
fn run_program(source : String, filename : String) -> Reply {
  let result = @pipeline.run(source, filename, @core.IfaceSymTab::empty())
  // The ONLY request kind that runs a type lens, so the only one that has an
  // adequacy figure to report.
  ok_reply(
    result.reports,
    @pipeline.render_result(result),
    Some(metrics_of(result)),
  )
}

///|
/// kind:"file" — dispatch on the filename's extension (the taxonomy lives in
/// the module root EXTENSIONS.md):
///   .mbt / .mbtx  → program three-inspection (.mbtx may carry an import block)
///   .md / .mbt.md → literate MoonBit (moonbit fences, real line numbers)
///   .mbti         → interface well-formedness audit
///   .mbtp         → proof-file logic-side audit
fn dispatch_file(filename : String, source : String) -> Reply {
  let lower = filename.to_lower()
  let kind = if lower.has_suffix(".mbt.md") || lower.has_suffix(".md") {
    "md"
  } else if lower.has_suffix(".mbti") {
    "iface"
  } else if lower.has_suffix(".mbtp") {
    "proof"
  } else {
    "program"
  }
  match kind {
    "md" => {
      let r = @moonfiles.literate(source, filename)
      ok_reply(r.reports, @pipeline.render_result(r), None)
    }
    "iface" => {
      // one file in, no module context: the empty table is the honest one —
      // a name is only resolvable when this file declares it
      let reports = @moonfiles.iface(
        source,
        filename,
        @core.IfaceSymTab::empty(),
      )
      ok_reply(reports, render_reports(reports), None)
    }
    "proof" => {
      let reports = @moonfiles.proof(source, filename)
      ok_reply(reports, render_reports(reports), None)
    }
    _ => run_program(source, filename)
  }
}

///|
/// render a bare report list without signatures (iface/proof audits)
fn render_reports(reports : Array[@report.Report]) -> String {
  let buf = StringBuilder()
  for rep in reports {
    buf.write_string(rep.render())
  }
  buf.write_string("\nSummary: \{reports.length()} finding(s)\n")
  buf.to_string()
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
      "file" =>
        dispatch_file(
          request.filename.unwrap_or("main.mbt"),
          request.source.unwrap_or(""),
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
/// `--file <path>`: read the request JSON from a file instead of argv.
///
/// Windows caps the WHOLE command line at 32,767 characters, not each
/// argument, so a request is unusable once the source passes roughly 30 KB:
/// the spawn fails with ENAMETOOLONG before this program starts, and it throws
/// synchronously rather than arriving as an 'error' event. In moonbit_doubleML
/// 27 of 180 files are over 30 KB.
///
/// Splitting the request across several argv entries was tried and does not
/// help -- the cap is on the total, not per argument. A path is short, so the
/// caller writes the request to a file and passes the path.
///
/// This needs file IO, so it puts the package on the wasm/native side of the
/// fence: the js backend has no async runtime and cannot read a file.
async fn file_request(args : Array[String]) -> String? {
  // Not a fixed index: under `moonrun <wasm> --file <path>` the runner's own
  // arguments come first, which is exactly why the inline form scans for the
  // request instead of taking args[0].
  let mut i = 0
  while i + 1 < args.length() {
    if args[i] == "--file" {
      let text = @fs.read_text(args[i + 1]) catch { _ => return None }
      return Some(text)
    }
    i += 1
  }
  None
}

///|
async fn main {
  let args : Array[String] = @env.args()
  let raw = match file_request(args) {
    Some(r) => Some(r)
    None => find_request_arg(args)
  }
  match raw {
    None =>
      println(
        reply_string(
          err_reply(
            "missing request (pass a JSON object, or --file <path> for sources too large for the 32767-character command line)",
          ),
        ),
      )
    Some(r) => println(reply_string(handle(r)))
  }
}

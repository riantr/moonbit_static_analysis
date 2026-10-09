// test: the mermaid renderer.
//
// The deliverable is a document some other program has to parse, so the tests
// here are not "does it contain this substring" — they re-read the emitted
// text against the grammar mermaid accepts and fail on anything that would not
// render. `mm_check` below is that gate: it walks every line, admits only the
// statement forms this renderer is allowed to emit, and then cross-checks that
// every transition endpoint was actually declared.
//
// Three grammar facts it encodes, all measured against this MoonBit's own
// stdlib and against mermaid rather than assumed:
//   - a node id is an identifier, so no id may contain `-`, `.` or `/`
//   - a transition label is everything after the FIRST `:`, so a label that
//     carries a location or a message must not introduce a second colon
//   - a quoted label cannot contain a `"`, so message text must be sanitized
//
// The negative control is at the bottom of this file: `mm_check` is shown
// failing on five documents it is meant to catch, and accepting this
// renderer's own output, so it cannot rot into a test that always passes.

///|
fn mm_span(line : Int, col : Int) -> @core.Span {
  { start: { line, col, }, end: { line, col, }, }
}

///|
fn mm_rep(
  family : @core.Family,
  lenses : Array[@core.Lens],
  message : String,
  line : Int,
) -> @report.Report {
  @report.Report::{ family, lenses, message, span: mm_span(line, 7), vst: [], }
}

///|
fn mm_verdict(
  path : String,
  findings : Array[@report.Report],
  parsed : Bool,
  region_line : Int,
  unreliable : Int,
  notices : Int,
) -> @sa.Verdict {
  @sa.Verdict::{
    path,
    kind: ".mbt",
    findings,
    parsed,
    reason: if parsed {
      ""
    } else {
      "first read failure"
    },
    total: findings.length() + unreliable,
    notices,
    region_line,
    unreliable,
  }
}

///|
/// A parsed file carrying `n` findings, cycled across three families so more
/// than one inspection owns a node in the drawing.
fn mm_parsed_with(n : Int) -> @sa.Verdict {
  let fams = [@core.FUndefinedName, @core.FUnusedLocal, @core.FArgType]
  let reps = []
  for i in 0..<n {
    reps.push(
      mm_rep(fams[i % 3], [@core.LStructural], "no visible binding 'x'", 10 + i),
    )
  }
  mm_verdict("src/a.mbt", reps, true, 0, 0, 0)
}

///|
/// A file that stopped being understood at line 40, with 9 findings past it.
fn mm_partial() -> @sa.Verdict {
  mm_verdict(
    "src/b.mbt",
    [mm_rep(@core.FUnusedParam, [@core.LType], "unused parameter 'n'", 12)],
    false,
    40,
    9,
    0,
  )
}

///|
/// A parsed file carrying 2 notices alongside its defects.
fn mm_with_notices() -> @sa.Verdict {
  mm_verdict(
    "src/c.mbt",
    [
      mm_rep(
        @core.FParse,
        [@core.LStructural],
        "test decl is outside the subset",
        3,
      ),
      mm_rep(
        @core.FParse,
        [@core.LStructural],
        "test decl is outside the subset",
        4,
      ),
      mm_rep(@core.FUndefinedName, [@core.LType], "no visible binding", 5),
    ],
    true,
    0,
    0,
    2,
  )
}

///|
/// One finding all three lenses saw, so the merged path is exercised.
fn mm_merged() -> @sa.Verdict {
  mm_verdict(
    "src/d.mbt",
    [
      mm_rep(
        @core.FOpMismatch,
        [@core.LStructural, @core.LType, @core.LBehavior],
        "operator '!' applied to Int",
        21,
      ),
    ],
    true,
    0,
    0,
    0,
  )
}

///|
fn mm_prov() -> @sa.ScanProvenance {
  @sa.ScanProvenance::{
    target: "corpus",
    version: "0.1.20260920+7d59c7ec9",
    scanned_at: "20261009T051511Z",
  }
}

///|
fn mm_render(
  vs : Array[@sa.Verdict],
  per_file : Int,
  max_files : Int,
) -> String {
  @sa.mermaid_states(vs, @sa.aggregate(vs), mm_prov(), per_file, max_files)
}

///|
/// Split on `\n` into owned strings. `split` yields `StringView`s and so does
/// `trim()`, so both need `.to_owned()` to become a `String`.
fn mm_lines(s : String) -> Array[String] {
  s.split("\n").map(fn(x) { x.to_owned() }).to_array()
}

///|
fn mm_id_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn mm_id_char(c : Char) -> Bool {
  mm_id_start(c) || (c >= '0' && c <= '9')
}

///|
/// A mermaid node id is an identifier. A filesystem path is not one, which is
/// why file ids are synthesised (`f12`) and the path rides in the label.
fn mm_valid_id(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let mut first = true
  for c in s {
    if first {
      if !mm_id_start(c) {
        return false
      }
      first = false
    } else if !mm_id_char(c) {
      return false
    }
  }
  true
}

///|
fn mm_count_quotes(s : String) -> Int {
  let mut n = 0
  for c in s {
    if c == '"' {
      n = n + 1
    }
  }
  n
}

///|
fn mm_occurrences(s : String, sub : String) -> Int {
  s.split(sub).to_array().length() - 1
}

///|
/// The text after the LAST occurrence of `marker`, or "" if absent.
///
/// Built from `split` rather than `find` + slicing on purpose: string
/// indexing is by BYTE while `find` reports a CHARACTER offset, so any helper
/// that slices a label containing a multi-byte character (the em-dash in every
/// state label here) silently reads the wrong span. `split` is not affected.
fn mm_after_last(s : String, marker : String) -> String {
  let parts = s.split(marker).map(fn(x) { x.to_owned() }).to_array()
  parts[parts.length() - 1]
}

///|
/// The text BEFORE the FIRST occurrence of `marker`, or all of `s`. Same
/// reason as `mm_after_last`: no manual offsets.
fn mm_before_first(s : String, marker : String) -> String {
  s.split(marker).map(fn(x) { x.to_owned() }).to_array()[0]
}

///|
/// The transition label: the text after the first ` : `.
fn mm_label(t : String) -> String {
  let parts = t.split(" : ").map(fn(x) { x.to_owned() }).to_array()
  if parts.length() >= 2 {
    parts[1]
  } else {
    ""
  }
}

///|
fn mm_spaces(s : String) -> Array[String] {
  s.split(" ").map(fn(x) { x.to_owned() }).to_array().filter(fn(x) { x != "" })
}

///|
/// The id of a `state "LABEL" as ID` line.
///
/// Two traps, both hit while writing this:
///   - the label may itself contain ` as `, so the id is read from after the
///     SECOND quote rather than from the first ` as `
///   - the id is taken WHOLE, not as the leading run of identifier
///     characters. Taking that run would silently truncate `f-0` to `f` and
///     wave through an id mermaid rejects, which is exactly what this gate
///     exists to catch.
fn mm_state_id(t : String) -> String {
  let mut seen = 0
  let mut after_close = false
  let tail = StringBuilder()
  for c in t {
    if after_close {
      tail.write_char(c)
    } else if c == '"' {
      seen = seen + 1
      if seen == 2 {
        after_close = true
      }
    }
  }
  let rest = mm_after_last(tail.to_string(), " as ")
  mm_before_first(rest, " {").trim().to_owned()
}

///|
/// The grammar gate. Returns a list of complaints; empty means every line is a
/// form mermaid accepts, every identifier is an identifier, every quoted label
/// holds exactly one pair of quotes, and every transition names a state that
/// was declared somewhere in the document.
fn mm_check(src : String) -> Array[String] {
  let errs = []
  let declared = []
  let edges = []
  let mut in_note = false
  let lines = mm_lines(src)
  for raw in lines {
    let t = raw.trim().to_owned()
    if in_note {
      if t == "end note" {
        in_note = false
      } else if t == "" {
        errs.push("blank line inside a note: the block end is lost")
      }
      continue
    }
    if t == "" || t.has_prefix("%%") || t == "stateDiagram-v2" {
      continue
    }
    if t.has_prefix("direction ") || t == "{" || t == "}" {
      continue
    }
    if t.has_prefix("note right of ") {
      let anchor = mm_after_last(t, "note right of ")
      if !mm_valid_id(anchor) {
        errs.push("note anchor is not an identifier: " + anchor)
      }
      in_note = true
      continue
    }
    if t.has_prefix("state \"") {
      if mm_count_quotes(t) != 2 {
        errs.push("state label is not one quoted string: " + t)
      }
      let bare = mm_state_id(t)
      if !mm_valid_id(bare) {
        errs.push("state id is not an identifier: " + bare)
      } else if !declared.contains(bare) {
        declared.push(bare)
      }
      continue
    }
    if t.contains(" --> ") {
      // Everything after the first ` : ` is the label, so the endpoint pair is
      // what precedes it, and the arrow itself is not an endpoint.
      let head = mm_before_first(t, " : ")
      let toks = mm_spaces(head.replace(old=" --> ", new=" "))
      if toks.length() != 2 {
        errs.push("transition is not `A --> B` or `A --> B : label`: " + t)
        continue
      }
      edges.push([toks[0], toks[1]])
      continue
    }
    errs.push("line is not a form this renderer may emit: " + t)
  }
  if in_note {
    errs.push("a note was opened and never closed")
  }
  for e in edges {
    for ep in e {
      if ep != "[*]" && !declared.contains(ep) {
        errs.push("transition names an undeclared state: " + ep)
      }
    }
  }
  errs
}

///|
/// Every shape the renderer can produce, drawn uncapped: a clean parsed file,
/// a file that stopped being understood, one carrying notices, and one whose
/// single finding all three lenses saw.
fn mm_rich() -> Array[@sa.Verdict] {
  [mm_parsed_with(3), mm_partial(), mm_with_notices(), mm_merged()]
}

///|
test "the emitted document is grammatically valid mermaid" {
  assert_eq(mm_check(mm_render(mm_rich(), 0, 0)), [])
}

///|
test "the header states the whole-scan summary" {
  let vs = mm_rich()
  let src = mm_render(vs, 0, 0)
  let s = @sa.aggregate(vs)
  assert_true(src.contains("files=\{vs.length()}"))
  assert_true(src.contains("parsed=\{s.parsed_files}"))
  assert_true(src.contains("actionable=\{s.actionable}"))
  // Uncapped: nothing is a subset, so the caveat must be absent.
  assert_false(src.contains("SUBSET"))
}

///|
test "a transition label is only ever the family name" {
  // Both the location and the message carry a colon or a quote. They belong in
  // the quoted state label; if either ever leaked onto a transition, mermaid
  // would read everything after the FIRST colon as the label.
  let vs = [
    mm_verdict(
      "src/e.mbt",
      [
        mm_rep(
          @core.FUndefinedName,
          [@core.LStructural],
          "undefined name 'a:b'",
          7,
        ),
        mm_rep(@core.FArgType, [@core.LType], "expected Int, got String", 8),
      ],
      true,
      0,
      0,
      0,
    ),
  ]
  let src = mm_render(vs, 0, 0)
  for raw in mm_lines(src) {
    let t = raw.trim().to_owned()
    if t.contains(" --> ") {
      let label = mm_label(t)
      assert_false(label.contains("'"))
      assert_false(label.contains("@"))
    }
  }
  // ...and they ARE on the node, so nothing was dropped to achieve that.
  assert_true(src.contains("undefined name 'a:b'"))
  assert_true(src.contains("@7:7"))
  assert_eq(mm_check(src), [])
}

///|
test "a partial file stops at its trust boundary" {
  let src = mm_render([mm_partial()], 0, 0)
  assert_true(src.contains("withheld past the boundary"))
  assert_true(src.contains("9 further findings on this file"))
  assert_eq(mm_check(src), [])
}

///|
test "notices are distinguished from defects" {
  let src = mm_render([mm_with_notices()], 0, 0)
  assert_true(src.contains("are NOTICES"))
  assert_true(src.contains("2 of the findings on this file"))
}

///|
test "every finding node explains itself" {
  let src = mm_render([mm_parsed_with(3)], 0, 0)
  assert_eq(mm_occurrences(src, "WHY: "), 3)
  assert_eq(mm_occurrences(src, "HOW: "), 3)
  // The real advice table, not a placeholder.
  assert_true(src.contains("WHY: No visible binding"))
}

///|
test "a finding all three lenses saw says so" {
  let src = mm_render(mm_rich(), 0, 0)
  assert_true(src.contains("SEEN BY: structural+type+behavior"))
}

///|
test "a per-file cap announces exactly what it dropped" {
  let src = mm_render([mm_parsed_with(5)], 2, 0)
  assert_eq(mm_occurrences(src, " as f0_e"), 2)
  assert_true(src.contains("3 further findings on this file were NOT drawn"))
  assert_true(src.contains("caps a file at 2"))
  assert_eq(mm_check(src), [])
}

///|
test "a per-file cap of zero means no cap" {
  let src = mm_render([mm_parsed_with(5)], 0, 0)
  assert_eq(mm_occurrences(src, " as f0_e"), 5)
  assert_false(src.contains("NOT drawn"))
}

///|
test "a file cap announces the subset and draws the worst first" {
  let vs = [mm_parsed_with(1), mm_parsed_with(5), mm_parsed_with(2)]
  let src = mm_render(vs, 0, 2)
  assert_true(src.contains("THIS DRAWING IS A SUBSET"))
  assert_true(src.contains("2 of 3 files"))
  assert_true(src.contains("scan --> f1 : 5 actionable, 0 notice(s), parsed"))
  assert_true(src.contains("scan --> f2 : 2 actionable, 0 notice(s), parsed"))
  assert_false(src.contains("scan --> f0"))
  assert_eq(mm_check(src), [])
}

///|
test "the summary describes the whole scan even when the drawing is capped" {
  // files=3 while only two are drawn. Without this split the header would read
  // as "3 files, all clean" for the one that is missing.
  let vs = [mm_parsed_with(1), mm_parsed_with(5), mm_parsed_with(2)]
  let src = mm_render(vs, 0, 2)
  assert_true(src.contains("files=3"))
  assert_true(src.contains("A file not drawn is NOT a file with no findings"))
}

///|
test "labels cannot break out of their quotes" {
  let src = mm_render(
    [
      mm_verdict(
        "src/q.mbt",
        [
          mm_rep(
            @core.FUnusedLocal,
            [@core.LStructural],
            "unused \"local\"; drop it\nsecond line",
            3,
          ),
        ],
        true,
        0,
        0,
        0,
      ),
    ],
    0,
    0,
  )
  assert_eq(mm_check(src), [])
  assert_true(src.contains("unused 'local', drop it second line"))
}

///|
test "an empty scan is still a valid diagram" {
  let src = mm_render([], 0, 0)
  assert_eq(mm_check(src), [])
  assert_true(src.contains("stateDiagram-v2"))
}

///|
test "a file cap ranks by ACTIONABLE, not by raw findings" {
  // Reproduces what moonbitlang/core actually showed: its largest raw-finding
  // file was 402 findings that were 402 notices and zero defects, and ranking
  // by raw count put that file first in a diagram meant to lead with what to
  // fix.
  let notice_heavy = mm_verdict(
    "src/noisy.mbt",
    [
      mm_rep(@core.FParse, [@core.LStructural], "outside the subset", 3),
      mm_rep(@core.FParse, [@core.LStructural], "outside the subset", 4),
      mm_rep(@core.FParse, [@core.LStructural], "outside the subset", 5),
      mm_rep(@core.FParse, [@core.LStructural], "outside the subset", 6),
    ],
    true,
    0,
    0,
    4,
  )
  let defect = mm_verdict(
    "src/real.mbt",
    [mm_rep(@core.FUndefinedName, [@core.LType], "no visible binding", 9)],
    true,
    0,
    0,
    0,
  )
  let src = mm_render([notice_heavy, defect], 0, 1)
  assert_true(src.contains("scan --> f1 : 1 actionable, 0 notice(s), parsed"))
  assert_false(src.contains("scan --> f0"))
  assert_true(src.contains("1 of 2 files"))
}

///|
test "a count of one is written in the singular" {
  // Caught by reading a real render, not by a test: a file with 2 notices and
  // 4 dropped findings produced "1 of the findings on this file are NOTICES"
  // and "1 further finding(s) ... were NOT drawn". Both read as machine output,
  // which is the one thing these notes must not be.
  let one = mm_verdict(
    "src/one.mbt",
    [
      mm_rep(@core.FParse, [@core.LStructural], "outside the subset", 3),
      mm_rep(@core.FUnusedLocal, [@core.LType], "unused local", 4),
    ],
    false,
    12,
    1,
    1,
  )
  let src = mm_render([one], 1, 0)
  assert_true(src.contains("1 finding on this file is a NOTICE"))
  assert_true(
    src.contains("1 further finding on this file sits at or after line 12"),
  )
  assert_true(src.contains("1 further finding on this file was NOT drawn"))
  assert_false(src.contains("finding(s)"))
  assert_false(src.contains("1 of the findings"))
  assert_eq(mm_check(src), [])
}

///|
test "the header carries the version and the scan time" {
  let src = mm_render(mm_rich(), 0, 0)
  assert_true(src.contains("target=corpus"))
  assert_true(src.contains("version=0.1.20260920+7d59c7ec9"))
  assert_true(src.contains("scanned_at=20261009T051511Z (UTC)"))
  // Repeated in the BODY, not only in the filename: a file gets renamed, and
  // then its name is no longer evidence.
  assert_eq(mm_check(src), [])
}

///|
test "an unknown version or clock says so rather than vanishing" {
  let src = @sa.mermaid_states(
    mm_rich(),
    @sa.aggregate(mm_rich()),
    @sa.ScanProvenance::{ target: "some/tree", version: "", scanned_at: "", },
    0,
    0,
  )
  assert_true(src.contains("version=unknown"))
  assert_true(src.contains("scanned_at=unknown (UTC)"))
  assert_eq(mm_check(src), [])
}

// --- notices are not defects ----------------------------------------------
//
// A scan of this analyzer's own source produced a file with one notice and two
// defects, and the drawing gave all three the same shape, the same id stem and
// the same "WHY / HOW, here is what to change" note. Nothing in the rendered
// text said which two to act on. The only way to recover it was to already
// know that the family name `FParse` means notice — knowledge that lives in
// the scanner, not in the diagram a downstream agent reads.

///|
/// One file, one notice, two defects — the exact shape that used to render
/// three identical nodes.
fn mm_mixed() -> @sa.Verdict {
  mm_verdict(
    "src/f.mbt",
    [
      mm_rep(
        @core.FParse,
        [@core.LStructural],
        "test declaration is outside the analyzed subset",
        12,
      ),
      mm_rep(
        @core.FUnusedLocal,
        [@core.LStructural],
        "local 's' assigned but may not be used",
        57,
      ),
      mm_rep(
        @core.FArgType,
        [@core.LType],
        "argument 1 expected Int, got String",
        55,
      ),
    ],
    true,
    0,
    0,
    1,
  )
}

///|
test "a notice is drawn differently from a defect" {
  let src = @sa.mermaid_states(
    [mm_mixed()],
    @sa.aggregate([mm_mixed()]),
    @sa.ScanProvenance::{
      target: "self",
      version: "0.4.4",
      scanned_at: "20261009T051511Z",
    },
    0,
    0,
  )
  // The marker, in the node a reader looks at... `ParseError` is the name the
  // family is DRAWN under; `FParse` is the enum case behind it.
  assert_true(src.contains("NOTICE — ParseError @12:7"))
  // ...and in the transition label, which is what carries the family.
  assert_true(src.contains("notice ParseError"))
  assert_true(src.contains("defect UnusedLocal"))
  assert_true(src.contains("defect ArgTypeMismatch"))
  // The id stem differs too: an agent grepping node ids must not have to
  // parse the label to tell the two apart.
  assert_true(src.contains("as f0_n0"))
  assert_true(src.contains("as f0_e1"))
  assert_true(src.contains("as f0_e2"))
  assert_false(src.contains("as f0_n1"))
  assert_false(src.contains("as f0_n2"))
  assert_eq(mm_check(src), [])
}

///|
/// A notice must not carry the "here is what to change" note. That advice is
/// written for the first genuine read failure, which never reaches this loop
/// — everything from the trust boundary on is counted and not drawn — so on a
/// notice it described a problem that does not exist.
test "a notice carries no how-to-fix advice" {
  let src = @sa.mermaid_states(
    [mm_mixed()],
    @sa.aggregate([mm_mixed()]),
    @sa.ScanProvenance::{
      target: "self",
      version: "0.4.4",
      scanned_at: "20261009T051511Z",
    },
    0,
    0,
  )
  assert_true(src.contains("excluded from `actionable`"))
  // The notice says what it is, in its own words.
  assert_true(
    src.contains("ParseError covers a form this analyzer does not model"),
  )
  // ...and the defects keep theirs.
  assert_true(src.contains("WHY: "))
  assert_true(src.contains("HOW: "))
}

///|
/// The negative control for the split: a file with NO notice must not grow a
/// notice node or a notice-marked transition. A renderer that simply labelled
/// every node "notice" would pass the two tests above.
test "a file with no notice draws no notice node" {
  let src = mm_render([mm_parsed_with(3)], 0, 0)
  assert_false(src.contains("notice ParseError"))
  assert_false(src.contains("NOTICE — "))
  assert_true(src.contains("defect UndefinedName"))
  assert_eq(mm_check(src), [])
}

///|
/// The accounting has to survive truncation. With per_file = 1 the two notices
/// and the defect are dropped, and the note has to say how many of the dropped
/// ones were notices — otherwise the per-inspection breakdown, which counts
/// defects only, does not add up to the number quoted just above it.
test "a truncated diagram says how many of the dropped findings were notices" {
  let v = mm_verdict(
    "src/g.mbt",
    [
      mm_rep(@core.FParse, [@core.LStructural], "outside the subset", 10),
      mm_rep(@core.FParse, [@core.LStructural], "outside the subset", 11),
      mm_rep(@core.FUnusedLocal, [@core.LStructural], "unused", 12),
    ],
    true,
    0,
    0,
    2,
  )
  let src = @sa.mermaid_states(
    [v],
    @sa.aggregate([v]),
    @sa.ScanProvenance::{
      target: "self",
      version: "0.4.4",
      scanned_at: "20261009T051511Z",
    },
    1,
    0,
  )
  // per_file = 1 draws findings[0] (the notice). Of the two dropped —
  // findings[1] (notice) and findings[2] (defect) — exactly one is a notice,
  // and that is what the note has to say.
  assert_true(src.contains("1 of them is a NOTICE"))
  assert_true(src.contains("2 further findings on this file were NOT drawn"))
  assert_true(src.contains("Per inspection: 1 from struct."))
  assert_eq(mm_check(src), [])
}

///|
test "the gate rejects what it is meant to reject" {
  // Only worth something if it fails on input it is meant to catch. Each of
  // these is a document that would not render.
  // a transition to an endpoint that was never declared
  assert_eq(
    mm_check("stateDiagram-v2\n    state \"a\" as A\n    A --> B\n").length(),
    1,
  )
  // a note that is never closed
  // a note that is never closed (no trailing newline: a blank line left
  // inside an open note is itself a second, separate complaint)
  assert_eq(mm_check("stateDiagram-v2\n    note right of X").length(), 1)
  // an id containing a dash
  assert_eq(mm_check("stateDiagram-v2\n    state \"a\" as f-0\n").length(), 1)
  // an undeclared transition target
  assert_eq(
    mm_check("stateDiagram-v2\n    state \"a\" as x1\n    x1 --> y1 : ok\n").length(),
    1,
  )
  // a line that is not a mermaid statement
  assert_eq(mm_check("stateDiagram-v2\n    huh\n").length(), 1)
  // ...and it accepts the real thing, so it is not simply rejecting everything
  assert_eq(mm_check(mm_render(mm_rich(), 3, 3)), [])
}

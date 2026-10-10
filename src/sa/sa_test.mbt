// test: the SUMMARY-line identity. One regression in 0.4.0 (`+withheld` was
// added to the printed sum on top of `unreliable`) slipped past 88/88
// because no test pinned the arithmetic. The 0.4.0 round shipped a printed
// identity that read as a fact but did not hold. The downstream reader of
// this output caught it by parsing the printed numbers and asserting the
// sum; the fix is to pin the same identity in this package's own tests so
// the regression cannot return.

///|
/// Build a dummy Report. Aggregate only reads `family` (to set the notice
/// count) and `lenses.length()`; nothing else is touched by the math.
fn mk_report(family : @core.Family) -> @report.Report {
  @report.Report::{
    family,
    lenses: [@core.LStructural],
    message: "",
    span: { start: { line: 0, col: 0, }, end: { line: 0, col: 0, }, },
    vst: [],
  }
}

///|
/// One parsed file with 2 findings (1 defect, 1 notice). The findings array
/// has length 2 so the per-file `actionable + notices` is the expected 1+1.
fn v_parsed() -> @sa.Verdict {
  @sa.Verdict::{
    path: "a.mbt",
    kind: ".mbt",
    findings: [mk_report(@core.FUndefinedName), mk_report(@core.FParse)],
    parsed: true,
    reason: "",
    total: 2,
    notices: 1,
    region_line: 0,
    unreliable: 0,
  }
}

///|
/// Partial file: 1 pre-boundary defect, 0 notices, 5 post-boundary findings.
/// `findings` has length 1 to make the pre-boundary contribution 1 defect /
/// 0 notices (the per-file `(n - notices) = 1 - 0 = 1` and `notices = 0`),
/// which lands entirely in the pre-boundary totals. The 5 post-boundary
/// findings go into `unreliable`, not `withheld` — `withheld` is reserved
/// for partial files whose pre-boundary count is zero (see v_partial_empty).
fn v_partial_with_findings() -> @sa.Verdict {
  @sa.Verdict::{
    path: "b.mbt",
    kind: ".mbt",
    findings: [mk_report(@core.FUndefinedName)],
    parsed: false,
    reason: "first read failure at line 10",
    total: 6,
    notices: 0,
    region_line: 10,
    unreliable: 5,
  }
}

///|
/// Partial file: nothing trustworthy above the boundary, 4 findings all
/// after it. This is the case the 0.4.0 bug cared about: these 4 are
/// counted in BOTH `unreliable` (per-file line in `aggregate`) AND
/// `withheld` (the partial-with-zero-findings branch), and the printed
/// identity then added them together. With the fix, withheld is reported
/// separately and not in the sum.
fn v_partial_empty() -> @sa.Verdict {
  @sa.Verdict::{
    path: "c.mbt",
    kind: ".mbt",
    findings: [],
    parsed: false,
    reason: "first read failure at line 1",
    total: 4,
    notices: 0,
    region_line: 1,
    unreliable: 4,
  }
}

///|
test "SUMMARY identity: actionable + notices + unreliable == total" {
  // Construct three files whose numbers were chosen so the 0.4.0 identity
  // (actionable+notices+unreliable+withheld == total) would have failed:
  //   1 + 1 + 5 + 4 + 4 = 15  (with the bug, "total" printed would be 15)
  //   1 + 1 + 5 + 4     = 11  (the actual total, 0.4.0 printed 15 anyway)
  let vs : Array[@sa.Verdict] = [
    v_parsed(),
    v_partial_with_findings(),
    v_partial_empty(),
  ]
  let s = @sa.aggregate(vs)
  assert_eq(s.parsed_files, 1)
  assert_eq(s.partial_files, 2)
  // Pre-boundary: 1 parsed file (1 defect, 1 notice) + 1 partial-with-findings
  // (1 defect, 0 notices) = 2 actionable, 1 notice.
  assert_eq(s.actionable, 2)
  assert_eq(s.notices, 1)
  // Post-boundary: 5 + 4 = 9.
  assert_eq(s.unreliable, 9)
  // Withheld is a subset of unreliable: only the empty-partial contributes
  // its 4 post-boundary findings.
  assert_eq(s.withheld, 4)
  // total = 2 + 6 + 4 (sum of v.total) = 12. Also = 2 + 1 + 9 (the
  // identity).
  assert_eq(s.total, 12)
  assert_eq(s.actionable + s.notices + s.unreliable, s.total)
  // The identity the 0.4.0 line wrongly asserted (must NOT hold):
  assert_eq(
    s.actionable + s.notices + s.unreliable + s.withheld == s.total,
    false,
  )
}

///|
test "SUMMARY identity: withheld is always a subset of unreliable" {
  // withheld is the post-boundary count of partial files whose pre-boundary
  // finding count is zero. It can never exceed unreliable, because every
  // withheld finding is also unreliable.
  let vs : Array[@sa.Verdict] = [
    v_parsed(),
    v_partial_with_findings(),
    v_partial_empty(),
  ]
  let s = @sa.aggregate(vs)
  assert_true(s.withheld <= s.unreliable)
  // If no file is partial-with-zero-findings, withheld is 0.
  let s2 = @sa.aggregate([v_parsed(), v_partial_with_findings()])
  assert_eq(s2.withheld, 0)
  assert_eq(s2.unreliable, 5)
  // Only the empty-partial case contributes, and then withheld == unreliable.
  let s3 = @sa.aggregate([v_partial_empty()])
  assert_eq(s3.withheld, s3.unreliable)
  assert_eq(s3.total, s3.unreliable)
  // The reverse: a parsed file alone contributes nothing to either side.
  let s4 = @sa.aggregate([v_parsed()])
  assert_eq(s4.withheld, 0)
  assert_eq(s4.unreliable, 0)
  assert_eq(s4.total, 2)
}

///|
test "SUMMARY identity: an empty input gives all zeros" {
  let s = @sa.aggregate([])
  assert_eq(s.parsed_files, 0)
  assert_eq(s.partial_files, 0)
  assert_eq(s.actionable, 0)
  assert_eq(s.notices, 0)
  assert_eq(s.unreliable, 0)
  assert_eq(s.withheld, 0)
  assert_eq(s.total, 0)
  // Identity holds trivially.
  assert_eq(s.actionable + s.notices + s.unreliable, s.total)
}

// --- moon.mod import extraction -------------------------------------------
//
// 0.4.3 shipped a `parse_moon_mod_imports` that scanned for the bare text
// `import ` anywhere in the file and read quoted strings until the next `}`.
// The self-scan caught what that does on a real moon.mod: this module's own
// header comment contains the words "we never import them", which opened a
// phantom import block, and the scanner then read the module's own `name =`
// and `repository =` values as dependencies. The run announced 4 imports for
// a file declaring 1, and tried to fetch the analyzer itself.
//
// These tests run against the REAL grammar, including this module's own
// moon.mod shape, because a parser that only works on a hand-written sample
// is how the last version shipped a phantom import.

///|
test "moon.mod: only the import block yields coordinates" {
  // A name= / repository= / license= header before the import block must
  // contribute nothing, even when the header mentions the word "import".
  let src = "name = \"riantr/thing\"\n// we never import them.\nrepository = \"https://github.com/riantr/thing\"\nlicense = \"MIT\"\nimport {\n  \"moonbitlang/async@0.22.4\",\n}\n"
  let got = @sa.parse_moon_mod_imports(src)
  assert_eq(got.length(), 1)
  assert_eq(got[0], "moonbitlang/async@0.22.4")
}

///|
test "moon.mod: the module's own header never becomes a dependency" {
  // The exact shape that made 0.4.3 fetch itself: a comment containing
  // `import ` ahead of the real block.
  let src = "// module: riantr/x — we never import them.\n// another comment line.\nname = \"riantr/x\"\nimport {\n  \"moonbitlang/core/error\",\n}\n"
  let got = @sa.parse_moon_mod_imports(src)
  assert_eq(got.length(), 1)
  assert_eq(got[0], "moonbitlang/core/error")
  // and the module's own name is NOT among them
  for c in got {
    assert_false(c == "riantr/x")
  }
}

///|
test "moon.mod: a URL is not a coordinate" {
  // `https://…` was accepted before because it contains a `/`.
  let src = "import {\n  \"https://github.com/riantr/x\",\n  \"moonbitlang/async\",\n}\n"
  let got = @sa.parse_moon_mod_imports(src)
  assert_eq(got.length(), 1)
  assert_eq(got[0], "moonbitlang/async")
}

///|
test "moon.mod: several coordinates, deduped, block closed by }" {
  let src = "import {\n  \"a/b\",\n  \"c/d@1.2.3\",\n  \"a/b\",\n}\nversion = \"0.1.0\"\nimport {\n  \"e/f\",\n}\n"
  let got = @sa.parse_moon_mod_imports(src)
  assert_eq(got.length(), 3)
  assert_eq(got[0], "a/b")
  assert_eq(got[1], "c/d@1.2.3")
  // the value AFTER the block is not an import
  assert_eq(got[2], "e/f")
}

///|
test "moon.mod: a file with no import block yields nothing" {
  assert_eq(
    @sa.parse_moon_mod_imports("name = \"a/b\"\nversion = \"1.0.0\"\n").length(),
    0,
  )
  assert_eq(@sa.parse_moon_mod_imports("").length(), 0)
}

///|
test "is_module_coord accepts coordinates and rejects everything else" {
  assert_true(@sa.is_module_coord("a/b"))
  assert_true(@sa.is_module_coord("moonbitlang/core/error@0.1.2"))
  // more than two segments is a package inside a module, and `moon fetch`
  // accepts the shape (it reaches the registry lookup rather than rejecting
  // the name outright)
  assert_true(@sa.is_module_coord("a/b/c"))
  assert_true(@sa.is_module_coord("a/b/c/d"))
  // not coordinates
  assert_false(@sa.is_module_coord(""))
  assert_false(@sa.is_module_coord("b")) // one segment: rejected by moon fetch
  assert_false(@sa.is_module_coord("https://github.com/a/b"))
  assert_false(@sa.is_module_coord("README.md"))
  assert_false(@sa.is_module_coord("a//b")) // empty segment
  assert_false(@sa.is_module_coord("a/../b")) // traversal
  assert_false(@sa.is_module_coord("@0.1.2")) // version with no module
}

// --- the --mmd artifact name ----------------------------------------------
//
// The CLI writes the diagram under an auto-generated name, and that name is
// the only record of WHICH scan produced the file. Two failure modes make it
// lie, and both are silent: a name that omits the version is indistinguishable
// from one where the version was `0`, and two scans a minute apart collide.

///|
/// The negative control first: the label for the most ordinary invocation.
/// `scan .` hands back `.`, whose last segment is `.`, so a name built from it
/// would be `_.mmd` and would tell nobody anything.
test "artifact name: '.' resolves against the working directory, not to '_'" {
  let p = @sa.ScanProvenance::{
    target: ".",
    version: "0.4.5",
    scanned_at: "",
    moonbit: "0.1.20260920",
  }
  let name = @sa.scan_artifact_name(p, ".")
  assert_false(name.has_prefix("_"))
  assert_true(name.has_suffix(".mmd"))
}

///|
/// A coordinate names its own module, so the artifact says which module was
/// scanned even when the tree it landed in is someone else's. The whole
/// `owner/module` is kept, not just the leaf: `core` alone would not say
/// whether this was `moonbitlang/core` or a private `core`, and the slug exists
/// precisely because a coordinate is full of `/`.
test "artifact name: a coordinate contributes the module, not the path" {
  let p = @sa.ScanProvenance::{
    target: "moonbitlang/core@latest",
    version: "0.1.20260920",
    scanned_at: "20261009T051925Z",
    moonbit: "0.1.20260920",
  }
  assert_eq(
    @sa.scan_artifact_name(p, "some/local/path"),
    "moonbitlang-core_0.1.20260920_0.1.20260920_20261009T051925Z.mmd",
  )
}

///|
/// The four fields, in order: package, target version, toolchain, stamp. The
/// toolchain is a separate fact from the target's version and both are kept —
/// a scan is only reproducible against a known parser.
test "artifact name: all four fields appear in the agreed order" {
  let p = @sa.ScanProvenance::{
    target: "my_pkg",
    version: "1.2.3",
    scanned_at: "20261009T051925Z",
    moonbit: "9.9.9",
  }
  assert_eq(
    @sa.scan_artifact_name(p, "my_pkg"),
    "my_pkg_1.2.3_9.9.9_20261009T051925Z.mmd",
  )
}

///|
/// The missing-clock case. The segment must say `unknown` rather than vanish.
test "artifact name: an unavailable clock is written as 'unknown', not dropped" {
  let p = @sa.ScanProvenance::{
    target: "t",
    version: "1.0.0",
    scanned_at: "",
    moonbit: "0.1.20260920",
  }
  assert_eq(@sa.scan_artifact_name(p, "t"), "t_1.0.0_0.1.20260920_unknown.mmd")
}

///|
/// And the missing-version case, same reasoning.
test "artifact name: an unavailable version is written as 'unknown', not dropped" {
  let p = @sa.ScanProvenance::{
    target: "t",
    version: "",
    scanned_at: "20261009T051925Z",
    moonbit: "0.1.20260920",
  }
  assert_eq(
    @sa.scan_artifact_name(p, "t"),
    "t_unknown_0.1.20260920_20261009T051925Z.mmd",
  )
}

///|
/// The missing-TOOLCHAIN case, and the reason four fields are more fragile than
/// three. A dropped segment does not merely lose information, it SHIFTS: a
/// reader parsing `t_1.0.0_20261009T051925Z` would take the stamp for the
/// toolchain version. So this one says `unknown` in place, and the four
/// segments are still four.
test "artifact name: an unavailable toolchain says 'unknown' IN PLACE" {
  let p = @sa.ScanProvenance::{
    target: "t",
    version: "1.0.0",
    scanned_at: "20261009T051925Z",
    moonbit: "",
  }
  assert_eq(
    @sa.scan_artifact_name(p, "t"),
    "t_1.0.0_unknown_20261009T051925Z.mmd",
  )
}

///|
/// The negative control for the test above: four `unknown`-able fields must
/// still produce FOUR segments. A name that collapses them is the failure this
/// format is most exposed to.
test "artifact name: every field missing still yields four segments" {
  let p = @sa.ScanProvenance::{
    target: "t",
    version: "",
    scanned_at: "",
    moonbit: "",
  }
  assert_eq(@sa.scan_artifact_name(p, "t"), "t_unknown_unknown_unknown.mmd")
}

///|
/// Two scans of the same tree seconds apart must not overwrite each other. The
/// stamp is the only thing separating them, which is why it is `unknown` rather
/// than absent — two `unknown` names still collide, and that is visible, whereas
/// a missing segment would not be.
test "artifact name: the stamp separates two scans of the same tree" {
  let a = @sa.ScanProvenance::{
    target: "t",
    version: "1.0.0",
    scanned_at: "20261009T051925Z",
    moonbit: "0.1.20260920",
  }
  let b = @sa.ScanProvenance::{
    target: "t",
    version: "1.0.0",
    scanned_at: "20261009T051926Z",
    moonbit: "0.1.20260920",
  }
  assert_true(@sa.scan_artifact_name(a, "t") != @sa.scan_artifact_name(b, "t"))
}

///|
/// A minimal partial verdict with a chosen path and reason, for the tally
/// rules below. Findings stay empty because the tally reads only `parsed`,
/// `reason` and `path`; a partial file WITH pre-boundary findings is covered
/// by `v_partial_with_findings`.
fn v_partial_at(path : String, reason : String) -> @sa.Verdict {
  @sa.Verdict::{
    path,
    kind: ".mbt",
    findings: [],
    parsed: false,
    reason,
    total: 0,
    notices: 0,
    region_line: 1,
    unreliable: 0,
  }
}

///|
/// The count for a reason, with `-1` for "absent": `Option[Int]` has no Show,
/// so the tests compare Ints, and an absent reason must stay distinguishable
/// from a count of zero.
fn tally_count(reasons : Map[String, Int], r : String) -> Int {
  match reasons.get(r) {
    Some(x) => x
    None => -1
  }
}

///|
/// The rule the 0.4.7 loop got wrong: it tallied a partial file's reason only
/// when the file had no pre-boundary findings, so a file that yielded findings
/// before its first parse error — the file with the most evidence of partial
/// reading — never reached the NOTPARSE count. Here BOTH partial templates
/// contribute, and the parsed file contributes nothing.
test "tally: every partial file's reason is counted, parsed files add nothing" {
  let (reasons, _) = @sa.tally_partial_reasons([
    v_parsed(),
    v_partial_with_findings(),
    v_partial_empty(),
  ])
  assert_eq(tally_count(reasons, "first read failure at line 10"), 1)
  assert_eq(tally_count(reasons, "first read failure at line 1"), 1)
  assert_eq(tally_count(reasons, "unspecified"), -1)
}

///|
test "tally: a partial file with no reason is counted as unspecified" {
  let (reasons, _) = @sa.tally_partial_reasons([v_partial_at("d.mbt", "")])
  assert_eq(tally_count(reasons, "unspecified"), 1)
  assert_eq(tally_count(reasons, ""), -1)
}

///|
test "tally: the example list stops at three files" {
  let (_, examples) = @sa.tally_partial_reasons([
    v_partial_at("a.mbt", "match expression"),
    v_partial_at("b.mbt", "match expression"),
    v_partial_at("c.mbt", "match expression"),
    v_partial_at("d.mbt", "match expression"),
  ])
  let ex = match examples.get("match expression") {
    Some(a) => a
    None => []
  }
  assert_eq(ex.length(), 3)
  assert_eq(ex[0], "a.mbt")
  assert_eq(ex[1], "b.mbt")
  assert_eq(ex[2], "c.mbt")
}

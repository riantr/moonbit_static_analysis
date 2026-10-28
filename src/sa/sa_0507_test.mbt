// sa_0507_test.mbt -- the family PROFILE and the `nosec` suppression.
//
// 0507, transfer 2b and transfer 3 of the 0505 porting plan.
//
// THE PROFILE is a statement about which findings a reader trusts, stated in
// STABLE IDS rather than in names, and it is CHECKED before the scan runs:
// an id this version does not know is a WARNING (a family added in a later
// release must not make an older analyzer's profile unusable, and a typo must
// be loud rather than fatal), and an id that is BOTH included and excluded is
// an ERROR (the two rules contradict each other, so no reading of the profile
// satisfies both, and which one won would be decided by the order of two
// `if`s inside the scanner).
//
// THE `nosec` is a per-line, per-family suppression, and it is OFF BY DEFAULT.
// A tool that stops reporting a finding because of a comment in the ANALYSED
// source has an output the reader cannot trust without reading that source
// first. A `nosec` that suppresses NOTHING is reported as a finding of its
// own: a stale suppression is a fact about the source, and the source is
// what this tool analyses.
//
// NOTE ON WHERE THESE TESTS RUN. This package is `+wasm+native` (it needs the
// async runtime for file IO), so its tests run on the wasm target and are
// SKIPPED on js and wasm-gc. The mutation gate for them therefore pins
// `-Target wasm`.

///|
fn rep(family : @core.Family, line : Int32) -> @report.Report {
  @report.Report::{
    family,
    lenses: [@core.LStructural],
    message: "a finding on line \{line}",
    span: @core.span_at(line, 1, 1),
    vst: [],
  }
}

///|
fn profile(inc : Array[String], exc : Array[String]) -> @sa.Profile {
  @sa.Profile::{ include_ids: inc, exclude_ids: exc, honor_nosec: true, }
}

///|
/// The DEFAULT profile reports everything and honours nothing. This is the
/// state every other release has shipped in, and it is pinned so that a
/// change to the default has to be a deliberate one.
test "the default profile reports every family and honours no nosec" {
  let p = @sa.default_profile()
  assert_eq(p.include_ids.length(), 0)
  assert_eq(p.exclude_ids.length(), 0)
  assert_true(!p.honor_nosec)
  assert_true(@sa.profile_keeps(@core.FArgType, p))
  assert_true(@sa.profile_keeps(@core.FUndefinedName, p))
}

///|
/// An EMPTY include set filters nothing. A filter with nothing in it must
/// not be read as "report nothing", or `--families` with an empty value
/// would silence every finding.
test "an empty include set keeps every family" {
  let p = profile([], [])
  assert_true(@sa.profile_keeps(@core.FArgType, p))
  assert_true(@sa.profile_keeps(@core.FParse, p))
}

///|
/// The include set keeps ONLY the families it names, and the exclude set
/// drops the families it names.
test "the include set keeps only the named families" {
  let p = profile(["MSA-007"], [])
  assert_true(@sa.profile_keeps(@core.FArgType, p))
  assert_true(!@sa.profile_keeps(@core.FUndefinedName, p))
  assert_true(!@sa.profile_keeps(@core.FParse, p))
}

///|
test "the exclude set drops the named families" {
  let p = profile([], ["MSA-007"])
  assert_true(!@sa.profile_keeps(@core.FArgType, p))
  assert_true(@sa.profile_keeps(@core.FUndefinedName, p))
}

///|
/// The filter is applied to the WHOLE report list, and the result is the list
/// the trusted-region split then works on -- so `total`, `unreliable` and
/// `notices` all describe the same findings.
test "apply_profile removes the excluded families and keeps the rest" {
  let reports = [
    rep(@core.FArgType, 1),
    rep(@core.FUndefinedName, 2),
    rep(@core.FParse, 3),
  ]
  let kept = @sa.apply_profile(reports, profile([], ["MSA-002"]))
  assert_eq(kept.length(), 2)
  assert_true(kept[0].family == @core.FArgType)
  assert_true(kept[1].family == @core.FParse)
}

///|
/// An unknown id is a WARNING and the scan still runs. A family added in a
/// later release must not make an older analyzer's profile unusable.
test "an unknown family id is a warning, not an error" {
  let (warnings, err) = @sa.validate_profile(["MSA-999"], [])
  assert_eq(err, "")
  assert_eq(warnings.length(), 1)
  assert_true(warnings[0].contains("MSA-999"))
}

///|
/// An id that is BOTH included and excluded is an ERROR, and the scan does
/// not run at all.
test "an id that is both included and excluded is an error" {
  let (_, err) = @sa.validate_profile(["MSA-007"], ["MSA-007"])
  assert_true(err.contains("MSA-007"))
  assert_true(err.contains("includes and excludes"))
}

///|
/// A profile that includes and excludes DIFFERENT ids is fine, and says so
/// with no warning at all.
test "a profile with no overlap and no unknown id is silent" {
  let (warnings, err) = @sa.validate_profile(["MSA-007"], ["MSA-002"])
  assert_eq(err, "")
  assert_eq(warnings.length(), 0)
}

///|
/// A blanket `// nosec` silences every finding ON ITS LINE, and nothing on
/// any other line.
test "a blanket nosec silences every finding on its line" {
  let src = "let x = f(1) // nosec\nlet y = g(2)\n"
  let ns = @sa.parse_nosec(src)
  assert_eq(ns.length(), 1)
  assert_eq(ns[0].line, 1)
  assert_true(ns[0].blanket)
  let (kept, stale) = @sa.apply_nosec(
    [rep(@core.FArgType, 1), rep(@core.FArgType, 2)],
    ns,
  )
  assert_eq(kept.length(), 1)
  assert_eq(kept[0].span.start.line, 2)
  assert_eq(stale.length(), 0)
}

///|
/// A `// nosec MSA-007` silences that ONE family on its line, and the other
/// family on the same line is still reported.
test "a family nosec silences only that family on its line" {
  let src = "let x = f(1) // nosec MSA-007\nlet y = g(2)\n"
  let ns = @sa.parse_nosec(src)
  assert_eq(ns.length(), 1)
  assert_true(!ns[0].blanket)
  assert_eq(ns[0].ids.length(), 1)
  assert_eq(ns[0].ids[0], "MSA-007")
  let (kept, stale) = @sa.apply_nosec(
    [rep(@core.FArgType, 1), rep(@core.FUndefinedName, 1)],
    ns,
  )
  assert_eq(kept.length(), 1)
  assert_true(kept[0].family == @core.FUndefinedName)
  assert_eq(stale.length(), 0)
}

///|
/// A `nosec` that suppressed NOTHING is a finding of its own -- the
/// STALE-SUPPRESSION family, `MSA-012`. A suppression that has gone stale is
/// dead weight in the source, and it is a sign that the code it referred to
/// has changed.
test "a nosec that matched nothing is reported as a stale suppression" {
  let src = "let y = g(2) // nosec\n"
  let ns = @sa.parse_nosec(src)
  let (kept, stale) = @sa.apply_nosec([rep(@core.FArgType, 2)], ns)
  assert_eq(kept.length(), 1)
  assert_eq(stale.length(), 1)
  assert_true(stale[0].family == @core.FStaleNosec)
  assert_eq(stale[0].span.start.line, 1)
  assert_true(stale[0].message.contains("suppressed nothing"))
}

///|
/// A `nosec` naming an id that is NOT a family suppresses nothing, and is
/// therefore stale. This is the case where the user's intent is not
/// expressible -- and saying so is more useful than silence.
test "a nosec naming an unknown family is stale" {
  let src = "let x = f(1) // nosec MSA-999\n"
  let ns = @sa.parse_nosec(src)
  let (kept, stale) = @sa.apply_nosec([rep(@core.FArgType, 1)], ns)
  assert_eq(kept.length(), 1)
  assert_eq(stale.length(), 1)
  assert_true(stale[0].message.contains("MSA-999"))
  assert_true(stale[0].message.contains("not a family id"))
}

///|
/// THE STALE FINDING IS PRODUCED AFTER THE SUPPRESSION PASS, so a blanket
/// `// nosec` cannot silence the warning about its own staleness. That
/// ordering is the only thing that makes the warning useful.
test "a blanket nosec cannot suppress the warning about its own staleness" {
  let src = "let y = g(2) // nosec\n"
  let ns = @sa.parse_nosec(src)
  let (kept, stale) = @sa.apply_nosec([rep(@core.FArgType, 2)], ns)
  assert_eq(kept.length(), 1)
  assert_eq(stale.length(), 1)
}

///|
/// A comment that merely MENTIONS the word is not a nosec comment. A
/// suppression that can be switched on by mentioning the word is a
/// suppression that gets switched on by accident.
test "a comment that only mentions nosec is not a nosec comment" {
  let src = "let y = g(2) // this is not a nosec comment\n"
  assert_eq(@sa.parse_nosec(src).length(), 0)
  let src2 = "let y = g(2) // nosecurity\n"
  assert_eq(@sa.parse_nosec(src2).length(), 0)
}

///|
/// A `//` inside a string literal comes first, so the LAST `//` on the line
/// is the comment. A URL in a string does not hide a real nosec, and a
/// string that CONTAINS a nosec comment does not become one.
test "the last // on the line is the comment" {
  let src = "let u = \"http://x\" // nosec\n"
  assert_eq(@sa.parse_nosec(src).length(), 1)
  let src2 = "let s = \"// nosec\"\n"
  assert_eq(@sa.parse_nosec(src2).length(), 0)
}

///|
/// The nosec comment is on the line it silences, and the line number is
/// counted from ONE.
test "a nosec is counted on the line it is written on" {
  let src = "let a = 1\nlet b = 2\nlet x = f(1) // nosec\nlet c = 3\n"
  let ns = @sa.parse_nosec(src)
  assert_eq(ns.length(), 1)
  assert_eq(ns[0].line, 3)
}

///|
/// Two ids on one nosec comment silence both families.
test "a nosec may name more than one family" {
  let src = "let x = f(1) // nosec MSA-007 MSA-002\n"
  let ns = @sa.parse_nosec(src)
  assert_eq(ns.length(), 1)
  assert_eq(ns[0].ids.length(), 2)
  let (kept, stale) = @sa.apply_nosec(
    [rep(@core.FArgType, 1), rep(@core.FUndefinedName, 1)],
    ns,
  )
  assert_eq(kept.length(), 0)
  assert_eq(stale.length(), 0)
}

///|
/// A `nosec` with NO ids is the blanket form, and it silences everything on
/// its line -- including a notice. That is the rule, and it is the same rule
/// bandit has: a suppression silences what is on the line, and the stale
/// warning is what catches the case where there was nothing to silence.
test "a nosec with no ids is the blanket form" {
  let src = "let x = f(1) // nosec\n"
  let ns = @sa.parse_nosec(src)
  assert_true(ns[0].blanket)
  assert_eq(ns[0].ids.length(), 0)
  let (kept, stale) = @sa.apply_nosec([rep(@core.FParse, 1)], ns)
  assert_eq(kept.length(), 0)
  assert_eq(stale.length(), 0)
}

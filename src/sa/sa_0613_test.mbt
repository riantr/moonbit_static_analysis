// sa_0613_test.mbt -- THE `nosec` GRAMMAR, and the twelve false positives it
// had.
//
// THE DEFECT. `parse_nosec` took the LAST `//` on a line and read the text
// after it as a suppression whenever the first whitespace-separated token was
// exactly `nosec`. That is right for the case the rule was written for -- a
// `//` inside a string literal comes first, so the last one is the comment --
// and it is wrong in two more places, and BOTH of them are places where the
// text is not a comment at all:
//
//   * a `//` inside a `///` DOC COMMENT is text, and the text is usually the
//     DOCUMENTATION OF THIS SYNTAX;
//   * a `//` inside a STRING LITERAL is text too, and the old guard only
//     caught it when the quote landed on the MARKER (`"// nosec"` -> the token
//     is `nosec"`, which is not the marker). The moment the comment names a
//     family -- the form every real suppression uses -- the quote lands on the
//     ID instead, and the guard stops working.
//
// MEASURED 2026-11-19 on this repository's own source, with `--honor-nosec`:
// TWELVE actionable findings, and every one of them was this analyzer's own
// documentation or its own test fixtures. The invented family ids were
// English words: "MSA-007`, silences, that, one".
//
// THE FIX is two rules, and both of them are about PROSE:
//
//   1. a `///` line is never a nosec comment -- a `//` inside one is text;
//   2. a nosec comment names families by their ids and NOTHING ELSE, so a
//      token that is not an id is not part of the comment's grammar.
//
// THE BLAST RADIUS WAS MEASURED BEFORE THE CHANGE: the whole tree and the
// pinned corpora hold TWENTY-FOUR nosec-shaped comments, and every one of
// them is prose or a test fixture. There is not one real suppression
// anywhere, so the change removes twenty-four false positives and breaks
// nothing.
//
// NOTE ON WHERE THESE TESTS RUN. This package is `+wasm+native` (it needs the
// async runtime for file IO), so its tests run on the wasm target and are
// SKIPPED on js and wasm-gc.

///|
fn rep0613(family : @core.Family, line : Int32) -> @report.Report {
  @report.Report::{
    family,
    lenses: [@core.LStructural],
    message: "a finding on line \{line}",
    span: @core.span_at(line, 1, 1),
    vst: [],
  }
}

///|
/// THE STRING-LITERAL CASE, IN THE FORM EVERY REAL SUPPRESSION TAKES. The old
/// rule caught `"// nosec"` because the quote landed on the MARKER; the quote
/// lands on the ID when the comment names a family, and that is the form a
/// reader actually writes.
test "0613: a `// nosec` that names a family inside a string literal is not a suppression" {
  let src = "let s = \"// nosec MSA-007\"\n"
  assert_eq(@sa.parse_nosec(src).length(), 0)
}

///|
/// THE DOC-COMMENT CASE. The text after the last `//` is the DOCUMENTATION OF
/// THIS SYNTAX, and reading it as a suppression is reading the documentation
/// as a defect.
test "0613: a `// nosec` inside a doc comment is not a suppression" {
  let src = "/// the syntax is `// nosec MSA-007`\n"
  assert_eq(@sa.parse_nosec(src).length(), 0)
}

///|
/// AND THE DOC-COMMENT CASE WITH EVERY ID WELL-FORMED, because that is the
/// shape that the id rule alone does not catch: every token after the marker
/// IS an id, so only the `///` rule can tell it from a real suppression.
test "0613: a doc comment that names TWO families is not a suppression either" {
  let src = "///     // nosec MSA-007 MSA-002\n"
  assert_eq(@sa.parse_nosec(src).length(), 0)
}

///|
/// THE SHAPE AND THE ROSTER MUST AGREE, or a real suppression written against
/// a real id would stop working -- and the failure would be SILENT, because a
/// suppression that does not fire reports nothing. Every id the roster mints
/// is accepted here, and the assertion names the id so a failure says WHICH.
test "0613: every id the roster mints is accepted as a family id" {
  for id in @sa.family_ids() {
    let src = "let x = f(1) // nosec " + id + "\n"
    let ns = @sa.parse_nosec(src)
    let mut got = "the id " + id + " was not accepted as a family id"
    if ns.length() == 1 &&
      !ns[0].blanket &&
      ns[0].ids.length() == 1 &&
      ns[0].ids[0] == id {
      got = "OK"
    }
    assert_eq(got, "OK")
  }
}

///|
/// AND THE UNKNOWN-ID CASE IS NOT LOST. `MSA-999` has the SHAPE of a family id
/// and names no family, and 0507's row says such a suppression is STALE -- a
/// report, not a silence. If the rule were the LOOKUP rather than the SHAPE,
/// `MSA-999` would be indistinguishable from prose and the stale report would
/// disappear.
test "0613: an id that names no family is still a suppression, so it is still stale" {
  let src = "let x = f(1) // nosec MSA-999\n"
  let ns = @sa.parse_nosec(src)
  let (kept, stale) = @sa.apply_nosec([rep0613(@core.FArgType, 1)], ns)
  assert_eq(kept.length(), 1)
  assert_eq(stale.length(), 1)
  assert_true(stale[0].family == @core.FStaleNosec)
  assert_true(stale[0].message.contains("MSA-999"))
}

///|
/// THE BLANKET FORM IS UNTOUCHED. `// nosec` names no family, so the id rule
/// has nothing to say about it, and the rule that says "every family" still
/// says it.
test "0613: the blanket form is untouched" {
  let src = "let x = f(1) // nosec\n"
  let ns = @sa.parse_nosec(src)
  assert_eq(ns.length(), 1)
  assert_true(ns[0].blanket)
}

///|
/// AND THE CONTROL, because a rule that stopped EVERY suppression would pass
/// every row above for the wrong reason: a real `// nosec` on the line of a
/// finding still suppresses that finding.
test "0613: a real `// nosec` still suppresses the finding on its line" {
  let src = "let x = f(1) // nosec MSA-007\n"
  let ns = @sa.parse_nosec(src)
  let (kept, stale) = @sa.apply_nosec([rep0613(@core.FArgType, 1)], ns)
  assert_eq(kept.length(), 0)
  assert_eq(stale.length(), 0)
}

///|
/// AND THE END OF THE ROAD, which is the row that would have caught the
/// twelve: the prose that started this produces NO stale suppression, so the
/// analyzer says nothing at all about a line that only DOCUMENTS the syntax.
test "0613: a doc comment that documents the syntax produces no stale suppression" {
  let src = "/// the syntax is `// nosec MSA-007`\nlet x = f(1)\n"
  let ns = @sa.parse_nosec(src)
  let (kept, stale) = @sa.apply_nosec([rep0613(@core.FArgType, 2)], ns)
  assert_eq(kept.length(), 1)
  assert_eq(stale.length(), 0)
}

///|
/// AND THE OTHER END: a real suppression that has gone STALE is still
/// reported. The fix must not silence the warning that 0507 exists to raise.
test "0613: a stale suppression is still reported" {
  let src = "let y = g(2) // nosec\n"
  let ns = @sa.parse_nosec(src)
  let (kept, stale) = @sa.apply_nosec([rep0613(@core.FArgType, 2)], ns)
  assert_eq(kept.length(), 1)
  assert_eq(stale.length(), 1)
  assert_true(stale[0].family == @core.FStaleNosec)
  assert_true(stale[0].message.contains("suppressed nothing"))
}

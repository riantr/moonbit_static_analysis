// report_0500_test.mbt -- the NOTICE label, and the one definition of
// "declared scope limit".
//
// THE BUG THIS PINS. Every ParseError the tool rendered carried the label
// `error:`, including the ones that are not errors at all: "match expression is
// outside the analyzed subset; it was read but not analysed" is a DECLARED
// SCOPE LIMIT of this analyzer, and a reader who sees `error:` on it has been
// told their code is wrong when the analyzer is the one that did not read it.
//
// FParse is ONE family with TWO meanings, and they come from different
// producers:
//
//   deliberate  `Parser::note_skip` and `moonfiles`' subset skip
//   genuine    the lexer's eight malformed-literal reports, `moonfiles`' eight
//               malformed-interface reports, and the parser's `err()`
//
// So "is this a notice?" is not "is this FParse?" -- it is a question about
// WHICH KIND, and the answer lives in one place: `Report::is_notice`.
//
// MEASURED (2026-10-30), with the per-file printing cap lifted so the count is
// the whole finding set: across the seven corpora and this repository's own
// source, 23,331 rendered ParseError lines, every one of them a deliberate
// exclusion, and not one of the seventeen genuine-defect producers carrying
// the marker. On today's corpora the old predicate and the new one agree
// NUMERICALLY, which is why the change moves no count -- but only one of them
// is right.
//
// => 判据: a label that is wrong on every line it appears on is not a label, it
//    is noise with a severity attached. The tool already had the word for this
//    -- `notice` -- in its own counts, its mermaid legend and its skill file,
//    and the rendered line was the only place that did not use it.

///|
fn mk(family : @core.Family, message : String) -> @report.Report {
  @report.Report::{
    family,
    lenses: [@core.LStructural],
    message,
    span: @core.span_at(1, 1, 1),
    vst: [],
  }
}

///|
/// Every message a DELIBERATE exclusion can carry.
///
/// This is the list the parser's `note_skip` and `skip_msg` produce, plus the
/// literate frontend's fence skip. It is spelled out rather than derived,
/// because a list that is derived from the code under test proves only that
/// the code agrees with itself.
fn deliberate_messages() -> Array[String] {
  [
    "short lambda is outside the analyzed subset; it was read but not analysed",
    "loop expression is outside the analyzed subset; it was read but not analysed",
    "if expression is outside the analyzed subset; it was read but not analysed",
    "match expression is outside the analyzed subset; it was read but not analysed",
    "lexmatch expression is outside the analyzed subset; it was read but not analysed",
    "try expression is outside the analyzed subset; it was read but not analysed",
    "anonymous function literal is outside the analyzed subset; its parameters were read but the body was not analysed",
    "inclusive range end is outside the analyzed subset; it was read but the bound was not analysed",
    "descending range direction is outside the analyzed subset; it was read but the direction was not analysed",
    "the `async` of an `async fn` declaration is outside the analyzed subset; it was read past",
    "async without a following `fn` is outside the analyzed subset; it was read past",
    "test declaration is outside the analyzed subset; its body was not analyzed",
    "struct declaration is outside the analyzed subset; its body was not analyzed",
    "derive declaration is outside the analyzed subset", "block starts with 'match', outside the analyzer's MoonBit subset; skipped whole",
  ]
}

///|
/// Every message a GENUINE defect can carry.
///
/// The lexer's eight, `moonfiles`' eight, and a representative of the parser's
/// token-level read failures. None of these is the analyzer's own limit: each
/// one is something wrong with the file, and the reader deserves to be told so.
fn genuine_messages() -> Array[String] {
  [
    // the lexer: malformed literals and escapes
    "unterminated string literal", "unterminated regex literal", "unterminated character literal",
    "character literal has a malformed escape", "character literal is not a valid Unicode code point",
    "character literal must hold exactly one character", "unterminated block string literal (expected a line-leading `#|`)",
    "unexpected character '§'",
    // moonfiles: malformed interface and proof text
     "duplicate signature 'f' (redeclaration)", "malformed interface line (expected a signature or type declaration)",
    "unknown type 'T' in interface signature (not declared here, not builtin, not in any scanned interface)",
    "string constant in a logic body (only Int/Bool constants lower)", "banned form '↔' in logic (write one-directional '→' or an '== ... ==' equation)",
    "banned form '!' in logic (write '== false')", "cross-package call '@pkg.f' in a proof file (proof code stays in-package)",
    "lemma without proof_ensure (nothing to discharge)",
    // the parser: a read failure, whose reason is token-level
     "expected `)`",
  ]
}

///|
/// A declared scope limit is a notice. All of them, not just the common one.
test "every deliberate exclusion is a notice" {
  for m in deliberate_messages() {
    let rep = mk(@core.FParse, m)
    assert_true(rep.is_notice())
  }
}

///|
/// A genuine defect is not a notice, however much it looks like one. This is
/// the direction that would be a FALSE POSITIVE if it broke: a real defect
/// relabelled `notice:` stops being actionable and stops being counted, and
/// the reader is told their file is fine.
test "every genuine defect is NOT a notice" {
  for m in genuine_messages() {
    let rep = mk(@core.FParse, m)
    assert_false(rep.is_notice())
  }
}

///|
/// The marker is a CONVENTION, and a convention nobody checks is a comment.
/// Every deliberate message carries the word and no genuine one does -- which
/// is what makes `is_notice` a question with a decidable answer.
test "the marker separates the two kinds exactly" {
  for m in deliberate_messages() {
    assert_true(m.contains("subset"))
  }
  for m in genuine_messages() {
    assert_false(m.contains("subset"))
  }
}

///|
/// The family still matters. A message carrying the marker on a family that is
/// not FParse is a normal defect, not a notice: the marker says WHAT the
/// message is about, and the family says WHICH kind of finding it is.
test "the marker alone does not make a notice" {
  let rep = mk(
    @core.FUndefinedName,
    "no visible binding for 'x' (outside the analyzed subset)",
  )
  assert_false(rep.is_notice())
}

///|
/// A notice is rendered `notice:` and a defect is rendered `error:`. The two
/// labels are different strings, so a reader -- or a grep -- can tell them
/// apart without knowing the tool's internals.
test "the rendered label is notice for a notice and error for a defect" {
  let n = mk(
    @core.FParse,
    "match expression is outside the analyzed subset; it was read but not analysed",
  )
  assert_eq(n.severity_label(), "notice")
  assert_true(n.render().contains(" - notice: "))
  assert_false(n.render().contains(" - error: "))

  let d = mk(@core.FUndefinedName, "no visible binding for 'x'")
  assert_eq(d.severity_label(), "error")
  assert_true(d.render().contains(" - error: "))
  assert_false(d.render().contains(" - notice: "))
}

///|
/// The other severities are untouched. A warning is a warning whatever the
/// message says.
///
/// AND A FACT THIS TEST DISCOVERED WHILE WRITING IT: no family maps to `Hint`
/// at all. `Family::severity` returns Error or Warning for each of the eleven
/// families, so the `Severity::Hint` variant exists in the model and nothing
/// produces it. That is not this increment's business to change -- the
/// taxonomy is a PROVED predicate over `Family` in `src/core/core_proof.mbtp`,
/// and a rendering change is not a reason to move a proof subject -- but it is
/// exactly the kind of thing a test that only checked the labels it cared
/// about would have kept to itself, so it is written down here.
test "the warning label is unchanged" {
  let w = mk(
    @core.FUnusedLocal,
    "local variable 'x' assigned but may not be used",
  )
  assert_eq(w.severity_label(), "warning")
  assert_true(w.render().contains(" - warning: "))
}

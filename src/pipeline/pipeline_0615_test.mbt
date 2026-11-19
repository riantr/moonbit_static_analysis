// Tests for 0615 -- `lexscan`, the lexical scan, and the arms it carries.
//
// THE FINDING THIS REMOVES. `lexscan <subject> [with <strategy>] { arms }` is
// MoonBit's STREAMING regex-lexer form of a match; the subject is a SCANNER
// and the arms are patterns whose first element is a REGEX LITERAL:
//
//     lexscan self {
//       (re"^[^\n]*" as line) + re"\r\n" => Some(line)
//       _ => None
//     }
//
// Reading `lexscan` as an ordinary NAME produced `undefined variable
// 'lexscan'` -- a false positive on code `moon check` accepts. MEASURED on the
// re-pinned corpus (`moonbitlang/core` `0.1.20261117+06da1ed44`), three sites,
// and every one of them in ORDINARY CODE rather than in a test body:
//
//     lexbuf/read_line.mbt:37
//     lexbuf/read_line_test.mbt:53
//     lexbuf/async_read_line_test.mbt:29
//
// This is the END-TO-END claim: the parser rows in
// `src/parser/parser_0615_test.mbt` assert the NODE, and this one asserts the
// FINDING, because the finding is what a user sees and the node is not.
//
// WHY THE OLD CORPUS NEVER SHOWED IT. The old corpus used `lexscan` in six
// files, and every one of those uses was in a place the analyzer never reads --
// a `test` body, or a doc comment. The construct was in the corpus the whole
// time and in no analysed code at all.

///|
/// The corpus's own shape of the construct: a `lexscan` whose arm pattern
/// BINDS a name with `as` and whose arm body READS that name. A reader that
/// read the arms but did not bind the pattern's name would report `line` as
/// unbound -- which is the same class of defect as the one this increment
/// removes, one step further in.
fn lexscan_pipeline_src() -> String {
  "fn f(self : String) -> String? {\n  lexscan self {\n    (re\"^[^\\n]*\" as line) + re\"\\r\\n\" => Some(line)\n    _ => None\n  }\n}\nlet out : String? = f(\"a\")\n"
}

///|
/// THE FIXTURE IS THE CORPUS SHAPE, and the claim is that the name is not
/// reported. The source is the corpus's own lines -- `lexscan` with a regex
/// arm that binds `line` and a body that reads it -- so a reader that only
/// handled the bare `lexscan s { re"^a" => 1 }` spelling would pass this row
/// and the corpus would not.
test "0615: a lexscan is not an undefined variable" {
  let r = @pipeline.run(
    lexscan_pipeline_src(),
    "lexscan.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CONTROL THAT MAKES THE ROW ABOVE MEANINGFUL, and it is the same
/// control shape every UndefinedName row in this repository uses: a name that
/// genuinely does not exist must still be reported. Without it the row above
/// would pass because the fixture never runs.
test "0615: a name that does not exist is still reported (control)" {
  let r = @pipeline.run(
    "fn f(self : String) -> String? {\n  lexscan self {\n    (re\"^[^\\n]*\" as line) + re\"\\r\\n\" => Some(line)\n    _ => None\n  }\n}\nlet out : String? = f(ZzMissing)\n",
    "lexscan.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE CONSTRUCT IS NOT SILENTLY ACCEPTED EITHER. The arms are READ, so
/// there is nothing to announce -- and a reader that had skipped the arms
/// would be announcing it. The row asserts the ABSENCE of the notice, which is
/// the claim the arms being read makes.
///
/// The row is here because the notice is the only place the difference between
/// "read" and "read but not analysed" is visible: the FINDING is the same
/// either way, so a reader that consumed the whole construct and said nothing
/// would satisfy the row above.
test "0615: a lexscan says nothing about its arms" {
  let r = @pipeline.run(
    lexscan_pipeline_src(),
    "lexscan.mbt",
    @core.IfaceSymTab::empty(),
  )
  let mut said = false
  for rep in r.reports {
    if rep.message.contains("lexscan expression is outside the analyzed subset") {
      said = true
    }
  }
  assert_true(!said)
}

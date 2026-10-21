// Tests for 0496 -- `lexmatch`, the lexical match, and the LABELLED CAPTURE it
// carries.
//
// THE FINDING THIS REMOVES. `lexmatch <subject> [with longest] { arms }` is
// MoonBit's regex-lexer form of a match; its arms are patterns whose first
// element is a REGEX LITERAL and whose second is the LABELLED `after=` binding
// that names the input AFTER the match:
//
//     lexmatch rest with longest {
//       (re"^//+" as t, after=next) => { ...; next }
//       (re"^[A-Za-z_][A-Za-z0-9_]*" as t, after=next) => { ...; next }
//       _ => abort("unreachable")
//     }
//
// Reading `lexmatch` as an ordinary NAME produced `undefined name
// 'lexmatch'` -- a false positive on code `moon check` accepts. Four sites in
// the PINNED corpus `moonbitlang/core`:
//
//     internal/strconv/strconv_int.mbt:174
//     diff/diff_align_test.mbt:56 and :94
//     diff/diff_word_test.mbt:33
//
// This is the END-TO-END claim: the parser rows in
// `src/parser/parser_0496_test.mbt` assert the NODE, and this one asserts the
// FINDING, because the finding is what a user sees and the node is not.
//
// THE SCOPE IS MEASURED, NOT INHERITED. The standing note said "18 sites in 3
// PINNED core files", and a grep for `after=` gives 283 lines in 22 files --
// but a grep counts LOCAL VARIABLES and COMMENTS too: moui's 13 hits are
// `let after = ...`, `receipt.after` and `// after = 83*46 - 2`, and labeler's
// two are a `let after` and a doc comment. The real construct is 84 sites in
// FIVE pinned `moonbitlang/core` files and ZERO in the other six pinned
// corpora.

///|
/// THE FIXTURE IS THE CORPUS SHAPE, and the claim is that the name is not
/// reported. The source is the corpus's own line -- `lexmatch` with the
/// `with longest` clause and a `lexmatch` arm -- so a reader that only
/// handled the bare `lexmatch s { .. }` spelling would pass this row and the
/// corpus would not.
test "0496: a lexmatch is not an undefined name" {
  let r = @pipeline.run(
    "fn f(s : String) -> String {\n  lexmatch s with longest {\n    (re\"^a\" as t, after=next) => next\n    _ => s\n  }\n}\nlet out : String = f(\"a\")\n",
    "lexmatch.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CONTROL THAT MAKES THE ROW ABOVE MEANINGFUL, and it is the same
/// control shape every UndefinedName row in this repository uses: a name that
/// genuinely does not exist must still be reported. Without it the row above
/// would pass because the fixture never runs.
test "0496: a name that does not exist is still reported (control)" {
  let r = @pipeline.run(
    "fn f(s : String) -> String {\n  lexmatch s with longest {\n    (re\"^a\" as t, after=next) => next\n    _ => s\n  }\n}\nlet out : String = f(ZzMissing)\n",
    "lexmatch.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE LEXMATCH IS NOT SILENTLY ACCEPTED EITHER. The subset has no arm
/// patterns, so the construct is read but not analysed, and that has to be
/// SAID: a reader that consumed the whole thing and said nothing would
/// satisfy the row above and hide the fact that the arms were never analysed.
///
/// The row asserts the notice by its text, because the corpus's own files
/// carry other notices and the count alone would count those too.
test "0496: a lexmatch says that its arms were not analysed" {
  let r = @pipeline.run(
    "fn f(s : String) -> String {\n  lexmatch s with longest {\n    (re\"^a\" as t, after=next) => next\n    _ => s\n  }\n}\nlet out : String = f(\"a\")\n",
    "lexmatch.mbt",
    @core.IfaceSymTab::empty(),
  )
  let mut said = false
  for rep in r.reports {
    if rep.message.contains(
        "lexmatch expression is outside the analyzed subset",
      ) {
      said = true
    }
  }
  assert_true(said)
}

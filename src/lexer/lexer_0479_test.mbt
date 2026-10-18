///|
/// 0479 -- U+FEFF, the BYTE-ORDER MARK, is skipped rather than refused.
///
/// `_verify/corpus_backlog.ps1` reported one `unexpected character '<U+FEFF>'` and it names
/// exactly one file: `riantr/moonbit_labeler/0.2.13/app_moui/labeler_ui_test.mbt`, whose
/// first three bytes are EF BB BF. Before this change the mark reached `lex_op`'s catch-all,
/// so the lexer reported a character the toolchain does not object to and the file's whole
/// analysis was withheld.
///
/// Settled before implementing (`_verify/settle_0479_bom.ps1`, 3 controls + 5 rows, GATE OK):
///
///   ACCEPT  the corpus's first three lines, byte for byte including the mark
///   ACCEPT  a mark before a declaration / before a `///|` / on an empty file
///   ACCEPT  a mark MIDFILE           `1 <mark> + 2` is `1 + 2`
///   ACCEPT  a mark inside a string literal
///
/// S4 is the row that decides the SIZE of the change and it ACCEPTs, so this is not a
/// three-byte preamble strip: it is a character the lexer skips wherever it appears. The
/// first version of the guard would have passed the corpus file and failed every other
/// file a mark turns up in, which is a fix verified by its own symptom.
///
/// The fixture is built from `\u{FEFF}` rather than pasted as bytes, so the test file stays
/// ASCII and the mark cannot be silently normalised away by an editor or a diff.
test "0479: a byte-order mark before code is skipped" {
  let (toks, _, reports) = @lexer.lex("\u{FEFF}///|\nfn f() -> Int {\n  1\n}\n")
  assert_eq(reports.length(), 0)
  assert_true(toks.length() > 1)
}

///|
/// MIDFILE, and this is the row the whole increment turns on. A preamble-only fix passes
/// the control above and this one, which is exactly how a narrow fix survives review: it
/// fixes the file that was reported and nothing else. `moon check` accepts the mark here
/// (settle S4), so refusing it would be a false refusal of a legal program.
test "0479: a byte-order mark inside an expression is skipped (control)" {
  let (toks, _, reports) = @lexer.lex("1 \u{FEFF} + 2")
  assert_eq(reports.length(), 0)
  // The mark is gone from the stream, so the tokens are `1`, `+`, `2` and the TEOF that
  // `lex` always appends (lexer.mbt:193). A preamble-only fix would leave the mark
  // mid-expression, and the stream would carry a fourth real token or a report; asserting
  // the COUNT is what makes that difference visible rather than assumed.
  assert_eq(toks.length(), 4)
  match toks[0] {
    @lexer.TInt(1) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
/// AND THE ROW THAT KEEPS THE SKIP FROM REACHING INTO A STRING. `run` dispatches to
/// `lex_string` on `"` and that reader consumes the whole literal, so a mark inside one is
/// never offered to the skip. Asserting the payload LENGTH is what pins that: if the skip
/// ever moved inside `lex_string`, or if `lex_string` delegated to the same loop, the value
/// would lose a character and every program comparing that string would silently disagree
/// with the compiler. Nothing else in this file would notice.
test "0479: a mark inside a string is content, not whitespace" {
  let (toks, _, reports) = @lexer.lex("\"a\u{FEFF}b\"")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s.length(), 3)
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL FOR THE WHOLE THING: the skip is a WIDENING of what the lexer tolerates, and
/// the only way to know it did not widen too far is a row where a character it must still
/// refuse is refused. The settle licenses EXACTLY ONE character, so the nearest miss to it
/// is the right probe -- U+FFFE, the code point immediately before U+FEFF in Unicode. A guard
/// written as a range, or one that reached for "the other byte-order mark", swallows it, and
/// that is the failure this row exists to catch. `\u{FFFF}` is not used: it is not adjacent
/// to anything the change touches, so it would pass against a guard that widened to a whole
/// block.
test "0479: the character beside the mark is still refused (control)" {
  let (_, _, reports) = @lexer.lex("\u{FFFE}")
  assert_eq(reports.length(), 1)
}

///|
/// A MARK INSIDE A COMMENT, which is where the corpus file actually carries it -- the first
/// line of `labeler_ui_test.mbt` is `//` immediately followed by the mark. It is worth its
/// own row because the comment branch consumes to end-of-line in its own loop rather than
/// through the token loop, so "skip U+FEFF like whitespace" and "skip U+FEFF inside
/// comments" are two different code paths that happen to agree today.
test "0479: a mark inside a comment is skipped" {
  // The comment ALONE, so the assertion is about this construct and not about what happens
  // to follow it. A whole-line comment emits nothing, so the only token can be the TEOF that
  // `lex` appends: the comment contributed nothing and the mark inside it contributed
  // nothing. If the mark ever escaped as a token this would be a stream of two.
  let (toks, _, reports) = @lexer.lex("//\u{FEFF} heading")
  assert_eq(reports.length(), 0)
  assert_eq(toks.length(), 1)
  match toks[0] {
    @lexer.TEOF => assert_true(true)
    _ => assert_true(false)
  }
}

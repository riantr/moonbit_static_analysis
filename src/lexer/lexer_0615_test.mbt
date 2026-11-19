///|
/// 0615 -- `lexscan` IS SYNTAX, NOT A NAME.
///
/// `lexscan <subject> [with <strategy>] { arms }` is MoonBit's streaming
/// regex-lexer form of a match, and reading it as an identifier produced
/// `undefined variable 'lexscan'` at three sites in the re-pinned corpus
/// (`moonbitlang/core` `0.1.20261117+06da1ed44`): `lexbuf/read_line.mbt:37`,
/// `lexbuf/read_line_test.mbt:53` and `lexbuf/async_read_line_test.mbt:29` --
/// on code `moon check` accepts.
///
/// The keyword list is the one place that answers "is this a name to resolve?",
/// so it has to carry `lexscan` for the same reason it carries `lexmatch`
/// (0496). The parser has a production for the construct; this list says the
/// same thing to the places that ask whether a word is a binding.

///|
/// THE WORD IS A KEYWORD. The row is the whole claim, and it is the claim the
/// false positive rested on: `lexscan` is not a binding, so resolving it as
/// one is what produced `undefined variable 'lexscan'`.
test "0615: lexscan is a keyword" {
  assert_true(@lexer.is_moonbit_keyword("lexscan"))
}

///|
/// AND THE CONTROL: a word that is NOT syntax is still not a keyword. The
/// row is here because a list that returned `true` for everything would
/// satisfy the row above.
test "0615: a name that is not syntax is not a keyword (control)" {
  assert_true(!@lexer.is_moonbit_keyword("lexscanner"))
  assert_true(!@lexer.is_moonbit_keyword("scan"))
}

///|
/// AND `lexmatch` IS STILL A KEYWORD. The two are siblings -- MoonBit's
/// non-streaming and streaming lexical matches -- and the increment that
/// learned the second must not have cost the first its place.
test "0615: lexmatch is still a keyword (control)" {
  assert_true(@lexer.is_moonbit_keyword("lexmatch"))
}

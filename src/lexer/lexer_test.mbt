///|
/// Lexer-level tests for the block-string closer.
///
/// The closer rule was measured against the toolchain rather than assumed,
/// because the previous rule (`|#`) appears in no real code and so reported
/// "unterminated block string" on anything containing a block string.
///
/// Note what these tests are NOT: they are not a response to a self-scan
/// complaint about src/samples/samples.mbt. That file has 107 `#|` markers, an
/// odd count, so its last one really does run to end of input and the report is
/// true. The rule was wrong on the five measured counts below, not because of
/// that report.
///
/// Measured with `moon run`:
///   #|AAA\n#|BBB          -> "AAA\nBBB"           closed, rest of line is content
///   #|AAA\n  #|BBB       -> "AAA\nBBB"           the closer may be indented
///   #|AAA\n#|BBB trailing -> "AAA\nBBB trailing"
///   #|one #|two\n#|three   -> "one #|two\nthree"  a mid-line `#|` is content
///   #|AAA\n|#BBB           -> not closed          `|#` is content
///   #|AAA\n#|BBB\nCCC      -> "AAA\nBBB", and CCC is then parsed as CODE

///|
test "block string closes on a line-leading #| and ends at that line" {
  let (toks, _, reports) = @lexer.lex(
    "fn f() -> int {\n  let s = #|AAA\n#|BBB\n  1\n}\n",
  )
  assert_eq(reports.length(), 0)
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s) => if s.contains("AAA") { v = s }
      _ => ()
    }
  }
  assert_eq(v, "AAA\nBBB")
}

///|
/// The `\n` after the closing `#|` belongs to the code, not to the string, and
/// the lines after it keep counting from where the block ended.
test "block string value and line counter" {
  let (toks, spans, reports) = @lexer.lex(
    "fn f() -> int {\n  let s = #|AAA\nBB\n#|\n  1\n}\n",
  )
  assert_eq(reports.length(), 0)
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s) => if s.contains("AAA") { v = s }
      _ => ()
    }
  }
  assert_eq(v, "AAA\nBB\n")
  assert_eq(spans.length(), toks.length())
}

///|
/// `|#` does not close, so the block runs to end of input and is reported.
test "|# does not close a block string" {
  let (_, _, reports) = @lexer.lex("fn f() -> int {\n  let s = #|AAA\n  1\n}\n")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("unterminated block string"))
}

///|
/// A mid-line `#|` is ordinary content; only a line-leading one closes.
test "a mid-line #| does not close" {
  let (toks, _, _) = @lexer.lex("let s = #|one #|two\n#|three\n")
  let mut v = ""
  for t in toks {
    match t {
      TStr(s) => v = s
      _ => ()
    }
  }
  assert_eq(v, "one #|two\nthree")
}

///|
/// Literal escapes: the single-quoted byte literal `b'..'` and the `\xNN` /
/// `\u{...}` escapes inside a character literal.
///
/// WHY THIS EXISTS. After 0458, wzzc-dev/moui was at 608/608 and the largest
/// remaining blocker across all six corpora was, by files actually unblocked:
///
///     46x  character literal must hold exactly one character
///          (28 async, 9 image, 5 labeler, 4 proton)
///
/// ONE message, TWO defects of very different sizes, and only probing told them
/// apart -- five one-line programs run through the scanner itself:
///
///     let x = '\u{0}'     -> the error
///     let x = b'\x00'     -> the error
///     let x = '\\'        -> clean
///     let x = '\n'        -> clean
///     let x = 'ab'        -> the error (correct)
///
/// The file counts behind them: `b'\x..'` in 58 files (async 32, image 15,
/// labeler 6, proton 5), `'\u{..}'` in 19.
///
/// THE FIRST DEFECT IS A SINGLE CHARACTER. `lexer.mbt` had a byte-string branch,
/// and it tested the character AFTER the `b` against a DOUBLE quote only. The
/// corpus writes the single-quoted form, so `b` lexed as an identifier and the
/// `'\x00'` that followed became a character literal four characters long.
///
/// THEY ARE NOT TWO SPELLINGS OF ONE THING, which is the part worth pinning:
/// `b"\x00"` is a `Bytes` string and `b'\x00'` is a single `Byte`. Settled,
/// `_verify/settle_0459_literal_escapes.ps1` 8/8. So they take different readers,
/// and the single-quoted one goes to `lex_char` -- the reader whose length check
/// rejects `b'ab'` the way the toolchain does.
///
/// => 判据: a blocker MESSAGE is not a construct. "46 files are blocked on
/// character literals" was a true statement and a useless one: the two gaps it
/// covered differed in size by 3x, in file, and in the reader that fixes them.
test "0459: a single-quoted byte literal with a hex escape is one token" {
  let (toks, _, reports) = @lexer.lex("b'\\x00'")
  assert_eq(reports.length(), 0)
  // `lex` appends a trailing TEOF, so a one-token program yields TWO entries.
  assert_eq(toks.length(), 2)
}

///|
/// AND IT IS ONE CHARACTER, not the three the escape spells out. This is the
/// assertion that separates a real decode from "the backslash was dropped and
/// the digits passed through" -- which is what the pre-fix lexer produced, and
/// what the length check then rejected.
test "0459: the hex escape decodes to a single character" {
  let (toks, _, _) = @lexer.lex("b'\\x00'")
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s.length(), 1)
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL THAT STILL FAILS. A single-quoted byte literal holds exactly one
/// byte -- `b'ab'` is REJECT(3001) against the toolchain -- so the payload must
/// still be reported. Without this row, "the byte literal parses" could be a
/// fact about the length check having been removed rather than about the reader
/// being right.
test "0459: a two-character byte literal is still reported (control)" {
  let (_, _, reports) = @lexer.lex("b'ab'")
  assert_eq(reports.length(), 1)
  assert_true(
    reports[0].message.contains(
      "character literal must hold exactly one character",
    ),
  )
}

///|
/// THE UNICODE ESCAPE, whose payload is a braced code point rather than a digit
/// pair. `'\u{0}'` is the form the corpus writes (NUL sentinels, 19 files).
///
/// The payload assertion is on the NUL form and deliberately NOT on
/// `'\u{1F600}'`, even though the settle accepts that beside it. Asserting the
/// length of a four-byte character through this token is a question about how the
/// string builder measures astral characters, not about whether the escape was
/// recognised -- and a test that mixes the two reports the wrong failure when it
/// goes red. `settle_0459` is the authority that the wide form is legal.
test "0459: a braced unicode escape is one character" {
  let (toks, _, reports) = @lexer.lex("'\\u{0}'")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s.length(), 1)
    _ => assert_true(false)
  }
}

///|
/// AND THE CONTROL FOR THAT ROW: a genuinely two-character literal is still a
/// two-character literal. `\u` is an escape the lexer now understands, and the
/// row above only means something if unrecognised escapes did not become a way to
/// smuggle multi-character payloads past the length check.
test "0459: a real two-character literal is still two (control)" {
  let (_, _, reports) = @lexer.lex("'ab'")
  assert_eq(reports.length(), 1)
}

///|
/// THE ESCAPES THAT ALREADY WORKED, kept because the new branch sits above them.
/// `\n`, `\\` and `\'` each map to one character and must not have been disturbed
/// by a hex decoder that consumes digits after a backslash.
test "0459: the pre-existing escapes still map to one character" {
  let (esc, _, r1) = @lexer.lex("'\\n'")
  assert_eq(r1.length(), 0)
  let (bs, _, r2) = @lexer.lex("'\\\\'")
  assert_eq(r2.length(), 0)
  let (q, _, r3) = @lexer.lex("'\\''")
  assert_eq(r3.length(), 0)
  assert_eq(esc.length(), 2)
  assert_eq(bs.length(), 2)
  assert_eq(q.length(), 2)
}

///|
/// AND THE REGRESSION CONTROL for the branch that made this work: the double-quoted
/// byte STRING still goes to `lex_string`, not to `lex_char`. The single character
/// that made this increment work was the `'"'` in that condition, so a "harmless"
/// widening of it to accept `'` inside `lex_string` would silently turn every
/// byte string into a one-character literal.
test "0459: the double-quoted byte string is still one token, not one byte" {
  let (toks, _, reports) = @lexer.lex("b\"\\x00\\x01\\x02\"")
  assert_eq(reports.length(), 0)
  // NOT `1`: routing this through `lex_char` is precisely the mistake this row
  // rules out, and `lex_char` is the reader that REPORTS a long payload --
  // `lex_string` passes `\x` through undecoded, so the payload is the
  // nine-character spelling `x00x01x02`. That is pre-existing behaviour on a
  // path 0459 did not touch, and nothing downstream reads a byte string's
  // contents; asserting three bytes would be asserting a fix never made.
  assert_eq(toks.length(), 2)
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s.length(), 9)
    _ => assert_true(false)
  }
}

///|
/// AND AN IDENTIFIER THAT MERELY STARTS WITH `b` IS STILL AN IDENTIFIER. The
/// branch tests the character AFTER the `b`, and `box` / `b2` are exactly what that
/// guard is for -- without it `b2` would try to lex a string and read to
/// end-of-file. Widening that condition, which is what 0459 did to reach `b'`, is
/// the change most likely to break this row later.
test "0459: a name starting with b is still one name (control)" {
  let (toks, _, _) = @lexer.lex("box b2 b")
  assert_eq(toks.length(), 4)
}

///|
/// AND THE DECODED CHARACTER IS THE RIGHT ONE, which is the assertion every other
/// row in this file was missing.
///
/// They all assert a LENGTH or a token count, and a decoder that returns the wrong
/// single character passes every one of them: `b'\x41'` decoded to `!` would still
/// be one token, one character, zero reports. That is not hypothetical. Mutation
/// M5 in `_verify/mutate_0459.ps1` changes the not-a-hex-digit sentinel from -1 to
/// 0 -- and 0 is the DIGIT ZERO, so it can no longer terminate the digit loop. That
/// corrupts exactly the VALUE and leaves every length here unchanged; it was killed
/// only because the over-consumption happened to change a token count somewhere
/// else in the suite. A guard that a wrong-but-well-formed answer walks past is not
/// a guard.
///
/// Printable code points on purpose. NUL is what the corpus writes and `b'\x00'` is
/// the shape that mattered, but asserting against a NUL payload measures whether
/// the harness can compare a NUL -- a different question from whether the decoder
/// produced the right character.
test "0459: the hex escape decodes to the RIGHT character, not merely one of them" {
  let (toks, _, _) = @lexer.lex("b'\\x41'")
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s, "A")
    _ => assert_true(false)
  }
}

///|
/// AND THE BRACED FORM DECODES TO THE RIGHT CHARACTER TOO, because it is a
/// different loop -- it steps over the `{` first and accepts any number of digits,
/// so a decoder that got the two-digit form right could still be wrong here.
test "0459: the braced escape decodes to the RIGHT character too" {
  let (toks, _, _) = @lexer.lex("'\\u{41}'")
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s, "A")
    _ => assert_true(false)
  }
}

///|
/// AND THE CONTROL that keeps the two rows above honest: a literal with NO escape
/// decodes to itself. So "the payload equals A" is about the ESCAPE rather than
/// about the assertion accepting whatever it is handed.
test "0459: a literal with no escape decodes to itself (control)" {
  let (toks, _, _) = @lexer.lex("'B'")
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s, "B")
    _ => assert_true(false)
  }
}

///|
/// Newline suppression after the BITWISE-OR token, and the or-pattern token it
/// shares an identity with.
///
/// WHY THIS EXISTS. `newline_suppressed_after` decides which tokens let an expression
/// continue across a line break. It listed `TPlus`, `TAmp`, `TCaret`, `TAndAnd`,
/// `TOrOr`, `TShl`, `TShr` and every comparison operator -- and did NOT list `TBar`.
/// So the lexer emitted `TNewline` after `|`, `parse_bitor` bumped the `|` correctly,
/// and the operand parse landed on `TNewline` and `parse_primary` raised
/// "unexpected end of line" (parser.mbt:4664).
///
/// THE DEFECT WAS INVISIBLE IN THE LEXER ALONE, which is why it survived: `a +\n b`
/// and `a &\n b` both parse, because those tokens were already in the set. Only the
/// one-character `|` was missing. A sweep for "trailing binary operators" finds 178
/// corpus files and 2296 sites and proves nothing, because every operator except this
/// one already continues correctly.
///
/// WHY `TBar` WAS THOUGHT NOT TO BELONG. Its declaration comment claimed "the parser
/// never sees one -- match bodies are skipped whole". That was true when written and
/// stopped being true when `parse_bitor` was added (parser.mbt:3134), which consumes
/// `TBar` and builds `EBin(OpBitOr, ...)`. A stale comment about a token is enough to
/// keep that token out of the set it belongs in, so the comment is now corrected at
/// the declaration and at the set itself.
///
/// THE RISK THIS HAS TO RULE OUT. `|` is ALSO the or-pattern separator inside match
/// arms (`SAssign(_) | SLet(_) => ...`). Suppressing the newline AFTER `TBar` drops
/// the `TNewline` TOKEN only -- `TBar` itself still reaches the stream -- and match
/// bodies are skipped whole, so no pattern parser can be confused by the missing line
/// break. `or-pattern survives suppression` pins that by lexing a real or-pattern.
///
/// THESE ASSERT ON TOKENS, NOT ON THE SET. `newline_suppressed_after` is private
/// (4021 from the test file), and widening production visibility so a test could
/// reach it would change the module's surface for a test's convenience. The rule it
/// implements is fully observable at the token level anyway, which is where every
/// other lexer test lives -- and the controls below would have caught a function
/// returning `true` for everything regardless.
///
/// THE SIGNATURES ARE QUALIFIED, `@lexer.Tok` and not `Tok`, and that is not style.
/// A bare `Tok` in a test is an implicit import, which `moon check --deny-warn`
/// reports as Error [0025] `test_unqualified_package`. The first version of this file
/// used `Array[Tok]` and `moon test --target js` reported 632/632 GREEN -- because
/// plain `moon test` does not deny warnings, while the release gate runs every target
/// with `--deny-warn`. An ad-hoc test run and the gate are not the same check, and the
/// difference is invisible until one of them is the stricter one.
///
/// Settled, with a positive control, in `_verify/settle_0455_paren_if.ps1` (20/20).
/// Corpus: moui 0.1.12 parsed 605 -> 606, `unexpected end of line` now 0 occurrences
/// across all six corpora, and a pre/post per-file comparison found ZERO files read
/// less -- one newly complete, one read further, the rest unchanged.

///|
fn count_newlines(toks : Array[@lexer.Tok]) -> Int32 {
  let mut n = 0
  for t in toks {
    match t {
      TNewline => n += 1
      _ => ()
    }
  }
  n
}

///|
fn count_bars(toks : Array[@lexer.Tok]) -> Int32 {
  let mut n = 0
  for t in toks {
    match t {
      TBar => n += 1
      _ => ()
    }
  }
  n
}

///|
/// The construct, at the token level: `|` followed by a line break produces NO
/// `TNewline`, so the parser never sees a statement boundary there.
test "newline suppression: bitwise-or continues an expression across a line break" {
  let (toks, _, reports) = @lexer.lex("a |\nb")
  assert_eq(reports.length(), 0)
  assert_eq(count_newlines(toks), 0)
  // The token is still EMITTED. Suppression drops the newline, not the operator --
  // which is exactly why the or-pattern reading is unharmed, and this asserts the
  // half of that which a newlines-only assertion would not catch.
  assert_eq(count_bars(toks), 1)
}

///|
/// THE SET IS NOT TRIVIALLY ALL-TRUE, expressed the same way the rule is. Every
/// assertion above would also pass against a lexer that suppressed every newline
/// everywhere, so this row pins both directions: operators that DO continue, and
/// tokens that do NOT. `}` is the one that matters most -- it is the boundary the
/// rule exists to preserve.
test "newline suppression: operators continue, a name and a closer do not" {
  let (bar, _, _) = @lexer.lex("a |\nb")
  let (plus, _, _) = @lexer.lex("a +\nb")
  let (amp, _, _) = @lexer.lex("a &\nb")
  let (name, _, _) = @lexer.lex("a\nb")
  let (brace, _, _) = @lexer.lex("a\n}")
  assert_eq(count_newlines(bar), 0)
  assert_eq(count_newlines(plus), 0)
  assert_eq(count_newlines(amp), 0)
  assert_eq(count_newlines(name), 1)
  assert_eq(count_newlines(brace), 1)
}

///|
/// The regression this whole change could have caused, stated as a test: the
/// or-pattern separator is the SAME token as the bitwise-or operator, so adding it to
/// the suppression set had better not cost the token its existence.
test "or-pattern survives suppression: A | B still lexes as one TBar" {
  let (toks, _, reports) = @lexer.lex("SAssign(_) | SLet(_) => x")
  assert_eq(reports.length(), 0)
  assert_eq(count_bars(toks), 1)
}

///|
/// The corpus shape that died, at token level. `input_dispatch_result.mbt:13-15` is
///
///     (if self.handled { 1 } else { 0 }) |
///     (if self.capture_pointer { 2 } else { 0 }) |
///     (if self.release_pointer { 4 } else { 0 })
///
/// and reported `unexpected end of line` at the first `|`. Three trailing `|` in a
/// row, so this also pins that suppression is not a one-shot: each one has to work.
test "corpus shape: three trailing bitwise-or pipes each continue the expression" {
  let (toks, _, reports) = @lexer.lex("a |\nb |\nc")
  assert_eq(reports.length(), 0)
  assert_eq(count_newlines(toks), 0)
  assert_eq(count_bars(toks), 2)
}

///|
/// THE POSITIVE CONTROL for this whole file, and the row that licenses the rest: two
/// things the lexer must still do. It must still REPORT a character it does not know,
/// or the tests above could be passing because the lexer had stopped rejecting
/// anything at all. And it must still emit a line break after a name, or
/// `bitwise-or continues an expression across a line break` would pass for the wrong
/// reason -- a lexer that never emitted `TNewline` would suppress every continuation
/// by accident and look exactly like one that suppresses the right ones.
///
/// The first version of this row asserted a newline count against a source containing
/// NO newline, and failed `0 != 1`. The error path was never the thing under test;
/// the two halves belong to different sources, so they are asserted apart.
test "positive control: an unknown character is still reported, and a name still ends its line" {
  let (_, _, reports) = @lexer.lex("a \u{5c} b")
  assert_true(reports.length() > 0)
  let (good, _, _) = @lexer.lex("a\nb")
  assert_eq(count_newlines(good), 1)
}

///|
/// THE OTHER CONJUNCT OF THE SAME CONDITION, and this test exists because gate 0455's
/// M4 SURVIVED. M4 deletes `closer_ahead` from
///
///     if !newline_suppressed_after(last) && !closer_ahead(self.chars, self.pos)
///
/// and the suite stayed 631/631 green: the newline-before-a-closer rule had no test
/// pinning it anywhere in this repository, even though the lexer's own comment calls
/// it out as a rule ("Same rule the lexer already applies for a newline before a
/// closing bracket"). A rule that nothing observes is not a rule, it is a comment.
///
/// It is not about TBar, and it is in this file rather than its own only because the
/// two rules share one `if` and one gate mutation each. The distinguishing rows are
/// the pair: a newline before a closer is suppressed, and a newline before anything
/// else is not. Testing only the first would pass against a lexer that suppressed
/// every newline in a parenthesised group.
test "newline before a closing bracket is a tail, not a statement separator" {
  let (closer, _, _) = @lexer.lex("f(a\n)")
  let (inner, _, _) = @lexer.lex("f(a\nb)")
  assert_eq(count_newlines(closer), 0)
  assert_eq(count_newlines(inner), 1)
}

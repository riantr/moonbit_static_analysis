///|
/// 0480 -- the UNBRACED Unicode escape, `'\uXXXX'`, in a character literal.
///
/// 0459 settled the BRACED form `'\u{...}'` and its guard at `lex_char` required `\u` to be
/// followed by `{`. The unbraced spelling therefore fell through to `other => other`, which
/// wrote the letter `u`, and the four hex digits were appended by the ordinary character
/// path -- payload `u007f`, five characters, refused with "character literal must hold
/// exactly one character". A FALSE refusal: proton and moonbit_labeler both ship files that
/// write it, and so does `moonbitlang/core` `builtin/char.mbt` about a hundred and fifty
/// times.
///
/// Settled before implementing (`_verify/settle_0480_unbraced_unicode_escape.ps1`, 3 controls
/// + 5 rows, GATE OK):
///
///   ACCEPT        `'\u007f'`    the proton shape        ACCEPT  `'\u000C'`  the labeler shape
///   ACCEPT        `'\u{1F600}'`  the braced form, which is the ONLY spelling for astral
///   REJECT(3001)  `'\u07f'`      THREE digits            REJECT(3001)  `'\u01F600'`  six
///   REJECT(3001)  `b'\u000C'`    a BYTE literal takes `b'\xNN'`, not this
///
/// The payload assertions are on the CHARACTER, not on the source spelling, because the
/// length check is what refused these files and the length is what has to come out right.
/// Asserting `s.length()` alone would pass on the old five-character `u007f` payload for the
/// braced form only by accident, so each row here checks both that there is no report and
/// that the payload is one character.
test "0480: an unbraced four-digit unicode escape is one character" {
  let (toks, _, reports) = @lexer.lex("'\\u007f'")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s.length(), 1)
    _ => assert_true(false)
  }
}

///|
/// THE LABELER SHAPE, `'\u000C'`, and the reason the code point is not asserted. Both are
/// one character and both must be ONE character, but the CONTROL below already pins the
/// unrecognised case, so these two rows differ only in which digits they carry.
test "0480: a NUL-page unbraced escape is one character" {
  let (toks, _, reports) = @lexer.lex("'\\u000C'")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s.length(), 1)
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL, and it is the row that makes the other two mean something. Before 0480 the
/// payload of an unbraced escape was the literal source text `u007f`. If the digit loop were
/// to stop early -- or the escape to swallow the closing quote -- the payload would still be
/// "some characters", and only its LENGTH distinguishes a correct one from a mangled one.
/// A genuine three-character literal must still be three, and must still be REFUSED.
test "0480: a genuine multi-character literal is still refused (control)" {
  let (toks, _, reports) = @lexer.lex("'abc'")
  assert_eq(reports.length(), 1)
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s.length(), 3)
    _ => assert_true(false)
  }
}

///|
/// THREE DIGITS ARE REFUSED, and this is the row that pins "exactly four" rather than "a run
/// of hex digits". The settle says REJECT(3001). If the guard accepted any run, `'\u07f'`
/// would become the one character U+007F -- silently the same value as `'\u007f'` -- and the
/// reader would be inventing an acceptance the compiler does not make.
test "0480: a three-digit escape is not an escape" {
  let (_, _, reports) = @lexer.lex("'\\u07f'")
  assert_eq(reports.length(), 1)
}

///|
/// SIX DIGITS ARE REFUSED, AND THE FIXTURE IS A BMP VALUE ON PURPOSE. The first version of
/// this row used `'\u01F600'`, which is ASTRAL, and it could not see the mutation it was
/// written for: with the fourth-digit check removed, that literal lexes to U+01F600, whose
/// length through this token is measured by the string builder's astral handling, so both
/// the correct and the broken reader report one finding. 0459's test file records the same
/// trap in its own words. `'\u00007f'` has the same six digits and a BMP value, so the
/// correct reader produces the seven-character payload `u00007f` and one report, and a
/// reader that accepts a run of hex digits produces one character and NO report.
/// Settled: REJECT(3001) for both the astral and the BMP spelling.
test "0480: a six-digit escape is not an escape" {
  let (toks, _, reports) = @lexer.lex("'\\u00007f'")
  assert_eq(reports.length(), 1)
  match toks[0] {
    @lexer.TStr(s, _) => assert_true(s.length() != 1)
    _ => assert_true(false)
  }
}

///|
/// THE VALUE IS THE CODE POINT, and this row exists because nothing above could see a wrong
/// one. Length and report count are both correct when the escape consumes four digits AND
/// when it consumes three and one is mistaken for the brace the 0459 branch was written to
/// skip -- `'\u1234'` and `'\u0234'` are each exactly one character and neither reports. A
/// reader that takes the first digit for a brace yields U+0234 here and the analyzer keeps
/// running on a file whose character constants are wrong. Nothing downstream in this project
/// compares characters, so the corpus would never have found it.
test "0480: the escape's value is the code point, not the digits after a skipped one" {
  let (toks, _, reports) = @lexer.lex("'\\u1234'")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s, "\u{1234}")
    _ => assert_true(false)
  }
}

///|
/// THE BRACED FORM IS THE CONTROL for the widening above. `'\u{1F600}'` is astral: there is
/// no four-digit spelling of it at all, so the brace form is the only way to write that code
/// point. A guard rewritten to read `\u` and then "consume digits" without distinguishing
/// the brace would break this, and the corpus would find it long after the test did not.
test "0480: the braced form still reads one character (control)" {
  let (toks, _, reports) = @lexer.lex("'\\u{0}'")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s.length(), 1)
    _ => assert_true(false)
  }
}

///|
/// AND THE ROW THAT KEEPS THE CHANGE IN ITS PLACE: the escape belongs to CHARACTER literals
/// only. `b'\x00'` is a Byte and settled legal (0459); `b'\u000C'` is REJECT(3001). The
/// unbraced form must not be admitted there, because the byte-literal branch routes into
/// this same reader and a widened guard would silently widen it too.
test "0480: the byte form does not take the unbraced escape" {
  let (_, _, reports) = @lexer.lex("b'\\u000C'")
  assert_eq(reports.length(), 1)
}

///|
/// `\xNN` is UNCHANGED, and it is the escape that shares this code path. A guard that now
/// tests `self.pos + 5` before accepting a four-character run could plausibly have cost the
/// two-digit form, and nothing above would notice: every other row in this file is about `u`.
test "0480: the hex escape is unchanged" {
  let (toks, _, reports) = @lexer.lex("'\\x41'")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => assert_eq(s.length(), 1)
    _ => assert_true(false)
  }
}

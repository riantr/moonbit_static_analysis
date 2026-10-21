///|
/// 0496 -- the CHARACTER LITERAL's escape, and the CHARACTER COUNT.
///
/// 0459 settled the BRACED form `'\u{...}'` and 0480 the UNBRACED `'\uXXXX'`.
/// Both guards were about the DIGIT COUNT, and both left the reader with one
/// question they never asked: how many CHARACTERS the literal holds.
///
/// THE ANSWER WAS WRONG, AND THE REASON WAS NOT THE DIGITS. The reader took as
/// many hex digits as there were -- `'\u{1F600}'` was read as U+1F600, not
/// truncated -- and then the length check counted the payload with
/// `s.length()`. MoonBit's `String::length()` counts UTF-16 CODE UNITS and
/// `String::to_array()` counts CODE POINTS, and the two DISAGREE for every
/// supplementary-plane character. Measured, not inferred:
///
///     "\u{1F600}".to_string().length()            -> 2
///     "\u{1F600}".to_string().to_array().length() -> 1
///
/// So U+1F600 -- ONE character, two units -- was counted as two, and the
/// literal was refused with "character literal must hold exactly one
/// character". The standing note in `_verify/NARRATIVE.md` (the 0494 block)
/// said the reader "takes at most FOUR hex digits, which is exactly the BMP",
/// and THAT WAS THE WRONG EXPLANATION of a right observation: a fix written
/// from it would have bounded the digits and still refused `'\u{10000}'`.
///
/// The witness is real corpus code. `moonbitlang/core`
/// `string/quickcheck_test.mbt:138`:
///
///     let qc_boundary_chars : Array[Char] = [
///       '@', 'A', 'B', ..., '\u{7F}', ..., '\u{10000}', '\u{1F600}', '\u{10FFFF}',
///     ]
///
/// `moon check` calls it legal MoonBit with 0 errors, and the frontend could
/// not read it.
///
/// THE SECOND DEFECT IS WORSE THAN THE FIRST. `'\u{110000}'` -- a code point
/// past the last one -- reached `v.unsafe_to_char()`, which is not a
/// conversion but a TRAP: the scanner printed `RuntimeError: unreachable` and
/// STOPPED, so every file after it in the scan went unread. A wrong answer is
/// one finding; a crash is the loss of the run.
///
/// So this file pins the whole grammar the toolchain implements, one form per
/// row, and the settle that produced it is
/// `_verify/settle_0496_unicode_escape.ps1`.

///|
/// The names a string literal's interpolation references. Used by the rows
/// about a LAMBDA inside an interpolation, which is the third thing this
/// increment measured.
fn interp_names(src : String) -> Array[String] {
  let (toks, _, _) = @lexer.lex(src)
  match toks[0] {
    @lexer.TStr(_, names) => names
    _ => []
  }
}

///|
/// THE ASTRAL ESCAPE IS ONE CHARACTER. `'\u{1F600}'` is U+1F600, which is one
/// character and two UTF-16 units, and the toolchain ACCEPTs it (settle row
/// `r04_astral_emoji`).
///
/// The assertion is on the CODE POINT count and not on `s.length()`, because
/// `s.length()` is 2 here and asserting it would pin the very confusion this
/// increment is about. The value is asserted too, because a reader that
/// produced the right COUNT and the wrong CHARACTER would satisfy a count
/// alone.
test "0496: an astral escape is ONE character" {
  let (toks, _, reports) = @lexer.lex("'\\u{1F600}'")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => {
      assert_eq(s.to_array().length(), 1)
      assert_eq(s, "\u{1F600}")
    }
    _ => assert_true(false)
  }
}

///|
/// THE CORPUS WITNESS'S OWN SHAPE. `moonbitlang/core`
/// `string/quickcheck_test.mbt:138` writes `'\u{10000}'` -- U+10000, the first
/// supplementary-plane code point, and the one whose SIX-HEX spelling has no
/// BMP counterpart.
test "0496: the first supplementary-plane code point is one character" {
  let (toks, _, reports) = @lexer.lex("'\\u{10000}'")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => {
      assert_eq(s.to_array().length(), 1)
      assert_eq(s, "\u{10000}")
    }
    _ => assert_true(false)
  }
}

///|
/// THE LAST CODE POINT, U+10FFFF. Six hex digits and the top of the range, so
/// this row and the one above it pin the braced form's SIX-digit ceiling from
/// both sides.
test "0496: the last code point is one character" {
  let (toks, _, reports) = @lexer.lex("'\\u{10FFFF}'")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => {
      assert_eq(s.to_array().length(), 1)
      assert_eq(s, "\u{10FFFF}")
    }
    _ => assert_true(false)
  }
}

///|
/// A DIRECT astral character -- not an escape, the character itself in the
/// source. The toolchain ACCEPTs it (settle row `r27_direct_astral`), and it
/// was refused by the same UTF-16 length check, because the lexer's `chars`
/// holds CODE POINTS (`for c in src`) and the payload it built therefore held
/// two units of one character.
///
/// This row is the one that says the fix is about the COUNT and not about the
/// ESCAPE: a reader that only understood `\u{...}` would pass the three rows
/// above and fail this one.
test "0496: a direct astral character is one character" {
  let (toks, _, reports) = @lexer.lex("'\u{1F600}'")
  assert_eq(reports.length(), 0)
  match toks[0] {
    @lexer.TStr(s, _) => {
      assert_eq(s.to_array().length(), 1)
      assert_eq(s, "\u{1F600}")
    }
    _ => assert_true(false)
  }
}

///|
/// A CODE POINT PAST THE LAST ONE IS REPORTED, NOT WRITTEN. `'\u{110000}'` is
/// REJECT(4064) by the toolchain, and before this increment it reached
/// `unsafe_to_char()` and took the whole scan down with it.
///
/// The row asserts the REPORT, and a reader that wrote the character instead
/// would have to produce one -- which is a crash, not a red test. So the row
/// pins the message, and the crash is pinned by the fact that the suite
/// finishes.
test "0496: a code point past the last one is reported" {
  let (_, _, reports) = @lexer.lex("'\\u{110000}'")
  assert_eq(reports.length(), 1)
  assert_true(
    reports[0].message.contains(
      "character literal is not a valid Unicode code point",
    ),
  )
}

///|
/// A SURROGATE IS NOT A SCALAR VALUE. U+D800..U+DFFF is the surrogate range,
/// which Unicode excludes from scalar values, and the toolchain REJECTs it
/// (4064, settle rows `r07_surrogate` and `r08_surr_end`).
///
/// The row asserts BOTH ends of the range, because a guard written as
/// `v >= 0xD800` would pass it and a guard written as `v >= 0xD800 && v <=
/// 0xDFFF` is what the range actually needs.
test "0496: a surrogate is not a valid code point" {
  let (_, _, lo) = @lexer.lex("'\\u{D800}'")
  assert_eq(lo.length(), 1)
  assert_true(
    lo[0].message.contains(
      "character literal is not a valid Unicode code point",
    ),
  )
  let (_, _, hi) = @lexer.lex("'\\u{DFFF}'")
  assert_eq(hi.length(), 1)
  assert_true(
    hi[0].message.contains(
      "character literal is not a valid Unicode code point",
    ),
  )
}

///|
/// AND THE TWO EDGES OF THE SURROGATE RANGE ARE LEGAL, which is the control
/// for the row above: a guard that refused everything from U+D800 upwards
/// would pass it.
test "0496: the edges of the surrogate range are legal" {
  let (_, _, below) = @lexer.lex("'\\u{D7FF}'")
  assert_eq(below.length(), 0)
  let (_, _, above) = @lexer.lex("'\\u{E000}'")
  assert_eq(above.length(), 0)
}

///|
/// THE BRACED FORM TAKES AT MOST SIX DIGITS, and a seventh is a REPORT. The
/// toolchain REJECTs `'\u{1000000}'` (4064, settle row `r12_7digits`) and
/// `'\u{FFFFFFFF}'` (4064, row `r13_8digits`).
///
/// The second row is the one that matters: EIGHT digits is 0xFFFFFFFF, which
/// does not fit in the reader's `Int32` accumulator, so a reader that
/// accumulated every digit would overflow on the way to a value it was going
/// to refuse anyway.
test "0496: the braced form takes at most six digits" {
  let (_, _, seven) = @lexer.lex("'\\u{1000000}'")
  assert_eq(seven.length(), 1)
  assert_true(
    seven[0].message.contains("character literal has a malformed escape"),
  )
  let (_, _, eight) = @lexer.lex("'\\u{FFFFFFFF}'")
  assert_eq(eight.length(), 1)
  assert_true(
    eight[0].message.contains("character literal has a malformed escape"),
  )
}

///|
/// THE BRACED FORM NEEDS ITS CLOSER. `'\u{7F'` -- no `}` -- is REJECT(3001) by
/// the toolchain (settle row `r15_no_closer`) and used to be read as the
/// character U+007F and then the end of the literal.
test "0496: the braced form needs its closer" {
  let (_, _, reports) = @lexer.lex("'\\u{7F'")
  assert_eq(reports.length(), 1)
  assert_true(
    reports[0].message.contains("character literal has a malformed escape"),
  )
}

///|
/// AND AN EMPTY BRACED FORM IS MALFORMED TOO. `'\u{}'` has no digits at all,
/// and the toolchain REJECTs it (3001, settle row `r14_empty_braces`).
test "0496: an empty braced escape is malformed" {
  let (_, _, reports) = @lexer.lex("'\\u{}'")
  assert_eq(reports.length(), 1)
  assert_true(
    reports[0].message.contains("character literal has a malformed escape"),
  )
}

///|
/// THE HEX ESCAPE TAKES EXACTLY TWO DIGITS. The toolchain REJECTs `'\x4'`
/// (3001), `'\x414'` (3001) and `'\x4142'` (3001) -- settle rows `r23`,
/// `r24` and `r25` -- and the reader used to take a RUN of hex digits, so all
/// three were read as one character and ACCEPTed.
///
/// The four-digit row is the one that matters: `'\x4142'` is 0x4142, a valid
/// code point, so a reader that took a run would produce a plausible-looking
/// character rather than an obvious mistake.
test "0496: the hex escape takes exactly two digits" {
  let (_, _, one) = @lexer.lex("'\\x4'")
  assert_eq(one.length(), 1)
  assert_true(
    one[0].message.contains("character literal has a malformed escape"),
  )
  let (_, _, three) = @lexer.lex("'\\x414'")
  assert_eq(three.length(), 1)
  assert_true(
    three[0].message.contains("character literal has a malformed escape"),
  )
  let (_, _, four) = @lexer.lex("'\\x4142'")
  assert_eq(four.length(), 1)
  assert_true(
    four[0].message.contains("character literal has a malformed escape"),
  )
}

///|
/// A BYTE LITERAL TAKES NO UNICODE ESCAPE. `b'\u{41}'` and `b'\u000C'` are both
/// REJECT(3001) by the toolchain -- settle rows `r20_byte_braced` and
/// `r21_byte_unbraced` -- and the BRACED form was read as a CHARACTER while
/// the UNBRACED one was already refused (0480).
test "0496: the byte form takes no unicode escape" {
  let (_, _, braced) = @lexer.lex("b'\\u{41}'")
  assert_eq(braced.length(), 1)
  assert_true(
    braced[0].message.contains("character literal has a malformed escape"),
  )
  let (_, _, unbraced) = @lexer.lex("b'\\u000C'")
  assert_eq(unbraced.length(), 1)
  assert_true(
    unbraced[0].message.contains("character literal has a malformed escape"),
  )
}

///|
/// THE CONTROLS. Everything the reader already got right, still right: the BMP
/// braced forms of 0459, the unbraced form of 0480, and the byte literal's
/// `\xNN`. A fix that bounded the braced form to four digits, or that touched
/// the byte form's hex escape, would go red here.
test "0496: the forms that already worked still work (control)" {
  let (_, _, two) = @lexer.lex("'\\u{7F}'")
  assert_eq(two.length(), 0)
  let (_, _, four) = @lexer.lex("'\\u{FFFF}'")
  assert_eq(four.length(), 0)
  let (_, _, unbraced) = @lexer.lex("'\\u007f'")
  assert_eq(unbraced.length(), 0)
  let (btoks, _, breports) = @lexer.lex("b'\\x41'")
  assert_eq(breports.length(), 0)
  match btoks[0] {
    @lexer.TStr(s, _) => assert_eq(s.to_array().length(), 1)
    _ => assert_true(false)
  }
}

///|
/// AND THE LENGTH RULE STILL HAS TEETH. A genuine two-character literal is
/// still refused -- with the length message, because nothing is wrong with its
/// escape. The rows above all report a MALFORMED ESCAPE, and a reader that
/// reported that for everything would pass them all and fail this one.
test "0496: a genuine multi-character literal is still refused (control)" {
  let (_, _, reports) = @lexer.lex("'ab'")
  assert_eq(reports.length(), 1)
  assert_true(
    reports[0].message.contains(
      "character literal must hold exactly one character",
    ),
  )
}

///|
/// A LAMBDA PARAMETER INSIDE AN INTERPOLATION IS A BINDING, NOT A READ.
///
/// The third thing this increment measured, and it was found BY the second: the
/// `lexmatch` fix made `moonbitlang/core` `builtin/autoloc.mbt` readable past
/// its old boundary, and the file then reported `no visible binding for 'sb'`
/// -- a name the interpolation's own lambda binds:
///
///     $|{"filename":\{sb => self.filename.escape_to(sb)},...}
///
/// The name was recorded as a READ of the enclosing frame, and the frame has
/// no `sb`. The corpus file is part of a PUBLISHED package and compiles, so
/// the finding was a false positive that a file stopped at line 74 had been
/// hiding.
///
/// The row asserts the NAME LIST and not the finding: the finding is the
/// walker's business, and the list is the lexer's.
test "0496: a lambda parameter inside an interpolation is not a read" {
  let names = interp_names("\"\\{sb => sb}\"")
  assert_true(!names.contains("sb"))
}

///|
/// AND THE NAMES THE INTERPOLATION REALLY READS ARE STILL RECORDED. The
/// enclosing `self` is a read of the frame, and the row is the control for the
/// one above: a reader that stopped recording names would satisfy it.
test "0496: the names an interpolation reads are still recorded (control)" {
  let names = interp_names("\"\\{self.filename.escape_to(sb)}\"")
  assert_true(names.contains("self"))
  assert_true(!names.contains("filename"))
}

///|
/// AND A READ BEFORE THE LAMBDA IS STILL RECORDED. `count` is read before the
/// lambda that binds `x`, so it is a read of the frame; `x` is the lambda's
/// own parameter. The row is what keeps the suppression from running
/// BACKWARDS.
test "0496: a read before the lambda is still recorded" {
  let names = interp_names("\"\\{count + xs.map(x => x + 1)}\"")
  assert_true(names.contains("count"))
  assert_true(names.contains("xs"))
  assert_true(!names.contains("x"))
}

///|
/// AND A TIGHT ARROW BINDS THE SAME WAY. `sb=>sb` -- no space -- is legal
/// MoonBit (settle row `L11_no_space_arrow`), and it reaches the lexer by a
/// DIFFERENT path: the name is still pending when the `=` arrives, so the
/// `=>` branch of the collector handles it, while `sb => sb` reaches the
/// lookahead in `at_lambda_head_after`. Both have to bind.
///
/// The row is also the control for the row above: a reader that recognised the
/// arrow only in the spaced spelling would pass it and fail this one.
test "0496: a tight arrow binds the same way" {
  let names = interp_names("\"\\{sb=>sb}\"")
  assert_true(!names.contains("sb"))
}

///|
/// AND A LABEL IS STILL NOT A READ. `radix=16` supplies a value to a
/// PARAMETER NAMED `radix` (0488), and nothing named `radix` is ever bound
/// there, so recording it was the false positive 0488 fixed. This increment
/// touched the same branch -- the `=>` carve-out now sits ABOVE it -- so the
/// row is the control for that.
test "0496: a labelled argument is still not a read (control)" {
  let names = interp_names("\"\\{value.to_string(radix=16)}\"")
  assert_true(names.contains("value"))
  // `to_string` is a MEMBER of `value`, and a member of a path is not a
  // binding -- the same rule that keeps `\{m.length()}` from recording
  // `length`.
  assert_true(!names.contains("to_string"))
  assert_true(!names.contains("radix"))
}

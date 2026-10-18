# Mutation gate 0480 -- the UNBRACED unicode escape `'\uXXXX'` in a character literal.
#
# WHAT THIS PINS. 0459 settled and implemented the BRACED form, `'\u{...}'`, and its guard
# required `\u` to be followed by `{`. The unbraced spelling therefore fell through to
# `other => other`, wrote the letter `u`, and the four hex digits were appended by the
# ordinary character path -- payload `u007f`, five characters, refused with "character
# literal must hold exactly one character".
#
# NOT ONE FILE. `moonbitlang/core` `builtin/char.mbt` writes the form about a hundred and
# fifty times, `char/predicate_reference_test.mbt` as many again, and two PINNED corpora were
# blocked by it: proton `internal/native/configuration.mbt:4` and moonbit_labeler
# `extensions/labeler/labeler.mbt:2741`.
#
# Measured: proton `parsed 135 -> 136`, `unreliable 37 -> 31`, `withheld 6 -> 0`;
# moonbit_labeler `parsed 35 -> 36`, `unreliable 55 -> 16`. `actionable` stayed 0 on both,
# which is the number that matters -- the reader unblocked files and invented nothing.
#
# `_verify/settle_0480_unbraced_unicode_escape.ps1`, 3 controls + 5 rows, GATE OK:
#   ACCEPT            `'\u007f'` (proton)   ACCEPT  `'\u000C'` (labeler)   ACCEPT  `'\u{1F600}'`
#   REJECT(3001)      `'\u07f'`  three digits   REJECT(3001)  `'\u01F600'` six
#   REJECT(3001)      `b'\u000C'` -- a BYTE literal takes `b'\xNN'`, not this
#
# M2 IS THE MUTATION THAT FOUND A REAL BUG, and it is here for that reason rather than
# because the rule is interesting. The first implementation widened the escape guard without
# a context flag, and `b'\u000C'` then lexed cleanly -- while the toolchain calls it
# REJECT(3001), with `b'\x0C'` ACCEPTing beside it. The byte branch routes into the SAME
# reader, so a guard widened in one place is widened in both. The test row caught it
# (`0 != 1`) before any corpus was scanned.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$LEXER = 'src\lexer\lexer.mbt'

Invoke-MutationGate -Name '0480' -Target 'wasm' -Mutations @(

  # M1 THE DIGIT-COUNT IS NOT ENFORCED: the fifth-character test goes, so `\u` is followed by
  # any run of hex digits. `'\u01F600'` then lexes as U+01F6 followed by the literal text
  # `00`, a three-character payload -- still refused, but by the length check rather than by
  # the escape rule, and a five-digit spelling would be silently accepted where the toolchain
  # refuses it. The settle's REJECT(3001) is what says six digits are not an escape.
  @{
    Name = 'M1 the four-digit count is not enforced (six digits truncate)'
    File = $LEXER
    Find = '        hex_value(self.chars[self.pos + 4]) >= 0 &&' + "`n" +
           '        hex_value(self.chars[self.pos + 5]) < 0'
    Repl = '        hex_value(self.chars[self.pos + 4]) >= 0'
    MustRed = '0480: a six-digit escape is not an escape'
  }
  # M2 THE BYTE CONTEXT FLAG IS DROPPED. `b'\u000C'` becomes a legal Byte literal. The
  # toolchain disagrees: REJECT(3001), with `b'\x0C'` ACCEPTing beside it, so this is a
  # false ACCEPTANCE of a program the compiler refuses -- invisible in every count, because
  # the file still parses.
  @{
    Name = 'M2 the byte-literal distinction is dropped (b''\u000C'' accepted)'
    File = $LEXER
    Find = '      let bare_u = !byte_form &&'
    Repl = '      let bare_u = true &&'
    MustRed = '0480: the byte form does not take the unbraced escape'
  }

  # M3 EXACTLY FOUR BECOMES "AT LEAST TWO", and this one SURVIVES BY PROOF rather than by
  # accident, so it is declared instead of being quietly dropped. Dropping the first two
  # digit checks does not change what any well-formed literal does, and the proof is that it
  # cannot: the digit loop below already stops at the first NON-hex, and it writes nothing
  # when it consumed none (`if digits > 0`), so an escape admitted with a non-hex where a
  # digit belongs writes NOTHING and leaves the source characters to the ordinary path. The
  # payload is shorter -- `!fg` where the unmoved guard gives `u!!fg` -- and both are refused
  # by the same one-character check. A reader that accepted a malformed escape would still
  # not produce a file that parses.
  #
  # That is a claim about the CURRENT shape of the guard and it expires the moment the guard
  # is rewritten, so it is stated here rather than left implicit. If a future increment makes
  # the escape write a character even when `digits == 0`, this proof stops being true and
  # the survivor has to be re-argued rather than inherited.
  @{
    Name = 'M3 three digits are enough (u07f silently becomes U+007F)'
    File = $LEXER
    Find = '        hex_value(self.chars[self.pos + 1]) >= 0 &&' + "`n" +
           '        hex_value(self.chars[self.pos + 2]) >= 0 &&'
    Repl = ''
    Expect = 'SURVIVED'
    Prove = 'the digit loop stops at the first non-hex and writes nothing when it consumed none, so an escape admitted by a weakened guard contributes no character and the one-character check refuses the literal either way'
    MustRed = ''
  }

  # M4 `braced` GOES BACK TO `e == ''u''`. With the unbraced form in the same branch that
  # value is now true for a literal with no brace after it, so the block below consumes the
  # FIRST HEX DIGIT as though it were `{`, and `'\u1234'` becomes U+0234. Both the correct
  # and the broken reader return one character and report nothing, so every length-and-count
  # row above is blind to it -- which is why the value row exists.
  @{
    Name = 'M4 the braced flag is `e == u` again, so a digit is consumed as a brace'
    File = $LEXER
    Find = '        let braced = braced_u'
    Repl = '        let braced = e == ''u'''
    MustRed = '0480: the escape''s value is the code point, not the digits after a skipped one'
  }
)

Write-MutationGateVerdict -Name '0480'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

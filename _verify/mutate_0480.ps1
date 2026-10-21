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
  #
  # 0496 RE-ANCHORED THIS ONE, AND THE CLAIM IS THE SAME ONE. 0496 replaced the old
  # fifth-character test with a PER-FORM digit bound -- `(2,2)` for `\xNN`, `(1,6)` for the
  # braced form and `(4,4)` for the unbraced one -- so the old anchor text is gone. The
  # mutation is now expressed on the bound itself: the unbraced form's `(4, 4)` becomes
  # `(4, 6)`, which admits six digits where the toolchain refuses them. The effect is the
  # one the row is named for: `'\u00007f'` -- six digits, value U+007F -- becomes ONE
  # character and is ACCEPTed, which is a false ACCEPTANCE of a program the compiler
  # REJECTs with 3001.
  @{
    Name = 'M1 the four-digit count is not enforced (six digits truncate)'
    File = $LEXER
    Find = '        } else {' + "`n" +
           '          (4, 4)' + "`n" +
           '        }'
    Repl = '        } else {' + "`n" +
           '          (4, 6)' + "`n" +
           '        }'
    MustRed = '0480: a six-digit escape is not an escape'
  }
  # M2 THE BYTE CONTEXT FLAG IS DROPPED. `b'\u000C'` becomes a legal Byte literal. The
  # toolchain disagrees: REJECT(3001), with `b'\x0C'` ACCEPTing beside it, so this is a
  # false ACCEPTANCE of a program the compiler refuses -- invisible in every count, because
  # the file still parses.
  #
  # 0496 RE-ANCHORED THIS ONE, AND THE CLAIM IS THE SAME ONE. The old guard was
  # `bare_u = !byte_form &&`, and 0496 DELETED `bare_u`: the escape branch now reads
  # `e == 'x' || e == 'u'` and checks the toolchain's rules afterwards, so the byte form
  # is refused by `if byte_form && e == 'u' { malformed = true }`.
  #
  # The mutation keeps the GUARD and narrows it to the BRACED form, which is exactly the
  # distinction the old `bare_u` drew -- it covered the UNBRACED form only. So the
  # unbraced escape in a byte literal is admitted again, `b'\u000C'` is ACCEPTed, and the
  # row that pins 0480's claim goes red. It is not 0496's M7 and does not duplicate it:
  # that mutation changes the guard's LETTER, so it also breaks `b'\xNN'`, and it names
  # 0496's own row. This one names 0480's.
  @{
    Name = 'M2 the byte-literal distinction is dropped (b''\u000C'' accepted)'
    File = $LEXER
    Find = '        if byte_form && e == ''u'' {'
    Repl = '        if byte_form && e == ''u'' && braced {'
    MustRed = '0480: the byte form does not take the unbraced escape'
  }

  # M3 EXACTLY FOUR BECOMES "AT LEAST TWO". This one WAS a declared SURVIVED, and the
  # proof it carried said, in its own words, that it "expires the moment the guard is
  # rewritten" -- and 0496 REWROTE THE GUARD. So the proof is EXPIRED and the survivor
  # has to be RE-ARGUED rather than inherited.
  #
  # THE OLD PROOF WAS THIS: dropping the first two digit checks does not change what any
  # well-formed literal does, and it cannot, because the digit loop stopped at the first
  # NON-hex and wrote nothing when it consumed none -- so an escape admitted by a weakened
  # guard contributed no character and the one-character check refused the literal either
  # way. That was a claim about the SHAPE of the old guard: a guard that wrote a character
  # even when it consumed none would break it.
  #
  # 0496'S GUARD DOES WRITE ONE, so the proof does not hold. The escape branch now counts
  # the characters it writes and REFUSES a literal that does not hold exactly one, and the
  # digit count is a PER-FORM BOUND -- `(4, 4)` for the unbraced form -- checked against the
  # digits that were actually read. Lower the bound to `(2, 4)` and `'\u07f'` -- THREE
  # digits, where the toolchain REJECTs it with 3001 -- is read as U+007F, ONE character,
  # with no report. That is a false ACCEPTANCE, and it is exactly what this row is named
  # for.
  #
  # SO THE SURVIVOR BECOMES A KILL, AND THE PROVE IS DELETED RATHER THAN REWORDED: a
  # proof that no longer holds is not a weaker proof, it is no proof. The named test is
  # `0480: a three-digit escape is not an escape`, and it goes red because the report
  # the reader must produce is not produced.
  @{
    Name = 'M3 three digits are enough (u07f silently becomes U+007F)'
    File = $LEXER
    Find = '        } else {' + "`n" +
           '          (4, 4)' + "`n" +
           '        }'
    Repl = '        } else {' + "`n" +
           '          (2, 4)' + "`n" +
           '        }'
    MustRed = '0480: a three-digit escape is not an escape'
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

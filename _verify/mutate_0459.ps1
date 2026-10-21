# Mutation gate 0459 -- byte literals and escape sequences.
#
# WHAT THIS PINS. `b'\x08'` is a single `Byte`; `b"\x08"` is a `Bytes` string. The
# reader was `lex_string` for both, so the single-quoted form became a
# three-character payload and every one of its 58 corpus files stopped at
#
#     character literal must hold exactly one character
#
# That message was ALSO covering a second, unrelated gap: `\xNN` and `\u{...}`
# passed through `other => other`, so their payload was the literal source text.
# One message, two lexer defects, 58 files and 19 files -- and only probing the
# message's two populations separated them.
#
# THE GRAMMAR FACTS, settled before implementing
# (`_verify/settle_0459_literal_escapes.ps1`, 8/8):
#
#     b'\x00'  accepted against `-> Byte`          (it is a Byte)
#     b"\x00"  a Bytes string                       (it is not one byte)
#     b'ab'    REJECT(3001)                         (one character, so the
#                                                   length check has teeth)
#     '\u{1F600}'  accepted                         (so the brace form is NOT
#                                                   "two hex digits")
#
# => 判据: the two forms look like a spelling difference and are two different
# constructs with two different readers. Routing the single-quoted form through
# `lex_string` would have made the message disappear without making a single file
# readable, which is the shape of a fix that is verified by its own symptom.
# RE-ANCHORED 2026-10-18 by increment 0480, and this is now the SECOND time one increment
# has silently invalidated another gate's anchors. 0480 gave `lex_char` a `byte_form`
# parameter, and that one signature moved three of the four anchors below:
#
#   M1/M6  `self.lex_char()`  ->  `self.lex_char(true)` at the byte-literal call site
#   M4     the inline `e == 'u' &&` inside the escape guard -> the named `braced_u` binding
#
# Pre-flight caught all three at once: `ABORT: 3 pattern(s) absent. No suite was run.`, in
# one second, on a gate whose last recorded verdict was green. None of the three questions
# stopped being live -- a single-quoted byte literal is still read as a character, a braced
# escape is still decoded, a two-character byte literal is still refused -- so all three are
# re-pointed at the CURRENT spelling of the SAME question rather than retired.
#
# => A mutation anchor is a claim about a SPELLING, and a refactor elsewhere in the same file
# spends it. The gate that notices is the pre-flight, and the cost of not re-anchoring is a
# rule that stops being checked while the gate keeps reading OK.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$LEXER = 'src\lexer\lexer.mbt'

Invoke-MutationGate -Name '0459' -Target 'js' -Mutations @(

  # M1 IS THE GATE. The single-quoted form goes back to `lex_string`, which is the
  # pre-0459 lexer verbatim -- and the 58 files this increment unblocked go back
  # to "character literal must hold exactly one character".
  @{
    Name = 'M1 the single-quoted byte literal is read as a string'
    File = $LEXER
    Find = "      if quoted {`n        last = self.lex_string()`n      } else {`n        last = self.lex_char(true)`n      }"
    Repl = "      if quoted {`n        last = self.lex_string()`n      } else {`n        last = self.lex_string()`n      }"
    MustRed = '0459: a single-quoted byte literal with a hex escape is one token'
  }

  # M2 THE DISPATCH IS INERT. The quote is read and then ignored, so both forms
  # take the first branch. This is the mutation that catches an edit which
  # "simplifies" the dispatch while leaving code that still reads as deliberate.
  @{
    Name = 'M2 the quote kind is read but ignored'
    File = $LEXER
    # Single-quoted PowerShell, with the MoonBit char literal `'"'` written by
    # doubling: a double-quoted PS string turns the `"` into a backtick escape and
    # the preflight then hunts for `== ""`, which is not the code.
    Find = 'let quoted = self.chars[self.pos + 1] == ''"'''
    Repl = 'let quoted = true'
    MustRed = '0459: a single-quoted byte literal with a hex escape is one token'
  }

  # M3 THE HEX ESCAPE IS REMOVED, restoring `other => other`. The payload becomes
  # the source text again -- which is the SECOND defect the same message covered,
  # and the one a corpus count alone would have attributed to the quote change.
  @{
    Name = 'M3 the hex and braced escapes are not decoded'
    File = $LEXER
    Find = "      if e == 'x' ||"
    Repl = "      if false ||"
    MustRed = '0459: the hex escape decodes to a single character'
  }

  # M4 ONLY THE HEX ESCAPE IS TAKEN, so the brace form falls through to
  # `other => other` and `'\u{0}'` becomes the four-character payload `u{0}`.
  # 19 corpus files write the brace form; this is the mutation that would let them
  # look covered by the same commit that fixed the other 58.
  #
  # 0496 RE-ANCHORED THIS ONE, and the MUTATION IS THE SAME ONE. 0496 added
  # `!byte_form &&` to the binding -- a byte literal takes no unicode escape at
  # all, which is the toolchain's rule -- so the old anchor text
  # `let braced_u = e == 'u' &&` no longer exists. The mutation is re-anchored on
  # the line that STILL decides the braced form, and the line above it is carried
  # in the anchor so the text is unique.
  @{
    Name = 'M4 the braced unicode escape is not decoded'
    File = $LEXER
    Find = "      let braced_u = !byte_form &&`n        e == 'u' &&"
    Repl = "      let braced_u = !byte_form &&`n        e == 'z' &&"
    MustRed = '0459: a braced unicode escape is one character'
  }

  # M5 THE SENTINEL IS 0 INSTEAD OF -1. The digit loop terminates on `h < 0`, so
  # a zero sentinel never terminates it: `b'\x08'` runs to the closing quote and
  # reports a multi-character payload. It compiles, it reads correctly, and the
  # difference between the digit `0` and "not a digit" is the entire content.
  @{
    Name = 'M5 the not-a-hex-digit sentinel is zero'
    File = $LEXER
    Find = "  } else {`n    -1`n  }`n}"
    Repl = "  } else {`n    0`n  }`n}"
    MustRed = '0459: the hex escape decodes to the RIGHT character, not merely one of them'
  }

  # M6 THE ONE-CHARACTER RULE IS DROPPED, so `b'ab'` -- REJECT(3001) in MoonBit --
  # is accepted. This is the control the settle bought: without it, "read the
  # single-quoted form as a string" and "read it as a character" are
  # indistinguishable on every corpus file that happens to be well-formed.
  @{
    Name = 'M6 a two-character byte literal is accepted'
    File = $LEXER
    Find = "        last = self.lex_char(true)"
    Repl = "        last = self.lex_string()"
    MustRed = '0459: a two-character byte literal is still reported (control)'
  }
)

Write-MutationGateVerdict -Name '0459'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

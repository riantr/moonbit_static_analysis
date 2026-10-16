# Mutation gate 0471 -- the tail between an anonymous `fn`'s `)` and its body.
#
# WHAT THIS PINS. `parse_fn_literal` went from `parse_param_list()` straight to
# `parse_block()`, so a literal carrying `-> Type` or `raise`/`noraise` left the cursor on
# the tail token and `parse_block` -- looking for `{` -- reported `expected '{'`. A
# complaint about a brace that was never the problem, which is the same shape as the
# declared-`fn` `-> T raise E` clause whose absence once cost 24.5% of wzzc-dev/moui's 608
# files.
#
# The fix is not a third reader. A DECLARED `fn` already reads this tail with two calls:
#
#     if self.at(TArrow) { retann = self.return_annotation() }
#     self.parse_raise_effect()
#
# and `parse_fn_literal` was making neither. So M1 and M2 remove exactly the two calls that
# were added, which is the point: this gate pins the two helpers being CALLED from a second
# site, not a second implementation of what they do.
#
# Corpus reach, per-FILE first blocker, on the tree at 0470: labeler 33 -> 35 parsed,
# proton 122 -> 131, proton's `unreliable` 544 -> 187 and `withheld` 35 -> 6, labeler's
# `unreliable` 89 -> 55, `actionable` 0 on both. moui, image, async and contract
# BYTE-IDENTICAL -- four unchanged against two moved is the control.
#
# The grammar is settled in `_verify/settle_0471_fn_literal_tail.ps1`, 9 rows, two controls.
#
# => 判据: a fix that makes files readable has to be checked for what it stops reading. A tail
# consumed with the wrong extent swallows the token after the literal: `parsed` goes UP on
# every affected corpus, every SUMMARY line looks like progress, and the analyzer has
# quietly stopped reading the code that follows. The six pins CANNOT see that, which is why
# the MustRed rows below are the ones placing a probe on the far side of the literal rather
# than the ones asserting a tail was read.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0471' -Target 'wasm' -Mutations @(

  # M1 THE RETURN ANNOTATION IS NOT READ. Leaves the cursor on `->`, and `parse_block`
  # reports `expected '{'` -- the message that names the wrong thing and made this cost a
  # corpus to find.
  @{
    Name = 'M1 the return annotation is not read'
    File = $PARSER
    Find = "  if self.at(TArrow) {`n    let _ = self.bump()`n    let _ = self.return_annotation()`n  }"
    Repl = '  if self.at(TArrow) { let _ = self.bump() }'
    MustRed = '0471: a literal with a return annotation parses'
  }

  # M2 THE RAISE CLAUSE IS NOT READ. `raise` arrives as a `TName`, so this is the case where
  # an unread keyword is indistinguishable from an unread identifier to everything
  # downstream -- `parse_block` cannot tell `raise` from the body's first name.
  #
  # ANCHORED BY ITS NEXT LINE, and not on `self.parse_raise_effect()` alone: that line
  # appears THREE times in this file (1605, 2039 and here), so a bare anchor would have
  # mutated whichever came first -- a different function entirely -- and the gate would have
  # been reporting on a change nobody made.
  @{
    Name = 'M2 the raise/noraise clause is not read'
    File = $PARSER
    Find = "  self.parse_raise_effect()`n  let (_, _) = self.parse_block(false)"
    Repl = "  let _ = 0`n  let (_, _) = self.parse_block(false)"
    MustRed = '0471: a literal with `raise E` parses'
  }

  # M3 THE ORIGINAL DEFECT, RESTORED LITERALLY. Both calls gone: the function as it shipped
  # before this increment, reached from the same call site.
  @{
    Name = 'M3 neither tail is read -- the original defect'
    File = $PARSER
    Find = "  if self.at(TArrow) {`n    let _ = self.bump()`n    let _ = self.return_annotation()`n  }`n  self.parse_raise_effect()"
    Repl = '  let _ = 0'
    MustRed = '0471: a literal with `-> T raise E` parses'
  }

  # M4 THE GUARD IS REMOVED, which is the DANGEROUS direction and the one the parse rows
  # below cannot see. Without `if self.at(TArrow)`, `return_annotation()` runs on an
  # UNTAILED literal and consumes the BODY's first token as a type -- so the untailed form,
  # which works today and is everywhere in the six corpora, would start losing its body.
  # Every "a literal with a tail parses" row would still be green; only the untailed row and
  # the corpus numbers would move.
  @{
    Name = 'M4 the TArrow guard is removed, so an untailed literal loses its body'
    File = $PARSER
    Find = "  if self.at(TArrow) {`n    let _ = self.bump()`n    let _ = self.return_annotation()`n  }"
    Repl = "  let _ = self.bump()`n  let _ = self.return_annotation()"
    MustRed = '0471: an untailed literal still parses'
  }

  # M5 THE TAIL IS READ AND THEN THE CURSOR IS PUT BACK. The inert version: every clause is
  # still parsed, so a reader of this function sees all the right calls, and the cursor
  # never moves, so `parse_block` still meets `->`. This is the shape a "harmless-looking"
  # refactor takes when it copies the reader without the `bump`.
  @{
    Name = 'M5 the tail is read and the cursor is restored, so it is read for nothing'
    File = $PARSER
    Find = "  if self.at(TArrow) {`n    let _ = self.bump()`n    let _ = self.return_annotation()`n  }"
    Repl = "  let _ = self.bump()`n  let _ = self.return_annotation()`n  self.p = self.p - 1"
    MustRed = '0471: a literal with a return annotation parses'
  }
)

Write-MutationGateVerdict -Name '0471'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

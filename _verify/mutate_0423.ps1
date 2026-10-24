# 0.4.23 mutation gate.
#
# Nine mutations over one clause: the `raise` effect annotation, read in two
# positions (after a function signature, and inside a function TYPE). As in 0.4.22
# the set is deliberately not one-per-guard: M7 and M8 are the SAME guard mutated
# in opposite directions, because a guard that admits too much and a guard that
# admits too little fail in completely different ways and only one of them is the
# bug you were actually worried about.
#
#   M1  the signature call site removed     -> every `-> T raise` file dies at
#                                             "expected '{'" again
#   M2  the type-position call site removed -> `() -> T raise` dies at
#                                             "expected ')'"; this is the one that
#                                             was silently missing at first
#   M3  `raise` never matched by name       -> the long form stops being read
#   M4  the `!` short form never taken      -> `-> String!` stops being read
#   M5  the `raise` keyword not consumed    -> `raise` is read as the effect TYPE
#   M6  the effect type never read          -> `raise E` leaves `E` at the cursor
#   M7  the type-head guard admits EVERYTHING-> a bare `raise` swallows the body
#                                             `{` or the closing `)` -- a SILENT
#                                             misparse, the dangerous direction
#   M8  the type-head guard admits NOTHING   -> every named effect stops being read
#   M9  the `guard!` bang never consumed    -> `guard! c` reads as NOT applied to
#                                             `c`: a confident FALSE POSITIVE
#                                             ("operand of '!' must be bool")
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as
# a failure so that a pattern that stops matching cannot pass silently.
#
# One clause was DELETED rather than tested. `parse_raise_effect` used to call
# `skip_indexed()` before reading the effect type; M5 removed it and the suite
# stayed 371/371 green, because `type_annotation` already calls `indexed_suffix()`
# on the name it reads. The call was unobservable, so it is gone rather than
# pinned -- and the reason is recorded at the call site so the next person does
# not "restore" it and credit it with a case it was never handling.
#
# -----------------------------------------------------------------------------
# CONVERTED to `_verify/mutate_lib.ps1`. This gate was already close: its runner
# had the SHA256 restore, the `Total tests:` COMPILE-ERR judgement, NO-OP-as-failure
# and `Expect` support, all of which the harness keeps. It was written as
# function-per-mutation (`Invoke-Mutation 'name' 'file' 'find' 'replace' 'expect'`)
# with no table, so converting it meant transposing the nine calls into a table --
# the arguments and their backtick continuation lines are carried over verbatim.
#
# What it was MISSING, and what the harness adds:
#
#   - a green BASELINE, asserted. The old runner went straight to the first
#     mutation. With no baseline, a suite that was already red produced nine
#     verdicts and, because every mutation would then also be red, nine apparent
#     kills -- the same false-green shape 0.4.29 hit in the other direction.
#   - PRE-FLIGHT. A pattern that no longer matches now stops the gate before any
#     mutation is applied, instead of being discovered one at a time.
#
# The original's line-ending comment is kept here because it matters: `moon fmt`
# rewrote the tree from LF to CRLF once, a literal multi-line pattern then matched
# NOTHING, and every mutation reported NO-OP. The harness normalises to LF and
# writes back in whatever style the file already used, for the same reason.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0423.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

$mutations = @(
  # M1 -- the whole pre-0.4.23 behaviour for signatures. `moonbit_image bmp.mbt:26`
  # and all 149 of moui's files return to reporting `expected '{'`.
  #
  # RE-ANCHORED 0503. The `?` marker put a `let bare_raise = ...` line and an `if`
  # block between the return annotation and the raise call, so the old three-line
  # anchor -- which spanned `retann = ...` straight to `parse_raise_effect()` --
  # stopped matching. Inserting lines between two pinned-adjacent lines is what
  # makes an anchor vanish; this is the FOURTH time (0467, 0487 on 0466, 0484 on
  # 0418, and now this).
  #
  # THE MUTATION IS UNCHANGED IN MEANING: the raise clause is still not read in the
  # return position, so `raise` stays at the cursor and the body dies at
  # "expected '{'". The anchor moved onto the block that still brackets the call,
  # and it is UNIQUE -- `retann = self.return_annotation()` is the declared-fn
  # spelling (the fn-literal path writes `let _ = ...`), and `(full, params,
  # retann)` names the return path's own result.
  @{
    Name = 'M1 signature call site removed (0503 re-anchor)'
    File = $PARSER
    Find = '    retann = self.return_annotation()
  }
  let bare_raise = self.at_bare_raise()
  self.parse_raise_effect()
  if bare_raise && self.at(TQuestion) {
    let _ = self.bump()
  }
  (full, params, retann)'
    Repl = '    retann = self.return_annotation()
  }
  let bare_raise = self.at_bare_raise()
  if bare_raise && self.at(TQuestion) {
    let _ = self.bump()
  }
  (full, params, retann)'
  }

  # M2 -- the one that was ACTUALLY missing when this release started. Reading the
  # clause in signature position only means `fn f(g : () -> Int raise)` dies at
  # `expected ')'` while `fn f() -> Int raise` is fine -- which is exactly the shape
  # 29 files of moui and 33 of moonbit-community use.
  #
  # RE-ANCHORED 0503, for the same reason as M1 -- and this one NEEDED THE
  # `out = out + "?"` LINE TO STAY UNIQUE, because the `bare_raise` block is now
  # written at three call sites (the function-type path, the return path and the
  # fn-literal path) and an anchor that matched all three would be ambiguous. The
  # harness removes the FIRST match, so an ambiguous anchor mutates the WRONG site
  # and reports a clean kill for it -- the one failure mode a pre-flight cannot
  # catch, because it warns and continues.
  #
  # THE MUTATION IS UNCHANGED IN MEANING: the raise clause is still not read in the
  # type position, so `raise` is left where the `)` is expected and the function
  # TYPE dies at "expected ')'".
  @{
    Name = 'M2 type-position call site removed'
    File = $PARSER
    Find = '  let bare_raise = self.at_bare_raise()
  let clause_start = self.p
  self.parse_raise_effect()
  let no_clause = self.p == clause_start
  if (bare_raise || no_clause) && self.at(TQuestion) {
    let _ = self.bump()
    out = out + "?"
  }'
    Repl = '  let bare_raise = self.at_bare_raise()
  let clause_start = self.p
  let no_clause = self.p == clause_start
  if (bare_raise || no_clause) && self.at(TQuestion) {
    let _ = self.bump()
    out = out + "?"
  }'
  }

  # M3 -- `raise` is not in the lexer's keyword table, so it arrives as a TName.
  # Matching it by anything other than its exact text stops the long form being read.
  #
  # RE-ANCHORED 0503, and this one is the AMBIGUOUS kind. The `?` marker needed a
  # helper that asks whether the clause at the cursor is a bare `raise`, and that
  # helper opens with the same `if !self.at_name("raise") {` this mutation used to
  # anchor on. The harness removes the FIRST match and only WARNS on an ambiguous
  # anchor, so the mutation would have landed on the HELPER -- a different
  # function, in a different file position -- and the gate would have reported a
  # clean kill for a change nobody made. That is the one failure mode a pre-flight
  # cannot catch, and it is the reason an anchor has to be UNIQUE and not merely
  # present.
  #
  # THE MUTATION IS UNCHANGED IN MEANING: `raise` is still matched by its exact
  # name, and `parse_raise_effect` still stops reading the long form without it.
  # The anchor now carries the `return` that follows, which is what tells the two
  # sites apart -- the helper returns `false`, this one returns nothing.
  @{
    Name = 'M3 raise never matched by name'
    File = $PARSER
    Find = 'if !self.at_name("raise") {
    return
  }'
    Repl = 'if !self.at_name("zzz_never_a_keyword") {
    return
  }'
  }

  # M4 -- `!` must be told apart from the boolean NOT operator BY POSITION. This is
  # the reminder that it is a position test and not a token scan: flipping the test
  # off only affects the short form, and the NOT-operator control test stays green
  # either way, which is what makes that control necessary.
  @{
    Name = 'M4 the ! short form never taken'
    File = $PARSER
    Find = 'if self.at(TBang) {
    let _ = self.bump()
    return
  }'
    Repl = 'if self.at(TRBrace) {
    let _ = self.bump()
    return
  }'
  }

  # M5 -- the keyword and its argument are consumed by two different lines, so each
  # can go missing on its own. Here the keyword survives, the type-head guard still
  # admits it (it is a TName), and `raise` is read as the effect TYPE -- leaving
  # `IntError` at the cursor for the body.
  @{
    Name = 'M5 the raise keyword never consumed'
    File = $PARSER
    Find = '  let _ = self.bump()
  // `-> T raise` names NO error type.'
    Repl = '  // `-> T raise` names NO error type.'
  }

  # M6 -- consuming the keyword without consuming its argument leaves the argument
  # at the cursor, and the reader then blames the body for it.
  #
  # RE-ANCHORED 0487. The anchor used to be the type read followed IMMEDIATELY by the
  # closing `}`, because that call was the last statement of `parse_raise_effect`. 0487 added
  # `eat_joined_effect(false)` after it -- the `raise E + nocancel` case, where the `+` is not
  # visible until the error type has been read -- and inserting those lines between two
  # pinned-adjacent lines is what made this anchor vanish. Same lesson as 0484's gate 0418 and
  # 0486-A's gate 0466, THIRD time.
  @{
    Name = 'M6 the effect type never read'
    File = $PARSER
    Find = '  let _ = self.type_annotation()
  // `raise E + nocancel`'
    Repl = '  // `raise E + nocancel`'
  }

  # M7 -- the dangerous direction. A bare `raise` followed by `{` or `)` would be
  # treated as naming an error type, and the body block or the closing paren would
  # be read as part of the type. That is a SILENT misparse: no error, a wrong
  # signature.
  #
  # RE-ANCHORED 0487, AND THIS ONE MATTERS MORE THAN THE PREFLIGHT MISS. `eat_joined_effect`
  # introduced a SECOND `type_head` guard with the same four lines, so the old three-line anchor
  # became AMBIGUOUS -- it matched twice, and the harness removes the FIRST match, which is now the
  # helper's guard rather than this one. The gate would have reported a clean kill for a mutation
  # applied to the wrong site, which is the one failure mode a pre-flight cannot catch: it warns
  # and continues. `if !type_head` is what distinguishes this guard from the helper's `if type_head`.
  @{
    Name = 'M7 type-head guard admits everything'
    File = $PARSER
    Find = '  let type_head = match self.peek() {
    TName(_) | TLParen | TAmp => true
    _ => false
  }
  if !type_head {'
    Repl = '  let type_head = match self.peek() {
    _ => true
  }
  if !type_head {'
  }

  # M8 -- the opposite direction, and the reason M7 is not the whole story:
  # over-strict reads nothing at all and every named effect stops being consumed.
  # Re-anchored with M7, for the same reason.
  @{
    Name = 'M8 type-head guard admits nothing'
    File = $PARSER
    Find = '  let type_head = match self.peek() {
    TName(_) | TLParen | TAmp => true
    _ => false
  }
  if !type_head {'
    Repl = '  let type_head = match self.peek() {
    _ => false
  }
  if !type_head {'
  }

  # M9 -- a SECOND defect fixed in the same release, and the only mutation here
  # whose failure mode is a FALSE POSITIVE rather than a parse error: `guard! cond`
  # was read as NOT applied to `cond`, so moonbitlang/async 0.22.4
  # `src/internal/fd_util/pipe.mbt:31` reported "operand of '!' must be bool, got
  # '[int]'" about code that compiles. Reverting this must make that kind of
  # finding reappear, not a parse error.
  @{
    Name = 'M9 the guard! bang never consumed'
    File = $PARSER
    Find = '  if self.at(TBang) {
    let _ = self.bump()
  }
  let cond = self.parse_expr()'
    Repl = '  let cond = self.parse_expr()'
  }
)

Invoke-MutationGate -Name '0.4.23' -Target 'js' -Mutations $mutations
Write-MutationGateVerdict -Name '0.4.23 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
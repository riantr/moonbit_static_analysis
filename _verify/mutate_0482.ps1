# Mutation gate 0482 -- the C-style `for` CLAUSE LIST is POSITIONAL, not separator-gated.
#
# WHAT THIS PINS. `bmp.mbt:117-119` separates a three-clause `for` header with LINE BREAKS:
#
#     for i = 0
#         i < num_colors && i * 4 + palette_offset + 3 < self.data.length()
#         i = i + 1 {
#
# The old chain gated the condition and the update behind one `if self.at(TSemi)`, so a header
# with no semicolon skipped the WHOLE clause list and `parse_block` reported `expected '{'` at
# the condition token. That was moonbit_image's last unreadable file.
#
# Measured: moonbit_image `parsed 17 -> 18`, `unreliable 13 -> 0`, `withheld 0 -> 0`,
# `notices 207 -> 218`, `actionable 0 -> 0`. 18/18 -- the corpus is closed, quarantine empty.
# FIVE of six pinned corpora are now closed (moui 608/608, moonbit_labeler 37/37,
# moonbit_image 18/18, proton 137/137, proton_contract 4/4); only async is short, at 403/419.
#
# `_verify/settle_0482_for_header_no_semicolons.ps1`, 3 controls + 3 claims + 6 recorded, GATE OK:
#   ACCEPT  three clauses on three lines with no `;`
#   ACCEPT  init + condition, no update
#   ACCEPT  a `&&`/`<` chain spanning two comparisons
#   REJECT(3002)  all on ONE line -- the line breaks are LOAD-BEARING, not optional punctuation
#   REJECT(3002)  semicolon before the condition and a line break before the update
#   REJECT(3002,4021)  the head on the line after the `for`
#
# THE SEED OF EVERY MUTATION BELOW IS THE SAME NON-LOCAL FACT: `parse_is` (parser.mbt:3779)
# consumes trailing newlines UNCONDITIONALLY, before testing for its own `is` continuation. So
# by the time any clause reader looks, a newline-separated clause is INDISTINGUISHABLE from an
# adjacent one. M1 is the mutation that says the chain must not ask about separators at all;
# M2..M4 each break one clause slot. A corpus number cannot see any of them, because every one
# of them leaves the file parsing -- they just move what gets read.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0482' -Target 'wasm' -Mutations @(

  # M1 BACK TO THE SEPARATOR GATE. This is the defect as it shipped, and it is ALSO the first
  # draft of this increment's fix: `at_sep()` is the natural reading of "a `;` or a line
  # break" and it does not fire, because `parse_is` already ate the newline. Restoring the
  # gate is what an implementer does by reflex, so the gate has to be the thing that fails.
  @{
    Name = 'M1 the clause list is gated on a typed separator again'
    File = $PARSER
    Find = @'
  if self.at(TSemi) {
    let _ = self.bump()
  }
  if !self.at(TSemi) && !self.at(TLBrace) && !self.at(TEOF) {
    cond = self.parse_expr()
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if self.at(TSemi) {
    let _ = self.bump()
    if !self.at(TSemi) && !self.at(TLBrace) {
      cond = self.parse_expr()
    }
  }
'@.Replace("`r`n", "`n")
    MustRed = '0482: a newline-separated for header desugars to SLet + SWhile with its condition read'
  }

  # M2 THE CONDITION IS NEVER READ. The chain still runs, still reaches the brace, and the file
  # still parses -- the loop just becomes unconditional. This is the failure that a corpus
  # scan is worst at: `actionable` stays 0, `parsed` stays 18/18, and the only difference is
  # that a `for` body which should stop now runs to the end of its bound in the analysis.
  #
  # THE FIRST DRAFT OF THIS MUTATION DID NOT COMPILE, and the gate said so rather than
  # guessing: the replacement was `let _ = cond`, which leaves `cond` declared `mut` and never
  # assigned, and `moon test --deny-warn` rejects the unused mutability as Error [0015]. A
  # COMPILE-ERR row is a SHAPE check, not a mutation -- it tells you the edit was malformed and
  # nothing at all about the code. The replacement below still assigns `cond`, so `mut` earns
  # itself, and what survives the edit is the actual claim: the clause is skipped.
  @{
    Name = 'M2 the condition clause is never read'
    File = $PARSER
    Find = @'
  if !self.at(TSemi) && !self.at(TLBrace) && !self.at(TEOF) {
    cond = self.parse_expr()
  }
'@.Replace("`r`n", "`n")
    Repl = '  cond = { span: sp, kind: @ast.EBool(true), }'
    MustRed = '0482: a newline-separated for header desugars to SLet + SWhile with its condition read'
  }

  # M3 THE UPDATE IS PARSED AND THEN THROWN AWAY. The clause is still read, still consumed,
  # still leaves the cursor on the brace -- and the statement does not reach the tree, so the
  # loop body loses its step. Nothing reports: `parsed` stays 18/18, `actionable` stays 0, and
  # the scan is byte-identical apart from the body being one statement shorter in every loop
  # that has an update clause.
  #
  # This is the shape 0478 called "parsed but not read" and 0481 repeated one layer down, and it
  # is why this gate asserts on the RENDERED loop body rather than on `first_error`. The first
  # draft of this row was "the `TEOF` guard is dropped from the update clause"; it was
  # replaced because the mutated parser then calls `parse_stmt` at end of input, where nothing
  # guarantees the cursor advances -- a mutation gate that can hang is worse than no mutation,
  # because it looks like a slow run rather than a bad question.
  @{
    Name = 'M3 the update clause is read and then discarded'
    File = $PARSER
    Find = @'
  for u in updates {
    loop_body.push(u)
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  updates = []
  for u in updates {
    loop_body.push(u)
  }
'@.Replace("`r`n", "`n")
    MustRed = '0482: a newline-separated for header desugars to SLet + SWhile with its condition read'
  }

  # M4 THE EMPTY MIDDLE SLOT IS NOT EMPTY ANY MORE. `for i = (0, 1); ; i = i + 1 {` is 0472's
  # `ctl_tuple_comma`, an ACCEPTed program whose condition slot holds nothing, and `skip_seps`
  # instead of one separator at a time collapses it -- which reads the update into the
  # condition slot. This is the mutation that went wrong DURING this increment and turned a
  # passing 0472 row red, which is exactly why it is pinned rather than left to memory.
  @{
    Name = 'M4 both separators are consumed at once, so an empty clause slot is not empty'
    File = $PARSER
    Find = @'
  if self.at(TSemi) {
    let _ = self.bump()
  }
  if !self.at(TSemi) && !self.at(TLBrace) && !self.at(TEOF) {
    cond = self.parse_expr()
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  self.skip_seps()
  if !self.at(TLBrace) && !self.at(TEOF) {
    cond = self.parse_expr()
  }
'@.Replace("`r`n", "`n")
    MustRed = '0472: a tuple in the initializer value is one binding, not two'
  }
)

Write-MutationGateVerdict -Name '0482'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

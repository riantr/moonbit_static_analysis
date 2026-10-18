# Mutation gate 0487 -- the FULL `+`-joined effect clause, `-> T <effect> + <effect>`.
#
# WHAT THIS PINS, AND WHY IT IS NOT A WIDER 0486. Gate 0486 shipped one spelling and left the
# rest to a settle. Settle 0487 (`_verify/settle_0487_combined_effect_order.ps1`, 21 rows /
# 6 controls, GATE OK) settled the whole clause, and the answer is a RULE rather than a list:
#
#     => EXACTLY TWO EFFECTS, EXACTLY ONE OF WHICH IS `nocancel`, THE OTHER BEING `noraise`
#        OR `raise [E]`, IN EITHER ORDER.
#
#     ACCEPT    -> T noraise + nocancel         <- 0486's spelling
#     ACCEPT    -> T raise + nocancel           <- 0486's DECLARED SURVIVOR
#     ACCEPT    -> T raise MyErr + nocancel
#     ACCEPT    -> T nocancel + noraise         <- 0486 REFUSED THIS LEGAL PROGRAM
#     ACCEPT    -> T nocancel + raise
#     ACCEPT    -> T nocancel + raise MyErr
#
#     REJECT 3002  -> T ! + nocancel             <- `!` is TBang, so a NAME guard excludes it
#     REJECT 3002  -> T noraise + raise MyErr    <- ORDER, see below
#     REJECT 3002  -> T raise MyErr + raise MyErr2
#     REJECT 3002  -> T noraise + nocancel + noraise   <- exactly two, never a chain
#     REJECT 4074  fn f() noraise + nocancel { () }    <- still needs an annotation
#
# TWO ASYMMETRIES, and each is a MUTATION here rather than a claim in a comment:
#
#   1. THE ORDER IS THE RULE. `left_was_nocancel` is not a convenience flag. Drop it (M2) and the
#      reader accepts `noraise + raise MyErr`, which the compiler refuses.
#   2. THE ARITY BELONGS TO THE ORDER, NOT THE WORD. `raise` alone takes an optional `E`, and that
#      `E` is legal ONLY when `raise` is SECOND. Skip it (M3) and `MyErr` is left to be parsed as
#      code; give it to the first position and the reader accepts a program `moon check` rejects.
#
# BOTH FAILURE DIRECTIONS ARE SILENT, which is the reason this is settled rather than discovered:
# reading an illegal program removes no blocker from any corpus, so no pinned number moves either
# way. Every mutation here is therefore killed by a ROW, and the rows exist for that reason.
#
# *** M2 IS THE ONE 0486 COULD NOT KILL. *** 0486's M4 declared "drop the `noraise`-first test"
# UNOBSERVABLE and shipped a Prove saying no legal pair starts with a bare `nocancel`. Row B1 says
# otherwise. M3 below is that mutation, re-aimed, and it is now KILLED.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE. fmt both rewraps one line into several
# and collapses several into one, and either way a stale anchor is a PREFLIGHT MISS that runs no
# suite at all.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0487' -Target 'wasm' -Mutations @(

  # M1 THE JOIN GUARD IS GONE: `eat_joined_effect` consumes `+` and whatever NAME follows. This is
  # the liberal direction -- `noraise + whatever` is REJECT 3002 and no corpus writes it, so the
  # defect is invisible in every number this repository pins. The row is the only instrument.
  @{
    Name = 'M1 the join guard is dropped, so + is followed by any name'
    File = $PARSER
    Find = @'
  let joins = if left_was_nocancel {
    right == "noraise" || right == "raise"
  } else {
    right == "nocancel"
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  let joins = true
'@.Replace("`r`n", "`n")
    MustRed = '0486: an arbitrary effect after the + is not read'
  }

  # M2 THE ORDER IS DROPPED -- both directions accept any effect, so `noraise + raise MyErr` is
  # read. The `MyErr` is left behind and the file's first error moves, which is the row that sees
  # it: the toolchain REJECTs that program with 3002, so a reader that takes it is wrong.
  @{
    Name = 'M2 the order distinction is dropped, reading noraise + raise MyErr'
    File = $PARSER
    Find = @'
  let joins = if left_was_nocancel {
    right == "noraise" || right == "raise"
  } else {
    right == "nocancel"
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  let joins = right == "noraise" || right == "nocancel" || right == "raise"
'@.Replace("`r`n", "`n")
    MustRed = '0487: the error type belongs to the order, not the word'
  }

  # M3 *** THE MUTATION 0486 M4 DECLARED UNOBSERVABLE, NOW KILLABLE. *** Forcing the flag false
  # stops the join whenever `nocancel` leads, so `nocancel + noraise` -- a program the toolchain
  # ACCEPTS, and the one 0486 refused -- goes unread. 0486's Prove said no such pair existed; row
  # B1 of the 0487 settle is the pair, and this row is what turned the verdict.
  @{
    Name = 'M3 left_was_nocancel is forced false, so nocancel + noraise stops being read'
    File = $PARSER
    Find = '    let left_was_nocancel = self.at_name("nocancel")'
    Repl = '    let left_was_nocancel = false'
    MustRed = '0487: nocancel + noraise reads'
  }

  # M4 THE SECOND EFFECT'S ERROR TYPE IS NOT READ. `nocancel + raise MyErr` parses, and `MyErr`
  # is then parsed as an expression in the body's position. Silent, and it is the reason the
  # body row exists: the file parses and the tree below is wrong.
  #
  # NOTE THE GUARD IS JUST `right == "raise"`, with no `left_was_nocancel` conjunct -- that
  # conjunct was removed as provably REDUNDANT (see the note in the source). So this mutation
  # disables the arity rule outright rather than narrowing it, which is why there is no separate
  # mutation for "the arity fires in the wrong order": with the conjunct gone that shape no
  # longer exists to mutate, and the ORDER is pinned one line up in `joins` by M2.
  @{
    Name = 'M4 the second effect''s optional error type is not read'
    File = $PARSER
    Find = @'
  if right == "raise" {
'@.Replace("`r`n", "`n")
    Repl = @'
  if false && right == "raise" {
'@.Replace("`r`n", "`n")
    MustRed = '0487: nocancel + raise reads, bare and with an error type'
  }

  # M5 THE `raise` ARM NEVER REACHES THE JOIN. `raise + nocancel` and `raise MyErr + nocancel`
  # are both ACCEPT, and both are read by the ordinary `-> T raise E` path that stops before the
  # `+`. Two rows name them, and the second one is why they are separate assertions: the typed and
  # bare forms land at DIFFERENT places in the arm, since `+` is not a type head.
  @{
    Name = 'M5 the raise arm never calls the join'
    File = $PARSER
    Find = @'
    let _ = self.eat_joined_effect(false)
    return
  }
  // No `skip_indexed()` here
'@.Replace("`r`n", "`n")
    Repl = @'
    return
  }
  // No `skip_indexed()` here
'@.Replace("`r`n", "`n")
    MustRed = '0487: raise + nocancel reads, bare and with an error type'
  }

  # M6 AND THE TYPED HALF SPECIFICALLY, which M5 cannot see. `raise E + nocancel` puts the `+`
  # AFTER the type annotation, so the join has to be asked a second time at the end of the arm.
  # Without this row, M5's kill would leave the typed spelling pinned by nothing.
  @{
    Name = 'M6 the join after a typed raise effect is not read'
    File = $PARSER
    Find = @'
  let _ = self.type_annotation()
  // `raise E + nocancel`: the error type is read FIRST, so the `+` is not visible until after
  // this line. A reader that only checked for the join before the type would read the bare form
  // and miss this one.
  let _ = self.eat_joined_effect(false)
'@.Replace("`r`n", "`n")
    Repl = @'
  let _ = self.type_annotation()
'@.Replace("`r`n", "`n")
    MustRed = '0487: raise + nocancel reads, bare and with an error type'
  }

  # M7 THE BANG ARM JOINS TOO. `!` is `TBang` while the three names are `TName`, so the guard in
  # `eat_joined_effect` excludes it STRUCTURALLY and there is no canary row in the source keeping
  # it out -- which is a claim worth a mutation rather than a comment. Widening the clause from
  # "the next NAME is an effect" to "the next TOKEN is an effect" would read `! + nocancel`, which
  # the toolchain REJECTs with 3002 (settle row A2), and it would also read `! + noraise`, which
  # it rejects too (row B3).
  @{
    Name = 'M7 the bang arm joins with + like an effect'
    File = $PARSER
    Find = @'
  if self.at(TBang) {
    let _ = self.bump()
    return
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if self.at(TBang) {
    let _ = self.bump()
    let _ = self.eat_joined_effect(false)
    return
  }
'@.Replace("`r`n", "`n")
    MustRed = '0487: the bang form does not pair'
  }
)

Write-MutationGateVerdict -Name '0487'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

# Mutation gate 0486 -- a `+`-JOINED EFFECT clause, `-> T noraise + nocancel`.
#
# WHAT THIS PINS. `parse_raise_effect` consumed `noraise` and returned, leaving `+ nocancel` to be
# read as code. It is the boundary line of `src/internal/coroutine/async_primitive.mbt:16` -- a
# file that read ZERO lines -- and of `internal/coroutine/coroutine.mbt:100`.
#
# Measured: async `parsed 411 -> 413`, `unreliable 65 -> 41`, `withheld 25 -> 17`,
# `notices 1812 -> 1821`, `total 1877 -> 1862`, `actionable 0 -> 0`. TWO files closed, not one --
# the ranked list named the construct and under-counted the sites, which is the third time that
# list has been wrong in a different way.
#
# `_verify/settle_0486_append_nextline_and_effects.ps1`, 13 rows / 5 controls, GATE OK:
#   ACCEPT      `fn f() -> Unit noraise + nocancel { () }`
#   REJECT(3002) `fn f() -> Unit raise + noraise { () }`
#                 "unexpected token `noraise`, you may expect `nocancel`"
#   REJECT(4074) `fn f() noraise + nocancel { () }`   -- the combined effect needs an annotation
#
# *** RE-ANCHORED 0487, AND ONE MUTATION IS RETIRED BECAUSE ITS VERDICT IS NOW FALSE. ***
# 0487 settled the WIDER clause and generalised this gate's inline block into
# `Parser::eat_joined_effect`. Three mutations were re-pointed at the call site and the helper;
# M4 is RETIRED because it asserted that dropping the `noraise`-first test was UNOBSERVABLE, and
# settle 0487 row B1 settled `nocancel + noraise` ACCEPT -- so the mutation is observable, and
# `mutate_0487` M3 now KILLS it. A survivor that later becomes killable is not an error in the
# earlier verdict: it was unobservable given the set of legal programs known AT THAT TIME, and the
# remedy is a wider settle, not a quieter claim. This is the same shape as 0458's M4 retirement.
#
# THE DIRECTION THIS PROJECT HAS NEVER TAKEN. Looping over effect names would read a program the
# compiler refuses. Accepting an illegal program removes no blocker, so NO corpus number would
# ever move and the defect would be invisible until someone wrote the program. M2 is the row that
# makes the narrowness load-bearing rather than incidental.
#
# ONE FIX COVERS THREE CALL SITES (parser.mbt:1633, :2127, :5875): a signature, a function type
# and a parameter position all route here, so there is one grammar and one reader.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE -- fmt collapsed `if c { stmt }` onto one
# line in 0485, and a multi-line anchor written before fmt is a PREFLIGHT MISS that runs no suite
# at all.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0486' -Target 'wasm' -Mutations @(

  # M1 THE CLAUSE IS GONE, which is the pre-0486 behaviour. Loud: the `+` is read as an
  # expression, the body is never reached, and every corpus file with this clause stays blocked.
  # Re-pointed from the inline block to the CALL that replaced it, so the mutation is still
  # "this arm reads no join" rather than "some helper is missing".
  @{
    Name = 'M1 the combined effect clause is removed'
    File = $PARSER
    Find = @'
    let _ = self.bump()
    let _ = self.eat_joined_effect(left_was_nocancel)
    return
'@.Replace("`r`n", "`n")
    Repl = @'
    let _ = self.bump()
    return
'@.Replace("`r`n", "`n")
    MustRed = '0486: a combined effect clause reads before the body'
  }

  # M2 THE CLAUSE IS GENERALISED TO ANY EFFECT AFTER `+`, which is the over-correction: it reads
  # `raise + noraise`, a program `moon check` REFUSES with 3002. Nothing in any corpus writes it,
  # so this mutation is invisible to every pinned number in the repository -- which is exactly why
  # it needs a row rather than a corpus.
  @{
    Name = 'M2 the clause accepts ANY effect after the +, reading an illegal pair'
    File = $PARSER
    Find = '    right == "nocancel"'
    Repl = '    true'
    MustRed = '0486: an arbitrary effect after the + is not read'
  }

  # M3 THE `+` IS CONSUMED BUT NOT ITS OPERAND, leaving `nocancel` to be read as a name in the
  # body's position. The two readers then disagree about where the function ends, which is a
  # quieter failure than M1 and the reason the body row exists.
  #
  # The anchor's THIRD line follows `eat_joined_effect`'s arity guard, which lost a redundant
  # `left_was_nocancel` conjunct in 0487 (`joins` already implies it), so this Find was re-anchored
  # once more for that reason rather than because the bump pair moved.
  @{
    Name = 'M3 the + is consumed but not its operand'
    File = $PARSER
    Find = @'
  let _ = self.bump()
  let _ = self.bump()
  if right == "raise" {
'@.Replace("`r`n", "`n")
    Repl = @'
  let _ = self.bump()
  if right == "raise" {
'@.Replace("`r`n", "`n")
    MustRed = '0486: the corpus shape reads whole'
  }

  # M4 THE `noraise`-FIRST TEST IS DROPPED. DECLARED SURVIVED in 0486, on the reasoning that no
  # legal pair starts with a bare `nocancel`. That reasoning was TRUE AND INCOMPLETE.
  #
  # RETIRED, not re-anchored, because the claim itself is now FALSE rather than merely unproven.
  # `_verify/settle_0487_combined_effect_order.ps1` row B1 settled:
  #
  #     ACCEPT   fn f() -> Unit nocancel + noraise { () }
  #
  # So `nocancel` CAN start a pair, the `was_noraise` test was refusing a LEGAL PROGRAM, and the
  # mutation is observable rather than unobservable. `mutate_0487` M3 now pins that predicate --
  # it forces `left_was_nocancel` false, which stops the join on `nocancel + noraise` and turns
  # `0487: nocancel + noraise reads` red. A retired row is not a weaker claim here: the guard it
  # made has been SUPERSEDED by a stronger one that fails.
  @{
    Name = 'M4 the noraise-first test is dropped'
    File = $PARSER
    # The Find/Repl below are DEAD TEXT and are never applied: the harness validates the shape of
    # every row before it splits live from retired, so a Retired row still has to carry all four
    # keys (mutate_0412's retired rows do the same). They are kept verbatim because they record
    # what the anchor WAS, which is the evidence for the retirement.
    Find = '    if was_noraise && self.at(TPlus) {'
    Repl = '    if self.at(TPlus) {'
    Retired = '0487 settled `nocancel + noraise` ACCEPT (settle_0487 row B1), so this mutation''s declared SURVIVED verdict is FALSE rather than merely unproven: the `was_noraise` test was refusing a program the toolchain accepts. `Parser::eat_joined_effect` replaced the inline block and the predicate is now the `left_was_nocancel` argument, which mutate_0487 M3 pins by forcing it false and killing `0487: nocancel + noraise reads`. Same supersession as 0458 M4.'
  }
)

Write-MutationGateVerdict -Name '0486'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

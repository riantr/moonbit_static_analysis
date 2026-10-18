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
# *** THE MOST IMPORTANT MUTATION HERE IS M2, AND IT IS THE DIRECTION THIS PROJECT HAS NEVER
# TAKEN. *** Looping over effect names would read `raise + noraise`, which the compiler refuses.
# Accepting an illegal program removes no blocker, so NO corpus number would ever move and the
# defect would be invisible until someone wrote the program. M2 is the row that makes the
# narrowness load-bearing rather than incidental.
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
  @{
    Name = 'M1 the combined effect clause is removed'
    File = $PARSER
    Find = @'
    if was_noraise && self.at(TPlus) {
      let pairs_with_nocancel = match self.peek2() {
        TName(n) => n == "nocancel"
        _ => false
      }
      if pairs_with_nocancel {
        let _ = self.bump()
        let _ = self.bump()
      }
    }
'@.Replace("`r`n", "`n")
    Repl = '    let _ = was_noraise'
    MustRed = '0486: a combined effect clause reads before the body'
  }

  # M2 THE CLAUSE IS GENERALISED TO ANY EFFECT AFTER `+`, which is the over-correction: it reads
  # `raise + noraise`, a program `moon check` REFUSES with 3002. Nothing in any corpus writes it,
  # so this mutation is invisible to every pinned number in the repository -- which is exactly why
  # it needs a row rather than a corpus.
  @{
    Name = 'M2 the clause accepts ANY effect after the +, reading an illegal pair'
    File = $PARSER
    Find = @'
      let pairs_with_nocancel = match self.peek2() {
        TName(n) => n == "nocancel"
        _ => false
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      let pairs_with_nocancel = match self.peek2() {
        TName(_) => true
        _ => false
      }
'@.Replace("`r`n", "`n")
    MustRed = '0486: an arbitrary effect after the + is not read'
  }

  # M3 THE `+` IS CONSUMED BUT NOT ITS OPERAND, leaving `nocancel` to be read as a name in the
  # body's position. The two readers then disagree about where the function ends, which is a
  # quieter failure than M1 and the reason the body row exists.
  @{
    Name = 'M3 the + is consumed but not its operand'
    File = $PARSER
    Find = @'
      if pairs_with_nocancel {
        let _ = self.bump()
        let _ = self.bump()
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      if pairs_with_nocancel {
        let _ = self.bump()
      }
'@.Replace("`r`n", "`n")
    MustRed = '0486: the corpus shape reads whole'
  }

  # M4 THE `noraise`-FIRST TEST IS DROPPED, so the clause would also read after a bare `nocancel`.
  #
  # DECLARED SURVIVOR, and the reason is a GAP rather than a weak mutation. Settle rows A5/A6 say
  # the toolchain refuses `noraise + raise` and `noraise + whatever`, so the narrow operand check
  # (M2) is load-bearing -- but nothing observes `nocancel + <anything>`, because the toolchain
  # licenses no such pair, so no corpus writes one, and this mutation is unobservable until
  # somebody does.
  #
  # *** SETTLING A7 SAYS `raise + nocancel` ACCEPTS, AND THIS ANALYZER DOES NOT READ IT. *** That
  # is a real missing construct, not a survivor: the `raise` arm returns before the `+`. It is
  # recorded here rather than fixed because the `+` pairs an effect with `nocancel` SPECIFICALLY,
  # which is a different shape of clause from the one this increment settled, and half-implementing
  # it on the back of a mutation gate is how the two drift. Next increment, with its own settle
  # rows and its own rows -- not folded in here.
  @{
    Name = 'M4 the noraise-first test is dropped (unobservable: no legal pair starts with nocancel)'
    File = $PARSER
    Find = '    if was_noraise && self.at(TPlus) {'
    Repl = '    if self.at(TPlus) {'
    Expect = 'SURVIVED'
    Prove = @'
No legal MoonBit pair starts with a bare `nocancel`, so nothing in any corpus or test can observe
this. The mutation is unobservable rather than harmless -- it would read `nocancel + noraise`, which
`moon check` refuses. Settle row A7 says the clause DOES pair `raise + nocancel`, and this
analyzer does not read that yet: the `raise` arm returns before the `+`. That is the next
increment's construct, and it needs its own settle and rows rather than being retrofitted here.
The observable half of the same guard -- the operand NAME -- is M2, and M2 is KILLED.
'@
  }
)

Write-MutationGateVerdict -Name '0486'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

# Mutation gate 0434 -- an arrow lambda in EXPRESSION position, and the
# lookahead that was hiding three limitations.
#
# On the harness: no runner of its own, all six rules from
# `_verify/mutate_lib.ps1` apply.
#
# THE CHANGE. An arrow lambda could not be read in expression position at all.
# Three sites knew about them -- `parse_call_args`' positional branch (bare
# `x =>` only), `parse_call_args`' named branch, and a parameter's default --
# and the parser's own comment recorded the cause without noticing it was a gap:
# "The arrow check below only runs on the positional path".
#
#   g(a => a)                 worked
#   children=_node => [c]    worked
#   f(x? : (Int) -> Unit = (_w) => ())   worked
#   g((a) => a)              died on the call's own `)`     -- a REAL GAP
#   let h = (a, b) => a + b  died on the `=`               -- a REAL GAP
#
# This was the LARGEST single cause behind wzzc-dev/moui 0.1.12's blocked files
# and I had ranked it wrong for several increments, because the scanner's reason
# strings say "unexpected token `:`" and "expected `)`" and I read those as `is`
# patterns and function types. Settled with the toolchain, twelve constructs one
# per package beside a broken canary (`_verify/probe_sweep_0434.ps1`).
#
#   M1  The `parse_expr` lambda branch is gone.
#   M2  The comprehension's own `=>` is read as a lambda -- the collision that
#       broke five comprehension tests on the first run. A comprehension's arrow
#       is spelled exactly like a lambda's.
#   M3  `at_lambda_head`'s bounds are removed: the `:` scan runs to the next `=`
#       in the FILE. DECLARED SURVIVED, with the argument below -- the doubled
#       colon in M4's guard already stops `T::` from entering the scan at all,
#       so with the guard present this row is unobservable.
#   M4  The whole regression: the doubled-colon guard AND the bounds go
#       together, which is the 0.4.29 code exactly. This is the row that is
#       killed, and the two above are split out of it so the redundancy is
#       visible rather than papered over.
#
# MustRed on all of them, because each could pass `first_error == 0` for a
# different source. M1 and M2 in particular: M1 leaves the named-argument and
# default paths working, and M2 leaves every real lambda working too.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    Name = 'M1 an arrow lambda in expression position is not read at all'
    File = $PARSER
    Find = @'
  if self.at_lambda_head() {
    let lsp = self.span()
    self.skip_lambda_head()
'@.Replace("`r`n", "`n")
    Repl = @'
  if false && self.at_lambda_head() {
    let lsp = self.span()
    self.skip_lambda_head()
'@.Replace("`r`n", "`n")
    MustRed = 'a parenthesised arrow lambda is read in let position'
  },

  @{
    Name = 'M2 a comprehension''s own arrow is read as a lambda'
    File = $PARSER
    Find = '  sources.push(self.parse_or())'
    Repl = '  sources.push(self.parse_expr())'
    MustRed = 'a comprehension''s arrow is not read as a lambda'
  },

  @{
    Name = 'M3 the lambda-head scan runs to the next = in the file again'
    File = $PARSER
    Find = @'
      if d == 0 &&
        (
          self.toks[j] == TComma ||
          self.toks[j] == TRParen ||
          self.toks[j] == TNewline ||
          self.toks[j] == TRBrace ||
          self.toks[j] == TEOF
        ) {
        return false
      }
'@.Replace("`r`n", "`n")
    Repl = ''
    Expect = 'SURVIVED'
    Prove = @'
MEASURED, not assumed: this mutation survived 489/489 green.

THE SCOPE OF THE CLAIM, and it is narrow enough to state exactly. These two
bounds and the doubled-colon guard are REDUNDANT, and each one is invisible
without the other:

  * With M4's guard present (which is the baseline this row mutates), `T::{}`
    never enters the annotated scan at all -- `annotated` is false, the `if` is
    never taken, and the scan below does not run. So the bounds cannot be
    observed from any source whose only `:` is part of a `::`.

  * With these bounds present (which is what M4 removes alongside the guard),
    the guard alone is enough: `T::{}` is rejected before the scan starts, and
    the scan's `while toks[j] != TAssign` is never reached.

WHAT IS OBSERVABLE IS THE PAIR, and M4 removes both together -- the 0.4.29 code
exactly. Applied by hand first, that reproduces the original failure precisely:
the same `T::{}` + `match self.values { true => true ... }` source measures
`PARSED 0/1 files understood (0.0%)` with the guard removed alone and
`PARSED 1/1` with the bounds removed alone, and `PARSED 0/1` with both removed.

The bounds are KEPT anyway, for the reason every other defensive check in this
parser is kept: correctness here should not depend on the other guard being
present. Deleting either to turn this row KILLED would be removing the thing the
row is about.

The scope is the suite plus the paired regression test, NOT the six corpora.
This is evidence that no source in the suite distinguishes the two bounds, not a
proof that no source anywhere does.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M4 the whole lambda-head regression: no guard and no bounds'
    File = $PARSER
    Find = @'
  let annotated = j < self.toks.length() &&
    self.toks[j] == TColon &&
    !(j + 1 < self.toks.length() && self.toks[j + 1] == TColon)
  if annotated {
    let mut d = 0
    while j < self.toks.length() && self.toks[j] != TAssign {
      if d == 0 &&
        (
          self.toks[j] == TComma ||
          self.toks[j] == TRParen ||
          self.toks[j] == TNewline ||
          self.toks[j] == TRBrace ||
          self.toks[j] == TEOF
        ) {
        return false
      }
      if self.toks[j] == TLParen || self.toks[j] == TLBracket {
        d += 1
      } else if self.toks[j] == TRParen || self.toks[j] == TRBracket {
        d -= 1
      }
      j += 1
    }
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  let annotated = j < self.toks.length() && self.toks[j] == TColon
  if annotated {
    while j < self.toks.length() && self.toks[j] != TAssign {
      j += 1
    }
  }
'@.Replace("`r`n", "`n")
    MustRed = 'a :: expression followed by a => arm is not one lambda'
  }
)

Write-MutationGateVerdict -Name '0434'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
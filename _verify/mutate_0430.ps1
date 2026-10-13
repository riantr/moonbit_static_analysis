# Mutation gate 0430 -- the `?` optional-argument shorthand, and `tok_desc`.
#
# ON THE HARNESS. This file carries NO runner of its own. It builds a mutation
# table and hands it to `_verify/mutate_lib.ps1`, so all six harness rules apply
# and a new gate cannot reintroduce a missing guard by forgetting one. Verified
# in the 0.4.30 audit: 15 gates on the harness, 0 carrying their own runner.
#
# WHAT IS BEING PINNED, and why these four and not others.
#
#   M1  Delete the whole `?` branch. The visible failure: `f(x?)` stops parsing,
#       the file dies at `expected ')'`.
#   M2  Keep the consumption, DROP the label assignment. This is the mutation
#       that matters. `?` still parses, every parse-only test stays green, and
#       the file looks fixed -- while the type lens loses the label and falls
#       back to matching arguments to parameters by INDEX. That fallback is the
#       false-positive path recorded on `ECall` in ast.mbt (six mismatches on
#       wzzc-dev/moui `core/gesture.mbt`). A mutation with no symptom is exactly
#       what a gate exists to catch, so M2 names the test that sees it.
#   M3  Render `TQuestion` in `tok_desc` as something that does not name the
#       token. The visible failure: the corpus blocker tally collapses back to
#       one anonymous `Nx` row. Before 0430 that row was `110x`, 90% of every
#       coverage blocker in wzzc-dev/moui 0.1.12.
#   M4  Drop one arm from `tok_desc`. Declared COMPILE-ERR on purpose: `tok_desc`
#       is exhaustive over all 46 `Tok` variants with no `_` arm, so removing one
#       is a non-exhaustive match that must not compile. This is rule 2 doing
#       its job -- a mutant that does not build is a mutant nobody measured, and
#       it is declared rather than dropped so the verdict is visible.
#
# ON MustRed. M1, M2 and M3 each name the test that must go red, because "killed"
# alone does not say the RIGHT thing was killed. That is harness rule 6, and it
# exists because 0.4.18's runner declared a `[string[]]$ExpectRed` parameter,
# passed the literal 'expectRed' at all twelve call sites, and never read it --
# a documented capability that was absent. M2's MustRed is the honest use of it:
# without a named test, M2 is killed by nothing that matters.
#
# Target js: these are parser-only mutations and the js suite runs in seconds.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$nl = [string][char]10

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  # ---- M1: delete the whole `?` branch -------------------------------------
  @{
    Name = 'M1 the ? argument shorthand branch is gone entirely'
    File = $PARSER
    Find = @'
    if self.at(TQuestion) {
      let _ = self.bump()
      if labels[labels.length() - 1] == "" {
        labels[labels.length() - 1] = self.name_at(arg_start)
      }
    }
'@.Replace("`r`n", "`n")
    Repl = ''
    MustRed = '0430: f(x?) parses clean and labels the argument x'
  },

  # ---- M2: consume the `?` but forget the LABEL ------------------------------
  # The symptomless one. Still parses; the type lens silently reverts to
  # index-based argument matching.
  @{
    Name = 'M2 the ? shorthand still parses but records NO label'
    File = $PARSER
    Find = @'
    if self.at(TQuestion) {
      let _ = self.bump()
      if labels[labels.length() - 1] == "" {
        labels[labels.length() - 1] = self.name_at(arg_start)
      }
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    if self.at(TQuestion) {
      let _ = self.bump()
    }
'@.Replace("`r`n", "`n")
    MustRed = 'carries the label'
  },

  # ---- M3: the message stops naming the token -------------------------------
  @{
    Name = 'M3 tok_desc stops naming the token, collapsing the blocker tally'
    File = $PARSER
    Find = @'
    TQuestion => "`?`"
'@.Replace("`r`n", "`n")
    Repl = @'
    TQuestion => "a marker"
'@.Replace("`r`n", "`n")
    MustRed = 'the unexpected-token message NAMES the offending token'
  },

  # ---- M4: drop an arm from the exhaustive match -----------------------------
  @{
    Name = 'M4 tok_desc loses a variant arm (must stop compiling)'
    File = $PARSER
    Find = @'
    TArrow => "`->`"
'@.Replace("`r`n", "`n")
    Repl = ''
    Expect = 'COMPILE-ERR'
    Prove = 'tok_desc has no `_` arm by design, so removing one variant makes the match non-exhaustive. This is the property that stops a future Tok variant landing in a fallback that names nothing -- which is the defect 0430 exists to remove. COMPILE-ERR is the correct verdict, not a failed kill: a mutant that does not build is a mutant nobody measured.'
  }
)

Write-MutationGateVerdict -Name '0430'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
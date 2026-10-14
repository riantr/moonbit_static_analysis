# Mutation gate 0437 -- `(expr : Type)`, an ascription inside parentheses.
#
# On the harness: no runner of its own, all six rules from
# `_verify/mutate_lib.ps1` apply.
#
# THE CHANGE. The grouping branch of `parse_atom`'s `TLParen` arm parsed the inner
# expression and then demanded `)`, which is where every one of the six blocked
# moui files died -- `expected ')'` on a line whose `:` is a type marker.
#
# WHY IT WAS RANKED THIRD AT THREE FILES WHEN IT BLOCKS SIX. The scanner's reason
# string for these files is `expected ')'`, which reads like a tuple or a function
# type. `_verify/blockers.ps1` joins each reason back to its blocking SOURCE LINE
# and all six turn out to be the same shape. That is the fifth time a reason
# string has been the wrong thing to rank by.
#
#   M1  The ascription branch is gone.
#   M2  The `:` is consumed but its type is not. The subtle half-fix: `('0' :
#       Int)` still reads, because a single leftover name happens to be followed
#       by `)` -- which is why this cannot be caught by the first fixture alone.
#   M3  A SUBSET-EXCLUSION NOTICE IS ADDED for the discarded type. This is the
#       mirror of gate 0435's M3, and it is killed by a CONTROL rather than a
#       positive test: the verdict here is "an ascription is an assertion, not a
#       coercion", so a notice would report a loss that does not happen.
#   M4  The branch is WIDENED to tuple elements, which `moon check` rejects. This
#       is the narrowness mutation, and it is killed by the control that asserts
#       `(1 : Int, 2)` still fails to parse.
#
# Settled one form per package with a broken canary beside it
# (`_verify/probe_sweep_0434.ps1`, canary firing):
#   `('0' : Int)`        MOON-OK   <- the only legal form, the one implemented
#   `let y = 1 : Int`    MOON-BAD  (no parentheses: rejected)
#   `(1 : Int, 2)`       MOON-BAD  (ascription on a tuple element: rejected)
#   `(s : Int)` on a String   MOON-BAD  (so: an assertion, not a coercion)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$BRANCH = @'
          if self.at(TColon) {
            let _ = self.bump()
            let _ = self.type_annotation()
          }
'@.Replace("`r`n", "`n")

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the ascription is not read at all'
    File = 'src\parser\parser.mbt'
    Find = $BRANCH
    Repl = ''
    MustRed = 'an ascription inside parentheses is read'
  },

  @{
    Name = 'M2 the colon is consumed but only ONE token of the type'
    File = 'src\parser\parser.mbt'
    Find = @'
          if self.at(TColon) {
            let _ = self.bump()
            let _ = self.type_annotation()
          }
'@.Replace("`r`n", "`n")
    Repl = @'
          if self.at(TColon) {
            let _ = self.bump()
            let _ = self.bump()
          }
'@.Replace("`r`n", "`n")
    MustRed = 'a qualified-type ascription keeps the call and the chain after it'
  },

  @{
    Name = 'M3 a subset-exclusion notice is invented for the discarded type'
    File = 'src\parser\parser.mbt'
    Find = @'
          if self.at(TColon) {
            let _ = self.bump()
            let _ = self.type_annotation()
          }
'@.Replace("`r`n", "`n")
    Repl = @'
          if self.at(TColon) {
            let asp = self.span()
            let _ = self.bump()
            let _ = self.type_annotation()
            self.note_skip(
              "ascription type is outside the analyzed subset; it was read but not analysed",
              asp,
            )
          }
'@.Replace("`r`n", "`n")
    MustRed = 'a grouping paren without an ascription is unchanged'
  },

  @{
    Name = 'M4 the branch is widened to TUPLE ELEMENTS, which moon check rejects'
    File = 'src\parser\parser.mbt'
    Find = @'
        let e = self.parse_expr()
        if self.at(TComma) {
'@.Replace("`r`n", "`n")
    Repl = @'
        let e = self.parse_expr()
        if self.at(TColon) {
          let _ = self.bump()
          let _ = self.type_annotation()
        }
        if self.at(TComma) {
'@.Replace("`r`n", "`n")
    MustRed = 'the two forms the toolchain rejects are still rejected'
  }
)

Write-MutationGateVerdict -Name '0437'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
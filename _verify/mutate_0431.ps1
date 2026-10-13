# Mutation gate 0431 -- a lambda as a PARAMETER DEFAULT.
#
# On the harness: this file carries no runner of its own. It builds a table and
# hands it to `_verify/mutate_lib.ps1`, so all six harness rules apply. Verified
# in the 0.4.30 audit: 15 gates on the harness, 0 carrying their own runner.
#
# The shape under test, settled with `moon check` (0 errors, canary-guarded, one
# form per package -- `_verify/grammar_probe.ps1`):
#
#   sync? : (Int, Int) -> Unit = (_w, _m,) => (),     <- multi-line
#   sync? : (Int) -> Unit = (_w) => ()                 <- single-line
#   notify? : (NotificationRequest) -> ServiceTask[Unit] = _request => { .. } <- brace body
#
# Before this gate those shapes killed the file with `expected ')'`. They appear
# behind FIVE different rows of the moui NOTPARSE tally, because the cascade
# lands in a different place per file -- which is why the tally alone made this
# look like five separate bugs.
#
#   M1  Delete the lambda-default branch entirely.
#   M2  Keep the branch but skip a BRACE body with the comma boundary instead of
#       `skip_braces`. The parameter list after a brace-bodied default gets
#       swallowed, so the function ends up with too few parameters -- silent
#       unless the count is asserted.
#   M3  Drop the `note_skip`. The file then parses with NO notice at all: the
#       lambda body is skipped and nothing says so. This is the mutation that
#       matters most for honesty, and it is why the tests assert the notice is
#       PRESENT rather than asserting "no reports".
#   M4  Drop the ordinary (non-lambda) default path. Guards the else-branch: a
#       fix that captured every `=` would send plain defaults down the lambda path.
#
# MustRed on all four. "Killed" alone does not say the right thing went red, and
# M3 in particular is the kind of mutation a count-only gate would report as
# SURVIVED rather than as a lie.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the lambda-as-parameter-default branch is gone entirely'
    File = $PARSER
    Find = @'
      if self.at_lambda_head() {
        let lsp = self.span()
        self.skip_lambda_head()
        if self.at(TLBrace) {
          self.skip_braces()
        } else {
          self.skip_to_arg_boundary()
        }
        self.note_skip(
          "short lambda is outside the analyzed subset; it was read but not analysed",
          lsp,
        )
      } else {
        ignore(self.parse_expr())
      }
'@.Replace("`r`n", "`n")
    Repl = ''
    MustRed = '0431: a single-line lambda default parses'
  },

  @{
    Name = 'M2 a BRACE body is skipped with the comma boundary instead of skip_braces'
    File = $PARSER
    Find = @'
        self.skip_lambda_head()
        if self.at(TLBrace) {
          self.skip_braces()
        } else {
          self.skip_to_arg_boundary()
        }
'@.Replace("`r`n", "`n")
    Repl = @'
        self.skip_lambda_head()
        self.skip_to_arg_boundary()
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = @'
Measured, not assumed -- this mutation survived and the honest verdict is that
the two skips are EQUIVALENT here, not that the branch is untested.

`skip_to_arg_boundary` tracks brace depth: it opens on TLBrace/TLParen/TLBracket
and closes on TRBrace/TRParen/TRBracket (parser.mbt:3048-3051), returning before
a depth-0 `,` or `)`. A lambda's brace body is therefore skipped whole and the
cursor lands on the same `,` that `skip_braces` leaves it on. The `if at(TLBrace)`
arm is a readability choice that mirrors the call-argument path, not a behaviour
switch, and this mutation is the evidence for saying so.

It was first written expecting KILLED and the gate said SURVIVED. Inventing a
test to make a stylistic branch look load-bearing would be the wrong repair; the
branch has no load to bear. What would be wrong is deleting this row, which is
why the verdict is declared with its argument instead.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M3 the skip notice is dropped -- the lambda body vanishes silently'
    File = $PARSER
    Find = @'
        self.note_skip(
          "short lambda is outside the analyzed subset; it was read but not analysed",
          lsp,
        )
'@.Replace("`r`n", "`n")
    Repl = ''
    MustRed = 'a multi-line lambda default parses'
  },

  @{
    Name = 'M4 an ORDINARY default value is no longer consumed'
    File = $PARSER
    Find = @'
      } else {
        ignore(self.parse_expr())
      }
    }
    params.push({ name: pname, tyann: ann, span: psp, })
'@.Replace("`r`n", "`n")
    Repl = @'
      } else {
      }
    }
    params.push({ name: pname, tyann: ann, span: psp, })
'@.Replace("`r`n", "`n")
    MustRed = 'an ordinary default value still parses'
  }
)

Write-MutationGateVerdict -Name '0431'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
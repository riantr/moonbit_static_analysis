# Mutation gate 0469 -- a `match` whose arms are skipped, and what its value is.
#
# WHAT THIS PINS. `parser.mbt`'s `TName("match")` arm used to read the subject and YIELD
# IT. That is the one place in the parser where "the expression I had to parse to keep the
# token stream in step" and "the value this expression produces" are different things: a
# `match`'s value is the join of its ARMS, and the arms are what this analyzer skips.
#
# Measured on moonbit_image 0.3.7 `png.mbt:980`:
#
#     operand of '!' must be bool, got 'int'
#
# for `!vok`, because `let vok = match bd { .. }` typed `vok` as `bd`'s type. That was
# moonbit_image's `actionable`. 0468 did not cause it; 0468 made the file readable.
#
# `EMatch(subject)` carries the subject and says NOTHING about the value: `walk_expr`
# descends (the subject is real code, so its reads are real), `ty_of` answers Unknown (the
# arms' join is not available), `eval` runs the subject for its effects and yields
# `ABottom`.
#
# THE OBVIOUS FIX WAS WRONG AND WAS WRITTEN AND MEASURED FIRST. Yielding the bare `EBigInt`
# that the anonymous-`fn` arm uses fixes the type and LOSES THE SUBJECT'S READS, which
# turns two TRUE positives in `pipeline_0433_test.mbt` into false negatives. It passed the
# corpus and failed two unit tests.
# => 判据: "the fix removed the finding" is not the same claim as "the fix removed the
# defect". M2 and M3 are the half of this gate that would have caught it.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$WALK = 'src\walk\walk.mbt'
$INFER = 'src\types\infer.mbt'

Invoke-MutationGate -Name '0469' -Target 'wasm' -Mutations @(

  # M1 THE ORIGINAL DEFECT, RESTORED. The subject is the match's value again.
  @{
    Name = 'M1 the match yields its subject again'
    File = $PARSER
    Find = '      { span: sp, kind: @ast.EMatch(subject), }'
    Repl = '      subject'
    MustRed = '0469: `!` on a match-bound value is not an operator mismatch'
  }

  # M2 THE SUBJECT IS NOT WALKED. This is the half that makes dropping the subject
  # unacceptable, and it is the mutation the first version of this increment would have
  # needed to justify. It is not decoration: without it M1 could be "fixed" by discarding
  # and two true positives would quietly vanish.
  #
  # MUST-RED WAS MEASURED, NOT GUESSED. It first named `a read inside a match subject
  # still counts as a use`, which asserts UnusedParam == 0 -- and that row is VACUOUS,
  # because a `match` silences UnusedParam for its whole enclosing function by design, so
  # it is 0 no matter what this mutation does. Removing `walk_expr`'s `EMatch` arm
  # reddens exactly three rows, and this is the 0469 one:
  #
  #   0469: an undefined name in a match subject is still reported
  #   0433: a match subject on the next line is read, not skipped
  #   0433 control: a match subject on the same line is read too
  #
  # => 判据: before keeping a negative row, ask whether ANY mutation can turn it red.
  @{
    Name = 'M2 the match subject is carried but never walked'
    File = $WALK
    Find = '    EMatch(subject) => self.walk_expr(subject)'
    Repl = '    EMatch(_) => ()'
    MustRed = '0469: an undefined name in a match subject is still reported'
  }

  # M3 THE COLLECTOR IS A SEPARATE ARM. Same lesson as 0467's M7 and 0468's M8: two arms
  # of one `match` are two arms, and a fixture that exercises only one leaves the other
  # unmeasured. The first version of this row put a `catch` in the subject and asserted
  # ZERO UndefinedNames -- which is 0 whether or not the collector descends, and M3
  # survived 857/857 for exactly that reason. The row now makes a BINDING inside the
  # subject and reads it there, which only the collector can satisfy.
  @{
    Name = 'M3 a match subject is never scanned for bindings'
    File = $WALK
    Find = '    EMatch(subject) => collect_expr_bindings(bs, subject)'
    Repl = '    EMatch(_) => ()'
    MustRed = '0469: a binding made inside a match subject is visible to the subject'
  }

  # M4 THE TYPE LENS ANSWERS WITH THE SUBJECT. M1 removes the node; M4 keeps the node and
  # reintroduces the same wrong ANSWER through the other door. Both were real ways this
  # bug could return, and a gate that only removes the node stops at the first one.
  @{
    Name = 'M4 the type lens answers Unknown with the subject''s type'
    File = $INFER
    Find = '    EMatch(_) => TUnknown'
    Repl = '    EMatch(subject) => self.ty_of(subject, hint)'
    MustRed = '0469: `!` on a match-bound value is not an operator mismatch'
  }
)

Write-MutationGateVerdict -Name '0469'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

# Mutation gate 0474 -- a loop in EXPRESSION position is dispatched to the WRONG reader.
#
# WHAT THIS PINS. `parse_atom` matches on `self.bump()`, so the loop keyword is consumed as
# the match SCRUTINEE. `parse_loop_as_expr` then chose between the two statement readers by
# re-testing `at_name("while")` -- against a cursor that had already moved past the keyword.
# The re-test is false for EVERY loop expression, so all of them went to `parse_for_stmt`,
# which bumped the token after the keyword as if it were `for`.
#
# Isolated by a temporary trace, added and then reverted, and reproduced here in the
# trigger table below so the next reader does not have to rebuild a parser to see it:
#
#     let k : Unit = while a > 0 { ignore(1) }   -> `unexpected token `>``
#     let k : Unit = while 1 < 2 { ignore(1) }   -> `unexpected token `<``
#     let k : Unit = while g(a) > 0 { ignore(1) }-> parses  (a CALL head survives it)
#     the same loops in STATEMENT position       -> parses
#
# The call-head row is why this survived so long, and `if a { while .. } else { .. }` is why
# it could have: the `if` arm SKIPS the branch whole, so a loop expression sitting inside
# one parses without being parsed at all. Neither is evidence.
#
# THE FIX restores the cursor before dispatching, so every downstream reader sees the state
# its own comments describe. One line, in each of two explicit arms.
#
# => 判据: a helper that RE-DERIVES which construct it is handling, from a cursor its caller
# has already moved, cannot be correct by construction -- the caller already knows which arm
# it matched. The two arms are separate on purpose: written as an or-pattern with this
# comment above it, `moon fmt` lays the comment out BETWEEN the alternatives and the result
# reads like a half-finished pattern.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0474' -Target 'wasm' -Mutations @(

  # M1 THE `for` ARM LOSES THE RESTORE. `for` in expression position is the shape async
  # writes at conn.mbt:486, so this is the one with a corpus site behind it.
  @{
    Name = 'M1 the `for` arm does not restore the cursor (the original defect)'
    File = $PARSER
    Find = @'
    TName("for") => {
      self.p -= 1
      self.parse_loop_as_expr(sp)
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    TName("for") => {
      self.parse_loop_as_expr(sp)
    }
'@.Replace("`r`n", "`n")
    MustRed = '0474: a for expression with a binder header is read'
  }

  # M2 THE `while` ARM LOSES IT TOO. Separate from M1 because the arms are separate, and a
  # single mutation on a shared pattern would have proved nothing about the second keyword:
  # `for` rows would be red either way.
  @{
    Name = 'M2 the `while` arm does not restore the cursor (the original defect)'
    File = $PARSER
    Find = @'
    TName("while") => {
      self.p -= 1
      self.parse_loop_as_expr(sp)
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    TName("while") => {
      self.parse_loop_as_expr(sp)
    }
'@.Replace("`r`n", "`n")
    MustRed = '0474: a while expression whose head carries an operator is read'
  }

  # M3 THE CURSOR IS RESTORED IN THE WRONG DIRECTION. `-=` becomes `+=`, so the token after
  # the keyword is skipped instead of the keyword being handed back. This is the row that
  # says the loop consumes EXACTLY itself -- and it is the one that turned out to be
  # unobservable, which is worth more as a declared fact than as a green row would be.
  # The full argument, and the measurement behind it, is in Prove.
  @{
    Name = 'M3 the cursor is stepped forward instead of restored'
    File = $PARSER
    Find = @'
    TName("for") => {
      self.p -= 1
      self.parse_loop_as_expr(sp)
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    TName("for") => {
      self.p += 1
      self.parse_loop_as_expr(sp)
    }
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = @'
MEASURED, and deliberately NOT searched for a row to kill it. The question "which test
catches this" and the question "can any test catch this" have different answers and
different verdicts, so the second one was measured instead of the first.

`_verify/measure_0474_m3.ps1` builds and scans the async corpus twice in one session,
changing only this line. Both columns:

    correct   Total tests: 924, passed: 924, failed: 0
              files=419 parsed=396 actionable=0 notices=1728 unreliable=203 withheld=31 total=1931
              20 PARTIAL (blocked-file) lines
    mutated   Total tests: 924, passed: 924, failed: 0
              files=419 parsed=396 actionable=0 notices=1728 unreliable=203 withheld=31 total=1931
              20 PARTIAL (blocked-file) lines

and the two blocked-file lists are IDENTICAL NAME FOR NAME, not merely equal in length --
the count alone would have hidden a file trading places with another. A 419-file corpus
that contains the loop-expression sites this increment is about moves not one bit, so
this is not a suite with a hole in it.

THE MECHANISM, and it is one line of the increment's own code:

    fn Parser::parse_loop_as_expr(self : Parser, sp : @core.Span) -> @ast.Expr {
      if self.at_name("while") { let _ = self.parse_while_stmt(sp) }
      else { let _ = self.parse_for_stmt(sp) }
      ...
      { span: sp, kind: @ast.EBigInt, }

The statement is DISCARDED and the value is `EBigInt` unconditionally. M3 chooses the other
reader by landing the cursor one token further on: for `for x in xs { .. }` the binder
scan then starts past the `in`, `is_c_style_for` returns true, and `parse_c_for` reads
`xs` as a C-style initializer and builds an `SBlock`+`SWhile` -- a well-formed tree that
is simply thrown away. Both readers consume the identical token range and end on the same
closing brace, so `first_error`, the statement count and the placeholder all match. That
is the worst shape a mutation can have: it does not crash, does not error, and is wrong.

WHAT WOULD KILL IT, and that is a real change rather than a missing fixture: analysing the
loop-expression body. Today the body is parsed and discarded, which `pipeline_0474_test.mbt`
pins in both directions -- an undefined name inside a loop expression's body is NOT
reported, while the same name in a statement-position loop IS. The moment a loop expression
keeps its tree, this mutation has something to be wrong about and this gate will say so.

=> 判据: "cannot fail" has to be argued from the mechanism, not inferred from a green run.
A green run is compatible with both "untested" and "unobservable", and only one of them is
acceptable to leave behind. Reach past the suite before declaring a survivor: the corpus is
a measurement the test suite structurally cannot make.
'@
  }

  # M4 M2 AGAIN, PINNED ON A PIPELINE ROW. The parser rows say the tree is right; this says
  # the right tree reaches the corpus, where a cursor that is merely close enough would lose
  # a statement silently -- a file that still parses, with code nobody looked at.
  #
  # => the same rule the four vacuous 0470 rows broke: before keeping a negative row, ask
  # whether ANY mutation can turn it red. The first draft of this increment had a row
  # asserting an unused parameter inside a loop-expression body, and its own control could
  # not turn it red either -- so it was a missing test, and it was deleted.
  @{
    Name = 'M4 the `while` arm does not restore the cursor, pinned on the pipeline row'
    File = $PARSER
    Find = @'
    TName("while") => {
      self.p -= 1
      self.parse_loop_as_expr(sp)
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    TName("while") => {
      self.parse_loop_as_expr(sp)
    }
'@.Replace("`r`n", "`n")
    MustRed = '0474 control: the statement after a loop expression is analysed'
  }
)

# NO MUTATION FOR `parse_loop_as_expr`'s OWN `at_name("while")` re-test, and that is a
# measured decision rather than an oversight. After the restore the re-test is correct, and
# the two arms above are what make it correct. Removing it would leave a single arm whose
# keyword could not be distinguished -- which is M1 and M2 again, from the other side. There
# is no separate edit here that is not one of those.

Write-MutationGateVerdict -Name '0474'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

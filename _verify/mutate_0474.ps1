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
  # the keyword is skipped instead of the keyword being handed back.
  #
  # DECLARED SURVIVED AT 0474 AND KILLED AT 0475, and the correction is the interesting part.
  # At 0474 this survived, and the reason was measured rather than assumed: both trees were
  # built and the 419-file async corpus scanned twice in one session, changing only this line,
  # and got 924/924 green with a byte-identical summary either way and the 20 blocked files
  # matching name for name. `_verify/measure_0474_m3.ps1` is that measurement, and it is
  # committed so the verdict can be re-checked rather than taken on trust.
  #
  # 0475 THEN MADE IT OBSERVABLE, AND NOT FOR THE REASON 0474 PREDICTED. The 0474 Prove said
  # this would become killable "the moment a loop expression keeps its tree" -- when the
  # loop-expression BODY starts being analysed. That never happened. What happened is that
  # 0475 added rows on a HEADER the misroute cannot swallow:
  #
  #     let total = for p in ps; len = 0 { .. } nobreak { len }
  #
  # Stepping the cursor forward sends the binder scan past the `in`, so `is_c_style_for`
  # returns true and `parse_c_for` tries to read `p in ps` as a C-style initializer, which
  # fails with three errors. Every binder head that existed at 0474 was a PLAIN one --
  # `for x in xs { .. }` -- and those survive the misroute, which is exactly why M3 was
  # unobservable then. THE MISROUTE WAS NOT HARMLESS; IT WAS SILENT ON THE HEADERS THAT
  # HAPPENED TO BE WRITTEN.
  #
  # The two rows that kill it are `0475: the corpus loop-expression shape is read` and the
  # inverted `0473: a binder head followed by a C-style clause is now READ`; both fail with
  # `3 != 0`, measured by applying this mutation by hand and reading the red list.
  #
  # => 判据: a declared survivor is a claim about the CURRENT suite, and it expires the moment
  # a row is added. The 0474 measurement was sound and the conclusion drawn from it was still
  # wrong, because "no test covers this" and "nothing can distinguish this" were separated by
  # evidence that did not yet exist. RE-RUN THE GATE RATHER THAN TRUSTING THE COMMENT: this
  # row flipped verdict without either of its two files changing, and only the 58-gate run
  # noticed -- `mutate_0474` run alone on the same tree would have failed identically, but a
  # reader trusting the `Expect = 'SURVIVED'` line would not have looked.
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
    MustRed = '0475: the corpus loop-expression shape is read'
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

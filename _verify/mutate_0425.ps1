# 0.4.25 mutation gate.
#
# Eight mutations over ONE idea: the behaviour lens must JOIN the flow of an
# `if`'s branches instead of letting the last one win.
#
# The set is deliberately built around the two ways a join can be wrong, because
# only testing one of them lets the other through:
#
#   too STRICT  -> the join says "terminated" when some branch falls through, and
#                  a false `unreachable code` comes back (M1, M2, M5, M6, M7, M8)
#   too LOOSE   -> the join says "falls through" unconditionally, and REAL dead
#                  code goes silent (M3, M4)
#
# The loose direction is the one that matters most and the one a coverage number
# can never see: a check whose precondition can never hold is the 0.4.5 failure
# mode, and it is worse than the false positive being fixed, because nothing
# reports it.
#
#   M1  a missing `else` stops falling through -> the original false positive,
#                                             back in `SIf`
#   M2  the join always terminates               -> same, louder: EVERY statement
#                                             after any `if` looks dead
#   M3  the join always falls through            -> real dead code goes silent,
#                                             EXPECTED KILLER of "over-fixing"
#   M4  the per-branch flow reset removed       -> the leak returns for the 2nd
#                                             branch onwards
#   M5  only the FIRST else-if is visited        -> the join reads one branch of
#                                             the chain and calls it a join
#   M6  `exec_alt`'s `else` always reports
#        fall-through                           -> a chain that really does
#                                             terminate goes quiet
#   M7  `exec_alt`'s missing else stops falling  -> same, one level down
#   M8  `exec_alt`'s TERMINAL missing else does   -> same, for a chain with no
#                                             else-if at all
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as
# a failure so that a pattern that stops matching cannot pass silently.
#
# THE PRE-FLIGHT EXISTS BECAUSE OF WHAT THIS FILE GOT WRONG ON ITS FIRST TWO
# RUNS. On the first, three of the seven patterns did not match the source at all
# -- M5 and M6 were written with the wrong indentation (`exec_alt`'s arms are at
# 6/8, not 10) and M7 was written as `None => true` where the arm reads
# `None => falls = true`. Each cost a full `moon test` run to learn nothing,
# because NO-OP is only reported AFTER the suite has run. So every pattern is
# now checked against the pristine text first, and an absent pattern aborts in
# milliseconds with the line it was looking for.
#
# On the second, the survivor was M6, and it was a fixture problem rather than a
# pattern problem: `exec_alt`'s terminal `match els` only runs when there are no
# else-ifs left, and every chain fixture had one. No amount of re-matching would
# have killed it. That is why M8 exists at all -- it is the statement behind M6,
# and it was equally unobserved until the survivor asked the question.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0425.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$F = 'src\interp\interp.mbt'

$muts = @(
  # --- M1: a missing `else` stops falling through ---------------------------
  # `None => flows.push(FNormal)` is the statement that a missing else falls
  # through: when no condition holds, nothing runs and control continues.
  #
  # RE-ANCHORED at 0495. The statement this mutation names was `None => falls =
  # true`, and 0495 REPLACED the `falls` flag with the branch FLOWS and
  # `join_flow` -- because a join that answered "terminated" whenever the
  # branches did not agree on a terminator was wrong about `continue` and
  # `break` (see `join_flow`'s own note). The MUTATION is the same one: the
  # missing-else arm stops contributing a fall-through flow, so the join
  # reports the branches as terminating. The ANCHOR is the current text.
  @{
    Name = 'M1 a missing else stops falling through'
    File = $F
    Find = @'
            // A MISSING else always falls through: when no branch is taken,
            // nothing runs and control continues, so it must not make the
            // statements after the `if` look dead either.
            None => flows.push(FNormal)
          }
          env.clear()
'@
    Repl = @'
            // A MISSING else always falls through: when no branch is taken,
            // nothing runs and control continues, so it must not make the
            // statements after the `if` look dead either.
            None => flows.push(FReturn)
          }
          env.clear()
'@
  }

  # --- M2: the join always terminates ---------------------------------------
  # The loud failure. Every statement after every `if` becomes dead code, so this
  # turns a precision bug into a volume bug.
  #
  # RE-ANCHORED at 0495. The join was `self.flow = if falls { FNormal } else {
  # FReturn }`, and 0495 replaced it with `self.flow = join_flow(flows)`. The
  # MUTATION is the same one -- the join reports "terminated" no matter what the
  # branches did -- and it is now expressed against the join's CALL SITE, which
  # is where the decision is made. `join_flow` itself is covered by
  # `mutate_0495.ps1` M3.
  @{
    Name = 'M2 the join always terminates'
    File = $F
    Find = @'
          self.flow = join_flow(flows)
        }
      }
    SWhile(cond, body) => {
'@
    Repl = @'
          self.flow = FReturn
        }
      }
    SWhile(cond, body) => {
'@
  }

  # --- M3: the join always falls through ------------------------------------
  # THE DANGEROUS ONE, and the reason the "real dead code" fixtures exist. If the
  # join were written as a bare `self.flow = FNormal`, every genuine
  # `unreachable code` in the language would stop being reported and nothing would
  # say so -- a check whose precondition can never hold.
  #
  # RE-ANCHORED at 0495, on the same call site as M2. The two mutations differ
  # by ONE line and are the two directions of the same decision, which is why
  # they share an anchor.
  @{
    Name = 'M3 the join always falls through'
    File = $F
    Find = @'
          self.flow = join_flow(flows)
        }
      }
    SWhile(cond, body) => {
'@
    Repl = @'
          self.flow = FNormal
        }
      }
    SWhile(cond, body) => {
'@
  }

  # --- M4: the per-branch flow reset removed ---------------------------------
  # The reset is what stops one branch from marking the NEXT branch's statements
  # dead. Removing it reinstates the original leak for the second branch onwards,
  # which is why the else-if fixture and the plain if fixture are separate tests.
  # Indent 12/12/12.
  #
  # RE-ANCHORED at 0493. The anchor was the three lines
  #
  #     let env_ei = copy_env(acc)
  #     self.flow = FNormal
  #     self.exec_block(ei.body, env_ei)
  #
  # and 0493 put the CONDITION EVALUATION between the reset and the body -- the
  # `else if` conditions were code that was never executed, and 0493 executes
  # them. The MUTATION is the same one: the per-branch flow reset is removed,
  # and with it the isolation between the branches. The ANCHOR is two lines now,
  # because that is where the reset is; the third line it used to name is still
  # there, further down, behind the condition.
  @{
    Name = 'M4 the per-branch flow reset removed'
    File = $F
    Find = @'
            let env_ei = copy_env(acc)
            self.flow = FNormal
'@
    Repl = @'
            let env_ei = copy_env(acc)
'@
  }

  # --- M5: only the first else-if is visited ---------------------------------
  # A "join" that reads a single branch is not a join. With the chain's later
  # branches unvisited, the result depends on which branch happened to be first.
  # `while j < 0` and not `while false`: a literal-false condition may draw a
  # compile warning, and a COMPILE-ERR here would be indistinguishable from a kill.
  @{
    Name = 'M5 only the first else-if is visited'
    File = $F
    Find = @'
        let mut j = idx + 1
        // A `while` and not `for j in (idx + 1)..elseifs.length()`: the range
        // operator binds tighter than the call after it, so that expression
        // parses as `(idx + 1)..elseifs` and then `.length()`.
        while j < elseifs.length() {
'@
    Repl = @'
        let mut j = idx + 1
        // A `while` and not `for j in (idx + 1)..elseifs.length()`: the range
        // operator binds tighter than the call after it, so that expression
        // parses as `(idx + 1)..elseifs` and then `.length()`.
        while j < 0 {
'@
  }

  # --- M6: exec_alt's `else` always reports fall-through ---------------------
  # `exec_alt`'s terminal `else` is the last word on the whole chain, so it has to
  # be able to say "terminated".
  #
  # RE-ANCHORED at 0495. The block used to end in `self.flow == FNormal` and
  # `None => true`, and 0495 replaced the `falls` flag with the branch FLOWS:
  # the terminal `else` now reports the FLOW it ended in, and a missing `else`
  # contributes `FNormal`. The MUTATION is the same one -- the terminal `else`
  # can no longer say "terminated" -- and it is now expressed against the flow
  # it reports.
  @{
    Name = 'M6 exec_alt else always reports fall-through'
    File = $F
    Find = @'
    match els {
      Some(e) => {
        self.flow = FNormal
        self.exec_block(e, env)
        self.flow
      }
      None => FNormal
    }
'@
    Repl = @'
    match els {
      Some(e) => {
        self.flow = FNormal
        self.exec_block(e, env)
        FNormal
      }
      None => FNormal
    }
'@
  }

  # --- M7: exec_alt's missing else stops falling through ---------------------
  # The same statement one level down, inside exec_alt's own unknown-condition
  # arm -- a chain that still HAS an else-if.
  #
  # RE-ANCHORED at 0495, on the same statement as M1 but at exec_alt's depth.
  # The MUTATION is the same one: the missing-else arm stops contributing a
  # fall-through flow. The ANCHOR is the current text, and the two arms are
  # distinguished by their indentation and their surrounding block.
  @{
    Name = 'M7 exec_alt missing else stops falling'
    File = $F
    Find = @'
        match els {
          Some(e) => {
            self.flow = FNormal
            self.exec_block(e, env)
            val = vjoin(val, self.last_value)
            flows.push(self.flow)
          }
          // A MISSING else always falls through: when no condition holds,
          // nothing runs and control continues.
          None => flows.push(FNormal)
        }
        self.last_value = val
        join_flow(flows)
'@
    Repl = @'
        match els {
          Some(e) => {
            self.flow = FNormal
            self.exec_block(e, env)
            val = vjoin(val, self.last_value)
            flows.push(self.flow)
          }
          // A MISSING else always falls through: when no condition holds,
          // nothing runs and control continues.
          None => flows.push(FReturn)
        }
        self.last_value = val
        join_flow(flows)
'@
  }

  # --- M8: exec_alt's TERMINAL `None` stops falling through ------------------
  # The fourth statement that decides "a missing else falls through", and the
  # only one of the four nothing tested until the M6 survivor forced the question.
  # `exec_alt`'s inner `match` (M7) handles a chain that still HAS an else-if;
  # this terminal block handles one that does not.
  #
  # Its Find string is M6's, on purpose: the two mutations differ by ONE line
  # inside the same block, and they are the two directions of the same decision.
  # M6 makes the terminal arm unable to say "terminated"; M8 makes it unable to
  # say "falls through". A block that can say neither is useless, and neither
  # mutation is visible without the other's fixture.
  @{
    Name = 'M8 exec_alt terminal missing else stops falling'
    File = $F
    Find = @'
    match els {
      Some(e) => {
        self.flow = FNormal
        self.exec_block(e, env)
        self.flow
      }
      None => FNormal
    }
'@
    Repl = @'
    match els {
      Some(e) => {
        self.flow = FNormal
        self.exec_block(e, env)
        self.flow
      }
      None => FReturn
    }
'@
  }
)

# -----------------------------------------------------------------------------
# CONVERTED to ``_verify/mutate_lib.ps1``. Everything above this line -- the prose
# rationale and the mutation table -- is VERBATIM from the original file; only the
# runner that followed it was replaced. What the harness adds over that runner:
#
#   - a green BASELINE is asserted, not printed. This gate used to print its
#     baseline lines and then score mutations regardless of what they said, so a
#     suite that was already red produced a full table of verdicts and exit 0.
#   - a kill is judged by the ``Total tests:`` line, so a mutant that fails to BUILD
#     is COMPILE-ERR instead of being indistinguishable from a caught one.
#   - restores are proven by SHA256 rather than moved back from a .bakmut file.
#   - a NO-OP is a failure. An anchor that stopped matching is reported and the gate
#     stops; it is never counted as neither-a-kill-nor-a-failure.
#   - ``Expect`` may declare a non-KILLED outcome (``SURVIVED`` / ``COMPILE-ERR``),
#     and a ``Prove`` string is printed with it. A declared verdict still has to be
#     argued rather than asserted.
#   - ``Retired = '<reason>'`` excludes a mutation whose target code no longer
#     exists, printing the reason. It is never re-anchored to something that merely
#     happens to match.
#
# The ``--target`` below is the one the original used. It is not cosmetic:
# ``src/sa`` needs the async runtime, so on the js backend that package degrades and
# ITS TESTS DO NOT RUN -- running a gate on the wrong target silently deletes the
# guards and then reports their absence as a pass.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name '0.4.25' -Target 'js' -Mutations $muts
Write-MutationGateVerdict -Name '0.4.25 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

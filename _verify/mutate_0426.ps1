# 0.4.26 mutation gate.
#
# Seven mutations over ONE idea: a function's TAIL EXPRESSION is its return
# value, and exactly one statement -- the last one, in a function body -- is it.
#
# The set is built around the fact that this fix touches FOUR decisions in FOUR
# files, and a change to any one of them can be invisible to the others:
#
#   parser, fn_body flag  is a FUNCTION body a tail?        (M3)
#   parser, position     is this the LAST statement?        (M4)
#   parser, plumbing     does the flag REACH a fn body?     (M7)
#   interp, record       is the value pushed at all?        (M1)
#   interp, what         is pushed -- the value or Bottom?  (M2)
#   interp, ()           is the empty tuple Unit?           (M5)
#   interp, over-fix     and is a REAL tuple still one?     (M6)
#
# M5 and M6 are the same arm in opposite directions and they are the pair that
# matters most: M5 is a REGRESSION I ACTUALLY SHIPPED INTO A SCAN. The type lens
# was taught that `()` is Unit to match the interpreter, and it cost a new false
# `OperatorMismatch` on wzzc-dev/moui `backend/macos/macos_backend.mbt:204`
# before the six-corpus diff caught it. M5 is the mutation that reproduces that
# mistake, so it is in the gate permanently rather than as a story.
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as
# a failure. The PRE-FLIGHT exists because 0.4.25 wasted three full `moon test`
# runs on patterns that did not match the source at all -- an absent pattern is
# now reported in milliseconds instead of after the suite.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0426.ps1
#
# RE-POINTED BY 0468, and the reason is worth keeping because it is the second time this
# has happened. M3 and M4 anchored on the literal `if fn_body && self.at(TRBrace) {`, and
# 0468 RENAMED that flag to `value_block` -- correctly, because the flag does not mean "this
# is a function body", it means "this block's last statement is its value", and a block in
# the RHS of a `let` is a second place that is true.
#
# THESE TWO ARE RE-POINTED, NOT RETIRED, and the difference matters. A rename changes the
# TEXT a mutation matches and nothing about the DECISION it removes; the mutations below
# still ask the same two questions and still have the same answers. The gate's own preflight
# message says to mark a mutation `Retired` "rather than inventing an anchor to match" --
# that applies when the code has changed SHAPE, and inventing a new shape would indeed be
# fiction. Here the shape is identical and only the identifier moved, so re-pointing is the
# honest repair and retiring would have silently deleted two questions.
#
# => 判据: a preflight MISS asks "did the code change shape?" before it asks "did the text
# change?". Get that order wrong and a rename looks like a deletion -- which is exactly what
# `mutate_lib.ps1`'s literal `IndexOf` matching did to 0443's M4 in 0467, where a DEDENT
# was indistinguishable from a deletion.
#
# M1 AND M2 RE-ANCHORED BY 0490, and this one IS a shape change, so the header rule above
# has to be applied rather than assumed. 0490 gave the interpreter a `last_value` -- a
# function whose body's last statement is an `if` has its value in the BRANCH, not in
# `ret_vals` -- and the `STail` arm became a three-line block:
#
#     STail(e) => {
#       self.last_value = self.eval(e, env)
#       self.ret_vals.push(self.last_value)
#     }
#
# The DECISION both mutations remove is unchanged, and the replacement anchors are shaped
# to remove exactly that decision and no more. M2 keeps the evaluation and changes only the
# pushed value, which is what the one-line original did. M1 has to drop the whole block,
# because the value now has TWO homes and removing only the `push` would leave `last_value`
# set -- which `analyze_fn` reads -- so it would have survived while claiming to test the
# same thing. A wider mutation is fine; a mutation that quietly stops asking the question
# is not.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$INTERP = 'src\interp\interp.mbt'
$PARSER = 'src\parser\parser.mbt'

$muts = @(
  # --- M1: the tail value is not recorded at all --------------------------
  # This is the ORIGINAL behaviour: `SExpr` evaluates and drops. With it, every
  # tail-expression function reports `-> None` again and callers inherit that.
  #
  # Written against the ONE-LINE form `moon fmt` leaves behind. The first version
  # of this gate assumed a braced three-line arm and the pre-flight rejected it
  # in milliseconds -- which is the whole reason the pre-flight exists.
  #
  # RE-ANCHORED BY 0490, and this is a SHAPE change rather than a rename, so the
  # standing rule needed saying out loud. 0490 gave the interpreter a
  # `last_value`, because a function whose body's last statement is an `if` has
  # its value in the BRANCH and not in `ret_vals`. The `STail` arm therefore
  # became a block:
  #
  #     STail(e) => {
  #       self.last_value = self.eval(e, env)
  #       self.ret_vals.push(self.last_value)
  #     }
  #
  # The DECISION this mutation removes is still "the tail's value is recorded".
  # Dropping the whole three-line block is the honest way to remove it now: the
  # value has two homes, and a mutation that removed only the `push` would leave
  # `last_value` set, which `analyze_fn` reads -- so it would have survived
  # while claiming to test the same thing. The mutation got WIDER, not weaker,
  # and it still asks the same question.
  @{
    Name = 'M1 the tail value is not recorded'
    File = $INTERP
    Find = @'
    STail(e) => {
      self.last_value = self.eval(e, env)
      self.ret_vals.push(self.last_value)
    }
'@
    Repl = @'
    STail(e) => {
      let _ = self.eval(e, env)
    }
'@
  }

  # --- M2: the wrong thing is recorded ------------------------------------
  # The `SRaise` mistake applied to a tail expression: pushing `ABottom`
  # instead of the value. The expression is the RESULT, not an operand after
  # the end of the frame, so this is the one place the raise rule must NOT
  # apply -- and it is the mistake the shared node shape invites.
  #
  # RE-ANCHORED BY 0490 for the same reason as M1, and the shape of the
  # replacement is the point: the EVALUATION is kept, exactly as the original
  # one-line mutation kept it (`push(self.eval(e, env))` -> `push(ABottom)`),
  # and only the pushed value changes. Removing the evaluation as well would
  # have been a second mutation wearing one name.
  @{
    Name = 'M2 the tail pushes Bottom instead of the value'
    File = $INTERP
    Find = @'
    STail(e) => {
      self.last_value = self.eval(e, env)
      self.ret_vals.push(self.last_value)
    }
'@
    Repl = @'
    STail(e) => {
      self.last_value = self.eval(e, env)
      self.ret_vals.push(ABottom)
    }
'@
  }

  # --- M3: `value_block` ignored -- every block has a tail ---------------------
  # A loop body's, an `if` arm's and a bare block's trailing expressions all
  # become return values, and the joins widen.
  #
  # RE-POINTED by 0468: `fn_body` was renamed `value_block`. See the header. The
  # mutation now also reaches an EXPRESSION block, which 0468 added and which is
  # exactly the second kind of block whose tail is its value -- so the mutation
  # got WIDER, not weaker.
  @{
    Name = 'M3 value_block ignored, every block has a tail'
    File = $PARSER
    Find = '    if value_block && self.at(TRBrace) {'
    Repl = '    if self.at(TRBrace) {'
  }

  # --- M4: position ignored -- every expression statement is a tail --------
  # The opposite half of the same condition. An `SExpr` anywhere in a function
  # body becomes the tail, so the LAST one is joined with all the others.
  @{
    Name = 'M4 position ignored, every expression statement is a tail'
    File = $PARSER
    Find = '    if value_block && self.at(TRBrace) {'
    Repl = '    if value_block {'
  }

  # --- M5: the empty tuple is a tuple again -------------------------------
  # THE REGRESSION THAT WAS MEASURED, not imagined. The type lens was taught
  # `()` is Unit to match the interpreter and produced a new false
  # `unsupported operand types for '>': 'int' and 'None'` on moui
  # `backend/macos/macos_backend.mbt:204`, in a file whose parse stop point,
  # notice count and actionable count had all been identical a moment before.
  # Six-corpus byte diff is what caught it; nothing else did.
  @{
    Name = 'M5 the empty tuple is a Tuple again'
    File = $INTERP
    Find = @'
    ETuple(elems) => {
      if elems.length() == 0 {
        return AType("None")
      }
      for x in elems {
'@
    Repl = @'
    ETuple(elems) => {
      for x in elems {
'@
  }

  # --- M6: the over-fix -- every tuple is Unit -----------------------------
  # M5's opposite. `()` is Unit, but `(1, 2)` is a tuple, and answering Unit
  # for both is as wrong as answering Tuple for both. The fixture that catches
  # it is the one where a tuple IS the returned value; a tuple bound to a local
  # never reaches `ret_vals` and reads this arm not at all.
  @{
    Name = 'M6 every tuple is Unit (the over-fix)'
    File = $INTERP
    Find = @'
    ETuple(elems) => {
      if elems.length() == 0 {
        return AType("None")
      }
      for x in elems {
'@
    Repl = @'
    ETuple(elems) => {
      if true {
        return AType("None")
      }
      for x in elems {
'@
  }

  # --- M7: the flag never reaches a function body --------------------------
  # Plumbing, not semantics: `parse_fn` hands `parse_block` `false`, so no
  # function ever produces a tail. Reads like M1 from the outside, and that is
  # the point -- it is the only mutation that can tell "the node is never built"
  # apart from "the node is built and dropped".
  #
  # RE-ANCHORED, not retired, and the reason is 0449. This pattern used to be two
  # adjacent lines:
  #
  #     let (name, params, retann) = self.parse_fn_signature()
  #     let (body, endsp) = self.parse_block(true)
  #
  # and 0449 inserted the external-binding check BETWEEN them, because a `fn` whose
  # body is `= "module" "symbol"` has to return before `parse_block` is reached.
  # The mutation is unchanged -- only the `true` at the `parse_block` call is the
  # subject -- so it is re-anchored to that call alone rather than retired, which
  # is the standing rule: surrounding text grew, the code under test did not.
  #
  # The single line is unique. The other `parse_block(true)` in this file is
  # `let (fbody, fendsp) = self.parse_block(true)` in `parse_extern_fn`, which
  # binds different names.
  @{
    Name = 'M7 the flag never reaches a function body'
    File = $PARSER
    Find = @'
  let (body, endsp) = self.parse_block(true)
'@
    Repl = @'
  let (body, endsp) = self.parse_block(false)
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

Invoke-MutationGate -Name '0.4.26' -Target 'js' -Mutations $muts
Write-MutationGateVerdict -Name '0.4.26 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

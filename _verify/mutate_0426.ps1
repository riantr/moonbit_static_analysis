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
  @{
    Name = 'M1 the tail value is not recorded'
    File = $INTERP
    Find = '    STail(e) => self.ret_vals.push(self.eval(e, env))'
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
  @{
    Name = 'M2 the tail pushes Bottom instead of the value'
    File = $INTERP
    Find = '    STail(e) => self.ret_vals.push(self.eval(e, env))'
    Repl = '    STail(e) => self.ret_vals.push(ABottom)'
  }

  # --- M3: `fn_body` ignored -- every block has a tail ---------------------
  # A loop body's, an `if` arm's and a bare block's trailing expressions all
  # become return values, and the joins widen.
  @{
    Name = 'M3 fn_body ignored, every block has a tail'
    File = $PARSER
    Find = '    if fn_body && self.at(TRBrace) {'
    Repl = '    if self.at(TRBrace) {'
  }

  # --- M4: position ignored -- every expression statement is a tail --------
  # The opposite half of the same condition. An `SExpr` anywhere in a function
  # body becomes the tail, so the LAST one is joined with all the others.
  @{
    Name = 'M4 position ignored, every expression statement is a tail'
    File = $PARSER
    Find = '    if fn_body && self.at(TRBrace) {'
    Repl = '    if fn_body {'
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
  @{
    Name = 'M7 the flag never reaches a function body'
    File = $PARSER
    Find = @'
  let (name, params, retann) = self.parse_fn_signature()
  let (body, endsp) = self.parse_block(true)
'@
    Repl = @'
  let (name, params, retann) = self.parse_fn_signature()
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

# 0.4.28 mutation gate.
#
# Four mutations over ONE idea: `derive(Debug, Eq, Clone)` is a parenthesised
# trait list with no braces, so it is a LINE declaration, not a braced one.
#
#   M1  revert the routing                 is the change load-bearing?
#   M2  the message claims a body again    message and routing are separate
#   M3  derive handled by neither          what a dropped branch would do
#   M4  the line skipper loses its end     is the boundary still bounded?
#
# M1 and M2 are deliberately separated because they are two different halves of
# the fix and only one of them shows in the notice TEXT. M1 restores the
# mis-routing, whose visible effect is that a following struct's exclusion notice
# disappears. M2 keeps the correct routing and re-adds the false "its body was
# not analyzed" wording. If only M1 were killed, the tests would be pinning the
# routing and would happily accept a message that claims a body that does not
# exist.
#
# M4 is the boundary the whole fix rests on. `skip_decl_line` stops at a newline;
# without that guard the derive line keeps eating whatever follows, which is the
# original bug wearing a different hat.
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as a
# failure; the PRE-FLIGHT reports an absent pattern in milliseconds.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0428.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$PARSER = 'src\parser\parser.mbt'

$muts = @(
  # --- M1: revert the routing ------------------------------------------------
  # `derive` back on the braced list. The skipper then scans forward for `{` and
  # consumes a LATER declaration's body -- which is what made struct notices
  # vanish in the corpus (572 -> 829 when this is correct, i.e. 257 exclusions
  # that were being swallowed).
  @{
    Name = 'M1 revert: derive goes back to the braced skipper'
    File = $PARSER
    Find = @'
      kw == "impl" ||
      kw == "extend" ||
      kw == "test" {
      p.skip_decl_braced(kw, sp)
    } else if kw == "type" || kw == "const" || kw == "derive" {
'@
    Repl = @'
      kw == "impl" ||
      kw == "derive" ||
      kw == "extend" ||
      kw == "test" {
      p.skip_decl_braced(kw, sp)
    } else if kw == "type" || kw == "const" {
'@
  }

  # --- M2: the message claims a body again ----------------------------------
  # Correct routing, wrong prose. Isolates the wording half of the fix.
  @{
    Name = 'M2 the derive notice claims a body that does not exist'
    File = $PARSER
    Find = '  self.skip(what, false, sp)'
    Repl = '  self.skip(what, true, sp)'
  }

  # --- M3: derive handled by neither arm -------------------------------------
  # What a branch that simply fell through would do. `derive` would reach the
  # expression parser as an ordinary name.
  @{
    Name = 'M3 derive is handled by no arm at all'
    File = $PARSER
    Find = '    } else if kw == "type" || kw == "const" || kw == "derive" {'
    Repl = '    } else if kw == "type" || kw == "const" {'
  }

  # --- M4: the line skipper loses its terminator -----------------------------
  # `skip_decl_line` stops at a newline or semicolon. Drop the newline guard and
  # the derive line consumes the following declaration -- the original bug in a
  # different disguise.
  @{
    Name = 'M4 the line skipper no longer stops at the newline'
    File = $PARSER
    Find = '  while !self.at(TEOF) && !self.at(TNewline) && !self.at(TSemi) {'
    Repl = '  while !self.at(TEOF) && !self.at(TSemi) {'
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

Invoke-MutationGate -Name '0.4.28' -Target 'js' -Mutations $muts
Write-MutationGateVerdict -Name '0.4.28 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

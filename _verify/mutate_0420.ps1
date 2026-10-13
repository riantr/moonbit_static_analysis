# 0.4.20 mutation gate.
#
# Two mutations, and they are opposite on purpose. The fix relaxed a sentinel;
# the interesting failure is not only "the fix is gone" but "the fix was the
# only thing protecting the file". M2 covers that second direction, which a
# one-mutation gate would have missed.
#
# Same rules as before: COMPILE-ERR is the absence of a `Total tests:` line,
# never a grep; every restore is byte-identical by SHA256.
#
# Usage: pwsh -File _verify/mutate_0420.ps1

# -----------------------------------------------------------------------------
# CONVERTED to ``_verify/mutate_lib.ps1``. This gate carried its own runner with
# the SHA256 restore and the `Total tests:` COMPILE-ERR judgement; what it lacked
# was a green BASELINE, PRE-FLIGHT, and line-ending normalisation. The prose above
# is VERBATIM and each mutation keeps the comment block that argued for it.
#
# The call arguments were lifted out of the original file with the PowerShell AST
# parser, not retyped. The patterns are multi-line with load-bearing indentation,
# and a transcription slip would not fail loudly -- it would make the pattern stop
# matching, which this harness reports as a NO-OP on a mutation whose real anchor
# is fine. That is a bug indistinguishable from a rotted anchor, so the conversion
# does not create one.
#
# The target is now PINNED to wasm. This gate ran bare `moon test`, which resolved
# through `preferred_target = "wasm"` in `moon.mod` -- 514 tests rather than the
# 442 the js target runs. The scope of the whole gate therefore depended on a field
# in the module manifest rather than on anything in this script.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$mutations = @(
  # --- M1: the `with` exception removed -------------------------------------
  # Back to firing on any `fn`. `impl T for U with fn m(self)` leaves its body
  # behind and `self` is reported undefined again.
  @{
    Name = 'M1 with-exception removed'
    File = 'src\parser\parser.mbt'
    Find = @'
if self.at_name("fn") && !saw_with {
'@
    Repl = @'
if self.at_name("fn") {
'@
  }

  # --- M2: the sentinel disabled outright -----------------------------------
  # The OPPOSITE direction, and the one that matters: if the scan never stops at
  # a top-level `fn`, then a BODILESS `pub impl E for S` runs past the following
  # top-level function and swallows the rest of the file. Only the control test
  # "0420: a bodiless impl still stops at the next top-level fn" can catch this.
  @{
    Name = 'M2 fn sentinel disabled'
    File = 'src\parser\parser.mbt'
    Find = @'
if self.at_name("fn") && !saw_with {
'@
    Repl = @'
if self.at_name("fn") && !saw_with && self.at_name("zzz_never") {
'@
  }

  # --- M3: the HARVEST stops skipping method holders -----------------------
  # `collect_declared_names` is a SECOND, separate name reader — it never goes
  # through `skip_decl_braced`. Without its own guard the phantom method name
  # comes straight back, and the whole 0.4.18/0.4.20 "two readers drift" lesson
  # repeats. Only this mutation can catch it; the pipeline tests cannot see the
  # sibling table.
  @{
    Name = 'M3 harvest method-holder guard'
    File = 'src\parser\parser.mbt'
    Find = @'
} else if depth == 0 &&
          !in_holder &&
          (declares_value(n) || declares_type(n)) {
'@
    Repl = @'
} else if depth == 0 &&
          (declares_value(n) || declares_type(n)) {
'@
  }

  # --- M4: `trait`'s OWN name no longer harvested --------------------------
  # The direction that a naive "skip the whole holder" fix gets wrong. Dropping
  # `trait Marker`'s own name broke the pre-existing pyroduct test, which is how
  # it was caught — this mutation pins that the name must still be there.
  @{
    Name = 'M4 trait name not harvested'
    File = 'src\parser\parser.mbt'
    Find = @'
          if n == "trait" {
'@
    Repl = @'
          if false {
'@
  }

)

Invoke-MutationGate -Name '0420' -Target 'wasm' -Mutations $mutations
Write-MutationGateVerdict -Name '0420 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

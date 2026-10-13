# 0.4.27 mutation gate.
#
# Five mutations over ONE idea: a parenthesised FUNCTION TYPE in return position
# (`-> (() -> Int)`) is not a one-element tuple, and the only thing separating
# the two is whether a `->` appears INSIDE the group or just after it.
#
# The set is built around how small that change is. The whole release is one
# boolean and one `||`, which is exactly the size of change that can be
# "obviously right" while being wrong in a direction nothing reports:
#
#   M1  revert entirely                     is the change load-bearing?
#   M2  the assignment neutered             or is only the `||` doing work?
#   M3  the OLD arm dropped                 does the unparenthesised spelling survive?
#   M4  `arrow_inside` starts `true`        is the over-fix caught? (the tuple controls)
#   M5  the scan never runs                 plumbing vs semantics
#
# M1 and M2 are deliberately redundant. M1 removes the feature; M2 leaves the
# feature in place and disarms the one line that records it. If only M1 killed,
# the tests would be pinning the `||` rather than the behaviour, and a rewrite
# that kept the `||` and moved the assignment would have passed them.
#
# M4 is the direction that ships damage rather than noise. `arrow_inside` starting
# `true` makes EVERY `-> (...)` a function type, including 179 genuine tuple
# returns. Whether the suite catches that is the question this gate exists to
# answer, and the answer is recorded rather than assumed.
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as a
# failure; the PRE-FLIGHT reports an absent pattern in milliseconds instead of
# after a full suite.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0427.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$PARSER = 'src\parser\parser.mbt'

$muts = @(
  # --- M1: revert the whole change -----------------------------------------
  # This is 0.4.26's behaviour. The parenthesised spelling falls into the tuple
  # arm, which consumes to the first `)` with no comma -- the one closing the
  # empty parameter list -- so `-> Int)` is left in the token stream and
  # `parse_block` reports `expected '{'` and the rest of the file dies.
  @{
    Name = 'M1 revert: parenthesised fn type reads as a tuple again'
    File = $PARSER
    Find = '    arrow_inside || is_fn'
    Repl = '    is_fn'
  }

  # --- M2: the assignment is the load-bearing line, not the `||` ------------
  # `arrow_inside` still exists, is still read, and is still OR-ed in. Only the
  # one statement that sets it is changed. If this survives, the tests are
  # pinning the expression and not the behaviour.
  @{
    Name = 'M2 the arrow assignment is neutralised'
    File = $PARSER
    Find = '        TArrow => arrow_inside = true'
    Repl = '        TArrow => arrow_inside = false'
  }

  # --- M3: the pre-existing arm is dropped ----------------------------------
  # `arrow_inside || is_fn` -> `arrow_inside`. The UNPARENTHESISED spelling
  # (`-> (Int) -> String`, where the arrow follows the matching `)`) sets no
  # `arrow_inside` at all, so it falls back to the tuple arm. This is the
  # mutation that keeps 0.4.27's code and breaks something older.
  @{
    Name = 'M3 the unparenthesised spelling is dropped'
    File = $PARSER
    Find = '    arrow_inside || is_fn'
    Repl = '    arrow_inside'
  }

  # --- M4: the over-fix ------------------------------------------------------
  # `arrow_inside` starts true, so every `-> (...)` is read by the function-type
  # arm. EXPECTED TO SURVIVE, and the expectation is proved rather than assumed --
  # see EQUIVALENT below.
  @{
    Name = 'M4 every parenthesised return is treated as a fn type'
    File = $PARSER
    Find = '    let mut arrow_inside = false'
    Repl = '    let mut arrow_inside = true'
    # Not a coverage gap. An equivalent mutant, with the proof:
    #
    #   * the tuple arm returns `""`               (parser.mbt:1272)
    #   * the fn-type arm returns "(Int)" etc.     (fn_type_annotation:1016 --
    #                                              no `->` follows, so `out`
    #                                              stays the parenthesised group)
    #   * `ann_to_ty("")`          == TUnknown     (types.mbt:140)
    #   * `ann_to_ty("(Int)")`     == TUnknown     (no arm matches a string that
    #                                              still carries its parentheses,
    #                                              so it falls through to
    #                                              ann_to_list_ty and matches
    #                                              neither `Array[` nor `[..]`)
    #
    # The annotation string has exactly one consumer, `declared_ret`, and both
    # arms feed it TUnknown for every input M4 redirects. So over the WHOLE input
    # space M4 cannot change an observable. Fabricating a fixture to kill it would
    # be theatre: the mutant has no behaviour to kill.
    #
    # It stays in the gate because "survived" and "equivalent" look identical on
    # screen, and only one of them is acceptable. The run asserts that M4 is the
    # one that survives, so a future change that makes M4 killable -- or that
    # breaks the equivalence -- shows up here instead of being assumed.
    Expect = 'SURVIVED'
    Prove = @'
equivalent: tuple arm returns "", fn-type arm returns "(Int)", and ann_to_ty maps
both to TUnknown (types.mbt:140); declared_ret is the annotation string's only consumer
'@
  }

  # --- M5: the scan never runs ------------------------------------------------
  # Plumbing, not semantics: the loop body never executes, so neither flag is
  # ever set. Reads from outside like M1, and that is the point -- it is the only
  # mutation that can tell "the scan ran and said no" apart from "the scan never
  # happened".
  @{
    Name = 'M5 the scan never runs'
    File = $PARSER
    Find = '    let mut j = self.p'
    Repl = '    let mut j = self.toks.length()'
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

Invoke-MutationGate -Name '0.4.27' -Target 'js' -Mutations $muts
Write-MutationGateVerdict -Name '0.4.27 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

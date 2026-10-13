# 0.4.19 mutation gate.
#
# Five mutations over the two 0.4.19 fixes. Same rules as mutate_0418.ps1 and
# for the same reasons:
#   * COMPILE-ERR is detected by the ABSENCE of a `Total tests:` line, never by
#     grepping the output — the 0.4.18 script did that and matched its own test
#     name "0419: ... is not a parse error";
#   * every restore is byte-identical, proven by SHA256, from bytes captured
#     with ReadAllBytes BEFORE the edit;
#   * a mutation that cannot go red is reported as SURVIVED, not counted.
#
# Usage: pwsh -File _verify/mutate_0419.ps1

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
  # --- M1: the is-pattern keyword test removed -------------------------------
  # `if x is Some(true)` binds the literal `true` again.
  #
  # RE-ANCHORED. The original pattern was an inline `!@lexer.is_moonbit_keyword(
  # self.peek_name()) &&` inside the reader itself. That code no longer exists: the
  # predicate was lifted into a NAMED helper, `Parser::pattern_binding_at`, and the
  # keyword test is now one clause of its rejection list at
  # src/parser/parser.mbt:2250. Same predicate, same call, same role -- the drift is
  # that it stopped being inline. The new pattern occurs exactly once in the file
  # (checked before the edit), so the mutation still touches one guard and not two.
  #
  # Re-anchoring is right here and retiring would not be: the guard is live, and the
  # whole point of M1 is that `true` stops being bindable in an is-pattern. The
  # 0.4.19 corpus evidence it cites is still true.
  @{
    Name = 'M1 is-pattern keyword test'
    File = 'src\parser\parser.mbt'
    Find = @'
  if n == "_" || @lexer.is_moonbit_keyword(n) {
    return false
  }
'@
    Repl = @'
  if n == "_" {
    return false
  }
'@
  }

  # --- M2: function types no longer recognized in an annotation -------------
  @{
    Name = 'M2 fn-type annotation'
    File = 'src\parser\parser.mbt'
    Find = @'
  if self.at(TLParen) {
    return self.fn_type_annotation()
  }
'@
    Repl = ''
  }

  # --- M3: return-position function type reverted to the old 3-token guess --
  # This is the version that actually shipped by mistake once: it matches only
  # `() -> T` and misses `(Int) -> String`, because `Int` sits between the
  # brackets. The fixture that caught it is "0419: a function-type return
  # annotation parses".
  @{
    Name = 'M3 return fn-type (3-token)'
    File = 'src\parser\parser.mbt'
    Find = @'
            is_fn = j + 1 < self.toks.length() && self.toks[j + 1] == TArrow
'@
    Repl = @'
            is_fn = j + 1 < self.toks.length() && self.toks[j - 1] == TArrow
'@
    # The comment above says "the fixture that caught it is ...". Until now that
    # sentence was prose. `MustRed` makes the harness check it: this test must be
    # among the red ones, or the gate fails even though `KILLED` is true.
    #
    # Measured by `_verify/named_claims.ps1`, not assumed. It fires; one other test
    # fires too ("0427: control -- an unparenthesised function type still parses"),
    # which is why the assertion is by NAME rather than by count.
    MustRed = '0419: a function-type return annotation parses'
  }

  # --- M4: every paren return treated as a function type --------------------
  # EXPECTED TO SURVIVE, and the reason is worth keeping: for every annotation
  # this lens can read, the tuple arm and the function-type arm consume EXACTLY
  # the same tokens. A tuple `(Int, String)` has no `->` after its close, so
  # `fn_type_annotation` renders it and returns just as the tuple arm consumed it
  # and returned "". Both reach `ann_to_ty` as an unknown. So `n_parse` cannot
  # distinguish them and the mutation is genuinely non-discriminating.
  #
  # The tuple test is KEPT regardless — not as a kill for this mutation, but as a
  # regression test for a future change that breaks tuple parsing for real.
  @{
    Name = 'M4 return fn-type over-eager (expected to survive)'
    File = 'src\parser\parser.mbt'
    Find = @'
            is_fn = j + 1 < self.toks.length() && self.toks[j + 1] == TArrow
'@
    Repl = @'
            is_fn = true
'@
    Expect = 'SURVIVED'
  }

)

Invoke-MutationGate -Name '0419' -Target 'wasm' -Mutations $mutations
Write-MutationGateVerdict -Name '0419 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

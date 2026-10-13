# 0.4.21 mutation gate.
#
# Seven mutations over four fixes, and the set is deliberately not one-per-fix:
# a gate that only removes each guard in turn cannot tell "the guard is the
# protection" from "something else happens to protect the same line".
#
#   M1  `guard` no longer parsed          -> the identifier reading returns
#   M2  `guard`'s else block dropped      -> the OPPOSITE direction: the guard
#                                            stops being the only thing that
#                                            bounds the statement, so a guard
#                                            that swallowed its own block would
#                                            look identical to a fixed one
#   M3  named-argument lambda head off    -> the argument list is abandoned
#   M4  the `is` newline continuation off-> the nastiest failure mode: the file
#                                            still parses, with the wrong tree
#   M5  tuple pattern returns only the 1st-> back to one binding per pattern
#   M6  the `.` neighbour rule removed    -> a qualified path binds every
#                                            segment as a local (a REGRESSION
#                                            direction: dropping the old depth
#                                            restriction opens this hole)
#   M7  the nested-constructor rule removed-> `Some(Os(error))` binds `Os`
#
# Same rules as before: COMPILE-ERR is the absence of a `Total tests:` line,
# never a grep; every restore is byte-identical by SHA256.
#
# Usage: pwsh -File _verify/mutate_0421.ps1

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
  # --- M1: `guard` is an ordinary identifier again -----------------------------
  # `guard` is not in the lexer's keyword list, so with this arm gone it is read
  # as a name and reported undefined — and the condition is never walked, so the
  # pattern's binding never lands either.
  @{
    Name = 'M1 guard not parsed'
    File = 'src\parser\parser.mbt'
    Find = @'
if self.at_name("guard") {
    return self.parse_guard()
  }
'@
    Repl = @'
if self.at_name("guard") && self.at_name("zzz_never") {
    return self.parse_guard()
  }
'@
  }

  # --- M2: the guard's else block dropped ------------------------------------
  # THE OPPOSITE DIRECTION. The bound of a guard statement is its `else` block;
  # drop it and the condition's names still resolve (M1-shaped tests stay green)
  # while the else body is never analyzed. Only
  # "0421: a guard's else body is still analyzed" can catch this.
  #
  # *** CORRECTED 2026-10-14: the sentence above was FALSE. ***
  #
  # Measured by `_verify/named_claims.ps1` against the real `moon test` failure
  # output: that test EXISTS (src/pipeline/pipeline_0421_test.mbt:76) and it does
  # NOT go red. This mutation is killed by six other tests:
  #
  #   0425: a guard whose else returns does not make the code after it dead
  #   0425: a guard whose else raises does not make the code after it dead
  #   0421: guard binds its condition's is-pattern (control)
  #   0421: a guard with a braced else body parses and binds
  #   0421: is continues an expression across a newline
  #   0421: the corpus guard + newline + tuple shape is clean
  #
  # WHY THE NAMED TEST STAYS GREEN -- the part worth keeping. The mutation stops
  # the parser CONSUMING `else`; it does not make the else body vanish. The `else`
  # token is left at the cursor and is then read as an ordinary statement, so
  # `{ zzz_else(decoder) }` is still walked and `zzz_else` is still reported. The
  # test asserts exactly one UndefinedName and still sees one, so it passes. It
  # pins M1 -- where the whole guard statement is misread -- and never pinned M2.
  #
  # CONSEQUENCE, stated rather than smoothed over: this mutation is killed by tests
  # from a LATER release (0.4.25), so the kill is INCIDENTAL. Reword either of
  # those tests, or break their incidental overlap with this mutation, and M2 would
  # report SURVIVED while still looking pinned. That is precisely what
  # `mutate_lib.ps1`'s `MustRed` rule makes visible -- see the 0.4.19 and 0.4.20
  # entries, where the named test IS among the red and the claim holds.
  #
  # RE-ANCHORED earlier, and that part still stands: pure signature drift, the guard
  # is character-for-character the same except that `parse_block` grew a Boolean
  # parameter and the call now passes `false` (src/parser/parser.mbt:2095). Checked
  # before the edit: this 4-line pattern occurs exactly once in the file, which
  # matters because `at_name("else")` also appears at the if/else-chain reader and
  # the method-holder reader -- a shorter pattern would have mutated the wrong one
  # of the three.
  @{
    Name = 'M2 guard else dropped'
    File = 'src\parser\parser.mbt'
    Find = @'
  if self.at_name("else") {
    let _ = self.bump()
    let (eb, _) = self.parse_block(false)
    els = Some(eb)
  }
'@
    Repl = @'
  if self.at_name("else") && self.at_name("zzz_never") {
    let _ = self.bump()
    let (eb, _) = self.parse_block(false)
    els = Some(eb)
  }
'@
    # NO `MustRed` HERE, DELIBERATELY, and the reason is the falsified claim above.
    # Wiring the test the comment used to name makes this gate go RED:
    #
    #   MUST-RED MISS: "0421: a guard's else body is still analyzed" did not go red
    #   GATE FAILED: 0421 mutation gate
    #     - M2 guard else dropped (named test did not go red)
    #
    # That was run, and it was the negative control for the new harness rule -- a
    # rule nobody has watched fail is not a rule. It is not kept, because the
    # mutation genuinely IS killed: six tests catch it. Leaving a known-false
    # assertion in place would keep the gate red for a claim nobody believes, and
    # removing the claim is the honest move. The coverage gap is stated above
    # instead of being enforced as something untrue.
  }

  # --- M3: a named argument's lambda is not a head ---------------------------
  # `event=(node, ctx) => f(...)` and `children=_node => [child]` stop being
  # recognised, the argument list is abandoned at the `=>`, and every statement
  # after it is re-read. `n_parse == 0` alone would stay green here, which is why
  # the control test also asserts an undefined name AFTER the lambda.
  @{
    Name = 'M3 named-arg lambda head disabled'
    File = 'src\parser\parser.mbt'
    Find = @'
if self.at_lambda_head() {
'@
    Repl = @'
if self.at_lambda_head() && self.at_name("zzz_never") {
'@
  }

  # --- M4: `is` no longer continues across a newline -------------------------
  # The line break ends the expression, `is` is read as an identifier, and the
  # file STILL PARSES — into a tree where every name after that point is wrong.
  # Nothing fails, so only the tests that assert on names after the continuation
  # can see it.
  @{
    Name = 'M4 is-newline continuation removed'
    File = 'src\parser\parser.mbt'
    Find = @'
while self.at(TNewline) {
    let _ = self.bump()
  }
  while self.at_name("is") {
'@
    Repl = @'
while self.at(TNewline) && self.at_name("zzz_never") {
    let _ = self.bump()
  }
  while self.at_name("is") {
'@
  }

  # --- M5: an is-pattern binds only its first name ---------------------------
  # Back to `EIs` carrying one `String` in practice. The tuple branch consumed the
  # whole group either way, so the group is still consumed — but every binding
  # after the first is dropped and reported undefined at its use.
  @{
    Name = 'M5 is-pattern binds only the first name'
    File = 'src\parser\parser.mbt'
    Find = @'
if !in_type && depth >= 2 && self.pattern_binding_at(j) {
            found.push(n)
          }
'@
    Repl = @'
if !in_type && depth >= 2 && self.pattern_binding_at(j) {
            found.push(n)
            break
          }
'@
  }

  # --- M6: the qualified-path rule removed -----------------------------------
  # A REGRESSION direction, and the reason the `.` neighbour rule exists. Dropping
  # the old `depth == 1` restriction opened this hole: every segment of
  # `@core.Role::Checkbox` now passes "not followed by `(`", so without this rule
  # each is bound as a local and reported unused. Eighteen such patterns are in
  # the corpus.
  @{
    Name = 'M6 qualified-path rule removed'
    File = 'src\parser\parser.mbt'
    Find = @'
if after < self.toks.length() &&
    (self.toks[after] == TLParen || self.toks[after] == TDot) {
    return false
  }
  if j > 0 && self.toks[j - 1] == TDot {
    return false
  }
'@
    Repl = @'
if after < self.toks.length() && self.toks[after] == TLParen {
    return false
  }
'@
  }

  # --- M7: the nested-constructor rule removed -------------------------------
  # The opposite side of the same predicate: without "the next token is not `(`",
  # `Some(Os(error))` binds `Os` — a name that is never used, so it is reported
  # unused while `error`, which IS used, is reported undefined. Two findings
  # instead of none.
  @{
    Name = 'M7 nested-constructor rule removed'
    File = 'src\parser\parser.mbt'
    Find = @'
if after < self.toks.length() &&
    (self.toks[after] == TLParen || self.toks[after] == TDot) {
    return false
  }
'@
    Repl = @'
if after < self.toks.length() && self.toks[after] == TDot {
    return false
  }
'@
  }

  # --- M8: the or-pattern depth rule removed --------------------------------
  # Found BY the differential, not by reasoning: `is (Gone | PageUnavailable)` in
  # proton `internal/bridge_admission_test/main.mbt:93` bound both constructors as
  # locals. The outer `(` of the tuple branch is a GROUPING paren, so its
  # bindings live at depth >= 2, one level in inside `Some(`. Relaxing to >= 1
  # brings the two phantom unused locals straight back.
  @{
    Name = 'M8 or-pattern depth rule removed'
    File = 'src\parser\parser.mbt'
    Find = @'
if !in_type && depth >= 2 && self.pattern_binding_at(j) {
'@
    Repl = @'
if !in_type && depth >= 1 && self.pattern_binding_at(j) {
'@
  }

)

Invoke-MutationGate -Name '0421' -Target 'wasm' -Mutations $mutations
Write-MutationGateVerdict -Name '0421 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

# 0.4.18 mutation gate.
#
# Twelve mutations, one per behavior the new tests claim to hold. The point is
# not that the code is covered but that the COVERAGE CAN FAIL: a test that
# cannot go red is not evidence. Each mutation reverts exactly one mechanism and
# asserts that at least one test turns red.
#
# Rules this script holds itself to, because each one has been violated before:
#   * every mutation must record `ran > 0` — a mutation that compiles the test
#     suite away, or that matches nothing, is reported as COMPILE-ERR or
#     NO-OP, never silently as a pass;
#   * COMPILE-ERR is reported separately from KILLED. A mutation that only
#     breaks the build has not shown the gate is load-bearing;
#   * restore is byte-identical, proven by SHA256, and the original bytes are
#     captured with ReadAllBytes BEFORE the edit. Re-deriving the file by
#     writing text back would round-trip it through the console encoding and
#     silently rewrite UTF-8 as GBK.
#
# Usage: pwsh -File _verify/mutate_0418.ps1

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
  # --- M1: &T no longer consumed in a type annotation ------------------------
  # `if false` was the first attempt and it is a COMPILE-ERR, which this script
  # deliberately does not count as evidence. `TCaret` is a real token of the same
  # type, so the mutation compiles and simply never fires on the `&` that starts
  # a `Ref[T]` annotation.
  @{
    Name = 'M1 &T in type_annotation'
    File = 'src\parser\parser.mbt'
    Find = @'
let amp = if self.at(TAmp) {
'@
    Repl = @'
let amp = if self.at(TQuestion) {
'@
  }

  # --- M2: TTilde removed from the lexer -------------------------------------
  @{
    Name = 'M2 TTilde lexer token'
    File = 'src\lexer\lexer.mbt'
    Find = @'
'~' => TTilde
'@
    Repl = @'
'~' => TBang
'@
  }

  # --- M3: label~ no longer accepted in a parameter list ---------------------
  @{
    Name = 'M3 TTilde in param list'
    File = 'src\parser\parser.mbt'
    Find = @'
} else if self.at(TTilde) {
        let _ = self.bump()
        more_mods = true
      }
'@
    Repl = @'
}
'@
  }

  # --- M4: value~ no longer accepted at a call site --------------------------
  # RE-ANCHORED, and the reason recorded rather than glossed. The original pattern
  # was the `TTilde` arm plus the `TComma` arm after it; that text no longer exists
  # because the arm GREW. `f(x~)` used to consume the `~` and stop; it now also
  # records the argument's LABEL, added when `~` was settled as the shorthand for
  # `f(x = x)`. The mutation is unchanged in MEANING -- value~ no longer accepted at
  # a call site -- and now removes the whole arm, label assignment included.
  #
  # This is a re-anchor, not a fresh anchor. The guard is still at
  # src/parser/parser.mbt:2770, in the same role, and the new pattern occurs exactly
  # once in the file (checked before the edit). Retiring it instead would have
  # dropped a LIVE guard from the gate because the code around it grew, which is not
  # what a rotted anchor means.
  @{
    Name = 'M4 TTilde in call args'
    File = 'src\parser\parser.mbt'
    Find = @'
    if self.at(TTilde) {
      let _ = self.bump()
      if labels[labels.length() - 1] == "" {
        labels[labels.length() - 1] = self.name_at(arg_start)
      }
    }
    if self.at(TComma) {
'@
    Repl = @'
    if self.at(TComma) {
'@
  }

  # --- M5: fn[T] type parameters no longer skipped --------------------------
  @{
    Name = 'M5 fn[T] type params'
    File = 'src\parser\parser.mbt'
    Find = @'
  self.skip_indexed()
  let (name, _) = self.expect_name("function name")
'@
    Repl = @'
  let (name, _) = self.expect_name("function name")
'@
  }

  # --- M6: sibling harvest no longer tolerates fn[T] -------------------------
  @{
    Name = 'M6 sibling name after fn[T]'
    File = 'src\parser\parser.mbt'
    Find = @'
match declared_name_after_kw(toks, i) {
'@
    Repl = @'
match declared_name_at(toks, i + 1) {
'@
  }

  # --- M7: byte-string literal no longer lexed ------------------------------
  @{
    Name = 'M7 b"" byte-string'
    File = 'src\lexer\lexer.mbt'
    Find = @'
if c == 'b' &&
'@
    Repl = @'
if c == 'Z' &&
'@
  }

  # --- M8: struct spread base no longer consumed ----------------------------
  @{
    Name = 'M8 { ..base } spread'
    File = 'src\parser\parser.mbt'
    Find = @'
if self.at(TDot) && self.at_next(TDot) {
      let _ = self.bump()
      let _ = self.bump()
      let base = self.parse_expr()
'@
    Repl = @'
if false {
      let base = self.parse_expr()
'@
  }

  # --- M9: a `{ ..` no longer recognized as a struct literal -----------------
  @{
    Name = 'M9 at_struct_literal (TDot,TDot)'
    File = 'src\parser\parser.mbt'
    Find = @'
(TDot, TDot) => true
'@
    Repl = @'
(TDot, TRBrace) => true
'@
  }

  # --- M10: leading-dot chain branch removed --------------------------------
  @{
    Name = 'M10 leading-dot chain'
    File = 'src\parser\parser.mbt'
    Find = @'
if self.at(TDot) {
    let sp0 = sp
'@
    Repl = @'
if false {
    let sp0 = sp
'@
  }

  # --- M11: the rewind removed — EXPECTED TO SURVIVE -------------------------
  # This one is a deliberate exception and the reason is worth stating, because
  # the honest answer is "this line is defensive and nothing distinguishes it".
  #
  # The chain loop speculatively consumes separators after a segment and rewinds
  # when the next line does not open with `.`. Removing the rewind leaves the
  # cursor AFTER those separators — but the enclosing statement loop calls
  # `skip_seps` again anyway, so the next statement starts in the same place and
  # the same findings are produced. A test cannot distinguish the two, and the
  # corpus does not either.
  #
  # So the rewind is KEPT — it makes the loop correct on its own terms rather
  # than correct only because a caller happens to clean up — and this mutation
  # records that it is unobservable. Reporting it as a kill would be the error;
  # deleting the line would be a behavior claim this evidence does not support.
  @{
    Name = 'M11 chain rewind (expected to survive)'
    File = 'src\parser\parser.mbt'
    Find = @'
        if !self.at(TDot) {
          self.p = save
          break
        }
'@
    Repl = @'
        if false {
          break
        }
'@
    Expect = 'SURVIVED'
  }

  # --- M12: ambient builtin types removed -----------------------------------
  @{
    Name = 'M12 Buffer/FuncRef ambient'
    File = 'src\core\builtins.mbt'
    Find = @'
"Buffer", "FuncRef",
'@
    Repl = @'
"Zz_not_a_type",
'@
  }

)

Invoke-MutationGate -Name '0418' -Target 'wasm' -Mutations $mutations
Write-MutationGateVerdict -Name '0418 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

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
  # RE-ANCHORED TWICE, and both reasons recorded rather than glossed.
  #
  # Re-anchor 1 (0.4.30 audit). The original pattern was the `TTilde` arm plus
  # the `TComma` arm after it; that text no longer existed because the arm GREW.
  # `f(x~)` used to consume the `~` and stop; it now also records the argument's
  # LABEL, added when `~` was settled as the shorthand for `f(x = x)`. The
  # mutation is unchanged in MEANING -- value~ no longer accepted at a call site
  # -- and removes the whole arm, label assignment included.
  #
  # Re-anchor 2 (0.4.30, after 0430). The `?` optional-argument shorthand was
  # added as a SIBLING branch immediately after this one, so the trailing
  # `if self.at(TComma) {` line no longer follows the `TTilde` arm directly and
  # the re-anchored pattern stopped matching. The full release gate caught it:
  # `ABORT: 1 pattern(s) absent` on 0418, which is the harness doing exactly what
  # it was built to do rather than reporting a pass for a mutation it never
  # applied.
  #
  # Both times the fix was to NARROW the pattern to the arm itself and drop the
  # trailing context, because the context was never the point -- the arm was.
  # The new pattern occurs EXACTLY ONCE in the file (verified before this edit).
  # Retiring instead would have dropped a LIVE guard because the code beside it
  # grew, which is not what a rotted anchor means.
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
'@
    Repl = ''
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
  # NO LONGER KILLED, and the reason is that the WORK MOVED rather than that the
  # guard stopped mattering. Declared SURVIVED with its argument (harness rule 5).
  #
  # Until 0.4.30 the statement-level `if self.at(TDot)` block in `parse_stmt` was
  # the ONLY code that read a chain whose `.` starts the next line, and M10 was
  # its guard. 0432 added the same handling to `parse_postfix_from`, which runs
  # during the expression parse -- so the chain is consumed there and the
  # statement-level block is never reached for that shape.
  #
  # MEASURED, not inferred: M10 was applied to parser.mbt by hand and these two
  # parses re-run against the mutated file. Both were still clean.
  #   fn g(x : Array[Int]) -> Int { x.length() }
  #   fn f(a : Array[Int]) -> Int { g(a)\n  .to_string() }
  #   fn f(a : Array[Int]) -> Int { let v = a\n  .length()\n  v }
  # They are pinned as `0432: a leading-dot chain in STATEMENT position still
  # parses` and `0432 control: a leading-dot chain after a plain receiver still
  # parses`, so the claim below is checkable rather than remembered.
  #
  # WHAT IS NOT CLAIMED: that the statement-level block is dead in every case.
  # It is unobservable on every shape tested; removing it is a separate change
  # that would want its own corpus A/B, and it is kept meanwhile for the same
  # reason M11's rewind is kept -- correct on its own terms rather than correct
  # only because something else happens to handle the case.
  @{
    Name = 'M10 leading-dot chain (subsumed by the 0432 postfix block)'
    File = 'src\parser\parser.mbt'
    Find = @'
if self.at(TDot) {
    let sp0 = sp
'@
    Repl = @'
if false {
    let sp0 = sp
'@
    Expect = 'SURVIVED'
    Prove = @'
Measured by applying this mutation by hand and re-running the two parses that
use the shape; both stayed clean. The 0432 change moved the work from
`parse_stmt`'s leading-dot block into `parse_postfix_from`, which runs during the
expression parse and therefore consumes the continuation first.

This is a MOVED guard, not a rotten one, and the distinction matters: the code
still exists and is still reachable in principle, so retiring the row would be
wrong. Declared with its argument instead of quietly dropped or re-anchored to
something that merely matches.
'@.Replace("`r`n", "`n")
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

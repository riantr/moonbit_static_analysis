# Mutation gate 0438 -- `value[:]`, a slice whose bounds may be EMPTY.
#
# On the harness: no runner of its own, all six rules from
# `_verify/mutate_lib.ps1` apply.
#
# THE CHANGE. `parse_postfix_from`'s bracket branch called `parse_expr()` for the
# START bound and only afterwards asked `at(TColon)`. A `[` sitting directly on a
# `:` therefore handed the colon to the expression parser, and the file died with
# "unexpected token `:`" -- which is the reason string on EIGHT of moui's blocked
# files, and on every one of those the `:` is a bound marker, not a stray token.
#
# Six blocked files, the largest remaining cause after 0.4.30's re-rank:
#   `value[:]`        both bounds empty   core/semantics.mbt:71,
#                     core/declaration.mbt:102, `bytes[:]` at
#                     backend/windows/windows_accessibility_bridge.mbt:490
#   `chars[:index]`   open start, real end core/unicode/grapheme_cluster.mbt:248
#
# The parser's own comment said an open START "is not in the corpus and reports
# honestly". `chars[:index]` made that stale, and "reports honestly" was doing a
# lot of work to disguise a blocker. Corrected in the source comment.
#
#   M1  The empty-start check is gone -- back to calling `parse_expr()` blind.
#   M2  The missing bound becomes `EInt(0)` instead of the opaque placeholder.
#       The silent one: `const_eval` must not fold a bound it never read, and an
#       invented 0 is indistinguishable from a written 0 in every other node.
#   M3  The check fires UNCONDITIONALLY, so every plain index loses its operand
#       and gets the placeholder instead. Killed by the plain-index CONTROL, and
#       only because that control asserts `index(int)` and not merely `index`:
#       the node kind is `EIndex` either way, so a weaker control passes.
#   M4  The placeholder branch also eats the colon, so `[:n]` no longer forms a
#       range. The off-by-one shape this fix is one token away from.
#
# Settled with the toolchain, one form per package with a broken canary beside
# each (`_verify/probe_sweep_0434.ps1`, canary firing, all three SELF-OK after):
#   `let s = value[:]`   MOON-OK
#   `let s = value[:2]`  MOON-OK
#   `let c = xs[0]`      MOON-OK   (the control)
#
# The control was `value[0]` on a String at first and came back MOON-BAD, which
# the probe reports as "this frontend reads MoonBit the toolchain rejects" -- a
# verdict about MY probe, since a String is not indexable. It now uses an Array.
# => a MOON-BAD cell is a question about the probe source first.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$NEW = @'
      let first : @ast.Expr = if self.at(TColon) {
        let zsp = self.span()
        { span: zsp, kind: @ast.EBigInt, }
      } else {
        self.parse_expr()
      }
'@.Replace("`r`n", "`n")

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the empty start bound is not checked at all'
    File = 'src\parser\parser.mbt'
    Find = $NEW
    Repl = @'
      let first : @ast.Expr = self.parse_expr()
'@.Replace("`r`n", "`n")
    MustRed = 'a slice with both bounds empty is read'
  },

  @{
    Name = 'M2 the missing bound is INVENTED as EInt(0) instead of opaque'
    File = 'src\parser\parser.mbt'
    Find = @'
        { span: zsp, kind: @ast.EBigInt, }
'@.Replace("`r`n", "`n")
    Repl = @'
        { span: zsp, kind: @ast.EInt(0), }
'@.Replace("`r`n", "`n")
    MustRed = 'a slice with both bounds empty is read'
  },

  @{
    Name = 'M3 the check fires unconditionally, so every plain index loses its operand'
    File = 'src\parser\parser.mbt'
    Find = $NEW
    Repl = @'
      let first : @ast.Expr = {
        let zsp = self.span()
        { span: zsp, kind: @ast.EBigInt, }
      }
'@.Replace("`r`n", "`n")
    MustRed = 'a plain index keeps its real operand and is not a range'
  },

  @{
    Name = 'M4 the placeholder branch also eats the colon, so [:n] forms no range'
    File = 'src\parser\parser.mbt'
    Find = @'
      let first : @ast.Expr = if self.at(TColon) {
        let zsp = self.span()
        { span: zsp, kind: @ast.EBigInt, }
      } else {
'@.Replace("`r`n", "`n")
    Repl = @'
      let first : @ast.Expr = if self.at(TColon) {
        let zsp = self.span()
        let _ = self.bump()
        { span: zsp, kind: @ast.EBigInt, }
      } else {
'@.Replace("`r`n", "`n")
    MustRed = 'an open start bound with a real end is read'
  }
)

Write-MutationGateVerdict -Name '0438'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
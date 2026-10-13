# Mutation gate 0433 -- a `match` subject on the next line, and `defer` as a
# statement.
#
# On the harness: no runner of its own, all six rules from
# `_verify/mutate_lib.ps1` apply. Verified in the 0.4.30 audit: 16 gates on the
# harness, 0 carrying their own runner.
#
# TWO CHANGES SHARE THIS GATE. They were found by the same A/B and neither was
# separable from the other in effect: reading one more file exposed the other.
# `command/command.mbt` became readable because of the `match` fix, and the only
# thing wrong with it was the missing `defer` arm.
#
#   1. A `match` whose SUBJECT starts on the NEXT LINE. `match` alone at the end
#      of a line, with the scrutinee and arms following, is the shape wzzc-dev/
#      moui 0.1.12 writes throughout -- `views/form/form_field.mbt:42`,
#      `runtime/scroll_to_key.mbt:30`, `runtime/runtime_events.mbt:358` -- and it
#      was the largest single blocker left at 0.4.30: 13 files, `unexpected
#      token `>``, the arrow of the first arm. Fixed with one `skip_seps` in the
#      `TName("match")` arm of `parse_atom`.
#
#   2. `defer { ... }` and `defer <expr>` as a statement. Without the arm the
#      keyword was an ordinary identifier and the file reported `undefined name
#      'defer'` -- a false positive about the ANALYZER, on code `moon check`
#      accepts with zero errors. Measured on moonbit-community/proton 0.3.4
#      `command/command.mbt:145`.
#
#      BOTH bodies exist and the counts are not sampled: 1950 `defer` lines
#      across the six corpora, of which 1534 are a method call, 268 another
#      expression, 130 a block, 18 an expression with a trailing `catch`. An arm
#      that assumed only the block form -- the first attempt -- produced 8x
#      `expected '{'` across proton alone. M2 is that exact mistake, kept as a
#      mutation so it cannot come back by accident.
#
#   M1  The `match` subject is not read across the newline at all. The file dies
#       on the first arm's `>`, which is the original symptom.
#   M2  `defer` accepts only a BLOCK -- the first attempt, reintroduced.
#   M3  The `defer` arm is switched off entirely, so the keyword is an ordinary
#       identifier again and the walker reports `no visible binding for
#       'defer'`. NOTE WHERE ITS CONTROL LIVES, because getting this wrong was
#       the gate's job on its first run: with the arm off the file still PARSES
#       -- `defer` reads as an ordinary name -- so a parse-level control
#       ("first_error == 0 and reports is empty") stays green with and without
#       the arm. It lives at pipeline level, where the walker can see the
#       difference. See the test it names.
#   M4  `defer` accepts only an EXPRESSION, dropping the block form.
#
# MustRed on all four. "Killed" alone does not say the RIGHT thing went red, and
# the distinction is not academic here: two of the four changes could be
# reverted while `first_error == 0` still held for a DIFFERENT source. The
# named tests are what pin which construct was actually read.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    Name = 'M1 a match subject on the next line is not read at all'
    File = $PARSER
    Find = @'
      self.skip_seps()
      let scrutinee = self.parse_expr()
'@.Replace("`r`n", "`n")
    Repl = @'
      let scrutinee = self.parse_expr()
'@.Replace("`r`n", "`n")
    MustRed = 'a match subject on the next line is read, not skipped'
  },

  @{
    Name = 'M2 defer accepts only a block, so defer <expr> dies on the keyword'
    File = $PARSER
    Find = @'
    if self.at(TLBrace) {
      let (body, _) = self.parse_block(false)
      return { span: sp, kind: @ast.SBlock(body), }
    }
    return { span: sp, kind: @ast.STail(self.parse_expr()), }
'@.Replace("`r`n", "`n")
    Repl = @'
    let (body, _) = self.parse_block(false)
    return { span: sp, kind: @ast.SBlock(body), }
'@.Replace("`r`n", "`n")
    MustRed = 'defer followed by an expression reads the whole call'
  },

  @{
    Name = 'M3 the defer arm is off, so the keyword is an ordinary identifier'
    File = $PARSER
    Find = '  if self.at_name("defer") {'
    Repl = '  if false && self.at_name("defer") {'
    MustRed = 'the defer keyword is not reported as an ordinary name'
  },

  @{
    Name = 'M4 defer accepts only an expression, dropping the block form'
    File = $PARSER
    Find = @'
    if self.at(TLBrace) {
      let (body, _) = self.parse_block(false)
      return { span: sp, kind: @ast.SBlock(body), }
    }
'@.Replace("`r`n", "`n")
    Repl = ''
    MustRed = 'defer followed by a block is one statement'
  }
)

Write-MutationGateVerdict -Name '0433'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
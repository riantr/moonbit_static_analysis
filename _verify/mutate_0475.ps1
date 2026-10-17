# Mutation gate 0475 -- a BINDER head carrying ONE declaration, and the `nobreak` this found.
#
# WHAT THIS PINS. `for p in ps; len = 0 { .. }` is legal MoonBit and the analyzer could not
# read it. 0473 made the head route CORRECTLY -- to `parse_for_stmt`'s binder branch -- and
# that branch stopped at the `;`, so the error moved from `expected ';'` to `expected 'in'`
# and five corpus sites stayed unread. Moving an error is not removing it, which is why
# `parser_0473_test.mbt` pinned the failure as a FAILING test; this increment inverts that pin.
#
# THE GRAMMAR IS NOT THE C-STYLE ONE, and that is the part a "just reuse the list reader" fix
# gets wrong, so it was settled rather than assumed -- `_verify/settle_0475_binder_clauses.ps1`,
# 2 controls and 9 rows, GATE OK:
#
#   for p in ps; len = 0 { .. }              ACCEPT   the shape is legal MoonBit
#   the declaration is readable in the body  ACCEPT
#   for p in ps; len = 0; n = 1 { .. }       REJECT(4106)  a second `;`-clause is STEPS
#   for p in ps; len = 0; len > 0 { .. }     REJECT(3002)  no condition after a binder head
#   for p in ps; n = p.length() { .. }       REJECT(4021)  the binder is NOT in scope here
#   for p in ps; len = 0 { .. } ignore(len)  REJECT(4021)  it does NOT outlive the loop
#   for k, v in m; n = 0 { .. }              ACCEPT        two binders compose
#
# => 判据: TWO REJECT(4021) ROWS ARE WHAT SAY "NO NEW NODE". The declaration cannot see the
# binder, so it is evaluated OUTSIDE the binder's scope, and hoisting it BEFORE the loop is
# correct by construction rather than by argument. It does not outlive the loop either -- the
# same scoping 0470 measured -- so `c_for_init`'s conversion is reusable unchanged.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0475' -Target 'wasm' -Mutations @(

  # M1 THE `;` GUARD IS DROPPED, so every binder head looks for a declaration. This is the
  # mutation that says the guard is load-bearing rather than decorative, and the CONTROL row is
  # what kills it: without the control a wrapper applied to every binder head would pass the
  # shape rows while changing the node for hundreds of loops.
  @{
    Name = 'M1 the `;` guard is dropped, so every binder head looks for a declaration'
    File = $PARSER
    Find = '  let decl : @ast.Stmt? = if self.at(TSemi) {'
    Repl = '  let decl : @ast.Stmt? = if true {'
    MustRed = '0475 control: a plain binder head is still a bare SFor, with no wrapper'
  }

  # M2 THE DECLARATION IS READ AND THEN DROPPED. The increment would keep compiling and every
  # `first_error == 0` row would stay green, because the reader still consumed the tokens --
  # this is the "it parses" trap, and the tree-shape row is the only instrument for it.
  @{
    Name = 'M2 the declaration is read and then thrown away'
    File = $PARSER
    Find = '        Some(d) => { span: sp, kind: @ast.SBlock([d, loop_stmt]), }'
    Repl = '        Some(_) => loop_stmt'
    MustRed = '0475: a binder head with a declaration desugars to SBlock[SLet, SFor]'
  }

  # M3 THE DECLARATION GOES AFTER THE LOOP. Same two statements, same count, same node kind --
  # only the ORDER differs, and the order IS the settle: the binder must not be in scope for
  # the declaration, which is what putting it first means. A reader that had the right two
  # statements in the wrong order would model a scope the toolchain refuses (REJECT 4021).
  @{
    Name = 'M3 the declaration is placed after the loop instead of before it'
    File = $PARSER
    Find = '        Some(d) => { span: sp, kind: @ast.SBlock([d, loop_stmt]), }'
    Repl = '        Some(d) => { span: sp, kind: @ast.SBlock([loop_stmt, d]), }'
    MustRed = '0475: a binder head with a declaration desugars to SBlock[SLet, SFor]'
  }

  # M4 `maybe_nobreak` IS DROPPED FROM THE MULTI-BINDER PATH -- the pre-existing defect this
  # increment REVEALED rather than created. `nobreak` is a postfix on a loop and is legal on
  # all three forms (settle_0443), so the multi-binder head is a loop like any other. Without
  # the call the keyword stayed on the cursor, the statement reader took `nobreak { .. }` as an
  # ordinary expression plus a block, and the resolver reported THREE `undefined name
  # 'nobreak'` plus one `undefined name 'acc'` into async/src/process/{unix,windows}.mbt as
  # ACTIONABLE findings on code `moon check` compiles.
  #
  # M4 is the mutation whose corpus number was measured: with it applied, `actionable` goes
  # 0 -> 4 and async parsed 399 -> 396. It was invisible while the header itself failed to
  # parse. UNBLOCKING A FILE DOES NOT CREATE FINDINGS; IT REVEALS ONES WHOSE REACH WAS BLOCKED.
  @{
    Name = 'M4 maybe_nobreak is dropped from the multi-binder path (the defect 0475 exposed)'
    File = $PARSER
    Find = @'
  self.maybe_nobreak(
    match decl {
      Some(d) => { span: sp, kind: @ast.SBlock([d, pair_loop]), }
      None => pair_loop
    },
  )
'@.Replace("`r`n", "`n")
    Repl = @'
  match decl {
    Some(d) => { span: sp, kind: @ast.SBlock([d, pair_loop]), }
    None => pair_loop
  }
'@.Replace("`r`n", "`n")
    MustRed = '0475: nobreak attaches to a multi-binder head that carries a declaration'
  }

  # M5 AND THE SAME DROP ON THE DESUGARED PATH. Separate from M4 because M4's anchor is the
  # whole tail block; without this row a future edit could keep `maybe_nobreak` and lose the
  # declaration, which reads fine and drops the binding.
  @{
    Name = 'M5 the declaration is dropped from the desugared multi-binder loop'
    File = $PARSER
    Find = '      Some(d) => { span: sp, kind: @ast.SBlock([d, pair_loop]), }'
    Repl = '      Some(_) => pair_loop'
    MustRed = '0475: a two-binder head with a declaration puts the declaration before the loop'
  }
)

# TWO ROWS IN `parser_0475_test.mbt` HAVE NO MUTATION HERE, and that is recorded rather than
# papered over. They are the NEGATIVE rows -- a condition after a binder head, and a second
# declaration clause -- and they assert `first_error != 0`.
#
# Nothing in this increment can turn them red. The refusal is not produced by a guard in this
# code: the reader takes the one declaration and then hands the cursor to `parse_block`, which
# finds a `;` where it wants `{`. The rows therefore guard the ORDER (one declaration, then
# the body) against a FUTURE edit that hands the tail to `c_for_inits` and walks the C-style
# variable-length list instead -- which would ACCEPT headers the toolchain refuses
# (REJECT 3002 and 4106), a new false negative in the direction this project has never taken.
#
# => 判据: before keeping a negative row, ask whether ANY mutation can turn it red. These
# cannot, so they are kept as a named FUTURE risk rather than presented as coverage -- which
# is the mistake 0470's four vacuous rows made, asserting a count of a finding-family name
# that was misspelled so nothing could ever contradict it.

Write-MutationGateVerdict -Name '0475'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

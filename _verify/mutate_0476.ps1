# Mutation gate 0476 -- the single STEP after a binder head's initialization clause.
#
# WHAT THIS PINS. `for p in ps; len = 0; len = len + p.length() { .. }` is the shape
# async/src/io/reader.mbt:186 writes, and 0475's settle REJECTed the whole clause on the
# evidence of ONE row -- `for p in ps; len = 0; n = 1 { .. }` is REJECT(4106). The corpus
# disagreed and the settle was what had to give.
#
# The compiler's own sentence says why, and neither hand-written program said it outright:
#
#     Unknown binder n in the for-loop steps.
#     Binders in the steps must be declared in the initialization block of the for-loop.
#
# 4106 was never about the NUMBER of clauses. It was about WHERE THE BINDER WAS DECLARED: `n`
# is declared nowhere, `len` is declared two tokens earlier. Generalising a grammar from one
# convenient fixture is how 0475's C3 went wrong, and the corpus is the thing carrying a
# compiler's verdict on real code.
#
# `_verify/settle_0476_for_steps.ps1`, 2 controls + 7 rows, GATE OK:
#   ACCEPT   the corpus shape
#   ACCEPT   a step may READ the loop binder
#   ACCEPT   `;` immediately followed by `{` -- an empty step list
#   REJECT(4106)  a step declaring a binder the init block does not declare
#   REJECT(3002)  a bare expression in a step
#   REJECT        two steps
#   REJECT(4021, 4018)  a step with no initialization clause
#
# => NO NEW NODE. A step runs at the END of each iteration, which is where `parse_c_for`
# already puts the C-style update clause, so the step is APPENDED to the loop body. Appending
# before the multi-binder path builds its `$pair` destructuring is what puts the step after it.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0476' -Target 'wasm' -Mutations @(

  # M1 THE TARGET-NAME GUARD IS DROPPED, so a step may assign a binder nothing declares. That is
  # the settle's REJECT(4106) row, and 0475's C3 row -- the row whose over-generalisation this
  # increment exists to undo -- becomes true again. The two 0475 negative rows were kept with
  # the admission that nothing in that gate could turn them red; this is the risk arriving.
  @{
    Name = 'M1 the step may assign a binder the initialization block does not declare'
    File = $PARSER
    Find = '    if target != "" && target == decl_name && self.at_next(TAssign) {'
    Repl = '    if target != "" && self.at_next(TAssign) {'
    MustRed = '0476: a step must be an assignment to the declared binder'
  }

  # M2 THE TOKEN-SHAPE GUARD IS DROPPED, so a bare expression is read as a step. The settle's
  # REJECT(3002) row. Separate from M1 because the two conditions are independent: M1 keeps the
  # shape and loses the name, M2 keeps the name and loses the shape, and `len > 0` is the row
  # that tells them apart -- the target IS the declared binder there, so only M2 can kill it.
  @{
    Name = 'M2 the step is not required to be an assignment'
    File = $PARSER
    Find = '    if target != "" && target == decl_name && self.at_next(TAssign) {'
    Repl = '    if target != "" && target == decl_name {'
    MustRed = '0476: a step must be an assignment to the declared binder'
  }

  # M3 THE STEP IS NEVER APPENDED, so the loop runs and the tree says it ran and nothing more.
  # Nothing errors: the tokens are consumed and the statement is dropped, which is exactly the
  # shape of defect this gate exists to catch and the reason `body.length()` is the instrument.
  @{
    Name = 'M3 the step is read and never appended to the loop body'
    File = $PARSER
    Find = @'
  match step {
    Some(s) => body.push(s)
    None => ()
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  match step {
    Some(_) => ()
    None => ()
  }
'@.Replace("`r`n", "`n")
    MustRed = '0476: the step is appended to the end of the loop body'
  }

  # M4 THE STEP IS PREPENDED INSTEAD, which is the placement error rather than the presence
  # error. Same two statements, same node kinds -- only the order differs, and the order is
  # what "runs at the end of each iteration" means. The multi-binder row is the sharp one: a
  # step before the `$pair` destructuring would read the step's value as the pair.
  @{
    Name = 'M4 the step is prepended to the body instead of appended'
    File = $PARSER
    Find = @'
  match step {
    Some(s) => body.push(s)
    None => ()
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  match step {
    Some(s) => body.insert(0, s)
    None => ()
  }
'@.Replace("`r`n", "`n")
    MustRed = '0476: a two-binder head puts the step after the pair destructuring'
  }
)

# NO MUTATION FOR THE `has_decl` GUARD, and that is measured rather than skipped. Dropping
# `has_decl &&` changes the behaviour of exactly one input -- `for p in ps; len = len + .. { }`,
# the settle's S7 row -- and even there it changes nothing the tree can show, because that
# header's single clause is read as the DECLARATION either way and the analyzer's divergence on
# S7 is already recorded against the lexical-scoping increment. So the guard is unreachable by
# any input this suite can distinguish.
#
# => 判据: a mutation that cannot fail tests nothing. 0473 deleted its depth-guard mutation for
# the same reason and said so in the gate; this one is the same case, and the honest thing is to
# record that the guard's reachability is bounded by a shape the analyzer does not yet handle
# correctly rather than to invent a fixture that would manufacture coverage.

Write-MutationGateVerdict -Name '0476'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

# Mutation gate 0457 -- the nested `async fn NAME(..) { .. }` DECLARATION.
#
# WHAT THIS PINS. `parse_atom`'s `async` arm has three cases: an anonymous
# literal (`async fn(`), a DECLARATION (`async fn log(`), and no `fn` at all.
# The middle one used to yield `EName("async")` -- handing the keyword back
# unchanged so `parse_block` would declare the function from `fn`. Correct for
# the cursor, wrong as a node: `async` is not a name, so the structural lens
# filed `undefined name 'async'` against legal MoonBit.
#
# IT WAS UNREACHABLE UNTIL 0456. Every file carrying the shape was blocked by
# something earlier -- `async 0.22.4 src/fs/watch_test.mbt` died at line 389 on
# `is @async.TimeoutError`, which is exactly the package-qualified `is` head
# 0456 fixed. The file then parsed whole and three sites surfaced at once,
# taking async's actionable count 0 -> 3.
#
#   Cross-checked by the same A/B that unblocked it: `_verify/ab_0456_0457_
#   coverage.ps1` records watch_test.mbt going from reach 389 to EOF. The line
#   this comment names as the blocker is the line the reach map moved from.
#
# => 判据: a finding no corpus can reach is not a finding that does not exist --
# it is a finding whose corpus has not been read yet. Fixing an unrelated
# blocker is what made this one visible, so "the corpus is green" was never
# evidence about it. Reach is the instrument that says which findings have been
# REACHED, and only an A/B over every file of every corpus can say whether a
# change costs coverage.
#
# WHY 0453'S GATE COULD NOT CATCH IT. 0453 pinned that a nested async
# declaration is not mistaken for a literal, via `parse_failures == 0` plus the
# absence of a false notice. Both hold while the branch still invents a name:
# a notice is not a failure, so a branch that announces itself and a branch that
# silently binds a name are indistinguishable to that pair of assertions. Only a
# lens that RESOLVES NAMES separates them -- hence M1 below, and hence
# `src/pipeline/pipeline_0457_test.mbt`.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

# The four tokens plus the notice, exactly as committed. Used as the Find of
# M1-M4 so every mutation is "change what this branch does" rather than an
# unrelated edit elsewhere in a 5000-line file.
$DECL = @'
          self.note_skip(
            "the `async` of an `async fn` declaration is outside the analyzed subset; it was read past",
            sp,
          )
          { span: sp, kind: @ast.EBigInt, }
'@

Invoke-MutationGate -Name '0457' -Target 'js' -Mutations @(

  # M1 IS THE GATE. The branch reverted to the node it used to yield. This is
  # the pre-0457 behaviour verbatim, and the named test is the one that can only
  # fail this way: `parse_failures == 0` would still hold, because a bogus
  # binding is not a parse failure -- it is a lens finding about a name.
  @{
    Name = 'M1 the declaration binds `async` as a name again'
    File = $PARSER
    Find = $DECL
    Repl = '          { span: sp, kind: @ast.EName("async"), }'
    MustRed = 'does not bind'
  }

  # M2 THE NOTICE IS DROPPED, sentinel kept. Same observable token stream as
  # the fix, so every reach number in the A/B is identical -- which is exactly
  # why a reach diff CANNOT pin this. A read-past that records nothing is
  # indistinguishable from one that lost the token stream, and only one of those
  # is honest. Measured reach cannot see the difference; only the message can.
  @{
    Name = 'M2 the read-past is silent, keeping the sentinel'
    File = $PARSER
    Find = $DECL
    Repl = '          { span: sp, kind: @ast.EBigInt, }'
    MustRed = 'is announced as read past'
  }

  # M3 THE TWO BRANCHES ARE CONFUSED. The declaration announces itself with the
  # no-following-`fn` message -- the sibling `else` four lines below, which says
  # something materially different: that `fn` is absent, when it is present.
  #
  # This is killed by 0453's test, NOT by anything in pipeline_0457_test.mbt,
  # and that cross-gate coupling is the point worth recording: the assertion
  # that the declaration must not claim `async` has no `fn` belongs to the
  # increment that created the declaration branch, because only that file
  # knows the sibling's message means something else. Renaming either message
  # without moving its test would silently merge two distinct honest reports
  # into one wrong one, and no local test would notice.
  @{
    Name = 'M3 the declaration announces the no-following-fn message'
    File = $PARSER
    Find = $DECL
    Repl = @'
          self.note_skip(
            "async without a following `fn` is outside the analyzed subset; it was read past",
            sp,
          )
          { span: sp, kind: @ast.EBigInt, }
'@
    MustRed = 'with a name is a declaration, not a literal'
  }

  # M4 THE CURSOR MOVES. Someone reads "read past" as "consume" and adds the
  # bump the branch deliberately does not have.
  #
  # MEASURED, NOT ASSUMED: declared KILLED in the first run specifically so the
  # suite could decide. It survived, 643/643 green, and the reason it cannot be
  # observed is structural rather than a gap in the suite:
  #
  # `parse_block` decides declaration-vs-expression by testing the token AT THE
  # CURSOR (`at_name("fn") && name_at(p+1) != ""`, the 0450 discriminator). It
  # falls through to this arm precisely because that test is false while the
  # cursor is on `async`. After the branch -- bumped or not -- the cursor sits on
  # `fn`, so the next loop iteration takes the declaration path either way. The
  # arm's returned node is an expression statement built from the same `sp` in
  # both cases, so the two parses produce the SAME TREE, not merely the same
  # test outcome.
  #
  # That is why this is declared rather than deleted. The branch's comment says
  # "no bump, before or after this increment", and a reader who took the no-bump
  # for load-bearing would be reasoning from a sentence that nothing enforces.
  # The 0436 M3 precedent: a guard nothing can observe should say so out loud
  # instead of growing a test to make it look load-bearing.
  @{
    Name = 'M4 the branch consumes the `async` keyword'
    File = $PARSER
    Find = $DECL
    Repl = @'
          self.note_skip(
            "the `async` of an `async fn` declaration is outside the analyzed subset; it was read past",
            sp,
          )
          let _ = self.bump()
          { span: sp, kind: @ast.EBigInt, }
'@
    Expect = 'SURVIVED'
    Prove = 'Unobservable by construction, not under-tested. parse_block tests the token at the cursor, and after this branch that token is `fn` whether or not the bump happens, so both variants produce the same tree. Measured 643/643 green.'
  }
)

Write-MutationGateVerdict -Name '0457'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

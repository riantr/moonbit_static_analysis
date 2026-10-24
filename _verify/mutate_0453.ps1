# Mutation gate 0453 -- an anonymous ASYNC function literal in expression position.
#
# On the harness: no runner of its own, all rules from `_verify/mutate_lib.ps1`.
# And rule 7 is the one to keep in mind here: nothing else may touch
# `src/parser/parser.mbt` while this runs.
#
# ANCHORS. Every `Find` below is the text as `moon fmt` left it, not as it was
# written. The formatter moved each match arm's brace onto the following line, so
# the first version of this gate had four stale patterns and the PREFLIGHT caught
# all four before a single test ran. That is the preflight earning its place: a
# stale anchor here would have looked like a killed mutation.
#
# AND EVERY `Find`/`Repl` IS PURE ASCII, which is a constraint discovered the hard
# way: M1's original anchor carried the em dash from the comment line below it,
# the preflight reported `PREFLIGHT MISS: M1`, and python found the pattern sitting
# in the source verbatim. The culprit is that PowerShell 5.1 reads a BOM-less .ps1
# as ANSI, so a non-ASCII literal inside a here-string is mangled on the way in --
# the pattern in memory is not the pattern in the file. M2/M3/M4 matched only
# because they are ASCII. (The same mechanism corrupted CJK in an earlier helper;
# see the README commit for that one.) The fix is not a BOM, it is to keep patterns
# ASCII and let the surrounding comment carry the prose.
#
# THE DEFECT. After 0452, moui 0.1.12 still could not finish reading 9 files,
# grouped by the reason the parser gave:
#
#     4x  expected ')'      <- this one
#     3x  unexpected token `,`
#     1x  unexpected end of line
#     1x  unexpected token `:`
#
# `expected ')'` is a complaint about the ARGUMENT of a call, not about the
# parenthesis -- the parser is downstream of the real failure, which is why the
# label sent the first reading towards brackets. Three of the four are the same
# construct (moui 0.1.12 `backend/macos/macos_app_runtime.mbt:24`,
# `backend/linux/linux_app_runtime.mbt:22`, `backend/windows/windows_backend.mbt`):
#
#     launch_async=Some(async fn(request, frame_interval_ms) {
#       ..
#     }),
#
# `parse_atom` had an arm for `TName("fn")` and none for `async`, so `async` was
# read as an ordinary name and the argument never started.
#
# Settled in `_verify/settle_0453_async_fn_expr.ps1`, 6/6 with a positive control:
#
#     Some(fn(a) { .. })        ACCEPT   <- already read, identical shape
#     Some(async fn(a) { .. })  ACCEPT
#     the corpus declaration    ACCEPT
#     ignore(async)             REJECT(3002) "you may expect `fn`"
#     async work()              REJECT(3002)
#
# THE ROWS THAT CONSTRAIN THE FIX are the last two. In the toolchain `async` is
# bound to `fn` and to nothing else -- no `async call` production, no value named
# `async` -- so "consume `async` wherever it appears" would be UNTESTED rather than
# correct. M4 exists for exactly that.
#
#   M1  the `async` arm never fires -- the original behaviour.
#   M2  the `fn` keyword after `async` is not consumed: the head shifts one token.
#   M3  the BODY is not read: parameters and block replaced by a skip.
#   M4  the guard is dropped, so `async` starts a function wherever it appears.
#
# M3 is the one worth having. M1 and M2 are both "the arm is wrong"; M3 is "the arm
# is right and the work behind it is skipped", and it produces neither a parse error
# nor a lost notice. The test that catches it asserts that a real defect INSIDE the
# body is still reported -- see M3's Prove for why the first choice of signal
# (UnusedParam on the literal's own parameters) could not have worked at all.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name 'M1..M5' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the async arm never fires (the original behaviour)'
    File = 'src\parser\parser.mbt'
    Find = @'
    TName("async") =>
      // `async fn(a, b) { .. }`
'@.Replace("`r`n", "`n")
    Repl = @'
    TName("async") if self.at_name("mut_0453_disabled") =>
      // `async fn(a, b) { .. }`
'@.Replace("`r`n", "`n")
    MustRed = '0453: an async fn literal is read as a named argument''s value'
    Prove = @'
The state before this increment. Measured on the corpus and on two fixtures:

    Some(async fn(a) { .. })  -> `expected ')'`
    Some(fn(a) { .. })        -> clean

`expected ')'` is the complaint AFTER the argument of `Some(` failed to parse. It is
about the argument, not about the parenthesis, and that is why the blocker tally
carried it under a reason that pointed at brackets.

THE GUARD IS `at_name` AND NOT `false`. Inside `parse_atom` the cursor has already
passed `async` when the arm is selected, so `at_name` reads the token AFTER it --
`fn` for the real construct, and for this mutation a name no program can contain.
A literal `false` guard was tried first and rejected: it compiles, but it makes the
arm statically dead, and a dead arm and a missing arm are indistinguishable to a
reader. This one is dead only at run time, for the same reason the production it
stands in for was dead.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M2 the fn keyword after async is not consumed'
    File = 'src\parser\parser.mbt'
    Find = @'
        if self.name_at(self.p + 1) == "" {
          let _ = self.bump()
          self.parse_fn_literal(sp)
'@.Replace("`r`n", "`n")
    Repl = @'
        if self.name_at(self.p + 1) == "" {
          self.parse_fn_literal(sp)
'@.Replace("`r`n", "`n")
    MustRed = '0453: an async fn literal is read as a named argument''s value'
    Prove = @'
THE OFF-BY-ONE MUTANT. The arm is found, the guard passes, and the literal is handed
to the reader one token too early. `fn` is still in the stream when
`parse_param_list` runs, so it reads `fn` as the first parameter NAME and the whole
rest of the argument list shifts by one.

This is the mutation that justifies keeping the guard test. It is a one-token change
that removes no production and adds no notice, so it can only be caught by a test
that pins the TOKEN ACCOUNT rather than the outcome -- and `parse_failures == 0`
alone would have called it killed.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M3 the body is skipped, not read'
    File = 'src\parser\parser.mbt'
    # RE-ANCHORED by 0471, and the reason is worth keeping. This pattern used to be the two
    # ADJACENT lines `parse_param_list()` / `parse_block(false)`, because the literal went
    # straight from one to the other. 0471 put the `-> T` / `raise` tail between them --
    #   let _ = self.parse_param_list()
    #   if self.at(TArrow) { ... }
    #   self.parse_raise_effect()
    #   let (_, _) = self.parse_block(false)
    # -- and the two-line pattern stopped matching, which the pre-flight caught and this
    # gate ABORTED on rather than running a suite it could not honestly report.
    #
    # The MUTATION is unchanged in meaning: the body is still skipped rather than read. Only
    # the anchor moved, and it moved onto the pair that still brackets the body parse. A
    # re-anchor is only safe if the thing being mutated is still the same thing, so the
    # anchor is now `parse_raise_effect()` / `parse_block(false)` -- a pair that is UNIQUE in
    # this file, where the bare `let (_, _) = self.parse_block(false)` is not (parse_c_for and
    # parse_if have it too, and anchoring on it alone would mutate one of those instead).
    #
    # RE-ANCHORED AGAIN BY 0503, and the pair stopped being adjacent for the same
    # reason it stopped being adjacent the first time. The `?` marker put a
    # `let bare_raise = ...` line and an `if` block between the raise call and the
    # body parse, so the anchor is now the WHOLE `bare_raise` block plus the body
    # parse. It is still UNIQUE -- the function-type path writes `out = out + "?"`
    # inside its `if`, and the return path is followed by `(full, params, retann)`
    # -- and the MUTATION is unchanged in meaning: the body is still skipped rather
    # than read.
    Find = @'
  let bare_raise = self.at_bare_raise()
  self.parse_raise_effect()
  if bare_raise && self.at(TQuestion) {
    let _ = self.bump()
  }
  let (_, _) = self.parse_block(false)
'@.Replace("`r`n", "`n")
    Repl = @'
  let bare_raise = self.at_bare_raise()
  self.parse_raise_effect()
  if bare_raise && self.at(TQuestion) {
    let _ = self.bump()
  }
  if self.at(TLBrace) { let _ = self.skip_braces() }
'@.Replace("`r`n", "`n")
    MustRed = '0453: a construct inside an async literal''s body is still announced'
    Prove = @'
THE MUTATION THAT MATTERS MOST, because it is the only one a parse-error count cannot
see. The tokens are consumed in order, so there is no parse failure and no lost
notice -- the file reads clean and reports exactly what it reported before.

What is lost is the BODY: a defect inside it is never reached, so a real `undefined
name` in code the toolchain also rejects stops being reported. The test pins that
count at 1, which is why it exists -- `parse_failures == 0` and the notice count are
both satisfied by a body that was stepped over rather than read.

THE MUST-RED WAS RENAMED TWICE BECAUSE THIS MUTATION SURVIVED THE TEST IT NAMED,
twice, and both failures are worth writing down because they are one mistake made
twice: choosing a signal that SOUNDS like the property rather than one that can move.

  1st attempt: `UnusedParam == 0` on the literal's own parameters, reasoning that a
  skipped body would leave them unread. Survived, 616/616 green.
  `parse_fn_literal` does `let _ = self.parse_param_list()`: the parameters are
  parsed and DISCARDED, so they were never in the binding table and `UnusedParam`
  had nothing to report either way. Structurally incapable of moving.

  2nd attempt: `UndefinedName == 1` for a bad call INSIDE the body. Also survived.
  This one fails for the deeper reason: `parse_block` RETURNS its statements and
  `parse_fn_literal` throws them away, so nothing inside a function literal's body
  reaches a lens at all -- for a plain `fn` literal exactly as much as for an async
  one. Asserting it reached 1 asserted a property this analyzer does not have.

  3rd attempt, the one that works: a construct the body DISCOVERS is still
  ANNOUNCED. `parse_block` calls `note_skip` for the declarations it declines to
  analyse, and those go onto the parser rather than into the discarded tree. A
  `match` inside the body is announced by a body that was read and missed by one
  that was skipped.

AND THE TEST ASSERTS THE MESSAGE, not a count, because a count was tried and was
just as bad: every function literal already emits one ParseError of its own, so the
clean fixture sits at 1 and the `match` one at 2 -- a difference of one, carried by
an absolute number that means nothing alone, and unable to say which notice moved.

IT IS THE ONE MUTATION THAT TOUCHES THE PLAIN `fn` PATH TOO, since the helper is
shared. That is deliberate and it is why the helper exists -- a copy would have given
this mutation a second, unaudited site.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M4 the fn guard is dropped'
    File = 'src\parser\parser.mbt'
    Find = @'
      if self.at_name("fn") {
        if self.name_at(self.p + 1) == "" {
'@.Replace("`r`n", "`n")
    Repl = @'
      if true {
        if self.name_at(self.p + 1) == "" {
'@.Replace("`r`n", "`n")
    MustRed = '0453: async without a following fn is read past, not bound as a name'
    Prove = @'
THE OVER-CORRECTION, and the direction a reader reaches after reading the settle: if
`async` introduces a function literal, treat every `async` as one.

The settle forbids it, and not by a small margin:

    ignore(async)     REJECT(3002) "unexpected token `)`, you may expect `fn`"
    async work()      REJECT(3002)

In the toolchain `async` is bound to `fn` and to nothing else. So there is no
`async call` production and no value named `async`, and an unconditional consumption
is justified only by "no valid input looks like this" -- which is exactly the
justification that one day meets one.

WHAT IT BREAKS IN OUR PARSER, and this is the part the settle could not have told me.
Without the guard, `ignore(async)` consumes `async` and then runs `parse_param_list`
at `)`. The `else` branch is what keeps that honest: it reads `async` past with a
notice and yields an opaque node, so the structural lens cannot file
`undefined name 'async'` against code no compiler would run, and cannot invent a
function literal out of a name.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M5 a nested async declaration is announced as an illegal async'
    File = 'src\parser\parser.mbt'
    # RE-ANCHORED by 0457, and the failure that forced it is the useful part.
    #
    # This pattern named the declaration branch's OLD body -- the `EName("async")`
    # that 0457 replaced. 0457 changed that body, so this gate's pre-flight
    # reported `PREFLIGHT MISS: M5` and ABORTED the whole gate rather than
    # quietly passing. That is the harness working: a gate whose anchor has
    # moved is a gate that no longer measures what its name claims.
    #
    # The regression M5 guards is NOT retired -- it shipped once in this
    # repository and the history below is why it stays pinned. The declaration
    # branch now announces itself with its OWN message, so the mutation is the
    # same confusion one branch down: announce the declaration with the sibling's
    # "no following `fn`" message, which is false, because `fn` IS there.
    #
    # This is now the same mutation as 0457's M3, which is a deliberate
    # duplicate rather than a consolidation. Two gates pointing at one branch
    # from two angles is exactly what made the staleness visible here: a single
    # copy would have gone stale in silence the first time 0457 touched the
    # text.
    Find = @'
          self.note_skip(
            "the `async` of an `async fn` declaration is outside the analyzed subset; it was read past",
            sp,
          )
          { span: sp, kind: @ast.EBigInt, }
        }
'@.Replace("`r`n", "`n")
    Repl = @'
          self.note_skip(
            "async without a following `fn` is outside the analyzed subset; it was read past",
            sp,
          )
          { span: sp, kind: @ast.EBigInt, }
        }
'@.Replace("`r`n", "`n")
    MustRed = '0453: a nested async fn with a name is a declaration, not a literal'
    Prove = @'
THE SECOND REGRESSION, and it is the one this increment shipped first and caught
second. Both earlier attempts got the middle case wrong in opposite directions: the
`fn`-only guard consumed a nested declaration as a literal, and the compound guard
sent it to the `else`, which announced it.

`moonbitlang/async@0.22.4` is written with `async fn log(s : String) {` nested inside
function bodies -- `src/all_any_test.mbt:138`, `src/fs/watch_test.mbt:50` and three
more -- and ALL FIVE sites fired that `else`. The notice read `async without a
following `fn` about legal, well-formed MoonBit.

WHAT THIS MUTATION DOES is what the broken version did: take the declaration branch
and announce it. The file still PARSES -- `note_skip` is a notice, not an error, so
`parse_failures` stays 0 and the nested function is still declared by `parse_block` on
the next pass. So a test asserting only that the file parses stays GREEN, and the
false notice ships.

That is why the test's second assertion exists and why it is a MESSAGE check: the
regression is an announcement about correct code, and the only way to see an
announcement that should not be there is to ask for it by name.
'@.Replace("`r`n", "`n")
  }
)

Write-MutationGateVerdict -Name '0453'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

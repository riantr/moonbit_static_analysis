# Mutation gate 0450 -- a `fn` in STATEMENT position is two different things.
#
# On the harness: no runner of its own, all rules from `_verify/mutate_lib.ps1`.
#
# THE DEFECT. A lambda in statement position -- which is how a branch is written
# when its value is a function:
#
#     paint: if disabled {
#       fn(_ctx) { { commands: 1 } }
#     } else {
#       fn(_ctx) { plan0() }
#     }
#
# `parse_block` routed EVERY `fn` to the declaration path, so the lambda fell into
# `parse_fn_signature`, which asks for a name, found `(`, and reported
# `expected function name` -- at a token that is neither unexpected nor unnamed.
# That is the message a reader would chase to a malformed function header, and
# there is none. It is moui 0.1.12 `modifier_env.mbt` cut at `fn(_ctx) {`.
#
# Settled in `_verify/settle_0450_shapes.ps1`, 10/10 with THREE positive controls:
# `ctl_missing` (a name that cannot exist), `ctl_bad_field_type` (4014, so the
# instrument is shown to separate a TYPE verdict from a SYNTAX one), and
# `ctl_quoted_keys` (4014, the step that invalidated two earlier preludes). The
# failing shape is ACCEPTed by `moon check`, so this is a defect and not a
# misreading of illegal code.
#
# WHY IT ONLY SHOWED UP IN A BRANCH, which is worth stating because it is not an
# accident of the corpus. In expression position `let f = fn(x) { .. }` always
# worked: `parse_primary` has a lambda branch. A block STATEMENT is the one place
# the two forms share a token and a cursor.
#
# TWO MUTATIONS ARE KEPT BESIDE THE OBVIOUS ONE because the fix is ONE condition,
# and a condition has two ways to be wrong -- too wide and too narrow. M1 is the
# original. M2 accepts every lambda and rejects every local function, which is the
# direction a reader reaches after reading M1. M3 deletes the condition, which is
# different from inverting it: M1 and M2 both send a LAMBDA to the named-function
# path, and M3 sends a NAMED function to the expression path. Same two tests go
# red, three different reasons, and only the third distinguishes "I flipped it"
# from "I removed it".
#
# The mixed test is a control rather than a killer: a named local function and a
# lambda in one block. It goes red under M2 and M3 and stays GREEN under M1,
# because the lambda in that fixture is in expression position (`let f = ..`) and
# `parse_primary` already handled it. A test that only ever kills one mutation is
# evidence for one mutation.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name 'M1..M3' -Target 'js' -Mutations @(

  @{
    Name = 'M1 every fn in a block is a declaration (the original behaviour)'
    File = 'src\parser\parser.mbt'
    Find = @'
    if self.at_name("fn") && self.name_at(self.p + 1) != "" {
'@.Replace("`r`n", "`n")
    Repl = @'
    if self.at_name("fn") {
'@.Replace("`r`n", "`n")
    MustRed = '0450: a lambda in an if branch is parsed'
    Prove = @'
The state before this increment. Every `fn` in a block goes to `parse_fn_signature`,
which wants a name, and a lambda has `(` where the name should be. Measured before
the fix: THREE ParseErrors on the bare shape -- `expected function name` at each of
the two branches, then `expected '}'` from a cursor that never moved -- and FIVE on
the struct-wrapped shape moui actually writes.

The message is the second half of the defect. `expected function name` names a
problem that does not exist: the token is not unexpected and there is no malformed
header to find. A reader who trusts it looks for the wrong thing entirely.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M2 every fn in a block is a lambda (the over-correction)'
    File = 'src\parser\parser.mbt'
    Find = @'
    if self.at_name("fn") && self.name_at(self.p + 1) != "" {
'@.Replace("`r`n", "`n")
    Repl = @'
    if self.at_name("fn") && self.name_at(self.p + 1) == "" {
'@.Replace("`r`n", "`n")
    MustRed = '0450: a named function declared inside a block is still a declaration'
    Prove = @'
THE DIRECTION A READER REACHES AFTER READING M1. If lambdas are the thing being
missed, treat them all as lambdas.

`SLocalFunc` is not a convenience: the analyzer's OWN `types.mbt` declares a
function inside a block, so this mutation makes the tool fail on its own source.
That is the control worth having -- it is why the named-function test exists
alongside the lambda one, and why a fix that satisfied the lambda test by simply
stopping treating `fn` as a declaration would have been caught by the suite rather
than by review.

It goes red on the mixed fixture too, where a named local function is followed by a
lambda in expression position: the first `fn` is taken as a literal and everything
after it is read as a lambda body.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M3 the named-function path is deleted outright'
    File = 'src\parser\parser.mbt'
    Find = @'
    if self.at_name("fn") && self.name_at(self.p + 1) != "" {
'@.Replace("`r`n", "`n")
    Repl = @'
    if false && self.at_name("fn") && self.name_at(self.p + 1) != "" {
'@.Replace("`r`n", "`n")
    MustRed = '0450: a named function declared inside a block is still a declaration'
    Prove = @'
NOT THE SAME AS M2, and the pair is the reason both are here. M2 sends a LAMBDA to
the named-function path; M3 sends a NAMED FUNCTION to the expression path. The same
test is red for each, and a reader who only saw the outcome could not tell which of
the two mistakes was made -- which is the whole difference between "the condition is
inverted" and "the condition is gone".

`false &&` keeps the `name_at` call compiled, so the mutation measures the DECISION
rather than the compiler deleting a call.

Measured cost: with no named-function path at all, every `fn` in the analyzer's own
`src/types.mbt` is parsed as an expression, so a named local function reports
`undefined name` for the name it declares.
'@.Replace("`r`n", "`n")
  }
)

Write-MutationGateVerdict -Name '0450'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

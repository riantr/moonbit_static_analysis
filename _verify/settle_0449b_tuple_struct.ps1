# Settles the TUPLE struct form `struct Name(T, T)` for 0.4.39.
#
# WHY THIS EXISTS. Settling the external `fn` binding (0449) made 21 more async
# files readable, and one of them then produced two FALSE POSITIVES that had
# been hidden by truncation:
#
#   moonbitlang/async 0.22.4 src/process/cancellation.mbt:41,42
#     undefined variable 'else'
#     undefined variable 'SIGTERM'
#
# The file contains
#
#     pub(all) struct CancellationHandler(async (Int) -> Unit)
#
#     ///|
#     let default_signal : @signal.Signal = if @event_loop.platform is Windows {
#       SIGBREAK
#     } else {
#       SIGTERM
#     }
#
# `skip_decl_braced` looks for the `{` that opens a declaration body. A tuple
# struct HAS NO BRACE, so the scan runs on and takes the `if`'s. The `let` and
# the `if` are swallowed with it, and what is left reads as a block containing
# the words `else` and `SIGTERM`.
#
# FOUR HYPOTHESES, THREE OF THEM FALSIFIED, because each looked like the cause:
#
#   "the `is` pattern is the problem"          FALSIFIED -- `if p is Windows {
#                                               .. } else { .. }` alone is clean.
#   "a qualified receiver is the problem"      FALSIFIED -- `if h.platform is
#                                               Windows { .. } else { .. }` is clean.
#   "a cross-package `@pkg.field` is it"       FALSIFIED -- `if @event_loop.platform
#                                               is Windows { .. } else { .. }`, scanned
#                                               against the REAL extern interfaces, is clean.
#   "it is what came BEFORE the if"            MEASURED -- tuple struct + `if/else`
#                                               reproduces; the same `if/else` with a
#                                               BRACED struct, or with no struct, is clean.
#
# That last one is the control the other three needed: all three probes tested
# the `if` in isolation, and the cause was not in the `if` at all. What the
# `is` probes share with the failing case is nothing, which is what a probe that
# only ever varies the wrong variable looks like.
#
# POSITIVE CONTROL. `ctl_missing` names something that cannot exist and MUST be
# rejected. Five malformed probes in this repository would have reported a
# confident wrong answer here. Three scaffold facts are load-bearing: `moon.mod`
# MUST declare `source = "src"`; a package cannot import its OWN root; and the
# output is joined with NEWLINES before any `(?m)` pattern is applied.

$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

$PRELUDE = @'
///|
enum Platform {
  Windows
  Linux
}

///|
pub struct Holder {
  platform : Platform
}

'@

# --- the control ----------------------------------------------------------
Add-Case 'ctl_missing' @'
///|
fn probe() -> Int {
  ignore(ZzMissing)
  0
}
'@ 'REJECT'

# An EMPTY tuple struct is not MoonBit. Pinned because `at_tuple_struct` answers
# `true` for it too, and a case that shows the toolchain rejects it keeps that
# from reading as "and those are fine as well".
Add-Case 'ctl_empty_tuple' ($PRELUDE + @'
///|
pub struct Unit()
'@) 'REJECT'

# --- the shapes -----------------------------------------------------------
# The corpus line, verbatim. This is the one the whole increment is about.
Add-Case 'tuple_fn_field' ($PRELUDE + @'
///|
pub(all) struct CancellationHandler(async (Int) -> Unit)
'@) 'ACCEPT'

Add-Case 'tuple_two_fields' ($PRELUDE + @'
///|
pub struct Pair(Int, Platform)
'@) 'ACCEPT'

# THE COMPOSITION, which is the shape that produced the false positives: a tuple
# struct followed by an `if/else`. Settled as ONE case because the two are only
# interesting together -- either alone parses, and the defect needs the second
# to show itself.
Add-Case 'tuple_then_if_else' ($PRELUDE + @'
///|
pub(all) struct CancellationHandler(async (Int) -> Unit)

///|
fn pick(p : Platform) -> Int {
  let v = if p is Windows {
    1
  } else {
    2
  }
  v
}

///|
fn init {
  ignore(pick(Windows))
}
'@) 'ACCEPT'

# THE CONTROL FOR THE BRACED PATH, and the reason `at_tuple_struct` can be a
# narrow check. A braced struct followed by the same `if/else` was already clean
# before this change; if it stops being clean, the discrimination has taken a
# declaration it should not have.
Add-Case 'braced_then_if_else' ($PRELUDE + @'
///|
fn pick(p : Platform) -> Int {
  let v = if p is Windows {
    1
  } else {
    2
  }
  v
}

///|
fn init {
  ignore(pick(Windows))
}
'@) 'ACCEPT'

# A QUALIFIED tuple-struct name is not MoonBit: `[3002]` at the declaration.
# Settled rather than assumed, because `at_tuple_struct` scans THROUGH `::` to
# reach the `(`, and the honest reading of that is that the scan must stop at a
# qualified name -- which would be a different and narrower predicate.
#
# It does not have to be. The `TColon` branch is not there to find a tuple
# struct behind a qualified name; there is no such form. It is there so that
# `struct Outer::Inner { .. }` -- a qualified BRACED struct, which does exist --
# walks past its `::` to the `{` and is answered false, keeping the braced path.
# Dropping the branch would send that declaration down the line skipper and parse
# its body as top-level statements: the cascade this increment removes, reached
# from the other side. Pinned as REJECT because it is what the toolchain says.
Add-Case 'tuple_qualified_name' ($PRELUDE + @'
///|
pub struct Outer::Inner(Int)
'@) 'REJECT'

# ... and the qualified BRACED form, which is not MoonBit either. Both qualified
# forms being absent is what licenses `at_tuple_struct` to be a PLAIN-NAME rule
# with no bound and no `::` branch: it answers false for two shapes that cannot
# occur, and true only for `struct Name(`.
Add-Case 'qualified_braced' ($PRELUDE + @'
///|
pub struct Outer::Inner {
  v : Int
}
'@) 'REJECT'

# --- run ------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0449b_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0449b`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') |
    ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($plan) {
    $got = 'BUILD-PLAN-FAILED'
    $ok = $false
  } elseif ($want -eq 'REJECT') {
    $got = if ($errs.Count) { 'REJECT(' + ($errs -join ',') + ')' } else { 'ACCEPT' }
    $ok = $got -like 'REJECT*'
  } else {
    $got = if ($errs.Count) { 'REJECT(' + ($errs -join ',') + ')' } else { 'ACCEPT' }
    $ok = ($got -eq 'ACCEPT')
  }
  Write-Output ('{0,-24} {1,-22} (want {2,-6}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. A BUILD-PLAN-FAILED row means the scaffold is wrong and NOTHING here'
  Write-Output 'is an answer. A `ctl_*` row reading ACCEPT means `moon check` is not'
  Write-Output 'discriminating and the ACCEPT rows beside it prove nothing.'
  exit 1
}
Write-Output 'GATE OK: the tuple struct is valid MoonBit with and without an if/else after'
Write-Output 'it, so the two false positives were produced by the skip and not by the'
Write-Output 'code. The braced path is settled beside it because that is the path the'
Write-Output 'discrimination must not touch.'
exit 0

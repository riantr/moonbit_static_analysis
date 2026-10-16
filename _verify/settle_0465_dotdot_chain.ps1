# Settle 0465 -- the `..` METHOD-CHAIN continuation.
#
# WHY. `..` is two constructs that share a spelling (see
# `_verify/blockers_0465_dotdot_chain.txt`). The struct-update spread `{ ..base, f }`
# is handled at parser.mbt:4321. The CHAIN is not: `parse_postfix_from` does `bump()`
# then `expect_name("field name")`, and `..m(x)` arrives as TDot TDot TName, so the
# second TDot reaches `expect_name`. Measured on fixtures -- all six double-dot shapes
# NOTPARSE with `expected field name`, both controls CLEAN.
#
# It is async-only: 180 chain sites across 33 files, versus 0 in moui and 0 in labeler,
# whose `..` are all spreads.
#
# THE QUESTION IS NOT "is this legal". The corpus is full of it. The question is what
# `a..f(x)` EVALUATES TO, because that decides the node:
#
#   (a) `..` is a spelling of `.`           -> the fix is "consume the extra dot"
#   (b) `..` calls f and KEEPS the receiver -> the fix is a distinct node whose type
#                                               is the receiver's, not f's
#
# The symbol suggests nothing. The corpus suggests (b): `self` is followed by two
# `..write(...)` links and one final `.send_headers(...)`, and under (a) the author was
# mixing two spellings of one operator for no reason.
#
# THE DECISIVE ROW IS `dd_after_int`. Under (b), `S::new()..get().v` is `S::new().v`
# and ACCEPTS, because `..get()` yields the RECEIVER, not the Int that `get` returned.
# Under (a) it is `(S::new().get()).v` and REJECTS -- there is no `.v` on an Int.
# `dot_after_int` is the control for that row: it is the `.` spelling of the same
# expression, and it must REJECT, or the row above would accept for an unrelated reason.
#
# => the expectations on the rows UNDER TEST are 'MEASURE', not ACCEPT/REJECT. This
# settle does not know the answers and is not allowed to encode a guess as truth: a
# settle that asserts what I already believe cannot tell me I was wrong. Only the
# CONTROLS carry asserted expectations, because a control that cannot fail is not a
# control.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# THE STRUCT, reused by every row. `bump` returns S (so it works under both readings),
# `get` returns Int (so it separates them), `reset` takes no argument (so a no-arg
# chain link can be tested at all).
$PRELUDE = @'
///|
struct S {
  v : Int
} derive(Show, Eq)

///|
fn S::new() -> S {
  { v: 0 }
}

///|
fn S::bump(self : S) -> S {
  { v: self.v + 1 }
}

///|
fn S::get(self : S) -> Int {
  self.v
}

///|
fn S::reset(self : S) -> S {
  { v: 0 }
}
'@

# CONTROL 1: the package must be able to ACCEPT something, or every ACCEPT below is
# an empty package rather than a legal construct.
Add-Case 'ctl_ok' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new().bump().get()
}
'@) 'ACCEPT'

# CONTROL 2: `moon check` must be able to REJECT, or an ACCEPT is meaningless. This
# is the row that proves the harness has a working failure channel.
Add-Case 'ctl_bad' ($PRELUDE + @'

///|
fn probe() -> Int {
  ZzMissing
}
'@) 'REJECT'

# THE SINGLE-DOT BASELINE, which the analyzer already reads (parser.mbt:2346). It is a
# third control: it is the shape the double-dot rows are variations of, so if it ever
# stops ACCEPTing the double-dot rows stop meaning anything.
Add-Case 'dot_chain' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new()
  .bump()
  .get()
}
'@) 'ACCEPT'

Add-Case 'dd_leading' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new()
  ..bump()
  .get()
}
'@) 'MEASURE'

Add-Case 'dd_inline' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new()..bump().get()
}
'@) 'MEASURE'

Add-Case 'dd_two_links' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new()..bump()..bump().get()
}
'@) 'MEASURE'

# THE DECISIVE ROW. Under (b) the chain yields the RECEIVER, so `.v` resolves and this
# ACCEPTS. Under (a) it yields `get`'s Int, and `.v` on an Int REJECTS.
Add-Case 'dd_after_int' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new()..get().v
}
'@) 'MEASURE'

# THE CONTROL FOR THE DECISIVE ROW -- the `.` spelling of the identical expression.
# Must REJECT. If it ACCEPTS, then `.v` is reachable some other way and `dd_after_int`
# proves nothing.
Add-Case 'dot_after_int' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new().get().v
}
'@) 'REJECT'

# `..` as the LAST link, with no trailing `.`. The corpus always ends on a single dot,
# so whether the double-dot form is legal in final position is unknown.
Add-Case 'dd_final_link' ($PRELUDE + @'

///|
fn probe() -> Int {
  let x = S::new()
    ..bump()
  x.v
}
'@) 'MEASURE'

Add-Case 'dd_noarg_link' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new()
  ..reset()
  .get()
}
'@) 'MEASURE'

# A link that is not a method at all. Under (b) this has to fail, since there is
# nothing to call and the receiver is what survives.
Add-Case 'dd_unknown_name' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new()
  ..zzz_missing
  .get()
}
'@) 'REJECT'

# IS `..` A CALL AT ALL, or is it a projection? Both rows below pass a chain link that
# only a CALL can reject, and both are checked statically by `moon check` because the
# arity and the field are resolved at type time regardless of whether the body runs.
#
# `dd_arity` gives the link a real name with the WRONG number of arguments. If `..`
# invokes it, this is an arity error. If `..` were a field access that merely keeps the
# receiver, the argument list would have nothing to bind to and it might still accept.
Add-Case 'dd_arity' ($PRELUDE + @'

///|
fn S::two(self : S, a : Int, b : Int) -> S {
  { v: self.v + a + b }
}

///|
fn probe() -> Int {
  S::new()
  ..two(1)
  .get()
}
'@) 'MEASURE'

# `dd_field` gives the link a name that is a FIELD, not a method. Under the call
# reading it is an error; if it accepts, `..` is reaching fields, and the node is not
# a discarded call.
Add-Case 'dd_field' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new()
  ..v
  .get()
}
'@) 'MEASURE'

# IS THE PARENTHESIS REQUIRED? `dd_noarg_link` settled `..reset()` -- zero arguments,
# parens present. This row drops the parens from a link that names a real METHOD. If
# it ACCEPTS, the parser has to accept a bare `..name` too, and if it REJECTs then a
# parenthesised-only production is not a shortcut but the grammar.
Add-Case 'dd_bare_name' ($PRELUDE + @'

///|
fn probe() -> Int {
  S::new()
  ..bump
  .get()
}
'@) 'MEASURE'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0465_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0465`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($plan) {
    $got = 'BUILD-PLAN-FAILED'
    $ok = $false
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'ACCEPT') { $ok = $false }
    elseif ($want -eq 'REJECT') { $ok = $got -like 'REJECT*' }
    else { $ok = $true }   # MEASURE
  } else {
    $got = 'ACCEPT'
    $ok = ($want -ne 'REJECT')
  }
  $tag = $(if ($want -eq 'MEASURE') { 'measured' } elseif ($ok) { 'OK' } else { '*** MISMATCH ***' })
  Write-Output ('{0,-18} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $tag)
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|constructor' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'GATE OK -- all CONTROLS held (ctl_ok/dot_chain ACCEPT, ctl_bad/dot_after_int/dd_unknown_name REJECT).'
} else {
  Write-Output ("*** GATE FAILED: $fail control(s) did not hold. Rows under test are not evidence until the controls hold. ***")
}
exit $fail

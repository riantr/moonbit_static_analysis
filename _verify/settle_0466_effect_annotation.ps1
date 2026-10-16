# Settle 0466 -- the return-type EFFECT ANNOTATION: `-> T noraise` / `-> T nocancel`.
#
# WHY. Re-ranked per-FILE FIRST BLOCKER on the tree that shipped as 8902242, because
# the ranking in `_verify/blockers_0464_ranked.txt` predates 0465 (async parsed
# 325 -> 330). Recovered from each PARTIAL file's `read up to line N`; the script is
# `_verify/rank_0466_first_blocker.ps1` and it PRINTS the classified lines, because
# three classifiers in a row returned a plausible total while being wrong.
#
# `raise` IS ALREADY HANDLED and is the control that makes this a two-keyword gap:
#
#     corpus     raise    noraise          nocancel
#     moui          2     0 (0 files)      0 (0 files)      moui 608/608 parsed
#     image        67     0                0                image 15/18 parsed
#     async       164     16 (9 files)    13 (7 files)
#     proton      781   121 (12 files)     0                proton 115/137 parsed
#
# REACH, and it is not the site count. Of the files still unread -- async 47 PARTIAL
# of 419, proton 17 of 137 -- the ones whose first blocker is this shape:
#
#     RETURN position   ) -> T noraise {      16 files  (async 11, proton 5)
#     PARAM  position   name : T noraise ,     5 files  (proton 4, async 1)
#
# 16 + 5 = 21 of the 64 unread files. The param form is NOT included: its corpus lines
# are `handler : async (A, B) -> Unit noraise,`, which also needs the `async (..)`
# TYPE -- a different construct with its own settle. Shipping both under one commit
# would measure a fix on half the work.
#
# The corpus spellings, which are what the rows below are written against:
#
#     pub async fn Mutex::acquire(self : Mutex) -> Unit noraise {
#     pub async fn remove(path : StringView) -> Unit nocancel {
#     ) -> async (@proton_contract.ContractRoute, String, Json) -> Unit noraise {
#
# => the expectations on rows UNDER TEST are 'MEASURE' where the answer is genuinely
# unknown, and asserted ACCEPT/REJECT only where the corpus already proves it or where
# a control has to be able to fail. A settle that asserts what I already believe
# cannot tell me I was wrong.
#
# ---------------------------------------------------------------------------
# RESULT, 13 rows, GATE OK:
#
#     ctl_ok                 ACCEPT            control: the package can accept
#     ctl_bad                REJECT(4021)      control: check can reject
#     ret_noraise            ACCEPT            -> Unit noraise
#     ret_nocancel           ACCEPT            -> Unit nocancel
#     ctl_async              ACCEPT            control: async fn already works (0457)
#     ret_async_noraise      ACCEPT            the effect on an async fn
#     ctl_raise              ACCEPT            control: `raise` ALREADY works
#     ret_bogus_effect       REJECT(3002)      CANARY: the slot is a keyword set
#     ret_noraise_nonunit    ACCEPT            any return type, not just Unit
#     ret_async_type_noraise ACCEPT            the effect attaches to an async type
#     ret_bang               ACCEPT            `!` is ALSO an effect in this slot
#     ret_noraise_raise      REJECT(3002)      effects do NOT stack -- exactly one
#     param_noraise          ACCEPT            the parameter slot too (not landed)
#
# THE GRAMMAR, all three parts measured:
#
#     <return-type> <effect>       where <effect> is ONE of `!` `raise` `noraise`
#                                                  `nocancel`
#                               -- and ONLY ONE of them.
#
# Two of those would have been implemented wrong on the symbol alone. `!` is not a
# keyword-looking neighbour of `noraise`; it is the effect-ROW operator that gates
# 0.4.23-0.4.29 already read, and it belongs in the same slot. And "effects stack" is
# what `raise` + `noraise` looks like in any other language, so a loop would have been
# the natural guess -- `ret_noraise_raise` REJECTs, so it must be a single optional
# keyword.
#
# The canary is what pins the third part. `ret_bogus_effect` REJECTs, so the slot
# cannot be "consume whatever sits between the type and `{`" -- which is the
# shortcut a parser reaches for first, and which would accept programs the
# toolchain refuses.
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# CONTROL 1: the package must be able to ACCEPT something.
Add-Case 'ctl_ok' @'
///|
fn f() -> Int {
  1
}
'@ 'ACCEPT'

# CONTROL 2: `moon check` must be able to REJECT. Without this an ACCEPT below could be
# a checker that accepts anything.
Add-Case 'ctl_bad' @'
///|
fn f() -> Int {
  ZzMissing
}
'@ 'REJECT'

# THE TWO CORPUS SPELLINGS. `src/mutex.mbt:42` and `src/fs/file.mbt:414`.
Add-Case 'ret_noraise' @'
///|
fn f() -> Unit noraise {
  ()
}
'@ 'ACCEPT'

Add-Case 'ret_nocancel' @'
///|
fn f() -> Unit nocancel {
  ()
}
'@ 'ACCEPT'

# AND ON AN `async fn`, which is how all 11 async sites spell it. `async fn` itself is
# already handled (0457), so this row is about the EFFECT and not about the keyword --
# which the `ctl_async` row beside it confirms by carrying no effect at all.
Add-Case 'ctl_async' @'
///|
async fn f() -> Unit {
  ()
}
'@ 'ACCEPT'

Add-Case 'ret_async_noraise' @'
///|
async fn f() -> Unit noraise {
  ()
}
'@ 'ACCEPT'

# `raise` IS ALREADY HANDLED (0 blocked files against 781 proton sites), so this row is
# the control for "the effect slot exists" rather than a thing being fixed. If it ever
# stops ACCEPTing, the parser regressed on a construct that was working.
Add-Case 'ctl_raise' @'
///|
fn f() -> Unit raise {
  ()
}
'@ 'ACCEPT'

# THE CANARY. The effect is a KEYWORD SLOT, not any word before the brace: if this
# ACCEPTS, the parser is reading "whatever is between the type and `{`" and would
# accept a program the toolchain refuses. It is the row that makes the ACCEPTs above
# mean something.
Add-Case 'ret_bogus_effect' @'
///|
fn f() -> Unit bogus {
  ()
}
'@ 'REJECT'

# A NON-UNIT return type with the effect, since all 16 reachable sites are `-> Unit`
# except `facade_bridge.mbt` which returns through an async type. A parser that only
# pattern-matched `Unit` would pass every corpus row and fail this one.
Add-Case 'ret_noraise_nonunit' @'
///|
fn f() -> Int noraise {
  1
}
'@ 'MEASURE'

# THE PROTON SPELLING: an `async (...)` RETURN type carrying the effect.
# `facade_bridge.mbt:411` is `) -> async (@proton_contract.ContractRoute, String, Json)
# -> Unit noraise {`.
#
# The first version of this row was `() => 1` and it REJECTed with 4013/4014, which
# reads like "the effect cannot attach to an async type". It cannot mean that. The
# error says, in full:
#
#   This function has type `async (Int, Int) -> Unit noraise`, which expects 2
#   argument(s), but is given 0 argument(s).
#
# Two things at once: `async (Int, Int)` is a function taking TWO ARGUMENTS and not a
# two-element tuple, which the row's author had assumed; and the toolchain prints the
# effect INSIDE the type, which is the whole claim. A rejected fixture is evidence
# about the fixture until you have read the error -- "REJECT" was going to be recorded
# as a grammar fact here and it was a syntax error in the test.
Add-Case 'ret_async_type_noraise' @'
///|
async fn f() -> async (Int) -> Unit noraise {
  x => ()
}
'@ 'MEASURE'

# CAN THERE BE MORE THAN ONE EFFECT, and in which ORDER? `!` is the effect-ROW operator
# the 0.4.23-0.4.29 gates read, and `noraise`/`nocancel` are rows on it. The corpus has
# none, so this is measured rather than assumed -- and it decides whether the parser
# needs a LOOP or a single optional keyword.
Add-Case 'ret_bang' @'
///|
fn f() -> Unit ! {
  ()
}
'@ 'MEASURE'

Add-Case 'ret_noraise_raise' @'
///|
fn f() -> Unit noraise raise {
  ()
}
'@ 'MEASURE'

# THE PARAMETER POSITION, which is 5 more files and is DELIBERATELY EXCLUDED. This row
# exists to record what the toolchain does with it, not to license shipping it: those
# 5 corpus sites also need the `async (..)` TYPE, so the effect slot there cannot be
# landed without a second construct in the same commit.
Add-Case 'param_noraise' @'
///|
fn f(g : (Int) -> Unit noraise) -> Int {
  1
}
'@ 'MEASURE'

# DOES `noraise` CARRY AN ERROR TYPE? `raise` does -- `-> T raise E` names one, and
# the parser's `parse_raise_effect` has a whole guard about where that type stops. If
# `noraise E` is legal then "bump and return" is WRONG and would leave the `E` in the
# token stream, which is the silent-misparse direction the existing comment on that
# guard warns about. Measured rather than assumed.
Add-Case 'ret_noraise_with_type' @'
///|
fn f() -> Unit noraise E {
  ()
}

///|
struct E
'@ 'MEASURE'

Add-Case 'ret_nocancel_with_type' @'
///|
fn f() -> Unit nocancel E {
  ()
}

///|
struct E
'@ 'MEASURE'

# And the mirror: a type with NO effect keyword at all must still work, or a parser
# that consumed "the word after the return type" would break it. This is the control
# for the guard above.
Add-Case 'ctl_no_effect' @'
///|
fn f() -> Int {
  1
}
'@ 'ACCEPT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0466_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0466`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-22} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $tag)
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|constructor|effect' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'GATE OK -- all CONTROLS and asserted rows held (ctl_ok/ret_noraise/ret_nocancel/ctl_async/ctl_raise ACCEPT; ctl_bad/ret_bogus_effect REJECT).'
} else {
  Write-Output ("*** GATE FAILED: $fail asserted row(s) did not hold. Rows under test are not evidence until the controls hold. ***")
}
exit $fail

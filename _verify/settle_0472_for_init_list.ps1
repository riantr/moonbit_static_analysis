# Settle 0472 -- the C-style `for` with MORE THAN ONE initializer, and `for` as an EXPRESSION.
#
# WHY. Measured as per-FILE first blockers on the tree at 0471 (31 unread files across the
# four corpora), two shapes dominate async, and the analyzer's own output -- the source line
# it stopped at -- is the only trustworthy ranking:
#
#   SHAPE A, a comma-separated INITIALIZER LIST plus an absent update clause. Four files,
#   and the first two stop on this exact line:
#
#       async/src/websocket/utils.mbt:49      for i = 0, remaining = remaining; i < data.length(); {
#       async/src/internal/gzip_internal/crc32.mbt:53   for crc = current, i = 0; i + 8 <= len; {
#       async/src/socket/addr_utils.mbt:262   for i = 0, zero_group_start = 0; i < 8; i = i + 1 {
#       async/src/internal/event_loop/io.mbt:202        for rest = buf[:n], produced = 0 {
#
#   Every one of those bodies then does `continue <v1>, <v2>` -- so the loop carries SEVERAL
#   mutable variables and `continue` assigns ALL of them.
#
#   SHAPE B, `for` in EXPRESSION position, whose value is a `nobreak` block. Five files:
#
#       async/src/websocket/conn.mbt:486     let kind : MessageKind = for frame = ... {
#       async/src/process/unix.mbt:66        for k, v in extra_env; i = 0 {
#       async/src/process/windows.mbt:57     let extra_env_len = for k, v in extra_env; acc = 0 {
#       async/src/io/reader.mbt:176          let prefix_len = for prefix in prefix_list; len = 0 {
#       async/src/http/parser.mbt:80         let available = for available = ...; available <
#
#   windows.mbt:57-61 and reader.mbt:176-180 show the whole shape:
#
#       let extra_env_len = for k, v in extra_env; acc = 0 {
#         continue acc + k.length() + v.length() + 2
#       } nobreak {
#         acc
#       }
#
# => 判据: THE RANKING THAT LOCATED THIS WAS WRONG FIRST. `_verify/rank_0468_first_blocker.ps1`
# prints, for each unreadable file, a header line and then the blocker SOURCE line, but the
# source lines are laid out AFTER the header they belong to only loosely, and reading them as
# paired produced a shape count that was wrong in both directions -- attributing a `for` to a
# file whose blocker was a destructuring `let`. The fix was to stop reading that layout and
# ask the scanner for `read up to line N`, then read line N of THAT file. A ranking is a
# report; deriving structure from a report's formatting is how the ranking gets wrong.
#
# This settle asks only what the TOOLCHAIN says. What the analyzer does about it is the next
# step, and the two have already disagreed once in this project.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
#
# THE CONTROL. The single-initializer, update-clause form this increment does not touch. It
# is what `parse_c_for` already reads, and it is settled by 0470's claim 1, so a failure here
# means the scaffold rather than the grammar.
Add-Case 'ctl_single_init' @'
///|
fn f(n : Int) -> Unit {
  for i = 0; i < n; i = i + 1 {
    ignore(i)
  }
}
'@ 'ACCEPT'

# AND A CONTROL FOR SHAPE A: a comma-separated list in a place that is definitely NOT a for
# initializer -- a tuple. If this fails, the fixture is wrong rather than the grammar.
Add-Case 'ctl_tuple_comma' @'
///|
fn f() -> Unit {
  let (a, b) = (1, 2)
  ignore(a + b)
}
'@ 'ACCEPT'

# --- SHAPE A. Gated. ----------------------------------------------------------
#
# A1. TWO comma-separated initializers, update clause PRESENT.
Add-Case 'A1_two_inits_with_update' @'
///|
fn f(n : Int) -> Unit {
  for i = 0, total = 0; i < n; i = i + 1 {
    continue i + 1, total + i
  }
}
'@ 'ACCEPT'

# A2. TWO initializers and the update clause ABSENT -- the trailing `;` before `{`, which is
# what utils.mbt:49 and crc32.mbt:53 both have. This is the form in the corpus and it is a
# DIFFERENT question from A1: whether the third clause may be omitted.
Add-Case 'A2_two_inits_no_update' @'
///|
fn f(n : Int) -> Unit {
  for i = 0, total = 0; i < n; {
    continue i + 1, total + i
  }
}
'@ 'ACCEPT'

# A3. `continue` assigning BOTH accumulators. If this is not legal, shapes A1/A2 are a
# different feature from the corpus shape and the increment is aimed at the wrong thing.
Add-Case 'A3_continue_two_values' @'
///|
fn f(data : Array[Int]) -> Unit {
  for i = 0, remaining = 0; i < data.length(); {
    continue i + 1, remaining - 1
  }
}
'@ 'ACCEPT'

# A4. THREE initializers, so the claim is about a LIST and not about the number two.
Add-Case 'A4_three_inits' @'
///|
fn f(n : Int) -> Unit {
  for i = 0, a = 1, b = 2; i < n; {
    ignore(a + b)
  }
}
'@ 'ACCEPT'

# --- SHAPE B. Gated. ----------------------------------------------------------
#
# B1. `for` in EXPRESSION position, value taken from a trailing `nobreak` block. This is
# reader.mbt:176-180 verbatim in shape.
Add-Case 'B1_for_expression_nobreak' @'
///|
fn f(xs : Array[Int]) -> Int {
  let total = for x in xs; acc = 0 {
    continue acc + x
  } nobreak {
    acc
  }
  total
}
'@ 'ACCEPT'

# B2. The same with the C-style header rather than the binder form. The `nobreak` value is
# the loop variable `i`, which IS in scope there -- the first draft used `total`, the very
# `let` being defined, and the toolchain said `the value identifier total is unbound`.
Add-Case 'B2_for_expression_cstyle' @'
///|
fn f(n : Int) -> Int {
  let total = for i = 0; i < n; i = i + 1 {
    continue i
  } nobreak {
    i
  }
  ignore(total)
  0
}
'@ 'ACCEPT'

# B3. `for` as an expression WITHOUT `nobreak`, where the value is the body's tail. reader.mbt
# and windows.mbt both use `nobreak`, but conn.mbt:486 reads `for frame = ... {` and the
# question "may the value be the tail instead" is separate from "is `nobreak` required".
Add-Case 'B3_for_expression_tail' @'
///|
fn f(xs : Array[Int]) -> Int {
  let total = for x in xs {
    ignore(x)
  }
  ignore(total)
  0
}
'@ 'ACCEPT'

# --- RECORDED. Read the column, do not gate on it. -----------------------------
#
# Whether a `for` expression's `nobreak` value is itself an EXPRESSION or only a block is a
# question this increment has not needed answered yet. Recorded rather than predicted.
Add-Case 'record_nobreak_expr_value' @'
///|
fn f(xs : Array[Int]) -> Int {
  let total = for x in xs; acc = 0 {
    continue acc + x
  } nobreak {
    acc + 1
  }
  total
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0472_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0472`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
    $got = 'BUILD-PLAN-FAILED'; $ok = $false
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'RECORD') { $ok = $true }
    elseif ($want -eq 'ACCEPT') { $ok = $false }
    else { $ok = $got -like 'REJECT*' }
  } else {
    $got = 'ACCEPT'
    if ($want -eq 'RECORD') { $ok = $true } else { $ok = ($want -eq 'ACCEPT') }
  }
  Write-Output ('{0,-30} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. Both controls must behave.'
  Write-Output 'A flipped CLAIM means the analyzer change is aimed at something the toolchain refuses.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

# Settle 0474 -- a loop in EXPRESSION position, and which HEAD it may carry.
#
# WHY. Settle 0472 established that `for` may be an EXPRESSION (rows B1/B2/B3, all
# ACCEPT). What it did NOT establish is that the ANALYZER reads it, and for a long time
# nobody checked: `parse_atom` has a `TName("for") | TName("while")` arm wired to
# `parse_loop_as_expr`, so the production exists and looks correct in a skim.
#
# It is not correct. `parse_atom` matches on `self.bump()`, so the loop keyword is consumed
# as the match SCRUTINEE, and by the time `parse_loop_as_expr` runs the cursor sits on the
# token AFTER it. Its `at_name("while")` re-test is therefore false for every loop
# expression and all of them are routed to `parse_for_stmt`, which bumps the next token as
# if it were `for`. Isolated by a temporary `println` trace, added and then reverted:
#
#     TRACE atom enter    p=13 cur=`while`
#     TRACE atom dispatch p=14 cur=`a`
#     TRACE as_expr       p=14 cur=`a` at_while=false
#
# => 判据: a helper that re-derives which construct it is handling, from a cursor its caller
# has already moved, cannot be correct by construction. The caller already knows which arm
# it matched.
#
# This settle asks only what the TOOLCHAIN says about the shapes the fix now claims to read.
# It is deliberately small: the grammar was already settled twice, and a settle that
# re-asks a settled question is ceremony rather than evidence. What is NEW here is the
# `while` head, which no earlier settle covered in expression position.
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
# THE CONTROL, and it is the one that matters most: the SAME loop in STATEMENT position.
# Statement position has always worked, so a failure here means the fixture, while a
# failure of the rows below means the fix. A change to expression position that quietly
# broke statement position would trade one class of unreadable file for another.
Add-Case 'ctl_while_statement' @'
///|
fn f(a : Int) -> Int {
  while a > 0 {
    ignore(1)
  }
  0
}
'@ 'ACCEPT'

# AND THE SAME for `for`, in the binder header form.
Add-Case 'ctl_for_statement_binder' @'
///|
fn f(xs : Array[Int]) -> Int {
  for x in xs {
    ignore(x)
  }
  0
}
'@ 'ACCEPT'

# --- A `while` EXPRESSION whose head carries an operator. -------------------------
#
# A1. The shape conn.mbt's neighbourhood is written in, and the one that broke.
#
# UNIT, NOT Int, and that is a scaffold lesson rather than a footnote. The first draft of
# this settle wrote `let k = while a > 0 { 1 }` and every row came back REJECT(4139) --
# `while` is Unit-valued, and a bare `1` in statement position cannot be implicitly ignored.
# Both controls failed too, which is what identified it as the SCAFFOLD: the toolchain was
# answering a type question, not a grammar one.
Add-Case 'A1_while_expr_operator' @'
///|
fn f(a : Int) -> Unit {
  let k : Unit = while a > 0 {
    ignore(1)
  }
  ignore(k)
}
'@ 'ACCEPT'

# A2. A call head. This row is here because it is the one that PARSED BEFORE THE FIX, and
# a fixture set containing only the failing rows would not have caught that the trigger was
# the misroute rather than the operator.
Add-Case 'A2_while_expr_call_head' @'
///|
fn g(a : Int) -> Int { a }

fn f(a : Int) -> Unit {
  let k : Unit = while g(a) > 0 {
    ignore(1)
  }
  ignore(k)
}
'@ 'ACCEPT'

# A3. A literal head, which failed before the fix with `unexpected token `<`` -- a
# DIFFERENT message from A1's. The message tally is what ranks this work, so one defect
# counted under two messages would have sent the next increment after a shape that does not
# exist.
Add-Case 'A3_while_expr_literal_head' @'
///|
fn f() -> Unit {
  let k : Unit = while 1 < 2 {
    ignore(1)
  }
  ignore(k)
}
'@ 'ACCEPT'

# --- `for` EXPRESSION, both header forms. --------------------------------------
Add-Case 'B1_for_expr_binder' @'
///|
fn f(xs : Array[Int]) -> Unit {
  let k : Unit = for x in xs {
    ignore(x)
  }
  ignore(k)
}
'@ 'ACCEPT'

# B2. The accumulator form, verbatim from settle 0472's B1, which ACCEPTed there. It is
# repeated here because it is the shape async writes and because the two settles should not
# have to be read together to see that the same source is legal in both.
Add-Case 'B2_for_expr_nobreak' @'
///|
fn f(ps : Array[String]) -> Int {
  let total = for p in ps; acc = 0 {
    continue acc + p.length()
  } nobreak {
    acc
  }
  total
}
'@ 'ACCEPT'

# --- RECORDED. Read the column, do not gate on it. ----------------------------
#
# Whether a loop expression may appear as a bare FUNCTION TAIL rather than on the right of
# a `let` is a question this increment does not need answered, and the analyzer does not
# model it either way. Recorded because the implementation makes an incidental choice here
# and an unrecorded choice is one nobody reviews.
Add-Case 'record_loop_as_tail' @'
///|
fn f(a : Int) -> Unit {
  while a > 0 {
    ignore(1)
  }
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0474_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0474`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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

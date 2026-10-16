# Settle 0470 -- is the C-style `for` init clause a DECLARATION scoped to the loop,
# or an assignment to the enclosing frame?
#
# WHY. The C-style `for` desugars to `SBlock([<init>, SWhile(cond, body + update)])`,
# so the init clause is a statement inside a block. The parser read it with the ordinary
# statement reader, which has no `let` to see and therefore built an `SAssign`. An
# `SAssign` ASSIGNS: `Infer::assign_check` REPORTS a type mismatch but does not rebind,
# so the loop's own name never replaced a same-named binding leaked from an enclosing
# body. That is moonbit_labeler 0.2.13 app_moui/rasterizer.mbt:1218 --
#
#     argument 2 to 'blend_pixel' has incompatible type 'float'; expected 'int'
#
# the last `actionable` finding on any pinned corpus. The fix is to read the clause as
# the `SLet` it is. But that is only correct if the toolchain agrees that it IS a
# declaration, and the toolchain is the authority here, not the fixture that failed.
#
# If the clause were a plain assignment, the fix would be wrong in a way no corpus can
# show: `SLet` introduces a scope, and the settle says the name does NOT outlive the loop.
#
# => 判据: settle the SEMANTICS against the toolchain before changing what the parser
# builds. A fix justified only by the finding it clears is a coincidence until `moon`
# says the clause is a binding.
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
# THE CONTROL. A name that is genuinely undefined must still be refused, so every ACCEPT
# below is about the init clause and not about `moon check` declining the file for some
# unrelated reason.
Add-Case 'ctl_undefined' @'
///|
fn probe(n : Int) -> Unit {
  ignore(zq_missing)
  ignore(n)
}
'@ 'REJECT'

# THE OTHER FOR FORM. `is_c_style_for` splits the two by which of `;` and `{` arrives
# first at depth 0. If this row failed, every result below would be about a broken
# scaffold rather than about the init clause.
Add-Case 'ctl_binder_form' @'
///|
fn probe(n : Int) -> Unit {
  for i in 0..<n {
    ignore(i)
  }
}
'@ 'ACCEPT'

# --- THE CLAIMS. Gated. --------------------------------------------------------
#
# CLAIM 1. `i = 0` with no `let` DECLARES `i`. If it were an assignment to the enclosing
# frame, this row would REJECT with `i` undefined -- exactly as ctl_undefined does.
Add-Case 'claim1_declares' @'
///|
fn probe(n : Int) -> Unit {
  for i = 0; i < n; i = i + 1 {
    ignore(i)
  }
}
'@ 'ACCEPT'

# CLAIM 2. `let` is FORBIDDEN in the init clause, so the clause cannot be reading an
# ordinary `let` binding under a different spelling. This is the row that would fall
# first if `parse_c_for` had been extended to accept `let` here.
Add-Case 'claim2_let_forbidden' @'
///|
fn probe(n : Int) -> Unit {
  for let i = 0; i < n; i = i + 1 {
    ignore(i)
  }
}
'@ 'REJECT'

# CLAIM 3. The name is SCOPED TO THE LOOP: it does not outlive it. This is the half
# that makes `SLet` the right node rather than any rebinding -- a clause that assigned
# would leave `j` visible here.
Add-Case 'claim3_does_not_outlive' @'
///|
fn probe(n : Int) -> Unit {
  for j = n; j > 0; j = j - 1 {
    ignore(j)
  }
  ignore(j)
}
'@ 'REJECT'

# CLAIM 4, and the sharpest evidence in the file: the toolchain says so in its OWN words.
# The update step references `n`, which the init clause did not declare, and `moon check`
# refuses with [4106]
#
#     Unknown binder n in the for-loop steps. Binders in the steps must be declared in the
#     initialization block of the for-loop.
#
# That is the increment stated as a rule: the init clause is a DECLARATION SITE and the
# steps reference what it declared. An assignment reading has no way to produce that
# message, because there would be nothing to "declare in the initialization block".
Add-Case 'claim4_binders_declared_in_init' @'
///|
fn probe(n : Int) -> Unit {
  for ; n > 0; n = n - 1 {
    ignore(n)
  }
}
'@ 'REJECT'

# --- RECORDED. Read the column, do not gate on it. -----------------------------
#
# The same clause with the binder PRESENT in the init block must ACCEPT, or claim 4 is
# only half of what it says. This is the control for claim 4.
Add-Case 'claim4b_control_declared' @'
///|
fn probe(n : Int) -> Unit {
  for n = n; n > 0; n = n - 1 {
    ignore(n)
  }
}
'@ 'ACCEPT'

# The shadowing read:
# The sharpest form of claim 1: the init clause binds a name an enclosing body already
# bound. A declaration SHADOWS (legal, new scope); an assignment would COLLIDE. Which
# of the two the toolchain reports is the direct evidence that the clause is a binding,
# so it is recorded rather than predicted -- predicting it would only encode my guess.
Add-Case 'record_shadows_outer' @'
///|
fn probe(n : Int) -> Unit {
  let x : Int = 99
  for x = 0; x < n; x = x + 1 {
    ignore(x)
  }
  ignore(x)
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0470_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0470`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'RECORD') { $ok = $true }
    elseif ($want -eq 'ACCEPT') { $ok = $false }
    else { $ok = $got -like 'REJECT*' }
  } else {
    $got = 'ACCEPT'
    if ($want -eq 'RECORD') { $ok = $true }
    else { $ok = ($want -eq 'ACCEPT') }
  }
  Write-Output ('{0,-26} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|reserved|shadow' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. Both controls must behave.'
  Write-Output 'A flipped CLAIM means the parser change is no longer justified -- re-settle before shipping.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
Write-Output 'record_shadows_outer is RECORDed on purpose: its result is evidence for or against'
Write-Output 'the shadowing reading, and encoding a guess as an expectation would prove nothing.'
exit 0

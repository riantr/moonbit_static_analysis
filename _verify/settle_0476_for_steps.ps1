# Settle 0476 -- the STEPS that may follow a binder head's initialization clause.
#
# WHY. 0475 taught the binder head to read `; <one declaration>` and the settle said a second
# `;`-clause is not a second initialization clause. That was right, and the settle's C3 row
# REJECTed `for p in ps; len = 0; n = 1 { .. }` with 4106:
#
#     Unknown binder n in the for-loop steps.
#     Binders in the steps must be declared in the initialization block of the for-loop.
#
# `io/reader.mbt:186` reads exactly that shape and `moon check` COMPILES it:
#
#     for prefix in prefix_list; len = 0; len = len + prefix.length() { .. }
#
# So C3 and reader.mbt:186 disagree, and the settle's row is what has to give. The difference
# is visible in the compiler's own sentence and was missed by reading `n = 1` as "a second
# declaration" rather than as "a binder that the init block does not declare": in reader.mbt
# `len` IS declared in the initialization block, so assigning to it is allowed. 4106 was never
# about the NUMBER of clauses. It was about WHERE THE BINDER WAS DECLARED.
#
# => 判据: a settle row that passes because the toolchain refused the fixture is evidence only
# about the fixture. C3 used `n = 1`, which is a binder nothing declares, and generalised from
# one program to "a second `;`-clause is steps" -- which the corpus contradicted the next day.
# THE ROWS THAT DECIDE A GRAMMAR ARE THE ONES THE CORPUS ALREADY WRITES, not the ones that are
# convenient to write by hand.
#
# The rows below are chosen so that each can only compile if a particular scope answer is true.
# `len` is declared in the init block, so a step may assign to it; the question every other row
# asks is what ELSE a step may touch, and whether the step is still there when the loop ends.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
Add-Case 'ctl_binder_plain' @'
///|
fn f(xs : Array[Int]) -> Unit {
  for x in xs {
    ignore(x)
  }
}
'@ 'ACCEPT'

Add-Case 'ctl_decl_only' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0 {
    ignore(p)
    ignore(len)
  }
}
'@ 'ACCEPT'

# --- S1  THE SHAPE reader.mbt:186 ACTUALLY WRITES -----------------------------
#
# The corpus row, and it is a CONTROL in the only sense that matters: 0475's settle said this
# class of header is REJECT and the compiler disagrees. If this row does not ACCEPT, then
# reader.mbt:186 is not valid MoonBit and the honest reading is a corpus-version mismatch
# rather than a parser gap.
Add-Case 'S1_step_assigns_a_declared_binder' @'
///|
fn f(prefix_list : Array[String]) -> Unit {
  for prefix in prefix_list; len = 0; len = len + prefix.length() {
    ignore(len)
  }
}
'@ 'ACCEPT'

# --- S2  AND THE ROW 0475 GOT WRONG, KEPT AS A CONTROL ------------------------
#
# Unchanged from C3, deliberately. A new binder in the steps is still refused, so 0475's C3
# survives as a fact about BINDERS and fails as a claim about CLAUSES. Both halves are needed
# and only one of them was recorded the first time.
Add-Case 'S2_step_declares_a_new_binder_refused' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0; n = 1 {
    ignore(p)
  }
}
'@ 'REJECT'

# --- S3  MAY A STEP TOUCH THE LOOP BINDER? ------------------------------------
#
# The sharp row. A step runs INSIDE the loop, so `p` ought to be in scope -- but the
# initialization clause is not, and the compiler's sentence singles out the initialization
# block specifically. If S3 ACCEPTs, the scope is: init outside the binder, steps inside it,
# which is the shape any per-iteration update has to have.
Add-Case 'S3_step_reads_the_loop_binder' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0; len = p.length() {
    ignore(len)
  }
}
'@ 'ACCEPT'

# --- S4  MAY A STEP BE AN EXPRESSION, NOT AN ASSIGNMENT? ---------------------
#
# 0475 settled that the initialization block is a DECLARATION by token shape -- `TName` then
# `TAssign`. If steps use the same reader, a bare expression here is refused, and steps are a
# different kind of clause. This is the row that separates "steps are assignments" from
# "steps are statements".
Add-Case 'record_step_bare_expression' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0; p.length() {
    ignore(p)
  }
}
'@ 'RECORD'

# --- S5  IS THERE MORE THAN ONE STEP? -----------------------------------------
#
# The C-style header's list is variable length and 0473 settled that; whether the STEP list is
# the same question is open, and a single-step reader that silently stops at the first `;` would
# accept this header and lose the rest. RECORDED rather than predicted, because which way it
# goes changes the reader rather than just documenting it.
Add-Case 'record_two_steps' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0; len = len + p.length(); len = len + 1 {
    ignore(len)
  }
}
'@ 'RECORD'

# --- S6  DOES THE STEP'S EFFECT OUTLIVE THE LOOP? -----------------------------
#
# The reader.mbt:186 case reads `prefix_len` after the loop, and `prefix_len` was computed by a
# DIFFERENT loop at line 176 with a `nobreak`, so the settle does not settle this from the
# corpus. If a step's binding is visible after the loop, `len` behaves like the init clause in
# reverse; if not, it is loop-scoped like everything else. Either answer the reader must honour,
# and predicting it would only encode a guess.
Add-Case 'record_step_binding_after_loop' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0; len = len + p.length() {
    ignore(p)
  }
  ignore(len)
}
'@ 'RECORD'

# --- S7  IS A STEP LEGAL WITHOUT AN INITIALIZATION BLOCK? ---------------------
#
# The toolchain's sentence says binders in the steps must be declared in the initialization
# block. If there is no initialization block, nothing can be, and this must be refused -- which
# is the direct reading of the message rather than an inference from it. If it ACCEPTs, then
# there is an implicit initialization block and the grammar is one list after all, which would
# make 0475's C3 wrong in a second way.
Add-Case 'S7_step_without_an_initialization_clause' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = len + p.length() {
    ignore(p)
  }
}
'@ 'REJECT'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0476_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0476`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-42} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown|Unknown' }) |
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

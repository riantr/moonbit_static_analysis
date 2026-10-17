# Settle 0475 -- a BINDER head followed by C-style clauses: `for p in ps; len = 0 { .. }`.
#
# WHY THIS EXISTS. 0473 stopped the `for` HEADER being read by a delimiter test and split it
# into "is the head a binder?" versus an initializer head. That made the binder head route
# CORRECTLY -- to the binder reader -- and the binder reader stops at the `;`. So the error
# moved from `expected ';'` to `expected 'in'` and async/src/io/reader.mbt:176 is STILL
# unread. Moving an error is not removing it, and `parser_0473_test.mbt` pins the failure so
# a later reader cannot mistake the improvement for the fix.
#
# This increment needs an AST DECISION, and an AST decision needs to know what the construct
# MEANS. Guessing it from the four corpus sites would be exactly the error this project keeps
# paying for, so the question goes to the compiler first.
#
# THE SHARP ROWS ARE SCOPE PROBES, NOT ACCEPT/REJECT ROWS. "It compiles" says the shape is
# legal; it does not say whether the binder still drives the iteration, whether the clauses
# are evaluated once or per iteration, or whether a clause binding escapes the loop. Those
# decide the node. So each claim below is a program that can only compile if the answer is a
# particular one:
#
#     `p` appearing in a CONDITION   -> the clauses are inside the binder's scope
#     `p` appearing in an INIT clause -> ditto, and the init is not hoisted above the binder
#     a clause binding read AFTER     -> the clause DECLARES, and it outlives the loop
#
# The last one is the 0470 question asked again on a different head. 0470 settled that a
# C-style `for x = 0; ..` init clause is a DECLARATION that SHADOWS an enclosing binding and
# does not outlive the loop. Whether the same holds after a binder head is NOT assumed to be
# the same; the corpus writes `nobreak { len }`, so it is at least visible to the nobreak
# block, and "visible to nobreak" and "visible afterwards" are different claims.
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
# Both forms 0473 settled, unchanged. A settle whose controls fail is measuring the fixture,
# and every claim below would then be evidence about nothing.
Add-Case 'ctl_binder_plain' @'
///|
fn f(xs : Array[Int]) -> Unit {
  for x in xs {
    ignore(x)
  }
}
'@ 'ACCEPT'

Add-Case 'ctl_cstyle_three_clause' @'
///|
fn f(n : Int) -> Unit {
  for i = 0; i < n; i = i + 1 {
    ignore(i)
  }
}
'@ 'ACCEPT'

# --- C1  IS THE SHAPE LEGAL AT ALL ---------------------------------------------
#
# The corpus writes it, so if this REJECTs the four sites are not a parser gap but code the
# toolchain refuses, and the honest reading is "not our problem" rather than a new AST node.
Add-Case 'C1_binder_then_one_clause' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0 {
    ignore(p)
  }
}
'@ 'ACCEPT'

# --- C2  IS THE CLAUSE BINDING VISIBLE IN THE BODY? ---------------------------
#
# This is the row the first draft got wrong, and getting it wrong was the useful part. The
# draft asked whether `p` is visible in the CONDITION, and that question does not have an
# answer because there is no condition after a binder head: the compiler rejects
# `for p in ps; p.length() > 0 { }` with "unexpected token `.` ... you may expect `=`", which
# is the clause reader demanding a DECLARATION and not a scope question at all.
#
# So the binder is never asked about, and the question becomes the one that actually decides
# the node: is the clause binding in scope in the BODY? If it is, the clause list is read
# around the binder loop with its bindings inside the loop's scope, and the existing
# declaration node plus a binder loop is the whole design.
Add-Case 'C2_clause_binding_visible_in_body' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0 {
    ignore(p)
    ignore(len)
  }
}
'@ 'ACCEPT'

# --- C3  MAY THE CLAUSE LIST BE LONGER THAN ONE? ------------------------------
#
# EXPECTED REJECT, AND THE REJECTION IS THE FINDING. The first draft predicted ACCEPT on the
# reasoning that the C-style clause list is variable length and that should carry over. It
# does not, and the compiler says why in its own words:
#
#     Unknown binder n in the for-loop steps.
#     Binders in the steps must be declared in the initialization block of the for-loop.
#
# `n = 1` PARSED -- 4106 is a semantic error, not a parse error -- and it was read as a
# binder declared in the for-loop STEPS rather than as a second clause of the initialization
# block. So after a binder head the initialization block takes exactly ONE declaration, and
# a second `;` introduces something else entirely.
#
# This is the row that decided the increment is a READER change and not a new node, and the
# row that says the C-style variable-length list does NOT simply extend across the binder head.
Add-Case 'C3_second_clause_is_steps_not_init' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0; n = 1 {
    ignore(p)
  }
}
'@ 'REJECT'

# --- C3b  IS AN EMPTY SECOND CLAUSE LEGAL? ------------------------------------
#
# RECORDED rather than predicted. If `for p in ps; len = 0; { .. }` ACCEPTs, the steps block
# can be empty and a trailing `;` is a shape the reader must tolerate; if it REJECTs, a
# `;` always introduces real steps. Either way it is a distinct question from C3, which asked
# what a SECOND DECLARATION does -- and this one cannot be inferred from it.
Add-Case 'record_empty_second_clause' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0; {
    ignore(p)
  }
}
'@ 'RECORD'

# --- C4  IS THERE A CONDITION AFTER A BINDER HEAD AT ALL? ----------------------
#
# Expected REJECT, and the REJECTION IS THE FINDING rather than a failure: it says the
# combined loop is a binder loop plus an initializer list, with no condition and therefore no
# per-iteration test. That is what makes the desugar small -- it is the C-style init list in
# front of a binder loop, not a new loop form.
Add-Case 'C4_condition_after_binder_refused' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0; len > 0 {
    ignore(p)
  }
}
'@ 'REJECT'

# --- C5  AND THE BINDER IS NOT VISIBLE TO THE CLAUSES -------------------------
#
# The row the draft accidentally wrote, kept because it is sharp. `n = p.length()` cannot
# compile, so the clauses are NOT evaluated inside the binder's scope -- the binder is
# introduced by the loop the clauses precede. This is what rules out desugaring the whole
# thing into a `while` over an index: there is no index, and the clauses never see `p`.
Add-Case 'C5_binder_not_visible_to_clauses' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; n = p.length() {
    ignore(p)
  }
}
'@ 'REJECT'

# --- C6  TWO BINDERS, THEN CLAUSES --------------------------------------------
#
# unix.mbt:66 and windows.mbt:57 both write a TWO-binder head. The multi-binder desugar
# rewrites the head into a `$pair` binding plus a destructuring statement, and that rewrite
# must not drop the clauses on the floor -- so this row is what makes the multi-binder path
# and the clause path meet. It ACCEPTed on the first run, which is the load-bearing fact:
# the two shapes compose.
Add-Case 'C6_two_binders_then_clause' @'
///|
fn f(m : Map[String, String]) -> Unit {
  for k, v in m; n = 0 {
    ignore(k)
    ignore(v)
  }
}
'@ 'ACCEPT'

# --- C7  DOES A CLAUSE BINDING OUTLIVE THE LOOP? ------------------------------
#
# The 0470 question on a different head, and it settles the SAME way: REJECT(4021), the
# clause binding is not readable after the loop. So the clause list is a DECLARATION scoped
# to the loop, exactly as 0470 measured for the C-style init -- which means `c_for_init`'s
# existing conversion is reusable and this increment is a reader change, not a new node.
Add-Case 'record_clause_binding_after_loop' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0 {
    ignore(p)
  }
  ignore(len)
}
'@ 'RECORD'

# --- C8  AND THE EXACT CORPUS SHAPE --------------------------------------------
#
# reader.mbt:176 as the corpus writes it: a loop EXPRESSION carrying the binder head, the
# clause, and a `nobreak` block that reads the clause binding. ACCEPT, so the increment is a
# parser gap and not "the corpus is not valid MoonBit".
Add-Case 'record_corpus_shape_with_nobreak' @'
///|
fn f(ps : Array[String]) -> Int {
  let total = for p in ps; len = 0 {
    continue len + p.length()
  } nobreak {
    len
  }
  total
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0475_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0475`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-34} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
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

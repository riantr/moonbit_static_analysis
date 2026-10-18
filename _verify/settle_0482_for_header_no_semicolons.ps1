# Settle 0482 -- the C-style `for` HEADER may carry its clauses WITHOUT semicolons.
#
# WHY. moonbit_image is 17/18 and the one file left is `bmp.mbt`, reported as `expected '{'`
# and PARTIAL -- "read up to line 118, 13 after it not shown". Lines 117-119 are:
#
#     for i = 0
#         i < num_colors && i * 4 + palette_offset + 3 < self.data.length()
#         i = i + 1 {
#
# THREE CLAUSES AND NOT ONE SEMICOLON. That is the shape, and the reader has exactly one
# assumption in the way: `parse_c_for` reads the init clause, then gates the condition and
# the update behind a single `if self.at(TSemi)`. No `;`, so the whole chain is skipped, and
# `parse_block` is entered with the cursor on the condition's `i` and reports `expected '{'`.
#
# THE BOUNDARY LINE IS THE RECEIPT. `region_line` 118 is the condition token and not the
# `for` at 117, which is what says the init clause was READ and only the SEPARATOR was
# missing. A boundary of 117 would have meant the head itself failed and this settle would
# be about something else entirely.
#
# 0473 already settled the neighbouring shape -- `C1_single_clause_no_semicolons`,
# `for n = step() { .. }` -- and that one works, because a single clause is followed straight
# by `{` and the gate is never entered. So the gap is NOT "semicolons are optional" in
# general; it is that THE GATE ITSELF is the semicolon. Settle 0476 extended the clause LIST,
# so what is left is the separator between clauses. This settle asks the toolchain which
# separators are legal, because the analyzer has to know whether it is reading newlines,
# nothing at all, or both.
#
# SCAFFOLD NOTES, CARRIED FROM 0479/0481. Every row writes `src/moon.pkg`, because a project
# without a package inside its source directory is not a package: `moon check` prints "no work
# to do", exits 0, and every ACCEPT row would read as a pass. `ctl_must_reject` proves the
# INSTRUMENT can fail, and "no work to do" is matched by name rather than inferred from a
# zero exit code.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------

# THE CONTROL. The three-clause form WITH semicolons: settled by 0470 claim 1 and read by the
# current `parse_c_for` unchanged. A failure here means the SCAFFOLD, not the grammar.
Add-Case 'ctl_c_for_with_semicolons' @'
///|
fn f(n : Int) -> Unit {
  for i = 0; i < n; i = i + 1 {
    ignore(i)
  }
}
'@ 'ACCEPT'

# THE OTHER CONTROL. The single-clause head with no semicolon at all, settled ACCEPT by 0473
# C1. This is the row that makes the increment a NARROWING of the grammar rather than a
# loosening of it: whatever this settle concludes, the shape 0473 already pinned keeps working,
# and a reader that started demanding `;` in the one place that never had one would pass every
# new row here and regress 0473.
Add-Case 'ctl_single_clause_no_semicolon' @'
///|
fn step() -> Int { 1 }

fn f() -> Int {
  let kind = for n = step() {
    break n + 1
  }
  kind
}
'@ 'ACCEPT'

# ctl_must_reject proves the INSTRUMENT can fail. Every other gated row here wants ACCEPT, so
# a compiler that is not running looks exactly like a compiler that approves the corpus.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# --- C1  THE BMP SHAPE, VERBATIM IN FORM ---------------------------------------
# The corpus line, reduced to its smallest instance: an initializer, a condition and an
# update, each on its own line, with no separator anywhere. If this REJECTs then the analyzer
# is right to complain and moonbit_image's file is not the defect this increment assumes.
Add-Case 'C1_three_clauses_newline_separated' @'
///|
fn f(n : Int) -> Unit {
  for i = 0
      i < n
      i = i + 1 {
    ignore(i)
  }
}
'@ 'ACCEPT'

# --- C2  TWO CLAUSES, NO UPDATE -------------------------------------------------
# bmp.mbt's neighbour rather than bmp.mbt itself, and the first thing a fix could get wrong:
# an implementation that requires all THREE clauses before it will read a condition would pass
# C1 and stop dead here. The body is infinite on purpose -- `i` never advances -- because the
# question is the HEADER and a type error in the body would answer a different one.
Add-Case 'C2_init_and_cond_only' @'
///|
fn f(n : Int) -> Unit {
  for i = 0
      i < n {
    ignore(i)
  }
}
'@ 'ACCEPT'

# --- C3  THE BMP CONDITION ITSELF ----------------------------------------------
# `&&` and `<` chained, and `<` applied to a call result. A reader that takes the condition to
# be "the rest of the line" would fail on the continuation, and this is the only row whose
# condition spans more than one comparison.
Add-Case 'C3_chained_condition' @'
///|
struct D { data : Array[Int] }

fn f(d : D, num_colors : Int, off : Int) -> Unit {
  for i = 0
      i < num_colors && i * 4 + off + 3 < d.data.length()
      i = i + 1 {
    ignore(i)
  }
}
'@ 'ACCEPT'

# --- RECORDED. Read the column, do not gate on it. ----------------------------

# Whether the separator-free header needs the NEWLINES, or whether whitespace alone does.
# This is the row that decides what the fix has to be: a parser that ignores newlines
# entirely would answer the same on all four gated rows and differ HERE, so this row is not
# an afterthought -- it is the question that separates two implementations that the corpus
# cannot tell apart.
Add-Case 'record_all_on_one_line' @'
///|
fn f(n : Int) -> Unit {
  for i = 0 i < n i = i + 1 {
    ignore(i)
  }
}
'@ 'RECORD'

# Whether a MIX is legal: semicolon before the condition, nothing before the update. If
# separators are optional but not required, this ACCEPTs; if they are either-all-or-nothing,
# it REJECTs. Recorded because the implementation must decide and an unrecorded decision is
# one nobody reviews.
Add-Case 'record_mixed_separators' @'
///|
fn f(n : Int) -> Unit {
  for i = 0; i < n i = i + 1 {
    ignore(i)
  }
}
'@ 'RECORD'

# And the same mix the other way round. Two rows, because the two are not the same claim:
# "the first separator is optional" and "the second separator is optional" are separate
# properties of a grammar and a reader could have one without the other.
Add-Case 'record_mixed_separators_reversed' @'
///|
fn f(n : Int) -> Unit {
  for i = 0 i < n; i = i + 1 {
    ignore(i)
  }
}
'@ 'RECORD'

# Whether the condition may be skipped while the update is kept: `for i = 0 i = i + 1 { .. }`.
# The three clauses are positional, so this asks whether the CONDITION alone is optional.
Add-Case 'record_init_and_update_no_cond' @'
///|
fn f() -> Unit {
  for i = 0 i = i + 1 {
    ignore(i)
  }
}
'@ 'RECORD'

# Whether the init may be skipped with the other two present: `for i < n i = i + 1 { .. }`,
# with `i` a parameter. 0473 already recorded the all-empty and binder-empty clause lists;
# this is the partial version of the same question and it is the shape a reader is most
# likely to swallow, because `i` on its own reads like a binder.
Add-Case 'record_cond_and_update_no_init' @'
///|
fn f(i : Int, n : Int) -> Unit {
  for i < n i = i + 1 {
    ignore(i)
  }
}
'@ 'RECORD'

# --- C4  THE 0470 FIXTURE, WHICH THIS INCREMENT MAY CONTRADICT ---------------------
# `parser_0470_test.mbt` fixture 1 records that `moon check` REJECTs [3002] this, and
# `mutate_0470.ps1` lines 127-132 build a NO-MUTATION decision on top of that claim: "no legal
# MoonBit program can reach" `c_for_init`'s separator step, because "the lexer emits no
# whitespace token between `for` and its first name".
#
# IT IS NOT THE SAME SPELLING AS C1. C1 keeps the head on the `for` line and separates only
# the clauses that follow; this one puts the initializer on the NEXT line, behind semicolons.
# So the 0470 measurement neither settles nor is settled by C1, and this increment changes the
# code path both go through. Asking it is the difference between correcting a falsified claim
# in place and leaving one standing because it was never re-checked.
Add-Case 'C4_for_alone_on_its_line' @'
///|
fn f(n : Int) -> Unit {
  for
    i = 0;
    i < n;
    i = i + 1
  {
    ignore(i)
  }
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0482_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0482`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # REQUIRED. A MoonBit project with no package inside its source directory is not a
  # package, and `moon check` says "no work to do" and exits 0 -- which every ACCEPT row
  # would read as a pass.
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $noop = $joined -match 'no work to do'
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($noop) {
    $got = 'MOON-DID-NOT-RUN'; $ok = $false
  } elseif ($plan) {
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
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown|Unexpected|unexpected' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All three controls must behave.'
  Write-Output 'A flipped CLAIM means the analyzer change is aimed at something the toolchain refuses.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

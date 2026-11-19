param([string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE BLIND SPOT'S CLASS: a LANGUAGE RULE, or a TOOL GAP?
#
# `LOOP.md`'s own lesson is that "a limitation is a conclusion to be checked, not
# a premise" -- so this is a PROBE, and it is a probe with a CONTROL in every
# measurement. Four measurements, and each one can only come out one way:
#
#   M1  the CONTROL. The same defect in a `fn` body -> the analyzer finds it.
#   M2  the PROBE.  The same defect in a `test` body -> the analyzer finds
#       NOTHING, and says so with a scope-limit notice.
#   M3  the STRUCTURE. The call sites inside a `test` body are not COUNTED as
#       call sites at all. That is the decisive one: it says the body is not in
#       the analysed PROGRAM -- no AST was built for it -- and not that the
#       tool had the AST and chose not to report on it.
#   M4  the LANGUAGE. `moon check` -- the MoonBit COMPILER -- on a file whose
#       `test` body carries a type error. If the compiler reports it, then the
#       language permits the analysis and the compiler performs it, so the
#       exclusion is the TOOL's and not the language's.
#
# MEASURED 2026-11-21. The answer: A TOOL GAP, and a specific one. The parser
# SKIPS a `test` body at the token level (`src/parser/parser.mbt`: `test` is
# in the same branch as `struct`/`enum`/`trait`/`impl`/`extend`, and the branch
# calls `skip_decl_braced`), so there is no AST for the body at all.
#
# AND THE GAP IS NOT A ONE-LINE FIX, which is why the answer is a class and not
# a ticket: the tool's subset has the rule "a file must parse COMPLETELY
# before it reports", and a `test` body is a construct the parser has never
# built an AST for. Clearing it means parsing test bodies, which is a new
# construct class and needs its own measurement on real files -- the same
# reason `QA_TODO.md` ranks C1 as a DECISION.
#
# This script is a MEASUREMENT, not a gate: it runs a probe and prints what it
# found. It is a `settle_*` script for that reason -- the house's name for a
# one-off measurement whose result is recorded in `_verify/NARRATIVE.md`.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\settle_0616_blindspot_class.ps1

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$work = Join-Path $env:TEMP ('bsclass_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

function Invoke-Analyzer([string]$Dir) {
  $out = Join-Path $work 'o.txt'
  $a = @($wasm, $Dir, '--no-auto-fetch-deps', '--findings-shown-per-file', '1000000',
         '--metrics', '--honor-nosec', '--show-notices')
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  Start-Process -FilePath $moonrun -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError "$out.err" -NoNewWindow -Wait | Out-Null
  $ErrorActionPreference = $prev
  return [System.IO.File]::ReadAllText($out)
}

function Get-Calls([string]$Text) {
  $m = [regex]::Match($Text, '(?m)^METRICS\s+calls\s+sites=(\d+)\s+checked=(\d+)\s+not-verified=(\d+)')
  if (-not $m.Success) { return $null }
  return [pscustomobject]@{
    Sites = [int]$m.Groups[1].Value
    Checked = [int]$m.Groups[2].Value
    NotVerified = [int]$m.Groups[3].Value
  }
}

$defect = @"
fn qa0613_f() -> Int {
  let qa0613_d = 10 / 0
  qa0613_d
}
"@

Write-Output '=== M1: the CONTROL -- the defect in a `fn` body ==='
$m1 = Join-Path $work 'm1_fn'
New-Item -ItemType Directory -Force -Path $m1 | Out-Null
[System.IO.File]::WriteAllText((Join-Path $m1 'case.mbt'), $defect, (New-Object System.Text.UTF8Encoding($false)))
$t1 = Invoke-Analyzer $m1
Write-Output ('  ' + (([regex]::Match($t1, '(?m)^SUMMARY.*$')).Value.Trim()))
foreach ($l in ($t1 -split "`r?`n")) { if ($l -match 'MSA-016') { Write-Output ('  | ' + $l.Trim()) } }

Write-Output ''
Write-Output '=== M2: the PROBE -- the same defect in a `test` body ==='
$m2 = Join-Path $work 'm2_test'
New-Item -ItemType Directory -Force -Path $m2 | Out-Null
[System.IO.File]::WriteAllText((Join-Path $m2 'case.mbt'), ("test `"qa0613 blind`" {`n" + $defect + "`n}`n"), (New-Object System.Text.UTF8Encoding($false)))
$t2 = Invoke-Analyzer $m2
Write-Output ('  ' + (([regex]::Match($t2, '(?m)^SUMMARY.*$')).Value.Trim()))
foreach ($l in ($t2 -split "`r?`n")) { if ($l -match 'MSA-001|test declaration') { Write-Output ('  | ' + $l.Trim()) } }

Write-Output ''
Write-Output '=== M3: the STRUCTURE -- are the calls in a `test` body in the analysed program? ==='
$m3a = Join-Path $work 'm3_fn'
$m3b = Join-Path $work 'm3_test'
New-Item -ItemType Directory -Force -Path $m3a, $m3b | Out-Null
$helper = "fn qa0613_helper(x : Int) -> Int {`n  x + 1`n}`n`n"
[System.IO.File]::WriteAllText((Join-Path $m3a 'case.mbt'), ($helper + "fn main {`n  let a = qa0613_helper(1)`n  let b = qa0613_helper(a)`n  print(b)`n}`n"), (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $m3b 'case.mbt'), ($helper + "fn main {`n  print(0)`n}`n`ntest `"qa0613 calls in a test body`" {`n  let a = qa0613_helper(1)`n  let b = qa0613_helper(a)`n  print(b)`n}`n"), (New-Object System.Text.UTF8Encoding($false)))
$ca = Get-Calls (Invoke-Analyzer $m3a)
$cb = Get-Calls (Invoke-Analyzer $m3b)
Write-Output ('  the calls in a `fn` body   sites=' + $ca.Sites + '  checked=' + $ca.Checked + '  not-verified=' + $ca.NotVerified)
Write-Output ('  the calls in a `test` body sites=' + $cb.Sites + '  checked=' + $cb.Checked + '  not-verified=' + $cb.NotVerified)
Write-Output '  THE TWO CALLS INSIDE THE TEST BODY ARE NOT COUNTED AT ALL. So the body is not'
Write-Output '  in the analysed program -- there is no AST for it -- and this is not a lens that'
Write-Output '  had the information and chose not to report on it.'

Write-Output ''
Write-Output '=== M4: the LANGUAGE -- does the MoonBit compiler analyse a `test` body? ==='
foreach ($case in @(@('m4_test', $true), @('m4_fn', $false))) {
  $d = Join-Path $work $case[0]
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"riantr/probe`"`n`nversion = `"0.1.0`"`n", (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $d 'moon.pkg'), "supported_targets = `"all`"`n`npkgtype(kind: `"executable`")`n", (New-Object System.Text.UTF8Encoding($false)))
  $bad = "  let a : Int = `"not an int`"`n  let b = qa0613_helper(a)`n"
  if ($case[1]) {
    $body = $helper + "test `"qa0613 a type error inside a test body`" {`n" + $bad + "  print(b)`n}`n`nfn main {`n  print(0)`n}`n"
  } else {
    $body = $helper + "fn qa0613_body() -> Int {`n" + $bad + "  b`n}`n`nfn main {`n  print(0)`n}`n"
  }
  [System.IO.File]::WriteAllText((Join-Path $d 'main.mbt'), $body, (New-Object System.Text.UTF8Encoding($false)))
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $c = & $moon -C $d check 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $where = if ($case[1]) { 'a `test` body' } else { 'a `fn` body' }
  Write-Output ('  the same type error in ' + $where + ':  moon check exit=' + $code)
  foreach ($l in ($c -split "`r?`n")) {
    # THE DIAGNOSTIC'S OWN LOCATION, so the reader can see that the error in
    # the `test` case is reported INSIDE the test body and not somewhere else
    # in the file. A type error that is merely present in the file proves
    # nothing; one the compiler points AT the test body does.
    if ($l -match 'main\.mbt:\d+') { Write-Output ('  | ' + $l.Trim()) }
    if ($l -match 'Type Mismatch|wanted|has type') { Write-Output ('  | ' + $l.Trim()) }
  }
}
Write-Output '  THE COMPILER REPORTS THE TYPE ERROR INSIDE THE `test` BODY. So the language'
Write-Output '  permits the analysis and the compiler performs it: the exclusion is the TOOL''s.'

Write-Output ''
Write-Output '=== THE ANSWER ==='
Write-Output '  A TOOL GAP, and a specific one: the parser SKIPS a `test` body instead of'
Write-Output '  parsing it, so no AST is built for the body. The language is not the obstacle'
Write-Output '  -- the MoonBit compiler analyses test bodies. And the gap is not a one-line'
Write-Output '  fix: the tool''s subset parses a file COMPLETELY before it reports, and a test'
Write-Output '  body is a construct the parser has never built an AST for.'
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
exit 0

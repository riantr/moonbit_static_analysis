$ErrorActionPreference = 'Continue'
# THE SHARED HARNESS'S OWN SELF-TEST: THE INCONCLUSIVE VERDICT, SHOWN TO GO RED.
#
# WHY THIS EXISTS. 0506's release gate failed on gate 0466, and the failure was
# NOT the mutation's fault: `moon test` printed the COMPILER'S OWN WARNING
#
#     Warning (unused_value): Unused variable 'n'
#
# and exited 1 with no test summary. The harness had no summary line, so it
# recorded COMPILE-ERR and blamed the mutant. MEASURED on the same tree, the
# same mutation is SURVIVED with 1184/1184 green -- and `moon test` on the
# mutated tree, with the package REBUILT, exits 0 and DOES print the summary
# (the warning goes to stderr, the summary to stdout). The machine was busy at
# the time; a starved build wears the same shape as a rejected one.
#
# So the harness now tells THREE things apart:
#
#     a summary line + a non-zero exit          -> KILLED
#     a summary line + a zero exit              -> SURVIVED
#     a COMPILER DIAGNOSTIC (`Error: [NNNN]`)   -> COMPILE-ERR
#     NONE OF THE ABOVE                          -> INCONCLUSIVE
#
# INCONCLUSIVE is not a verdict: it is a failed measurement, it is retried once
# (the failure mode is fast, so the retry is cheap), and it FAILS the gate if
# the retry does not rescue it. It can never manufacture a pass.
#
# AND A VERDICT PATH THAT HAS NEVER BEEN SHOWN TO GO RED IS A COMMENT, which is
# what this file is for. It takes a COPY of `_verify` in TEMP, breaks the
# harness's summary-line regex for the MUTATION runs only -- the BASELINE's
# regex is left alone, because a demonstration that breaks the baseline proves
# nothing about the mutation path -- and runs a one-mutation gate against the
# copy. The copy's harness cannot see any summary, so the row must come out
# INCONCLUSIVE, the gate must FAIL, and the process must exit non-zero.
#
# The real tree is never left patched: the copy's gate still restores its
# target byte-identically, and the harness proves that by SHA256.
$root = Split-Path -Parent $PSScriptRoot
$verify = Join-Path $root '_verify'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'

$tmp = Join-Path $env:TEMP ('harness_selftest_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$copy = Join-Path $tmp '_verify'
Copy-Item -LiteralPath $verify -Destination $copy -Recurse -Force

# --- 1. break the summary-line regex for the MUTATION runs only ----------------
$lib = Join-Path $copy 'mutate_lib.ps1'
$t = [System.IO.File]::ReadAllText($lib, [System.Text.Encoding]::UTF8)
$needle = 'Total tests: (\d+), passed: (\d+), failed: (\d+)'
$n = ([regex]::Matches($t, [regex]::Escape($needle))).Count
Write-Output ('the summary-line regex is in the harness ' + $n + ' time(s)')
if ($n -lt 3) {
  Write-Output 'FAIL: the harness does not carry the summary-line regex three times (baseline, mutation, retry).'
  exit 1
}
$broken = 'XXX-Total-tests-(\d+)-passed-(\d+)-failed-(\d+)'
$idx = $t.IndexOf($needle)
$first = $true
for ($i = 0; $i -lt 3; $i++) {
  $at = $t.IndexOf($needle, $idx)
  if ($at -lt 0) { break }
  $idx = $at + $needle.Length
  if ($first) { $first = $false; continue }
  $t = $t.Remove($at, $needle.Length).Insert($at, $broken)
}
$intact = ([regex]::Matches($t, [regex]::Escape($needle))).Count
Write-Output ('the intact summary-line regex left in the copy: ' + $intact + ' (the baseline one)')
if ($intact -ne 1) {
  Write-Output 'FAIL: the copy does not keep exactly one intact summary-line regex.'
  exit 1
}
[System.IO.File]::WriteAllText($lib, $t, (New-Object System.Text.UTF8Encoding($false)))

# --- 2. a gate with ONE mutation, in the copy ---------------------------------
$gate = Join-Path $copy 'mutate_0998.ps1'
[System.IO.File]::WriteAllText($gate, @'
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')
Invoke-MutationGate -Name 'selftest-inconclusive' -Target 'js' -Root '__ROOT__' -Mutations @(
  @{
    Name = 'M1 the mutation is applied and the suite is green'
    File = 'src\parser\parser.mbt'
    Find = '  n != "_" && !@lexer.is_moonbit_keyword(n)'
    Repl = '  true'
    Expect = 'SURVIVED'
    Prove = 'the demonstration: the harness cannot see the summary line, so this row cannot be scored'
  }
)
Write-MutationGateVerdict -Name 'selftest-inconclusive'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
'@.Replace('__ROOT__', $root), (New-Object System.Text.UTF8Encoding($false)))

# --- 3. run the copy's gate, from the repo root ------------------------------
Set-Location $root
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $gate 2>&1 | Out-String
$code = $LASTEXITCODE
$ErrorActionPreference = $prev

Write-Output ''
Write-Output '=== what the copy did ==='
foreach ($ln in ($out -split "`r?`n")) {
  if ($ln -match '(NO RUN|Retrying once|RETRY|INCONCLUSIVE|GATE FAILED|GATE OK|SURVIVED|COMPILE-ERR|restored)') {
    Write-Output ('  ' + $ln.Trim())
  }
}
Write-Output ''
Write-Output ('the demonstration gate exited ' + $code)

$mustSee = @('NO RUN', 'Retrying once', 'RETRY ALSO GOT NO RUN', 'INCONCLUSIVE', 'GATE FAILED')
$missing = @($mustSee | Where-Object { $out.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 })
if ($missing.Count -gt 0) {
  Write-Output ('FAIL: the demonstration did not show: ' + ($missing -join ', '))
  exit 1
}
if ($code -eq 0) {
  Write-Output 'FAIL: the demonstration gate exited 0 -- a run that could not be scored must FAIL.'
  exit 1
}
Write-Output 'SELFTEST OK: the INCONCLUSIVE verdict fires, is retried once, and FAILS the gate.'
exit 0

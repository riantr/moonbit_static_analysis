# 0.4.25 corpus scan -- the SECOND 0.4.25 scan.
#
# `fin0425_*.txt` already exists and was compared byte-for-byte against the
# 0.4.24 baseline before the test suite was rewritten. This script writes
# `fin0425b_*.txt` instead, for the reason scan_0423.ps1 states: two scans writing
# the same filename is how a baseline silently becomes its own comparison.
#
# The claim under test is the weakest kind this project makes -- "this change
# moves nothing" -- so it is checked the only way a zero can be checked: against
# BOTH the previous release and the previous run of this release, byte for byte.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/scan_0425.ps1
$ErrorActionPreference = 'Continue'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$wasm = "$root\_build\wasm\debug\build\moonbit_static_analysis.wasm"
$repos = "$env:TEMP\riantr_sibling_scans\riantr_moonbit_labeler\.repos"

$targets = [ordered]@{
  'moui'            = "$repos\wzzc-dev\moui\0.1.12"
  'moonbit_labeler' = "$repos\riantr\moonbit_labeler\0.2.13"
  'moonbit_image'   = "$repos\riantr\moonbit_image\0.3.7"
  'async'           = "$repos\moonbitlang\async\0.22.4"
  'proton'          = "$repos\moonbit-community\proton\0.3.4"
  'proton_contract' = "$repos\moonbit-community\proton_contract\0.3.4"
}

Set-Location $root
foreach ($k in $targets.Keys) {
  $p = $targets[$k]
  if (-not (Test-Path $p)) { Write-Output "MISSING $k -> $p"; continue }
  & C:\Users\31379\.moon\bin\moonrun.exe $wasm $p --extern-iface-dir $repos --no-auto-fetch-deps 2>&1 |
    Out-File "$env:TEMP\fin0425b_$k.txt" -Encoding UTF8
  $sum = (Get-Content "$env:TEMP\fin0425b_$k.txt" -Encoding UTF8 | Select-String -Pattern '^SUMMARY') -join ''
  Write-Output ("{0,-16} {1}" -f $k, $sum.Trim())
}

Write-Output ''
Write-Output '=== byte comparison against 0.4.24 and against the first 0.4.25 scan ==='
$allSame = $true
foreach ($k in $targets.Keys) {
  $b = "$env:TEMP\fin0425b_$k.txt"
  if (-not (Test-Path $b)) { Write-Output ("{0,-16} NO NEW SCAN" -f $k); $allSame = $false; continue }
  $sha = (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash
  foreach ($base in @("fin0424_", 'fin0425_')) {
    $o = "$env:TEMP\$base$k.txt"
    if (-not (Test-Path $o)) { Write-Output ("{0,-16} {1} MISSING" -f $k, $base); $allSame = $false; continue }
    $osha = (Get-FileHash -LiteralPath $o -Algorithm SHA256).Hash
    $same = ($sha -eq $osha)
    if (-not $same) { $allSame = $false }
    Write-Output ("{0,-16} vs {1}{2}.txt : identical={3}" -f $k, $base, $k, $same)
  }
}
Write-Output ''
if ($allSame) { Write-Output 'ALL SIX CORPORA BYTE-IDENTICAL to 0.4.24 and to the first 0.4.25 scan.' }
else { Write-Output 'MISMATCH -- do not claim "no corpus delta".'; exit 1 }
exit 0
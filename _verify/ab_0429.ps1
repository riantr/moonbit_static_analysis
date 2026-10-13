# 0.4.29 corpus A/B.
#
# THE COMPARISON IS BETWEEN TWO BUILDS OF THE ANALYZER OVER ONE UNCHANGED TREE.
# The baseline dumps in %TEMP%\fin_0429_base were taken from the 0.4.28 build
# before a single source file was edited; the new dumps come from the 0.4.29 build.
# The corpus tree is asserted unchanged first -- a corpus swapped underneath a
# comparison is how proton's actionable count once appeared to fall 100 -> 68 for
# no reason connected to the fix.
#
# THE EXPECTATION IS EXACT, not directional:
#   - moui is the ONLY corpus that may move. Its actionable count must go 1 -> 0.
#   - every other corpus must be byte-identical, because none of them contains an
#     `as` cast: the population was measured at exactly one site in six corpora.
# A change anywhere else is a regression, not a bonus.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\ab_0429.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$repos = Join-Path $root '.repos'

$baseDir = Join-Path $env:TEMP 'fin_0429_base'
$newDir  = Join-Path $env:TEMP 'fin_0429_new'

$targets = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
}

# ---------------------------------------------------------------------------
# 0. THE TREE MUST BE THE TREE
# ---------------------------------------------------------------------------
Write-Output '=== corpus file counts (both dumps must have been taken on this tree) ==='
$counts = @{}
$bad = 0
foreach ($k in $targets.Keys) {
  $p = Join-Path $repos $targets[$k]
  $n = @(Get-ChildItem -Path $p -Recurse -File -Filter '*.mbt' -EA SilentlyContinue |
         Where-Object { $_.FullName -notmatch '\\\.mooncakes\\' }).Count
  $counts[$k] = $n
  if ($n -eq 0) { Write-Output ("  {0,-16} NO CORPUS -- not a zero" -f $k); $bad++ }
  else { Write-Output ("  {0,-16} {1} .mbt files" -f $k, $n) }
}
if ($bad -gt 0) { Write-Output 'ABORT: a corpus is absent.'; exit 1 }

# ---------------------------------------------------------------------------
# 1. THE NEW BUILD
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output 'Rebuilding the 0.4.29 analyzer...'
$bo = Join-Path $env:TEMP 'ab_build.out'; $be = Join-Path $env:TEMP 'ab_build.err'
Start-Process -FilePath 'C:\Users\31379\.moon\bin\moon.exe' `
  -ArgumentList @('build','--target','wasm') -RedirectStandardOutput $bo `
  -RedirectStandardError $be -NoNewWindow -Wait | Out-Null
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
if (-not (Test-Path $wasm)) { Write-Output 'ABORT: no wasm artifact.'; exit 1 }
Write-Output ("  build exit clean, artifact {0} bytes" -f (Get-Item $wasm).Length)

New-Item -ItemType Directory -Force -Path $newDir | Out-Null
foreach ($k in $targets.Keys) {
  $p = Join-Path $repos $targets[$k]
  $out = Join-Path $newDir "$k.txt"; $err = Join-Path $newDir "$k.err"
  Start-Process -FilePath 'C:\Users\31379\.moon\bin\moonrun.exe' `
    -ArgumentList @($wasm, $p, '--extern-iface-dir', $repos, '--no-auto-fetch-deps') `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  if ((Get-Item $out).Length -eq 0) { Write-Output ("  {0,-16} EMPTY OUTPUT -- aborting" -f $k); $bad++ }
}

# ---------------------------------------------------------------------------
# 2. COMPARE
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== per-corpus comparison (0.4.28 baseline vs 0.4.29) ==='
$expectMove = @('moui')
foreach ($k in $targets.Keys) {
  $bf = Join-Path $baseDir "$k.txt"
  $nf = Join-Path $newDir "$k.txt"
  if (-not (Test-Path $bf)) { Write-Output ("  {0,-16} NO BASELINE DUMP -- aborting" -f $k); $bad++; continue }
  $bt = [System.IO.File]::ReadAllText($bf)
  $nt = [System.IO.File]::ReadAllText($nf)
  $bsum = ([regex]::Match($bt, '(?m)^SUMMARY.*$')).Value
  $nsum = ([regex]::Match($nt, '(?m)^SUMMARY.*$')).Value
  $asCount = ([regex]::Matches($nt, "undefined name 'as'")).Count
  $same = ($bt -eq $nt)
  $tag = if ($same) { 'IDENTICAL' } else { 'CHANGED  ' }
  Write-Output ("  [{0}] {1}" -f $tag, $k)
  if (-not $same) {
    Write-Output ("      before: " + $bsum)
    Write-Output ("      after : " + $nsum)
    $bl = $bt -split "`r?`n"; $nl2 = $nt -split "`r?`n"
    $max = [Math]::Max($bl.Length, $nl2.Length)
    $shown = 0
    for ($i = 0; $i -lt $max -and $shown -lt 12; $i++) {
      $a = if ($i -lt $bl.Length) { $bl[$i] } else { '<none>' }
      $b = if ($i -lt $nl2.Length) { $nl2[$i] } else { '<none>' }
      if ($a -ne $b) { Write-Output ("      - " + $a); Write-Output ("      + " + $b); $shown++ }
    }
  }
  if ($expectMove -contains $k) {
    Write-Output ("      `as` findings now: {0} (want 0)" -f $asCount)
    if ($asCount -ne 0) { $bad++ }
  } else {
    if (-not $same) { Write-Output '      *** UNEXPECTED: this corpus contains no cast and must be byte-identical ***'; $bad++ }
  }
}
Write-Output ''
if ($bad -gt 0) { Write-Output ("ABORT: {0} problem(s)." -f $bad); exit 1 }
Write-Output 'A/B OK: only moui moved, and its `as` false positive is gone.'
exit 0
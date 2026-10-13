# 0.4.27 corpus scan.
#
# RE-POINTED. The corpora used to live under
# `%TEMP%\riantr_sibling_scans\riantr_moonbit_labeler\.repos` and that tree was
# EMPTIED mid-run: every directory survived and every FILE in it was gone.
#
# The reason that mattered is not the lost files, it is what the scripts said
# next. `Get-ChildItem -Recurse -File -Filter '*.mbt'` returned 0, and
# measure_0427_retfn.ps1 reported "FN-TYPE RETURNS=0" for all six corpora --
# indistinguishable from a real result. An absent corpus reads as a clean zero.
# Every script here now prints its file count and refuses to report a zero over
# an empty tree, and `--extern-iface-dir` still points at the shared `.repos` so
# the six are read as SIBLINGS, which is what the baselines were.
#
# `moonx <coordinate>` restores a corpus on demand. The restored trees came back
# with identical file counts: 551 / 362 / 114 / 2 / 35 / 17.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/scan_0427.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$wasm = "$root\_build\wasm\debug\build\moonbit_static_analysis.wasm"
$repos = "$root\.repos"

$targets = [ordered]@{
  'moui'            = "$repos\wzzc-dev\moui\0.1.12"
  'moonbit_labeler' = "$repos\riantr\moonbit_labeler\0.2.13"
  'moonbit_image'   = "$repos\riantr\moonbit_image\0.3.7"
  'async'           = "$repos\moonbitlang\async\0.22.4"
  'proton'          = "$repos\moonbit-community\proton\0.3.4"
  'proton_contract' = "$repos\moonbit-community\proton_contract\0.3.4"
}

Set-Location $root
$empty = @()
foreach ($k in $targets.Keys) {
  $p = $targets[$k]
  if (-not (Test-Path $p)) { Write-Output "MISSING $k -> $p"; $empty += $k; continue }
  $n = @(Get-ChildItem -Path $p -Recurse -File -Filter '*.mbt' -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -notmatch '\\\.mooncakes\\' }).Count
  if ($n -eq 0) {
    Write-Output ("{0,-16} NO CORPUS (0 .mbt files) -- NOT SCANNED, and NOT a zero" -f $k)
    Write-Output ("      restore: moonx riantr/moonbit_static_analysis@<version> {0}" -f ($k -replace '_.*',''))
    $empty += $k
    continue
  }
  $out = & C:\Users\31379\.moon\bin\moonrun.exe $wasm $p --extern-iface-dir $repos --no-auto-fetch-deps 2>&1 | Out-String
  $sum = ([regex]::Match($out, '(?m)^SUMMARY.*$')).Value
  Write-Output ("{0,-16} files={1,-5} {2}" -f $k, $n, $sum)
}
if ($empty.Count -gt 0) {
  Write-Output ''
  Write-Output ("ABORT: " + $empty.Count + " corpus/corpora absent. Do not read the above as a result.")
  exit 1
}
exit 0
# 0.4.26 corpus scan.
#
# Same six corpora and the same measurement as scan_0421/0423/0425, writing to
# `fin0426_*.txt` so every earlier baseline survives.
#
# THE POINT OF THIS RUN. 0.4.26 makes a function's tail expression its return
# value. 305 corpus functions (measured by measure_0426_tail_surface.ps1) have a
# declared return type and a tail-expression body, so their abstract return type
# changes from `None` to something real. That is the fix working -- and it is
# also exactly the kind of change that can turn a silent wrong answer into a
# loud new finding. The delta is reported per corpus and by family so a rise can
# be attributed instead of argued about.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/scan_0426.ps1
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
    Out-File "$env:TEMP\fin0426_$k.txt" -Encoding UTF8
  $sum = (Get-Content "$env:TEMP\fin0426_$k.txt" -Encoding UTF8 | Select-String -Pattern '^SUMMARY') -join ''
  Write-Output ("{0,-16} {1}" -f $k, $sum.Trim())
}

Write-Output ''
Write-Output '=== delta vs 0.4.25, per corpus ==='
foreach ($k in $targets.Keys) {
  $new = "$env:TEMP\fin0426_$k.txt"
  $old = "$env:TEMP\fin0425b_$k.txt"
  if (-not ((Test-Path $new) -and (Test-Path $old))) { Write-Output ("{0,-16} missing a baseline" -f $k); continue }
  $sn = (Get-Content $new -Encoding UTF8 | Select-String -Pattern '^SUMMARY') -join ''
  $so = (Get-Content $old -Encoding UTF8 | Select-String -Pattern '^SUMMARY') -join ''
  $same = ($sn -eq $so)
  Write-Output ("{0,-16} identical={1}" -f $k, $same)
  if (-not $same) {
    Write-Output ('    0.4.25: ' + $so.Trim())
    Write-Output ('    0.4.26: ' + $sn.Trim())
    $dn = Compare-Object (Get-Content $old -Encoding UTF8) (Get-Content $new -Encoding UTF8)
    Write-Output ('    changed lines: ' + @($dn).Count)
    $dn | Group-Object SideIndicator | ForEach-Object { Write-Output ('      ' + $_.Name + ' ' + $_.Count) }
  }
}
exit 0
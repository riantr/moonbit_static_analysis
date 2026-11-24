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
  & moonrun $wasm $p --extern-iface-dir $repos --no-auto-fetch-deps 2>&1 |
    Out-File "$env:TEMP\fin0421_$k.txt" -Encoding UTF8
  $sum = (Get-Content "$env:TEMP\fin0421_$k.txt" -Encoding UTF8 | Select-String -Pattern '^SUMMARY') -join ''
  Write-Output ("{0,-16} {1}" -f $k, $sum.Trim())
}
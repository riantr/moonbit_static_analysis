$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wasm = Join-Path $root '_build\wasm\debug\build\src\jsoncli\jsoncli.wasm'
$tmp  = Join-Path $env:TEMP 'retretann_probe'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# NO `raise` anywhere in this set. If these fail, the defect is the return
# annotation's tuple-vs-function-type discrimination and predates 0.4.23.
$cases = [ordered]@{
  'retfn_plain.mbt'    = "fn f() -> (() -> Int) {`n  return 1`n}`nlet x = f()`n"
  'retfn_paren.mbt'    = "fn f() -> ((Int) -> String) {`n  return ""a""`n}`nlet x = f()`n"
  'retfn_nested.mbt'   = "fn f() -> ((String) -> Msg) {`n  return ""a""`n}`nlet x = f()`n"
  'ret_tuple_plain.mbt'= "fn f() -> (Int, String) {`n  return (1, ""a"")`n}`nlet x = f()`n"
  'retfn_raise.mbt'    = "suberror E {`n  E(Int)`n}`nfn f() -> (() -> Int raise E) {`n  return 1`n}`nlet x = f()`n"
}

$enc = New-Object System.Text.UTF8Encoding($false)
foreach ($k in $cases.Keys) {
  $req = @{ kind = 'program'; filename = $k; source = $cases[$k] } | ConvertTo-Json -Compress
  $reqPath = Join-Path $tmp 'req.json'
  [System.IO.File]::WriteAllText($reqPath, $req, $enc)
  $out = & C:\Users\31379\.moon\bin\moonrun.exe $wasm --file $reqPath 2>&1 | Out-String
  Write-Output ('===== ' + $k + ' =====')
  try { $j = $out | ConvertFrom-Json } catch { Write-Output ('  RAW: ' + $out.Trim()); continue }
  foreach ($f in @($j.findings)) { Write-Output ('    [' + $f.family + '] ' + $f.message) }
  if (@($j.findings).Count -eq 0) { Write-Output '    findings: 0' }
}

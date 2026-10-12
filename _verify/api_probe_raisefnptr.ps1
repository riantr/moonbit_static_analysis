$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wasm = Join-Path $root '_build\wasm\debug\build\src\jsoncli\jsoncli.wasm'
$tmp  = Join-Path $env:TEMP 'raise0423_probe'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$DECL = "suberror E {`n  E(Int)`n}`n"
$cases = [ordered]@{
  'control_named.mbt'   = $DECL + "fn f() -> Int raise E {`n  return 1`n}`nlet x = f()`n"
  'indexed_effect.mbt'  = $DECL + "fn f() -> Int raise E[Int] {`n  return 1`n}`nlet x = f()`n"
  'fnptr_bare.mbt'      = $DECL + "fn f(g : () -> Int raise) -> Int {`n  return g()`n}`nlet x = f(fn() { 1 })`n"
  'fnptr_named.mbt'     = $DECL + "fn f(g : () -> Int raise E) -> Int {`n  return g()`n}`nlet x = f(fn() { 1 })`n"
  'fnptr_bang.mbt'      = $DECL + "fn f(g : () -> Int!) -> Int {`n  return g()`n}`nlet x = f(fn() { 1 })`n"
  'ret_fnptr.mbt'       = $DECL + "fn f() -> (() -> Int raise E) {`n  return fn() { 1 }`n}`nlet x = f()`n"
}

$enc = New-Object System.Text.UTF8Encoding($false)
foreach ($k in $cases.Keys) {
  $req = @{ kind = 'program'; filename = $k; source = $cases[$k] } | ConvertTo-Json -Compress
  $reqPath = Join-Path $tmp 'req.json'
  [System.IO.File]::WriteAllText($reqPath, $req, $enc)
  $out = & C:\Users\31379\.moon\bin\moonrun.exe $wasm --file $reqPath 2>&1 | Out-String
  Write-Output ('===== ' + $k + ' =====')
  try { $j = $out | ConvertFrom-Json } catch { Write-Output ('  RAW: ' + $out.Trim()); continue }
  Write-Output ('  findings: ' + @($j.findings).Count)
  foreach ($f in @($j.findings)) { Write-Output ('    [' + $f.family + '] ' + $f.message) }
}

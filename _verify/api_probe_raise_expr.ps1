$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wasm = Join-Path $root '_build\wasm\debug\build\src\jsoncli\jsoncli.wasm'
$tmp  = Join-Path $env:TEMP 'raise_expr_probe'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$D = "suberror E {`n  E(Int)`n}`n"
$cases = [ordered]@{
  'control_plain.mbt'     = "fn f() -> Int {`n  return 1`n}`nlet x = f()`n"
  'raise_bare.mbt'        = $D + "fn f() -> Int raise E {`n  raise E`n  return 1`n}`nlet x = f()`n"
  'raise_payload.mbt'     = $D + "fn f(n : Int) -> Int raise E {`n  raise E(n)`n  return 1`n}`nlet x = f(1)`n"
  'raise_guard_else.mbt'  = $D + "fn f(g : Int?) -> Int raise E {`n  guard g is Some(v) else {`n    raise E(0)`n  }`n  return v`n}`nlet x = f(1)`n"
  'raise_bang.mbt'        = $D + "fn f(n : Int) -> Int! {`n  raise E(n)`n  return 1`n}`nlet x = f(1)`n"
  'raise_tail.mbt'        = $D + "fn f(n : Int) -> Int raise E {`n  if n > 0 { raise E(n) }`n  return 1`n}`nlet x = f(1)`n"
  # THE SHARP ONE: a real defect INSIDE a raise must still be reported.
  'raise_inner_defect.mbt'= $D + "fn f() -> Int raise E {`n  raise E(nosuchfunction())`n  return 1`n}`nlet x = f()`n"
}

$enc = New-Object System.Text.UTF8Encoding($false)
foreach ($k in $cases.Keys) {
  $req = @{ kind = 'program'; filename = $k; source = $cases[$k] } | ConvertTo-Json -Compress
  $reqPath = Join-Path $tmp 'req.json'
  [System.IO.File]::WriteAllText($reqPath, $req, $enc)
  $out = & C:\Users\31379\.moon\bin\moonrun.exe $wasm --file $reqPath 2>&1 | Out-String
  Write-Output ('===== ' + $k + ' =====')
  try { $j = $out | ConvertFrom-Json } catch { Write-Output ('  RAW: ' + $out.Trim()); continue }
  $fs = @($j.findings)
  if ($fs.Count -eq 0) { Write-Output '  findings: 0' }
  foreach ($f in $fs) { Write-Output ('    [' + $f.family + '] ' + $f.message) }
}
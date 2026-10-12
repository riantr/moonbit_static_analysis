$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wasm = Join-Path $root '_build\wasm\debug\build\src\jsoncli\jsoncli.wasm'
$tmp  = Join-Path $env:TEMP 'flowjoin_probe'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)

# expect 0 = the FALSE positive that the join fixes
# expect 1 = REAL dead code that the join must NOT silence
$cases = [ordered]@{
  'fp_guard_else_return.mbt' = "fn f(g : Int?) -> Int {`n  guard g is Some(v) else {`n    return 0`n  }`n  return v`n}`nlet x = f(1)`n"
  'fp_guard_else_raise.mbt'  = "suberror E {`n  E(Int)`n}`nfn f(g : Int?) -> Int raise E {`n  guard g is Some(v) else {`n    raise E(0)`n  }`n  return v`n}`nlet x = f(1)`n"
  'fp_elseif_mixed.mbt'      = "fn f(n : Int) -> Int {`n  if n > 0 {`n    return 1`n  } else if n < 0 {`n    return 2`n  } else {`n    return 3`n  }`n  return 4`n}`nlet x = f(1)`n"
  'real_both_terminate.mbt' = "fn f(n : Int) -> Int {`n  if n > 0 {`n    return 1`n  } else {`n    return 2`n  }`n  return 3`n}`nlet x = f(1)`n"
  'real_after_return.mbt'    = "fn f() -> Int {`n  return 1`n  return 2`n}`nlet x = f()`n"
  'real_raise_then.mbt'      = "suberror E {`n  E(Int)`n}`nfn f() -> Int raise E {`n  raise E`n  return 1`n}`nlet x = f()`n"
  'ctrl_no_else.mbt'         = "fn f(n : Int) -> Int {`n  if n > 0 {`n    return 1`n  }`n  return 2`n}`nlet x = f(1)`n"
}

foreach ($k in $cases.Keys) {
  $req = @{ kind='program'; filename=$k; source=$cases[$k] } | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText((Join-Path $tmp 'req.json'), $req, $enc)
  $out = & C:\Users\31379\.moon\bin\moonrun.exe $wasm --file (Join-Path $tmp 'req.json') 2>&1 | Out-String
  Write-Output ('===== ' + $k + ' =====')
  try { $j = $out | ConvertFrom-Json } catch { Write-Output ('  RAW: ' + $out.Trim()); continue }
  $fs = @($j.findings)
  $un = @($fs | Where-Object { $_.family -eq 'Unreachable' }).Count
  Write-Output ('  Unreachable = ' + $un)
  foreach ($f in $fs) { Write-Output ('    L' + $f.line + ' [' + $f.family + '] ' + $f.message) }
}
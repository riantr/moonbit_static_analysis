$ErrorActionPreference = 'Stop'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$wasm = Join-Path $root '_build\wasm\debug\build\src\jsoncli\jsoncli.wasm'
$tmp  = Join-Path $env:TEMP 'payloadtype'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)

$D = "suberror E {`n  E(Int)`n}`n"
$G = "fn g(x : Bool) -> Int {`n  return 1`n}`n"
$cases = [ordered]@{
  'a_known_call_arg.mbt' = $D + $G + "fn f() -> Int raise E {`n  raise E(g(1))`n  return 1`n}`nlet x = f()`n"
  'b_bare_op.mbt'       = $D + "fn f() -> Int raise E {`n  raise 1 + `"a`"`n  return 1`n}`nlet x = f()`n"
  'c_bare_not.mbt'       = $D + "fn f(n : Int) -> Int raise E {`n  raise !n`n  return 1`n}`nlet x = f(1)`n"
  'd_bare_raise_only.mbt'= $D + "fn f() -> Int raise E {`n  raise`n  return 1`n}`nlet x = f()`n"
  'e_bare_in_block.mbt'  = $D + "fn f() -> Int raise E {`n  if true {`n    raise`n  }`n  return 1`n}`nlet x = f()`n"
}
foreach ($k in $cases.Keys) {
  $req = @{ kind='program'; filename=$k; source=$cases[$k] } | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText((Join-Path $tmp 'req.json'), $req, $enc)
  $out = & C:\Users\31379\.moon\bin\moonrun.exe $wasm --file (Join-Path $tmp 'req.json') 2>&1 | Out-String
  Write-Output ('===== ' + $k + ' =====')
  try { $j = $out | ConvertFrom-Json } catch { Write-Output ('  RAW: ' + $out.Trim()); continue }
  foreach ($f in @($j.findings)) { Write-Output ('    L' + $f.line + ' [' + $f.family + '] ' + $f.message) }
}

# and the settle side for the bare forms
$dir = Join-Path $env:TEMP 'settle0424c'
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0424c`"`nversion = `"0.1.0`"`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", $enc)
Write-Output ''
Write-Output '===== settle ====='
$settles = [ordered]@{
  's_op.mbt'   = $D + "fn f() -> Int raise E {`n  raise 1 + `"a`"`n  return 1`n}`n"
  's_not.mbt'  = $D + "fn f(n : Int) -> Int raise E {`n  raise !n`n  return 1`n}`n"
}
Push-Location $dir
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
foreach ($k in $settles.Keys) {
  Get-ChildItem -Path (Join-Path $dir 'src') -File | Remove-Item -Force
  [System.IO.File]::WriteAllText((Join-Path $dir ("src\" + $k)), $settles[$k], $enc)
  $o = & C:\Users\31379\.moon\bin\moon.exe check 2>&1 | Out-String
  $e = [regex]::Matches($o, 'Error: \[(\d+)\]')
  Write-Output ('  ' + $k + ' -> ' + $(if ($e.Count -eq 0) { 'OK (no errors)' } else { ($e.Count.ToString() + ' errors, codes ' + (@($e | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) -join ',')) }))
}
$ErrorActionPreference = $prev
Pop-Location
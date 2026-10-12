$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP 'settle0424b'
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0424b`"`nversion = `"0.1.0`"`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", (New-Object System.Text.UTF8Encoding($false)))

$D = "suberror E {`n  E(Int)`n}`n"
$cases = [ordered]@{
  'bare_raise_only.mbt' = $D + "fn f() -> Int raise E {`n  raise`n}`nlet x = f()`n"
  'bare_raise_then.mbt' = $D + "fn f(n : Int) -> Int raise E {`n  raise`n  return n`n}`nlet x = f(1)`n"
  'bare_raise_close.mbt'= $D + "fn f() -> Int raise E {`n  if true {`n    raise`n  }`n  return 1`n}`nlet x = f()`n"
}
$enc = New-Object System.Text.UTF8Encoding($false)
Push-Location $dir
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
foreach ($k in $cases.Keys) {
  Get-ChildItem -Path (Join-Path $dir 'src') -File | Remove-Item -Force
  [System.IO.File]::WriteAllText((Join-Path $dir ("src\" + $k)), $cases[$k], $enc)
  Write-Output ('===== ' + $k + ' =====')
  $out = & C:\Users\31379\.moon\bin\moon.exe check 2>&1 | Out-String
  $errs = [regex]::Matches($out, 'Error: \[(\d+)\]')
  if ($errs.Count -eq 0) { Write-Output '  OK (no errors)' }
  else {
    $codes = @($errs | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    Write-Output ('  ' + $errs.Count + ' errors, codes: ' + ($codes -join ','))
    foreach ($line in ($out -split "`n" | Where-Object { $_ -match 'Error' } | Select-Object -First 3)) { Write-Output ('    ' + $line.Trim()) }
  }
}
$ErrorActionPreference = $prev
Pop-Location

# Now the type-lens question: does a type error inside a raise payload report?
Write-Output ''
Write-Output '===== analyzer: type error inside a raise payload ====='
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$wasm = Join-Path $root '_build\wasm\debug\build\src\jsoncli\jsoncli.wasm'
$tmp  = Join-Path $env:TEMP 'raisepayload'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$src = $D + "fn f(n : Int) -> Int raise E {`n  raise E(!n)`n  return 1`n}`nlet x = f(1)`n"
$req = @{ kind='program'; filename='payload_type.mbt'; source=$src } | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText((Join-Path $tmp 'req.json'), $req, $enc)
& C:\Users\31379\.moon\bin\moonrun.exe $wasm --file (Join-Path $tmp 'req.json') 2>&1 | Select-Object -First 2
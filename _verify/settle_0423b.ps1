$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP 'settle0423b'
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0423b`"`nversion = `"0.1.0`"`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", (New-Object System.Text.UTF8Encoding($false)))

$DECL = "suberror E {`n  E(Int)`n}`n"
$cases = [ordered]@{
  'opt_fnptr_raise.mbt' = $DECL + "fn f(g : (() -> Int raise)?) -> Int {`n  return 1`n}`n"
  'raise_then_comma.mbt'= $DECL + "fn f(g : () -> Int raise, h : Int) -> Int {`n  return h`n}`n"
  'opt_named.mbt'       = $DECL + "fn f(g : (() -> Int raise E)?) -> Int {`n  return 1`n}`n"
  'indexed_in_fntype.mbt'= $DECL + "fn f(g : () -> Int raise E[Int]) -> Int {`n  return 1`n}`n"
  'control_fnptr.mbt'   = "fn f(g : () -> Int) -> Int {`n  return 1`n}`n"
  'control_opt.mbt'     = "fn f(g : (() -> Int)?) -> Int {`n  return 1`n}`n"
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

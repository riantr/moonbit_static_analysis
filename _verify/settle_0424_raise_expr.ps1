$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP 'settle0424'
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0424`"`nversion = `"0.1.0`"`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", (New-Object System.Text.UTF8Encoding($false)))

$D = "suberror E {`n  E(Int)`n}`n"
$cases = [ordered]@{
  'raise_stmt_bare.mbt'   = $D + "fn f() -> Int raise E {`n  raise E`n  return 1`n}`n"
  'raise_stmt_payload.mbt'= $D + "fn f(n : Int) -> Int raise E {`n  raise E(n)`n  return 1`n}`n"
  'raise_in_guard_else.mbt' = $D + "fn f(g : Int?) -> Int raise E {`n  guard g is Some(v) else {`n    raise E(0)`n  }`n  return v`n}`n"
  'raise_tail_expr.mbt'   = $D + "fn f(n : Int) -> Int raise E {`n  if n > 0 { raise E(n) }`n  1`n}`n"
  'raise_no_effect.mbt'   = $D + "fn f() -> Int {`n  return 1`n}`n"
  'raise_bang_stmt.mbt'   = $D + "fn f(n : Int) -> Int! {`n  raise E(n)`n  return 1`n}`n"
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
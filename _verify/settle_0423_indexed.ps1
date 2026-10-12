$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP 'settle0423'
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0423`"`nversion = `"0.1.0`"`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", (New-Object System.Text.UTF8Encoding($false)))

$cases = [ordered]@{
  'indexed_effect.mbt' = "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E[Int] {\n  return 1\n}\nlet x = f()\n"
  'indexed_generic.mbt' = "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E[Int] {\n  return 1\n}\n"
  'ext_alias.mbt'       = "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  return 1\n}\n"
  'bang_with_args.mbt'  = "suberror E {\n  E(Int)\n}\nfn f() -> Int! {\n  return 1\n}\n"
  'fnptr_effect.mbt'    = "fn f(g : () -> Int raise) -> Int {\n  return g()\n}\n"
}
foreach ($k in $cases.Keys) {
  [System.IO.File]::WriteAllText((Join-Path $dir ("src\" + $k)), $cases[$k], (New-Object System.Text.UTF8Encoding($false)))
}

Push-Location $dir
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
foreach ($k in $cases.Keys) {
  # `moon check` runs the WHOLE package, so every file must be wiped between
  # cases or the output is the union of all of them and tells us nothing about
  # any single one.
  Get-ChildItem -Path (Join-Path $dir 'src') -File | Remove-Item -Force
  [System.IO.File]::WriteAllText((Join-Path $dir ("src\" + $k)), $cases[$k], (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ('===== ' + $k + ' =====')
  $out = & C:\Users\31379\.moon\bin\moon.exe check 2>&1 | Out-String
  $errs = [regex]::Matches($out, 'Error: \[(\d+)\]')
  if ($errs.Count -eq 0) { Write-Output '  OK (no errors)' }
  else {
    $codes = @($errs | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    Write-Output ('  ' + $errs.Count + ' errors, codes: ' + ($codes -join ','))
    foreach ($line in ($out -split "`n" | Where-Object { $_ -match 'Error|error:' } | Select-Object -First 4)) { Write-Output ('    ' + $line.Trim()) }
  }
}
$ErrorActionPreference = $prev
Pop-Location

# The ParseError / subset-exclusion backlog, measured rather than remembered.
#
# WHY THIS EXISTS. The coverage caveat in README.md lists the largest exclusions as
# "match (155), struct (36), derive (31), enum (14)". That list was assembled by
# hand over several releases and it is INCOMPLETE: measured now, an `if`
# expression in expression position accounts for 45 more, and `anonymous function
# literal` for 10, `const` for 6, `short lambda` for 2, `try` for 1. A list that
# omits 45 items while looking precise is worse than no list, because it reads as
# a ranking.
#
# It also does not say what the numbers are a count OF. Each of these notices marks
# a declaration or expression the frontend read past and did not analyse, so what
# sits inside those spans is invisible to every lens -- reads are lost, and so are
# bindings. The count is therefore a floor on the coverage gap, not the gap itself.
#
# THE DISPLAY CAP. `sa` prints a bounded number of findings per file ("... N more
# before the boundary"). The counts below are what was PRINTED, so they are a lower
# bound on the notices, and the script prints the cap alongside them rather than
# letting the sum silently disagree with SUMMARY. At 0.4.29: 729 printed of 823,
# with 94 behind the cap.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\backlog.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
if (-not (Test-Path $wasm)) { Write-Output 'ABORT: build first -- moon build --target wasm'; exit 1 }

$dir = Join-Path $env:TEMP ('backlog_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir 'o.txt'; $err = Join-Path $dir 'o.err'
Start-Process -FilePath $moonrun `
  -ArgumentList @($wasm, $root, '--extern-iface-dir', (Join-Path $root '.repos')) `
  -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
$t = [System.IO.File]::ReadAllText($out)

$sum = ([regex]::Match($t, '(?m)^SUMMARY.*$').Value) -replace "`t", ' '
$notices = [int]([regex]::Match($sum, 'notices=(\d+)').Groups[1].Value)

$lines = @($t -split "`r?`n" | Where-Object { $_ -match '^\d+:\d+ - (error|warning|hint): ' })
$groups = @{}
foreach ($l in $lines) {
  $m = [regex]::Match($l, '^\d+:\d+ - (error|warning|hint): (.*) \([A-Za-z]+\) \[')
  if (-not $m.Success) { continue }
  $msg = $m.Groups[2].Value
  if ($groups.ContainsKey($msg)) { $groups[$msg]++ } else { $groups[$msg] = 1 }
}
$capped = @([regex]::Matches($t, '(?m)^\.\.\.\s+(\d+) more') | ForEach-Object { [int]$_.Groups[1].Value })
$cappedTotal = ($capped | Measure-Object -Sum).Sum

Write-Output '=== self-scan subset-exclusion backlog ==='
Write-Output ('  ' + ($sum -replace '\s+', ' '))
Write-Output ''
Write-Output '  printed notices by message (descending)'
$i = 0
foreach ($e in ($groups.GetEnumerator() | Sort-Object -Property Value -Descending)) {
  $i++
  Write-Output ("  {0,2}. {1,5}  {2}" -f $i, $e.Value, $e.Key)
}
Write-Output ''
Write-Output ("  printed {0} of {1} notices; {2} sit behind the per-file display cap." -f $lines.Count, $notices, $cappedTotal)
Write-Output ''
Write-Output '  Every row above is a span the frontend read past and did not analyse, so'
Write-Output '  what lives inside it is invisible to all three lenses. Removing one row'
Write-Output '  needs an AST node for that form, which is why these are features and not'
Write-Output '  notices to be reworded.'
Write-Output ''
Write-Output '  The `test` row is different in kind: `test` shares `skip_decl_braced` with'
Write-Output '  `impl` and `trait`, so every test body is excluded. That is the largest'
Write-Output '  single group and it is the project excluding its own suite.'

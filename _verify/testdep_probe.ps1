$ErrorActionPreference = 'Stop'
# Does ANALYSING test bodies (the biggest backlog row, 429) depend on `match` being
# analysed first? That ordering is not obvious and it decides which item to build,
# so it is measured rather than guessed.
#
# The suspected failure mode: a match arm body is skipped whole (parser.mbt:3315).
# A local read ONLY inside an arm therefore loses its read, and once test bodies
# are analysed that local is reported UNUSED -- a false positive about code that
# `moon check` accepts. 429 test bodies are exactly the population most likely to
# contain that shape.
#
# Three cases, differing only in WHERE the read sits:
#   plain_read     local read in ordinary code
#   match_arm_read local read ONLY inside a match arm
#   in_test_body   the same, inside a test declaration
#
# A parser that skips test bodies wholesale reports nothing in any of them today,
# so case 3 alone cannot answer the question. What answers it is the DIFFERENCE
# between case 1 and case 2: that is the false positive that would be introduced.
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
if (-not (Test-Path $wasm)) { Write-Output 'ABORT: build the analyzer first.'; exit 1 }

$cases = [ordered]@{
  'plain_read' = @'
fn go() {
  let seed = 1
  let total = seed + 1
  let _ = total
}
let r = 1
let _ = r
'@
  'match_arm_read' = @'
fn go(z : Int) {
  let seed = 1
  let total = match z {
    0 => seed
    _ => 0
  }
  let _ = total
}
let r = 1
let _ = r
'@
  'in_test_body' = @'
test "seed is read" {
  let seed = 1
  let total = seed + 1
  assert_eq(total, 2)
}
let r = 1
let _ = r
'@
}

Write-Output '=== is a local read only inside a match arm lost today? ==='
Write-Output ''
$baseline = @{}
foreach ($name in $cases.Keys) {
  $dir = Join-Path $env:TEMP ('testdep_' + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path $dir 'c.mbt'), $cases[$name], $enc)
  $out = Join-Path $dir 'o.txt'; $err = Join-Path $dir 'o.err'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $dir, '--extern-iface-dir', (Join-Path $root '.repos')) `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  $txt = [System.IO.File]::ReadAllText($out)
  $lines = @($txt -split "`r?`n" | Where-Object { $_ -match '^\d+:\d+ - (error|warning|hint): ' })
  $baseline[$name] = $lines
  Write-Output ("--- {0} ---" -f $name)
  if ($lines.Count -eq 0) { Write-Output '  (no findings)' }
  foreach ($l in $lines) { Write-Output ('  ' + $l.Trim()) }
}

Write-Output ''
Write-Output '=== the difference that decides the ordering ==='
$plain     = $baseline['plain_read']
$arm       = $baseline['match_arm_read']
$inTest    = $baseline['in_test_body']
$plainFam  = @($plain | ForEach-Object { [regex]::Match($_, '\(([A-Za-z]+)\)').Groups[1].Value } | Sort-Object -Unique)
$armFam    = @($arm   | ForEach-Object { [regex]::Match($_, '\(([A-Za-z]+)\)').Groups[1].Value } | Sort-Object -Unique)
$testFam   = @($inTest| ForEach-Object { [regex]::Match($_, '\(([A-Za-z]+)\)').Groups[1].Value } | Sort-Object -Unique)
Write-Output ("  plain_read families    : " + ($plainFam -join ', '))
Write-Output ("  match_arm_read families: " + ($armFam   -join ', '))
Write-Output ("  in_test_body families   : " + ($testFam  -join ', '))
$armExtra = @($armFam | Where-Object { $plainFam -notcontains $_ })
Write-Output ("  families present ONLY when the read sits in a match arm: " + $(if ($armExtra.Count) { $armExtra -join ', ' } else { '(none)' }))
Write-Output ''
if ($inTest.Count -eq 0) {
  Write-Output '  test bodies are skipped wholesale today, so this case is silent'
  Write-Output '  BY CONSTRUCTION -- it is not evidence that analysing them is safe.'
} else {
  Write-Output '  test bodies already produce findings; see above.'
}

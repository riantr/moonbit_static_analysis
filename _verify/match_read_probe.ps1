$ErrorActionPreference = 'Stop'
# Does skipping a `match` arm body LOSE the reads inside it?
#
# The first attempt at this asked "does a local read only inside an arm get reported
# unused?" and the answer was NO -- which falsified the hypothesis that match is a
# prerequisite for analysing test bodies. A negative answer is only informative
# next to a positive control, so all three cases are run together:
#
#   unused_local     a local that is genuinely never read   -> MUST report
#   read_in_arm      the same local, read only inside a match arm
#   read_normally    the same local, read in ordinary code
#
# If `unused_local` reports and `read_in_arm` does not, the arm's read is being
# seen by SOMETHING -- either the walk reaches it, or a skip notice suppresses the
# finding. Those are very different situations and they decide whether the two
# backlog items are independent.
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
if (-not (Test-Path $wasm)) { Write-Output 'ABORT: build the analyzer first.'; exit 1 }

$cases = [ordered]@{
  'unused_local' = @'
fn go() {
  let seed = 1
  let _ = 0
}
let r = 1
let _ = r
'@
  'read_in_arm' = @'
fn go(z : Int) {
  let seed = 1
  let _ = match z {
    0 => seed
    _ => 0
  }
}
let r = 1
let _ = r
'@
  'read_normally' = @'
fn go(z : Int) {
  let seed = 1
  let _ = if z { seed } else { 0 }
}
let r = 1
let _ = r
'@
}

$res = @{}
foreach ($name in $cases.Keys) {
  $dir = Join-Path $env:TEMP ('mread_' + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path $dir 'c.mbt'), $cases[$name], $enc)
  $out = Join-Path $dir 'o.txt'; $err = Join-Path $dir 'o.err'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $dir, '--extern-iface-dir', (Join-Path $root '.repos')) `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  $txt = [System.IO.File]::ReadAllText($out)
  $lines = @($txt -split "`r?`n" | Where-Object { $_ -match '^\d+:\d+ - (error|warning|hint): ' })
  $res[$name] = $lines
  Write-Output ("--- {0} ---" -f $name)
  if ($lines.Count -eq 0) { Write-Output '  (no findings)' }
  foreach ($l in $lines) { Write-Output ('  ' + $l.Trim()) }
}

Write-Output ''
Write-Output '=== verdict ==='
$unusedReports = ($res['unused_local'] | Where-Object { $_ -match "UnusedLocal|may not be used|unused" }).Count
$armReports    = ($res['read_in_arm'] | Where-Object { $_ -match "UnusedLocal|may not be used|unused" }).Count
Write-Output ("  a genuinely unused local IS reported : " + $(if ($unusedReports -gt 0) { 'yes (' + $unusedReports + ')' } else { 'NO -- positive control failed' }))
Write-Output ("  the same local read in a match arm   : " + $(if ($armReports -gt 0) { 'reported (' + $armReports + ')' } else { 'not reported' }))
Write-Output ''
if ($unusedReports -eq 0) {
  Write-Output '  POSITIVE CONTROL FAILED: the probe cannot see unused locals at all, so'
  Write-Output '  the "not reported" result above means nothing.'
} elseif ($armReports -eq 0) {
  Write-Output '  The arm read is NOT reported -- but DO NOT read that as "the read was'
  Write-Output '  recorded". Two explanations fit and this probe cannot separate them:'
  Write-Output '    (A) the reads inside a skipped arm ARE recorded, or'
  Write-Output '    (B) there is a blanket suppression: a local is not reported unused when'
  Write-Output '        its function contains ANY unanalysed region, so the analyzer'
  Write-Output '        declines to claim it knows.'
  Write-Output '  match_read_discriminator.ps1 separates them, and it finds (B).'
  Write-Output '  Source: Walker::audit_suppressed (walk.mbt:354), applied to UnusedLocal'
  Write-Output '  at walk.mbt:707. An earlier version of THIS file asserted (A); it was'
  Write-Output '  wrong, and the correction is the more consequential of the two.'
} else {
  Write-Output '  The arm read IS lost. `match` is a PREREQUISITE for analysing test'
  Write-Output '  bodies -- doing test first would import false positives.'
}

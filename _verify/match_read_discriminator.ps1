$ErrorActionPreference = 'Stop'
# WHICH of two explanations is right?
#
# Measured so far, with the positive control passing:
#   a local genuinely never read, in a function with NO unanalysed region  -> REPORTED
#   the same local, read only inside a match arm                          -> not reported
#   the same local, read in ordinary code inside an `if`                  -> not reported
#
# Two explanations fit that, and they call for opposite decisions:
#
#   (A) the reads inside a skipped arm ARE recorded. Then `match` and `test` are
#       independent backlog rows and either can be built first.
#   (B) there is a BLANKET SUPPRESSION: a local is not reported unused when its
#       function contains any unanalysed region, because the analyzer cannot
#       prove it is unused. Then the silence proves nothing about arms, AND
#       analysing test bodies would not import false positives -- but neither
#       would it import ANY unused-local finding until match is done, which is
#       its own kind of trap: a green run that is green for the wrong reason.
#
# The discriminator: a local that is never read AT ALL, in a function that DOES
# contain a match. Under (A) it is reported (arms contributed no reads either
# way). Under (B) it is not (the presence of the region suppresses everything).
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
if (-not (Test-Path $wasm)) { Write-Output 'ABORT: build the analyzer first.'; exit 1 }

$cases = [ordered]@{
  'neverread_no_skip'   = @'
fn go() {
  let seed = 1
  let _ = 0
}
let r = 1
let _ = r
'@
  'neverread_with_skip' = @'
fn go(z : Int) {
  let seed = 1
  let _ = match z {
    0 => 2
    _ => 0
  }
}
let r = 1
let _ = r
'@
}

$res = @{}
foreach ($name in $cases.Keys) {
  $dir = Join-Path $env:TEMP ('disc_' + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path $dir 'c.mbt'), $cases[$name], $enc)
  $out = Join-Path $dir 'o.txt'; $err = Join-Path $dir 'o.err'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $dir, '--extern-iface-dir', (Join-Path $root '.repos')) `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  $lines = @([System.IO.File]::ReadAllText($out) -split "`r?`n" |
             Where-Object { $_ -match '^\d+:\d+ - (error|warning|hint): ' })
  $res[$name] = $lines
  Write-Output ("--- {0} ---" -f $name)
  if ($lines.Count -eq 0) { Write-Output '  (no findings)' }
  foreach ($l in $lines) { Write-Output ('  ' + $l.Trim()) }
}

$plain = @($res['neverread_no_skip']  | Where-Object { $_ -match 'UnusedLocal' }).Count
$with  = @($res['neverread_with_skip'] | Where-Object { $_ -match 'UnusedLocal' }).Count
Write-Output ''
Write-Output '=== which explanation is right ==='
Write-Output ("  never-read local, function has NO unanalysed region : " + $(if ($plain -gt 0) { 'REPORTED' } else { 'not reported' }))
Write-Output ("  never-read local, function HAS an unanalysed region  : " + $(if ($with  -gt 0) { 'REPORTED' } else { 'not reported' }))
Write-Output ''
if ($plain -eq 0) {
  Write-Output '  POSITIVE CONTROL FAILED again -- the probe sees no unused locals at all.'
} elseif ($with -gt 0) {
  Write-Output '  (A) The reads inside a skipped arm ARE recorded. `match` and `test` are'
  Write-Output '      independent backlog rows; either can be built first.'
} else {
  Write-Output '  (B) BLANKET SUPPRESSION. A local is not reported unused when its function'
  Write-Output '      contains any unanalysed region, so the analyzer declines to claim it'
  Write-Output '      knows. Consequences, both of them real:'
  Write-Output '        - match/test are independent for FALSE POSITIVES;'
  Write-Output '        - but while any such region exists, unused-local findings for that'
  Write-Output '          whole function are OFF, so a green self-scan is partly green'
  Write-Output '          because it is not looking.'
}

# Re-measure all six corpora after a change, with the SAME invocation the release
# gate uses, so the numbers are comparable to the pinned ones.
#
#   moonrun.exe <wasm> <corpus dir> --extern-iface-dir <.repos>
#
# The `--extern-iface-dir` flag is not optional detail: proton reads 2142 without
# it and 2107 with it, so a set of numbers taken without the flag is a different
# measurement rather than an older one.
param([string]$Only = '')
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$wasm = Join-Path $repo '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$repos = Join-Path $repo '.repos'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'

$targets = [ordered]@{
  'moui'             = Join-Path $repos 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler'  = Join-Path $repos 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'    = Join-Path $repos 'riantr\moonbit_image\0.3.7'
  'async'            = Join-Path $repos 'moonbitlang\async\0.22.4'
  'proton'           = Join-Path $repos 'moonbit-community\proton\0.3.4'
  'proton_contract'  = Join-Path $repos 'moonbit-community\proton_contract\0.3.4'
}

$dir = Join-Path $env:TEMP ('remeas_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$keep = Join-Path $PSScriptRoot 'remeasure_out'
New-Item -ItemType Directory -Force -Path $keep | Out-Null

foreach ($k in $targets.Keys) {
  if (-not [string]::IsNullOrEmpty($Only) -and $k -notlike "*$Only*") { continue }
  $out = Join-Path $dir 'o.txt'
  $err = Join-Path $dir 'o.err'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $targets[$k], '--extern-iface-dir', $repos) `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  # Same lock `release.ps1` hit: `-Wait` ends with the process, not necessarily
  # with the redirected file's handle. Retry rather than report a harness failure
  # as a corpus number.
  $text = ''
  for ($i = 1; $i -le 20; $i++) {
    try { $text = [System.IO.File]::ReadAllText($out); break }
    catch [System.IO.IOException] {
      if ($i -eq 20) { throw ("could not read " + $out + " after 20 attempts") }
      Start-Sleep -Milliseconds (100 * $i)
    }
  }
  # KEEP THE WHOLE THING. The scanner prints a `files=N ...` line as it goes, so
  # the FIRST match is a progress line -- the first version of this script
  # reported `moonbit_image files=17 parsed=1` where the pinned value is 18/2, and
  # a scan that reports a number that is not the total is worse than no scan.
  [System.IO.File]::WriteAllText((Join-Path $keep ($k + '.txt')), $text)
  $all = [regex]::Matches($text, '(?m)^.*\bfiles=\d+.*$')
  $sum = if ($all.Count -gt 0) { $all[$all.Count - 1].Value.Trim() } else { '(no summary line)' }
  Write-Output ('{0,-18} {1}' -f $k, $sum)
  $np = [regex]::Matches($text, '(?m)^.*\bNOTPARSE\b.*$')
  if ($np.Count -gt 0) { Write-Output ('                 ' + $np[$np.Count - 1].Value.Trim()) }
  Write-Output ('                 (full output: _verify\remeasure_out\' + $k + '.txt)')
}
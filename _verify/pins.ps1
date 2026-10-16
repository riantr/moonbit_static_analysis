# Measure the SUMMARY line for all six pinned corpora.
#
# WHY THIS FILE EXISTS. The pins in release.ps1 must be measured, never
# inferred from a previous run's prose. An earlier ad-hoc loop over the same six
# corpora returned `files=3675 parsed=2831 actionable=125` for moonbit_labeler
# and then returned THE IDENTICAL line for moonbit_image. Two different corpora
# cannot produce identical summaries, so that was a stale or mismatched output
# file being read -- a measurement of nothing. It was caught only because the
# two answers were byte-identical; had one corpus happened to agree it would
# have been pinned as truth.
#
# => 判据: a measurement must assert WHICH SUBJECT it measured. "The scanner
# printed a SUMMARY" is not the claim; "the scanner printed a SUMMARY for the
# target I asked for, and it scanned a plausible number of files" is. Every
# failure mode here -- wrong tree, stale file, dropped argument -- is invisible
# in the number itself, which is precisely why the number needs a subject check
# beside it rather than a second opinion on the figure.
#
# So this asserts, per corpus:
#   * the TARGET line names the corpus that was requested
#   * the SCANNED count is non-zero
#   * the SCANNED count equals the number of .mbt/.mbti/.mbt.md files on disk
# Any of those failing aborts rather than printing a number.

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'

$TARGETS = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
}

$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
if (-not (Test-Path $wasm)) { throw "no wasm: $wasm" }

$seen = @{}
foreach ($k in $TARGETS.Keys) {
  $p = Join-Path '.repos' $TARGETS[$k]
  if (-not (Test-Path $p)) { throw "no corpus at $p" }

  # A fresh directory per corpus. The earlier failure mode was two reads of one
  # file, so nothing here is reused and nothing is left over.
  $d = Join-Path $env:TEMP ('pins_' + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Force -Path $d | Out-Null

  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $p, '--extern-iface-dir', '.repos') `
    -RedirectStandardOutput (Join-Path $d 'o.txt') `
    -RedirectStandardError (Join-Path $d 'o.err') -NoNewWindow -Wait | Out-Null

  $t = [IO.File]::ReadAllText((Join-Path $d 'o.txt'))

  # --- the subject checks -------------------------------------------------------
  # `${k}:` not `$k:` -- PowerShell reads a colon straight after a variable as
  # a drive qualifier, so "$k: scanner" is a parse error, not a string.
  $targetLine = ([regex]::Match($t, '(?m)^TARGET\s+(\S+)').Groups[1].Value)
  if ($targetLine -ne $p) { throw ("${k}: scanner reported TARGET '" + $targetLine + "', asked for '" + $p + "'") }

  $scanned = [int]([regex]::Match($t, '(?m)^SCANNED\s+(\d+)').Groups[1].Value)
  $onDisk = @(Get-ChildItem -Path (Join-Path $root $p) -Recurse -File |
    Where-Object { $_.Extension -in @('.mbt', '.mbti') -or $_.Name.EndsWith('.mbt.md') }).Count
  if ($scanned -le 0) { throw "${k}: SCANNED is $scanned" }
  if ($scanned -ne $onDisk) { throw ("${k}: SCANNED $scanned but $onDisk scannable files on disk -- different tree") }

  # --- the number, and a duplicate guard ----------------------------------------
  $s = ([regex]::Match($t, '(?m)^SUMMARY.*$').Value) -replace "`t", ' '
  $s = ($s -replace '^SUMMARY\s*', '') -replace '\s*\(actionable.*$', ''
  $s = $s.Trim()
  if ($seen.ContainsKey($s)) { throw ("$k and $($seen[$s]) produced an IDENTICAL summary -- not a measurement") }
  $seen[$s] = $k

  Write-Output ("'" + $k + "'".PadRight(18) + "= '" + $s + "'")
}

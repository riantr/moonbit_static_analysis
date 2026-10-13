# 0.4.28: how many `as &Trait` casts does the analyzer currently misreport?
#
# MEASURED BY THE TOOL, NOT BY A MATCHER.
#
# 0.4.27 cost two false zeros because the population was counted with a regex
# that could not match ordinary MoonBit (`fn[T]`, `Type::name`, a multi-line
# parameter list). This question does not need a matcher at all: the analyzer
# already emits one finding per occurrence, and the finding names the token.
# `undefined name 'as'` is a self-report. Counting it in the analyzer's own
# output cannot inherit a matcher's blind spot, because there is no matcher.
#
# THE COUNT IS BY NAME, NOT BY FAMILY. `undefined name 'raise'` was 65 of an
# UndefinedName population that could not be told apart from "no undefined names
# at all" by a family count (see pipeline_0424_test.mbt:38). Same trap, same
# answer: grep the message.
#
# WHAT THIS DOES AND DOES NOT ESTABLISH. It counts what the analyzer SAW. A cast
# in a file the analyzer never reached contributes nothing, so this is a LOWER
# BOUND on the construct and an EXACT count of the misreports. Both numbers are
# printed, because they are different claims and only the second one is a
# deliverable.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/measure_0428_as.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$wasm = "$root\_build\wasm\debug\build\moonbit_static_analysis.wasm"
$repos = "$root\.repos"
$outdir = Join-Path $env:TEMP 'fin_0428_as'
New-Item -ItemType Directory -Force -Path $outdir | Out-Null

$targets = [ordered]@{
  'moui'            = "$repos\wzzc-dev\moui\0.1.12"
  'moonbit_labeler' = "$repos\riantr\moonbit_labeler\0.2.13"
  'moonbit_image'   = "$repos\riantr\moonbit_image\0.3.7"
  'async'           = "$repos\moonbitlang\async\0.22.4"
  'proton'          = "$repos\moonbit-community\proton\0.3.4"
  'proton_contract' = "$repos\moonbit-community\proton_contract\0.3.4"
}

Set-Location $root
$abs = (Resolve-Path $wasm).Path
$total = 0; $bad = 0; $allFiles = @{}
foreach ($k in $targets.Keys) {
  $p = $targets[$k]
  # An absent corpus reads as "0 findings" rather than as "no corpus". Asserted,
  # not assumed -- that is how the TEMP tree emptying mid-run looked like a clean
  # zero twice.
  $n = @(Get-ChildItem -Path $p -Recurse -File -Filter '*.mbt' -EA SilentlyContinue |
         Where-Object { $_.FullName -notmatch '\\\.mooncakes\\' }).Count
  if ($n -eq 0) { Write-Output ("{0,-16} NO CORPUS -- 0 .mbt under {1}. NOT a zero." -f $k, $p); $bad++; continue }
  $out = Join-Path $outdir "$k.txt"
  $err = Join-Path $outdir "$k.err"
  # Start-Process takes an argument ARRAY; the `cmd.exe /c "... > f"` form had its
  # embedded quotes mangled once and produced six 0-byte dumps that still printed
  # a line per corpus.
  Start-Process -FilePath 'C:\Users\31379\.moon\bin\moonrun.exe' `
    -ArgumentList @($abs, $p, '--extern-iface-dir', $repos, '--no-auto-fetch-deps') `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  $len = (Get-Item $out).Length
  if ($len -eq 0) { Write-Output ("{0,-16} EMPTY OUTPUT -- aborting, NOT a zero" -f $k); $bad++; continue }

  $text = [System.IO.File]::ReadAllText($out)
  $hits = @([regex]::Matches($text, "undefined name 'as'"))
  # The per-finding lines carry only L:C, so the file comes from the nearest
  # FOUND/PARTIAL header above each hit. One pass, one increment per hit.
  $lines = $text -split "`r?`n"
  $cur = ''; $byFile = @{}
  foreach ($l in $lines) {
    if ($l -match '^(FOUND|PARTIAL)\s') { $cur = ($l -split "`t")[-1] }
    elseif ($l -match "undefined name 'as'" -and $cur -ne '') {
      $rel = $cur.Replace($p, '').TrimStart('\','/')
      if ($byFile.ContainsKey($rel)) { $byFile[$rel] = $byFile[$rel] + 1 } else { $byFile[$rel] = 1 }
      $allFiles[$k + '|' + $rel] = $true
    }
  }
  $summary = ([regex]::Match($text, '(?m)^SUMMARY.*$')).Value
  Write-Output ("{0,-16} files={1,-5} undefined-'as'={2,-4} in {3} file(s)" -f $k, $n, $hits.Count, $byFile.Count)
  foreach ($f in ($byFile.Keys | Sort-Object)) { Write-Output ("      {0}  x{1}" -f $f, $byFile[$f]) }
  $total += $hits.Count
  Write-Output ("      {0}" -f $summary)
}
Write-Output ''
if ($bad -gt 0) { Write-Output ("ABORT: $bad corpus/corpora absent or empty. The numbers above do not cover them."); exit 1 }
Write-Output ("TOTAL misreported `as` tokens across the six corpora: {0}, in {1} file(s)." -f $total, $allFiles.Count)
Write-Output 'This is an EXACT count of the misreports the analyzer emits, and a LOWER BOUND on the construct (a cast in a file the analyzer never reached is not counted).'
exit 0
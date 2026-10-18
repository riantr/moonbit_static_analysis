# The Direction 5 work queue: which PINNED-CORPUS files the frontend cannot read, and why.
#
# NOT the same thing as `backlog.ps1`. That one measures the analyzer's own source and groups
# the subset-EXCLUSION notices by message -- spans it read past and deliberately did not
# analyse. This one measures the corpora the release gate pins, and reports only the
# NOTPARSE block: the files where a parse actually FAILED, which is a different and much
# smaller queue. A row here is worth a settle and a reader; a row there is worth an AST node.
#
# Run from the REPO ROOT. That is load-bearing, not a convention: `auto_fetch_deps` fetches
# into a path RELATIVE to the process CWD (sa/main.mbt:483), so a scan from elsewhere indexes
# a different interface tree and every number below moves for a reason that has nothing to do
# with the parser. `_verify\ab_scan.ps1` is the guard for exactly that confound.
#
# A file that fails to parse reports NOTHING else useful: its findings are withheld, because
# they would measure what the analyzer does not understand rather than what the code does.
# So the NOTPARSE block is the only place the tool admits which files it could not read.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\corpus_backlog.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$repos = Join-Path $root '.repos'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
if (-not (Test-Path $wasm)) { Write-Output 'ABORT: build first -- moon build --target wasm'; exit 1 }

$TARGETS = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
}

function Read-TextWhenFree {
  # `Start-Process -Wait` waits for the PROCESS. It does not promise the redirected output
  # file's handle is already closed, and on this machine it is not, so a bare ReadAllText
  # reads a LOCKED file and throws. Read as an empty result it looks like a corpus that found
  # nothing -- a verdict about the code that is really a verdict about the harness. Same
  # helper and same reason as release.ps1; `backlog.ps1:36` still does not use one, which is
  # the most concrete lead so far on "why does moon test intermittently return empty output".
  param([string]$Path, [int]$Tries = 20)
  for ($i = 1; $i -le $Tries; $i++) {
    try {
      return [System.IO.File]::ReadAllText($Path)
    } catch [System.IO.IOException] {
      if ($i -eq $Tries) {
        throw ('could not read redirected output after ' + $Tries + ' attempts: ' + $Path +
               ' -- a harness failure, not a corpus result.')
      }
      Start-Sleep -Milliseconds 250
    }
  }
}

Write-Output ('commit : ' + (git rev-parse --short HEAD))
Write-Output ('cwd    : ' + (Get-Location).Path)
Write-Output ''
Write-Output '=== per-corpus ParseError backlog ==='

$total = 0
foreach ($k in $TARGETS.Keys) {
  $path = Join-Path $repos $TARGETS[$k]
  if (-not (Test-Path $path)) { Write-Output ("  {0,-16} [ABSENT]" -f $k); continue }
  $dir = Join-Path $env:TEMP ('cbl_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $out = Join-Path $dir 'o.txt'
  $err = Join-Path $dir 'o.err'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $path, '--extern-iface-dir', $repos) `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  $text = Read-TextWhenFree -Path $out

  $sum = (([regex]::Match($text, '(?m)^SUMMARY.*$').Value) -replace "`t", ' ') `
    -replace '^SUMMARY\s*', '' -replace '\s*\(actionable.*$', ''
  Write-Output ("  {0,-16} {1}" -f $k, $sum)

  $lines = $text -split "`r?`n"
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^NOTPARSE') { $start = $i; break }
  }
  if ($start -lt 0) { Write-Output '      (no NOTPARSE block: every file parsed)'; Write-Output ''; continue }

  for ($i = $start + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s+\d+x\s+') {
      $total++
      Write-Output ('      ' + $lines[$i].Trim())
      if (($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '^\s+e\.g\.') {
        Write-Output ('        ' + $lines[$i + 1].Trim())
      }
    } elseif ($lines[$i] -match '^SUMMARY') { break }
  }
  Write-Output ''
}

Write-Output ('=== total distinct NOTPARSE reasons across all corpora: ' + $total + ' ===')

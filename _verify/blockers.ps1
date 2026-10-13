# What actually BLOCKS a corpus file from being read -- ranked by the token on the
# line the parser stopped at.
#
# WHY THIS EXISTS. `_verify/backlog.ps1` ranks the subset-EXCLUSION notices
# ("match expression is outside the analyzed subset"), and README.md carries that
# ranking. That is a count of spans the frontend read past WITHOUT ANALYSING --
# the file still parses. The standing coverage metric is a different thing:
# `parsed=486/608` on wzzc-dev/moui 0.1.12, i.e. 122 files the frontend could not
# read AT ALL, each losing every finding after its first failure.
#
# So the two lists answer different questions, and only one of them is the metric.
# Measured on the same corpus the NOTPARSE reason tally already answers coarsely:
#   110x unexpected token, 2x expected '{', 3x invalid assignment target, ...
# "unexpected token" is the catch-all arm of `parse_atom` (parser.mbt:3438) and it
# does not name the token, so 90% of the blocked files are one anonymous line.
#
# This script recovers the evidence behind that number without changing the
# analyzer: the scanner prints a `PARTIAL` line per partly-understood file carrying
# its path and `region_line` (the line the parser stopped at), so the blocking
# source line can simply be read back from disk and printed.
#
# HONEST LIMIT. A partial file with ZERO findings before its boundary prints no
# `PARTIAL` line at all, so those files are invisible here. The script prints the
# recovered/122 ratio rather than letting the reader assume the tally is complete.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\blockers.ps1
#        [-Root <moui dir>] [-Scan <precomputed scan output file>]
param(
  [string]$Root = '',
  [string]$Scan = ''
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$wasm = Join-Path $repo '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'

if ([string]::IsNullOrEmpty($Root)) {
  $Root = Join-Path $repo '.repos\wzzc-dev\moui\0.1.12'
}
if (-not (Test-Path -LiteralPath $Root)) { Write-Output "ABORT: no such root: $Root"; exit 1 }

# --- obtain the scan text -------------------------------------------------
$scanText = ''
if (-not [string]::IsNullOrEmpty($Scan)) {
  if (-not (Test-Path -LiteralPath $Scan)) { Write-Output "ABORT: no such scan file: $Scan"; exit 1 }
  $scanText = [System.IO.File]::ReadAllText($Scan)
  Write-Output "  (using precomputed scan output: $Scan)"
} else {
  if (-not (Test-Path -LiteralPath $wasm)) { Write-Output 'ABORT: build first -- moon build --target wasm'; exit 1 }
  $dir = Join-Path $env:TEMP ('blockers_' + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $out = Join-Path $dir 'o.txt'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $Root, '--extern-iface-dir', (Join-Path $repo '.repos')) `
    -RedirectStandardOutput $out -RedirectStandardError (Join-Path $dir 'o.err') -NoNewWindow -Wait | Out-Null
  $scanText = [System.IO.File]::ReadAllText($out)
}

$sum = ([regex]::Match($scanText, '(?m)^SUMMARY.*$').Value) -replace "`t", ' '
$par = [regex]::Match($scanText, '(?m)^PARSED\s+(\d+)/(\d+) files understood \(([^)]*)\);\s+(\d+) more').Groups
$parsedN = [int]$par[1].Value; $fileN = [int]$par[2].Value; $pct = $par[3].Value; $blocked = [int]$par[4].Value

# The scanner's own reason tally -- the coarse answer, kept for comparison.
# Parsed out of the NOTPARSE block TOGETHER WITH its `e.g.` example paths, so a
# reason can be paired with the actual source line that produced it. The scanner
# prints only a few examples per reason (35 of 122 on moui), so this pairing is a
# labelled SAMPLE and the script says so rather than presenting it as the whole
# set. It is what turns "34x unexpected token `,`" into a syntax form.
$reasonTally = [ordered]@{}
$reasonExamples = [ordered]@{}
$curReason = ''
foreach ($l in ($scanText -split "`r?`n")) {
  $m = [regex]::Match($l, '(?m)^\s+(\d+)x\s+(.+)$')
  if ($m.Success) {
    $curReason = $m.Groups[2].Value.Trim()
    $reasonTally[$curReason] = [int]$m.Groups[1].Value
    $reasonExamples[$curReason] = @()
    continue
  }
  $e = [regex]::Match($l, '^\s+e\.g\.\s+(.+)$')
  if ($e.Success -and -not [string]::IsNullOrEmpty($curReason)) {
    $reasonExamples[$curReason] += $e.Groups[1].Value.Trim()
  }
}

# PARTIAL lines, keyed by path, so an example file can be resolved to its
# blocking line. `PARTIAL\t.mbt\t...\tread up to line L, U after it not shown\t<path>`
# The path is the text after the LAST tab: paths may contain spaces.
$rec = @{}
$recOrder = @()
foreach ($l in ($scanText -split "`r?`n")) {
  if ($l -notmatch '^PARTIAL\t') { continue }
  $sp = $l.LastIndexOf("`t")
  if ($sp -lt 0) { continue }
  $path = $l.Substring($sp + 1).Trim()
  $lm = [regex]::Match($l, 'read up to line (\d+)')
  if (-not $lm.Success) { continue }
  # Normalise the KEY on insert, not only at lookup. The two sides of the join
  # come from different parts of the scanner's output and spell the same path
  # differently -- PARTIAL prints it relative-to-CWD with the separator the
  # walk produced, while the NOTPARSE examples print it with `/` inside the
  # corpus root. Normalising only the lookup side paired 0 of 35 examples, which
  # prints as a confident "0 pairs" rather than as a bug.
  $path = $path -replace '/', '\'
  if (-not $rec.ContainsKey($path)) { $recOrder += $path }
  $rec[$path] = [int]$lm.Groups[1].Value
}

# --- read the blocking source line back off disk ---------------------------
# Powershell function trap, third recurrence in this repo: a function returns
# EVERYTHING it writes. `Get-SourceLine` below therefore returns an object and
# nothing else -- no Write-Output -- so it is safe to call inside an expression.
function Get-SourceLine([string]$abs, [int]$line) {
  if (-not (Test-Path -LiteralPath $abs)) { return $null }
  $all = [System.IO.File]::ReadAllLines($abs)
  if ($line -lt 1 -or $line -gt $all.Length) { return $null }
  return $all[$line - 1]
}

$rows = @{}
$missing = 0
foreach ($path in $recOrder) {
  # The scanner prints the path RELATIVE TO THE PROCESS CWD, which is the repo
  # root, so it comes back already absolute. Joining it onto $Root as well
  # produced a doubled path and made all 98 reads fail on the first run -- a
  # ranking of "<source line unreadable>" 98 times over, which reads like a
  # result. Rooted paths are used as they arrive.
  $abs = $path -replace '/', '\'
  if (-not [System.IO.Path]::IsPathRooted($abs)) { $abs = Join-Path $Root $abs }
  $src = Get-SourceLine $abs $rec[$path]
  if ($null -eq $src) { $missing++; $src = '<source line unreadable>' }
  $rows[$path] = [pscustomobject]@{
    Path = $path; Line = $rec[$path]
    Src  = $src.Trim()
    Key  = ($src.Trim() -replace '\s+', ' ')
  }
}

# --- rank by the shape of the blocking line --------------------------------
# Ranked on the token that FOLLOWS the indentation, which is the thing the
# parser choked on. Bucket key = first 60 chars of the trimmed line, so a
# repeated idiom aggregates instead of 110 one-off rows.
$groups = @{}
foreach ($path in $recOrder) {
  $r = $rows[$path]
  $k = $r.Key
  if ($k.Length -gt 60) { $k = $k.Substring(0, 60) }
  if (-not $groups.ContainsKey($k)) {
    $groups[$k] = [pscustomobject]@{ Count = 0; Files = @(); Src = $r.Src }
  }
  $groups[$k].Count++
  if ($groups[$k].Files.Count -lt 4) { $groups[$k].Files += ("{0}:{1}" -f $r.Path, $r.Line) }
}

Write-Output '=== what BLOCKS files from being read (hard parse failures) ==='
Write-Output ('  corpus  ' + $Root)
Write-Output ('  ' + ($sum -replace '\s+', ' '))
Write-Output ('  coverage: ' + $pct + ' understood; ' + $blocked + ' blocked')
Write-Output ''
Write-Output '  scanner reason tally (its own words, one per blocked file):'
foreach ($e in ($reasonTally.GetEnumerator() | Sort-Object -Property Value -Descending)) {
  Write-Output ("    {0,5}x  {1}" -f $e.Value, $e.Key)
}
Write-Output ''
Write-Output ("  blocking source line recovered for {0} of {1} blocked files" -f $rows.Count, $blocked)
if ($missing -gt 0) { Write-Output ("  ({0} of those had an unreadable source line)" -f $missing) }
if ($rows.Count -lt $blocked) {
  Write-Output ("  NOT RECOVERED: {0} blocked files print no PARTIAL line because they had zero" -f ($blocked - $rows.Count))
  Write-Output '  findings before their boundary. They are counted above and absent here --'
  Write-Output '  this list is a lower bound on the blocked set, not the whole of it.'
}

# --- each reason, with the source line that produced it --------------------
# THE PART THAT MAKES THE TALLY ACTIONABLE. "34x unexpected token `,`" says how
# many; this says which syntax. It works because `tok_desc` (parser.mbt) names the
# offending token AND the scanner prints an example path per reason -- so a reason
# can be joined to the PARTIAL line for that file and the source line read back.
#
# A LABELLED SAMPLE, not the full set: the scanner prints a few examples per
# reason, not every one. The count column is the real population; the lines are
# what that population looks like. Both numbers are printed so the reader never
# mistakes the sample for the census.
$paired = 0
$pairTotal = 0
Write-Output ''
Write-Output '  each reason, with the source line behind it (SAMPLE: the scanner prints'
Write-Output '  only some example paths per reason, so the lines illustrate the count)'
foreach ($e in ($reasonTally.GetEnumerator() | Sort-Object -Property Value -Descending)) {
  $why = $e.Key
  $ex = $reasonExamples[$why]
  Write-Output ''
  Write-Output ("    {0,5}x  {1}" -f $e.Value, $why)
  $shown = 0
  foreach ($p in $ex) {
    $pk = $p -replace '/', '\'
    if (-not $rows.ContainsKey($pk)) { continue }
    $pairTotal++
    $shown++
    $short = $pk.Substring($pk.LastIndexOf('\') + 1)
    Write-Output ("            {0}:{1}  |{2}|" -f $short, $rows[$pk].Line, $rows[$pk].Key)
  }
  $paired += $shown
  if ($shown -eq 0) { Write-Output '            (no example path had a PARTIAL line to resolve)' }
}
Write-Output ''
Write-Output ("  paired {0} reason/example pairs to a source line" -f $pairTotal)

Write-Output ''
Write-Output '  ranked by blocking line (descending); the line is truncated to 60 chars'
$i = 0
foreach ($g in ($groups.GetEnumerator() | Sort-Object -Property @{Expression={$_.Value.Count}; Descending=$true})) {
  $i++
  Write-Output ("  {0,2}. {1,4}x  {2}" -f $i, $g.Value.Count, $g.Key)
  foreach ($f in $g.Value.Files) { Write-Output ("        e.g. {0}" -f $f) }
}
Write-Output ''
Write-Output '  CONTRAST with _verify/backlog.ps1, which ranks NOTICES instead -- spans that'
Write-Output '  were read past without analysis. Those files still parse. Only the rows above'
Write-Output '  move the `parsed=` number the release gate pins.'
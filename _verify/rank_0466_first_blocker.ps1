# Per-FILE FIRST BLOCKER over async 0.22.4, measured on the tree that shipped as 8902242
# (0465: the `..` chain and 0465b loops in expression position).
#
# WHY PER FILE AND NOT PER MESSAGE. The scanner's NOTPARSE tally groups by MESSAGE, and
# one message covers several constructs -- `expected a struct literal field here` leads
# it with 36 sites and covers at least three unrelated shapes. Counting sites is worse
# still: labeler writes an annotated-`let` shape 148 times and is 5 files unread. Only
# the FIRST parse error decides a file's fate, and that is recoverable from each file's
# `read up to line N` line by reading line N.
#
# => 判据: print the CLASSIFIED LINES, not just the totals. This is the same lesson the
# `..` classifier taught three times over -- a plausible total is not evidence, and two
# different bad classifiers both produced plausible totals while returning DIFFERENT
# numbers for every corpus, so no cross-corpus sanity check catches them.
$ErrorActionPreference = 'Continue'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$corpus = Join-Path $repos 'moonbitlang\async\0.22.4'

$out = & 'C:\Users\31379\.moon\bin\moonrun.exe' $wasm $corpus --extern-iface-dir $repos 2>&1 | Out-String

# CONTROL FIRST: assert the parse produced per-file PARTIAL lines at all. Without this
# the ranking silently degrades to the message tally, which is the thing being replaced.
$partial = @()
foreach ($line in ($out -split "`n")) {
  if ($line -match '^PARTIAL\s+\.mbt\s+.*read up to line (\d+),.*\t(.+)$') {
    $partial += [pscustomobject]@{ Line = [int]$Matches[1]; Path = $Matches[2].Trim() }
  }
}
Write-Output ("CONTROL: PARTIAL lines recovered = {0}" -f $partial.Count)
if ($partial.Count -eq 0) { Write-Output '*** NO PER-FILE DETAIL. The ranking below would be the message tally. ***'; exit 1 }

# The line the parse STOPPED at is the first blocker, but the construct can begin a line
# or two earlier -- a multi-line `for` header, an annotated `let` whose body is on the
# next line. So read a window and show it. Showing is the point.
$rows = @()
foreach ($p in $partial) {
  if (-not (Test-Path $p.Path)) { continue }
  $src = [IO.File]::ReadAllLines($p.Path)
  $lo = [Math]::Max(0, $p.Line - 2)
  $hi = [Math]::Min($src.Length - 1, $p.Line + 1)
  $window = @()
  for ($i = $lo; $i -le $hi; $i++) { $window += $src[$i].Trim() }
  $rows += [pscustomobject]@{
    Rel   = $p.Path.Replace($corpus + '\', '').Replace($corpus + '/', '')
    Line  = $p.Line
    Text  = ($window -join ' | ')
  }
}

Write-Output ("files ranked = {0}" -f $rows.Count)
Write-Output ''
foreach ($r in ($rows | Sort-Object Line, Rel)) {
  Write-Output ('{0,5}  {1,-52} {2}' -f $r.Line, $r.Rel, $r.Text)
}

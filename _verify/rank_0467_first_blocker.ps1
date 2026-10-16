# Per-FILE FIRST BLOCKER, measured on the tree that shipped as 12b38a3
# (0466: `-> T noraise` / `-> T nocancel`, and 0466b `.. rest` in an array pattern).
#
# WHY THIS IS A NEW FILE AND NOT THE 0466 ONE RE-RUN. A ranking is a claim about a
# source state. 0466 moved async 330 -> 337 parsed and proton 115 -> 116, and took
# proton's `withheld` from 323 to 59 -- so 0466's own ranking is stale by definition,
# and re-running it would reprint 0466's answer while looking like fresh evidence.
#
# BOTH CORPORA THIS TIME, not async alone. 0466's reach moved mostly in proton, so an
# async-only ranking would rank a corpus that 0466 barely touched. proton goes 115 -> 116
# parsed but its `unreliable` fell 921 -> 727, and those are different populations:
# `unreliable` counts files with findings, `parsed` counts files read whole.
#
# WHY PER FILE AND NOT PER MESSAGE. The scanner's NOTPARSE tally groups by MESSAGE, and
# one message covers several constructs -- `expected a struct literal field here` leads
# it and covers at least three unrelated shapes. Counting sites is worse still: labeler
# writes an annotated-`let` shape 148 times and is 5 files unread. Only the FIRST parse
# error decides a file's fate, and that is recoverable from each file's
# `read up to line N` line by reading line N.
#
# => 判据: print the CLASSIFIED LINES, not just the totals. The `..` classifier taught
# this three times over -- a plausible total is not evidence, and two different bad
# classifiers both produced plausible totals while returning DIFFERENT numbers for every
# corpus, so no cross-corpus sanity check catches them.
$ErrorActionPreference = 'Continue'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'

# The bare `.repos\moonbitlang\async` holds three versions and must never be used.
$TARGETS = [ordered]@{
  'async'  = 'moonbitlang\async\0.22.4'
  'proton' = 'moonbit-community\proton\0.3.4'
}

$all = @()
foreach ($k in $TARGETS.Keys) {
  $corpus = Join-Path $repos $TARGETS[$k]
  $out = & 'C:\Users\31379\.moon\bin\moonrun.exe' $wasm $corpus --extern-iface-dir $repos 2>&1 | Out-String

  $nParsed = ([regex]::Match($out, '(?m)^SUMMARY\s+files=(\d+)\s+parsed=(\d+)'))
  $files = [int]$nParsed.Groups[1].Value
  $parsed = [int]$nParsed.Groups[2].Value

  # `parsed` IS `FOUND + CLEAN`, NOT `files - PARTIAL`. `files` also counts the .mbti and
  # manifest entries the scanner walks, so `files - parsed` overshoots badly -- async
  # reports files=419 parsed=337, which looks like 82 unread when only 40 are PARTIAL.
  # This was measured rather than assumed: the first version of this control asserted
  # `PARTIAL == files - parsed` and it failed on its own corpus, which is the only thing
  # that could have told the difference.
  $found = 0; $clean = 0
  foreach ($line in ($out -split "`n")) {
    if ($line -match '^FOUND\t')   { $found++ }
    if ($line -match '^CLEAN\t')   { $clean++ }
  }

  $partial = @()
  foreach ($line in ($out -split "`n")) {
    if ($line -match '^PARTIAL\s+\.mbt\s+.*read up to line (\d+),.*\t(.+)$') {
      $partial += [pscustomobject]@{ Line = [int]$Matches[1]; Path = $Matches[2].Trim() }
    }
  }
  Write-Output ('CONTROL {0,-8} SUMMARY files={1} parsed={2}  FOUND={3} CLEAN={4} (sum={5})  PARTIAL recovered={6}' -f $k, $files, $parsed, $found, $clean, ($found + $clean), $partial.Count)
  # Without per-file detail the ranking silently degrades to the message tally, which is
  # the thing being replaced. Assert it rather than assume it.
  if ($partial.Count -eq 0) {
    Write-Output ('*** NO PER-FILE DETAIL FOR {0}. The ranking below would be the message tally. ***' -f $k)
    exit 1
  }
  if (($found + $clean) -ne $parsed) {
    Write-Output ('*** {0}: FOUND+CLEAN={1} != SUMMARY parsed={2}. The scanner and this parser disagree. ***' -f $k, ($found + $clean), $parsed)
    exit 1
  }

  foreach ($p in $partial) {
    # Absolute path, or ReadAllLines resolves against the wrong root. A failed read must
    # NOT leave a previous file's lines alive -- so the read is checked, not assumed.
    if (-not [IO.File]::Exists($p.Path)) { continue }
    $src = $null
    try { $src = [IO.File]::ReadAllLines($p.Path) } catch { $src = $null }
    if ($null -eq $src) { continue }
    $lo = [Math]::Max(0, $p.Line - 2)
    $hi = [Math]::Min($src.Length - 1, $p.Line + 1)
    $window = @()
    for ($i = $lo; $i -le $hi; $i++) { $window += $src[$i].Trim() }
    $rel = $p.Path.Replace($corpus + '\', '').Replace($corpus + '/', '')
    $all += [pscustomobject]@{ Corpus = $k; Line = $p.Line; Rel = $rel; Text = ($window -join ' | ') }
  }
}

Write-Output ''
Write-Output ('files ranked = {0}' -f $all.Count)
Write-Output ''
foreach ($r in ($all | Sort-Object Corpus, Line, Rel)) {
  Write-Output ('{0,-8} {1,5}  {2,-46} {3}' -f $r.Corpus, $r.Line, $r.Rel, $r.Text)
}

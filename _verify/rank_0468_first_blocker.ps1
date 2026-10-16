# Per-FILE FIRST BLOCKER across ALL SIX corpora, on the tree that shipped as
# 7437666 (0467 + the corpus-derived grammar probe control).
#
# WHY A NEW FILE AND NOT `_verify/rank_0467_first_blocker.ps1` RE-RUN. Two reasons,
# and the second is the one that matters.
#
# 1. A ranking is a claim about a SOURCE STATE. 0467 moved async 337 -> 352 parsed and
#    proton 116 -> 121, so 0467's own ranking is stale by definition and re-running it
#    would reprint its answer while looking like fresh evidence.
#
# 2. 0467's SHAPE BUCKETS WERE WRONG, and they were wrong in a way that a total could
#    never reveal. The buckets were assigned by matching a 4-line window around the
#    blocker against a taxonomy, and five files that DID move (`async.mbt`,
#    `integration.mbt`, `integration.wasm.mbt`, `test_util.mbt`, `server_wbtest.mbt`)
#    had been bucketed `OTHER`. A bucket is an INFERENCE about a construct; a wrong
#    inference produces a plausible count, and a plausible count is exactly what a
#    cross-corpus sanity check cannot catch.
#
# => 判据: PRINT THE CLASSIFIED THING ITSELF. This file does not classify anything. It
# prints, for each unreadable file, the EXACT SOURCE TEXT of its first blocker line, and
# then groups by that text. The taxonomy is the reader's, not the script's: the script
# reports and does not decide. A wrong bucket cannot survive being printed next to the
# line it was wrong about.
#
# PER FILE AND NOT PER MESSAGE, for the reason `_verify/rank_0467_first_blocker.ps1`
# gives: the scanner's NOTPARSE tally groups by MESSAGE, one message covers several
# constructs, and counting sites is worse still -- labeler writes an annotated-`let`
# shape 148 times and is 5 files unread. Only the FIRST parse error decides a file's
# fate, and that is recoverable from each file's `read up to line N` line by reading
# line N.
$ErrorActionPreference = 'Continue'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'

# The bare `.repos\moonbitlang\async` holds three versions and must never be used.
$TARGETS = [ordered]@{
  'moui'     = 'wzzc-dev\moui\0.1.12'
  'labeler'  = 'riantr\moonbit_labeler\0.2.13'
  'image'    = 'riantr\moonbit_image\0.3.7'
  'async'    = 'moonbitlang\async\0.22.4'
  'proton'   = 'moonbit-community\proton\0.3.4'
  'contract' = 'moonbit-community\proton_contract\0.3.4'
}

$all = @()
foreach ($k in $TARGETS.Keys) {
  $corpus = Join-Path $repos $TARGETS[$k]
  $out = & 'C:\Users\31379\.moon\bin\moonrun.exe' $wasm $corpus --extern-iface-dir $repos 2>&1 | Out-String

  $nParsed = [regex]::Match($out, '(?m)^SUMMARY\s+files=(\d+)\s+parsed=(\d+)')
  $files = [int]$nParsed.Groups[1].Value
  $parsed = [int]$nParsed.Groups[2].Value
  # `parsed` IS `FOUND + CLEAN`, NOT `files - PARTIAL` -- `files` also counts the .mbti
  # and manifest entries the scanner walks, so the subtraction overshoots.
  $found = 0; $clean = 0
  foreach ($line in ($out -split "`n")) {
    if ($line -match '^FOUND\t') { $found++ }
    if ($line -match '^CLEAN\t') { $clean++ }
  }
  $partial = @()
  foreach ($line in ($out -split "`n")) {
    if ($line -match '^PARTIAL\s+\.mbt\s+.*read up to line (\d+),.*\t(.+)$') {
      $partial += [pscustomobject]@{ Line = [int]$Matches[1]; Path = $Matches[2].Trim() }
    }
  }
  Write-Output ('CONTROL {0,-9} files={1} parsed={2}  FOUND={3} CLEAN={4} (sum={5})  PARTIAL recovered={6}' -f $k, $files, $parsed, $found, $clean, ($found + $clean), $partial.Count)

  # The invariant that is actually checkable is `FOUND + CLEAN == parsed`: it says the
  # scanner's own two verdicts account for every file it claims to have read.
  #
  # It is NOT `PARTIAL > 0`. The first version of this file aborted when a corpus
  # reported no per-file detail, and the first corpus it saw was moui at 608/608 --
  # ZERO unread files, so ZERO detail, which is the healthy case. A check that cannot
  # tell "nothing to report" from "the detail is broken" is the confident-zero hazard
  # this repository keeps re-documenting, and it took one run to walk into it.
  if (($found + $clean) -ne $parsed) {
    Write-Output ('*** {0}: FOUND+CLEAN={1} != SUMMARY parsed={2}. The scanner and this parser disagree. ***' -f $k, ($found + $clean), $parsed)
    exit 1
  }
  if ($partial.Count -eq 0) {
    Write-Output ('         {0}: nothing unread in this corpus ({1} of {2} files read whole) -- no rows to rank.' -f $k, $parsed, $files)
  }

  $dropped = 0
  foreach ($p in $partial) {
    # Absolute path, or ReadAllLines resolves against the wrong root. A failed read must
    # NOT leave the previous file's lines alive, so the read is checked, not assumed.
    #
    # And it must NOT be SILENT. The first version did `continue` on a missing or
    # unreadable file, which is a ranking that quietly loses rows and still prints a
    # confident total -- the same defect the parser itself has, one layer out. A
    # dropped row is counted and named instead.
    $src = $null
    if (-not [IO.File]::Exists($p.Path)) {
      $dropped++
      Write-Output ('         DROPPED (absent)   {0}' -f $p.Path)
      continue
    }
    try { $src = [IO.File]::ReadAllLines($p.Path) } catch { $src = $null }
    if ($null -eq $src) {
      $dropped++
      Write-Output ('         DROPPED (unreadable) {0}' -f $p.Path)
      continue
    }
    $n = $p.Line - 1
    if ($n -lt 0 -or $n -ge $src.Length) {
      $dropped++
      Write-Output ('         DROPPED (line {0} outside a {1}-line file) {2}' -f $p.Line, $src.Length, $p.Path)
      continue
    }
    $rel = $p.Path.Replace($corpus + '\', '').Replace($corpus + '/', '')
    $all += [pscustomobject]@{
      Corpus = $k; Line = $p.Line; Rel = $rel
      Text = $src[$n].Trim()   # the construct, verbatim -- NOT classified
      Prev = $(if ($n -gt 0) { $src[$n - 1].Trim() } else { '' })
    }
  }
  # A ranking that dropped rows is a ranking with a hole in it. Say so and stop, rather
  # than printing a smaller total that reads exactly like a smaller corpus.
  if ($dropped -gt 0) {
    Write-Output ('*** {0}: {1} recovered row(s) could not be read, so the ranking below is INCOMPLETE. ***' -f $k, $dropped)
    exit 1
  }
}

Write-Output ''
Write-Output ('unreadable files recovered across all six corpora = {0}' -f $all.Count)
Write-Output ''

Write-Output '=== GROUPED BY THE VERBATIM FIRST-BLOCKER LINE ==='
Write-Output '    (count = files, not sites: only the first error decides a file)'
Write-Output ''
foreach ($g in ($all | Group-Object Text | Sort-Object Count -Descending)) {
  Write-Output ('{0,4} files  {1}' -f $g.Count, $g.Name)
  $where = @($g.Group | Sort-Object Corpus, Rel | Select-Object -First 6)
  foreach ($w in $where) {
    Write-Output ('          {0,-9} {1,5}  {2}' -f $w.Corpus, $w.Line, $w.Rel)
  }
  if ($g.Count -gt $where.Count) { Write-Output ('          ... and {0} more' -f ($g.Count - $where.Count)) }
  Write-Output ''
}

Write-Output '=== EVERY UNREADABLE FILE, its first blocker line, and the line above it ==='
Write-Output '    (printed in full so a wrong reading is visible next to the evidence)'
Write-Output ''
foreach ($r in ($all | Sort-Object Corpus, Text, Rel)) {
  Write-Output ('{0,-9} {1,5}  {2}' -f $r.Corpus, $r.Line, $r.Rel)
  Write-Output ('              | ' + $r.Text)
  if (-not [string]::IsNullOrWhiteSpace($r.Prev)) { Write-Output ('           >  | ' + $r.Prev) }
}

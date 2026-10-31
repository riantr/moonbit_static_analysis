# DIRECTION 2: IS THE BEHAVIOR LENS OBSERVABLE AT ALL?
#
# MEASURED ANSWER, and it is the finding this direction was opened to look for. The answer is
# yes -- and it is observable on ONE pinned corpus, not on none.
#
#   THE SEVEN PINNED CORPORA. TWO NUMBERS EACH, because they are different numbers:
#   `printed` is the findings the analyzer prints one per line, and `total` is the findings
#   behind them -- the analyzer prints a finding only when it can HIDE another finding, and
#   counts the rest BY SHAPE.
#
#     moui                printed 1126  total 3457   behavior 0
#     moonbit_labeler     printed  142  total  699   behavior 0
#     moonbit_image       printed   93  total  186   behavior 0
#     async               printed  250  total 1654   behavior 0
#     proton              printed  497  total 1799   behavior 0
#     proton_contract     printed    0  total   29   behavior 0
#     moonbit_core        printed 1172  total 10770  behavior 5  only 3
#
# WHY THE OLD TABLE WAS WRONG, AND WHY IT WAS WRONG QUIETLY. It said "7493 findings" in
# total and gave per-corpus numbers (moui 4152, async 1677, proton 959, ...) that matched
# nothing this analyzer produces. It was not wrong by a little: it was counting a DIFFERENT
# THING. The analyzer used to print every finding; it now prints one per line only when the
# finding can hide another, and counts the rest by shape. So the printed count FELL while
# the finding count ROSE. A table that called the printed count "findings" could not be
# compared with anything, and nothing compared it with anything -- until this file read its
# own header and failed. The four numbers that moved are the four corpora whose printed
# count is smaller than it was; proton, proton_contract and moonbit_core did not move.
#
# NOT AN ARTEFACT OF PARSING. The positive control is in this file's own body below: a
# fixture the scanner DOES tag `[behavior]` proves the tag is emitted and can be counted.
# A count of zero measured with a broken reader would look exactly like this.
#
# THE MECHANISM, CONFIRMED CAUSALLY AND NOT BY CORRELATION. `interp.mbt` executes
# top-level statements and whatever they reach; a function nothing calls is never executed.
# Appending ONE top-level call to a copy of moonbit-community/proton_contract 0.3.4 --
# changing no other byte -- takes that corpus from 0 findings to 1, and that 1 is
# `[behavior]` ALONE:
#
#     322:18 - error: no method matching application_route() (MethodError) [behavior]
#
# THE FIVE ON CORE ARE NOT THAT MECHANISM. They are `UndefinedName` reader gaps --
# the interpreter read a name the reader could not resolve -- so they are the behavior
# lens firing on a corpus that HAS an entry point, not the lens finding a method call
# that nothing reaches. Three of the five carry `behavior` ALONE.
#
# => 判据: this is a VERIFICATION gap, not a correctness gap, and the distinction matters.
# Roughly a thousand lines of `interp.mbt` are unexercised by every pinned corpus, so the
# SIX SUMMARY lines this release gate pins -- its primary defence -- carry ZERO signal about
# the behavior lens. Any regression there leaves all six pins green. Every interp
# mutation is catchable ONLY by a unit test, which is why `mutate_0426`'s M1/M2, `mutate_0443`
# and `mutate_0469`'s M11 all name interp tests explicitly rather than relying on a drift.
#
# WHAT THIS FILE CHECKS ABOUT ITSELF. The table above is a number written down, and a number
# written down twice will disagree with itself. So this file READS ITS OWN HEADER and
# fails if what it measured differs from what the header claims. The header is therefore a
# CHECKED claim, not a comment -- and it cannot go stale against the analyzer, because the
# analyzer is what the check compares it to.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/dir2_behavior_reach.ps1
$ErrorActionPreference = 'Continue'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'

# THE PRINTED COUNT, NOT THE TOTAL. The analyzer prints a finding one per line when it can
# HIDE another finding -- when its region lies inside some function's extent -- and counts
# the rest BY SHAPE. So "printed lines" and "findings" are two different numbers, and a
# table that says "findings" while counting printed lines is a table with the wrong name.
#
# The cap is raised here for the same reason the release gate raises it: at the default
# cap the count is a property of the CAP, not of the corpus, and a cap that changes makes
# the number move without anything about the analyzer changing. The SUMMARY line is read
# and printed beside it so the reader can see printed-vs-total instead of trusting one.
$rx = '\(([A-Za-z]+)\)\s*\[([a-z+\-]+)(, MSA-\d{3}, (high|low|undecided))?\]\s*$'

function Get-Findings([string]$dir) {
  $out = & 'C:\Users\31379\.moon\bin\moonrun.exe' $wasm $dir --extern-iface-dir $repos --findings-shown-per-file 1000000 2>&1 | Out-String
  $total = 0; $behav = 0; $only = 0
  $summary = 0
  foreach ($ln in ($out -split "`n")) {
    # 0507. The bracket carries the lenses, the family's stable id and the
    # confidence. The LENS TAG is the first comma-separated part; matching the
    # whole bracket would make every finding UNMATCHED and the count zero.
    if ($ln -notmatch $rx) { continue }
    $total++
    $lenses = $Matches[2] -split '\+'
    $hasB = $lenses -contains 'behavior'
    if ($hasB) { $behav++ }
    if ($hasB -and -not ($lenses -contains 'structural') -and -not ($lenses -contains 'type')) { $only++ }
  }
  foreach ($ln in ($out -split "`n")) {
    if ($ln -match '\bSUMMARY\b.*\btotal=(\d+)') { $summary = [int]$Matches[1] }
  }
  return @{ total = $total; behav = $behav; only = $only; summary = $summary; raw = $out }
}

Write-Output '=== POSITIVE CONTROL: the tag IS emitted, and this counter CAN see it ==='
$c = Join-Path $env:TEMP ('dir2ctrl_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $c | Out-Null
[IO.File]::WriteAllText((Join-Path $c 'moon.mod'), "name = `"dir2/ctrl`"`n`nversion = `"0.1.0`"`n")
[IO.File]::WriteAllText((Join-Path $c 'moon.pkg'), "supported_targets = `"+all`"`n")
[IO.File]::WriteAllText((Join-Path $c 'subject.mbt'), "fn build() -> Unit {`n  no_such_helper()`n}`nbuild()`n")
$r = Get-Findings $c
Write-Output ("  control: findings={0} with-behavior={1} behavior-ONLY={2}" -f $r.total, $r.behav, $r.only)
if ($r.behav -eq 0) {
  Write-Output '  *** THE CONTROL FAILED: the behavior tag is not being counted at all. ***'
  Write-Output '      Every number below would be a confident zero. Stop here.'
  exit 1
}
Write-Output '  control OK: the counter sees behavior findings, so a zero elsewhere is real.'
Write-Output ''

Write-Output '=== THE CORPUS QUESTION: does ANY pinned corpus exercise the lens? ==='
$TARGETS = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
  'moonbit_core'    = 'moonbitlang\core\0.1.20260920+7d59c7ec9'
}
$gt = 0; $gb = 0; $go = 0; $gs = 0
$measured = [ordered]@{}
foreach ($k in $TARGETS.Keys) {
  $r = Get-Findings (Join-Path $repos $TARGETS[$k])
  Write-Output ("  {0,-16} printed={1,-6} total={2,-6} with-behavior={3,-4} behavior-ONLY={4}" -f $k, $r.total, $r.summary, $r.behav, $r.only)
  $measured[$k] = @{ printed = $r.total; total = $r.summary; behav = $r.behav; only = $r.only }
  $gt += $r.total; $gs += $r.summary; $gb += $r.behav; $go += $r.only
}
Write-Output ("  {0,-16} printed={1,-6} total={2,-6} with-behavior={3,-4} behavior-ONLY={4}" -f 'ALL SEVEN', $gt, $gs, $gb, $go)
Write-Output ''

# --- THE HEADER IS A CHECKED CLAIM ------------------------------------------------
#
# The table at the top of this file is read back and compared with what was just
# measured. A table that is only a comment rots silently -- and this one had already
# rotted: it still carried the Oct-17 numbers (7493 in total) while the analyzer that
# produces them had moved on twice. The check below is what stops it happening again.
$headerPath = $PSCommandPath
$headerTxt = [System.IO.File]::ReadAllText($headerPath, [System.Text.Encoding]::UTF8)
$bad = 0
foreach ($k in $measured.Keys) {
  $m = $measured[$k]
  # The header row names what each number IS, so the row cannot be read as something it is
  # not:   <corpus>  printed <n>  total <n>  behavior <n>  [only <n>]
  $rxRow = '(?m)^#\s+' + [regex]::Escape($k) + '\s+printed\s+(\d+)\s+total\s+(\d+)\s+behavior\s+(\d+)(?:\s+only\s+(\d+))?\s*$'
  $mm = [regex]::Match($headerTxt, $rxRow)
  if (-not $mm.Success) {
    Write-Output ('  FAIL: the header has no row for ' + $k + ' -- the table and the measurement disagree about WHICH corpora exist.')
    $bad++
    continue
  }
  $hPrinted = [int]$mm.Groups[1].Value
  $hTotal   = [int]$mm.Groups[2].Value
  $hBehav   = [int]$mm.Groups[3].Value
  $hOnly    = 0
  if ($mm.Groups[4].Success) { $hOnly = [int]$mm.Groups[4].Value }
  if ($hPrinted -ne $m.printed -or $hTotal -ne $m.total -or $hBehav -ne $m.behav -or $hOnly -ne $m.only) {
    Write-Output ('  FAIL: the header says ' + $k + ' printed=' + $hPrinted + ' total=' + $hTotal + ' behavior=' + $hBehav + ' only=' + $hOnly +
                  '; the measurement says printed=' + $m.printed + ' total=' + $m.total + ' behavior=' + $m.behav + ' only=' + $m.only + '.')
    $bad++
  } else {
    Write-Output ('  {0,-16} the header agrees: printed={1} total={2} behavior={3} only={4}' -f $k, $hPrinted, $hTotal, $hBehav, $hOnly)
  }
}
Write-Output ''
if ($bad -gt 0) {
  Write-Output ('GATE FAILED: ' + $bad + ' header row(s) disagree with the measurement.')
  Write-Output '  The table at the top of this file is a CHECKED claim, and it is wrong.'
  Write-Output '  Correct it to the measured numbers above, and say WHY it moved.'
  exit 1
}
Write-Output 'GATE OK: the header table IS what the analyzer produces today.'

if ($gb -eq 0) {
  Write-Output 'MEASURED: the behavior lens contributes NOTHING on any pinned corpus.'
  Write-Output 'That is the Direction 2 answer, and it is a VERIFICATION gap, not a bug:'
  Write-Output 'the six SUMMARY lines this gate pins carry no signal about interp.mbt.'
  Write-Output 'The next step is a DECISION, not a fix -- see the header.'
  exit 0
}
Write-Output ("MEASURED: {0} findings carry the behavior lens, {1} of them behavior-ONLY." -f $gb, $go)
Write-Output 'The lens IS observable -- on moonbit_core, and only there. The six older corpora'
Write-Output 'still carry none, which is what makes this a VERIFICATION gap on those six.'
exit 0

# DIRECTION 2: IS THE BEHAVIOR LENS OBSERVABLE AT ALL?
#
# MEASURED ANSWER, and it is the finding this direction was opened to look for. The answer is
# yes, and it is observable ONLY on code that has an entry point -- which no pinned corpus
# has.
#
#   ALL SIX CORPORA      7493 findings      0 carrying the behavior lens
#     moui                4152              0
#     async               1677              0
#     proton               959              0
#     moonbit_labeler      469              0
#     moonbit_image        202              0
#     proton_contract        34              0
#
# NOT AN ARTEFACT OF PARSING. The positive control is in this file's own body below: a
# fixture the scanner DOES tag `[behavior]` proves the tag is emitted and can be counted.
# A count of zero measured with a broken reader would look exactly like this.
#
# THE MECHANISM, CONFIRMED CAUSALLY AND NOT BY CORRELATION. `interp.mbt` executes top-level
# statements and whatever they reach; a function nothing calls is never executed. Appending
# ONE top-level call to a copy of moonbit-community/proton_contract 0.3.4 -- changing no
# other byte -- takes that corpus from 0 findings to 1, and that 1 is `[behavior]` ALONE:
#
#     322:18 - error: no method matching application_route() (MethodError) [behavior]
#
# So the lens is not broken and not silent for lack of findings. It has nothing to run.
#
# => 判据: this is a VERIFICATION gap, not a correctness gap, and the distinction matters.
# Roughly a thousand lines of `interp.mbt` are unexercised by every pinned corpus, so the
# SIX SUMMARY lines this release gate pins -- its primary defence -- carry ZERO signal about
# the behavior lens. Any regression there is catchable only by a unit test, and a corpus
# pin will happily stay green through it.
#
# TWO RELATED FACTS, both measured during 0469 and both recorded where they were found:
#   - the lens ABSORBS `AAny`: interp.mbt:1076 has `AAny => true` in `numeric` and :1094
#     short-circuits the operator arm on it, so a mutation that leaves a value unknown is
#     invisible to it (that is why `mutate_0469.ps1`'s M11 had to mutate to a CONCRETE
#     `AType("str")` rather than `AAny`);
#   - it needs a CALL: a function nothing calls is never executed, which is how its own
#     guard rows had to end with a trailing `f()`.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/dir2_behavior_reach.ps1
$ErrorActionPreference = 'Continue'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'

function Get-Findings([string]$dir) {
  $out = & 'C:\Users\31379\.moon\bin\moonrun.exe' $wasm $dir --extern-iface-dir $repos 2>&1 | Out-String
  $total = 0; $behav = 0; $only = 0
  foreach ($ln in ($out -split "`n")) {
    if ($ln -notmatch '\(([A-Za-z]+)\)\s*\[([a-z+]+)\]\s*$') { continue }
    $total++
    $lenses = $Matches[2] -split '\+'
    $hasB = $lenses -contains 'behavior'
    if ($hasB) { $behav++ }
    if ($hasB -and -not ($lenses -contains 'structural') -and -not ($lenses -contains 'type')) { $only++ }
  }
  return @{ total = $total; behav = $behav; only = $only; raw = $out }
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
}
$gt = 0; $gb = 0; $go = 0
foreach ($k in $TARGETS.Keys) {
  $r = Get-Findings (Join-Path $repos $TARGETS[$k])
  Write-Output ("  {0,-16} findings={1,-6} with-behavior={2,-4} behavior-ONLY={3}" -f $k, $r.total, $r.behav, $r.only)
  $gt += $r.total; $gb += $r.behav; $go += $r.only
}
Write-Output ("  {0,-16} findings={1,-6} with-behavior={2,-4} behavior-ONLY={3}" -f 'ALL SIX', $gt, $gb, $go)
Write-Output ''
if ($gb -eq 0) {
  Write-Output 'MEASURED: the behavior lens contributes NOTHING on any pinned corpus.'
  Write-Output 'That is the Direction 2 answer, and it is a VERIFICATION gap, not a bug:'
  Write-Output 'the six SUMMARY lines this gate pins carry no signal about interp.mbt.'
  Write-Output 'The next step is a DECISION, not a fix -- see the header.'
  exit 0
}
Write-Output ("MEASURED: {0} findings carry the behavior lens, {1} of them behavior-ONLY." -f $gb, $go)
exit 0

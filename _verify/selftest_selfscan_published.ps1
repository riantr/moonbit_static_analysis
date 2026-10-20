# Self-test for the published-package self-scan gate -- the EMPTY TREE defect.
#
# WHAT THIS IS. `_verify/selfscan_published.ps1` is a gate: it fetches the
# PUBLISHED package from the registry, runs the analyzer that shipped inside it
# over that package's own source, and asserts the result is clean. On
# 2026-10-20, cutting 0.4.30, that gate reported
#
#     GATE OK: the published 0.4.30 scans its own shipped source clean.
#
# on a scan that had read NOTHING. The registry download had timed out, `moonx`
# created the package directory EMPTY, and the scanner -- which found an empty
# directory -- printed a perfectly well-formed report:
#
#     SCANNED  0 files under .repos/riantr/moonbit_static_analysis/0.4.30
#     SKIP     .repos/riantr/moonbit_static_analysis/0.4.30/moon.mod unreadable: OSError(...)
#     PARSED   0/0 files understood (0.0%)
#     SUMMARY  files=0 parsed=0 actionable=0 notices=0 unreliable=0 withheld=0 total=0
#
# `actionable=0` is TRUE of an empty tree. Every check the gate made was a true
# statement about nothing, and the sum of true statements about nothing is
# GATE OK. The script's own header had warned against this -- "EMPTY OUTPUT IS
# A FAILURE, NOT A ZERO" -- and the missing guard was one level down: that note
# catches a scan that printed nothing, and nothing caught a scan that printed a
# SUMMARY and read no files.
#
# THE FIX is two assertions on the SCANNER's own output, in
# `selfscan_published.ps1`: the scanned file count must be GREATER THAN ZERO,
# and the package's own `moon.mod` must not appear in a `SKIP` line.
#
# WHY THIS SCRIPT EXISTS. A guard that has never been shown to go red is a
# comment. The two fixtures below are REAL CAPTURES, not hand-written
# imitations of one, and the third check below is the one that makes the
# evidence mean something:
#
#   the same broken capture PASSES with the guard disarmed.
#
# That is the difference between "the gate is red" and "THE GUARD is why the
# gate is red". Without it, a gate that is red for any other reason -- a
# changed version assertion, a typo in a message -- would look like a working
# guard.
#
# THE FIXTURES.
#   _verify\fixtures\selfscan_empty_tree_0430.out
#     The 2026-10-20 capture of the timed-out 0.4.30 download. 719 bytes.
#   _verify\fixtures\selfscan_healthy_0429.out
#     The same day's capture of the PUBLISHED 0.4.29 tree -- 68 files, parsed
#     68/68, actionable=0, 823 notices. 93 KB.
#
# Both are byte-identical copies of the captures in the temp scratch directories
# the 2026-10-20 runs left behind; they are committed rather than regenerated
# because a fixture written to make a guard look good is worth nothing.
#
# => 判据: a vacuous pass is worse than a red gate. A gate that reports OK on a
# scan of nothing has told the release that the shipped artifact is clean, and
# the shipped artifact was never read.
#
# A NOTE ON THE TWO MESSAGE ASSERTIONS IN CHECK 1. They match the guard's own
# wording -- "the scan read ZERO files" and "own moon.mod was SKIPped" -- and
# that coupling is on purpose: the point of CHECK 1 is not merely that the
# capture fails, but that it fails FOR THE TREE-PRESENCE REASON. A reworded
# message will make this self-test go red, and that red is a prompt, not a
# defect: reword the message and these two regexes in the SAME commit. The
# count assertion -- exactly two checks failed -- is parsed out of the ABORT
# line and is message-independent.
param(
  # Skip the source-level pin (CHECK 4). It exists because the live path cannot
  # be exercised without the network, and it is the only check here that is not
  # a behavioural one.
  [switch]$SkipSourcePin
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $PSScriptRoot 'selfscan_published.ps1'
$fx = Join-Path $PSScriptRoot 'fixtures'
$broken = Join-Path $fx 'selfscan_empty_tree_0430.out'
$healthy = Join-Path $fx 'selfscan_healthy_0429.out'

$failed = @()

function Run-Scan {
  param([string[]]$Extra)
  $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $target)
  if ($Extra) { $argv += $Extra }
  $o = & powershell @argv 2>&1 | Out-String
  return @{ Out = $o; Code = $LASTEXITCODE }
}

function Check {
  param([string]$Name, [bool]$Ok, [string]$Detail)
  if ($Ok) {
    Write-Output ('  ok   ' + $Name)
  } else {
    Write-Output ('  FAIL ' + $Name)
    if ($Detail) { Write-Output ('       ' + $Detail) }
    $script:failed += $Name
  }
}

foreach ($f in @($target, $broken, $healthy)) {
  if (-not (Test-Path -LiteralPath $f)) {
    Write-Output ('ABORT: missing ' + $f); exit 1
  }
}

Write-Output ''
Write-Output '=== self-test: the published-package self-scan gate ==='
Write-Output ''

# --- CHECK 1  the guard fires on a scan that read nothing ----------------------
Write-Output 'CHECK 1  the empty-tree capture must FAIL, and the guard must be the reason'
$r1 = Run-Scan @('-Replay', $broken)
$o1 = $r1.Out
if ($r1.Code -ne 0) {
  Write-Output '  ok   exit code is non-zero'
} else {
  Write-Output ('  FAIL exit code is ' + $r1.Code + ' -- the gate passed a scan of nothing')
  $failed += 'CHECK1 exit code'
}
Check 'CHECK1 zero-files assertion fired' ($o1 -match 'the scan read ZERO files') 'no zero-file assertion in the output'
Check 'CHECK1 moon.mod SKIP assertion fired' ($o1 -match "own moon\.mod was SKIPped") 'no moon.mod SKIP assertion in the output'
# EXACTLY two failures. If a third check also fired, the guard would not be the
# whole story -- the capture would be failing for some other reason too, and
# this evidence would be about that reason instead.
$aborts = @([regex]::Matches($o1, 'ABORT: (\d+) check\(s\) failed'))
$abortedWith = 0
if ($aborts.Count -eq 1) { $abortedWith = [int]$aborts[0].Groups[1].Value }
Check 'CHECK1 exactly two checks failed' ($abortedWith -eq 2) ('the capture failed ' + $abortedWith + ' check(s), not 2')

# --- CHECK 2  the guard is the CAUSE, not a passenger -------------------------
Write-Output ''
Write-Output 'CHECK 2  the same capture with the guard DISARMED must PASS -- that is what makes CHECK 1 mean something'
$r2 = Run-Scan @('-Replay', $broken, '-SelfTestNoTreeGuard')
$o2 = $r2.Out
Check 'CHECK2 the disarm switch took effect' ($o2 -match 'guard is DISARMED') 'the disarm banner is missing'
if ($r2.Code -eq 0) {
  Write-Output '  ok   exit code is zero -- without the guard, the empty tree reads as clean'
  Write-Output '       (this is the 2026-10-20 behaviour, reproduced on demand)'
} else {
  Write-Output ('  FAIL exit code is ' + $r2.Code + ' -- something other than the guard is failing the capture')
  $failed += 'CHECK2 exit code'
}

# --- CHECK 3  no false positive ------------------------------------------------
Write-Output ''
Write-Output 'CHECK 3  the healthy capture must PASS -- the guard must not fire on a real tree'
$r3 = Run-Scan @('-Replay', $healthy)
$o3 = $r3.Out
if ($r3.Code -eq 0) {
  Write-Output '  ok   exit code is zero'
} else {
  Write-Output ('  FAIL exit code is ' + $r3.Code)
  $failed += 'CHECK3 exit code'
}
Check 'CHECK3 the healthy tree was read, not empty' ($o3 -match 'scanned 68 files') 'the healthy capture did not report 68 files'
Check 'CHECK3 the healthy capture is reported clean' ($o3 -match 'REPLAY OK') 'the healthy capture did not reach REPLAY OK'

# --- CHECK 4  the live path cannot be disarmed --------------------------------
# The live path is the network path, and exercising it here would make a
# sub-second self-test depend on a registry download that has already timed
# out twice in one afternoon. So this one is pinned at the SOURCE level: the
# arming expression has to require $replaying, or the live gate could be
# disarmed by a stray flag.
Write-Output ''
Write-Output 'CHECK 4  the disarm switch must be reachable ONLY in replay mode'
if ($SkipSourcePin) {
  Write-Output '  skip (-SkipSourcePin)'
} else {
  $src = [System.IO.File]::ReadAllText($target)
  $arming = [regex]::Match($src, '(?m)^\s*\$guardOn\s*=\s*(.+)$')
  if (-not $arming.Success) {
    Write-Output '  FAIL no $guardOn assignment found in the target script'
    $failed += 'CHECK4 $guardOn not found'
  } else {
    $expr = $arming.Groups[1].Value
    Check 'CHECK4 the arming expression mentions $SelfTestNoTreeGuard' ($expr -match '\$SelfTestNoTreeGuard') ('got: ' + $expr)
    Check 'CHECK4 the arming expression requires $replaying' ($expr -match '\$replaying') ('got: ' + $expr)
  }
}

Write-Output ''
if ($failed.Count -gt 0) {
  Write-Output ('SELF-TEST FAILED: ' + $failed.Count + ' check(s) red.')
  $failed | ForEach-Object { Write-Output ('  - ' + $_) }
  exit 1
}
Write-Output 'SELF-TEST OK: the empty-tree capture fails, the healthy capture passes,'
Write-Output '              and the guard is what makes the difference.'
exit 0

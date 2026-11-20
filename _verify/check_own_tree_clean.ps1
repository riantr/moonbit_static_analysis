param([switch]$SelfTest, [string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE FALSE-POSITIVE PIN, AS A GATE.
#
# WHY THIS EXISTS. `_verify/QA_TODO.md` §1 recorded twelve actionable findings
# on this tree -- and every one of them was a FALSE POSITIVE: the analyzer
# reading its own documentation of the suppression syntax, and its own test
# fixtures for that syntax, as live suppressions. The invented family ids were
# English words.
#
# 0613 FIXED the two rules that produced them, and it put the pin where the
# release gate already measures the tree: the self-scan stage asserts
# `actionable == 0` under `--honor-nosec`. That assertion is the gate that
# would have caught the twelve, and it is the strictest reading of the tree --
# even with every suppression honoured, the analyzer finds nothing here that
# is not a defect.
#
# AND THE CLAIM IS NOT DUPLICATED. The release gate's self-scan stage reads the
# actionable count out of ITS OWN scan, because it needs that scan for the
# notice table, the file set and the SSA cost as well. This gate scans the
# same tree and holds the SAME pin, and the release gate runs BOTH -- so the
# number is produced by the analyzer once per scan and the VERDICT is checked
# here, in one place, by a gate a reader can run on its own:
#
#     powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_own_tree_clean.ps1
#
# A false positive is FIXED, never pinned. This gate does not assert that the
# twelve are still there -- it asserts that there are NONE, and that the
# assertion is capable of going red.
#
# AND THAT LAST PART IS THE POINT. A gate that has never been shown to go red
# is a comment. So the -SelfTest switch copies the tree's scannable files,
# checks that the copy is FAITHFUL (it must read the same files and produce
# the same SUMMARY as the tree itself), and then plants a defect in the copy
# and requires the count to move:
#
#   * THE CONTROL. The untouched copy reads `actionable = 0`.
#   * THE DEFECT. A stale suppression -- the very family 0613 fixed -- is
#     planted in the copy, and the count must become non-zero.
#
# The planted defect is a stale suppression rather than a planted bug because
# that is what the pin is FOR: the twelve were stale suppressions that the
# analyzer read as live ones. A pin that cannot see one of those cannot see
# the twelve.
#
# THE REPOSITORY IS NOT TOUCHED. The copy is under %TEMP% and the analyzer
# (the wasm) is the thing being tested, not the thing being copied.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_own_tree_clean.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_own_tree_clean.ps1 -SelfTest

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'

# THE SOURCE-KINDS THE ANALYZER READS. The same five the release gate's own
# file-set row names, read out of `src/sa/main.mbt`: .mbt, .mbti, .mbtp,
# .mbt.md and .mbtx.
$script:sourceKinds = @('.mbt', '.mbti', '.mbtp', '.mbt.md', '.mbtx')

# THE SCAN. One walk of one tree, through the local wasm.
function Scan-Tree {
  param([string]$Path, [string]$Exclude = '')
  $tmp = Join-Path $env:TEMP ('otc_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $out = Join-Path $tmp 'o.txt'
  $err = Join-Path $tmp 'o.err'
  $a = @($wasm, $Path, '--extern-iface-dir', $repos, '--no-auto-fetch-deps',
         '--findings-shown-per-file', '1000000', '--honor-nosec')
  if ($Exclude -ne '') { $a += @('--exclude', $Exclude) }
  Start-Process -FilePath $moonrun -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  $text = [System.IO.File]::ReadAllText($out)
  $errText = [System.IO.File]::ReadAllText($err)
  $sum = ''
  $files = 0
  $parsed = 0
  $act = -1
  foreach ($l in ($text -split "`r?`n")) {
    if ($l -match '^SUMMARY\t') {
      $sum = $l
      $files = [int]([regex]::Match($l, 'files=(\d+)').Groups[1].Value)
      $parsed = [int]([regex]::Match($l, 'parsed=(\d+)').Groups[1].Value)
      $act = [int]([regex]::Match($l, 'actionable=(\d+)').Groups[1].Value)
    }
  }
  return [pscustomobject]@{ Text = $text; Err = $errText; Summary = $sum; Files = $files; Parsed = $parsed; Actionable = $act }
}

# THE FILES THE SCAN READS, enumerated from the tree. Used to build the
# copy, so that the copy is the tree and not an approximation of it.
function Get-ScannableFiles {
  param([string]$Base)
  $out = @()
  $all = @(Get-ChildItem -LiteralPath $Base -Recurse -File -ErrorAction SilentlyContinue)
  foreach ($f in $all) {
    $rel = $f.FullName.Substring($Base.Length).TrimStart('\', '/') -replace '\\', '/'
    # `_verify` is excluded from the scan, and a directory whose name starts
    # with `.` is skipped by the toolchain -- `.repos` is a REGISTRY CACHE,
    # not this project's source, and scanning it would read other packages'
    # code as if it were ours.
    if ($rel -match '^_verify/') { continue }
    if ($rel -match '(^|/)\.') { continue }
    $isSource = $false
    foreach ($k in $script:sourceKinds) { if ($f.Name.EndsWith($k)) { $isSource = $true } }
    if (-not $isSource) { continue }
    $out += [pscustomobject]@{ Full = $f.FullName; Rel = $rel }
  }
  return $out
}

# A COPY of the tree's scannable files, under %TEMP%, with the same relative
# paths.
function Copy-ScannableTree {
  param([string]$Base, [string]$Dst)
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null
  foreach ($f in @(Get-ScannableFiles $Base)) {
    $to = Join-Path $Dst ($f.Rel -replace '/', '\')
    $dir = Split-Path -Parent $to
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item -LiteralPath $f.Full -Destination $to -Force
  }
  return @(Get-ScannableFiles $Dst).Count
}

# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $wasm)) {
  Write-Output 'ABORT: no wasm artifact. Build it first.'
  exit 1
}

if (-not $SelfTest) {
  Write-Output '=== the false-positive pin: this tree has no actionable finding ==='
  $sw = Scan-Tree $root '_verify'
  if ($sw.Err.Trim() -ne '') {
    Write-Output ('  FAIL: the scan wrote to stderr: ' + $sw.Err.Trim())
    exit 1
  }
  if ($sw.Summary -eq '') {
    Write-Output '  FAIL: the scan printed no SUMMARY. A scan that did not run is not a clean scan.'
    exit 1
  }
  Write-Output ('  ' + $sw.Summary)
  if ($sw.Actionable -ne 0) {
    Write-Output ('  FAIL: actionable is not 0 -- it is ' + $sw.Actionable + ', and the scan HONOURED `// nosec`, so every one of these is a finding on this tree that is not a defect.')
    exit 1
  }
  if ($sw.Files -ne $sw.Parsed) {
    Write-Output ('  FAIL: parsed ' + $sw.Parsed + ' of ' + $sw.Files + ' files.')
    exit 1
  }
  Write-Output ('  ' + $sw.Files + '/' + $sw.Files + ' parsed, actionable 0 (with `// nosec` honoured)')
  Write-Output 'TREE CLEAN OK: the analyzer finds nothing in this tree that is not a defect, even with every suppression honoured.'
  exit 0
}

# --- the self-test ------------------------------------------------------------
Write-Output '=== the false-positive pin, shown to go red ==='
$base = Join-Path $env:TEMP ('otcself_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $base | Out-Null
$copy = Join-Path $base 'tree'
$n = Copy-ScannableTree $root $copy
Write-Output ('  the copy holds ' + $n + ' scannable files')

$bad = 0

# THE CONTROL. The untouched copy must read `actionable = 0`, AND it must read
# the same files as the tree. A copy that read fewer files would make the
# defect below look like it worked for the wrong reason.
Write-Output ''
Write-Output '--- the control: the copy must be the tree ---'
$treeSw = Scan-Tree $root '_verify'
$ctlSw = Scan-Tree $copy
Write-Output ('  the tree : ' + $treeSw.Summary)
Write-Output ('  the copy : ' + $ctlSw.Summary)
if ($ctlSw.Files -eq $treeSw.Files -and $ctlSw.Parsed -eq $treeSw.Parsed) {
  Write-Output ('  OK: the copy reads the same ' + $ctlSw.Files + ' files and parses the same ' + $ctlSw.Parsed + '.')
} else {
  Write-Output '  FAIL: the copy is not the tree -- it reads a different number of files, so a defect planted in it would prove nothing.'
  $bad++
}
if ($ctlSw.Actionable -eq 0) {
  Write-Output '  OK: the unmutated copy is clean.'
} else {
  Write-Output ('  FAIL: the unmutated copy already reads actionable = ' + $ctlSw.Actionable + '.')
  $bad++
}

# THE DEFECT. A stale suppression -- the family 0613 fixed -- planted in the
# copy. It must move the count.
Write-Output ''
Write-Output '--- the defect: a stale suppression planted in the copy ---'
$planted = Join-Path $copy 'src\qa0615_stale_suppression.mbt'
$plantedBody = @(
  'fn qa0615_f() -> Int {'
  '  // nosec MSA-999'
  '  let qa0615_ok = 1'
  '  qa0615_ok'
  '}'
  'qa0615_f()'
) -join "`n"
[System.IO.File]::WriteAllText($planted, ($plantedBody + "`n"), (New-Object System.Text.UTF8Encoding($false)))
$defSw = Scan-Tree $copy
Write-Output ('  the copy with the defect : ' + $defSw.Summary)
if ($defSw.Actionable -gt 0) {
  Write-Output ('  OK: the count moved to ' + $defSw.Actionable + ', so the pin is not vacuous -- it can go red.')
} else {
  Write-Output '  FAIL: the count did NOT move. A pin that cannot go red is a comment.'
  $bad++
}

Write-Output ''
if ($bad -eq 0) {
  Write-Output 'SELFTEST OK: the copy is the tree, it reads clean, and a planted stale suppression makes the count move.'
  exit 0
}
Write-Output ('SELFTEST FAILED: ' + $bad + ' check(s) did not hold.')
exit 1

# Coverage-loss A/B for the uncommitted 0466 change.
#
# WHAT THIS PROVES, AND WHAT IT CANNOT
# -----------------------------------
# The concern: 0466 parses MORE in async and proton than 0465 did (async
# 330 -> 337 files parsed, proton 115 -> 116, proton withheld 323 -> 59). A
# move that size must not be pinned on inference, so this builds BOTH parsers
# from ONE tree and diffs how far the scanner reads in every single file of
# all six corpora.
#
# It answers one question only: did any file get read LESS? It does not claim
# the finding counts are correct -- only that nothing was lost.
#
# RESTORING HEAD
# --------------
# `git checkout HEAD -- <path>` is deliberately NOT used anywhere here: it can
# destroy staged work, and this repo forbids it on a dirty tree. `git cat-file
# blob HEAD:<path>` reads the committed blob without touching the index or the
# working state, and the redirect runs under cmd.exe because PowerShell's `>`
# re-encodes as UTF-16 and mangles the em dashes in these source comments.
#
# The 0466 test files are moved aside for the HEAD build because they pin
# behaviour the HEAD (0465) parser does not have; leaving them in place would
# make the HEAD build fail for a reason that has nothing to do with the
# measurement. This list is NOT optional bookkeeping: a new test file left out
# of it fails the HEAD build, and a build failure is indistinguishable from a
# measurement problem unless you already know to look for it.

# Native tools here write progress to stderr (git's LF/CRLF warning, moon's
# task log). With ErrorActionPreference=Stop that stderr becomes a terminating
# NativeCommandError, so the script aborts on a harmless warning. Exit codes
# are checked explicitly instead.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$moon  = 'C:\Users\31379\.moon\bin\moon.exe'
$ver   = Join-Path $root '_verify'

# Pinned corpus paths -- identical to release.ps1 $TARGETS. Note async: the
# bare `.repos\moonbitlang\async` holds three versions and must never be used.
$TARGETS = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
}

# Every file the change touches, sources AND tests. The tests are here because the
# "HEAD" build compiles the whole package: a test that pins 0466 behaviour
# would fail to build against the HEAD parser, and the build failure would look
# exactly like a measurement problem. BOTH of the three test entries below are
# NOT in HEAD at all (0466 added them), which the restore step handles by
# leaving them absent -- and which the byte-comparison guard below has to
# tolerate rather than treat as a mismatch.
#
# 0466 touched no lexer/ast/types/interp file, so unlike the 0456+0457 list this
# one is three entries wide. Re-pointing this list is part of every increment:
# the previous list's stale entries are harmless (they restore to their own HEAD
# blob), but a MISSING new test file is fatal.
$CHANGED = @(
  'src/parser/parser.mbt',
  'src/parser/parser_0466_test.mbt',
  'src/pipeline/pipeline_0466_test.mbt'
)

function Build-Wasm {
  Push-Location $root
  try {
    $o = & $moon build --target wasm 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "wasm build failed`n$o" }
  } finally { Pop-Location }
}

function Save-Reach {
  param([string]$OutFile)
  $all = @()
  foreach ($k in $TARGETS.Keys) {
    $r = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ver 'reach_map.ps1') $TARGETS[$k]
    $rows = @($r | Where-Object { $_ -match '^REACH' })
    # A corpus whose map is not total cannot support a no-loss claim, so this
    # is a hard stop rather than a warning.
    $hdr = ($r | Where-Object { $_ -match '^SCANNED' })
    $scanned = [int](([regex]::Match(($r -join "`n"), '(?m)^SCANNED\s+(\d+)')).Groups[1].Value)
    if ($rows.Count -ne $scanned) {
      throw ("reach map for {0} is not total: {1} rows vs SCANNED {2}" -f $k, $rows.Count, $scanned)
    }
    foreach ($row in $rows) { $all += ($k + "`t" + $row.Substring(6)) }
    Write-Host ("  {0,-16} {1,4} files mapped (total)" -f $k, $scanned)
  }
  [IO.File]::WriteAllText((Join-Path $ver $OutFile), (($all | Sort-Object) -join "`n"), (New-Object Text.UTF8Encoding($false)))
}

function Restore-Working {
  foreach ($p in $CHANGED) {
    $bak = Join-Path $ver ('_work_' + ($p -replace '/', '_'))
    if (Test-Path $bak) { Copy-Item $bak (Join-Path $root $p) -Force }
  }
}

Write-Host 'coverage A/B -- 0466'
Write-Host ('  repo   : ' + $root)
Write-Host ('  HEAD   : ' + ((git rev-parse --short HEAD).Trim()))
Write-Host ('  change : ' + ((git diff --stat src/parser/parser.mbt) -replace "`r?`n", ' '))
Write-Host ''

# --- stash the working state ----------------------------------------------------
foreach ($p in $CHANGED) {
  $bak = Join-Path $ver ('_work_' + ($p -replace '/', '_'))
  if (Test-Path (Join-Path $root $p)) { Copy-Item (Join-Path $root $p) $bak -Force }
}

# Whatever happens -- including a build throwing three lines down -- the
# working tree must come back to the change. A finally block is the only
# thing standing between a failed measurement and a destroyed day of work.
try {
  Write-Host '1. build HEAD parser, map reach on all six corpora'
  Push-Location $root
  try {
    foreach ($p in $CHANGED) {
      $dest = Join-Path $root $p
      if (Test-Path $dest) { [IO.File]::Delete($dest) }
      $tmp = Join-Path $ver '_head_tmp'
      # Delete the scratch file FIRST. An earlier version of this script ran
      # `git cat-file` on a path that does not exist in HEAD (the new test
      # file), git failed, and the STALE scratch file left over from the
      # previous iteration was copied into place -- so a HEAD build silently
      # contained the previous file's contents. Removing it up front makes
      # that failure mode impossible rather than merely noticed.
      if (Test-Path $tmp) { [IO.File]::Delete($tmp) }
      cmd.exe /c "git cat-file blob HEAD:$p > _verify\_head_tmp" | Out-Null
      if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) { continue }  # not in HEAD: leave absent
      Copy-Item $tmp $dest -Force
    }
  } finally { Pop-Location }

  # Positive control on the restore step. If parser.mbt on disk is not
  # byte-identical to the HEAD blob, the "HEAD" measurement is not HEAD and
  # the whole comparison is void -- so this is checked, not assumed.
  Push-Location $root
  try {
    $onDisk = (cmd.exe /c "git hash-object src/parser/parser.mbt").Trim()
    $inHead = (cmd.exe /c "git rev-parse HEAD:src/parser/parser.mbt").Trim()
    if ($onDisk -ne $inHead) { throw "parser.mbt is NOT the HEAD blob ($onDisk vs $inHead) -- A/B void" }
    # Every file the change touches must be byte-identical to HEAD before the
    # "HEAD" build, not just parser.mbt. This used to assert that one specific
    # test file was ABSENT, which was correct only while that file was new --
    # and it became a false check the moment the file was committed, which is
    # exactly the kind of stale guard that stops meaning anything.
    foreach ($p in $CHANGED) {
      # A file that is NOT in HEAD has no blob to match, and its correct HEAD
      # state is ABSENCE. `git rev-parse` prints its own error and leaves the
      # variable empty, so an unguarded comparison here would read "" as a
      # mismatch and void an A/B that is in fact correct.
      cmd.exe /c "git rev-parse HEAD:$p > NUL 2>&1" | Out-Null
      if ($LASTEXITCODE -ne 0) {
        if (Test-Path (Join-Path $root $p)) { throw "$p is not in HEAD but is on disk -- A/B void" }
        continue
      }
      $o = (cmd.exe /c "git hash-object $p").Trim()
      $h = (cmd.exe /c "git rev-parse HEAD:$p").Trim()
      if ($o -ne $h) { throw "$p is NOT the HEAD blob ($o vs $h) -- A/B void" }
    }
    Write-Host ('   restore verified: ' + $CHANGED.Count + ' files match HEAD (or are absent from it)')
  } finally { Pop-Location }

  Build-Wasm
  Save-Reach '_ab2_head.txt'

  Write-Host ''
  Write-Host '2. restore the change, build it, map reach again'
  Restore-Working
  Build-Wasm
  Save-Reach '_ab2_fixed.txt'

  Write-Host ''
  Write-Host 'done -- run ab_0456_0457_diff.ps1 to classify'
} finally {
  Restore-Working
  foreach ($p in $CHANGED) {
    $b = Join-Path $ver ('_work_' + ($p -replace '/', '_'))
    if (Test-Path $b) { Write-Host ('  restored ' + $p) }
  }
}

# 0.4.29 — the PUBLISHED package must scan its own shipped source clean.
#
# WHY THIS CHECK EXISTS, twice over.
#
# 1. It has caught two shipped defects that nothing else could. 0.4.9 shipped an
#    artifact named `..._unknown_....mmd` whose header read `version=unknown`,
#    because the documented `@latest` self-scan names no version. 0.4.10 shipped
#    `actionable=2` where 0.4.8 had been clean -- two real names in provenance.mbt.
#    Neither was visible to a working-tree scan: the first is about the OUTPUT
#    format, the second appeared only once a fix let the parser reach code that a
#    dropped `if` expression had been hiding.
#
# 2. It is the only check that exercises the real delivery path: mooncakes compiles
#    the artifact server-side, and `moonx` fetches and runs THAT. A green local
#    `moon test` says nothing about whether the shipped wasm works.
#
# TWO THINGS THIS SCRIPT DELIBERATELY DOES NOT DO.
#
#   It runs OUTSIDE the repository. `moonx` materialises the package into
#   `.repos/<owner>/<name>/<ver>/` relative to the CURRENT DIRECTORY, and the
#   project's own `.repos` is what `--extern-iface-dir` feeds the corpus A/B.
#   Writing the analyzer into that tree would add its names to the cross-file
#   interface table and silently change every corpus baseline measured since.
#   This was a real hazard, not a hypothetical one: the first draft of this script
#   would have run in the repo root.
#
#   It does not treat `@latest` as the target. `@latest` is whatever the registry
#   currently advertises, so a stale-but-successful resolution would scan a
#   DIFFERENT package and still print `actionable=0`. The version is asserted
#   against `moon.mod` before any finding count is believed. Pass `-UseLatest` to
#   check the advertised-latest path instead, which is what the 0.4.9 note is about.
#
# ParseError lines are NOT counted as defects. They are the subset-coverage
# notices -- `struct` / `enum` / `derive` / `match` bodies are outside the analyzed
# subset, and saying so is the notice's job. `actionable=0` alongside a large
# notice count is the expected shape, not a contradiction.
#
# EMPTY OUTPUT IS A FAILURE, NOT A ZERO. Six 0-byte dumps once printed a line per
# corpus and read as a clean result.
#
# AND A SUMMARY OVER AN EMPTY TREE IS ALSO A FAILURE. 2026-10-20: the registry
# download timed out, the package directory was created empty, the scanner printed
# `SCANNED 0 files` together with a real `SUMMARY actionable=0`, and this stage
# reported GATE OK. The "EMPTY OUTPUT" note above catches a scan that printed
# nothing; the tree-presence assertions below catch a scan that printed a summary
# and read nothing at all.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\selfscan_published.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\selfscan_published.ps1 -UseLatest
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\selfscan_published.ps1 -Replay <path-to-run.out>
#     Replays a CAPTURED scan instead of fetching one. The version assertion is
#     informational in that mode; the tree-presence guard is the thing under test.
#     `-SelfTestNoTreeGuard` additionally disarms that guard, and is honoured ONLY
#     in replay mode.
param(
  [switch]$UseLatest,
  # Audit a SPECIFIC version instead of the one in moon.mod. Exists so the version
  # assertion has a negative control: without it, nothing here can be shown to
  # fail, and a gate that cannot fail is a comment. `-Coordinate @0.4.28` against
  # a moon.mod of 0.4.29 must FAIL, and that failure is the evidence.
  [string]$Coordinate = '',
  # Replay a CAPTURED `run.out` instead of invoking `moonx`. Exists so the
  # "the tree is really there" guard can be shown to go RED: the capture of a
  # scan whose package download TIMED OUT reads ZERO files, prints actionable=0
  # and passes every other check, and it is a real artefact of 2026-10-20 rather
  # than a fixture written to make the guard look good. The version assertion is
  # INFORMATIONAL in replay mode -- a replay may carry any version -- and the
  # tree-presence guard is the thing under test.
  [string]$Replay = '',
  # DISARM the tree-presence guard. Honoured ONLY together with `-Replay`: the LIVE
  # path can never be disarmed, so this cannot weaken the real gate. It exists so
  # the self-test can show that the guard is the CAUSE of the empty-tree failure
  # and not a passenger in it -- the same capture must pass with the guard off.
  [switch]$SelfTestNoTreeGuard
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot

$moonmod = [System.IO.File]::ReadAllText((Join-Path $root 'moon.mod'))
$mv = ([regex]::Match($moonmod, '(?m)^version\s*=\s*"([^"]+)"')).Groups[1].Value
if ($mv -eq '') { Write-Output 'ABORT: cannot read version from moon.mod.'; exit 1 }

$coordinate = if ($Coordinate -ne '') { $Coordinate } elseif ($UseLatest) { '@latest' } else { '@' + $mv }
$self = 'riantr/moonbit_static_analysis'
Write-Output ("package : " + $self + $coordinate)
Write-Output ("moon.mod: " + $mv)
Write-Output ''

$replaying = ($Replay -ne '')
$scratch = ''
if ($replaying) {
  # A CAPTURED scan. No `moonx`, no scratch directory, and the version assertion
  # below becomes INFORMATIONAL -- see the note there.
  Write-Output ('replaying a captured scan: ' + $Replay)
  if (-not (Test-Path -LiteralPath $Replay)) {
    Write-Output ('ABORT: the capture does not exist: ' + $Replay); exit 1
  }
  $out = [System.IO.File]::ReadAllText($Replay)
} else {
  $scratch = Join-Path $env:TEMP ('selfscan_' + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Force -Path $scratch | Out-Null
  $underRoot = $scratch.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
  if ($underRoot) { Write-Output ('ABORT: scratch dir is inside the repo: ' + $scratch); exit 1 }
  $o = Join-Path $scratch 'run.out'; $e = Join-Path $scratch 'run.err'
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  Start-Process -FilePath 'C:\Users\31379\.moon\bin\moonx.exe' `
    -ArgumentList @($self + $coordinate, $self + $coordinate) `
    -WorkingDirectory $scratch -RedirectStandardOutput $o -RedirectStandardError $e `
    -NoNewWindow -Wait | Out-Null
  $ErrorActionPreference = $prev
  $out = [System.IO.File]::ReadAllText($o)
}
if ([string]::IsNullOrWhiteSpace($out)) {
  Write-Output 'ABORT: the scan produced no output. That is not a clean scan.'
  if ($replaying) {
    Write-Output ('  the captured file is empty: ' + $Replay)
  } else {
    Write-Output ("  stderr: " + ([System.IO.File]::ReadAllText($e) -split "`r?`n" | Select-Object -First 3))
  }
  exit 1
}

$fail = 0
$lines = $out -split "`r?`n"

# --- the tree actually scanned must be the version we asked for ----------------
# Read from `SCANNED n files under .repos/<owner>/<name>/<version>`, and it has to
# be that line: the first draft of this check asserted on `Latest version ... is X`,
# which moonx prints ONLY when the coordinate is `@latest`. Asking for an explicit
# `@0.4.29` prints `Fetching ...@0.4.29 to ...` and a `TARGET` line instead, so the
# assertion read an absent line as an empty resolution and failed a healthy release.
# The scanned path is the one piece of evidence present in BOTH modes, and it is
# also the stronger claim: it names the directory the findings came from.
$scannedLine = ([regex]::Match($out, '(?m)^SCANNED\s+(\d+) files under (.+)$'))
$scannedN = $scannedLine.Groups[1].Value
$scannedPath = $scannedLine.Groups[2].Value.Trim()
$scannedVer = ($scannedPath -split '[\\/]')[-1]
Write-Output ('  scanned ' + $scannedN + ' files under ' + $scannedPath)
if ($replaying) {
  # INFORMATIONAL in replay mode. A capture may be of ANY version -- the healthy
  # one on hand is a 0.4.29 scan taken before 0.4.30 was cut -- and asserting it
  # against today's moon.mod would fail a healthy artefact for the WRONG reason
  # and hide the guard this mode exists to exercise. The version claim is made by
  # the LIVE path, against the version that was actually asked for; a replay only
  # exercises the tree-presence guard below.
  if ($scannedVer -eq $mv) {
    Write-Output ('  ok  the tree scanned is ' + $mv)
  } else {
    Write-Output ('  note  the replayed tree is ' + $scannedVer + ', this repo is ' + $mv + ' -- informational in replay mode.')
  }
} elseif (-not $UseLatest) {
  if ($scannedVer -eq $mv) {
    Write-Output ('  ok  the tree scanned is ' + $mv)
  } else {
    Write-Output ('FAIL: asked for ' + $mv + ', but the scan read version ''' + $scannedVer + '''.')
    Write-Output '      A scan of a DIFFERENT package would still be able to print actionable=0.'
    $fail++
  }
} else {
  $latest = ([regex]::Match($out, 'Latest version of [^\s]+ is ([0-9][^\s]*)')).Groups[1].Value
  Write-Output ("  ok  @latest resolved to " + $latest + " and its tree is " + $scannedVer)
}

# --- the tree must ACTUALLY BE THERE -------------------------------------------
# A scan of a tree that was never fetched reads ZERO files, prints `actionable=0`,
# and passes every check below -- VACUOUSLY. This is the same defect the "EMPTY
# OUTPUT IS A FAILURE" note above describes, one level down: that guard catches a
# scan that printed nothing, and this one catches a scan that printed a SUMMARY
# and read nothing at all.
#
# Measured 2026-10-20, cutting 0.4.30: the registry download TIMED OUT, so the
# package directory was created EMPTY, the scanner reported `SCANNED 0 files` and
# `SKIP .../moon.mod unreadable: OSError(...)`, and this stage reported GATE OK.
# A green stage on a scan of nothing is the worst shape a gate can have.
#
# Two assertions, both on the SCANNER's own output rather than on `moonx`'s
# wording: the scanned file count must be GREATER THAN ZERO, and the package's own
# `moon.mod` must not be in the SKIP list. The scanner prints `SKIP <path>
# unreadable: ...` for a file it could not read, and that one file is the proof
# that the tree is really there.
#
# `-SelfTestNoTreeGuard` disarms both of them, and ONLY in replay mode. The
# self-test uses it to show that the guard is the CAUSE of the failure rather
# than a passenger in it: the same broken capture has to PASS with the guard off.
# The live path cannot be disarmed, so this cannot weaken the real gate.
$guardOn = -not ($SelfTestNoTreeGuard -and $replaying)
if ($SelfTestNoTreeGuard) {
  if ($guardOn) {
    Write-Output '  ****  SELF-TEST: -SelfTestNoTreeGuard was passed, but the LIVE path cannot be disarmed. The guard is ARMED.  ****'
  } else {
    Write-Output '  ****  SELF-TEST: the tree-presence guard is DISARMED. This cannot happen on the LIVE path.  ****'
  }
}
if (-not $guardOn) {
  Write-Output '  (guard disarmed -- the empty tree will be reported as clean)'
} else {
  $scannedNInt = 0
  [void][int]::TryParse($scannedN, [ref]$scannedNInt)
  if ($scannedNInt -le 0) {
    Write-Output 'FAIL: the scan read ZERO files -- the package was not fetched, or its tree is empty.'
    $fail++
  }
  $modRel = ($scannedPath -replace '\\', '/') + '/moon.mod'
  $skippedMod = @($lines | Where-Object { $_.StartsWith('SKIP') -and $_.Contains($modRel) })
  if ($skippedMod.Count -gt 0) {
    Write-Output 'FAIL: the package''s own moon.mod was SKIPped -- the tree is not really there.'
    $skippedMod | Select-Object -First 3 | ForEach-Object { Write-Output ('      ' + $_) }
    $fail++
  }
}

# --- coverage must not regress --------------------------------------------------
$parsed = ([regex]::Match($out, '(?m)^PARSED\s+(\d+)/(\d+) files understood \(([0-9.]+)%\)'))
if ($parsed.Success) {
  $p = $parsed.Groups[1].Value; $tot = $parsed.Groups[2].Value
  Write-Output ("  ok  parsed " + $p + "/" + $tot + " files")
  if ($p -ne $tot) { Write-Output 'FAIL: a file was read only up to its first parse error.'; $fail++ }
} else {
  Write-Output 'FAIL: no PARSED line in the output.'; $fail++
}

# --- the actual assertion ------------------------------------------------------
$sum = ([regex]::Match($out, '(?m)^SUMMARY.*$')).Value
Write-Output ('  ' + $sum)
$actionable = ([regex]::Match($sum, 'actionable=(\d+)')).Groups[1].Value
if ($actionable -ne '0') {
  Write-Output ('FAIL: actionable=' + $actionable + ' on the analyzer''s own source.')
  $bad = @($lines | Where-Object { $_ -match ' - error: ' -and $_ -notmatch 'ParseError' })
  $bad | Select-Object -First 25 | ForEach-Object { '      ' + $_ }
  $fail++
} else {
  Write-Output '  ok  actionable = 0'
}

# --- belt and braces: no non-ParseError error line at all -----------------------
$bad = @($lines | Where-Object { $_ -match ' - error: ' -and $_ -notmatch 'ParseError' })
if ($bad.Count -gt 0) {
  Write-Output ('FAIL: ' + $bad.Count + ' non-ParseError error line(s) in the report.')
  $fail++
}

Write-Output ''
if (-not $replaying) { Write-Output ("scratch kept for inspection: " + $scratch) }
if ($fail -gt 0) { Write-Output ("ABORT: {0} check(s) failed." -f $fail); exit 1 }
if ($replaying) {
  Write-Output ("REPLAY OK: the captured scan passes every check (tree " + $scannedVer + ", " + $scannedN + " files).")
  Write-Output '            This says the CAPTURE is clean -- it is not a claim that a package was fetched just now.'
} elseif ($UseLatest) {
  Write-Output ("GATE OK: @latest scanned itself clean. NOTE: @latest is not pinned -- " +
    "this proves the advertised latest is clean, not that it is the version just released.")
} else {
  Write-Output ("GATE OK: the published " + $mv + " scans its own shipped source clean.")
}
exit 0
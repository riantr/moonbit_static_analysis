param([switch]$SelfTest, [switch]$Live, [string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE PUBLISHED SCAN RECORD, as a gate.
#
# WHY THIS EXISTS. Both READMEs publish a MEASUREMENT: "Measured on the published
# `riantr/moonbit_static_analysis@0.6.0` over the published `riantr/LunaFlow@0.1.37`
# (76 files): 73 parsed (96.0%), 3 actionable". That sentence is the reader's only
# evidence that this tool does anything on somebody ELSE's code -- the tool's own
# tree is measured by a hundred other gates, but the LunaFlow row is measured by
# NOTHING, and it was a PROSE NUMBER until this gate existed.
#
# MEASURED 0650, and this is the defect this gate was built for, in the shape
# this repository keeps meeting:
#
#   * The README published a number that no gate could check. `check_readme_links.ps1`
#     derives the corpus numbers from release.ps1's pin table -- but the LUNAFLOW row
#     was not in that table, so it was not derived, so it was not checked. A number
#     that is published but not pinned is a number that rots silently.
#   * The row was written by hand, from a scan that was run ONCE, in a scratch
#     directory, with a command nobody could re-run without knowing the trick:
#     `moonx` creates `.repos/` under the CURRENT directory, and this repository's
#     corpus A/B READS `.repos/`. A scan run here writes the fetched package into
#     the very tree the measurements are taken against. The README now says so, and
#     this gate REFUSES to run inside the repository.
#   * The row named `moonbitlang/core` -- 1766 files, 1705 parsed, 30 actionable --
#     and that record was stale in a way nobody noticed: it had been true for a
#     release and a half, and the corpus it named is pinned by other gates for
#     other reasons, so it could not simply be deleted. It was a SECOND tree's
#     measurement sitting in a place that read like this tree's.
#
# => 判据: A PUBLISHED MEASUREMENT IS THREE THINGS -- THE EVIDENCE, THE PIN, AND
# THE DOCUMENT -- and it is only a measurement when all three agree. The evidence is
# the captured output of the scan; the pin is the set of numbers release.ps1 holds;
# the document is the two READMEs. This gate checks all three against each other,
# and it re-measures the whole thing against the PUBLISHED packages when it is
# allowed to.
#
# WHAT IT CHECKS, in the order the claims get stronger:
#
#   1. THE EVIDENCE EXISTS and parses. The captured output of the scan is committed
#      at `_verify\fixtures\lunaflow_scan_<analyzer>_<corpus>.out` -- the file name
#      carries BOTH versions, because the analyzer's version is NOT in the output:
#      `moonx` does not say which version of the analyzer it ran (MEASURED: its
#      output names the TARGET and the corpus, and nothing else). A capture that
#      does not say which analyzer produced it is not evidence of anything.
#   2. THE EVIDENCE AGREES WITH THE PIN, field by field, and the capture's own
#      INTERNAL invariants hold -- `actionable + notices + unreliable = total`,
#      `parsed + notparse = files`, the per-file rows sum to the summary, and the
#      three actionable findings are all in ONE file of the corpus's own fixtures.
#   3. THE PIN IS ONE PLACE. The numbers live in release.ps1's pin table and are
#      DERIVED here, exactly the way `check_readme_links.ps1` derives the corpus
#      numbers. A number written down twice is a number that will disagree with
#      itself.
#   4. BOTH READMEs QUOTE THE PIN. Not "contain a number somewhere" -- the exact
#      sentence fragments, with the numbers interpolated from the pin.
#   5. (-Live) THE PUBLISHED PACKAGES STILL MEASURE THE SAME. The scan is re-run
#      against the registry, OUTSIDE this repository, and the numbers must match.
#      And the registry's `latest_version` for BOTH packages must still be the
#      pinned one -- because a record that names versions which have moved on is
#      stale even when the numbers happen not to have moved.
#
# THE COMPILER'S ROW IS PINNED SEPARATELY, and it is the compiler's measurement,
# not this tool's: `moon check --target all` over the same fetched tree reports
# "93 warnings, 0 errors". It is measured with the core this repository is gated
# against (`$CORE_REGATED`), so the live check compares it only when the running
# compiler IS that core -- otherwise the row is UNKNOWN, loudly, because the
# compiler's diagnostics move with the compiler and that is not a defect HERE.
#
# THE THREE OUTCOMES, and they are not the same thing:
#
#   exit 0  OK          -- every claim holds.
#   exit 1  FAILED      -- a claim is FALSE. The numbers moved, the evidence and
#                          the pin disagree, or the READMEs quote something else.
#   exit 2  UNKNOWN     -- the claim could not be MEASURED (no network, no
#                          `moonx`, a toolchain that is not the pinned one). An
#                          unknown is not a pass and it is not a failure: it is
#                          the absence of a measurement, and the release gate
#                          says so rather than pretending.
#
# THE -SelfTest SWITCH builds a FIXTURE in %TEMP% -- a copy of the pin, of the
# capture and of the two READMEs -- and requires it to go RED twice: once with a
# number changed in the EVIDENCE, and once with a number changed in the DOCUMENT.
# A gate that has never been shown to go red is a comment.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_lunaflow_scan.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_lunaflow_scan.ps1 -Live
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_lunaflow_scan.ps1 -SelfTest

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$fail = 0
$unknown = 0

# ---------------------------------------------------------------- the parsing ---
# THE SCAN OUTPUT IS LINE-ORIENTED AND TAB-SEPARATED, and the fields are the
# analyzer's own. The parser reads the FIELDS, never the prose: the per-file rows
# are `STATUS<TAB>kind<TAB>defects=N<TAB>notices=N<TAB>unchecked=N<TAB>...<TAB>path`,
# and the path is the LAST field, because `PARTIAL` carries a free-text field
# ("read up to line 154, 19 after it not shown") between the counters and it.
function Read-ScanOutput {
  param([string[]]$Lines)
  $res = [ordered]@{}
  $rows = @()
  $bykind = @()
  foreach ($l in $Lines) {
    if ($l -match '^SUMMARY\tfiles=(\d+)\tparsed=(\d+)\tactionable=(\d+)\tnotices=(\d+)\tunreliable=(\d+)\twithheld=(\d+)\tunchecked=(\d+)\ttotal=(\d+)') {
      $res['files'] = [int]$Matches[1]
      $res['parsed'] = [int]$Matches[2]
      $res['actionable'] = [int]$Matches[3]
      $res['notices'] = [int]$Matches[4]
      $res['unreliable'] = [int]$Matches[5]
      $res['withheld'] = [int]$Matches[6]
      $res['unchecked'] = [int]$Matches[7]
      $res['total'] = [int]$Matches[8]
      continue
    }
    if ($l -match '^PARSED\t(\d+)/(\d+) files understood \(([0-9.]+)%\)') {
      $res['parsed_line'] = $Matches[1] + '/' + $Matches[2]
      $res['pct'] = $Matches[3]
      continue
    }
    if ($l -match '^BYKIND\t(\S+)\tfiles=(\d+)\tparsed=(\d+)\tdefects=(\d+)\tnotices=(\d+)') {
      $bykind += [pscustomobject]@{
        Kind = $Matches[1]; Files = [int]$Matches[2]; Parsed = [int]$Matches[3]
        Defects = [int]$Matches[4]; Notices = [int]$Matches[5]
      }
      continue
    }
    if ($l -match '^NOTPARSE\t(\d+) files, (\d+) finding\(s\) withheld') {
      $res['notparse'] = [int]$Matches[1]
      $res['notparse_withheld'] = [int]$Matches[2]
      continue
    }
    if ($l -match '^TARGET\t(\S+)\t(\S+)') {
      $res['target'] = $Matches[1]
      $res['target_dir'] = $Matches[2]
      continue
    }
    $f = $l -split "`t"
    if ($f.Count -lt 4) { continue }
    if (@('CLEAN', 'FOUND', 'PARTIAL') -notcontains $f[0]) { continue }
    $d = 0; $n = 0; $u = 0
    for ($i = 2; $i -lt ($f.Count - 1); $i++) {
      if ($f[$i] -match '^defects=(\d+)$') { $d = [int]$Matches[1] }
      elseif ($f[$i] -match '^notices=(\d+)$') { $n = [int]$Matches[1] }
      elseif ($f[$i] -match '^unchecked=(\d+)$') { $u = [int]$Matches[1] }
    }
    $rows += [pscustomobject]@{
      Status = $f[0]; Kind = $f[1]; Defects = $d; Notices = $n; Unchecked = $u
      Path = $f[$f.Count - 1]
    }
  }
  $res['rows'] = $rows
  $res['bykind'] = $bykind
  return $res
}

# THE PIN. Read out of release.ps1, never written down here: a second copy of a
# number is a second place for it to be wrong.
function Get-Pins {
  param([string]$Tree)
  $rel = [System.IO.File]::ReadAllText((Sub-Path $Tree @('_verify', 'release.ps1')), [System.Text.Encoding]::UTF8)
  $scanM = [regex]::Match($rel, "\`$LUNAFLOW_SCAN\s*=\s*'([^']*)'")
  $chkM = [regex]::Match($rel, "\`$LUNAFLOW_MOONCHECK\s*=\s*'([^']*)'")
  $coreM = [regex]::Match($rel, "\`$CORE_REGATED\s*=\s*'([^']*)'")
  $out = [ordered]@{ ok = $false; scan = [ordered]@{}; check = [ordered]@{}; core = '' }
  if (-not ($scanM.Success -and $chkM.Success)) { return $out }
  foreach ($part in ($scanM.Groups[1].Value -split '\|')) {
    $kv = $part -split '=', 2
    if ($kv.Count -eq 2) { $out['scan'][$kv[0].Trim()] = $kv[1].Trim() }
  }
  foreach ($part in ($chkM.Groups[1].Value -split '\|')) {
    $kv = $part -split '=', 2
    if ($kv.Count -eq 2) { $out['check'][$kv[0].Trim()] = $kv[1].Trim() }
  }
  $out['core'] = if ($coreM.Success) { $coreM.Groups[1].Value } else { '' }
  $out['ok'] = $true
  return $out
}

# THE PATHS ARE BUILT, NEVER TYPED. A backslash is a SEPARATOR on Windows and
# an ordinary CHARACTER on Linux, so a typed `_verify\release.ps1` is a path on
# one platform and a FILENAME on the other -- and this gate has to run on the CI
# runner, which is Linux. Every path below is assembled from parts.
function Sub-Path {
  param([string]$Base, [string[]]$Parts)
  $p = $Base
  foreach ($part in $Parts) { $p = Join-Path $p $part }
  return $p
}

# THE MOON EXECUTABLES. Looked up rather than written down, and looked up for
# BOTH platforms: the Windows toolchain ships `moon.exe` and `moonx.exe`, the
# Linux one ships `moon` and `moonx` -- and `moonx` on Linux is a SYMLINK to
# `moon`, created by the very installer the CI workflow runs.
function Get-MoonxExe {
  foreach ($n in @('moonx.exe', 'moonx')) {
    $c = Get-Command $n -ErrorAction SilentlyContinue
    if ($null -ne $c) { return $c.Source }
  }
  $home = if ($env:MOON_HOME -ne '') { $env:MOON_HOME } elseif ($env:USERPROFILE -ne '') { $env:USERPROFILE } else { $env:HOME }
  if ($home -ne '') {
    foreach ($n in @('moonx.exe', 'moonx')) {
      $p = Sub-Path $home @('.moon', 'bin', $n)
      if (Test-Path -LiteralPath $p) { return $p }
    }
  }
  return ''
}

function Get-MoonExe {
  foreach ($n in @('moon.exe', 'moon')) {
    $c = Get-Command $n -ErrorAction SilentlyContinue
    if ($null -ne $c) { return $c.Source }
  }
  $home = if ($env:MOON_HOME -ne '') { $env:MOON_HOME } elseif ($env:USERPROFILE -ne '') { $env:USERPROFILE } else { $env:HOME }
  if ($home -ne '') {
    foreach ($n in @('moon.exe', 'moon')) {
      $p = Sub-Path $home @('.moon', 'bin', $n)
      if (Test-Path -LiteralPath $p) { return $p }
    }
  }
  return ''
}

# ============================================================ the offline checks ==
if (-not $SelfTest) {
  Write-Output '=== the published scan record: the evidence, the pin and the documents ==='
  Write-Output ('  the tree it reads: ' + $root)

  $pins = Get-Pins $root
  if (-not $pins.ok) {
    Write-Output '  FAIL: release.ps1 no longer carries $LUNAFLOW_SCAN and $LUNAFLOW_MOONCHECK.'
    Write-Output '        Restore them, or this gate has nothing to check the documents against.'
    Write-Output 'LUNAFLOW SCAN FAILED: the pins are gone.'
    exit 1
  }
  $scan = $pins['scan']
  $chk = $pins['check']

  # --- 1. the evidence exists ---------------------------------------------------
  $capName = 'lunaflow_scan_' + $scan['analyzer'] + '_' + $scan['corpus'] + '.out'
  $capPath = Sub-Path $root @('_verify', 'fixtures', $capName)
  if (-not (Test-Path -LiteralPath $capPath)) {
    Write-Output ('  FAIL: the evidence for this pin is not committed: _verify\fixtures\' + $capName)
    Write-Output '        A pin with no capture behind it is a number in a comment.'
    Write-Output 'LUNAFLOW SCAN FAILED: the capture is missing.'
    exit 1
  }
  $capLines = [System.IO.File]::ReadAllLines($capPath, [System.Text.Encoding]::UTF8)
  $m = Read-ScanOutput $capLines
  Write-Output ('  the capture: _verify\fixtures\' + $capName + '  (' + $capLines.Count + ' lines)')
  Write-Output ('  (pins: analyzer ' + $scan['analyzer'] + ', corpus ' + $scan['corpus'] + ')')

  # --- 2. the evidence agrees with the pin, field by field ----------------------
  $fields = @('files', 'parsed', 'actionable', 'notices', 'unreliable', 'withheld', 'unchecked', 'total', 'notparse')
  foreach ($k in $fields) {
    $want = $scan[$k]
    $got = if ($m.Contains($k)) { [string]$m[$k] } else { '<absent>' }
    $ok = ($want -ne $null -and $want -eq $got)
    if (-not $ok) { $fail++ }
    Write-Output ('  {0,-46} {1,8}  {2}' -f ('capture ' + $k), $want, $(if ($ok) { 'OK' } else { 'FAIL (capture says ' + $got + ')' }))
  }
  # The percentage is the analyzer's own, not a re-computation: 73 of 76 is 96.0526
  # per cent, which ROUNDS to 96.1 and TRUNCATES to 96.0, and the analyzer prints
  # 96.0. Re-deriving it here would have been a second rule to get wrong.
  $pctOk = ($scan['pct'] -eq $m['pct'])
  if (-not $pctOk) { $fail++ }
  Write-Output ('  {0,-46} {1,8}  {2}' -f 'capture pct', $scan['pct'], $(if ($pctOk) { 'OK' } else { 'FAIL (capture says ' + $m['pct'] + ')' }))

  # --- 3. the capture's own invariants -----------------------------------------
  $inv = @()
  if ($m.Contains('total') -and $m.Contains('actionable') -and $m.Contains('notices') -and $m.Contains('unreliable')) {
    $sum = $m['actionable'] + $m['notices'] + $m['unreliable']
    $inv += ,@('actionable + notices + unreliable = total', ($sum -eq $m['total']), ($sum.ToString() + ' = ' + $m['total']))
  }
  if ($m.Contains('parsed') -and $m.Contains('notparse') -and $m.Contains('files')) {
    $sum = $m['parsed'] + $m['notparse']
    $inv += ,@('parsed + notparse = files', ($sum -eq $m['files']), ($sum.ToString() + ' = ' + $m['files']))
  }
  if ($m.Contains('parsed_line')) {
    $inv += ,@('the PARSED line agrees with the SUMMARY', ($m['parsed_line'] -eq ($m['parsed'].ToString() + '/' + $m['files'].ToString())), $m['parsed_line'])
  }
  $bkFiles = 0; $bkDefects = 0; $bkNotices = 0
  foreach ($b in $m['bykind']) { $bkFiles += $b.Files; $bkDefects += $b.Defects; $bkNotices += $b.Notices }
  if ($m['bykind'].Count -gt 0) {
    $inv += ,@('the BYKIND rows sum to the summary', ($bkFiles -eq $m['files'] -and $bkDefects -eq $m['actionable'] -and $bkNotices -eq $m['notices']),
               ('files ' + $bkFiles + ', defects ' + $bkDefects + ', notices ' + $bkNotices))
  }
  $rowFiles = @($m['rows']).Count
  $rowDefects = 0; $rowNotices = 0
  foreach ($r in $m['rows']) { $rowDefects += $r.Defects; $rowNotices += $r.Notices }
  $inv += ,@('the per-file rows cover every file', ($rowFiles -eq $m['files']), ($rowFiles.ToString() + ' of ' + $m['files']))
  $inv += ,@('the per-file rows sum to the summary', ($rowDefects -eq $m['actionable'] -and $rowNotices -eq $m['notices']),
             ('defects ' + $rowDefects + ', notices ' + $rowNotices))
  if ($m.Contains('notparse_withheld')) {
    $inv += ,@('the NOTPARSE line agrees with the summary', ($m['notparse_withheld'] -eq $m['withheld']), $m['notparse_withheld'].ToString())
  }
  # THE ATTRIBUTION. The README says the three actionable findings are in the
  # corpus's own demo fixture and that the product source has none. That is the
  # claim that would embarrass us if it were wrong, so it is checked against the
  # evidence rather than trusted.
  $srcDefects = 0
  $defectFiles = @()
  foreach ($r in $m['rows']) {
    if ($r.Path -match '/src/') { $srcDefects += $r.Defects }
    if ($r.Defects -gt 0) { $defectFiles += $r.Path }
  }
  $inv += ,@('the product source (src/) has no actionable finding', ($srcDefects -eq [int]$scan['src_actionable']), ('src/ defects ' + $srcDefects))
  $allInOne = ($defectFiles.Count -eq 1) -and ($defectFiles[0].EndsWith($scan['defects_in']))
  $inv += ,@('every actionable finding is in the pinned file', $allInOne, ($defectFiles -join ', '))
  # THE LARGEST RAW-FINDING FILE. The READMEs publish it, so it is derived here.
  $topFile = ''; $topN = -1
  foreach ($r in $m['rows']) {
    $tot = $r.Defects + $r.Notices
    if ($tot -gt $topN) { $topN = $tot; $topFile = $r.Path }
  }
  $topRel = $topFile -replace ('^\.repos/riantr/LunaFlow/' + [regex]::Escape($scan['corpus']) + '/'), ''
  $inv += ,@('the largest raw-finding file is the pinned one', ($topRel -eq $scan['top_file'] -and $topN -eq [int]$scan['top_findings']), ($topRel + ' at ' + $topN))
  Write-Output ''
  Write-Output "  === the capture's own invariants ==="
  foreach ($i in $inv) {
    if (-not $i[1]) { $fail++ }
    Write-Output ('  {0,-46} {1}' -f $i[0], $(if ($i[1]) { 'OK   ' + $i[2] } else { 'FAIL (' + $i[2] + ')' }))
  }

  # --- 4. both READMEs quote the pin -------------------------------------------
  # THE STRINGS ARE DERIVED FROM THE PIN, so re-pinning the record re-derives
  # them: a claim that is written twice is a claim that will disagree with itself.
  Write-Output ''
  Write-Output '  === the documents quote the pin ==='
  $enClaim = '**' + $scan['parsed'] + ' parsed (' + $scan['pct'] + '%), ' + $scan['actionable'] + ' actionable**'
  $zhClaim = '**解析 ' + $scan['parsed'] + ' 个（' + $scan['pct'] + '%），actionable ' + $scan['actionable'] + ' 条**'
  $enChk = '**' + $chk['warnings'] + ' warnings and no error**'
  $zhChk = '**' + $chk['warnings'] + ' 条 warning、零条 error**'
  $enTop = '`' + $scan['top_file'] + '` at **' + $scan['top_findings'] + '** findings'
  $zhTop = '`' + $scan['top_file'] + '`，**' + $scan['top_findings'] + '** 条发现'
  $want = @(
    @{ F = 'README.md';    S = ('riantr/moonbit_static_analysis@' + $scan['analyzer']); N = 'the analyzer coordinate' }
    @{ F = 'README.md';    S = ('riantr/LunaFlow@' + $scan['corpus']); N = 'the corpus coordinate' }
    @{ F = 'README.md';    S = $enClaim; N = 'the parsed/actionable row' }
    @{ F = 'README.md';    S = $enChk; N = "the compiler's row" }
    @{ F = 'README.md';    S = $enTop; N = 'the largest raw-finding file' }
    @{ F = 'README.md';    S = ('`' + $scan['defects_in'] + '`'); N = 'where the actionable findings are' }
    @{ F = 'README.md';    S = 'there is **no** actionable finding'; N = 'the product source has none' }
    @{ F = 'README.md';    S = ('moonx riantr/moonbit_static_analysis@' + $scan['analyzer'] + ' riantr/LunaFlow@' + $scan['corpus']); N = 'the reproduce command' }
    @{ F = 'README.md';    S = 'Run it from an empty scratch directory'; N = 'the .repos/ warning' }
    @{ F = 'README.zh.md'; S = ('riantr/moonbit_static_analysis@' + $scan['analyzer']); N = 'the analyzer coordinate (zh)' }
    @{ F = 'README.zh.md'; S = ('riantr/LunaFlow@' + $scan['corpus']); N = 'the corpus coordinate (zh)' }
    @{ F = 'README.zh.md'; S = $zhClaim; N = 'the parsed/actionable row (zh)' }
    @{ F = 'README.zh.md'; S = $zhChk; N = "the compiler's row (zh)" }
    @{ F = 'README.zh.md'; S = $zhTop; N = 'the largest raw-finding file (zh)' }
    @{ F = 'README.zh.md'; S = ('`' + $scan['defects_in'] + '`'); N = 'where the actionable findings are (zh)' }
    @{ F = 'README.zh.md'; S = '**没有** actionable'; N = 'the product source has none (zh)' }
    @{ F = 'README.zh.md'; S = ('moonx riantr/moonbit_static_analysis@' + $scan['analyzer'] + ' riantr/LunaFlow@' + $scan['corpus']); N = 'the reproduce command (zh)' }
    @{ F = 'README.zh.md'; S = '在一个空的临时目录里跑'; N = 'the .repos/ warning (zh)' }
  )
  $docText = @{}
  foreach ($f in @('README.md', 'README.zh.md')) {
    $p = Join-Path $root $f
    if (-not (Test-Path -LiteralPath $p)) {
      Write-Output ('  FAIL: ' + $f + ' is missing.')
      $fail++
      continue
    }
    # THE WHITESPACE IS COLLAPSED before the comparison, because the READMEs WRAP
    # their sentences: the top-file row is broken across two lines in both
    # documents, and a comparison that does not see that would report a false
    # failure for a formatting choice.
    $docText[$f] = ([regex]::Replace([System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8), '\s+', ' '))
  }
  foreach ($w in $want) {
    if (-not $docText.ContainsKey($w.F)) { continue }
    $ok = $docText[$w.F].Contains($w.S)
    if (-not $ok) { $fail++ }
    Write-Output ('  {0,-42} {1,-18} {2}' -f $w.N, $w.F, $(if ($ok) { 'OK' } else { 'FAIL' }) + $(if ($ok) { '' } else { '  (missing: ' + $w.S + ')' }))
  }

  # --- 5. the live re-measurement ----------------------------------------------
  if ($Live) {
    Write-Output ''
    Write-Output '  === the published packages, re-measured ==='
    $moonx = Get-MoonxExe
    if ($moonx -eq '') {
      Write-Output '  UNKNOWN: no moonx was found (PATH, MOON_HOME and ~/.moon/bin all failed).'
      Write-Output '           The record was NOT re-measured. That is not a pass.'
      $unknown++
    } else {
      # THE SCAN MUST NOT RUN INSIDE THE REPOSITORY. `moonx` creates `.repos/`
      # under the CURRENT directory, and this repository's corpus A/B READS
      # `.repos/` -- a scan run here writes the fetched package into the tree the
      # measurements are taken against. The README says so; this gate ENFORCES it.
      $reposDir = Join-Path $root '.repos'
      $before = 0; $beforeT = [datetime]::MinValue
      if (Test-Path -LiteralPath $reposDir) {
        $items = @(Get-ChildItem -LiteralPath $reposDir -Recurse -File -ErrorAction SilentlyContinue)
        $before = $items.Count
        foreach ($i in $items) { if ($i.LastWriteTime -gt $beforeT) { $beforeT = $i.LastWriteTime } }
      }
      $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('lunaflow_gate_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
      New-Item -ItemType Directory -Path $tmp -Force | Out-Null
      if ($tmp.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Output ('  FAIL: the scratch directory is INSIDE the repository (' + $tmp + ').')
        $fail++
      }
      # THE OUTPUT VARIABLE IS NOT `$live`. PowerShell's variable names are
      # CASE-INSENSITIVE, so `$live` and the `[switch]$Live` parameter are the
      # SAME variable -- and assigning the scan's 421 lines to it raised
      # "Cannot convert value System.Object[] to type SwitchParameter" at the
      # assignment. The scan never ran, and the exit code left behind by the
      # previous native call read as a pass.
      $liveLines = $null
      $liveExit = 0
      Push-Location $tmp
      try {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        # THE PINNED PAIR, not `@latest`. This run answers the REPRODUCIBILITY
        # question -- "do the published artifacts still measure what the capture
        # says?" -- and the STALENESS question is answered separately, by the
        # registry probe below. Running `@latest` here would conflate the two:
        # a moved version and a changed artifact would look like the same failure.
        $analyzerCoord = 'riantr/moonbit_static_analysis@' + $scan['analyzer']
        $corpusCoord = 'riantr/LunaFlow@' + $scan['corpus']
        $liveLines = & $moonx $analyzerCoord $corpusCoord 2>&1 | ForEach-Object { [string]$_ }
        $liveExit = $LASTEXITCODE
        $ErrorActionPreference = $prev
      } finally {
        Pop-Location
      }
      # A COMMAND THAT DID NOT RUN LEAVES $LASTEXITCODE BEHIND, and a stale 0
      # reads as a pass. So the OUTPUT is checked first: no output at all means
      # the invocation never happened, whatever the exit code says.
      if (@($liveLines).Count -eq 0) {
        Write-Output '  UNKNOWN: the live scan produced no output at all -- the command did not run.'
        $unknown++
      } else {
        Write-Output ('  the live scan exited ' + $liveExit)
      }
      if ((@($liveLines).Count -gt 0) -and ($liveExit -ne 0)) {
        Write-Output '  UNKNOWN: the live scan did not complete, so the record was NOT re-measured.'
        @($liveLines) | Select-Object -Last 6 | ForEach-Object { Write-Output ('      | ' + $_) }
        $unknown++
      } else {
        $lm = Read-ScanOutput $liveLines
        if (-not $lm.Contains('files')) {
          Write-Output '  UNKNOWN: the live scan produced no SUMMARY line, so there is nothing to compare.'
          $unknown++
        } else {
          foreach ($k in $fields) {
            $wantV = $scan[$k]; $gotV = if ($lm.Contains($k)) { [string]$lm[$k] } else { '<absent>' }
            $ok = ($wantV -eq $gotV)
            if (-not $ok) { $fail++ }
            Write-Output ('  {0,-46} {1,8}  {2}' -f ('live ' + $k), $wantV, $(if ($ok) { 'OK' } else { 'FAIL (live says ' + $gotV + ')' }))
          }
        }
      }
      # THE STALENESS PROBE. The record names VERSIONS, and a record that names
      # versions which have moved on is stale even when the numbers did not move.
      # `moonx` does not say which analyzer version it ran, so the analyzer's
      # latest is read from the registry -- the same registry `moonx @latest`
      # resolves against.
      $stale = $false
      $newAnalyzer = $scan['analyzer']
      $newCorpus = $scan['corpus']
      foreach ($pkg in @('riantr/moonbit_static_analysis', 'riantr/LunaFlow')) {
        try {
          # THE REGISTRY IS READ WITH WebClient, the way the release gate reads
          # it: `Invoke-RestMethod -UseBasicParsing` does not exist on the CI
          # runner's PowerShell 7 (the switch was REMOVED there, because
          # parsing is not optional any more), and a parameter that does not
          # exist on one of the two platforms is a gate that runs on one of them.
          $wc = New-Object System.Net.WebClient
          $wc.Headers.Add('User-Agent', 'moonbit_static_analysis release gate')
          $body = $wc.DownloadString('https://mooncakes.io/api/v0/modules/' + $pkg)
          $j = $body | ConvertFrom-Json
          $latest = [string]$j.latest_version
          $wantV = if ($pkg -like '*moonbit_static_analysis') { $scan['analyzer'] } else { $scan['corpus'] }
          $ok = ($latest -eq $wantV)
          if (-not $ok) {
            $fail++
            $stale = $true
            if ($pkg -like '*moonbit_static_analysis') { $newAnalyzer = $latest } else { $newCorpus = $latest }
          }
          Write-Output ('  {0,-46} {1,8}  {2}' -f ('the latest of ' + $pkg), $wantV, $(if ($ok) { 'OK' } else { 'FAIL (the registry now serves ' + $latest + ') -- the record is stale and must be re-measured' }))
        } catch {
          Write-Output ('  UNKNOWN: the registry did not answer for ' + $pkg + ' (' + $_.Exception.Message + ')')
          $unknown++
        }
      }
      # THE COMPILER'S ROW. It is the compiler's measurement, so it is compared
      # only when the compiler IS the one the record was measured with.
      $moon = Get-MoonExe
      $pkgDir = Sub-Path $tmp @('.repos', 'riantr', 'LunaFlow', $scan['corpus'])
      if (($moon -eq '') -or (-not (Test-Path -LiteralPath $pkgDir))) {
        Write-Output '  UNKNOWN: the compiler row could not be measured (no moon, or the package was not fetched).'
        $unknown++
      } else {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $ver = & $moon version --all 2>&1 | ForEach-Object { [string]$_ }
        $coreNow = ''
        foreach ($v in $ver) { if ($v -match 'moonc\s+v(\S+)') { $coreNow = $Matches[1]; break } }
        $ErrorActionPreference = $prev
        if (($pins['core'] -eq '') -or ($coreNow -ne $pins['core'])) {
          Write-Output ('  UNKNOWN: the compiler row is not comparable -- the record was measured with core ' + $pins['core'] + ' and this machine runs ' + $coreNow + '.')
          $unknown++
        } else {
          $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
          $co = & $moon -C $pkgDir check --target all 2>&1 | ForEach-Object { [string]$_ }
          $cc = $LASTEXITCODE
          $ErrorActionPreference = $prev
          $line = ''
          foreach ($l in $co) { if ($l -match '\((\d+) warnings?, (\d+) errors?\)') { $line = $l; break } }
          if ($line -eq '') {
            Write-Output '  UNKNOWN: `moon check --target all` reported no warning count, so the compiler row was not measured.'
            $unknown++
          } else {
            $mm = [regex]::Match($line, '\((\d+) warnings?, (\d+) errors?\)')
            $w = $mm.Groups[1].Value; $e = $mm.Groups[2].Value
            $ok = ($w -eq $chk['warnings']) -and ($e -eq $chk['errors'])
            if (-not $ok) { $fail++ }
            Write-Output ('  {0,-46} {1,8}  {2}' -f "the compiler's row", ($chk['warnings'] + '/' + $chk['errors']), $(if ($ok) { 'OK' } else { 'FAIL (the compiler says ' + $w + '/' + $e + ')' }))
          }
        }
      }
      # THE CANDIDATE. When the record is stale, the remedy is the ritual the
      # READMEs name: run the scan against `@latest` and re-pin from the result.
      # The gate RUNS that ritual and prints the line to paste, so the remedy is a
      # measurement and not a guess -- and the maintainer does not have to
      # rediscover that the scan must not run inside this repository.
      if ($stale) {
        Write-Output ''
        Write-Output '  === the candidate: the same scan against @latest ==='
        $cand = $null
        $candCode = 0
        Push-Location $tmp
        try {
          $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
          $cand = & $moonx 'riantr/moonbit_static_analysis@latest' 'riantr/LunaFlow@latest' 2>&1 | ForEach-Object { [string]$_ }
          $candCode = $LASTEXITCODE
          $ErrorActionPreference = $prev
        } finally {
          Pop-Location
        }
        if ($candCode -ne 0) {
          Write-Output '  UNKNOWN: the candidate scan did not complete, so no candidate was measured.'
          @($cand) | Select-Object -Last 5 | ForEach-Object { Write-Output ('      | ' + $_) }
          $unknown++
        } else {
          $cm = Read-ScanOutput $cand
          if (-not $cm.Contains('files')) {
            Write-Output '  UNKNOWN: the candidate scan produced no SUMMARY line, so no candidate was measured.'
            $unknown++
          } else {
            $cCorpus = $scan['corpus']
            if ($cm.Contains('target_dir')) {
              $seg = @([string]$cm['target_dir'] -split '/')
              if ($seg.Count -gt 0) { $cCorpus = $seg[$seg.Count - 1] }
            }
            $cTopFile = ''; $cTopN = -1; $cSrc = 0; $cDefect = ''
            foreach ($r in $cm['rows']) {
              if ($r.Path -match '/src/') { $cSrc += $r.Defects }
              if (($r.Defects -gt 0) -and ($cDefect -eq '')) {
                $cDefect = $r.Path -replace ('^\.repos/riantr/LunaFlow/' + [regex]::Escape($cCorpus) + '/'), ''
              }
              $tot = $r.Defects + $r.Notices
              if ($tot -gt $cTopN) { $cTopN = $tot; $cTopFile = $r.Path }
            }
            $cTopRel = $cTopFile -replace ('^\.repos/riantr/LunaFlow/' + [regex]::Escape($cCorpus) + '/'), ''
            $cNotParse = if ($cm.Contains('notparse')) { $cm['notparse'] } else { 0 }
            Write-Output ("  `$LUNAFLOW_SCAN = 'analyzer=" + $newAnalyzer + "|corpus=" + $cCorpus +
              "|files=" + $cm['files'] + "|parsed=" + $cm['parsed'] + "|pct=" + $cm['pct'] +
              "|actionable=" + $cm['actionable'] + "|notices=" + $cm['notices'] +
              "|unreliable=" + $cm['unreliable'] + "|withheld=" + $cm['withheld'] +
              "|unchecked=" + $cm['unchecked'] + "|total=" + $cm['total'] +
              "|notparse=" + $cNotParse + "|src_actionable=" + $cSrc +
              "|defects_in=" + $cDefect + "|top_file=" + $cTopRel + "|top_findings=" + $cTopN + "'")
            Write-Output '  Re-measure with it, re-commit the capture under the new name, and re-pin the READMEs.'
          }
        }
      }
      # AND THE PIT IS ENFORCED, not just documented: the repository's `.repos/`
      # must be exactly as it was before the scan.
      $after = 0; $afterT = [datetime]::MinValue
      if (Test-Path -LiteralPath $reposDir) {
        $items = @(Get-ChildItem -LiteralPath $reposDir -Recurse -File -ErrorAction SilentlyContinue)
        $after = $items.Count
        foreach ($i in $items) { if ($i.LastWriteTime -gt $afterT) { $afterT = $i.LastWriteTime } }
      }
      $pitOk = ($before -eq $after) -and ($beforeT -eq $afterT)
      if (-not $pitOk) { $fail++ }
      Write-Output ('  {0,-46} {1,8}  {2}' -f "the repository's .repos/ is untouched", ($before.ToString() + ' files'), $(if ($pitOk) { 'OK' } else { 'FAIL (it is now ' + $after + ' files) -- the scan wrote into the repository' }))
      Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Write-Output ''
  if ($fail -eq 0 -and $unknown -eq 0) {
    Write-Output 'LUNAFLOW SCAN OK: the evidence, the pin and the two documents agree.'
    exit 0
  }
  if ($fail -eq 0) {
    Write-Output ('LUNAFLOW SCAN UNKNOWN: ' + $unknown + ' claim(s) could not be measured. That is not a pass.')
    exit 2
  }
  Write-Output ('LUNAFLOW SCAN FAILED: ' + $fail + ' problem(s).')
  exit 1
}

# ================================================================ the self-test ===
Write-Output '=== the scan-record gate, shown to go red ==='

# THE FIXTURE. A copy of the pin, of the capture and of the two READMEs. The
# repository is never touched: the copy is made fresh for every fault, so one
# fault cannot mask another.
function New-ScanFixture {
  param([string]$Tree, [switch]$BadCapture, [switch]$BadReadme)
  $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('lfscan_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Path (Sub-Path $dir @('_verify', 'fixtures')) -Force | Out-Null
  Copy-Item -LiteralPath (Sub-Path $Tree @('_verify', 'release.ps1')) -Destination (Sub-Path $dir @('_verify', 'release.ps1')) -Force
  $pins = Get-Pins $Tree
  $capName = 'lunaflow_scan_' + $pins['scan']['analyzer'] + '_' + $pins['scan']['corpus'] + '.out'
  $capSrc = Sub-Path $Tree @('_verify', 'fixtures', $capName)
  $capDst = Sub-Path $dir @('_verify', 'fixtures', $capName)
  $enc = New-Object System.Text.UTF8Encoding($false)
  $capText = [System.IO.File]::ReadAllText($capSrc, [System.Text.Encoding]::UTF8)
  if ($BadCapture) {
    # THE EVIDENCE IS CHANGED, not the pin: the number in the capture no longer
    # agrees with the number in the pin, and the gate has to say so.
    $capText = $capText -replace '(?m)^(SUMMARY\tfiles=\d+\tparsed=\d+\tactionable=)(\d+)', ('${1}99')
  }
  [System.IO.File]::WriteAllText($capDst, $capText, $enc)
  foreach ($f in @('README.md', 'README.zh.md')) {
    $t = [System.IO.File]::ReadAllText((Join-Path $Tree $f), [System.Text.Encoding]::UTF8)
    if ($BadReadme) {
      # THE DOCUMENT IS CHANGED, not the pin: the README now quotes a number the
      # pin does not hold.
      $t = $t.Replace('parsed (', 'parsed 99 (')
    }
    [System.IO.File]::WriteAllText((Join-Path $dir $f), $t, $enc)
  }
  return $dir
}

function Invoke-OnFixture {
  param([string]$Dir)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  # THE CHILD POWERSHELL IS THE ONE THAT IS RUNNING. `powershell` does not exist
  # on the CI runner -- it is `pwsh` there -- and `-ExecutionPolicy` is a
  # Windows-only parameter, so it is added only where it exists.
  $psExe = (Get-Process -Id $PID).Path
  $childArgs = @('-NoProfile')
  if ($PSVersionTable.PSEdition -eq 'Desktop') { $childArgs += @('-ExecutionPolicy', 'Bypass') }
  $childArgs += @('-File', $PSCommandPath, '-Root', $Dir)
  $o = & $psExe @childArgs 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  return [pscustomobject]@{ Code = $code; Out = $o }
}

$bad = 0
$checked = 0

# THE CONTROL. An unmutated fixture must PASS. A self-test that only proves the
# gate can fail proves nothing about the gate.
Write-Output ''
Write-Output '--- the control: the evidence, the pin and the documents agree ---'
$ctlDir = New-ScanFixture $root
$ctl = Invoke-OnFixture $ctlDir
$checked++
if ($ctl.Code -eq 0) {
  Write-Output '  OK: the control passes (exit 0).'
} else {
  Write-Output ('  FAIL: the control FAILS with exit ' + $ctl.Code + '.')
  foreach ($ln in ($ctl.Out -split "`r?`n")) { if ($ln -match 'FAIL|LUNAFLOW') { Write-Output ('        ' + $ln.Trim()) } }
  $bad++
}

# THE DEFECT, in the EVIDENCE. The capture no longer agrees with the pin.
Write-Output ''
Write-Output '--- the defect: the capture disagrees with the pin ---'
$defDir = New-ScanFixture $root -BadCapture
$def = Invoke-OnFixture $defDir
$checked++
$caught = ($def.Code -eq 1) -and ($def.Out -like '*capture actionable*')
if ($caught) {
  Write-Output ('  OK: the gate caught it (exit ' + $def.Code + ').')
} else {
  Write-Output ('  FAIL: the gate did NOT catch it (exit ' + $def.Code + ').')
  foreach ($ln in ($def.Out -split "`r?`n")) { if ($ln -match 'FAIL|LUNAFLOW') { Write-Output ('        ' + $ln.Trim()) } }
  $bad++
}

# THE DEFECT, in the DOCUMENT. The README quotes a number the pin does not hold.
Write-Output ''
Write-Output '--- the defect: a document quotes a number the pin does not hold ---'
$docDir = New-ScanFixture $root -BadReadme
$doc = Invoke-OnFixture $docDir
$checked++
$caught = ($doc.Code -eq 1) -and ($doc.Out -like '*parsed/actionable row*')
if ($caught) {
  Write-Output ('  OK: the gate caught it (exit ' + $doc.Code + ').')
} else {
  Write-Output ('  FAIL: the gate did NOT catch it (exit ' + $doc.Code + ').')
  foreach ($ln in ($doc.Out -split "`r?`n")) { if ($ln -match 'FAIL|LUNAFLOW') { Write-Output ('        ' + $ln.Trim()) } }
  $bad++
}

# AND EVERY CHECK RAN. A self-test that silently skipped one of its own checks
# is the same green light that measured nothing.
if ($checked -ne 3) {
  Write-Output ('  FAIL: ' + $checked + ' of 3 checks ran.')
  $bad++
}

Write-Output ''
if ($bad -eq 0) {
  Write-Output 'SELFTEST OK: the control passed, and a changed capture and a changed document were both caught.'
  exit 0
}
Write-Output ('SELFTEST FAILED: ' + $bad + ' of 3 checks did not hold.')
exit 1

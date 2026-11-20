param([switch]$SelfTest, [string]$FixtureDir = '', [string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE FALSIFICATION SWEEP, AS A GATE.
#
# WHY THIS EXISTS. `_verify/QA_TODO.md` §1 recorded a census: "families that
# fire actionably: 17 of 18". That census was made BY HAND, in a scratch
# directory, and it will rot exactly the way a hand-written table rots. A QA
# that is not a gate is a comment, and a comment that says "17 of 18" is a
# comment that will still say it after the eighteenth family stops firing.
#
# So this gate asks the question the census answered, and it asks it of the
# SOURCE and of the ARTIFACT:
#
#   1. EVERY family in `Family::all_families()` has a fixture, and the fixture
#      is named for it. The list of families is read out of `src/core/core.mbt`
#      -- the SAME source `check_family_roster.ps1` reads -- so a family added
#      to the enum and not given a fixture turns this gate RED instead of
#      quietly shrinking the census.
#   2. The sweep's `METRICS family` TABLE holds every one of them, and holds
#      nothing else.
#   3. Each fixture file fires ITS OWN family. This is the strong form, and it
#      is the one that catches the failure the census cannot: a family can be
#      in the table because ANOTHER file put it there.
#
# THE CENSUS IS THE TABLE, NOT THE FINDING COUNT. Two of the eighteen do not
# produce an actionable finding and MUST NOT be counted as if they did:
#
#   * MSA-001 can only ever be a NOTICE -- a genuine parse failure's findings
#     are WITHHELD (`unreliable=`/`withheld=` in the SUMMARY), so a file that
#     fails to parse contributes NO row to the census at all. The half of the
#     family a census can see is the DECLARED SCOPE LIMIT, and the fixture for
#     MSA-001 is that shape.
#   * MSA-002 is reported at LOW CONFIDENCE, so 0508 renders it a notice. It is
#     in the table as `low=1`, and a table row is a row.
#
# AND TWO OF THEM NEED A SHAPE, NOT A FLAG. MSA-007 and MSA-008 share the
# `arg-type` merge group with MSA-009, and a merged finding keeps the family
# of the HIGHEST-RANKED lens -- behavior beats type beats structural. There is
# NO `--lens` option in this tool, so "the type lens alone" is a property of
# the FIXTURE: MSA-007's call sits in a function NOTHING CALLS, and MSA-008's
# is `!` on a known Int. Each fixture's own header says so.
#
# AND ONE OF THEM NEEDS A FLAG. MSA-012 is a suppression that suppresses
# nothing, and the analyzer cannot see that unless it honours suppressions, so
# the sweep runs with `--honor-nosec`. MSA-018 needs the taint source and sink
# to be NAMED, and the two names are read out of THE FIXTURE'S OWN HEADER, so
# that a name is written down in exactly one place.
#
# IT SCANS THE LOCAL WASM, not the registry. A gate that depends on the
# network is a gate that fails for a reason that is not about the code, and
# "the machine misbehaved is not a verdict".
#
# THE -SelfTest SWITCH injects faults into a COPY of the fixture set under
# %TEMP% and requires the copy to go RED for the right reason. A guard that
# has never been shown to go red is not a guard. The repository is not
# touched: the copy is the fixture set and nothing else, because the analyzer
# (the wasm) is the thing being tested, not the thing being copied.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_family_fires.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_family_fires.ps1 -SelfTest

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$coreSrc = Join-Path $root 'src\core\core.mbt'
$fixtures = Join-Path $root '_verify\fixtures\families'
# THE SELF-TEST'S OWN INVOCATION points at a COPY of the fixture set, and this
# is the switch that points it there. It is a parameter and not a variable
# because the copy is scanned by a WHOLE OTHER PROCESS -- the child has to be
# told where to look, or it would look at the repository's own fixtures and
# prove nothing at all.
if ($FixtureDir -ne '') { $fixtures = $FixtureDir }

# THE FAMILY LIST, READ OUT OF THE SOURCE. The same expression
# `check_family_roster.ps1` uses, against the same file, so there is ONE list
# in this repository and it is the enum.
function Get-FamilyIds {
  $src = [System.IO.File]::ReadAllText($coreSrc)
  $m = [regex]::Matches($src, 'F([A-Za-z]+)\s*=>\s*"(MSA-\d{3})"')
  $ids = @($m | ForEach-Object { $_.Groups[2].Value } | Sort-Object -Unique)
  return $ids
}

# THE TAINT NAMES, READ OUT OF THE FIXTURE. A name written down twice is a
# name that will disagree with itself, so the FIXTURE is the place that holds
# them and this function only reads.
function Get-TaintNames {
  param([string]$Dir)
  $out = @{}
  foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter 'MSA-018_*.mbt' -File -ErrorAction SilentlyContinue)) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $sm = [regex]::Match($t, '(?m)^//\s*taint-source:\s*(\S+)\s*$')
    $km = [regex]::Match($t, '(?m)^//\s*taint-sink:\s*(\S+)\s*$')
    if ($sm.Success) { $out['source'] = $sm.Groups[1].Value }
    if ($km.Success) { $out['sink'] = $km.Groups[1].Value }
  }
  return $out
}

# THE SWEEP. One scan of the fixture set through the local wasm.
function Invoke-Sweep {
  param([string]$Dir, [string]$TaintSource, [string]$TaintSink)
  $tmp = Join-Path $env:TEMP ('ff_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $out = Join-Path $tmp 'o.txt'
  $err = Join-Path $tmp 'o.err'
  $a = @($wasm, $Dir, '--extern-iface-dir', $repos, '--no-auto-fetch-deps',
         '--findings-shown-per-file', '1000000', '--metrics', '--honor-nosec',
         '--show-notices')
  if ($TaintSource -ne '' -and $TaintSink -ne '') {
    $a += @('--taint-source', $TaintSource, '--taint-sink', $TaintSink)
  }
  Start-Process -FilePath $moonrun -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  $text = [System.IO.File]::ReadAllText($out)
  $errText = [System.IO.File]::ReadAllText($err)
  return [pscustomobject]@{ Text = $text; Err = $errText; Tmp = $tmp }
}

# THE THREE CHECKS. They return the number of problems, and they PRINT the
# reason for every one of them -- a red row that names its cause beats a green
# row that measured nothing.
function Test-FamilyFires {
  param([string]$Dir, [switch]$Quiet)
  $script:firesFail = 0
  $ids = @(Get-FamilyIds)
  if ($ids.Count -eq 0) {
    if (-not $Quiet) { Write-Output '  FAIL: no family ids were read out of src\core\core.mbt.' }
    return
  }

  # --- 1. one fixture per family -----------------------------------------------
  if (-not $Quiet) { Write-Output ('  the source holds ' + $ids.Count + ' families') }
  $files = @(Get-ChildItem -LiteralPath $Dir -Filter '*.mbt' -File -ErrorAction SilentlyContinue | Sort-Object Name)
  $byId = @{}
  foreach ($f in $files) {
    $m = [regex]::Match($f.Name, '^(MSA-\d{3})_')
    if (-not $m.Success) {
      if (-not $Quiet) {
        Write-Output ('  FAIL: the fixture ' + $f.Name + ' does not name the family it is for. A fixture is named `MSA-NNN_<what>.mbt`.')
      }
      $script:firesFail++
      continue
    }
    $id = $m.Groups[1].Value
    if (-not $byId.ContainsKey($id)) { $byId[$id] = @() }
    $byId[$id] += $f.Name
  }
  foreach ($id in $ids) {
    if (-not $byId.ContainsKey($id)) {
      if (-not $Quiet) {
        Write-Output ('  FAIL: no fixture for ' + $id + '. The family is in the source and nothing in the fixture set is for it.')
      }
      $script:firesFail++
    } elseif ($byId[$id].Count -gt 1) {
      if (-not $Quiet) {
        Write-Output ('  FAIL: ' + $id + ' has ' + $byId[$id].Count + ' fixtures (' + ($byId[$id] -join ', ') + '). One family, one fixture.')
      }
      $script:firesFail++
    }
  }
  foreach ($id in ($byId.Keys | Sort-Object)) {
    if ($ids -notcontains $id) {
      if (-not $Quiet) {
        Write-Output ('  FAIL: the fixture set holds a fixture for ' + $id + ', which is not a family in the source.')
      }
      $script:firesFail++
    }
  }
  if ($script:firesFail -eq 0 -and -not $Quiet) {
    Write-Output ('  ' + $files.Count + ' fixtures, one per family, and every one is named for a family in the source')
  }
  if ($script:firesFail -gt 0) { return }

  # --- the taint names ---------------------------------------------------------
  $taint = Get-TaintNames $Dir
  if (-not $taint.ContainsKey('source') -or -not $taint.ContainsKey('sink')) {
    if (-not $Quiet) {
      Write-Output '  FAIL: the MSA-018 fixture does not declare its taint source and sink. The sweep cannot name the family without them.'
    }
    return
  }

  # --- the sweep ---------------------------------------------------------------
  $sw = Invoke-Sweep $Dir $taint['source'] $taint['sink']
  $lines = $sw.Text -split "`r?`n"
  if ($sw.Err.Trim() -ne '') {
    if (-not $Quiet) { Write-Output '  FAIL: the sweep wrote to stderr:' ; Write-Output ('        ' + $sw.Err.Trim()) }
    $script:firesFail++
  }
  $summary = ''
  foreach ($l in $lines) { if ($l -match '^SUMMARY\t') { $summary = $l } }
  if ($summary -eq '') {
    if (-not $Quiet) { Write-Output '  FAIL: the sweep printed no SUMMARY. A scan that did not run is not a clean scan.' }
    $script:firesFail++
  } elseif (-not $Quiet) {
    Write-Output ('  ' + $summary)
  }

  # --- 2. the census holds every family ----------------------------------------
  $census = @{}
  foreach ($l in $lines) {
    if ($l -match '^METRICS\tfamily\t(MSA-\d{3})\t') { $census[$Matches[1]] = $l }
  }
  foreach ($id in $ids) {
    if (-not $census.ContainsKey($id)) {
      if (-not $Quiet) {
        Write-Output ('  FAIL: the census holds no row for ' + $id + '. The family is in the source and the sweep produced no row for it.')
      }
      $script:firesFail++
    }
  }
  foreach ($id in ($census.Keys | Sort-Object)) {
    if ($ids -notcontains $id) {
      if (-not $Quiet) { Write-Output ('  FAIL: the census holds a row for ' + $id + ', which is not a family in the source.') }
      $script:firesFail++
    }
  }
  if (-not $Quiet) {
    Write-Output ('  the census holds ' + $census.Count + ' rows for ' + $ids.Count + ' families')
  }

  # --- 3. each fixture fires its OWN family ------------------------------------
  $cur = ''
  $perFile = @{}
  foreach ($l in $lines) {
    if ($l -match '^(FOUND|CLEAN)\t') {
      $p = (($l -split "`t")[-1]).Trim()
      $cur = [System.IO.Path]::GetFileName(($p -replace '/', '\'))
      if (-not $perFile.ContainsKey($cur)) { $perFile[$cur] = @() }
    } elseif ($l -match '\[.*?,\s*(MSA-\d{3}),\s*\w+\]') {
      if ($cur -ne '') { $perFile[$cur] += $Matches[1] }
    }
  }
  foreach ($f in $files) {
    $want = [regex]::Match($f.Name, '^(MSA-\d{3})').Groups[1].Value
    $got = @()
    if ($perFile.ContainsKey($f.Name)) { $got = @($perFile[$f.Name] | Sort-Object -Unique) }
    if ($got -notcontains $want) {
      if (-not $Quiet) {
        Write-Output ('  FAIL: the fixture ' + $f.Name + ' fired [' + ($got -join ',') + '] and not ' + $want + '. A family in the census is not enough: the FIXTURE for a family has to fire that family.')
      }
      $script:firesFail++
    }
  }
  if (-not $Quiet) {
    if ($script:firesFail -eq 0) {
    Write-Output ('  ' + $files.Count + ' fixtures, and each one fired its own family')
  }
  }
  return
}

# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $wasm)) {
  Write-Output 'ABORT: no wasm artifact. Build it first.'
  exit 1
}
if (-not (Test-Path -LiteralPath $fixtures)) {
  Write-Output ('ABORT: the fixture set is missing: ' + $fixtures)
  exit 1
}

if (-not $SelfTest) {
  Write-Output '=== the family sweep: every family fires, from its own fixture ==='
  Test-FamilyFires $fixtures
  Write-Output ''
  if ($script:firesFail -eq 0) {
    Write-Output 'FIRES OK: every family in the source has a fixture, the census holds every one of them, and each fixture fires its own family.'
    exit 0
  }
  Write-Output ('FIRES FAILED: ' + $script:firesFail + ' problem(s).')
  exit 1
}

# --- the self-test ------------------------------------------------------------
Write-Output '=== the family-sweep gate, shown to go red ==='

function New-FixtureCopy {
  $dir = Join-Path $env:TEMP ('ffselftest_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Copy-Item -Path (Join-Path $fixtures '*.mbt') -Destination $dir -Force
  return $dir
}

function Invoke-OnCopy {
  param([string]$Dir)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -FixtureDir $Dir 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  return [pscustomobject]@{ Code = $code; Out = $o }
}

# THE CONTROL. An unmutated copy must PASS. A self-test that only proves the
# gate can fail proves nothing about the gate.
#
# AND THE CONTROL COUNTS. A control that fails and is not counted would let the
# self-test print SELFTEST OK over a gate that does not even pass its own
# fixture set -- which is the one thing this gate exists to say.
$script:controlOk = $false
Write-Output '--- the control: an unmutated copy must pass ---'
$ctlDir = New-FixtureCopy
$ctl = Invoke-OnCopy $ctlDir
if ($ctl.Code -eq 0) {
  Write-Output '  OK: the unmutated copy passes.'
  $script:controlOk = $true
} else {
  Write-Output ('  FAIL: the unmutated copy FAILS with exit ' + $ctl.Code + '.')
  foreach ($ln in ($ctl.Out -split "`r?`n")) { if ($ln -match 'FAIL') { Write-Output ('        ' + $ln.Trim()) } }
}

$faults = @(
  [pscustomobject]@{
    N = 'a family with no fixture'
    Expect = 'no fixture for MSA-007'
    Apply = {
      param($d)
      $p = Join-Path $d 'MSA-007_arg_type.mbt'
      if (Test-Path -LiteralPath $p) { [System.IO.File]::Delete($p); return $true }
      return $false
    }
  }
  [pscustomobject]@{
    N = 'two fixtures that fire each other''s family'
    Expect = 'fired [MSA-009] and not MSA-007'
    Apply = {
      param($d)
      # THE SWAP. MSA-007's fixture gets the shape that fires MSA-009, and
      # MSA-009's fixture gets the shape that fires MSA-007.
      #
      # AND THIS IS THE FAULT THE CENSUS CANNOT SEE. After the swap the
      # census STILL holds both families -- MSA-007 is in it because the file
      # named MSA-009 now fires it, and MSA-009 is in it because the file
      # named MSA-007 now fires it. Every row of the table is still there.
      # What is wrong is that NO FIXTURE FIRES ITS OWN FAMILY, and only the
      # per-file check can say so. A census that only counted rows would have
      # called this set complete.
      $p7 = Join-Path $d 'MSA-007_arg_type.mbt'
      $p9 = Join-Path $d 'MSA-009_method_error.mbt'
      if (-not (Test-Path -LiteralPath $p7)) { return $false }
      if (-not (Test-Path -LiteralPath $p9)) { return $false }
      $b7 = [System.IO.File]::ReadAllText($p7)
      $b9 = [System.IO.File]::ReadAllText($p9)
      # The HEADER of each file names the family it is for, and the header is
      # what the swap must not carry over: a header that says MSA-007 above
      # MSA-009's body would be a second lie.
      #
      # AND THE BODY IS EVERY PART AFTER THE HEADER. The split is a zero-width
      # lookahead, so it does not consume the `fn ` it splits on, and the body
      # is more than one part: the first attempt took only parts[1] and threw
      # the SECOND FUNCTION of each file away, so the swapped files did not
      # parse and the fault was caught for the wrong reason.
      $parts7 = @($b7 -split '(?m)^(?=fn )')
      $parts9 = @($b9 -split '(?m)^(?=fn )')
      if ($parts7.Count -lt 3 -or $parts9.Count -lt 3) { return $false }
      $h7 = $parts7[0]
      $h9 = $parts9[0]
      $body7 = ($parts7[1..($parts7.Count - 1)] -join '')
      $body9 = ($parts9[1..($parts9.Count - 1)] -join '')
      $enc = New-Object System.Text.UTF8Encoding($false)
      [System.IO.File]::WriteAllText($p7, ($h7 + $body9), $enc)
      [System.IO.File]::WriteAllText($p9, ($h9 + $body7), $enc)
      return $true
    }
  }
)

$bad = 0
$checked = 0
foreach ($f in $faults) {
  Write-Output ('--- the defect: ' + $f.N + ' ---')
  $d = New-FixtureCopy
  $applied = & $f.Apply $d
  if ($applied -ne $true) {
    Write-Output '  FAIL: the defect did not apply -- the mutation found nothing to change.'
    $bad++
    $checked++
    continue
  }
  $r = Invoke-OnCopy $d
  # THE MESSAGE IS COMPARED AS A LITERAL, not as a wildcard. `-like` reads `[`
  # and `]` as a character class, and the message this gate prints for a
  # mis-firing fixture CONTAINS them -- so a `-like` comparison threw a
  # WildcardPatternException, the exception skipped the whole comparison, and
  # the self-test went on to print SELFTEST OK having checked NOTHING.
  #
  # That is the house lesson in its sharpest form: a green light that measured
  # nothing. So the comparison is literal, AND a throw is a FAILURE, AND the
  # number of checks that actually ran is asserted at the end.
  $caught = $false
  try {
    $caught = ($r.Code -ne 0) -and $r.Out.Contains($f.Expect)
  } catch {
    Write-Output ('  FAIL: the check itself threw: ' + $_.Exception.Message)
    $caught = $false
  }
  $checked++
  if ($caught) {
    Write-Output ('  OK: the gate caught it (exit ' + $r.Code + ').')
  } else {
    Write-Output ('  FAIL: the gate did NOT catch it (exit ' + $r.Code + ').')
    foreach ($ln in ($r.Out -split "`r?`n")) { if ($ln -match 'FAIL') { Write-Output ('        ' + $ln.Trim()) } }
    $bad++
  }
}

# AND EVERY FAULT WAS ACTUALLY CHECKED. A self-test that silently skipped one
# of its own checks is the same green light that measured nothing.
if ($checked -ne $faults.Count) {
  Write-Output ('  FAIL: ' + $checked + ' of ' + $faults.Count + ' faults were checked.')
  $bad++
}

Write-Output ''
if ($bad -eq 0 -and $script:controlOk) {
  Write-Output ('SELFTEST OK: the control passed and all ' + $faults.Count + ' injected defects were caught.')
  exit 0
}
if (-not $script:controlOk) { Write-Output 'SELFTEST FAILED: the control did not pass.' }
Write-Output ('SELFTEST FAILED: ' + $bad + ' of ' + ($faults.Count + 1) + ' checks did not hold.')
exit 1

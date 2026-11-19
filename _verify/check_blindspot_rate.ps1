param([switch]$SelfTest, [string]$FixtureDir = '', [string]$Wasm = '', [string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE BLIND-SPOT RATE, as a PIN.
#
# WHAT THIS PINS. Six planted defects, each the SAME defect its family's own
# fixture carries, and the only difference is that here the defect sits inside
# a `test` body. MEASURED: the analyzer detects 18 of 18 of them in a `fn`
# body and 0 of 6 of them in a `test` body. So the rate of planted defects
# invisible inside a `test` body is 0 of 6 -- and until this gate existed, the
# only place that number existed was a scratch directory.
#
# WHY A PIN AND NOT A COMMENT. The number is PUBLISHED -- the README's coverage
# section states it -- and a published number with nothing that re-measures it
# is a number that drifts. The pin is the number: 0 detected, and 6 files each
# saying so.
#
# AND THE PIN IS NOT VACUOUS, WHICH IS THE PART THAT MATTERS. A gate that
# counts zero findings can be green for two reasons: the defects are invisible,
# or the analyzer is blind. The `-SelfTest` tells them apart. It takes a COPY of
# the fixture set, takes the `test` wrapper OFF the copy, and requires the very
# same defects to be DETECTED -- and requires each of them to be detected AS
# ITS OWN FAMILY. If they stay invisible outside a `test` body too, the
# analyzer is blind and this pin is measuring nothing. If they come back as the
# WRONG families, the pin is measuring something else.
#
# THE WRAPPER IS REMOVED, NOT THE DEFECT. The copy keeps the comment header,
# the function, and the defect; it loses the `test "..." {` line and the brace
# that closed it.
#
# AND THE CALL THAT REACHES THE FUNCTION IS THE FAMILY'S OWN. A `test` body is
# not a program, so the behavioural lens has to be given a call to reach the
# function at all. The call is NOT guessed: it is READ from the family's own
# fixture, whose last line of code is exactly that call. This matters --
# MEASURED: MSA-011's function takes an argument, and a wrapper-removed copy
# that called it with none would have reported MSA-007 (a wrong arity) instead
# of MSA-011 (the unreachable statement). The pin would then have been green
# for the wrong reason.
#
# AND THE ONE FAMILY THAT SPEAKS IN THE CONTROL IS MSA-001. The scope-limit
# notice -- "test declaration is outside the analyzed subset" -- BELONGS to the
# ParseError family, so the census names it, and naming it is the point: the
# exclusion is ANNOUNCED. What must not appear is any OTHER family. So the
# census is checked for exactly one row, MSA-001, and that row's total must be
# the number of fixtures -- one notice each, no fixture silent.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_blindspot_rate.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_blindspot_rate.ps1 -SelfTest

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
if ($Wasm -eq '') { $Wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm' }
$fixtures = Join-Path $root '_verify\fixtures\blindspot'
$families = Join-Path $root '_verify\fixtures\families'
# The self-test's own invocation points at a COPY of the fixture set, and this
# is the switch that points it there. It is a parameter and not a variable
# because the copy is scanned by a WHOLE OTHER PROCESS -- the child has to be
# told where to look, or it would look at the repository's own fixtures and
# prove nothing at all.
if ($FixtureDir -ne '') { $fixtures = $FixtureDir }

function Invoke-Sweep([string]$Dir) {
  $tmp = Join-Path $env:TEMP ('bsr_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $out = Join-Path $tmp 'o.txt'
  $err = Join-Path $tmp 'o.err'
  $a = @($Wasm, $Dir, '--no-auto-fetch-deps', '--findings-shown-per-file', '1000000',
         '--metrics', '--honor-nosec')
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  Start-Process -FilePath $moonrun -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  $ErrorActionPreference = $prev
  return [System.IO.File]::ReadAllText($out)
}

# THE SUMMARY LINE, and a field read OUT OF IT.
#
# THE FIELDS ARE READ FROM THE SUMMARY AND NOT FROM THE WHOLE SCAN. A scan
# prints a `notices=` on every per-file line as well, and a search over the
# whole text finds THAT one first -- which is how an earlier draft of this
# gate read "notices=1" for a sweep that reported six. The SUMMARY is the one
# line that is about the whole tree, so the tree's numbers are read from it.
function Get-SummaryLine([string]$Text) {
  $m = [regex]::Match($Text, '(?m)^SUMMARY.*$')
  if ($m.Success) { return $m.Value }
  return ''
}

function Get-Field([string]$Line, [string]$Key) {
  $m = [regex]::Match($Line, [regex]::Escape($Key) + '=(\d+)')
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return -1
}

# THE FAMILIES THE SCAN REPORTED, and how many findings each carried. The
# census is the analyzer's own table: one row per family that spoke.
function Get-Census([string]$Text) {
  $rows = @{}
  foreach ($m in [regex]::Matches($Text, '(?m)^METRICS\tfamily\t(MSA-\d+)\t\S+\tseverity=\S+\thigh=(\d+)\tlow=(\d+)\tundecided=(\d+)\ttotal=(\d+)')) {
    $rows[$m.Groups[1].Value] = [int]$m.Groups[5].Value
  }
  return $rows
}

# THE FAMILY A FIXTURE CLAIMS. Read from the file's own header, so a fixture
# that is renamed does not need this script renamed with it.
function Get-Family([string]$Path) {
  foreach ($l in [System.IO.File]::ReadAllLines($Path)) {
    if ($l -match '^\s*//\s*family:\s*(MSA-\d+)') { return $Matches[1] }
  }
  return ''
}

# THE FAMILY'S OWN TOP-LEVEL CALL: the last line of code in the family's own
# fixture. Not a guess -- MEASURED, and the arity matters.
function Get-OwnCall([string]$Family) {
  $own = Get-ChildItem -LiteralPath $families -Filter ($Family + '*.mbt') -File | Select-Object -First 1
  if ($null -eq $own) { return '' }
  $call = ''
  foreach ($l in [System.IO.File]::ReadAllLines($own.FullName)) {
    $s = $l.Trim()
    if ($s -ne '' -and -not $s.StartsWith('//')) { $call = $s }
  }
  return $call
}

# THE UNWRAPPER. It removes the `test` wrapper and puts the family's own call
# back. The function's name is READ from the file, so a fixture that is
# renamed does not need this script renamed with it.
function Unwrap-Test([string]$Path) {
  $lines = [System.IO.File]::ReadAllLines($Path)
  $out = New-Object System.Collections.Generic.List[string]
  $fnname = ''
  foreach ($l in $lines) {
    if ($l -match '^\s*test\s+"') { continue }
    if ($l -match '^\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)') { $fnname = $Matches[1] }
    $out.Add($l)
  }
  while ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq '') { $out.RemoveAt($out.Count - 1) }
  if ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq '}') { $out.RemoveAt($out.Count - 1) }
  $fam = Get-Family $Path
  $call = Get-OwnCall $fam
  if ($call -eq '' -and $fnname -ne '') { $call = $fnname + '()' }
  if ($call -ne '') { $out.Add($call) }
  return $out.ToArray()
}

# ================================================================= the self-test ===
if ($SelfTest) {
  Write-Output '=== the blind-spot pin, shown to be a real measurement ==='
  $bad = 0

  # THE CONTROL. The copy, as it is, must be GREEN: zero detected, and the only
  # family in the census is MSA-001 -- the scope-limit notice's own family. A
  # control that is not green proves nothing about the fault.
  $ctl = Join-Path $env:TEMP ('bsr_ctl_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $ctl | Out-Null
  try {
    Copy-Item -Path (Join-Path $fixtures '*.mbt') -Destination $ctl -Force
    $t = Invoke-Sweep $ctl
    $n = @(Get-ChildItem -LiteralPath $ctl -Filter '*.mbt' -File).Count
    $sum = Get-SummaryLine $t
    $act = Get-Field $sum 'actionable'
    $census = Get-Census $t
    $onlyMsa001 = ($census.Count -eq 1 -and $census.ContainsKey('MSA-001'))
    $ctlOk = ($act -eq 0 -and $onlyMsa001 -and $census['MSA-001'] -eq $n)
    Write-Output ('  CONTROL  ' + $n + ' fixture(s), actionable=' + $act + ', families in the census=' + $census.Count +
                  ' (MSA-001=' + $(if ($census.ContainsKey('MSA-001')) { $census['MSA-001'] } else { 'absent' }) + ')' +
                  '  -> ' + $(if ($ctlOk) { 'as it must be' } else { 'WRONG' }))
    if (-not $ctlOk) {
      $bad++
      Write-Output '    The control did not hold: the copy was not green before the fault was injected.'
    }
  } finally {
    Remove-Item -LiteralPath $ctl -Recurse -Force -ErrorAction SilentlyContinue
  }

  # THE FAULT. The SAME defects, with the `test` wrapper taken off. They must
  # be DETECTED -- that is what makes the pin a measurement of the wrapper and
  # not of the analyzer's eyesight -- and each of them as ITS OWN FAMILY.
  $flt = Join-Path $env:TEMP ('bsr_flt_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $flt | Out-Null
  try {
    $files = @(Get-ChildItem -LiteralPath $fixtures -Filter '*.mbt' -File | Sort-Object Name)
    $want = @{}
    foreach ($f in $files) {
      $lines = Unwrap-Test $f.FullName
      [System.IO.File]::WriteAllLines((Join-Path $flt $f.Name), $lines, (New-Object System.Text.UTF8Encoding($false)))
      $want[(Get-Family $f.FullName)] = $true
    }
    $t2 = Invoke-Sweep $flt
    $n2 = $files.Count
    $sum2 = Get-SummaryLine $t2
    $act2 = Get-Field $sum2 'actionable'
    $census2 = Get-Census $t2
    $faultOk = ($act2 -eq $n2)
    Write-Output ('  FAULT    the same ' + $n2 + ' defect(s) with the `test` wrapper removed, actionable=' + $act2 +
                  '  -> ' + $(if ($faultOk) { 'caught, as they must be' } else { 'MISSED' }))
    if (-not $faultOk) {
      $bad++
      Write-Output '    The defects stayed invisible outside a `test` body too, so the pin is measuring'
      Write-Output '    the analyzer''s eyesight and not the wrapper.'
    }
    # AND EACH OF THEM AS ITS OWN FAMILY. A count of six can come from six
    # families or from one family six times, and only the second is a pin on
    # what this increment claims to be about.
    foreach ($fam in ($want.Keys | Sort-Object)) {
      $seen = $census2.ContainsKey($fam) -and $census2[$fam] -gt 0
      Write-Output ('    ' + $fam + '  ' + $(if ($seen) { 'fired' } else { 'DID NOT FIRE' }))
      if (-not $seen) { $bad++ }
    }
  } finally {
    Remove-Item -LiteralPath $flt -Recurse -Force -ErrorAction SilentlyContinue
  }

  Write-Output ''
  if ($bad -eq 0) {
    Write-Output 'SELFTEST OK: the control is green, and the same defects are detected once the wrapper is off.'
    exit 0
  }
  Write-Output ('SELFTEST FAILED: ' + $bad + ' check(s) did not hold.')
  exit 1
}

# ==================================================================== the live run ===
Write-Output '=== the blind-spot rate: planted defects inside a `test` body ==='
$files = @(Get-ChildItem -LiteralPath $fixtures -Filter '*.mbt' -File | Sort-Object Name)
if ($files.Count -eq 0) {
  Write-Output ('ABORT: no fixtures in ' + $fixtures)
  exit 1
}
Write-Output ('  ' + $files.Count + ' blind-spot fixture(s):')
foreach ($f in $files) { Write-Output ('    ' + $f.Name + '  (' + (Get-Family $f.FullName) + ')') }

$text = Invoke-Sweep $fixtures
$sum = Get-SummaryLine $text
if ($sum -eq '') {
  Write-Output '  FAIL: the sweep printed no SUMMARY. A scan that did not run is not a clean scan.'
  exit 1
}
Write-Output ('  ' + $sum.Trim())

$fail = 0
$files_n = Get-Field $sum 'files'
$parsed = Get-Field $sum 'parsed'
$act = Get-Field $sum 'actionable'
$notices = Get-Field $sum 'notices'
$census = Get-Census $text

if ($files_n -ne $files.Count -or $parsed -ne $files.Count) {
  Write-Output ('  FAIL: the sweep read ' + $files_n + ' file(s) and parsed ' + $parsed + ', and the fixture set holds ' + $files.Count + '.')
  Write-Output '        A rate over a set that was not fully read is not a rate.'
  $fail++
}
if ($act -ne 0) {
  Write-Output ('  FAIL: ' + $act + ' planted defect(s) inside a `test` body were DETECTED.')
  Write-Output '        The blind spot has closed, or a fixture has stopped being blind -- either way this'
  Write-Output '        pin is stale and the number published from it must be re-measured.'
  $fail++
}
# THE CENSUS. Exactly one family, and it is the scope-limit notice's own.
$others = @($census.Keys | Where-Object { $_ -ne 'MSA-001' })
if ($others.Count -ne 0) {
  Write-Output ('  FAIL: the census names ' + ($others -join ', ') + ' -- a family that spoke inside a `test` body.')
  Write-Output '        The exclusion is not what this pin claims it is.'
  $fail++
}
if (-not $census.ContainsKey('MSA-001') -or $census['MSA-001'] -ne $files.Count) {
  Write-Output ('  FAIL: the MSA-001 census row says ' + $(if ($census.ContainsKey('MSA-001')) { $census['MSA-001'] } else { 'nothing' }) +
                ', and the fixture set holds ' + $files.Count + ' fixture(s).')
  Write-Output '        Each blind-spot fixture owes the reader ONE scope-limit notice -- the analyzer saying'
  Write-Output '        "I did not read this". A fixture that says nothing is a silent exclusion.'
  $fail++
}
if ($notices -ne $files.Count) {
  Write-Output ('  FAIL: the SUMMARY reported ' + $notices + ' notice(s) for ' + $files.Count + ' fixture(s).')
  $fail++
}

Write-Output ''
Write-Output ('  RATE: 0 of ' + $files.Count + ' planted defects inside a `test` body were detected.')
Write-Output '        (the same defects in a `fn` body: 18 of 18 -- see `_verify\check_family_fires.ps1`)'
if ($fail -eq 0) {
  Write-Output 'BLIND-SPOT RATE OK: every planted defect inside a `test` body is invisible, and every one of them says so.'
  exit 0
}
Write-Output ('BLIND-SPOT RATE FAILED: ' + $fail + ' problem(s).')
exit 1

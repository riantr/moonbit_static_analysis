# Settle 0642 -- THE VERDICT OF A CHAINED VERIFICATION MUST BE EVERY STAGE'S, NOT
# THE LAST STAGE'S.
#
# WHY. On 2026-11-23 a background task ran the tests and the README gate as ONE
# compound command:
#
#     moon -C $m test --deny-warn ... ; Write-Output "TEST=$LASTEXITCODE"
#     powershell ... check_readme_links.ps1 ... ; Write-Output "README_GATE=$LASTEXITCODE"
#
# and it reported FAILED, correctly, because the README gate really was red at
# that moment (26 problems). But the command had a defect that had NOT fired
# yet, and the defect is the point:
#
#     THE PROCESS EXIT CODE WAS THE LAST NATIVE COMMAND'S, NOT THE VERDICT.
#
# Each stage's code was PRINTED, and nothing aggregated them. So a red FIRST
# stage followed by a green LAST stage reported SUCCESS.
#
# MEASURED, on this machine, both directions, on the same fixture:
#
#     stage A red (exit 2), stage B green (exit 0)
#       the OLD shape   -> process exit 0    (the red stage was MASKED)
#       the FIXED shape -> process exit 1    (the red stage is CAUGHT)
#     stage A green (exit 0), stage B green (exit 0)
#       the FIXED shape -> process exit 0    (so the fix is not "always red")
#
# THE REPOSITORY DOES NOT HAVE THIS DEFECT, and that is a MEASUREMENT, not an
# assumption: `_verify/release.ps1` sets `$script:stageOk` per stage and appends
# to `$failed`, and the verdict is `$failed.Count`. So what this settle holds is
# the CLASS, in the tree, from now on.
#
# THE CLASS IS STATED, because a check that claims to hold a class must say
# which class it holds. It is: A CHILD GATE -- a `powershell` process a gate
# invokes, whose exit code becomes part of a verdict.
#
# IT IS NOT: a TOOLCHAIN call (`& moon ...`). A toolchain call inside a settle
# is not a stage; the settle's ROWS are the verdict there, and the rows are
# counted against expectations. Those sites are COUNTED and REPORTED below, so a
# reader can see them, but they are not asserted -- and the difference is the
# point: asserting them would mean a hand-written exception per site, and a
# list that long rots.
#
# A SITE THAT DOES NOT TAKE THE EXIT CODE IS ALLOWED ONLY IF THE FILE CARRIES A
# DIFFERENT MECHANISM THAT MAKES THE FAILURE VISIBLE, and that mechanism is
# FOUND IN THE FILE. An exception that is only asserted is an exception that
# rots.
#
# THE ROWS.
#
#   R1  CONTROL. Every child gate invoked in `_verify/*.ps1` has its exit code
#       taken before the next child process runs. The count that does NOT must
#       be 0.
#   R2  NEGATIVE CONTROL. The same detector, run on a COPY of a real site with
#       the capture removed. It must count that site -- a fault that changes
#       nothing proves nothing, and a detector that has never been seen to fail
#       is not a detector.
#   R3  RECORD. The OLD shape, measured on a fixture: first stage red, last
#       stage green -> the PROCESS reports GREEN. That is the defect, recorded.
#   R4  THE FIXED shape, same fixture -> the PROCESS reports RED.
#   R5  POSITIVE CONTROL. The FIXED shape, both stages green -> GREEN.
#
# IT WRITES NOTHING INTO THIS REPOSITORY. The fixtures live in %TEMP%.
$ErrorActionPreference = 'Stop'
$fail = 0
$root = Split-Path -Parent $PSScriptRoot
$verify = Join-Path $root '_verify'

# ---------------------------------------------------------------- the detector ---
# ONE implementation, used by R1 and by R2. A check computed in two places is
# two implementations of one claim, and the second one is the one that drifts.
function Get-InvocationSites {
  param([string]$Dir)
  $sites = @()
  foreach ($f in (Get-ChildItem -LiteralPath $Dir -Filter *.ps1 -File)) {
    $lines = [System.IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $ln = $lines[$i]
      # A COMMENT is not an invocation, and a line that merely MENTIONS one is
      # not an invocation either.
      if ($ln -match '^\s*#') { continue }
      # THE CLASS: a child GATE.
      if ($ln -notmatch '&\s*powershell\b') { continue }
      # THE CAPTURE. The exit code has to be taken before the NEXT child process
      # runs, because `$LASTEXITCODE` is overwritten by the next one.
      $taken = $false
      for ($k = $i + 1; $k -lt [Math]::Min($i + 4, $lines.Count); $k++) {
        if ($lines[$k] -match '\$LASTEXITCODE') { $taken = $true; break }
        if ($lines[$k] -match '^\s*#') { continue }
        if ($lines[$k] -match '&\s*powershell\b') { break }
      }
      $sites += [pscustomobject]@{
        File = $f.Name
        Line = $i + 1
        Text = $ln.Trim()
        Taken = $taken
      }
    }
  }
  return $sites
}

# The exceptions, each with the MECHANISM that has to be present in the file.
# The mechanism is CHECKED, not the note.
$exceptions = @(
  [pscustomobject]@{
    File = 'ab_0456_0457_coverage.ps1'
    Mechanism = 'not total'
    Why = 'the reach map is validated for TOTALITY and throws, so a failed child cannot pass silently'
  }
  [pscustomobject]@{
    File = 'grammar_probe_control.ps1'
    Mechanism = 'canary did not report'
    Why = 'the probe carries a canary, so "the probe did not run" is visible instead of silent'
  }
)

function Test-Exception {
  param([string]$Dir, [string]$FileName)
  foreach ($e in $exceptions) {
    if ($e.File -ne $FileName) { continue }
    $p = Join-Path $Dir $e.File
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $t = [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
    if ($t.Contains($e.Mechanism)) { return $e }
    return $null
  }
  return $null
}

Write-Output '=== R1  CONTROL: every child gate in _verify has its exit code taken ==='
$live = @(Get-InvocationSites $verify)
$notTaken = @($live | Where-Object { -not $_.Taken })
$allowed = @()
$unexplained = @()
foreach ($s in $notTaken) {
  $e = Test-Exception -Dir $verify -FileName $s.File
  if ($null -eq $e) { $unexplained += $s } else { $allowed += $s }
}
Write-Output ('  ' + $live.Count + ' child-gate invocation site(s) in _verify, ' + $notTaken.Count + ' without an exit-code capture')
if ($unexplained.Count -eq 0) {
  Write-Output '  OK: every one of them takes its exit code, or carries a stated mechanism that makes a failure visible'
} else {
  Write-Output ('  FAIL: ' + $unexplained.Count + ' site(s) take no exit code and have NO stated mechanism:')
  foreach ($s in $unexplained) { Write-Output ('      ' + $s.File + ':' + $s.Line + '  ' + $s.Text) }
  $fail++
}
foreach ($s in $allowed) {
  $e = Test-Exception -Dir $verify -FileName $s.File
  Write-Output ('  note: ' + $s.File + ':' + $s.Line + ' takes no exit code, and its mechanism is present: ' + $e.Why)
}

# THE TOOLCHAIN CALLS. Reported, not asserted -- see the header. A reader can see
# them, and the count moves as the tree moves, so it is not a pin.
$toolchain = 0
foreach ($f in (Get-ChildItem -LiteralPath $verify -Filter *.ps1 -File)) {
  $lines = [System.IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]
    if ($ln -match '^\s*#') { continue }
    if (($ln -match '&\s*\$moon\b') -or ($ln -match '&\s*moon\b')) { $toolchain++ }
  }
}
Write-Output ('  note: ' + $toolchain + ' toolchain call site(s) are outside this class, and are counted here rather than asserted')

Write-Output ''
Write-Output '=== R2  NEGATIVE CONTROL: the detector must SEE a site that lost its capture ==='
$scratch = Join-Path $env:TEMP ('settle0642_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
  # A COPY of a file that HAS a capture, with the captures stripped. The file is
  # chosen from the sites the detector just found, so the fault is a real one
  # and not a shape invented for the occasion.
  $candidates = @($live | Where-Object { $_.Taken })
  $chosen = $null
  foreach ($c in $candidates) {
    if ($null -eq (Test-Exception -Dir $verify -FileName $c.File)) { $chosen = $c; break }
  }
  if ($null -eq $chosen) {
    Write-Output '  FAIL: no file with a capture was found, so the negative control proved nothing.'
    $fail++
  } else {
    $src = Join-Path $verify $chosen.File
    $copyText = [System.IO.File]::ReadAllText($src, [Text.Encoding]::UTF8)
    $before = ([regex]::Matches($copyText, '(?m)^\s*\$\w+\s*=\s*\$LASTEXITCODE')).Count
    $stripped = [regex]::Replace($copyText, '(?m)^\s*\$\w+\s*=\s*\$LASTEXITCODE[^\r\n]*\r?\n', '')
    $after = ([regex]::Matches($stripped, '(?m)^\s*\$\w+\s*=\s*\$LASTEXITCODE')).Count
    if ($before -eq 0) {
      Write-Output ('  FAIL: ' + $chosen.File + ' carries no capture line to remove, so the negative control proved nothing.')
      $fail++
    } elseif ($after -ne ($before - 1)) {
      Write-Output ('  FAIL: the copy removed ' + ($before - $after) + ' capture line(s) from ' + $chosen.File + '; it had to remove exactly one.')
      $fail++
    } else {
      Write-Output ('  ok  the copy of ' + $chosen.File + ' lost exactly one capture line (' + $before + ' -> ' + $after + ')')
      $copyPath = Join-Path $scratch $chosen.File
      [System.IO.File]::WriteAllText($copyPath, $stripped, (New-Object System.Text.UTF8Encoding($false)))
      $copySites = @(Get-InvocationSites $scratch)
      $copyNotTaken = @($copySites | Where-Object { -not $_.Taken })
      $copyUnexplained = @()
      foreach ($s in $copyNotTaken) {
        if ($null -eq (Test-Exception -Dir $scratch -FileName $s.File)) { $copyUnexplained += $s }
      }
      if ($copyUnexplained.Count -ge 1) {
        Write-Output ('  ok  the detector SAW it: ' + $copyUnexplained.Count + ' site(s) without a capture, and the copy carries no exception')
        foreach ($s in $copyUnexplained) { Write-Output ('      ' + $s.File + ':' + $s.Line) }
      } else {
        Write-Output '  FAIL: the detector did not see the fault, so R1 measures nothing.'
        $fail++
      }
    }
  }
} finally {
  Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------- the two shapes, measured ------
# The fixture is SYNTHETIC on purpose: the claim is about how a verdict is
# COMPOSED, and that composition does not depend on which gates are being run.
# The real runner and the real gates are measured by R1.
$fixture = Join-Path $env:TEMP ('settle0642_shape_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
try {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path $fixture 'stage_red.ps1'), "exit 2`n", $enc)
  [System.IO.File]::WriteAllText((Join-Path $fixture 'stage_green.ps1'), "exit 0`n", $enc)
  # THE OLD SHAPE: each stage's code is PRINTED, and the process exit code is
  # whatever the LAST native command left behind.
  $old = @'
$ErrorActionPreference = 'Continue'
$d = Split-Path -Parent $MyInvocation.MyCommand.Path
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $d 'stage_red.ps1') | Out-Null
Write-Output ('A=' + $LASTEXITCODE)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $d 'stage_green.ps1') | Out-Null
Write-Output ('B=' + $LASTEXITCODE)
'@
  [System.IO.File]::WriteAllText((Join-Path $fixture 'old_shape.ps1'), $old, $enc)
  # THE FIXED SHAPE: every stage's code is taken, and the verdict is their OR.
  $new = @'
$ErrorActionPreference = 'Continue'
$d = Split-Path -Parent $MyInvocation.MyCommand.Path
$fail = 0
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $d 'stage_red.ps1') | Out-Null
$a = $LASTEXITCODE
Write-Output ('A=' + $a)
if ($a -ne 0) { $fail = 1 }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $d 'stage_green.ps1') | Out-Null
$b = $LASTEXITCODE
Write-Output ('B=' + $b)
if ($b -ne 0) { $fail = 1 }
if ($fail -ne 0) { exit 1 }
exit 0
'@
  [System.IO.File]::WriteAllText((Join-Path $fixture 'new_shape.ps1'), $new, $enc)

  # THE FAULT MUST LAND: the red stage has to be red, and the green one green.
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'stage_red.ps1') | Out-Null
  $redCode = $LASTEXITCODE
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'stage_green.ps1') | Out-Null
  $greenCode = $LASTEXITCODE
  Write-Output ''
  Write-Output '=== the fixture is what it claims to be ==='
  if ($redCode -eq 0) {
    Write-Output '  FAIL: the red stage exited 0, so the rows below would prove nothing.'
    $fail++
  } else {
    Write-Output ('  ok  the red stage exits ' + $redCode)
  }
  if ($greenCode -ne 0) {
    Write-Output ('  FAIL: the green stage exits ' + $greenCode + ', so it is not green.')
    $fail++
  } else {
    Write-Output '  ok  the green stage exits 0'
  }

  Write-Output ''
  Write-Output '=== R3  RECORD: the OLD shape masks a red first stage ==='
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'old_shape.ps1') | Out-Null
  $oldCode = $LASTEXITCODE
  Write-Output ('  the old shape, with a red FIRST stage, exits ' + $oldCode)
  if ($oldCode -eq 0) {
    Write-Output '  ok  RECORDED: the process reported success with a red stage inside it. That is the defect.'
  } else {
    Write-Output ('  note: the old shape exits ' + $oldCode + ' here, so the defect does not reproduce on this host')
  }

  Write-Output ''
  Write-Output '=== R4  the FIXED shape catches a red first stage ==='
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'new_shape.ps1') | Out-Null
  $newCode = $LASTEXITCODE
  Write-Output ('  the fixed shape, with the same fixture, exits ' + $newCode)
  if ($newCode -ne 0) {
    Write-Output '  ok  the red stage is caught'
  } else {
    Write-Output '  FAIL: the fixed shape reported success with a red stage inside it.'
    $fail++
  }

  Write-Output ''
  Write-Output '=== R5  POSITIVE CONTROL: the FIXED shape is not always red ==='
  # The same shape, with a GREEN first stage. The verdict must be green, or the
  # fix is not a fix -- it is a broken verifier.
  $greenFirst = $new.Replace('stage_red.ps1', 'stage_green.ps1')
  [System.IO.File]::WriteAllText((Join-Path $fixture 'new_shape_green.ps1'), $greenFirst, $enc)
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'new_shape_green.ps1') | Out-Null
  $greenAllCode = $LASTEXITCODE
  Write-Output ('  the fixed shape, with both stages green, exits ' + $greenAllCode)
  if ($greenAllCode -eq 0) {
    Write-Output '  ok  the fixed shape reports success when every stage is green'
  } else {
    Write-Output '  FAIL: the fixed shape reports failure with every stage green.'
    $fail++
  }
} finally {
  Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output ('ABORT: ' + $fail + ' row(s) failed.')
  exit 1
}
Write-Output 'GATE OK. Read the rows above -- they are the answer, not this line.'
exit 0

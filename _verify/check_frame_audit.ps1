$ErrorActionPreference = 'Continue'
# Verify the FRAME AUDIT is per binding, not per function.
#
# WHY THIS EXISTS. `Walker::audit_suppressed` was a single Bool over a
# function's extent: one region the frontend did not analyse anywhere in the
# function switched off EVERY conclusion the frame could support. A `match` at
# the end of a function took the unused-local verdict away from a binding
# declared at the top of it -- a binding the unread region cannot have read,
# because the region comes later.
#
# 0501 replaced the Bool with the LIST of regions, and the frame audit now
# judges each binding against the regions that can reach it.
#
# WHAT IT CHECKS, and each item is a thing that can be WRONG:
#
#   1. THE OUTPUT CONTRACT, on the real scanner and not on the library. Six
#      fixtures, each scanned, each asserted on the family counts AND on the
#      notice count -- because a narrowing that also lost the notice would be
#      a coverage loss dressed as a fix.
#
#   2. THE NEGATIVE DIRECTION, which is the one that matters. The binding that
#      is read ONLY inside the unread region must NOT be reported: that is the
#      false positive the narrowing exists to avoid, and it is the assertion
#      that goes red if the rule is ever wrong in the direction that hurts.
#
#   3. THE FIXTURES ARE NOT VACUOUS. Every fixture that asserts silence
#      asserts a notice as well, so "nothing was reported" cannot be read as
#      "there was no region to report about".
#
# There is no -SelfTest switch, and that is deliberate: this gate is shown to go
# red by INJECTING a defect into the tree and running it, which is a stronger
# statement than a switch that reproduces the checker's own logic.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_frame_audit.ps1

$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$repos = Join-Path $root '.repos'
$fail = 0

if (-not (Test-Path -LiteralPath $wasm)) {
  Write-Output 'ABORT: no wasm artifact. Build it first.'
  exit 1
}

# --- the fixtures ------------------------------------------------------------
# Each is a whole file, so the counts are per file and cannot be confused with
# one another. `after_region` is the shape 0501 makes judgeable; `before_region`
# and `read_inside_region` are the shapes it must leave alone.
$FIXTURES = [ordered]@{
  'after_region.mbt' = @(
    'fn f(z : Int) {'
    '  match z {'
    '    0 => 1'
    '    _ => 0'
    '  }'
    '  let never_read = 1'
    '}'
  )
  'after_region_if.mbt' = @(
    'fn f(z : Int) {'
    '  let _ = if z > 0 {'
    '    1'
    '  } else {'
    '    0'
    '  }'
    '  let never_read = 1'
    '}'
  )
  'before_region.mbt' = @(
    'fn f(z : Int) {'
    '  let maybe_used = 1'
    '  match z {'
    '    0 => 1'
    '    _ => 0'
    '  }'
    '}'
  )
  'read_inside_region.mbt' = @(
    'fn f(z : Int) {'
    '  let maybe_used = 1'
    '  match z {'
    '    0 => maybe_used'
    '    _ => 0'
    '  }'
    '}'
  )
  'param_in_region.mbt' = @(
    'fn f(unused_param : Int, z : Int) {'
    '  match z {'
    '    0 => 1'
    '    _ => 0'
    '  }'
    '}'
  )
  'no_region.mbt' = @(
    'fn f() {'
    '  let never_read = 1'
    '}'
  )
  # THE POSITION MATTERS. A statement-position `if` is parsed into the tree and
  # its branches are analysed, so it is NOT a region: no notice, and nothing
  # suppressed. Without this fixture, "a local declared after an `if` is
  # reported" could be true of a statement-position `if` -- where there is no
  # region and no narrowing involved -- and the narrowing would never have
  # been tested at all.
  'statement_if_not_a_region.mbt' = @(
    'fn f(z : Int) {'
    '  if z > 0 {'
    '    1'
    '  } else {'
    '    0'
    '  }'
    '  let never_read = 1'
    '}'
  )
  'two_functions.mbt' = @(
    'fn first() {'
    '  let never_read = 1'
    '}'
    'fn second(z : Int) {'
    '  match z {'
    '    0 => 1'
    '    _ => 0'
    '  }'
    '}'
  )
}

# what each fixture must produce: UnusedLocal, UnusedParam, notices
$EXPECT = [ordered]@{
  'after_region.mbt'       = @(1, 0, 1)
  'after_region_if.mbt'    = @(1, 0, 1)
  'before_region.mbt'      = @(0, 0, 1)
  'read_inside_region.mbt' = @(0, 0, 1)
  'param_in_region.mbt'    = @(0, 0, 1)
  'no_region.mbt'          = @(1, 0, 0)
  'statement_if_not_a_region.mbt' = @(1, 0, 0)
  # THE EXTENT FILTER, which nothing else here exercises. The region is in the
  # SECOND function, and the binding is in the FIRST. A region in another
  # function cannot have read this binding, so the binding is judged -- and if
  # the extent filter is dropped, the region reaches across and silences it.
  'two_functions.mbt' = @(1, 0, 1)
}

$dir = Join-Path $env:TEMP ('frameaudit_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
foreach ($name in $FIXTURES.Keys) {
  [IO.File]::WriteAllText((Join-Path $dir $name), ($FIXTURES[$name] -join "`n") + "`n", $enc)
}
$out = Join-Path $dir 'o.txt'; $errf = Join-Path $dir 'o.err'
Start-Process -FilePath $moonrun `
  -ArgumentList @($wasm, $dir, '--extern-iface-dir', $repos, '--no-auto-fetch-deps',
                  '--findings-shown-per-file', '1000000') `
  -RedirectStandardOutput $out -RedirectStandardError $errf -NoNewWindow -Wait | Out-Null
$t = [IO.File]::ReadAllText($out)

# --- collect the findings, per file -----------------------------------------
# The file comes from the header above the findings, and it is the LAST tab
# separated field of it: `FOUND <kind> <defects> <notices> <path>`.
#
# The file is keyed by its LEAF NAME, not by the path. The scanner writes the
# path with a FORWARD slash before the file name (`<dir>/after_region.mbt`)
# while `Join-Path` produces a BACKSLASH, so a path comparison misses every
# file and every count comes out zero -- which reads as "nothing was found"
# rather than "nothing was looked for".
$perFile = @{}
$file = ''
foreach ($ln in ($t -split "`r?`n")) {
  if ($ln -match '^(FOUND|CLEAN)\t') {
    $parts = $ln -split "`t"
    $file = ($parts[$parts.Count - 1].Trim() -split '[\\/]')[-1]
    if (-not $perFile.ContainsKey($file)) { $perFile[$file] = @() }
    continue
  }
  if ($ln -match '^\d+:\d+ - (error|warning|hint|notice): (.*) \((\w+)\) \[([^\]]*)\]\s*$') {
    if (-not $perFile.ContainsKey($file)) { $perFile[$file] = @() }
    $perFile[$file] = $perFile[$file] + @($Matches[3])
  }
}

Write-Output '=== 1. the output contract, on the real scanner ==='
foreach ($name in $FIXTURES.Keys) {
  $fams = @()
  if ($perFile.ContainsKey($name)) { $fams = $perFile[$name] }
  $ul = @($fams | Where-Object { $_ -eq 'UnusedLocal' }).Count
  $up = @($fams | Where-Object { $_ -eq 'UnusedParam' }).Count
  $nt = @($fams | Where-Object { $_ -eq 'ParseError' }).Count
  $want = $EXPECT[$name]
  $ok = ($ul -eq $want[0]) -and ($up -eq $want[1]) -and ($nt -eq $want[2])
  $mark = if ($ok) { 'ok  ' } else { 'FAIL' }
  if (-not $ok) { $fail++ }
  Write-Output ("  {0} {1,-24} UnusedLocal={2} UnusedParam={3} notices={4}   (want {5}/{6}/{7})" -f `
    $mark, $name, $ul, $up, $nt, $want[0], $want[1], $want[2])
}

Write-Output ''
Write-Output '=== 2. the negative direction: a binding read ONLY inside the region ==='
# The one assertion that must not be traded away. `read_inside_region.mbt` has
# a binding that is read only by the unread arms, so reporting it would be a
# false positive on correct code.
$rp = 'read_inside_region.mbt'
$fams = @()
if ($perFile.ContainsKey($rp)) { $fams = $perFile[$rp] }
$ul = @($fams | Where-Object { $_ -eq 'UnusedLocal' }).Count
$nt = @($fams | Where-Object { $_ -eq 'ParseError' }).Count
if ($ul -ne 0) {
  Write-Output ("  FAIL: a binding read only inside the region was reported ({0} UnusedLocal)" -f $ul)
  $fail++
} else {
  Write-Output '  ok   a binding read only inside the region is NOT reported'
}
if ($nt -ne 1) {
  Write-Output ("  FAIL: the region itself was not reported ({0} notices) -- the fixture proves nothing" -f $nt)
  $fail++
} else {
  Write-Output '  ok   and the region IS reported, so the silence above is a fact'
}

Write-Output ''
Write-Output '=== 3. the fixtures are not vacuous ==='
foreach ($name in $FIXTURES.Keys) {
  if (-not $perFile.ContainsKey($name)) {
    Write-Output ("  FAIL: " + $name + " produced no findings at all -- the scanner did not read it")
    $fail++
  }
}
if ($fail -eq 0) { Write-Output '  ok   every fixture was read' }

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'GATE OK: the frame audit judges per binding, and spares the bindings an unread region could have read.'
  exit 0
} else {
  Write-Output ("GATE FAILED: " + $fail + " check(s).")
  exit 1
}

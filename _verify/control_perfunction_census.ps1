# The POSITIVE CONTROL for the per-function census.
#
# WHAT THIS SETTLES. The per-function view reports actionable findings in
# `moonbitlang/core`. The README is going to say that NONE of them is a defect
# in the analysed code, and that claim needs two halves:
#
#   1. ACCEPTED -- `moon check` reports no diagnostic at any of those sites.
#   2. READ     -- `moon check` actually LOOKED at those files.
#
# The second half is the one a number cannot show. A file with no diagnostic is
# indistinguishable from a file nobody opened, so the control OPENS the file:
# a deliberate type error is appended, and the error MUST come back for THAT
# file.
#
# 0570: THE CORPUS IS CLEAN NOW, AND THAT CHANGES THE CONTROL'S WHOLE SHAPE.
#
# The pin used to be `moonbitlang/core 0.1.20260920+7d59c7ec9`, and THAT corpus
# carried exactly one diagnostic -- `abort/pkg.mbti:4`, where the `String` of
# `fn[T] abort(String) -> T` is out of scope because the core is self-hosted and
# this toolchain type-checks interface files. The checker BAILS on that error
# before it type-checks anything else: every probe came back carrying that one
# error and the probe's own error never appeared, so the control read 0 of 18
# files and the stage had been RED since 0.4.43.
#
# The re-pin to `0.1.20261105+65efd5b93` moves the corpus to a version this
# toolchain can check END TO END. MEASURED 2026-11-13 on a copy:
#
#   `moon check --target all`  ->  exit 0, 28 s, ZERO diagnostics.
#
# So the baseline this control demands is now the STRONGEST one there is -- no
# errors at all -- and a check that produced zero errors is no longer
# ambiguous: the corpus is clean, and the control says so.
#
# THE COST IS THE PROBES. One `moon check` on the corpus takes ~28 s, and the
# per-file loop costs one of those per file -- about nine minutes for nineteen
# files. So the control tries the FAST PATH first: every probe at once, ONE
# check, and every probe must come back. When one does not, the slow per-file
# loop runs for the files that did not, and only to say WHICH file was not
# read -- because `moon check` skips every package whose dependency failed, and
# a probe in one package can hide the probe in another.
#
# TWO FACTS THAT COST THIS SCRIPT A WRONG ANSWER, both measured:
#
#   1. THE TARGET MATTERS. MoonBit's per-file `targets` options in `moon.pkg`
#      decide which files a given target compiles. `moon check --target js`
#      NEVER COMPILES `bigint/bigint_default.mbt` ("not","js","wasm","native"
#      -- that is the wasm-gc target), `bigint/bigint_wide.mbt` ("native",
#      "wasm"), `bigint/decimal_wide.mbt`, `builtin/double_scalbn.mbt` and
#      `math/algebraic_double_nonjs.mbt` ("not","js"). Five of the files that
#      carry a finding therefore produced NO probe error under `--target js` --
#      which reads exactly like "the file is not read", and is not. Under
#      `--target all` every one of them is reported.
#   2. A FILE WITH NO DIAGNOSTIC IS NOT EVIDENCE. It is the reason the probe
#      exists at all: "no diagnostic" and "nobody opened it" are the same
#      observation until something breaks the file on purpose.
#
# The corpus is COPIED, never edited: the probe is written into the copy and
# the copy is thrown away. The pinned corpus directory is never touched.
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$repos = Join-Path $root '.repos'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$coreRel = 'moonbitlang\core\0.1.20261105+65efd5b93'
$core = Join-Path $repos $coreRel

$BOX = [regex]::Escape(([string][char]0x256D) + ([string][char]0x2500))
$enc = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $core)) { Write-Output ("MISSING corpus: " + $core); exit 1 }
if (-not (Test-Path -LiteralPath $wasm)) { Write-Output ("MISSING wasm: " + $wasm); exit 1 }

# --- 1  the files that carry an actionable finding -----------------------------
$out = Join-Path $env:TEMP ('pfctl_' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.txt')
$errf = Join-Path $env:TEMP ('pfctl_' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.err')
$p = Start-Process -FilePath $moonrun -ArgumentList @(
      $wasm, $core, '--extern-iface-dir', $repos, '--no-auto-fetch-deps',
      '--per-function', '--findings-shown-per-file', '1000000'
    ) -WorkingDirectory $root -RedirectStandardOutput $out -RedirectStandardError $errf -NoNewWindow -Wait -PassThru
$txt = [System.IO.File]::ReadAllText($out, [System.Text.Encoding]::UTF8)
Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $errf -Force -ErrorAction SilentlyContinue

$corpusRoot = [regex]::Escape($core.TrimEnd('\'))
$files = @()
$cur = ''
foreach ($l in ($txt -split "`r?`n")) {
  $t = $l -split "`t"
  if ($t.Count -ge 2 -and ($t[0] -in @('FOUND','PARTIAL','CLEAN'))) { $cur = ($t[-1].Trim() -replace ('^' + $corpusRoot + '[\\/]'), ''); continue }
  if (($l -match ' - error: ' -or $l -match ' - warning: ') -and $l -notmatch '\(ParseError\)') {
    if ($files -notcontains $cur) { $files += $cur }
  }
}
Write-Output ("=== files carrying an actionable finding: " + $files.Count + " ===")
foreach ($f in $files) { Write-Output ('  ' + $f) }
if ($files.Count -eq 0) { Write-Output 'NO FILES: the census found nothing, so there is nothing to control.'; exit 1 }

# --- 2  the copy ---------------------------------------------------------------
$scratch = Join-Path $env:TEMP ('corectl_' + [guid]::NewGuid().ToString('N').Substring(0,6))
Copy-Item -LiteralPath $core -Destination $scratch -Recurse -Force
Remove-Item -LiteralPath (Join-Path $scratch '_build') -Recurse -Force -ErrorAction SilentlyContinue

function Check {
  $o = Join-Path $env:TEMP ('chk_' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.out')
  $e = Join-Path $env:TEMP ('chk_' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.err')
  $pp = Start-Process -FilePath $moon -ArgumentList @('check','--target','all') -WorkingDirectory $scratch -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -Wait -PassThru
  $t = ''
  if (Test-Path $e) { $t = [System.IO.File]::ReadAllText($e, [System.Text.Encoding]::UTF8) }
  if (Test-Path $o) { $t += [System.IO.File]::ReadAllText($o, [System.Text.Encoding]::UTF8) }
  $errs = @(); $sev = ''; $unparsed = @()
  foreach ($l in ($t -split "`r?`n")) {
    if ($l -match '^(Error|Warning):\s*\[(\d+)\]') { $sev = $Matches[1]; continue }
    # 0519: A DIAGNOSTIC THE TOOLCHAIN DID NOT ATTRIBUTE TO A SOURCE LOCATION.
    # `moon check` prints these when it could not run at all --
    #     Error: failed to run check for targets [Wasm, WasmGC, Js, Native]
    #     Error: failed when checking project
    # -- and the locator parser below cannot see them. Before this line they
    # arrived as ZERO errors, which is exactly what a clean tree returns. So
    # "the check never ran" and "nothing is wrong" were the same value, and the
    # baseline reported a pass it had not earned. They are now a separate,
    # loud result that no caller can mistake for silence.
    if ($l -match '^Error:')      { $unparsed += $l.Trim(); $sev = 'Error';   continue }
    if ($l -match '^Warning:')    { $sev = 'Warning'; continue }
    $m = [regex]::Match($l, $BOX + '\[\s*(.+):(\d+):(\d+)\s*\]')
    if ($m.Success -and $sev -eq 'Error') {
      $rel = $m.Groups[1].Value -replace ('.*' + [regex]::Escape($scratch) + '[\\/]'), ''
      $errs += (($rel -replace '\\','/') + ':' + $m.Groups[2].Value)
    }
  }
  return [pscustomobject]@{ Errors = $errs; Unparsed = $unparsed; Exit = $pp.ExitCode }
}

# `@()` matters here and is not decoration. `Check` now returns an OBJECT, but
# its `Errors` member is an array that PowerShell UNROLLS to a scalar STRING
# when it holds exactly one element -- `$after[0]` on a string is its first
# CHARACTER, not its first element, so the restore check would compare 'j' with
# the expected path and report a restore that did not happen. Every read of
# `.Errors` therefore goes through `@()`.

# THE PROBE. A deliberate type error appended to the file: a `const` whose
# annotation says Int and whose value is a String.
#
# THE NAME IS UNIQUE PER FILE, and that is not tidiness. The corpus has more
# than one file in some packages, and two probes with the same name in the same
# package would be a DUPLICATE DEFINITION -- a second error, in a file the
# control did not probe, which would read as "every file is read" and prove
# nothing.
function ProbeText([int]$i) {
  return "`nconst __probe_0570_" + $i + " : Int = `"not an int`"`n"
}

# --- 3  the baseline: the corpus's own errors ----------------------------------
Write-Output ''
Write-Output '=== BASELINE: moon check --target all on an untouched COPY ==='
$t0 = Get-Date
$res = Check
$base = @($res.Errors)
Write-Output ("elapsed=" + [int]((Get-Date) - $t0).TotalSeconds + "s  exit=" + $res.Exit + "  errors=" + $base.Count)
foreach ($e in $base) { Write-Output ('  ERROR ' + $e) }

# THE BASELINE MUST BE EMPTY, AND IT MUST HAVE BEEN PRODUCED BY A CHECK THAT
# RAN.
#
# The pinned corpus is CLEAN -- measured, exit 0 and zero diagnostics -- so
# "one error, the known one" is no longer the shape of this baseline. What is
# left is the STRONGER claim, and it is the one the corpus now earns: the
# toolchain type-checks the whole corpus and finds nothing wrong with it.
#
# The two ways to have NO errors are still different things, and both are
# checked:
#
#   * the check DID NOT RUN -- `moon check` printed a failure it could not
#     attribute to a source location. The corpus was never type-checked, and a
#     corpus that cannot be checked is not a corpus with nothing wrong.
#   * the check RAN AND FOUND NOTHING -- exit 0, no attributed error, no
#     unattributed error. That is the baseline, and it is the only pass.
if (@($res.Errors).Count -eq 0 -and $res.Unparsed.Count -gt 0) {
  Write-Output 'BASELINE FAILED: `moon check` reported a failure and attributed it to NO source location,'
  Write-Output '  so the corpus was never type-checked and this control has nothing to stand on:'
  foreach ($u in $res.Unparsed) { Write-Output ('    ' + $u) }
  Write-Output '  A corpus that cannot be checked is not a corpus with nothing wrong.'
  exit 1
}
if (@($res.Errors).Count -ne 0) {
  Write-Output ('BASELINE FAILED: the corpus is not clean -- ' + $base.Count + ' error(s): ' + ($base -join ' '))
  Write-Output 'A corpus that grew an error changes the claim, so this control refuses to absorb it.'
  exit 1
}
if ($res.Exit -ne 0) {
  Write-Output ('BASELINE FAILED: `moon check` exited ' + $res.Exit + ' with no attributed error.')
  Write-Output '  Silence is not a clean tree.'
  exit 1
}
Write-Output 'baseline is CLEAN: `moon check --target all` reads the whole corpus and finds nothing wrong with it.'

# --- 4  the positive control --------------------------------------------------
#
# THE FAST PATH: every probe at once, ONE check, and every probe must come
# back. `moon check` reports every error it finds in a package, so a batch of
# independent probes in independent packages comes back as a batch.
#
# The fallback is the per-file loop, and it exists because `moon check` SKIPS
# every package whose dependency failed: a probe in one package can hide the
# probe in a package that depends on it. The fallback is what says WHICH file
# was not read, and it is also what answers the question when the batch is
# inconclusive.
Write-Output ''
Write-Output '=== the positive control: a deliberate type error, in every file that carries a finding ==='
$orig = @{}
$i = 0
$probeable = @()
foreach ($f in $files) {
  $i++
  $fp = Join-Path $scratch ($f -replace '/', '\')
  if (-not (Test-Path -LiteralPath $fp)) { Write-Output ('  MISSING ' + $f); continue }
  $orig[$f] = [System.IO.File]::ReadAllText($fp, [System.Text.Encoding]::UTF8)
  [System.IO.File]::WriteAllText($fp, $orig[$f] + (ProbeText $i), $enc)
  $probeable += $f
}

$resAll = Check
$errsAll = @($resAll.Errors)
foreach ($f in $probeable) {
  $fp = Join-Path $scratch ($f -replace '/', '\')
  [System.IO.File]::WriteAllText($fp, $orig[$f], $enc)   # restore byte-exactly
}

$read = @()
$notRead = @()
foreach ($f in $probeable) {
  if (@($errsAll | Where-Object { $_ -like ($f + ':*') }).Count -ge 1) { $read += $f } else { $notRead += $f }
}
Write-Output ('  the batched probe: ' + $read.Count + ' of ' + $probeable.Count + ' came back in ONE check')

if ($notRead.Count -gt 0) {
  # THE SLOW PATH, and it is only for the files the batch could not answer.
  #
  # THE BATCH USUALLY CANNOT ANSWER, and the reason is worth stating: `moon
  # check` SKIPS every package whose dependency failed, so a probe in one
  # package hides the probe in every package that depends on it. On this
  # corpus the batch came back with ONE of seventeen. The per-file loop is
  # therefore the MEASUREMENT, and the batch is only a way to save the time
  # when the corpus happens to have one finding per independent package.
  Write-Output ('  the batch was inconclusive for ' + $notRead.Count + ' file(s); probing them one at a time:')
  foreach ($f in $notRead) {
    $fp = Join-Path $scratch ($f -replace '/', '\')
    [System.IO.File]::WriteAllText($fp, $orig[$f] + (ProbeText 1), $enc)
    $pres = Check
    $r = @($pres.Errors)
    [System.IO.File]::WriteAllText($fp, $orig[$f], $enc)   # restore byte-exactly
    if (@($r | Where-Object { $_ -like ($f + ':*') }).Count -ge 1) {
      $read += $f
      Write-Output ('  READ     ' + $f)
    } else {
      $why = ''
      if (@($r).Count -eq 0 -and $pres.Unparsed.Count -gt 0) { $why = '   the check attributed nothing: ' + $pres.Unparsed[0] }
      Write-Output ('  NOT READ ' + $f + '   errors=' + $r.Count + '  ' + ($r -join ' ') + $why)
    }
  }
}
$miss = @()
foreach ($f in $probeable) { if ($read -notcontains $f) { $miss += $f } }
foreach ($f in $files) { if ($probeable -notcontains $f) { $miss += $f } }

Write-Output ''
Write-Output ("read by moon check: " + $read.Count + " of " + $files.Count)
if ($miss.Count -gt 0) { Write-Output ('NOT READ: ' + $miss.Count); foreach ($m in $miss) { Write-Output ('  ' + $m) } }

# --- 5  the tree is restored, so the baseline must come back alone -------------
$afterRes = Check
$after = @($afterRes.Errors)
Write-Output ("after restore: exit=" + $afterRes.Exit + "  errors=" + $after.Count + "  " + ($after -join ' '))
if (@($after).Count -eq 0 -and $afterRes.Unparsed.Count -gt 0) {
  Write-Output ('RESTORE FAILED: the check after the restore attributed nothing: ' + ($afterRes.Unparsed -join ' | '))
  exit 1
}
if ($after.Count -ne 0) { Write-Output 'RESTORE FAILED: the copy is not back to its baseline state.'; exit 1 }
if ($afterRes.Exit -ne 0) { Write-Output ('RESTORE FAILED: `moon check` exited ' + $afterRes.Exit + ' after the restore.'); exit 1 }

Write-Output ''
if ($miss.Count -eq 0) {
  Write-Output ('GATE OK: all ' + $files.Count + ' files that carry an actionable finding are READ by moon check,')
  Write-Output 'and the corpus itself is CLEAN: `moon check --target all` reads all of it and finds nothing wrong.'
  exit 0
}
Write-Output 'GATE FAILED.'
exit 1

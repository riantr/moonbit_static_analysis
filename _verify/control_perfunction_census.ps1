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
# file. One file at a time, because a broken package makes the toolchain stop
# type-checking the packages that depend on it -- and a run that finishes
# suspiciously fast did not run the suite.
#
# TWO FACTS THAT COST THIS SCRIPT A WRONG ANSWER, both measured:
#
#   1. THE TARGET MATTERS. MoonBit's per-file `targets` options in `moon.pkg`
#      decide which files a given target compiles. `moon check --target js`
#      NEVER COMPILES `bigint/bigint_default.mbt` ("not","js","wasm","native"
#      -- that is the wasm-gc target), `bigint/bigint_wide.mbt` ("native",
#      "wasm"), `bigint/decimal_wide.mbt`, `builtin/double_scalbn.mbt` and
#      `math/algebraic_double_nonjs.mbt` ("not","js"). Five of the files that
#      carry a finding therefore produced NO probe error under `--target js` -- which
#      reads exactly like "the file is not read", and is not. Under
#      `--target all` every one of them is reported.
#   2. A FILE WITH NO DIAGNOSTIC IS NOT EVIDENCE. The corpus-wide check
#      reports exactly ONE error, in `abort/pkg.mbti` -- the pinned core is
#      self-hosted and this toolchain type-checks interface files, so the
#      `String` in that one is out of scope -- and it is not one of the files
#      that carry a finding. So those files carry nothing, and the control
#      proves they are read.
#
# The corpus is COPIED, never edited: the probe is written into the copy and
# the copy is thrown away. The pinned corpus directory is never touched.
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$repos = Join-Path $root '.repos'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$coreRel = 'moonbitlang\core\0.1.20260920+7d59c7ec9'
$core = Join-Path $repos $coreRel

# The one diagnostic the corpus has on its own. MEASURED 2026-11-13 on the
# pinned core: `abort/pkg.mbti:4` -- `fn[T] abort(String) -> T`, where
# `String` is out of scope because the core is self-hosted and this toolchain
# type-checks interface files. It was `json/README.mbt.md:48` until the
# toolchain moved, and this pin moved with it.
#
# It is the CONTROL for this control: if the corpus ever grows a SECOND error,
# this control must notice rather than absorb it silently -- and it still does,
# because the baseline demands EXACTLY ONE error (`$base.Count -ne 1`).
$KNOWN_ERROR = 'abort/pkg.mbti:4'

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

# --- 3  the baseline: the corpus's own errors ----------------------------------
Write-Output ''
Write-Output '=== BASELINE: moon check --target all on an untouched COPY ==='
$t0 = Get-Date
$res = Check
$base = @($res.Errors)
Write-Output ("elapsed=" + [int]((Get-Date) - $t0).TotalSeconds + "s  exit=" + $res.Exit + "  errors=" + $base.Count)
foreach ($e in $base) { Write-Output ('  ERROR ' + $e) }

# THE BASELINE MUST BOTH CONTAIN THE KNOWN ERROR AND CONTAIN NOTHING ELSE.
#
# 0519. It used to test only for errors BEYOND the known one, so a check that
# produced NO errors passed this block -- and an unattributed `Error:` line from
# a check that could not start produced exactly that. The two ways to have no
# baseline are now named separately, because they mean different things and
# neither of them is a pass.
#
# THE ORDER MATTERS, and it is why the "did not run" test is `nothing was
# attributed AND something was reported`. `moon check` ends EVERY failed check
# with an unattributed summary line (`Error: failed when checking project`), so
# treating an unattributed line on its own as "did not run" would mislabel a
# check that did run -- which is the same class of mistake in the other
# direction.
if (@($res.Errors).Count -eq 0 -and $res.Unparsed.Count -gt 0) {
  Write-Output 'BASELINE FAILED: `moon check` reported a failure and attributed it to NO source location,'
  Write-Output '  so the corpus was never type-checked and this control has nothing to stand on:'
  foreach ($u in $res.Unparsed) { Write-Output ('    ' + $u) }
  Write-Output '  A corpus that cannot be checked is not a corpus with nothing wrong.'
  exit 1
}
if (@($res.Errors).Count -eq 0) {
  Write-Output 'BASELINE FAILED: the check produced NO errors at all, and the corpus has one known error.'
  Write-Output ('  An empty result means the check did not run: silence is not a clean tree.')
  exit 1
}
$bad = @($base | Where-Object { $_ -ne $KNOWN_ERROR })
if ($bad.Count -gt 0) {
  Write-Output ('BASELINE FAILED: the corpus has errors beyond the one this control knows: ' + ($bad -join ' '))
  foreach ($u in $res.Unparsed) { Write-Output ('    (moon: ' + $u + ')') }
  Write-Output 'A corpus that grew an error changes the claim, so this control refuses to absorb it.'
  exit 1
}
if ($base.Count -ne 1) {
  Write-Output ('BASELINE FAILED: expected exactly the one known error, got ' + $base.Count + ': ' + ($base -join ' '))
  exit 1
}
Write-Output ('baseline is exactly the one known error (' + $KNOWN_ERROR + '), which is not one of the files that carries a finding.')

# --- 4  the positive control: one probe per file, one file at a time -----------
#
# 0566: THE PIN ABOVE IS MEASURED, SO THIS BLOCK RUNS -- AND IT READS 0 FILES.
# The `abort` diagnostic is FOUNDATIONAL: the checker bails on it before it
# type-checks any other package, so every probe comes back carrying that one
# error and the probe's own error never appears. The stage stays RED, and it
# now says WHY, instead of dying at the baseline with a message that accused
# the corpus of an error it does not have.
Write-Output ''
Write-Output '=== the positive control: a deliberate type error, one file at a time ==='
$probe = "`nconst __probe_xyz_0496 : Int = `"not an int`"`n"
$ok = 0; $miss = @()
foreach ($f in $files) {
  $fp = Join-Path $scratch ($f -replace '/', '\')
  if (-not (Test-Path -LiteralPath $fp)) { Write-Output ('  MISSING ' + $f); $miss += $f; continue }
  $orig = [System.IO.File]::ReadAllText($fp, [System.Text.Encoding]::UTF8)
  [System.IO.File]::WriteAllText($fp, $orig + $probe, $enc)
  $pres = Check
  $r = @($pres.Errors)
  [System.IO.File]::WriteAllText($fp, $orig, $enc)   # restore byte-exactly
  if (@($r | Where-Object { $_ -like ($f + ':*') }).Count -ge 1) {
    $ok++
    Write-Output ('  READ     ' + $f)
  } else {
    $miss += $f
    $why = ''
    if (@($r).Count -eq 0 -and $pres.Unparsed.Count -gt 0) { $why = '   the check attributed nothing: ' + $pres.Unparsed[0] }
    Write-Output ('  NOT READ ' + $f + '   errors=' + $r.Count + '  ' + ($r -join ' ') + $why)
  }
}
Write-Output ''
Write-Output ("read by moon check: " + $ok + " of " + $files.Count)
if ($miss.Count -gt 0) { Write-Output ('NOT READ: ' + $miss.Count); foreach ($m in $miss) { Write-Output ('  ' + $m) } }

# --- 5  the tree is restored, so the baseline must come back alone -------------
$afterRes = Check
$after = @($afterRes.Errors)
Write-Output ("after restore: exit=" + $afterRes.Exit + "  errors=" + $after.Count + "  " + ($after -join ' '))
if (@($after).Count -eq 0 -and $afterRes.Unparsed.Count -gt 0) {
  Write-Output ('RESTORE FAILED: the check after the restore attributed nothing: ' + ($afterRes.Unparsed -join ' | '))
  exit 1
}
if ($after.Count -ne 1 -or $after[0] -ne $KNOWN_ERROR) { Write-Output 'RESTORE FAILED: the copy is not back to its baseline state.'; exit 1 }

Write-Output ''
if ($miss.Count -eq 0) {
  Write-Output ('GATE OK: all ' + $files.Count + ' files that carry an actionable finding are READ by moon check,')
  Write-Output ('and the corpus itself carries exactly one error, in ' + $KNOWN_ERROR + ', which is not one of them.')
  exit 0
}
Write-Output 'GATE FAILED.'
exit 1

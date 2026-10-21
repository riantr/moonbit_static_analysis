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
#      `math/algebraic_double_nonjs.mbt` ("not","js"). Five of the twenty-four
#      files therefore produced NO probe error under `--target js` -- which
#      reads exactly like "the file is not read", and is not. Under
#      `--target all` all twenty-four are reported.
#   2. A FILE WITH NO DIAGNOSTIC IS NOT EVIDENCE. The corpus-wide check
#      reports exactly ONE error, in `json/README.mbt.md` -- a `.mbt.md`
#      literate file, and not one of the twenty-four. So the twenty-four
#      carry nothing, and the control proves they are read.
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

# The one diagnostic the corpus has on its own. It is a `.mbt.md` doc file,
# and it is the CONTROL for this control: if the corpus ever grows a real
# error, this control must notice rather than absorb it silently.
$KNOWN_ERROR = 'json/README.mbt.md:48'

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
  $errs = @(); $sev = ''
  foreach ($l in ($t -split "`r?`n")) {
    if ($l -match '^(Error|Warning):\s*\[(\d+)\]') { $sev = $Matches[1]; continue }
    $m = [regex]::Match($l, $BOX + '\[\s*(.+):(\d+):(\d+)\s*\]')
    if ($m.Success -and $sev -eq 'Error') {
      $rel = $m.Groups[1].Value -replace ('.*' + [regex]::Escape($scratch) + '[\\/]'), ''
      $errs += (($rel -replace '\\','/') + ':' + $m.Groups[2].Value)
    }
  }
  return $errs
}

# `@()` matters here and is not decoration. PowerShell UNROLLS a one-element
# array on return, so `Check` hands back a scalar STRING when the corpus has
# exactly one error, and `$after[0]` on a string is its first CHARACTER, not
# its first element. The restore check then compares 'j' with the expected
# path and reports a restore that did not happen.

# --- 3  the baseline: the corpus's own errors ----------------------------------
Write-Output ''
Write-Output '=== BASELINE: moon check --target all on an untouched COPY ==='
$t0 = Get-Date
$base = @(Check)
Write-Output ("elapsed=" + [int]((Get-Date) - $t0).TotalSeconds + "s  errors=" + $base.Count)
foreach ($e in $base) { Write-Output ('  ERROR ' + $e) }

$bad = @($base | Where-Object { $_ -ne $KNOWN_ERROR })
if ($bad.Count -gt 0) {
  Write-Output ('BASELINE FAILED: the corpus has errors beyond the one this control knows: ' + ($bad -join ' '))
  Write-Output 'A corpus that grew an error changes the claim, so this control refuses to absorb it.'
  exit 1
}
Write-Output ('baseline is exactly the one known error (' + $KNOWN_ERROR + '), which is not one of the files that carries a finding.')

# --- 4  the positive control: one probe per file, one file at a time -----------
Write-Output ''
Write-Output '=== the positive control: a deliberate type error, one file at a time ==='
$probe = "`nconst __probe_xyz_0496 : Int = `"not an int`"`n"
$ok = 0; $miss = @()
foreach ($f in $files) {
  $fp = Join-Path $scratch ($f -replace '/', '\')
  if (-not (Test-Path -LiteralPath $fp)) { Write-Output ('  MISSING ' + $f); $miss += $f; continue }
  $orig = [System.IO.File]::ReadAllText($fp, [System.Text.Encoding]::UTF8)
  [System.IO.File]::WriteAllText($fp, $orig + $probe, $enc)
  $r = Check
  [System.IO.File]::WriteAllText($fp, $orig, $enc)   # restore byte-exactly
  if (@($r | Where-Object { $_ -like ($f + ':*') }).Count -ge 1) {
    $ok++
    Write-Output ('  READ     ' + $f)
  } else {
    $miss += $f
    Write-Output ('  NOT READ ' + $f + '   errors=' + $r.Count + '  ' + ($r -join ' '))
  }
}
Write-Output ''
Write-Output ("read by moon check: " + $ok + " of " + $files.Count)
if ($miss.Count -gt 0) { Write-Output ('NOT READ: ' + $miss.Count); foreach ($m in $miss) { Write-Output ('  ' + $m) } }

# --- 5  the tree is restored, so the baseline must come back alone -------------
$after = @(Check)
Write-Output ("after restore: errors=" + $after.Count + "  " + ($after -join ' '))
if ($after.Count -ne 1 -or $after[0] -ne $KNOWN_ERROR) { Write-Output 'RESTORE FAILED: the copy is not back to its baseline state.'; exit 1 }

Write-Output ''
if ($miss.Count -eq 0) {
  Write-Output ('GATE OK: all ' + $files.Count + ' files that carry an actionable finding are READ by moon check,')
  Write-Output ('and the corpus itself carries exactly one error, in ' + $KNOWN_ERROR + ', which is not one of them.')
  exit 0
}
Write-Output 'GATE FAILED.'
exit 1

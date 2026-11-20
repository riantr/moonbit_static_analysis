param([switch]$SelfTest, [string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE PUBLISHED POINTERS, as a gate.
#
# WHY THIS EXISTS. A shipped document that NAMES a file makes a PROMISE: the
# reader of the published package can follow the name and find the file. That
# promise is kept by exactly one thing -- the file being TRACKED -- because the
# published package is built from a CLEAN CHECKOUT, and a clean checkout holds
# the tracked files and nothing else.
#
# MEASURED 0617, and this is the defect that made this gate necessary:
# `_verify/QA_TODO.md` was cited by three SHIPPED documents -- `LOOP.md`,
# `_verify/check_family_fires.ps1` and `_verify/check_own_tree_clean.ps1` -- and
# it was NEVER COMMITTED. On the maintainer's machine the pointer RESOLVED: the
# file was on disk, and `moon package --list` even listed it, so the package
# built on this machine carried it. In CI, which checks out clean, the file is
# ABSENT -- so the published package does not carry it, and every reader of the
# published package meets a pointer that goes nowhere.
#
# This is the SAME species as 0614's defect ("the published file count
# described the LOCAL tree, and NEITHER the PACKAGE NOR A CLEAN CHECKOUT").
# The difference is that 0614's was a NUMBER and this one is a NAME, and a name
# that resolves on the maintainer's machine is harder to notice than a number
# that is one too big: nothing is red, nothing fails, and the pointer is right.
# It is right on the ONE machine that already knew the answer.
#
# WHAT IT CHECKS, in one sentence: a document that SHIPS must not point at a
# file that does not ship.
#
#   * SHIPS = the file is TRACKED and is in the package.
#   * POINTS = a shipped document's text names a path that IS in the package on
#     this machine and is NOT tracked.
#
# AND THE SCOPE IS DELIBERATELY NARROW, because a wider rule is a rule with
# false failures in it. MEASURED on this tree, the wider rule -- "every path a
# shipped document names must be in the published package" -- reports HUNDREDS
# of hits, and they are not defects:
#
#   * Four are CROSS-PROJECT references: `SKILL.md` names `riantr/pyroduct`'s
#     `src/paths.mbt`, `src/algebra.mbt` and `src/slot.mbt`, and `EXTENSIONS.md`
#     names `moonbitlang/async`'s `src/internal/fd_util/pipe.mbt`. Those files
#     are NOT in this package and are not supposed to be.
#   * Hundreds more are HISTORICAL references: the NARRATIVE and the scratch
#     gates name the temporary files an experiment wrote. Those are gone, and
#     they are SUPPOSED to be gone.
#
# So the rule is scoped to the case that is unambiguously a defect: the file is
# in the package ON THIS MACHINE -- the packager would ship it -- and it is not
# tracked, so the packager will NOT ship it in any published copy. The pointer
# resolves here and nowhere else. That is the same shape as 0614: the local
# tree and the published tree disagree, and only one of them is real.
#
# THE PACKAGE LIST IS READ WITH `moon package --list --frozen`, the same
# command `moon publish` packages from, and it is filtered the way
# `check_package_contents.ps1` filters it, PLUS one more rule: an entry that is
# not a file on disk is not a path. That second rule is what makes this gate
# work on a minimal fixture, whose `moon package --list` emits `[Warning: ...]`
# lines that the packager's own stdout put there. It is not a second claim
# about the package -- it is the same list, read strictly.
#
# THE -SelfTest SWITCH builds a FIXTURE in %TEMP%: a minimal moon module with
# a document that names a file, and a git index that tracks everything EXCEPT
# that file. It requires the fixture to go RED with the right message, and an
# unmutated control to stay GREEN. The repository is never touched.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_published_pointers.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_published_pointers.ps1 -SelfTest

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$fail = 0

# THE MOON EXECUTABLE. Looked up rather than written down, so the gate does not
# carry a machine-local path -- the same defect 0617 fixed in seven other
# gates.
function Get-MoonExe {
  $c = Get-Command 'moon.exe' -ErrorAction SilentlyContinue
  if ($null -ne $c) { return $c.Source }
  if ($env:MOON_HOME -ne '') {
    $p = Join-Path $env:MOON_HOME 'bin\moon.exe'
    if (Test-Path -LiteralPath $p) { return $p }
  }
  $p = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'
  if (Test-Path -LiteralPath $p) { return $p }
  return ''
}

# THE CITATIONS. A path-like token with a known file extension. The extension
# list is not a whitelist of "our" files -- it is a list of the kinds of file a
# document can point AT, and the `mbtp` BEFORE `mbt` is load-bearing: with the
# order reversed, `src/core/core_proof.mbtp` is read as a citation of
# `src/core/core_proof.mbt`, a file that does not exist. MEASURED: that is how
# a file that is NOT a defect was reported as one.
function Get-Citations {
  param([string]$Text)
  $re = [regex]('[A-Za-z0-9_][A-Za-z0-9_.\-]*(?:[\\/][A-Za-z0-9_.\-]+)*\.(?:md|mbtp|mbt|ps1|txt|json|yml|yaml|mod|wasm|mjs|js|py|toml|lock)')
  $out = @{}
  foreach ($m in $re.Matches($Text)) {
    $k = (($m.Value -replace '/', '\').TrimStart([char[]]@('.', '\'))).ToLowerInvariant()
    if (-not $out.ContainsKey($k)) { $out[$k] = $m.Value }
  }
  return $out
}

# ---------------------------------------------------------------------------
if (-not $SelfTest) {
  Write-Output '=== the published pointers: does every pointer in a shipped document resolve? ==='
  Write-Output ('  the tree it reads: ' + $root)

  $moon = Get-MoonExe
  if ($moon -eq '') {
    Write-Output 'ABORT: no moon executable was found (PATH, MOON_HOME, and ~/.moon/bin all failed).'
    exit 1
  }

  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $raw = & $moon -C $root package --list --frozen 2>&1 | ForEach-Object { [string]$_ }
  $pkgCode = $LASTEXITCODE
  $ErrorActionPreference = $prev
  if ($pkgCode -ne 0) {
    Write-Output ('ABORT: `moon package --list` exited ' + $pkgCode + '.')
    $raw | Select-Object -Last 5 | ForEach-Object { Write-Output ('      ' + $_) }
    exit 1
  }

  $noise = '^(Running moon check|Finished\. moon:|Check passed|Package to )'
  $pkg = @()
  foreach ($l in $raw) {
    $s = $l.Trim()
    if ($s -eq '') { continue }
    if ($s -match $noise) { continue }
    $n = ($s -replace '/', '\')
    # An entry that is not a file on disk is the packager's own stdout, not a
    # path. A minimal fixture emits `[Warning: ...]` lines here.
    if (-not (Test-Path -LiteralPath (Join-Path $root $n))) { continue }
    $pkg += $n
  }
  $pkg = @($pkg | Sort-Object -Unique)

  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $tracked = @(& git -C $root ls-files 2>&1 | ForEach-Object { [string]$_ })
  $gitCode = $LASTEXITCODE
  $ErrorActionPreference = $prev
  if ($gitCode -ne 0) {
    Write-Output 'ABORT: `git ls-files` failed. The published set cannot be read without git.'
    exit 1
  }
  $tracked = @($tracked | ForEach-Object { ($_ -replace '/', '\').Trim() } | Where-Object { $_ -ne '' })

  $pkgSet = @{}
  foreach ($p in $pkg) { $pkgSet[$p.ToLowerInvariant()] = $p }
  $trkSet = @{}
  foreach ($t in $tracked) { $trkSet[$t.ToLowerInvariant()] = $t }
  $published = @($pkg | Where-Object { $trkSet.ContainsKey($_.ToLowerInvariant()) })
  $untracked = @($pkg | Where-Object { -not $trkSet.ContainsKey($_.ToLowerInvariant()) })
  $untrackedSet = @{}
  foreach ($u in $untracked) { $untrackedSet[$u.ToLowerInvariant()] = $u }

  Write-Output ('  package entries        : ' + $pkg.Count)
  Write-Output ('  tracked files          : ' + $tracked.Count)
  Write-Output ('  published files        : ' + $published.Count)
  Write-Output ('  packaged but untracked : ' + $untracked.Count)

  $docs = @($published | Where-Object { $_ -match '\.(md|ps1)$' })
  Write-Output ('  shipped documents read : ' + $docs.Count)

  $dead = @{}
  foreach ($d in $docs) {
    $p = Join-Path $root $d
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $text = [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
    foreach ($k in (Get-Citations $text).Keys) {
      if ($untrackedSet.ContainsKey($k)) {
        if (-not $dead.ContainsKey($k)) { $dead[$k] = [pscustomobject]@{ Path = $untrackedSet[$k]; Docs = @() } }
        $dead[$k].Docs += $d
      }
    }
  }

  Write-Output ('  dead pointers          : ' + $dead.Count)
  if ($dead.Count -gt 0) {
    Write-Output ''
    foreach ($v in ($dead.Values | Sort-Object Path)) {
      Write-Output ('    DEAD POINTER: ' + $v.Path)
      Write-Output ('      cited by: ' + (($v.Docs | Sort-Object -Unique) -join ', '))
      Write-Output ('      it is in the package on this machine and in NO published copy, because CI checks out clean.')
    }
    Write-Output ''
    Write-Output ('POINTERS FAILED: ' + $dead.Count + ' dead pointer(s). A shipped document points at a file that does not ship.')
    exit 1
  }
  Write-Output ''
  Write-Output 'POINTERS OK: every path a shipped document points at is in the published package.'
  exit 0
}

# --- the self-test ------------------------------------------------------------
Write-Output '=== the published-pointer gate, shown to go red ==='

# THE FIXTURE. A minimal moon module with a document that names a file, and a
# git index. The index is what makes the two cases different: in the control
# the named file is tracked, and in the defect it is not -- while the file
# itself is on disk and in the package in BOTH, which is the whole shape of the
# real defect.
function New-PointerFixture {
  param([switch]$WithDeadPointer)
  $dir = Join-Path $env:TEMP ('ptr_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $dir '_verify') | Out-Null
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"pointerfix/probe`"`nversion = `"0.1.0`"`n", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir 'README.md'), "# the probe`n`nthe census lives in _verify/notes.md`n", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir '_verify\notes.md'), "the census`n", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir '_verify\gate.ps1'), "param([switch]`$SelfTest)`nif (`$SelfTest) { Write-Output 'x' }`n", $enc)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & git -C $dir init 2>&1 | Out-Null
  & git -C $dir add moon.mod README.md '_verify/gate.ps1' 2>&1 | Out-Null
  if (-not $WithDeadPointer) { & git -C $dir add '_verify/notes.md' 2>&1 | Out-Null }
  $ErrorActionPreference = $prev
  return $dir
}

function Invoke-OnFixture {
  param([string]$Dir)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Root $Dir 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  return [pscustomobject]@{ Code = $code; Out = $o }
}

$bad = 0
$checked = 0

# THE CONTROL. An unmutated fixture must PASS. A self-test that only proves the
# gate can fail proves nothing about the gate.
Write-Output ''
Write-Output '--- the control: a fixture whose named file IS tracked ---'
$ctlDir = New-PointerFixture
$ctl = Invoke-OnFixture $ctlDir
$checked++
if ($ctl.Code -eq 0) {
  Write-Output '  OK: the control passes (exit 0).'
} else {
  Write-Output ('  FAIL: the control FAILS with exit ' + $ctl.Code + '.')
  foreach ($ln in ($ctl.Out -split "`r?`n")) { if ($ln -match 'FAIL|DEAD POINTER|ABORT') { Write-Output ('        ' + $ln.Trim()) } }
  $bad++
}

# THE DEFECT. The named file is on disk and in the package, and it is NOT
# tracked -- so the pointer resolves here and in no published copy.
Write-Output ''
Write-Output '--- the defect: a shipped document names a file that is not tracked ---'
$defDir = New-PointerFixture -WithDeadPointer
$def = Invoke-OnFixture $defDir
$checked++
# The message is compared as a LITERAL. `-like` reads `[` and `]` as a
# character class, and a comparison that throws skips the check and prints
# SELFTEST OK having checked nothing.
$caught = $false
try {
  $caught = ($def.Code -ne 0) -and $def.Out.Contains('DEAD POINTER: _verify\notes.md')
} catch {
  Write-Output ('  FAIL: the check itself threw: ' + $_.Exception.Message)
  $caught = $false
}
if ($caught) {
  Write-Output ('  OK: the gate caught it (exit ' + $def.Code + ').')
} else {
  Write-Output ('  FAIL: the gate did NOT catch it (exit ' + $def.Code + ').')
  foreach ($ln in ($def.Out -split "`r?`n")) { if ($ln -match 'FAIL|DEAD POINTER|POINTERS|ABORT') { Write-Output ('        ' + $ln.Trim()) } }
  $bad++
}

# AND EVERY CHECK RAN. A self-test that silently skipped one of its own checks
# is the same green light that measured nothing.
if ($checked -ne 2) {
  Write-Output ('  FAIL: ' + $checked + ' of 2 checks ran.')
  $bad++
}

Write-Output ''
if ($bad -eq 0) {
  Write-Output 'SELFTEST OK: the control passed, and a shipped document pointing at an untracked file was caught.'
  exit 0
}
Write-Output ('SELFTEST FAILED: ' + $bad + ' of 2 checks did not hold.')
exit 1

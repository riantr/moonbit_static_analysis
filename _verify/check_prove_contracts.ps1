param([switch]$SelfTest)
$ErrorActionPreference = 'Continue'
# The PROOF CONTRACTS must be honest.
#
# WHY THIS FILE EXISTS. `#proof_pure` marks a function as a proof contract: the
# prover generates a verification condition for it and the body has to be
# PURE -- only Int/Bool constants and direct pure calls. A function whose body
# allocates a `StringBuilder` is not pure, and the prover rejects it with
# error 4207, "unsupported expression in pure function body".
#
# AND ONE FALSE ANNOTATION STOPS THE WHOLE FILE FROM PROVING. The check is
# per-package, so a single 4207 anywhere in `src/core` means the file does not
# lower at all -- no goals, no VCs, no proof. That is not a partial result; it
# is the whole thing gone.
#
# MEASURED 2026-10-22. Two `#proof_pure` annotations were false, on
# `path_tail` and `unqualified` -- both build a `StringBuilder` -- and both
# were added on 2026-10-09, in the same commit that added the second of them.
# `moon prove src/core` had been failing with 4207 ever since, and nothing
# noticed, because the release gate never ran it.
#
# The two annotations are removed. This gate is what keeps them removed.
#
# WHAT IT CHECKS, and what it does NOT:
#   - it FAILS if `moon prove` reports ANY error 4207. That is the false
#     annotation class, and it is checkable and it can pass.
#   - it does NOT fail on the toolchain's missing prelude theories. The
#     generated Why3 file declares `array` and `map` types that the proof
#     prelude has no theory for, so the file does not load, the lemmas are NOT
#     being discharged, and `moon prove` reports "0 of 1 packages proved". That
#     is a separate defect with a separate fix -- moving `IfaceSig` and
#     `IfaceSymTab` out of the proof subject changes the package's public API
#     -- and it is reported here, not papered over.
#
# => 判据: a documented command that nothing runs is a comment. The claim was
# "21/21 goals VALID", and the release gate could not tell a proof from a
# command that had not run since 2026-10-09.
#
# 0615, MEASURED: THE LIMITATION MOVED ITS NAME, AND THIS GATE HAD STOPPED
# REPORTING IT. The gate counted `unbound type symbol 'map'` and this header
# named `map` as THE limitation. On the toolchain of 2026-11-20 (core
# 0.10.21+06da1ed44) the FIRST unbound symbol why3 reports is `array`, not
# `map`: `IfaceSig` carries `array (array int)` and is declared BEFORE
# `IfaceSymTab`, which carries the maps -- and why3 stops at the first symbol
# it cannot resolve. So the counter read 0, the "KNOWN, and reported rather
# than hidden" block never printed, and the header named a symbol the toolchain
# no longer reports first. The limitation was still there the whole time; only
# the report of it had rotted.
#
# The counter is now over EVERY `unbound type symbol '<X>'`, the names it finds
# are printed as it finds them, and the lemma count is MEASURED rather than
# written down -- 19 today, and not one of them discharged.
#
# 0615, MEASURED: THE SWITCH WAS DEAD. This file declared
# `param([switch]$SelfTest)` and then never mentioned `$SelfTest` again: a
# switch that selects nothing, in the one gate whose whole subject is a red
# that had never been shown. The roster gate now requires every `check_*` gate
# to either carry a LIVE `-SelfTest` or to say in a comment why it carries
# none, and this file could satisfy neither.
#
# So the switch is now LIVE. It copies the tree into TEMP twice: once as it
# is, and once with a false `#proof_pure` injected in front of a function
# whose body allocates. The first copy must report NO 4207 and the second must
# report 4207, and the second's red has to come from the injection and not
# from anything else.
#
# THE INJECTION TARGET IS NOT A NAME TYPED IN HERE. It is found from the
# source: the first public function whose body allocates a `StringBuilder` and
# which carries no `#proof_pure`. That is the shape the prover rejects, and
# finding it means the fault survives a rename of the function it was found in.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_prove_contracts.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_prove_contracts.ps1 -SelfTest

$root = Split-Path -Parent $PSScriptRoot
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$why3 = Join-Path $root '.why3.conf'
$fail = 0

# THE CONTRACTS. Read from the source, so the list is the source's own.
function Get-Contracts([string]$CorePath) {
  $out = @()
  if (-not (Test-Path -LiteralPath $CorePath)) { return $out }
  $lines = Get-Content -LiteralPath $CorePath -Encoding UTF8
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq '#proof_pure') {
      $j = $i + 1
      while ($j -lt $lines.Count -and $lines[$j].Trim() -eq '') { $j++ }
      if ($j -lt $lines.Count) { $out += $lines[$j].Trim() }
    }
  }
  return $out
}

# THE INJECTION TARGET: the first public function whose body allocates a
# StringBuilder and which is not already a contract.
function Get-ImpureTarget([string]$CorePath) {
  if (-not (Test-Path -LiteralPath $CorePath)) { return $null }
  $lines = Get-Content -LiteralPath $CorePath -Encoding UTF8
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch '^\s*pub fn\s+([A-Za-z_][A-Za-z0-9_]*)') { continue }
    $name = $Matches[1]
    $k = $i - 1
    while ($k -ge 0 -and $lines[$k].Trim() -eq '') { $k-- }
    if ($k -ge 0 -and $lines[$k].Trim() -eq '#proof_pure') { continue }
    $end = [Math]::Min($i + 25, $lines.Count)
    for ($j = $i; $j -lt $end; $j++) {
      if ($lines[$j] -match 'StringBuilder\s*\(') {
        return [pscustomobject]@{ Name = $name; Line = ($i + 1); Text = $lines[$i].Trim() }
      }
    }
  }
  return $null
}

# ONE PROVE RUN, and everything it is asked about. Every number this gate
# prints comes out of here, so there is one place a number is measured.
function Invoke-Prove([string]$Root, [string]$Why3Path) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & $moon -C $Root prove src/core --why3-config $Why3Path 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $unbound = @()
  foreach ($m in [regex]::Matches($out, "unbound type symbol '([A-Za-z_][A-Za-z0-9_]*)'")) {
    $n = $m.Groups[1].Value
    if ($unbound -notcontains $n) { $unbound += $n }
  }
  $lemmas = 0
  $mlw = @(Get-ChildItem -Path (Join-Path $Root '_build\verif\src\core\*.mlw') -ErrorAction SilentlyContinue)
  if ($mlw.Count -gt 0) {
    $lemmas = ([regex]::Matches([System.IO.File]::ReadAllText($mlw[0].FullName), '\blemma\b')).Count
  }
  return [pscustomobject]@{
    Code   = $code
    Out    = $out
    N4207  = ([regex]::Matches($out, '\[4207\]')).Count
    Unbound = $unbound
    Lemmas = $lemmas
  }
}

# A COPY OF THE TREE. `moon prove src/core` resolves the package's imports, so
# a copy of `src/core` alone is not a project -- the whole `src` and the two
# project files have to come with it. MEASURED 2026-11-15: copying only
# `src/core` gives "Cannot find import 'riantr/moonbit_static_analysis/src/sa'".
function New-TreeCopy {
  $tmp = Join-Path $env:TEMP ('prove_selftest_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Path (Join-Path $tmp 'src') -Force | Out-Null
  Copy-Item -Path (Join-Path $root 'src\*') -Destination (Join-Path $tmp 'src') -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $root 'moon.mod') -Destination (Join-Path $tmp 'moon.mod') -Force
  Copy-Item -LiteralPath (Join-Path $root 'moon.pkg') -Destination (Join-Path $tmp 'moon.pkg') -Force
  return $tmp
}

# ================================================================= the self-test ===
if ($SelfTest) {
  Write-Output '=== the proof contracts, shown to go red ==='
  $bad = 0

  $treeContracts = @(Get-Contracts (Join-Path $root 'src\core\core.mbt'))
  Write-Output ('  the tree declares ' + $treeContracts.Count + ' #proof_pure contracts.')

  # THE CONTROL. An unmodified copy must report NO 4207, and must declare the
  # same number of contracts as the tree. A control that is not green proves
  # nothing: a gate that says "4207 found" on a clean tree is not a gate.
  $ctl = New-TreeCopy
  try {
    $ctlContracts = @(Get-Contracts (Join-Path $ctl 'src\core\core.mbt'))
    $r1 = Invoke-Prove $ctl $why3
    $ctlOk = ($r1.N4207 -eq 0) -and ($ctlContracts.Count -eq $treeContracts.Count)
    Write-Output ('  CONTROL  4207=' + $r1.N4207 + '  contracts=' + $ctlContracts.Count + ' of ' +
                  $treeContracts.Count + '  -> ' + $(if ($ctlOk) { 'as it must be' } else { 'WRONG' }))
    if (-not $ctlOk) {
      $bad++
      Write-Output '    The control did not hold. A self-test whose control is red proves nothing.'
    }
  } finally {
    Remove-Item -LiteralPath $ctl -Recurse -Force -ErrorAction SilentlyContinue
  }

  # THE FAULT. A false annotation must produce 4207, and it must produce it
  # for the injected reason.
  $flt = New-TreeCopy
  try {
    $core = Join-Path $flt 'src\core\core.mbt'
    $target = Get-ImpureTarget $core
    if ($null -eq $target) {
      Write-Output '  FAULT    no impure target was found in the copy -- the injection did not happen.'
      $bad++
    } else {
      $t = [System.IO.File]::ReadAllText($core)
      $needle = $target.Text
      if ($t.IndexOf($needle) -lt 0) {
        Write-Output ('  FAULT    the target line was not found verbatim: ' + $needle)
        $bad++
      } else {
        $t = $t.Replace($needle, "#proof_pure`n" + $needle)
        [System.IO.File]::WriteAllText($core, $t, (New-Object System.Text.UTF8Encoding($false)))
        $r2 = Invoke-Prove $flt $why3
        $faultOk = ($r2.N4207 -gt 0)
        Write-Output ('  FAULT    injected #proof_pure on ' + $target.Name + ' (line ' + $target.Line +
                      ')  4207=' + $r2.N4207 + '  -> ' + $(if ($faultOk) { 'caught, as it must be' } else { 'MISSED' }))
        if (-not $faultOk) {
          $bad++
          Write-Output '    A false annotation did not make the prover complain, so this gate cannot see one.'
        }
      }
    }
  } finally {
    Remove-Item -LiteralPath $flt -Recurse -Force -ErrorAction SilentlyContinue
  }

  Write-Output ''
  if ($bad -eq 0) {
    Write-Output 'SELFTEST OK: the control reported no false annotation, and the injected one was caught.'
    exit 0
  }
  Write-Output ('SELFTEST FAILED: ' + $bad + ' check(s) did not hold.')
  exit 1
}

# ==================================================================== the live run ===
Write-Output '=== the proof contracts in src/core ==='
$core = Join-Path $root 'src\core\core.mbt'
if (-not (Test-Path -LiteralPath $core)) {
  Write-Output ('ABORT: no ' + $core)
  exit 1
}
$pure = @(Get-Contracts $core)
Write-Output ('  #proof_pure contracts: ' + $pure.Count)
foreach ($p in $pure) { Write-Output ('    ' + $p) }

Write-Output '=== moon prove src/core ==='
if (-not (Test-Path -LiteralPath $why3)) {
  Write-Output '  MISSING: .why3.conf is not in the repository (it is a local shim).'
  Write-Output '          The proof lane cannot run without it; see the skill notes.'
  exit 1
}
$r = Invoke-Prove $root $why3
Write-Output ('  exit code: ' + $r.Code)
Write-Output ('  error 4207 (a #proof_pure body the prover rejects): ' + $r.N4207)
Write-Output ('  the lemma count the prover generated: ' + $r.Lemmas)
if ($r.Unbound.Count -gt 0) {
  Write-Output ('  the symbols the proof prelude does not define: ' + ($r.Unbound -join ', '))
} else {
  Write-Output '  the symbols the proof prelude does not define: none'
}

if ($r.N4207 -gt 0) {
  Write-Output ''
  Write-Output ('  FAIL: ' + $r.N4207 + ' error(s) 4207. A #proof_pure contract has a body the')
  Write-Output '  prover rejects, and ONE of them stops the whole file from proving.'
  Write-Output '  Find the function above whose body allocates or calls anything impure, and'
  Write-Output '  remove its #proof_pure -- the annotation was a claim the body did not keep.'
  ($r.Out -split "`r?`n" | Where-Object { $_ -match '4207' -or $_ -match 'core\.mbt:\d+' } | Select-Object -First 8) |
    ForEach-Object { Write-Output ('    | ' + $_.Trim()) }
  $fail++
}

if ($r.Unbound.Count -gt 0) {
  Write-Output ''
  Write-Output '  KNOWN, and reported rather than hidden: the generated Why3 file declares'
  Write-Output '  `array` and `map` types -- `IfaceSig` carries arrays, `IfaceSymTab` carries'
  Write-Output '  maps -- and the toolchain''s proof prelude defines neither, so the file does'
  Write-Output ('  not load. The ' + $r.Lemmas + ' lemmas are generated and NOT being discharged.')
  Write-Output '  The fix is to move those types out of the proof subject -- a public-API'
  Write-Output '  change, and therefore a version-line decision.'
  Write-Output '  The names above are the ones the toolchain reports TODAY; why3 stops at the'
  Write-Output '  first symbol it cannot resolve, so this list grows as the prelude changes.'
}

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'PROVE CONTRACTS OK: no false annotation, so the file lowers and the goals are generated.'
  exit 0
}
Write-Output ('PROVE CONTRACTS FAILED: ' + $fail + ' problem(s).')
exit 1

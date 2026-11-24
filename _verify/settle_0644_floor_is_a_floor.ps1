# 0644. THE FLOOR IS A FLOOR, AND THE GATE THAT COMPARED IT AS A MIRROR WAS WRONG.
#
# WHAT THIS SCRIPT MEASURES. On 2026-11-24 the release gate went RED with three
# stages -- `host-requirements`, `host-requirements-selftest` and
# `selfscan-selftest` -- and the failure said:
#
#     FAIL: the toolchain bundles core 0.10.22+124d61d05, the contracted floor
#            is 0.10.21+06da1ed44.
#
# Three facts had to be separated before anything could be called a defect:
#
#   1. IS THE TREE THE CAUSE? The gate reads the tree AND the machine. So the
#      same gate was run on the PREVIOUS commit's tree, on this machine. If it
#      says the same thing there, the tree did not do it.
#   2. IS THE FLOOR STILL A FLOOR? The floor is the MINIMUM core a host has to
#      bundle. A toolchain that bundles a NEWER core is not a violation of a
#      floor, and 0631 already ruled it: "the floor stays moon 0.1.20261117 or
#      later -- the new core declares 213 host externs and the runtime
#      implements 288 more, and together they still cover all 93."
#   3. CAN THE RULE STILL GO RED? A floor that cannot be checked is a comment.
#      So the gate itself is run against a core BELOW the floor, and it has to
#      go red -- and it has to go red FOR THAT REASON ALONE, with every other
#      check in it still green.
#
# THE INSTRUMENT IS THE GATE, NOT A COPY OF IT. Each case is produced by
# pointing `_verify/check_host_requirements.ps1` at a fixture core directory
# with `-CoreDir` and reading its EXIT CODE and its FAIL lines. The two
# fixtures differ in ONE thing -- the version in their own `moon.mod` -- and
# every one of them declares every contracted symbol, so the coverage check
# passes in both and the version rule is the only thing that can decide.
#
# WHY THERE IS NO "THE FLOOR ITSELF" CASE HERE. It is covered by the gate's
# OWN self-test (`check_host_requirements.ps1 -SelfTest`), which exercises the
# same comparison on the floor's own version. A fixture whose version IS the
# floor's would, in the gate, turn the "counts the documents quote" check ON
# -- that check is skipped unless the bundled core is the contracted one -- and
# the fixture declares 93 externs where the documents quote 213, so the case
# would go red for the COUNTS' reason and prove nothing about the version.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\settle_0644_floor_is_a_floor.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\settle_0644_floor_is_a_floor.ps1 -SkipTreeControl
param(
  # The tree control needs a git worktree of the previous commit. It is the
  # claim that matters most -- "the red was not this tree's fault" -- so it
  # runs by default and can be skipped on a machine without git.
  [switch]$SkipTreeControl,
  # The commit to run the control on. The default is the commit BEFORE this
  # one, read from git, so the control always compares against the tree that
  # was there before the fix.
  [string]$ControlCommit = ''
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$gate = Join-Path $root '_verify\check_host_requirements.ps1'
$contractPath = Join-Path $root '_verify\host_requirements.txt'
$releasePath = Join-Path $root '_verify\release.ps1'
$coreDir = Join-Path $HOME '.moon\lib\core'
$runtimeDir = Join-Path $HOME '.moon\lib\runtime'
$releaseWasm = Join-Path $root '_build\wasm\release\build\moonbit_static_analysis.wasm'

$failed = 0
function Say {
  param([string]$Text)
  Write-Output $Text
}
function Note {
  param([string]$Name, [bool]$Ok, [string]$Detail)
  if ($Ok) {
    Write-Output ('  ok   ' + $Name)
  } else {
    Write-Output ('  FAIL ' + $Name)
    if ($Detail) { Write-Output ('       ' + $Detail) }
    $script:failed++
  }
}

# --- the contract, read with the same shape the gate reads it -------------------
# EVERY FIELD IS SKIPPED BY NAME, or it is read as a symbol. The first version
# of this script skipped `min-host-core:`, `host-abi-module:` and `symbols:` and
# forgot `min-host-toolchain:` -- so the contract "carried 94 symbols" and the
# coverage check reported one uncovered symbol that was never a symbol at all.
$floor = ''
$floorTool = ''
$abi = ''
$symbols = @()
foreach ($line in [System.IO.File]::ReadAllLines($contractPath, [System.Text.Encoding]::UTF8)) {
  $t = $line.Trim()
  if ($t -eq '' -or $t.StartsWith('#')) { continue }
  if ($t.StartsWith('min-host-core:')) { $floor = $t.Substring(14).Trim(); continue }
  if ($t.StartsWith('min-host-toolchain:')) { $floorTool = $t.Substring(19).Trim(); continue }
  if ($t.StartsWith('host-abi-module:')) { $abi = $t.Substring(16).Trim(); continue }
  if ($t.StartsWith('symbols:')) { continue }
  $symbols += $t
}

# --- the machine ----------------------------------------------------------------
$coreVersion = ''
$coreMoonMod = Join-Path $coreDir 'moon.mod'
if (Test-Path -LiteralPath $coreMoonMod) {
  $coreVersion = ([regex]::Match([System.IO.File]::ReadAllText($coreMoonMod, [System.Text.Encoding]::UTF8), '(?m)^version\s*=\s*"([^"]+)"')).Groups[1].Value
}
$toolchain = ''
$moon = Get-Command 'moon.exe' -ErrorAction SilentlyContinue
if ($null -ne $moon) {
  $toolchain = ([regex]::Match((& $moon.Source version 2>&1 | Out-String), '(\d+\.\d+\.\d{8})')).Groups[1].Value
}
# THE CORE THE TREE WAS RE-GATED ON. 0631 set this pin, and it is the fact that
# decides which of the two cores is the sanctioned one: the tree was re-gated
# against 0.10.22, so a toolchain bundling 0.10.22 is the state the tree is
# supposed to be built and gated in.
$regated = ''
if (Test-Path -LiteralPath $releasePath) {
  $regated = ([regex]::Match([System.IO.File]::ReadAllText($releasePath, [System.Text.Encoding]::UTF8), "(?m)^\`$CORE_REGATED\s*=\s*'([^']+)'")).Groups[1].Value
}

# --- the coverage, measured ----------------------------------------------------
$externs = @{}
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $coreDir 'async') -Recurse -File -Filter '*.mbt') {
  $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  foreach ($m in [regex]::Matches($txt, '"' + [regex]::Escape($abi) + '"\s+"([^"]+)"')) { $externs[$m.Groups[1].Value] = $true }
}
$runtime = @{}
foreach ($f in Get-ChildItem -LiteralPath $runtimeDir -Recurse -File -Include '*.c', '*.h') {
  $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  foreach ($m in [regex]::Matches($txt, '\bmoonbit_rt_([A-Za-z0-9_]+)\s*\(')) { $runtime[$m.Groups[1].Value] = $true }
}
$uncovered = @($symbols | Where-Object {
  $bare = $_.Substring($_.LastIndexOf('/') + 1)
  (-not $externs.ContainsKey($_)) -and (-not $runtime.ContainsKey($bare))
})

# THE VERSION ORDER, read the way the gate reads it: the numeric part orders.
function Core-Minor {
  param([string]$Version)
  $m = [regex]::Match($Version, '^(\d+)\.(\d+)\.(\d+)')
  if (-not $m.Success) { return -1 }
  return [int]$m.Groups[3].Value
}

Write-Output '=== 0644: the floor is a floor, and the version rule is a lower bound ==='
Write-Output ''
Write-Output 'THE FACTS'
Say ('  the contracted floor        : ' + $floor + ' (core), toolchain ' + $floorTool)
Say ('  the local toolchain         : ' + $toolchain)
Say ('  the local bundled core       : ' + $coreVersion)
Say ('  the core the tree re-gated on: ' + $regated)
Say ('  the contract carries        : ' + $symbols.Count + ' symbol(s)')
Say ('  the bundled core declares   : ' + $externs.Count + ' host extern(s)')
Say ('  the runtime implements      : ' + $runtime.Count + ' `moonbit_rt_*` name(s)')
Say ('  together they cover         : ' + ($symbols.Count - $uncovered.Count) + ' of ' + $symbols.Count)
Write-Output ''

Note 'the contract carries the 93 symbols it claims to' ($symbols.Count -eq 93) ('the contract carries ' + $symbols.Count + ' symbol(s)')
Note 'the toolchain is AT OR ABOVE the floor' ($coreVersion -ne '' -and $floor -ne '' -and (Core-Minor $coreVersion) -ge (Core-Minor $floor)) ('the local core is ' + $coreVersion + ' and the floor is ' + $floor)
Note 'the coverage still covers every contracted symbol' ($uncovered.Count -eq 0) ($uncovered.Count.ToString() + ' symbol(s) are covered by neither the core nor the runtime: ' + ($uncovered -join ', '))
Note 'the tree was re-gated on a core this toolchain bundles' ($regated -ne '' -and $coreVersion -eq $regated) ('the tree was re-gated on ' + $regated + ' and this toolchain bundles ' + $coreVersion)

# --- the gate itself, against two cores that differ only in their version ------
Write-Output ''
Write-Output 'THE GATE, AGAINST TWO CORES THAT DIFFER ONLY IN THEIR VERSION'
$scratch = Join-Path $env:TEMP ('settle0644_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$base = [regex]::Match($floor, '^(\d+\.\d+\.)(\d+)(.*)$')
$cases = @()
if ($base.Success) {
  $minor = [int]$base.Groups[2].Value
  $cases += @{ label = 'a core below the floor'; version = ($base.Groups[1].Value + ($minor - 1) + $base.Groups[3].Value); want = 1 }
  $cases += @{ label = 'a core above the floor'; version = ($base.Groups[1].Value + ($minor + 1) + $base.Groups[3].Value); want = 0 }
} else {
  $cases += @{ label = 'a core below the floor'; version = ''; want = 1 }
  $cases += @{ label = 'a core above the floor'; version = ''; want = 0 }
}
foreach ($c in $cases) {
  if ($c.version -eq '') {
    Note ($c.label + ' -- the fixture could not be built') $false ('the floor is ' + $floor + ' and it could not be shifted')
    continue
  }
  $cdir = Join-Path $scratch ([regex]::Replace($c.version, '[^0-9A-Za-z]', '_'))
  New-Item -ItemType Directory -Force -Path (Join-Path $cdir 'async') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $cdir 'moon.mod'), (@('name = "moonbitlang/core"', ('version = "' + $c.version + '"'), '') -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
  $decls = @()
  foreach ($s in $symbols) { $decls += ('fn host_' + $decls.Count + '() = "' + $abi + '" "' + $s + '"') }
  [System.IO.File]::WriteAllText((Join-Path $cdir 'async\externs.mbt'), (($decls -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $gate -CoreDir $cdir 2>&1 | Out-String
  $code = $LASTEXITCODE
  $failLines = @($out -split "`r?`n" | Where-Object { $_ -match '^\s*FAIL:' })
  Say ('  ' + $c.label + ' (' + $c.version + ') -> exit ' + $code + ', ' + $failLines.Count + ' FAIL line(s)')
  foreach ($l in $failLines) { Say ('       ' + $l.Trim()) }
  Note ('the gate ' + $(if ($c.want -eq 0) { 'ACCEPTS' } else { 'REJECTS' }) + ' ' + $c.label) ($code -eq $c.want) ('the gate exited ' + $code + ' and ' + $c.want + ' was expected')
  if ($c.want -eq 1) {
    # THE REASON HAS TO BE THE VERSION, AND IT HAS TO BE THE ONLY REASON. A
    # gate that goes red for a second reason as well would not prove that the
    # version rule is what decides -- and the fixture declares every symbol, so
    # the coverage check passes and the counts check is skipped.
    Note ('the rejection of ' + $c.label + ' is the VERSION rule alone') ($failLines.Count -eq 1 -and $failLines[0] -match 'OLDER than the contracted floor') ($failLines.Count.ToString() + ' FAIL line(s): ' + (($failLines | ForEach-Object { $_.Trim() }) -join ' | '))
  }
}

# --- the gate's own self-test: the floor itself, and the rule that can go red --
Write-Output ''
Write-Output "THE GATE'S OWN SELF-TEST (it covers the floor itself)"
$selfOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $gate -SelfTest 2>&1 | Out-String
$selfCode = $LASTEXITCODE
$selfFails = @($selfOut -split "`r?`n" | Where-Object { $_ -match '^\s*FAIL' })
Note 'the self-test is green' ($selfCode -eq 0) ($selfFails.Count.ToString() + ' FAIL line(s): ' + (($selfFails | ForEach-Object { $_.Trim() }) -join ' | '))
foreach ($l in ($selfOut -split "`r?`n" | Where-Object { $_ -match 'the floor is a lower bound' -or $_ -match 'accepted the floor itself' -or $_ -match 'rejected a core below the floor' -or $_ -match 'accepted a core above the floor' })) {
  Say ('       ' + $l.Trim())
}

# --- the tree control: the SAME gate on the tree BEFORE this fix ---------------
Write-Output ''
Write-Output 'THE TREE CONTROL: THE SAME QUESTION, ON THE TREE BEFORE THIS FIX'
if ($SkipTreeControl) {
  Say '  skip (-SkipTreeControl)'
} else {
  $commit = $ControlCommit
  if ($commit -eq '') {
    $commit = (& git -C $root log --format=%H -1 HEAD~1 2>&1 | Out-String).Trim()
  }
  if ($commit -eq '' -or $commit -match 'fatal') {
    Note 'the previous commit could not be read' $false ('git said: ' + $commit)
  } elseif (-not (Test-Path -LiteralPath $releaseWasm)) {
    Note 'this tree''s release build is not on this machine, so the control cannot be run' $false ('the wasm is missing: ' + $releaseWasm)
  } else {
    $wt = Join-Path $env:TEMP ('settle0644_wt_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Say ('  the previous commit: ' + $commit.Substring(0, 7))
    $add = & git -C $root worktree add --detach $wt $commit 2>&1 | Out-String
    if (-not (Test-Path -LiteralPath (Join-Path $wt '_verify\check_host_requirements.ps1'))) {
      Note 'the worktree of the previous commit could not be made' $false ($add.Trim())
    } else {
      try {
        # THE WASM COMES FROM THIS TREE. A fresh worktree carries no `_build`,
        # and the gate ABORTS with "there is no artifact to audit" before it
        # reaches the version rule -- so without this the control would measure
        # the ABORT instead of the failure.
        $oldOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $wt '_verify\check_host_requirements.ps1') -Wasm $releaseWasm 2>&1 | Out-String
        $oldCode = $LASTEXITCODE
        $oldFails = @($oldOut -split "`r?`n" | Where-Object { $_ -match '^\s*FAIL:' })
        Say ('  the previous tree, same machine -> exit ' + $oldCode + ', ' + $oldFails.Count + ' FAIL line(s)')
        foreach ($l in $oldFails) { Say ('       ' + $l.Trim()) }
        Note 'the previous tree reports the SAME failure, so this tree did not cause it' ($oldCode -eq 1 -and $oldFails.Count -eq 1 -and $oldFails[0] -match 'bundles core') ('the previous tree exited ' + $oldCode + ' with ' + $oldFails.Count + ' FAIL line(s): ' + (($oldFails | ForEach-Object { $_.Trim() }) -join ' | '))
      } finally {
        & git -C $root worktree remove --force $wt 2>&1 | Out-Null
        & git -C $root worktree prune 2>&1 | Out-Null
      }
    }
  }
}

Write-Output ''
if ($failed -gt 0) {
  Write-Output ('SETTLE 0644 FAILED: ' + $failed + ' check(s) red.')
  exit 1
}
Write-Output 'SETTLE 0644 OK: the floor is a floor, the rule can still go red -- for the version'
Write-Output '                 reason alone -- and the previous tree reports the same failure, so'
Write-Output '                 the failure was never this tree''s fault.'
exit 0

param([switch]$SelfTest)
$ErrorActionPreference = 'Continue'
# The ROSTER of mutation gates is HAND-KEPT, and the claim that closed Direction 1
# was a COMMENT.
#
# THE DEFECT. Two facts are true today and NEITHER OF THEM IS CHECKED BY ANYTHING:
#
#   1. Every numbered gate in `_verify` calls the shared harness
#      `_verify/mutate_lib.ps1`, which is where the baseline, the pre-flight, the
#      SHA256 restore check, the COMPILE-ERR verdict and the NO-OP rule live. That
#      is the whole content of Direction 1's remainder, and it was closed BY HAND:
#      fourteen files were edited one at a time.
#   2. `_verify/release.ps1` runs the gates from a HAND-KEPT list of numbers
#      (`$gates`).
#
# A list kept by hand is a list that rots, and it rots in the direction that LOOKS
# FINE:
#
#   - a gate added to `_verify` but not to `$gates` NEVER RUNS. It is on disk, it
#     is named like a gate, and a release run reports every gate green. A gate that
#     does not run is indistinguishable from a gate that passes. The README
#     publishes the opposite claim -- "all 79 are inside the gate list in
#     `release.ps1`, so no mutation gate is left out of the release path" -- so
#     this is a PUBLISHED claim with no check behind it.
#   - a gate that carries its own copy of the runner again -- the exact defect
#     Direction 1 was about -- would be counted by the sentence in
#     `mutate_lib.ps1`'s header and would have none of the guarantees.
#
# MEASURED 2026-10-22, and this is the part that makes the header a lie: the
# header says "all 74 numbered gates". There are 79. The sentence was written on
# 2026-10-20, five gates ago, and nothing noticed, because a number in a comment
# is not checked by anything.
#
# => 判据: a roster kept by hand is a roster that rots, and the direction it rots
# in is the one that looks like a pass. The invariant has to be CHECKED, not
# described.
#
# WHAT THIS GATE CHECKS, each item a thing that can be WRONG:
#
#   1. the roster in `release.ps1` IS the roster on disk, in BOTH directions.
#   2. every numbered gate uses the shared harness: it dot-sources `mutate_lib.ps1`,
#      it calls `Invoke-MutationGate` exactly once, it defines no local function of
#      its own, and it passes no `--filter` (the old runners ran a SUBSET, and a
#      filter that selects zero tests reports green for any mutation).
#   3. the shared harness still carries its guarantees. Each is checked BY NAME, so
#      deleting one of them fails this gate instead of quietly weakening every gate
#      in the repository at once.
#   4. the COUNT in `mutate_lib.ps1`'s header is the count on disk. The header is
#      the claim; this is the check.
#
# NOTHING HERE RUNS A SUITE. This gate reads files and counts, so it costs
# milliseconds and is safe to run next to anything.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_gate_roster.ps1
$root = Split-Path -Parent $PSScriptRoot
$verify = Join-Path $root '_verify'
$fail = 0

# ---------------------------------------------------------------- code lines ---
# A gate file is COMMENTS, a here-string of MoonBit source or prose, and a little
# PowerShell. Only the last of those is code, and telling them apart matters:
# three gates carry the word "function" inside a `Prove` text, and a naive scan
# reports them as gates that define their own runner.
#
# A here-string opens with `@'` or `@"` at the END of a line and closes with `'@`
# or `"@` at the START of a line. Everything between is DATA.
#
# THE ORDER OF THE TWO CHECKS IS LOAD-BEARING, and it was wrong in the first
# version of this file. A COMMENT line that mentions `@'` -- and a header comment
# in twenty-two of the gates does, because they quote a mutation pattern -- was
# read as a here-string OPENER, and the file was swallowed from that point on.
# Twenty-two gates then reported "does not call Invoke-MutationGate", which is
# false: they all call it, at the bottom of the file, where the swallow had
# eaten it.
#
# => 判据: a reader that cannot tell a comment from code will confidently report
# on code it never read. The order of the filters is what decides which one it
# read, so the order is part of the reader.
function Get-CodeLines {
  param([string[]]$Lines)
  $out = New-Object System.Collections.Generic.List[string]
  $inHere = $false
  $hereEnd = ''
  foreach ($l in $Lines) {
    if ($inHere) {
      if ($l -match ('^\s*' + [regex]::Escape($hereEnd))) { $inHere = $false }
      continue
    }
    # A COMMENT is not a here-string opener, and a comment is checked FIRST.
    if ($l.TrimStart().StartsWith('#')) { continue }
    # The opener has to be the last thing on the line, and the `@` has to start a
    # word -- so a string that merely ENDS in `@'` is not mistaken for one.
    # THE CAPTURE IS THE QUOTE ALONE, not the whole `@'`: capturing `@'` and then
    # appending `@` builds the terminator `@'@`, which matches nothing, and every
    # here-string in the file swallows the rest of it. That was the second version
    # of this bug, and it is the same shape as the first: a reader that gets the
    # delimiter wrong does not report an error, it reports a file it did not read.
    if ($l -match "(?:^|\s)@(['`"])\s*$") {
      $q = $Matches[1]
      $hereEnd = $q + '@'
      $inHere = $true
      continue
    }
    $out.Add($l)
  }
  return $out.ToArray()
}

function Get-Text([string]$Path) {
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

# ------------------------------------------------------------- the self-test ---
# A GATE THAT HAS NEVER BEEN SHOWN TO GO RED IS A COMMENT. This injects each
# defect the gate claims to catch, into a COPY of `_verify` in TEMP, and requires
# the copy to fail WITH THE RIGHT MESSAGE. The real tree is never touched: the
# copy is made fresh for every fault, so one fault cannot mask another.
#
# The faults are the five the gate checks, plus the two directions of the roster
# mismatch -- because a roster check that only catches ONE direction catches the
# direction nobody is looking for.
if ($SelfTest) {
  Write-Output '=== the roster gate, shown to go red ==='

  function New-FaultCopy {
    $tmp = Join-Path $env:TEMP ('roster_selftest_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $c = Join-Path $tmp '_verify'
    Copy-Item -LiteralPath $verify -Destination $c -Recurse -Force
    return $c
  }

  function Run-Copy([string]$CopyDir) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $CopyDir 'check_gate_roster.ps1') 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    return [pscustomobject]@{ Code = $code; Out = $o }
  }

  # The count the header currently claims, read from the header itself, so the
  # fault does not depend on a number typed in here.
  $hdr = Get-Text (Join-Path $verify 'mutate_lib.ps1')
  $hm = [regex]::Match($hdr, 'all (\d+) numbered gates')
  $n = if ($hm.Success) { [int]$hm.Groups[1].Value } else { 0 }

  $faults = @(
    [pscustomobject]@{
      N = 'a gate on disk that the release list does not name'
      Expect = 'NEVER RUN'
      Apply = {
        param($c)
        [System.IO.File]::WriteAllText((Join-Path $c 'mutate_0999.ps1'), "# a gate that nothing runs`n")
      }
    }
    [pscustomobject]@{
      N = 'a gate in the release list that is not on disk'
      Expect = 'LISTED BUT NOT ON DISK'
      Apply = {
        param($c)
        Remove-Item -LiteralPath (Join-Path $c 'mutate_0496.ps1') -Force
      }
    }
    [pscustomobject]@{
      N = 'a gate that does not call the shared harness'
      Expect = 'NOT ON THE SHARED HARNESS'
      Apply = {
        param($c)
        $p = Join-Path $c 'mutate_0493.ps1'
        $t = Get-Text $p
        $t = $t.Replace('Invoke-MutationGate -Name', 'Invoke-MyOwnRunner -Name')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
      }
    }
    [pscustomobject]@{
      N = 'a guarantee removed from the shared harness'
      Expect = 'MISSING GUARANTEE'
      Apply = {
        param($c)
        $p = Join-Path $c 'mutate_lib.ps1'
        $t = Get-Text $p
        $t = $t.Replace("' (baseline red)'", "' (baseline reddish)'")
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
      }
    }
    [pscustomobject]@{
      N = 'a --filter in the shared harness'
      Expect = 'passes a --filter'
      Apply = {
        param($c)
        $p = Join-Path $c 'mutate_lib.ps1'
        $t = Get-Text $p
        $t = $t.Replace('$script:MutationGateFailures = @()', '$script:MutationGateFailures = @() # --filter legacy')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
      }
    }
    [pscustomobject]@{
      N = 'a stale count in the harness header'
      Expect = 'the header is stale'
      Apply = {
        param($c, $count)
        $p = Join-Path $c 'mutate_lib.ps1'
        $t = Get-Text $p
        $t = $t.Replace(('all ' + $count + ' numbered gates'), ('all ' + ($count - 1) + ' numbered gates'))
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
      }
    }
    [pscustomobject]@{
      N = 'a moon invocation that does not name the project root'
      Expect = 'do not name the project root'
      Apply = {
        param($c)
        $p = Join-Path $c 'mutate_lib.ps1'
        $t = Get-Text $p
        $t = $t.Replace('-C $Root test --target', 'test --target')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
      }
    }
    [pscustomobject]@{
      N = 'a check gate on disk that the release gate does not run'
      Expect = 'NEVER RUN'
      Apply = {
        param($c)
        # A gate with a LIVE self-test, so the ONLY thing wrong with it is that
        # nothing runs it. A file that was wrong in two ways would prove less.
        $body = "param([switch]`$SelfTest)`nif (`$SelfTest) { Write-Output 'never run' }`n"
        [System.IO.File]::WriteAllText((Join-Path $c 'check_zzz.ps1'), $body, (New-Object System.Text.UTF8Encoding($false)))
      }
    }
    [pscustomobject]@{
      N = 'a check gate whose self-test the release gate does not run'
      Expect = 'SELF-TEST NOT RUN'
      Apply = {
        param($c)
        # THE FAULT THE OTHER CHECKS CANNOT SEE. The gate is on disk, the
        # release gate names it, and its -SelfTest switch is LIVE -- the only
        # thing wrong with it is that nobody RUNS the self-test. One thing is
        # wrong with it, so the check that catches it cannot be catching
        # something else.
        $p = Join-Path $c 'release.ps1'
        $t = Get-Text $p
        if ($t.IndexOf('-File $GCL -SelfTest') -lt 0) { return $false }
        $t = $t.Replace('-File $GCL -SelfTest', '-File $GCL')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
    [pscustomobject]@{
      N = 'a check gate whose -SelfTest switch is declared and never used'
      Expect = 'DEAD SWITCH'
      Apply = {
        param($c)
        $p = Join-Path $c 'check_prove_contracts.ps1'
        $t = Get-Text $p
        if ($t.IndexOf('if ($SelfTest) {') -lt 0) { return $false }
        $t = $t.Replace('if ($SelfTest) {', 'if ($false) {')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
    [pscustomobject]@{
      N = 'a numbered gate that cannot fail'
      Expect = 'CANNOT FAIL'
      Apply = {
        param($c)
        $p = Join-Path $c 'mutate_0502.ps1'
        $t = Get-Text $p
        if ($t.IndexOf('Write-MutationGateVerdict') -lt 0) { return $false }
        # THE HISTORICAL DEFECT, EXACTLY: no verdict, and no exit to carry it.
        $t = $t.Replace('Write-MutationGateVerdict', 'Write-NoVerdict')
        $t = $t.Replace('if ($script:MutationGateFailures.Count -gt 0) { exit 1 }', 'if ($false) { exit 1 }')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
    [pscustomobject]@{
      N = 'a check gate with no -SelfTest and no stated reason'
      Expect = 'NO SELF-TEST'
      Apply = {
        param($c)
        $p = Join-Path $c 'check_frame_audit.ps1'
        $t = Get-Text $p
        $mark = 'There is no -SelfTest switch, and that is deliberate'
        if ($t.IndexOf($mark) -lt 0) { return $false }
        $t = $t.Replace($mark, 'There is no self-test switch')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
  )

  $bad = 0
  foreach ($f in $faults) {
    $c = New-FaultCopy
    try {
      # Every fault takes the copy dir; the ones that need the header count take
      # it as a second argument and the rest leave it in $args.
      #
      # A fault that returns $false did NOT APPLY -- the anchor it was going to
      # change is not in the copy. A fault that quietly does nothing produces a
      # copy that is green, and a green copy looks like a caught defect.
      $applied = & $f.Apply $c $n
      if ($applied -eq $false) {
        Write-Output ('  MISSED  ' + $f.N + '  (the anchor was not found -- the defect was never injected)')
        $bad++
        continue
      }
      $r = Run-Copy $c
      $caught = ($r.Code -ne 0) -and ($r.Out -like ('*' + $f.Expect + '*'))
      Write-Output ('  ' + $(if ($caught) { 'CAUGHT ' } else { 'MISSED ' }) + $f.N +
                    '  (exit ' + $r.Code + ', expected "' + $f.Expect + '")')
      if (-not $caught) {
        $bad++
        foreach ($ln in ($r.Out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 12)) {
          Write-Output ('      | ' + $ln.Trim())
        }
      }
    } finally {
      Remove-Item -LiteralPath (Split-Path -Parent $c) -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  Write-Output ''
  if ($bad -eq 0) {
    Write-Output ('SELFTEST OK: all ' + $faults.Count + ' injected defects were caught.')
    exit 0
  }
  Write-Output ('SELFTEST FAILED: ' + $bad + ' of ' + $faults.Count + ' injected defects were NOT caught.')
  exit 1
}

$gateFiles = @(Get-ChildItem -LiteralPath $verify -Filter 'mutate_0*.ps1' -File | Sort-Object Name)
$onDisk = @($gateFiles | ForEach-Object { $_.BaseName.Substring('mutate_'.Length) })
Write-Output ('=== numbered gates on disk: ' + $onDisk.Count + ' ===')

# ------------------------------------------------------- 1. the two rosters ---
Write-Output '=== 1. the roster in release.ps1 IS the roster on disk ==='
$rel = Get-Text (Join-Path $verify 'release.ps1')
$gm = [regex]::Match($rel, '\$gates\s*=\s*@\(([^)]*)\)')
if (-not $gm.Success) {
  Write-Output '  MISSING: release.ps1 no longer declares `$gates = @(...)`.'
  Write-Output '          The gates must be run from ONE list; find the new one and check it here.'
  $fail++
  $listed = @()
} else {
  $listed = @([regex]::Matches($gm.Groups[1].Value, "'(\d{4})'") | ForEach-Object { $_.Groups[1].Value })
  Write-Output ('  release.ps1 lists ' + $listed.Count + ' gates; disk has ' + $onDisk.Count)

  $notListed = @($onDisk | Where-Object { $listed -notcontains $_ })
  $notOnDisk = @($listed | Where-Object { $onDisk -notcontains $_ })
  if ($notListed.Count -gt 0) {
    Write-Output ('  NOT IN THE RELEASE LIST (these gates NEVER RUN): ' + ($notListed -join ', '))
    Write-Output '    A gate on disk but not in $gates is a gate that does not run. It looks'
    Write-Output '    exactly like a gate that passes. Add it to $gates in release.ps1.'
    $fail++
  }
  if ($notOnDisk.Count -gt 0) {
    Write-Output ('  LISTED BUT NOT ON DISK: ' + ($notOnDisk -join ', '))
    $fail++
  }
  if ($notListed.Count -eq 0 -and $notOnDisk.Count -eq 0) {
    Write-Output '  OK: the two rosters are the same set.'
  }
  # The list has to be CONSUMED. A list nobody iterates is a list that runs nothing.
  if ($rel -notmatch 'foreach\s*\(\s*\$g\s+in\s+\$gates\s*\)') {
    Write-Output '  MISSING: release.ps1 no longer iterates `$gates`. The list is declared and unused.'
    $fail++
  }
}

# ------------------------------------------------- 2. every gate on the harness ---
Write-Output '=== 2. every numbered gate uses the shared harness ==='
$notHarnessed = @()
$locallyDefined = @()
$filtered = @()
foreach ($f in $gateFiles) {
  $code = Get-CodeLines (Get-Content -LiteralPath $f.FullName -Encoding UTF8)
  $body = ($code -join "`n")
  $nInvoke = @($code | Where-Object { $_ -match 'Invoke-MutationGate' }).Count
  $nSrc    = @($code | Where-Object { $_ -match 'mutate_lib\.ps1' }).Count
  $nFunc   = @($code | Where-Object { $_ -match '^\s*function\s+[A-Za-z]' }).Count
  $nFilter = @($code | Where-Object { $_ -match '--filter' }).Count
  if ($nInvoke -ne 1 -or $nSrc -lt 1) { $notHarnessed += ($f.Name + ' (Invoke=' + $nInvoke + ', dot-source=' + $nSrc + ')') }
  if ($nFunc -gt 0) { $locallyDefined += ($f.Name + ' (' + $nFunc + ' local function(s))') }
  if ($nFilter -gt 0) { $filtered += ($f.Name + ' (' + $nFilter + ' --filter)') }
}
if ($notHarnessed.Count -gt 0) {
  Write-Output '  NOT ON THE SHARED HARNESS:'
  foreach ($x in $notHarnessed) { Write-Output ('    - ' + $x) }
  Write-Output '    A gate that does not call Invoke-MutationGate has none of the baseline,'
  Write-Output '    the pre-flight or the SHA256 restore check. That is Direction 1 itself.'
  $fail++
} else {
  Write-Output ('  OK: all ' + $onDisk.Count + ' gates dot-source mutate_lib.ps1 and call Invoke-MutationGate once.')
}
if ($locallyDefined.Count -gt 0) {
  Write-Output '  GATES DEFINING THEIR OWN FUNCTION:'
  foreach ($x in $locallyDefined) { Write-Output ('    - ' + $x) }
  Write-Output '    A local function is where a copied runner starts.'
  $fail++
}
if ($filtered.Count -gt 0) {
  Write-Output '  GATES PASSING A --filter:'
  foreach ($x in $filtered) { Write-Output ('    - ' + $x) }
  Write-Output '    A filter that selects zero tests reports green for any mutation.'
  $fail++
}

# ------------------------------------------- 3. the harness still has its guards ---
Write-Output '=== 3. the shared harness still carries its guarantees ==='
$lib = Get-Text (Join-Path $verify 'mutate_lib.ps1')
$guards = @(
  @{ N = 'baseline: a RED suite aborts the gate';        T = '(baseline red)' }
  @{ N = 'baseline: a suite that did not run aborts';     T = '(baseline did not run)' }
  @{ N = 'baseline: a suite that ran 0 tests aborts';     T = '(baseline 0)' }
  @{ N = 'pre-flight: an absent pattern is a failure';    T = '(preflight)' }
  @{ N = 'pre-flight: an anchor satisfied by a comment is a failure'; T = '(preflight prose)' }
  @{ N = 'a mutation that did not apply is a failure';    T = '(NO-OP)' }
  @{ N = 'every restore is proven by SHA256';             T = '$sha0 -ne (Get-FileHash' }
  @{ N = 'a failed restore is a failure';                 T = '(restore)' }
  @{ N = 'COMPILE-ERR is distinguished from a kill';       T = "`$outcome = 'COMPILE-ERR'" }
  @{ N = 'a run that never happened is INCONCLUSIVE';       T = "`$outcome = 'INCONCLUSIVE'" }
  @{ N = 'a compiler rejection is told from a run that never happened'; T = 'Error:\s*\[\d+\]' }
  @{ N = 'SURVIVED is distinguished from a kill';          T = "`$outcome = 'SURVIVED'" }
  @{ N = 'a named-test claim is checked';                 T = '(named test did not go red)' }
  @{ N = 'a declared non-KILLED outcome must carry an argument'; T = 'with no argument)' }
  @{ N = 'a retired mutation is EXCLUDED, not scored';    T = "`$_.ContainsKey('Retired')" }
  @{ N = 'Expect is honoured';                            T = "`$m.ContainsKey('Expect')" }
  @{ N = 'MustRed is honoured';                           T = "`$m.ContainsKey('MustRed')" }
  @{ N = 'Prove travels with a survivor';                 T = "`$m.ContainsKey('Prove')" }
)
$missingGuards = @()
foreach ($g in $guards) {
  if ($lib.IndexOf($g.T, [System.StringComparison]::Ordinal) -lt 0) { $missingGuards += $g.N }
}
if ($missingGuards.Count -gt 0) {
  Write-Output '  MISSING GUARANTEE(S) in mutate_lib.ps1:'
  foreach ($x in $missingGuards) { Write-Output ('    - ' + $x) }
  Write-Output '  A guarantee that is only DESCRIBED is not a guarantee.'
  $fail++
} else {
  Write-Output ('  OK: all ' + $guards.Count + ' guarantees are present in the harness.')
}
# EVERY MOON INVOCATION MUST NAME THE PROJECT ROOT. `moon` resolves the project
# from the CURRENT DIRECTORY, so an invocation that does not name it works only
# by accident -- and when it does not work it says "not in a Moon project",
# which the harness reports as "the suite does not compile". That is a verdict
# about the SUITE for a mistake about the DIRECTORY, and the reader believes it.
# The harness resolves `$Root` for every FILE it touches; the moon calls were
# the only ones that did not, so this counts them against the root.
$moonCalls = @([regex]::Matches($lib, '\$MoonExe\s+(?![=])')).Count
$rootedCalls = @([regex]::Matches($lib, '\$MoonExe\s+-C\s+\$Root\s')).Count
if ($moonCalls -eq 0) {
  Write-Output '  MISSING: mutate_lib.ps1 makes no moon invocation at all.'
  $fail++
} elseif ($moonCalls -ne $rootedCalls) {
  Write-Output ('  MISSING: ' + ($moonCalls - $rootedCalls) + ' of ' + $moonCalls + ' moon invocation(s) do not name the project root.')
  Write-Output '        A gate run from the wrong directory reports "the suite does not compile".'
  $fail++
} else {
  Write-Output ('  OK: all ' + $moonCalls + ' moon invocations name the project root.')
}
# The runner scores the FULL suite. A --filter in the harness would bring back the
# 0.4.13 defect, where a glob that selects zero tests reports green for anything.
if ($lib.IndexOf('--filter', [System.StringComparison]::Ordinal) -ge 0) {
  Write-Output '  MISSING: mutate_lib.ps1 passes a --filter. The harness must score the FULL suite.'
  $fail++
} else {
  Write-Output '  OK: the harness scores the full suite, with no --filter.'
}

# ------------------------------------------------- 4. the count in the header ---
Write-Output '=== 4. the count in the harness header is the count on disk ==='
$cm = [regex]::Match($lib, 'all (\d+) numbered gates')
if (-not $cm.Success) {
  Write-Output '  MISSING: the header no longer says "all N numbered gates".'
  Write-Output '          That sentence IS the claim this gate checks. Restore it.'
  $fail++
} else {
  $claimed = [int]$cm.Groups[1].Value
  Write-Output ('  header says ' + $claimed + '; disk has ' + $onDisk.Count)
  if ($claimed -ne $onDisk.Count) {
    Write-Output ('  FAIL: the header is stale by ' + [Math]::Abs($claimed - $onDisk.Count) + '.')
    Write-Output '        A number in a comment is not checked by anything -- until now.'
    Write-Output '        Update the count in mutate_lib.ps1 (and the README, which quotes it).'
    $fail++
  } else {
    Write-Output '  OK: the header and the disk agree.'
  }
}

# ------------------------------------- 5. the check_* gates: run, and showable ---
# Everything above is about the MUTATION gates -- `mutate_0*.ps1`, each one a
# mutation with a baseline. The `check_*` gates are a different kind of thing:
# they READ the tree and judge it. Until 0615 nothing said they had to be run
# at all, and nothing said they could be shown to work.
#
# TWO DEFECTS, and both are the same shape as the roster defect this file was
# built for:
#
#   1. A `check_*.ps1` on disk that `release.ps1` does not run NEVER RUNS. It
#      is on disk, it is named like a gate, and a release run reports every
#      gate green. A gate that does not run is indistinguishable from a gate
#      that passes -- and the README publishes the opposite claim.
#   2. A `check_*.ps1` whose `-SelfTest` switch is DECLARED AND NEVER USED is
#      a switch that selects nothing. It looks like the gate can be shown to go
#      red, and it cannot. MEASURED 0615: `check_prove_contracts.ps1` declared
#      `param([switch]$SelfTest)` and then never mentioned `$SelfTest` again
#      -- in the one gate whose whole subject is a red that had never been
#      shown.
#
# SO EVERY `check_*.ps1` IS ACCOUNTED FOR: it either carries a LIVE
# `-SelfTest` -- declared AND read by the body -- or it says, in a comment, why
# it carries none.
#
# "LIVE" IS READ FROM THE CODE, NOT FROM THE TEXT. The count is taken over
# CODE LINES ONLY, with the same here-string-aware reader this file already
# uses, so a `$SelfTest` mentioned in a comment -- in a header that explains
# what the switch does -- does not make a dead switch look alive. That is not
# a hypothetical: the header of `check_prove_contracts.ps1` names `$SelfTest`
# twice, and both mentions are prose.
#
# The stated reason is a FIXED PHRASE, not a mood: "There is no -SelfTest
# switch, and that is deliberate". Five gates carry it, and the reason it
# exists is that their red is demonstrated by injecting a defect into the
# tree, which is a stronger statement than a switch that reproduces the
# checker's own logic.
Write-Output ''
Write-Output '=== 5. the check gates: every one runs, and every one is showable ==='
$checkFiles = @(Get-ChildItem -LiteralPath $verify -Filter 'check_*.ps1' -File | Sort-Object Name)
$relTxt = Get-Text (Join-Path $verify 'release.ps1')
$notRun = @()
$deadSwitch = @()
$noSelfTest = @()
$liveSwitch = @()
$stated = @()
foreach ($f in $checkFiles) {
  $t = Get-Text $f.FullName
  if ($relTxt.IndexOf($f.Name, [System.StringComparison]::Ordinal) -lt 0) {
    $notRun += $f.Name
  }
  # The count is over CODE LINES: comments and here-strings are removed first,
  # so prose about the switch cannot make it look alive.
  $code = Get-CodeLines (Get-Content -LiteralPath $f.FullName -Encoding UTF8)
  $nRef = @($code | Where-Object { $_ -match '\$SelfTest' }).Count
  if ($nRef -eq 0) {
    # No switch at all. The gate has to say why it has none.
    if ($t.IndexOf('There is no -SelfTest switch, and that is deliberate', [System.StringComparison]::Ordinal) -ge 0) {
      $stated += $f.Name
    } else {
      $noSelfTest += $f.Name
    }
  } elseif ($nRef -ge 2) {
    $liveSwitch += $f.Name
  } else {
    # Declared, and read exactly once -- which is the declaration itself.
    $deadSwitch += $f.Name
  }
}
Write-Output ('  ' + $checkFiles.Count + ' check gates on disk')
if ($notRun.Count -gt 0) {
  Write-Output ('  NEVER RUN (the release gate does not name them): ' + ($notRun -join ', '))
  Write-Output '    A gate on disk that nothing runs looks exactly like a gate that passes.'
  $fail++
} else {
  Write-Output ('  OK: all ' + $checkFiles.Count + ' check gates are named by the release gate.')
}
if ($deadSwitch.Count -gt 0) {
  Write-Output ('  DEAD SWITCH (declared, and never read by the body): ' + ($deadSwitch -join ', '))
  Write-Output '    A switch that selects nothing looks like a gate that can be shown to go red.'
  $fail++
} else {
  Write-Output ('  OK: ' + $liveSwitch.Count + ' carry a live -SelfTest, ' + $stated.Count + ' state why they carry none.')
}
# 0638. AND THE PROOF HAS TO BE RUN. A gate that carries a live `-SelfTest`
# is a gate that can be SHOWN to go red -- and a self-test nobody runs is a
# comment. MEASURED on 2026-11-21: the release gate ran eleven check
# gates' self-tests and did NOT run four, and two of those four had rotted
# into faults that could not land -- and nothing could see it, because the
# question had never been asked.
#
# The gate is invoked through a VARIABLE, so the filename alone cannot
# answer the question: the variables `release.ps1` assigns to the gates are
# read first, and then those variables are looked for with `-SelfTest`.
$gateVars = @{}
foreach ($m in [regex]::Matches($relTxt, '(?m)^\s*(\$[A-Za-z0-9_]+)\s*=\s*[^\r\n]*?(check_[A-Za-z0-9_]+\.ps1)')) {
  $fn = $m.Groups[2].Value
  if (-not $gateVars.ContainsKey($fn)) { $gateVars[$fn] = @() }
  $gateVars[$fn] += $m.Groups[1].Value
}
$selfTestNotRun = @()
foreach ($f in $checkFiles) {
  $code = Get-CodeLines (Get-Content -LiteralPath $f.FullName -Encoding UTF8)
  $nRef = @($code | Where-Object { $_ -match '\$SelfTest' }).Count
  if ($nRef -lt 2) { continue }
  $run = $false
  foreach ($v in @($gateVars[$f.Name])) {
    if ([string]::IsNullOrEmpty([string]$v)) { continue }
    if ($relTxt -match ([regex]::Escape([string]$v) + '\s+-SelfTest')) { $run = $true }
  }
  if (-not $run) { $selfTestNotRun += $f.Name }
}
if ($selfTestNotRun.Count -gt 0) {
  Write-Output ('  SELF-TEST NOT RUN (the gate carries one, and nothing runs it): ' + ($selfTestNotRun -join ', '))
  Write-Output '    A proof that is never run is a comment, and a comment rots without saying so.'
  $fail++
} else {
  Write-Output '  OK: every check gate that carries a live -SelfTest has that self-test run by the release gate.'
}
if ($noSelfTest.Count -gt 0) {
  Write-Output ('  NO SELF-TEST AND NO STATED REASON: ' + ($noSelfTest -join ', '))
  Write-Output '    Either give the gate a -SelfTest, or say in a comment why it has none.'
  $fail++
}

# ------------------------------------------ 6. every numbered gate can FAIL ---
# MEASURED 0615, and this section is about a defect the other sections could not
# see.
#
# The harness RECORDS a failure in `$script:MutationGateFailures` -- and a
# record that nothing reads is not a verdict. FIVE of the numbered gates (0491,
# 0496, 0500, 0501, 0502) ended at the `Invoke-MutationGate` call, with no
# `Write-MutationGateVerdict` and no `exit`: the script ended normally,
# `powershell -File` exited 0, the transcript carried no `GATE FAILED` line,
# and `release.ps1`'s `Run-Gate` -- which reads the transcript for a verdict
# ONLY when the exit code is non-zero -- reported the gate as PASS.
#
# PROVEN, not argued. With one `MustRed` claim in `mutate_0502.ps1` deliberately
# pointing at a test that does not exist, the gate printed `MUST-RED MISS`,
# recorded the failure in `$script:MutationGateFailures`, and STILL EXITED 0
# with no `GATE FAILED` line anywhere in its transcript. A release run would
# have reported that gate green, on a gate whose own mutation claim was false.
#
# AND THE OTHER DIRECTION IS THE SAME ONE. `check_gate_roster.ps1` checked that
# every numbered gate USES the shared harness -- the baseline, the pre-flight,
# the SHA256 restore, the COMPILE-ERR verdict -- and said nothing about whether
# the gate's own verdict could REACH the release gate. The harness's guarantees
# were all in place and the gate still could not fail.
#
# SO EVERY NUMBERED GATE MUST CARRY BOTH LINES: the verdict, and the exit that
# turns the recorded failures into a non-zero exit code. A gate that cannot
# fail is indistinguishable from a gate that passes -- the same shape as the
# roster defect this file was built for, one level down.
#
# THE LINES ARE READ FROM THE CODE, with the same here-string-aware reader this
# file already uses, so a mention of them inside a comment cannot make a gate
# look able to fail. That is not a hypothetical: the fix's own explanation
# quotes both lines.
Write-Output ''
Write-Output '=== 6. every numbered gate can FAIL ==='
$cannotFail = @()
$noVerdict = @()
$noExit = @()
foreach ($f in $gateFiles) {
  $code = Get-CodeLines (Get-Content -LiteralPath $f.FullName -Encoding UTF8)
  $body = ($code -join "`n")
  $hasVerdict = ($body -match 'Write-MutationGateVerdict')
  $hasExit = ($body -match '\$script:MutationGateFailures\.Count\s*-gt\s*0')
  if (-not $hasVerdict) { $noVerdict += $f.Name }
  if (-not $hasExit) { $noExit += $f.Name }
  if (-not ($hasVerdict -and $hasExit)) { $cannotFail += $f.Name }
}
if ($cannotFail.Count -gt 0) {
  Write-Output ('  CANNOT FAIL (no verdict, or no exit that carries it): ' + ($cannotFail -join ', '))
  Write-Output '    A gate that cannot fail looks exactly like a gate that passes. The harness'
  Write-Output '    records its failure in $script:MutationGateFailures and nobody reads it.'
  $fail++
} else {
  Write-Output ('  OK: all ' + $gateFiles.Count + ' numbered gates carry the verdict and the exit that carries it.')
}

Write-Output ''
if ($fail -eq 0) {
  Write-Output ('ROSTER OK: ' + $onDisk.Count + ' mutation gates, one harness, one roster, and a count that matches;')
  Write-Output ('           every one of them can FAIL, and the check gates below are run and showable.')
  Write-Output ('           ' + $checkFiles.Count + ' check gates, all of them run, and each one either showable or stated.')
  exit 0
}
Write-Output ('ROSTER FAILED: ' + $fail + ' problem(s).')
exit 1

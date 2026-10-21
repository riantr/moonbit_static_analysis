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
# The faults are the four the gate checks, plus the two directions of the roster
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
  )

  $bad = 0
  foreach ($f in $faults) {
    $c = New-FaultCopy
    try {
      # Every fault takes the copy dir; the ones that need the header count take
      # it as a second argument and the rest leave it in $args.
      & $f.Apply $c $n
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

Write-Output ''
if ($fail -eq 0) {
  Write-Output ('ROSTER OK: ' + $onDisk.Count + ' gates, one harness, one roster, and a count that matches.')
  exit 0
}
Write-Output ('ROSTER FAILED: ' + $fail + ' problem(s).')
exit 1

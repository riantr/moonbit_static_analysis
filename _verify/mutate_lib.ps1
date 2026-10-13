# Shared mutation-gate harness.
#
# WHY THIS FILE EXISTS. `_verify/mutate_0429.ps1` once reported
# "M4 KILLED, 2 of 442 red" while the two tests doing the killing were FAILING ON
# CLEAN CODE -- they asserted a `MethodError` the analyzer never emits. Every later
# mutation reported those same two red, so the gate looked healthy and the one
# mutation it had not actually pinned was reported as pinned. The fix was to run the
# UNMUTATED suite first and abort unless it is green.
#
# That fix was applied to 0429 only. Measured 2026-10-13, thirteen of the fourteen
# gates had no baseline check at all:
#
#     mutate_0412.ps1  baseline=False preflight=False sha256=False
#     mutate_0428.ps1  baseline=False preflight=True  sha256=True
#     mutate_0429.ps1  baseline=True  preflight=True  sha256=True
#
# So the defect was not in one script, it was in the PATTERN that fourteen copies
# of the pattern inherited -- and each copy has to be fixed by hand, which is
# exactly how the next one gets missed. This file is the harness; a release gate
# becomes a list of mutations and nothing else, so a new gate cannot reintroduce
# the bug by forgetting a guard.
#
# THE RULES IT ENFORCES, all of them learned the hard way.
#
#   1. BASELINE FIRST. A mutation count means nothing against a red suite. "KILLED"
#      and "was already red" are indistinguishable without a baseline.
#   2. COMPILE-ERR IS THE ABSENCE OF A `Total tests:` LINE, never a grep. A mutant
#      that fails to build is not a killed mutant; it is a mutant nobody measured.
#   3. NO-OP IS A FAILURE. A pattern that does not apply means the mutation never
#      happened, and a gate that reports success for a mutation it did not apply
#      is worse than no gate.
#   4. EVERY RESTORE IS PROVEN BY SHA256. Writing back the bytes you read is not
#      the same as writing back the bytes that were there.
#   5. `Expect = 'SURVIVED'` IS ALLOWED AND MUST BE ARGUED. Some mutations really
#      are unobservable; those are declared, not quietly dropped. The harness
#      cannot tell whether a survivor is legitimate -- only the comment can, and
#      that is the point of requiring the field.
#
# Usage from a release gate:
#
#     . (Join-Path $PSScriptRoot 'mutate_lib.ps1')
#     Invoke-MutationGate -Name 'M1..M5' -Target 'js' -Mutations @(
#       @{ Name='M1 ...'; File=$PARSER; Find=@'
#   ...
# '@; Repl='' },
#       ...
#     )
#
# `$Mutations` entries accept an optional `Expect` (default 'KILLED') and an
# optional `Prove` string, printed alongside a survivor so the argument travels
# with the result.

$script:MutationGateFailures = @()

function Invoke-MutationGate {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][Array]$Mutations,
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$MoonExe = 'C:\Users\31379\.moon\bin\moon.exe'
  )

  Write-Output ('=== mutation gate: ' + $Name + ' (target ' + $Target + ') ===')

  $nl = [string][char]10
  $enc = New-Object System.Text.UTF8Encoding($false)

  # ---- read every file the mutations touch, once ------------------------------
  $files = @($Mutations | ForEach-Object { $_.File } | Sort-Object -Unique)
  $texts = @{}
  foreach ($f in $files) {
    $p = Join-Path $Root $f
    if (-not (Test-Path -LiteralPath $p)) {
      Write-Output ('ABORT: no such file: ' + $f)
      $script:MutationGateFailures += ($Name + ' (missing file ' + $f + ')')
      return
    }
    $texts[$f] = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($p))
  }

  # ---- pre-flight: every pattern must be present, in milliseconds -------------
  $absent = @()
  foreach ($m in $Mutations) {
    $findText = ([string]$m.Find).Replace("`r`n", $nl)
    if ($texts[$m.File].IndexOf($findText, [System.StringComparison]::Ordinal) -lt 0) {
      $absent += $m.Name
      Write-Output ('PREFLIGHT MISS: ' + $m.Name + '  (' + $m.File + ')')
      Write-Output ('  looking for: |' + (($findText -split "`n")[0]) + '|')
    }
  }
  if ($absent.Count -gt 0) {
    Write-Output ('ABORT: ' + $absent.Count + ' pattern(s) absent. No suite was run.')
    $script:MutationGateFailures += ($Name + ' (preflight)')
    return
  }
  Write-Output ('Pre-flight: all ' + $Mutations.Count + ' patterns present.')

  # ---- BASELINE --------------------------------------------------------------
  # Rule 1. Without this, every count below is uninterpretable.
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $base = & $MoonExe test --target $Target 2>&1 | Out-String
  $ErrorActionPreference = $prev
  $bRan = [regex]::Matches($base, 'Total tests: (\d+), passed: (\d+), failed: (\d+)')
  if ($bRan.Count -lt 1) {
    Write-Output 'ABORT: baseline did not run (no `Total tests:` line). The suite does not compile.'
    $script:MutationGateFailures += ($Name + ' (baseline did not run)')
    return
  }
  $bM = $bRan[$bRan.Count - 1]
  $bTotal = [int]$bM.Groups[1].Value
  $bFailed = [int]$bM.Groups[3].Value
  Write-Output ("Baseline: {0}/{1} passed, {2} failed." -f $bM.Groups[2].Value, $bTotal, $bFailed)
  if ($bTotal -le 0) { Write-Output 'ABORT: baseline ran 0 tests.'; $script:MutationGateFailures += ($Name + ' (baseline 0)'); return }
  if ($bFailed -gt 0) {
    Write-Output ''
    Write-Output 'ABORT: the suite is RED on unmutated code. Every count below would be meaningless.'
    foreach ($ln in ($base -split "`r?`n" | Where-Object { $_ -match 'failed' } | Select-Object -First 10)) {
      Write-Output ('  ' + $ln.Trim())
    }
    $script:MutationGateFailures += ($Name + ' (baseline red)')
    return
  }

  # ---- run -------------------------------------------------------------------
  $results = @()
  foreach ($m in $Mutations) {
    $path = Join-Path $Root $m.File
    $bytes0 = [System.IO.File]::ReadAllBytes($path)
    $sha0 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $text = [System.Text.Encoding]::UTF8.GetString($bytes0)
    $eol = if ($text.Contains([string][char]13 + [char]10)) { [string][char]13 + [char]10 } else { $nl }
    $norm = $text.Replace($eol, $nl)
    $findN = ([string]$m.Find).Replace("`r`n", $nl)
    $replN = ([string]$m.Repl).Replace("`r`n", $nl)
    $want = if ($m.ContainsKey('Expect')) { [string]$m.Expect } else { 'KILLED' }

    # Rule 3. A pattern that does not apply is a failure, not a pass.
    if ($norm.IndexOf($findN, [System.StringComparison]::Ordinal) -lt 0) {
      $results += [pscustomobject]@{ Mutation = $m.Name; Outcome = 'NO-OP'; Killed = 0; Want = $want; Detail = 'pattern absent' }
      $script:MutationGateFailures += ($m.Name + ' (NO-OP)')
      continue
    }
    [System.IO.File]::WriteAllText($path, $norm.Replace($findN, $replN).Replace($nl, $eol), $enc)

    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $MoonExe test --target $Target 2>&1 | Out-String
    $ErrorActionPreference = $prev

    # Rule 2. Absence of the line, not a grep for an error string.
    $ran = [regex]::Matches($out, 'Total tests: (\d+), passed: (\d+), failed: (\d+)')
    $killed = 0; $detail = ''
    if ($ran.Count -ge 1) {
      $m2 = $ran[$ran.Count - 1]
      $total = [int]$m2.Groups[1].Value
      $passed = [int]$m2.Groups[2].Value
      if ($total -le 0) { $outcome = 'NO-RUN'; $detail = 'Total tests: 0' }
      else {
        $killed = $total - $passed
        if ($killed -gt 0) { $outcome = 'KILLED'; $detail = "$killed of $total red" }
        else { $outcome = 'SURVIVED'; $detail = "$total/$total still green" }
      }
    } else { $outcome = 'COMPILE-ERR'; $detail = 'no Total tests line; the suite did not run' }

    # Rule 4. Prove the restore byte-for-byte.
    [System.IO.File]::WriteAllBytes($path, $bytes0)
    if ($sha0 -ne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) {
      $detail += ' RESTORE-MISMATCH'
      $script:MutationGateFailures += ($m.Name + ' (restore)')
    }

    if ($outcome -ne $want) { $script:MutationGateFailures += ($m.Name + ' (wanted ' + $want + ')') }
    $results += [pscustomobject]@{ Mutation = $m.Name; Outcome = $outcome; Killed = $killed; Want = $want; Detail = $detail }

    $tag = if ($want -eq 'SURVIVED') { '   [expected survivor]' } else { '' }
    Write-Output ('  ' + $outcome.PadRight(11) + ' ' + $m.Name + '  -- ' + $detail + $tag)

    # Rule 5. A survivor has to carry its argument.
    if ($want -eq 'SURVIVED' -and $outcome -eq 'SURVIVED' -and $m.ContainsKey('Prove')) {
      Write-Output ('      prove: ' + $m.Prove)
    }
  }

  Write-Output ''
  $results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
  $killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
  $survExpected = @($results | Where-Object { $_.Outcome -eq 'SURVIVED' }).Count
  Write-Output ("{0} killed, {1} expected survivor(s), of {2}; every restore verified byte-identical" -f $killedCount, $survExpected, $Mutations.Count)
}

function Write-MutationGateVerdict {
  # RETURNS NOTHING, ON PURPOSE. The first version of this function ended with
  # `return $true` / `return $false` AND used Write-Output for its messages, and
  # PowerShell put those messages into the return value: `$ok` became a
  # `System.Object[]`, every array is truthy, so `if (-not $ok)` never fired and a
  # gate that had ABORTED still exited 0. The exact failure this harness exists to
  # prevent, reintroduced by the harness.
  #
  # Callers read `$script:MutationGateFailures.Count` directly. A function that both
  # speaks and answers has to choose, and in PowerShell the speaking wins.
  param([string]$Name)
  if ($script:MutationGateFailures.Count -eq 0) {
    Write-Output ("GATE OK: " + $Name)
    return
  }
  Write-Output ("GATE FAILED: " + $Name)
  foreach ($f in $script:MutationGateFailures) { Write-Output ('  - ' + $f) }
}

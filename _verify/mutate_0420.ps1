# 0.4.20 mutation gate.
#
# Two mutations, and they are opposite on purpose. The fix relaxed a sentinel;
# the interesting failure is not only "the fix is gone" but "the fix was the
# only thing protecting the file". M2 covers that second direction, which a
# one-mutation gate would have missed.
#
# Same rules as before: COMPILE-ERR is the absence of a `Total tests:` line,
# never a grep; every restore is byte-identical by SHA256.
#
# Usage: pwsh -File _verify/mutate_0420.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$results = @()
$failed  = @()

function Invoke-Mutation {
  param(
    [string]$Name, [string]$File, [string]$Find, [string]$Replace,
    [string]$Expect = 'KILLED'
  )
  $path = Join-Path $root $File
  if (-not (Test-Path $path)) {
    $script:results += [pscustomobject]@{ Mutation=$Name; Outcome='NO-FILE'; Killed=0; Detail="missing $File" }
    $script:failed += $Name; return
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $sha0  = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  $text0 = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($text0.IndexOf($Find, [System.StringComparison]::Ordinal) -lt 0) {
    $script:results += [pscustomobject]@{ Mutation=$Name; Outcome='NO-OP'; Killed=0; Detail='pattern absent' }
    $script:failed += $Name; return
  }
  [System.IO.File]::WriteAllText($path, $text0.Replace($Find, $Replace), (New-Object System.Text.UTF8Encoding($false)))

  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & moon test 2>&1 | Out-String
  $ErrorActionPreference = $prev

  $ran = [regex]::Matches($out, 'Total tests: (\d+), passed: (\d+), failed: (\d+)')
  $killed = 0; $detail = ''
  if ($ran.Count -ge 1) {
    $m = $ran[$ran.Count - 1]
    $total = [int]$m.Groups[1].Value
    $passed = [int]$m.Groups[2].Value
    if ($total -le 0) { $outcome='NO-RUN'; $detail='Total tests: 0'; $script:failed += $Name }
    else {
      $killed = $total - $passed
      if ($killed -gt 0) { $outcome='KILLED'; $detail="$killed of $total red" }
      else { $outcome='SURVIVED'; $detail="$total/$total still green" }
    }
  } else { $outcome='COMPILE-ERR'; $detail='no Total tests line; the suite did not run' }

  [System.IO.File]::WriteAllBytes($path, $bytes)
  if ($sha0 -ne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) {
    $detail += ' RESTORE-MISMATCH'; $script:failed += "$Name (restore)"
  }
  $script:results += [pscustomobject]@{ Mutation=$Name; Outcome=$outcome; Killed=$killed; Detail=$detail }
  if ($outcome -ne $Expect) { $script:failed += $Name }
}

# --- M1: the `with` exception removed -------------------------------------
# Back to firing on any `fn`. `impl T for U with fn m(self)` leaves its body
# behind and `self` is reported undefined again.
Invoke-Mutation 'M1 with-exception removed' 'src\parser\parser.mbt' `
  'if self.at_name("fn") && !saw_with {' `
  'if self.at_name("fn") {' 'KILLED'

# --- M2: the sentinel disabled outright -----------------------------------
# The OPPOSITE direction, and the one that matters: if the scan never stops at
# a top-level `fn`, then a BODILESS `pub impl E for S` runs past the following
# top-level function and swallows the rest of the file. Only the control test
# "0420: a bodiless impl still stops at the next top-level fn" can catch this.
Invoke-Mutation 'M2 fn sentinel disabled' 'src\parser\parser.mbt' `
  'if self.at_name("fn") && !saw_with {' `
  'if self.at_name("fn") && !saw_with && self.at_name("zzz_never") {' 'KILLED'

# --- M3: the HARVEST stops skipping method holders -----------------------
# `collect_declared_names` is a SECOND, separate name reader — it never goes
# through `skip_decl_braced`. Without its own guard the phantom method name
# comes straight back, and the whole 0.4.18/0.4.20 "two readers drift" lesson
# repeats. Only this mutation can catch it; the pipeline tests cannot see the
# sibling table.
Invoke-Mutation 'M3 harvest method-holder guard' 'src\parser\parser.mbt' `
  '} else if depth == 0 &&
          !in_holder &&
          (declares_value(n) || declares_type(n)) {' `
  '} else if depth == 0 &&
          (declares_value(n) || declares_type(n)) {' 'KILLED'

# --- M4: `trait`'s OWN name no longer harvested --------------------------
# The direction that a naive "skip the whole holder" fix gets wrong. Dropping
# `trait Marker`'s own name broke the pre-existing pyroduct test, which is how
# it was caught — this mutation pins that the name must still be there.
Invoke-Mutation 'M4 trait name not harvested' 'src\parser\parser.mbt' `
  '          if n == "trait" {' `
  '          if false {' 'KILLED'

Write-Output ''
Write-Output '=== 0.4.20 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
$survived = @($results | Where-Object { $_.Outcome -eq 'SURVIVED' }).Count
Write-Output ("{0} killed, {1} survived; every restore verified byte-identical" -f $killedCount, $survived)
if ($failed.Count -gt 0) { Write-Output ("FAILED: {0}" -f ($failed -join ', ')); exit 1 }
exit 0
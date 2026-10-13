# 0.4.29 mutation gate.
#
# Five mutations over one idea: `as` is an OPERATOR in expression position, the
# parser must consume it, and the three lenses must each keep working on what is
# left. Each one targets a DIFFERENT piece of the change, because a gate that
# only reverts the whole fix cannot tell whether the tests pin the parser rule or
# the lens wiring.
#
#   M1  revert the parser branch          is the `as` production load-bearing?
#   M2  walk stops walking the operand    does the fix trade one FP for another?
#   M3  infer stops typing the operand    is checking inside a cast preserved?
#   M4  interp stops evaluating it        is the interpreter arm doing anything?
#   M5  parser drops the target type      is the `as` rule bounded?
#
# M2 IS THE ONE THAT MATTERS MOST. Removing the false positive is easy; doing it
# by not looking at the operand would also make every parameter read only inside
# a cast look unused. The suite must go red for the second reason too.
#
# M5 is the boundary. `type_annotation` consumes `&Trait`; without it the `&` and
# the type name are left in the stream and the parse desynchronises -- which is
# the original bug in a different disguise, not a safe no-op.
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as a
# failure; the PRE-FLIGHT reports an absent pattern in milliseconds.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0429.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$PARSER = 'src\parser\parser.mbt'
$WALK   = 'src\walk\walk.mbt'
$INFER  = 'src\types\infer.mbt'
$INTERP = 'src\interp\interp.mbt'

$muts = @(
  # --- M1: revert the parser branch -------------------------------------------
  # The postfix loop breaks on `as` again, exactly as before 0.4.29. The leftover
  # `as` becomes the next statement and the binding walk resolves it as a name.
  @{
    Name = 'M1 revert: the parser has no production for `as`'
    File = $PARSER
    Find = @'
    if self.at_name("as") {
      let asp = self.span()
      let _ = self.bump()
      let _ = self.type_annotation()
      e = { span: asp, kind: @ast.ECast(e), }
      continue
    }
'@
    Repl = ''
  }

  # --- M2: walk stops walking the operand -------------------------------------
  # The cast still parses and still silences `undefined name 'as'`; only the
  # operand is dropped. This is the mutation that would trade one false positive
  # for another, and only the "parameter read only inside a cast" test sees it.
  @{
    Name = 'M2 walk no longer walks the cast operand'
    File = $WALK
    Find = '    ECast(base) => self.walk_expr(base)'
    Repl = '    ECast(_) => ()'
  }

  # --- M3: infer stops typing the operand -------------------------------------
  # The cast returns TUnknown either way, so the RESULT is unchanged; what is lost
  # is every finding inside the operand. Only the ArgTypeMismatch test sees it.
  @{
    Name = 'M3 infer no longer types the cast operand'
    File = $INFER
    Find = @'
    ECast(base) => {
      let _ = self.ty_of(base, TUnknown)
      TUnknown
    }
'@
    Repl = '    ECast(_) => TUnknown'
  }

  # --- M4: interp stops evaluating the operand --------------------------------
  # The result is AAny either way. This one is EXPECTED TO SURVIVE and is gated as
  # such -- see the note below the results table. It is not a coverage gap that
  # was papered over: `_verify/probe_0429_m4.ps1` applies this mutation, rebuilds,
  # and diffs the analyzer's real output on five programs (an `is` binding inside a
  # cast operand, the same without a cast, a cast in a called function, an unbound
  # read in a called function, and an `is` binding plus an unbound read). All five
  # are byte-identical with and without the mutation.
  #
  # Two mechanisms explain it, both measured rather than guessed:
  #   - an unbound name inside a cast operand is reported by WALK, as
  #     `undefined name` [structural+type]. The interpreter's `undefined variable`
  #     shares the family and the span, so `merge_findings` shows one and hides
  #     the other -- dropping the interpreter's copy changes nothing downstream.
  #   - `FMethodError` and `FOpMismatch` share the `"arg-type"` group
  #     (core.mbt:380), so an operator mismatch inside the operand is also
  #     collapsed into whichever lens reported first.
  @{
    Name = 'M4 interp no longer evaluates the cast operand'
    File = $INTERP
    Expect = 'SURVIVED'
    Find = @'
    ECast(base) => {
      let _ = self.eval(base, env)
      AAny
    }
'@
    Repl = '    ECast(_) => AAny'
  }

  # --- M5: the parser drops the target type -----------------------------------
  # `as` is consumed but `&Trait` is not, so the stream is left mid-type. This is
  # the boundary the whole branch rests on.
  @{
    Name = 'M5 the parser stops consuming the cast target type'
    File = $PARSER
    Find = @'
      let _ = self.bump()
      let _ = self.type_annotation()
      e = { span: asp, kind: @ast.ECast(e), }
'@
    Repl = @'
      let _ = self.bump()
      e = { span: asp, kind: @ast.ECast(e), }
'@
  }
)

# ---------------------------------------------------------------------------
# PRE-FLIGHT
# ---------------------------------------------------------------------------
$nl = [string][char]10
$texts = @{}
foreach ($f in @($PARSER, $WALK, $INFER, $INTERP)) {
  $texts[$f] = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Join-Path $root $f)))
}

$absent = @()
foreach ($m in $muts) {
  $findText = $m.Find.Replace("`r`n", $nl)
  if ($texts[$m.File].IndexOf($findText, [System.StringComparison]::Ordinal) -lt 0) {
    $absent += $m.Name
    Write-Output ("PREFLIGHT MISS: " + $m.Name + "  (" + $m.File + ")")
    Write-Output ("  looking for: |" + (($findText -split "`n")[0]) + "|")
  }
}
if ($absent.Count -gt 0) {
  Write-Output ("ABORT: " + $absent.Count + " pattern(s) absent. No suite was run.")
  exit 1
}
Write-Output ('Pre-flight: all ' + $muts.Count + ' patterns present.')

# ---------------------------------------------------------------------------
# BASELINE
# ---------------------------------------------------------------------------
# This gate was wrong once and the reason is worth recording. A run reported
# "M4 KILLED, 2 of 442 red" while the two tests doing the killing were FAILING ON
# CLEAN CODE -- they asserted a `MethodError` that the analyzer never emits. Every
# later mutation also reported those same two red, so the gate looked healthy and
# the one mutation it had not actually pinned was reported as pinned.
#
# A mutation count only means something against a green baseline. Without this
# block, "KILLED" and "was already red" are indistinguishable, and a suite that
# is broken from the start launders its own breakage into evidence.
$prev0 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$base = & C:\Users\31379\.moon\bin\moon.exe test --target js 2>&1 | Out-String
$ErrorActionPreference = $prev0
$bRan = [regex]::Matches($base, 'Total tests: (\d+), passed: (\d+), failed: (\d+)')
if ($bRan.Count -lt 1) {
  Write-Output 'ABORT: baseline did not run (no `Total tests:` line). The suite does not compile.'
  exit 1
}
$bM = $bRan[$bRan.Count - 1]
$bTotal = [int]$bM.Groups[1].Value
$bPassed = [int]$bM.Groups[2].Value
$bFailed = [int]$bM.Groups[3].Value
Write-Output ("Baseline: {0}/{1} passed, {2} failed." -f $bPassed, $bTotal, $bFailed)
if ($bTotal -le 0) { Write-Output 'ABORT: baseline ran 0 tests.'; exit 1 }
if ($bFailed -gt 0) {
  Write-Output ''
  Write-Output 'ABORT: the suite is RED on unmutated code. Every count below would be meaningless.'
  foreach ($ln in ($base -split "`r?`n" | Where-Object { $_ -match 'failed' } | Select-Object -First 10)) {
    Write-Output ('  ' + $ln.Trim())
  }
  exit 1
}

# ---------------------------------------------------------------------------
# RUN
# ---------------------------------------------------------------------------
$results = @()
$failed  = @()

foreach ($m in $muts) {
  $path = Join-Path $root $m.File
  $bytes0 = [System.IO.File]::ReadAllBytes($path)
  $sha0  = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  $text  = [System.Text.Encoding]::UTF8.GetString($bytes0)
  $eol = if ($text.Contains([string][char]13 + [char]10)) { [string][char]13 + [char]10 } else { [string][char]10 }
  $norm  = $text.Replace($eol, $nl)
  $findN = $m.Find.Replace("`r`n", $nl)
  $replN = $m.Repl.Replace("`r`n", $nl)

  if ($norm.IndexOf($findN, [System.StringComparison]::Ordinal) -lt 0) {
    $results += [pscustomobject]@{ Mutation=$m.Name; Outcome='NO-OP'; Killed=0; Detail='pattern absent' }
    $failed += $m.Name
    continue
  }
  [System.IO.File]::WriteAllText($path, $norm.Replace($findN, $replN).Replace($nl, $eol), (New-Object System.Text.UTF8Encoding($false)))

  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & C:\Users\31379\.moon\bin\moon.exe test --target js 2>&1 | Out-String
  $ErrorActionPreference = $prev

  $ran = [regex]::Matches($out, 'Total tests: (\d+), passed: (\d+), failed: (\d+)')
  $killed = 0; $detail = ''
  if ($ran.Count -ge 1) {
    $m2 = $ran[$ran.Count - 1]
    $total = [int]$m2.Groups[1].Value
    $passed = [int]$m2.Groups[2].Value
    if ($total -le 0) { $outcome='NO-RUN'; $detail='Total tests: 0'; $failed += $m.Name }
    else {
      $killed = $total - $passed
      if ($killed -gt 0) { $outcome='KILLED'; $detail="$killed of $total red" }
      else { $outcome='SURVIVED'; $detail="$total/$total still green" }
    }
  } else { $outcome='COMPILE-ERR'; $detail='no Total tests line; the suite did not run' }

  [System.IO.File]::WriteAllBytes($path, $bytes0)
  if ($sha0 -ne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) {
    $detail += ' RESTORE-MISMATCH'; $failed += ($m.Name + ' (restore)')
  }
  $results += [pscustomobject]@{ Mutation=$m.Name; Outcome=$outcome; Killed=$killed; Detail=$detail }
  $want = if ($m.ContainsKey('Expect')) { $m.Expect } else { 'KILLED' }
  if ($outcome -ne $want) { $failed += ($m.Name + ' (wanted ' + $want + ')') }
  Write-Output ('  ' + $outcome.PadRight(11) + ' ' + $m.Name + '  -- ' + $detail + $(if ($want -eq 'SURVIVED') { '   [expected survivor]' } else { '' }))
}

Write-Output ''
Write-Output '=== 0.4.29 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
$survExpected = @($results | Where-Object { $_.Outcome -eq 'SURVIVED' }).Count
Write-Output ("{0} of {1} killed; {2} expected survivor(s); every restore verified byte-identical" -f $killedCount, $muts.Count, $survExpected)
Write-Output ''
Write-Output 'ON THE SURVIVOR. M4 (interp does not evaluate the cast operand) is EXPECTED to'
Write-Output 'survive and is NOT counted as a failure, but it is also NOT claimed equivalent'
Write-Output 'over the whole input space -- that was not proven and is not asserted. What is'
Write-Output 'measured is that _verify/probe_0429_m4.ps1 finds the analyzer output byte-identical'
Write-Output 'with and without it on five programs, for two reasons given in the M4 comment above.'
Write-Output 'The `eval` is kept because every sibling arm (EField, ETupleField, EStruct, EComp,'
Write-Output 'EMethodCall) evaluates its operands; consistency with them is a reason, not a proof.'
if ($failed.Count -gt 0) { Write-Output ("FAILED: {0}" -f ($failed -join ', ')); exit 1 }
exit 0
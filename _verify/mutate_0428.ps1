# 0.4.28 mutation gate.
#
# Four mutations over ONE idea: `derive(Debug, Eq, Clone)` is a parenthesised
# trait list with no braces, so it is a LINE declaration, not a braced one.
#
#   M1  revert the routing                 is the change load-bearing?
#   M2  the message claims a body again    message and routing are separate
#   M3  derive handled by neither          what a dropped branch would do
#   M4  the line skipper loses its end     is the boundary still bounded?
#
# M1 and M2 are deliberately separated because they are two different halves of
# the fix and only one of them shows in the notice TEXT. M1 restores the
# mis-routing, whose visible effect is that a following struct's exclusion notice
# disappears. M2 keeps the correct routing and re-adds the false "its body was
# not analyzed" wording. If only M1 were killed, the tests would be pinning the
# routing and would happily accept a message that claims a body that does not
# exist.
#
# M4 is the boundary the whole fix rests on. `skip_decl_line` stops at a newline;
# without that guard the derive line keeps eating whatever follows, which is the
# original bug wearing a different hat.
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as a
# failure; the PRE-FLIGHT reports an absent pattern in milliseconds.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0428.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$PARSER = 'src\parser\parser.mbt'

$muts = @(
  # --- M1: revert the routing ------------------------------------------------
  # `derive` back on the braced list. The skipper then scans forward for `{` and
  # consumes a LATER declaration's body -- which is what made struct notices
  # vanish in the corpus (572 -> 829 when this is correct, i.e. 257 exclusions
  # that were being swallowed).
  @{
    Name = 'M1 revert: derive goes back to the braced skipper'
    File = $PARSER
    Find = @'
      kw == "impl" ||
      kw == "extend" ||
      kw == "test" {
      p.skip_decl_braced(kw, sp)
    } else if kw == "type" || kw == "const" || kw == "derive" {
'@
    Repl = @'
      kw == "impl" ||
      kw == "derive" ||
      kw == "extend" ||
      kw == "test" {
      p.skip_decl_braced(kw, sp)
    } else if kw == "type" || kw == "const" {
'@
  }

  # --- M2: the message claims a body again ----------------------------------
  # Correct routing, wrong prose. Isolates the wording half of the fix.
  @{
    Name = 'M2 the derive notice claims a body that does not exist'
    File = $PARSER
    Find = '  self.skip(what, false, sp)'
    Repl = '  self.skip(what, true, sp)'
  }

  # --- M3: derive handled by neither arm -------------------------------------
  # What a branch that simply fell through would do. `derive` would reach the
  # expression parser as an ordinary name.
  @{
    Name = 'M3 derive is handled by no arm at all'
    File = $PARSER
    Find = '    } else if kw == "type" || kw == "const" || kw == "derive" {'
    Repl = '    } else if kw == "type" || kw == "const" {'
  }

  # --- M4: the line skipper loses its terminator -----------------------------
  # `skip_decl_line` stops at a newline or semicolon. Drop the newline guard and
  # the derive line consumes the following declaration -- the original bug in a
  # different disguise.
  @{
    Name = 'M4 the line skipper no longer stops at the newline'
    File = $PARSER
    Find = '  while !self.at(TEOF) && !self.at(TNewline) && !self.at(TSemi) {'
    Repl = '  while !self.at(TEOF) && !self.at(TSemi) {'
  }
)

# ---------------------------------------------------------------------------
# PRE-FLIGHT
# ---------------------------------------------------------------------------
$nl = [string][char]10
$texts = @{}
foreach ($f in @($PARSER)) {
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
  if ($outcome -ne 'KILLED') { $failed += $m.Name }
  Write-Output ('  ' + $outcome.PadRight(11) + ' ' + $m.Name + '  -- ' + $detail)
}

Write-Output ''
Write-Output '=== 0.4.28 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
Write-Output ("{0} of {1} killed; every restore verified byte-identical" -f $killedCount, $muts.Count)
if ($failed.Count -gt 0) { Write-Output ("FAILED: {0}" -f ($failed -join ', ')); exit 1 }
exit 0
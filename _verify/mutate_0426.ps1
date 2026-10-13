# 0.4.26 mutation gate.
#
# Seven mutations over ONE idea: a function's TAIL EXPRESSION is its return
# value, and exactly one statement -- the last one, in a function body -- is it.
#
# The set is built around the fact that this fix touches FOUR decisions in FOUR
# files, and a change to any one of them can be invisible to the others:
#
#   parser, fn_body flag  is a FUNCTION body a tail?        (M3)
#   parser, position     is this the LAST statement?        (M4)
#   parser, plumbing     does the flag REACH a fn body?     (M7)
#   interp, record       is the value pushed at all?        (M1)
#   interp, what         is pushed -- the value or Bottom?  (M2)
#   interp, ()           is the empty tuple Unit?           (M5)
#   interp, over-fix     and is a REAL tuple still one?     (M6)
#
# M5 and M6 are the same arm in opposite directions and they are the pair that
# matters most: M5 is a REGRESSION I ACTUALLY SHIPPED INTO A SCAN. The type lens
# was taught that `()` is Unit to match the interpreter, and it cost a new false
# `OperatorMismatch` on wzzc-dev/moui `backend/macos/macos_backend.mbt:204`
# before the six-corpus diff caught it. M5 is the mutation that reproduces that
# mistake, so it is in the gate permanently rather than as a story.
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as
# a failure. The PRE-FLIGHT exists because 0.4.25 wasted three full `moon test`
# runs on patterns that did not match the source at all -- an absent pattern is
# now reported in milliseconds instead of after the suite.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0426.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$INTERP = 'src\interp\interp.mbt'
$PARSER = 'src\parser\parser.mbt'

$muts = @(
  # --- M1: the tail value is not recorded at all --------------------------
  # This is the ORIGINAL behaviour: `SExpr` evaluates and drops. With it, every
  # tail-expression function reports `-> None` again and callers inherit that.
  #
  # Written against the ONE-LINE form `moon fmt` leaves behind. The first version
  # of this gate assumed a braced three-line arm and the pre-flight rejected it
  # in milliseconds -- which is the whole reason the pre-flight exists.
  @{
    Name = 'M1 the tail value is not recorded'
    File = $INTERP
    Find = '    STail(e) => self.ret_vals.push(self.eval(e, env))'
    Repl = @'
    STail(e) => {
      let _ = self.eval(e, env)
    }
'@
  }

  # --- M2: the wrong thing is recorded ------------------------------------
  # The `SRaise` mistake applied to a tail expression: pushing `ABottom`
  # instead of the value. The expression is the RESULT, not an operand after
  # the end of the frame, so this is the one place the raise rule must NOT
  # apply -- and it is the mistake the shared node shape invites.
  @{
    Name = 'M2 the tail pushes Bottom instead of the value'
    File = $INTERP
    Find = '    STail(e) => self.ret_vals.push(self.eval(e, env))'
    Repl = '    STail(e) => self.ret_vals.push(ABottom)'
  }

  # --- M3: `fn_body` ignored -- every block has a tail ---------------------
  # A loop body's, an `if` arm's and a bare block's trailing expressions all
  # become return values, and the joins widen.
  @{
    Name = 'M3 fn_body ignored, every block has a tail'
    File = $PARSER
    Find = '    if fn_body && self.at(TRBrace) {'
    Repl = '    if self.at(TRBrace) {'
  }

  # --- M4: position ignored -- every expression statement is a tail --------
  # The opposite half of the same condition. An `SExpr` anywhere in a function
  # body becomes the tail, so the LAST one is joined with all the others.
  @{
    Name = 'M4 position ignored, every expression statement is a tail'
    File = $PARSER
    Find = '    if fn_body && self.at(TRBrace) {'
    Repl = '    if fn_body {'
  }

  # --- M5: the empty tuple is a tuple again -------------------------------
  # THE REGRESSION THAT WAS MEASURED, not imagined. The type lens was taught
  # `()` is Unit to match the interpreter and produced a new false
  # `unsupported operand types for '>': 'int' and 'None'` on moui
  # `backend/macos/macos_backend.mbt:204`, in a file whose parse stop point,
  # notice count and actionable count had all been identical a moment before.
  # Six-corpus byte diff is what caught it; nothing else did.
  @{
    Name = 'M5 the empty tuple is a Tuple again'
    File = $INTERP
    Find = @'
    ETuple(elems) => {
      if elems.length() == 0 {
        return AType("None")
      }
      for x in elems {
'@
    Repl = @'
    ETuple(elems) => {
      for x in elems {
'@
  }

  # --- M6: the over-fix -- every tuple is Unit -----------------------------
  # M5's opposite. `()` is Unit, but `(1, 2)` is a tuple, and answering Unit
  # for both is as wrong as answering Tuple for both. The fixture that catches
  # it is the one where a tuple IS the returned value; a tuple bound to a local
  # never reaches `ret_vals` and reads this arm not at all.
  @{
    Name = 'M6 every tuple is Unit (the over-fix)'
    File = $INTERP
    Find = @'
    ETuple(elems) => {
      if elems.length() == 0 {
        return AType("None")
      }
      for x in elems {
'@
    Repl = @'
    ETuple(elems) => {
      if true {
        return AType("None")
      }
      for x in elems {
'@
  }

  # --- M7: the flag never reaches a function body --------------------------
  # Plumbing, not semantics: `parse_fn` hands `parse_block` `false`, so no
  # function ever produces a tail. Reads like M1 from the outside, and that is
  # the point -- it is the only mutation that can tell "the node is never built"
  # apart from "the node is built and dropped".
  @{
    Name = 'M7 the flag never reaches a function body'
    File = $PARSER
    Find = @'
  let (name, params, retann) = self.parse_fn_signature()
  let (body, endsp) = self.parse_block(true)
'@
    Repl = @'
  let (name, params, retann) = self.parse_fn_signature()
  let (body, endsp) = self.parse_block(false)
'@
  }
)

# ---------------------------------------------------------------------------
# PRE-FLIGHT
# ---------------------------------------------------------------------------
$nl = [string][char]10
$texts = @{}
foreach ($f in @($INTERP, $PARSER)) {
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
Write-Output '=== 0.4.26 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
$survived = @($results | Where-Object { $_.Outcome -eq 'SURVIVED' }).Count
Write-Output ("{0} killed, {1} survived; every restore verified byte-identical" -f $killedCount, $survived)
if ($failed.Count -gt 0) { Write-Output ("FAILED: {0}" -f ($failed -join ', ')); exit 1 }
exit 0
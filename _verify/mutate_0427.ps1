# 0.4.27 mutation gate.
#
# Five mutations over ONE idea: a parenthesised FUNCTION TYPE in return position
# (`-> (() -> Int)`) is not a one-element tuple, and the only thing separating
# the two is whether a `->` appears INSIDE the group or just after it.
#
# The set is built around how small that change is. The whole release is one
# boolean and one `||`, which is exactly the size of change that can be
# "obviously right" while being wrong in a direction nothing reports:
#
#   M1  revert entirely                     is the change load-bearing?
#   M2  the assignment neutered             or is only the `||` doing work?
#   M3  the OLD arm dropped                 does the unparenthesised spelling survive?
#   M4  `arrow_inside` starts `true`        is the over-fix caught? (the tuple controls)
#   M5  the scan never runs                 plumbing vs semantics
#
# M1 and M2 are deliberately redundant. M1 removes the feature; M2 leaves the
# feature in place and disarms the one line that records it. If only M1 killed,
# the tests would be pinning the `||` rather than the behaviour, and a rewrite
# that kept the `||` and moved the assignment would have passed them.
#
# M4 is the direction that ships damage rather than noise. `arrow_inside` starting
# `true` makes EVERY `-> (...)` a function type, including 179 genuine tuple
# returns. Whether the suite catches that is the question this gate exists to
# answer, and the answer is recorded rather than assumed.
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as a
# failure; the PRE-FLIGHT reports an absent pattern in milliseconds instead of
# after a full suite.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0427.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$PARSER = 'src\parser\parser.mbt'

$muts = @(
  # --- M1: revert the whole change -----------------------------------------
  # This is 0.4.26's behaviour. The parenthesised spelling falls into the tuple
  # arm, which consumes to the first `)` with no comma -- the one closing the
  # empty parameter list -- so `-> Int)` is left in the token stream and
  # `parse_block` reports `expected '{'` and the rest of the file dies.
  @{
    Name = 'M1 revert: parenthesised fn type reads as a tuple again'
    File = $PARSER
    Find = '    arrow_inside || is_fn'
    Repl = '    is_fn'
  }

  # --- M2: the assignment is the load-bearing line, not the `||` ------------
  # `arrow_inside` still exists, is still read, and is still OR-ed in. Only the
  # one statement that sets it is changed. If this survives, the tests are
  # pinning the expression and not the behaviour.
  @{
    Name = 'M2 the arrow assignment is neutralised'
    File = $PARSER
    Find = '        TArrow => arrow_inside = true'
    Repl = '        TArrow => arrow_inside = false'
  }

  # --- M3: the pre-existing arm is dropped ----------------------------------
  # `arrow_inside || is_fn` -> `arrow_inside`. The UNPARENTHESISED spelling
  # (`-> (Int) -> String`, where the arrow follows the matching `)`) sets no
  # `arrow_inside` at all, so it falls back to the tuple arm. This is the
  # mutation that keeps 0.4.27's code and breaks something older.
  @{
    Name = 'M3 the unparenthesised spelling is dropped'
    File = $PARSER
    Find = '    arrow_inside || is_fn'
    Repl = '    arrow_inside'
  }

  # --- M4: the over-fix ------------------------------------------------------
  # `arrow_inside` starts true, so every `-> (...)` is read by the function-type
  # arm. EXPECTED TO SURVIVE, and the expectation is proved rather than assumed --
  # see EQUIVALENT below.
  @{
    Name = 'M4 every parenthesised return is treated as a fn type'
    File = $PARSER
    Find = '    let mut arrow_inside = false'
    Repl = '    let mut arrow_inside = true'
    # Not a coverage gap. An equivalent mutant, with the proof:
    #
    #   * the tuple arm returns `""`               (parser.mbt:1272)
    #   * the fn-type arm returns "(Int)" etc.     (fn_type_annotation:1016 --
    #                                              no `->` follows, so `out`
    #                                              stays the parenthesised group)
    #   * `ann_to_ty("")`          == TUnknown     (types.mbt:140)
    #   * `ann_to_ty("(Int)")`     == TUnknown     (no arm matches a string that
    #                                              still carries its parentheses,
    #                                              so it falls through to
    #                                              ann_to_list_ty and matches
    #                                              neither `Array[` nor `[..]`)
    #
    # The annotation string has exactly one consumer, `declared_ret`, and both
    # arms feed it TUnknown for every input M4 redirects. So over the WHOLE input
    # space M4 cannot change an observable. Fabricating a fixture to kill it would
    # be theatre: the mutant has no behaviour to kill.
    #
    # It stays in the gate because "survived" and "equivalent" look identical on
    # screen, and only one of them is acceptable. The run asserts that M4 is the
    # one that survives, so a future change that makes M4 killable -- or that
    # breaks the equivalence -- shows up here instead of being assumed.
    Expect = 'SURVIVED'
    Prove = @'
equivalent: tuple arm returns "", fn-type arm returns "(Int)", and ann_to_ty maps
both to TUnknown (types.mbt:140); declared_ret is the annotation string's only consumer
'@
  }

  # --- M5: the scan never runs ------------------------------------------------
  # Plumbing, not semantics: the loop body never executes, so neither flag is
  # ever set. Reads from outside like M1, and that is the point -- it is the only
  # mutation that can tell "the scan ran and said no" apart from "the scan never
  # happened".
  @{
    Name = 'M5 the scan never runs'
    File = $PARSER
    Find = '    let mut j = self.p'
    Repl = '    let mut j = self.toks.length()'
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
  # A mutation may declare the outcome it is entitled to, and only with a proof.
  # This is NOT "expected failures are allowed" -- a SURVIVED without `Expect`
  # still fails the gate. What it does is stop the run from calling two very
  # different things (untested, and behaviourally equivalent) by the same name.
  $expected = if ($m.ContainsKey('Expect')) { $m.Expect } else { 'KILLED' }
  if ($outcome -eq $expected) {
    $verdict = $outcome
    if ($expected -eq 'SURVIVED' -and $m.ContainsKey('Prove')) {
      $verdict = 'EQUIVALENT'
      Write-Output ('  ' + $verdict.PadRight(11) + ' ' + $m.Name)
      Write-Output ('      proof: ' + ($m.Prove -replace '\s+', ' ').Trim())
    }
  } else {
    $verdict = 'UNEXPECTED-' + $outcome
    $failed += ($m.Name + ' (expected ' + $expected + ', got ' + $outcome + ')')
    Write-Output ('  ' + $verdict.PadRight(11) + ' ' + $m.Name + '  -- ' + $detail)
  }
  $results += [pscustomobject]@{ Mutation=$m.Name; Outcome=$verdict; Killed=$killed; Detail=$detail }
}

Write-Output ''
Write-Output '=== 0.4.27 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
$equivCount = @($results | Where-Object { $_.Outcome -eq 'EQUIVALENT' }).Count
Write-Output ("{0} killed, {1} proved equivalent; every restore verified byte-identical" -f $killedCount, $equivCount)
if ($failed.Count -gt 0) { Write-Output ("FAILED: {0}" -f ($failed -join ', ')); exit 1 }
exit 0
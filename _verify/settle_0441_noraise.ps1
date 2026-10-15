# 0.4.31 settle: is `noraise` real MoonBit syntax, and what shape does it take?
#
# WHY. 0441 left 4 actionable `undefined name 'noraise'` findings, the largest
# single NAMED item left. Measured sites, all four of them:
#
#   proton facade_identity.mbt:99    } noraise {
#   proton facade_identity.mbt:136   } noraise {
#   proton protocol_wbtest.mbt:5     } noraise {
#   async  network.mbt:68            } noraise {
#
# The measured source shape (proton facade_identity.mbt:95-101) is
#
#     try @proton_config.validate_application_identifier(identifier) catch {
#       @proton_config.InvalidField(expectation~, ..) =>
#         Err(InvalidSetting(name="identifier", message=expectation))
#       error => Err(InvalidSetting(name="identifier", message=error.message()))
#     } noraise {
#       identifier => Ok(identifier)
#     }
#
# So `noraise` is NOT a function, a macro or a decorator -- it is a SECOND HANDLER
# BLOCK attached to a completed `try ... catch`, and the analyzer reads the bare
# token as an ordinary name and reports it undefined.
#
# The obvious question is whether proton is using real syntax at all. It is, or
# proton does not compile, and proton 0.3.4 is a published package this project
# already scans -- but "obviously yes" is exactly the kind of claim that has
# burned six increments in a row, so it is settled here with the compiler rather
# than asserted. The thing a compiler settles and a reading of proton cannot is
# WHICH SHAPES ARE LEGAL, and that is what the AST has to carry.
#
# THE POSITIVE CONTROL IS FIRST AND IT IS NOT DECORATIVE. 0439's probe threw away
# three preludes because all twelve cells failed INCLUDING the control; a run in
# which the control fails has measured the probe, not the grammar. If
# POS_no_noraise is REJECTED, stop and fix the prelude -- read nothing else.
#
# WHAT THIS PROBE CANNOT SETTLE, STATED RATHER THAN FAKED: what the `noraise`
# pattern BINDS semantically. `bind_x_is_the_result` gets type-checked evidence
# (it is the closest thing to a binding test a compiler offers here), but a real
# semantic statement about `raise` propagation and arm selection needs runtime
# behaviour, not `moon check`. This probe settles GRAMMAR.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/settle_0441_noraise.ps1
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP ('settle0441_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0441`"`nversion = `"0.1.0`"`n", $enc)

$PRE = @"
priv suberror MyErr

fn fallible(n : Int) -> Int raise MyErr {
  if n == 0 { raise MyErr }
  n
}

fn silent(n : Int) -> Unit raise MyErr {
  if n == 0 { raise MyErr }
}

"@

$cases = [ordered]@{
  # POSITIVE CONTROL: `catch` and NO `noraise` anywhere. Settled by 0439 as
  # ACCEPTED. If this is rejected the prelude or the harness is wrong and every
  # verdict below is void.
  'POS_no_noraise.mbt' = $PRE + "fn keep(n : Int) -> Int raise MyErr {`n  fallible(n) catch { _ => 0 }`n}`n"

  # A: THE CORPUS SHAPE, reduced. Block-bodied catch, then `noraise` with one
  # expression arm. proton writes this 4 times; if it is rejected, every one of
  # those findings is proton's bug and not ours.
  'a_after_catch.mbt' = $PRE + "fn keep(n : Int) -> Int raise MyErr {`n  fallible(n) catch { _ => 0 } noraise { _ => 1 }`n}`n"

  # B: MULTIPLE arms in the noraise block, the way `catch` takes several.
  'b_two_arms.mbt' = $PRE + "fn keep(n : Int) -> Int raise MyErr {`n  fallible(n) catch { _ => 0 } noraise {`n    _ => 1`n    _ => 2`n  }`n}`n"

  # C: BLOCK-bodied noraise arm, the shape the catch parser already knows how to
  # read. If only the expression form is legal, the AST needs only one production
  # and the handler body is not a statement list.
  'c_block_arm.mbt' = $PRE + "fn keep(n : Int) -> Int raise MyErr {`n  fallible(n) catch { _ => 0 } noraise { x => {`n    let y = x`n    y + 1`n  } }`n}`n"

  # D: THE BINDING TEST. `x + 1` type-checks ONLY if `x` is the Int RESULT of the
  # try base. If `noraise`'s pattern bound the error value instead, this is a type
  # error and the arm binds something else -- which the analyzer would have to
  # know before it can bind names in the block.
  'bind_x_is_the_result.mbt' = $PRE + "fn keep(n : Int) -> Int raise MyErr {`n  fallible(n) catch { _ => 0 } noraise { x => x + 1 }`n}`n"

  # E: NO `catch` AT ALL. If this is accepted then `noraise` is not a property of
  # a completed catch handler and the parser's guard has to be elsewhere.
  'nr_without_catch.mbt' = $PRE + "fn keep(n : Int) -> Int raise MyErr {`n  fallible(n) noraise { _ => 1 }`n}`n"

  # NEGATIVE CONTROL 1: an EMPTY noraise block. If ACCEPTED, `noraise` is not
  # being enforced and every ACCEPTED above means less than it appears to.
  'NEG_empty.mbt' = $PRE + "fn keep(n : Int) -> Int raise MyErr {`n  fallible(n) catch { _ => 0 } noraise { }`n}`n"

  # NEGATIVE CONTROL 2: a `noraise` attached to something that is not a try at
  # all. `noraise` must be a postfix on the try/catch expression and not a
  # statement-level keyword that binds loosely.
  'NEG_not_a_try.mbt' = $PRE + "fn keep(n : Int) -> Int raise MyErr {`n  let x = 1`n  noraise { _ => x }`n  x`n}`n"
}

$expected = @{
  'POS_no_noraise.mbt'     = 'ACCEPTED'
  'a_after_catch.mbt'      = 'ACCEPTED'
  'b_two_arms.mbt'         = 'ACCEPTED'
  'c_block_arm.mbt'        = 'ACCEPTED'
  'bind_x_is_the_result.mbt' = 'ACCEPTED'
  'nr_without_catch.mbt'   = 'REJECTED'
  'NEG_empty.mbt'          = 'REJECTED'
  'NEG_not_a_try.mbt'      = 'REJECTED'
}

$outFile = Join-Path $dir 'check.out'
$fail = 0
Push-Location $dir
foreach ($k in $cases.Keys) {
  Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File | ForEach-Object { [System.IO.File]::Delete($_.FullName) }
  [System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir ('src\' + $k)), $cases[$k], $enc)
  $present = @(Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File)
  if ($present.Count -ne 1 -or $present[0].Name -ne $k) {
    Write-Output ("{0,-24} ABORT: src holds {1} file(s)" -f $k, $present.Count); $fail++; continue
  }
  & cmd.exe /c "moon check > `"$outFile`" 2>&1"
  $out = [System.IO.File]::ReadAllText($outFile)
  # "moon check did no work" IS NOT "moon check found nothing". A clean compile
  # prints `Finished. moon: ran N task, now up to date`; a rejected one prints
  # `Error: failed when checking project` and NO Finished line. moon ran if it
  # printed EITHER.
  if ([string]::IsNullOrWhiteSpace($out)) {
    Write-Output ("{0,-24} ABORT: moon check produced no output at all" -f $k); $fail++; continue
  }
  if ($out -notmatch 'Finished\.\s*moon:\s*ran\s+\d+\s+task' -and
      $out -notmatch 'failed when checking project') {
    Write-Output ("{0,-24} ABORT: moon check did no work" -f $k); $fail++; continue
  }
  $errs = @([regex]::Matches($out, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $real = @($errs | Where-Object { $_ -notin @('4069') })
  $got = if ($real.Count -gt 0) { 'REJECTED' } else { 'ACCEPTED' }
  $want = $expected[$k]
  $ok = ($got -eq $want)
  Write-Output ('{0,-24} {1,-9} (want {2}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    ($out -split "`n" | Where-Object { $_ -match 'Parse error|Error: \[' } | Select-Object -First 3) |
      ForEach-Object { '      ' + $_.Trim() }
  }
}
Pop-Location
Write-Output ''
if ($fail -gt 0) { Write-Output "ABORT: $fail case(s) did not match the expected verdict."; exit 1 }
Write-Output 'GATE OK: `noraise` is a postfix handler block on a completed `try ... catch`.'
exit 0

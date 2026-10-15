# 0.4.32 settle: is `nobreak { .. }` real MoonBit, and what shape does it take?
#
# WHY. After 0442 removed all four `noraise` findings, proton
# `internal/bridge_admission_test/main.mbt:20` is the next item, and it is the
# same construct attached to a LOOP instead of a `try`:
#
#     while true {
#       while runtime.poll_event() is Some(event) {
#         if event.bridge_request() is Some(request) {
#           assert_eq(request.op, "app:probe")
#           return request
#         }
#       }
#       @async.sleep(5)
#     } nobreak {
#       fail("unreachable")
#     }
#
# So `nobreak` is a postfix block on a loop, and the grammar question is the same
# one 0441 settled for `noraise`: is it real, what arms/bodies does it take, and
# what does it bind. The corpus file is `moon check`-clean, so the construct is
# legal MoonBit -- but "the corpus compiles" is not the same measurement as "here
# is the grammar", and 0441 established that the difference is where the false
# positives come from.
#
# THE POSITIVE CONTROL IS FIRST AND IT IS NOT DECORATIVE. A settle run in which
# the control fails has measured the probe, not the grammar.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/settle_0443_nobreak.ps1
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP ('settle0443_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0443`"`nversion = `"0.1.0`"`n", $enc)

$PRE = @"
fn spin(n : Int) -> Int {
  let mut i = 0
  while i < n {
    i = i + 1
  }
  i
}

"@

$cases = [ordered]@{
  # POSITIVE CONTROL: a plain `while` loop and NO `nobreak` anywhere. If this is
  # rejected the prelude or the harness is wrong and every verdict below is void.
  'POS_no_nobreak.mbt' = $PRE + "fn keep(n : Int) -> Int {`n  spin(n)`n}`n"

  # A: THE CORPUS SHAPE, reduced. A `while` whose body falls through -- never
  # breaks -- and a `nobreak` block on it. If this is rejected, proton's file is
  # the problem and not ours; it is not.
  'a_after_while.mbt' = $PRE + "fn keep(n : Int) -> Int {`n  while spin(n) < 0 {`n    ignore(0)`n  } nobreak {`n    ignore(1)`n  }`n  0`n}`n"

  # B: A STATEMENT-LIST BODY, which is what A already showed and what the first
  # draft of this case got wrong. It wrote `nobreak { 1 }` expecting an
  # expression body and the compiler answered 4139 -- a value in statement
  # position cannot be dropped. So `nobreak`'s block is STATEMENTS, which is a
  # different thing from `noraise`'s `pattern => body` arm list, and the probe
  # now says so instead of the comment asserting it.
  'b_stmt_body.mbt' = $PRE + "fn keep(n : Int) -> Int {`n  while spin(n) < 0 {`n    ignore(0)`n  } nobreak {`n    ignore(1)`n  }`n  0`n}`n"

  # B2: THE NEGATIVE that B's failure actually is, kept as its own case so the
  # verdict is about `nobreak` and not about a dropped literal.
  'NEG_dropped_value.mbt' = $PRE + "fn keep(n : Int) -> Int {`n  while spin(n) < 0 {`n    ignore(0)`n  } nobreak { 1 }`n  0`n}`n"

  # C1: A CONTROL FOR THE `for` LOOP ITSELF. The first draft's `c_after_for`
  # failed with 3801 and the obvious reading -- "`nobreak` is not allowed on
  # `for`" -- was a guess about a source that was not a valid loop at all. Two
  # things were being measured by one case.
  #
  # 3801 was MY PRELUDE, not the grammar. MoonBit's `for` is
  # `for x in <iterable> { .. }` over something iterable -- read off proton's own
  # source, where all six hits are `for x in <list or field> {` -- and `0..n` is
  # not one of them in binder position. The control caught it; had it not been
  # split out, the verdict would have been read as a fact about `nobreak`.
  'POS_for_loop.mbt' = $PRE + "fn keep(n : Int) -> Int {`n  for i in [0, 1, 2] {`n    ignore(i)`n  }`n  0`n}`n"

  # C2: `nobreak` on that loop, now that the loop is known to compile.
  'c_after_for.mbt' = $PRE + "fn keep(n : Int) -> Int {`n  for i in [0, 1, 2] {`n    ignore(i)`n  } nobreak {`n    ignore(1)`n  }`n  0`n}`n"

  # D: NO LOOP AT ALL -- an expression in postfix position. The `noraise` probe
  # settled that its construct REQUIRES a `try`; if `nobreak` does not require a
  # loop then the parser's guard belongs somewhere else entirely.
  'nr_without_loop.mbt' = $PRE + "fn keep(n : Int) -> Int {`n  spin(n) nobreak {`n    ignore(1)`n  }`n}`n"

  # E: THE BREAK DIRECTION, which is what the name says and what no other case
  # can check -- a body that DOES break must still accept the block.
  'e_with_break.mbt' = $PRE + "fn keep(n : Int) -> Int {`n  while spin(n) < 0 {`n    break`n  } nobreak {`n    ignore(1)`n  }`n  0`n}`n"

  # AND THE EMPTY BLOCK, WHICH IS LEGAL HERE AND IS NOT LEGAL FOR `noraise`.
  # The first draft carried this as `NEG_empty` with an expectation of REJECTED,
  # copied across from the `noraise` probe -- and the compiler ACCEPTED it. That
  # is worth keeping as its own case, named for what it is, because the two
  # constructs now differ and a future reader who assumes they are the same will
  # write a parser guard that rejects valid code.
  'empty_block.mbt' = $PRE + "fn keep(n : Int) -> Int {`n  while spin(n) < 0 {`n    ignore(0)`n  } nobreak { }`n  0`n}`n"

  # NEGATIVE CONTROL 2: `nobreak` attached to a `let`, which is not a loop. The
  # construct must be a postfix ON A LOOP and not a statement-level keyword that
  # binds loosely -- that is what makes matching it by keyword dangerous.
  'NEG_not_a_loop.mbt' = $PRE + "fn keep(n : Int) -> Int {`n  let x = 1`n  nobreak {`n    ignore(x)`n  }`n  x`n}`n"
}

$expected = @{
  'POS_no_nobreak.mbt'    = 'ACCEPTED'
  'a_after_while.mbt'     = 'ACCEPTED'
  'b_stmt_body.mbt'       = 'ACCEPTED'
  'POS_for_loop.mbt'      = 'ACCEPTED'
  'c_after_for.mbt'       = 'ACCEPTED'
  'e_with_break.mbt'      = 'ACCEPTED'
  'empty_block.mbt'       = 'ACCEPTED'
  'nr_without_loop.mbt'   = 'REJECTED'
  'NEG_dropped_value.mbt' = 'REJECTED'
  'NEG_not_a_loop.mbt'    = 'REJECTED'
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
Write-Output 'GATE OK: `nobreak` is a postfix STATEMENT block on a LOOP, and an empty one is legal.'
exit 0

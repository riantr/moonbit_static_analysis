# 0.4.30 settle: what shapes does a postfix `catch { ... }` handler actually take?
#
# WHY. The postfix `catch` arm in `parse_postfix_from` used to call
# `skip_braces`, so every read inside a handler body was invisible. The measured
# cost is moui `backend/macos/macos_native_ime.mbt:437`:
#
#     437:3 - warning: parameter 'prefix' may not be used (UnusedParam)
#
# `prefix` is read at line 442, inside `catch { err => { ... } }`. Fixing it
# means carrying the handler into the AST, and the AST shape depends on the
# grammar. This probe settles the grammar, not the design.
#
# IT TOOK THREE PRELUDES, AND THE POSITIVE CONTROL IS WHAT CAUGHT THE FIRST TWO.
# Both earlier preludes failed all twelve cells at once, control included:
#   1. `priv fn`  -> "No 'private' visibility for function"          (3005)
#   2. `derive(Error)` -> "The type Error is not a trait"            (4100)
#      `derive(@error.Error)` -> still "Type MyErr is not an error type" (4127)
# MoonBit's error type is the `suberror` DECLARATION. A multi-variant `enum`
# cannot be made into one by any derivation this probe tried.
# => a settle run whose POSITIVE CONTROL fails has measured the probe, not the
#    grammar. Check that first, every time, before reading a single verdict.
#
# WHAT THIS PROBE CANNOT SETTLE, STATED RATHER THAN FAKED. A suberror has no
# VARIANTS, so a catch pattern that destructures one -- `Boom(n) =>`,
# `Wrap({ x }) =>`, `(a, b) =>`, `A | B =>` -- cannot be written against an
# error type at all. Those four cases were cut rather than kept with a prelude
# that does not compile. `Parser::parse_catch_pattern` still handles them, on
# the strength of `Parser::skip_pattern`'s long-standing comment and the corpus
# census, and that gap is a KNOWN LIMITATION of this probe rather than a claim
# about the grammar.
#
# The arm shapes that ARE settled here are also the ones the corpus census says
# matter: 45 of moui's 54 handler sites and 273 of proton's 323 are
# expression-bodied (`_verify/census_catch.ps1`). A settle that only covered the
# block form would have settled the rare one.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/settle_0439_catch.ps1
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP ('settle0439_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0439`"`nversion = `"0.1.0`"`n", $enc)

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
  # POSITIVE CONTROL: no `catch` anywhere. If this is rejected the whole run is
  # void -- it proves the prelude and the harness are sound. It has now caught
  # two wrong preludes that twelve case verdicts would have papered over.
  'POS_no_catch.mbt' = $PRE + "fn keep(p : String) -> Int raise MyErr {`n  fallible(p.length())`n}`n"

  # A: THE CORPUS SHAPE. Block body, newlines around everything. This is moui
  # macos_native_ime.mbt:439 verbatim in structure.
  'a_block_body.mbt' = $PRE + "fn keep(p : String) -> Int raise MyErr {`n  fallible(1) catch {`n    e => {`n      let _ = p`n      0`n    }`n  }`n}`n"

  # B: unit-expression body -- `_ => ()`, the form proton writes 18 times.
  # The base has to be Unit-typed (`silent`), because the catch expression has
  # the BASE's type -- see the NEG_arm_type case below, which is what settled
  # that. `ignore(..)` is not decoration: a catch expression in a NON-FINAL
  # statement position is a value that cannot be implicitly dropped (4139).
  'b_unit_body.mbt' = $PRE + "fn keep(p : String) -> Unit raise MyErr {`n  ignore(silent(p.length()) catch { _ => () })`n}`n"

  # C: plain expression body, and the shape the CENSUS says is the common one.
  'c_expr_body.mbt' = $PRE + "fn keep(p : String) -> Int raise MyErr {`n  fallible(1) catch { _ => p.length() }`n}`n"

  # D: NO ARROW AT ALL. If this is accepted the handler list is not uniformly
  # `pattern => body` and the AST needs a second production. The parser reads
  # the arrow if one is present and does not insist on one, so an accepted D
  # would not have broken anything -- it would mean the AST is under-specified.
  'D_no_arrow.mbt' = $PRE + "fn keep(p : String) -> Int raise MyErr {`n  fallible(1) catch { e }`n  fallible(p.length())`n}`n"

  # E: TWO ARMS separated only by a newline -- `e` binds the error, `_` does not.
  'e_two_arms.mbt' = $PRE + "fn keep(p : String) -> Int raise MyErr {`n  fallible(1) catch {`n    e => 0`n    _ => p.length()`n  }`n}`n"

  # I: `return` as the arm body -- the corpus writes `catch { _ => return "" }`.
  # `return` is a STATEMENT in this subset, so the arm body has to be a
  # statement list and not an expression. The catch is the function's TAIL here
  # rather than a discarded statement, which is what keeps 4139 out.
  'i_return_body.mbt' = $PRE + "fn keep(p : String) -> Int raise MyErr {`n  fallible(p.length()) catch { _ => return 0 }`n}`n"

  # NEGATIVE CONTROL 1: an empty handler list. If this is ACCEPTED then `catch`
  # is not being enforced at all and every ACCEPTED above means nothing.
  'NEG_empty.mbt' = $PRE + "fn keep(p : String) -> Int raise MyErr {`n  fallible(p.length()) catch { }`n  fallible(1)`n}`n"

  # NEGATIVE CONTROL 2: an arrow with no pattern.
  'NEG_no_pattern.mbt' = $PRE + "fn keep(p : String) -> Int raise MyErr {`n  fallible(p.length()) catch { => 0 }`n  fallible(1)`n}`n"

  # NEGATIVE CONTROL 3, AND IT IS A TYPE RULE RATHER THAN A SYNTAX ONE. The
  # catch expression has the BASE's type, not the arm's: `fallible` returns Int
  # and the arm yields `()`, so `ignore(..)` around the whole catch is handed an
  # Int where Unit is wanted. This is why `@ast.ECatch` is inferred as the BASE's
  # type in `types/infer.mbt` -- joining the arms' types in would be wrong, and
  # the compiler says so in one line of MoonBit.
  'NEG_arm_type.mbt' = $PRE + "fn keep(p : String) -> Unit raise MyErr {`n  ignore(fallible(p.length()) catch { _ => () })`n}`n"
}

$expected = @{
  'POS_no_catch.mbt'    = 'ACCEPTED'
  'a_block_body.mbt'    = 'ACCEPTED'
  'b_unit_body.mbt'     = 'ACCEPTED'
  'c_expr_body.mbt'     = 'ACCEPTED'
  'D_no_arrow.mbt'      = 'REJECTED'
  'e_two_arms.mbt'      = 'ACCEPTED'
  'i_return_body.mbt'   = 'ACCEPTED'
  'NEG_empty.mbt'       = 'REJECTED'
  'NEG_no_pattern.mbt'  = 'REJECTED'
  'NEG_arm_type.mbt'    = 'REJECTED'
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
    Write-Output ("{0,-20} ABORT: src holds {1} file(s)" -f $k, $present.Count); $fail++; continue
  }
  & cmd.exe /c "moon check > `"$outFile`" 2>&1"
  $out = [System.IO.File]::ReadAllText($outFile)
  # "moon check did no work" IS NOT "moon check found nothing". A program that
  # compiles CLEANLY prints `Finished. moon: ran 1 task, now up to date` and
  # nothing else -- the best possible verdict for a positive case, and the first
  # draft of this guard read it as a harness failure. Four cases aborted on it.
  #
  # The other direction is just as wrong: a program moon REJECTS prints
  # `Error: failed when checking project` and no `Finished` line at all, so
  # asking for `ran N task` alone reports every negative control as a harness
  # failure. moon ran if it printed EITHER.
  if ([string]::IsNullOrWhiteSpace($out)) {
    Write-Output ("{0,-20} ABORT: moon check produced no output at all" -f $k); $fail++; continue
  }
  if ($out -notmatch 'Finished\.\s*moon:\s*ran\s+\d+\s+task' -and
      $out -notmatch 'failed when checking project') {
    Write-Output ("{0,-20} ABORT: moon check did no work (neither a run nor a failure)" -f $k); $fail++; continue
  }
  $errs = @([regex]::Matches($out, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $real = @($errs | Where-Object { $_ -notin @('4069') })   # 4069 = main in a non-main package
  $got = if ($real.Count -gt 0) { 'REJECTED' } else { 'ACCEPTED' }
  $want = $expected[$k]
  $ok = ($got -eq $want)
  Write-Output ('{0,-20} {1,-9} (want {2}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    ($out -split "`n" | Where-Object { $_ -match 'Parse error|Error: \[' } | Select-Object -First 3) |
      ForEach-Object { '      ' + $_.Trim() }
  }
}
Pop-Location
Write-Output ''
if ($fail -gt 0) { Write-Output "ABORT: $fail case(s) did not match the expected verdict."; exit 1 }
Write-Output 'GATE OK: the handler list is `pattern => (block | stmt | expr)`; no-arrow and empty are rejected.'
Write-Output 'NOT settled here (a suberror has no variants to destructure): Boom(n), Wrap({x}), (a,b), A|B.'
exit 0

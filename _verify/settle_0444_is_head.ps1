# 0.4.34 settle: in `expr is PATTERN`, when does the head NAME bind a variable?
#
# WHY. `Parser::parse_is_pattern` consumes the head name unconditionally -- as a
# CONSTRUCTOR -- and only collects names from a parenthesised payload. So
#
#     if probe() is err && err != 0 { .. err .. }
#
# yields an EMPTY binding list: `err` is swallowed by the head, and every later
# use of it is an undefined name. Measured, async 0.22.4 `src/tls/schannel.mbt`
# lines 218, 224, 235, 284 and 446, all `if EXPR is err && err != 0 {` -- and
# those five report `unsupported operand types for '!=': 'fn err (signature not
# read)' and 'int'`, not "undefined", because something ELSE named `err` is in
# scope in that package and wins.
#
# So the parser's question is the whole increment: is the head a CONSTRUCTOR or
# a BINDING? That cannot be guessed, because the corpus contains BOTH shapes and
# treating one as the other is how the five findings became type errors instead of
# the undefined names a minimal reproduction produces (measured: an isolated
# `if probe() is err && err != 0 { err }` reports `undefined name 'err'`).
#
# THE POSITIVE CONTROL AND THE CANARY ARE BOTH HERE, and the canary matters more
# than usual: a probe whose every case is ACCEPTED has measured nothing. `canary`
# is a program with a genuinely unbound name, and it MUST be rejected -- if it is
# accepted, this probe cannot see a failure and every other verdict is void.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/settle_0444_is_head.ps1
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP ('settle0444_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0444`"`nversion = `"0.1.0`"`n", $enc)

$PRE = @"
fn probe() -> Int {
  0
}

fn opt() -> Option[Int] {
  Some(0)
}

"@

$cases = [ordered]@{
  # POSITIVE CONTROL: a constructor WITH a payload, the shape the parser already
  # handles. The base here is `opt()`, NOT `probe()`.
  #
  # THE FIRST DRAFT USED `probe()`, WHICH RETURNS `Int`, AND THE CONTROL WAS
  # REJECTED WITH 4014 -- a TYPE mismatch between Int and Option, not a verdict
  # about pattern heads. Three cases failed the same way. A positive control that
  # fails means the PROBE is wrong, and reading its verdict as a fact about the
  # grammar is the exact error this file exists to prevent: the first draft would
  # have concluded "an uppercase head is rejected" from three Int/Option type
  # errors.
  'POS_payload.mbt' = $PRE + "fn keep() -> Int {`n  if opt() is Some(_) {`n    1`n  } else {`n    0`n  }`n}`n"

  # THE CANARY: a name that is bound NOWHERE. It MUST be rejected, or this probe
  # cannot distinguish "accepted" from "not checked". It passed on the first run,
  # which is what makes the ACCEPTED verdicts below mean something.
  'canary.mbt' = $PRE + "fn keep() -> Int {`n  if probe() is err {`n    nope`n  } else {`n    0`n  }`n}`n"

  # A: A LOWERCASE head, used after the test. If the head binds, this compiles;
  # if the head is a constructor, `err` is unbound and `err + 1` is rejected.
  # This is the corpus shape and the question the increment turns on.
  'a_lower_used.mbt' = $PRE + "fn keep() -> Int {`n  if probe() is err && err != 0 {`n    err`n  } else {`n    0`n  }`n}`n"

  # B: A LOWERCASE head with NO use after it. Separates "does the name bind" from
  # "does binding a name break anything else" -- A could fail for a reason that
  # has nothing to do with the binding.
  'b_lower_unused.mbt' = $PRE + "fn keep() -> Int {`n  if probe() is err {`n    1`n  } else {`n    0`n  }`n}`n"

  # C: AN UPPERCASE head, no use, over an Option so the pattern is well typed. If
  # uppercase heads also bind, this is the same as B; if they are CONSTRUCTOR
  # TESTS, it is legal for a different reason.
  'c_upper_unused.mbt' = $PRE + "fn keep() -> Int {`n  if opt() is Some {`n    1`n  } else {`n    0`n  }`n}`n"

  # D: THE DISCRIMINATOR, and the one that separates "uppercase binds" from
  # "uppercase is a constructor test". `Some != 0` type-checks ONLY if `Some` is a
  # fresh binding of the Option's element type; if `Some` is the CONSTRUCTOR then
  # this compares a function with an integer and is rejected.
  'd_upper_compared.mbt' = $PRE + "fn keep() -> Int {`n  if opt() is Some && Some != 0 {`n    1`n  } else {`n    0`n  }`n}`n"

  # E: THE MIRROR of D for the lowercase case, so the two are measured with the
  # same instrument rather than inferred from each other.
  'e_lower_compared.mbt' = $PRE + "fn keep() -> Int {`n  if probe() is err && err != 0 {`n    1`n  } else {`n    0`n  }`n}`n"

  # CUT, AND STATED RATHER THAN FAKED. The first draft's `f_upper_as_value` asked
  # whether an uppercase head is referenceable as a bare value:
  #
  #     if opt() is Some { ignore(Some) } else { 0 }
  #
  # and the compiler rejects it, 4014 then 4203. That is a real answer -- a bare
  # constructor name is not a value here -- but it is a fact about referencing
  # constructors, NOT about whether a pattern head binds, which is what this
  # increment turns on. It was cut rather than kept with an expectation invented
  # to match whatever it returned.
  #
  # NOTHING IS LOST BY CUTTING IT. The uppercase side is already measured by `c`
  # (an uppercase head is a legal TEST) and, decisively, by `d` (`Some != 0` is
  # rejected, so `Some` is a function and not a binding). `POS_payload` covers
  # the uppercase-with-payload shape.

  # H: AN UNUSED PAYLOAD BINDING, `is Some(v)` with `v` never read. The head
  # case (`b_lower_unused`) already says an unused HEAD binding is legal, and this
  # asks the same question about the name inside a constructor's payload.
  #
  # IT MATTERS TO THE FIX, not just to the catalogue. `EIs` carries the head and
  # the payload names in ONE `Array[String]`, and the walker binds them all the
  # same way. If an unused payload binding is legal, the walker should use
  # `bind_pattern` for all of them, exactly as catch arms do; if it is an error,
  # only the head may be exempt and the AST would have to distinguish them. That
  # is a design decision and this case is what decides it.
  'h_payload_unused.mbt' = $PRE + "fn keep() -> Int {`n  if opt() is Some(v) {`n    1`n  } else {`n    0`n  }`n}`n"

  # G: THE WILDCARD. `_` must stay a non-binding: the parser already refuses it,
  # and a change that made heads bind must not make `_` bind too.
  'g_wildcard.mbt' = $PRE + "fn keep() -> Int {`n  if probe() is _ {`n    1`n  } else {`n    0`n  }`n}`n"
}

$expected = @{
  'POS_payload.mbt'       = 'ACCEPTED'
  'canary.mbt'            = 'REJECTED'
  'a_lower_used.mbt'      = 'ACCEPTED'
  'b_lower_unused.mbt'    = 'ACCEPTED'
  'c_upper_unused.mbt'    = 'ACCEPTED'
  'd_upper_compared.mbt'  = 'REJECTED'
  'e_lower_compared.mbt'  = 'ACCEPTED'
  'h_payload_unused.mbt'  = 'ACCEPTED'
  'g_wildcard.mbt'        = 'ACCEPTED'
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
    Write-Output ("{0,-22} ABORT: src holds {1} file(s)" -f $k, $present.Count); $fail++; continue
  }
  & cmd.exe /c "moon check > `"$outFile`" 2>&1"
  $out = [System.IO.File]::ReadAllText($outFile)
  if ([string]::IsNullOrWhiteSpace($out)) {
    Write-Output ("{0,-22} ABORT: moon check produced no output at all" -f $k); $fail++; continue
  }
  if ($out -notmatch 'Finished\.\s*moon:\s*ran\s+\d+\s+task' -and
      $out -notmatch 'failed when checking project') {
    Write-Output ("{0,-22} ABORT: moon check did no work" -f $k); $fail++; continue
  }
  $errs = @([regex]::Matches($out, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $real = @($errs | Where-Object { $_ -notin @('4069') })
  $got = if ($real.Count -gt 0) { 'REJECTED' } else { 'ACCEPTED' }
  $want = $expected[$k]
  $ok = ($got -eq $want)
  Write-Output ('{0,-22} {1,-9} (want {2}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    ($out -split "`n" | Where-Object { $_ -match 'Parse error|Error: \[' } | Select-Object -First 3) |
      ForEach-Object { '      ' + $_.Trim() }
  }
}
Pop-Location
Write-Output ''
if ($fail -gt 0) { Write-Output "ABORT: $fail case(s) did not match the expected verdict."; exit 1 }
Write-Output 'GATE OK: a lowercase `is` head BINDS; an uppercase one is a constructor test.'
exit 0

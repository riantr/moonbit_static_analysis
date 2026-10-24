$ErrorActionPreference = 'Continue'
# 0502 settle: MAY `as` START A NEW LINE?
#
# WHY. The parser's postfix loop breaks at a newline, and the cast arm is
# reached only from inside that loop. So `e` NEWLINE `as &Trait` left the `as`
# in the token stream, the statement reader took it as the start of the next
# expression, and the analyzer reported `no visible binding for 'as'` -- on
# code `moon check` accepts with zero errors. Measured: moonbitlang/async
# 0.22.4 `src/fs/watch.mbt:216,222,233`, three findings, all inside match arm
# bodies (which 0502 is the first release to read).
#
# THE COMPILER IS THE ORACLE, and the SYNTAX IS COPIED FROM THE CORPUS rather
# than invented: a trait method is declared with `Self`
# (moonbitlang/core `arg_spec.mbt:255` uses the `with fn` impl form). A first
# draft declared it with `self`, and the compiler rejected the PREAMBLE -- so
# every case was a verdict about the preamble instead of about the question.
#
# TWO GUARDS, because a probe whose every case is ACCEPTED has measured NOTHING:
#
#   * THE CANARY binds nothing and uses the name. It MUST be REJECTED, or the
#     probe cannot tell "accepted" from "not checked". The first draft of this
#     probe passed a FILE PATH to `moon check`, and every case -- the canary
#     included -- came back ACCEPTED, which is how that draft measured nothing.
#   * THE NEGATIVE CONTROL casts to a trait the type does NOT implement. It
#     MUST be REJECTED too: that is what proves the cast is really being
#     type-checked, so an ACCEPT is a fact about the grammar and not about a
#     checker that ignored the expression.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\settle_0502_as.ps1
$dir = Join-Path $env:TEMP ('settle0502as_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0502as`"`nversion = `"0.1.0`"`n", $enc)

$PRE = @"
priv trait Backend {
  fn close(Self) -> Unit
}

priv trait Other {
  fn close(Self) -> Unit
}

priv enum E {
  E(Int)
}

impl Backend for E with fn close(self) -> Unit {
  ()
}

"@

$cases = [ordered]@{
  # THE CANARY: a name bound NOWHERE. It MUST be rejected.
  'canary.mbt' = "fn keep() -> Int {`n  nope`n}`n"

  # THE NEGATIVE CONTROL: the cast is real, so casting to a trait the type does
  # NOT implement MUST be rejected. If this is ACCEPTED, the cast is not being
  # checked and every ACCEPT below means nothing.
  'neg_cast_to_wrong_trait.mbt' = $PRE + "fn f(e : E) -> &Other {`n  e as &Other`n}`n"

  # A: the cast on the SAME LINE as its operand.
  'a_as_same_line.mbt' = $PRE + "fn f(e : E) -> &Backend {`n  e as &Backend`n}`n"

  # B: the cast on the NEXT LINE -- the async corpus shape.
  'b_as_next_line.mbt' = $PRE + "fn f(e : E) -> &Backend {`n  e`n  as &Backend`n}`n"

  # C: the same, inside a BLOCK that is a match arm body.
  'c_as_next_line_in_arm.mbt' = $PRE + "fn f(e : E) -> &Backend {`n  match 0 {`n    0 => {`n      e`n      as &Backend`n    }`n    _ => e as &Backend`n  }`n}`n"

  # D: the cast on the next line, after a CALL -- the exact async shape.
  'd_as_next_line_after_call.mbt' = $PRE + "fn mk(e : E) -> E {`n  e`n}`n`nfn f(e : E) -> &Backend {`n  match 0 {`n    0 => {`n      mk(e)`n      as &Backend`n    }`n    _ => e as &Backend`n  }`n}`n"
}

$expected = [ordered]@{
  'canary.mbt'                   = 'REJECTED'
  'neg_cast_to_wrong_trait.mbt'  = 'REJECTED'
  'a_as_same_line.mbt'           = 'ACCEPTED'
  'b_as_next_line.mbt'           = 'ACCEPTED'
  'c_as_next_line_in_arm.mbt'    = 'ACCEPTED'
  'd_as_next_line_after_call.mbt' = 'ACCEPTED'
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
    Write-Output ("{0,-30} ABORT: src holds {1} file(s)" -f $k, $present.Count); $fail++; continue
  }
  & cmd.exe /c "moon check > `"$outFile`" 2>&1"
  $out = [System.IO.File]::ReadAllText($outFile)
  if ([string]::IsNullOrWhiteSpace($out)) {
    Write-Output ("{0,-30} ABORT: moon check produced no output at all" -f $k); $fail++; continue
  }
  if ($out -notmatch 'Finished\.\s*moon:\s*ran\s+\d+\s+task' -and
      $out -notmatch 'failed when checking project') {
    Write-Output ("{0,-30} ABORT: moon check did no work" -f $k); $fail++; continue
  }
  $errs = @([regex]::Matches($out, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $real = @($errs | Where-Object { $_ -notin @('4069') })
  $got = if ($real.Count -gt 0) { 'REJECTED' } else { 'ACCEPTED' }
  $want = $expected[$k]
  $ok = ($got -eq $want)
  Write-Output ('{0,-30} {1,-9} (want {2}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    ($out -split "`n" | Where-Object { $_ -match 'Parse error|Error: \[' } | Select-Object -First 3) |
      ForEach-Object { '      ' + $_.Trim() }
  }
}
Pop-Location
Write-Output ''
if ($fail -gt 0) { Write-Output "ABORT: $fail case(s) did not match the expected verdict."; exit 1 }
Write-Output 'GATE OK: `as` MAY start a new line -- the toolchain accepts it, so a parser that refuses it invents a finding.'
exit 0

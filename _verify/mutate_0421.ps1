# 0.4.21 mutation gate.
#
# Seven mutations over four fixes, and the set is deliberately not one-per-fix:
# a gate that only removes each guard in turn cannot tell "the guard is the
# protection" from "something else happens to protect the same line".
#
#   M1  `guard` no longer parsed          -> the identifier reading returns
#   M2  `guard`'s else block dropped      -> the OPPOSITE direction: the guard
#                                            stops being the only thing that
#                                            bounds the statement, so a guard
#                                            that swallowed its own block would
#                                            look identical to a fixed one
#   M3  named-argument lambda head off    -> the argument list is abandoned
#   M4  the `is` newline continuation off-> the nastiest failure mode: the file
#                                            still parses, with the wrong tree
#   M5  tuple pattern returns only the 1st-> back to one binding per pattern
#   M6  the `.` neighbour rule removed    -> a qualified path binds every
#                                            segment as a local (a REGRESSION
#                                            direction: dropping the old depth
#                                            restriction opens this hole)
#   M7  the nested-constructor rule removed-> `Some(Os(error))` binds `Os`
#
# Same rules as before: COMPILE-ERR is the absence of a `Total tests:` line,
# never a grep; every restore is byte-identical by SHA256.
#
# Usage: pwsh -File _verify/mutate_0421.ps1
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

  # Match and write back in ONE line-ending style, whichever the file already
  # uses. `moon fmt` rewrote the whole tree from LF to CRLF at 0.1.20261012,
  # and a literal multi-line pattern in this file — which is LF, because it is
  # not MoonBit source and the formatter never touches it — then matched
  # NOTHING and every mutation reported NO-OP. The gate did fail loudly on
  # that, which is why NO-OP counts as a failure here; but a gate that silently
  # stops matching is one edit away from being decorative, so the comparison is
  # normalised instead. `Replace` is ordinal and the patterns are unique.
  $eol = if ($text0.Contains("`r`n")) { "`r`n" } else { "`n" }
  $norm   = $text0.Replace("`r`n", "`n")
  $findN  = $Find.Replace("`r`n", "`n")
  $replN  = $Replace.Replace("`r`n", "`n")
  if ($norm.IndexOf($findN, [System.StringComparison]::Ordinal) -lt 0) {
    $script:results += [pscustomobject]@{ Mutation=$Name; Outcome='NO-OP'; Killed=0; Detail='pattern absent' }
    $script:failed += $Name; return
  }
  $mutated = $norm.Replace($findN, $replN)
  [System.IO.File]::WriteAllText($path, $mutated.Replace("`n", $eol), (New-Object System.Text.UTF8Encoding($false)))

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

# --- M1: `guard` is an ordinary identifier again -----------------------------
# `guard` is not in the lexer's keyword list, so with this arm gone it is read
# as a name and reported undefined — and the condition is never walked, so the
# pattern's binding never lands either.
Invoke-Mutation 'M1 guard not parsed' 'src\parser\parser.mbt' `
  'if self.at_name("guard") {
    return self.parse_guard()
  }' `
  'if self.at_name("guard") && self.at_name("zzz_never") {
    return self.parse_guard()
  }' 'KILLED'

# --- M2: the guard's else block dropped ------------------------------------
# THE OPPOSITE DIRECTION. The bound of a guard statement is its `else` block;
# drop it and the condition's names still resolve (M1-shaped tests stay green)
# while the else body is never analyzed. Only
# "0421: a guard's else body is still analyzed" can catch this.
Invoke-Mutation 'M2 guard else dropped' 'src\parser\parser.mbt' `
  'if self.at_name("else") {
    let _ = self.bump()
    let (eb, _) = self.parse_block()
    els = Some(eb)
  }' `
  'if self.at_name("else") && self.at_name("zzz_never") {
    let _ = self.bump()
    let (eb, _) = self.parse_block()
    els = Some(eb)
  }' 'KILLED'

# --- M3: a named argument's lambda is not a head ---------------------------
# `event=(node, ctx) => f(...)` and `children=_node => [child]` stop being
# recognised, the argument list is abandoned at the `=>`, and every statement
# after it is re-read. `n_parse == 0` alone would stay green here, which is why
# the control test also asserts an undefined name AFTER the lambda.
Invoke-Mutation 'M3 named-arg lambda head disabled' 'src\parser\parser.mbt' `
  'if self.at_lambda_head() {' `
  'if self.at_lambda_head() && self.at_name("zzz_never") {' 'KILLED'

# --- M4: `is` no longer continues across a newline -------------------------
# The line break ends the expression, `is` is read as an identifier, and the
# file STILL PARSES — into a tree where every name after that point is wrong.
# Nothing fails, so only the tests that assert on names after the continuation
# can see it.
Invoke-Mutation 'M4 is-newline continuation removed' 'src\parser\parser.mbt' `
  'while self.at(TNewline) {
    let _ = self.bump()
  }
  while self.at_name("is") {' `
  'while self.at(TNewline) && self.at_name("zzz_never") {
    let _ = self.bump()
  }
  while self.at_name("is") {' 'KILLED'

# --- M5: an is-pattern binds only its first name ---------------------------
# Back to `EIs` carrying one `String` in practice. The tuple branch consumed the
# whole group either way, so the group is still consumed — but every binding
# after the first is dropped and reported undefined at its use.
Invoke-Mutation 'M5 is-pattern binds only the first name' 'src\parser\parser.mbt' `
  'if !in_type && depth >= 2 && self.pattern_binding_at(j) {
            found.push(n)
          }' `
  'if !in_type && depth >= 2 && self.pattern_binding_at(j) {
            found.push(n)
            break
          }' 'KILLED'

# --- M6: the qualified-path rule removed -----------------------------------
# A REGRESSION direction, and the reason the `.` neighbour rule exists. Dropping
# the old `depth == 1` restriction opened this hole: every segment of
# `@core.Role::Checkbox` now passes "not followed by `(`", so without this rule
# each is bound as a local and reported unused. Eighteen such patterns are in
# the corpus.
Invoke-Mutation 'M6 qualified-path rule removed' 'src\parser\parser.mbt' `
  'if after < self.toks.length() &&
    (self.toks[after] == TLParen || self.toks[after] == TDot) {
    return false
  }
  if j > 0 && self.toks[j - 1] == TDot {
    return false
  }' `
  'if after < self.toks.length() && self.toks[after] == TLParen {
    return false
  }' 'KILLED'

# --- M7: the nested-constructor rule removed -------------------------------
# The opposite side of the same predicate: without "the next token is not `(`",
# `Some(Os(error))` binds `Os` — a name that is never used, so it is reported
# unused while `error`, which IS used, is reported undefined. Two findings
# instead of none.
Invoke-Mutation 'M7 nested-constructor rule removed' 'src\parser\parser.mbt' `
  'if after < self.toks.length() &&
    (self.toks[after] == TLParen || self.toks[after] == TDot) {
    return false
  }' `
  'if after < self.toks.length() && self.toks[after] == TDot {
    return false
  }' 'KILLED'

# --- M8: the or-pattern depth rule removed --------------------------------
# Found BY the differential, not by reasoning: `is (Gone | PageUnavailable)` in
# proton `internal/bridge_admission_test/main.mbt:93` bound both constructors as
# locals. The outer `(` of the tuple branch is a GROUPING paren, so its
# bindings live at depth >= 2, one level in inside `Some(`. Relaxing to >= 1
# brings the two phantom unused locals straight back.
Invoke-Mutation 'M8 or-pattern depth rule removed' 'src\parser\parser.mbt' `
  'if !in_type && depth >= 2 && self.pattern_binding_at(j) {' `
  'if !in_type && depth >= 1 && self.pattern_binding_at(j) {' 'KILLED'

Write-Output ''
Write-Output '=== 0.4.21 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
$survived = @($results | Where-Object { $_.Outcome -eq 'SURVIVED' }).Count
Write-Output ("{0} killed, {1} survived; every restore verified byte-identical" -f $killedCount, $survived)
if ($failed.Count -gt 0) { Write-Output ("FAILED: {0}" -f ($failed -join ', ')); exit 1 }
exit 0
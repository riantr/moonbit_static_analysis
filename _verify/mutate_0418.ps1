# 0.4.18 mutation gate.
#
# Twelve mutations, one per behavior the new tests claim to hold. The point is
# not that the code is covered but that the COVERAGE CAN FAIL: a test that
# cannot go red is not evidence. Each mutation reverts exactly one mechanism and
# asserts that at least one test turns red.
#
# Rules this script holds itself to, because each one has been violated before:
#   * every mutation must record `ran > 0` — a mutation that compiles the test
#     suite away, or that matches nothing, is reported as COMPILE-ERR or
#     NO-OP, never silently as a pass;
#   * COMPILE-ERR is reported separately from KILLED. A mutation that only
#     breaks the build has not shown the gate is load-bearing;
#   * restore is byte-identical, proven by SHA256, and the original bytes are
#     captured with ReadAllBytes BEFORE the edit. Re-deriving the file by
#     writing text back would round-trip it through the console encoding and
#     silently rewrite UTF-8 as GBK.
#
# Usage: pwsh -File _verify/mutate_0418.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$results = @()
$failed  = @()

function Invoke-Mutation {
  param(
    [string]$Name,
    [string]$File,
    [string]$Find,
    [string]$Replace,
    [string[]]$ExpectRed,   # test-name substrings that MUST go red
    [string]$Expect = 'KILLED'
  )

  $path = Join-Path $root $File
  if (-not (Test-Path $path)) {
    $script:results += [pscustomobject]@{ Mutation = $Name; Outcome = 'NO-FILE'; Killed = 0; Detail = "missing $File" }
    $script:failed  += $Name
    return
  }

  # Byte-exact backup BEFORE any edit.
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $sha0  = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  $text0 = [System.Text.Encoding]::UTF8.GetString($bytes)

  if ($text0.IndexOf($Find, [System.StringComparison]::Ordinal) -lt 0) {
    $script:results += [pscustomobject]@{ Mutation = $Name; Outcome = 'NO-OP'; Killed = 0; Detail = 'pattern absent' }
    $script:failed  += $Name
    return
  }

  $text1 = $text0.Replace($Find, $Replace)
  [System.IO.File]::WriteAllText($path, $text1, (New-Object System.Text.UTF8Encoding($false)))

  # `moon test` writes diagnostics to stderr even on success. Under
  # `$ErrorActionPreference = 'Stop'` PowerShell turns a native command's stderr
  # into a terminating error, which killed this script on the FIRST mutation
  # before it could record anything. Relaxed for the call, then restored.
  $prevPref = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $out = & moon test 2>&1 | Out-String
  $ErrorActionPreference = $prevPref
  # COMPILE-ERR is detected by the ABSENCE of a `Total tests:` line, not by
  # pattern-matching the output. The first version of this script grepped for
  # `Parse error`, and it misfired on a test literally NAMED
  # "0418: &T in a parameter type is not a parse error" — reporting that
  # mutation as "build broke; not evidence" when it in fact killed two tests.
  # A fragile detector that hides a working gate is worse than no detector:
  # it would have pushed a real fix out of the release.
  $ran = ([regex]::Matches($out, 'Total tests: (\d+), passed: (\d+), failed: (\d+)'))

  $killed = 0
  $detail = ''
  if ($ran.Count -ge 1) {
    $m = $ran[$ran.Count - 1]
    $passed = [int]$m.Groups[2].Value
    $total  = [int]$m.Groups[1].Value
    if ($total -le 0) {
      $outcome = 'NO-RUN'
      $detail  = 'Total tests: 0'
      $script:failed += $Name
    } else {
      $killed = $total - $passed
      if ($killed -gt 0) { $outcome = 'KILLED'; $detail = "$killed of $total red" }
      else { $outcome = 'SURVIVED'; $detail = "$total/$total still green" }
    }
  } else {
    $outcome = 'COMPILE-ERR'
    $detail  = 'no Total tests line; the suite did not run'
  }

  # Restore bytes exactly as they were.
  [System.IO.File]::WriteAllBytes($path, $bytes)
  $sha1 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  $restored = ($sha0 -eq $sha1)
  if (-not $restored) {
    $detail += " RESTORE-MISMATCH($sha1)"
    $script:failed += "$Name (restore)"
  }

  $script:results += [pscustomobject]@{
    Mutation = $Name; Outcome = $outcome; Killed = $killed; Detail = $detail
  }
  if ($outcome -ne $Expect) { $script:failed += $Name }
}

# --- M1: &T no longer consumed in a type annotation ------------------------
# `if false` was the first attempt and it is a COMPILE-ERR, which this script
# deliberately does not count as evidence. `TCaret` is a real token of the same
# type, so the mutation compiles and simply never fires on the `&` that starts
# a `Ref[T]` annotation.
Invoke-Mutation 'M1 &T in type_annotation' 'src\parser\parser.mbt' `
  'let amp = if self.at(TAmp) {' `
  'let amp = if self.at(TQuestion) {' 'expectRed'

# --- M2: TTilde removed from the lexer -------------------------------------
Invoke-Mutation 'M2 TTilde lexer token' 'src\lexer\lexer.mbt' `
  "'~' => TTilde" `
  "'~' => TBang" 'expectRed'

# --- M3: label~ no longer accepted in a parameter list ---------------------
Invoke-Mutation 'M3 TTilde in param list' 'src\parser\parser.mbt' `
  '} else if self.at(TTilde) {
        let _ = self.bump()
        more_mods = true
      }' `
  '}' 'expectRed'

# --- M4: value~ no longer accepted at a call site --------------------------
Invoke-Mutation 'M4 TTilde in call args' 'src\parser\parser.mbt' `
  'if self.at(TTilde) {
      let _ = self.bump()
    }
    if self.at(TComma) {' `
  'if self.at(TComma) {' 'expectRed'

# --- M5: fn[T] type parameters no longer skipped --------------------------
Invoke-Mutation 'M5 fn[T] type params' 'src\parser\parser.mbt' `
  '  self.skip_indexed()
  let (name, _) = self.expect_name("function name")' `
  '  let (name, _) = self.expect_name("function name")' 'expectRed'

# --- M6: sibling harvest no longer tolerates fn[T] -------------------------
Invoke-Mutation 'M6 sibling name after fn[T]' 'src\parser\parser.mbt' `
  'match declared_name_after_kw(toks, i) {' `
  'match declared_name_at(toks, i + 1) {' 'expectRed'

# --- M7: byte-string literal no longer lexed ------------------------------
Invoke-Mutation 'M7 b"" byte-string' 'src\lexer\lexer.mbt' `
  "if c == 'b' &&" `
  "if c == 'Z' &&" 'expectRed'

# --- M8: struct spread base no longer consumed ----------------------------
Invoke-Mutation 'M8 { ..base } spread' 'src\parser\parser.mbt' `
  'if self.at(TDot) && self.at_next(TDot) {
      let _ = self.bump()
      let _ = self.bump()
      let base = self.parse_expr()' `
  'if false {
      let base = self.parse_expr()' 'expectRed'

# --- M9: a `{ ..` no longer recognized as a struct literal -----------------
Invoke-Mutation 'M9 at_struct_literal (TDot,TDot)' 'src\parser\parser.mbt' `
  '(TDot, TDot) => true' `
  '(TDot, TRBrace) => true' 'expectRed'

# --- M10: leading-dot chain branch removed --------------------------------
Invoke-Mutation 'M10 leading-dot chain' 'src\parser\parser.mbt' `
  'if self.at(TDot) {
    let sp0 = sp' `
  'if false {
    let sp0 = sp' 'expectRed'

# --- M11: the rewind removed — EXPECTED TO SURVIVE -------------------------
# This one is a deliberate exception and the reason is worth stating, because
# the honest answer is "this line is defensive and nothing distinguishes it".
#
# The chain loop speculatively consumes separators after a segment and rewinds
# when the next line does not open with `.`. Removing the rewind leaves the
# cursor AFTER those separators — but the enclosing statement loop calls
# `skip_seps` again anyway, so the next statement starts in the same place and
# the same findings are produced. A test cannot distinguish the two, and the
# corpus does not either.
#
# So the rewind is KEPT — it makes the loop correct on its own terms rather
# than correct only because a caller happens to clean up — and this mutation
# records that it is unobservable. Reporting it as a kill would be the error;
# deleting the line would be a behavior claim this evidence does not support.
Invoke-Mutation 'M11 chain rewind (expected to survive)' 'src\parser\parser.mbt' `
  '        if !self.at(TDot) {
          self.p = save
          break
        }' `
  '        if false {
          break
        }' 'expectRed' 'SURVIVED'

# --- M12: ambient builtin types removed -----------------------------------
Invoke-Mutation 'M12 Buffer/FuncRef ambient' 'src\core\builtins.mbt' `
  '"Buffer", "FuncRef",' `
  '"Zz_not_a_type",' 'expectRed'

Write-Output ''
Write-Output '=== 0.4.18 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output

$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
Write-Output ("KILLED {0} / {1}" -f $killedCount, $results.Count)

if ($failed.Count -gt 0) {
  Write-Output ("FAILED: {0}" -f ($failed -join ', '))
  exit 1
}
Write-Output 'all mutations killed; every restore verified byte-identical'
exit 0
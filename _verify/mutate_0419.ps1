# 0.4.19 mutation gate.
#
# Five mutations over the two 0.4.19 fixes. Same rules as mutate_0418.ps1 and
# for the same reasons:
#   * COMPILE-ERR is detected by the ABSENCE of a `Total tests:` line, never by
#     grepping the output — the 0.4.18 script did that and matched its own test
#     name "0419: ... is not a parse error";
#   * every restore is byte-identical, proven by SHA256, from bytes captured
#     with ReadAllBytes BEFORE the edit;
#   * a mutation that cannot go red is reported as SURVIVED, not counted.
#
# Usage: pwsh -File _verify/mutate_0419.ps1
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
    [string]$Expect = 'KILLED'
  )

  $path = Join-Path $root $File
  if (-not (Test-Path $path)) {
    $script:results += [pscustomobject]@{ Mutation = $Name; Outcome = 'NO-FILE'; Killed = 0; Detail = "missing $File" }
    $script:failed  += $Name
    return
  }

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

  $prevPref = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $out = & moon test 2>&1 | Out-String
  $ErrorActionPreference = $prevPref

  $ran = ([regex]::Matches($out, 'Total tests: (\d+), passed: (\d+), failed: (\d+)'))
  $killed = 0
  $detail = ''
  if ($ran.Count -ge 1) {
    $m = $ran[$ran.Count - 1]
    $passed = [int]$m.Groups[2].Value
    $total  = [int]$m.Groups[1].Value
    if ($total -le 0) {
      $outcome = 'NO-RUN'; $detail = 'Total tests: 0'; $script:failed += $Name
    } else {
      $killed = $total - $passed
      if ($killed -gt 0) { $outcome = 'KILLED'; $detail = "$killed of $total red" }
      else { $outcome = 'SURVIVED'; $detail = "$total/$total still green" }
    }
  } else {
    $outcome = 'COMPILE-ERR'
    $detail  = 'no Total tests line; the suite did not run'
  }

  [System.IO.File]::WriteAllBytes($path, $bytes)
  $sha1 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  if ($sha0 -ne $sha1) {
    $detail += " RESTORE-MISMATCH"
    $script:failed += "$Name (restore)"
  }

  $script:results += [pscustomobject]@{ Mutation = $Name; Outcome = $outcome; Killed = $killed; Detail = $detail }
  if ($outcome -ne $Expect) { $script:failed += $Name }
}

# --- M1: the is-pattern keyword test removed -------------------------------
# `if x is Some(true)` binds the literal `true` again.
Invoke-Mutation 'M1 is-pattern keyword test' 'src\parser\parser.mbt' `
  '        !@lexer.is_moonbit_keyword(self.peek_name()) &&' `
  '' 'KILLED'

# --- M2: function types no longer recognized in an annotation -------------
Invoke-Mutation 'M2 fn-type annotation' 'src\parser\parser.mbt' `
  '  if self.at(TLParen) {
    return self.fn_type_annotation()
  }' `
  '' 'KILLED'

# --- M3: return-position function type reverted to the old 3-token guess --
# This is the version that actually shipped by mistake once: it matches only
# `() -> T` and misses `(Int) -> String`, because `Int` sits between the
# brackets. The fixture that caught it is "0419: a function-type return
# annotation parses".
Invoke-Mutation 'M3 return fn-type (3-token)' 'src\parser\parser.mbt' `
  '            is_fn = j + 1 < self.toks.length() && self.toks[j + 1] == TArrow' `
  '            is_fn = j + 1 < self.toks.length() && self.toks[j - 1] == TArrow' 'KILLED'

# --- M4: every paren return treated as a function type --------------------
# EXPECTED TO SURVIVE, and the reason is worth keeping: for every annotation
# this lens can read, the tuple arm and the function-type arm consume EXACTLY
# the same tokens. A tuple `(Int, String)` has no `->` after its close, so
# `fn_type_annotation` renders it and returns just as the tuple arm consumed it
# and returned "". Both reach `ann_to_ty` as an unknown. So `n_parse` cannot
# distinguish them and the mutation is genuinely non-discriminating.
#
# The tuple test is KEPT regardless — not as a kill for this mutation, but as a
# regression test for a future change that breaks tuple parsing for real.
Invoke-Mutation 'M4 return fn-type over-eager (expected to survive)' 'src\parser\parser.mbt' `
  '            is_fn = j + 1 < self.toks.length() && self.toks[j + 1] == TArrow' `
  '            is_fn = true' 'SURVIVED'

# NOTE — the `is_moonbit_keyword` export in `src/lexer/pkg.generated.mbti` has
# NO mutation here, because `moon test` is the wrong instrument for it: the
# suite compiles from SOURCE, and only the SELF-SCAN reads the tracked `.mbti`
# interface files. Deleting the export line leaves all 391 tests green. That
# gap is real and it already bit once in 0.4.18, so the release check runs the
# self-scan and requires `actionable=0` — with the export removed, the
# self-scan reports `undefined name 'is_moonbit_keyword'` in the parser's own
# source. Asserted there rather than here.

Write-Output ''
Write-Output '=== 0.4.19 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
Write-Output ("KILLED {0} / {1}" -f $killedCount, $results.Count)
if ($failed.Count -gt 0) {
  Write-Output ("FAILED: {0}" -f ($failed -join ', '))
  exit 1
}
$survived = @($results | Where-Object { $_.Outcome -eq 'SURVIVED' }).Count
Write-Output ("{0} killed, {1} survived (each recorded above with its reason); every restore verified byte-identical" -f $killedCount, $survived)
exit 0
# 0.4.23 mutation gate.
#
# Eight mutations over one clause: the `raise` effect annotation, read in two
# positions (after a function signature, and inside a function TYPE). As in 0.4.22
# the set is deliberately not one-per-guard: M7 and M8 are the SAME guard mutated
# in opposite directions, because a guard that admits too much and a guard that
# admits too little fail in completely different ways and only one of them is the
# bug you were actually worried about.
#
#   M1  the signature call site removed     -> every `-> T raise` file dies at
#                                             "expected '{'" again
#   M2  the type-position call site removed -> `() -> T raise` dies at
#                                             "expected ')'"; this is the one that
#                                             was silently missing at first
#   M3  `raise` never matched by name       -> the long form stops being read
#   M4  the `!` short form never taken      -> `-> String!` stops being read
#   M5  the `raise` keyword not consumed    -> `raise` is read as the effect TYPE
#   M6  the effect type never read          -> `raise E` leaves `E` at the cursor
#   M7  the type-head guard admits EVERYTHING-> a bare `raise` swallows the body
#                                             `{` or the closing `)` -- a SILENT
#                                             misparse, the dangerous direction
#   M8  the type-head guard admits NOTHING   -> every named effect stops being read
#   M9  the `guard!` bang never consumed    -> `guard! c` reads as NOT applied to
#                                             `c`: a confident FALSE POSITIVE
#                                             ("operand of '!' must be bool")
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as
# a failure so that a pattern that stops matching cannot pass silently.
#
# One clause was DELETED rather than tested. `parse_raise_effect` used to call
# `skip_indexed()` before reading the effect type; M5 removed it and the suite
# stayed 371/371 green, because `type_annotation` already calls `indexed_suffix()`
# on the name it reads. The call was unobservable, so it is gone rather than
# pinned -- and the reason is recorded at the call site so the next person does
# not "restore" it and credit it with a case it was never handling.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0423.ps1
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
  # uses. `moon fmt` rewrote the tree from LF to CRLF, and a literal multi-line
  # pattern would then match NOTHING and every mutation would report NO-OP.
  # `Replace` is ordinal and every pattern below is unique.
  $eol = if ($text0.Contains([string][char]13 + [char]10)) { [string][char]13 + [char]10 } else { [string][char]10 }
  $nl  = [string][char]10
  $norm   = $text0.Replace($eol, $nl)
  $findN  = $Find.Replace($eol, $nl)
  $replN  = $Replace.Replace($eol, $nl)
  if ($norm.IndexOf($findN, [System.StringComparison]::Ordinal) -lt 0) {
    $script:results += [pscustomobject]@{ Mutation=$Name; Outcome='NO-OP'; Killed=0; Detail='pattern absent' }
    $script:failed += $Name; return
  }
  $mutated = $norm.Replace($findN, $replN)
  [System.IO.File]::WriteAllText($path, $mutated.Replace($nl, $eol), (New-Object System.Text.UTF8Encoding($false)))

  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & C:\Users\31379\.moon\bin\moon.exe test --target js 2>&1 | Out-String
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

# --- M1: the signature-position call site removed ---------------------------
# The whole pre-0.4.23 behaviour for signatures. `moonbit_image bmp.mbt:26` and
# all 149 of moui's files return to reporting `expected '{'`.
Invoke-Mutation 'M1 signature call site removed' 'src\parser\parser.mbt' `
  '    retann = self.return_annotation()
  }
  self.parse_raise_effect()
  (full, params, retann)' `
  '    retann = self.return_annotation()
  }
  (full, params, retann)' 'KILLED'

# --- M2: the type-position call site removed ---------------------------------
# The one that was ACTUALLY missing when this release started. Reading the clause
# in signature position only means `fn f(g : () -> Int raise)` dies at
# `expected ')'` while `fn f() -> Int raise` is fine -- which is exactly the
# shape 29 files of moui and 33 of moonbit-community use.
Invoke-Mutation 'M2 type-position call site removed' 'src\parser\parser.mbt' `
  '  self.parse_raise_effect()
  if self.at(TQuestion) {' `
  '  if self.at(TQuestion) {' 'KILLED'

# --- M3: `raise` never matched by name ---------------------------------------
# `raise` is not in the lexer's keyword table, so it arrives as a TName. Matching
# it by anything other than its exact text stops the long form being read.
Invoke-Mutation 'M3 raise never matched by name' 'src\parser\parser.mbt' `
  'if !self.at_name("raise") {' `
  'if !self.at_name("zzz_never_a_keyword") {' 'KILLED'

# --- M4: the `!` short form never taken --------------------------------------
# `!` must be told apart from the boolean NOT operator BY POSITION. This mutation
# is the reminder that it is a position test and not a token scan: flipping the
# test off only affects the short form, and the NOT-operator control test stays
# green either way, which is what makes that control necessary.
Invoke-Mutation 'M4 the ! short form never taken' 'src\parser\parser.mbt' `
  'if self.at(TBang) {
    let _ = self.bump()
    return
  }' `
  'if self.at(TRBrace) {
    let _ = self.bump()
    return
  }' 'KILLED'

# --- M5: the `raise` keyword itself never consumed ---------------------------
# The keyword and its argument are consumed by two different lines, so each can
# go missing on its own. Here the keyword survives, the type-head guard still
# admits it (it is a TName), and `raise` is read as the effect TYPE -- leaving
# `IntError` at the cursor for the body.
Invoke-Mutation 'M5 the raise keyword never consumed' 'src\parser\parser.mbt' `
  '  let _ = self.bump()
  // `-> T raise` names NO error type.' `
  '  // `-> T raise` names NO error type.' 'KILLED'

# --- M6: the effect type never read ------------------------------------------
# Consuming the keyword without consuming its argument leaves the argument at the
# cursor, and the reader then blames the body for it.
Invoke-Mutation 'M6 the effect type never read' 'src\parser\parser.mbt' `
  '  let _ = self.type_annotation()
}' `
  '}' 'KILLED'

# --- M7: the type-head guard admits EVERYTHING -------------------------------
# The dangerous direction. A bare `raise` followed by `{` or `)` would be treated
# as naming an error type, and the body block or the closing paren would be read
# as part of the type. That is a SILENT misparse: no error, a wrong signature.
Invoke-Mutation 'M7 type-head guard admits everything' 'src\parser\parser.mbt' `
  '    TName(_) | TLParen | TAmp => true
    _ => false
  }' `
  '    _ => true
  }' 'KILLED'

# --- M8: the type-head guard admits NOTHING ----------------------------------
# The opposite direction, and the reason M7 is not the whole story: over-strict
# reads nothing at all and every named effect stops being consumed.
Invoke-Mutation 'M8 type-head guard admits nothing' 'src\parser\parser.mbt' `
  '    TName(_) | TLParen | TAmp => true
    _ => false
  }' `
  '    _ => false
  }' 'KILLED'

# --- M9: the `guard!` bang never consumed -----------------------------------
# A SECOND defect fixed in the same release, and the only mutation here whose
# failure mode is a FALSE POSITIVE rather than a parse error: `guard! cond` was
# read as NOT applied to `cond`, so `moonbitlang/async` 0.22.4
# `src/internal/fd_util/pipe.mbt:31` reported "operand of '!' must be bool,
# got '[int]'" about code that compiles. Reverting this must make that kind of
# finding reappear, not a parse error.
Invoke-Mutation 'M9 the guard! bang never consumed' 'src\parser\parser.mbt' `
  '  if self.at(TBang) {
    let _ = self.bump()
  }
  let cond = self.parse_expr()' `
  '  let cond = self.parse_expr()' 'KILLED'

Write-Output ''
Write-Output '=== 0.4.23 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
$survived = @($results | Where-Object { $_.Outcome -eq 'SURVIVED' }).Count
Write-Output ("{0} killed, {1} survived; every restore verified byte-identical" -f $killedCount, $survived)
if ($failed.Count -gt 0) { Write-Output ("FAILED: {0}" -f ($failed -join ', ')); exit 1 }
exit 0

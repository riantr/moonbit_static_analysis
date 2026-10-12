# 0.4.24 mutation gate.
#
# Seven mutations over one change: `raise` as an EXPRESSION. 0.4.23 handled the
# same clause in the two positions it appears on a FUNCTION (the signature
# annotation and a function type's return annotation); this release handles the
# statement that actually performs the raising.
#
# The set is deliberately spread across the four places the statement has to be
# right, because a raise can be "handled" in the parser and still be wrong in a
# lens -- and the failure modes are opposite. M3 and M4 each make the payload
# stop being analysed, which makes the analyzer QUIETER; M5 and M6 make it
# terminate when it should not (or with the wrong value), which makes it LOUDER
# and wrong. A gate that only tested the first kind would pass a change that had
# simply stopped looking inside error construction.
#
#   M1  the `raise` dispatch removed      -> back to `undefined name 'raise'`,
#                                             65 false positives across the six
#                                             corpora come straight back
#   M2  the payload never parsed          -> `SRaise(None)` always; the error
#                                             value is dropped at the cursor
#   M3  walk stops walking the payload    -> a real defect INSIDE a raise goes
#                                             silent (the quiet failure)
#   M4  the type lens stops type-checking the payload -> same, one lens down
#   M5  a raise does not terminate       -> the frame stays live and the
#                                             statements after a raise look
#                                             reachable (the loud failure)
#   M6  a raise pushes a value            -> the raise invents a return value
#                                             `raise` never produces
#   M7  the termination-set guard removed -> a bare `raise` at the end of a block
#                                             tries to read the NEXT statement
#                                             as its payload
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as
# a failure so that a pattern that stops matching cannot pass silently.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0424.ps1
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
  # uses, and normalise before matching. `moon fmt` rewrites the tree between
  # releases and a literal multi-line pattern would then match NOTHING -- every
  # mutation reporting NO-OP, which the gate treats as a failure precisely so
  # that a silently non-matching pattern cannot pass. `Replace` is ordinal and
  # every pattern below is unique.
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

# --- M1: the `raise` statement dispatch removed ------------------------------
# The whole pre-0.4.24 behaviour, and the reason this release exists: `raise`
# went back to being an ordinary identifier, and `moonbit-community/proton`
# 0.3.4 `facade_app_metadata.mbt:82` went back to reporting
# `undefined name 'raise'` at 82:5. Measured across the six corpora this one
# dispatch is worth 65 findings -- 56 of them proton's.
Invoke-Mutation 'M1 raise statement dispatch removed' 'src\parser\parser.mbt' `
  'if self.at_name("raise") {
    return self.parse_raise_stmt()
  }
' `
  '' 'KILLED'

# --- M2: the payload never parsed --------------------------------------------
# `SRaise(None)` unconditionally. The error value is left at the cursor and the
# next statement gets read as if it were the payload.
Invoke-Mutation 'M2 the raise payload never parsed' 'src\parser\parser.mbt' `
  '{ span: sp, kind: @ast.SRaise(Some(self.parse_expr())), }
}' `
  '{ span: sp, kind: @ast.SRaise(None), }
}' 'KILLED'

# --- M3: walk stops walking the payload -------------------------------------
# THE QUIET FAILURE. `raise` must not become the one place in the language where
# a real defect goes unnoticed, so `raise E(nosuchfunction())` still has to find
# `nosuchfunction`. A mutation that merely stops looking is the failure mode a
# coverage number cannot see, which is why this is its own gate rather than
# folded into M2.
Invoke-Mutation 'M3 walk stops walking the raise payload' 'src\walk\walk.mbt' `
  'SRaise(e) =>
      match e {
        Some(x) => self.walk_expr(x)
        None => ()
      }' `
  'SRaise(_) => ()' 'KILLED'

# --- M4: the type lens stops type-checking the payload ----------------------
# The same quiet failure one lens down. M3 and M4 are separate because a change
# could plausibly fix one and not the other, and only one of them would fail a
# test that looked at findings from a single lens.
Invoke-Mutation 'M4 type lens stops checking the payload' 'src\types\infer.mbt' `
  'SRaise(e) =>
      match e {
        Some(x) => {
          let _ = self.ty_of(x, TUnknown)
        }
        None => ()
      }' `
  'SRaise(_) => ()' 'KILLED'

# --- M5: a raise does not terminate the frame -------------------------------
# THE LOUD FAILURE, and the one with real corpus consequences. `SRaise` exists
# precisely because `SReturn` would be wrong here, and the observable difference
# is the terminator: with this arm gutted the statements after a `raise` look
# reachable and every dead-code report after a raise disappears.
Invoke-Mutation 'M5 a raise does not terminate the frame' 'src\interp\interp.mbt' `
  'SRaise(_) => {
      self.ret_vals.push(ABottom)
      self.flow = FReturn
    }' `
  'SRaise(_) => ()' 'KILLED'

# --- M6: a raise pushes a value ----------------------------------------------
# A raise produces NO value. Pushing anything else invents a return value that
# the source never had, and it lands in `ret_vals`, which is where the rendered
# signature's return type comes from.
Invoke-Mutation 'M6 a raise pushes a value' 'src\interp\interp.mbt' `
  'SRaise(_) => {
      self.ret_vals.push(ABottom)
      self.flow = FReturn
    }' `
  'SRaise(_) => {
      self.ret_vals.push(AAny)
      self.flow = FReturn
    }' 'KILLED'

# --- M7: the termination-set guard removed -----------------------------------
# A bare `raise` with nothing after it -- on its own line, or closing a block
# with no semicolon -- must produce `SRaise(None)`. Without the guard the reader
# goes on to parse whatever follows as the error value, which in the corpus is
# the next real statement.
Invoke-Mutation 'M7 the bare-raise termination guard removed' 'src\parser\parser.mbt' `
  'if self.at(TNewline) || self.at(TSemi) || self.at(TRBrace) || self.at(TEOF) {
    return { span: sp, kind: @ast.SRaise(None), }
  }
' `
  '' 'KILLED'

Write-Output ''
Write-Output '=== 0.4.24 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
$survived = @($results | Where-Object { $_.Outcome -eq 'SURVIVED' }).Count
Write-Output ("{0} killed, {1} survived; every restore verified byte-identical" -f $killedCount, $survived)
if ($failed.Count -gt 0) { Write-Output ("FAILED: {0}" -f ($failed -join ', ')); exit 1 }
exit 0
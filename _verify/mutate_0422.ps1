# 0.4.22 mutation gate.
#
# Eight mutations over the two changes, and the set is deliberately not
# one-per-fix: a gate that only removes each guard in turn cannot tell "this is
# the protection" from "something else happens to protect the same line".
#
#   M1  param_index never matches        -> named matching silently off, back to
#                                           positional; the corpus shape reports
#                                           three argument mismatches again
#   M2  `name = value` label not recorded-> the ordinary named-argument path stops
#                                           naming a parameter
#   M3  the `x~` label not recorded      -> the shorthand stops naming a parameter
#   M4  a positional argument pushes no label -> the two parallel arrays fall out
#                                           of step and every later argument
#                                           mis-indexes
#   M5  `Int32` dropped from ann_to_ty   -> the annotation reads Unknown, which is
#                                           always safe and always wrong
#   M6  the arity threshold loosened     -> the positional arity check goes quiet
#   M7  the `all_positional` gate removed-> EXPECTED TO SURVIVE. No unit test can
#                                           see it; see the note at M7.
#   M8  method-call labels dropped       -> EXPECTED TO SURVIVE. infer discards
#                                           EMethodCall labels entirely.
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as
# a failure so that a pattern that stops matching cannot pass silently.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0422.ps1
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
  # uses. `moon fmt` rewrote the tree from LF to CRLF at 0.1.20261012, and a
  # literal multi-line pattern in a script -- which is not MoonBit source and
  # which the formatter never touches -- then matched NOTHING and every mutation
  # reported NO-OP. The gate failed loudly on that, which is why NO-OP counts as
  # a failure here, but a gate that silently stops matching is one edit away from
  # being decorative. `Replace` is ordinal and every pattern below is unique.
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

# --- M1: param_index never finds its label ----------------------------------
# The whole change in one edit: with no label ever resolving, every argument
# falls back to its index and `moui core/gesture.mbt:754`'s shape reports three
# argument mismatches -- `group` on `shortcut`, `description` on `enabled`, and
# `shortcut` on `group`. This is the pre-0.4.22 behaviour, exactly.
Invoke-Mutation 'M1 param_index never matches' 'src\types\infer.mbt' `
  'for i, n in pnames {
    if n == label {
      return Some(i)
    }
  }
  None' `
  'for i, n in pnames {
    if n == "zzz_never_a_label" {
      return Some(i)
    }
  }
  None' 'KILLED'

# --- M2: the `name = value` label is not recorded ---------------------------
# The ordinary named-argument path, as opposed to the shorthand. Distinct from
# M1 because it breaks the WRITER, not the reader: `param_index` is still
# correct, it is simply handed `""` for every argument.
Invoke-Mutation 'M2 name=value label not recorded' 'src\parser\parser.mbt' `
  '        } else {
          args.push(self.parse_expr())
          labels.push(arg_label)
        }' `
  '        } else {
          args.push(self.parse_expr())
          labels.push("")
        }' 'KILLED'

# --- M3: the `x~` shorthand label is not recorded ---------------------------
# `f(x~)` still parses and still passes the argument, so nothing about the call
# looks broken; it simply stops naming a parameter. The reordered-shorthand test
# is the only thing that can see it, and only because that fixture puts the
# shorthand at an index that does not belong to it.
Invoke-Mutation 'M3 tilde shorthand label not recorded' 'src\parser\parser.mbt' `
  'if labels[labels.length() - 1] == "" {
        labels[labels.length() - 1] = self.name_at(arg_start)
      }' `
  'if labels[labels.length() - 1] == "zzz_never_a_label" {
        labels[labels.length() - 1] = self.name_at(arg_start)
      }' 'KILLED'

# --- M4: a positional argument pushes no label ------------------------------
# The parallel-array invariant. `args` and `labels` must grow together at every
# push; a shorter `labels` does not fail loudly, it makes `labels.get(i)` return
# None for every argument after the gap, which reads as "positional". So the
# fixture that only ever names arguments still catches it -- the second and
# later arguments silently lose their labels.
Invoke-Mutation 'M4 positional argument pushes no label' 'src\parser\parser.mbt' `
  '    } else {
      args.push(self.parse_expr())
      labels.push("")
    }
    // `f(x~)`' `
  '    } else {
      args.push(self.parse_expr())
    }
    // `f(x~)`' 'KILLED'

# --- M5: Int32 dropped from the annotation reader ---------------------------
# The SAFE wrong answer. Unknown is assignable everywhere the lens is concerned,
# so nothing reports, nothing crashes, and the reader looks like it is simply
# conservative. Only the unit test that compares `ann_to_ty("Int32")` with
# `TInt` directly can tell it apart from that.
Invoke-Mutation 'M5 Int32 dropped from ann_to_ty' 'src\types\types.mbt' `
  '"Int" | "Int32" | "int" => TInt' `
  '"Int" | "int" => TInt' 'KILLED'

# --- M6: the arity threshold loosened ---------------------------------------
# One extra argument of slack. Settled against `moon check`, which rejects a
# call that passes more arguments than the function declares (error 4080), so
# the check should be reporting the excess, not tolerating it.
Invoke-Mutation 'M6 arity threshold loosened' 'src\types\infer.mbt' `
  'if all_positional && args.length() > params.length() {' `
  'if all_positional && args.length() > params.length() + 1 {' 'KILLED'

# --- M7: the `all_positional` gate removed ----------------------------------
# EXPECTED TO SURVIVE, and this is a measured result rather than a missing test.
#
# The gate exempts label-addressed calls from the arity check. Removing it
# cannot turn any unit test red, because no test -- and no VALID MoonBit
# program -- passes MORE named arguments than the function declares. Settled
# against `moon check` on 0.1.20261012: a duplicate label is error 4084 and a
# label naming no parameter is error 4085, so every shape the gate covers is a
# compile error the toolchain already reports.
#
# What the gate actually costs was measured on the six corpora rather than
# assumed: across 12,428 files it changes exactly ONE finding, an arity report
# in `moui backend/web/web_host.mbt` at a call past that file's
# reliable-region boundary, so it lands in the `unreliable` bucket and is never
# shown as a result. That one could not be confirmed as a true positive, and an
# argument-COUNT check is exactly where a misread cross-file signature
# manufactures a false positive.
#
# So: recorded honestly as SURVIVED. Writing a test that pins a behaviour no
# valid program exhibits would make this gate green and the test suite weaker.
Invoke-Mutation 'M7 all_positional arity gate removed' 'src\types\infer.mbt' `
  'let all_positional = labels.is_empty() ||
            labels.every(fn(l) { l == "" })' `
  'let all_positional = true' 'SURVIVED'

# --- M8: method-call labels dropped -----------------------------------------
# EXPECTED TO SURVIVE for a different reason, and this one is a real gap rather
# than a deliberate leniency. `EMethodCall` carries labels now, but infer
# discards them (`EMethodCall(base, _, args, _)`) because method arguments are
# not type-checked at all in this model -- there is no receiver signature to
# check them against. So the labels are parsed, carried, and ignored, and no
# mutation of them is observable. Recorded rather than papered over: the way to
# kill it is a method-receiver signature, which is a larger change than this
# release.
Invoke-Mutation 'M8 method-call labels dropped' 'src\parser\parser.mbt' `
  'e = { span: csp, kind: @ast.EMethodCall(base, m, args, labels), }' `
  'e = { span: csp, kind: @ast.EMethodCall(base, m, args, ["", "", "", "", "", ""]), }' 'SURVIVED'

Write-Output ''
Write-Output '=== 0.4.22 mutation results ==='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
$survived = @($results | Where-Object { $_.Outcome -eq 'SURVIVED' }).Count
Write-Output ("{0} killed, {1} survived; every restore verified byte-identical" -f $killedCount, $survived)
if ($failed.Count -gt 0) { Write-Output ("FAILED: {0}" -f ($failed -join ', ')); exit 1 }
exit 0
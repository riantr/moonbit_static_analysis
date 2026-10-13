# One-shot converter: rewrite the Gen B mutation gates onto `_verify/mutate_lib.ps1`.
#
# Gen B files are `_verify/mutate_04<NN>.ps1` for NN in 25..28: a header of prose
# rationale, a `$muts = @(...)` table, then a runner tail. The header carries the
# reasoning for every individual mutation and is the most valuable part of each
# file, so it is kept VERBATIM; only the tail is replaced.
#
# THE ASSERTS, because both of these have already cost a false result once.
#
#   1. The original `--target` is READ OUT OF THE TAIL BEING REPLACED and reused.
#      mutate_0412 was converted onto `js` by hand and two mutations became fake
#      survivors, because `src/sa` degrades on js and its tests do not run. A flag
#      that deletes the guards and then reports their absence as a pass is worse
#      than no gate, and nothing about the rewritten file would show it.
#
#   2. The boundary is asserted, not guessed. The head's last NON-BLANK line must be
#      the mutation array's closing paren, and the tail must contain a runner
#      marker. If either fails the file is skipped and reported, never half-written.
#      The first run asserted on the immediately preceding line, found a blank line,
#      and skipped all four -- correct behaviour, wrong rule.
#
#   3. The converted file must still PARSE as PowerShell before it is accepted. The
#      first successful run emitted `$$PARSER` (a backtick-escaped `$` followed by a
#      second one) and a gate named `0.0428` instead of `0.4.28`, and four files were
#      written before anyone noticed. Re-run this converter freely; it only ever
#      writes a file that parses.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\convert_genb.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$enc = New-Object System.Text.UTF8Encoding($false)

$NOTE = @'

# -----------------------------------------------------------------------------
# CONVERTED to ``_verify/mutate_lib.ps1``. Everything above this line -- the prose
# rationale and the mutation table -- is VERBATIM from the original file; only the
# runner that followed it was replaced. What the harness adds over that runner:
#
#   - a green BASELINE is asserted, not printed. This gate used to print its
#     baseline lines and then score mutations regardless of what they said, so a
#     suite that was already red produced a full table of verdicts and exit 0.
#   - a kill is judged by the ``Total tests:`` line, so a mutant that fails to BUILD
#     is COMPILE-ERR instead of being indistinguishable from a caught one.
#   - restores are proven by SHA256 rather than moved back from a .bakmut file.
#   - a NO-OP is a failure. An anchor that stopped matching is reported and the gate
#     stops; it is never counted as neither-a-kill-nor-a-failure.
#   - ``Expect`` may declare a non-KILLED outcome (``SURVIVED`` / ``COMPILE-ERR``),
#     and a ``Prove`` string is printed with it. A declared verdict still has to be
#     argued rather than asserted.
#   - ``Retired = '<reason>'`` excludes a mutation whose target code no longer
#     exists, printing the reason. It is never re-anchored to something that merely
#     happens to match.
#
# The ``--target`` below is the one the original used. It is not cosmetic:
# ``src/sa`` needs the async runtime, so on the js backend that package degrades and
# ITS TESTS DO NOT RUN -- running a gate on the wrong target silently deletes the
# guards and then reports their absence as a pass.
'@

$report = @()
foreach ($n in @('0425', '0426', '0427', '0428')) {
  $path = Join-Path $root ("_verify\mutate_$n.ps1")
  if (-not (Test-Path -LiteralPath $path)) { $report += "SKIP $n : no such file"; continue }
  $lines = [System.IO.File]::ReadAllLines($path)

  $tailStart = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^# -{20,}' -or $lines[$i] -match '^\$nl = \[string\]\[char\]10') {
      $tailStart = $i; break
    }
  }
  if ($tailStart -lt 0) { $report += "SKIP $n : no runner boundary found"; continue }

  $lastNonBlank = $tailStart - 1
  while ($lastNonBlank -ge 0 -and [string]::IsNullOrWhiteSpace($lines[$lastNonBlank])) { $lastNonBlank-- }
  if ($lastNonBlank -lt 0 -or $lines[$lastNonBlank].Trim() -ne ')') {
    $report += "SKIP $n : head's last non-blank line is not ')' (got '" + $lines[$lastNonBlank] + "')"
    continue
  }
  $head = ($lines[0..$lastNonBlank]) -join "`n"
  $tail = ($lines[$tailStart..($lines.Count - 1)]) -join "`n"

  $tm = [regex]::Match($tail, '--target\s+(\w+)')
  if (-not $tm.Success) { $report += "SKIP $n : could not read the original --target from the tail"; continue }
  $target = $tm.Groups[1].Value

  $vm = [regex]::Match($head, '(?m)^\s*\$(\w+)\s*=\s*@\(\s*$')
  if (-not $vm.Success) { $report += "SKIP $n : no mutation array found in the head"; continue }
  $var = $vm.Groups[1].Value

  # `mutate_0425.ps1` is release 0.4.25 -- four characters, not a decimal.
  $ver = '0.4.' + $n.Substring(2)

  # The head ALREADY declares the file-path variables the mutation table
  # references ($PARSER = 'src\parser\parser.mbt' and friends), so nothing has to
  # be regenerated or re-emitted -- the only job is to cut the runner off and append
  # the harness call. An earlier version re-extracted and re-emitted those
  # declarations; that was both unnecessary and the source of a `$$PARSER` bug, and
  # it made the converter skip all four files for a reason that had nothing to do with
  # the files themselves.
  $tail2 = @()
  $tail2 += $NOTE
  $tail2 += ''
  $tail2 += "`$ErrorActionPreference = 'Stop'"
  $tail2 += ". (Join-Path `$PSScriptRoot 'mutate_lib.ps1')"
  $tail2 += ''
  $tail2 += ("Invoke-MutationGate -Name '" + $ver + "' -Target '" + $target + "' -Mutations `$" + $var)
  $tail2 += ("Write-MutationGateVerdict -Name '" + $ver + " mutation gate'")
  $tail2 += 'if ($script:MutationGateFailures.Count -gt 0) { exit 1 }'
  $tail2 += 'exit 0'

  $candidate = $head + "`n" + ($tail2 -join "`n") + "`n"

  # ---- only write what parses ------------------------------------------------
  $tmp = Join-Path $env:TEMP ('genb_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
  [System.IO.File]::WriteAllText($tmp, $candidate, $enc)
  $perr = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$null, [ref]$perr)
  $bad = @($perr | Where-Object { $_ -ne $null })
  if ($bad.Count -gt 0) {
    $report += ("SKIP $n : generated file does not parse -- " + $bad[0].Message)
    continue
  }
  [System.IO.File]::WriteAllText($path, $candidate, $enc)
  $report += ("CONVERTED mutate_$n : version=" + $ver + " target=" + $target + " array=$" + $var + " head=" + $lastNonBlank + " lines")
}
$report | ForEach-Object { Write-Output $_ }
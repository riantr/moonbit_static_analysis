# Splice a Gen D gate (0418-0422) onto the shared harness.
#
# Gen D gates are the last generation carrying their own runner: they have the
# SHA256 restore and the `Total tests:` COMPILE-ERR judgement, but no baseline,
# no pre-flight, and no line-ending normalisation. Converting them means
# transposing a run of `Invoke-Mutation` calls into a table.
#
# WHY THIS SCRIPT PARSES INSTEAD OF ME RE-TYPING. The mutations carry the
# reasoning -- multi-line anchor patterns with exact leading whitespace, where a
# single lost space turns the pattern into a silent NO-OP. So the arguments are
# lifted out of the ORIGINAL FILE with the PowerShell AST parser, never
# transcribed by hand. A hand-transcription bug here is invisible by
# construction: it produces a pattern that simply does not match, and the gate
# reports NO-OP on a mutation whose real anchor is fine.
#
# The prose header is spliced mechanically for the same reason. The comment
# block above each call travels with its mutation.
#
# Target: every Gen D gate ran bare `moon test`, which resolves through
# `preferred_target = "wasm"` in `moon.mod` -- 514 tests, not the 442 the js
# target runs. That is pinned explicitly below, because the whole scope of the
# gate currently depends on a field in the module manifest rather than on
# anything in the script.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\convert_gend.ps1 -Gate 0418
param([Parameter(Mandatory = $true)][string]$Gate)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root ("_verify\mutate_" + $Gate + ".ps1")
if (-not (Test-Path $src)) { Write-Output ("ABORT: no such gate: " + $src); exit 1 }
$dst = Join-Path $root ("_verify\mutate_" + $Gate + "_converted.ps1")
$enc = New-Object System.Text.UTF8Encoding($false)

$lines = [System.IO.File]::ReadAllLines($src)
$fnIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^function Invoke-Mutation') { $fnIdx = $i; break }
}
if ($fnIdx -lt 0) { Write-Output 'ABORT: no Invoke-Mutation function found.'; exit 1 }

# ---- header: the prose before the runner, minus scaffolding the harness owns --
$scaffolding = '^\$ErrorActionPreference\s*=', '^\$root\s*=', '^Set-Location\s+\$root',
               '^\$results\s*=\s*@\(\)', '^\$failed\s*=',
               '^\$moon\s*=', '^\$nl\s*=', '^\$enc\s*=', '^\$live\s*='
$head = @()
for ($i = 0; $i -lt $fnIdx; $i++) {
  $skip = $false
  foreach ($s in $scaffolding) { if ($lines[$i] -match $s) { $skip = $true } }
  if (-not $skip) { $head += $lines[$i] }
}
while ($head.Count -gt 0 -and [string]::IsNullOrWhiteSpace($head[$head.Count - 1])) { $head = $head[0..($head.Count - 2)] }

# ---- lift the calls out of the AST, exactly as written -----------------------
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$tokens, [ref]$errs)
if ($errs.Count -gt 0) { Write-Output ('ABORT: source does not parse: ' + $errs[0].Message); exit 1 }

$calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and
                                       $n.GetCommandName() -eq 'Invoke-Mutation' }, $true))
if ($calls.Count -eq 0) { Write-Output 'ABORT: no Invoke-Mutation calls found.'; exit 1 }

# ---- does THIS gate's runner have the vestigial $ExpectRed parameter? --------
# 0.4.18's runner is `param(Name, File, Find, Replace, [string[]]$ExpectRed,
# [string]$Expect)`; the other four are `param(Name, File, Find, Replace,
# [string]$Expect)`. So the FIFTH argument is a vestigial placeholder in 0418 and
# the declared EXPECT in the rest.
#
# Assuming one shape for all five silently loses data: it turns 0419's M4, which
# declares `SURVIVED`, into a mutation that wants KILLED, and the gate then either
# fails or -- worse -- reports a non-discriminating mutation as load-bearing. The
# distinction is read out of each runner rather than assumed.
$hasExpectRed = ($lines -join "`n") -match '\[\s*string\[\]\s*\]\s*\$ExpectRed'
if ($hasExpectRed) {
  Write-Output '  runner has $ExpectRed: arg 5 is the vestigial placeholder, arg 6 is Expect.'
} else {
  Write-Output '  runner has no $ExpectRed: arg 5 is the declared Expect.'
}

# Every argument in these gates is a string literal, so the AST gives the exact
# unquoted value -- no re-quoting, no re-escaping, no transcription.
$rows = @()
foreach ($c in $calls) {
  $el = $c.CommandElements
  $args = @()
  for ($i = 1; $i -lt $el.Count; $i++) {
    if ($el[$i] -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
      Write-Output ('ABORT: argument ' + $i + ' of a call is not a string literal (line ' +
                    $el[$i].Extent.StartLineNumber + '). Refusing to guess.'); exit 1
    }
    $args += $el[$i].Value
  }
  # 5 args = Name, File, Find, Replace, and one more. 6 adds a sixth.
  # Anything else means this gate is not the shape this converter knows.
  if ($args.Count -lt 5 -or $args.Count -gt 6) {
    Write-Output ('ABORT: a call takes ' + $args.Count + ' args, expected 5 or 6.'); exit 1
  }
  if (-not $hasExpectRed -and $args.Count -eq 6) {
    Write-Output ('ABORT: line ' + $c.Extent.StartLineNumber + ' passes 6 args to a 5-parameter runner.')
    exit 1
  }
  # With $ExpectRed present, 5 args means the placeholder was passed and $Expect
  # took its 'KILLED' default; 6 means both were passed.
  $row = [ordered]@{
    Name = $args[0]; File = $args[1]; Find = $args[2]; Repl = $args[3]
    Placeholder = if ($hasExpectRed) { $args[4] } else { '' }
    Expect = if ($hasExpectRed) { if ($args.Count -eq 6) { $args[5] } else { 'KILLED' } }
             elseif ($args.Count -eq 5) { $args[4] } else { 'KILLED' }
    Line  = $c.Extent.StartLineNumber
  }
  $rows += [pscustomobject]$row
}

# ---- the comment block above each call travels with it ------------------------
for ($r = 0; $r -lt $rows.Count; $r++) {
  $comments = @()
  $j = $rows[$r].Line - 2   # 0-based index of the line above the call
  while ($j -ge 0 -and $lines[$j] -match '^\s*#') { $comments = @($lines[$j].TrimEnd()) + $comments; $j-- }
  $rows[$r] | Add-Member -NotePropertyName Comment -NotePropertyValue ($comments -join "`n") -Force
}

# ---- emit --------------------------------------------------------------------
# A here-string terminator `'@` must start a line; if a pattern contained one the
# emitted file would silently end early, so this is checked rather than trusted.
#
# The terminator is emitted FLUSH LEFT even though the body is indented. That is a
# PowerShell rule, not a style choice -- leading whitespace before `'@` is a parse
# error ("White space is not allowed before the string terminator"). The body lines
# may be indented freely, because here-strings are literal and the indentation
# becomes part of the pattern, which is exactly why the AST-lifted value is emitted
# unchanged.
function ConvertTo-HereString {
  param([string]$Text)
  # The EMPTY string is ZERO lines, not one empty line. `-split` turns '' into @('') --
  # a single empty element -- so a naive here-string emits the indent and the
  # mutation REPLACES its anchor with whitespace instead of deleting it. Several
  # of these gates delete a whole arm (`Repl = ''`), and the result still parses,
  # so nothing downstream would have complained.
  if ($Text.Length -eq 0) { return "''" }
  $parts = @($Text -split "`r?`n")
  if ($parts | Where-Object { $_ -match "^\s*'@" }) { return $null }
  # EMITTED VERBATIM, WITH NO ADDED INDENTATION. A here-string's value is every
  # character between the delimiters, leading spaces included, so indenting the body
  # to line it up under `Find =` prepends that indent to the PATTERN. Every pattern
  # in these gates is whitespace-significant -- they are literal slices of .mbt
  # source -- so a cosmetic indent turns all of them into silent NO-OPs. This is
  # the third bug the round-trip self-check caught; the first two were the
  # $ExpectRed argument position and the empty-Repl case, and neither of those would
  # have failed a kill-count comparison either.
  return "@'`n" + ($parts -join "`n") + "`n'@"
}

$NOTE = @'

# -----------------------------------------------------------------------------
# CONVERTED to ``_verify/mutate_lib.ps1``. This gate carried its own runner with
# the SHA256 restore and the `Total tests:` COMPILE-ERR judgement; what it lacked
# was a green BASELINE, PRE-FLIGHT, and line-ending normalisation. The prose above
# is VERBATIM and each mutation keeps the comment block that argued for it.
#
# The call arguments were lifted out of the original file with the PowerShell AST
# parser, not retyped. The patterns are multi-line with load-bearing indentation,
# and a transcription slip would not fail loudly -- it would make the pattern stop
# matching, which this harness reports as a NO-OP on a mutation whose real anchor
# is fine. That is a bug indistinguishable from a rotted anchor, so the conversion
# does not create one.
#
# The target is now PINNED to wasm. This gate ran bare `moon test`, which resolved
# through `preferred_target = "wasm"` in `moon.mod` -- 514 tests rather than the
# 442 the js target runs. The scope of the whole gate therefore depended on a field
# in the module manifest rather than on anything in this script.
'@

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine(($head -join "`n"))
[void]$sb.AppendLine($NOTE)
[void]$sb.AppendLine("`n`$ErrorActionPreference = 'Stop'")
[void]$sb.AppendLine(". (Join-Path `$PSScriptRoot 'mutate_lib.ps1')")
[void]$sb.AppendLine("`n`$mutations = @(")

for ($r = 0; $r -lt $rows.Count; $r++) {
  $row = $rows[$r]
  $fs = ConvertTo-HereString -Text $row.Find
  $rs = ConvertTo-HereString -Text $row.Repl
  if ($null -eq $fs -or $null -eq $rs) { Write-Output 'ABORT: a pattern contains a here-string terminator.'; exit 1 }
  if ($row.Comment) {
    foreach ($cl in ($row.Comment -split "`n")) { [void]$sb.AppendLine('  ' + $cl) }
  }
  [void]$sb.AppendLine('  @{')
  [void]$sb.AppendLine("    Name = '" + $row.Name.Replace("'", "''") + "'")
  [void]$sb.AppendLine("    File = '" + $row.File.Replace("'", "''") + "'")
  [void]$sb.AppendLine("    Find = " + $fs)
  [void]$sb.AppendLine("    Repl = " + $rs)
  if ($row.Expect -ne 'KILLED') { [void]$sb.AppendLine("    Expect = '" + $row.Expect + "'") }
  [void]$sb.AppendLine('  }')
  [void]$sb.AppendLine('')
}
[void]$sb.AppendLine(')')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Invoke-MutationGate -Name '" + $Gate + "' -Target 'wasm' -Mutations `$mutations")
[void]$sb.AppendLine("Write-MutationGateVerdict -Name '" + $Gate + " mutation gate'")
[void]$sb.AppendLine('if ($script:MutationGateFailures.Count -gt 0) { exit 1 }')
[void]$sb.AppendLine('exit 0')
$candidate = $sb.ToString()

$tmp = Join-Path $env:TEMP ('gend_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
[System.IO.File]::WriteAllText($tmp, $candidate, $enc)
$perr = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$null, [ref]$perr)
$bad = @($perr | Where-Object { $_ -ne $null })
if ($bad.Count -gt 0) { Write-Output ('ABORT: generated file does not parse -- ' + $bad[0].Message); exit 1 }

# ---- ROUND-TRIP SELF-CHECK ---------------------------------------------------
# Parse the file just generated and compare every value back against the source.
# Both bugs found while building this converter were invisible to "it parses" and
# invisible to a kill-count comparison: one turned 0419's declared SURVIVED into a
# KILLED because argument 5 means different things in two runners, and one turned
# `Repl = ''` into a here-string holding the indentation, so the mutation left
# whitespace behind instead of deleting its anchor. Neither would have shown up
# as a failure -- both would have quietly changed what the gate measures.
#
# So the emitted table is re-read and compared field by field. If they differ, the
# file is not written.
$check = [System.Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$null, [ref]$null)
$hashes = @($check.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true))
if ($hashes.Count -ne $rows.Count) {
  Write-Output ('ABORT: emitted ' + $hashes.Count + ' table entries, source has ' + $rows.Count + ' calls.'); exit 1
}
$mismatch = @()
for ($r = 0; $r -lt $rows.Count; $r++) {
  $kv = @{}
  foreach ($pair in $hashes[$r].KeyValuePairs) {
    $k = $pair.Item1.Extent.Text.Trim("'", '"')
    # A hashtable value arrives as PipelineAst -> CommandExpressionAst -> the
    # expression itself. Testing Item2 directly for a string type matches nothing,
    # and a check that quietly reads nothing reports every field MISSING.
    $v = $pair.Item2
    if ($v -is [System.Management.Automation.Language.PipelineAst]) { $v = $v.PipelineElements[0] }
    if ($v -is [System.Management.Automation.Language.CommandExpressionAst]) { $v = $v.Expression }
    if ($v -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $v -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { $kv[$k] = $v.Value }
    else { $mismatch += ($rows[$r].Name + '.' + $k + ' is a ' + $v.GetType().Name + ', not a string literal') }
  }
  $src = $rows[$r]
  foreach ($f in @('Name', 'File', 'Find', 'Repl')) {
    $want = [string]$src.$f
    if (-not $kv.ContainsKey($f)) { $mismatch += ($src.Name + '.' + $f + ' MISSING in output'); continue }
    if ($kv[$f] -cne $want) {
      $mismatch += ($src.Name + '.' + $f + ' differs; want |' + ($want -replace "`n", '\n') +
                    '| got |' + ($kv[$f] -replace "`n", '\n') + '|')
    }
  }
  $wantExpect = if ($src.Expect -ne 'KILLED') { $src.Expect } else { $null }
  $gotExpect = if ($kv.ContainsKey('Expect')) { $kv['Expect'] } else { $null }
  if ($wantExpect -ne $gotExpect) {
    $mismatch += ($src.Name + '.Expect differs; want |' + $wantExpect + '| got |' + $gotExpect + '|')
  }
}
if ($mismatch.Count -gt 0) {
  Write-Output ('ABORT: round-trip self-check found ' + $mismatch.Count + ' mismatch(es). Nothing written.')
  foreach ($m in $mismatch) { Write-Output ('  ' + $m) }
  exit 1
}

[System.IO.File]::WriteAllText($dst, $candidate, $enc)

Write-Output ("WROTE " + $dst)
Write-Output ("  header lines kept : " + $head.Count + " of " + $fnIdx)
Write-Output ("  calls transposed  : " + $rows.Count)
Write-Output ("  declared SURVIVED : " + @($rows | Where-Object { $_.Expect -eq 'SURVIVED' }).Count)
Write-Output ("  round-trip        : all " + $rows.Count + " entries compared field by field")
Write-Output ("  parses            : yes")

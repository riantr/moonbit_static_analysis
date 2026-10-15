# Re-rank: what is ACTUALLY costing actionable findings across all six corpora?
#
# WHY. The blocker/backlog lists rank by FIRST error, so a row on either is a
# hypothesis about a file, not a forecast about the finding. That has now
# mis-ranked six increments in a row -- `is` (list said 5, delivered 5),
# `..<=` (said 4, delivered 5), ascription (said 6, delivered 2). This script
# ranks the OTHER way: from the findings themselves, backwards.
#
# It reads the per-file scan dumps `_verify/remeasure.ps1` already writes and
# groups every `actionable`-class finding by (family, normalised message). A
# finding is actionable when it is not inside a NOTPARSE file -- the scanner
# withholds findings from files it could not read, because those measure what
# this analyzer does not understand rather than what the code does.
#
# `noraise` is the reason this exists. It has 99 sites in moonbitlang/async and
# a dozen in proton, and it produced ZERO actionable findings -- every file that
# carries it is either already blocked or the modifier is handled. It sat at the
# top of the todo list because a stale note said so.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\rerank_actionable.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $PSScriptRoot 'remeasure_out'
if (-not (Test-Path $dir)) {
  Write-Output ("no scan dumps in " + $dir)
  Write-Output 'run _verify/remeasure.ps1 first'
  exit 1
}

# WHAT COUNTS AS ACTIONABLE, corrected after measuring it twice.
#
# The scanner's `actionable` is POSITIONAL, not a family. `sa/main.mbt`:
#
#     actionable += n - v.notices        where n = v.findings.length()
#
# and `v.findings` holds only PRE-BOUNDARY findings -- "the boundary drops
# everything from the first failure on". So `actionable` is a count, not a type,
# and two family-based rules were tried here and both were wrong:
#
#   * exclude the whole `ParseError` FAMILY -- dropped one of proton's seven,
#     `10:1 block starts with 'test', ... skipped whole`, which IS actionable.
#   * exclude anything matching `is outside the analyzed subset` -- admitted 90
#     false rows, because `block starts with 'async', outside the analyzer's
#     MoonBit subset` uses a DIFFERENT wording and async's README.mbt.md alone
#     contributes 90.
#
# THE RULE THAT SURVIVES MEASUREMENT: a notice says the word `subset` and an
# actionable finding does not. Every pre-boundary notice in the dumps reads
# "... is outside the analyzed subset ..." or "... outside the analyzer's MoonBit
# subset ...", and no actionable message contains it.
#
# AND ITS KNOWN LIMIT, STATED RATHER THAN PAPERED OVER. The `subset` rule
# reproduces async's `actionable=` exactly (6) and undercounts proton's by one.
# The difference is this finding, which the scanner calls actionable and the rule
# calls a notice because it too says `subset`:
#
#     10:1 - error: block starts with 'test', outside the analyzer's MoonBit
#            subset; skipped whole (ParseError) [structural]
#
# Separating it from async's 90 identical-shaped `block starts with 'async'` rows
# needs the scanner's PRE/POST-BOUNDARY position, and the dump format carries no
# flag for that. An earlier attempt to infer it per file from each header's
# `notices=` was WRONG -- it reported the same count for nineteen files with
# `notices=` ranging from 41 to 220 -- so it was removed rather than trusted.
#
# => THE AUTHORITATIVE ACTIONABLE TOTAL IS THE `actionable=` FIELD ON EACH
#    CORPUS'S SUMMARY LINE, NEVER THIS SCRIPT'S COUNT. This script ranks the
#    SHAPES; it does not certify the total. proton's is 7, not the 6 below.
$rows = @()
foreach ($f in (Get-ChildItem $dir -Filter '*.txt' -File | Sort-Object Name)) {
  $corpus = $f.BaseName
  $cur = ''
  $blocked = $false
  foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
    if ($line -match '^(FOUND|NOTPARSE|CLEAN|SKIP|PARTIAL)\s') {
      $cur = ($line -split "`t")[-1].Trim()
      $blocked = ($line -match '^NOTPARSE')
      continue
    }
    if ($blocked) { continue }
    if ($line -match '^\s*(\d+):(\d+) - (error|warning): (.*?)\s\(([A-Za-z]+)\)\s*\[(.*)\]') {
      $fam = $Matches[5]
      $msg = $Matches[4]
      # The rule that survived measurement: a notice says `subset`, an
      # actionable finding does not. See the header for the two family-based
      # rules that failed first.
      if ($msg -match 'subset') { continue }
      # Normalise so one rule reads as one row: strip quotes and identifiers.
      $k = [regex]::Replace($msg, "'[^']*'", "'X'")
      # The RAW message is kept alongside. `Shape` is what groups a grammar
      # rule together, but the first identifier in it is often a separate
      # construct with its own fix -- `undefined name 'noraise'` and
      # `undefined name 'CookieWaiting'` are the same SHAPE and nothing else.
      # Extracting the name from `Shape` returns the literal `X`, which is the
      # first draft's second mistake after folding them together in the first
      # place.
      $nm = [regex]::Match($msg, "'([^']*)'")
      $rows += [pscustomobject]@{
        Corpus = $corpus
        Family = $fam
        Shape = $k
        Name = $(if ($nm.Success) { $nm.Groups[1].Value } else { '' })
        File = (Split-Path $cur -Leaf)
      }
    }
  }
}

Write-Output ('SHAPES below: ' + $rows.Count + ' findings. The AUTHORITATIVE actionable')
Write-Output 'total is each corpus''s actionable= on the SUMMARY line -- see the header.'
Write-Output ''
Write-Output '=== by message SHAPE (one grammar rule = one row) ==='
$rows | Group-Object Shape | Sort-Object Count -Descending |
  Select-Object -First 14 @{n='N';e={$_.Count}}, @{n='Shape';e={$_.Name}} |
  Format-Table -AutoSize -Wrap | Out-String -Width 150 | Write-Output

# THE SHAPE TABLE ALONE IS NOT ENOUGH, and its first draft got that wrong in the
# most expensive way available. Normalising `'[^']*'` -> `'X'` folds
# `undefined name 'noraise'` and `undefined name 'CookieWaiting'` into one row,
# and `noraise` -- 4 real findings across two corpora -- vanished behind the
# others. A shape is a grammar rule; a NAME is often a whole separate
# construct with its own fix. `noraise` had been at the top of the todo list on
# a stale note, the re-rank "cleared" it as part of an unrelated 9-row bucket,
# and only reading the raw sites brought it back.
#
# => whenever a shape bucket is more than a few rows, ask what the NAMES are.
Write-Output '=== by family x corpus ==='
$rows | Group-Object Family, Corpus | Sort-Object Count -Descending |
  Select-Object -First 14 @{n='N';e={$_.Count}}, Name |
  Format-Table -AutoSize | Out-String -Width 150 | Write-Output

Write-Output '=== by NAME, for the families whose message carries one ==='
# `$_.Name`, NOT a re-extraction from `$_.Shape`. `Shape` is the NORMALISED
# message -- every quoted identifier is already `'X'` -- so extracting from it
# returns the literal letter X, which is exactly what this table printed. The
# `Name` field was added for this and the table kept reading `Shape` anyway, so
# the fix was half-applied and the table stayed useless.
$named = $rows | Where-Object { $_.Name -ne '' }
$named | Group-Object Name | Sort-Object Count -Descending |
  Select-Object -First 16 @{n='N';e={$_.Count}}, @{n='Name';e={$_.Name}},
    @{n='Corpora';e={ (($_.Group | Select-Object -ExpandProperty Corpus -Unique) -join ',') }} |
  Format-Table -AutoSize | Out-String -Width 150 | Write-Output

Write-Output '=== distinct FILES behind the top shapes ==='
$top = $rows | Group-Object Shape | Sort-Object Count -Descending | Select-Object -First 5
foreach ($t in $top) {
  Write-Output ('-- ' + $t.Count + 'x  ' + $t.Name)
  $t.Group | Group-Object File | Sort-Object Count -Descending | Select-Object -First 4 |
    ForEach-Object { '     ' + $_.Count + 'x ' + $_.Name }
}

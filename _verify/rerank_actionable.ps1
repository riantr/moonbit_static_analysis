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

# A family is actionable unless it is one the project records as a declared
# scope limit. `ParseError` on a read file is a subset-exclusion notice, not a
# finding about the code -- the scanner already withholds those, and this keeps
# the count honest if a dump was taken mid-change.
$rows = @()
foreach ($f in (Get-ChildItem $dir -Filter '*.txt' -File | Sort-Object Name)) {
  $corpus = $f.BaseName
  $cur = ''
  $blocked = $false
  foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
    if ($line -match '^(FOUND|NOTPARSE|CLEAN|SKIP)\s') {
      $cur = ($line -split "`t")[-1].Trim()
      $blocked = ($line -match '^NOTPARSE')
      continue
    }
    if ($blocked) { continue }
    if ($line -match '^\s*(\d+):(\d+) - (error|warning): (.*?)\s\(([A-Za-z]+)\)\s*\[(.*)\]') {
      $fam = $Matches[5]
      $msg = $Matches[4]
      if ($fam -eq 'ParseError') { continue }
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

Write-Output ('actionable findings across all corpora: ' + $rows.Count)
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
$named = $rows | Where-Object { $_.Shape -match "name|function|binding for" } | ForEach-Object {
  $m = [regex]::Match($_.Shape, "'([^']*)'")
  [pscustomobject]@{ Name = $(if ($m.Success) { $m.Groups[1].Value } else { '?' }); Corpus = $_.Corpus }
}
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

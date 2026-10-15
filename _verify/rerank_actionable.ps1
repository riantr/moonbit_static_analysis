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
      $rows += [pscustomobject]@{
        Corpus = $corpus
        Family = $fam
        Shape = $k
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

Write-Output '=== by family x corpus ==='
$rows | Group-Object Family, Corpus | Sort-Object Count -Descending |
  Select-Object -First 14 @{n='N';e={$_.Count}}, Name |
  Format-Table -AutoSize | Out-String -Width 150 | Write-Output

Write-Output '=== distinct FILES behind the top shapes ==='
$top = $rows | Group-Object Shape | Sort-Object Count -Descending | Select-Object -First 5
foreach ($t in $top) {
  Write-Output ('-- ' + $t.Count + 'x  ' + $t.Name)
  $t.Group | Group-Object File | Sort-Object Count -Descending | Select-Object -First 4 |
    ForEach-Object { '     ' + $_.Count + 'x ' + $_.Name }
}

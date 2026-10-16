# Classify the 0467 per-file-first-blocker rows into SHAPES, and print every member.
#
# WHY A SCRIPT FOR THIS. Reading 57 rows and eyeballing a shape off each one is exactly
# the `..`-classifier failure: two different bad reads both produce PLAUSIBLE totals and
# both differ per corpus, so no cross-corpus sanity check catches them. The rows are
# printed by `rank_0467_first_blocker.ps1`; this groups them and prints the members so a
# mis-filed row is visible instead of being folded into a total.
#
# => 判据: a classifier must print its own output. A bucket count can only be checked
# against an expectation you already hold; the members show what the filter actually did.
#
# THE KNOWN TRAPS in this environment, all of which have bitten this ranking before:
#   * PowerShell variables are CASE-INSENSITIVE, so `$RET` (a regex string) and `$ret`
#     (an array) are the SAME variable. `-match @()` coerces an empty array to '' which
#     matches every line, putting all 47/47 files in every bucket.
#   * `[^,]` excludes the comma INSIDE `async (A, B)`, so every multi-argument parameter
#     form silently fails to match.
#   * a failed `ReadAllLines` leaves the previous file's lines alive.
$ErrorActionPreference = 'Continue'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'

$TARGETS = [ordered]@{
  'async'  = 'moonbitlang\async\0.22.4'
  'proton' = 'moonbit-community\proton\0.3.4'
}

# Bucket order matters: the first match wins, so the specific shapes are tested before
# the general ones. A row that matches two shapes is filed under the one that explains
# WHY THE PARSE STOPPED, not merely one that happens to appear in the window.
$Buckets = [ordered]@{
  'async_param_type'  = ': async\s*\('
  'for_brace_header'  = 'for\b[^\r\n]*\{'
  'annotated_let'     = 'let\s+_\w*\s*:\s*\w+\s*=\s*\{'
  'struct_pat_rest'   = 'is\s*\{[^\r\n]*\.\.'
  'let_destructure'   = 'let\s+[A-Z]\w*\([^)]*\.\.'
}

$rows = @()
foreach ($k in $TARGETS.Keys) {
  $corpus = Join-Path $repos $TARGETS[$k]
  $out = & 'C:\Users\31379\.moon\bin\moonrun.exe' $wasm $corpus --extern-iface-dir $repos 2>&1 | Out-String
  $found = 0; $clean = 0; $part = @()
  foreach ($line in ($out -split "`n")) {
    if ($line -match '^FOUND\t') { $found++ }
    if ($line -match '^CLEAN\t') { $clean++ }
    if ($line -match '^PARTIAL\s+\.mbt\s+.*read up to line (\d+),.*\t(.+)$') {
      $part += [pscustomobject]@{ Line = [int]$Matches[1]; Path = $Matches[2].Trim() }
    }
  }
  # CONTROL: parsed IS FOUND + CLEAN. Assert it, do not assume it.
  $parsed = [int]([regex]::Match($out, '(?m)^SUMMARY\s+files=\d+\s+parsed=(\d+)')).Groups[1].Value
  if (($found + $clean) -ne $parsed) {
    Write-Output ('*** {0}: FOUND+CLEAN={1} != parsed={2} ***' -f $k, ($found + $clean), $parsed); exit 1
  }
  Write-Output ('CONTROL {0,-8} parsed={1}  PARTIAL={2}' -f $k, $parsed, $part.Count)
  if ($part.Count -eq 0) { Write-Output ('*** {0}: no PARTIAL detail ***' -f $k); exit 1 }

  foreach ($p in $part) {
    if (-not [IO.File]::Exists($p.Path)) { continue }
    $src = $null
    try { $src = [IO.File]::ReadAllLines($p.Path) } catch { $src = $null }
    if ($null -eq $src) { continue }
    $lo = [Math]::Max(0, $p.Line - 2)
    $hi = [Math]::Min($src.Length - 1, $p.Line + 1)
    $win = @()
    for ($i = $lo; $i -le $hi; $i++) { $win += $src[$i].Trim() }
    $rel = $p.Path.Replace($corpus + '\', '').Replace($corpus + '/', '')
    $rows += [pscustomobject]@{ Corpus = $k; Line = $p.Line; Rel = $rel; Text = ($win -join ' | ') }
  }
}

Write-Output ''
Write-Output ('rows = {0}' -f $rows.Count)
Write-Output ''

$assigned = @{}
$out = @()
foreach ($name in $Buckets.Keys) {
  $pat = $Buckets[$name]
  $hit = @($rows | Where-Object { -not $assigned.ContainsKey(($_.Corpus + '|' + $_.Rel)) -and $_.Text -match $pat })
  $out += [pscustomobject]@{ Name = $name; Pat = $pat; Hit = $hit }
  foreach ($h in $hit) { $assigned[($h.Corpus + '|' + $h.Rel)] = $name }
}
$rest = @($rows | Where-Object { -not $assigned.ContainsKey(($_.Corpus + '|' + $_.Rel)) })
$out += [pscustomobject]@{ Name = 'OTHER'; Pat = '(none of the above)'; Hit = $rest }

foreach ($b in $out) {
  Write-Output ('### {0}  ({1} files)   /{2}/' -f $b.Name, $b.Hit.Count, $b.Pat)
  foreach ($h in ($b.Hit | Sort-Object Corpus, Rel)) {
    Write-Output ('    {0,-8} {1,5}  {2}' -f $h.Corpus, $h.Line, $h.Rel)
  }
  Write-Output ''
}

Write-Output '--- TOTALS ---'
foreach ($b in $out) { Write-Output ('  {0,-20} {1}' -f $b.Name, $b.Hit.Count) }
$sum = 0; foreach ($b in $out) { $sum += $b.Hit.Count }
Write-Output ('  {0,-20} {1}   (must equal rows)' -f 'SUM', $sum)
if ($sum -ne $rows.Count) { Write-Output '*** BUCKETS DO NOT PARTITION THE ROWS ***'; exit 1 }

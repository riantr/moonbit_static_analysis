$ErrorActionPreference = 'Continue'
# Verify the README restructure.
#
# WHAT THIS CHECKS, and each item is a thing that can be WRONG:
#
#   1. Every relative markdown link in README.md / README.zh.md / CHANGELOG.md
#      resolves to a file that EXISTS. A link to a file the restructure moved is
#      the classic way a README rots: the target moved and nobody noticed.
#   2. Every `#anchor` in the "Contents" list resolves to a heading that exists.
#   3. Every version reference in the READMEs names 0.4.32 and nothing older.
#   4. The changelog still carries the in-place corrections -- the release that
#      corrected a wrong claim must still carry it, in the file it moved to.
#   5. The counts the README quotes are the ones the tools measured.
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$fail = 0

Write-Output '=== 1. relative links resolve ==='
foreach ($f in @('README.md','README.zh.md','CHANGELOG.md','CHANGELOG.zh.md')) {
  $p = Join-Path $root $f
  $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $dir = Split-Path -Parent $p
  $bad = 0; $n = 0
  foreach ($m in [regex]::Matches($txt, '\[[^\]]*\]\(([^)\s]+)\)')) {
    $target = $m.Groups[1].Value
    if ($target -match '^(https?:|mailto:|#)') { continue }
    $n++
    $pathPart = ($target -split '#')[0]
    if ($pathPart -eq '') { continue }
    $full = Join-Path $dir $pathPart
    if (-not (Test-Path -LiteralPath $full)) {
      Write-Output ("  BROKEN " + $f + " -> " + $target)
      $bad++
    }
  }
  Write-Output ("  {0,-16} {1,3} relative links, {2} broken" -f $f, $n, $bad)
  $fail += $bad
}

Write-Output '=== 2. Contents anchors resolve to headings ==='
function Get-Anchor([string]$heading) {
  # GitHub's rule: lowercase, drop punctuation except hyphens and underscores,
  # spaces -> hyphens.
  $a = $heading.ToLowerInvariant()
  $a = $a -replace '[^\p{L}\p{N}\s\-_]', ''
  $a = $a -replace '\s', '-'
  return $a
}
foreach ($f in @('README.md','README.zh.md')) {
  $p = Join-Path $root $f
  $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $lines = $txt -split "`r?`n"
  $headings = @{}
  foreach ($l in $lines) { if ($l -match '^#{1,6}\s+(.*)$') { $h = Get-Anchor $Matches[1]; if (-not $headings.ContainsKey($h)) { $headings[$h] = $true } } }
  $bad = 0; $n = 0
  foreach ($l in $lines) {
    if ($l -match '^- \[([^\]]+)\]\(#([^)]+)\)$') {
      $n++
      if (-not $headings.ContainsKey($Matches[2])) { Write-Output ("  BROKEN ANCHOR " + $f + " -> #" + $Matches[2]); $bad++ }
    }
  }
  Write-Output ("  {0,-16} {1,3} TOC anchors, {2} broken  (headings available: {3})" -f $f, $n, $bad, $headings.Count)
  $fail += $bad
}

Write-Output '=== 3. version references ==='
foreach ($f in @('README.md','README.zh.md')) {
  $p = Join-Path $root $f
  $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $vers = @{}
  foreach ($m in [regex]::Matches($txt, '0\.4\.\d+')) {
    $v = $m.Value
    # A version that belongs to ANOTHER package is not this module's version:
    # `moonbitlang/parser@0.4.3` and `moonbitlang/lexer@0.4.2` are external
    # references in the References section, and flagging them would be noise.
    $start = [Math]::Max(0, $m.Index - 40)
    $ctx = $txt.Substring($start, $m.Index - $start)
    if ($ctx -match '(parser|lexer)@$') { continue }
    if (-not $vers.ContainsKey($v)) { $vers[$v] = 0 }
    $vers[$v]++
  }
  foreach ($k in ($vers.Keys | Sort-Object)) { Write-Output ("  {0,-16} {1} x {2}" -f $f, $vers[$k], $k) }
  $wrong = @($vers.Keys | Where-Object { $_ -ne '0.4.32' })
  if ($wrong.Count -gt 0) { Write-Output ("    FAIL: this module's version must be 0.4.32; also found: " + ($wrong -join ', ')); $fail++ }
}

Write-Output '=== 4. the in-place corrections survived the move ==='
$checks = @(
  @{ F = 'CHANGELOG.md';    S = 'CORRECTED IN 0.4.32 -- that census covered SIX corpora' }
  @{ F = 'CHANGELOG.md';    S = 'The "2" was the census of six corpora, and the seventh was never counted' }
  @{ F = 'CHANGELOG.md';    S = '## 0.4.32' }
  @{ F = 'CHANGELOG.zh.md'; S = '## 0.4.32' }
  @{ F = 'CHANGELOG.zh.md'; S = '那个「2」是六个语料的普查，第七个从来没被数过' }
  @{ F = 'README.md';       S = 'This note said **116 → 2** until 0.4.32' }
  @{ F = 'README.zh.md';    S = '这条注记原本写的是 **116 → 2**' }
)
foreach ($c in $checks) {
  $p = Join-Path $root $c.F
  $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $ok = $txt.Contains($c.S)
  Write-Output ("  {0,-18} {1,-62} {2}" -f $c.F, $c.S, $(if ($ok) { 'FOUND' } else { 'MISSING' }))
  if (-not $ok) { $fail++ }
}

Write-Output '=== 5. the counts the README quotes ==='
# The GATE COUNT is COMPUTED, not pinned. A literal '79' in this file would be
# another number that has to be kept right by hand -- and the roster it describes
# changes every time a gate is added. So the number comes from the disk, and the
# README has to say THAT number. When a gate is added, this check fails with the
# new count in the message, and the README is a one-word edit.
#
# The two claims that are not counts are claims about the LIST, and they are
# checked here because the roster gate enforces the same thing from the other
# side: every gate on disk is in `release.ps1`'s list, so no gate is left out of
# the release path.
$gateCount = @(Get-ChildItem -LiteralPath (Join-Path $root '_verify') -Filter 'mutate_0*.ps1' -File).Count
Write-Output ('  (the roster has ' + $gateCount + ' numbered gates on disk)')
$expect = @(
  @{ F = 'README.md';    S = '1163/1163'; N = 'wasm test count' }
  @{ F = 'README.md';    S = '1083/1083'; N = 'js/wasm-gc test count' }
  @{ F = 'README.md';    S = '957 parsed'; N = 'core parsed' }
  @{ F = 'README.md';    S = '33 actionable'; N = 'core module actionable' }
  @{ F = 'README.md';    S = '**58** `actionable`'; N = 'per-function census total' }
  @{ F = 'README.md';    S = '24 of 24'; N = 'positive control' }
  @{ F = 'README.md';    S = ($gateCount.ToString() + ' of them'); N = 'mutation gates' }
  @{ F = 'README.md';    S = ('**' + $gateCount + ' mutation gates**'); N = 'mutation gates (the second mention)' }
  @{ F = 'README.md';    S = ('and all ' + $gateCount + ' are inside the'); N = 'every gate is in the release list' }
  @{ F = 'README.zh.md'; S = '1163/1163'; N = 'wasm test count (zh)' }
  @{ F = 'README.zh.md'; S = '1083/1083'; N = 'js/wasm-gc test count (zh)' }
  @{ F = 'README.zh.md'; S = '解析 957 个'; N = 'core parsed (zh)' }
  @{ F = 'README.zh.md'; S = '**58** 条'; N = 'per-function census total (zh)' }
  @{ F = 'README.zh.md'; S = '24 / 24'; N = 'positive control (zh)' }
  @{ F = 'README.zh.md'; S = ('**' + $gateCount + '** 个'); N = 'mutation gates (zh)' }
  @{ F = 'README.zh.md'; S = ('**' + $gateCount + ' 道变异门**'); N = 'mutation gates (zh, the second mention)' }
  @{ F = 'README.zh.md'; S = ('而且 ' + $gateCount + ' 个全在'); N = 'every gate is in the release list (zh)' }
)
foreach ($e in $expect) {
  $p = Join-Path $root $e.F
  $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $ok = $txt.Contains($e.S)
  Write-Output ("  {0,-14} {1,-34} {2}" -f $e.F, $e.N, $(if ($ok) { 'OK' } else { 'MISSING: ' + $e.S }))
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($fail -eq 0) { Write-Output 'VERIFY OK: links, anchors, versions, corrections and counts all check out.'; exit 0 }
Write-Output ("VERIFY FAILED: " + $fail + " problem(s).")
exit 1

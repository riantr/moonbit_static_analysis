$ErrorActionPreference = 'Continue'
# Verify the README restructure.
#
# WHAT THIS CHECKS, and each item is a thing that can be WRONG:
#
#   1. Every relative markdown link in README.md / README.zh.md / CHANGELOG.md
#      resolves to a file that EXISTS. A link to a file the restructure moved is
#      the classic way a README rots: the target moved and nobody noticed.
#   2. Every `#anchor` in the "Contents" list resolves to a heading that exists.
#   3. Every version reference to THIS package, in every published document, names
#      the released version -- and each document's install line names it too.
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
# The version is READ FROM `moon.mod`, not pinned here. A literal version string in
# this file would be another number that has to be kept right by hand, and the
# version changes on every release -- so a release would have to edit the GATE as
# well as the README, and a missed edit would either block the release for the
# wrong reason or, worse, let a README naming an OLD version through.
#
# So the authority is `moon.mod`, the file the registry reads. The documents have to
# name THAT version, and the failure message says which one, so a stale document
# names the number it should have said.
#
# WHAT COUNTS AS A VERSION REFERENCE. A version number in PROSE is not a reference.
# "until 0.4.32" is a true statement about a correction that happened in 0.4.32, and
# it stays true in every release after it -- so a check that demands it change is
# demanding a falsehood. A version number that FOLLOWS THIS PACKAGE'S NAME is a
# reference to the thing a reader installs, or to the artifact a reader receives,
# and THAT is the one that has to be current.
#
# So the matcher is built from the package's own name rather than from a pattern for
# "anything version-shaped":
#
#     moonbit_static_analysis@<v>       what the reader installs
#     moonbit_static_analysis_<v>_      what the reader receives
#
# The first version of this check said "every 0.4.x in the README must be the
# current one", which is the same RULE with a coarser MATCHER. It passed at 0.4.32 --
# the only other version in the file was that historical note -- and at 0.4.33 it
# FAILED for exactly that note (MEASURED: "FAIL: README.md must name 0.4.33 and
# nothing older; also found: 0.4.32"). A gate that fails on a true statement is a
# gate that gets disabled, and a disabled gate is a comment.
#
# It also looked only at the two READMEs. SKILL.md ships to the registry too
# (MEASURED: the published 0.4.32 tree carries it at the top level) and it tells the
# reader to run `moonx riantr/moonbit_static_analysis@0.4.32` -- so a release that
# synced the READMEs and left SKILL.md behind would publish an install instruction
# for the previous version, and no check would have said so.
#
# CHANGELOG.md is deliberately NOT in the list below: every release section names
# its OWN version, and those references are historical by construction.
$moonMod = [System.IO.File]::ReadAllText((Join-Path $root 'moon.mod'), [System.Text.Encoding]::UTF8)
$vm = [regex]::Match($moonMod, '(?m)^version\s*=\s*"([^"]+)"')
if (-not $vm.Success) {
  Write-Output '  FAIL: moon.mod does not declare a version, so there is nothing for the documents to match.'
  $fail++
  $thisVersion = ''
} else {
  $thisVersion = $vm.Groups[1].Value
  Write-Output ('  moon.mod says: ' + $thisVersion)
}

# Every document the registry serves, and every version reference in each of them.
$docs = @('README.md','README.zh.md','SKILL.md')
$ownRef = 'moonbit_static_analysis[@_](\d+\.\d+\.\d+)'
foreach ($f in $docs) {
  $p = Join-Path $root $f
  if (-not (Test-Path -LiteralPath $p)) {
    Write-Output ("  FAIL: " + $f + " is not in the tree, so nothing can check what it says.")
    $fail++
    continue
  }
  $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $seen = @{}
  foreach ($m in [regex]::Matches($txt, $ownRef)) {
    $v = $m.Groups[1].Value
    if (-not $seen.ContainsKey($v)) { $seen[$v] = 0 }
    $seen[$v]++
  }
  if ($seen.Count -eq 0) {
    Write-Output ("    FAIL: " + $f + " names no version of this package at all -- a check that passes on nothing is not a check.")
    $fail++
    continue
  }
  foreach ($k in ($seen.Keys | Sort-Object)) { Write-Output ("  {0,-16} {1} x {2}" -f $f, $seen[$k], $k) }
  $wrong = @($seen.Keys | Where-Object { $_ -ne $thisVersion })
  if ($wrong.Count -gt 0) {
    Write-Output ("    FAIL: " + $f + " must name " + $thisVersion + " wherever it names THIS package; also found: " + ($wrong -join ', '))
    $fail++
  }
}

# The form each document uses to tell the reader what to install. A document that
# names the right version in the wrong place -- or that drops the line -- is not
# telling the reader anything, and a version reference that is not IN the install
# line does not tell the reader what to install. The READMEs show `moon add`;
# SKILL.md shows `moonx`.
$installForms = @(
  @{ F = 'README.md';    R = 'moon add riantr/moonbit_static_analysis@(\d+\.\d+\.\d+)' }
  @{ F = 'README.zh.md'; R = 'moon add riantr/moonbit_static_analysis@(\d+\.\d+\.\d+)' }
  @{ F = 'SKILL.md';     R = 'moonx riantr/moonbit_static_analysis@(\d+\.\d+\.\d+)' }
)
foreach ($e in $installForms) {
  $p = Join-Path $root $e.F
  $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $im = [regex]::Match($txt, $e.R)
  if (-not $im.Success) {
    Write-Output ("    FAIL: " + $e.F + " has no install line of the form " + $e.R + " -- the reader is not told what to install.")
    $fail++
    continue
  }
  $v = $im.Groups[1].Value
  if ($v -ne $thisVersion) {
    Write-Output ("    FAIL: " + $e.F + " tells the reader to install " + $v + "; the released version is " + $thisVersion + ".")
    $fail++
  } else {
    Write-Output ("  {0,-16} install line names {1}   OK" -f $e.F, $v)
  }
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
  @{ F = 'README.md';    S = 'The roster is **checked, not asserted**'; N = 'the roster is checked, not asserted' }
  @{ F = 'README.md';    S = '_verify/check_gate_roster.ps1'; N = 'the gate that checks the roster is named' }
  @{ F = 'README.zh.md'; S = '1163/1163'; N = 'wasm test count (zh)' }
  @{ F = 'README.zh.md'; S = '1083/1083'; N = 'js/wasm-gc test count (zh)' }
  @{ F = 'README.zh.md'; S = '解析 957 个'; N = 'core parsed (zh)' }
  @{ F = 'README.zh.md'; S = '**58** 条'; N = 'per-function census total (zh)' }
  @{ F = 'README.zh.md'; S = '24 / 24'; N = 'positive control (zh)' }
  @{ F = 'README.zh.md'; S = ('**' + $gateCount + '** 个'); N = 'mutation gates (zh)' }
  @{ F = 'README.zh.md'; S = ('**' + $gateCount + ' 道变异门**'); N = 'mutation gates (zh, the second mention)' }
  @{ F = 'README.zh.md'; S = '这份名册是**被检查的，不是被断言的**'; N = 'the roster is checked, not asserted (zh)' }
  @{ F = 'README.zh.md'; S = '_verify/check_gate_roster.ps1'; N = 'the gate that checks the roster is named (zh)' }
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

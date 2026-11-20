param([string]$Root = '')
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
#
# There is no -SelfTest switch, and that is deliberate: this gate is shown to go
# red by INJECTING a defect into the tree and running it, which is a stronger
# statement than a switch that reproduces the checker's own logic. Its subject
# is this repository's own published documents, and the injection that showed it
# red was a stage added to `release.ps1` that the READMEs did not name: the
# gate went RED until both named it. A switch that re-read the same documents
# would only prove that the checker can read its own inputs.
$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
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

# The MUTATION COUNTS are COMPUTED too, and they used to be PINNED LITERALS in
# the README with nothing checking them at all. That is the same defect the
# test count had, one level down: "393 of the 430 live mutations expect a
# kill; 316 of them also name the test" was a published number that a gate
# adding a mutation could move without any gate noticing.
#
# Three numbers, three different meanings, and they are counted from the gate
# sources rather than asserted:
#
#   live mutations      every `Name = 'M...'` declaration
#   expect a kill       the ones whose `Expect` is the default 'KILLED'; the
#                       others declare themselves 'SURVIVED' or 'COMPILE-ERR'
#                       and are counted apart
#   name the test       the ones that carry a `MustRed`, which is the harness's
#                       way of saying WHICH test must go red
$mutTotal = 0
$mutMustRed = 0
$mutDeclared = 0
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $root '_verify') -Filter 'mutate_0*.ps1' -File)) {
  $src = [System.IO.File]::ReadAllText($f.FullName)
  $mutTotal += [regex]::Matches($src, "(?m)^\s*Name = 'M\d").Count
  $mutMustRed += [regex]::Matches($src, '(?m)^\s*MustRed = ').Count
  foreach ($m in [regex]::Matches($src, "(?m)^\s*Expect = '([^']*)'")) {
    if ($m.Groups[1].Value -ne 'KILLED') { $mutDeclared++ }
  }
}
$mutExpectKill = $mutTotal - $mutDeclared
Write-Output ('  (the roster has ' + $mutTotal + ' live mutations: ' + $mutExpectKill + ' expect a kill, ' + $mutMustRed + ' name the test)')

# The TEST COUNT is COMPUTED too, and it used to be PINNED -- which is the wrong
# way round. A pinned literal catches the README moving without this file
# moving; it does NOT catch the SUITE moving without the README moving, which is
# the direction that matters: an increment that adds tests and does not update
# the README leaves a published number that is stale, and a pinned gate reads it
# as correct. (0500 added eleven tests and moved the number from 1163 to 1174,
# which is how this was found: the pinned literal and the edited README
# disagreed, and the gate said so -- but only because the edit and the pin were
# changed together.)
#
# So the suite is run here and the README is checked against what it actually
# produced. The two targets are not the same number and the difference is
# STRUCTURAL: `src/sa` needs the async runtime, so it is skipped on js and on
# wasm-gc, and its tests do not run there. js and wasm-gc are therefore expected
# to AGREE with each other, and that is asserted rather than assumed.
function Get-TestCount {
  param([string]$Target)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = & $moon -C $root test --target $Target --deny-warn 2>&1 | Out-String
  $ErrorActionPreference = $prev
  $m = [regex]::Match($o, 'Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)')
  if (-not $m.Success) { return $null }
  return [pscustomobject]@{
    Total = [int]$m.Groups[1].Value
    Passed = [int]$m.Groups[2].Value
    Failed = [int]$m.Groups[3].Value
  }
}
$wasmT = Get-TestCount 'wasm'
$jsT = Get-TestCount 'js'
$gcT = Get-TestCount 'wasm-gc'
if ($null -eq $wasmT -or $null -eq $jsT -or $null -eq $gcT) {
  Write-Output '  FAIL: the suite did not run, so the README''s test count cannot be checked.'
  $fail++
  $wasmT = @{ Passed = 0; Total = 1 }
  $jsT = @{ Passed = 0; Total = 1 }
  $gcT = @{ Passed = 0; Total = 1 }
} else {
  Write-Output ('  (the suite says: wasm ' + $wasmT.Passed + '/' + $wasmT.Total +
                ', js ' + $jsT.Passed + '/' + $jsT.Total +
                ', wasm-gc ' + $gcT.Passed + '/' + $gcT.Total + ')')
  if ($jsT.Total -ne $gcT.Total) {
    Write-Output ('  FAIL: js ran ' + $jsT.Total + ' tests and wasm-gc ran ' + $gcT.Total +
                  '. The README quotes ONE number for both, so they have to agree.')
    $fail++
  }
  if ($wasmT.Failed -ne 0 -or $jsT.Failed -ne 0 -or $gcT.Failed -ne 0) {
    Write-Output '  FAIL: the suite is red, so a "n/n" claim in the README cannot be true.'
    $fail++
  }
}
$wasmStr = ($wasmT.Passed.ToString() + '/' + $wasmT.Total.ToString())
$jsStr = ($jsT.Passed.ToString() + '/' + $jsT.Total.ToString())
# THE CORPUS NUMBERS ARE DERIVED FROM release.ps1's PIN TABLE, not written here
# as literals.
#
# WHY, and it is not tidiness. 0502 moved four of these numbers at once -- the
# core module's `actionable`, the per-function census total, the positive
# control's file count -- and the README gate PASSED with every one of them
# stale, because the gate only asked "does the README contain the string I
# wrote down". The literals were a SECOND PLACE the same fact was written,
# and the two places drifted apart: release.ps1's pin was re-pinned from the
# measurement, the gate's literals were not, and the README kept publishing
# numbers that had been true for a release and a half.
#
# => 判据: A NUMBER WRITTEN DOWN TWICE IS A NUMBER THAT WILL DISAGREE WITH
# ITSELF. The corpus numbers now live in ONE place -- release.ps1's pin table,
# which the corpus stage checks against a live scan -- and the README gate
# DERIVES its expectations from that table. So the gate asks "does the README
# say what the pin says", which is the question it can actually answer.
#
# AND THE GATE FAILS LOUDLY if the pins are gone, rather than quietly
# checking against a default.
$relTxt = [System.IO.File]::ReadAllText((Join-Path $root '_verify\release.ps1'), [System.Text.Encoding]::UTF8)
$coreM = [regex]::Match($relTxt, "'moonbit_core'\s*=\s*'files=(\d+)\s+parsed=(\d+)\s+actionable=(\d+)")
$censusM = [regex]::Match($relTxt, '\$PERFN_TOTAL\s*=\s*''(\d+)''')
$ctrlM = [regex]::Match($relTxt, '\$CONTROL_N\s*=\s*''(\d+)''')
if (-not $coreM.Success -or -not $censusM.Success -or -not $ctrlM.Success) {
  Write-Output '  FAIL: release.ps1 no longer carries the corpus pins this gate derives from.'
  Write-Output '        Restore them, or this gate has nothing to check the README against.'
  $fail++
  $coreParsed = '?'
  $coreActionable = '?'
  $censusTotal = '?'
  $controlN = '?'
} else {
  $coreParsed = $coreM.Groups[2].Value
  $coreActionable = $coreM.Groups[3].Value
  $censusTotal = $censusM.Groups[1].Value
  $controlN = $ctrlM.Groups[1].Value
  Write-Output ('  (release.ps1 pins: core parsed ' + $coreParsed + ', core actionable ' +
                $coreActionable + ', census total ' + $censusTotal + ', control ' + $controlN + ' of ' + $controlN + ')')
}
$expect = @(
  @{ F = 'README.md';    S = $wasmStr; N = 'wasm test count' }
  @{ F = 'README.md';    S = $jsStr; N = 'js/wasm-gc test count' }
  @{ F = 'README.md';    S = ($coreParsed + ' parsed'); N = 'core parsed' }
  @{ F = 'README.md';    S = ($coreActionable + ' actionable'); N = 'core module actionable' }
  @{ F = 'README.md';    S = ('**' + $censusTotal + '** `actionable`'); N = 'per-function census total' }
  @{ F = 'README.md';    S = ($controlN + ' of ' + $controlN); N = 'positive control' }
  @{ F = 'README.md';    S = ($gateCount.ToString() + ' of them'); N = 'mutation gates' }
  @{ F = 'README.md';    S = ('**' + $gateCount + ' mutation gates**'); N = 'mutation gates (the second mention)' }
  @{ F = 'README.md';    S = ('**' + $mutTotal + '** live mutations'); N = 'live mutations' }
  @{ F = 'README.md';    S = ('**' + $mutExpectKill + '** expect a kill'); N = 'mutations that expect a kill' }
  @{ F = 'README.md';    S = ('**' + $mutMustRed + '** of them also name the test'); N = 'mutations that name the test' }
  @{ F = 'README.md';    S = 'The roster is **checked, not asserted**'; N = 'the roster is checked, not asserted' }
  @{ F = 'README.md';    S = '_verify/check_gate_roster.ps1'; N = 'the gate that checks the roster is named' }
  @{ F = 'README.zh.md'; S = $wasmStr; N = 'wasm test count (zh)' }
  @{ F = 'README.zh.md'; S = $jsStr; N = 'js/wasm-gc test count (zh)' }
  @{ F = 'README.zh.md'; S = ('解析 ' + $coreParsed + ' 个'); N = 'core parsed (zh)' }
  @{ F = 'README.zh.md'; S = ('**' + $censusTotal + '** 条'); N = 'per-function census total (zh)' }
  @{ F = 'README.zh.md'; S = ($controlN + ' / ' + $controlN); N = 'positive control (zh)' }
  @{ F = 'README.zh.md'; S = ('**' + $gateCount + '** 个'); N = 'mutation gates (zh)' }
  @{ F = 'README.zh.md'; S = ('**' + $gateCount + ' 道变异门**'); N = 'mutation gates (zh, the second mention)' }
  @{ F = 'README.zh.md'; S = ('**' + $mutTotal + '** 个存活变异里'); N = 'live mutations (zh)' }
  @{ F = 'README.zh.md'; S = ('**' + $mutExpectKill + '** 个预期被杀'); N = 'mutations that expect a kill (zh)' }
  @{ F = 'README.zh.md'; S = ('**' + $mutMustRed + ' 个**还点名了'); N = 'mutations that name the test (zh)' }
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
# --- the README's own-source notice TABLE, and the numbers 0502 re-measured ----
#
# These four numbers were all published by the README and all of them were
# quoted from an OLDER state of the analyzer: the `ParseError` count was
# measured before the `match` arms were read, the notice table was measured
# with the per-file printing cap at 40 (so it counted 1,499 of the 1,584
# notices), and the "what the suppression hides" pair was measured before the
# suppression was narrowed per binding.
#
# They are DERIVED here from release.ps1's pin table, the same way the corpus
# numbers are: the release gate MEASURES them on every run and compares them
# with the pin, and this gate asks only "does the README say what the pin
# says". That is the question a gate can actually answer, and it is the
# question that keeps a README from publishing a number nobody re-measured.
$relTxt2 = [System.IO.File]::ReadAllText((Join-Path $root '_verify\release.ps1'), [System.Text.Encoding]::UTF8)
$peM  = [regex]::Match($relTxt2, "\`$NOTICE_TOTAL\s*=\s*'(\d+)'")
$sfM  = [regex]::Match($relTxt2, "\`$SELF_FILES\s*=\s*'(\d+)'")
$snM  = [regex]::Match($relTxt2, "\`$SELF_NOTICES\s*=\s*'([^']*)'")
$sxM  = [regex]::Match($relTxt2, "\`$SELF_PRINTED\s*=\s*'(\d+)'")
$sdM  = [regex]::Match($relTxt2, "\`$SELF_AGGREGATED\s*=\s*'(\d+)'")
$loM  = [regex]::Match($relTxt2, "\`$SUPPOFF_LOCAL\s*=\s*'(\d+)'")
$paM  = [regex]::Match($relTxt2, "\`$SUPPOFF_PARAM\s*=\s*'(\d+)'")
# 0611. THE EIGHT-TREE SPLIT, for the same reason the total is read: the
# READMEs publish the printed and the aggregated halves of the eight trees, and
# the paragraph they sit in was WRONG -- it said 3,971 + 19,426 = 23,397, and
# the pins said 3,972 + 19,452 = 23,424. The prose had not moved since the split
# was last re-pinned, and nothing read it. A published number that is not gated
# is a number that can go missing silently.
$spM  = [regex]::Match($relTxt2, "\`$NOTICE_SPLIT_PRINTED\s*=\s*'(\d+)'")
$saM  = [regex]::Match($relTxt2, "\`$NOTICE_SPLIT_AGGREGATED\s*=\s*'(\d+)'")
# 0602. THE SOUNDINESS COUNTS, derived from the pins the family roster gate
# checks against the SOURCE. The deck is `Soundiness` (Yue Li and Tian Tan,
# Nanjing University, 2021 Fall), and its p.14 gives three verdicts whose
# difference is the CAUSE of a gap rather than its size. The README publishes
# the counts, so the counts are derived here from the same pins the roster
# gate derives them from -- one authority for a number.
$soM  = [regex]::Match($relTxt2, "\`$SOUNDINESS_SOUND\s*=\s*'(\d+)'")
$syM  = [regex]::Match($relTxt2, "\`$SOUNDINESS_SOUNDY\s*=\s*'(\d+)'")
$suM  = [regex]::Match($relTxt2, "\`$SOUNDINESS_UNSOUND\s*=\s*'(\d+)'")
$suIM = [regex]::Match($relTxt2, "\`$SOUNDINESS_UNSOUND_IDS\s*=\s*'([^']*)'")
$isaM = [regex]::Match($relTxt2, "\`$IFACE_SIG_AVAILABLE\s*=\s*'(\d+)'")
$isgM = [regex]::Match($relTxt2, "\`$IFACE_SIG_AGREES\s*=\s*'(\d+)'")
$sfdM = [regex]::Match($relTxt2, "\`$SURFACE_DECLARED\s*=\s*'(\d+)'")
$sfcM = [regex]::Match($relTxt2, "\`$SURFACE_COVERED\s*=\s*'(\d+)'")
$sfmM = [regex]::Match($relTxt2, "\`$SURFACE_MISSING\s*=\s*'(\d+)'")
# 0615. THE CORE'S OWN SURFACE ROW, derived from the PER-CORPUS pin rather
# than written out by hand. The eight-tree row is the AGGREGATE, and the
# standard library's own row is a DIFFERENT tree's measurement -- so it is
# derived from `$PINNED_SURFACE['moonbit_core']`, the same pin the corpus stage
# checks against the analyzer's own line.
#
# It used to be a LITERAL here, and that is exactly how the row went stale: the
# literal still said 1,123 / 1,076 / 47 while the pin said 1,155 / 1,075 / 80,
# and the gate was happy with the literal because the gate was checking the
# literal. A gate that checks its own copy of a number cannot notice the copy
# going stale -- so the copy is gone, and the number comes from the pin.
$coreSurfM = [regex]::Match($relTxt2, "'moonbit_core'\s*=\s*'modelled=\d+\|declared=(\d+)\|covered=(\d+)\|missing=(\d+)\|")
if (-not ($peM.Success -and $sfM.Success -and $snM.Success -and $sxM.Success -and $sdM.Success -and $loM.Success -and $paM.Success -and $spM.Success -and $saM.Success)) {
  Write-Output '  FAIL: release.ps1 no longer carries the pins this gate derives from.'
  Write-Output '        Restore them, or this gate has nothing to check the README against.'
  $fail++
  $peTotal = '?'; $sn = ''; $sx = '?'; $sd = '?'; $lo = '?'; $pa = '?'; $sp8 = '?'; $sa8 = '?'
} else {
  $peTotal = ([int]$peM.Groups[1].Value).ToString('N0')
  $sf = $sfM.Groups[1].Value
  $sn = $snM.Groups[1].Value
  $sx = $sxM.Groups[1].Value
  $sd = $sdM.Groups[1].Value
  $lo = $loM.Groups[1].Value
  $pa = $paM.Groups[1].Value
  $sp8 = ([int]$spM.Groups[1].Value).ToString('N0')
  $sa8 = ([int]$saM.Groups[1].Value).ToString('N0')
  Write-Output ('  (release.ps1 pins: notices ' + $peTotal + ', own-source files ' + $sf + ', notice table ' + (@($sn -split '\|').Count) +
                ' kinds, printed ' + $sx + ', aggregated ' + $sd +
                ', suppression off ' + $lo + ' / ' + $pa + ')')
}
if (-not ($soM.Success -and $syM.Success -and $suM.Success -and $suIM.Success)) {
  Write-Output '  FAIL: release.ps1 no longer carries the soundiness pins.'
  $fail++
  $so = '?'; $sy = '?'; $su = '?'; $suIds = ''
} else {
  $so = $soM.Groups[1].Value
  $sy = $syM.Groups[1].Value
  $su = $suM.Groups[1].Value
  $suIds = $suIM.Groups[1].Value
  Write-Output ('  (release.ps1 pins: soundiness sound ' + $so + ', soundy ' + $sy + ', unsound ' + $su + ')')
}

# 0603. THE DECK'S p.40 PAIR, derived from the pins the corpus stage checks
# against the ANALYZER'S OWN line. Two numbers, and the second one is
# meaningless without the first -- a count of agreements with no count of
# opportunities is a number about nothing.
if (-not ($isaM.Success -and $isgM.Success)) {
  Write-Output '  FAIL: release.ps1 no longer carries the iface-sig pins.'
  $fail++
  $sigAvailable = '?'; $sigAgrees = '?'
} else {
  $sigAvailable = ([int]$isaM.Groups[1].Value).ToString('N0')
  $sigAgrees = ([int]$isgM.Groups[1].Value).ToString('N0')
  Write-Output ('  (release.ps1 pins: cross-file targets ' + $sigAvailable + ', arities agreeing ' + $sigAgrees + ')')
}

# 0604. THE DECK'S p.57 QUESTION, derived from the pins the corpus stage checks
# against the ANALYZER'S OWN line. THREE NUMBERS, and the third is meaningless
# without the first two: how many methods the eight trees declare for the
# modelled types, how many of those the hand-written table holds, and how many
# it does not.
if (-not ($sfdM.Success -and $sfcM.Success -and $sfmM.Success)) {
  Write-Output '  FAIL: release.ps1 no longer carries the native-surface pins.'
  $fail++
  $surfDeclared = '?'; $surfCovered = '?'; $surfMissing = '?'
} else {
  $surfDeclared = ([int]$sfdM.Groups[1].Value).ToString('N0')
  $surfCovered = ([int]$sfcM.Groups[1].Value).ToString('N0')
  $surfMissing = ([int]$sfmM.Groups[1].Value).ToString('N0')
  Write-Output ('  (release.ps1 pins: native surface declared ' + $surfDeclared + ', covered ' + $surfCovered + ', missing ' + $surfMissing + ')')
}

# 0615. AND THE CORE'S OWN THREE NUMBERS, from the per-corpus pin.
if (-not $coreSurfM.Success) {
  Write-Output '  FAIL: release.ps1 no longer carries the moonbit_core native-surface pin.'
  $fail++
  $coreSurfDeclared = '?'; $coreSurfCovered = '?'; $coreSurfMissing = '?'
} else {
  $coreSurfDeclared = ([int]$coreSurfM.Groups[1].Value).ToString('N0')
  $coreSurfCovered = ([int]$coreSurfM.Groups[2].Value).ToString('N0')
  $coreSurfMissing = ([int]$coreSurfM.Groups[3].Value).ToString('N0')
  Write-Output ('  (release.ps1 pins: moonbit_core native surface declared ' + $coreSurfDeclared + ', covered ' + $coreSurfCovered + ', missing ' + $coreSurfMissing + ')')
}

# 0616. THE SPLIT OF THE UNVERIFIED CALL SITES, in the two pins the corpus
# stage checks against the ANALYZER's own `unverified-split` row.
#
# TWO PINS AND NOT ONE, because the READMEs publish TWO numbers: the seven
# corpora on their own, and this repository's own source on their own.
#
# AND THE FIVE REASONS HAVE TO ADD UP TO THE REMAINDER THEY SPLIT. A table
# whose rows do not add up is a list of numbers that does not split anything,
# and the analyzer's own row checks the same identity -- so this gate checks it
# too, from the pins.
$uscM = [regex]::Match($relTxt2, "\`$UNVERIFIED_SPLIT_CORPORA\s*=\s*'([^']*)'")
$useM = [regex]::Match($relTxt2, "\`$UNVERIFIED_SPLIT_EIGHT\s*=\s*'([^']*)'")
$splitReasons = @('sig-unknown','not-callable','unresolved','method','dotdot')
$splitCorp = @{}
$splitEight = @{}
$splitTree = @{}
$splitPctTreeSilent = '?'
$splitPctCorpSilent = '?'
$splitPctTreeMethod = '?'
if (-not ($uscM.Success -and $useM.Success)) {
  Write-Output '  FAIL: release.ps1 no longer carries the unverified-split pins.'
  $fail++
} else {
  foreach ($p in ($uscM.Groups[1].Value -split '\|')) {
    $kv = $p -split '='
    $splitCorp[$kv[0]] = [int]$kv[1]
  }
  foreach ($p in ($useM.Groups[1].Value -split '\|')) {
    $kv = $p -split '='
    $splitEight[$kv[0]] = [int]$kv[1]
  }
  $corpSum = 0
  $eightSum = 0
  foreach ($k in $splitReasons) {
    $corpSum += $splitCorp[$k]
    $eightSum += $splitEight[$k]
    $splitTree[$k] = $splitEight[$k] - $splitCorp[$k]
  }
  # AND THE REMAINDER ITSELF, which is not one of the five reasons -- it is what
  # they split, and the tree's own remainder is the difference between the two
  # pins' remainders.
  $splitTree['not-verified'] = $splitEight['not-verified'] - $splitCorp['not-verified']
  if ($corpSum -ne $splitCorp['not-verified']) {
    Write-Output ('  FAIL: the seven corpora split the remainder into ' + $corpSum + ' and the remainder is ' + $splitCorp['not-verified'] + '.')
    $fail++
  }
  if ($eightSum -ne $splitEight['not-verified']) {
    Write-Output ('  FAIL: the eight trees split the remainder into ' + $eightSum + ' and the remainder is ' + $splitEight['not-verified'] + '.')
    $fail++
  }
  # AND THE THREE SHARES THE READMEs PUBLISH, derived from the same pins.
  #
  # THE SILENT REASONS ARE THREE OF THE FIVE -- the two that REPORT are
  # not-callable and unresolved -- so the silent share is the other three.
  $silentReasons = @('sig-unknown','method','dotdot')
  $treeSilent = 0
  $corpSilent = 0
  foreach ($k in $silentReasons) {
    $treeSilent += $splitTree[$k]
    $corpSilent += $splitCorp[$k]
  }
  $splitPctTreeSilent = [math]::Round(100.0 * $treeSilent / $splitTree['not-verified'], 1, [System.MidpointRounding]::AwayFromZero).ToString('0.0')
  $splitPctCorpSilent = [math]::Round(100.0 * $corpSilent / $splitCorp['not-verified'], 1, [System.MidpointRounding]::AwayFromZero).ToString('0.0')
  $splitPctTreeMethod = [math]::Round(100.0 * $splitTree['method'] / $splitTree['not-verified'], 1, [System.MidpointRounding]::AwayFromZero).ToString('0.0')
  Write-Output ('  (release.ps1 pins: the seven corpora split ' + $splitCorp['not-verified'] + ', the eight trees ' + $splitEight['not-verified'] + ', this tree ' + $splitTree['not-verified'] + ')')
}

# The kind -> the label each README prints it under. The labels are PRESENTATION
# and the numbers are the MEASUREMENT, so the map lives here and the numbers
# come from the pin.
$noticeLabel = [ordered]@{
  'test declaration'          = @{ en = '`test` declaration';          zh = '`test` 声明' }
  'if expression'              = @{ en = '`if` expression';              zh = '`if` 表达式' }
  'struct declaration'         = @{ en = '`struct` declaration';         zh = '`struct` 声明' }
  'derive declaration'         = @{ en = '`derive` declaration';         zh = '`derive` 声明' }
  'enum declaration'           = @{ en = '`enum` declaration';           zh = '`enum` 声明' }
  'anonymous function literal' = @{ en = '`anonymous function literal`'; zh = '匿名函数字面量' }
  'const declaration'          = @{ en = '`const` declaration';          zh = '`const` 声明' }
  'short lambda'               = @{ en = '`short lambda`';               zh = '短 lambda' }
  'try expression'             = @{ en = '`try` expression';             zh = '`try` 表达式' }
  # 0522. A `type X = ...` alias is outside the analysed subset, so a file that
  # carries one gets a notice -- and a notice kind with no label here would make
  # the README table unable to name it.
  'type declaration'           = @{ en = '`type` declaration';           zh = '`type` 声明' }
}
$more = New-Object System.Collections.Generic.List[object]
if ($sn -ne '') {
  foreach ($part in ($sn -split '\|')) {
    $kv = $part -split '='
    $kind = $kv[0]
    if (-not $noticeLabel.Contains($kind)) {
      Write-Output ('  FAIL: the pinned notice kind "' + $kind + '" has no label in this gate.')
      $fail++
      continue
    }
    $more.Add(@{ F = 'README.md';    S = ($noticeLabel[$kind].en + ' | ' + $kv[1]); N = ('notice table: ' + $kind) })
    $more.Add(@{ F = 'README.zh.md'; S = ($noticeLabel[$kind].zh + ' | ' + $kv[1]); N = ('notice table (zh): ' + $kind) })
  }
}
$more.Add(@{ F = 'README.md';    S = ('**' + $peTotal + '**'); N = 'the notice count over the eight trees' })
$more.Add(@{ F = 'README.zh.md'; S = ('**' + $peTotal + '**'); N = 'the notice count over the eight trees (zh)' })
$more.Add(@{ F = 'README.md';    S = ('**' + $sp8 + '** of them as printed per line'); N = 'the eight-tree printed notices' })
$more.Add(@{ F = 'README.zh.md'; S = ('**' + $sp8 + '** 条算作逐行打印'); N = 'the eight-tree printed notices (zh)' })
$more.Add(@{ F = 'README.md';    S = ('**' + $sa8 + '** as aggregated'); N = 'the eight-tree aggregated notices' })
$more.Add(@{ F = 'README.zh.md'; S = ('**' + $sa8 + '** 条算作汇总'); N = 'the eight-tree aggregated notices (zh)' })
# AND THE THREE NUMBERS ADD UP, which is the claim the paragraph makes about
# itself. A split that does not add up to the total it is a split of is two
# numbers that happen to be printed next to each other.
$more.Add(@{ F = 'README.md';    S = ($sp8 + ' + ' + $sa8 + ' = ' + $peTotal); N = 'the eight-tree split adds up' })
$more.Add(@{ F = 'README.zh.md'; S = ($sp8 + ' + ' + $sa8 + ' = ' + $peTotal); N = 'the eight-tree split adds up (zh)' })
# 0602. THE SOUNDINESS COUNTS, and the three deliberate treatments. The deck's
# p.10 is the complaint this answers -- "Treatments to hard language features
# are usually omitted or only mentioned in an off-hand manner in some impl/eval
# parts in papers" -- so the README publishes the tree's own unsound choices,
# and the numbers come from the same pins the roster gate derives them from.
$more.Add(@{ F = 'README.md';    S = ('sound=' + $so + '  soundy=' + $sy + '  unsound=' + $su); N = 'the soundiness counts' })
$more.Add(@{ F = 'README.zh.md'; S = ('sound=' + $so + '  soundy=' + $sy + '  unsound=' + $su); N = 'the soundiness counts (zh)' })
foreach ($id in ($suIds -split '\|')) {
  $more.Add(@{ F = 'README.md';    S = $id; N = 'the deliberate (unsound) treatment' })
  $more.Add(@{ F = 'README.zh.md'; S = $id; N = 'the deliberate (unsound) treatment (zh)' })
}
# 0603. THE DECK'S p.40 PAIR, in the READMEs' own tables. The numbers come from
# the same pins the corpus stage checks against the analyzer's line.
$more.Add(@{ F = 'README.md';    S = ('cross-file calls whose callee the `.mbti` declares a signature for | **' + $sigAvailable + '**'); N = 'the resolvable cross-file targets' })
$more.Add(@{ F = 'README.md';    S = ('whose declared arity agrees with the argument count of the call | **' + $sigAgrees + '**'); N = 'the agreeing arities' })
$more.Add(@{ F = 'README.zh.md'; S = ('被调用者的 `.mbti` 声明了签名的数量 | **' + $sigAvailable + '**'); N = 'the resolvable cross-file targets (zh)' })
$more.Add(@{ F = 'README.zh.md'; S = ('声明的 arity 与该调用的实参个数一致的数量 | **' + $sigAgrees + '**'); N = 'the agreeing arities (zh)' })
# 0604. THE DECK'S p.57 QUESTION, in the READMEs' own tables: the hand-modelled
# native surface measured against the DECLARED one. The numbers come from the
# same pins the corpus stage checks against the analyzer's line.
$more.Add(@{ F = 'README.md';    S = ('| **the eight trees** | **' + $surfDeclared + '** | **' + $surfCovered + '** | **' + $surfMissing + '** |'); N = 'the eight-tree native surface' })
$more.Add(@{ F = 'README.md';    S = ('| `moonbit_core` — the standard library | **' + $coreSurfDeclared + '** | **' + $coreSurfCovered + '** | **' + $coreSurfMissing + '** |'); N = 'the standard library native surface row' })
$more.Add(@{ F = 'README.md';    S = ('| `async` | 10 | 0 | 10 |'); N = 'the async native surface row' })
$more.Add(@{ F = 'README.zh.md'; S = ('| **八棵树** | **' + $surfDeclared + '** | **' + $surfCovered + '** | **' + $surfMissing + '** |'); N = 'the eight-tree native surface (zh)' })
$more.Add(@{ F = 'README.zh.md'; S = ('| `moonbit_core`——标准库自己 | **' + $coreSurfDeclared + '** | **' + $coreSurfCovered + '** | **' + $coreSurfMissing + '** |'); N = 'the standard library native surface row (zh)' })
# 0616. THE SPLIT OF THE UNVERIFIED CALL SITES, in the READMEs' own tables. The
# labels are PRESENTATION and the numbers are the MEASUREMENT, so the labels
# live here and the numbers come from the two pins.
#
# AND THE WHOLE ROW IS CHECKED, not just the number: a row whose label changed
# and whose numbers did not is a different table, and a reader would be reading
# a table the gate has never seen.
if ($splitCorp.Count -gt 0) {
  $tSig = $splitTree['sig-unknown'].ToString('N0')
  $tNot = $splitTree['not-callable'].ToString('N0')
  $tUnr = $splitTree['unresolved'].ToString('N0')
  $tMet = $splitTree['method'].ToString('N0')
  $tDot = $splitTree['dotdot'].ToString('N0')
  $tRem = $splitTree['not-verified'].ToString('N0')
  $cSig = $splitCorp['sig-unknown'].ToString('N0')
  $cNot = $splitCorp['not-callable'].ToString('N0')
  $cUnr = $splitCorp['unresolved'].ToString('N0')
  $cMet = $splitCorp['method'].ToString('N0')
  $cDot = $splitCorp['dotdot'].ToString('N0')
  $cRem = $splitCorp['not-verified'].ToString('N0')
  $more.Add(@{ F = 'README.md';    S = ('| a method call — the lens has no signature for a method | **' + $tMet + '** | **' + $cMet + '** | silent |'); N = 'the split: method calls (en)' })
  $more.Add(@{ F = 'README.md';    S = ('| a callee that is not callable | **' + $tNot + '** | **' + $cNot + '** | reports (`MSA-008`) |'); N = 'the split: not-callable (en)' })
  $more.Add(@{ F = 'README.md';    S = ('| a cross-file value whose signature was never read | **' + $tSig + '** | **' + $cSig + '** | silent |'); N = 'the split: sig-unknown (en)' })
  $more.Add(@{ F = 'README.md';    S = ('| a `..` chain link — the lens has no signature for it | **' + $tDot + '** | **' + $cDot + '** | silent |'); N = 'the split: dotdot (en)' })
  $more.Add(@{ F = 'README.md';    S = ('| a name that did not resolve at all | **' + $tUnr + '** | **' + $cUnr + '** | reports (`MSA-002`) |'); N = 'the split: unresolved (en)' })
  $more.Add(@{ F = 'README.md';    S = ('| **the remainder** | **' + $tRem + '** | **' + $cRem + '** | |'); N = 'the split: the remainder (en)' })
  $more.Add(@{ F = 'README.zh.md'; S = ('| 方法调用——这个透镜没有方法的签名 | **' + $tMet + '** | **' + $cMet + '** | 哑 |'); N = 'the split: method calls (zh)' })
  $more.Add(@{ F = 'README.zh.md'; S = ('| 被调者不可调用 | **' + $tNot + '** | **' + $cNot + '** | 报（`MSA-008`） |'); N = 'the split: not-callable (zh)' })
  $more.Add(@{ F = 'README.zh.md'; S = ('| 跨文件的值，签名从来没读过 | **' + $tSig + '** | **' + $cSig + '** | 哑 |'); N = 'the split: sig-unknown (zh)' })
  $more.Add(@{ F = 'README.zh.md'; S = ('| `..` 链——这个透镜也没有它的签名 | **' + $tDot + '** | **' + $cDot + '** | 哑 |'); N = 'the split: dotdot (zh)' })
  $more.Add(@{ F = 'README.zh.md'; S = ('| 名字压根没解析出来 | **' + $tUnr + '** | **' + $cUnr + '** | 报（`MSA-002`） |'); N = 'the split: unresolved (zh)' })
  $more.Add(@{ F = 'README.zh.md'; S = ('| **剩下部分** | **' + $tRem + '** | **' + $cRem + '** | |'); N = 'the split: the remainder (zh)' })
  # AND THE THREE SHARES, and the eight-tree totals the prose quotes.
  $more.Add(@{ F = 'README.md';    S = ('**' + $splitPctTreeSilent + ' %** of this tree''s ' + $tRem + ' unverified call sites are silent'); N = 'the share of the tree''s remainder that is silent' })
  $more.Add(@{ F = 'README.zh.md'; S = ('**' + $splitPctTreeSilent + ' %** 是哑的'); N = 'the share of the tree''s remainder that is silent (zh)' })
  $more.Add(@{ F = 'README.md';    S = ('corpora''s ' + $cRem + ' are'); N = 'the share of the corpora''s remainder that is silent' })
  $more.Add(@{ F = 'README.zh.md'; S = ('语料那 ' + $cRem + ' 个里 **' + $splitPctCorpSilent + ' %**'); N = 'the share of the corpora''s remainder that is silent (zh)' })
  $more.Add(@{ F = 'README.md';    S = ('**' + $splitPctTreeMethod + ' %** of this tree''s remainder is one reason'); N = 'the share of the tree''s remainder that is one reason' })
  $more.Add(@{ F = 'README.zh.md'; S = ('本仓库剩下部分的 **' + $splitPctTreeMethod + ' %** 是老那句话从来没点过的同一个原因'); N = 'the share of the tree''s remainder that is one reason (zh)' })
  $more.Add(@{ F = 'README.md';    S = ('**' + $splitEight['not-verified'].ToString('N0') + '** unverified call sites, of which **' + $splitEight['method'].ToString('N0') + '** are method calls'); N = 'the eight-tree remainder and its method count' })
  $more.Add(@{ F = 'README.zh.md'; S = ('是 **' + $splitEight['not-verified'].ToString('N0') + '** 个没被验证的调用点，其中 **' + $splitEight['method'].ToString('N0') + '** 个是方法调用'); N = 'the eight-tree remainder and its method count (zh)' })
  # 0618. AND THE SAME FIVE REASONS, IN `SKILL.md`. The skill file ships to the
  # registry and a reader is sent to it, and it carried the sentence 0616 REFUTED --
  # that `not-verified` splits into TWO reasons -- next to a self-measurement eight
  # releases old. Nothing read it: the READMEs' numbers are derived from the pins, and
  # `SKILL.md` was checked for exactly ONE thing, the `moonx ... @version` command.
  #
  # THE SENTENCES ARE CHECKED WHOLE. A sentence whose number changed and whose wording
  # did not is a DIFFERENT claim, and a reader would be reading a claim the gate has
  # never seen -- so the fragment carries the number AND the words around it.
  $more.Add(@{ F = 'SKILL.md'; S = ('a method call (**' + $tMet + '** on this tree)'); N = 'SKILL.md: the split, method calls' })
  $more.Add(@{ F = 'SKILL.md'; S = ('that is not callable (**' + $tNot + '**, reported as `MSA-008`)'); N = 'SKILL.md: the split, not-callable' })
  $more.Add(@{ F = 'SKILL.md'; S = ('signature was never read (**' + $tSig + '**)'); N = 'SKILL.md: the split, sig-unknown' })
  $more.Add(@{ F = 'SKILL.md'; S = ('a `..` chain link (**' + $tDot + '**)'); N = 'SKILL.md: the split, dotdot' })
  $more.Add(@{ F = 'SKILL.md'; S = ('did not resolve at all (**' + $tUnr + '**, reported as `MSA-002`)'); N = 'SKILL.md: the split, unresolved' })
  $more.Add(@{ F = 'SKILL.md'; S = ('the silent three are **' + $splitPctTreeSilent + ' %** of the'); N = 'SKILL.md: the share of the tree remainder that is silent' })
  # AND THE ROW ITSELF, with the RAW digits the analyzer prints -- the prose carries
  # the thousands separators, and the row does not.
  $skillSplit = 'METRICS' + "`t" + 'unverified-split' + "`t" +
                'sig-unknown=' + $splitTree['sig-unknown'] + "`t" +
                'not-callable=' + $splitTree['not-callable'] + "`t" +
                'unresolved=' + $splitTree['unresolved'] + "`t" +
                'method=' + $splitTree['method'] + "`t" +
                'dotdot=' + $splitTree['dotdot'] + "`t" +
                'sum=' + $splitTree['not-verified'] + "`t" +
                'not-verified=' + $splitTree['not-verified']
  $more.Add(@{ F = 'SKILL.md'; S = $skillSplit; N = 'SKILL.md: the unverified-split metrics row' })
}
$more.Add(@{ F = 'README.zh.md'; S = ('| `async` | 10 | 0 | 10 |'); N = 'the async native surface row (zh)' })
$more.Add(@{ F = 'README.md';    S = ('**' + ([int]$lo).ToString('N0') + '**'); N = 'the suppression-off UnusedLocal count' })
$more.Add(@{ F = 'README.md';    S = ('**' + ([int]$pa).ToString('N0') + '**'); N = 'the suppression-off UnusedParam count' })
$more.Add(@{ F = 'README.zh.md'; S = ('**' + ([int]$lo).ToString('N0') + '**'); N = 'the suppression-off UnusedLocal count (zh)' })
$more.Add(@{ F = 'README.zh.md'; S = ('**' + ([int]$pa).ToString('N0') + '**'); N = 'the suppression-off UnusedParam count (zh)' })
# THE SPLIT. 0506 changed what the two numbers ARE: they used to be the
# expression-level and declaration-level notices, worked out from the SHAPE of
# each message, and they are now the notices the analyzer itself printed and
# the ones it itself aggregated -- the split the analyzer's own geometry
# makes. The old proxy called a top-level `short lambda` expression-level,
# which it is not: it is outside every function's extent, and it hides
# nothing.
$more.Add(@{ F = 'README.md';    S = ('**' + $sx + '** of them sit inside'); N = 'the printed notices' })
$more.Add(@{ F = 'README.md';    S = ('**' + $sd + '** sit outside'); N = 'the aggregated notices' })
$more.Add(@{ F = 'README.zh.md'; S = ('**' + $sx + '** 条落在某个函数体的范围内'); N = 'the printed notices (zh)' })
$more.Add(@{ F = 'README.zh.md'; S = ('**' + $sd + '** 条在所有函数体之外'); N = 'the aggregated notices (zh)' })
# THE OWN-SOURCE FILE COUNT, DERIVED FROM THE PIN. It used to be the literal
# `178` written into THIS gate, which is a number that can only ever agree with
# itself -- the release gate measured the count and never compared it with
# anything, so the count moved twice (178 -> 179 -> 181) with nothing
# objecting. It is a pin in release.ps1 now, and this gate asks only what the
# pin says.
$more.Add(@{ F = 'README.md';    S = ('(' + $sf + ' files)'); N = 'the own-source file count' })
$more.Add(@{ F = 'README.zh.md'; S = ($sf + ' 个文件'); N = 'the own-source file count (zh)' })
# 0618. THE `--metrics` BLOCK, IN `SKILL.md`. The skill file shows the block as the
# EXAMPLE of what the output looks like, and the copy in that document had been
# describing THIS tree as 194 files with an 8.2 % adequacy for eight releases. The row
# is pinned in `release.ps1` now, and the LINES are checked whole here -- a line whose
# numbers changed and whose shape did not is a DIFFERENT line, and a reader would be
# reading a block the gate has never seen.
#
# AND `SKILL.md`'s OWN-SOURCE COUNT AND ADEQUACY, which are the same two numbers in
# prose rather than in the block.
$scM = [regex]::Match($relTxt2, "\`$SELF_CALLS\s*=\s*'([^']*)'")
$suM = [regex]::Match($relTxt2, "\`$SELF_UNCHECKED\s*=\s*'([^']*)'")
if (-not ($scM.Success -and $suM.Success)) {
  Write-Output '  FAIL: release.ps1 no longer carries the call-metrics pins.'
  $fail++
} else {
  $callFields = @($scM.Groups[1].Value -split '\|')
  $more.Add(@{ F = 'SKILL.md'; S = ('METRICS' + "`t" + 'calls' + "`t" + $callFields[0] + "`t" + $callFields[1] + "`t" + $callFields[2] + "`t" + $callFields[3]); N = 'SKILL.md: the calls metrics row' })
  $more.Add(@{ F = 'SKILL.md'; S = ('METRICS' + "`t" + 'read' + "`t" + 'files=' + $sf + "`t" + 'parsed=' + $sf); N = 'SKILL.md: the read metrics row' })
  $more.Add(@{ F = 'SKILL.md'; S = ($sf + ' files, every'); N = 'SKILL.md: the own-source file count' })
  $more.Add(@{ F = 'SKILL.md'; S = ('a call-argument adequacy of ' + ($callFields[3] -replace '^checked-share=', '')); N = 'SKILL.md: the call-argument adequacy' })
  # THE TWO UNITS. The row counts a call ONCE and the SUMMARY counts a VISIT -- a call
  # in a block's tail position is typed twice -- so the naive subtraction of one from
  # the other is NEGATIVE, and that negative number is the tell `SKILL.md` uses to show
  # the two are two units and not one arithmetic identity. The value it quoted was -16,
  # eight releases old; it is -100 today.
  $naiveSites = [int]($callFields[0] -replace '^sites=', '')
  $naiveChecked = [int]($callFields[1] -replace '^checked=', '')
  $naiveUnchecked = [int]$suM.Groups[1].Value
  $naive = $naiveSites - $naiveChecked - $naiveUnchecked
  # THE MINUS SIGN IS THE DOCUMENT'S, not the shell's: the text writes U+2212.
  $naiveStr = ([string]$naive).Replace('-', [string][char]0x2212)
  $more.Add(@{ F = 'SKILL.md'; S = ('subtraction `sites - checked - unchecked` is **' + $naiveStr + '**'); N = 'SKILL.md: the naive subtraction' })
  # AND THE NOTICE TOTAL, from the two halves the release gate already pins.
  $selfTotal = [int]$sxM.Groups[1].Value + [int]$sdM.Groups[1].Value
  $more.Add(@{ F = 'SKILL.md'; S = ('METRICS' + "`t" + 'findings' + "`t" + 'total=' + $selfTotal); N = 'SKILL.md: the findings metrics row' })
  $more.Add(@{ F = 'SKILL.md'; S = ('METRICS' + "`t" + 'family' + "`t" + 'MSA-001' + "`t" + 'ParseError' + "`t" + 'severity=error' + "`t" + 'high=0' + "`t" + 'low=0' + "`t" + 'undecided=' + $selfTotal + "`t" + 'total=' + $selfTotal); N = 'SKILL.md: the family metrics row' })
}
# 0618. AND THE REFUTED SENTENCE MUST NOT COME BACK. The five fragments above are
# PRESENCE checks, so a document that kept them AND re-asserted the old two-reason
# account would pass every one of them -- and would be teaching two contradictory
# stories about the same number. So the sentence 0616 refuted is named here, VERBATIM,
# as something that must NOT be there.
#
# IT IS NAMED, NOT DESCRIBED. A guard that says "no old wording" and then looks for a
# paraphrase of the old wording is a guard that can be fooled by a rephrase, and the
# rephrase is the easy way in.
$refutedSentence = '`not-verified` splits into a callee that resolved to something not callable'
$skillPath = Join-Path $root 'SKILL.md'
$skillTxt = [System.IO.File]::ReadAllText($skillPath, [Text.Encoding]::UTF8)
if ($skillTxt.Contains($refutedSentence)) {
  Write-Output ('  FAIL: SKILL.md carries the sentence 0616 refuted: ' + $refutedSentence)
  $fail++
} else {
  Write-Output '  SKILL.md does not carry the refuted two-reason sentence  OK'
}
foreach ($e in $more) {
  $p = Join-Path $root $e.F
  $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $ok = $txt.Contains($e.S)
  Write-Output ("  {0,-14} {1,-34} {2}" -f $e.F, $e.N, $(if ($ok) { 'OK' } else { 'MISSING: ' + $e.S }))
  if (-not $ok) { $fail++ }
}

# --- the SSA COST, DERIVED FROM THE PIN ---------------------------------------
#
# The READMEs quote the SSA cost of this project's own source TWICE -- once in
# prose and once in a sample output line -- and BOTH copies were written once, at
# 0572, and never re-measured. The pin moved at 0573 and again at 0595, and the
# READMEs kept publishing the numbers that were true when the paragraph was
# written. MEASURED, the drift was 32 files (208 -> 240 -> 242), and the two copies
# did not even agree WITH EACH OTHER: the sample line said `declined=5080` and the
# prose said "4,979 of them".
#
# => THE SAME VERDICT AS THE PARAGRAPH ABOVE: A NUMBER WRITTEN DOWN TWICE IS A
# NUMBER THAT WILL DISAGREE WITH ITSELF. So the SSA cost is DERIVED from the pin
# here, and the READMEs have to say what the pin says.
$ssaM = [regex]::Match($relTxt2, "\`$SSA_COST\s*=\s*'([^']*)'")
if (-not $ssaM.Success) {
  Write-Output '  FAIL: release.ps1 no longer carries the $SSA_COST pin this gate derives from.'
  Write-Output '        Restore it, or this gate has nothing to check the READMEs against.'
  $fail++
} else {
  $ssa = @{}
  foreach ($part in ($ssaM.Groups[1].Value -split '\|')) {
    $kv = $part -split '='
    $ssa[$kv[0]] = $kv[1]
  }
  $n0 = { param([string]$k) ([int]$ssa[$k]).ToString('N0') }
  $ssaLine = ('SSA-COST files=' + $ssa['files'] + ' unreadable=' + $ssa['unreadable'] +
              ' functions=' + $ssa['functions'] + ' converted=' + $ssa['converted'] +
              ' partial=' + $ssa['partial'] + ' declined=' + $ssa['declined'])
  $ssaExpect = @(
    @{ F = 'README.md';    S = $ssaLine; N = 'the SSA cost line' }
    @{ F = 'README.md';    S = ($ssa['files'] + ' files, ' + (& $n0 'functions') + ' functions, ' + (& $n0 'instructions') + ' instructions of 3AC'); N = 'the SSA cost, the coverage' }
    @{ F = 'README.md';    S = ('**' + (& $n0 'variables') + '** variables becoming **' + (& $n0 'versions') + '** versions'); N = 'the SSA cost, the variables and the versions' }
    @{ F = 'README.md';    S = ('**' + (& $n0 'phis') + '** phi-functions and **' + (& $n0 'copies') + '** copies'); N = 'the SSA cost, the phi-functions and the copies' }
    @{ F = 'README.md';    S = ('lowering declined (' + (& $n0 'declined')); N = 'the SSA cost, the declined statements' }
    @{ F = 'README.zh.md'; S = $ssaLine; N = 'the SSA cost line (zh)' }
    @{ F = 'README.zh.md'; S = ($ssa['files'] + ' 个文件、' + (& $n0 'functions') + ' 个函数、' + (& $n0 'instructions') + ' 条三地址码指令'); N = 'the SSA cost, the coverage (zh)'; Tight = $true }
    @{ F = 'README.zh.md'; S = ('**' + (& $n0 'variables') + '** 个变量变成 **' + (& $n0 'versions') + '** 个版本、**' + (& $n0 'phis') + '** 个 φ 函数、'); N = 'the SSA cost, the variables and the versions (zh)'; Tight = $true }
    @{ F = 'README.zh.md'; S = ('**' + (& $n0 'copies') + '** 条拷贝'); N = 'the SSA cost, the copies (zh)'; Tight = $true }
    @{ F = 'README.zh.md'; S = ('（' + (& $n0 'declined') + ' 条'); N = 'the SSA cost, the declined statements (zh)'; Tight = $true }
  )
  foreach ($e in $ssaExpect) {
    $p = Join-Path $root $e.F
    $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
    # THE WHITESPACE IS NORMALIZED, because the READMEs WRAP their prose and the
    # sample line is separated by TABS -- and a check that cannot match a wrapped
    # sentence is a check that fails on the wrapping and not on the number.
    $flat = [regex]::Replace($txt, '\s+', ' ')
    $ok = $flat.Contains($e.S)
    # AND THE CHINESE PROSE IS COMPARED WITH THE WHITESPACE REMOVED, because the
    # Chinese sentence WRAPS MID-PHRASE and Chinese has no meaningful spaces: the
    # needle "242 个文件、1,349 个函数" is split across a line break in the file,
    # so the collapsed form still carries a space the file does not have.
    # MEASURED: this check failed on exactly that, which is why it is here.
    if (-not $ok -and $e.ContainsKey('Tight')) {
      $ok = ([regex]::Replace($txt, '\s+', '')).Contains([regex]::Replace($e.S, '\s+', ''))
    }
    Write-Output ("  {0,-14} {1,-34} {2}" -f $e.F, $e.N, $(if ($ok) { 'OK' } else { 'MISSING: ' + $e.S }))
    if (-not $ok) { $fail++ }
  }
}


# --- 6  the stages the release gate RUNS, and the README NAMES --------------------
#
# The READMEs enumerate what `_verify/release.ps1` runs. That enumeration was kept
# BY HAND, and it drifted: the stages the 0505-0508 increments added -- the family
# roster, the three bandit transfers, the confidence demotion -- were never named,
# so a reader could not find the stage that checks the very thing the READMEs
# document. A reader who cannot find the gate that proves a claim cannot tell
# whether the claim is proven.
#
# So the list is DERIVED from release.ps1, and the READMEs have to name every one
# of them. That is what makes it CHECKED rather than ASSERTED: a stage added to
# the gate and not named in the README makes THIS gate red, instead of quietly
# widening what the gate does.
#
# The derivation is the one the release gate's own summary table is built from,
# minus the mutation gates (87 of them, counted by check_gate_roster.ps1) and
# minus the self-test stages, which only run under -SelfTest. It was checked
# against the gate's own output: the names derived here are the names the gate
# printed, one for one.
Write-Output '=== 6. the release gate runs the stages the READMEs name ==='
$relPath = Join-Path $root '_verify\release.ps1'
$relTxt = [System.IO.File]::ReadAllText($relPath, [System.Text.Encoding]::UTF8)
$stageNames = New-Object System.Collections.Generic.List[string]
foreach ($m in [regex]::Matches($relTxt, "(?m)^[ \t]*Stage[ \t]+'((?:[^']|'')+)'")) {
  # A doubled quote inside a PowerShell single-quoted string is an escaped quote.
  $n = $m.Groups[1].Value -replace "''", "'"
  if ($n -like 'selftest:*') { continue }
  if ($n -like 'mutation gate *') { continue }
  $stageNames.Add($n)
}
# The three test targets are staged in a loop, and the harness self-test names
# its stage through a variable. Both are stages the gate runs, so both are
# stages the README has to name.
foreach ($t in @('js','wasm','wasm-gc')) { $stageNames.Add("moon test --target " + $t) }
foreach ($m in [regex]::Matches($relTxt, "(?m)^[ \t]*\$stageName[ \t]*=[ \t]*'((?:[^']|'')+)'")) {
  $stageNames.Add(($m.Groups[1].Value -replace "''", "'"))
}
$stageNames = @($stageNames | Select-Object -Unique)
Write-Output ('  the release gate runs ' + $stageNames.Count + ' stages besides the mutation gates')
foreach ($f in @('README.md','README.zh.md')) {
  $p = Join-Path $root $f
  $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $missing = @()
  foreach ($n in $stageNames) { if (-not $txt.Contains($n)) { $missing += $n } }
  if ($missing.Count -eq 0) {
    Write-Output ("  {0,-14} names all {1} stages  OK" -f $f, $stageNames.Count)
  } else {
    Write-Output ("  {0,-14} MISSING {1} stage name(s):" -f $f, $missing.Count)
    foreach ($n in $missing) { Write-Output ('      ' + $n) }
    $fail += $missing.Count
  }
}

Write-Output ''
Write-Output '=== 7. the family id tables name every family the code has ==='
# WHY THIS CHECK EXISTS, AND WHAT IT COSTED TO LEARN. The READMEs publish the
# family roster as a TABLE -- an id and a name per family -- and for a whole
# release that table was missing `MSA-015` (`DeadStore`), a family that exists
# in the code and fires on real code. Nothing said so, because every other gate
# compared the code's roster with ITSELF: `check_family_roster.ps1` reads
# `Family::id` and `family_by_id` out of `src/core/core.mbt` and checks that
# they are exact inverses, and that is a real check -- but it cannot see a table
# in a README that is not in the code. The published table and the code's roster
# were two tables written down twice, and nothing compared THEM.
#
# So the comparison is made here, and the roster comes from THE CODE rather than
# from a list written down here: `all_families()` is read out of
# `src/core/core.mbt`, along with each family's id and name. A family added to
# the code and forgotten in the README is then a failure with the family's own
# name in the message -- which is the difference between a gate failure and a
# reader's discovery.
#
# THE MATCHER IS THE TABLE ROW, not the whole document. The ids and the names
# appear in prose too (`--explain MSA-011`, the `nosec` paragraphs), and a
# matcher over the whole file would count those as table rows and pass a table
# that is missing a family. So the rows are the lines that look like table
# rows: a pipe, an `MSA-NNN` in backticks, and a name in backticks.
#
# The check is in BOTH directions, because a table with a family that does not
# exist is just as wrong as a table missing one -- and a stale row is how a
# renamed family survives in the published document.
$coreTxt = [System.IO.File]::ReadAllText((Join-Path $root 'src\core\core.mbt'), [System.Text.Encoding]::UTF8)
# The id table: `FParse => "MSA-001"` and the name table: `FParse => "ParseError"`.
#
# BOTH ARE SCOPED TO THEIR OWN FUNCTION, and the scoping is not tidiness. The
# first version of this check matched `=> "..."` over the WHOLE file, and it
# picked up `merge_group`'s arms as well -- `FUndefinedName => "undef"` and
# `FCondBool => "cond"` -- so the roster it built said the family `UndefinedName`
# was named "undef" and the gate reported the README's own correct row as a
# mismatch. A matcher that is too wide produces a FALSE failure, and a gate that
# fails on a true statement is a gate that gets disabled.
$idM = [regex]::Match($coreTxt, '(?s)pub fn Family::id\(self : Family\)\s*->\s*String\s*\{(.*?)\n\}')
$nameM = [regex]::Match($coreTxt, '(?s)pub fn Family::name\(self : Family\)\s*->\s*String\s*\{(.*?)\n\}')
if (-not $idM.Success -or -not $nameM.Success) {
  Write-Output '  FAIL: could not read Family::id / Family::name out of src/core/core.mbt -- the check has nothing to compare against.'
  $fail++
}
$idOf = @{}
foreach ($m in [regex]::Matches($idM.Groups[1].Value, '(?m)^\s*(F[A-Za-z0-9]+)\s*=>\s*"(MSA-\d+)"')) {
  $idOf[$m.Groups[1].Value] = $m.Groups[2].Value
}
$nameOf = @{}
foreach ($m in [regex]::Matches($nameM.Groups[1].Value, '(?m)^\s*(F[A-Za-z0-9]+)\s*=>\s*"([A-Za-z][A-Za-z0-9]*)"')) {
  $nameOf[$m.Groups[1].Value] = $m.Groups[2].Value
}
# THE ROSTER, read from `all_families()`, so the expectation is the CODE's list
# and not a copy of it. The function's body is a bracketed list of the tags.
$rosterM = [regex]::Match($coreTxt, '(?s)pub fn all_families\(\)\s*->\s*Array\[Family\]\s*\{(.*?)\}')
if (-not $rosterM.Success) {
  Write-Output '  FAIL: could not read all_families() out of src/core/core.mbt -- the check has nothing to compare against.'
  $fail++
} else {
  $roster = @()
  foreach ($m in [regex]::Matches($rosterM.Groups[1].Value, 'F[A-Za-z0-9]+')) { $roster += $m.Value }
  Write-Output ('  the code has ' + $roster.Count + ' families')
  $expected = @()
  foreach ($tag in $roster) {
    if (-not $idOf.ContainsKey($tag) -or -not $nameOf.ContainsKey($tag)) {
      Write-Output ('  FAIL: ' + $tag + ' has no id or no name in core.mbt, so the READMEs cannot be checked against it.')
      $fail++
    } else {
      $expected += ($idOf[$tag] + '|' + $nameOf[$tag])
    }
  }
  foreach ($f in @('README.md','README.zh.md')) {
    $p = Join-Path $root $f
    $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
    $lines = $txt -split "`r?`n"
    $rows = @()
    foreach ($l in $lines) {
      # A table row: it starts with a pipe, and it carries an `MSA-NNN` in
      # backticks. Every cell of the row is read, so a two-pair row counts both
      # of its families.
      if ($l -notmatch '^\s*\|') { continue }
      foreach ($m in [regex]::Matches($l, '`(MSA-\d+)`\s*\|\s*`([A-Za-z][A-Za-z0-9]*)`')) {
        $rows += ($m.Groups[1].Value + '|' + $m.Groups[2].Value)
      }
    }
    $missing = @($expected | Where-Object { $rows -notcontains $_ })
    $extra = @($rows | Where-Object { $expected -notcontains $_ })
    if ($missing.Count -eq 0 -and $extra.Count -eq 0) {
      Write-Output ("  {0,-14} names all {1} families  OK" -f $f, $expected.Count)
    } else {
      if ($missing.Count -gt 0) {
        Write-Output ("  {0,-14} MISSING {1} family row(s):" -f $f, $missing.Count)
        foreach ($m in $missing) { Write-Output ('      ' + $m) }
        $fail += $missing.Count
      }
      if ($extra.Count -gt 0) {
        Write-Output ("  {0,-14} has {1} row(s) the code does not have:" -f $f, $extra.Count)
        foreach ($e in $extra) { Write-Output ('      ' + $e) }
        $fail += $extra.Count
      }
    }
  }
}

Write-Output ''
Write-Output '=== 8. the NARRATIVE course map names only what this tree has ==='
# WHY THIS CHECK EXISTS. Chapter 0564 of `_verify/NARRATIVE.md` maps the course's own
# assignment list (the lecture's p.73) onto this tree: for each assignment it names
# the MODULE that implements it and the FAMILY it speaks for. That map is a claim
# ABOUT THE TREE, and a claim about the tree that only prose carries is a claim
# that rots -- rename a module, drop a family, and the map goes on saying the tree
# has it.
#
# So the map is read here, and every path and every family id it names is checked
# against the tree: the paths must exist, and the ids must be in the CODE's roster
# -- read in section 7 out of `src/core/core.mbt`, not written down a second time.
$narrPath2 = Join-Path $root '_verify\NARRATIVE.md'
$narrTxt2 = [System.IO.File]::ReadAllText($narrPath2, [System.Text.Encoding]::UTF8)
# THE CAPTURE IS BOUNDED TO THE CHAPTER, and it was not. The regex was
# `(?ms)^## 0564:.*\z`, and `\z` is THE END OF THE FILE -- so the 'course map'
# this gate checks was chapter 0564 AND EVERY CHAPTER AFTER IT. The check
# still verified every path it saw, so it never failed on its own terms; but
# the number it REPORTED was not the map's number. MEASURED: chapter 0564's own
# map names 14 files and 4 family ids, and the gate reported 53 files -- the
# 39 extra ones are paths mentioned in the chapters that came after it, which
# is why the count grew when this increment added three files it had nothing
# to do with.
#
# A gate that says how much it checked, and checks something else, is a green
# row that measured nothing. So the capture stops at the next chapter heading.
$chapM = [regex]::Match($narrTxt2, '(?ms)^## 0564:.*?(?=^## \d{4}:|\z)')
if (-not $chapM.Success) {
  Write-Output '  FAIL: the NARRATIVE has no chapter 0564, so the course map cannot be checked.'
  $fail++
} else {
  $chap = $chapM.Value
  $paths = @()
  foreach ($pm in [regex]::Matches($chap, 'src/[A-Za-z0-9_/]+\.mbt')) {
    $p2 = $pm.Value -replace '/', '\'
    if ($paths -notcontains $p2) { $paths += $p2 }
  }
  $badPaths = @()
  foreach ($p2 in $paths) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $p2))) { $badPaths += $p2 }
  }
  $ids = @()
  foreach ($im in [regex]::Matches($chap, 'MSA-\d{3}')) {
    if ($ids -notcontains $im.Value) { $ids += $im.Value }
  }
  $knownIds = @($idOf.Values | Sort-Object -Unique)
  $badIds = @($ids | Where-Object { $knownIds -notcontains $_ })
  if ($badPaths.Count -eq 0 -and $badIds.Count -eq 0) {
    Write-Output ("  the 0564 course map names {0} file(s) and {1} family id(s), and every one of them exists  OK" -f $paths.Count, $ids.Count)
  } else {
    if ($badPaths.Count -gt 0) {
      Write-Output ("  the 0564 course map names {0} file(s) that do not exist:" -f $badPaths.Count)
      foreach ($b in $badPaths) { Write-Output ('      ' + $b) }
      $fail += $badPaths.Count
    }
    if ($badIds.Count -gt 0) {
      Write-Output ("  the 0564 course map names {0} family id(s) the code does not have:" -f $badIds.Count)
      foreach ($b in $badIds) { Write-Output ('      ' + $b) }
      $fail += $badIds.Count
    }
  }
}

Write-Output ''
Write-Output ''
Write-Output '=== 9. the NARRATIVE has HEADINGS, and no family says the same thing twice ==='
# WHY THIS CHECK EXISTS. Two defects, ONE cause, and NEITHER was caught by a gate:
#
#   1. The patch that installs an increment's prose was applied TWICE to
#      `src/core/core.mbt`, so the paragraph about the deck's derived-value boundary
#      sat in the `FTaintFlow` arm of `Family::excluded` TWICE -- 586 characters,
#      twice. The file compiled, the notice pins did not move (a string literal is
#      not a notice), and the text read as though it were explaining itself twice.
#   2. The same double-apply left chapters 0587 and 0588 without their `## `
#      prefix, so they rendered as body text and the record silently lost two of
#      its chapters from its own structure.
#
# A defect written only in prose is unfixed, and these two WERE prose: the notice
# pins count NOTICES, the family tables count FAMILIES, and nothing counted HEADINGS
# or SENTENCES. So they are counted now.
#
#   9a. every chapter in the NARRATIVE is a level-2 heading -- no line at column 0
#       may start with `NNNN: ` -- and no chapter number is used twice. The COUNT
#       is pinned in `release.ps1` as $NARRATIVE_CHAPTERS and derived here, the same
#       way the corpus numbers are: ONE place carries the number, and this gate
#       asks whether the file agrees with it.
#   9b. no family's boundary text repeats a sentence. A boundary text is prose, and
#       prose that says the same thing twice is a paste that went in twice.
$narrLines = [System.IO.File]::ReadAllLines($narrPath2, [System.Text.Encoding]::UTF8)
$lostHeads = @()
$chapSeen = @{}
$dupChaps = @()
$chapCount = 0
foreach ($ln in $narrLines) {
  $m = [regex]::Match($ln, '^##\s+(\d{4}):\s+\S')
  if ($m.Success) {
    $chapCount++
    $c = $m.Groups[1].Value
    if ($chapSeen.ContainsKey($c)) { $dupChaps += $c } else { $chapSeen[$c] = $true }
    continue
  }
  $m2 = [regex]::Match($ln, '^(\d{4}):\s+[A-Z]')
  if ($m2.Success) { $lostHeads += $ln.Trim() }
}
$ncM = [regex]::Match($relTxt2, "\`$NARRATIVE_CHAPTERS\s*=\s*'(\d+)'")
if (-not $ncM.Success) {
  Write-Output '  FAIL: release.ps1 no longer carries the $NARRATIVE_CHAPTERS pin.'
  $fail++
} elseif ([int]$ncM.Groups[1].Value -ne $chapCount) {
  Write-Output ("  FAIL: the NARRATIVE carries {0} chapter heading(s) and the pin says {1}." -f $chapCount, $ncM.Groups[1].Value)
  $fail++
} else {
  Write-Output ("  the NARRATIVE carries {0} chapter heading(s), and the pin says {0}  OK" -f $chapCount)
}
if ($lostHeads.Count -gt 0) {
  Write-Output ('  FAIL: {0} chapter heading(s) carry no `## ` prefix, so they render as body text:' -f $lostHeads.Count)
  foreach ($h in $lostHeads) { Write-Output ('      ' + $h) }
  $fail += $lostHeads.Count
} elseif ($dupChaps.Count -gt 0) {
  Write-Output ("  FAIL: {0} chapter number(s) are used twice:" -f $dupChaps.Count)
  foreach ($d in $dupChaps) { Write-Output ('      ' + $d) }
  $fail += $dupChaps.Count
} else {
  Write-Output '  every chapter is a `## ` heading, and no chapter number is used twice  OK'
}
$corePath = Join-Path $root 'src\core\core.mbt'
$coreTxt = [System.IO.File]::ReadAllText($corePath, [System.Text.Encoding]::UTF8)
$armM = [regex]::Matches($coreTxt, '(?ms)^    (F[A-Za-z0-9]+) =>\r?\n      ("(?:[^"\\]|\\.)*")')
$repSents = @()
foreach ($a in $armM) {
  $fam = $a.Groups[1].Value
  $body = $a.Groups[2].Value
  if ($body.StartsWith('"')) { $body = $body.Substring(1) }
  if ($body.EndsWith('"')) { $body = $body.Substring(0, $body.Length - 1) }
  $body = $body -replace '\\"', '"'
  $sentSeen = @{}
  foreach ($s in ([regex]::Split($body, '(?<=[.!?]) (?=[A-Z`"])'))) {
    $st = $s.Trim()
    if ($st.Length -le 20) { continue }
    $k = $st.Substring(0, [Math]::Min(90, $st.Length))
    if ($sentSeen.ContainsKey($k)) { $repSents += ($fam + ' -- ' + $k) } else { $sentSeen[$k] = $true }
  }
}
if ($repSents.Count -eq 0) {
  Write-Output ("  no family's boundary text repeats a sentence ({0} family arm(s) read)  OK" -f $armM.Count)
} else {
  Write-Output ("  FAIL: {0} repeated sentence(s) in family boundary text(s):" -f $repSents.Count)
  foreach ($rs in $repSents) { Write-Output ('      ' + $rs) }
  $fail += $repSents.Count
}

#   9c. NO README SECTION IS PASTED IN TWICE, and this is the THIRD defect of the
#       same family that no gate could see.
#
#       0587 applied a README patch that inserted a section which was ALREADY THERE,
#       and the English README has carried TWO byte-identical copies of
#       `### And a tainted datum that reaches a sink is a finding` ever since -- 40
#       lines each, equal line for line. Nothing caught it: the links gate resolves
#       links, the counts gate counts NUMBERS, and a section that appears twice
#       still resolves every link in it and still contributes the right numbers.
#       A reader scrolling the README saw the same paragraphs twice and the second
#       copy read as though the first were explaining itself.
#
#       IT IS THE SAME CLASS AS THE TWO ABOVE: a patch applied twice, where the
#       thing it pasted was PROSE, and no gate counted prose. 9b counts a repeated
#       SENTENCE inside a family's boundary text; 9c counts a repeated SECTION
#       inside a README -- and it counts it by the heading AND by the body, so a
#       copy pasted under a different heading is caught too.
#
#       The headings are read OUTSIDE the fenced code blocks, because a `#` line in
#       a shell snippet is not a heading.
$readmeFiles = @('README.md', 'README.zh.md')
foreach ($rf in $readmeFiles) {
  $rfPath = Join-Path $root $rf
  $rfLines = [System.IO.File]::ReadAllLines($rfPath, [System.Text.Encoding]::UTF8)
  $headings = @()
  $inFence = $false
  for ($i = 0; $i -lt $rfLines.Count; $i++) {
    $ln = $rfLines[$i]
    if ($ln.TrimStart().StartsWith('```')) { $inFence = -not $inFence; continue }
    if ($inFence) { continue }
    $hm = [regex]::Match($ln, '^(#{2,4})\s+(\S.*?)\s*$')
    if ($hm.Success) {
      $headings += [pscustomobject]@{ Line = $i + 1; Title = $hm.Groups[2].Value; Body = '' }
    }
  }
  # the body of a section is everything up to the next heading
  for ($k = 0; $k -lt $headings.Count; $k++) {
    $from = $headings[$k].Line
    $to = if ($k + 1 -lt $headings.Count) { $headings[$k + 1].Line - 1 } else { $rfLines.Count }
    $body = ''
    for ($j = $from; $j -lt $to; $j++) {
      $body += ($rfLines[$j].TrimEnd() + "`n")
    }
    $headings[$k].Body = $body
  }
  $dupHeads = @()
  $hSeen = @{}
  foreach ($h in $headings) {
    if ($hSeen.ContainsKey($h.Title)) { $dupHeads += ('line ' + $h.Line + ': ' + $h.Title) }
    else { $hSeen[$h.Title] = $true }
  }
  $bSeen = @{}
  $dupBodies = @()
  foreach ($h in $headings) {
    $norm = ($h.Body -replace "`n", '').Trim()
    if ($norm.Length -lt 40) { continue }
    $k2 = $norm.Substring(0, [Math]::Min(120, $norm.Length))
    if ($bSeen.ContainsKey($k2)) { $dupBodies += ('line ' + $h.Line + ': ' + $h.Title) }
    else { $bSeen[$k2] = $true }
  }
  if ($dupHeads.Count -gt 0) {
    Write-Output ("  FAIL: {0} README section heading(s) are used twice in {1}:" -f $dupHeads.Count, $rf)
    foreach ($d in $dupHeads) { Write-Output ('      ' + $d) }
    $fail += $dupHeads.Count
  }
  if ($dupBodies.Count -gt 0) {
    Write-Output ("  FAIL: {0} README section(s) in {1} carry a body another section already carries:" -f $dupBodies.Count, $rf)
    foreach ($d in $dupBodies) { Write-Output ('      ' + $d) }
    $fail += $dupBodies.Count
  }
  if ($dupHeads.Count -eq 0 -and $dupBodies.Count -eq 0) {
    Write-Output ("  no README section is pasted in twice ({0} section(s) read in {1})  OK" -f $headings.Count, $rf)
  }
}
Write-Output ''
Write-Output ''
Write-Output '=== 10. the deck citations name the FILE, and the map names every deck ==='
# WHY THIS CHECK EXISTS. Three defects, ONE cause -- a citation that names a deck by
# TITLE does not tell a reader which file to open:
#
#   1. Chapters 0602, 0603 and 0604 each opened with "The lecture is `Soundiness` (Yue
#      Li and Tian Tan, Nanjing University, 2021 Fall), 68 pages" -- the title, the
#      authors and the page count, and NOT the file. The tree knew the name:
#      `16_Soundiness.pdf` appears in six EARLIER chapters, every one of them saying
#      the deck had NOT been read yet. So the record carried the filename for a deck
#      it had not read, and then cited it by title once it had -- and a title is a
#      phrase, not a name a reader can open.
#   2. Chapter 0572's table is titled "THE MAP THAT NAMES EVERY DECK" and named NINE
#      of the twelve. The three it missed are the three read LAST -- Datalog, IFDS and
#      Soundiness -- so the map was written when the course had nine decks and was
#      never extended when the course grew to twelve. A table whose own title says
#      "every" and whose body says nine is a claim that nothing checked.
#   3. The READMEs sent the reader to `_verify/NARRATIVE.md` §0564 for "the map".
#      §0564 carries the course's own assignment ladder and the one place the
#      framework and this tree disagree -- both true, and both what §0564 is for --
#      but the DECK TABLE is in §0572, and the References named no deck file at all.
#
# A citation is a FACT about a file, and a fact nothing reads rots. So the map is read
# here and checked against the deck files THEMSELVES: every deck on disk is named in
# the map, and every page count in the map is the page count MEASURED out of the file.
#
# WHERE THE DECK FILES ARE. They are a private lecture directory on the author's
# machine: they are not in this repository and not on CI. So the file-measuring half
# of this check runs where the directory is, and where it is not the gate SAYS THAT IT
# DID NOT MEASURE -- a green row that measured nothing is worse than a red row.
$deckDir = 'C:\Users\31379\Documents\NJU'
if ($env:MSA_DECK_DIR) { $deckDir = $env:MSA_DECK_DIR }

function Get-DeckRows {
  # the MAP's rows: the deck name sits on the FIRST line of the row, at four spaces,
  # and the continuation lines of the row are the other two columns.
  param([string]$Text)
  $h = [ordered]@{}
  foreach ($m in [regex]::Matches($Text, '(?m)^ {4}(\S+\.pdf) \((\d+)p\)')) {
    if (-not $h.Contains($m.Groups[1].Value)) { $h[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
  }
  return $h
}
function Get-DeckInventory {
  # the INVENTORY's rows: a deck name and its page count, wherever the name sits.
  param([string]$Text)
  $h = [ordered]@{}
  foreach ($m in [regex]::Matches($Text, '([A-Za-z0-9_.-]+\.pdf) \((\d+)p\)')) {
    if (-not $h.Contains($m.Groups[1].Value)) { $h[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
  }
  return $h
}
function Get-PdfPages {
  # the page count, read out of the PDF's own page tree.
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $txt = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
  $best = 0
  foreach ($m in [regex]::Matches($txt, '/Type\s*/Pages[^>]*?/Count\s+(\d+)')) {
    $v = [int]$m.Groups[1].Value
    if ($v -gt $best) { $best = $v }
  }
  if ($best -gt 0) { return $best }
  return [regex]::Matches($txt, '/Type\s*/Page(?![s])').Count
}

$mapChapM = [regex]::Match($narrTxt2, '(?ms)^## 0572:.*?(?=^## \d{4}:|\z)')
if (-not $mapChapM.Success) {
  Write-Output '  FAIL: the NARRATIVE has no chapter 0572, so the deck map cannot be checked.'
  $fail++
  $mapRows = [ordered]@{}
} else {
  $mapRows = Get-DeckRows $mapChapM.Value
}
$invChapM = [regex]::Match($narrTxt2, '(?ms)^## 0612:.*?(?=^## \d{4}:|\z)')
if ($invChapM.Success) { $invRows = Get-DeckInventory $invChapM.Value } else { $invRows = [ordered]@{} }

# 10a. THE MAP NAMES EVERY DECK, AND THE PAGE COUNTS ARE THE MEASURED ONES.
$deckDirThere = Test-Path -LiteralPath $deckDir
$onDisk = @()
if ($deckDirThere) {
  $onDisk = @(Get-ChildItem -LiteralPath $deckDir -Filter '*.pdf' -File | ForEach-Object { $_.Name })
}
if (-not $deckDirThere) {
  Write-Output ('  the deck directory (' + $deckDir + ') is not on this machine: the page counts were NOT measured.')
  Write-Output ('  (the map still names ' + $mapRows.Count + ' deck(s); set MSA_DECK_DIR to measure them)')
} else {
  $missed = @($onDisk | Where-Object { -not $mapRows.Contains($_) })
  $invented = @($mapRows.Keys | Where-Object { $onDisk -notcontains $_ })
  if ($missed.Count -gt 0) {
    Write-Output ('  FAIL: the deck map does not name ' + $missed.Count + ' deck(s) that are on disk:')
    foreach ($d in $missed) { Write-Output ('      ' + $d) }
    $fail += $missed.Count
  }
  if ($invented.Count -gt 0) {
    Write-Output ('  FAIL: the deck map names ' + $invented.Count + ' deck(s) that are not on disk:')
    foreach ($d in $invented) { Write-Output ('      ' + $d) }
    $fail += $invented.Count
  }
  $badPages = @()
  foreach ($d in $onDisk) {
    if (-not $mapRows.Contains($d)) { continue }
    $measured = Get-PdfPages (Join-Path $deckDir $d)
    if ($measured -ne $mapRows[$d]) {
      $badPages += ($d + ': the map says ' + $mapRows[$d] + 'p, the file has ' + $measured + 'p')
    }
  }
  if ($badPages.Count -gt 0) {
    Write-Output ('  FAIL: ' + $badPages.Count + ' page count(s) in the deck map are not the ones the file has:')
    foreach ($b in $badPages) { Write-Output ('      ' + $b) }
    $fail += $badPages.Count
  }
  if ($missed.Count -eq 0 -and $invented.Count -eq 0 -and $badPages.Count -eq 0) {
    Write-Output ('  the deck map names ' + $mapRows.Count + ' deck(s), and every page count is the one MEASURED from the file  OK')
  }
}

# 10b. THE INVENTORY AND THE MAP AGREE. They are two copies of the same fact, so
# they are both checked against the FILES rather than against each other.
$badInv = @()
foreach ($k in $invRows.Keys) {
  if (-not $mapRows.Contains($k)) { $badInv += ($k + ': the inventory names it, the map does not') }
  elseif ($invRows[$k] -ne $mapRows[$k]) {
    $badInv += ($k + ': the inventory says ' + $invRows[$k] + 'p, the map says ' + $mapRows[$k] + 'p')
  }
}
foreach ($k in $mapRows.Keys) {
  if (-not $invRows.Contains($k)) { $badInv += ($k + ': the map names it, the inventory does not') }
}
if ($badInv.Count -gt 0) {
  Write-Output ('  FAIL: the deck inventory and the deck map disagree on ' + $badInv.Count + ' deck(s):')
  foreach ($b in $badInv) { Write-Output ('      ' + $b) }
  $fail += $badInv.Count
} else {
  Write-Output ('  the deck inventory and the deck map agree on ' + $invRows.Count + ' deck(s)  OK')
}

# 10c. EVERY DECK CITATION NAMES THE FILE. A citation that names a deck by its
# TITLE tells the reader which lecture, and not which file -- and the file is the
# thing a reader opens. So the file has to be in the sentence that introduces the
# deck.
#
# WHY THE LIST IS HERE AND NOT DERIVED. The deck files are OUTSIDE this
# repository: they are a private lecture library on the author's machine, so the
# gate cannot read the decks and derive the list of citations. What it CAN do is
# read the DOCUMENTS, and check that each one names the file for the deck it
# cites. That is what this table is: the citation, and the file it must name.
#
# The NARRATIVE's rows are CHAPTER-SCOPED -- the chapter that opens by naming the
# deck is the one that has to name the file -- and the READMEs' rows are
# DOCUMENT-SCOPED, because a README is one document.
$DECK_CITES = @(
  @{ Doc = '_verify/NARRATIVE.md'; Ch = '0551'; File = '2_IR.pdf' }
  @{ Doc = '_verify/NARRATIVE.md'; Ch = '0564'; File = '1_Intro.pdf' }
  @{ Doc = '_verify/NARRATIVE.md'; Ch = '0597'; File = '15_IFDS.pdf' }
  @{ Doc = '_verify/NARRATIVE.md'; Ch = '0602'; File = '16_Soundiness.pdf' }
  @{ Doc = '_verify/NARRATIVE.md'; Ch = '0603'; File = '16_Soundiness.pdf' }
  @{ Doc = '_verify/NARRATIVE.md'; Ch = '0604'; File = '16_Soundiness.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '1_Intro.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '2_IR.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '5-6_DFA-FD.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '7_Inter.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '8_PTA.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '9-10_PTA-FD.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '11-12_PTA-CS.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '13_Security.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '14_Datalog.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '15_IFDS.pdf' }
  @{ Doc = 'README.md';    Ch = '';     File = '16_Soundiness.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '1_Intro.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '2_IR.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '5-6_DFA-FD.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '7_Inter.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '8_PTA.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '9-10_PTA-FD.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '11-12_PTA-CS.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '13_Security.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '14_Datalog.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '15_IFDS.pdf' }
  @{ Doc = 'README.zh.md'; Ch = '';     File = '16_Soundiness.pdf' }
)
$deckCiteOk = 0
foreach ($c in $DECK_CITES) {
  $cp = Join-Path $root ($c.Doc -replace '/', '\')
  if (-not (Test-Path -LiteralPath $cp)) {
    Write-Output ('  FAIL: ' + $c.Doc + ' is not in the tree, so its deck citations cannot be checked.')
    $fail++
    continue
  }
  $ct = [System.IO.File]::ReadAllText($cp, [System.Text.Encoding]::UTF8)
  if ($c.Ch -eq '') {
    $scope = $ct
  } else {
    $cm2 = [regex]::Match($ct, '(?ms)^## ' + $c.Ch + ':.*?(?=^## \d{4}:|\z)')
    if (-not $cm2.Success) {
      Write-Output ('  FAIL: ' + $c.Doc + ' has no chapter ' + $c.Ch + ', so its citation cannot be checked.')
      $fail++
      continue
    }
    $scope = $cm2.Value
  }
  if (-not $scope.Contains($c.File)) {
    $where = if ($c.Ch -eq '') { $c.Doc } else { $c.Doc + ' chapter ' + $c.Ch }
    Write-Output ('  FAIL: ' + $where + ' does not name the deck file `' + $c.File + '`.')
    $fail++
  } else {
    $deckCiteOk++
  }
}
if ($deckCiteOk -eq $DECK_CITES.Count) {
  Write-Output ('  every deck citation names the file (' + $deckCiteOk + ' citation(s) checked)  OK')
}

# 10d. AND THE READMEs NAME THE DECKS THEY CITE. The two are the ones the
# References list names by title, and the course-map passage names the first lecture.
# 10d. AND THE READMEs NAME EVERY DECK THEY CITE. The two READMEs are
# translations of one another, so the deck each one cites is the same deck -- and
# a file named in one and not in the other is a README that has drifted from its
# translation. This is counted, so the count says how much was checked.
$readmeDeckFiles = @($DECK_CITES | Where-Object { $_.Doc -like 'README*' } | ForEach-Object { $_.File } | Sort-Object -Unique)
foreach ($rf in @('README.md', 'README.zh.md')) {
  $rt = [System.IO.File]::ReadAllText((Join-Path $root $rf), [System.Text.Encoding]::UTF8)
  $missingHere = @($readmeDeckFiles | Where-Object { -not $rt.Contains($_) })
  if ($missingHere.Count -gt 0) {
    Write-Output ('  FAIL: ' + $rf + ' does not name ' + $missingHere.Count + ' deck file(s):')
    foreach ($m in $missingHere) { Write-Output ('      ' + $m) }
    $fail += $missingHere.Count
  } else {
    Write-Output ('  ' + $rf + ' names all ' + $readmeDeckFiles.Count + ' deck files it cites  OK')
  }
}
if ($fail -eq 0) { Write-Output 'VERIFY OK: links, anchors, versions, corrections, counts, family tables, the course map, the chapter headings, the family texts, the README sections and the deck citations all check out.'; exit 0 }
Write-Output ("VERIFY FAILED: " + $fail + " problem(s).")
exit 1

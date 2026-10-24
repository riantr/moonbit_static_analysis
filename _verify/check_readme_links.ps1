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
$peM  = [regex]::Match($relTxt2, "\`$PARSERR_TOTAL\s*=\s*'(\d+)'")
$sfM  = [regex]::Match($relTxt2, "\`$SELF_FILES\s*=\s*'(\d+)'")
$snM  = [regex]::Match($relTxt2, "\`$SELF_NOTICES\s*=\s*'([^']*)'")
$sxM  = [regex]::Match($relTxt2, "\`$SELF_EXPR\s*=\s*'(\d+)'")
$sdM  = [regex]::Match($relTxt2, "\`$SELF_DECL\s*=\s*'(\d+)'")
$loM  = [regex]::Match($relTxt2, "\`$SUPPOFF_LOCAL\s*=\s*'(\d+)'")
$paM  = [regex]::Match($relTxt2, "\`$SUPPOFF_PARAM\s*=\s*'(\d+)'")
if (-not ($peM.Success -and $sfM.Success -and $snM.Success -and $sxM.Success -and $sdM.Success -and $loM.Success -and $paM.Success)) {
  Write-Output '  FAIL: release.ps1 no longer carries the pins this gate derives from.'
  Write-Output '        Restore them, or this gate has nothing to check the README against.'
  $fail++
  $peTotal = '?'; $sn = ''; $sx = '?'; $sd = '?'; $lo = '?'; $pa = '?'
} else {
  $peTotal = ([int]$peM.Groups[1].Value).ToString('N0')
  $sf = $sfM.Groups[1].Value
  $sn = $snM.Groups[1].Value
  $sx = $sxM.Groups[1].Value
  $sd = $sdM.Groups[1].Value
  $lo = $loM.Groups[1].Value
  $pa = $paM.Groups[1].Value
  Write-Output ('  (release.ps1 pins: ParseError ' + $peTotal + ', own-source files ' + $sf + ', notice table ' + (@($sn -split '\|').Count) +
                ' kinds, expression-level ' + $sx + ', declaration-level ' + $sd +
                ', suppression off ' + $lo + ' / ' + $pa + ')')
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
$more.Add(@{ F = 'README.md';    S = ('**' + $peTotal + '**'); N = 'the rendered ParseError count' })
$more.Add(@{ F = 'README.zh.md'; S = ('**' + $peTotal + '**'); N = 'the rendered ParseError count (zh)' })
$more.Add(@{ F = 'README.md';    S = ('**' + ([int]$lo).ToString('N0') + '**'); N = 'the suppression-off UnusedLocal count' })
$more.Add(@{ F = 'README.md';    S = ('**' + ([int]$pa).ToString('N0') + '**'); N = 'the suppression-off UnusedParam count' })
$more.Add(@{ F = 'README.zh.md'; S = ('**' + ([int]$lo).ToString('N0') + '**'); N = 'the suppression-off UnusedLocal count (zh)' })
$more.Add(@{ F = 'README.zh.md'; S = ('**' + ([int]$pa).ToString('N0') + '**'); N = 'the suppression-off UnusedParam count (zh)' })
$more.Add(@{ F = 'README.md';    S = ('exclusion (' + $sx + ' of them)'); N = 'the expression-level exclusions' })
$more.Add(@{ F = 'README.md';    S = ('exclusion (' + $sd + ')'); N = 'the declaration-level exclusions' })
$more.Add(@{ F = 'README.zh.md'; S = ($LP + $sx + ' 条' + $RP); N = 'the expression-level exclusions (zh)' })
$more.Add(@{ F = 'README.zh.md'; S = ($LP + $sd + ' 条' + $RP); N = 'the declaration-level exclusions (zh)' })
# THE OWN-SOURCE FILE COUNT, DERIVED FROM THE PIN. It used to be the literal
# `178` written into THIS gate, which is a number that can only ever agree with
# itself -- the release gate measured the count and never compared it with
# anything, so the count moved twice (178 -> 179 -> 181) with nothing
# objecting. It is a pin in release.ps1 now, and this gate asks only what the
# pin says.
$more.Add(@{ F = 'README.md';    S = ('(' + $sf + ' files)'); N = 'the own-source file count' })
$more.Add(@{ F = 'README.zh.md'; S = ($sf + ' 个文件'); N = 'the own-source file count (zh)' })
foreach ($e in $more) {
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

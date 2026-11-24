$ErrorActionPreference = 'Continue'
# THE SHARED HARNESS'S OWN SELF-TEST: THE INCONCLUSIVE VERDICT, SHOWN TO GO RED.
#
# WHY THIS EXISTS. 0506's release gate failed on gate 0466, and the failure was
# NOT the mutation's fault: `moon test` printed the COMPILER'S OWN WARNING
#
#     Warning (unused_value): Unused variable 'n'
#
# and exited 1 with no test summary. The harness had no summary line, so it
# recorded COMPILE-ERR and blamed the mutant. MEASURED on the same tree, the
# same mutation is SURVIVED with 1184/1184 green -- and `moon test` on the
# mutated tree, with the package REBUILT, exits 0 and DOES print the summary
# (the warning goes to stderr, the summary to stdout). The machine was busy at
# the time; a starved build wears the same shape as a rejected one.
#
# So the harness now tells THREE things apart:
#
#     a summary line + a non-zero exit          -> KILLED
#     a summary line + a zero exit              -> SURVIVED
#     a COMPILER DIAGNOSTIC (`Error: [NNNN]`)   -> COMPILE-ERR
#     NONE OF THE ABOVE                          -> INCONCLUSIVE
#
# INCONCLUSIVE is not a verdict: it is a failed measurement, it is retried once
# (the failure mode is fast, so the retry is cheap), and it FAILS the gate if
# the retry does not rescue it. It can never manufacture a pass.
#
# AND A VERDICT PATH THAT HAS NEVER BEEN SHOWN TO GO RED IS A COMMENT, which is
# what this file is for. It takes a COPY of `_verify` in TEMP, breaks the
# harness's summary-line regex for the MUTATION runs only -- the BASELINE's
# regex is left alone, because a demonstration that breaks the baseline proves
# nothing about the mutation path -- and runs a one-mutation gate against the
# copy. The copy's harness cannot see any summary, so the row must come out
# INCONCLUSIVE, the gate must FAIL, and the process must exit non-zero.
#
# The real tree is never left patched: the copy's gate still restores its
# target byte-identically, and the harness proves that by SHA256.
$root = Split-Path -Parent $PSScriptRoot
$verify = Join-Path $root '_verify'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'

$tmp = Join-Path $env:TEMP ('harness_selftest_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$copy = Join-Path $tmp '_verify'
Copy-Item -LiteralPath $verify -Destination $copy -Recurse -Force

# --- 1. break the summary-line regex for the MUTATION runs only ----------------
$lib = Join-Path $copy 'mutate_lib.ps1'
$t = [System.IO.File]::ReadAllText($lib, [System.Text.Encoding]::UTF8)
$needle = 'Total tests: (\d+), passed: (\d+), failed: (\d+)'
$n = ([regex]::Matches($t, [regex]::Escape($needle))).Count
Write-Output ('the summary-line regex is in the harness ' + $n + ' time(s)')
if ($n -lt 3) {
  Write-Output 'FAIL: the harness does not carry the summary-line regex three times (baseline, mutation, retry).'
  exit 1
}
$broken = 'XXX-Total-tests-(\d+)-passed-(\d+)-failed-(\d+)'
$idx = $t.IndexOf($needle)
$first = $true
for ($i = 0; $i -lt 3; $i++) {
  $at = $t.IndexOf($needle, $idx)
  if ($at -lt 0) { break }
  $idx = $at + $needle.Length
  if ($first) { $first = $false; continue }
  $t = $t.Remove($at, $needle.Length).Insert($at, $broken)
}
$intact = ([regex]::Matches($t, [regex]::Escape($needle))).Count
Write-Output ('the intact summary-line regex left in the copy: ' + $intact + ' (the baseline one)')
if ($intact -ne 1) {
  Write-Output 'FAIL: the copy does not keep exactly one intact summary-line regex.'
  exit 1
}
[System.IO.File]::WriteAllText($lib, $t, (New-Object System.Text.UTF8Encoding($false)))

# --- 2. a gate with ONE mutation, in the copy ---------------------------------
$gate = Join-Path $copy 'mutate_0998.ps1'
[System.IO.File]::WriteAllText($gate, @'
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')
Invoke-MutationGate -Name 'selftest-inconclusive' -Target 'js' -Root '__ROOT__' -Mutations @(
  @{
    Name = 'M1 the mutation is applied and the suite is green'
    File = 'src\parser\parser.mbt'
    Find = '  n != "_" && !@lexer.is_moonbit_keyword(n)'
    Repl = '  true'
    Expect = 'SURVIVED'
    Prove = 'the demonstration: the harness cannot see the summary line, so this row cannot be scored'
  }
)
Write-MutationGateVerdict -Name 'selftest-inconclusive'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
'@.Replace('__ROOT__', $root), (New-Object System.Text.UTF8Encoding($false)))

# --- 3. run the copy's gate, from the repo root ------------------------------
Set-Location $root
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $gate 2>&1 | Out-String
$code = $LASTEXITCODE
$ErrorActionPreference = $prev

Write-Output ''
Write-Output '=== what the copy did ==='
foreach ($ln in ($out -split "`r?`n")) {
  if ($ln -match '(NO RUN|Retrying once|RETRY|INCONCLUSIVE|GATE FAILED|GATE OK|SURVIVED|COMPILE-ERR|restored)') {
    Write-Output ('  ' + $ln.Trim())
  }
}
Write-Output ''
Write-Output ('the demonstration gate exited ' + $code)

$mustSee = @('NO RUN', 'Retrying once', 'RETRY ALSO GOT NO RUN', 'INCONCLUSIVE', 'GATE FAILED')
$missing = @($mustSee | Where-Object { $out.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 })
if ($missing.Count -gt 0) {
  Write-Output ('FAIL: the demonstration did not show: ' + ($missing -join ', '))
  exit 1
}
if ($code -eq 0) {
  Write-Output 'FAIL: the demonstration gate exited 0 -- a run that could not be scored must FAIL.'
  exit 1
}

# --- 4. 0645. THE PRE-FLIGHT AND THE MUTATION MUST READ THE SAME TEXT ----------
#
# THE DEFECT THIS PROVES. MEASURED 2026-11-24: 64 of the 89 mutation gates went
# RED with "ABORT: N pattern(s) absent. No suite was run." -- the PRE-FLIGHT
# could not find anchors that the MUTATION PHASE would have found, because the
# mutation phase normalises the file to LF before it matches (it detects the
# file's EOL and replaces CRLF with LF, then converts back when it writes) and
# the pre-flight matched the RAW text against an LF anchor. Two rulers for one
# text, and the gate aborted on the stricter one before it ran anything.
#
# WHY A CRLF FILE IS THE RIGHT FIXTURE. The mutation tables in this repository
# write their anchors with "`n" (LF), because the blobs are LF. A file whose
# bytes are CRLF is therefore the case where the two readers disagree, and it
# is not a hypothetical one: `core.autocrlf=true` (from the Git installation's
# own config) rewrites the files a checkout touches, and `git status` stays
# CLEAN while it does it, because git normalises before it compares.
#
# THE TWO HALVES OF THE PROOF, on ONE fixture:
#
#   the REAL harness          the pre-flight MUST find the anchor
#   a harness with the fix REMOVED   the pre-flight MUST miss it
#
# The second half is what makes the first one mean something: a fixture that
# passes for any reason would pass the first half too.
#
# The fixture lives in TEMP and is a few lines long, so the real tree is never
# patched and the demonstration costs no test suite.
$crlfDir = Join-Path $tmp 'crlf'
New-Item -ItemType Directory -Force -Path $crlfDir | Out-Null
$crlfFile = Join-Path $crlfDir 'fixture.txt'
# THE ANCHOR SPANS TWO LINES, and the file's bytes are CRLF.
[System.IO.File]::WriteAllText($crlfFile, "alpha`r`n  match toks[i] {`r`n    TName(n) => {`r`nbeta`r`n", (New-Object System.Text.UTF8Encoding($false)))

$fixtureGate = Join-Path $tmp 'mutate_crlf_fixture.ps1'
$fixtureSrc = @'
$ErrorActionPreference = 'Stop'
. '__HARNESS__'
Invoke-MutationGate -Name 'selftest-crlf' -Target 'js' -Root '__ROOT__' -Mutations @(
  @{
    Name = 'M1 the anchor spans two lines'
    File = 'fixture.txt'
    Find = "  match toks[i] {`n    TName(n) => {"
    Repl = "  match toks[j] {`n    TName(n) => {"
    Expect = 'COMPILE-ERR'
    Prove = 'the demonstration: the fixture is not a MoonBit project, so no suite can run'
  }
)
Write-MutationGateVerdict -Name 'selftest-crlf'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
'@

function Invoke-Fixture {
  param([string]$Harness, [string]$Tag)
  $g = Join-Path $tmp ('mutate_crlf_' + $Tag + '.ps1')
  [System.IO.File]::WriteAllText($g, $fixtureSrc.Replace('__HARNESS__', $Harness).Replace('__ROOT__', $crlfDir), (New-Object System.Text.UTF8Encoding($false)))
  $prev2 = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $g 2>&1 | Out-String
  $c = $LASTEXITCODE
  $ErrorActionPreference = $prev2
  return @{ Out = $o; Code = $c }
}

Write-Output ''
Write-Output '=== 0645: the pre-flight and the mutation must read the same text ==='
$fixed = Invoke-Fixture (Join-Path $verify 'mutate_lib.ps1') 'fixed'
$fixedHit = ($fixed.Out -match 'Pre-flight: all 1 live patterns present and UNIQUE')
$fixedMiss = ($fixed.Out -match 'PREFLIGHT MISS')
Write-Output ('  the real harness on a CRLF fixture: pre-flight found the anchor = ' + $fixedHit + ', and missed it = ' + $fixedMiss)
if (-not $fixedHit -or $fixedMiss) {
  Write-Output 'FAIL: the real harness did not find a two-line anchor in a CRLF file -- the pre-flight and the mutation still disagree.'
  exit 1
}

# THE HARNESS WITH THE FIX REMOVED. The line that normalises the haystack is
# deleted from a COPY, and the copy has to go back to missing the anchor.
$noFixLib = Join-Path $tmp 'mutate_lib_nofix.ps1'
$libText = [System.IO.File]::ReadAllText((Join-Path $verify 'mutate_lib.ps1'), [System.Text.Encoding]::UTF8)
$normLines = @(
  '    $hayEol = if ($hay.Contains([string][char]13 + [char]10)) { [string][char]13 + [char]10 } else { $nl }',
  '    $hay = $hay.Replace($hayEol, $nl)'
)
$stripped = $libText
foreach ($l in $normLines) { $stripped = $stripped.Replace($l + "`r`n", '').Replace($l + "`n", '') }
if ($stripped -eq $libText) {
  Write-Output 'FAIL: the harness does not carry the normalisation this self-test removes -- the case would prove nothing.'
  exit 1
}
[System.IO.File]::WriteAllText($noFixLib, $stripped, (New-Object System.Text.UTF8Encoding($false)))
$broken = Invoke-Fixture $noFixLib 'nofix'
$brokenMiss = ($broken.Out -match 'PREFLIGHT MISS')
$brokenAbort = ($broken.Out -match 'ABORT: 1 pattern\(s\) absent')
Write-Output ('  the same fixture, fix removed: pre-flight missed it = ' + $brokenMiss + ', and aborted = ' + $brokenAbort)
if (-not $brokenMiss -or -not $brokenAbort) {
  Write-Output 'FAIL: the harness without the fix did NOT miss the anchor -- so the case cannot tell the two readers apart.'
  exit 1
}
Write-Output '  ok  the same fixture, the same anchor: the real harness finds it and the un-fixed one misses it.'

# --- 5. 0646. THE REPLACEMENT IS APPLIED AT EVERY SITE, AND THE HARNESS SAYS SO ----
#
# THE DEFECT THIS PROVES. The harness's own comment said it "removes the FIRST literal
# match", and it has NEVER done that: the write is `$norm.Replace($findN, $replN)`, and
# .NET's String.Replace replaces EVERY occurrence. MEASURED 2026-11-24: the comment
# said one site and the code replaced two, on one fixture, with the two readings side
# by side. The comment had been in the file since the harness was created, and it was
# the source of a chapter that explained a red the WRONG way -- so a claim about the
# harness's behaviour has to be measured, like anything else.
#
# THE FIXTURE. A REAL, TINY MoonBit project in TEMP -- because the harness aborts
# BEFORE the mutation phase when the baseline cannot run, so a plain text file
# would never reach the code under test. The project's source carries the anchor
# TWICE, and its test goes red when the mutation is applied.
#
# THE NUMBER THE HARNESS PRINTS IS NOT A COPY OF THE PRE-FLIGHT'S COUNT. It is the
# difference between the anchor's occurrences BEFORE the write and the occurrences
# that REMAIN in the file the write produced -- two observations of the file. If the
# harness ever went back to mutating one site, the second number would be 1 and the
# line would say "applied at 1 site(s)".
#
# THE COUNTERFACTUAL IS THE SECOND READING OF THE SAME FIXTURE: a copy of the harness
# whose write splices the FIRST occurrence only. It must report ONE site. Two readings
# that agree on this fixture would prove nothing, so the case FAILS if they agree.
$dupDir = Join-Path $tmp 'dup'
$dupPkg = Join-Path $dupDir 'src\dup'
New-Item -ItemType Directory -Force -Path $dupPkg | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dupDir 'moon.mod'), "name = `"dupfixture`"`nversion = `"0.1.0`"`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $dupDir 'moon.pkg'), "supported_targets = `"+js+native`"`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $dupPkg 'moon.pkg'), "supported_targets = `"+js+native`"`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $dupPkg 'dup.mbt'), @'
pub fn classify(n : Int) -> Int {
  if n > 0 {
    1
  } else {
    0
  }
}

pub fn twice(n : Int) -> Int {
  if n > 0 {
    2
  } else {
    0
  }
}
'@, $utf8)
[System.IO.File]::WriteAllText((Join-Path $dupPkg 'dup_test.mbt'), @'
test "classify_positive" {
  assert_eq(classify(1), 1)
}

test "twice_positive" {
  assert_eq(twice(1), 2)
}
'@, $utf8)

$dupGate = Join-Path $tmp 'mutate_dup_fixture.ps1'
$dupSrc = @'
$ErrorActionPreference = 'Stop'
. '__HARNESS__'
Invoke-MutationGate -Name 'selftest-dup' -Target 'js' -Root '__ROOT__' -Mutations @(
  @{
    Name = 'M1 the anchor occurs twice'
    File = 'src\dup\dup.mbt'
    Find = '  if n > 0 {'
    Repl = '  if n > 0 && false {'
    MustRed = 'classify_positive'
  }
)
Write-MutationGateVerdict -Name 'selftest-dup'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
'@

function Invoke-DupFixture {
  param([string]$Harness, [string]$Tag)
  $g = Join-Path $tmp ('mutate_dup_' + $Tag + '.ps1')
  [System.IO.File]::WriteAllText($g, $dupSrc.Replace('__HARNESS__', $Harness).Replace('__ROOT__', $dupDir), (New-Object System.Text.UTF8Encoding($false)))
  $prev3 = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $g 2>&1 | Out-String
  $c = $LASTEXITCODE
  # 0646. THE EXIT CODE IS TAKEN, AND IT IS TAKEN AT ONCE -- the very next line.
  # The first version of this function did not take it, and the release gate's own
  # exit-code stage said so, by name:
  #
  #     FAIL: 1 site(s) take no exit code and have NO stated mechanism:
  #         mutate_lib_selftest.ps1:305  $o = & powershell ... -File $g
  #
  # which is the rule this very repository holds every other child gate to. A gate
  # that invokes a child and does not take its exit code cannot tell a child that
  # failed from a child that said nothing.
  #
  # IT IS TAKEN AT ONCE, and that is not a detail of style. $LASTEXITCODE is
  # overwritten by the next child process, so a capture that is separated from its
  # invocation by prose is a capture of whatever ran next. The first version of
  # this function took the exit code ten lines further down, below this comment,
  # and the gate's detector still named the site: its window is three lines, for
  # the same reason. A fix that is technically present but placed where the rule
  # does not reach is not a fix.
  $ErrorActionPreference = $prev3
  return @{ Out = $o; Code = $c }
}

Write-Output ''
Write-Output '=== 0646: the replacement is applied at EVERY site, and the harness says so ==='
$dupReal = Invoke-DupFixture (Join-Path $verify 'mutate_lib.ps1') 'real'
$realTwo = ($dupReal.Out -match 'applied at 2 site\(s\)')
$realKilled = ($dupReal.Out -match 'KILLED')
Write-Output ('  the real harness on a project whose anchor occurs twice: reported 2 site(s) = ' + $realTwo + ', and killed = ' + $realKilled + ', and the fixture gate exited ' + $dupReal.Code)
if (-not $realTwo) {
  Write-Output 'FAIL: the real harness did not report that it applied the replacement at TWO sites.'
  Write-Output '      The harness REPLACES every occurrence, so an anchor that occurs twice must say 2.'
  Write-Output '      What it said instead:'
  foreach ($ln in ($dupReal.Out -split "`r?`n" | Where-Object { $_ -match 'applied at|site\(s\)' })) { Write-Output ('        | ' + $ln.Trim()) }
  exit 1
}
if (-not $realKilled) {
  Write-Output 'FAIL: the fixture mutation did not kill the fixture suite -- the case measured nothing.'
  exit 1
}
if ($dupReal.Code -ne 0) {
  Write-Output ('FAIL: the fixture gate exited ' + $dupReal.Code + '; the case ran against a gate that failed.')
  exit 1
}

# THE COUNTERFACTUAL. The write line is replaced by a splice of the FIRST occurrence
# only, in a COPY of the harness. The copy must report ONE site -- and if it did not,
# this fixture could not tell the two readings apart and the case would prove nothing.
$spliceLib = Join-Path $tmp 'mutate_lib_firstonly.ps1'
$libText2 = [System.IO.File]::ReadAllText((Join-Path $verify 'mutate_lib.ps1'), [System.Text.Encoding]::UTF8)
$writeLine = 'Write-TextWithRetry -Path $path -Text ($norm.Replace($findN, $replN).Replace($nl, $eol)) -Enc $enc'
$spliceLine = 'Write-TextWithRetry -Path $path -Text ($norm.Substring(0, $norm.IndexOf($findN)) + $replN + $norm.Substring($norm.IndexOf($findN) + $findN.Length)).Replace($nl, $eol) -Enc $enc'
if (-not $libText2.Contains($writeLine)) {
  Write-Output 'FAIL: the harness does not carry the write line this self-test rewrites -- the case would prove nothing.'
  exit 1
}
$spliced = $libText2.Replace($writeLine, $spliceLine)
[System.IO.File]::WriteAllText($spliceLib, $spliced, (New-Object System.Text.UTF8Encoding($false)))
$dupSplice = Invoke-DupFixture $spliceLib 'splice'
$spliceOne = ($dupSplice.Out -match 'applied at 1 site\(s\)')
Write-Output ('  the same fixture, first-occurrence only: reported 1 site(s) = ' + $spliceOne + ', and the fixture gate exited ' + $dupSplice.Code)
if (-not $spliceOne) {
  Write-Output 'FAIL: a harness that mutates the FIRST occurrence only did not report 1 site -- so the'
  Write-Output '      real harness and the first-occurrence one cannot be told apart by this fixture,'
  Write-Output '      and the case above would prove nothing.'
  exit 1
}
Write-Output '  ok  the same fixture, two readings: EVERY occurrence (2) and the FIRST only (1).'

Write-Output ''
Write-Output 'SELFTEST OK: the INCONCLUSIVE verdict fires, is retried once, and FAILS the gate;'
Write-Output '              the pre-flight finds a two-line anchor in a CRLF file, exactly as'
Write-Output '              the mutation phase does;'
Write-Output '              and the replacement is applied at EVERY site the anchor matches, and the'
Write-Output '              harness prints how many that was.'
exit 0

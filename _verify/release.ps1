# ONE local release entry point.
#
# WHY THIS FILE EXISTS. `.github/workflows/gate.yml` runs four commands -- fmt,
# check, one test target, one build. That is the floor CI enforces, and it is not
# wrong; it is just much smaller than what this project actually relies on. The
# mutation gates, the self-scan and the corpus comparison all run locally or not
# at all, so a regression in any of them reaches a tag behind a green CI badge.
# Every stage below is something this repository has been changed by before.
#
# The order is not arbitrary:
#
#   1. The suite is proven green BEFORE any mutation gate runs. A mutation count
#      against a red suite means nothing, and mutate_lib.ps1 aborts on a red
#      baseline for exactly that reason. Proving it here too means the failure is
#      reported as "the tests are red" rather than as fourteen confusing gates.
#   2. `moon fmt --check` runs first because a formatter that wants to rewrite a
#      file makes every later measurement a moving target.
#   3. The corpus comparison is last because it is the only stage needing a build,
#      and the slowest per unit of information.
#   4. The published-package self-scan sits after the mutation gates because it is
#      the one stage that depends on something outside this repository, so it should
#      not be reached until everything local is already known good.
#
# The mutation gates pin their own targets. 0412/0413 need wasm; 0423-0429 run js;
# 0418-0422 run wasm. That is not a detail to standardise away -- `src/sa` needs
# the async runtime, so on js those packages degrade and their tests do not run,
# and a js run of 0412 manufactures two false survivors. Each gate knows its own;
# this file does not second-guess it.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\release.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\release.ps1 -SkipMutations
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\release.ps1 -SelfTest
param([switch]$SkipMutations, [switch]$AllowCorpusDrift, [switch]$SelfTest)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$repos = Join-Path $root '.repos'

$script:results = @()
$script:stageOk = $true
$script:lastOk = $true

# WHY Stage RETURNS NOTHING AND ANSWERS IN $script:lastOk.
#
# The first version of this file read `if (-not (Stage 'name' { ... })) { $failed += 'name' }`.
# That never fails. In PowerShell a function's return value is EVERYTHING it wrote
# to the output stream, so a Stage that prints twelve lines returns an array of
# twelve things; that array is truthy whatever the stage did, `-not` makes it false,
# and `$failed` stays empty. Every stage below would have reported ok while failing,
# and the run would have printed RELEASE GATE PASSED with a red suite.
#
# This is the same trap that made `mutate_0429.ps1` exit 0 after aborting, and the
# same one `Write-MutationGateVerdict` carries a comment about: a function that both
# speaks and answers has to choose, and in PowerShell the speaking wins. So Stage
# only PRINTS, and the answer lives in a script-scope variable.
#
# -SelfTest exercises exactly that, below. A guard that has never been shown to go
# red is not a guard.
function Stage {
  param([string]$Name, [scriptblock]$Body)
  Write-Output ''
  Write-Output ('=== ' + $Name + ' ===')
  $t0 = Get-Date
  $script:stageOk = $true
  $msg = ''
  try { $msg = (& $Body | Out-String) } catch { $msg = $_.Exception.Message; $script:stageOk = $false }
  $dt = [int]((Get-Date) - $t0).TotalSeconds
  if ($msg) { Write-Output $msg.TrimEnd() }
  $script:results += [pscustomobject]@{ Stage = $Name; Ok = $script:stageOk; Seconds = $dt }
  Write-Output ('  -> ' + $(if ($script:stageOk) { 'ok' } else { 'FAILED' }) + ", ${dt}s")
  $script:lastOk = $script:stageOk
}

function Run-Moon {
  param([string[]]$MoonArgs)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = & $moon @MoonArgs 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  # A `moon` stage is the LAST LINE OF DEFENCE, not the only one: if the command
  # did not run at all, `$LASTEXITCODE` is whatever the previous native call left
  # behind, and a stale 0 reads as a pass.
  if ($null -eq $code) { $code = 1 }
  Write-Output $o
  if ($code -ne 0) { $script:stageOk = $false; Write-Output ('moon exited ' + $code) }
}

function Run-Gate {
  param([string]$Path)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $Path 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  # KEEP THE WHOLE TRANSCRIPT. The filter below is for READING, not for evidence.
  #
  # Measured: a release run reported four gates FAILED (0433, 0434, 0441, 0442), and
  # every one of them passes standalone on the same tree with the same 626/626
  # baseline. Six gates have now flaked this way across two runs. The detail that
  # would have said WHY was thrown away twice: first by this filter, which kept the
  # verdict lines and dropped the per-mutation table behind them, and then by
  # `Select-Object -Last 70` over the run's own output. A failure that cannot be
  # diagnosed after the fact is not a measurement, so every gate's full text now
  # lands in _verify\_gatelogs\ and the run's transcript names the file on failure.
  $logDir = Join-Path $root '_verify\_gatelogs'
  if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
  $logName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
  [System.IO.File]::WriteAllText((Join-Path $logDir ($logName + '.log')), $o, (New-Object System.Text.UTF8Encoding($false)))
  # The verdict lines, PLUS the per-mutation outcome. A gate that fails on a
  # COMPILE-ERR or on a survivor has to say WHICH mutation and what it got -- the
  # old filter printed the failure list naming mutations whose outcome it hid.
  foreach ($ln in ($o -split "`r?`n")) {
    if ($ln -match '^(GATE OK|GATE FAILED|ABORT|RELEASE GATE|  Baseline:|Pre-flight|=== mutation gate)' -or
        $ln -match '^\s+- ' -or
        $ln -match '^\s+(KILLED|SURVIVED|NO-OP|COMPILE-ERR|NO-RUN)\s') {
      Write-Output $ln
    }
  }
  if ($code -ne 0) {
    $script:stageOk = $false
    Write-Output ('  [child exit ' + $code + '; full transcript: _verify\_gatelogs\' + $logName + '.log]')
  }
}

function Read-TextWhenFree {
  # `Start-Process -Wait` waits for the PROCESS. It does not promise the
  # redirected output file's handle is already closed, and on this machine it is
  # not: the corpus stage died with
  #
  #   Exception calling "ReadAllText" with "1" argument(s): The process cannot
  #   access the file '...\rel_eebe873b\o.txt' because it is being used by another
  #   process.
  #
  # which reads as a corpus mismatch and is not one -- the comparison never ran.
  # A gate that reports a lock as a verdict is worse than a gate that fails loudly,
  # so this retries, and if it still cannot read the file it SAYS SO and names the
  # file instead of surfacing a bare .NET exception that says nothing about which
  # stage failed.
  param([string]$Path, [int]$Tries = 20)
  for ($i = 1; $i -le $Tries; $i++) {
    try {
      return [System.IO.File]::ReadAllText($Path)
    } catch [System.IO.IOException] {
      if ($i -eq $Tries) {
        throw ("could not read the redirected output after " + $Tries +
               " attempts: " + $Path + " -- the scanner's stdout was still locked." +
               " This is a harness failure, not a corpus result.")
      }
      Start-Sleep -Milliseconds (100 * $i)
    }
  }
}

function Scan-Tree {
  param([string]$Wasm, [string]$Path)
  $dir = Join-Path $env:TEMP ('rel_' + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $out = Join-Path $dir 'o.txt'; $err = Join-Path $dir 'o.err'
  # THE PER-FILE PRINTING CAP IS LIFTED HERE, and it is lifted HERE rather than
  # in each caller because the cap is a property of the PRINTED output and not
  # of the measurement: the SUMMARY line is the same either way (MEASURED: the
  # seven corpus SUMMARYs and the self-scan SUMMARY are byte-identical with the
  # cap at 40 and at 1,000,000), while a count of RENDERED lines is only a fact
  # about the corpus if the cap is out of the way.
  #
  # `--no-auto-fetch-deps` is added for the same reason the measurement scripts
  # pass it: a release gate that can reach the network is a release gate whose
  # result depends on the network.
  Start-Process -FilePath $moonrun `
    -ArgumentList @($Wasm, $Path, '--extern-iface-dir', $repos, '--no-auto-fetch-deps', '--findings-shown-per-file', '1000000') `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  return Read-TextWhenFree -Path $out
}

# THE ANALYZER'S NOTICE TABLE, and the numbers in it.
#
# 0506 changed the SHAPE of a scan's output. A notice is printed one per line
# only when it can HIDE a finding -- when its region lies inside some
# function's extent -- and every other notice is counted by shape in one
# `NOTICES` table at the end of the scan. So the RENDERED `ParseError` lines
# are no longer the notice count: they are the printed half of it, and a gate
# that kept counting them as the whole would come to disagree with the
# SUMMARY and blame the corpus.
#
# The TOTAL line carries the tree's whole notice count, and it is what the
# gate reads. Three numbers, from three different computations, and they must
# reconcile:
#
#     notices == printed + aggregated == the SUMMARY's `notices`
#     the rendered `notice:` lines == printed
#
# THE LAST ONE IS THE PROOF THAT NOTHING WAS DROPPED ON THE WAY. Every notice
# the analyzer counted as printed is on a line of the reader's screen, and
# every `notice:` line on the screen is one of them.
#
# 0508 CHANGED THE SPELLING, NOT THE CLAIM. Before the demotion the printed
# notices were the scope limits alone, so the gate counted the rendered
# `ParseError` lines and got the same set. The demotion put the low-confidence
# findings on a line of their own too -- a demotion that HID them would take
# the name and the place away -- so the count is of the RENDERED NOTICE lines
# now, and the ParseError family has its own check beside it: a defect of that
# family renders `error:`, and the count of those must be zero.
function Get-NoticeTable {
  param([string]$Text)
  $rows = @()
  foreach ($x in [regex]::Matches($Text, '(?m)^NOTICES\tcount=(\d+)\t(.+)$')) {
    $rows += [pscustomobject]@{ N = [int]$x.Groups[1].Value; Message = $x.Groups[2].Value }
  }
  $m = [regex]::Match($Text, '(?m)^NOTICES\tTOTAL\tnotices=(\d+)\tprinted=(\d+)\taggregated=(\d+)')
  if (-not $m.Success) {
    # No table at all: the tree has no notices to count.
    return [pscustomobject]@{ Present = $false; Notices = 0; Printed = 0; Aggregated = 0; Rows = $rows }
  }
  return [pscustomobject]@{
    Present = $true
    Notices = [int]$m.Groups[1].Value
    Printed = [int]$m.Groups[2].Value
    Aggregated = [int]$m.Groups[3].Value
    Rows = $rows
  }
}

# THE RENDERED NOTICE LINES, and the ParseError-FAMILY DEFECTS.
#
# 0508. THE DEMOTION CHANGED WHAT A NOTICE LINE IS, and this is where the gate
# learned it. Before 0508 the declared scope limit was the ONLY kind of notice,
# so "the rendered `ParseError` lines" and "the rendered notice lines" were the
# same set, and the gate could count one and compare it with the table's
# `printed`. After 0508 there are TWO kinds of notice on the reader's screen:
# the scope limit, which renders `(ParseError)`, and the low-confidence finding
# the analyzer does not stand behind, which renders its OWN family. So the
# count is of the NOTICE lines, and the ParseError family keeps a SEPARATE
# check.
#
# THE CHECK IS THE SAME CLAIM AS BEFORE, SPELLED DIFFERENTLY:
#
#     every ParseError-family finding in the tree renders `notice:`
#
# A genuine defect of that family renders `error:` -- the label the analyzer
# gives a finding it stands behind -- so a defect is counted here, and the
# count must be zero. The family is read from the line's PARENTHESES and never
# from its message: a message may carry parentheses of its own ("no method
# matching +(Struct)"), and a matcher that read the family out of the message
# would silently stop seeing the defects it is looking for.
function Get-NoticeLineCount {
  param([string]$Text)
  return @([regex]::Matches($Text, '(?m)^\d+:\d+ - notice: ')).Count
}

# The ParseError-family findings that are NOT notices: a genuine defect of
# that family. Zero is the only acceptable answer, and it is measured on every
# tree the gate scans.
function Get-ParseErrorDefectCount {
  param([string]$Text)
  $n = 0
  foreach ($l in ($Text -split "`r?`n")) {
    if ($l.Contains('(ParseError)') -and -not $l.Contains(' - notice: ')) { $n++ }
  }
  return $n
}

# THE KIND of a notice: the construct its message names.
#
# ONE rule, here, and the gate FAILS on a message it cannot map. A new
# construct form that the README's table could not name has to be loud: a
# breakdown that quietly dropped it would leave the published table short a
# row without saying so.
function Get-NoticeKind {
  param([string]$Message)
  $i = $Message.IndexOf(' is outside the analyzed subset')
  if ($i -ge 0) { return $Message.Substring(0, $i) }
  # 0508. A notice that is NOT a scope limit is a DEMOTED FINDING -- the
  # low-confidence finding the analyzer does not stand behind. It is named as
  # such and not by its message: the message names a SYMBOL, and a table of
  # symbols is not a table of kinds.
  return 'demoted finding'
}

function Get-Summary {
  param([string]$Text)
  $s = ([regex]::Match($Text, '(?m)^SUMMARY.*$').Value) -replace "`t", ' '
  $s = $s -replace '^SUMMARY\s*', ''
  $s = $s -replace '\s*\(actionable.*$', ''
  return ((($s -split '\s+') | Where-Object { $_ -ne '' }) -join ' ')
}

Write-Output 'release gate'
Write-Output ('  repo    : ' + $root)
Write-Output ('  commit  : ' + (git rev-parse --short HEAD).Trim())
Write-Output ('  version : ' + (((Select-String -Path (Join-Path $root 'moon.mod') -Pattern '^version').Line) -replace '.*=\s*"|"'))

# --- the pins the early stages read --------------------------------------------
#
# WHY THIS BLOCK SITS HERE, ABOVE EVERY STAGE, AND NOT AT THE BOTTOM OF THIS
# FILE BESIDE $PINNED AND $PERFN. Because these four pins are read by stages
# that run EARLY, and PowerShell runs a script top to bottom.
#
# 0.4.34 shipped them at the bottom, next to the other pin tables, and the
# self-scan stage read every one of them as the EMPTY STRING: the own-source
# notice table was compared against "" and the corpus stage would have compared
# the ParseError total against "". The stage reported
#
#     FAIL: the own-source notice table drifted from the pin.
#         pinned :
#         actual : =0
#
# and the blank after "pinned :" is the whole diagnosis. The MEASURED values
# were right -- expression-level 123, declaration-level 1461, both exactly the
# pins -- and the gate was still red, because it was comparing against
# nothing. A gate that prints the pinned value NEXT TO the measured one turns
# "the number is wrong" into "the number was never read".
#
# => 判据: A PIN MUST BE DEFINED BEFORE THE STAGE THAT READS IT, AND A GATE
# THAT COMPARES AGAINST A MISSING PIN MUST SAY SO OUT LOUD. Two things made
# this findable in one reading of the log: the stage printed the pin beside
# the measurement, and the empty-pin guard below refuses to run at all.
#
# The corpus pins further down ($PINNED, $PERFN, $CONTROL_N) are read by LATER
# stages and are pinned at the point of use. These four are read by earlier
# ones, so they are pinned here.
#

# THE README'S OTHER PUBLISHED NUMBERS, pinned here for the same reason the
# corpus numbers are: they are MEASURED on every release gate, and the README
# gate DERIVES its expectations from this table.
#
# 0502 found the cost of not doing this. The README published a rendered
# `ParseError` count and a "what the suppression hides" pair, and BOTH were
# quoted from an OLDER mechanism: the first was measured before the `match`
# arms were read, the second before the suppression was narrowed per binding.
# Nothing noticed, because nothing re-measured them -- a published number that
# is not re-measured is a number that is wrong, and it is wrong silently.
#
#   $NOTICE_TOTAL    the notices over the seven pinned corpora AND this
#                    repository's own source, with the per-file printing cap
#                    lifted. Without the cap lifted this number is a property
#                    of the CAP and not of the corpus.
#
#                    IT WAS THE RENDERED `ParseError` LINES BEFORE 0506, and
#                    it is the tree's NOTICE COUNT now, because 0506 stopped
#                    rendering every notice: a notice is printed one per line
#                    only when it can hide a finding, and the rest are counted
#                    by shape. The number the README publishes did not move --
#                    the number of notices is the same -- but the MEASUREMENT
#                    that produces it did, and a measurement that reads a
#                    rendering the tool no longer produces measures nothing.
#   $SELF_NOTICES    the own-source notices by kind, the same cap-lifted
#                    measurement. The README's table IS this string, and the
#                    order is the order the README prints.
#   $SELF_PRINTED    the own-source notices that lie INSIDE some function's
#   $SELF_AGGREGATED extent -- the ones that can hide a finding, and are
#                    printed one per line -- and the ones that lie outside
#                    every function's extent, which hide nothing and are
#                    counted by shape.
#
#                    THE SPLIT IS THE ANALYZER'S OWN GEOMETRY, and it is not
#                    the shape-of-the-message proxy that used to stand in for
#                    it. The proxy put 1,023 of the core corpus's notices in
#                    the expression-level class and 9,073 in the other; the
#                    geometry puts 1,144 and 8,952. The geometry is right in
#                    BOTH directions: it counts 132 expression notices the
#                    proxy's list did not name, and it excludes 11 top-level
#                    expressions the proxy called expression-level.
$NOTICE_TOTAL = '19636'
$SELF_FILES = '189'
$SELF_NOTICES = 'test declaration=1427|if expression=104|struct declaration=62|derive declaration=54|enum declaration=25|anonymous function literal=18|const declaration=6|short lambda=2|try expression=1'
$SELF_PRINTED = '125'
$SELF_AGGREGATED = '1574'
#   $SUPPOFF_LOCAL   what the region suppression hides, measured by
#   $SUPPOFF_PARAM   `_verify/measure_suppression_off.ps1` with the
#                    suppression switched OFF.
$SUPPOFF_LOCAL = '597'
$SUPPOFF_PARAM = '1137'

#   $RAISEQ_REACH   the reach of the `raise?` construct 0503 fixed, measured by
#                   `_verify/measure_0503_reach.ps1`: the return-position sites
#                   and the files carrying them, in the pinned core corpus.
#   $RAISEQ_OTHERS  the same measurement over the other six corpora and this
#                   analyzer's own source. It is ZERO, and it is pinned because
#                   "the reach is confined to core" is a claim, not a remark.
$RAISEQ_REACH = '188|33'
$RAISEQ_OTHERS = '0'

# THE EMPTY-PIN GUARD. A pin that is empty is not a pin -- it is a comparison
# against nothing, and it fails in the most confusing way there is: the pinned
# value printed next to the measured one comes out BLANK, and a reader has to
# notice the blank before they can believe the number. The self-scan stage
# printed "pinned : " with nothing after it, and that blank is the only reason
# the bug was one reading away from being "the measurement drifted". A stage
# that had compared silently would have passed.
$emptyPins = @()
if ([string]::IsNullOrWhiteSpace($NOTICE_TOTAL)) { $emptyPins += 'NOTICE_TOTAL' }
if ([string]::IsNullOrWhiteSpace($SELF_FILES))    { $emptyPins += 'SELF_FILES' }
if ([string]::IsNullOrWhiteSpace($SELF_NOTICES))  { $emptyPins += 'SELF_NOTICES' }
if ([string]::IsNullOrWhiteSpace($SELF_PRINTED))  { $emptyPins += 'SELF_PRINTED' }
if ([string]::IsNullOrWhiteSpace($SELF_AGGREGATED)) { $emptyPins += 'SELF_AGGREGATED' }
if ([string]::IsNullOrWhiteSpace($SUPPOFF_LOCAL)) { $emptyPins += 'SUPPOFF_LOCAL' }
if ([string]::IsNullOrWhiteSpace($SUPPOFF_PARAM)) { $emptyPins += 'SUPPOFF_PARAM' }
if ($emptyPins.Count -gt 0) {
  Write-Output ('FATAL: the pins ' + ($emptyPins -join ', ') + ' are empty.')
  Write-Output '  A gate that compares against an empty pin compares against nothing.'
  Write-Output '  A pin must be DEFINED ABOVE the stage that reads it.'
  if (-not $SelfTest) { exit 1 }
}

# --- the self-test ------------------------------------------------------------
# Shown to go red, because this gate's whole job is to go red. Three assertions,
# each of which the previous shape would have passed by accident.
if ($SelfTest) {
  Write-Output 'release gate -- SELF TEST'
  Write-Output ''
  Write-Output 'A. a stage whose body FAILS must report FAILED'
  Stage 'selftest: failing body' {
    Write-Output 'this body prints several lines on purpose'
    Write-Output 'and they must not turn a failure into a pass'
    $script:stageOk = $false
  }
  $a = (-not $script:lastOk)
  Write-Output ("   lastOk = {0}  -> {1}" -f $script:lastOk, $(if ($a) { 'PASS' } else { 'FAIL' }))

  Write-Output ''
  Write-Output 'B. a stage whose body throws must report FAILED'
  Stage 'selftest: throwing body' { throw 'deliberate' }
  $b = (-not $script:lastOk)
  Write-Output ("   lastOk = {0}  -> {1}" -f $script:lastOk, $(if ($b) { 'PASS' } else { 'FAIL' }))

  Write-Output ''
  Write-Output 'C. a stage whose body succeeds must report ok'
  Stage 'selftest: passing body' { Write-Output 'fine' }
  $c = $script:lastOk
  Write-Output ("   lastOk = {0}  -> {1}" -f $script:lastOk, $(if ($c) { 'PASS' } else { 'FAIL' }))

  Write-Output ''
  if ($a -and $b -and $c) {
    Write-Output 'SELF TEST PASSED: a failing stage is distinguishable from a passing one.'
    exit 0
  }
  Write-Output 'SELF TEST FAILED: this gate cannot tell a failure from a pass. Do not trust a run.'
  exit 1
}

$failed = @()

# --- 1..3  formatting, check, all three test targets -------------------------
Stage 'moon fmt --check' { Run-Moon @('fmt','--check') }
if (-not $script:lastOk) { $failed += 'fmt' }

Stage 'moon check --deny-warn' { Run-Moon @('check','--deny-warn') }
if (-not $script:lastOk) { $failed += 'check' }

foreach ($t in @('js','wasm','wasm-gc')) {
  Stage ("moon test --target " + $t) { Run-Moon @('test','--target',$t,'--deny-warn') }
  if (-not $script:lastOk) { $failed += ('test:' + $t) }
}

Stage 'moon build --target wasm' { Run-Moon @('build','--target','wasm') }
if (-not $script:lastOk) { $failed += 'build:wasm' }
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
if (-not (Test-Path $wasm)) {
  Write-Output ''
  Write-Output '  no wasm artifact -- the scan stages cannot run.'
  $failed += 'build:wasm'
}

# --- 3a  THE HOST CONTRACT OF THE ARTIFACT -----------------------------------
# 0.4.38 shipped a wasm that a user could not RUN.
#
# The published wasm is not self-contained: it imports 90 symbols from
# `moonbitlang/async`, and the HOST has to supply every one of them when the
# module is instantiated. `moonx` supplies them from the async package BUNDLED
# WITH THE USER'S TOOLCHAIN -- not from the version this package pins. The
# `moonbitlang/async` 0.22.5 -> 0.22.6 bump added three of them
# (`thread_pool/make_write_console_job`, `thread_pool/make_read_console_job`,
# `thread_pool/get_read_console_result`), and 0.22.6 declares those three as
# externs the host must provide. A user on a toolchain bundling 0.22.5 got:
#
#     LinkError: WebAssembly.Instance(): Import #5 "moonbitlang/async"
#     "thread_pool/make_write_console_job": function import requires a callable
#
# Nothing here saw it, because every gate in this repo runs the analyzer FROM
# SOURCE. The published BYTES were never linked against a host, so the artifact's
# host requirements were a fact no gate could see.
#
# So the RELEASE build is built here and audited against the pinned contract in
# `_verify\host_requirements.txt`. The debug build is audited too: both are
# audited, and the contract covers both.
Stage 'moon build --release --target wasm' { Run-Moon @('build','--release','--target','wasm') }
if (-not $script:lastOk) { $failed += 'build:wasm:release' }

Stage 'the host contract of the artifact (what a user''s toolchain must supply)' {
  Run-Gate (Join-Path $root '_verify\check_host_requirements.ps1')
}
if (-not $script:lastOk) { $failed += 'host-requirements' }

# --- 3b  the grammar probe's own verdicts can go red ---------------------------
# Placed after the wasm build because the control reads the scanner through it,
# and before the mutation gates because a probe that reports "no gaps" when it
# found one would make every parser comment that cites it worthless -- which is
# what 0.4.30 found, twice, in one file: a filtered run that dropped the canary,
# and a `.Count` on a scalar that silently suppressed both tallies.
$GP = Join-Path $root '_verify\grammar_probe_control.ps1'
if (-not (Test-Path $GP)) {
  Write-Output ''
  Write-Output 'MISSING: _verify\grammar_probe_control.ps1'
  $failed += 'grammar-probe-control'
} else {
  Stage 'grammar probe control (its verdicts can go red)' {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $GP 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($ln in ($o -split "`r?`n")) {
      if ($ln -match '(PASS|FAIL|  - )') { Write-Output ('  ' + $ln.Trim()) }
    }
    if ($code -ne 0) { $script:stageOk = $false }
  }
  if (-not $script:lastOk) { $failed += 'grammar-probe-control' }
}

# --- 4  self-scan ------------------------------------------------------------
if ($failed.Count -eq 0) {
  Stage 'self-scan (own source)' {
    $text = Scan-Tree $wasm $root
    $sum = Get-Summary $text
    Write-Output ('  ' + $sum)
    $files  = [int]([regex]::Match($sum, 'files=(\d+)').Groups[1].Value)
    $parsed = [int]([regex]::Match($sum, 'parsed=(\d+)').Groups[1].Value)
    $act    = [int]([regex]::Match($sum, 'actionable=(\d+)').Groups[1].Value)
    # actionable must be 0 AND every file must parse. The second condition is what
    # stops a scan that crashed half-way from reading as a clean tree.
    if ($act -ne 0) { Write-Output '  FAIL: actionable is not 0.'; $script:stageOk = $false }
    elseif ($files -ne $parsed) { Write-Output ("  FAIL: parsed {0} of {1} files." -f $parsed, $files); $script:stageOk = $false }
    else { Write-Output ('  ' + $files + '/' + $files + ' parsed, actionable 0') }

    # THE OWN-SOURCE FILE COUNT IS PINNED, and it was NOT until 0504.
    #
    # The README publishes it -- "Measured on this project's own source (178
    # files)" -- and NOTHING checked it: the release gate measured `$files` and
    # used it only to compare against `$parsed`, and `check_readme_links.ps1`
    # compared the README against a LITERAL 178 written into the gate itself.
    # A literal inside the gate that checks the README is a number that can
    # only ever agree with itself, and the file count moved twice -- 178 to 179
    # with 0503's test file, and 179 to 181 with 0504's two -- without
    # anything objecting.
    #
    # So the count is a PIN now, it is measured here, and the README gate
    # DERIVES its string from this pin instead of carrying its own.
    if ("$files" -ne $SELF_FILES) {
      Write-Output ('  FAIL: the own-source file count is ' + $files + ', pinned ' + $SELF_FILES + '.')
      $script:stageOk = $false
    } else {
      Write-Output ('  the own-source file count matches the pin (' + $files + ')')
    }

    # THE OWN-SOURCE NOTICES. 0506 changed what a scan RENDERS: a notice is
    # printed one per line only when it can HIDE a finding -- when its region
    # lies inside some function's extent -- and every other notice is counted
    # by shape in one `NOTICES` table. So the gate reads the analyzer's OWN
    # numbers -- the table's TOTAL line -- instead of counting rendered lines,
    # and it checks that the halves reconcile against the SUMMARY.
    #
    # 0508: the demotion puts the low-confidence findings on a line of their
    # own as well, so "the rendered lines" are the NOTICE lines now -- the
    # scope limits and the demoted findings together -- and the ParseError
    # family has its own check beside the reconciliation.
    $tab = Get-NoticeTable $text
    $sumNotices = [int]([regex]::Match($sum, 'notices=(\d+)').Groups[1].Value)
    $rendered = Get-NoticeLineCount $text
    $peDefect = Get-ParseErrorDefectCount $text
    $rowSum = 0
    foreach ($r in $tab.Rows) { $rowSum += $r.N }
    if ($sumNotices -ne 0 -and -not $tab.Present) {
      Write-Output ('  FAIL: the scan has ' + $sumNotices + ' notices but printed no NOTICES table.')
      $script:stageOk = $false
    } elseif ($tab.Notices -ne $sumNotices) {
      Write-Output ('  FAIL: the NOTICES table says ' + $tab.Notices + ' notices, the SUMMARY says ' + $sumNotices + '.')
      $script:stageOk = $false
    } elseif (($tab.Printed + $tab.Aggregated) -ne $sumNotices) {
      Write-Output ('  FAIL: printed ' + $tab.Printed + ' + aggregated ' + $tab.Aggregated + ' is not the ' + $sumNotices + ' notices.')
      $script:stageOk = $false
    } elseif ($rowSum -ne $tab.Aggregated) {
      Write-Output ('  FAIL: the table''s rows add up to ' + $rowSum + ', its TOTAL line says ' + $tab.Aggregated + '.')
      $script:stageOk = $false
    } elseif ($rendered -ne $tab.Printed) {
      Write-Output ('  FAIL: ' + $rendered + ' rendered notice lines, the table says ' + $tab.Printed + ' were printed.')
      $script:stageOk = $false
    } elseif ($peDefect -ne 0) {
      Write-Output ('  FAIL: ' + $peDefect + ' ParseError-family findings render as something other than a notice.')
      $script:stageOk = $false
    } else {
      Write-Output ('  the notices reconcile: ' + $sumNotices + ' = ' + $tab.Printed + ' printed + ' + $tab.Aggregated + ' aggregated; ' + $rendered + ' rendered notice lines, and no ParseError-family defect')
    }
    $script:selfNotices = $sumNotices
    $script:selfPrinted = $tab.Printed
    $script:selfAggregated = $tab.Aggregated

    # THE OWN-SOURCE NOTICES BY KIND. The README publishes this table, so the
    # table is measured here and PINNED.
    #
    # 0506: THE TABLE IS BUILT FROM BOTH HALVES -- the `NOTICES` table's rows
    # carry the notices that hide nothing, and the rendered notice lines carry
    # the ones that are printed -- so the breakdown is COMPLETE. Before 0506 it
    # was built from the rendered lines alone, and after 0506 the rendered
    # lines alone are only half of the notices: a table built from them would
    # have lost every `test` declaration without saying so.
    $byKind = @{}
    foreach ($r in $tab.Rows) {
      $k = Get-NoticeKind $r.Message
      if ($byKind.ContainsKey($k)) { $byKind[$k] = $byKind[$k] + $r.N } else { $byKind[$k] = $r.N }
    }
    foreach ($m in [regex]::Matches($text, '(?m)^\d+:\d+ - notice: (.+?) \([A-Za-z]+\) \[')) {
      $k = Get-NoticeKind $m.Groups[1].Value
      if ($byKind.ContainsKey($k)) { $byKind[$k] = $byKind[$k] + 1 } else { $byKind[$k] = 1 }
    }
    $kindSum = 0
    foreach ($k in $byKind.Keys) { $kindSum += $byKind[$k] }
    if ($kindSum -ne $sumNotices) {
      Write-Output ('  FAIL: the kinds add up to ' + $kindSum + ', the notices are ' + $sumNotices + '.')
      $script:stageOk = $false
    }
    $order = @($SELF_NOTICES -split '\|' | ForEach-Object { ($_ -split '=')[0] })
    $got = (($order | ForEach-Object { $_ + '=' + [int]$byKind[$_] }) -join '|')
    if ($got -ne $SELF_NOTICES) {
      Write-Output '  FAIL: the own-source notice table drifted from the pin.'
      Write-Output ('      pinned : ' + $SELF_NOTICES)
      Write-Output ('      actual : ' + $got)
      $script:stageOk = $false
    } else {
      Write-Output ('  the notice table matches the pin (' + $order.Count + ' kinds)')
    }
    # A KIND THAT IS NOT IN THE PIN is a new scope limit, and the README's
    # table would be missing a row. A pin that only compares the kinds it
    # knows cannot see that, so the set is compared as well as the counts.
    $extra = @($byKind.Keys | Where-Object { $order -notcontains $_ } | Sort-Object)
    if ($extra.Count -gt 0) {
      Write-Output ('  FAIL: notice kinds that the pin does not name: ' + ($extra -join ', '))
      $script:stageOk = $false
    }
    # THE SPLIT, and it is the analyzer's OWN geometry rather than a
    # shape-of-the-message proxy: the notices that lie inside some function's
    # extent are printed one per line, and the ones that lie outside every
    # function's extent hide nothing and are counted by shape.
    if ("$($script:selfPrinted)" -ne $SELF_PRINTED -or "$($script:selfAggregated)" -ne $SELF_AGGREGATED) {
      Write-Output ('  FAIL: printed ' + $script:selfPrinted + ' / aggregated ' + $script:selfAggregated +
                    ', pinned ' + $SELF_PRINTED + ' / ' + $SELF_AGGREGATED + '.')
      $script:stageOk = $false
    } else {
      Write-Output ('  printed ' + $script:selfPrinted + ', aggregated ' + $script:selfAggregated)
    }
  }
  if (-not $script:lastOk) { $failed += 'self-scan' }
}

# --- 4b  the README's own links, anchors, versions and counts ------------------
# The registry SERVES README.md, so a broken link there is a broken link on
# mooncakes.io -- and a README that quotes a count nobody re-measures is the same
# failure mode the per-function census had: a published number that can go
# missing silently. This stage checks the four things that actually rot:
# a relative link to a file that moved, a "#anchor" with no heading behind it,
# a version reference that names something other than the released version, and
# a count that no longer matches what the tools measured.
if ($failed.Count -eq 0) {
  $RL = Join-Path $root '_verify\check_readme_links.ps1'
  if (-not (Test-Path $RL)) {
    Write-Output ''
    Write-Output 'MISSING: _verify\check_readme_links.ps1'
    $failed += 'readme-links'
  } else {
    Stage 'README links, anchors, versions and counts' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $RL 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '(BROKEN|FAIL|VERIFY|MISSING)') { Write-Output ('  ' + $ln.Trim()) }
      }
      if ($code -ne 0) { $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'readme-links' }
  }
}

# --- 4c  the ROSTER of mutation gates, and the gate that checks it --------------
# The mutation gates are run from a list, and the list was kept BY HAND. A gate
# added to `_verify` but not to that list NEVER RUNS -- it is on disk, it is named
# like a gate, and a release run reports every gate green. A gate that does not
# run is indistinguishable from a gate that passes.
#
# This stage sits BEFORE the mutation gates on purpose: a release run costs about
# half an hour, and it should not spend that on a roster that is already known to
# be wrong. The self-test runs first, because a gate that has never been shown to
# go red is a comment -- it injects seven defects into a COPY of `_verify` in TEMP
# and requires the copy to fail with the right message.
if ($failed.Count -eq 0) {
  $GR = Join-Path $root '_verify\check_gate_roster.ps1'
  if (-not (Test-Path $GR)) {
    Write-Output ''
    Write-Output 'MISSING: _verify\check_gate_roster.ps1'
    $failed += 'gate-roster'
  } else {
    Stage 'gate roster: self-test (seven injected defects must be caught)' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $GR -SelfTest 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '(CAUGHT|MISSED|SELFTEST)') { Write-Output ('  ' + $ln.Trim()) }
      }
      if ($code -ne 0) { $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'gate-roster-selftest' }
  }
  if ($failed.Count -eq 0) {
    Stage 'gate roster: one harness, one list, and a count that matches' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $GR 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '(ROSTER|NEVER RUN|NOT ON THE SHARED|MISSING|LISTED BUT|FAIL)') { Write-Output ('  ' + $ln.Trim()) }
      }
      if ($code -ne 0) { $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'gate-roster' }
  }

  # --- 4c  the shared harness's own self-test ----------------------------------
  #
  # 0506. The harness has a FOURTH verdict now -- INCONCLUSIVE, for a run that
  # produced no summary AND no compiler diagnostic -- and a verdict path that
  # has never been shown to go red is a comment. This stage proves it goes red:
  # it takes a COPY of `_verify` in TEMP, breaks the copy's summary-line regex
  # for the MUTATION runs, and requires the copy's one-mutation gate to come out
  # INCONCLUSIVE, to FAIL, and to exit non-zero.
  #
  # It is here, BEFORE the mutation gates, for the same reason the notice-labels
  # stage is: it mutates a source file (in a copy of the tree, and restores it
  # byte-identically), and a mutation gate that had mutated a source file would
  # be read as part of it.
  if ($failed.Count -eq 0) {
    $HS = Join-Path $root '_verify\mutate_lib_selftest.ps1'
    if (-not (Test-Path -LiteralPath $HS)) {
      Write-Output ''
      Write-Output 'MISSING: _verify\mutate_lib_selftest.ps1'
      $failed += 'harness-selftest'
    } else {
      Stage 'the shared harness: the INCONCLUSIVE verdict, shown to go red' {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $HS 2>&1 | Out-String
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        foreach ($ln in ($o -split "`r?`n")) {
          if ($ln -match '(SELFTEST OK|FAIL|INCONCLUSIVE|NO RUN|RETRY)') { Write-Output ('  ' + $ln.Trim()) }
        }
        if ($code -ne 0) { $script:stageOk = $false }
      }
      if (-not $script:lastOk) { $failed += 'harness-selftest' }
      $stageName = 'the shared harness: the INCONCLUSIVE verdict, shown to go red'
      $seen = @($script:results | Where-Object { $_.Stage -eq $stageName }).Count
      if ($seen -ne 1) {
        Write-Output ''
        Write-Output ('MISSING STAGE: "' + $stageName + '" ran ' + $seen + ' time(s); it must run once.')
        $failed += 'harness-selftest'
      }
    }
  }
}

# --- 4d  the proof contracts in src/core must be HONEST -------------------------
# `moon prove src/core` is a command the README documents, and it had been
# failing since 2026-10-09 with two false `#proof_pure` annotations -- one of
# them enough to stop the whole file from proving -- and nothing noticed,
# because the release gate never ran it. This stage runs it and fails on the
# false-annotation class (error 4207).
#
# It does NOT fail on the known `map` limitation: `src/core` carries
# `IfaceSymTab`, whose fields are `Map[String, Bool]`, and the toolchain's proof
# prelude has no `Map` theory, so the generated Why3 file will not load. That is
# reported, not hidden -- see the script.
if ($failed.Count -eq 0) {
  $PC = Join-Path $root '_verify\check_prove_contracts.ps1'
  if (-not (Test-Path $PC)) {
    Write-Output ''
    Write-Output 'MISSING: _verify\check_prove_contracts.ps1'
    $failed += 'prove-contracts'
  } else {
    Stage 'proof contracts: no false #proof_pure' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $PC 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '(4207|contracts:|PROVE CONTRACTS|KNOWN)') { Write-Output ('  ' + $ln.Trim()) }
      }
      if ($code -ne 0) { $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'prove-contracts' }
  }
}

# --- 4e  WHAT THE REGISTRY WILL RECEIVE ---------------------------------------
# `.moonignore` decides what gets packaged. A rule that is never exercised is a
# comment, and an ignore file whose rules silently stop matching is a package
# that silently grows.
#
# MEASURED 2026-10-23: four scratch `COMMIT_*.md` files were TRACKED, and a
# tracked file is in the checkout CI publishes from -- so they reached the
# registry in every published version up to and including 0.4.33. The rules
# that exclude them are now in `.moonignore` and in `.gitignore`, and the
# thirteen files that were tracked and should not have been were removed from
# the index.
#
# This stage runs `moon package --list` -- the same command `moon publish`
# packages from -- and asserts BOTH directions: the junk is out, and the
# evidence is in. It is a LOCAL check of what would be published; stage 5b
# below then scans what WAS published.
if ($failed.Count -eq 0) {
  $PK = Join-Path $root '_verify\check_package_contents.ps1'
  if (-not (Test-Path $PK)) {
    Write-Output ''
    Write-Output 'MISSING: _verify\check_package_contents.ps1'
    $failed += 'package-contents'
  } else {
    Stage 'package contents: the junk stays out, the evidence stays in' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $PK 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '(PACKAGE OK|PACKAGE FAILED|\sFAIL)') { Write-Output ('  ' + $ln.Trim()) }
      }
      if ($code -ne 0) { $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'package-contents' }
  }
}

# --- 4f  A DECLARED SCOPE LIMIT IS NOT AN ERROR -------------------------------
# Every ParseError the tool rendered carried the label `error:`, including the
# ones that are not errors at all: "match expression is outside the analyzed
# subset; it was read but not analysed" is a DECLARED SCOPE LIMIT of this
# analyzer, and a reader who sees `error:` on it has been told their code is
# wrong when the analyzer is the one that did not read it.
#
# MEASURED 2026-10-30, with the per-file printing cap lifted so the count is
# the whole finding set: across the seven corpora and this repository's own
# source, 23,331 rendered ParseError lines, EVERY ONE of them a deliberate
# exclusion, and not one of the seventeen genuine-defect producers carrying
# the marker. So the fix moves no count -- and the corpus pins below are
# unchanged by it, which is the point: a LABEL fix that moved the numbers
# would be a behaviour change wearing a rendering change's clothes.
#
# The gate checks three things: the rendered output's contract, the four
# producer paths against the tool's OWN messages, and the source convention
# that keeps a new exclusion message from silently going back to being an
# `error:`. It is placed BEFORE the mutation gates on purpose -- it reads the
# tree, and a mutation gate that has mutated a source file would be read as
# part of it.
if ($failed.Count -eq 0) {
  $NL = Join-Path $root '_verify\check_notice_labels.ps1'
  if (-not (Test-Path $NL)) {
    Write-Output ''
    Write-Output 'MISSING: _verify\check_notice_labels.ps1'
    $failed += 'notice-labels'
  } else {
    Stage 'notice labels: a scope limit is a notice, a defect is an error' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $NL 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '(OK$|FAIL|NOTICE LABELS|note_skip call sites|deliberate producers|genuine producers)') { Write-Output ('  ' + $ln.Trim()) }
      }
      if ($code -ne 0) { $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'notice-labels' }
  }
}

# --- 4f2  THE FAMILY ROSTER -----------------------------------------------------
# 0507 added the STABLE FAMILY IDS, and the id table is HAND-ALLOCATED on
# purpose: deriving it from the enum's position would renumber every family
# after an insertion, which is the one thing an id must never do.
#
# Two tables are written out by hand -- `Family::id` and `family_by_id` -- and
# the compiler enforces the FIRST one (a new family breaks the build there)
# and NOTHING about the second (a missing arm in a string match simply never
# matches). A family whose id could not be selected in a profile and could not
# be named in a `nosec`, with nothing saying so, is exactly the kind of defect
# a reader cannot see.
#
# So the gate compares the two tables, and the enum, and it checks that the
# ids are CONTIGUOUS from MSA-001: a gap means a number was allocated and never
# used, and a family given a number in the middle of the run means every
# suppression written against that number now names a different family.
#
# It is placed here, before the mutation gates, for the same reason as the
# notice-labels stage: it reads the tree, and a mutation gate that has mutated
# a source file would be read as part of it.
if ($failed.Count -eq 0) {
  $FR = Join-Path $root '_verify\check_family_roster.ps1'
  if (-not (Test-Path $FR)) {
    Write-Output ''
    Write-Output 'MISSING: _verify\check_family_roster.ps1'
    $failed += 'family-roster'
  } else {
    Stage 'the family roster: one id each, contiguous, and reversible' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $FR 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '(FAIL|ROSTER OK|ROSTER FAILED|MISSING|ids:|members:|values:|names:)') { Write-Output ('  ' + $ln.Trim()) }
      }
      if ($code -ne 0) { $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'family-roster' }
  }
}

# --- 4g  the frame audit, per binding -----------------------------------------
# The gate checks that the frame audit judges each BINDING against the regions
# that can reach it: a binding declared after a region is judged, a binding
# declared before one is not, and a binding read ONLY inside a region is not
# judged at all. It is placed here, before the mutation gates, for the same
# reason as the notice-labels stage: it reads the tree, and a mutation gate
# that has mutated a source file would be read as part of it.
if ($failed.Count -eq 0) {
  $FA = Join-Path $root '_verify\check_frame_audit.ps1'
  if (-not (Test-Path $FA)) {
    Write-Output ''
    Write-Output 'MISSING: _verify\check_frame_audit.ps1'
    $failed += 'frame-audit'
  } else {
    Stage 'frame audit: a region silences the bindings it could have read, and no others' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $FA 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '(ok |FAIL|GATE OK|GATE FAILED)') { Write-Output ('  ' + $ln.Trim()) }
      }
      if ($code -ne 0) { $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'frame-audit' }
  }
}

# --- 4h  the match's ARMS, read end to end ------------------------------------
# 0502. A `match`'s arms used to be consumed whole by `skip_braces` -- a region
# the frontend deliberately did not analyse -- and a region put a HOLE in the
# frame of the enclosing function, which silenced the unused-local and
# unused-parameter checks for that WHOLE function.
#
# The gate checks that the arms ARE read, that the findings which come back are
# TRUE ones (a binding read only inside an arm body is not dead, and a `with`
# constraint READS its right-hand side), and that a match whose arms the subset
# cannot read falls back to the OLD behaviour EXACTLY -- the notice comes back
# and the frame is NOT judged, rather than half-read.
#
# It is placed here, before the mutation gates, for the same reason as the
# frame-audit stage above: it READS THE TREE, and a mutation gate that has
# mutated a source file would be read as part of it.
#
# IT IS NOT VACUOUS. The gate was shown to go red twice by injecting a defect
# into the analyzer's own source, rebuilding, and running it:
#
#   - the arm body is not walked        -> 12 checks fail, the negative
#     direction included (`live_local`, `live_param`);
#   - the `with` constraint is not recognised -> 2 checks fail, naming
#     `m6_with_constraint`.
#
# Both trees were restored byte-identically (SHA256 checked).
if ($failed.Count -eq 0) {
  $MA = Join-Path $root '_verify\check_match_arms.ps1'
  if (-not (Test-Path $MA)) {
    Write-Output ''
    Write-Output 'MISSING: _verify\check_match_arms.ps1'
    $failed += 'match-arms'
  } else {
    Stage 'match arms: the arms are read, the findings are true ones, and the fallback is exact' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $MA 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '(ok |FAIL|GATE OK|GATE FAILED)') { Write-Output ('  ' + $ln.Trim()) }
      }
      if ($code -ne 0) { $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'match-arms' }
  }
}

# --- 5  every mutation gate --------------------------------------------------
$gates = @('0412','0413','0418','0419','0420','0421','0422','0423','0424','0425','0426','0427','0428','0429','0430','0431','0432','0433','0434','0435','0436','0437','0438','0439','0440','0441','0442','0443','0444','0445','0446','0447','0449','0450','0452','0453','0454','0455','0456','0457','0458','0459','0460','0461','0462','0463','0464','0465','0466','0467','0468','0469','0470','0471','0472','0473','0474','0475','0476','0477','0478','0479','0480','0481','0482','0483','0484','0485','0486','0487','0488','0489','0490','0491','0492','0493','0494','0495','0496','0500','0501','0502','0503','0504','0506','0507','0508')
if ($SkipMutations) {
  Write-Output ''
  Write-Output ('=== ' + $gates.Count + ' mutation gates SKIPPED (-SkipMutations) ===')
  $script:results += [pscustomobject]@{ Stage = 'mutation gates'; Ok = $true; Seconds = 0 }
} elseif ($failed.Count -gt 0) {
  Write-Output ''
  Write-Output '=== mutation gates SKIPPED (an earlier stage failed) ==='
  $script:results += [pscustomobject]@{ Stage = 'mutation gates'; Ok = $false; Seconds = 0 }
  $failed += 'mutation-gates'
} else {
  foreach ($g in $gates) {
    $p = Join-Path $root ("_verify\mutate_" + $g + ".ps1")
    if (-not (Test-Path $p)) { Write-Output ("MISSING GATE: " + $p); $failed += ('missing-gate:' + $g); continue }
    Stage ("mutation gate " + $g) { Run-Gate $p }
    if (-not $script:lastOk) { $failed += ('mutate:' + $g) }
  }
}

# --- 5a  the published-self-scan gate's OWN self-test -------------------------
# `selfscan_published.ps1` is a gate, and a gate that has never been shown to go
# red is a comment. This stage runs that gate against TWO REAL CAPTURES committed
# under `_verify\fixtures\`:
#
#   `selfscan_empty_tree_0430.out` -- the 2026-10-20 scan of the published 0.4.30
#     after the registry download timed out. The package directory was created
#     empty, the scanner read ZERO files, printed a well-formed SUMMARY carrying
#     `actionable=0`, and the gate reported GATE OK. It must now FAIL.
#   `selfscan_healthy_0429.out` -- the same day's scan of the published 0.4.29
#     tree: 68 files, parsed 68/68, actionable=0. It must still PASS.
#
# The third check is the one that carries the evidence: the EMPTY capture must
# PASS with the tree-presence guard DISARMED. Without that, a gate that was red
# for some other reason -- a changed version assertion, a reworded message --
# would look exactly like a working guard.
#
# It runs before 5b because 5b uses the gate, and it is FAST and OFFLINE: it
# fetches nothing. The live stage below is the one that depends on the network.
$ST = Join-Path $root '_verify\selftest_selfscan_published.ps1'
if (-not (Test-Path $ST)) {
  Write-Output ''
  Write-Output 'MISSING: _verify\selftest_selfscan_published.ps1'
  $failed += 'selfscan-selftest'
} else {
  Stage 'published self-scan self-test' {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $ST 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($ln in ($o -split "`r?`n")) {
      if ($ln -match '(^\s+(ok|FAIL|skip)\s)|(SELF-TEST)|(^\s*CHECK )') { Write-Output $ln }
    }
    if ($code -ne 0) { $script:stageOk = $false }
  }
  if (-not $script:lastOk) { $failed += 'selfscan-selftest' }
}

# --- 5b  the PUBLISHED package, scanned by the analyzer that shipped ----------
# Placed after the mutation gates because it is the slowest stage that depends on
# something outside this repository. It is also the only one that exercises the real
# delivery path: mooncakes compiles the artifact server-side and `moonx` runs THAT,
# so a green local suite says nothing about whether the shipped wasm works. It runs
# outside the repo on purpose -- `moonx` materialises into `.repos/` relative to the
# current directory, and writing the analyzer into that tree would change every
# corpus baseline measured since.
#
# THIS STAGE IS A POST-PUBLISH CHECK, and the ORDER of the release is what makes that
# true. `selfscan_published.ps1` asks the registry for the version in `moon.mod` and
# asserts the tree it read IS that version -- because a scan of a DIFFERENT package
# would still be able to print `actionable=0`. So once `moon.mod` names a version
# that has not been published yet, this stage CANNOT pass: the registry has nothing
# to serve, `moonx` prints nothing, and the stage aborts with "moonx produced no
# output. That is not a clean scan."
#
# Measured 2026-10-20, cutting 0.4.30: the stage aborted exactly that way. The
# diagnosis was one command -- `selfscan_published.ps1 -Coordinate @0.4.29` scanned
# the PUBLISHED tree clean (68 files, actionable=0) and failed ONLY the version
# assertion, because 0.4.30 was not on the registry yet. A registry that serves
# nothing and a broken scan print the same line, and only the coordinate run tells
# them apart.
#
# So the release order is:
#   1. the local gate -- and `-SkipMutations` runs the corpus pins and the own-source
#      self-scan, which is what has to be green BEFORE the version is bumped;
#   2. bump `moon.mod`, sync the READMEs, commit, tag, push the tag -- CI publishes;
#   3. THIS STAGE, against the version that was just published.
#
# And a run that aborts here before step 2 has NOT found a defect: it has found an
# ordering fact. The corpus comparison after it is gated on `$failed`, so an aborted
# run leaves the pins UNMEASURED -- run them with `-SkipMutations` rather than
# reading the abort as a regression.
#
# AND A GREEN STAGE HERE IS NOT, BY ITSELF, EVIDENCE THAT THE PACKAGE WAS READ.
# Measured 2026-10-20, AFTER 0.4.30 was published: this stage reported
#
#     GATE OK: the published 0.4.30 scans its own shipped source clean.
#
# on a scan that had read NOTHING. The registry download had timed out, `moonx`
# created the package directory EMPTY, and the scanner printed a well-formed
# report of an empty tree -- `SCANNED 0 files`, `PARSED 0/0`, `actionable=0` --
# which is a TRUE statement about nothing, and the sum of true statements about
# nothing is GATE OK. The script's own header warned against this ("EMPTY OUTPUT
# IS A FAILURE, NOT A ZERO"); the missing guard was one level down, for a scan
# that printed a SUMMARY and read no files.
#
# `selfscan_published.ps1` now asserts the tree is really there -- the scanned
# file count must be GREATER THAN ZERO, and the package's own `moon.mod` must not
# be in the SKIP list -- and stage 5a above proves that guard can go red, on a
# committed copy of that very capture. A green stage now means a tree was read.
#
# => 判据: a vacuous pass is worse than a red gate. A gate that reports OK on a
# scan of nothing has told the release that the shipped artifact is clean, and
# the shipped artifact was never read.
$SP = Join-Path $root '_verify\selfscan_published.ps1'
if ($SkipMutations) {
  Write-Output ''
  Write-Output '=== published-package self-scan SKIPPED (-SkipMutations) ==='
} elseif ($failed.Count -gt 0) {
  Write-Output ''
  Write-Output '=== published-package self-scan SKIPPED (an earlier stage failed) ==='
} elseif (-not (Test-Path $SP)) {
  Write-Output ''
  Write-Output 'MISSING: _verify\selfscan_published.ps1'
  $failed += 'selfscan-published'
} else {
  Stage 'published package self-scan' {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $SP 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($ln in ($o -split "`r?`n")) {
      if ($ln -match '(SUMMARY|SCANNED|Latest version|ABORT|FAIL|actionable)') { Write-Output $ln }
    }
    if ($code -ne 0) { $script:stageOk = $false }
  }
  if (-not $script:lastOk) { $failed += 'selfscan-published' }
}

# --- 6  corpus comparison ----------------------------------------------------
# Measured WITH --extern-iface-dir .repos on this tree. Another set of
# numbers is in circulation that was taken WITHOUT that flag and is not
# comparable: proton reads 2142 that way and 2107 with it.
#
# The 0.4.30 move, and it is worth stating what each change did rather than only
# where it landed:
#   moui   parsed 534 -> 547 -> 571. The `match` subject on the next line, then
#          an arrow lambda in EXPRESSION position -- which turned out to be the
#          largest single cause all along, and which I had ranked wrong for
#          several increments because the scanner's reason strings for it are
#          "unexpected token `:`" and "expected `)`".
#   async  actionable 13 -> 14, proton 54 -> 61. NOT new defects: these are
#          findings that an over-permissive lookahead in `at_lambda_head` was
#          HIDING. Bounding that scan made it precise, and eight latent false
#          positives became visible:
#            4x `undefined name 'noraise'`   proton, `fn f() -> T noraise {`
#            3x `no visible binding for 'InvalidSetting'`  proton, a suberror
#                variant used in a DIFFERENT file from its declaration
#            1x `undefined name 'Waiting'`    async, same cross-file shape
#          Verified by A/B, not assumed: the same two corpora were rescanned
#          with the guard removed (gate 0434's M4) and with the bounds removed
#          (M3). Both hardenings present -> the 8 rows appear. Guard removed
#          alone -> they do NOT, because the bounds stop the scan first. Bounds
#          removed alone -> they do NOT, because the guard stops the scan first.
#          Both removed -> the original failure, `PARSED 0/1`.
#          So `noraise` is a real missing production and the other four are the
#          known per-file `enum_ctors` limitation, both recorded rather than
#          re-hidden: a lookahead wide enough to eat a `=>` sixty lines away is
#          not a reading worth keeping.
#
#   moui   parsed 571 -> 576, and +5 rather than the +4 the blocker list
#          predicted: `..<=` also unblocks one file whose first error was
#          something else entirely and was only reachable afterwards.
#   async  notices 962 -> 964, unreliable 2269 -> 2266, actionable UNCHANGED at
#          14. Two `..<=` uses were already inside files that parsed, and each
#          now emits the inclusive-end subset notice instead of counting as
#          unreadable. Nothing else moved.
#
# The `is Type::Ctor` move, and the ranking it corrects:
#   moui   parsed 576 -> 581, exactly the 5 files the re-rank named, and NOT one
#          more. unreliable 475 -> 406, notices 3955 -> 3999: 69 findings that had
#          been withheld past an unreadable boundary are now read.
#   proton parsed UNCHANGED at 101, actionable UNCHANGED at 61, unreliable
#          950 -> 927. proton has `is` patterns already inside files that parsed,
#          so this removes 23 unreadable findings and adds no defect.
#   The other four corpora are byte-identical to the previous pin. A change that
#          moves one corpus and leaves five alone is the expected shape here, and
#          is why the pin is per-corpus rather than one total.
#
# AND THE RANKING WAS WRONG AGAIN, in a new way. The backlog called this "`is`
# pattern in EXPRESSION position". `parse_is` has existed at the right precedence
# tier for several releases; what was missing is that `parse_is_pattern` never
# consumed the `::` of a QUALIFIED head, because the lexer has no `TColonColon`
# and `::` is two `TColon` tokens. The scanner's reason string therefore read
# "unexpected token `:`" on a line whose only `:` is a path marker -- which is the
# fourth time a reason string has been the wrong thing to rank by, and the fourth
# time `blockers.ps1` (which joins each reason back to its blocking SOURCE LINE)
# gave the opposite answer.
#
# The same re-rank turned up a gap with 48 sites and ONE blocked file.
# `is @pkg.Type::Ctor` does not parse at all -- the head token is `@`, not a name.
# Scanning each of moui's 16 such files ALONE (`_verify/pkg_head_impact.ps1`):
# 15 come back parsed, because their site sits inside a skipped `test` block, and
# exactly one -- `backend/macos/macos_services.mbt` -- is blocked. That file is
# also one of the four that print no `PARTIAL` line, so cross-referencing it
# against `blockers.ps1` gives OVERLAP 0 and the gap reads as free. ⇒ 判据: a
# lower bound that agrees with "no problem" is not evidence of no problem. Pinned
# as a KNOWN LIMIT in `parser_0436_test.mbt`, not fixed here.
#
# The `(expr : Type)` move, and the first UNDER-delivery of the round:
#   moui   parsed 581 -> 583. The blocker list named SIX files behind this
#          construct and only TWO came free. The other four fail EARLIER, on
#          something else, and were never reachable by fixing the ascription --
#          which is what "the blocker list ranks by FIRST error" means, and it
#          is now the third increment in a row where the list's count and the
#          delivered count disagree (the `is` one delivered +5 against +5, the
#          `..<=` one +5 against +4, this one +2 against +6).
#
#          So a row count in `blockers.ps1` is NOT a forecast, and ranking by it
#          is a heuristic rather than a measurement. Delivered so far: `is` +5,
#          `..<=` +5, ascription +2 -- which does not preserve the order the
#          lists gave.
#          unreliable 406 -> 335 and withheld 51 -> 34: 71 findings that were
#          withheld past an unreadable boundary are now read. notices rose
#          3999 -> 4050, which is the expected direction -- a file that parses
#          produces subset-exclusion notices a file that stops early cannot.
#   The other FIVE corpora are byte-identical to the previous pin, proton
#   included. A change that moves one corpus and leaves five alone is the shape
#   to expect from a construct no other corpus uses.
#
# The scope of that fix is narrower than the six lines suggested, and the
# toolchain settled it rather than convenience. Four forms, one package each,
# canary beside every one:
#   `('0' : Int)`                  MOON-OK  <- the only legal form, implemented
#   `let y = 1 : Int`              MOON-BAD (no parentheses: rejected)
#   `(1 : Int, 2)`                 MOON-BAD (ascription on a tuple element)
#   `(s : Int)` where `s : String` MOON-BAD (so: an ASSERTION, not a coercion)
#
# The last one is why there is NO subset-exclusion notice, and it is the mirror
# of gate 0435's `..<=`. That one discards a value too and DOES get a notice,
# because an inclusive end changes n iterations into n+1. An ascription changes
# nothing at runtime -- the compiler has already checked the type -- so
# announcing a subset exclusion there would report a loss that does not happen.
# Gate 0437's M3 invents exactly that notice and is killed by a CONTROL that
# compares the two spellings' report counts, not by a positive test.
#
# The `value[:]` move -- the largest single jump of the round, and the one that
# COST something:
#   moui   parsed 583 -> 590 (+7, the largest of the round). unreliable 335 -> 246
#          and withheld 34 -> 2: 87 findings that were withheld past an unreadable
#          boundary are now read. The blocked set falls 25 -> 18.
#   proton parsed 101 -> 103, unreliable 927 -> 914
#   async  parsed 226 -> 227, unreliable 2266 -> 2199
#   labeler and moonbit_image byte-identical in parsed; labeler's unreliable
#          332 -> 320
#
#   *** moui actionable 0 -> 1, proton actionable 61 -> 63. ***
#   The first time in this release cycle that reading MORE files has raised an
#   actionable anywhere, and it is not a regression -- but it is not free either,
#   so here is the whole accounting, file by file, rather than "no new defects":
#
#     moui   backend/macos/macos_native_ime.mbt:437  parameter 'prefix' may not
#            be used (UnusedParam, structural). `prefix` IS used, at line 442,
#            inside a `catch { }` body. The postfix `catch` arm consumes its
#            block with `skip_braces`, so a read that happens ONLY there is
#            invisible. That limitation is PINNED as a KNOWN LIMIT at
#            `parser_0432_test.mbt:155` and re-pinned for the deferred form at
#            `pipeline_0433_test.mbt:172`, whose note already records "proton
#            facade_bridge.mbt:584 and 17 other lines in the six corpora".
#
#     proton internal/native/app_control.mbt:5  undefined name 'noraise'
#            (structural+type). `parse_raise_effect` handles `!` and `raise E`
#            but not `noraise`, which `moonfiles.mbt`'s own `is_error_modifier`
#            lists as one of four. A recorded missing production.
#
#     proton updater/hex.mbt:22 and :45  no visible binding for
#            'MalformedSignature' (structural, x2). A suberror variant used in a
#            DIFFERENT file from its declaration -- the per-file `enum_ctors`
#            limitation, already recorded, and the same shape as the
#            'InvalidSetting' x3 rows from the 0.4.30 A/B.
#
#   All three are pre-existing limitations of this analyzer on code `moon check`
#   accepts; none is caused by the slice change, which only made the files
#   readable. This is the shape README.md already describes: reading more files
#   raises false positives before lowering them.
#
#   It is still the first time moui's actionable has left 0, and that number is
#   the standing objective's own metric. The pin moves UP with the reason
#   written here rather than quietly, and fixing the `catch`-body limitation is
#   the way to move it back -- it is now the cheapest thing on the board, since
#   the finding is already located and already pinned as a defect.
#
# --- 0.4.30, the catch-body fix: moui back to 0, proton UP by 15 ---------------
#
# FIXED, in 0439: the postfix `catch` arm parses its handler arms instead of
# consuming them with `skip_braces`, so a parameter read ONLY inside a handler is
# seen. The finding named above is gone, and the same fix removed proton's
# `facade_paths.mbt:473` `parameter 'label' may not be used` — the second
# measured instance of the identical defect, recorded since 0432.
#
#   moui     actionable  1 -> 0    parsed 590 UNCHANGED
#   async    actionable 14 -> 12   parsed 227 UNCHANGED
#   proton   actionable 63 -> 78   parsed 103 UNCHANGED
#
# proton's +15 ARE ALL `no visible binding for '<a suberror variant>'`, and every
# one is inside a catch body that used to be skipped. `ipc/protocol.mbt:260` is
# the clearest:
#
#     @json.parse(raw) catch {
#       err => raise MalformedJson(detail=err.to_string())
#     }
#
# That is the per-file `enum_ctors` harvest limitation already recorded in the
# hex.mbt rows above — a suberror variant used in a DIFFERENT file from its
# declaration. Reading the body makes the `raise` visible to the resolver, and
# the resolver does not have the variant. It is the same trade the README
# describes, in the same direction it has gone before, paid in false positives
# rather than in unread files.
#
# `parsed=` IS UNCHANGED ON ALL SIX, and that is the number this gate exists to
# protect. It was NOT unchanged on the first attempt: with the arms parsed and no
# guard, proton `facade_locale.mbt` went from `parsed` to `not-parsed`, because
# its handler carries an `@xlog` `<?` payload that is not in the subset. M7 in
# `mutate_0439.ps1` is that regression, and `catch_group_has_log_payload` is the
# guard that holds `parsed=` at 103.
#
# --- the per-increment narrative now lives in NARRATIVE.md ------------------
#
# Everything between here used to be in this file: one comment block per increment, 1270
# lines of it at 0470, against 262 lines of code in the whole script. It was moved by
# `_verify/_split_release_narrative.ps1` -- verbatim, minus the leading comment marker.
#
# WHAT STAYS HERE, and why: the harness, the stages, the pin table, and the notes that
# explain code ADJACENT to them. A reader verifying a release needs those at the site. The
# moved text is history -- what an increment got wrong, what it was settled against, which
# corpus moved -- and history at the top of the release script is what made the entry
# point unreadable.
#
# EIGHT LIVE CAVEATS that bear on the pin table below stayed here deliberately, because
# they are claims about THESE numbers rather than about a past increment:
#
#   - the SEVEN SUMMARY lines carry only THIN signal about the behavior lens. The six
#     older corpora carried NONE (no finding on any of them was tagged `behavior`, and
#     not one of the six contains a `main()`); `moonbit_core`, added at 0494, carries
#     5 findings tagged `behavior` out of 15758 findings across the seven (measured
#     2026-10-21). A pin that cannot distinguish two states is not a pin, and 5
#     findings is close to that line: see the DIRECTION 2 block in NARRATIVE.md.
#   - `moonbit_labeler` moved 801 -> 800 at 0470 (the last `actionable` on any corpus) and
#     800 -> 793 at 0471. `proton` moved at 0471: 122 -> 131 parsed, `unreliable`
#     544 -> 187. `async` moved at 0472: 390 -> 392 parsed, `unreliable` 285 -> 264;
#     at 0473, 392 -> 394; at 0474, 394 -> 396 with `notices` 1698 -> 1728 and `unreliable`
#     243 -> 203; and at 0475, 396 -> 399 parsed, `notices` 1728 -> 1752, `unreliable`
#     203 -> 161. `actionable` has been 0 on every one of them.
#   - `async` AT 0475, and this one went through `actionable` 0 -> 4 and back, which is the
#     only time in this cycle a corpus number has moved the WRONG way and been fixed rather
#     than pinned. The binder head now accepts ONE declaration before the body, and reading
#     it unblocked `process/unix.mbt` and `process/windows.mbt` -- which is when three
#     `undefined name 'nobreak'` and one `undefined name 'acc'` appeared as ACTIONABLE
#     findings on code `moon check` compiles. Root cause was a PRE-EXISTING defect the
#     increment revealed rather than created: the multi-binder path never called
#     `maybe_nobreak`, so the keyword stayed on the cursor and was re-read as an expression
#     plus a block. `nobreak` is a postfix on a loop and is legal on all three forms
#     (settle_0443). Fixed, re-measured, `actionable` back to 0, and `mutate_0475` M4 is
#     that regression with a corpus number attached: applied, it puts `actionable` back to 4.
#     parsed 396 -> 399, `unreliable` 203 -> 161, `notices` +24. Five of six corpora are
#     byte-identical. The other 0475 sites (`io/reader.mbt`) still did not parse: the header
#     at reader.mbt:176 was read, and the file stopped LATER, at line 186.
#   - `async` AT 0476, and this one CORRECTED A SETTLE. 0475's settle REJECTed a second
#     `;`-clause on the evidence of one row (`n = 1` is REJECT 4106); reader.mbt:186 writes
#     `for prefix in prefix_list; len = 0; len = len + prefix.length() { .. }` and `moon check`
#     COMPILES it. The compiler's sentence says binders in the steps must be declared IN THE
#     INITIALIZATION BLOCK, so 4106 was about WHERE A BINDER IS DECLARED and never about the
#     number of clauses. Reading it -- `parsed` 399 -> 400 and `io/reader.mbt` parsing with zero
#     defects, `unreliable` 161 -> 158, `notices` +2, `total` 1913 -> 1912, `actionable` still 0
#     and the other five corpora byte-identical. The general lesson is in NARRATIVE.md: a settle
#     row that passes BECAUSE the toolchain refused the fixture is evidence about the fixture,
#     and the rows that decide a grammar are the ones the corpus already writes.
#   - `async` AND `proton` AT 0477. `os_error/error.mbt` reported `1x expected '='` and
#     nothing else: there is no `parse_pattern` in the parser, so `let OSError(errno,
#     context~) = self` had `OSError` consumed as the bound VARIABLE and then met `(` where it
#     wanted `=`. 21 such sites in async. Settled in `_verify/settle_0477_let_pattern.ps1`,
#     2 controls + 9 rows, and implemented as a CALL SITE onto the `parse_is_pattern` reader
#     that already exists for `is`, emitting the existing `SLetDestruct` node -- no new node.
#       async    parsed 400 -> 403, unreliable 158 -> 120, notices 1754 -> 1776,
#                total 1912 -> 1896, withheld 31 unchanged, actionable still 0
#       proton   unreliable 187 -> 186, total 2068 -> 2067; parsed 131, notices 1881 and
#                withheld 6 all UNCHANGED
#     `parsed +3` on async is exactly the three files the backlog named, and `unreliable -38`
#     against it is the expected PAIR and not two events: unblocking a file reveals findings
#     whose reach was blocked, it does not create them. ZERO `undefined name` findings anywhere
#     in async is the load-bearing number -- a reader that parsed the pattern and bound NOTHING
#     would have been silent on `first_error` and loud on the next line.
#     proton's -1 is attributed, and the attribution is the hard part of this increment. The
#     whole 2198-line scan output differs on exactly ONE line: `facade_session.mbt ... 91 after
#     it not shown`, where HEAD said 92. `notices` is 128 and the region boundary is 1548 in
#     both, so one finding moved from after the boundary to before it, and the mechanism is
#     `facade_session.mbt:1664` (`let Open(id, completion) = command`, the single
#     constructor-pattern site in that corpus). At HEAD that line was the file's first parse
#     error; 0477 reads past it, so the first failure moves later. The file is still blocked,
#     by the `<?` log payload.
#     TWO WRONG TURNS ARE RECORDED THERE because both would have shipped a confident story.
#     First: `read up to line 1548` was read as the parse cut, which would have "proved" 1664
#     could not matter -- it is the ANALYSIS REGION boundary, and the arithmetic
#     (`total = actionable + notices + unreliable`) is what actually pins the move. Second: the
#     first `git worktree` A/B was CONFOUNDED, because `--extern-iface-dir` is IGNORED and the
#     extern tree is taken from the process CWD's `.repos`; the two runs sat in different
#     directories, so HEAD resolved against a different interface tree. Redone from one CWD
#     with the `Info:` line confirming both runs used the same tree, the same 187-vs-186 stands
#     -- now for the right reason.
#     => an A/B that does not verify its own inputs agrees with a broken one by coincidence, and
#     the coincidence is indistinguishable from the result.
#   - `async` AT 0473, attributed rather than asserted. Every one of async's C1-shaped
#     headers -- `for <name> = .. {` with no `;` before `{` -- was enumerated across the
#     tree and cross-referenced against the scanner's own PARTIAL list, then A/B'd against
#     a `git worktree` build of HEAD so the two blocked-file sets could be diffed:
#       io/buffered_reader.mbt       blocked at 57 -> PARSES           (`for searched = 0 {`)
#       internal/event_loop/io.mbt   blocked at 202 -> blocked at 364   (`for rest = .., produced = 0 {`)
#     Nothing else moved in either corpus. The second `+1` on the parsed count is a file
#     that failed at HEAD with NO findings, so it prints no PARTIAL line and cannot appear
#     in that diff at all; unparsed 27 -> 25 with blocked-with-findings 22 -> 21 accounts
#     for it, and `http/utils.mbt` (`for input = input {`, `for rest = start {`) is the
#     only candidate in that class. That is an inference from the arithmetic, not a
#     measurement, and it is labelled as one.
#   - `async` AT 0474, attributed the same way. A loop in EXPRESSION position was routed to
#     the wrong reader -- `parse_loop_as_expr` re-tested `at_name("while")` against a cursor
#     its own caller had already moved past the keyword, so the re-test was false for EVERY
#     loop expression. A/B'd against a `git worktree` build of HEAD:
#       websocket/conn.mbt              blocked at 486 -> PARSES   (`let kind = for frame = .. {`)
#       internal/event_loop/io.mbt      blocked at 364 -> PARSES   (a `while` expression)
#       http/parser.mbt                 blocked at  80 -> blocked at 440
#     and nothing else moved in either corpus; blocked-with-findings 21 -> 20.
#     `notices` +30 with `unreliable` -40 is the expected pair, not two events: those two
#     files used to be counted rather than reported, so they now report real notices.
#     WHAT IT BUYS IS EXACTLY "the file parses". The loop-expression BODY is still parsed
#     and thrown away (`parse_loop_as_expr` returns an opaque `EBigInt`), so an undefined
#     name inside one is still not reported -- pinned in both directions in
#     `pipeline_0474_test.mbt`. A gain in `parsed` is a gain in coverage, not in analysis.
#   - `moonbit_image`'s `unreliable` fell 23 -> 15 at 0472 and 15 -> 13 at 0473 while its
#     `notices` did NOT move, and that asymmetry is the whole explanation. `unreliable` is
#     the findings at or after a file's FIRST READ FAILURE -- "derived from an already-wrong
#     tree, so reported only as a count, never as results" (`src/sa/main.mbt`). bmp.mbt's
#     failure is a multi-line C-style header at lines 117-119:
#         for i = 0
#             i < num_colors && .. < self.data.length()
#             i = i + 1 {
#
#     *** CORRECTED AT 0482. THE SENTENCE THAT USED TO SIT HERE WAS FALSE. *** It read:
#
#         which `moon check` REJECTS [3002], so the analyzer's refusal is correct.
#
#     `moon check` ACCEPTS that header. `_verify/settle_0482_for_header_no_semicolons.ps1`
#     row `C1_three_clauses_newline_separated` is the measurement, and the analyzer's refusal
#     was a MISSED FILE, not a correct complaint. Two increments reasoned about this header on
#     the strength of the bad sentence -- 0473 kept the boundary where it was because the file
#     "should not parse", and 0472's A/B was used to confirm a move within a region that was
#     never wrong to begin with. The boundary did move, 117 -> 118, and the A/B was honest
#     about the move; what it could not say was that the move was heading anywhere, because
#     the destination was assumed to be a second error.
#
#     The line breaks ARE the clause separators -- settle C1 ACCEPT, and the one-line
#     spelling of the same header is REJECT(3002), so the breaks are load-bearing rather than
#     cosmetic. 0482 made the clause list POSITIONAL and moonbit_image is 18/18:
#         parsed 17 -> 18, unreliable 13 -> 0, withheld 0, notices 207 -> 218,
#         actionable 0 -> 0, total 220 -> 218
#     The A/B against HEAD from 0472 is retained above because it still describes the move it
#     measured; only the conclusion drawn from it was wrong.
#
#     => 判据: AN ARGUMENT IS A CLAIM AND CAN BE FALSIFIED LIKE ANY OTHER. This one was
#     re-measured only because 0482's own settle needed a row about `for` headers and this
#     was the header already sitting in the repository. A claim that has been carried for two
#     increments is not thereby twice-checked, and "the toolchain agrees with us" is the most
#     reassuring sentence available -- which is exactly why it needs a row of its own. Same
#     shape as the falsified `--extern-iface-dir` claim in 0477 and the `no whitespace token`
#     claim in 0470: third time the argument, not the code, was the defect.
#   - `async` at 0482: `unreliable` 120 -> 122 with `parsed` UNCHANGED at 403 and `withheld`
#     unchanged at 31. That is the boundary MOVING, not a new failure -- two files now read
#     farther before their own first failure. `parsed` not moving is the load-bearing half:
#     no file that read cleanly before is now refused. Distinct NOTPARSE reasons across the
#     whole backlog fell 14 -> 9, and only async is still short at 403/419. Its five
#     `expected '{'` files are a DIFFERENT construct from bmp.mbt's -- measured, not assumed,
#     and worth knowing because two increments of ranking would otherwise have pointed the
#     next one at this fix twice.
#   - `parse_block`'s parameter is named `value_block`, not `fn_body`. The old name is
#     what let a real bug read as a decision.
#
# `moonbitlang/core` is the SEVENTH pinned corpus, and the FIRST one with a
# non-zero `actionable`. It was added because the grammar probe control needed a
# corpus this frontend still cannot read, and the six above had all become fully
# readable -- see `_verify/derive_planted_gap.ps1` and the 0494 section of
# NARRATIVE.md.
#
# Its 48 actionable findings were NOT corpus defects. They were NAMED CONSTRUCTS
# THE READER DID NOT READ, and the accounting reconciled exactly: 43 in
# fully-parsed files (the per-file `defects=` headers are not truncated) plus 5
# pre-boundary findings in the two partial files that have any. The inventory,
# by construct, as it stood before 0495:
#
#   10  `undefined name 'rl'` / `'lr'`      the `is` pattern `(Node(..) as rl)` --
#                                            a REST pattern bound to a name
#   10  a type mismatch                    `==` on two array-typed operands (6),
#                                            `+` on 'int' and 'str' (2), `*` on a fn
#                                            whose signature was not read (1), and
#                                            `abs` handed a 'float' (1)
#   9   `undefined name 'p'` / `'p1023'` / a HEX-FLOAT literal: `0x1.0p97`, and
#       `'P'` / `'F6A8885A308CA8A54'`       `0x3.243F6A8885A308CA8A54`
#   7   `undefined name 'N'`               the `N` suffix on an integer literal
#                                            (`10N` is an Int64)
#   4   `undefined name 'lexmatch'`        the `lexmatch` keyword
#   4   `no visible binding for ...`       a package-private or associated name
#                                            (`Arbitrary::arbitrary`, `makei`)
#   2   UnusedLocal                        `i1` / `i2` in diff/diff.mbt
#   1   `undefined variable 'declare'`    the `declare` keyword
#   1   `undefined name 'strconv'`         `@internal/strconv.parse_double(s)` --
#                                            an absolute package path with a `/`
#
# AT 0495 IT IS 37, AND THE PIN MOVES DOWN WITH THE REASON ATTACHED.
#
# MEASURED, as an A/B of the SAME corpus with TWO wasms: the pre-0495 tree
# (`git archive HEAD`, which at the time was 731659c) built on one side and the
# 0495 tree on the other, both scanned over the same `.repos` path:
#
#     actionable  48 -> 37
#     notices     9988 -> 9988   UNCHANGED
#     unreliable  2956 -> 2956   UNCHANGED
#     withheld    552 -> 552     UNCHANGED
#     parsed      935 -> 935     UNCHANGED
#     files       1029 -> 1029   UNCHANGED
#
# AND THE FINDING SETS DIFFER BY EXACTLY 11, WITH ZERO NEW ONES. Not "the count
# went down" -- the SET is a strict subset, and the per-file `defects=` headers
# (which are NOT truncated) show that exactly TWO of the 680 files with findings
# changed at all:
#
#     internal/regex_engine/shared_types/rechar_set/tree.mbt   10 -> 0
#     quickcheck/generator.mbt                                  1 -> 0
#
# The ten are `undefined name 'rl'` / `'lr'` -- the `is` pattern `(Node(..) as
# rl)`, a REST pattern bound to a name, which is 0495's family G. The one is
# `no visible binding for 'Arbitrary::arbitrary'` -- a TRAIT's method read as a
# value, which is 0495's family E. Every other file's count is identical, and
# the shown finding lines diff to GONE 11 / NEW 0. None of the eleven is
# `behavior`-tagged, so the five behaviour-lens findings below are untouched.
#
# The 5 pre-boundary findings are untouched as well, so the accounting still
# reconciles: 32 in fully-parsed files plus 5 pre-boundary is 37.
#
# => 判据: A PIN THAT MOVES DOWN IS A CLAIM THAT WAS TOO STRICT, AND THE PROOF
# IS THE SET, NOT THE NUMBER. "48 -> 37" could have been eleven findings fixed
# and eleven new ones raised, and the count alone cannot tell the two apart.
# The A/B of the two wasms over the same corpus can, and it says GONE 11, NEW 0,
# in two files, with every other file's count identical. A pin moved on a number
# alone would have been a release that traded a corpus defect for a corpus
# defect and called it a release.
#
# AT 0496 IT IS 33, AND THE PIN MOVES DOWN AGAIN -- WITH THE REASON ATTACHED.
#
# MEASURED, as an A/B of the SAME corpus with TWO wasms: the pre-0496 tree
# (`git archive HEAD`, which at the time was be21ecd) built on one side and the
# 0496 tree on the other, both scanned over the same `.repos` path:
#
#     actionable  37 -> 33
#     parsed      935 -> 957
#     notices     9988 -> 10228
#     unreliable  2956 -> 2432
#     withheld    552 -> 464
#     files       1029 -> 1029   UNCHANGED
#
# AND THE FINDING SET IS A STRICT SUBSET: GONE 4, NEW 0. The four are all
# `undefined name 'lexmatch'`, and they are the ONLY per-file `defects=` headers
# that changed at all:
#
#     diff/diff_align_test.mbt            2 -> 0
#     diff/diff_word_test.mbt             1 -> 0
#     internal/strconv/strconv_int.mbt    1 -> 0
#
# THE +22 PARSED FILES RECONCILE FILE BY FILE, and the reconciliation is exact:
#
#     19  PARTIAL -> FOUND
#     3   PARTIAL with NO findings (so no header row at all) -> FOUND
#     2   stayed PARTIAL and read FURTHER
#     0   new findings on any of the twenty-two
#
# The 19 are
#
#     argparse/options_test.mbt                    json/from_json_test.mbt
#     buffer/buffer_test.mbt                       string/quickcheck_test.mbt
#     builtin/autoloc.mbt                          string/view_test.mbt
#     builtin/bytes_test.mbt                       internal/strconv/strconv_number.mbt
#     builtin/char.mbt                             char/char_coverage_test.mbt
#     builtin/char_test.mbt                        char/char_test.mbt
#     builtin/clamped_view_test.mbt                builtin/intrinsics_test.mbt
#     builtin/hasher_test.mbt                      builtin/show_test.mbt
#     builtin/string_char_set_quickcheck_test.mbt  builtin/string_test.mbt
#     builtin/stringview_test.mbt
#
# The 3 are the files that were PARTIAL with nothing to show for it, so the scan
# printed no row for them at all and they are invisible in the row diff:
#
#     char/predicate_reference_test.mbt
#     encoding/utf16/utf16_v128_bench_test.mbt
#     internal/strconv/strconv_bool.mbt
#
# The 2 are the same defect seen from the other side -- still PARTIAL, but they
# read FURTHER:
#
#     builtin/string_methods.mbt                 line 117 -> line 1465
#     string/internal/regex_parser/parser.mbt    51 -> 14 findings after the
#                                                 boundary
#
# THE CAUSE OF THE 22 IS THE CHARACTER COUNT, AND IT COVERS BOTH FORMS OF AN
# ASTRAL CHARACTER LITERAL -- the ESCAPED one and the one written DIRECTLY.
# `string/quickcheck_test.mbt:138` writes the escaped form (`'\u{1F600}'`,
# `'\u{10FFFF}'`); `builtin/string_methods.mbt:117` writes the direct one
# (`c == '😂'`), and that direct one is what stopped the file at line 117.
# Measured with the two wasms on a two-literal probe: the pre-0496 wasm cannot
# even PARSE a file containing either form (`parsed=0`, 2 withheld), and the 0496
# wasm reads it CLEAN.
#
# THE `lexmatch` ARM IS WHAT REMOVES THE FOUR FINDINGS, and it is also what
# collapses the post-boundary findings of `string/internal/regex_parser/parser.mbt`
# from 51 to 14: that file's 61 `lexmatch` arms are now read-and-skipped whole,
# so the findings inside them are gone.
#
# `builtin/autoloc.mbt` was PARTIAL at line 74 -- where the `lexmatch` at line
# 63 stopped the reader -- so its findings were WITHHELD and the inventory could
# not see them. 0496's `lexmatch` fix made the file readable and the withheld
# finding appeared: `no visible binding for 'sb'`, a LAMBDA PARAMETER inside an
# interpolation, on code `moon check` accepts. 0496 FIXED it rather than pinning
# `actionable=1` as though the finding were correct -- the 0488 rule, and the
# same uncovering the 0488 comment records for `radix`.
#
# => 判据: +22 PARSED IS NOT A NUMBER, IT IS A LIST. "935 -> 957" could have
# been twenty-two files that stopped being read, and the summary line cannot
# tell the two apart. Nineteen files moved from PARTIAL to FOUND, three more
# were PARTIAL-with-no-findings before and FOUND after, and every one of the
# twenty-two is a file the character reader could not finish. The two that
# stayed PARTIAL read FURTHER, which is the same defect seen from the other
# side. And NONE of the twenty-two carries a finding: the code that became
# readable produced nothing. So the pin moved down by four and the reader moved
# up by twenty-two at the same time, and a pin that had moved on the summary
# line alone would have said "fewer findings" without saying "more code read".
#
# => 判据: AN UNCOVERING IS NOT A REGRESSION. A false positive that was
# WITHHELD behind a parse boundary is not a finding, and fixing it is not
# "hiding a problem" -- the problem was in the ANALYZER, and the increment
# removed it. Pinning `actionable=1` for `no visible binding for 'sb'` would
# have frozen a defect into the pin and called it a corpus fact.
#
# `notices=9808` is dominated by the `.mbt.md` literate files: a `test` block
# inside a Markdown file is "outside the analyzer's MoonBit subset", which is a
# notice, not a defect. `unreliable=2240` is the post-boundary tail of the 72
# partial files -- 94 at 0495, 72 now, because twenty-two of them are whole.
#
# 0502 MOVED EVERY ONE OF THESE NUMBERS, and the reason is that a `match`'s
# ARMS ARE NOW READ. A `match` used to be a REGION -- a part of the file the
# frontend read but did not analyse -- and every match in the corpora put a
# notice on the count. Reading the arms removed 2,146 of those notices across
# the eight trees, and the notices that remain are the ones that are still
# true: a `lexmatch`'s arms, an `if` expression, a lambda body, and a `match`
# whose arms hold MoonBit this frontend cannot model.
#
# `actionable` MOVED DOWN ON CORE, from 33 to 28, and that is the point of the
# increment: reading the arms brought back findings, and 9 of the ones it
# brought back on `moonbit_core` were FALSE POSITIVES on code `moon check`
# accepts -- three `makei` calls in `immut/vector/invariants_wbtest.mbt` and
# the `i1`/`i2` shadow in `diff/diff.mbt`, plus five `with`-constraint
# parameters. `moonbit_labeler` went UP, from 0 to 1, and that one is TRUE:
# `app_moui/rasterizer.mbt:489`, `local variable 'd_off' assigned but may not
# be used`, computed at 489 and never read.
#
# And the SEVEN corpus pins carry BEHAVIOUR-LENS signal, which the six did
# not: core contributes 5 findings tagged `behavior`, and all five are
# consequences of the reader gaps listed above (`undefined variable 'N'` three
# times, `undefined variable 'declare'`, and `F6A8885A308CA8A54`). Five
# findings is thin, and it is the whole of it: see the DIRECTION 2 block in
# NARRATIVE.md for why the behaviour lens needs `--per-function` to be reached
# at all.
#
# 0507 ADDED `unchecked` TO EVERY ONE OF THESE PINS, and the reason is that a
# number that is not re-measured is a number that is wrong silently.
#
# `unchecked` is NOT a finding count. It is the number of CALLS the type lens
# could not check, because it never read the callee's signature: a name known
# only from another package's `.mbti`, a method call, and a `..` chain link.
# It is printed BESIDE the sum and is deliberately NOT part of it -- an
# unchecked call is not a defect, and adding it to `total` would break the
# identity the SUMMARY prints.
#
# WHAT DID NOT MOVE, and that is the point of the whole increment: `actionable`,
# `notices`, `unreliable`, `withheld` and `total` are UNCHANGED on all seven
# corpora. The three transfers from bandit change what the analyzer SAYS about
# a finding, not which findings it makes. A transfer that had moved a finding
# count would be a transfer that changed the analysis, and that is a different
# increment with a different justification.
$PINNED = [ordered]@{
  'moui'            = 'files=608 parsed=608 actionable=0 notices=3457 unreliable=0 withheld=0 unchecked=7678 total=3457'
  'moonbit_labeler' = 'files=37 parsed=37 actionable=1 notices=698 unreliable=0 withheld=0 unchecked=1340 total=699'
  'moonbit_image'   = 'files=18 parsed=18 actionable=0 notices=186 unreliable=0 withheld=0 unchecked=754 total=186'
  'async'           = 'files=419 parsed=419 actionable=0 notices=1654 unreliable=0 withheld=0 unchecked=2879 total=1654'
  'proton'          = 'files=137 parsed=137 actionable=0 notices=1799 unreliable=0 withheld=0 unchecked=2897 total=1799'
  'proton_contract' = 'files=4 parsed=4 actionable=0 notices=29 unreliable=0 withheld=0 unchecked=12 total=29'
  'moonbit_core'    = 'files=1029 parsed=984 actionable=10 notices=10114 unreliable=646 withheld=65 unchecked=7867 total=10770'
}
$TARGETS = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
  'moonbit_core'    = 'moonbitlang\core\0.1.20260920+7d59c7ec9'
}

# --- 6a  THE NOTICE RECONCILIATION CAN GO RED ---------------------------------
# A gate that has never been seen to go red is a comment.
#
# The corpus stage below proves that no ParseError-family DEFECT exists in the
# corpora, by counting the ones that render `error:`. That count must be zero
# -- and a counter that counts nothing would be zero the same way. So this
# stage runs the SAME counter over a REAL defect: a malformed interface file,
# which the literate frontend reports as a genuine ParseError defect and
# renders `error:`.
#
# It is the ANALYZER'S OWN OUTPUT that is measured, not a line of text written
# here: a synthetic line would only prove that the counter counts synthetic
# lines.
if ($failed.Count -eq 0) {
  Stage 'the notice reconciliation can go red (a real defect is seen)' {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $fx = Join-Path $env:TEMP ('reldefect_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $fx | Out-Null
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $fx 'bad.mbti'), "package demo`n`ntype Shape`n`nthis line is not a signature and not a type declaration`n", $enc)
    $text = Scan-Tree $wasm $fx
    $defects = Get-ParseErrorDefectCount $text
    if ($defects -lt 1) {
      Write-Output ('  FAIL: the defect counter saw ' + $defects + ' defect(s) in a tree that has one. It would pass the corpus stage on nothing.')
      $script:stageOk = $false
    } else {
      Write-Output ('  a real ParseError defect renders error:, and the counter sees it (' + $defects + ')')
    }
    $ErrorActionPreference = $prev
  }
  if (-not $script:lastOk) { $failed += 'notice-reconciliation' }
}

if ($failed.Count -eq 0) {
  Stage 'corpus SUMMARY vs pinned baseline' {
    $drift = 0
    $parseErr = $script:selfNotices
    foreach ($k in $TARGETS.Keys) {
      $p = Join-Path $repos $TARGETS[$k]
      if (-not (Test-Path $p)) { Write-Output ("  [ABSENT] {0,-16}" -f $k); $drift++; continue }
      $text = Scan-Tree $wasm $p
      $sum = Get-Summary $text
      # THE ANALYZER'S OWN NOTICE NUMBERS, and the reconciliation.
      #
      # 0506: the rendered `ParseError` lines are no longer the notice count
      # -- they are the notices that can hide a finding, and the rest are
      # counted by shape in the `NOTICES` table. So the gate reads the table's
      # TOTAL line, and it checks three things:
      #
      #     the table's notices == the SUMMARY's notices
      #     printed + aggregated == notices
      #     the rendered `notice:` lines == printed
      #
      # 0508: THE THIRD ONE IS COUNTED OVER THE NOTICE LINES, not over the
      # `ParseError` lines. The demotion put the low-confidence findings on a
      # line of their own, and they are notices and not ParseError-family
      # findings, so counting the family would have compared two different sets
      # -- and the corpus stage went red on exactly that, 1144 against 1162.
      # The family keeps its OWN check beside the reconciliation: a defect of
      # that family renders `error:`, and the count of those must be zero.
      $tab = Get-NoticeTable $text
      $nt = [int]([regex]::Match($sum, 'notices=(\d+)').Groups[1].Value)
      $rendered = Get-NoticeLineCount $text
      $peDefect = Get-ParseErrorDefectCount $text
      $rowSum = 0
      foreach ($r in $tab.Rows) { $rowSum += $r.N }
      if ($tab.Notices -ne $nt) {
        Write-Output ("  [DRIFT ] {0,-16} the NOTICES table says {1}, the SUMMARY says {2}" -f $k, $tab.Notices, $nt)
        $drift++
      } elseif (($tab.Printed + $tab.Aggregated) -ne $nt) {
        Write-Output ("  [DRIFT ] {0,-16} printed {1} + aggregated {2} is not the {3} notices" -f $k, $tab.Printed, $tab.Aggregated, $nt)
        $drift++
      } elseif ($rowSum -ne $tab.Aggregated) {
        Write-Output ("  [DRIFT ] {0,-16} the table's rows add up to {1}, the TOTAL line says {2}" -f $k, $rowSum, $tab.Aggregated)
        $drift++
      } elseif ($rendered -ne $tab.Printed) {
        Write-Output ("  [DRIFT ] {0,-16} rendered {1} notice lines, the table says {2} were printed" -f $k, $rendered, $tab.Printed)
        $drift++
      } elseif ($peDefect -ne 0) {
        Write-Output ("  [DRIFT ] {0,-16} {1} ParseError-family findings render as something other than a notice" -f $k, $peDefect)
        $drift++
      }
      $parseErr += $nt
      $want = $PINNED[$k]
      if ($sum -eq $want) { Write-Output ("  [MATCH ] {0,-16} {1}" -f $k, $sum) }
      else {
        $drift++
        Write-Output ("  [DRIFT ] {0,-16}" -f $k)
        Write-Output ('      pinned : ' + $want)
        Write-Output ('      actual : ' + $sum)
      }
    }
    # THE TOTAL over the seven corpora AND this repository's own source. This
    # is the number the README publishes, and it is CHECKED here because a
    # number that is only written down cannot be wrong loudly -- it can only
    # be wrong quietly.
    if ("$parseErr" -ne $NOTICE_TOTAL) {
      Write-Output ('  [DRIFT ] the eight trees carry ' + $parseErr + ' notices, pinned ' + $NOTICE_TOTAL + '.')
      $drift++
    } else {
      Write-Output ('  [MATCH ] the eight trees carry ' + $parseErr + ' notices')
    }
    if ($drift -eq 0) { return }
    if ($AllowCorpusDrift) { Write-Output '  (-AllowCorpusDrift: drift reported, not failed)'; return }
    Write-Output ("  {0} corpus/corpora drifted from the pinned baseline." -f $drift)
    $script:stageOk = $false
  }
  if (-not $script:lastOk) { $failed += 'corpus' }
}

# --- 6b  the per-function census, and the CONTROL for it -----------------------
# The census is pinned because it was NOT pinned once, and the cost of that is
# written in NARRATIVE.md: the 0.4.31 README claimed the per-function view had
# been measured "across the pinned corpora" and that the inventory was empty
# but for two findings, and the census that produced those two covered SIX
# corpora. The seventh carries more findings than all six put together. A
# published number that is not gated is a number that can go missing silently.
$PERFN = [ordered]@{
  'moui'            = '0'
  'moonbit_labeler' = '1'
  'moonbit_image'   = '0'
  'async'           = '0'
  'proton'          = '0'
  'proton_contract' = '0'
  'moonbit_core'    = '28'
}
$PERFN_TOTAL = '29'
# 0508. THE DEMOTED SET, pinned beside the actionable one for the same reason.
# A finding the analyzer does not stand behind is rendered `notice:` and leaves
# the actionable count -- and a set of findings that leaves the census is a set
# that can go missing silently. These 21 are the low-confidence ones, and they
# are the population the false-positive families A/B/F/L track.
$PERFN_DEMOTED = [ordered]@{
  'moui'            = '0'
  'moonbit_labeler' = '0'
  'moonbit_image'   = '0'
  'async'           = '0'
  'proton'          = '2'
  'proton_contract' = '0'
  'moonbit_core'    = '19'
}
$PERFN_DEMOTED_TOTAL = '21'
# THE POSITIVE CONTROL'S FILE COUNT, pinned here for the same reason the census
# total is: it is a corpus number, and the corpus numbers live in ONE place.
# `_verify/check_readme_links.ps1` DERIVES the README's expectation from this
# table rather than writing the number down a second time -- 0502 moved four
# corpus numbers at once and the README kept publishing the old ones, because
# the gate's literals were a second copy of the fact and nothing compared the
# two copies.
# 0508 MOVED THIS PIN: the demotion took four files out of the actionable set --
# they carried a low-confidence finding and nothing the analyzer stands behind --
# so the control's file count is 16 and not 20.
$CONTROL_N = '16'

if ($failed.Count -eq 0) {
  $CS = Join-Path $root '_verify\census_perfunction.ps1'
  if (-not (Test-Path $CS)) {
    Write-Output ''
    Write-Output 'MISSING: _verify\census_perfunction.ps1'
    $failed += 'perfunction-census'
  } else {
    Stage 'per-function census vs pinned baseline' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $CS 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      $total = ''
      $perCorpus = ''
      $demotedTotal = ''
      $demotedCorpus = ''
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '^PER-FUNCTION CENSUS actionable = (\d+)') { $total = $Matches[1] }
        elseif ($ln -match '^PER-FUNCTION CENSUS demoted = (\d+)') { $demotedTotal = $Matches[1] }
        elseif ($ln -match '^\s+per corpus: (.+)$') { $perCorpus = $Matches[1] }
        elseif ($ln -match '^\s+demoted per corpus: (.+)$') { $demotedCorpus = $Matches[1] }
        elseif ($ln -match '^\s+(\S+)\s+actionable=(\d+)\s+demoted=(\d+)\s+files=') {
          $name = $Matches[1]
          $n = [int]$Matches[2]
          $dn = [int]$Matches[3]
          $want = [int]$PERFN[$name]
          $wantD = [int]$PERFN_DEMOTED[$name]
          if ($n -eq $want -and $dn -eq $wantD) {
            Write-Output ("  [MATCH ] {0,-16} actionable {1}  demoted {2}" -f $name, $n, $dn)
          } else {
            Write-Output ("  [DRIFT ] {0,-16} actionable pinned {1}, actual {2}; demoted pinned {3}, actual {4}" -f $name, $want, $n, $wantD, $dn)
            $script:stageOk = $false
          }
        }
      }
      if ($total -eq '') { Write-Output '  FAIL: the census printed no total.'; $script:stageOk = $false }
      elseif ($total -ne $PERFN_TOTAL) { Write-Output ("  FAIL: total {0}, pinned {1}." -f $total, $PERFN_TOTAL); $script:stageOk = $false }
      else { Write-Output ("  TOTAL {0}   ({1})" -f $total, $perCorpus) }
      if ($demotedTotal -eq '') { Write-Output '  FAIL: the census printed no demoted total.'; $script:stageOk = $false }
      elseif ($demotedTotal -ne $PERFN_DEMOTED_TOTAL) { Write-Output ("  FAIL: demoted total {0}, pinned {1}." -f $demotedTotal, $PERFN_DEMOTED_TOTAL); $script:stageOk = $false }
      else { Write-Output ("  DEMOTED {0}   ({1})" -f $demotedTotal, $demotedCorpus) }
      if ($code -ne 0) { Write-Output '  FAIL: the census script exited non-zero (an UNCLASSIFIED finding).'; $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'perfunction-census' }
  }
}

if ($failed.Count -eq 0) {
  $PC = Join-Path $root '_verify\control_perfunction_census.ps1'
  if (-not (Test-Path $PC)) {
    Write-Output ''
    Write-Output 'MISSING: _verify\control_perfunction_census.ps1'
    $failed += 'perfunction-control'
  } else {
    Stage 'per-function census control (the files are READ by moon check)' {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $PC 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      foreach ($ln in ($o -split "`r?`n")) {
        if ($ln -match '^(GATE OK|GATE FAILED|read by moon check|BASELINE FAILED|RESTORE FAILED|  NOT READ)') { Write-Output ('  ' + $ln.Trim()) }
        if ($ln -match '^read by moon check: (\d+) of (\d+)') {
          # THE PINNED FILE COUNT. The control proves that every file carrying a
          # finding is READ by `moon check`; the COUNT of those files is a
          # corpus number like any other, so it is pinned here and the README
          # gate derives its expectation from this table.
          if ([int]$Matches[1] -ne [int]$Matches[2]) {
            Write-Output ('  FAIL: the control read ' + $Matches[1] + ' of ' + $Matches[2] + ' files.')
            $script:stageOk = $false
          }
          if ([int]$Matches[1] -ne [int]$CONTROL_N) {
            Write-Output ('  [DRIFT ] the control read ' + $Matches[1] + ' files, pinned ' + $CONTROL_N + '.')
            $script:stageOk = $false
          } else {
            Write-Output ('  [MATCH ] the control read ' + $CONTROL_N + ' files, all of them.')
          }
        }
      }
      if ($code -ne 0) { $script:stageOk = $false }
    }
    if (-not $script:lastOk) { $failed += 'perfunction-control' }
  }
}

# --- 8  what the region suppression hides -------------------------------------
# The README publishes this number, and the number describes a MECHANISM rather
# than a corpus -- so the stage that measures it is a stage that switches the
# mechanism off, rebuilds the analyzer, scans the eight trees, and puts the
# source back. The restore is proven by SHA256 inside the script, and the
# script REFUSES TO START if it finds the source already patched, so an
# interrupted run cannot be mistaken for a clean tree.
$MSO = Join-Path $root '_verify\measure_suppression_off.ps1'
if (-not (Test-Path $MSO)) {
  Write-Output ''
  Write-Output 'MISSING: _verify\measure_suppression_off.ps1'
  $failed += 'suppression-off'
} else {
  Stage 'the region suppression: what it hides, measured and pinned' {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $MSO 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($ln in ($o -split "`r?`n")) {
      if ($ln -match '(FAIL|restored|matches the pin|pinned:|UnusedLocal=|TOTAL)') { Write-Output ('  ' + $ln.Trim()) }
    }
    if ($code -ne 0) { $script:stageOk = $false }
  }
  if (-not $script:lastOk) { $failed += 'suppression-off' }
}

# --- 9  the reach of the `raise?` construct ------------------------------------
# 0.4.35 published "162 return-position sites in 31 files", and that number was
# measured by an ad-hoc grep whose RULE WAS NOT RECORDED, so it could not be
# reproduced: re-measured with a recorded rule it is 188 sites in 33 files, and
# with a type pattern that admits no comma in a generic it is 173 in 31. The
# FILE count matched and the SITE count did not, which is the worst shape a
# published figure can have -- a reader cannot tell which rule produced it.
#
# So the rule now lives in a file, the figure is pinned, and the pin is checked
# on every release gate. The stage also measures the OTHER SIX CORPORA and this
# analyzer's own source, because "the reach is confined to core" is a claim
# too, and a claim that is never measured is a claim that is never checked.
$MRQ = Join-Path $root '_verify\measure_0503_reach.ps1'
if (-not (Test-Path $MRQ)) {
  Write-Output ''
  Write-Output 'MISSING: _verify\measure_0503_reach.ps1'
  $failed += 'raiseq-reach'
} else {
  Stage 'the reach of the `raise?` construct, measured and pinned' {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $MRQ 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($ln in ($o -split "`r?`n")) {
      if ($ln -match '(FAIL|control ok|core:|the other six|matches the pin)') { Write-Output ('  ' + $ln.Trim()) }
    }
    if ($code -ne 0) { $script:stageOk = $false }
  }
  if (-not $script:lastOk) { $failed += 'raiseq-reach' }
}
# --- the 0505 stage -------------------------------------------------------------
# 0505 is a PLAN, and a plan whose premises are written down from memory is a plan
# that will be built on a premise that stopped being true while nobody was looking.
# This stage runs the settle that MEASURES every premise: the cross-file call that
# is silently unchecked, the family roster, the CLI surface, and the numbers the
# 0505 section of the narrative quotes.
#
# It is here for the same reason the reach measurement is here: the 0505 section
# ships in the narrative, the narrative ships in the package, and a published number
# that nothing checks can go missing silently. The settle's row D1 reads those
# numbers back out of the narrative and fails if any of them disagrees with the
# measurement, so the narrative and the measurement cannot drift apart.
#
# AND THIS BLOCK IS HERE BECAUSE THE FIRST VERSION OF IT WAS SILENTLY SKIPPED, which
# is worth recording rather than quietly fixing. The block that wrote this file
# expanded the shell variable that names the settle script, so the path was never
# assigned; `Test-Path $MSQ` was then called with a NULL path, and PowerShell treats
# that as a PARAMETER-BINDING error inside the `if` CONDITION. A failed condition
# skips the WHOLE `if` -- neither the branch nor the else -- the script carries on,
# and the gate printed RELEASE GATE PASSED with this stage MISSING from the summary.
#
# That is the worst shape a gate failure can take: not a red stage, but an ABSENT
# one, under a verdict that says everything is fine. So the fix is the one this
# repository already uses everywhere else -- the precondition is checked, the stage
# is NAMED, and the summary is checked for the stage by name. A stage that does not
# appear in the summary IS a failure, and the check below says so.
$MSQ = Join-Path $root '_verify\settle_0505_finding_quality.ps1'
if (-not (Test-Path -LiteralPath $MSQ -PathType Leaf)) {
  Write-Output ''
  Write-Output 'MISSING: _verify\settle_0505_finding_quality.ps1'
  $failed += 'finding-quality'
} else {
  Stage 'the premises of the 0505 porting plan, measured' {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $MSQ 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($ln in ($o -split "`r?`n")) {
      if ($ln -match '(MISMATCH|MISSING|GATE OK|ABORT)' -or $ln -match '^\s+(A6|A6b|A6ctl|B1|B2|B4|C1|C3)\s') {
        Write-Output ('  ' + $ln.Trim())
      }
    }
    if ($code -ne 0) { $script:stageOk = $false }
  }
  if (-not $script:lastOk) { $failed += 'finding-quality' }
  # THE STAGE MUST APPEAR IN THE SUMMARY. This is the check that would have caught
  # the version above, and it is here because "the gate passed" and "the gate ran
  # what it says it ran" are different claims and only the second one is worth
  # anything.
  $stageName = 'the premises of the 0505 porting plan, measured'
  $seen = @($script:results | Where-Object { $_.Stage -eq $stageName }).Count
  if ($seen -ne 1) {
    Write-Output ''
    Write-Output ('MISSING STAGE: "' + $stageName + '" ran ' + $seen + ' time(s); it must run once.')
    $failed += 'finding-quality'
  }
}
# --- the 0506 stage -------------------------------------------------------------
# 0506 is the NOTICE FLOOD, and it changed the SHAPE of what a scan renders, so
# the thing to pin is not a number but a RULE: a notice is printed one per line
# only when it can hide a finding, and every other notice is counted by shape in
# one table.
#
# The settle's row N3 is the sharp control for that rule -- the SAME "if
# expression" message, printed inside a function and aggregated at module top
# level -- and row N9 is the corpus measurement the README quotes. Both ship in
# the narrative and in the README, and a published number that nothing checks can
# go missing silently.
#
# The stage carries the same guard the 0505 stage carries, for the same reason:
# the stage must APPEAR in the summary. "The gate passed" and "the gate ran what
# it says it ran" are different claims, and only the second one is worth
# anything.
$MNF = Join-Path $root '_verify\settle_0506_notice_flood.ps1'
if (-not (Test-Path -LiteralPath $MNF -PathType Leaf)) {
  Write-Output ''
  Write-Output 'MISSING: _verify\settle_0506_notice_flood.ps1'
  $failed += 'notice-flood'
} else {
  Stage 'the notice flood: which notices deserve a line, measured' {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $MNF 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($ln in ($o -split "`r?`n")) {
      if ($ln -match '(MISMATCH|MISSING|GATE OK|ABORT)' -or $ln -match '^\s+N\d+\s') {
        Write-Output ('  ' + $ln.Trim())
      }
    }
    if ($code -ne 0) { $script:stageOk = $false }
  }
  if (-not $script:lastOk) { $failed += 'notice-flood' }
  $stageName = 'the notice flood: which notices deserve a line, measured'
  $seen = @($script:results | Where-Object { $_.Stage -eq $stageName }).Count
  if ($seen -ne 1) {
    Write-Output ''
    Write-Output ('MISSING STAGE: "' + $stageName + '" ran ' + $seen + ' time(s); it must run once.')
    $failed += 'notice-flood'
  }
}
# --- the 0507 stage -------------------------------------------------------------
# 0507 is the THREE TRANSFERS from bandit: the confidence axis, the stable
# family ids and the checked profile, and the `nosec` with its stale-
# suppression warning. It changed what the analyzer SAYS about a finding, and
# NOT which findings it makes -- so the corpus pins moved in exactly one
# field (`unchecked`) and in nothing else.
#
# The settle's rows are the MEASUREMENTS of the three transfers: the
# confidence each situation produces, the profile's two rules, and the
# `nosec`'s four behaviours. They ship in the narrative and in the README, and
# a published number that nothing checks can go missing silently.
#
# The stage carries the same guard the 0505 and 0506 stages carry, for the same
# reason: the stage must APPEAR in the summary. "The gate passed" and "the
# gate ran what it says it ran" are different claims, and only the second one
# is worth anything.
$MTR = Join-Path $root '_verify\settle_0507_bandit_transfers.ps1'
if (-not (Test-Path -LiteralPath $MTR -PathType Leaf)) {
  Write-Output ''
  Write-Output 'MISSING: _verify\settle_0507_bandit_transfers.ps1'
  $failed += 'bandit-transfers'
} else {
  Stage 'the three bandit transfers: measured, not asserted' {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $MTR 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($ln in ($o -split "`r?`n")) {
      if ($ln -match '(MISMATCH|MISSING|GATE OK|ABORT)' -or $ln -match '^\s+T\d+\s') {
        Write-Output ('  ' + $ln.Trim())
      }
    }
    if ($code -ne 0) { $script:stageOk = $false }
  }
  if (-not $script:lastOk) { $failed += 'bandit-transfers' }
  $stageName = 'the three bandit transfers: measured, not asserted'
  $seen = @($script:results | Where-Object { $_.Stage -eq $stageName }).Count
  if ($seen -ne 1) {
    Write-Output ''
    Write-Output ('MISSING STAGE: "' + $stageName + '" ran ' + $seen + ' time(s); it must run once.')
    $failed += 'bandit-transfers'
  }
}
# --- the 0508 stage -------------------------------------------------------------
# 0508 is THE CONFIDENCE DEMOTION: the axis that shipped in 0507 is ACTED on for
# the first time. A finding the analyzer does not stand behind is rendered
# `notice:` and is counted in `notices` rather than in `actionable` -- and it is
# NOT hidden: it keeps its family, its stable id, its confidence and its line on
# the reader's screen.
#
# The settle's rows are the MEASUREMENTS of the demotion, on the real scanner:
# the label, the counts, the two kinds of notice, and the split that PRINTS a
# demoted finding while AGGREGATING a scope limit.
$MDT = Join-Path $root '_verify\settle_0508_confidence_demotion.ps1'
if (-not (Test-Path -LiteralPath $MDT -PathType Leaf)) {
  Write-Output ''
  Write-Output 'MISSING: _verify\settle_0508_confidence_demotion.ps1'
  $failed += 'confidence-demotion'
} else {
  Stage 'the confidence demotion: measured, not asserted' {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $MDT 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($ln in ($o -split "`r?`n")) {
      if ($ln -match '(MISMATCH|MISSING|GATE OK|ABORT)' -or $ln -match '^\s+D\d+\s') {
        Write-Output ('  ' + $ln.Trim())
      }
    }
    if ($code -ne 0) { $script:stageOk = $false }
  }
  if (-not $script:lastOk) { $failed += 'confidence-demotion' }
  $stageName = 'the confidence demotion: measured, not asserted'
  $seen = @($script:results | Where-Object { $_.Stage -eq $stageName }).Count
  if ($seen -ne 1) {
    Write-Output ''
    Write-Output ('MISSING STAGE: "' + $stageName + '" ran ' + $seen + ' time(s); it must run once.')
    $failed += 'confidence-demotion'
  }
}
# --- verdict -----------------------------------------------------------------
Write-Output ''
Write-Output '=== stage summary ==='
$script:results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
Write-Output ''
if ($failed.Count -gt 0) {
  Write-Output ('RELEASE GATE FAILED: ' + ($failed -join ', '))
  Write-Output 'Nothing was published and no tag should be pushed.'
  exit 1
}
Write-Output 'RELEASE GATE PASSED.'
if ($SkipMutations) { Write-Output 'NOTE: the mutation gates were SKIPPED. This is not a release-grade run.' }
exit 0

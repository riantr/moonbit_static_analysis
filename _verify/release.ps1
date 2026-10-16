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
  Start-Process -FilePath $moonrun `
    -ArgumentList @($Wasm, $Path, '--extern-iface-dir', $repos) `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  return Read-TextWhenFree -Path $out
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
    $sum = Get-Summary (Scan-Tree $wasm $root)
    Write-Output ('  ' + $sum)
    $files  = [int]([regex]::Match($sum, 'files=(\d+)').Groups[1].Value)
    $parsed = [int]([regex]::Match($sum, 'parsed=(\d+)').Groups[1].Value)
    $act    = [int]([regex]::Match($sum, 'actionable=(\d+)').Groups[1].Value)
    # actionable must be 0 AND every file must parse. The second condition is what
    # stops a scan that crashed half-way from reading as a clean tree.
    if ($act -ne 0) { Write-Output '  FAIL: actionable is not 0.'; $script:stageOk = $false }
    elseif ($files -ne $parsed) { Write-Output ("  FAIL: parsed {0} of {1} files." -f $parsed, $files); $script:stageOk = $false }
    else { Write-Output ('  ' + $files + '/' + $files + ' parsed, actionable 0') }
  }
  if (-not $script:lastOk) { $failed += 'self-scan' }
}

# --- 5  every mutation gate --------------------------------------------------
$gates = @('0412','0413','0418','0419','0420','0421','0422','0423','0424','0425','0426','0427','0428','0429','0430','0431','0432','0433','0434','0435','0436','0437','0438','0439','0440','0441','0442','0443','0444','0445','0446','0447','0449','0450','0452','0453','0454','0455','0456','0457','0458','0459','0460','0461','0462','0463','0464','0465','0466','0467','0468','0469')
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

# --- 5b  the PUBLISHED package, scanned by the analyzer that shipped ----------
# Placed after the mutation gates because it is the slowest stage that depends on
# something outside this repository. It is also the only one that exercises the real
# delivery path: mooncakes compiles the artifact server-side and `moonx` runs THAT,
# so a green local suite says nothing about whether the shipped wasm works. It runs
# outside the repo on purpose -- `moonx` materialises into `.repos/` relative to the
# current directory, and writing the analyzer into that tree would change every
# corpus baseline measured since.
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
# against `blockers.ps1` gives OVERLAP 0 and the gap reads as free. 鈬?鍒ゆ嵁: a
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
# `facade_paths.mbt:473` `parameter 'label' may not be used` 鈥?the second
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
# hex.mbt rows above 鈥?a suberror variant used in a DIFFERENT file from its
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
# --- 0.4.30, 0440: a `.mbti` `suberror` body declares value constructors -------
#
# ONE PREDICATE, and it was the largest single false-positive source in the
# project. `parse_iface` set `in_ctor_body = matched == "enum " && d > 0`, so a
# braced `suberror` body was matched and descended into -- its member types were
# collected -- and its member NAMES were discarded.
#
# proton's OWN generated interface says, at `pkg.generated.mbti:68`,
#
#     pub(all) suberror AppConfigurationError {
#       InvalidSetting(name~ : String, message~ : String)
#     }
#
# and `collect_iface_symtabs` already reads the target's own tree, the target's
# root being `iface_dirs[0]` in `sa/main.mbt`. `InvalidSetting` was written down
# in the file being scanned and was still reported as having no visible binding.
#
#   moui             actionable  0 -> 0    parsed 590 UNCHANGED
#   moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
#   moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
#   async            actionable 12 -> 12   parsed 227 UNCHANGED
#   proton           actionable 78 -> 12   parsed 103 UNCHANGED
#   proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED
#
# 80 actionable findings across the six corpora became 24. proton's drop is 66,
# larger than the 58 the re-rank counted before the change, because 0439's 15
# catch-body findings were the same shape -- `err => raise MalformedJson(..)` --
# and were waiting on this same harvest.
#
# WHY IT WAS INVISIBLE FOR SO LONG, which is the part worth keeping. The MAIN
# PARSER already harvested suberror bodies (`Parser::skip_decl`: `what == "enum"
# || what == "suberror"`), so a variant used in the file that DECLARES it always
# resolved. proton's `.mbti` files carry 30 braced suberror bodies and 0
# body-less ones, so no rare spelling ever showed up as a discrepancy. Only the
# CROSS-FILE path was broken, which is why the symptom was false positives on
# correct code rather than unreadable files -- and why reading more files, the
# move that has fixed every blocker so far, could never have fixed this one.
#
# --- 0.4.31, 0441: two top-level functions of ONE NAME shared one table --------
#
# A TABLE KEYED BY A NAME THAT IS NOT UNIQUE. `WalkResult.fn_bindings` was a
# `Map[String, Array[Binding]]` keyed by `f.name`, and BOTH consumers looked a
# function's declarations up by that name -- the walk at pass 3 and, separately,
# `Infer::run_fn` in the type lens. Two top-level functions of one name therefore
# shared ONE table and the second `set` overwrote the first, so every function of
# that name was analysed against the LAST one's parameters.
#
# It is now an `Array` parallel to `fns`, indexed by position, and `run_fn` takes
# its bindings as an argument because the position is the caller's to know. There
# is no longer any by-name lookup to get wrong.
#
# `#cfg` IS HOW REAL CODE REACHES THIS, AND IT IS NOT THE CAUSE. MoonBit allows
# two top-level functions of one name when `#cfg` gates them per platform, and
# `Lexer::lex_attribute` deliberately emits NO token for an attribute, so both
# variants are analysed together -- a stated fidelity cost, not an accident. The
# regression test has NO `#cfg` in it at all, because the defect is the key and
# not the attribute. `#cfg` appears 689 times across 99 async files: that is how
# real code reaches the defect, not what causes it.
#
#   moui             actionable  0 -> 0    parsed 590 UNCHANGED
#   moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
#   moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
#   async            actionable 12 ->  7   parsed 227 UNCHANGED
#   proton           actionable 12 -> 10   parsed 103 UNCHANGED
#   proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED
#
# 24 actionable across the six corpora became 17, and `parsed=` did not move on any
# of them -- which is the acceptance criterion here, because this was a change to
# how findings are ATTRIBUTED, and a change that lowered one corpus while raising
# another would be a regression wearing a fix's clothes.
#
# WORTH KEEPING: this gate failed its FIRST run with all four mutations KILLED.
# M2 and M4 named the test that was supposed to pin `run_fn`'s own by-name lookup,
# and that test did not go red -- a guard claiming coverage it did not have,
# written with a source in which mistyping a parameter could not show up. The test
# was rewritten rather than the claim re-anchored onto something that did go red,
# and the rewrite was proved green on clean code AND red under both mutations
# before the gate was re-run. The four kills are the SECOND run. The whole account
# is in `mutate_0441.ps1`.
#
# --- 0.4.32, 0442: `noraise { .. }` is a handler block, not a name -------------
#
# FOUR FALSE POSITIVES ON CODE `moon check` ACCEPTS, and the shape of the fix was
# not the one the findings suggested. proton `facade_identity.mbt:99` and `:136`,
# `protocol_wbtest.mbt:5`, and async `network.mbt:68` all reported
# `undefined name 'noraise'`.
#
# THE GRAMMAR IS SETTLED BY THE COMPILER, `_verify/settle_0441_noraise.ps1`, 8/8
# as predicted with the positive control green: `noraise { pattern => body }` is
# a postfix handler block on a COMPLETED `try ... catch`. A `try expr noraise {..}`
# with no catch is REJECTED, the arm list is `catch`'s grammar, an empty block is
# rejected, and the pattern binds the base's RESULT value. Nesting the production
# inside the existing `catch` arm is therefore faithful grammar rather than a
# convenient placement, and it cannot swallow a user's own `noraise` function.
#
# THERE ARE TWO PARSER PATHS AND THE FINDINGS LIVE IN THE SECOND ONE, which cost
# most of the increment. `parse_postfix_from` reads the postfix `catch`; the
# statement-level `try` is read by the PREFIX reader and its catch loop ends in
# `skip_braces`. The first change taught the postfix path `noraise`, and the
# result was a fully GREEN suite with a COMPLETELY UNCHANGED corpus -- all four
# findings still present. A green suite is not evidence that a corpus finding
# moved; the two are separate measurements and only the second is the claim.
#
#   moui             actionable  0 -> 0    parsed 590 UNCHANGED
#   moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
#   moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
#   async            actionable  7 ->  6   parsed 227 UNCHANGED
#   proton           actionable 10 ->  7   parsed 103 UNCHANGED
#   proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED
#
# 17 actionable across the six corpora became 13, with `parsed=` unmoved
# everywhere. The statement-level block is CONSUMED but not analysed, deliberately
# and consistently with the lines above it: that branch is the un-analysed `try`,
# its body is already skipped and `note_skip` already put a hole in the frame, and
# reading the `noraise` arms alone would find reads in a block whose sibling
# catch block is deliberately unread.
#
# --- A HARNESS DEFECT THIS GATE FOUND, WHICH AFFECTS EVERY GATE ----------------
#
# Gate 0442 reported five of five KILLED and still reported MUST-RED MISS on all
# five, naming as evidence the very tests that had gone red. The needle and the
# captured name were BYTE-IDENTICAL (65 bytes each, same hex).
#
# The cause: `mutate_lib.ps1` matched with `-like`, and PowerShell's `-like` runs
# the PATTERN through escape processing, where the backtick is the escape
# character. A needle containing a backtick therefore cannot match a name
# containing the same backtick -- and this suite's test names are full of them,
# because the doc comments are markdown. Bisected on the failing needle: a
# 30-character prefix with no backtick matched, 40 characters with one did not.
# `-like` also treats `[` `]` as a wildcard set and throws on an unbalanced one,
# so a bracketed test name could crash the harness rather than merely miss.
#
# Rule 6 asks a SUBSTRING question and was being answered with a PATTERN matcher.
# It is now an ordinal `IndexOf`, which is that question. All 27 gates were
# re-checked: no gate relied on wildcard behaviour, and the one `MustRed`
# containing a `?` (0430's `f(x?)`) is a literal in that test's name, so it
# matches exactly.
#
# --- 0.4.33, 0443: `nobreak { .. }` is a postfix block on a LOOP -----------------
#
# One false positive, and the smallest increment in a while: proton
# `internal/bridge_admission_test/main.mbt:20` reported `undefined name
# 'nobreak'` on code proton 0.3.4 compiles.
#
# SETTLED, not assumed -- `_verify/settle_0443_nobreak.ps1`, 10/10 with the
# positive control green, after three corrections to the probe itself:
#
#   - it is a postfix on a LOOP, and the compiler REJECTS `expr nobreak { .. }`
#     with no loop at all, so matching the keyword loosely would accept programs
#     the compiler refuses.
#   - it is accepted on `while` AND `for`, so the wrap is applied to all three
#     loop forms. The corpus site happens to be a `while`, so a `while`-only
#     parser would have passed the corpus measurement while being wrong.
#   - the body is a STATEMENT LIST: `nobreak { 1 }` is rejected 4139, a value in
#     statement position cannot be dropped. A different shape from `noraise`,
#     which takes an arm list.
#   - an EMPTY `nobreak { }` is ACCEPTED, unlike `noraise { }`. The two are easy
#     to assume identical and are not, and a parser copying `noraise`'s "at least
#     one arm" rule would reject valid MoonBit.
#
#   moui             actionable  0 -> 0    parsed 590 UNCHANGED
#   moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
#   moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
#   async            actionable  6 -> 6    parsed 227 UNCHANGED
#   proton           actionable  7 -> 6    parsed 103 UNCHANGED
#   proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED
#
# 13 actionable across the six corpora became 12. async is UNCHANGED and that is
# the expected result rather than a disappointment: it carries 34 `nobreak` lines
# and every one of them was already blocked or already excluded. A census number
# is not a finding count -- the same lesson `noraise` taught at 4x the size.
#
# THE NODE NEEDS FOUR ARMS AND THE FIRST DRAFT HAD ONE. `walk_stmt` learned
# `SNoBreak`, and the suite's two `for` tests then failed with `no visible
# binding for 'x'` and `no visible binding for 'i'` -- the FOR BINDERS, not
# `nobreak`. There are two binding collectors, not one: `collect_fn_bindings` for
# a function's own declarations and `collect_top` for the module frame, and both
# have a `_ => ()` catch-all, so the compiler said nothing about the missing arms.
# A top-level `for` executes at module level and so puts its binder there. M4 and
# M5 pin the two collectors separately.
#
# --- 0.4.34, 0444: a bare LOWERCASE `is` pattern head is a BINDING ------------
#
# Six actionable findings, async 6 -> 1 and proton 6 -> 5, `parsed=` unchanged on
# all six. Twelve across the six corpora became six.
#
# SETTLED, not assumed -- `_verify/settle_0444_is_head.ps1`, 9/9 with BOTH the
# positive control and a deliberately-broken canary green:
#
#   - `if probe() is err && err != 0 { err }` COMPILES: a lowercase head BINDS,
#     so it is not a constructor test and must have a binding.
#   - `if opt() is Some && Some != 0` is REJECTED. Uppercase is a constructor
#     test, and "a function compared with an integer" is the only reading that
#     explains the rejection. So case is not a heuristic, it is the grammar.
#   - an unused head binding AND an unused payload binding are both LEGAL, and `_`
#     binds nothing. `is St::Shutdown` binds nothing either.
#
# THE PROBE'S FIRST DRAFT WAS WRONG IN A WAY THAT WOULD HAVE BEEN MISREAD. It
# used an `Int` base with `Some`/`Err`, so three cases failed 4014 for a plain
# Int-vs-Option mismatch and would have read as "uppercase is rejected". The fix
# was a second `opt() -> Option[Int]`, NOT a revised expectation. A failing
# positive control means fix the prelude, never the expectation.
#
# THE CORPUS SYMPTOM AND THE ISOLATED SYMPTOM WERE TWO BUGS' FINGERPRINTS FOR ONE
# CAUSE. 0444 reported `unsupported operand types for '!=': 'fn err (signature
# not read)' and 'int'` in async schannel.mbt -- NOT `undefined name 'err'` --
# because something else named `err` is in scope in that package and wins. An
# isolated reproduction reports `undefined name 'err'`. Two symptoms, one cause,
# and only the isolated form points at the parser. The shape-based re-rank would
# have filed 0444 under the TYPE lens, and the type lens was already correct.
#
# BINDING THE HEAD INTRODUCED A NEW FALSE POSITIVE THAT THE SETTLE CAUGHT.
# `Walker::bind` puts the name on the audit list, so an unused `is` head binding
# reported `local variable 'err' assigned but may not be used` -- a false
# positive, `b_lower_unused` ACCEPTED. `EIs` therefore uses `bind_pattern`, which
# never touches `self.orders[fi]`. That also fixes the PRE-EXISTING payload half
# (`is Some(v)` with `v` unread), so the fix is strictly an improvement on both
# halves rather than a trade between them.
#
#   moui             actionable  0 -> 0    parsed 590 UNCHANGED
#   moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
#   moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
#   async            actionable  6 -> 1    parsed 227 UNCHANGED
#   proton           actionable  6 -> 5    parsed 103 UNCHANGED
#   proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED
#
# GATE 0444: 2 KILLED (M1 the parse, M3 the walk), 3 declared SURVIVED with a
# measured argument -- M2/M4/M5 are green because `bind_pattern` never reaches
# the audit list (so no `UnusedLocal` can appear) and `Infer::EIs` seeds a
# spurious name as `TUnknown`, i.e. resolved-and-unknown rather than unresolved,
# which can only SUPPRESS a type finding. Both mutations are quieter; a
# suppressed finding is not observable in this tool's output. Declared honestly
# as expressing the settled grammar while NOT being load-bearing against today's
# lenses -- they would become so the moment a lens began auditing `is` bindings.
#
# AND THE SAME ARGUMENT, ONE SCALE UP: 0444 COST FOUR PINS THAT WERE STILL
# LOAD-BEARING. This is the part that must not be buried in a gate log.
#
# Moving `EIs` from `bind` to `bind_pattern` closes the unused-local audit for `is`
# bindings: `bind` appends to `self.orders[fi]`, `bind_pattern` never touches it.
# Every guard inside `pattern_binding_at` was observable ONLY through that audit,
# because the phantom names each one prevents -- `true`, `Os`, `core`/`Role`/
# `Checkbox`, `Gone`/`PageUnavailable` -- are never READ anywhere. A name that binds
# but is never read resolves (no `UndefinedName`), and `Infer::EIs` seeds it `TUnknown`,
# which can only suppress a type finding. So four pins that had been load-bearing
# since 0.4.19/0.4.21 stopped being load-bearing:
#
#     0419 M1  is-pattern keyword test          646/646 green
#     0421 M6  qualified-path rule removed      646/646 green
#     0421 M7  nested-constructor rule removed  646/646 green
#     0421 M8  or-pattern depth rule removed    646/646 green
#
# The move itself is REQUIRED, not a trade: the settle measured 9/9 that an unread
# `is` head or payload binding is legal MoonBit, so auditing them would be a false
# positive on correct code. All four guards remain in the source and remain
# semantically right; none of them is load-bearing against today's lenses.
#
# WHAT PROVES IT IS THE CHANNEL AND NOT A STALE ANCHOR: gate 0421 M5 anchors on the
# SAME `depth >= 2` expression, survives the same parser change, and still KILLS,
# because its symptom is `UndefinedName` -- it leaves `error` unbound in
# `is Some(Os(error))` where `error + 1` reads it. Same file, same change,
# different channel, opposite outcome.
#
# GATE 0436 ALSO BROKE, for the ordinary reason, and is re-anchored rather than
# retired. 0444 added `qualified = true` inside the `::` consumption loop and a new
# block between `let binding` and `if self.at(TLParen)`, so all four Find strings went
# absent and the preflight aborted before a suite ran. M1 and M4 additionally stopped
# being VALID mutations: they deleted that loop, and the loop now sets a variable the
# head-binding decision reads, so deleting it no longer compiled at all (COMPILE-ERR,
# no `Total tests:` line -- a mutation that cannot build measures the compiler, not
# the guard). Both now point the loop condition at a token a qualified head never
# sits on: same broken behaviour, still builds. Anchors shortened to the two lines
# carrying `qualified = true`, unique to this one of the three qualified-path readers,
# which is the point -- the previous anchors named surrounding prose and that is what
# 0444's growth invalidated. 0436 is back to 3 KILLED + 1 declared survivor.
#
# GATE 0436 M4 IS DUPLICATE M1 UNDER A SECOND NAME, which predates 0.4.34 and is
# recorded rather than quietly rewritten: both mutations stop the `::` loop from
# running, and they differ only in which named test they pin. The "consumed AFTER
# the payload test" in its title is not what its Find/Repl pair expresses -- a real
# ordering mutation would MOVE the loop below the `TLParen` branch. Both still KILL,
# so nothing is unprotected today; the duplication is a genuine weakness.
#
# --- 0.4.35, 0445: the builtin-method table could not see GENERIC methods -------
#
# The defect was in the GENERATOR, not in the analyzer. `tools/gen_builtin_methods.ps1`
# extracted methods with a pattern demanding the name come straight after `fn`:
#
#     (?m)^\s*(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)
#
# MoonBit's generated interfaces put type parameters there --
# `pub fn[K : Eq] Set::add(Self[K], K) -> Unit` -- so every generic method of every
# builtin type was invisible. Measured against the toolchain in hand the old pattern
# produced ZERO hits on `<core>/set/pkg.generated.mbti`, which alone declares 32 of
# them, and missed 445 names across the tree.
#
# WHY IT STAYED INVISIBLE. `Array::add` was never reported on any corpus only
# because real MoonBit writes the METHOD form `a.add(x)`; the qualified form
# `Array::add(a, x)` is mostly used for constructors. That is the shape the one
# finding had: `Set::from_array`, async 0.22.4 `src/http/send.mbt:37`, reported
# `undefined function` on code `moon check` accepts.
#
# AND IT IS NOT A DECLARED `fn` AT ALL. `#alias(from_array)` sits above
# `type Set[K]`, so the DIRECTIVE is where the name is written. The generator now
# carries pending aliases to whatever declaration follows, and keeps only
# identifier-shaped ones -- `#alias("_[_:_]")` is a quoted operator and is not a
# qualified name this table can hold. 140 such names; 1265 in the table against 656
# before, VERIFIED A STRICT SUPERSET with none lost.
#
#   moui             actionable  0 -> 0    parsed 590 UNCHANGED
#   moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
#   moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
#   async            actionable  1 -> 0    parsed 227 UNCHANGED
#   proton           actionable  5 -> 5    parsed 103 UNCHANGED
#   proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED
#
# Six actionable across the six corpora became five. proton is UNCHANGED and that is
# the expected result, not a disappointment: its remaining five are `undefined name`
# and `undefined function` on names that are not builtin methods at all
# (`CookieWaiting`, `@async.CondVar::Cond`), so no amount of table can move them.
#
# THE 18 `T::to_json` NAMES, AND A HYPOTHESIS THAT WAS WRONG. Those names appear in
# NO `pkg.generated.mbti` in the tree, and the table had been generated at
# moon 0.1.20260920 against a toolchain that is no longer installed, so the reading
# was "stale, drop it". They are not stale: `Bool::to_json(true)` COMPILES today.
# They are intrinsic members, the same category as `Array::make`, which is why the
# generator carries a hand-settled intrinsic list. They are listed there now, and
# gate 0445's M3 exists so that dropping them again is a red suite.
#
# The sweep that "confirmed" it was worse. Calling `T::to_json(1)` for all 45 bare
# types reported 35 as nonexistent, and every one of those was a TYPE mismatch,
# because `1` is not a `Bool`. A probe wrong about its own prelude produces a
# clean, confident, entirely false answer; the settle survived it only because a
# correctly-typed case sat beside the malformed one. Second time this repository
# has been caught by it, and both times the fix was the PRELUDE.
#
# NOT ESTABLISHED, and deliberately claimed nowhere: whether the `.mbti` fn-head
# FORMAT changed between those two toolchains, or whether the generator was always
# blind to generic heads. The old toolchain is not installed. The claim here is the
# gap against the toolchain in hand, and nothing earlier.
#
# GATE 0445: 4/4 KILLED, every named test confirmed, every restore byte-identical.
# M1 generic head, M2 alias of a type constructor, M3 name no interface declares,
# M4 alias of a METHOD. M4 is pinned on table MEMBERSHIP rather than behaviourally,
# because `Array::clone` is a deprecated alias of a deprecated spelling that no
# corpus writes -- a behavioural test for it would have meant inventing a call site
# no measurement produced.
# --- 0.4.36, 0446: a `#|` closer is a BLANK one, and the lexer was eating it --------
#
# Three of the five remaining actionable findings were ONE predicate, and the cause was not
# a missing declaration. proton 0.3.4 `facade_types.mbt` declares `CookieWaiting` and
# `CookieCompleted` at lines 589-594, but the scanner read that file only to line 246.
# `region_line` is `first_error_line`, so a file that hit an error was cut at the error and
# contributed NOTHING to the cross-file symtab -- and the sibling that USES those names was
# told they were undefined. Three findings, three files, one predicate.
#
# WHY THE FILE WAS CUT. `lex_block_string` demanded a `#|` with only whitespace BEFORE it
# on its line. The CLOSER is a `#|` with nothing AFTER it, so it satisfied that demand and
# was consumed as content; the block never closed and the lexer went on reading it as code.
#
# THE RULE, SETTLED BY VALUE, not by acceptance. `moon check` accepts EVERY shape -- all
# nine probes passed it -- so it measures nothing here and was not used to settle it.
# `moon run`'s printed string settles it, in `_verify/settle_0446_block_string.ps1` (9/9,
# positive control green). A closer is a LINE-LEADING `#|` whose rest of line is blank;
# trailing spaces are fine and it may be indented. Every other `#|` is a content segment.
# Segments are trimmed and joined by a SINGLE SPACE, and the closer contributes an empty
# final segment, hence the trailing space. End of input also closes, with no trailing empty
# segment, and is still reported. A non-blank line without `#|` ends the block as CODE with
# no unterminated report; a blank line does not.
#
# THE OLD HEADER WAS WRONG, AND IT IS RECORDED RATHER THAN DELETED. It claimed the closer
# needs whitespace BEFORE it, and listed `#|AAA\n#|BBB trailing -> "AAA\nBBB trailing"` as a
# measurement. Both are false: trailing text is CONTENT, and the join is a space, not a
# newline. Its one correct claim -- that the closer may be indented -- had NO test of its
# own and survived only because an unrelated test happened to indent one.
#
#   moui             actionable  0 -> 0    parsed 590 -> 591
#   moonbit_labeler  actionable  0 -> 0    parsed  25 ->  26
#   moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
#   async            actionable  0 -> 0    parsed 227 -> 253
#   proton           actionable  5 -> 2    parsed 103 -> 106
#   proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED
#
# Five actionable across the six corpora became two, and 31 more files parse fully -- the
# sum of those `parsed` deltas -- with none lost anywhere. NOT A GENERAL TRUNCATION FIX:
# 178 other truncated files across the corpora have other causes. The
# `unterminated block string literal` report itself fired on only 4 files, and that is NOT
# the same count as the 31 extra parses; a file cut here can stop short without ever
# producing that report. This note does not claim the two sets are identical.
#
# GATE 0446: 5/5 KILLED, every named test confirmed, every restore byte-identical. M1/M3
# first came back COMPILE-ERR -- they removed a binding still read later (`j`), or made
# `cur` an unused `let mut` -- so what they were measuring was the COMPILER. Both were
# corrected to compile, with the failure recorded in their `Prove`.
#
# M2 is the one worth reading. It indents the closer, and no test had ever done that: seven
# tests for this construct all put the closer at column 0 because they were copied from each
# other, so the rule was pinned only by an UNRELATED test that happened to indent. Two tests
# were added and M2 re-pointed at them.
#
# WHAT IS LEFT, and it is not this predicate: proton `facade_notification.mbt:12,14`,
# `undefined function '@async.CondVar::Cond'` twice -- a qualified path through
# `pub using @cond_var {type Cond as CondVar}` in async's `pkg.generated.mbti`.
#
# WHAT THE RELEASE GATE CAUGHT IN 0446, AND IT WAS IN 0446'S OWN CODE. The first
# run of this file failed at stage 2 with four `0020` deprecation warnings: the new
# `lex_block_string` wrote `cur.to_string().trim().to_string()`, and `StringView::to_string`
# is deprecated in favour of `to_owned`. `--deny-warn` turns those into errors, so the
# suite stopped before a single mutation gate ran. All four sites now say `to_owned()`.
#
# A GREEN TEST TALLY IS NOT `--deny-warn` CLEAN, and the reverse is also true.
# During development this same code reported `moon test --target wasm` at 655/655;
# under this suite the same package exits 1 and prints NO tally at all. The cause
# of THAT discrepancy is NOT ESTABLISHED and is not claimed here.
#
# 0.4.37 supplied the cleaner half of the same point, in the OPPOSITE direction: a
# `local` binding in a new test file left `moon test --target wasm` reporting
# 662/662 PASSED while `moon check --deny-warn` failed it -- `local` is a MoonBit
# reserved keyword and the test runner does not treat that as fatal. Neither stage
# is a substitute for the other in either direction, which is the actual reason
# this suite runs both. A suite running only the tests would have shipped four
# deprecation warnings; a suite running only the linter would have shipped a
# reserved-keyword binding inside the test that guards the re-export link.
#
# Counted as shipped: wasm 657/657 (the two tests M2 forced into existence are in that
# 657), js 585/585, wasm-gc 585/585. js and wasm-gc run fewer because `src/sa` needs the
# async runtime and degrades off wasm. GATE 0446: 5/5 KILLED.
#
# --- 0.4.37, 0447: a RE-EXPORTED type carried its name but not its MEMBERS -----
#
# These were the last 2 actionable findings in existence across the six corpora.
# proton 0.3.4 `facade_notification.mbt:12,14` writes
#
#     gate: @async.CondVar::Cond(),
#
# and was reported `undefined function '@async.CondVar::Cond'` on both lines, on
# code the toolchain accepts. async 0.22.4 re-exports the type under that name --
# `pub using @cond_var {type Cond as CondVar}`, `src/pkg.generated.mbti:111` -- and
# `@cond_var/pkg.generated.mbti` declares `type Cond` with `pub fn Cond::Cond() -> Self`.
#
# BOTH HALVES WERE ALREADY IN THE TABLE. The re-exported NAME, because the `using`
# branch pushed it into `declared`; and `Cond::Cond`, because `@cond_var`'s own
# interface is read and its signatures are bare. Nothing CONNECTED them.
# `has_value` tried the exact key and then `unqualified`, so `@async.CondVar::Cond`
# became `CondVar::Cond`, found nothing, and reported a name written down two files
# away. It looked like a missing declaration and was a missing LINK.
#
# THE RULE, settled WITH THE TOOLCHAIN in `_verify/settle_0447_condvar_alias.ps1`
# (6/6, three negative controls firing). A constructor IS callable through an
# aliased type re-export, CROSS-PACKAGE -- and a name that does not exist is STILL
# rejected through it: `[4029]` for a missing member, `[4032]` for a missing type.
#
# THAT SECOND HALF IS THE POINT, and it is why this is a link and not a
# suppression. An earlier version of this fix -- silence every `@mod.X::m` that
# reaches a re-exported name -- ALSO takes these two findings to zero, on all six
# corpora, with a green suite and nothing whatever to tell the two apart. Gate
# 0447's M2 is that version, and the control test is what kills it. The settle
# exists because the corpus cannot make that distinction and the test can.
#
#   moui             actionable  0 -> 0    parsed 591 UNCHANGED
#   moonbit_labeler  actionable  0 -> 0    parsed  26 UNCHANGED
#   moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
#   async            actionable  0 -> 0    parsed 253 UNCHANGED
#   proton           actionable  2 -> 0    parsed 106 UNCHANGED
#   proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED
#
# TOTAL actionable across the six corpora is ZERO, and `parsed=` did not move on
# any of them -- so this is a false positive removed, not a corpus traded. notices,
# unreliable and withheld are identical on all six too; only proton's `total`
# falls, by exactly the 2 findings that were wrong.
#
# TWO LIMITS, recorded because they are limits and not because they were reached.
# The alias key is the BARE re-exported name, since `collect_iface_names` reads
# interface text and is not told which module it came from -- two modules
# re-exporting different types under one name would collide, first-one-wins. And
# only the FIRST alias on a re-export line is recorded, because later segments have
# already lost their package qualifier to the `{`-strip. The whole table is flat in
# exactly this way, so neither is a new shape of limit; neither is a claim that the
# mapping is sound, and no corpus here exercises either.
#
# The settle also records two SCAFFOLD facts that cost a wasted run each: `moon.mod`
# must declare `source = "src"` or the build plan fails and every case reads ACCEPT,
# and a package cannot import its OWN root package. Its first version reported all
# three negative controls as ACCEPT for the first reason, and its second did so for
# the third -- it normalised the toolchain's output with `replace '\s+', ' '` before
# matching `(?m)^Error:`, which destroys the line boundaries the pattern needs. Four
# malformed probes in four days now, each of which would have reported the right
# answer for the wrong reason.
#
# GATE 0447: 4 KILLED + 1 declared SURVIVED (M5, the redundant bare form: both
# callers apply `unqualified` to every candidate and `unqualified("@cond_var.Cond::Cond")`
# IS `Cond::Cond`, so the extra entry cannot be reached). wasm 662/662, js and
# wasm-gc 590/590 (up 5 on each 鈥?the five 0447 tests live in `moonfiles`, which is
# not a `src/sa` package, so they run on every target). Self-scan 88/88 actionable 0,
# up one file and six notices over 0.4.36: the new test file.
# --- 0.4.38, 0449: an EXTERNAL fn binding, and a TUPLE STRUCT that read the next
#     declaration's brace -------------------------------------------------------
#
# TWO DEFECTS IN ONE INCREMENT, because fixing the first one found the second.
#
# DEFECT A. `fn f() -> T = "module" "symbol"` -- a `fn` whose body lives in another
# language is DECLARED, not defined. The parser finished the signature, found `=`
# where it wanted `{`, and reported `expected '{'`: the parser naming a token that
# was never the problem. That report is the file's `first_error`, so the file went
# NOTPARSE and everything after the declaration went unread. Settled with the
# toolchain in `_verify/settle_0449_ffi_decl.ps1`, 7/7 with BOTH negative controls
# firing; all three shapes (no parameters, single-line list, multi-line list) are
# ACCEPTed by `moon check`. Cost on moui 0.1.12: FOUR of the seventeen files
# `_verify/diagnose_moui_truncations.ps1` reports, the largest single shape there.
#
# DEFECT B. `struct Name(T)` -- a tuple struct has no body, so the braced skipper
# scanned forward for the `{` that opens one and took the NEXT declaration's brace.
# On async 0.22.4 `src/process/cancellation.mbt` that brace belongs to an `if`, so
# the `let` and the `if` went with it and `else` / `SIGTERM` were reported as
# undefined variables -- two false positives on correct code. Settled in
# `_verify/settle_0449b_tuple_struct.ps1`, 8/8 with three negative controls.
#
# THREE HYPOTHESES WERE FALSIFIED before that one, and the record is worth more
# than the fix: the `is` pattern, a qualified receiver, and a cross-package
# `@pkg.field` receiver each looked like the cause, and each probe varied the `if`.
# The cause was never in the `if`. It was that what came BEFORE the `if` had no
# `{` to stop at.
#
# TWO CLAIMS IN THE OLD GATE PROSE WERE FALSIFIED BY MEASUREMENT, and both are
# corrected in place in `_verify/mutate_0449.ps1` rather than quietly dropped.
#
#   1. `extern_fns` does NOT suppress `undefined function`. It is consumed at
#      exactly one place, `walk.mbt:1170`, guarding `audit_frame` -- so what the
#      registration buys is `UnusedParam = 0` on a header-only fn whose body was
#      never read. Dropping it leaves undefined-function findings untouched and
#      takes a clean external fn from no findings to `UnusedParam = 1`. That is
#      the whole trade the fix refuses: without it, four unread files would have
#      become four files with a false positive each.
#   2. Consuming only the FIRST of the two strings is unobservable. Nine fixtures
#      -- an external binding followed by a `fn`, a `let`, a braced struct, a tuple
#      struct, a second external binding, with no blank line, plus two controls --
#      give byte-identical findings, because a leftover string literal is a
#      well-formed top-level expression statement. M2 is now a declared SURVIVED.
#
# AND ONE FIXTURE WAS WRONG IN A WAY WORTH KEEPING. The M4 fixture had a struct
# with ONE field, which absorbs the leftover line without ever reporting a name, so
# the named test stayed green while the suite was red. Two fields is what makes it
# discriminating. Separately, a fixture putting a `fn` after the tuple struct was
# rejected by rule 6 and named the test that had actually gone red: `skip_decl_braced`
# breaks at a top-level `fn` (`parser.mbt:802`), so a following FUNCTION is never
# swallowed. The damage needs a `let ... = if` between the struct and the brace --
# which is what the corpus writes.
#
#   moui             actionable  0 -> 0    parsed 591 -> 595 (+4, exactly the FFI files)
#                          unreliable 244 -> 144, notices 4120 -> 4123, total 4364 -> 4267
#   async            actionable  0 -> 0    parsed 253 -> 274 (+21)
#                          unreliable 2208 -> 1193, notices 1081 -> 1234, total 3289 -> 2427
#   the other FOUR corpora byte-identical.
#
# The async actionable=0 is the load-bearing line and it was NOT free. The FFI fix
# alone took it 0 -> 2, both false positives revealed by 21 newly-readable files
# rather than introduced by the change. "Pre-existing defect merely revealed" is a
# real distinction and still not a shippable one, so the tuple-struct defect went in
# the same increment instead of leaving actionable above zero.
#
# GATE 0449: 5 KILLED + 1 declared SURVIVED (M2, above), every named test confirmed
# red, every restore byte-identical, baseline 600/600.
# --- 0.4.39, 0450: a `fn` in STATEMENT position is two different things ---------
#
# A lambda whose value is a branch:
#
#     paint: if disabled {
#       fn(_ctx) { { commands: 1 } }
#     } else {
#       fn(_ctx) { plan0() }
#     }
#
# `parse_block` routed EVERY `fn` to the declaration path, so the lambda fell into
# `parse_fn_signature`, which asks for a name, found `(`, and reported
# `expected function name` -- at a token that is neither unexpected nor unnamed, so
# the message sent a reader hunting a malformed function header that does not
# exist. That is moui 0.1.12 `modifier_env.mbt` cut at `fn(_ctx) {`.
#
# ONE CONDITION, and the token after `fn` is the whole discriminator: a NAME means a
# local function declaration, `(` means a lambda expression. It only ever surfaced
# in a BRANCH because expression position always worked -- `let f = fn(x) { .. }`
# reaches `parse_primary`'s lambda branch -- and a lambda that is the tail of an
# `if` branch is a block STATEMENT, the one place the two forms share a token and a
# cursor.
#
# Settled in `_verify/settle_0450_shapes.ps1`, 10/10 with THREE positive controls,
# two of which exist because malformed preludes built first: a wrong field type made
# nine agreeing REJECT(4014) rows, and the corpus's QUOTED keys reject against a
# struct too. Fix the prelude, never the expectation.
#
#   moui     parsed 595 -> 596 (+1, exactly modifier_env.mbt)  unreliable 144 -> 131
#   async    parsed 274 UNCHANGED                              unreliable 1193 -> 1201
#   proton   parsed 106 UNCHANGED                              unreliable 1077 -> 1103
#   the other three corpora byte-identical.  actionable 0 on all six.
#
# THE UNRELIABLE RISE IS NOT NEW FINDINGS, and saying so required a measurement
# rather than an argument. `_verify/measure_0450_unreliable.ps1` diffs the scan of
# both corpora before and after the fix. Every differing line is a CONTROL line:
#
#     async  task_group.mbt      read up to line 50, 35 after -> 47 after
#     async  process/redirect.mbt                     57 after -> 32 after
#     async  io/data.mbt                              6 after ->  4 after
#     proton six files, +2 to +9 lines each
#
# Six files per corpus now read FURTHER, so more of an already-unread tail is seen,
# and the extra findings land in NOTPARSE files where they are already unreliable or
# withheld. NOT ONE new finding message appears anywhere. The defect's own
# signature is gone: `1x expected function name` leaves async's withheld tally, and
# proton's `2x unexpected token ')'` with it.
#
# THAT DIFF HAD TO BE REWRITTEN ONCE, because the first version compared only the
# printed `LINE:COL - error:` lines and reported added=0 removed=0 on both corpora
# -- while the SUMMARY beside it said `unreliable` had moved 1193 -> 1201 and
# 1077 -> 1103. Byte-identical lists and a moving count cannot both be true. The
# findings that moved are printed as control lines (PARTIAL read-depth, the withheld
# tally), not one line per finding. A probe that engages its instrument and prints a
# confident zero is worse than one that prints nothing, and that is the whole
# hazard: `actionable = 0` on its own would have "confirmed" this change while
# measuring nothing about it.
#
# GATE 0450: 3/3 KILLED (M1 the original, M2 the inversion, M3 the condition
# deleted outright), every named test confirmed red, every restore byte-identical.
# M2 and M3 turn the same test red for different reasons, and only M3 tells "I
# flipped it" from "I removed it".
#
# GATE 0452: the three remaining `{`-cut moui files. The cause was NOT a brace.
# `parse_struct_fields` reads a braced list and keys every entry by the identifier
# before the colon; a map literal with a QUOTED key has no identifier there, so
# `peek_name()` returned "" and the whole literal was abandoned. The fix reads a
# string key in that position and requires the colon that follows it, because
# `{ "a" }` is rejected by the toolchain and must not parse.
#
# THE TWO FORMS CANNOT BE MERGED, and `_verify/settle_0452_quoted_key_map.ps1`
# (5/5, with a positive control) is what establishes it. `{ "a": 1 }` as
# `Map[String,Int]` ACCEPTS; `{ a: 1 }` as Map REJECTS (4033, 4028); `{ a: 1 }`
# as a struct literal ACCEPTS; the corpus declaration verbatim ACCEPTS. So the
# quoted form is a map, the unquoted form is a struct, and a fix that let a
# string key pass WITHOUT a colon would have silently taught the parser to accept
# a program the toolchain rejects.
#
#   moui     parsed 596 -> 599 (+3, exactly the three `{`-cut files)  unreliable 131 -> 105
#   labeler  parsed  26 ->  28 (+2)                                  unreliable 319 -> 309
#   proton   parsed 106 -> 108 (+2)                                  unreliable 1103 -> 1082
#   async    parsed 274 UNCHANGED                                    unreliable 1201 -> 1189
#   moonbit_image and proton_contract byte-identical.  actionable 0 on all six.
#
# async is the interesting row: `parsed` did not move, yet 12 findings left the
# unreliable bucket and 7 joined notices. Both are expected of this fix and both
# are reported here so that neither can later be mistaken for corpus noise -- a
# map literal previously read as a struct literal contributed a bogus control
# line, and reading it correctly replaces that with real findings on a now-parsed
# file. Across all six corpora: parsed +7, unreliable -69, total findings -30.
#
# GATE 0452: 4/4 KILLED (M1 the branch removed, M2 no colon demanded, M3 the value
# expression discarded, M4 the string-vs-name discrimination dropped), every named
# test confirmed red, every restore byte-identical. Two of the four had to be
# re-aimed before they could distinguish anything: M2 was asserted on a failure
# COUNT, and under the mutation the fixture still produced two failures, only the
# second one different -- so it now asserts the MESSAGE `expected ':'`. M4's
# MustRed points at an existing test in another file, because the mutation
# destroys the field KEY while `{ a: a }` still parses as a value.
# GATE 0453: an anonymous ASYNC function literal in expression position.
# After 0452 moui still could not finish reading 9 files, and the largest by-reason
# bucket was `4x expected ')'`. That label is about the ARGUMENT of a call, not the
# parenthesis -- the parser is downstream of the real failure, which is why the first
# reading sent the search towards brackets. Three of the four are one construct:
#
#     launch_async=Some(async fn(request, frame_interval_ms) { .. }),
#
# `parse_atom` had an arm for `TName("fn")` and none for `async`. The short-lambda
# named argument on the line ABOVE it parses, which is why those files were PARTIAL
# at line 23-24 rather than unparsed at zero.
#
# Settled in `_verify/settle_0453_async_fn_expr.ps1`, 6/6 with a positive control:
#
#     Some(fn(a) { .. })        ACCEPT   <- already read, identical shape
#     Some(async fn(a) { .. })  ACCEPT
#     the corpus declaration    ACCEPT
#     ignore(async)             REJECT(3002) "you may expect `fn`"
#     async work()              REJECT(3002)
#
#   moui     parsed 599 -> 602 (+3)   unreliable 105 -> 46   notices 4150 -> 4203
#   image and proton_contract byte-identical; actionable 0 on all six.
#   The `expected ')'` bucket is GONE from the by-reason grouping, and the
#   `unexpected token ','` bucket is 4 -- the three files that were in it, plus
#   runtime/app_builder.mbt, which has a SECOND defect behind the first and only
#   now shows its own.
#
# THE THREE OTHER CORPORA MOVED AND NOBODY ASKED THEM TO. proton unreliable
# 1082 -> 1112, withheld 309 -> 321; async notices 1234 -> 1241; labeler withheld
# 134 -> 136. `parsed=` is UNCHANGED on all three, which is the signature of
# "reading further", not of a regression -- and it was checked rather than argued:
# proton carries 25 `async fn(` literal sites and async carries 45, so a file that
# used to stop at one of them now stops at whatever comes NEXT and has more of its
# tail seen. That is the same mechanism 0450 documented, and it is the reason
# `unreliable` can rise while `parsed=` holds.
#
# TWO REGRESSIONS OF MY OWN WERE CAUGHT BY THOSE CORPORA, NOT BY THE GATE:
#
#   1. A `fn`-only guard consumed `async fn log(s) { .. }` -- a NESTED
#      DECLARATION -- as an anonymous literal, so `parse_block` never declared it.
#      labeler withheld 134 -> 136, two files that had parsed became PARTIAL.
#   2. The compound guard `at_name("fn") && name_at(p+1) == ""` sent that same
#      nested declaration to the `else`, which announced `async without a following
#      fn` -- a FALSE notice about legal code. async hit it on all five of its
#      nested sites. `else` fires 0 times in all six corpora now.
#
# Neither was visible to `_verify/mutate_0453.ps1`, and the reason is worth
# recording rather than fixing: no fixture in the 0453 file contains a nested async
# declaration, and a mutation gate cannot see a corpus it was not given. The corpus
# is the instrument for that, which is why all six SUMMARY lines are pinned.
#
# GATE 0453: 5/5 KILLED (M1 the arm never fires, M2 the `fn` not consumed, M3 the
# body skipped, M4 the `fn` guard dropped, M5 the nested declaration announced).
# M3's MustRed was RENAMED TWICE before it could discriminate, and both attempts
# were structurally incapable: `UnusedParam` on the literal's own parameters (they
# are `let _ =`-discarded, never bound) and a defect inside the body (`parse_block`
# returns statements that are thrown away, so nothing inside a function literal
# reaches a lens -- for a plain `fn` exactly as much as for an async one). What
# works is what reading the body DISCOVERS: a `match` inside it is announced.
# GATE 0454: `label?=value` in a call argument -- the member the shorthand family
# was missing. After 0453 moui could not finish reading 6 files and the largest
# by-reason bucket was `unexpected token `,``:
#
#     let normal = @views.new_control_state_style(
#       foreground=@core.Color::black(),
#       border?=normal_border,
#       radius=0.0,
#     )
#
# The complaint named a COMMA, three tokens from the cause. `parse_call_args`
# handles two shorthands, both AFTER the argument is parsed -- `f(x~)` at the
# `TTilde` test and `f(x?)` at the `TQuestion` test -- and neither is followed by
# an `=`. So for `border?=normal_border` the `TAssign` test was FALSE (the next
# token is `?`), `p` was restored, `border` was read as a positional name, the
# `TQuestion` shorthand consumed the `?` as if the argument ENDED, the comma test
# found the `=` that the first test skipped over, and the loop broke.
#
# The `?` CARRIES MEANING, so this is not sugar for `=`. Settled in
# `_verify/settle_0454_label_qmark_eq.ps1`, 9/9 with a positive control:
#
#     border?=v   against  border? : Int   ACCEPT
#     border?=v   against  border~ : Int   REJECT(4141) "not declared with border? : _"
#     border?=                      REJECT(3002)
#     border?v                      REJECT(3002)
#
# A `name? : T` parameter has type `T?` -- measured as REJECT(4014) "wanted Int?"
# with a bare `7` -- so dropping the `?` would read illegal code as legal. The last
# row is what licenses the two-token lookahead: `?` either ends an argument or starts
# `?=`, and never prefixes an expression.
#
#   moui     parsed 602 -> 605 (+3)   unreliable 46 -> 23   notices 4203 -> 4209
#   proton   parsed 108 -> 109 (+1)   unreliable 1112 -> 1032   notices 1344 -> 1374
#   the other four byte-identical. actionable 0 on all six.
#
# proton moved too, and it was CHECKED rather than waved at: it uses `label?=value`
# 17 times across four files (`facade_builders.mbt` 5, `facade_native_types.mbt` 7,
# `facade_runtime.mbt` 4, `facade_event_loop.mbt` 1). `facade_builders.mbt` is also
# the file that held the `async fn(context) {` literal 0453 fixed, so it had two
# stacked defects and only now resolves. The -80 unreliable is that file's.
#
# The `unexpected token `,`` bucket is GONE from moui and the three files that
# resolved are exactly the three `?=` ones. What remains is three files and three
# DIFFERENT causes, one each -- the shape a tail of this kind is supposed to have:
#
#     1x  expected ')'             runtime/app_builder.mbt:47
#     1x  unexpected end of line   runtime/input_dispatch_result.mbt:13
#     1x  unexpected token `:`     backend/macos/macos_services.mbt:406
#
# GATE 0454: 5/5 KILLED (M1 the branch removed, M2 the `=` not required, M3 the
# value consumed but not analysed, M4 the `?` dropped from the label, M5 the
# lookahead widened to any `?`).
#
# M4's MustRed MOVED FILES and that is the finding. It SURVIVED the first version of
# this gate: every 0454 test was written through `@pipeline.run`, asserting findings,
# and nothing on the pipeline path READS the label -- `parse_call_args` returns
# `(args, labels)`, the labels go into `ECall`, and neither lens consults them for any
# finding these fixtures trigger. A blank label changed no count; 623/623 stayed
# green. That is a property of the ANALYZER, not of the parser, so the assertion
# moved to `src/parser/parser_0454_test.mbt` and reads `ECall`'s third field directly,
# the way `parser_0430_test.mbt` already does for `x~` and `x?`. Asserting "the call
# parses" passes; asserting a finding count passes; neither is evidence about a label.
# 0.4.xx -- newline suppression after the BITWISE-OR token. `unexpected end of line`
# is 0 occurrences across all six corpora; it was 1 in moui.
#
# ONE TOKEN WAS MISSING. `newline_suppressed_after` listed TPlus, TAmp, TCaret,
# TAndAnd, TOrOr, TShl, TShr and every comparison operator, and did not list TBar. So
# the lexer emitted TNewline after `|`, `parse_bitor` bumped the `|` correctly, and
# the operand parse landed on TNewline and `parse_primary` raised "unexpected end of
# line" (parser.mbt:4664).
#
# THE EVIDENCE KEPT POINTING ELSEWHERE, which is the part worth keeping. A sweep for
# "trailing binary operators" reports 178 corpus files and 2296 sites and would have
# ranked this as the largest available lever; 103 of those are moui files and only 3
# moui files fail to parse at all, because `+`, `&` and `||` already continue. And
# `input_dispatch_result.mbt` had been carried for several rounds as "a parenthesised
# `if` as an operand", which is false -- a parenthesised `if` parses fine. A token's
# role is whatever the CONSUMER does with it, and `TBar`'s own comment still said "the
# parser never sees one" after `parse_bitor` had started consuming it.
#
#   moui             parsed 605 -> 606 (+1)   actionable 0 -> 0
#   moonbit_labeler  parsed  28 ->  28        unreliable 311 -> 294
#   moonbit_image    parsed   2 ->   2        unreliable 294 -> 285
#   async            parsed 274 -> 274        unreliable 1188 -> 1175
#   proton           parsed 109 -> 109        byte-identical
#   proton_contract  parsed   4 ->   4        byte-identical
#
# THE 42 FINDINGS THAT LEFT `unreliable` ARE NOT A COVERAGE LOSS, and it was verified
# rather than assumed: both builds came from the same tree, one with TBar in the set
# and one without, and the per-file comparison found ZERO files read less, one newly
# complete (`input_dispatch_result.mbt`) and one read further (labeler). `actionable`
# and `notices` are unchanged in every corpus, so what vanished was exactly the class
# the analyzer itself flags as "this file was not fully understood".
#
# GATE 0455, 4/4 KILLED with named tests. M4 is the row worth noting: it deletes the
# OTHER conjunct of the same `if` -- `closer_ahead` -- and it SURVIVED the first run,
# which is how the repository learned that the newline-before-a-closing-bracket rule
# had no test pinning it anywhere. That test now exists.
#
# GATES 0456 + 0457, shipped together because 0456 alone breaks the invariant this
# file exists to protect.
#
# 0456 consumed the `.Type` of a package-qualified `is` head (`@pkg.Type::Ctor`, four
# tokens, parser.mbt:3033). moui 606 -> 607; `backend/macos/macos_services.mbt` parses
# whole. It also corrects the pin on `parser_0436_test.mbt` that recorded the WRONG
# mechanism: it said `peek_name()` is `""` for an `@` head, which is false -- it returns
# `"@pkg"`. Both stories predict the same symptom and a different repair, which is the
# only reason the disagreement was worth chasing.
#
# 0456 BROKE async actionable 0 -> 3 by unblocking `src/fs/watch_test.mbt`, which had
# been dying at line 389 on `is @async.TimeoutError`. The file then parsed whole and
# three `undefined name 'async'` sites surfaced at once -- a false positive 0457 removed.
# So `actionable` could not be pinned between the two increments, which is why they ship
# as one commit: a visible parse failure traded for invisible wrong findings is worse
# than either alone.
#
# WHY async's `unreliable` ROSE 1175 -> 1248 while `actionable` fell to 0. Honest
# re-classification, verified rather than argued. 46 read-past `async fn` sites now mark
# their region unreliable instead of silently binding a name. A move that size cannot be
# pinned on inference, so `_verify/ab_0456_0457_coverage.ps1` builds BOTH parsers from ONE
# tree and diffs how far the scanner reads in EVERY file of all six corpora:
#
#     files in HEAD map 1223 / fixed map 1223
#     unchanged 1220   read further 3   READ LESS 0
#
#     async/src/fs/watch_test.mbt          389 -> EOF     (0456 unblocked it)
#     async/src/websocket/server.mbt   NOLINE -> PARTIAL 34
#     moui/backend/macos/macos_services.mbt 406 -> EOF     (0456)
#
# `watch_test.mbt` moving FROM 389 is the cross-check: 389 is the `is @async.TimeoutError`
# line the 0457 comment names as the blocker, so the A/B confirms the comment's own claim
# by a different instrument.
#
# THE REACH METRIC, and why it had to be built rather than reused. `FOUND` lines look like
# the per-file record and cover only 183 of async's 419 files -- a fully-read clean file
# prints `CLEAN`, and one that failed at its FIRST construct prints nothing at all. Keying
# the diff on `FOUND` would have dropped 56% of the corpus silently, and every clean file
# would have read as "absent" rather than "unchanged". So reach is one state per file:
# EOF / a line number / NOLINE, with NOLINE made explicit precisely because it is the
# state most likely to MOVE. The map is checked for totality against the files on disk,
# and it validates itself twice against the scanner's own accounting:
# EOF == `parsed` (275) and PARTIAL + NOLINE == `NOTPARSE` (83 + 61 = 144).
#
# `pins.ps1` exists because these six numbers were once measured by an ad-hoc loop that
# returned `files=3675 parsed=2831 actionable=125` for moonbit_labeler and then returned
# the IDENTICAL line for moonbit_image. Two corpora cannot agree exactly, so that was a
# stale file being read -- and it was caught only by the coincidence of the match. Every
# corpus now asserts its TARGET line and its file count against disk before the number is
# printed, and any two identical summaries abort the run.
#
# GATE 0457, 3 KILLED / 1 declared survivor. M4 (adding the `bump` the branch deliberately
# does not have) was declared KILLED in the first run so the suite could decide; it
# survived 643/643, and structurally so -- `parse_block` tests the token at the cursor, and
# after this branch that token is `fn` either way, so both variants build the same tree.
#
# 639 -> 643 tests: `pipeline_0457_test.mbt` is new, and none of its four cases existed
# before. 0453 pinned that a nested async declaration is not mistaken for a literal, via
# `parse_failures == 0` plus the absence of a false notice -- and both hold while the branch
# still binds a bogus name, because a notice is not a failure. Only a lens that resolves
# names separates the two, which is what the new file asserts.
#
# ---------------------------------------------------------------------------
# GATE 0458 -- and this one closes the corpus.
#
#     PARSED 608/608 files understood (100.0%); 0 more read only up to their
#     first parse error
#
# moui is no longer "607 of 608". `runtime/app_builder.mbt` was the last file it
# could not finish, and `unreliable` went 9 -> 0 with it: every file in that corpus
# is now UNDERSTOOD rather than read-until-some-error, which is a stronger statement
# than "no file is blocked".
#
# The blocker was one missing head in `fn_type_annotation`. After the `(` it handed
# `async` to `type_annotation()` as an ordinary type NAME; the parameter loop then
# broke on the `(` that followed rather than on a comma, and `expect(TRParen)`
# reported `expected ')'` at line 47.
#
# THE GRAMMAR IS NOT WHAT THE SOURCE LOOKS LIKE, settled 7/7 with two controls that
# can fail (`_verify/settle_0458_async_fn_type.ps1`). The trailing `?` makes the
# RETURN type optional; it does not lift the group into a nullable function:
#
#     fn build(f? : ((Int) -> Unit)? = None)                          ACCEPT
#     fn build(f? : ((Int) -> Unit)  = None)                          REJECT(4014)
#     fn build(launch_async? : (async (Int, Int) -> Unit)? = None)    ACCEPT
#
# Three fixtures had to be corrected before any grammar was measured, and each
# correction first looked like a verdict ABOUT the grammar: two were call sites given
# the wrong return shape, one confused an optional PARAMETER (`x?`) with a nullable
# TYPE (`T?`) -- and the corpus line carries both. When a probe about the language
# disagrees with you, suspect the probe's fixture first; it was wrong three times here.
#
# M4 IS THE ROW WORTH READING. Dropping `at_name("async")` from the head and keying on
# the bracket alone SURVIVED the first 648-test run -- which is exactly enough evidence
# to write "unobservable by construction" into a `Prove`, and it would have been wrong.
# `fn f(g : (((Int)) -> Unit)) -> Unit` is valid MoonBit (ACCEPT, zero errors), and after
# the outer `(` is bumped the cursor is on `(` with the next token also `(`. The
# plain-function-type control cannot see it, because there the cursor lands on
# `String`. So: "no test covers this" and "no program can reach this" are different
# claims, and a survivor verdict is a claim about the second while the evidence on hand
# only ever supports the first.
#
# M5 IS A SURVIVOR WHOSE CLAIM IS MEASURED RATHER THAN ARGUED. Two end-to-end tests in
# this increment's first draft asserted the RENDERED annotation and were deleted: the
# string is consumed inside the parser and handed to `ann_to_ty`, and it is not part of
# the pipeline result, so no end-to-end assertion can reach it (the same trap
# `pipeline_0413_test.mbt:83` describes). `src/types/types_0458_test.mbt` then answers
# the real question -- are the two renderings indistinguishable DOWNSTREAM -- by
# asserting `ann_to_ty("async (Int, Int) -> Unit?")` is `TUnknown` beside a control
# showing `ann_to_ty` does distinguish types. Teach it the `async` head and that test
# goes red on purpose, at which point M5 must become KILLED. A survivor with no
# tripwire is an untested guard with a footnote.
#
# Tests 643 -> 651: `pipeline_0458_test.mbt` and `types_0458_test.mbt`, eight cases.
# Re-pinned after 0464 (the pipe operators, `errdefer`, and a lambda as a pipe's
# right operand). Two corpora moved, both in the direction that means more files are
# understood rather than merely more opinions:
#
#     async   parsed 302 -> 325   unreliable 916 -> 733   notices 1406 -> 1550
#     proton  parsed 115 (same)   unreliable 922 -> 921   total    2406 -> 2405
#
# `unreliable` is the number that carries the meaning: it counts files read only up
# to a parse error, so async's 23 newly-parsed files are now read whole. The
# `notices` rise on async is the same trade 0459 made and is worth reading rather
# than waving at -- a file that parses reports the deliberate exclusions inside it
# (mostly skipped lambda bodies), so more files understood means more notices as
# well as fewer unreachable ones.
#
# proton moved by ONE finding: the `errdefer` arm reads its argument rather than
# skipping it, so a name in an already-understood file is now read at all.
# `notices` there is unchanged, so nothing new was merely noticed -- something that
# could not have been seen before is now seen.
#
# MEASURED TWICE, because the first pin was wrong and nothing noticed until the
# gate ran. The 312 in an earlier draft of this block was taken BEFORE the
# lambda-as-pipe-right-operand fix landed; that fix is worth 13 more async files on
# its own (312 -> 325). The pin now records the FINAL source state, re-measured by
# `_verify/scan_0427.ps1` independently of this gate and agreeing with it.
#
# => 判据: a pin is a claim about a source state, so it must be measured against
# the state that ships. A number copied from a scan taken mid-increment is not a
# stale baseline, it is a wrong one -- and the release gate is the only thing in
# this repository positioned to catch it.
# Tests 795 -> 820: `parser_0467_test.mbt` (13 cases) and `pipeline_0467_test.mbt`
# (12 cases). Re-pinned after 0467 and 0467b. TWO corpora moved, and async moved a long
# way -- the largest single-increment gain since the pipe:
#
#     async   parsed 337 -> 352   unreliable 614 -> 373   withheld 189 -> 115
#     proton  parsed 116 -> 121   unreliable 727 -> 575   withheld  59 ->  53
#
# async's `unreliable` fell 241 and proton's 152. `unreliable` is the count that carries
# meaning: those files are now read whole instead of stopping at a parse error. `withheld`
# counts the notices the analyzer deliberately does not make inside a partially-read file,
# so a drop there is reach rather than silence.
#
# 0467 THE ASYNC FUNCTION TYPE. One construct, THREE spellings, and until this increment
# exactly one of them parsed:
#
#     (async (A, B) -> R)?      a parenthesised annotation   -- parsed=1 (0458)
#     async (A, B) -> R         a bare parameter annotation  -- parsed=0
#     -> async (A, B) -> R      a bare return annotation    -- parsed=0
#
# Measured by running the analyzer over one file per shape, NOT by reading the code. The
# cause was an ORDERING fact rather than a missing keyword: the `async` lookahead in
# `fn_type_annotation` sat AFTER its `bump() // (`, so it could only ever see `async` when
# something had already put a `(` in front of it. The body is now shared
# (`fn_type_body`) behind three thin entry arms, so the spellings cannot drift again.
#
# The grammar is settled in `_verify/settle_0467_async_param_type.ps1`, 17 rows, and two
# parts of it are not guessable from the symbol. The toolchain's own diagnostic for a bare
# `async` is the whole first argument --
#
#     Parse error, unexpected token `)`, you may expect `(`.
#
# -- so the parenthesised list is REQUIRED and `lparen_at` is a discriminator rather than
# a guard. And `g : bogus (Int) -> Unit` REJECTs with 3002, so the head is a KEYWORD and
# not any name followed by a parenthesised list; that is what makes gate 0467's M3
# killable rather than a survivor.
#
# 0467b THE BINDING COLLECTOR, WHICH WAS NOT IN THE RANKING AT ALL. Reaching
# `moonbitlang/async 0.22.4 src/fs/dir.mbt` produced two ACTIONABLE false positives on
# code `moon check` compiles: `49:26 no visible binding for 'last_path_sep_index'` and
# `55:13 no visible binding for 'parent'`. Both are bound by a `let` INSIDE A CATCH ARM.
# `collect_fn_bindings` descends into `SIf`/`SFor`/`SWhile`/`SBlock`, but `catch` is an
# EXPRESSION, so no arm ever scanned one -- and `walk_stmt`'s `SLet` never binds anything
# itself, so the pre-pass is the only thing that fills the frame.
#
# THAT IS THE 0464b SHAPE FOR THE FOURTH TIME, and gate 0443 had already written the same
# sentence one level up for `SNoBreak`: "walk_stmt was taught `SNoBreak` and the COLLECTOR
# was not, and the compiler is silent about a missing arm in a match that has a catch-all".
# Nobody noticed for years because `Walker::resolve` is gated on `!self.partial`, and
# every file containing a catch arm was unread.
#
# => 判据: a false positive nobody can reach is not a false positive that does not exist.
# It is a finding whose file has not been read yet, and the only way to tell the two apart
# is to unblock the corpus and look. The reach was legitimate, so the GAP was fixed rather
# than the reach given back.
# --- 0468: a BLOCK in the RHS of a `let`, and TWO THINGS IT IS NOT ONE OF ---------
#
# Until this increment every `{` in expression position reached the atom's TLBrace arm and
# went to the FIELD grammar, which rejected the content and reported `expected a struct
# literal field here` at the brace. A block -- `{ let y = 1; y + 1 }`, whose value is its
# TAIL -- was unreadable.
#
#   moui             actionable  0 -> 0   parsed 608 UNCHANGED
#   moonbit_labeler  actionable  0 -> 1   parsed  32 -> 33
#   moonbit_image    actionable  0 -> 1   parsed  15 -> 17
#   async            actionable  0 -> 0   parsed 352 -> 390
#   proton           actionable  0 -> 0   parsed 121 -> 122
#   proton_contract  actionable  0 -> 0   parsed   4 UNCHANGED
#
# moui and proton_contract are the CONTROL and they are the reason the other four can be
# read as gain: both were ALREADY complete (608/608 and 4/4) and so cannot have
# contributed a single parse.
#
# *** ACTIONABLE IS 1 ON TWO CORPORA AND NOT 0, AND NEITHER IS CAUSED BY THE BLOCK. ***
#
# Both are PRE-EXISTING defects that 0468 made REACHABLE by reading more files -- the
# standing 判据 that a false positive nobody can reach is not a false positive that does not
# exist. They are pinned HERE rather than quietly, and they are the reason the pin moves UP:
#
#   moonbit_image 0.3.7 png.mbt:980          `operand of '!' must be bool, got 'int'`
#   moonbit_labeler 0.2.13 app_moui/rasterizer.mbt:1218
#                                           `argument 2 to 'blend_pixel' has incompatible
#                                            type 'float'; expected 'int'`
#
# The image one is ROOT-CAUSED and the fix is one line, deliberately NOT in this increment:
# parser.mbt's `TName("match")` arm reads the scrutinee and YIELDS IT, so
# `let vok = match bd { .. }` binds `vok` to `bd` itself -- same value, same type. The
# sibling `TName("fn")` arm does the same kind of skip and correctly yields an OPAQUE node;
# `match` is the inconsistent one. That changes parser semantics for an existing construct,
# so it is its own increment with its own guard test, not a line borrowed into 0468.
# The comment at that arm asserted the opposite ("the scrutinee is an ordinary expression")
# and has been corrected in place.
#
# The labeler one is UNRESOLVED and is not fixed here: either the argument index is off by
# one, or a single-line `for`-header binder takes a wrong type -- the latter would tie it to
# the `for` family.
#
# A SECOND PIN MOVED INSIDE 0468 THAT NEVER SHOWED IN ANY SUMMARY: `parse_block` was called
# with `false`, so no `EBlock` body ever contained a `STail`, `Infer::ty_of` returned
# `TUnknown` for EVERY block and `Interp::eval` returned `AAny`. Both arms were dead code
# and every corpus number above is the same with and without them, because `walk_stmt` reads
# an `SExpr` tail exactly as well as an `STail` one.
# => 判据: a construct can be READ correctly and still carry no value. Only a row that
# counts what the tree CARRIES sees this -- `0468: the tail's TYPE reaches the operator
# below` -- and it is M4 of `mutate_0468.ps1`. The flag is now named `value_block`, because
# "this is a function body" was the name that let the bug read as a decision.
#
# GATE 0468: 11/11 KILLED, no declared survivors, every restore byte-identical. Two of the
# eleven had to be REWRITTEN rather than re-anchored, and both rewrites are in the gate:
# M5's named row was the wrong one (a third lens already reports that name), and M11's first
# form mutated to `AAny`, which this behavior lens absorbs BY DESIGN -- interp.mbt:1076 has
# `AAny => true` in `numeric` and :1094 short-circuits the whole operator arm on it.
# => 判据: a survivor is not always an untested property. Sometimes it is a mutation whose
# RESULT is unobservable, and the two want opposite responses.
#
# --- 0469: a `match`'s value is the ARMS, not the subject -------------------------
#
# `parser.mbt`'s `TName("match")` arm used to read the subject and YIELD IT. That is the
# one place in the parser where "the expression I had to parse to keep the token stream in
# step" and "the value this expression produces" are different things: a `match`'s value is
# the join of its arms, and the arms are what this analyzer skips.
#
#   moui             actionable 0 -> 0   UNCHANGED, byte for byte
#   moonbit_labeler  actionable 1 -> 1   total 803 -> 801
#   moonbit_image    actionable 1 -> 0   total 231 -> 230
#   async            actionable 0 -> 0   UNCHANGED, byte for byte
#   proton           actionable 0 -> 0   UNCHANGED, byte for byte
#   proton_contract  actionable 0 -> 0   UNCHANGED, byte for byte
#
# FOUR OF SIX ARE BYTE-IDENTICAL, and that is the result being claimed: a fix that moved
# every corpus would be a fix whose scope nobody measured. moonbit_image's actionable goes
# to ZERO -- that is the whole increment. labeler's stays at 1 because its finding is the
# unrelated `for`-header/argument-index defect 0468 made reachable.
#
# THE OBVIOUS FIX WAS WRONG, WAS WRITTEN FIRST, AND WAS MEASURED BEFORE IT WAS KEPT.
# Yielding the bare `EBigInt` the anonymous-`fn` arm uses fixes the type and LOSES THE
# SUBJECT'S READS, turning two TRUE positives in `pipeline_0433_test.mbt` into false
# negatives. It passed this corpus stage and failed two unit tests.
# => 判据: "the fix removed the finding" is not the same claim as "the fix removed the
# defect". A trade of one true positive for the absence of a false one is not a trade.
# `EMatch(subject)` carries the subject and says nothing about the value: `walk_expr`
# descends, `ty_of` answers Unknown, `eval` runs the subject for its effects and yields
# `ABottom` rather than `AAny` (which every operator arm absorbs).
#
# IT CANNOT BE FOLDED INTO `ECatch` DESPITE THE IDENTICAL SHAPE. `ECatch` TYPES as its
# base because `expr catch { .. }` really does produce the base's value when no arm
# matches. A `match` does not -- its value comes from the arms. Same shape, opposite
# answer, and that difference is the entire argument for a new variant.
#
# A TEST WAS CORRECTED IN PLACE RATHER THAN LEFT: it was named "a match expression is
# skipped whole and yields its scrutinee" and asserted `@ast.EName("e")`. That was not a
# description of the construct, it was a PIN ON THE DEFECT.
#
# AND TWO ROWS WERE FOUND VACUOUS BY THE GATE. `UnusedParam == 0` for a parameter read
# only inside a match subject cannot fail, because a `match` silences `UnusedParam` for its
# whole enclosing function by design. M2 measured it: deleting the walk arm reddens three
# rows and not that one. It is recorded in place rather than deleted.
# => 判据: before keeping a negative row, ask whether ANY mutation can turn it red.
#
# GATE 0469: 4/4 KILLED, no declared survivors, every restore byte-identical.
#
$PINNED = [ordered]@{
  'moui'            = 'files=608 parsed=608 actionable=0 notices=4225 unreliable=0 withheld=0 total=4225'
  'moonbit_labeler' = 'files=37 parsed=33 actionable=1 notices=711 unreliable=89 withheld=16 total=801'
  'moonbit_image'   = 'files=18 parsed=17 actionable=0 notices=207 unreliable=23 withheld=0 total=230'
  'async'           = 'files=419 parsed=390 actionable=0 notices=1686 unreliable=285 withheld=49 total=1971'
  'proton'          = 'files=137 parsed=122 actionable=0 notices=1645 unreliable=544 withheld=35 total=2189'
  'proton_contract' = 'files=4 parsed=4 actionable=0 notices=34 unreliable=0 withheld=0 total=34'
}
$TARGETS = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
}

if ($failed.Count -eq 0) {
  Stage 'corpus SUMMARY vs pinned baseline' {
    $drift = 0
    foreach ($k in $TARGETS.Keys) {
      $p = Join-Path $repos $TARGETS[$k]
      if (-not (Test-Path $p)) { Write-Output ("  [ABSENT] {0,-16}" -f $k); $drift++; continue }
      $sum = Get-Summary (Scan-Tree $wasm $p)
      $want = $PINNED[$k]
      if ($sum -eq $want) { Write-Output ("  [MATCH ] {0,-16} {1}" -f $k, $sum) }
      else {
        $drift++
        Write-Output ("  [DRIFT ] {0,-16}" -f $k)
        Write-Output ('      pinned : ' + $want)
        Write-Output ('      actual : ' + $sum)
      }
    }
    if ($drift -eq 0) { return }
    if ($AllowCorpusDrift) { Write-Output '  (-AllowCorpusDrift: drift reported, not failed)'; return }
    Write-Output ("  {0} corpus/corpora drifted from the pinned baseline." -f $drift)
    $script:stageOk = $false
  }
  if (-not $script:lastOk) { $failed += 'corpus' }
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

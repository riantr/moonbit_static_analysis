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
  # Only the verdict lines; the per-mutation tables are 30 lines each and fourteen
  # of them bury the one line that says whether the gate passed.
  foreach ($ln in ($o -split "`r?`n")) {
    if ($ln -match '^(GATE OK|GATE FAILED|ABORT|RELEASE GATE|  Baseline:|Pre-flight|=== mutation gate)' -or $ln -match '^\s+- ') {
      Write-Output $ln
    }
  }
  if ($code -ne 0) { $script:stageOk = $false }
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
$gates = @('0412','0413','0418','0419','0420','0421','0422','0423','0424','0425','0426','0427','0428','0429','0430','0431','0432','0433','0434','0435','0436','0437','0438','0439','0440','0441','0442','0443')
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
$PINNED = [ordered]@{
  'moui'            = 'files=608 parsed=590 actionable=0 notices=4119 unreliable=246 withheld=2 total=4365'
  'moonbit_labeler' = 'files=37 parsed=25 actionable=0 notices=553 unreliable=320 withheld=140 total=873'
  'moonbit_image'   = 'files=18 parsed=2 actionable=0 notices=102 unreliable=294 withheld=117 total=396'
  'async'           = 'files=419 parsed=227 actionable=6 notices=979 unreliable=2176 withheld=499 total=3161'
  'proton'          = 'files=137 parsed=103 actionable=6 notices=1116 unreliable=900 withheld=316 total=2022'
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

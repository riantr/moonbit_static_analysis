# Negative control for `_verify/grammar_probe.ps1` -- PROVE the probe's own
# verdicts can go red before trusting a run that says they are green.
#
# WHY THIS FILE EXISTS. The probe's two headline tallies were both written as
#
#     $x = $rows | Where-Object { ... }
#     if ($x.Count -gt 0) { ...report... } else { ...'no gaps'... }
#
# `Where-Object` returns a BARE `PSCustomObject` when exactly one row matches,
# and on Windows PowerShell 5.1 a scalar `PSCustomObject` has no `.Count`
# property: `$x.Count` is `$null`, `$null -gt 0` is `$False`, and the section is
# skipped. Measured, not reasoned:
#
#   - a run whose own table showed `MOON-BAD  SELF-OK` printed
#     `no gaps: every form moon accepts is a form this frontend reads` and then
#     NOTHING for the too-permissive tally -- the finding, unreported;
#   - the same bug guarded the REAL GAP tally, so ONE real gap produced
#     `no gaps`. The headline verdict inverted in precisely the run that had
#     something to report.
#
# That is the worst shape a check can take: not a false negative but a false
# `all clear`, and the guard's presence read as evidence that the run was clean.
#
# SO THIS IS THE REPAIR'S PROOF, not a second opinion. It feeds the probe one
# known MOON-BAD/SELF-OK row, one known MOON-OK/SELF-FAIL row, one deliberately
# broken canary, and one row that pins the MOON verdict's own arithmetic -- and
# fails unless the tallies fire and `no gaps` does not.
#
# --- THE PLANTED ROW IS DERIVED, NOT HARDCODED ------------------------------
#
# `ctrl_real_gap` has been moved FOUR times, which is why the rule is written
# here rather than left tacit:
#
#   1. A lambda with an explicit parameter type,
#      `let g = (_node : Flow) => children(_node)`. The 0.4.30 lambda fix made
#      that parse and the control went RED on the next release run.
#   2. `1..<=n`, the inclusive range. The 0.4.30 inclusive-range fix made that
#      parse, and the control went RED again -- with the right symptom,
#      "announced `no gaps` while reporting a real gap".
#   3. `value[:]`, an empty slice. The empty-bounds fix made that parse too.
#   4. An anonymous `fn` as a CALL-ARGUMENT value. 0467 fixed the `async`
#      parameter annotation ABOVE it, so the parse reached past it and the row
#      closed -- the fourth RED in a row.
#
# Four moves, each costing a hand-built fixture and a full release-gate round
# trip. The fourth was also the one that could not be fixed by hand: after 0467,
# every MOON-OK case in the probe's own bank of ~26 known forms was SELF-OK, and
# ~20 hand-written candidates were either rejected by `moon check` (my fixture
# was invalid MoonBit) or already read. There was no gap left to plant on.
#
# So the row is now a SLOT and its SOURCE is derived at RUN time by
# `_verify/derive_planted_gap.ps1`, which takes a file from the PINNED CORPORA
# that this frontend genuinely cannot read -- a gap by construction, not by guess.
# The assertions below are UNCHANGED by that change: same five checks, same
# strings. What changed is where the row comes from.
#
# => THE HONEST ENDPOINT IS A FAILURE, NOT A FALLBACK. When the derivation finds
# nothing, this control FAILS and prints the log. It must never fall back to a
# hardcoded row, and it must never skip the assertion. A control that passes
# because it stopped looking is the exact defect it exists to catch, wearing the
# control's own clothes. (A row hardcoded as a fallback would ALSO be the wrong
# answer here: a stale row that has quietly become SELF-OK would then be planted
# as proof of a gap, which is a green light manufactured from nothing.)
#
# --- THE MOON VERDICT'S OWN ARITHMETIC IS PINNED TOO ------------------------
#
# `moonverdict_ten_errors` exists because the probe's MOON test was unanchored.
# `moon check` prints `Failed with 0 warnings, 10 errors`; the pattern `0 errors`
# is CONTAINED in `10 errors`, so that case scored MOON-OK -- illegal MoonBit
# reported as LEGAL, which promotes the row straight into the REAL GAP tally.
# Measured sweep over counts 0..25: the old test disagrees with the truth at
# exactly 10, 20, 30 ... and at no other count.
#
# The fixture is TEN SYNTAX errors (`let = 1` .. `let = 10`), not ten undefined
# names, and that distinction is load-bearing. Type errors are readable by this
# frontend -- it reports an undefined value as a FINDING, not a parse error --
# so a type-error fixture would score SELF-OK and land in the TOO-PERMISSIVE
# tally, breaking the `1 TOO-PERMISSIVE` assertion below for a reason that has
# nothing to do with what the row pins. With syntax errors the row is MOON-BAD /
# SELF-FAIL, which appears in neither tally, and its MOON cell is asserted
# directly instead.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\grammar_probe_control.ps1
#
#   -SimulateExhaustion   force the "no usable planted row" path, which must FAIL.
#                         This exists because that branch is the one the release
#                         gate can never reach on its own -- it only fires when the
#                         frontend reads every pinned corpus -- so without a switch
#                         it would be untested code guarding the control's whole
#                         meaning. Same reasoning as the probe's canary. The gate
#                         runs with no arguments, so normal behaviour is unchanged.
param([switch]$SimulateExhaustion)
$ErrorActionPreference = 'Stop'

$probe = Join-Path $PSScriptRoot 'grammar_probe.ps1'
if (-not (Test-Path -LiteralPath $probe)) { Write-Output 'ABORT: grammar_probe.ps1 is missing'; exit 1 }
$derive = Join-Path $PSScriptRoot 'derive_planted_gap.ps1'
if (-not (Test-Path -LiteralPath $derive)) { Write-Output 'ABORT: derive_planted_gap.ps1 is missing'; exit 1 }

Write-Output '=== grammar probe control ==='
Write-Output ''
Write-Output 'deriving a live planted gap from the pinned corpora (a file this frontend cannot read)...'
. $derive
$gap = Get-DerivedPlantedGap
if ($SimulateExhaustion) {
  $gap = [pscustomobject]@{
    Found = $false; Text = ''; Provenance = ''; Checks = 0; CorporaScanned = @()
    Unit = ''; Mode = ''
    Log = @('SIMULATED exhaustion: the derivation was short-circuited on purpose', '         so the "no usable planted row" path can be exercised')
  }
}
foreach ($l in $gap.Log) { Write-Output ('  ' + $l) }

if (-not $gap.Found) {
  Write-Output ''
  Write-Output 'grammar probe control: FAIL'
  Write-Output '  - no corpus file is both legal MoonBit and unread by this frontend, so there is'
  Write-Output '    no row left that can prove the REAL GAP tally fires.'
  Write-Output ''
  Write-Output 'This is NOT a licence to weaken the assertions below, and NOT a licence to'
  Write-Output 'hardcode a replacement row. Either of those makes the control green without'
  Write-Output 'making it evidence. The real options are:'
  Write-Output '  - pin a NEW corpus that still contains a gap this frontend cannot read, or'
  Write-Output '  - accept in writing that this frontend now reads every pinned corpus, and that'
  Write-Output '    the probe can no longer be shown to detect a gap at all -- a fact worth'
  Write-Output '    recording, not a reason to fake the demonstration.'
  exit 1
}
Write-Output ('  planted from {0}:{1}' -f $gap.Corpus, $gap.Provenance)
Write-Output ('  blocker line: {0}' -f $gap.BlockedLine)
Write-Output ''

# The derived text is base64-encoded into the generated cases file, and so is every
# other row. These are real MoonBit sources of arbitrary shape -- backticks,
# quotes, newlines, `$` -- and this repo has lost several settle cycles to a probe
# whose FIXTURE, not whose target, was malformed. Base64 sidesteps the whole
# escaping class, and the here-string below is SINGLE-quoted so that nothing in it
# is interpolated or backtick-decoded on the way out: the only substitutions are
# the four explicit `.Replace` tokens.
$tooPermissive = "fn sub(x : Int) -> Int { x }`nfn caller(c : Int) -> Int {`n  match`n    sub(c)`n  {`n    1 => 2`n    _ => 3`n  }`n}"
$canary        = "fn canary( { let = 1 }`n"
$tenErrors     = "fn f() -> Int {`n"
1..10 | ForEach-Object { $tenErrors += "  let = $_`n" }
$tenErrors    += "  0`n}`n"

function To-B64([string]$s) { return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)) }

$cases = Join-Path $env:TEMP ('grammar_control_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
$body = @'
$PROBE_CASES = [ordered]@{
  'ctrl_too_permissive'    = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__TP__'))
  'ctrl_real_gap'          = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__RG__'))
  'moonverdict_ten_errors' = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__TE__'))
  'zz_canary_must_be_rejected' = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CN__'))
}
'@
$body = $body.Replace('__TP__', (To-B64 $tooPermissive))
$body = $body.Replace('__RG__', (To-B64 $gap.Text))
$body = $body.Replace('__TE__', (To-B64 $tenErrors))
$body = $body.Replace('__CN__', (To-B64 $canary))
[IO.File]::WriteAllText($cases, $body)

try {
  $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $probe -Cases $cases 2>&1 | Out-String)
} finally {
  if (Test-Path -LiteralPath $cases) { Remove-Item -LiteralPath $cases -Force -ErrorAction SilentlyContinue }
}

$fail = @()

# 1. The canary. Without it, rows 2 and 3 would pass on a probe that never ran.
if ($out -notmatch 'canary: REJECTED by both') {
  $fail += 'the canary did not report, so the probe did not run and nothing below is evidence'
}

# 2. The REAL GAP tally, at exactly ONE row -- the count that used to vanish.
if ($out -notmatch '1 REAL GAP\(S\)') {
  $fail += 'the REAL GAP tally did not fire at one row'
}
if ($out -notmatch 'ctrl_real_gap') {
  $fail += 'the REAL GAP row is missing from the report'
}

# 3. The TOO-PERMISSIVE tally, at exactly ONE row.
if ($out -notmatch '1 TOO-PERMISSIVE') {
  $fail += 'the TOO-PERMISSIVE tally did not fire at one row'
}
if ($out -notmatch 'ctrl_too_permissive') {
  $fail += 'the TOO-PERMISSIVE row is missing from the report'
}

# 4. The inversion itself: with a real gap present, `no gaps` must be ABSENT.
#    This is the assertion the old code silently failed, and it is the one that
#    matters -- the other two would also pass if the probe printed both.
if ($out -match 'no gaps') {
  $fail += 'the probe announced "no gaps" while reporting a real gap'
}

# 5. The MOON verdict's arithmetic. The counts above cannot see this one: a row
#    misclassified as MOON-OK is promoted into the REAL GAP tally, which is still
#    "1 REAL GAP" and still fires -- so without this assertion the probe could
#    prove its tallies work while one of its verdicts is arithmetically wrong.
if ($out -notmatch 'moonverdict_ten_errors\s+MOON-BAD') {
  $fail += 'moonverdict_ten_errors was not scored MOON-BAD -- the MOON verdict regex is unanchored again'
}

if ($fail.Count -eq 0) {
  Write-Output 'grammar probe control: PASS -- both tallies fire at one row, the canary is live,'
  Write-Output ('  the planted gap is real corpus code ({0}:{1}), and the MOON verdict is anchored.' -f $gap.Corpus, $gap.Provenance)
  exit 0
}
Write-Output 'grammar probe control: FAIL'
foreach ($f in $fail) { Write-Output ("  - " + $f) }
Write-Output ''
Write-Output '--- probe output ---'
Write-Output $out
exit 1

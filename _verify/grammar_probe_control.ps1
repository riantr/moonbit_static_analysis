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
# known MOON-BAD/SELF-OK row and one known MOON-OK/SELF-FAIL row -- exactly the
# one-row shape that used to vanish -- and fails unless BOTH tallies appear and
# the string `no gaps` does not.
#
# The two control rows are REAL code, not mocks:
#   ctrl_too_permissive -- `match` with its subject and its `{` on separate
#     lines. `moon check` rejects it ("missing `{` at the end of this line"),
#     this frontend reads it. Measured MOON-BAD / SELF-OK.
#   ctrl_real_gap -- an ANONYMOUS `fn` used as a CALL-ARGUMENT value,
#     `g(async fn(request, ms) { .. })`. `moon check` accepts it; this frontend
#     reports ``unexpected token `)` ``, because `parse_call_args` has no
#     production for an `fn` literal in that position. Measured MOON-OK /
#     SELF-FAIL, and 3 files of wzzc-dev/moui 0.1.12 sit on it
#     (`backend/windows/windows_backend.mbt:155`,
#     `backend/macos/macos_app_runtime.mbt:24`,
#     `backend/linux/linux_app_runtime.mbt:22`).
#
# ctrl_real_gap HAS NOW BEEN MOVED THREE TIMES, which is why the rule is written
# here rather than left tacit:
#
#   1. It was a lambda with an explicit parameter type,
#      `let g = (_node : Flow) => children(_node)`. The 0.4.30 lambda fix made
#      that parse and the control went RED on the next release run.
#   2. It was `1..<=n`, the inclusive range. The 0.4.30 inclusive-range fix made
#      that parse, and the control went RED again on this one -- with the right
#      symptom, "announced `no gaps` while reporting a real gap".
#   3. It was `value[:]`, an empty slice. The empty-bounds fix made that parse
#      too, for the THIRD time and with the same symptom.
#
# Three moves in one release cycle, which is itself the finding: every increment
# this round landed on a gap big enough to retire a control row, and a control
# that has to be re-aimed after each one is a control that will eventually be
# re-aimed carelessly. The rule below is what makes the re-aim cheap.
#
# Each time it did its job: a row that stops being a gap stops proving anything,
# and the release gate is what notices. **When this control fails because its row
# has become SELF-OK, move the row to a still-live gap. Do not delete the control,
# and do not weaken the assertion.** Pick the replacement from the CURRENT
# `blockers.ps1` run, not from memory -- and remember that a row count there is a
# count of blocking LINES, not a forecast of files.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\grammar_probe_control.ps1
$ErrorActionPreference = 'Stop'

$probe = Join-Path $PSScriptRoot 'grammar_probe.ps1'
if (-not (Test-Path -LiteralPath $probe)) { Write-Output 'ABORT: grammar_probe.ps1 is missing'; exit 1 }

$cases = Join-Path $env:TEMP ('grammar_control_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
$body = @'
$PROBE_CASES = [ordered]@{
  'ctrl_too_permissive' = "fn sub(x : Int) -> Int { x }`nfn caller(c : Int) -> Int {`n  match`n    sub(c)`n  {`n    1 => 2`n    _ => 3`n  }`n}"
  'ctrl_real_gap'       = "async fn g(cb : async (Int, Int) -> Unit) -> Unit {`n  cb(1, 2)`n}`nasync fn f() -> Unit {`n  g(async fn(request : Int, ms : Int) {`n    ignore(request)`n    ignore(ms)`n  })`n}`n"
  'zz_canary_must_be_rejected' = "fn canary( { let = 1 }`n"
}
'@
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

if ($fail.Count -eq 0) {
  Write-Output 'grammar probe control: PASS -- both tallies fire at one row, and the canary is live.'
  exit 0
}
Write-Output 'grammar probe control: FAIL'
foreach ($f in $fail) { Write-Output ("  - " + $f) }
Write-Output ''
Write-Output '--- probe output ---'
Write-Output $out
exit 1
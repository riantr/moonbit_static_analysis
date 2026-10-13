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
#   ctrl_real_gap -- `let g = (_node : Flow) => children(_node)`, a lambda with
#     an EXPLICIT PARAM TYPE. `moon check` accepts it; this frontend reports
#     `expected ')'`. Measured MOON-OK / SELF-FAIL. This is not a synthetic
#     defect: it is the real next blocker on wzzc-dev/moui 0.1.12, so if it is
#     ever fixed this control must be moved to a still-live gap rather than
#     deleted -- a control that goes stale would stop proving anything.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\grammar_probe_control.ps1
$ErrorActionPreference = 'Stop'

$probe = Join-Path $PSScriptRoot 'grammar_probe.ps1'
if (-not (Test-Path -LiteralPath $probe)) { Write-Output 'ABORT: grammar_probe.ps1 is missing'; exit 1 }

$cases = Join-Path $env:TEMP ('grammar_control_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
$body = @'
$PROBE_CASES = [ordered]@{
  'ctrl_too_permissive' = "fn sub(x : Int) -> Int { x }`nfn caller(c : Int) -> Int {`n  match`n    sub(c)`n  {`n    1 => 2`n    _ => 3`n  }`n}"
  'ctrl_real_gap'       = "enum Flow { Leaf(Int) }`nfn children(n : Flow) -> Int { 0 }`nfn f() -> Int {`n  let g = (_node : Flow) => children(_node)`n  g(Leaf(1))`n}`n"
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
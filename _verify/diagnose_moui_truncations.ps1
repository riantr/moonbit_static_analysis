# Ranks the moui files that are READ BUT NOT FULLY PARSED, by what actually stops
# the read.
#
# WHY THIS SCRIPT EXISTS, and what it took to learn how to write it.
#
# The standing note said the core metric is "moui readable files -> zero". moui is
# files=608 parsed=591, so 17 files are PARTIAL. Two earlier attempts to rank them
# were wrong, and both wrong in a way worth recording:
#
#   1. Attributing each truncation to the FIRST NOTICE in that file. Wrong: the
#      notices sit at lines 5 and 9 while the read stopped at 13. `region_line`
#      is `first_error_line`, and no notice is AT the cut in any of the 17 -- which
#      is itself the clue that the cut is not a notice at all.
#   2. Attributing to the "outside the analyzed subset" notices, which are what a
#      first reading suggests. Also wrong: those notices describe constructs that
#      were SKIPPED, and a construct that was skipped still parsed. The read stops
#      where the PARSER failed, which is why no notice exists there -- the failure
#      happened before a notice could be produced.
#
# So the ranking below reads the SOURCE at the cut line. That is the measurement,
# and everything else was a guess about it.
#
# TWO OF THE TOP CAUSES WERE ALREADY ON THE BACKLOG, which is the useful part:
# the FFI form `fn f(..) -> T = "js" "sym"` and `async fn(..)` in call-argument
# position were both listed as open coverage items without a count. They are 4
# files and 3 files respectively, so they are the two largest single causes and
# the backlog was right to list them.
#
# This is a RANKING, not a fix. Nothing here changes the analyzer, so the 32-gate
# suite run on the parent commit still describes that tree.

$ErrorActionPreference = 'Stop'

$repo = $PSScriptRoot | Split-Path -Parent
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$wasm = Join-Path $repo '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$target = Join-Path $repo '.repos\wzzc-dev\moui\0.1.12'

if (-not (Test-Path $wasm)) { Write-Output "ABORT: no wasm at $wasm -- run `moon build --target wasm` first."; exit 1 }

$out = Join-Path $env:TEMP ('moui_trunc_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
Push-Location $repo
try {
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, '.repos\wzzc-dev\moui\0.1.12', '--extern-iface-dir', '.repos') `
    -RedirectStandardOutput $out -RedirectStandardError ($out + '.err') -NoNewWindow -Wait | Out-Null
} finally {
  Pop-Location
}

$text = [IO.File]::ReadAllText($out)
if ($text -notmatch 'SUMMARY') {
  Write-Output 'ABORT: the scanner produced no SUMMARY -- this is a harness failure, not a result.'
  exit 1
}

$summary = ($text -split "`n" | Where-Object { $_ -match '^\s*SUMMARY' } | Select-Object -First 1)
Write-Output ('moui ' + ($summary.Trim() -replace '\s*\(actionable.*$', ''))
$act = if ($summary -match 'actionable=(\d+)') { [int]$matches[1] } else { -1 }
Write-Output ''

# The read stops where the PARSER failed. `read up to line N, M after it not shown`
# is the only place N is written down, and no notice is reported at N in the same
# file -- which is what makes this script read the source rather than the notices.
$rows = @()
$noticeLines = @{}
$current = ''
foreach ($line in ($text -split "`n")) {
  # A section header names the file every finding beneath it belongs to. Getting
  # this wrong is how the FIRST version of this check produced "252 of 17": it
  # compared each notice's line against cut lines belonging to OTHER files, and a
  # number that large is a giveaway that the question was malformed.
  if ($line -match '^(PARTIAL|FOUND|CLEAN)\t') {
    $current = ($line -split "`t")[-1].Trim()
    $noticeLines[$current] = @()
    continue
  }
  if ($line -match '^\s*(\d+):\d+ - error:' -and $current -ne '') {
    $noticeLines[$current] += [int]$matches[1]
  }
}
foreach ($line in ($text -split "`n")) {
  if ($line -match '^PARTIAL' -and $line -match 'read up to line (\d+), (\d+) after') {
    $cut = [int]$matches[1]
    $after = [int]$matches[2]
    $file = ($line -split "`t")[-1].Trim()
    $src = [IO.File]::ReadAllText($file) -split "`r?`n"
    $at = if ($cut -le $src.Count) { $src[$cut - 1].Trim() } else { '<past EOF>' }
    $own = @($noticeLines[$file])
    $rows += [pscustomobject]@{
      file = $file; cut = $cut; after = $after; text = $at
      noticeAtCut = ($own -contains $cut)
      firstNotice = $(if ($own.Count) { ($own | Measure-Object -Minimum).Minimum } else { -1 })
    }
  }
}

# Classifiers, most specific first. These are the SHAPES, not the causes; the
# cause is whatever in the parser does not accept the shape.
function Classify([string]$t) {
  if ($t -match '^\)\s*->.*=\s*"' -or $t -match '^\s*fn\s+\w+\(.*\)\s*->.*=\s*"') { return 'FFI: fn .. -> T = "js" "sym"' }
  if ($t -match 'async\s+fn\s*\(') { return 'async fn(..) in call-argument position' }
  if ($t -match '^\w+\??=') { return 'labeled argument continuation' }
  # These two were ONE bucket until 0450 measured them apart, and keeping them
  # together was wrong in the worst direction: it implied the `{` files fail
  # because of the brace.
  #
  #   - `foo.mbt` cut@N on `{` -- THE CAUSE IS THE QUOTED KEYS, settled in
  #     `_verify/settle_0452_quoted_key_map.ps1`. It is a MAP literal,
  #     `{"schemaVersion": .. }`, and the toolchain ACCEPTs it against a Map while
  #     REFUSING the unquoted spelling there -- so the two are different language
  #     forms, not a typo for one another.
  #
  #     This label previously read "shape parses, cause UNISOLATED", on the
  #     evidence of nine fixtures that all read cleanly. Those fixtures used
  #     `key: value`. The SAME increment's settle had already shown a quoted key
  #     REJECT(4014) against a struct -- that was the warning, and every fixture
  #     after it quietly changed the subject. Nine green results about a struct
  #     literal said nothing about a map literal.
  #
  #     Measured, for the record:
  #       bare tail `{"a": 1}`   -> `unexpected token ':'`
  #       let value `{"a": e}`   -> `expected a struct literal field here`
  #       control `{ a: e }`     -> clean
  #   - `foo.mbt` cut@N on `fn(_ctx) {` is a lambda in an `if` BRANCH, fixed in
  #     0450.
  if ($t -eq '{') { return 'quoted-key MAP literal: the keys are the cause' }
  if ($t -match '^fn\(.*\)\s*\{$') { return 'lambda in a branch (fixed in 0450)' }
  if ($t -match '^\(if\s') { return 'parenthesised if as an operand' }
  if ($t -match '^\s*is\s+@') { return '`is` pattern continuation line' }
  if ($t -match '^\w+\?\s*:') { return 'optional parameter with a type annotation' }
  return 'UNCLASSIFIED'
}

Write-Output '=== ranked by the shape at the cut line ==='
$rows | Group-Object { Classify $_.text } | Sort-Object Count -Descending | ForEach-Object {
  Write-Output ("{0,2} x  {1}" -f $_.Count, $_.Name)
  $_.Group | Sort-Object file | ForEach-Object {
    Write-Output ("        {0,-40} cut@{1} +{2} hidden | {3}" -f (Split-Path $_.file -Leaf), $_.cut, $_.after, $_.text)
  }
}
Write-Output ''
$atCut = @($rows | Where-Object { $_.noticeAtCut })
Write-Output ("notices sitting AT their OWN file's cut line: " + $atCut.Count + " of " + $rows.Count)
if ($atCut.Count -gt 0) {
  Write-Output '  those files: ' + (($atCut | ForEach-Object { Split-Path $_.file -Leaf }) -join ', ')
  Write-Output '  a non-zero count means the premise above is stale: for those files the'
  Write-Output '  cut IS a notice line, and attributing by source would be wrong.'
}
$un = @($rows | Where-Object { (Classify $_.text) -eq 'UNCLASSIFIED' })
Write-Output ("UNCLASSIFIED cuts: " + $un.Count)

# The two numbers this script exists to keep honest.
if ($rows.Count -ne 17) {
  Write-Output ''
  Write-Output "NOTE: expected 17 PARTIAL files, found $($rows.Count). A DIFFERENT NUMBER"
  Write-Output 'means the analyzer moved and this ranking needs re-deriving -- read it'
  Write-Output 'before trusting the order above.'
}
if ($act -ne 0) {
  Write-Output ''
  Write-Output "ABORT: moui actionable=$act, not 0. This script ranks truncation, and a"
  Write-Output 'ranking of truncated files is not interesting while real findings are open.'
  exit 1
}
Write-Output ''
Write-Output 'OK: actionable is 0 and the truncation set is ranked above.'
exit 0

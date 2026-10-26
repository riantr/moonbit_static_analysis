# The ParseError / subset-exclusion backlog, measured rather than remembered.
#
# WHY THIS EXISTS. The coverage table in README.md ("The constructs the frontend
# reads past") IS THIS SCRIPT'S OUTPUT -- run it and paste what it prints. The
# table used to be assembled by hand over several releases, and it was
# INCOMPLETE: an `if` expression in expression position accounted for 45 items
# the hand-written list omitted, and `anonymous function literal` for 10,
# `const` for 6, `short lambda` for 2, `try` for 1. A list that omits 45 items
# while looking precise is worse than no list, because it reads as a ranking.
#
# So the README table is not a claim of its own: it is this script's output, and
# when the two disagree, this script is the authority.
#
# IT ALSO DOES NOT SAY WHAT THE NUMBERS ARE A COUNT OF. Each of these notices
# marks a declaration or expression the frontend read past and did not analyse,
# so what sits inside those spans is invisible to every lens -- reads are
# lost, and so are bindings. The count is therefore a floor on the coverage
# gap, not the gap itself.
#
# 0506 CHANGED WHERE THE SPLIT COMES FROM, and it is the substance of this
# increment rather than a detail of it.
#
# THE TWO CLASSES ARE NOT COSMETIC. `audit_suppressed` (walk.mbt) is a
# LINE-RANGE overlap against a function's whole extent, so only exclusions
# that can land INSIDE a function body suppress that function's frame audit
# (UnusedLocal / UnusedParam / ParamChanged). A top-level `test` block or a
# struct declaration is outside every function's extent and suppresses nothing.
#
# The script used to work that out ITSELF, from a hand-written list of five
# message shapes. That was a PROXY for the analyzer's geometry, and it was
# wrong in both directions: it did not name `loop expression`, `lexmatch
# expression`, `descending range direction` or `inclusive range end` -- all
# expressions, all inside functions, all capable of suppressing a frame audit
# -- and it called a module-level `short lambda` expression-level, which it is
# not.
#
# So the split now comes from the ANALYZER, out of the `NOTICES` table it
# prints: `printed` is the notices that lie inside some function's extent and
# are rendered one per line, and `aggregated` is the ones that lie outside
# every function's extent, hide nothing, and are counted by shape. One rule,
# in one place, and this script asks the analyzer instead of guessing.
#
# THE DISPLAY CAP IS LIFTED HERE. The counts below are the whole finding set,
# not the first 40 per file, because the README's table is measured the same
# way and a script whose output does not match the table it is supposed to
# produce is a script nobody can use.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\backlog.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$repos = Join-Path $root '.repos'
if (-not (Test-Path $wasm)) { Write-Output 'ABORT: build first -- moon build --target wasm'; exit 1 }

$dir = Join-Path $env:TEMP ('backlog_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir 'o.txt'; $err = Join-Path $dir 'o.err'
# NO `--show-notices` HERE, and that is deliberate. With the flag every notice
# is rendered per line, and the rendered list no longer says WHICH notices
# were printed -- so the breakdown could not be split. Without it the
# rendered lines ARE the printed notices and the `NOTICES` table carries the
# aggregated ones, and the two together are the complete set.
Start-Process -FilePath $moonrun `
  -ArgumentList @($wasm, $root, '--extern-iface-dir', $repos, '--findings-shown-per-file', '1000000') `
  -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
$t = [System.IO.File]::ReadAllText($out)

$sum = ([regex]::Match($t, '(?m)^SUMMARY.*$').Value) -replace "`t", ' '
$notices = [int]([regex]::Match($sum, 'notices=(\d+)').Groups[1].Value)

# THE ANALYZER'S OWN NUMBERS. The TOTAL line is the tree's notice count, and
# its `printed` and `aggregated` are the two classes -- the analyzer's own
# geometry, not a proxy for it.
$tabM = [regex]::Match($t, '(?m)^NOTICES\tTOTAL\tnotices=(\d+)\tprinted=(\d+)\taggregated=(\d+)')
if (-not $tabM.Success) {
  Write-Output 'ABORT: the scan printed no NOTICES table, so the split cannot be read.'
  exit 1
}
$tabNotices = [int]$tabM.Groups[1].Value
$printedTotal = [int]$tabM.Groups[2].Value
$aggregatedTotal = [int]$tabM.Groups[3].Value

# THE PRINTED NOTICES: the rendered notice lines. Their message is the shape.
$printedByMsg = @{}
foreach ($l in ($t -split "`r?`n")) {
  $m = [regex]::Match($l, '^\d+:\d+ - notice: (.*) \([A-Za-z]+\) \[')
  if (-not $m.Success) { continue }
  $msg = $m.Groups[1].Value
  if ($printedByMsg.ContainsKey($msg)) { $printedByMsg[$msg] = $printedByMsg[$msg] + 1 } else { $printedByMsg[$msg] = 1 }
}
# THE AGGREGATED NOTICES: the `NOTICES` table's rows.
$aggregatedByMsg = @{}
foreach ($m in [regex]::Matches($t, '(?m)^NOTICES\tcount=(\d+)\t(.+)$')) {
  $aggregatedByMsg[$m.Groups[2].Value] = [int]$m.Groups[1].Value
}

# ONE BREAKDOWN, BUILT FROM BOTH HALVES. A message can be in both: `if
# expression` is printed where it sits inside a function and aggregated where
# it sits at module top level, and the two counts are the truth about it.
$all = @{}
foreach ($k in $printedByMsg.Keys) { $all[$k] = $printedByMsg[$k] }
foreach ($k in $aggregatedByMsg.Keys) {
  if ($all.ContainsKey($k)) { $all[$k] = $all[$k] + $aggregatedByMsg[$k] } else { $all[$k] = $aggregatedByMsg[$k] }
}
$sumPrinted = 0
foreach ($k in $printedByMsg.Keys) { $sumPrinted += $printedByMsg[$k] }
$sumAggregated = 0
foreach ($k in $aggregatedByMsg.Keys) { $sumAggregated += $aggregatedByMsg[$k] }

Write-Output '=== self-scan subset-exclusion backlog ==='
Write-Output ('  ' + ($sum -replace '\s+', ' '))
Write-Output ''
Write-Output '  notices by message (descending); p = printed per line, a = aggregated'
$i = 0
foreach ($e in ($all.GetEnumerator() | Sort-Object -Property Value -Descending)) {
  $i++
  $p = 0; if ($printedByMsg.ContainsKey($e.Key)) { $p = $printedByMsg[$e.Key] }
  $a = 0; if ($aggregatedByMsg.ContainsKey($e.Key)) { $a = $aggregatedByMsg[$e.Key] }
  Write-Output ("  {0,2}. {1,5}  [p {2} / a {3}]  {4}" -f $i, $e.Value, $p, $a, $e.Key)
}
Write-Output ''
Write-Output ("  printed   (can suppress a frame audit) : {0}" -f $printedTotal)
Write-Output ("  aggregated (cannot)                   : {0}" -f $aggregatedTotal)
Write-Output ("  total notices                          : {0}" -f $notices)
Write-Output ''

# THE RECONCILIATION. Three numbers from three different computations, and
# they must agree: the SUMMARY's notices, the table's TOTAL, and the two
# halves of the breakdown above.
if ($tabNotices -ne $notices -or ($printedTotal + $aggregatedTotal) -ne $notices -or
    $sumPrinted -ne $printedTotal -or $sumAggregated -ne $aggregatedTotal) {
  Write-Output ('  FAIL: the numbers do not reconcile. SUMMARY ' + $notices +
                ', table ' + $tabNotices + ', printed ' + $sumPrinted + ' / ' + $printedTotal +
                ', aggregated ' + $sumAggregated + ' / ' + $aggregatedTotal + '.')
  exit 1
}
Write-Output ('  the breakdown reconciles: ' + $notices + ' = ' + $printedTotal + ' printed + ' + $aggregatedTotal + ' aggregated')
Write-Output ''
Write-Output '  Every row above is a span the frontend read past and did not analyse, so'
Write-Output '  what lives inside it is invisible to all three lenses. Removing one row'
Write-Output '  needs an AST node for that form, which is why these are features and not'
Write-Output '  notices to be reworded.'
Write-Output ''
Write-Output '  The `test` row is the largest single group, and it is the project excluding'
Write-Output '  its own suite. It is ALSO the clearest case of a row that does NOT suppress'
Write-Output '  anything, because a top-level test block lies outside every function extent.'
Write-Output ''
Write-Output '  What is NOT computed here: how many functions each printed row actually'
Write-Output '  switches off. That needs every fn line range, and the analyzer does not'
Write-Output '  export it. The printed total above is an UPPER BOUND and is labelled as one.'

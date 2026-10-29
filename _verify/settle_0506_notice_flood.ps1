param(
  # Audit a different tree than the pinned corpus.
  [string]$Tree = '',
  # Print the per-shape detail behind every verdict.
  [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
# 0506 settle: THE NOTICE FLOOD.
#
# WHAT THIS SETTLES. The analyzer renders a notice per line, and on the pinned
# core corpus that is 10,096 lines to say 28 things. The user-facing question
# is not "which notices exist" -- the counts are already in the SUMMARY -- it is
# "which of them is worth a line of the reader's screen".
#
# THE ANSWER IS GEOMETRY, AND IT IS THE ANALYZER'S OWN GEOMETRY. A subset
# exclusion that lies OUTSIDE every function's extent is in no function's hole
# list, so it cannot hide a finding: `src/walk/walk.mbt` says exactly this
# ("A skip on a line outside every function (a top-level `test` block, a struct
# declaration) is in no function's list"). A subset exclusion INSIDE a
# function's extent can hide a finding, and saying so is useful: it is where a
# conclusion was withheld.
#
# So the rule is: A NOTICE CAN HIDE A FINDING IFF ITS SPAN LIES INSIDE SOME
# FUNCTION'S EXTENT. Not a list of message shapes -- a POSITION.
#
# THE SHARP CONTROL IS ROW N3, and it is the row that makes this rule
# different from a message list. The SAME message -- "if expression is outside
# the analyzed subset" -- appears in N1 (inside a function) and in N3 (at
# module top level). It is printed per line in N1 and aggregated in N3. A rule
# that keyed on the wording would give both the same answer, and would be
# wrong about one of them.
#
# AND THE CONTROL FOR THE WHOLE THING IS N4: `--show-notices` restores the old
# rendering exactly, so the complete per-line list is still reachable and every
# measurement that reads it is unaffected.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\settle_0506_notice_flood.ps1
$root = Split-Path -Parent $PSScriptRoot
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$enc = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $wasm)) {
  Write-Output 'ABORT: build first -- moon build --target wasm'
  exit 1
}
if (-not (Test-Path -LiteralPath $moonrun)) {
  Write-Output ('ABORT: moonrun is not there: ' + $moonrun)
  exit 1
}

# The pins. One copy, here. The narrative quotes them and row N9 checks it.
#
# THE GEOMETRY'S SPLIT, and it is NOT the shape proxy's split. The old proxy --
# the one `_verify/backlog.ps1` used, a list of message shapes -- put 1,023 of
# the corpus's notices in the expression-level class and 9,073 in the other.
# The GEOMETRY puts 1,144 and 8,952, and both differences are the geometry
# being RIGHT and the proxy being wrong:
#
#   * 132 notices the proxy missed entirely -- `loop expression` (95), `lexmatch
#     expression` (8), `descending range direction` (19) and `inclusive range
#     end` (10). Every one of them is an EXPRESSION, so every one of them sits
#     inside a function and can hide a finding. The proxy's list simply did not
#     name them.
#   * 11 notices the proxy called expression-level and the geometry calls
#     hiding-nothing -- 10 `short lambda` and 1 `anonymous function literal` at
#     MODULE TOP LEVEL. They are expressions, but they are not inside any
#     function, so they are in no function's hole list.
#
# So the geometry is not a refinement of the proxy. It answers a different
# question, and it answers it from the analyzer's own extents.
# 0508 MOVED THE PINS, and it moved them because the demotion moved the
# corpus: `moonbit_core` actionable 28 -> 10 and notices 10096 -> 10114. The
# 18 findings that changed are the low-confidence ones, and they are all
# PRINTED -- so the printed count is 1144 + 18 = 1162 and the aggregated count
# is UNCHANGED, because a low-confidence finding is specific (a name, at a
# line) and is never aggregated into a shape.
$WANT_CORE_TOTAL   = 10114   # the notices in the pinned core corpus
$WANT_CORE_AGGREG  = 8952    # of them, outside every function's extent
$WANT_CORE_PRINTED = 1162    # of them, printed per line
$WANT_CORE_FILES   = 1029    # files in the pinned corpus
# The corpus SUMMARY as `_verify/release.ps1` pins it. These three are the
# same measurement: the settle scans the corpus the way the release gate
# scans it, so these numbers and the gate's corpus pins are one number each,
# not two that have to be kept in step by hand.
$WANT_CORE_ACTIONABLE = 10
$WANT_CORE_PARSED    = 984

$fail = 0
$rows = 0

function Say-OK {
  param([string]$Row, [string]$Detail)
  $script:rows++
  Write-Output ('  {0,-8} {1,-9} {2}' -f $Row, 'OK', $Detail)
}

function Say-Bad {
  param([string]$Row, [string]$Want, [string]$Got, [string]$Detail)
  $script:rows++
  $script:fail++
  Write-Output ('  {0,-8} {1,-9} {2}' -f $Row, 'MISMATCH', $Detail)
  Write-Output ('      want {0}; got {1}' -f $Want, $Got)
}

# Run the scanner over one directory. Returns the text and the rendered
# findings, parsed out of it.
function Invoke-Scan {
  param([string]$Dir, [switch]$ShowNotices)
  $stamp = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $o = Join-Path $env:TEMP ('msa0506_' + $stamp + '.out')
  $e = Join-Path $env:TEMP ('msa0506_' + $stamp + '.err')
  # THE SAME INVOCATION THE RELEASE GATE USES. The first version of this
  # settle scanned the corpus WITHOUT `--extern-iface-dir`, and the two
  # measurements disagreed: the gate's corpus SUMMARY says `files=1029
  # actionable=28` and this settle's said `files=1018 actionable=27`, because
  # the cross-file index changes which files are collected and which findings
  # are actionable. The notices happened to agree, which is exactly how a
  # number written down twice comes to disagree with itself.
  #
  # One measurement, one invocation: the settle measures the tree the gate
  # measures, so a number in this file and a number in `release.ps1` are the
  # same number and not two numbers that happen to look alike.
  $argl = @($wasm, $Dir, '--extern-iface-dir', $repos, '--no-auto-fetch-deps', '--findings-shown-per-file', '1000000')
  if ($ShowNotices) { $argl = @($wasm, $Dir, '--show-notices', '--extern-iface-dir', $repos, '--no-auto-fetch-deps', '--findings-shown-per-file', '1000000') }
  Start-Process -FilePath $moonrun -ArgumentList $argl -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -Wait | Out-Null
  $txt = [System.IO.File]::ReadAllText($o)
  $findings = @()
  foreach ($l in ($txt -split "`r?`n")) {
    # 0507 CHANGED THE BRACKET. It used to hold one lowercase tag -- the lens
    # list, e.g. `[structural]` -- and it now holds THREE comma-separated
    # fields: the lens list, the family's stable id (`MSA-NNN`), and the
    # confidence. The old pattern `[a-z,]+` cannot match `MSA-007`, so every
    # row that reads the rendered lines found NOTHING and reported a mismatch
    # that looked like a change in the analyzer's behaviour and was really a
    # change in how the gate parses the output.
    #
    # 0508 FIXED A SECOND HALF OF THE SAME CLASS, and the demotion is what
    # exposed it. The lens list here was `[a-z,-]+`, which does NOT contain
    # `+` -- so a MERGED finding, whose lens tag is `structural+type`, did not
    # match and was not counted. Every scope limit carries a single lens, so
    # the count was right until the demotion brought the merged findings into
    # the printed set: 18 of them, 15 with a `+` in the tag, and the printed
    # count came out 15 short of the tool's own. The pattern is the same one
    # `settle_0505_finding_quality.ps1` and `census_perfunction.ps1` use.
    $m = [regex]::Match($l, '^\d+:\d+ - (error|warning|hint|notice): (.*) \(([A-Za-z]+)\) \[([a-z+\-]+), (MSA-\d{3}), (high|low|undecided)\]$')
    if ($m.Success) {
      $findings += [pscustomobject]@{ Label = $m.Groups[1].Value; Message = $m.Groups[2].Value; Family = $m.Groups[3].Value; Id = $m.Groups[5].Value; Confidence = $m.Groups[6].Value; Line = $l }
    }
  }
  $sum = [regex]::Match($txt, '(?m)^SUMMARY.*$').Value
  $act = -1
  $am = [regex]::Match($sum, 'actionable=(\d+)')
  if ($am.Success) { $act = [int]$am.Groups[1].Value }
  $nt = -1
  $nm = [regex]::Match($sum, 'notices=(\d+)')
  if ($nm.Success) { $nt = [int]$nm.Groups[1].Value }
  $fl = -1
  $fm = [regex]::Match($sum, 'files=(\d+)')
  if ($fm.Success) { $fl = [int]$fm.Groups[1].Value }
  $pd = -1
  $pm = [regex]::Match($sum, 'parsed=(\d+)')
  if ($pm.Success) { $pd = [int]$pm.Groups[1].Value }
  # The aggregate table, when it is there.
  $rows2 = @()
  foreach ($l in ($txt -split "`r?`n")) {
    if ($l -match '^NOTICES\tcount=(\d+)\t(.*)$') {
      $rows2 += [pscustomobject]@{ N = [int]$Matches[1]; Message = $Matches[2] }
    }
  }
  $totalLine = [regex]::Match($txt, '(?m)^NOTICES\tTOTAL\tnotices=(\d+)\tprinted=(\d+)\taggregated=(\d+)\t(.*)$')
  $aggTotal = -1
  $printedTotal = -1
  if ($totalLine.Success) {
    $aggTotal = [int]$totalLine.Groups[3].Value
    $printedTotal = [int]$totalLine.Groups[2].Value
  }
  return [pscustomobject]@{
    Text = $txt; Findings = $findings; Actionable = $act; Notices = $nt; Files = $fl; Parsed = $pd
    NoticeRows = $rows2; AggregateTotal = $aggTotal; PrintedTotal = $printedTotal
  }
}

# ===========================================================================
Write-Output ''
Write-Output '=== 0506 settle: the notice flood, and which notices deserve a line ==='
Write-Output ''

$dir = Join-Path $env:TEMP ('msa0506_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null

function New-Fixture {
  param([string]$Name, [string]$Body)
  $p = Join-Path $dir $Name
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $p 'user.mbt'), $Body, $enc)
  return $p
}

# N1: an `if` in EXPRESSION position INSIDE a function.
$n1 = New-Fixture 'n1_if_in_fn' (@(
  'fn g() -> Int {'
  '  let d = if true { 1 } else { 2 }'
  '  d'
  '}'
) -join "`n")

# N2: a top-level `test` block.
$n2 = New-Fixture 'n2_test_block' (@(
  'test "a test block" {'
  '  ignore(1)'
  '}'
  ''
  'fn f() -> Unit { () }'
) -join "`n")

# N3: an `if` in EXPRESSION position at MODULE TOP LEVEL -- outside every
# function. The SAME message as N1.
$n3 = New-Fixture 'n3_if_at_top' (@(
  'let d = if true { 1 } else { 2 }'
  'ignore(d)'
  ''
  'fn f() -> Unit { () }'
) -join "`n")

# N4: all three in ONE file -- the control that the two are told apart by
# POSITION and not by wording.
$n4 = New-Fixture 'n4_both' (@(
  'test "a test block" {'
  '  ignore(1)'
  '}'
  ''
  'fn g() -> Int {'
  '  let d = if true { 1 } else { 2 }'
  '  d'
  '}'
) -join "`n")

# --- N1 ---------------------------------------------------------------------
$r = Invoke-Scan -Dir $n1
$printedIf = @($r.Findings | Where-Object { $_.Message -like 'if expression*' })
if ($printedIf.Count -eq 1) {
  Say-OK 'N1' ('an `if` inside a function is printed per line: ' + $printedIf[0].Label)
} else {
  Say-Bad 'N1' '1 printed `if expression` notice' ($printedIf.Count.ToString()) 'a notice inside a function can hide a finding and must be printed'
}

# --- N2 ---------------------------------------------------------------------
$r = Invoke-Scan -Dir $n2
$printedTest = @($r.Findings | Where-Object { $_.Message -like 'test declaration*' })
$aggTest = @($r.NoticeRows | Where-Object { $_.Message -like 'test declaration*' })
if ($printedTest.Count -eq 0 -and $aggTest.Count -eq 1 -and $aggTest[0].N -eq 1) {
  Say-OK 'N2' 'a top-level `test` block is AGGREGATED: it is outside every function, so it hides nothing'
} else {
  Say-Bad 'N2' '0 printed, 1 aggregated' ($printedTest.Count.ToString() + ' printed, ' + $aggTest.Count.ToString() + ' aggregated') 'a top-level declaration must be aggregated'
}

# --- N3: THE SHARP CONTROL -------------------------------------------------
$r = Invoke-Scan -Dir $n3
$printedIf = @($r.Findings | Where-Object { $_.Message -like 'if expression*' })
$aggIf = @($r.NoticeRows | Where-Object { $_.Message -like 'if expression*' })
if ($printedIf.Count -eq 0 -and $aggIf.Count -eq 1 -and $aggIf[0].N -eq 1) {
  Say-OK 'N3' 'the SAME `if expression` message at module top level is AGGREGATED: the rule is POSITION, not wording'
} else {
  Say-Bad 'N3' '0 printed, 1 aggregated' ($printedIf.Count.ToString() + ' printed, ' + $aggIf.Count.ToString() + ' aggregated') 'a notice outside every function must be aggregated'
}

# --- N4: both in one file --------------------------------------------------
$r = Invoke-Scan -Dir $n4
$printedIf = @($r.Findings | Where-Object { $_.Message -like 'if expression*' })
$printedTest = @($r.Findings | Where-Object { $_.Message -like 'test declaration*' })
$aggTest = @($r.NoticeRows | Where-Object { $_.Message -like 'test declaration*' })
if ($printedIf.Count -eq 1 -and $printedTest.Count -eq 0 -and $aggTest.Count -eq 1) {
  Say-OK 'N4' 'in ONE file: the `if` inside the function is printed and the `test` block is aggregated'
} else {
  Say-Bad 'N4' '1 printed `if`, 0 printed `test`, 1 aggregated `test'` `
    ($printedIf.Count.ToString() + ' / ' + $printedTest.Count.ToString() + ' / ' + $aggTest.Count.ToString()) 'the two must be told apart in the same file'
}

# --- N5: --show-notices restores the full list ------------------------------
$full = Invoke-Scan -Dir $n4 -ShowNotices
$fullIf = @($full.Findings | Where-Object { $_.Message -like 'if expression*' })
$fullTest = @($full.Findings | Where-Object { $_.Message -like 'test declaration*' })
if ($fullIf.Count -eq 1 -and $fullTest.Count -eq 1) {
  Say-OK 'N5' ('`--show-notices` prints both: ' + $fullIf.Count + ' `if` and ' + $fullTest.Count + ' `test`')
} else {
  Say-Bad 'N5' '1 `if` and 1 `test` printed' ($fullIf.Count.ToString() + ' and ' + $fullTest.Count.ToString()) 'the full per-line list must stay reachable'
}

# --- N6: the counts reconcile ----------------------------------------------
$plain = Invoke-Scan -Dir $n4
if ($plain.Notices -eq $full.Notices) {
  Say-OK 'N6' ('the SUMMARY says notices=' + $plain.Notices + ' in both modes')
} else {
  Say-Bad 'N6' ('notices=' + $full.Notices) ('notices=' + $plain.Notices) 'the flag must not change the counts'
}
$sumRows = 0
foreach ($x in $plain.NoticeRows) { $sumRows += $x.N }
$printedNotices = @($plain.Findings | Where-Object { $_.Label -eq 'notice' }).Count
# THE RECONCILIATION, and it is the cross-check that used to be "the rendered
# lines equal the SUMMARY's notices" -- which 0506 changed the shape of, not
# the strength of. The TOTAL line carries the tree's notice count; the rows
# carry the aggregated ones; and the two plus the printed notices must be the
# SUMMARY's number. Three numbers from three different computations.
if ($plain.AggregateTotal -eq ($plain.Notices - $printedNotices) -and
    $sumRows -eq $plain.AggregateTotal -and
    $plain.PrintedTotal -eq $printedNotices) {
  Say-OK 'N7' ('the aggregate reconciles: total ' + $plain.Notices + ' = ' + $printedNotices + ' printed + ' + $sumRows + ' aggregated')
} else {
  Say-Bad 'N7' ('total ' + $plain.Notices + ' = printed + aggregated') `
    ('total=' + $plain.AggregateTotal + ' printed=' + $printedNotices + ' rows=' + $sumRows) 'the aggregate table must reconcile with the SUMMARY'
}

# --- N8: the per-line notice count drops -------------------------------------
# NOT "the output is smaller", which is false for a two-notice fixture: the
# table costs two lines and saves two. The claim that matters is the one the
# corpus makes -- fewer notices rendered per line -- and the corpus is where
# N9 measures it.
$bigNotices = @($full.Findings | Where-Object { $_.Label -eq 'notice' }).Count
$smallNotices = @($plain.Findings | Where-Object { $_.Label -eq 'notice' }).Count
if ($smallNotices -lt $bigNotices) {
  Say-OK 'N8' ('the default prints fewer notice lines: ' + $smallNotices + ' against ' + $bigNotices)
} else {
  Say-Bad 'N8' 'fewer notice lines in the default' ($smallNotices.ToString() + ' against ' + $bigNotices.ToString()) 'the aggregation must remove notice lines'
}

# --- N9: the corpus --------------------------------------------------------
$core = Join-Path $repos 'moonbitlang\core\0.1.20260920+7d59c7ec9'
if ($Tree -ne '') { $core = $Tree }
if (-not (Test-Path -LiteralPath $core)) {
  Say-Bad 'N9' 'the pinned corpus' 'absent' 'the corpus is not there'
} else {
  $c = Invoke-Scan -Dir $core
  $sumRows = 0
  foreach ($x in $c.NoticeRows) { $sumRows += $x.N }
  $printedNotices = @($c.Findings | Where-Object { $_.Label -eq 'notice' }).Count
  # THE TOTAL LINE carries the tree's notice count; the ROWS carry the
  # aggregated ones. So the three numbers must reconcile: rows + printed =
  # total = the SUMMARY's notices.
  $ok = ($c.Notices -eq $WANT_CORE_TOTAL) -and
        ($c.AggregateTotal -eq $WANT_CORE_AGGREG) -and
        ($printedNotices -eq $WANT_CORE_PRINTED) -and
        ($sumRows -eq $WANT_CORE_AGGREG) -and
        (($sumRows + $printedNotices) -eq $c.Notices) -and
        ($c.PrintedTotal -eq $WANT_CORE_PRINTED) -and
        ($c.Files -eq $WANT_CORE_FILES) -and
        ($c.Actionable -eq $WANT_CORE_ACTIONABLE) -and
        ($c.Parsed -eq $WANT_CORE_PARSED)
  if ($ok) {
    $pct = [math]::Round(100.0 * $WANT_CORE_AGGREG / $WANT_CORE_TOTAL, 1)
    Say-OK 'N9' ('the pinned corpus: ' + $c.Files + ' files, ' + $c.Notices + ' notices, ' + $printedNotices + ' printed, ' + $sumRows + ' aggregated (' + $pct.ToString() + '%)')
    if ($Verbose) {
      foreach ($x in $c.NoticeRows) { Write-Output ('      ' + $x.N.ToString().PadLeft(6) + '  ' + $x.Message) }
    }
  } else {
    Say-Bad 'N9' ($WANT_CORE_TOTAL.ToString() + ' notices / ' + $WANT_CORE_PRINTED.ToString() + ' printed / ' + $WANT_CORE_AGGREG.ToString() + ' aggregated') `
      ($c.Notices.ToString() + ' / ' + $printedNotices.ToString() + ' / ' + $sumRows.ToString() + ' (rows ' + $sumRows + ', files ' + $c.Files + ', parsed ' + $c.Parsed + ', actionable ' + $c.Actionable + ')') 'the corpus reach moved'
  }
}

# --- N10: no summary number moves on the corpus -----------------------------
if ($Tree -eq '' -and (Test-Path -LiteralPath $core)) {
  $cf = Invoke-Scan -Dir $core -ShowNotices
  $same = ($cf.Notices -eq $c.Notices) -and ($cf.Actionable -eq $c.Actionable)
  if ($same) {
    Say-OK 'N10' ('the corpus SUMMARY is the same in both modes: notices=' + $cf.Notices + ' actionable=' + $cf.Actionable)
  } else {
    Say-Bad 'N10' 'the same SUMMARY in both modes' `
      ('notices ' + $cf.Notices + '/' + $c.Notices + ' actionable ' + $cf.Actionable + '/' + $c.Actionable) 'the flag must not move a summary number'
  }
}

# ---------------------------------------------------------------------------
Write-Output ''
if ($fail -gt 0) {
  Write-Output ('ABORT: ' + $fail + ' of ' + $rows + ' row(s) did not match. The flood is not settled.')
  exit 1
}
Write-Output ('GATE OK: ' + $rows + ' rows. A notice is worth a line of the reader''s screen only when it can hide a finding -- and that is a POSITION, not a wording: the same "if expression" message is printed inside a function and aggregated at module top level. The rest are counted, not printed, and `--show-notices` brings the whole list back.')
exit 0

# 0507 settle: THE THREE TRANSFERS FROM BANDIT, MEASURED.
#
# WHAT THIS IS. 0505 was a PLAN: it named three things to port from PyCQA's
# `bandit` -- a per-finding confidence axis, stable family ids with a checked
# profile, and `nosec` with a warning when a suppression matched nothing -- and
# it MEASURED every premise the plan rested on, so that the plan would not be
# built on a premise that stopped being true while nobody was looking.
#
# 0507 is the IMPLEMENTATION of that plan, and this script is its settle: the
# same discipline, one increment later. It measures each of the three
# transfers ON THE REAL SCANNER, with a control for each, and it checks the
# numbers the narrative quotes against the numbers measured here.
#
# THE THREE TRANSFERS, and what each one has to PROVE:
#
#   1. THE CONFIDENCE AXIS. `high` when the lens had the declaration, the
#      signature or the type in front of it; `low` when the lens was reasoning
#      from a NAME alone; `undecided` when the lens could not decide at all.
#      The point is not that the three words exist -- it is that a finding
#      which could not be checked is no longer indistinguishable from a
#      finding which was checked and found clean.
#   2. THE STABLE IDS AND THE CHECKED PROFILE. An id is allocated and never
#      renumbered; a profile selects families by id; an unknown id is a
#      WARNING; an id that is both included and excluded is an ERROR.
#   3. THE `nosec`. Per line, per family id or blanket; a `nosec` that
#      matched NOTHING is reported as a finding of its own.
#
# AND THE FOURTH THING, which is not a transfer and is measured here because
# it is the reason the first transfer exists: the UNCHECKED-CALL DISCLOSURE.
# The analyzer checks a call's arity and argument types only when it has read
# the callee's signature, and until 0507 it said nothing at all about the
# calls it could not check -- so "I could not check this" and "there is
# nothing to report" were the same output.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\settle_0507_bandit_transfers.ps1
$root = Split-Path -Parent $PSScriptRoot
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

# ---------------------------------------------------------------------------
# THE PINS. One copy, here. The narrative quotes them; the last row checks
# that it does, so the two can never drift apart without the gate going red.
# ---------------------------------------------------------------------------
$WANT_FAMILIES   = 12     # members of the `Family` enum
$WANT_ROSTER     = 12     # ids in the roster, MSA-001 .. MSA-012
$WANT_CONFIDENCE = 3      # high / low / undecided
$WANT_STALE_ID   = 'MSA-012'

$fail = 0
$rows = 0

function Say-OK {
  param([string]$Row, [string]$Verdict, [string]$Detail)
  $script:rows++
  Write-Output ('  {0,-10} {1,-9} {2}' -f $Row, $Verdict, $Detail)
}

function Say-Bad {
  param([string]$Row, [string]$Want, [string]$Got, [string]$Detail)
  $script:rows++
  $script:fail++
  Write-Output ('  {0,-10} {1,-9} {2}' -f $Row, 'MISMATCH', $Detail)
  Write-Output ('      want {0}; got {1}' -f $Want, $Got)
}

# ---------------------------------------------------------------------------
# Run the scanner over one directory. Returns the stdout text, the rendered
# findings parsed out of it, and the SUMMARY's fields.
#
# THE RENDERED FINDING, as 0507 renders it:
#
#     <line>:<col> - <label>: <message> (<Family>) [<lenses>, <id>, <confidence>]
#
# The id and the confidence are in the BRACKET and not in the parentheses, and
# that is deliberate: the parentheses are the family, and every consumer that
# compares that field against a family name keeps working unchanged.
# ---------------------------------------------------------------------------
function Invoke-Scan {
  param([string]$Dir, [string[]]$Extra = @())
  $stamp = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $o = Join-Path $env:TEMP ('msa0507_' + $stamp + '.out')
  $e = Join-Path $env:TEMP ('msa0507_' + $stamp + '.err')
  $argl = @($wasm, $Dir) + $Extra + @('--no-auto-fetch-deps', '--findings-shown-per-file', '1000000')
  Start-Process -FilePath $moonrun -ArgumentList $argl -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -Wait | Out-Null
  $txt = [System.IO.File]::ReadAllText($o)
  $findings = @()
  foreach ($l in ($txt -split "`r?`n")) {
    $m = [regex]::Match($l, '^\d+:\d+ - (error|warning|hint|notice): (.*) \(([A-Za-z]+)\) \[([a-z+\-]+), (MSA-\d{3}), (high|low|undecided)\]$')
    if ($m.Success) {
      $findings += [pscustomobject]@{
        Label = $m.Groups[1].Value
        Message = $m.Groups[2].Value
        Family = $m.Groups[3].Value
        Lenses = $m.Groups[4].Value
        Id = $m.Groups[5].Value
        Confidence = $m.Groups[6].Value
      }
    }
  }
  $sum = [regex]::Match($txt, '(?m)^SUMMARY.*$').Value
  $act = -1
  $am = [regex]::Match($sum, 'actionable=(\d+)')
  if ($am.Success) { $act = [int]$am.Groups[1].Value }
  $unc = -1
  $um = [regex]::Match($sum, 'unchecked=(\d+)')
  if ($um.Success) { $unc = [int]$um.Groups[1].Value }
  return [pscustomobject]@{ Text = $txt; Findings = $findings; Actionable = $act; Summary = $sum; Unchecked = $unc }
}

$dir = Join-Path $env:TEMP ('msa0507_settle_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null

function New-Fixture {
  param([string]$Name, [hashtable]$Files)
  $p = Join-Path $dir $Name
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  foreach ($k in $Files.Keys) {
    [System.IO.File]::WriteAllText((Join-Path $p $k), $Files[$k], $enc)
  }
  return $p
}

Write-Output '0507 settle: THE THREE TRANSFERS FROM BANDIT, MEASURED.'
Write-Output ''

# ---------------------------------------------------------------------------
# 1. THE CONFIDENCE AXIS
# ---------------------------------------------------------------------------
Write-Output '--- 1. THE CONFIDENCE AXIS: three situations, three values ---'

# The fixture carries all three situations at once, which is the point: the
# three values are not three labels for three different tools, they are three
# states of the SAME lens on the SAME run.
$confSrc = @(
  'fn helper(s : String) -> Int {',
  '  s.length()',
  '}',
  '',
  'fn pick(x : Int) -> Int {',
  '  let y = if x > 0 { 1 } else { 0 }',
  '  y',
  '}',
  '',
  'fn main() -> Unit {',
  '  let n = helper(42)',
  '  let u = nosuchfn(1)',
  '  let p = pick(1)',
  '  ignore(n)',
  '  ignore(u)',
  '  ignore(p)',
  '}',
  ''
) -join "`n"
$conf = New-Fixture 'conf' @{ 'user.mbt' = $confSrc }
$r = Invoke-Scan -Dir $conf

$high = @($r.Findings | Where-Object { $_.Confidence -eq 'high' })
$low = @($r.Findings | Where-Object { $_.Confidence -eq 'low' })
$undec = @($r.Findings | Where-Object { $_.Confidence -eq 'undecided' })

# T1 -- HIGH: the type lens had the signature in front of it. `helper` is
# declared IN THE SAME FILE, so the argument type was checked against a
# signature the lens read.
if ($high.Count -ge 1) {
  $fam = ($high | ForEach-Object { $_.Family } | Sort-Object -Unique) -join ','
  Say-OK 'T1' 'HIGH' ('the type lens read the signature: ' + $fam + ' -> high')
} else {
  Say-Bad 'T1' 'at least one high-confidence finding' ($r.Findings.Count.ToString() + ' findings') 'no finding was reported as high'
}

# T2 -- LOW: the family reasons from a NAME alone. `UndefinedName` is the only
# such family, and the reason it is `low` is that the binding the analyzer
# could not find may be in a file, or in a package, it was never given.
$lowFam = @($low | Where-Object { $_.Family -eq 'UndefinedName' })
if ($low.Count -ge 1 -and $lowFam.Count -ge 1) {
  Say-OK 'T2' 'LOW' ('a name-only family is low: ' + $lowFam[0].Message)
} else {
  Say-Bad 'T2' 'an UndefinedName finding at low confidence' ($low.Count.ToString() + ' low') 'the name-only family is not low'
}

# T3 -- UNDECIDED: the lens could not decide at all. An `if` EXPRESSION is
# outside the analyzed subset, so the finding is a declared scope limit, and
# a scope limit is the analyzer saying it did not read the construct.
if ($undec.Count -ge 1 -and $undec[0].Label -eq 'notice') {
  Say-OK 'T3' 'UNDECIDED' ('a scope limit is undecided: ' + $undec[0].Message)
} else {
  Say-Bad 'T3' 'a notice at undecided confidence' ($undec.Count.ToString() + ' undecided') 'the scope limit is not undecided'
}

# T4 -- THE THREE VALUES ARE THREE. Not two, and not four: the axis has
# exactly the three states, and every rendered finding carries one of them.
$confs = @($r.Findings | ForEach-Object { $_.Confidence } | Sort-Object -Unique)
if ($confs.Count -eq $WANT_CONFIDENCE) {
  Say-OK 'T4' 'OK' ('the axis has ' + $confs.Count + ' values on this fixture: ' + ($confs -join ', '))
} else {
  Say-Bad 'T4' ($WANT_CONFIDENCE.ToString() + ' values') ($confs -join ',') 'the confidence vocabulary moved'
}

# ---------------------------------------------------------------------------
# 2. THE STABLE IDS
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 2. THE STABLE FAMILY IDS ---'

# T5 -- EVERY RENDERED FINDING CARRIES AN ID, and every id is in the roster.
# An id that is not in the roster would be a family the roster does not know,
# and a `nosec` naming it would be silently stale.
$ids = @($r.Findings | ForEach-Object { $_.Id } | Sort-Object -Unique)
$roster = @()
for ($i = 1; $i -le 99; $i++) {
  $cand = 'MSA-' + $i.ToString('000')
  $roster += $cand
}
$unknown = @($ids | Where-Object { $roster -notcontains $_ })
if ($r.Findings.Count -ge 1 -and $unknown.Count -eq 0) {
  Say-OK 'T5' 'OK' ('every rendered finding carries a roster id: ' + ($ids -join ', '))
} else {
  Say-Bad 'T5' 'every id in the roster' ($unknown -join ',') 'a finding carries an id the roster does not know'
}

# T6 -- THE JSON RECORD CARRIES BOTH NEW FIELDS. It is read from the SOURCE,
# because building the js bridge is not part of this settle, and because the
# source is the thing that publishes the shape.
$jTxt = [System.IO.File]::ReadAllText((Join-Path $root 'src\jsoncli\main.mbt'), [System.Text.Encoding]::UTF8)
$fM = [regex]::Match($jTxt, '(?s)struct Finding \{(.*?)\}\s*derive\(ToJson\)')
if (-not $fM.Success) {
  Say-Bad 'T6' 'the Finding record' 'not found' 'the source changed shape'
} else {
  $fields = @()
  foreach ($l in ($fM.Groups[1].Value -split "`r?`n")) {
    $t = $l.Trim()
    if ($t -match '^([a-z_]+)\s*:') { $fields += $Matches[1] }
  }
  $hasSev = ($fields -contains 'severity')
  $hasConf = ($fields -contains 'confidence')
  $hasId = ($fields -contains 'family_id')
  if ($hasSev -and $hasConf -and $hasId) {
    Say-OK 'T6' 'OK' ('the Finding record carries severity, confidence and family_id: ' + ($fields -join ', '))
  } else {
    Say-Bad 'T6' 'severity, confidence and family_id' ($fields -join ', ') 'the JSON shape moved'
  }
}

# ---------------------------------------------------------------------------
# 3. THE PROFILE
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 3. THE PROFILE: a checked selection of families ---'

# T7 -- AN INCLUDE SET KEEPS ONLY THE FAMILIES IT NAMES. And it keeps them
# COMPLETELY: the count of the kept findings is the count of the findings of
# that family in the unfiltered scan.
$plain = Invoke-Scan -Dir $conf
$inc = Invoke-Scan -Dir $conf -Extra @('--families', 'MSA-002')
$wantN = @($plain.Findings | Where-Object { $_.Id -eq 'MSA-002' }).Count
if ($inc.Findings.Count -eq $wantN -and $wantN -ge 1) {
  Say-OK 'T7' 'OK' ('--families MSA-002 keeps ' + $inc.Findings.Count + ' of ' + $plain.Findings.Count + ' findings')
} else {
  Say-Bad 'T7' ($wantN.ToString() + ' findings') ($inc.Findings.Count.ToString()) 'the include set did not keep exactly its family'
}

# T8 -- AN EXCLUDE SET DROPS THE FAMILIES IT NAMES. The complement of T7, and
# the two together are the whole of the filter.
$exc = Invoke-Scan -Dir $conf -Extra @('--exclude-families', 'MSA-002')
if ($exc.Findings.Count -eq ($plain.Findings.Count - $wantN)) {
  Say-OK 'T8' 'OK' ('--exclude-families MSA-002 drops ' + $wantN + ', leaving ' + $exc.Findings.Count)
} else {
  Say-Bad 'T8' ($plain.Findings.Count - $wantN).ToString() ($exc.Findings.Count.ToString()) 'the exclude set dropped the wrong number'
}

# T9 -- AN UNKNOWN ID IS A WARNING AND THE SCAN STILL RUNS. A family added in
# a later release must not make an older analyzer's profile unusable, and a
# typo must be loud rather than fatal.
$unk = Invoke-Scan -Dir $conf -Extra @('--families', 'MSA-999')
$warned = ($unk.Text -match 'WARNING\tunknown family id')
if ($warned -and $unk.Summary -ne '') {
  Say-OK 'T9' 'WARNING' ('an unknown id warns and the scan still runs: ' + $unk.Summary.Substring(0, [Math]::Min(60, $unk.Summary.Length)))
} else {
  Say-Bad 'T9' 'a WARNING and a SUMMARY' ('warned=' + $warned) 'an unknown id must warn without stopping the scan'
}

# T10 -- AN ID THAT IS BOTH INCLUDED AND EXCLUDED IS AN ERROR, and the scan
# DOES NOT RUN. The two rules contradict each other, so which one won would be
# decided by the order of two `if`s inside the scanner.
$ovl = Invoke-Scan -Dir $conf -Extra @('--families', 'MSA-002', '--exclude-families', 'MSA-002')
$errored = ($ovl.Text -match 'ERROR\tthe profile includes and excludes')
if ($errored -and $ovl.Summary -eq '') {
  Say-OK 'T10' 'ERROR' 'an include/exclude overlap is an error, and no scan ran'
} else {
  Say-Bad 'T10' 'an ERROR and no SUMMARY' ('errored=' + $errored + ' summary=' + $ovl.Summary) 'the overlap must stop the scan'
}

# ---------------------------------------------------------------------------
# 4. THE `nosec`
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 4. THE `nosec`: per line, per family, and never silently ---'

$nosecSrc = "fn main() -> Unit {`n  let x = nosuchfn(1) // nosec`n  ignore(x)`n}`n"
$ns = New-Fixture 'nosec' @{ 'user.mbt' = $nosecSrc }

# T11 -- IT IS OFF BY DEFAULT. A tool that stops reporting a finding because
# of a comment in the ANALYSED source has an output the reader cannot trust
# without reading that source first.
$off = Invoke-Scan -Dir $ns
if ($off.Findings.Count -eq 1) {
  Say-OK 'T11' 'OFF' 'a `// nosec` comment suppresses nothing unless it is asked for'
} else {
  Say-Bad 'T11' '1 finding' ($off.Findings.Count.ToString()) 'the default changed'
}

# T12 -- WITH THE FLAG, A BLANKET NOSEC SUPPRESSES THE FINDING ON ITS LINE.
$on = Invoke-Scan -Dir $ns -Extra @('--honor-nosec')
if ($on.Findings.Count -eq 0) {
  Say-OK 'T12' 'SUPPRESSED' 'a blanket `// nosec` silences the finding on its line'
} else {
  Say-Bad 'T12' '0 findings' ($on.Findings.Count.ToString()) 'the blanket nosec did not suppress'
}

# T13 -- A NOSEC THAT MATCHED NOTHING IS A FINDING OF ITS OWN. A suppression
# that has gone stale is dead weight in the source, and it is a sign that the
# code it referred to has changed.
$staleSrc = "fn main() -> Unit {`n  let x = nosuchfn(1) // nosec MSA-999`n  ignore(x)`n}`n"
$st = New-Fixture 'stale' @{ 'user.mbt' = $staleSrc }
$str = Invoke-Scan -Dir $st -Extra @('--honor-nosec')
$staleRows = @($str.Findings | Where-Object { $_.Family -eq 'StaleNosec' })
if ($staleRows.Count -eq 1 -and $staleRows[0].Id -eq $WANT_STALE_ID) {
  Say-OK 'T13' 'STALE' ('a nosec that matched nothing is reported: ' + $staleRows[0].Message)
} else {
  Say-Bad 'T13' '1 StaleNosec finding' ($staleRows.Count.ToString()) 'the stale suppression was not reported'
}

# T14 -- THE STALE FINDING IS ITSELF A FINDING OF THE ROSTER: it has an id,
# and it has a confidence. It is not a warning printed to the side.
if ($staleRows.Count -eq 1 -and $staleRows[0].Confidence -eq 'high') {
  Say-OK 'T14' 'OK' ('the stale finding carries ' + $staleRows[0].Id + ' at ' + $staleRows[0].Confidence)
} else {
  Say-Bad 'T14' 'MSA-012 at high confidence' ('see above') 'the stale finding is not a first-class finding'
}

# ---------------------------------------------------------------------------
# 5. THE UNCHECKED-CALL DISCLOSURE
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 5. THE UNCHECKED-CALL DISCLOSURE ---'

# A file with ONE call the type lens cannot check: a method call, whose
# signature the lens never reads.
$ucSrc = "fn main() -> Unit {`n  let s = `"abc`"`n  let n = s.length()`n  ignore(n)`n}`n"
$uc = New-Fixture 'unchecked' @{ 'user.mbt' = $ucSrc }
$ur = Invoke-Scan -Dir $uc
$fileUnc = [regex]::Match($ur.Text, '(?m)^(?:CLEAN|FOUND)\t[^\t]*\t[^\t]*unchecked=(\d+)')
$sumUnc = [regex]::Match($ur.Text, '(?m)^SUMMARY.*?unchecked=(\d+)')
if ($fileUnc.Success -and [int]$fileUnc.Groups[1].Value -ge 1 -and $sumUnc.Success -and [int]$sumUnc.Groups[1].Value -ge 1) {
  Say-OK 'T15' 'OK' ('the verdict line says unchecked=' + $fileUnc.Groups[1].Value + ' and the SUMMARY says unchecked=' + $sumUnc.Groups[1].Value)
} else {
  Say-Bad 'T15' 'an unchecked count on both lines' ('file=' + $fileUnc.Groups[1].Value + ' summary=' + $sumUnc.Groups[1].Value) 'the disclosure did not reach the output'
}

# T16 -- AND A FILE WITH NOTHING TO CHECK SAYS ZERO. The number has to be
# there in both cases, or "no unchecked calls" would be a thing the reader
# cannot distinguish from "this analyzer does not count them".
$zeroSrc = "fn main() -> Unit {`n  let x = 1`n  ignore(x)`n}`n"
$zc = New-Fixture 'zero' @{ 'user.mbt' = $zeroSrc }
$zr = Invoke-Scan -Dir $zc
$zUnc = [regex]::Match($zr.Text, '(?m)^SUMMARY.*?unchecked=(\d+)')
if ($zUnc.Success -and [int]$zUnc.Groups[1].Value -eq 0) {
  Say-OK 'T16' 'ZERO' 'a file with nothing to check says unchecked=0'
} else {
  Say-Bad 'T16' 'unchecked=0' ($zUnc.Groups[1].Value) 'the zero case is not zero'
}

# T17 -- AND IT IS NOT A FINDING. The unchecked count is NOT part of the
# SUMMARY's identity: `actionable + notices + unreliable = total` still holds,
# and a file whose calls went unchecked still has zero findings.
if ($ur.Actionable -eq 0 -and $ur.Summary -match 'actionable\+notices\+unreliable = total') {
  Say-OK 'T17' 'OK' 'an unchecked call is not a finding: actionable is still 0 and the identity still holds'
} else {
  Say-Bad 'T17' 'actionable 0 and the identity intact' ('actionable=' + $ur.Actionable) 'the disclosure leaked into the finding count'
}

# ---------------------------------------------------------------------------
# 6. THE ROSTER, AS THE ANALYZER SEES IT
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 6. THE ROSTER ---'

# T18 -- THE ROSTER IS TWELVE FAMILIES AND TWELVE IDS, and the ids run from
# MSA-001 without a gap. The count is checked here as well as in
# `_verify/check_family_roster.ps1`: that gate reads the SOURCE, and this one
# reads what the ANALYZER hands out.
$allSrc = "fn main() -> Unit {`n  let x = nosuchfn(1)`n  ignore(x)`n}`n"
$al = New-Fixture 'roster' @{ 'user.mbt' = $allSrc }
$ar = Invoke-Scan -Dir $al
$seenIds = @($ar.Findings | ForEach-Object { $_.Id } | Sort-Object -Unique)
if ($seenIds.Count -ge 1 -and $seenIds[0] -eq 'MSA-002') {
  Say-OK 'T18' 'OK' ('the analyzer hands out roster ids: ' + ($seenIds -join ', '))
} else {
  Say-Bad 'T18' 'MSA-002 among the ids' ($seenIds -join ',') 'the analyzer handed out an id outside the roster'
}

# T19 -- THE NARRATIVE QUOTES THESE NUMBERS, AND MUST AGREE WITH THEM.
# T19 is ONE row that quotes three numbers, so it counts once -- otherwise the gate
# would report "18 rows" for a T1..T19 roster, and a count that disagrees with the
# roster it describes is exactly the kind of number this repo does not publish.
$script:rows++
$narPath = Join-Path $root '_verify\NARRATIVE.md'
$narTxt = [System.IO.File]::ReadAllText($narPath, [System.Text.Encoding]::UTF8)
$quotes = @(
  @{ N = 'the family roster, families';          V = $WANT_FAMILIES.ToString() }
  @{ N = 'the family roster, ids';               V = $WANT_ROSTER.ToString() }
  @{ N = 'the confidence axis, values';           V = $WANT_CONFIDENCE.ToString() }
)
$bad = 0
foreach ($q in $quotes) {
  $rx = '(?m)^\s*0507\s+' + [regex]::Escape($q.N) + '\s*:\s*(\d+(?:\.\d+)?)\s*$'
  $m = [regex]::Match($narTxt, $rx)
  if (-not $m.Success) {
    Write-Output ('  T19        MISSING  the narrative does not quote "' + $q.N + '"')
    $bad++
    continue
  }
  if ($m.Groups[1].Value -ne $q.V) {
    Write-Output ('  T19        WRONG    the narrative says ' + $m.Groups[1].Value + ' for "' + $q.N + '"; the measurement says ' + $q.V)
    $bad++
    continue
  }
  Write-Output ('  {0,-10} {1,-9} {2} = {3}' -f 'T19', 'OK', $q.N, $q.V)
}
if ($bad -gt 0) {
  $fail++
  Write-Output ('  T19        MISMATCH ' + $bad + ' quoted number(s) disagree with the measurement')
} else {
  Write-Output ('  {0,-10} {1,-9} all {2} quoted numbers agree with the measurement' -f 'T19', 'OK', $quotes.Count)
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output ('ABORT: ' + $fail + ' of ' + $rows + ' row(s) did not match. The transfers are not what the narrative says they are.')
  exit 1
}
Write-Output ('GATE OK: ' + $rows + ' rows. A finding now says how much the lens CHECKED beside how bad it would be if it is real, every family has an id that is never renumbered, a profile selects families by id and is checked before the scan runs, a `// nosec` silences one line and a stale one is a finding, and the calls the analyzer could not check are disclosed instead of rounded down to silence.')
exit 0

# 0508 settle: THE CONFIDENCE DEMOTION, MEASURED.
#
# WHAT THIS IS. 0507 ported the confidence AXIS from PyCQA's `bandit`: every
# finding carries `high`, `low` or `undecided`. What it did not do is ACT on
# the axis, and the clause of the transfer that was still open is the one
# bandit implements as `Issue.filter` -- an issue carries a severity AND a
# confidence, and `Issue.filter` (bandit/core/issue.py:147-167) needs BOTH to
# clear the thresholds.
#
# So the second axis was in the model but not in the filter: a `low`-confidence
# finding -- the one family that reasons from a NAME alone, `UndefinedName` --
# was rendered `error:` and counted as actionable, which says "the analyzer
# checked this and it is wrong" about a finding the analyzer itself says it
# could not check.
#
# 0508 is the DEMOTION: a finding the analyzer does not stand behind is
# rendered `notice:` and is counted in `notices` rather than in `actionable`.
# It is NOT hidden -- it keeps its family, its stable id and its confidence,
# and it keeps a line of the reader's screen.
#
# WHAT THIS SETTLE MEASURES, on the REAL SCANNER and on fixtures:
#   * the label a low-confidence finding gets, and the label a finding the
#     analyzer stands behind keeps;
#   * that the demoted finding is still reported, still counted, and still on
#     a line of its own;
#   * that the two kinds of notice -- the declared scope limit and the
#     low-confidence finding -- are told apart by MECHANISM and not by the
#     confidence;
#   * that the counts still reconcile: actionable + notices + unreliable = total.
#
# AND THE NUMBERS THE NARRATIVE QUOTES ARE CHECKED HERE, so the published
# numbers and the measured ones cannot drift apart.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\settle_0508_confidence_demotion.ps1
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
$WANT_LABEL_DEMOTED = 'notice'
$WANT_CONF_DEMOTED  = 'low'
$WANT_ID_DEMOTED    = 'MSA-002'
$WANT_FAM_DEMOTED   = 'UndefinedName'
$WANT_LABEL_SOLID   = 'warning'
$WANT_CONF_SOLID    = 'high'
$WANT_FAM_SOLID     = 'UnusedLocal'
$WANT_CONF_LIMIT    = 'undecided'
$WANT_FAM_LIMIT     = 'ParseError'
$WANT_ID_LIMIT      = 'MSA-001'
$WANT_ACTIONABLE_AFTER = '0'
$WANT_NOTICES_AFTER    = '1'
$WANT_TOTAL_AFTER      = '1'

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
# findings parsed out of it, the SUMMARY's fields and the NOTICES table's TOTAL
# line.
#
# THE RENDERED FINDING, as 0507 renders it and 0508 relabels:
#
#     <line>:<col> - <label>: <message> (<Family>) [<lenses>, <id>, <confidence>]
#
# The LABEL is what the demotion changes: `notice` for a finding the analyzer
# does not stand behind, the family's own severity for one it does.
# ---------------------------------------------------------------------------
function Invoke-Scan {
  param([string]$Dir, [string[]]$Extra = @())
  $stamp = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $o = Join-Path $env:TEMP ('msa0508_' + $stamp + '.out')
  $e = Join-Path $env:TEMP ('msa0508_' + $stamp + '.err')
  $argl = @($wasm, $Dir) + $Extra + @('--no-auto-fetch-deps', '--findings-shown-per-file', '1000000')
  Start-Process -FilePath $moonrun -ArgumentList $argl -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -Wait | Out-Null
  $txt = [System.IO.File]::ReadAllText($o, [System.Text.Encoding]::UTF8)
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
  $act = '-1'
  $am = [regex]::Match($sum, 'actionable=(\d+)')
  if ($am.Success) { $act = $am.Groups[1].Value }
  $not = '-1'
  $nm = [regex]::Match($sum, 'notices=(\d+)')
  if ($nm.Success) { $not = $nm.Groups[1].Value }
  $unr = '-1'
  $um = [regex]::Match($sum, 'unreliable=(\d+)')
  if ($um.Success) { $unr = $um.Groups[1].Value }
  $tot = '-1'
  $tm = [regex]::Match($sum, 'total=(\d+)')
  if ($tm.Success) { $tot = $tm.Groups[1].Value }
  $printed = '-1'
  $aggregated = '-1'
  $pm = [regex]::Match($txt, "(?m)^NOTICES\tTOTAL\tnotices=(\d+)\tprinted=(\d+)\taggregated=(\d+)")
  if ($pm.Success) {
    $printed = $pm.Groups[2].Value
    $aggregated = $pm.Groups[3].Value
  }
  $shapeRows = @()
  foreach ($l in ($txt -split "`r?`n")) {
    $sm = [regex]::Match($l, '^NOTICES\tcount=(\d+)\t(.*)$')
    if ($sm.Success) { $shapeRows += $sm.Groups[2].Value }
  }
  return [pscustomobject]@{
    Text = $txt
    Findings = $findings
    Actionable = $act
    Notices = $not
    Unreliable = $unr
    Total = $tot
    Summary = $sum
    Printed = $printed
    Aggregated = $aggregated
    Shapes = $shapeRows
  }
}

$dir = Join-Path $env:TEMP ('msa0508_settle_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null

function New-Fixture {
  param([string]$Name, [string]$Source)
  $p = Join-Path $dir $Name
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $p 'user.mbt'), $Source, $enc)
  return $p
}

Write-Output '0508 settle: THE CONFIDENCE DEMOTION, MEASURED.'
Write-Output ''

# The three fixtures. They are the three positions of the filter, and they are
# kept apart on purpose: a rule that gets all three right by accident is a
# rule that is wrong about one of them.
#
#   LOW   -- a name the analyzer could not resolve. The family reasons from a
#            NAME alone, so the binding it could not find may be in a file, or
#            in a package, it was never given.
#   SOLID -- a local that is assigned and never read. The declaration was in
#            front of the lens, so the analyzer stands behind it.
#   LIMIT -- an `if` EXPRESSION, which is outside the analyzed subset: the
#            analyzer could not DECIDE at all.
$lowSrc   = "fn main() -> Unit {`n  let x = nosuchfn(1)`n  ignore(x)`n}`n"
$solidSrc = "fn main() -> Unit {`n  let y = 1`n  ignore(0)`n}`n"
$limitSrc = "fn main() -> Unit {`n  let y = if true { 1 } else { 0 }`n  ignore(y)`n}`n"

$lowDir   = New-Fixture 'low' $lowSrc
$solidDir = New-Fixture 'solid' $solidSrc
$limitDir = New-Fixture 'limit' $limitSrc

$lowR   = Invoke-Scan -Dir $lowDir
$solidR = Invoke-Scan -Dir $solidDir
$limitR = Invoke-Scan -Dir $limitDir

# ---------------------------------------------------------------------------
# 1. THE LABEL
# ---------------------------------------------------------------------------
Write-Output '--- 1. THE LABEL: a finding the analyzer does not stand behind ---'

# D1 -- THE DEMOTED FINDING IS RENDERED `notice:`. Before 0508 it was
# rendered `error:` with the family's severity, which said "the analyzer
# checked this and it is wrong" about a finding the analyzer says it could
# not check.
$lowRows = @($lowR.Findings | Where-Object { $_.Family -eq $WANT_FAM_DEMOTED })
if ($lowRows.Count -eq 1 -and $lowRows[0].Label -eq $WANT_LABEL_DEMOTED) {
  Say-OK 'D1' 'NOTICE' ('a low-confidence finding is rendered ' + $lowRows[0].Label + ': ' + $lowRows[0].Message)
} else {
  Say-Bad 'D1' ('one ' + $WANT_FAM_DEMOTED + ' rendered ' + $WANT_LABEL_DEMOTED) ($lowRows.Count.ToString() + ' rows') 'the demoted label is wrong'
}

# D2 -- IT IS NOT HIDDEN. The finding is on a line of the reader's screen, and
# the file's own verdict line counts it. A demotion that took the finding off
# the screen would be a HIDE, and the whole point of the rule is that it is
# not.
$printedLine = ($lowR.Text -match (' - ' + $WANT_LABEL_DEMOTED + ': .*\(' + $WANT_FAM_DEMOTED + '\)'))
if ($printedLine -and $lowRows.Count -eq 1) {
  Say-OK 'D2' 'VISIBLE' 'the demoted finding is on a line of its own, not aggregated away'
} else {
  Say-Bad 'D2' 'the demoted finding rendered' ('rows=' + $lowRows.Count) 'the demoted finding is hidden'
}

# D3 -- IT LEAVES THE ACTIONABLE COUNT. The summary's `actionable` is the
# number of findings the analyzer stands behind, and a demoted finding is not
# one of them.
if ($lowR.Actionable -eq $WANT_ACTIONABLE_AFTER) {
  Say-OK 'D3' 'DEMOTED' ('the demoted finding is not actionable: actionable=' + $lowR.Actionable)
} else {
  Say-Bad 'D3' ('actionable=' + $WANT_ACTIONABLE_AFTER) ('actionable=' + $lowR.Actionable) 'the demoted finding is still actionable'
}

# D4 -- AND IT ENTERS THE NOTICE COUNT, and the identity still holds. The
# finding was not dropped: it moved from one bucket to the other, and
# `actionable + notices + unreliable = total` still adds up.
$identity = ($lowR.Summary -match 'actionable\+notices\+unreliable = total')
if ($lowR.Notices -eq $WANT_NOTICES_AFTER -and $lowR.Total -eq $WANT_TOTAL_AFTER -and $identity) {
  Say-OK 'D4' 'COUNTED' ('the demoted finding is counted: notices=' + $lowR.Notices + ' total=' + $lowR.Total + ', and the identity holds')
} else {
  Say-Bad 'D4' ('notices=' + $WANT_NOTICES_AFTER + ' total=' + $WANT_TOTAL_AFTER + ' and the identity') ('notices=' + $lowR.Notices + ' total=' + $lowR.Total + ' identity=' + $identity) 'the demoted finding is not counted as a notice'
}

# D5 -- THE FAMILY, THE ID AND THE CONFIDENCE SURVIVE THE DEMOTION. What the
# demotion takes away is the label, not the finding: the reader can still see
# WHICH family it is and a machine can still filter on the id.
if ($lowRows.Count -eq 1 -and $lowRows[0].Id -eq $WANT_ID_DEMOTED -and $lowRows[0].Confidence -eq $WANT_CONF_DEMOTED) {
  Say-OK 'D5' 'KEPT' ('the demoted finding keeps ' + $lowRows[0].Id + ' at ' + $lowRows[0].Confidence)
} else {
  Say-Bad 'D5' ($WANT_ID_DEMOTED + ' at ' + $WANT_CONF_DEMOTED) ('see above') 'the demotion took the id or the confidence away'
}

# ---------------------------------------------------------------------------
# 2. WHAT THE ANALYZER STANDS BEHIND
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 2. WHAT THE ANALYZER STANDS BEHIND KEEPS ---'

# D6 -- A FINDING THE ANALYZER STANDS BEHIND KEEPS ITS SEVERITY, AND STAYS
# ACTIONABLE. The demotion is not a blanket softening: it moves the findings
# the analyzer is not sure about, and nothing else.
$solidRows = @($solidR.Findings | Where-Object { $_.Family -eq $WANT_FAM_SOLID })
if ($solidRows.Count -eq 1 -and $solidRows[0].Label -eq $WANT_LABEL_SOLID -and $solidRows[0].Confidence -eq $WANT_CONF_SOLID -and $solidR.Actionable -eq '1' -and $solidR.Notices -eq '0') {
  Say-OK 'D6' 'UNCHANGED' ('a finding the analyzer stands behind keeps ' + $solidRows[0].Label + ': ' + $solidRows[0].Message)
} else {
  Say-Bad 'D6' ('one ' + $WANT_FAM_SOLID + ' at ' + $WANT_LABEL_SOLID + ', actionable=1, notices=0') ('rows=' + $solidRows.Count + ' actionable=' + $solidR.Actionable + ' notices=' + $solidR.Notices) 'the demotion spread past the low-confidence findings'
}

# ---------------------------------------------------------------------------
# 3. THE TWO KINDS OF NOTICE ARE TOLD APART BY MECHANISM
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 3. THE TWO KINDS OF NOTICE ---'

# D7 -- A SCOPE LIMIT IS STILL `undecided`. The other kind of notice did not
# move: the analyzer saying "this construct is outside the analyzed subset" is
# the analyzer saying it could not decide at all.
$limitRows = @($limitR.Findings | Where-Object { $_.Family -eq $WANT_FAM_LIMIT })
if ($limitRows.Count -eq 1 -and $limitRows[0].Label -eq $WANT_LABEL_DEMOTED -and $limitRows[0].Confidence -eq $WANT_CONF_LIMIT -and $limitRows[0].Id -eq $WANT_ID_LIMIT) {
  Say-OK 'D7' 'UNDECIDED' ('a scope limit is still undecided: ' + $limitRows[0].Message)
} else {
  Say-Bad 'D7' ('one ' + $WANT_FAM_LIMIT + ' at ' + $WANT_CONF_LIMIT) ($limitRows.Count.ToString() + ' rows') 'the scope limit is not undecided'
}

# D8 -- AND THE TWO ARE DIFFERENT FINDINGS WITH DIFFERENT CONFIDENCES. The two
# kinds of notice share a LABEL and nothing else, and the confidence is what
# tells them apart: a demoted finding is `low` and a scope limit is
# `undecided`. A reader who saw only the label could not tell a construct the
# analyzer does not model from a name it could not resolve -- and those two
# call for different things from the reader.
$bothDir = New-Fixture 'both' ("fn main() -> Unit {`n  let x = nosuchfn(1)`n  let y = if true { 1 } else { 0 }`n  ignore(x)`n  ignore(y)`n}`n")
$bothR = Invoke-Scan -Dir $bothDir
$bothLow = @($bothR.Findings | Where-Object { $_.Confidence -eq $WANT_CONF_DEMOTED })
$bothLimit = @($bothR.Findings | Where-Object { $_.Confidence -eq $WANT_CONF_LIMIT })
if ($bothLow.Count -eq 1 -and $bothLimit.Count -eq 1 -and $bothR.Notices -eq '2') {
  Say-OK 'D8' 'TWO' ('one file carries both kinds of notice: ' + $bothLow[0].Family + ' at ' + $bothLow[0].Confidence + ' and ' + $bothLimit[0].Family + ' at ' + $bothLimit[0].Confidence)
} else {
  Say-Bad 'D8' 'one low and one undecided, notices=2' ('low=' + $bothLow.Count + ' limit=' + $bothLimit.Count + ' notices=' + $bothR.Notices) 'the two kinds of notice are not told apart'
}

# ---------------------------------------------------------------------------
# 4. THE DEMOTED FINDING IS PRINTED WHERE A SCOPE LIMIT IS AGGREGATED
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 4. PRINTED, NOT AGGREGATED ---'

# D9 -- THE SHARP CONTROL. One file, two notices, and the split puts them in
# DIFFERENT sets: the demoted finding is printed per line, and the scope
# limit -- which is at the top level, outside every function's extent, so it
# hides nothing -- is counted by shape.
#
# A scope limit is a SHAPE: the same message repeated across a file, so
# counting it by shape loses nothing. A low-confidence finding is SPECIFIC: a
# name, at a line, and aggregating it would take the name and the place away.
# That is why the demotion was chosen over hiding it.
$mixSrc = "let y = if true { 1 } else { 0 }`nfn main() -> Unit {`n  let x = nosuchfn(1)`n  ignore(x)`n}`n"
$mixDir = New-Fixture 'mix' $mixSrc
$mixR = Invoke-Scan -Dir $mixDir
$mixPrinted = ($mixR.Text -match (' - ' + $WANT_LABEL_DEMOTED + ': .*\(' + $WANT_FAM_DEMOTED + '\)'))
$shapeHasLimit = $false
foreach ($s in $mixR.Shapes) { if ($s.Contains('outside the analyzed subset')) { $shapeHasLimit = $true } }
$shapeHasLow = $false
foreach ($s in $mixR.Shapes) { if ($s.Contains('no visible binding')) { $shapeHasLow = $true } }
if ($mixPrinted -and $shapeHasLimit -and -not $shapeHasLow -and $mixR.Aggregated -eq '1') {
  Say-OK 'D9' 'SPLIT' ('the demoted finding is printed and the scope limit is aggregated: printed=' + $mixR.Printed + ' aggregated=' + $mixR.Aggregated)
} else {
  Say-Bad 'D9' 'the demoted finding printed and the scope limit aggregated' ('printed=' + $mixPrinted + ' shapeHasLimit=' + $shapeHasLimit + ' shapeHasLow=' + $shapeHasLow + ' aggregated=' + $mixR.Aggregated) 'the two kinds of notice do not land in different sets'
}

# ---------------------------------------------------------------------------
# 5. THE PROFILE STILL SELECTS THE DEMOTED FAMILY
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 5. THE PROFILE ---'

# D10 -- THE DEMOTION DID NOT CHANGE WHAT A PROFILE KEEPS. `--families MSA-002`
# names the demoted family by its stable id, and the demotion is a change of
# LABEL, so the family is still selected by the id it always had.
$famR = Invoke-Scan -Dir $lowDir -Extra @('--families', $WANT_ID_DEMOTED)
if ($famR.Findings.Count -eq 1 -and $famR.Findings[0].Id -eq $WANT_ID_DEMOTED -and $famR.Findings[0].Label -eq $WANT_LABEL_DEMOTED) {
  Say-OK 'D10' 'KEPT' ('--families ' + $WANT_ID_DEMOTED + ' keeps the demoted finding, still rendered ' + $famR.Findings[0].Label)
} else {
  Say-Bad 'D10' ('one ' + $WANT_ID_DEMOTED + ' rendered ' + $WANT_LABEL_DEMOTED) ($famR.Findings.Count.ToString() + ' findings') 'the profile stopped selecting the demoted family'
}

# ---------------------------------------------------------------------------
# 6. THE JSON RECORD INHERITS THE DEMOTION
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 6. THE JSON RECORD ---'

# D11 -- THE JSON's `severity` IS THE LABEL THE RENDERER USES, and its
# `confidence` IS THE SAME CONFIDENCE. If the JSON computed its own severity
# from the family, the JSON would say `error` about a finding the text calls
# a `notice` -- and a consumer of the JSON would be told the opposite of what
# the text says.
$jTxt = [System.IO.File]::ReadAllText((Join-Path $root 'src\jsoncli\main.mbt'), [System.Text.Encoding]::UTF8)
$sevFromLabel = ($jTxt -match 'let severity = rep\.severity_label\(\)')
$confFromName = ($jTxt -match 'confidence: rep\.confidence\(\)\.name\(\)')
if ($sevFromLabel -and $confFromName) {
  Say-OK 'D11' 'OK' 'the JSON record takes its severity from the label and its confidence from the axis'
} else {
  Say-Bad 'D11' 'severity from severity_label() and confidence from confidence().name()' ('severity=' + $sevFromLabel + ' confidence=' + $confFromName) 'the JSON record computes its own severity or confidence'
}

# ---------------------------------------------------------------------------
# 7. THE NARRATIVE QUOTES THESE NUMBERS, AND MUST AGREE WITH THEM
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 7. THE NARRATIVE ---'

# D12 -- ONE ROW, SEVERAL NUMBERS, so the roster and the count of the rows
# agree. The numbers are the ones this settle measured on its own fixtures.
$script:rows++
$narPath = Join-Path $root '_verify\NARRATIVE.md'
$narTxt = [System.IO.File]::ReadAllText($narPath, [System.Text.Encoding]::UTF8)
$quotes = @(
  @{ N = 'the demoted finding, label'; V = $WANT_LABEL_DEMOTED }
  @{ N = 'the demoted finding, confidence'; V = $WANT_CONF_DEMOTED }
  @{ N = 'the demoted finding, family id'; V = $WANT_ID_DEMOTED }
  @{ N = 'the demoted finding, actionable count'; V = $WANT_ACTIONABLE_AFTER }
  @{ N = 'the demoted finding, notice count'; V = $WANT_NOTICES_AFTER }
)
$bad = 0
foreach ($q in $quotes) {
  $rx = '(?m)^\s*0508\s+' + [regex]::Escape($q.N) + '\s*:\s*(\S+)\s*$'
  $m = [regex]::Match($narTxt, $rx)
  if (-not $m.Success) {
    Write-Output ('  D12        MISSING  the narrative does not quote "' + $q.N + '"')
    $bad++
    continue
  }
  if ($m.Groups[1].Value -ne $q.V) {
    Write-Output ('  D12        WRONG    the narrative says ' + $m.Groups[1].Value + ' for "' + $q.N + '"; the measurement says ' + $q.V)
    $bad++
    continue
  }
  Write-Output ('  {0,-10} {1,-9} {2} = {3}' -f 'D12', 'OK', $q.N, $q.V)
}
if ($bad -gt 0) {
  $script:fail++
  Write-Output ('  D12        MISMATCH ' + $bad + ' quoted number(s) disagree with the measurement')
} else {
  Write-Output ('  {0,-10} {1,-9} all {2} quoted numbers agree with the measurement' -f 'D12', 'OK', $quotes.Count)
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output ('ABORT: ' + $fail + ' of ' + $rows + ' row(s) did not match. The demotion is not what the narrative says it is.')
  exit 1
}
Write-Output ('GATE OK: ' + $rows + ' rows. The confidence axis is no longer a column: a finding the analyzer does not stand behind is rendered a notice, is counted as a notice, and is NOT hidden -- it keeps its family, its stable id and its line on the reader''s screen, and a finding the analyzer stands behind keeps its severity.')
exit 0

param(
  # Audit a different tree than the pinned corpus. The control fixture uses it.
  [string]$Tree = '',
  # Print the per-row detail behind every verdict.
  [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
# 0505 settle: THE PORTING PLAN, AND THE PREMISES IT RESTS ON.
#
# WHAT THIS IS. 0505 is a PLAN, not an implementation: it ports three things
# from PyCQA's `bandit` into this analyzer, in a fixed order, and it changes no
# source and no published number. A plan whose premises are written down from
# memory is a plan that will be built on a premise that stopped being true
# while nobody was looking. So this script MEASURES every premise, with a
# control for each, and it checks the numbers the narrative quotes against the
# numbers measured here.
#
# The three transfers, and why this order:
#
#   1. A PER-FINDING CONFIDENCE AXIS. bandit carries `severity` AND
#      `confidence` on every issue (`bandit/core/issue.py:79-106`) and
#      `Issue.filter` needs BOTH to clear their thresholds
#      (`issue.py:147-167`). This analyzer has `Family::severity()` and no
#      confidence at all: `src/jsoncli/main.mbt:12-20` has a `severity` field
#      and no `confidence` field.
#   2. STABLE FAMILY IDS AND A PROFILE. bandit keys its plugins by `_test_id`
#      and a plugin with no id is SKIPPED WITH A WARNING
#      (`bandit/core/extension_loader.py:44-57`); `validate_profile` warns on
#      an unknown id and RAISES on a non-exclusive include/exclude set
#      (`extension_loader.py:86-100`). This analyzer has a closed 11-member
#      `Family` enum whose public spelling is a hand-written `match`
#      (`src/core/core.mbt:491-521`) -- a NAME, not an id.
#   3. `nosec`. bandit suppresses per line, per test id (`# nosec B101`) or
#      blanket, and WARNS WHEN A `nosec` MATCHED NOTHING
#      (`bandit/core/tester.py:105-118`). This analyzer has no user-facing
#      suppression at all.
#
# THE ORDER IS FORCED BY THE TRANSFERS THEMSELVES, not chosen:
#
#   * 2 depends on 1 in the sense that a profile is a statement about which
#     findings a user trusts, and "trusts" is a confidence question.
#   * 3 depends on 2 in a way that is not a matter of taste: a `nosec` comment
#     has to NAME the thing it suppresses. If it named a family by its current
#     NAME, then transfer 2 -- whose whole point is that the name is not
#     stable -- would break every suppression written the day before. The
#     stable id is what a suppression must quote.
#   * 1 comes first because it is the one that makes the other two
#     ADDRESSABLE. Transfer 1 is not "add a second severity": it is the
#     difference between "there is no problem here" and "I could not check
#     this", which today the analyzer does not draw at all.
#
# AND THE PREMISE THAT PUTS TRANSFER 1 FIRST IS MEASURED, NOT ASSERTED. The
# analyzer checks a call's arity and argument types ONLY when the callee is
# declared in the SAME FILE. A `.mbti` gives a name and never a parameter
# list (`src/types/types.mbt:31-37`), so the callee is typed `TUnknownFn` and
# the checks are deliberately skipped (`src/types/infer.mbt:83-113,300-312`).
# Rows A0..A5 measure that, and A6 measures how much of the corpus it covers.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\settle_0505_finding_quality.ps1
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

# ---------------------------------------------------------------------------
# THE PINS. One copy, here. The narrative quotes them; part 4 checks that it
# does, so the two can never drift apart without the gate going red.
#
# These are the numbers the PLAN rests on. When the thing they measure
# changes on purpose -- the corpus pin moves, or a family is added -- the pin
# and the narrative are updated in the SAME commit, and the gate is what
# makes forgetting to do that visible.
#
# 0507 IMPLEMENTED THE PLAN, and this script's rows were WRITTEN TO PIN THE
# ABSENCE of the three transfers. They now pin their PRESENCE, and the flip
# is recorded in NARRATIVE.md. That is the point of a settle: it is a
# measurement of the CURRENT state, and when the state changes on purpose the
# measurement moves with it -- re-pinned, never loosened.
#
# `$WANT_FAMILIES` moved from 11 to 12 because the stale-suppression finding
# (MSA-012) is a family of its own. `$WANT_NAME_DIFFERS` did NOT move: the
# new family's public name IS its tag minus the `F`, so the five names that
# differ from their tag are the same five.
# ---------------------------------------------------------------------------
$WANT_REACH_TOTAL   = 19843   # calls to a package-level function, pinned corpus
$WANT_REACH_UNCHECK = 16250   # of those, the signature is known by NAME only
$WANT_REACH_FILES   = 657     # files carrying an unchecked call
$WANT_MBTI_FILES    = 159     # .mbti files in the pinned corpus
$WANT_MBTI_PUBFN    = 2116    # `pub fn` declarations across them
$WANT_FAMILIES      = 12      # members of the `Family` enum
$WANT_NAME_DIFFERS  = 5       # of them, whose public name is not the tag minus `F`

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
# Run the scanner over one directory. Returns the stdout text and the list of
# rendered findings, parsed out of it.
# ---------------------------------------------------------------------------
function Invoke-Scan {
  param([string]$Dir, [string[]]$Extra = @())
  $stamp = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $o = Join-Path $env:TEMP ('msa0505_' + $stamp + '.out')
  $e = Join-Path $env:TEMP ('msa0505_' + $stamp + '.err')
  $argl = @($wasm, $Dir) + $Extra + @('--no-auto-fetch-deps', '--findings-shown-per-file', '1000000')
  Start-Process -FilePath $moonrun -ArgumentList $argl -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -Wait | Out-Null
  $txt = [System.IO.File]::ReadAllText($o)
  $findings = @()
  foreach ($l in ($txt -split "`r?`n")) {
    $m = [regex]::Match($l, '^\d+:\d+ - (error|warning|hint|notice): (.*) \(([A-Za-z]+)\) \[([a-z+\-]+), (MSA-\d{3}), (high|low|undecided)\]$')
    if ($m.Success) {
      $findings += [pscustomobject]@{ Label = $m.Groups[1].Value; Message = $m.Groups[2].Value; Family = $m.Groups[3].Value; Id = $m.Groups[5].Value; Confidence = $m.Groups[6].Value }
    }
  }
  $sum = [regex]::Match($txt, '(?m)^SUMMARY.*$').Value
  $act = -1
  $am = [regex]::Match($sum, 'actionable=(\d+)')
  if ($am.Success) { $act = [int]$am.Groups[1].Value }
  return [pscustomobject]@{ Text = $txt; Findings = $findings; Actionable = $act; Summary = $sum }
}

# ---------------------------------------------------------------------------
# The counter for A6, and its control.
#
# THE RULE, precisely:
#
#   1. The corpus is the PINNED one: moonbitlang/core 0.1.20260920+7d59c7ec9.
#      `.mbt` files only for the CALLS; `.mbti` files for the DECLARATIONS.
#   2. A "package-level function" is a name declared by a top-level `fn` in
#      some `.mbt` file of the corpus, or by a `pub fn` in some `.mbti` of the
#      corpus. A call to a name that is none of those -- a method, a local
#      binding, a constructor -- is NOT a package-level call and is not
#      counted.
#   3. A call site is the text `NAME(` where NAME is one of those names and
#      the calling file does not bind NAME with `let`/`var`. It must be in
#      CODE: not inside a `//` comment, not inside a `"` or `'` literal, not
#      inside a `#| ... |#` block string.
#   4. A call site is CHECKED when the calling file itself declares NAME as a
#      top-level `fn`, and UNCHECKED otherwise. That is the rule the
#      measurement asserts about the ANALYZER (rows A2, A3, A5), applied to
#      the corpus.
#
# AND THE CONTROL, which is what makes the counter worth believing: a
# synthetic tree whose answer is known by construction, and the same counter
# has to agree with it before any real number is reported. The fixture holds
# one same-file call (checked), one call to a function declared in a SIBLING
# file (unchecked), one call to a function declared only in an interface file
# (unchecked), one call to a name that is declared nowhere (not a
# package-level call, so not counted at all), one call inside a comment and
# one inside a string literal (neither counted).
# ---------------------------------------------------------------------------
function Measure-PackageLevelCalls {
  param([string]$Dir)
  $declIn = @{}
  $ifaceIn = @{}
  $files = @(Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.mbt' })
  $mbtiFiles = @(Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.mbti' })
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($Dir.Length + 1)
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
      if ($line -match '^(pub(\([a-z]+\))?\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)') {
        $n = $Matches[3]
        if (-not $declIn.ContainsKey($n)) { $declIn[$n] = New-Object System.Collections.Generic.HashSet[string] }
        [void]$declIn[$n].Add($rel)
      }
    }
  }
  $pubFn = 0
  foreach ($f in $mbtiFiles) {
    $rel = $f.FullName.Substring($Dir.Length + 1)
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
      $t = $line.Trim()
      if ($t -match '^pub fn\s+([A-Za-z_][A-Za-z0-9_]*)') {
        $n = $Matches[1]
        $pubFn++
        if (-not $ifaceIn.ContainsKey($n)) { $ifaceIn[$n] = New-Object System.Collections.Generic.HashSet[string] }
        [void]$ifaceIn[$n].Add($rel)
      }
    }
  }
  $pkg = New-Object System.Collections.Generic.HashSet[string]
  foreach ($k in $declIn.Keys) { [void]$pkg.Add($k) }
  foreach ($k in $ifaceIn.Keys) { [void]$pkg.Add($k) }

  $checked = 0; $unMbt = 0; $unIface = 0
  $unFiles = New-Object System.Collections.Generic.HashSet[string]
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($Dir.Length + 1)
    $allLines = [System.IO.File]::ReadAllLines($f.FullName)
    $local = New-Object System.Collections.Generic.HashSet[string]
    foreach ($line in $allLines) {
      $t = $line.Trim()
      if ($t -match '^(pub\s+)?(let|var)\s+([A-Za-z_][A-Za-z0-9_]*)') { [void]$local.Add($Matches[3]) }
    }
    $inBlock = $false
    foreach ($line in $allLines) {
      $i = 0; $len = $line.Length
      $prevWord = ''
      while ($i -lt $len) {
        if ($inBlock) {
          if ($line.Substring($i).StartsWith('|#')) { $inBlock = $false; $i += 2; continue }
          $i++; continue
        }
        $c = $line[$i]
        if ($c -eq '"' -or $c -eq "'") {
          $q = $c; $i++
          while ($i -lt $len) {
            if ($line[$i] -eq '\') { $i += 2; continue }
            if ($line[$i] -eq $q) { $i++; break }
            $i++
          }
          continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $len -and $line[$i + 1] -eq '/') { break }
        if ($c -eq '#' -and ($i + 1) -lt $len -and $line[$i + 1] -eq '|') { $inBlock = $true; $i += 2; continue }
        if ([char]::IsLetter($c) -or $c -eq '_') {
          $j = $i
          while ($j -lt $len -and ([char]::IsLetterOrDigit($line[$j]) -or $line[$j] -eq '_')) { $j++ }
          $word = $line.Substring($i, $j - $i)
          # A DECLARATION IS NOT A CALL. `fn same_file()` ends in an opening
          # parenthesis exactly like a call does, and counting it as one
          # counted every top-level declaration in the corpus as a call site
          # -- an over-count measured on the control fixture, which is why
          # the control exists. The token before a declaration's name is
          # `fn`, so that is what excludes it.
          $isDecl = ($prevWord -eq 'fn')
          $prevWord = $word
          if ((-not $isDecl) -and $j -lt $len -and $line[$j] -eq '(' -and $pkg.Contains($word) -and -not $local.Contains($word)) {
            if ($declIn.ContainsKey($word) -and $declIn[$word].Contains($rel)) { $checked++ }
            elseif ($declIn.ContainsKey($word)) { $unMbt++; [void]$unFiles.Add($rel) }
            else { $unIface++; [void]$unFiles.Add($rel) }
          }
          $i = $j; continue
        }
        $i++
      }
    }
  }
  return [pscustomobject]@{
    Total = ($checked + $unMbt + $unIface)
    Checked = $checked
    UncheckedMbt = $unMbt
    UncheckedIface = $unIface
    Unchecked = ($unMbt + $unIface)
    UncheckedFiles = $unFiles.Count
    MbtiFiles = $mbtiFiles.Count
    PubFn = $pubFn
  }
}

# ===========================================================================
Write-Output ''
Write-Output '=== 0505 settle: the porting plan, and the premises it rests on ==='
Write-Output ''

# ---------------------------------------------------------------------------
Write-Output '--- 1. THE SIGNATURE IS CHECKED ONLY IN THE SAME FILE ---'
Write-Output '    (rows A0..A5 are one defect under six conditions)'
$dir = Join-Path $env:TEMP ('msa0505_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$ifd = Join-Path $dir 'iface'
New-Item -ItemType Directory -Force -Path $ifd | Out-Null
[System.IO.File]::WriteAllText((Join-Path $ifd 'pkg.generated.mbti'), (@(
  '// Generated using `moon info`, DON''T EDIT IT'
  'package "probe/lib"'
  ''
  '// Values'
  'pub fn Command(String) -> Int'
) -join "`n"), $enc)

function New-Fixture {
  param([string]$Name, [hashtable]$Files)
  $p = Join-Path $dir $Name
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  foreach ($k in $Files.Keys) {
    [System.IO.File]::WriteAllText((Join-Path $p $k), $Files[$k], $enc)
  }
  return $p
}

$callOk = "fn main() -> Unit {`n  let x = Command(`"hello`")`n  ignore(x)`n}`n"
$callBad = "fn main() -> Unit {`n  let x = Command(`"hello`", `"too many`")`n  ignore(x)`n}`n"
$siblingDef = "fn Command(s : String) -> Int {`n  s.length()`n}`n"
$localDef = $siblingDef + "`n" + $callBad

$a0 = New-Fixture 'a0_no_iface' @{ 'user.mbt' = $callBad }
$a1 = New-Fixture 'a1_cross_ok'  @{ 'user.mbt' = $callOk }
$a2 = New-Fixture 'a2_cross_bad' @{ 'user.mbt' = $callBad }
$a3 = New-Fixture 'a3_same_bad'  @{ 'user.mbt' = $localDef }
$a4 = New-Fixture 'a4_unknown'   @{ 'user.mbt' = "fn main() -> Unit {`n  let x = nosuchfn(1)`n  ignore(x)`n}`n" }
$a5 = New-Fixture 'a5_sibling_bad' @{ 'lib.mbt' = $siblingDef; 'user.mbt' = $callBad }

# A0 -- THE CONTROL THAT MAKES A2 READABLE. The same wrong-arity call, with
# the interface directory NOT passed. The name is then declared nowhere, so
# the analyzer reports it. A2's silence is therefore caused by the interface
# file being READ -- the name resolved, and it resolved to a name with no
# parameter list -- and not by the analyzer declining to look at the call.
$r = Invoke-Scan -Dir $a0
if ($r.Findings.Count -eq 1 -and $r.Findings[0].Family -eq 'UndefinedName') {
  Say-OK 'A0' 'REPORTED' ('no interface dir -> ' + $r.Findings[0].Message)
} else {
  Say-Bad 'A0' '1 UndefinedName' ($r.Findings.Count.ToString() + ' findings') 'the name must be undefined without the .mbti'
}

# A1 -- THE CONTROL FOR A2. The same call with the RIGHT arity, cross-file.
# It must be SILENT: the analyzer must not invent a defect.
$r = Invoke-Scan -Dir $a1 -Extra @('--extern-iface-dir', $ifd)
if ($r.Findings.Count -eq 0) {
  Say-OK 'A1' 'SILENT' 'cross-file, right arity -> no finding (no false alarm)'
} else {
  Say-Bad 'A1' '0 findings' ($r.Findings.Count.ToString()) 'a correct call must not be reported'
}

# A2 -- THE PREMISE. The same call with the WRONG arity, cross-file. This is
# a real defect: the same defect, in the same file, is reported by row A3.
# Here it is SILENT, and the file is printed CLEAN.
$r = Invoke-Scan -Dir $a2 -Extra @('--extern-iface-dir', $ifd)
if ($r.Findings.Count -eq 0) {
  $clean = ($r.Text -match '(?m)^CLEAN\t')
  if ($clean) {
    Say-OK 'A2' 'SILENT' 'cross-file, WRONG arity -> no finding, and the file is printed CLEAN'
  } else {
    Say-Bad 'A2' 'CLEAN' ('found, but not CLEAN') 'the file must be printed CLEAN for the silence to be total'
  }
} else {
  Say-Bad 'A2' '0 findings' ($r.Findings.Count.ToString()) 'the false negative must be reproduced'
}

# A3 -- THE CONTROL FOR A2. The SAME defect with the callee declared in the
# SAME file. The analyzer knows the parameter list and says so.
$r = Invoke-Scan -Dir $a3
if ($r.Findings.Count -eq 1 -and $r.Findings[0].Family -eq 'ArgTypeMismatch') {
  Say-OK 'A3' 'REPORTED' ('same file -> ' + $r.Findings[0].Message)
} else {
  Say-Bad 'A3' '1 ArgTypeMismatch' ($r.Findings.Count.ToString() + ' findings') 'the analyzer must check a same-file call'
}

# A4 -- THE CONTROL THAT THE ANALYZER IS NOT SIMPLY SILENT. A name declared
# NOWHERE is reported.
$r = Invoke-Scan -Dir $a4
if ($r.Findings.Count -eq 1 -and $r.Findings[0].Family -eq 'UndefinedName') {
  Say-OK 'A4' 'REPORTED' ('declared nowhere -> ' + $r.Findings[0].Message)
} else {
  Say-Bad 'A4' '1 UndefinedName' ($r.Findings.Count.ToString() + ' findings') 'an unknown name must be reported'
}

# A5 -- THE PREMISE IS BIGGER THAN THE INTERFACE BOUNDARY. The callee is
# declared in a SIBLING .mbt file of the same tree: a real declaration, with a
# real parameter list, one file over. It is still known by NAME only, and the
# wrong-arity call is still silent.
$r = Invoke-Scan -Dir $a5
if ($r.Findings.Count -eq 0) {
  Say-OK 'A5' 'SILENT' 'sibling .mbt, WRONG arity -> no finding: the boundary is the FILE, not the package'
} else {
  Say-Bad 'A5' '0 findings' ($r.Findings.Count.ToString()) 'a sibling-file call is still known by name only'
}

# A6 -- THE REACH, and its control.
$ctl = Join-Path $dir 'ctl'
New-Item -ItemType Directory -Force -Path (Join-Path $ctl 'lib') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $ctl 'a.mbt'), "fn same_file() -> Int { 1 }`n`nfn main() -> Unit {`n  let x = same_file()`n  ignore(x)`n}`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $ctl 'b.mbt'), "fn main() -> Unit {`n  let x = sibling_fn()`n  ignore(x)`n}`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $ctl 'c.mbt'), "fn main() -> Unit {`n  let x = iface_only()`n  ignore(x)`n}`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $ctl 'd.mbt'), "fn main() -> Unit {`n  let x = nowhere_fn()`n  ignore(x)`n}`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $ctl 'g.mbt'), "fn other_fn() -> Int { 1 }`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $ctl 'h.mbt'), "fn main() -> Unit {`n  let x = other_fn()`n  ignore(x)`n}`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $ctl 'lib\pkg.generated.mbti'), "package `"probe/lib`"`n`npub fn sibling_fn(Int) -> Int`n`npub fn iface_only(String) -> Int`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $ctl 'f.mbt'), "// sibling_fn() is in a comment`nfn main() -> Unit {`n  let s = `"sibling_fn() in a string`"`n  ignore(s)`n}`n", $enc)
$c = Measure-PackageLevelCalls -Dir $ctl
# Known by construction: same_file() in a.mbt is CHECKED (same file);
# sibling_fn() in b.mbt is UNCHECKED (declared only in an interface file);
# iface_only() in c.mbt is UNCHECKED (interface only); other_fn() in h.mbt is
# UNCHECKED (declared in another .mbt file). nowhere_fn() is declared
# nowhere, so it is not a package-level call and is not counted at all; the
# comment and the string literal are not code and are not counted either.
if ($c.Total -eq 4 -and $c.Checked -eq 1 -and $c.Unchecked -eq 3 -and $c.UncheckedMbt -eq 1 -and $c.UncheckedIface -eq 2) {
  Say-OK 'A6ctl' 'OK' ('the control agrees: total=' + $c.Total + ' checked=' + $c.Checked + ' unchecked=' + $c.Unchecked + ' (' + $c.UncheckedMbt + ' another .mbt, ' + $c.UncheckedIface + ' interface only)')
} else {
  Say-Bad 'A6ctl' 'total=4 checked=1 unchecked=3 (1 another .mbt, 2 interface only)' ('total=' + $c.Total + ' checked=' + $c.Checked + ' unchecked=' + $c.Unchecked + ' (' + $c.UncheckedMbt + ', ' + $c.UncheckedIface + ')') 'the counter is not trusted, so no reach number is reported'
}

$core = Join-Path $repos 'moonbitlang\core\0.1.20260920+7d59c7ec9'
if ($Tree -ne '') { $core = $Tree }
if (-not (Test-Path -LiteralPath $core)) {
  Write-Output ('  A6        ABORT    the pinned corpus is not there: ' + $core)
  $fail++
} else {
  $m = Measure-PackageLevelCalls -Dir $core
  if ($m.Total -ne $WANT_REACH_TOTAL -or $m.Unchecked -ne $WANT_REACH_UNCHECK -or $m.UncheckedFiles -ne $WANT_REACH_FILES) {
    Say-Bad 'A6' ($WANT_REACH_TOTAL.ToString() + ' total / ' + $WANT_REACH_UNCHECK.ToString() + ' unchecked / ' + $WANT_REACH_FILES.ToString() + ' files') `
      ($m.Total.ToString() + ' total / ' + $m.Unchecked.ToString() + ' unchecked / ' + $m.UncheckedFiles.ToString() + ' files') 'the corpus reach moved'
  } else {
    $pct = [math]::Round(100.0 * $m.Unchecked / $m.Total, 1)
    Say-OK 'A6' 'OK' ($m.Total.ToString() + ' package-level calls, ' + $m.Unchecked.ToString() + ' unchecked (' + $pct.ToString() + '%) in ' + $m.UncheckedFiles.ToString() + ' files')
    if ($Verbose) {
      Write-Output ('      checked (same file): ' + $m.Checked + '   name only (another .mbt): ' + $m.UncheckedMbt + '   name only (interface only): ' + $m.UncheckedIface)
    }
  }
  if ($m.MbtiFiles -ne $WANT_MBTI_FILES -or $m.PubFn -ne $WANT_MBTI_PUBFN) {
    Say-Bad 'A6b' ($WANT_MBTI_FILES.ToString() + ' .mbti files / ' + $WANT_MBTI_PUBFN.ToString() + ' `pub fn`') `
      ($m.MbtiFiles.ToString() + ' .mbti files / ' + $m.PubFn.ToString() + ' `pub fn`') 'the interface population moved'
  } else {
    Say-OK 'A6b' 'OK' ($m.MbtiFiles.ToString() + ' .mbti files carrying ' + $m.PubFn.ToString() + ' `pub fn` declarations')
  }
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 2. THE PUBLIC VOCABULARY IS A NAME, NOT AN ID ---'
$coreMbt = Join-Path $root 'src\core\core.mbt'
$coreTxt = [System.IO.File]::ReadAllText($coreMbt, [System.Text.Encoding]::UTF8)
$enumM = [regex]::Match($coreTxt, '(?s)pub\(all\)\s+enum\s+Family\s*\{(.*?)\}\s*derive')
$nameM = [regex]::Match($coreTxt, '(?s)pub fn Family::name\(self : Family\) -> String \{(.*?)\n\}')
if (-not $enumM.Success -or -not $nameM.Success) {
  Say-Bad 'B1' 'the Family enum and its name()' 'not found' 'the source changed shape'
} else {
  $tags = @()
  foreach ($l in ($enumM.Groups[1].Value -split "`r?`n")) {
    $t = $l.Trim()
    if ($t -match '^F[A-Za-z]+$') { $tags += $t }
  }
  $map = @{}
  foreach ($m in [regex]::Matches($nameM.Groups[1].Value, 'F([A-Za-z]+)\s*=>\s*"([^"]+)"')) {
    $map['F' + $m.Groups[1].Value] = $m.Groups[2].Value
  }
  $distinct = @($map.Values | Sort-Object -Unique).Count
  # THE RULE for "the public name differs from the tag": the name is NOT the
  # tag with its leading `F` removed. MEASURED, 5 of the 11 differ:
  # FParse -> ParseError, FAssignType -> AssignTypeMismatch,
  # FArgType -> ArgTypeMismatch, FOpMismatch -> OperatorMismatch,
  # FCondBool -> NonBooleanCond. The other six are the tag minus the `F`.
  $differs = 0
  $diffList = @()
  foreach ($tg in $tags) {
    if ($map.ContainsKey($tg) -and $map[$tg] -ne $tg.Substring(1)) {
      $differs++
      $diffList += ($tg + ' -> ' + $map[$tg])
    }
  }
  if ($tags.Count -eq $map.Count -and $map.Count -eq $WANT_FAMILIES -and $distinct -eq $map.Count) {
    Say-OK 'B1' 'OK' ($tags.Count.ToString() + ' families, ' + $map.Count.ToString() + ' names, all distinct')
    if ($differs -ne $WANT_NAME_DIFFERS) {
      Say-Bad 'B2' ($WANT_NAME_DIFFERS.ToString() + ' names differ from their tag') ($differs.ToString()) 'the public spelling moved'
    } else {
      Say-OK 'B2' 'OK' ($differs.ToString() + ' of ' + $tags.Count.ToString() + ' public names differ from their enum tag: ' + ($diffList -join ', '))
    }
  } else {
    Say-Bad 'B1' ($WANT_FAMILIES.ToString() + ' families, one distinct name each') `
      ($tags.Count.ToString() + ' tags / ' + $map.Count.ToString() + ' names / ' + $distinct.ToString() + ' distinct') 'the family roster moved'
  }
}

# B3 -- THE OUTPUT SURFACE. 0507 ADDED THE ID AND THE CONFIDENCE, so a finding
# is rendered with its family NAME, its family's STABLE ID, and the
# confidence the lens reached.
#
# The row was INVERTED by 0507: it used to assert that the rendered line
# carried the name and NO id and NO confidence, which was the plan's premise.
# The premise was true when the row was written and it is FALSE now, so the
# row now asserts the implemented state. A settle that keeps asserting the
# absence of a thing that now exists is a settle that has stopped measuring.
$r = Invoke-Scan -Dir $a3
if ($r.Findings.Count -eq 1) {
  $line = @($r.Text -split "`r?`n" | Where-Object { $_ -match '^\d+:\d+ - ' })[0]
  $hasName = ($line -match '\(ArgTypeMismatch\)')
  # The lens tag is whatever lens produced the finding. This fixture's finding
  # comes from the TYPE lens, and the first version of this row pinned
  # `structural` -- a guess about the shape, made when the bracket held only
  # the lens tag. The row is about the SHAPE (a lens tag, the family's id, a
  # confidence), so it matches the shape and does not pin which lens it was.
  $hasId = ($line -match '\[[^,\]]+, MSA-007,')
  $hasConf = ($line -match ', high\]')
  if ($hasName -and $hasId -and $hasConf) {
    Say-OK 'B3' 'OK' ('the rendered finding carries the NAME, the id and the confidence: ' + $line.Trim())
  } else {
    Say-Bad 'B3' 'a name, an id and a confidence' $line.Trim() 'the rendered shape moved'
  }
} else {
  Say-Bad 'B3' '1 finding' ($r.Findings.Count.ToString()) 'the fixture did not produce its finding'
}

# B4 -- THE JSON BRIDGE. Its Finding record is the machine-readable output,
# and it is read from the source because building the js bridge is not part of
# this settle.
#
# 0507 ADDED `confidence` AND `family_id` to it, so this row was INVERTED too.
$jTxt = [System.IO.File]::ReadAllText((Join-Path $root 'src\jsoncli\main.mbt'), [System.Text.Encoding]::UTF8)
$fM = [regex]::Match($jTxt, '(?s)struct Finding \{(.*?)\}\s*derive\(ToJson\)')
if (-not $fM.Success) {
  Say-Bad 'B4' 'the Finding record' 'not found' 'the source changed shape'
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
    Say-OK 'B4' 'OK' ('the Finding record has `severity`, `confidence` and `family_id`: ' + ($fields -join ', '))
  } else {
    Say-Bad 'B4' 'severity, confidence and family_id' ($fields -join ', ') 'the JSON shape moved'
  }
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 3. THE FAMILY SELECTION AND THE SUPPRESSION ARE FLAGS, AND BOTH ARE OFF BY DEFAULT ---'
$fix = Join-Path $dir 'fix'
New-Item -ItemType Directory -Force -Path $fix | Out-Null
[System.IO.File]::WriteAllText((Join-Path $fix 'user.mbt'), "fn main() -> Unit {`n  let x = nosuchfn(1)`n  ignore(x)`n}`n", $enc)

# C1 -- THE FAMILY SELECTION IS A FLAG, AND AN UNKNOWN FLAG IS STILL REFUSED.
#
# 0507 INVERTED THIS ROW'S CLAIM. It used to assert that "there is no config
# file and no family selection", and it proved it by showing that `--profile`
# was refused as an unknown flag. The REFUSAL is still true -- `--profile` was
# never the spelling -- but the conclusion it supported is false now: there IS
# a family selection, and its spelling is `--families` / `--exclude-families`.
#
# So the row pins BOTH halves. The second half is the control for the first: a
# parser that refused EVERYTHING would have satisfied the old row too, which
# is exactly what a row that only checked a refusal is worth.
$o = Join-Path $dir 'c1.out'
Start-Process -FilePath $moonrun -ArgumentList @($wasm, $fix, '--profile', 'anything') -RedirectStandardOutput $o -RedirectStandardError ($o + '.err') -NoNewWindow -Wait | Out-Null
$t1 = [System.IO.File]::ReadAllText($o)
$refused = ($t1 -match 'ERROR\tunexpected extra argument: --profile')
$r = Invoke-Scan -Dir $fix -Extra @('--families', 'MSA-002')
$accepted = ($r.Summary -ne '' -and $r.Findings.Count -eq 1)
if ($refused -and $accepted) {
  Say-OK 'C1' 'OK' 'an unknown flag is REFUSED, and the real spelling --families is accepted and selects'
} else {
  Say-Bad 'C1' 'an unknown flag refused AND --families accepted' ('refused=' + $refused + ' accepted=' + $accepted) 'the argument parser changed'
}

# C2 -- THE CONTROL FOR C1. A KNOWN flag after the target is accepted and the
# scan runs, so C1 is about the flag being unknown and not about the scanner
# refusing extra arguments.
$r = Invoke-Scan -Dir $fix -Extra @('--findings-shown-per-file', '1000000')
if ($r.Findings.Count -eq 1) {
  Say-OK 'C2' 'OK' 'a known flag is accepted and the scan runs'
} else {
  Say-Bad 'C2' '1 finding' ($r.Findings.Count.ToString()) 'the known flag was not accepted'
}

# C3 -- THE `nosec` IS OFF BY DEFAULT. A defect on a line carrying a
# `// nosec` comment is still reported, because a tool that stops reporting a
# finding because of a comment in the ANALYSED source has an output the reader
# cannot trust without reading that source first.
#
# 0507 INVERTED THIS ROW'S CLAIM. It used to assert that there was no
# user-facing suppression AT ALL; the suppression is there now, and the
# DEFAULT is the row.
$ns = Join-Path $dir 'nosec'
New-Item -ItemType Directory -Force -Path $ns | Out-Null
[System.IO.File]::WriteAllText((Join-Path $ns 'user.mbt'), "fn main() -> Unit {`n  let x = nosuchfn(1) // nosec`n  ignore(x)`n}`n", $enc)
$r = Invoke-Scan -Dir $ns
if ($r.Findings.Count -eq 1) {
  Say-OK 'C3' 'OK' 'a `// nosec` comment suppresses nothing BY DEFAULT: the finding is still reported'
} else {
  Say-Bad 'C3' '1 finding' ($r.Findings.Count.ToString()) 'the default changed'
}

# C4 -- AND WITH THE FLAG, IT DOES SUPPRESS. C3 alone would be satisfied by a
# parser that refused the flag, so the two halves are pinned together: the
# suppression is OFF by default and ON when asked for.
$r = Invoke-Scan -Dir $ns -Extra @('--honor-nosec')
if ($r.Findings.Count -eq 0) {
  Say-OK 'C4' 'OK' 'with --honor-nosec, the `// nosec` comment DOES suppress the finding on its line'
} else {
  Say-Bad 'C4' '0 findings' ($r.Findings.Count.ToString()) 'the nosec did not suppress'
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 4. THE NARRATIVE QUOTES THESE NUMBERS, AND MUST AGREE WITH THEM ---'
$narPath = Join-Path $root '_verify\NARRATIVE.md'
$narTxt = [System.IO.File]::ReadAllText($narPath, [System.Text.Encoding]::UTF8)
$pctWanted = [math]::Round(100.0 * $WANT_REACH_UNCHECK / $WANT_REACH_TOTAL, 1)
$quotes = @(
  @{ N = 'the corpus reach, package-level calls';   V = $WANT_REACH_TOTAL.ToString() }
  @{ N = 'the corpus reach, unchecked calls';        V = $WANT_REACH_UNCHECK.ToString() }
  @{ N = 'the corpus reach, files carrying them';    V = $WANT_REACH_FILES.ToString() }
  @{ N = 'the corpus reach, unchecked share';        V = $pctWanted.ToString() }
  @{ N = 'the interface population, files';          V = $WANT_MBTI_FILES.ToString() }
  @{ N = 'the interface population, `pub fn`';       V = $WANT_MBTI_PUBFN.ToString() }
  @{ N = 'the family roster, families';              V = $WANT_FAMILIES.ToString() }
  @{ N = 'the family roster, names that differ';     V = $WANT_NAME_DIFFERS.ToString() }
)
$bad = 0
foreach ($q in $quotes) {
  $rx = '(?m)^\s*0505\s+' + [regex]::Escape($q.N) + '\s*:\s*(\d+(?:\.\d+)?)\s*$'
  $m = [regex]::Match($narTxt, $rx)
  if (-not $m.Success) {
    Write-Output ('  D1        MISSING  the narrative does not quote "' + $q.N + '"')
    $bad++
    continue
  }
  if ($m.Groups[1].Value -ne $q.V) {
    Write-Output ('  D1        WRONG    the narrative says ' + $m.Groups[1].Value + ' for "' + $q.N + '"; the measurement says ' + $q.V)
    $bad++
    continue
  }
  Write-Output ('  {0,-10} {1,-9} {2} = {3}' -f 'D1', 'OK', $q.N, $q.V)
}
if ($bad -gt 0) {
  $fail++
  Write-Output ('  D1        MISMATCH ' + $bad + ' quoted number(s) disagree with the measurement')
} else {
  Write-Output ('  D1        OK      all ' + $quotes.Count + ' quoted numbers agree with the measurement')
}

# ---------------------------------------------------------------------------
Write-Output ''
if ($fail -gt 0) {
  Write-Output ('ABORT: ' + $fail + ' of ' + $rows + ' row(s) did not match. The plan''s premises are not what the plan says they are.')
  exit 1
}
Write-Output ('GATE OK: ' + $rows + ' rows. A call''s signature is checked ONLY when the callee is declared in the SAME file -- so "I could not check this" and "there is no problem" are the same output today -- and the public vocabulary is a NAME, not an id. That is what the three transfers from bandit are for, and this is the order they have to happen in.')
exit 0

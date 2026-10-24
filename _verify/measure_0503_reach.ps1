param(
  # Audit a different tree than the pinned corpus. Used by the control.
  [string]$Tree = '',
  # Print the per-file breakdown as well as the totals.
  [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
# Measure the REACH of the `raise?` construct that 0503 fixed, under a rule that
# is WRITTEN DOWN, and compare it with a pin that lives in release.ps1.
#
# WHY THIS IS A STAGE AND NOT A NUMBER WRITTEN DOWN. The 0.4.35 release
# published "162 return-position sites in 31 files" -- measured by an ad-hoc
# grep whose RULE WAS NOT RECORDED, so the figure could not be reproduced
# afterwards: re-measuring on 2026-10-25 gave 173 (31 files) with a type
# pattern that admits no comma, and 188 (33 files) with one that does. The
# number was close and the file count matched, which is worse than being
# plainly wrong, because a reader had no way to tell WHICH rule produced it.
#
# => THE RULE IS THE NUMBER. A reach figure without a recorded rule is a
# number that cannot be re-derived, and a number that cannot be re-derived is a
# number that cannot be checked. This file is that rule, in code.
#
# THE RULE, precisely:
#
#   1. The corpus is the PINNED one: moonbitlang/core 0.1.20260920+7d59c7ec9,
#      `.mbt` files only. The `.mbti` interface files carry `raise?` too (332
#      return-position sites in 38 files) but they were CLEAN under 0.4.34 as
#      well -- the analyzer reads an interface file's declarations without
#      choking on the marker -- so they never blocked anything and they are
#      not part of the reach.
#   2. A site is a `raise?` CLAUSE IN A FUNCTION DECLARATION'S RETURN
#      POSITION: a `-> T raise?` whose arrow is at PAREN DEPTH 0, i.e. not
#      inside any parameter list. A `-> T raise?` at depth >= 1 is the arrow of
#      a FUNCTION TYPE -- `f : (T) -> U raise?` -- and the parser already read
#      that position before 0503.
#   3. The depth is computed by a walker that SKIPS STRING LITERALS, CHAR
#      LITERALS and LINE COMMENTS. Without that care the depth drifts:
#      builtin/string.mbt ends at depth -6, and every site after the first
#      stray parenthesis is then misfiled. This was measured, not assumed.
#   4. The type may be a generic with a comma -- `-> SortedMap[K, V] raise?` --
#      so the type pattern admits `,` and the spaces around it. A pattern that
#      does not is what produced the 162.
#   5. A site must be CODE. A `raise?` inside a comment or inside a string
#      literal is documentation, or data, and is not counted. This matters
#      HERE rather than in principle: the analyzer's own 0503 test file and the
#      parser's own comments DOCUMENT the rule, and a counter that counted
#      them would report 14 sites in this analyzer's own source and make the
#      reach look as though it had spread into the analyzer. With the rule as
#      stated, this analyzer's own source carries ZERO -- the construct is in
#      the CORPUS, not in the analyzer.
#
# AND THE CONTROL, which is what makes the counter worth believing: a
# synthetic fixture is built here, with a number of return-position sites that
# is known BY CONSTRUCTION, and the same counter has to agree with it before
# any real number is reported. A counter that has never been shown to
# disagree is a counter that cannot say anything. The fixture carries a
# commented-out declaration and a `raise?` inside a string literal as well,
# so the control also pins rule 5: those two must NOT be counted, and the
# expected answer does not move if they are counted wrongly -- which is why
# the expected answer is checked and not merely printed.
$root = Split-Path -Parent $PSScriptRoot
$repos = Join-Path $root '.repos'

# --- the counter -------------------------------------------------------------
function Get-ReturnRaiseQ {
  param([string]$Dir)
  $rx = [regex]'->\s*([A-Za-z_][\w\[\]\.]*(?:\s*,\s*[\w\[\]\.]*)*\??)\s+raise\s*\?'
  $out = @()
  $files = @(Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.mbt' })
  foreach ($f in $files) {
    $depth = 0; $ln = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
      $ln++
      $depthAt = New-Object 'int[]' ($line.Length + 1)
      # $isCode marks the positions that are CODE. A `raise?` inside a comment
      # or inside a string literal is not a site: it is documentation, or it is
      # data the analyzer reads as a string. The analyzer's OWN source is the
      # case in point -- its 0503 test file and the parser's own comments
      # DOCUMENT the rule, and counting those would have made the reach look
      # like it had spread into the analyzer.
      $isCode = New-Object 'bool[]' ($line.Length + 1)
      $i = 0; $d = $depth; $inStr = $false; $inChr = $false
      while ($i -lt $line.Length) {
        $c = $line[$i]
        if ($inStr) { if ($c -eq '\') { $i += 2; continue } elseif ($c -eq '"') { $inStr = $false }; $i++; continue }
        if ($inChr) { if ($c -eq '\') { $i += 2; continue } elseif ($c -eq "'") { $inChr = $false }; $i++; continue }
        if ($c -eq '"') { $inStr = $true; $i++; continue }
        if ($c -eq "'") { $inChr = $true; $i++; continue }
        if ($c -eq '/' -and ($i + 1) -lt $line.Length -and $line[$i + 1] -eq '/') { break }
        if ($c -eq '(') { $d++ } elseif ($c -eq ')') { $d-- }
        $depthAt[$i] = $d
        $isCode[$i] = $true
        $i++
      }
      foreach ($m in $rx.Matches($line)) {
        $at = if ($m.Index -lt $depthAt.Length) { $depthAt[$m.Index] } else { $d }
        $code = if ($m.Index -lt $isCode.Length) { $isCode[$m.Index] } else { $true }
        if ($at -eq 0 -and $code) {
          $out += [pscustomobject]@{
            File = $f.FullName.Substring($Dir.Length + 1) -replace '\\', '/'
            Line = $ln
          }
        }
      }
      $depth = $d
    }
  }
  return $out
}

# --- the control -------------------------------------------------------------
# A synthetic tree whose answer is known by construction. The same counter has
# to produce it, or the script reports nothing about the real corpus.
$ctlDir = Join-Path $env:TEMP ('raiseq_ctl_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $ctlDir | Out-Null
$ctl = @(
  '// CONTROL FIXTURE. The counts are known by construction: 4 return-position'
  '// sites in 1 file, and 2 function-type sites that must NOT be counted.'
  '// A commented-out declaration must NOT be counted either:'
  '// pub fn commented_out() -> Int raise? { 1 }'
  'pub fn ret_only() -> Int raise? { 1 }'
  'pub fn both(f : (Int) -> Int raise?) -> Int raise? { 0 }'
  'pub fn ft_only(f : (Int) -> Int raise?) -> Int { 0 }'
  'pub fn[K, V] generic() -> SortedMap[K, V] raise? { todo }'
  'pub fn with_string() -> Int raise? { let s = ")" ; ignore(s) ; 1 }'
  'pub fn quoted() -> Int { let s = "-> Int raise? " ; ignore(s) ; 1 }'
  'pub fn no_raise() -> Int { 1 }'
)
[System.IO.File]::WriteAllText((Join-Path $ctlDir 'ctl.mbt'), ($ctl -join "`n"))
$ctlHits = @(Get-ReturnRaiseQ $ctlDir)
$ctlWant = 4
if ($ctlHits.Count -ne $ctlWant) {
  Write-Output ('FAIL: the control is wrong: the counter found ' + $ctlHits.Count +
    ' return-position sites in the fixture and the fixture has ' + $ctlWant +
    '. The counter is not trusted, so no reach number is reported.')
  exit 1
}
Write-Output ('  control ok: the counter found ' + $ctlHits.Count + '/' + $ctlWant +
  ' return-position sites in a fixture whose answer is known by construction')

# --- the pin -----------------------------------------------------------------
$relTxt = [System.IO.File]::ReadAllText((Join-Path $root '_verify\release.ps1'), [System.Text.Encoding]::UTF8)
$pinM = [regex]::Match($relTxt, "\`$RAISEQ_REACH\s*=\s*'(\d+)\|(\d+)'")
$othM = [regex]::Match($relTxt, "\`$RAISEQ_OTHERS\s*=\s*'(\d+)'")
if (-not $pinM.Success -or -not $othM.Success) {
  Write-Output 'FAIL: release.ps1 no longer carries the reach pins.'
  exit 1
}
$wantSites = [int]$pinM.Groups[1].Value
$wantFiles = [int]$pinM.Groups[2].Value
$wantOthers = [int]$othM.Groups[1].Value

# --- the measurement ---------------------------------------------------------
$core = Join-Path $repos 'moonbitlang\core\0.1.20260920+7d59c7ec9'
if ($Tree -ne '') { $core = $Tree }
if (-not (Test-Path -LiteralPath $core)) {
  Write-Output ('FAIL: the corpus is not there: ' + $core)
  exit 1
}
$hits = @(Get-ReturnRaiseQ $core)
$files = @($hits | Select-Object -ExpandProperty File -Unique)
Write-Output ('  core: ' + $hits.Count + ' return-position `raise?` sites in ' + $files.Count + ' files')
if ($Verbose) {
  $hits | Group-Object File | Sort-Object Name | ForEach-Object {
    Write-Output ('      ' + $_.Count.ToString().PadLeft(4) + '  ' + $_.Name)
  }
}

# THE OTHER SIX CORPORA AND THIS ANALYZER'S OWN SOURCE. The published claim was
# "ALL of them in moonbitlang/core ... Zero in the other six corpora and zero in
# this analyzer's own source", and the second half of that is a claim too.
$others = @(
  'wzzc-dev\moui\0.1.12',
  'riantr\moonbit_labeler\0.2.13',
  'riantr\moonbit_image\0.3.7',
  'moonbitlang\async\0.22.4',
  'moonbit-community\proton\0.3.4',
  'moonbit-community\proton_contract\0.3.4'
)
$otherSites = 0
foreach ($o in $others) {
  $p = Join-Path $repos $o
  if (-not (Test-Path -LiteralPath $p)) { continue }
  $otherSites += @(Get-ReturnRaiseQ $p).Count
}
$ownSites = @(Get-ReturnRaiseQ (Join-Path $root 'src')).Count
Write-Output ('  the other six corpora: ' + $otherSites + ' sites   this analyzer own source: ' + $ownSites + ' sites')

$fail = 0
if ($hits.Count -ne $wantSites -or $files.Count -ne $wantFiles) {
  Write-Output ('FAIL: core reach is ' + $hits.Count + ' sites in ' + $files.Count +
    ' files, pinned ' + $wantSites + '|' + $wantFiles + '.')
  $fail++
}
if ($otherSites -ne $wantOthers -or $ownSites -ne $wantOthers) {
  Write-Output ('FAIL: the reach is supposed to be confined to core. The other six corpora say ' +
    $otherSites + ' and this own source says ' + $ownSites + ', pinned ' + $wantOthers + '.')
  $fail++
}
if ($fail -gt 0) { Write-Output ('ABORT: ' + $fail + ' check(s) failed.'); exit 1 }
Write-Output ('  matches the pin: ' + $wantSites + '|' + $wantFiles +
  ' (core), ' + $wantOthers + ' (everywhere else)')
exit 0

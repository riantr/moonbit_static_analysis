# Settle 0479 -- a UTF-8 BOM at the start of a `.mbt` file.
#
# WHY. `_verify\corpus_backlog.ps1`, measured across all six pinned corpora, reports one
# `unexpected character '<U+FEFF>'` and it names exactly one file:
#
#     riantr/moonbit_labeler/0.2.13/app_moui/labeler_ui_test.mbt
#
# Its first three bytes are EF BB BF, and a sweep of every `.mbt` under `.repos` finds it is
# the ONLY file in the corpus that starts with one -- so this refusal is worth exactly one
# file today, and that is not a reason to leave it: the analyzer is refusing input the
# toolchain's own ecosystem ships, and a refusal of valid code is the one class of defect
# that is never "coverage" and always "wrong".
#
# THE QUESTION IS NOT "IS A BOM LEGAL" BUT "WHERE", and the answer decides the size of the
# change. If U+FEFF is legal only at OFFSET 0 the fix is to STRIP IT before lexing, one
# place, and a U+FEFF anywhere else stays a refusal. If it is legal as ordinary whitespace
# the fix is a token-class change that reaches every position. S4 and S5 exist to tell those
# two apart, and a settle that only asks the first question would let me pick the bigger
# change without knowing it was bigger.
#
# NOTE ON WRITING THE FIXTURES. The BOM is written as three RAW BYTES (EF BB BF), not as a
# decoded character in this file, because that is what the corpus contains and what the
# compiler has to be shown. `<<BOM>>` marks the position and the writer splices the bytes.
# This file is deliberately pure ASCII: PowerShell 5.1 reads a BOM-less .ps1 as ANSI, and a
# literal U+FEFF in the source of a settle is a mojibake waiting for the next edit.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
#
# ctl_no_bom is a well-formed file with NO byte-order mark. It is the row that proves the
# scaffold itself compiles: without it a settle can be entirely green while measuring
# nothing, which is exactly what happened to the 0478 RECORD rows.
Add-Case 'ctl_no_bom' @'
///|
fn add(a : Int, b : Int) -> Int {
  a + b
}
'@ 'ACCEPT'

# ctl_corpus_shape is the FIRST THREE LINES OF THE REAL FILE, byte for byte including the
# mark. It is the positive control for the whole increment: if this row rejects, the
# toolchain refuses the corpus's own code and every row below would be measuring a fiction.
Add-Case 'ctl_corpus_shape' @'
<<BOM>>// app_moui/labeler_ui_test.mbt - Phase 16.C verification tests.

///|
fn f() -> Unit {
  ()
}
'@ 'ACCEPT'

# ctl_must_reject IS THE ROW THIS SETTLE WAS MISSING, and it is the one that would have
# caught the no-op above. It is a deliberately broken file whose verdict is already known, so
# its only job is to prove the INSTRUMENT can produce a REJECT at all. Every other row in
# this file wants ACCEPT, which means a scaffold that silently checks nothing is
# indistinguishable from a scaffold that checks and finds the corpus legal.
#
# This is the same gap the 0478 settle recorded -- "only an ACCEPT control can detect a
# broken prelude" -- and the OTHER half of it, which nobody had: only a REJECT control can
# detect a compiler that is not running.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# --- S1  A MARK BEFORE A DECLARATION, WITH NO LEADING COMMENT -------------------
# The corpus file has a comment first, so a reader that happens to skip the mark while
# skipping a comment would pass ctl_corpus_shape while being wrong here.
Add-Case 'S1_bom_before_decl' @'
<<BOM>>///|
fn g() -> Int {
  1
}
'@ 'ACCEPT'

# --- S2  A MARK BEFORE A `///|` DOC BLOCK ---------------------------------------
# MoonBit attaches doc comments to the item that follows, so a leading `///|` is the one
# shape where the mark is genuinely adjacent to syntax rather than to whitespace.
Add-Case 'S2_bom_before_doc' @'
<<BOM>>///|
/// Adds one.
///
/// ```
/// ```
fn h() -> Int {
  2
}
'@ 'ACCEPT'

# --- S3  AN EMPTY FILE WITH A MARK ---------------------------------------------
# Decides whether the fix can sit before the "is there anything here" check or has to
# live inside the loop that reads characters.
Add-Case 'S3_bom_empty_file' @'
<<BOM>>
'@ 'ACCEPT'

# --- S4  A MARK IN THE MIDDLE, NOT AT OFFSET 0 ---------------------------------
# THE DISCRIMINATOR. If this ACCEPTs, U+FEFF is ordinary whitespace wherever it appears and
# the change is a token-class one. If it REJECTs, the mark is legal only as a file preamble
# and the change is to strip exactly three bytes before lexing -- much smaller, and the
# difference between the two is this one row.
Add-Case 'S4_bom_midfile' @'
///|
fn i() -> Int {
  1 <<BOM>> + 2
}
'@ 'RECORD'

# --- S5  A MARK INSIDE A STRING LITERAL ----------------------------------------
# The other position where a "treat it as whitespace" fix would be observably wrong: it
# would silently change the VALUE of a string that the program can compare against.
Add-Case 'S5_bom_in_string' @'
///|
fn j() -> String {
  "a<<BOM>>b"
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0479_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)
$BOM = [byte[]](0xEF, 0xBB, 0xBF)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0479`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # `src/moon.pkg` IS NOT OPTIONAL, and the first version of this file omitted it and measured
  # NOTHING. A MoonBit project with a `source = "src"` directory but no PACKAGE inside it is
  # not a package, so `moon check` prints "Finished. moon: no work to do", exits 0, and every
  # row in this settle reads ACCEPT -- including rows that are supposed to fail. The verdict
  # looked like a result about the BOM and was a result about my scaffold.
  #
  # It is caught below three ways, and the first is the one that matters: `ctl_must_reject` is
  # a deliberately broken file, so a harness that cannot fail is a harness that has failed.
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)

  # SPLICE THE RAW BYTES. `<<BOM>>` is replaced by EF BB BF; everything around it is
  # encoded as UTF-8 WITHOUT a preamble, so the fixture has exactly one mark, exactly where
  # it was asked for, and no accidental second one from the writer.
  $parts = $cases[$k] -split '<<BOM>>'
  $bytes = New-Object System.Collections.Generic.List[byte]
  for ($i = 0; $i -lt $parts.Count; $i++) {
    if ($i -gt 0) { foreach ($b in $BOM) { $bytes.Add($b) } }
    foreach ($b in $enc.GetBytes($parts[$i])) { $bytes.Add($b) }
  }
  [IO.File]::WriteAllBytes((Join-Path $d 'src\main.mbt'), $bytes.ToArray())

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  # "no work to do" IS THE SHAPE OF A COMPILER THAT DID NOT RUN. It exits 0, so every
  # verdict-matching expression below would read it as ACCEPT. A project with no package
  # inside `source = "src"` produces exactly this, and the first version of this settle
  # returned 7/7 ACCEPT for that reason. Detect it by name rather than by inference.
  $noop = $joined -match 'no work to do'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($noop) {
    $got = 'MOON-DID-NOT-RUN'; $ok = $false
  } elseif ($plan) {
    $got = 'BUILD-PLAN-FAILED'; $ok = $false
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'RECORD') { $ok = $true }
    elseif ($want -eq 'ACCEPT') { $ok = $false }
    else { $ok = $got -like 'REJECT*' }
  } else {
    $got = 'ACCEPT'
    if ($want -eq 'RECORD') { $ok = $true } else { $ok = ($want -eq 'ACCEPT') }
  }
  Write-Output ('{0,-42} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown|Unknown|unexpected|╰── ' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. Both controls must behave.'
  Write-Output 'A flipped CLAIM means the analyzer change is aimed at something the toolchain refuses.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

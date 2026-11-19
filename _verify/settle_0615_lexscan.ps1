# Settle 0615 -- `lexscan`, THE LEXICAL SCAN, and its two strategies.
#
# WHY. `lexscan <subject> [with <strategy>] { arms }` is MoonBit's STREAMING
# regex-lexer form of a match. The subject is a SCANNER -- a `Lexbuf`, a
# `StringScanner`, or anything implementing `Scannable` -- and the arms are
# patterns whose first element is a REGEX LITERAL:
#
#     lexscan self {
#       (re"^[^\n]*" as line) + re"\r\n" => Some(line)
#       _ => None
#     }
#
# It is NOT a name, and reading it as one produced `undefined variable
# 'lexscan'` -- a FALSE POSITIVE on code `moon check` accepts. MEASURED on the
# re-pinned corpus (`moonbitlang/core` `0.1.20261117+06da1ed44`), three sites,
# and every one of them in ORDINARY CODE rather than in a test body:
#
#     lexbuf/read_line.mbt:37
#     lexbuf/read_line_test.mbt:53
#     lexbuf/async_read_line_test.mbt:29
#
# The OLD corpus used `lexscan` in six files and the analyzer reported nothing
# at all, because every one of those uses was in a place the analyzer never
# reads -- a `test` body, or a doc comment. The construct was in the corpus the
# whole time and in no analysed code at all.
#
# THE GRAMMAR IS WHAT THIS SETTLES. Five forms, one probe each, and the two
# STRATEGIES are the part the corpus does not exercise: the corpus writes the
# bare form at all three of its sites, so a reader that only knew the bare form
# would pass every corpus measurement and be wrong about the toolchain.
#
#     lexscan s { .. }                the bare form -- the corpus's form
#     lexscan s with longest { .. }   the second strategy
#     lexscan s with first { .. }     the default strategy, named
#     lexscan s with { .. }           `with` without its strategy
#     lexscan s                       the arms are not optional
#
# AND THE TARGET'S TYPE, which is what makes every row here need an IMPORT: a
# `lexscan` subject is a SCANNER, and a `String` is not one. The toolchain
# says so in its own words:
#
#     Invalid lexscan target: expected @lexbuf.Lexbuf, @lexbuf.AsyncLexbuf,
#     @lexbuf.StringScanner, @lexbuf.BytesLexbuf, @lexbuf.AsyncBytesLexbuf,
#     @lexbuf.BytesScanner, or a type implementing @lexbuf.Scannable or
#     @lexbuf.BytesScannable, but got String.
#
# So every row imports `moonbitlang/core/lexbuf` and scans a `StringScanner`.
# That import is RESOLVED FROM THE TOOLCHAIN'S OWN BUNDLED CORE, so the rows
# do not reach the network -- and the bundled core is the one the corpus is
# pinned to, so the two cannot disagree.
#
# SCAFFOLD NOTES, CARRIED FROM 0480 AND 0488 AND 0496 BECAUSE ALL FOUR BIT THE
# SAME WAY. Every row here is written to a project that HAS a `src/moon.pkg`,
# because a MoonBit project without a package inside its source directory is
# not a package: `moon check` prints "no work to do", exits 0, and every row
# reads ACCEPT. `ctl_must_reject` exists so a harness that cannot fail cannot
# look like a harness that found the corpus legal, and "no work to do" is
# matched by name so that specific no-op can never again pass silently.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
Add-Case 'ctl_no_escape' @'
///|
fn a(s : String) -> String {
  s
}
'@ 'ACCEPT'

# ctl_must_reject proves the INSTRUMENT can fail.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# ctl_plain_match -- an ordinary `match` is accepted, so the rows below are
# about the `lexscan` and not about matching in general.
Add-Case 'ctl_plain_match' @'
///|
fn a(s : String) -> String {
  match s {
    "x" => s
    _ => s
  }
}
'@ 'ACCEPT'

# ctl_regex_literal -- the regex literal itself is legal (0494), so a row that
# failed on the `re"..."` and not on the `lexscan` would be about the wrong
# thing.
Add-Case 'ctl_regex_literal' @'
///|
fn a(s : String) -> Bool {
  s =~ re"^a"
}
'@ 'ACCEPT'

# ctl_scanner_type -- a `StringScanner` is a legal value on its own, so a row
# that failed would be about the `lexscan` and not about the scanner.
Add-Case 'ctl_scanner_type' @'
///|
fn a(s : String) -> Int {
  let scanner = @lexbuf.StringScanner(s[:])
  scanner.cursor
}
'@ 'ACCEPT'

# --- THE GRAMMAR. ------------------------------------------------------------
# L1 IS THE CORPUS'S OWN FORM: no strategy clause at all. The corpus writes it
# at all three of its sites.
Add-Case 'L1_lexscan_bare' @'
///|
fn a(s : String) -> Int {
  let scanner = @lexbuf.StringScanner(s[:])
  lexscan scanner {
    re"^a" as t => 1
    _ => 0
  }
}
'@ 'ACCEPT'

# L2 IS THE SECOND STRATEGY. `longest` asks the scanner for the LONGEST match
# rather than the first, and it is the strategy the corpus's sibling construct
# (`lexmatch`) is written with.
Add-Case 'L2_lexscan_with_longest' @'
///|
fn a(s : String) -> Int {
  let scanner = @lexbuf.StringScanner(s[:])
  lexscan scanner with longest {
    re"^a" as t => 1
    _ => 0
  }
}
'@ 'ACCEPT'

# L3 IS THE DEFAULT STRATEGY, NAMED. The toolchain's own error message names
# the two: "Only `first` (the default one) and `longest` match strategies are
# supported". A reader that knew only `longest` would leave `first` in the
# token stream -- and the corpus writes NEITHER strategy, so nothing else in
# this repository would notice.
Add-Case 'L3_lexscan_with_first' @'
///|
fn a(s : String) -> Int {
  let scanner = @lexbuf.StringScanner(s[:])
  lexscan scanner with first {
    re"^a" as t => 1
    _ => 0
  }
}
'@ 'ACCEPT'

# L4 IS THE ROW THAT PINS `with`'s COMPANION: `with` on its own is not a
# clause, it is the first half of one.
Add-Case 'L4_lexscan_bare_with' @'
///|
fn a(s : String) -> Int {
  let scanner = @lexbuf.StringScanner(s[:])
  lexscan scanner with {
    re"^a" as t => 1
    _ => 0
  }
}
'@ 'REJECT'

# L5 IS THE ROW THAT PINS THE ARMS AS MANDATORY. A `lexscan` without a block
# is not a construct.
Add-Case 'L5_lexscan_without_arms' @'
///|
fn a(s : String) -> Int {
  let scanner = @lexbuf.StringScanner(s[:])
  lexscan scanner
}
'@ 'REJECT'

# --- THE TARGET'S TYPE. ------------------------------------------------------
# L6 IS THE TYPE RULE, and it is why every row above needs an import. The
# subject is a SCANNER; a `String` is not one, and the toolchain refuses the
# construct rather than the program:
#
#     Invalid lexscan target: expected @lexbuf.Lexbuf, ... but got String.
Add-Case 'L6_a_string_is_not_a_scanner' @'
///|
fn a(s : String) -> Int {
  lexscan s {
    re"^a" as t => 1
    _ => 0
  }
}
'@ 'REJECT'

# --- THE CORPUS'S OWN SHAPE. -------------------------------------------------
# L7 IS THE CORPUS'S ARMS: a COMPOUND pattern -- two regexes joined by `+`,
# with a capture bound by `as` -- and the arm body reads that capture. The
# corpus writes exactly this at `lexbuf/read_line.mbt:37` and `:53`.
Add-Case 'L7_the_corpus_shape' @'
///|
fn a(s : String) -> Int {
  let scanner = @lexbuf.StringScanner(s[:])
  lexscan scanner {
    (re"^[^\n]*" as line) + re"\r\n" => 1
    (re"^[^\n]*" as line) + re"\n" => 1
    re"^[^\n]+" as line => 1
    _ => 0
  }
}
'@ 'ACCEPT'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0615ls_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0615ls`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # REQUIRED. See the scaffold notes above.
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "import {`n  `"moonbitlang/core/lexbuf`",`n}`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  $o = Join-Path $root ($k + '.out')
  $p = Start-Process -FilePath 'moon' -ArgumentList @('-C', $d, 'check') -RedirectStandardOutput $o -RedirectStandardError ($o + '.err') -NoNewWindow -Wait -PassThru
  $joined = ''
  if (Test-Path -LiteralPath $o) { $joined += [IO.File]::ReadAllText($o) }
  if (Test-Path -LiteralPath ($o + '.err')) { $joined += [IO.File]::ReadAllText($o + '.err') }
  $noop = $joined -match 'no work to do'
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
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
    $lines = $joined -split "`r?`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown|Unknown|unexpected|Invalid lexscan|Only .first' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All five controls must behave.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

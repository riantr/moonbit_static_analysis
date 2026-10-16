# What actually blocks `input_dispatch_result.mbt`?
#
# THE ANSWER, settled here 20/20 with a positive control: the single-character
# BITWISE-OR `|` did not continue an expression across a newline. Nothing else about
# the file is broken. The fix is one token in one list.
#
# THE CAUSE. `newline_suppressed_after` (src/lexer/lexer.mbt:176) decides which tokens
# let an expression continue over a line break. It listed `TAmp`, `TCaret`, `TAndAnd`,
# `TOrOr`, `TShl`, `TShr` and every arithmetic and comparison operator, and did NOT
# list `TBar`. So the lexer emitted `TNewline` after `|`, `parse_bitor` bumped the `|`
# correctly, and then the operand parse landed on `TNewline` and `parse_primary` raised
# "unexpected end of line" (parser.mbt:4664).
#
# WHY EVERY OTHER OPERATOR LOOKED FINE, which is what made this hard to see: `+`, `&`
# and `||` were all in the suppression list already, so `a +\n b` and `a &\n b` parse.
# Only `|` was missing. That is also why a sweep for "trailing binary operators" finds
# 178 files and 2296 sites and proves NOTHING: 103 of those are moui files and only 3
# moui files fail to parse at all, because the other operators all continue correctly.
# A site count is not a leverage count.
#
# THIS FILE HAS BOTH STATES IN IT. The eight rows that now expect `PARSES` each read
# `FAILS` before the fix, and that is exactly what makes them a guard rather than a
# description: remove `| TBar` from the suppression list and all eight go red again.
# `corpus_host_flags` is the corpus function verbatim, and it is the row that fails if
# the mechanism ever comes back.
#
# WHY THIS EXISTS. After 0454 moui 0.1.12 is 605 of 608 files, and the three that
# remained were one file each with three DIFFERENT reasons:
#
#     expected ')'            runtime/app_builder.mbt:40,47
#     unexpected end of line  runtime/input_dispatch_result.mbt:13
#     unexpected token `:`    backend/macos/macos_services.mbt:406
#
# `input_dispatch_result.mbt:13-15` was carried forward across several rounds as "a
# parenthesised `if` as an operand". THAT LABEL IS WRONG, and the rows below are why.
# The corpus function is:
#
#     (if self.handled { 1 } else { 0 }) |
#     (if self.capture_pointer { 2 } else { 0 }) |
#     (if self.release_pointer { 4 } else { 0 })
#
# Four hypotheses were measured and all four died:
#
#   1. "a parenthesised `if` as an operand". DEAD: `paren_if_alone` and
#      `paren_if_single_line` both PARSE, before and after the fix. The analyzer also
#      demonstrably understands `if` -- it emits "if expression is outside the
#      analyzed subset" (`macos_services.mbt:193:18`), which is a note about analysis
#      scope, not a parse failure. `\(\s*if\s` also appears in 20 files of moui while
#      only 3 files in all of moui fail to parse, so at least 17 of those 20 parse.
#   2. "the expression is final in the block". DEAD: `trailing_op_body_nonfinal` puts
#      the same shape mid-body and behaved identically.
#   3. "an enclosing delimiter has to stay open". DEAD: `trailing_op_in_call` and
#      `trailing_op_in_let` cover both, and behaved identically.
#   4. "a trailing binary operator does not continue the expression". ALSO WRONG, and
#      this was the one I believed longest -- `trailing_plus_body_final` (`a +` newline
#      `b`) PARSED before the fix, as did `bitand_trailing` and `logical_or_trailing`.
#
# SO IT IS THE OPERATOR, NOT THE POSITION AND NOT THE NEWLINE RULE. `pipe_same_line`
# (`a | b`, no newline) PARSED before the fix, so bitwise-or was fully supported in
# expression position; what was missing was its participation in continuation.
#
# `ctl_known_fail_patctor` is the POSITIVE CONTROL and the most important row in the
# file: it is the `macos_services.mbt:406` is-pattern, a known failure. If it read
# PARSES, this probe could not see a failure and every other row would be decoration.
#
# This measures THIS ANALYZER, not the toolchain. Each fixture is written alone into
# its own directory and scanned with the built wasm, because `moonrun` takes a
# directory. The copy loses its imports, which does not matter: every question here is
# a parse question, not a name-resolution one.
param()
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
$wasm = Join-Path $repo '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$repos = Join-Path $repo '.repos'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'

if (-not (Test-Path -LiteralPath $wasm)) {
  Write-Output ('ABORT: no scanner at ' + $wasm)
  Write-Output '  Every row here would be a confident wrong answer about a build that'
  Write-Output '  does not exist. Build it first.'
  exit 1
}

$cases = [ordered]@{}
$expect = [ordered]@{}
function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# CONTROL 1: `if` as a statement, which the corpus uses everywhere and which the
# analyzer must already handle. Establishes that the probe reads PARSES at all.
Add-Case 'ctl_if_statement' @'
///|
fn probe(a : Bool) -> Int {
  if a {
    1
  } else {
    0
  }
}
'@ 'PARSES'

# POSITIVE CONTROL: the KNOWN failure, verbatim in shape from macos_services.mbt:405-406
# including the `is` on the FOLLOWING line. This is the row that proves the probe can
# see a failure; without it every other row is decoration.
Add-Case 'ctl_known_fail_patctor' @'
///|
fn probe(menu : Int) -> Bool {
  let in_menu_bar = menu
    is @services.ApplicationMenuPlacement::MenuBar
  in_menu_bar
}
'@ 'FAILS'

# (a) ALONE, on one line: a parenthesised `if` used as an operand of `|`.
Add-Case 'paren_if_single_line' @'
///|
fn probe(a : Bool, b : Bool) -> Int {
  (if a { 1 } else { 0 }) | (if b { 2 } else { 0 })
}
'@ 'PARSES'

# THE SAME EXPRESSION with the operator at the end of the line -- the corpus shape.
# This is the row that separates (a) from (b).
Add-Case 'paren_if_trailing_op' @'
///|
fn probe(a : Bool, b : Bool) -> Int {
  (if a { 1 } else { 0 }) |
  (if b { 2 } else { 0 })
}
'@ 'PARSES'

# (b) WITH NO PARENTHESISED `if` ANYWHERE: a bare trailing operator continues the
# expression.
#
# MEASURED FAILS, and I expected PARSES when this row was written. That mismatch is
# the finding, so it is recorded here rather than quietly corrected: if a bare trailing
# `|` worked everywhere, this row would pass and the continuation would not be the
# defect. It does not pass -- so line continuation is CONTEXT-DEPENDENT, and the rows
# after it are what scope it.
Add-Case 'trailing_op_plain' @'
///|
fn probe(a : Int, b : Int) -> Int {
  a |
  b
}
'@ 'PARSES'

# SCOPING ROW 1: the same operator inside CALL ARGUMENTS, where the closing `)` has
# not been reached.
#
# MEASURED FAILS; I expected PARSES on the theory that continuation is driven by "an
# enclosing delimiter is still open". It is not, or this row would pass -- the trailing
# `|` is dropped in every context tried, not just the failing one. The expectation
# below is the measurement, not the guess.
Add-Case 'trailing_op_in_call' @'
///|
fn sink(x : Int, y : Int) -> Int {
  x + y
}

///|
fn probe(a : Int, b : Int) -> Int {
  sink(a |
       b)
}
'@ 'PARSES'

# SCOPING ROW 2: inside an ASSIGNMENT. MEASURED FAILS, expected PARSES for the same
# reason as row 1.
Add-Case 'trailing_op_in_let' @'
///|
fn probe(a : Int, b : Int) -> Int {
  let x = a |
          b
  x
}
'@ 'PARSES'

# SCOPING ROW 3: the failing shape, but with the statement NOT last in the body.
# MEASURED FAILS, expected PARSES. Together with rows 1 and 2 this retires "final
# expression of a block" as the discriminator: position does not matter, the operator
# does.
Add-Case 'trailing_op_body_nonfinal' @'
///|
fn probe(a : Int, b : Int) -> Int {
  let x = a |
          b
  0
}
'@ 'PARSES'

# SCOPING ROW 4: a DIFFERENT operator in the trailing position.
# MEASURED PARSES; I expected FAILS, having written the row to prove the defect was
# about trailing operators AS A CLASS. It is not. `+` continues across the newline
# perfectly, and this row is the reason the description changed from "trailing
# operator" to "the bitwise-or token".
Add-Case 'trailing_plus_body_final' @'
///|
fn probe(a : Int, b : Int) -> Int {
  a +
  b
}
'@ 'PARSES'

# SCOPING ROW 5: the failing shape but with the parenthesised `if` REMOVED and the
# operands made simple names -- byte-for-byte `trailing_op_plain`. Present so the
# claim "this is about `|`, not about `if`" is pinned by a row rather than by reading.
Add-Case 'trailing_op_two_lines_three' @'
///|
fn probe(a : Int, b : Int, c : Int) -> Int {
  a |
  b |
  c
}
'@ 'PARSES'

# ---- THE TURN. The rows above said `+` continues at end of line and `|` does not, in
# every context tried. That retires "trailing binary operator" as the description and
# makes `|` itself the suspect. In MoonBit `|` is ALSO the pattern-alternative
# separator -- `A | B => ...` inside a `match` -- so the expression parser may be
# routing it to pattern logic. The question that settles it is whether `|` works in
# expression position AT ALL, with no newline anywhere.
Add-Case 'pipe_same_line' @'
///|
fn probe(a : Int, b : Int) -> Int {
  a | b
}
'@ 'PARSES'

# Same operator, same line, inside an assignment rather than as the final expression.
Add-Case 'pipe_same_line_let' @'
///|
fn probe(a : Int, b : Int) -> Int {
  let x = a | b
  x
}
'@ 'PARSES'

# `||` is logical-or, a different token from `|`. If `||` continues and `|` does not,
# the defect is scoped to the bitwise-or token and not to the pipe family.
Add-Case 'logical_or_trailing' @'
///|
fn probe(a : Bool, b : Bool) -> Bool {
  a ||
  b
}
'@ 'PARSES'

# `&` is bitwise-and. It decides whether `|` is uniquely broken or is one member of a
# broken family of single-character bitwise operators.
Add-Case 'bitand_trailing' @'
///|
fn probe(a : Int, b : Int) -> Int {
  a &
  b
}
'@ 'PARSES'

# `a | b` on ONE line inside the corpus's own shape -- parenthesised `if` operands,
# single line. If this passes while `paren_if_trailing_op` fails, the newline is the
# whole difference and the fix belongs in line continuation, not in the operator.
Add-Case 'pipe_paren_if_one_line' @'
///|
fn probe(a : Bool, b : Bool, c : Bool) -> Int {
  (if a { 1 } else { 0 }) |
  (if b { 2 } else { 0 }) |
  (if c { 4 } else { 0 })
}
'@ 'PARSES'

# (a) ALONE, not chained at all: one parenthesised `if` as the whole body.
Add-Case 'paren_if_alone' @'
///|
fn probe(a : Bool) -> Int {
  (if a { 1 } else { 0 })
}
'@ 'PARSES'

# ---- REGRESSION ROWS FOR THE FIX ITSELF. Adding `TBar` to `newline_suppressed_after`
# is a change to a set whose omission was DELIBERATE, and the reason is recorded at
# lexer.mbt:68-73 and :1364-1368:
#
#   "A lone `|` -- the or-pattern separator inside match arms
#    (`SAssign(_) | SLet(_) => ...`). Match bodies are skipped whole, so no pattern
#    grammar is needed; the token exists so the CHARACTER stops reaching lex_op's
#    unknown-char arm."
#
# That comment is STALE relative to the parser -- `parse_bitor` (parser.mbt:3134) now
# consumes `TBar` and builds `EBin(OpBitOr, ...)`, so `|` is also the bitwise-or
# operator token, not only a pattern token. The reasoning above is about MATCH BODIES,
# which are skipped whole and never reach a pattern parser, and suppression only drops
# the `TNewline` TOKEN -- `TBar` itself still reaches the stream. So or-patterns should
# be unaffected. These rows exist so that claim is pinned by measurement.
#
# The ordinary one-line or-pattern: the form the corpus actually writes.
Add-Case 'or_pattern_same_line' @'
///|
enum Shape {
  Circle(Int)
  Square(Int)
}

///|
fn probe(s : Shape) -> Int {
  match s {
    Circle(_) | Square(_) => 1
  }
}
'@ 'PARSES'

# The leading-alternative arm style, `| Ctor => ...`, which is how the corpus writes
# an arm that continues the previous pattern.
Add-Case 'or_pattern_leading_pipe' @'
///|
enum Shape {
  Circle(Int)
  Square(Int)
  Dot
}

///|
fn probe(s : Shape) -> Int {
  match s {
    Circle(_) => 1
    | Square(_) => 2
    | Dot => 3
  }
}
'@ 'PARSES'

# A bitwise-or on ONE line inside a real expression, next to the or-pattern rows, so a
# future change cannot make the operator quietly stop being parsed while the pattern
# rows stay green.
Add-Case 'bitor_expression_same_line' @'
///|
fn probe(a : Int, b : Int, c : Int) -> Int {
  a | b | c
}
'@ 'PARSES'

# THE CORPUS FUNCTION, verbatim. It must FAIL, or the rows above are not measuring
# the file they claim to measure.
Add-Case 'corpus_host_flags' @'
///|
pub struct InputDispatchResult {
  handled : Bool
  capture_pointer : Bool
  release_pointer : Bool
}

///|
pub fn InputDispatchResult::host_flags(self : InputDispatchResult) -> Int {
  (if self.handled { 1 } else { 0 }) |
  (if self.capture_pointer { 2 } else { 0 }) |
  (if self.release_pointer { 4 } else { 0 })
}
'@ 'PARSES'

# --- run --------------------------------------------------------------------
$enc = New-Object System.Text.UTF8Encoding($false)
$base = Join-Path $env:TEMP ('settle0455_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $base | Out-Null
$fail = 0

Write-Output ('=== fixture  verdict           (want)          reason' + "n")

foreach ($k in $cases.Keys) {
  $d = Join-Path $base $k
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'probe.mbt'), $cases[$k], $enc)

  $o = Join-Path $base ($k + '.out')
  $e = Join-Path $base ($k + '.err')
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $d, '--extern-iface-dir', $repos) `
    -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -Wait | Out-Null

  # The redirected handle is not closed the instant the process exits on this machine,
  # and ReadAllText on a locked file throws an IOException that names neither the file
  # nor the stage. Retry, and say so rather than surfacing a bare .NET error.
  $txt = ''
  for ($i = 1; $i -le 20; $i++) {
    try { $txt = [System.IO.File]::ReadAllText($o); break }
    catch [System.IO.IOException] {
      if ($i -eq 20) { $txt = '' }
      else { Start-Sleep -Milliseconds (100 * $i) }
    }
  }

  $bk = [regex]::Match($txt, '(?m)^BYKIND\t\.mbt\tfiles=(\d+)\tparsed=(\d+)')
  $reason = ''
  if (-not $bk.Success) {
    $reason = 'no BYKIND .mbt line at all'
  }
  $files = if ($bk.Success) { [int]$bk.Groups[1].Value } else { -1 }
  $parsed = if ($bk.Success) { [int]$bk.Groups[2].Value } else { -1 }
  if ($files -le 0) { $reason = 'scanned 0 files' }

  $got = if ($parsed -lt 0) { 'NO-RESULT' } elseif ($parsed -ge $files) { 'PARSES' } else { 'FAILS' }

  # Surface the reason the scanner gave, so a row that fails for a DIFFERENT reason
  # than the one under test cannot be read as confirming it.
  $nr = [regex]::Match($txt, '(?m)^\s+1x\s+(.+)$')
  if ($nr.Success) { $reason = ($nr.Groups[1].Value).Trim() }

  $want = $expect[$k]
  $ok = ($got -eq $want)
  Write-Output ('{0,-26} {1,-16} (want {2,-8}) {3}   {4}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }), $reason)
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($cases['ctl_known_fail_patctor'] -and $expect['ctl_known_fail_patctor'] -eq 'FAILS') {
  # The control's own verdict, stated separately so it cannot be skimmed past.
  Write-Output 'The POSITIVE CONTROL row is the one that licenses the rest: if'
  Write-Output '`ctl_known_fail_patctor` did not read FAILS, this probe cannot see a'
  Write-Output 'failure and every other row here is decoration.'
  Write-Output ''
}

if ($fail -gt 0) {
  Write-Output ('ABORT: ' + $fail + ' row(s) disagree with the expectation. The rows are')
  Write-Output 'hypotheses about this file, not established facts, and a mismatch means the'
  Write-Output 'hypothesis is wrong -- not that the file should be made to match it.'
  exit 1
}
Write-Output 'GATE OK: see the two `trailing_op*` / `paren_if*` rows together -- they are'
Write-Output 'what separates the carried-forward label from the measured one.'
exit 0

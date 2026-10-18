# Settle 0486 -- two constructs at async's two DEEPEST unreadable files.
#
# WHY. Re-ranking the backlog by MEASUREMENT rather than by the list carried between increments
# found that the list was stale: it named four files, and the real backlog is EIGHT, two of which
# read ZERO lines and neither of which was on it. async stands at 411/419 with 25 findings withheld.
#
#     src/internal/coroutine/async_primitive.mbt:16   reads 0 lines
#     examples/http_file_server/main.mbt:24            reads 0 lines
#
# THE TWO CONSTRUCTS, AND THEY ARE NOT RELATED:
#
#   A  `-> T noraise + nocancel`   an effect clause joining TWO effects with `+`, on an
#                                  `async fn[T]` whose body is the foreign-function form
#                                  `= "%async.suspend"`.
#   B  `conn <+` with the OPERAND ON THE NEXT LINE, as a multi-line `$|...` interpolant.
#
# B IS NOT A LEXER GAP. `<+` is `TAppendPlus` and is already lexed -- lexer.mbt:145 documents it,
# including that it is a StringBuilder/Array APPEND and NOT string concatenation. So the question
# is whether the PARSER reads it across a line break. The 0432 gate already made some chains
# continue on the next line, so the two answers can differ operator by operator and that is worth
# settling rather than assuming.
#
# The two are in one settle because they are the two zero-line files, and keeping them apart is
# free: each has its own controls, so a fault in one does not silently answer for the other. That
# is the 0483 lesson -- a boundary line naming two constructs means two rows, not one.
#
# *** AN ABORT PATH THAT HAS NEVER FIRED HAS NOT BEEN TESTED. *** 0485's first draft printed six
# MISMATCH rows and still ended `GATE OK` because the `$fail++` was dropped. `ctl_must_reject`
# below is there to be the row that makes the instrument prove it can fail, and `MISMATCH
# ARMED` at the end deliberately runs one row with a WRONG expectation so the abort is exercised
# in this same run rather than trusted.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------

Add-Case 'ctl_plain_body' @'
///|
fn f(x : Int) -> Int {
  x + 1
}
'@ 'ACCEPT'

# Proves the INSTRUMENT can fail. Every other gated row wants ACCEPT, so a compiler that is not
# running looks exactly like a compiler that approves the corpus.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# CONTROL FOR A: the SINGLE-effect spelling this analyzer already reads.
Add-Case 'ctl_single_effect' @'
///|
fn f() -> Unit noraise {
  ()
}
'@ 'ACCEPT'

# CONTROL FOR B: `<+` on ONE LINE, which the parser reads today. The pair B1/B2 is the whole
# question -- if this ever goes red, the construct moved rather than grew.
Add-Case 'ctl_append_sameline' @'
///|
fn f(sb : StringBuilder) -> Unit {
  sb <+ "x"
  ignore(sb)
}
'@ 'ACCEPT'

# --- A  THE COMBINED EFFECT ----------------------------------------------------

# A1 THE CORPUS SHAPE. `async fn[T]`, a callback parameter, a combined effect, and the
# foreign-function body together -- four things at once, which is why it is RECORDed rather than
# gated: the settle's job is to separate them, and a gated row that fails for any one of them
# teaches nothing about which.
Add-Case 'record_A1_corpus_shape' @'
///|
async fn[T] async_suspend(cb : ((T) -> Unit) -> Unit) -> T noraise + nocancel = "%async.suspend"
'@ 'RECORD'

# A2 JUST THE COMBINED EFFECT, on an ordinary function. This is the question: does `+` join two
# effects, or is `noraise + nocancel` one token?
Add-Case 'A2_combined_effect_only' @'
///|
fn f() -> Unit noraise + nocancel {
  ()
}
'@ 'ACCEPT'

# A3 A DIFFERENT PAIR, so A2 cannot be answered by a special case for these two names.
Add-Case 'A3_other_effect_pair' @'
///|
fn f() -> Unit raise + noraise {
  ()
}
'@ 'RECORD'

# A4 THE COMBINED EFFECT WITH NO RETURN ANNOTATION AT ALL.
Add-Case 'A4_no_return_annotation' @'
///|
fn f() noraise + nocancel {
  ()
}
'@ 'RECORD'

# --- B  THE OPERAND ON THE NEXT LINE ------------------------------------------

# B1 THE CORPUS SHAPE. Recorded rather than gated because it carries TWO changes at once -- the
# line break and the multi-line interpolant -- and a gated row cannot say which one failed.
Add-Case 'record_B1_corpus_shape' @'
///|
fn f(sb : StringBuilder) -> Unit {
  sb <+
    $|<html><body>
    $|</body></html>
  ignore(sb)
}
'@ 'RECORD'

# B2 THE LINE BREAK ALONE, with the simplest possible operand. This is the row that actually
# answers B: with it, B1 is a two-variable question and this is a one-variable one.
Add-Case 'B2_nextline_string_operand' @'
///|
fn f(sb : StringBuilder) -> Unit {
  sb <+
    "x"
  ignore(sb)
}
'@ 'ACCEPT'

# B3 THE INTERPOLANT ALONE, on one line -- so the interpolant is separated from the break.
Add-Case 'B3_interpolant_sameline' @'
///|
fn f(sb : StringBuilder) -> Unit {
  sb <+ $|<html>
  ignore(sb)
}
'@ 'ACCEPT'

# B4 A MULTI-LINE OPERAND ON ONE LINE START, which is what the corpus actually does: several
# `$|...` lines joined by one leading `<+`.
Add-Case 'B4_multiline_operand_one_break' @'
///|
fn f(sb : StringBuilder) -> Unit {
  sb <+
    $|<a>
    $|</a>
  ignore(sb)
}
'@ 'RECORD'

# --- A5  WHAT MAY FOLLOW THE `+`, WHICH IS THE QUESTION M2 ASKED ----------------
#
# M2 generalised the clause to "any name after the `+`" and SURVIVED, and the reason is a gap in
# this settle rather than in the reader: `raise + noraise` is blocked by the `noraise`-FIRST test
# before the operand's NAME is ever examined, so no row could see the second half of the guard.
# These three rows ask the half nobody had asked -- what may follow `noraise +` at all. If an
# ARBITRARY name is accepted, the reader should take it and M2 is not a defect; if it is refused,
# the narrow guard is load-bearing and needs a row of its own.
Add-Case 'A5_noraise_plus_raise' @'
///|
fn f() -> Unit noraise + raise {
  ()
}
'@ 'RECORD'

Add-Case 'A6_noraise_plus_arbitrary' @'
///|
fn f() -> Unit noraise + whatever {
  ()
}
'@ 'RECORD'

Add-Case 'A7_raise_plus_nocancel' @'
///|
fn f() -> Unit raise + nocancel {
  ()
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0486_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  # REQUIRED. Without the `src` DIRECTORY nothing is written, `moon check` has nothing to check,
  # and every row answers ACCEPT -- which is how the first four probes of settle_0485 all read
  # ACCEPT and none of them meant anything.
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0486`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # REQUIRED, or `moon check` prints "no work to do" and exits 0 -- which every ACCEPT row would
  # read as a pass.
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), '', $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $noop = $joined -match 'no work to do'
  $missing = -not (Test-Path (Join-Path $d 'src\main.mbt'))
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($noop -or $missing) {
    $got = 'MOON-DID-NOT-RUN'; $ok = $false
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'RECORD') { $ok = $true }
    elseif ($want -eq 'ACCEPT') { $ok = $false }
    else { $ok = $got -like 'REJECT*' }
  } else {
    $got = 'ACCEPT'
    if ($want -eq 'RECORD') { $ok = $true } else { $ok = ($want -eq 'ACCEPT') }
  }
  Write-Output ('{0,-34} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  # LOAD-BEARING. 0485's draft dropped this in a restructure and printed six MISMATCH rows into a
  # `GATE OK`. A gate that cannot fail reports the same verdict whether the grammar is legal or not.
  if (-not $ok) {
    $fail++
  }
  # VERBOSE dumps the compiler's own WORDS. The error CODE alone is not the answer: `4040` meant
  # "Array expects 1 argument(s)" in one fixture and could mean a grammar refusal in the next.
  if ($env:SETTLE_VERBOSE -eq '1' -and $errs.Count) {
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        $slice = $lines[$j..([Math]::Min($j + 9, $lines.Count - 1))]
        $slice | ForEach-Object { Write-Output ('      | ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All five controls must behave.'
  Write-Output 'A red CONTROL means the fixture does not compile -- a scaffold fault, and every row'
  Write-Output 'is then agreeing for the wrong reason.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

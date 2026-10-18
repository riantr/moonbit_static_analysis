# Settle 0487 -- the SECOND half of the combined-effect clause: `raise + nocancel`.
#
# WHY THIS EXISTS, AND IT IS NOT "MORE OF THE SAME". Gate 0486 settled ONE spelling --
# `noraise + nocancel` -- and declared `raise + nocancel` a survivor because the `raise` arm
# returns before the `+` is ever reached. Settle row A7 of 0486 already showed the toolchain
# ACCEPTS it. So the clause is `<any effect> + nocancel`, not `noraise + nocancel`, and the
# 0486 implementation is a SPECIAL CASE of the real grammar.
#
# That is exactly the shape that drifts: 0486 pins `noraise` as the left operand, and the next
# increment discovers `raise` also works, so the guard changes and 0486's own M4 -- the
# `was_noraise` test -- either becomes dead or becomes the wrong half of a wider predicate.
# Settle FIRST, then re-derive which mutation is load-bearing.
#
# WHAT IS ACTUALLY UNKNOWN. 0486 established only that `noraise + nocancel` is accepted and that
# `noraise + raise` / `noraise + whatever` are refused 3002 -- i.e. the RIGHT operand is
# `nocancel` specifically. It says NOTHING about:
#
#   - whether `raise` (with or without an error type) may be the LEFT operand  [known: yes, A7]
#   - whether `!`, which 0466 settled into the SAME slot as `noraise`, may be the left operand
#   - whether the order is fixed, or `nocancel + <effect>` is also legal
#   - whether a THIRD effect may join
#   - whether the clause still requires a return annotation
#
# `!` IS THE ROW THAT MATTERS MOST. 0466's settle recorded `-> T !` ACCEPT in the same slot as
# `noraise`, so if `!` also pairs with `+ nocancel` then the left operand is a SET, and 0486's
# `was_noraise` is a one-element spelling of it.
#
# *** AN ABORT PATH THAT HAS NEVER FIRED HAS NOT BEEN TESTED. *** `ctl_must_reject` is the row
# that makes the instrument prove it can fail, and every ACCEPT row would otherwise agree with a
# compiler that is not running at all.
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
# running looks exactly like a compiler that approves the grammar.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# CONTROL 1: the single-effect spellings 0486's sibling gate 0466 already reads.
Add-Case 'ctl_single_noraise' @'
///|
fn f() -> Unit noraise {
  ()
}
'@ 'ACCEPT'

Add-Case 'ctl_single_bang' @'
///|
fn f() -> Unit ! {
  ()
}
'@ 'ACCEPT'

Add-Case 'ctl_single_raise' @'
///|
fn f() -> Unit raise MyErr {
  ()
}

suberror MyErr
'@ 'ACCEPT'

# CONTROL 2, THE REGRESSION ROW: 0486's construct. If this ever goes red, the change this settle
# is written to inform BROKE a shipped gate rather than extending it.
Add-Case 'ctl_combined_noraise_nocancel' @'
///|
fn f() -> Unit noraise + nocancel {
  ()
}
'@ 'ACCEPT'

# --- A  WHAT MAY BE THE LEFT OPERAND ------------------------------------------

# A1 THE KNOWN GAP, restated so this settle carries it rather than citing 0486's A7. A settle that
# only probes the unknown is a settle that cannot tell whether the known half moved.
Add-Case 'A1_raise_plus_nocancel' @'
///|
fn f() -> Unit raise + nocancel {
  ()
}
'@ 'RECORD'

# A2 THE ROW THAT DECIDES WHETHER THE CLAUSE IS A SET. `!` is in the same slot as `noraise`
# (settle 0466, `bang_effect` ACCEPT). If this is ACCEPT then `was_noraise` in 0486 is a
# ONE-ELEMENT SPELLING of a three-element set, and the 0487 implementation must widen it.
Add-Case 'A2_bang_plus_nocancel' @'
///|
fn f() -> Unit ! + nocancel {
  ()
}
'@ 'RECORD'

# A3 `raise` WITH AN ERROR TYPE, which is the case that actually differs from `raise` bare: 0486
# settled that `noraise` takes NO error type, so if `raise E + nocancel` also refuses a type then
# the left operand's arity is being ignored, which would be surprising and worth knowing.
Add-Case 'A3_raise_typed_plus_nocancel' @'
///|
fn f() -> Unit raise MyErr + nocancel {
  ()
}

suberror MyErr
'@ 'RECORD'

# A4 DOES THE ERROR TYPE STAY BOUND TO `raise` WHEN A SECOND EFFECT FOLLOWS? The type is
# ambiguous in the surface form: `raise MyErr + nocancel` could bind `MyErr` as the type and then
# read `+ nocancel`, or could be read as an expression. This row separates those two readings.
Add-Case 'A4_raise_typed_then_arbitrary' @'
///|
fn f() -> Unit raise MyErr + whatever {
  ()
}

suberror MyErr
'@ 'RECORD'

# --- B  IS THE ORDER FIXED ----------------------------------------------------

# B1 `nocancel` FIRST. If this is ACCEPT then the clause is a SYMMETRIC pair and 0486's
# left-operand-specific code is one of two orders that both need reading.
Add-Case 'B1_nocancel_plus_noraise' @'
///|
fn f() -> Unit nocancel + noraise {
  ()
}
'@ 'RECORD'

Add-Case 'B2_nocancel_plus_raise' @'
///|
fn f() -> Unit nocancel + raise {
  ()
}
'@ 'RECORD'

Add-Case 'B3_nocancel_plus_bang' @'
///|
fn f() -> Unit nocancel + ! {
  ()
}
'@ 'RECORD'

# --- C  CAN A THIRD JOIN ------------------------------------------------------

# C1 The chained spelling. A pair that cannot extend to a triple is a PAIR grammar, and that
# distinction decides whether the implementation is `effect (+ nocancel)?` or a loop.
Add-Case 'C1_three_effects' @'
///|
fn f() -> Unit noraise + nocancel + noraise {
  ()
}
'@ 'RECORD'

Add-Case 'C2_raise_nocancel_noraise' @'
///|
fn f() -> Unit raise + nocancel + noraise {
  ()
}
'@ 'RECORD'

# --- D  DOES THE CLAUSE STILL NEED AN ANNOTATION -----------------------------

# D1 0486 settled REJECT 4074 for the combined clause with no return annotation. If the wider
# clause drops that requirement, the annotation check is positioned differently and the fix
# cannot be a copy of 0486's.
Add-Case 'D1_no_return_annotation' @'
///|
fn f() noraise + nocancel {
  ()
}
'@ 'RECORD'

Add-Case 'D2_raise_nocancel_no_annotation' @'
///|
fn f() raise + nocancel {
  ()
}
'@ 'RECORD'

# --- E  MAY THE SECOND EFFECT CARRY AN ERROR TYPE? ---------------------------

# E1 THE ROW THAT DECIDES WHETHER `eat_joined_effect` NEEDS TO READ A TYPE. `raise` is the one
# operand with an arity of 1 or 2, so "second effect" is ambiguous: if `nocancel + raise MyErr`
# is ACCEPT then the join must read an optional error type after `raise`, and a reader that
# consumed only the two names would leave `MyErr` to be read as code -- a defect on a legal
# program, which is the wrong direction to be wrong in.
Add-Case 'E1_nocancel_plus_typed_raise' @'
///|
fn f() -> Unit nocancel + raise MyErr {
  ()
}

suberror MyErr
'@ 'RECORD'

Add-Case 'E2_noraise_plus_typed_raise' @'
///|
fn f() -> Unit noraise + raise MyErr {
  ()
}

suberror MyErr
'@ 'RECORD'

Add-Case 'E3_typed_raise_plus_typed_raise' @'
///|
fn f() -> Unit raise MyErr + raise MyErr2 {
  ()
}

suberror MyErr

suberror MyErr2
'@ 'RECORD'

# E4 THE CORPUS SHAPE, RECORDED -----------------------------------------------

# E5 The real site, which is the construct 0486 already closed. Recorded so that if the wider
# grammar ever changes THIS corpus case is re-measured rather than assumed.
Add-Case 'E5_corpus_shape' @'
///|
async fn[T] async_suspend(cb : ((T) -> Unit) -> Unit) -> T noraise + nocancel = "%async.suspend"
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0487_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  # REQUIRED. Without the `src` DIRECTORY nothing is written, `moon check` has nothing to check,
  # and every row answers ACCEPT -- which is how the first four probes of settle_0485 all read
  # ACCEPT and none of them meant anything.
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0487`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-36} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  # LOAD-BEARING. A gate that cannot fail reports the same verdict whether the grammar is legal or
  # not, and printed six MISMATCH rows into a `GATE OK` in 0485 because this line was dropped.
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
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All controls must behave.'
  Write-Output 'A red CONTROL means the fixture does not compile -- a scaffold fault, and every row'
  Write-Output 'is then agreeing for the wrong reason.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

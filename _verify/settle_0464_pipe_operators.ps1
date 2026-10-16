# Settle 0464 -- the PIPE OPERATORS: `<|`, `|>`, `<+`, `>>`.
#
# WHY. Ranking async's 61 PARTIAL files by their FIRST blocker -- not by the
# scanner's grouped message tally, which is what a first pass did and which is
# useless here because one message covers several constructs -- puts the pipe
# family at the top:
#
#     11 files   x <| f        Promise::from_async(abort_signal~) <| () => { .. }
#      2 files   x |> f        |> ignore
#      2 files   logger <+ s   logger <+ "\{k}: \{v}\n"
#      5 files   a..b()..c()   conn..send_response(400, ..)..write(msg).end_response()
#
# The lexer already has `<<`, `<=`, `..<`, `<..` and `>>`. It has no `<|` and no
# `<+`, so each of those is two tokens where MoonBit has one operator, and the
# parser then reports whatever the second token is -- which is how a pipe becomes
# "unexpected token `|`" (22 sites) rather than anything mentioning a pipe.
#
# `..` is in the same family: it is the method-CHAIN operator, and it reads as
# two `.` tokens today.
#
# THE QUESTION IS NOT "is this legal" -- the corpus is full of it and `moon check`
# compiles the corpus. The question is WHICH direction each operator reads and
# what it means, because an operator implemented with the arguments swapped is
# worse than one missing: it parses, it binds, and it is wrong.
#
# => 判据: fix the PRELUDE. Every case below is a positive control first -- a
# program that must ACCEPT for the measurement to mean anything -- and the one
# failure-capable control has to REJECT.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# THE POSITIVE CONTROL AND THE FAILURE-CAPABLE CONTROL, in one place. Without the
# first, an ACCEPT below could be an empty program. Without the second, it could
# be a parser that accepts anything.
Add-Case 'ctl_ok' @'
///|
fn inc(x : Int) -> Int {
  x + 1
}

///|
fn probe() -> Int {
  inc(1)
}
'@ 'ACCEPT'

Add-Case 'ctl_bad' @'
///|
fn probe() -> Int {
  ZzMissing
}
'@ 'REJECT'

# `<|` -- the corpus spelling. `f <| x` applies `f` to `x`.
Add-Case 'pipe_lt_apply' @'
///|
fn inc(x : Int) -> Int {
  x + 1
}

///|
fn probe() -> Int {
  inc <| 1
}
'@ 'ACCEPT'

# AND WITH A LAMBDA, which is the shape at `src/js_async/readable_stream.mbt:167`
# and 10 of the other 10 sites: `Promise::from_async(abort_signal~) <| () => { .. }`.
#
# THE FIRST DRAFT USED `() => 7` AND FAILED WITH [3002] "unexpected token integer,
# you may expect `{ ... }`". That is a fixture error and not a verdict about the
# operator: the lambda's body in this position must be a BLOCK. Exactly the shape
# the prelude rule warns about -- the probe was wrong and would have been read as
# the language.
Add-Case 'pipe_lt_lambda' @'
///|
fn apply(f : () -> Int) -> Int {
  f()
}

///|
fn probe() -> Int {
  apply <| () => { 7 }
}
'@ 'ACCEPT'

# THE MIRROR, and this is the row that SETTLES THE DIRECTION. `1 <| inc` is
# REJECT(4101) where `inc <| 1` is ACCEPT, so `<|` is one-directional:
# `f <| x` applies the LEFT to the RIGHT. An implementation that accepted both
# would be accepting code the toolchain refuses, and one that got the direction
# wrong would parse every corpus line and bind it backwards.
Add-Case 'pipe_lt_reversed' @'
///|
fn inc(x : Int) -> Int {
  x + 1
}

///|
fn probe() -> Int {
  1 <| inc
}
'@ 'REJECT'

# `|>` -- the other spelling, 2 corpus sites. And it is the MIRROR of `<|`, not a
# synonym: `inc |> 1` is REJECT(4101) for exactly the reason `1 <| inc` is.
Add-Case 'pipe_gt_reversed_dir' @'
///|
fn inc(x : Int) -> Int {
  x + 1
}

///|
fn probe() -> Int {
  inc |> 1
}
'@ 'REJECT'

Add-Case 'pipe_gt_apply' @'
///|
fn inc(x : Int) -> Int {
  x + 1
}

///|
fn probe() -> Int {
  1 |> inc
}
'@ 'ACCEPT'

# `<+` -- and the first draft GUESSED this one wrong in the most expensive
# direction. It was written as "pipe OR append" and probed with `inc <+ 1` on the
# assumption that it falls back to a pipe. The toolchain answers with [3002]
# "unexpected token integer, you may expect TEMPLATE STRING": `<+` takes strings on
# BOTH sides and is string concatenation. There is no function fallback.
#
# So the corpus line `logger <+ "\{k}: \{v}\n"` is a string build, not a pipe, and
# an implementation that had treated `<+` as a pipe variant would have parsed it
# into the wrong node -- the kind of error that passes every parse check.
Add-Case 'pipe_plus_string' @'
///|
fn probe() -> String {
  let sb = StringBuilder::new()
  sb <+ "b"
  sb.to_string()
}
'@ 'ACCEPT'

# AND `"a" <+ "b"` is REJECT(4015) where `sb <+ "b"` is the form under test, so
# `<+` is a BUILDER append rather than a `String` operator. Two guesses were wrong
# in a row here ("pipe or append", then "string concat"); only the builder form
# accepts. That is three settled fixtures in this file corrected against the
# toolchain and zero grammar claims taken from the symbol's shape.
Add-Case 'pipe_plus_not_on_string' @'
///|
fn probe() -> String {
  "a" <+ "b"
}
'@ 'REJECT'

# THE CONTROL that `+` is a separate token with separate behaviour.
Add-Case 'ctl_plus_is_not_pipe_plus' @'
///|
fn probe() -> Int {
  1 + 1
}
'@ 'ACCEPT'

# `>>` -- NOT FUNCTION APPLICATION. Both directions were measured and both fail:
# `inc >> 1` is [4014] "has type : (Int) -> Int, wanted : Int" and `1 >> inc` is
# the same class of complaint at the same position. It PARSES and the TYPES do not
# line up, so `>>` is some other operator that this increment does not need.
#
# Recorded as a REJECT-wanting case because the measurement is the useful part: it
# is the fourth time a plausible-looking reading of a symbol turned out to be a
# different construct (`b''` vs `b""`, `name(args)`, `suberror E of T`, and now
# this), and each was only caught by asking the toolchain rather than the corpus.
Add-Case 'arrow_gt_is_not_application' @'
///|
fn inc(x : Int) -> Int {
  x + 1
}

///|
fn probe() -> Int {
  inc >> 1
}
'@ 'REJECT'

# THE CHAIN OPERATOR is 5 corpus files and is DELIBERATELY NOT IN THIS SETTLE.
# `a..b()..c()` measured REJECT(0015, 4015) on a mutable Int binding, and the
# typing rules that make it legal are not yet known -- so pinning a direction
# here would be inventing the grammar rather than measuring it. It needs its own
# settle against the corpus shape
# `conn..send_response(400, "Bad Request")..write(msg).end_response()`, which is a
# struct METHOD, not a free function.
#
# => 判据: "it is in the same neighbourhood of symbols as the one I am fixing" is
# not a reason to add it to this file.

# PRECEDENCE, which is the difference between a pipe that parses and a pipe that
# is WRONG. Both rows below are arranged so the two possible readings give
# DIFFERENT numbers, because a test where both readings agree cannot settle
# anything:
#
#     2 * 3 |> inc     as (2*3) |> inc  ->  7      as 2 * (3 |> inc)  ->  8
#     2 |> inc * 3     as (2 |> inc) * 3 ->  9      as 2 |> (inc * 3)  ->  refused
#
# The first says whether the pipe binds LOOSER than arithmetic on its left. The
# second says the same on its right. Reading an operator's precedence off the
# symbol is the guess that cost this file three wrong fixtures already.
Add-Case 'prec_pipe_after_mul' @'
///|
fn inc(x : Int) -> Int {
  x + 1
}

///|
fn probe() -> Int {
  2 * 3 |> inc
}
'@ 'ACCEPT'

# AND THE MIRROR SIDE, which is where this settled the PRECEDENCE and not the
# direction. `2 |> inc * 3` is REJECT(4101, 4018, 4014), and the temptation is to
# read the 4101 as "wrong direction again". It is not: the pipe is the LOOSEST
# binary operator, so its RIGHT operand is the whole `inc * 3`, and that is a type
# error rather than a function. Read as `(2 |> inc) * 3` the row would be 9 and
# would accept.
#
# So both sides are settled together:
#
#     `2 * 3 |> inc`  ACCEPT  ->  the LEFT operand is `(2 * 3)`, not `2 * (3 |> inc)`
#     `2 |> inc * 3`  REJECT  ->  the RIGHT operand is `inc * 3`, not `inc`
#     `1 |> inc |> inc` ACCEPT -> left-associative, no parenthesising needed
#
# => the pipe is a single lowest-precedence level. An implementation that grabbed
# only the following ATOM would pass both direction rows and fail both of these,
# binding corpus code into a different tree without reporting anything wrong.
Add-Case 'prec_pipe_before_mul' @'
///|
fn inc(x : Int) -> Int {
  x + 1
}

///|
fn probe() -> Int {
  2 |> inc * 3
}
'@ 'REJECT'

# AND CHAINING, which is the corpus shape at `src/process/process.mbt:272`:
# `@async.with_task_group() <| group => { .. }` on its own line after others.
Add-Case 'pipe_chained' @'
///|
fn inc(x : Int) -> Int {
  x + 1
}

///|
fn probe() -> Int {
  1 |> inc |> inc
}
'@ 'ACCEPT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0464_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0464`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($plan) {
    $got = 'BUILD-PLAN-FAILED'
    $ok = $false
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'ACCEPT') { $ok = $false }
    elseif ($want -eq 'REJECT') { $ok = $got -like 'REJECT*' }
    else { $ok = $got -eq $want }
  } else {
    $got = 'ACCEPT'
    $ok = ($want -eq 'ACCEPT')
  }
  Write-Output ('{0,-20} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|constructor' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. ctl_ok must ACCEPT and ctl_bad must REJECT.'
  exit 1
}
Write-Output 'GATE OK. Read the ACCEPT/REJECT column: it says which spellings exist and'
Write-Output 'whether an operator is directional. That is what decides the implementation.'
exit 0

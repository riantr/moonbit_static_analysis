# Settles `async fn(..) { .. }` in EXPRESSION position for 0.4.42.
#
# WHY THIS EXISTS. After 0452 (the quoted-key map literal) moui 0.1.12 still
# cannot finish reading 9 files, and the by-reason grouping is:
#
#     4x  expected ')'      <- this one
#     3x  unexpected token `,`
#     1x  unexpected end of line
#     1x  unexpected token `:`
#
# The 4 `expected ')'` files are NOT a bracket problem. Two of them
# (backend/macos/macos_app_runtime.mbt:24, backend/linux/linux_app_runtime.mbt:22)
# stop at exactly this, and both files are byte-for-byte the same shape:
#
#     launch_async=Some(async fn(request, frame_interval_ms) {
#       ...
#     }),
#
# `expected ')'` is what the parser says AFTER it has failed to read the
# argument of `Some(` -- it is a complaint about the argument, not about the
# parenthesis. `parse_primary` has an arm for `TName("fn")` (an anonymous
# function literal) and no arm for `async`, so `async` is read as an ordinary
# name and the argument never starts. `async` is not even a lexer token: it
# arrives as `TName("async")`, and declarations already skip it in
# `skip_fn_modifiers`.
#
# The same file's `launch=request => { ... }` on the line before parses fine,
# because the SHORT LAMBDA head is recognised before the named-argument `=`
# check. So the file gets 23 good lines and then stops, which is why it is
# `PARTIAL` and not unparsed-at-zero.
#
# WHAT THIS SETTLE ANSWERS, and the row that matters most is the last one:
#
#     Some(fn(a) { 1 })      ACCEPT   <- already parsed today
#     Some(async fn(a) { 1 })  ?      <- the claim under test
#     async  as a value        ?      <- if ACCEPT, an UNGUARDED `async`
#                                       consumption in the parser is wrong
#
# That last row is the one that would otherwise be skipped. `async` looks like
# a reserved word, but "looks like" is not a measurement, and the fix consumes
# a token. If `async` can appear as an ordinary identifier, then consuming it
# wherever it is found in primary position would silently swallow a real read.
# The fix must be conditioned on `fn` following, and this settle is what makes
# that condition a measurement rather than a guess.
#
# SCAFFOLD FACTS, load-bearing, each of which has silently produced a confident
# wrong answer in this repository: `moon.mod` MUST declare `source = "src"`; a
# package cannot import its OWN root; and the output is joined with NEWLINES
# before any `(?m)` pattern is applied.

$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# POSITIVE CONTROL. A name that cannot exist must be rejected; if it is accepted,
# `moon check` is not discriminating here and every ACCEPT below proves nothing.
Add-Case 'ctl_missing' @'
///|
fn probe() -> Int {
  ignore(ZzMissing)
  0
}
'@ 'REJECT'

# THE DISCRIMINATION PAIR. Identical shape, `async` is the ONLY difference.
# This is the row the 4 files turn on, and the one that says whether the
# missing arm is about `async` or about the argument position.
#
# NO return type is written on `probe`, and that is deliberate rather than lazy:
# the first run of this settle annotated it `-> Option[Int]` and every row came
# back REJECT(4014) "Type Mismatch / has type: function type / wanted: Int" --
# a complaint about MY annotation, not about the construct. Inference is what
# lets the fixture state only the shape under test.
Add-Case 'fn_literal_in_some' @'
///|
fn probe() -> Unit {
  ignore(Some(fn(a) { a + 1 }))
}
'@ 'ACCEPT'

Add-Case 'async_fn_in_some' @'
///|
fn probe() -> Unit {
  ignore(Some(async fn(a) { a + 1 }))
}
'@ 'ACCEPT'

# THE CORPUS DECLARATION, verbatim in shape: a short-lambda named argument that
# this parser already handles, immediately followed by a NAMED argument whose
# value is `Some(async fn(..) { .. })`. Both together, because the first is
# what makes the second's failure look like a bracket problem -- 23 lines of
# good parse, then the stop.
#
# The CALLEE IS GENERIC (`fn[A, B]`), and that is a decision, not a dodge. The
# first three attempts at this row all failed on MY type annotation rather than
# on the syntax under test:
#
#   launch_async~ : Option[(Int, Int) -> Int]        -> 4118 "error type is
#       mismatched: wanted no error, has Error (implicitly implied by `async`)"
#   ... -> Error!Int                                 -> 4127 "Type Int is not an
#       error type" + a deprecation warning for the `!Err` spelling
#   ... -> raise Int                                 -> 3002 "unexpected token
#       `raise`, you may expect type"
#
# The toolchain kept naming the construct's type back at me, which is a
# question about TYPING, and this settle is about whether the SYNTAX is legal.
# Type parameters let the fixture state the shape and nothing else.
Add-Case 'corpus_declaration_shape' @'
///|
fn[A, B] build(launch~ : A, launch_async~ : B) -> Unit {
  ignore(launch)
  ignore(launch_async)
}

///|
fn probe() -> Unit {
  build(
    launch=(a : Int, b : Int) => a + b,
    launch_async=Some(async fn(request : Int, frame_interval_ms : Int) {
      request + frame_interval_ms
    }),
  )
}
'@ 'ACCEPT'

# `async` as an ordinary value. THE ROW THAT DECIDES THE FIX.
# Measured: "Parse error, unexpected token `)`, you may expect `fn`" -- so the
# grammar binds `async` to `fn` and to nothing else. `async` cannot be a value.
# That does NOT make an unconditional consumption safe (it makes it untested),
# and the parser still has to be conditioned on the following token, because a
# rule justified by "no valid input looks like this" is exactly the rule that
# one day meets one.
Add-Case 'async_as_plain_value' @'
///|
fn probe() -> Int {
  ignore(async)
  0
}
'@ 'REJECT'

# `async` applied to a call. Same message: `async` is only ever followed by
# `fn`. This is the production an over-eager "async starts something" rule
# would wrongly invent.
Add-Case 'async_call_form' @'
///|
fn work() -> Int {
  1
}

///|
fn probe() -> Int {
  async work()
}
'@ 'REJECT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0453_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0453`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') |
    ForEach-Object { $_.Groups[1].Value })
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
  Write-Output ('{0,-26} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. A BUILD-PLAN-FAILED row means the scaffold is wrong and NOTHING here'
  Write-Output 'is an answer. A `ctl_*` row reading ACCEPT means `moon check` is not'
  Write-Output 'discriminating and the ACCEPT rows beside it prove nothing.'
  exit 1
}
Write-Output 'GATE OK: an anonymous async function literal is a legal expression, and so'
Write-Output 'is the corpus declaration with it as a named-argument value. The plain `fn`'
Write-Output 'form beside it is the shape this parser already reads, so the missing arm is'
Write-Output 'about `async`, not about the argument position.'
Write-Output 'Read `async_as_plain_value` above before writing the fix: it decides whether'
Write-Output '`async` must be consumed only when `fn` follows.'
exit 0

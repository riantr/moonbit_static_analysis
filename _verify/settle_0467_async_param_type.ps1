# Settle 0467 -- the `async (..)` TYPE in PARAMETER position.
#
# WHY THIS IS NEXT, measured rather than remembered. Re-ranked per-FILE FIRST BLOCKER
# on the tree that shipped as 12b38a3 (0466): 57 unread files, 40 async + 17 proton,
# bucketed by shape with every member printed (`_verify/rank_0467_shapes.ps1`):
#
#     async_param_type    19 files   <- THIS ONE, 11 async + 8 proton
#     for_brace_header    13 files
#     annotated_let        5 files
#     struct_pat_rest      2 files
#     let_destructure      1 file
#     OTHER               17 files
#
# 0466's own settle named this as the blocker it was deferring:
#
#   "The param form is NOT included: its corpus lines are
#    `handler : async (A, B) -> Unit noraise,`, which also needs the `async (..)` TYPE
#    -- a different construct with its own settle. Shipping both under one commit
#    would measure a fix on half the work."
#
# So this is a strict DEPENDENCY, not merely a bigger number: the effect-in-param-position
# files cannot land until the `async (..)` type parses, because in all of them the effect
# hangs off an async type in a parameter annotation.
#
# THE CORPUS SPELLINGS, which the rows below are written against:
#
#     async   src/task_group.mbt:50            f : async () -> Unit,
#     async   src/socket/tcp.mbt:143           f : async (Tcp, Addr) -> Unit,
#     async   src/fs/dir.mbt:433               f : async (String, Array[String]) -> Unit,
#     async   src/http/server.mbt:294          f : async (Request, &@io.Reader, ServerConnection) -> Unit,
#     async   src/lazy_init.mbt:95             f : async () -> X,
#     proton  core/app_command_host.mbt:37     d : async (String?, String, String) -> Unit,
#     proton  facade_context.mbt:137           e : async (@proton_contract.ContractRoute, String, Json) -> Unit noraise,
#     proton  updater/channel.mbt:190          c : async (Bytes) -> Unit raise UpdateError,
#     proton  facade_updater.mbt:142           p? : async (Int64) -> Unit noraise = _ => (),
#
# => the expectations on rows UNDER TEST are 'MEASURE' where the answer is genuinely
# unknown, and asserted ACCEPT/REJECT only where the corpus already proves it or where a
# control has to be able to fail. A settle that asserts what I already believe cannot
# tell me I was wrong. `moon check` is the authority here, not this parser -- the rows
# record what the TOOLCHAIN accepts, and the parser is then made to match.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS ------------------------------------------------------------------
# 1: the package must be able to ACCEPT something, or every ACCEPT below is vacuous.
Add-Case 'ctl_ok' @'
///|
fn f() -> Int {
  1
}
'@ 'ACCEPT'

# 2: `moon check` must be able to REJECT, or this is a checker that accepts everything.
Add-Case 'ctl_bad' @'
///|
fn f() -> Int {
  ZzMissing
}
'@ 'REJECT'

# 3: `async fn` already works (0457). Carries NO async TYPE, so it is the control that
# the rows below are about the TYPE and not about the keyword.
Add-Case 'ctl_async_fn' @'
///|
async fn f() -> Unit {
  ()
}
'@ 'ACCEPT'

# 4: an async TYPE in RETURN position already works. If this ever REJECTs, the `..` work
# or 0466 regressed on a construct that was already landing files.
#
# FIXTURE BUG, caught by this row and worth recording: the first version was
# `let g = async fn (x : Int) { x }` typed `async (Int) -> Unit`, and it REJECTed 4014.
# That is NOT a grammar refusal -- the toolchain said, in full,
#     has type : async (Int) -> Int
#     wanted  : async (Int) -> Unit
# which means it PARSED the async type, INFERRED it, and compared it. A lambda returning
# its argument is an `Int`. The row was measuring my fixture, not the grammar.
Add-Case 'ctl_async_return_type' @'
///|
fn f() -> async (Int) -> Unit {
  let g = async fn (x : Int) { () }
  g
}
'@ 'ACCEPT'

# 5: the plain function TYPE in a parameter, no `async` in front. The plain row is the
# control that a parser which "handles async parameter types" did so by widening the
# function-type rule rather than by adding a keyword branch.
Add-Case 'ctl_plain_fn_param' @'
///|
fn f(g : (Int) -> Unit) -> Int {
  1
}
'@ 'ACCEPT'

# --- THE CORPUS SPELLINGS -------------------------------------------------------
# Empty argument list -- `async () -> Unit`, the single most common corpus shape
# (task_group, event_loop, lazy_init, js_async, install_wbtest).
Add-Case 'p_empty_args' @'
///|
fn f(g : async () -> Unit) -> Int {
  1
}
'@ 'MEASURE'

# One argument.
Add-Case 'p_one_arg' @'
///|
fn f(g : async (String) -> Unit) -> Int {
  1
}
'@ 'ACCEPT'

# Two arguments. This is the row that a `[^,]`-style character class silently fails on,
# which is why the multi-argument forms are in the settle rather than assumed from the
# single-argument one.
Add-Case 'p_two_args' @'
///|
fn f(g : async (Int, Int) -> Unit) -> Int {
  1
}
'@ 'ACCEPT'

# A generic argument -- `Array[String]`, the corpus shape at src/fs/dir.mbt:433.
Add-Case 'p_generic_arg' @'
///|
fn f(g : async (String, Array[String]) -> Unit) -> Int {
  1
}
'@ 'MEASURE'

# A mutable EXTERNAL-reference argument -- `&@io.Reader`, src/http/server.mbt:294. If
# `&@` is not itself legal in an async argument list this REJECTs and the row is wrong.
Add-Case 'p_extern_mut_arg' @'
///|
fn f(g : async (Int, &Int) -> Unit) -> Int {
  1
}
'@ 'MEASURE'

# An OPTIONAL argument type -- `String?`, proton core/app_command_host.mbt:37.
Add-Case 'p_optional_arg' @'
///|
fn f(g : async (Int?, Int, Int) -> Unit) -> Int {
  1
}
'@ 'MEASURE'

# THE EFFECT, on an async type in a parameter. proton facade_context.mbt:137.
Add-Case 'p_effect_noraise' @'
///|
fn f(g : async (Int) -> Unit noraise) -> Int {
  1
}
'@ 'MEASURE'

# THE EFFECT WITH AN ERROR TYPE. `raise` is the one effect that names one -- 0466 settled
# that `noraise`/`nocancel` take none and `raise` takes one. proton updater/channel.mbt:190
# has BOTH on one parameter, so this row is where the two settle results have to compose.
Add-Case 'p_effect_raise_type' @'
///|
fn f(g : async (Int) -> Unit raise MyErr) -> Int {
  1
}

///|
priv struct MyErr
'@ 'MEASURE'

# AN OPTIONAL PARAMETER WITH A DEFAULT -- `p? : async (Int64) -> Unit noraise = _ => ()`,
# proton facade_updater.mbt:142. Three things at once: the type, the effect, a default.
Add-Case 'p_default' @'
///|
fn f(g? : async (Int) -> Unit = _ => ()) -> Int {
  1
}
'@ 'MEASURE'

# --- CANARIES -------------------------------------------------------------------
# The slot is a KEYWORD, not "consume whatever name is followed by a parenthesised
# list". If this ACCEPTs, any parser reading `name ( .. ) -> T` as an async type would
# accept a program the toolchain refuses -- the same shortcut 0466's canary forbids.
Add-Case 'canary_any_name' @'
///|
fn f(g : bogus (Int) -> Unit) -> Int {
  1
}
'@ 'REJECT'

# A bare `async` with no argument list and no return type. If the grammar is "async"
# followed by an optional `( .. )` this ACCEPTs; if `( .. )` is REQUIRED it REJECTs, and
# that decides whether the parser needs a fallback arm.
Add-Case 'canary_bare_async' @'
///|
fn f(g : async) -> Int {
  1
}
'@ 'MEASURE'

# --- THE NEIGHBOURS THAT MUST NOT BREAK ----------------------------------------
# An async declaration next to an ordinary one. This row's first version CALLED the
# `async fn` from a plain `fn`, and REJECTed 4122/4149 -- which is the toolchain saying
# "you cannot call an async function from a synchronous context", which is a fact about
# CALLING and not about the type at all. Declared, not called.
Add-Case 'ctl_method_after_async' @'
///|
async fn f() -> Unit {
  ()
}

///|
fn g() -> Unit {
  ()
}
'@ 'ACCEPT'

# The async type as a STANDALONE binding, not a parameter. Not called, for the same
# reason the row above stopped calling: a synchronous call site would report the CALL.
Add-Case 'p_standalone_type' @'
///|
fn f() -> Unit {
  let g : async (Int) -> Unit = async fn (x : Int) { () }
  ignore(g)
}
'@ 'MEASURE'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0467_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0467`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
    else { $ok = $true }   # MEASURE
  } else {
    $got = 'ACCEPT'
    $ok = ($want -ne 'REJECT')
  }
  $tag = $(if ($want -eq 'MEASURE') { 'measured' } elseif ($ok) { 'OK' } else { '*** MISMATCH ***' })
  Write-Output ('{0,-22} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $tag)
  # Only an ASSERTED row counts toward the verdict. A MEASURE row that rejects is a
  # RESULT, not a failure -- and folding it into `$fail` (which the first version of
  # this block did, by widening the same `if`) reported "GATE FAILED: 3" on three rows
  # whose expectation was deliberately MEASURE.
  if (-not $ok) { $fail++ }
  # A MEASURE row that REJECTs is the interesting half of a measure: the code tells me
  # nothing about WHY, and 4127 or 4100 names neither the construct nor the rule. Print
  # its body too, or a measured rejection is a number with no reading.
  if ((-not $ok) -or (($want -eq 'MEASURE') -and ($got -ne 'ACCEPT'))) {
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        # Print the WHOLE error block, unfiltered. The first version of this filter
        # selected on `╰──`, `╭─` and `│` to catch the pretty diagnostic -- and a
        # BOM-less .ps1 is read as ANSI on this machine, so those characters came back
        # mangled and unterminated the string, which took the whole script down with a
        # parser error pointing at a `Write-Output` three lines away. Non-ASCII does not
        # go in a pattern here. 16 lines covers a diagnostic block; blanks are dropped so
        # the output stays readable.
        ($lines[$j..([Math]::Min($j + 16, $lines.Count - 1))] |
          Where-Object { $_ -and $_.Trim().Length -gt 0 }) |
          ForEach-Object { Write-Output ('      ' + $_.TrimEnd()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'GATE OK -- controls held (ctl_ok ACCEPT, ctl_bad REJECT, canary_any_name REJECT).'
} else {
  Write-Output ("*** GATE FAILED: $fail asserted row(s) did not hold. Rows under test are not evidence until the controls hold. ***")
}
exit $fail

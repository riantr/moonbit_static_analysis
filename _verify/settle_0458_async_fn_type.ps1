# Settle 0458 -- the ASYNC FUNCTION TYPE.
#
# THE BLOCKER. wzzc-dev/moui 0.1.12 `runtime/app_builder.mbt:40,47`, 4 sites over
# 2 files (one of them a .mbti, so exactly ONE .mbt file). It is the last file
# moui cannot finish reading:
#
#     PARTIAL  .mbt  defects=0 notices=2  read up to line 47, 9 after it not shown
#
# Line 47, verbatim:
#
#     launch_async? : (async (AppLaunchRequest, Int) -> Unit)? = None,
#
# and the analyzer reports `expected ')'`.
#
# WHY LINE 40 IS NOT EVIDENCE THAT THE TYPE ALREADY PARSES. The same type is
# written at line 40, inside a `struct` body, and struct bodies are skipped
# WHOLESALE. Line 40 was never parsed, so it cannot testify that the reader
# handles this type.
#
# => 判据: "this construct already parses elsewhere in the file" is evidence only
# if you can show the reader REACHED the other occurrence. Two identical
# constructs at different depths can sit on opposite sides of a skipped region,
# and only the one the reader entered can be a witness.
#
# ---------------------------------------------------------------------------
# THE GRAMMAR FACT, which is not the obvious reading of the source text.
#
# `(async (Int, Int) -> Unit)?` is NOT an optional async function. The toolchain
# reads it as
#
#     async (Int, Int) -> Unit?
#
# The trailing `?` makes the RETURN TYPE optional. Measured, not inferred, from
# three agreeing rows:
#
#     fn build(f? : ((Int) -> Unit)? = None)          ACCEPT
#         ... called with `fn(a) { ... }`             wanted: (Int) -> Unit?
#     fn build(f? : ((Int) -> Unit)  = None)          REJECT(4014)
#     fn build(launch_async? : (async (Int, Int) -> Unit)? = None)   ACCEPT
#
# So the `?` lands on `Unit`, and the whole parenthesised group is NOT lifted into
# a nullable function type. Three fixture errors hid this at first, and all three
# read as verdicts about the grammar before they were found to be about MY code:
#
#   1. `f? : (Int) -> Unit = None` -- an optional PARAMETER whose type is not
#      optional, defaulted to `None`. Rejected on the default, not the type.
#      An optional parameter `x?` and a nullable type `T?` are different things
#      and the corpus line has BOTH.
#   2. `f? : ((Int) -> Unit)? = None` called with a lambda returning `Unit` --
#      the wanted type was `(Int) -> Unit?`, i.e. returns-optional.
#   3. an `async fn` literal passed where `async (Int, Int) -> Unit?` was wanted.
#
# The first draft of this settle put a CALL in every fixture, so all three errors
# landed on call sites and none of them was about the annotation. The rows below
# are declarations only, which is the thing actually in question: whether the type
# ANNOTATION is legal. `moon check` reports unused-value warnings for a
# never-called function, and warnings are not verdicts here -- only `Error:` lines
# are read.
#
# `ctl_plain_no_question_mark` is the row that makes the ACCEPTs informative: it
# is the same declaration with the `?` deleted, and it REJECTs. Without a control
# that can fail, "the optional rows accept" could be a fact about the fixture.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# THE CANARY. A name that cannot exist. If this ACCEPTs, every ACCEPT below is
# decoration.
Add-Case 'ctl_missing' @'
///|
fn probe() -> Int raise {
  ignore(ZzMissing)
  0
}
'@ 'REJECT'

# THE ROW THE INCREMENT STANDS ON: the corpus shape, an async function type whose
# return type is optional, on an optional parameter defaulted to `None`.
Add-Case 'async_optional_param' @'
///|
fn build(
  launch_async? : (async (Int, Int) -> Unit)? = None,
) -> Unit {
  ignore(launch_async)
}
'@ 'ACCEPT'

# LINE 40'S SHAPE: the same type as a struct FIELD. A separate question from a
# parameter, because struct fields carry their own optionality rules.
Add-Case 'async_field' @'
///|
struct PlatformEntry {
  id : String
  launch_async_fn : (async (Int, Int) -> Unit)?
}

///|
fn use_it(e : PlatformEntry) -> Unit {
  ignore(e.id)
}
'@ 'ACCEPT'

# BARE: the same type with no trailing `?`. Without it, the fix might add the
# return-optional form while dropping the plain one.
Add-Case 'async_bare_field' @'
///|
struct Holder {
  f : (async (Int, Int) -> Unit)
}

///|
fn use_it(h : Holder) -> Unit {
  ignore(h.f)
}
'@ 'ACCEPT'

# THE NON-ASYNC CONTROL. Same wrapper shape, ordinary function type. It must
# ACCEPT, and it is what lets an async rejection be attributed to `async` rather
# than to the optional machinery.
Add-Case 'plain_optional_param' @'
///|
fn build(
  f? : ((Int) -> Unit)? = None,
) -> Unit {
  ignore(f)
}
'@ 'ACCEPT'

# THE CONTROL THAT CAN FAIL. Identical to the row above with the `?` deleted, so
# the default `None` no longer matches. If this ACCEPTed, the ACCEPT rows would be
# saying nothing about optionality at all.
Add-Case 'ctl_plain_no_question_mark' @'
///|
fn build(
  f? : ((Int) -> Unit) = None,
) -> Unit {
  ignore(f)
}
'@ 'REJECT'

# The CONTROL that keeps `async` honest in the other direction: `async` is a
# keyword and cannot be a bare function type with no argument list.
Add-Case 'ctl_async_no_args' @'
///|
struct Holder {
  f : async Unit?
}
'@ 'REJECT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0458_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0458`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-28} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 10, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|wanted|has type' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the grammar. The canary must REJECT, and so must'
  Write-Output '`ctl_plain_no_question_mark` -- if the optional wrapper is inert then its ACCEPT'
  Write-Output 'rows say nothing about this grammar.'
  exit 1
}
Write-Output 'GATE OK: the async function type is legal MoonBit, bare and with an optional'
Write-Output 'return type, as a parameter and as a struct field. AND the trailing `?` makes the'
Write-Output 'RETURN type optional -- it does not lift the group into a nullable function -- so a'
Write-Output 'parser fix has to read `(async (A, B) -> R)?` as `async (A, B) -> R?`.'
Write-Output '`expected )` at `app_builder.mbt:47` is therefore a parser defect.'
exit 0

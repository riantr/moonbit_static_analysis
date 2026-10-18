# Settle 0481 -- a NESTED optional type, `-> String??`.
#
# WHY. After 0480 proton is 136/137, and the one file left is
# `internal/native/types.mbt`, reported as `unexpected token ':'` and PARTIAL -- "read up to
# line 1351, 31 after it not shown". Line 1351 is:
#
#     pub fn RuntimeEvent::notification_click(self : RuntimeEvent) -> String?? {
#       match self {
#         NotificationClicked(payload) => Some(payload)
#         _ => None
#       }
#     }
#
# `String??` is `Option<Option<String>>`, and it is the ONLY doubly-optional type in the pinned
# corpora. It is worth one grammar clause: it closes proton entirely at 137/137, and the
# operator itself is not exotic -- an optional wrapping an optional.
#
# THE ERROR MESSAGE IS NOT THE ERROR. The report says `unexpected token ':'` and the line
# contains exactly one colon, in `self : RuntimeEvent`, eight tokens before the `??`. That is
# a report landing somewhere other than the thing that is wrong, so it is worth saying now:
# the reader is not confused at the colon, and chasing the reported token would mean fixing
# labelled parameters, which work. WHERE it goes wrong is in the type reader, and the settle
# below is what says which shapes are legal.
#
# SCAFFOLD NOTES, CARRIED FROM 0479. Every row writes `src/moon.pkg`, because a project
# without a package inside its source directory is not a package: `moon check` prints "no
# work to do", exits 0, and every row reads ACCEPT. `ctl_must_reject` proves the INSTRUMENT
# can fail, and "no work to do" is matched by name.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
Add-Case 'ctl_plain_return' @'
///|
fn f() -> String {
  ""
}
'@ 'ACCEPT'

# ctl_must_reject proves the INSTRUMENT can fail. Every other row here wants ACCEPT, so a
# compiler that is not running looks exactly like a compiler that approves the corpus.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# ctl_labelled_param is the CONTROL FOR THE ERROR MESSAGE. The NOTPARSE reason is
# `unexpected token ':'` and `self : RuntimeEvent` is the only colon on the line, so the
# first thing to rule out is that labelled parameters are somehow implicated. They are not,
# and this row is what says so rather than my assuming it.
Add-Case 'ctl_labelled_param' @'
///|
fn f(self : String) -> Unit {
  ignore(self)
}
'@ 'ACCEPT'

# --- S1  ONE `?` IS THE ORDINARY CASE ------------------------------------------
# Nothing about nesting can be settled without the unnested form being pinned first: a
# reader that simply stops consuming `?` after the first one would pass S1 and every other
# row here, and would show up only in the corpus.
Add-Case 'S1_single_optional' @'
///|
fn f() -> String? {
  Some("")
}
'@ 'ACCEPT'

# --- S2  THE PROTON SHAPE ------------------------------------------------------
# `-> String??` returning `Some(payload)` or `None`. The outer `?` is satisfied by `None`
# and the inner by the payload, so the body is what a reader has to keep consistent.
Add-Case 'S2_return_double_optional' @'
///|
fn f() -> String?? {
  Some(None)
}
'@ 'ACCEPT'

# --- S3  A PARAMETER, NOT A RETURN ---------------------------------------------
# The parser has more than one place to read a type, and a rule that holds only after `->`
# is a rule that half the grammar does not have. proton's own line is a RETURN, so without
# this row the corpus would never ask the parameter question.
Add-Case 'S3_param_double_optional' @'
///|
fn g(x : String??) -> Unit {
  ignore(x)
}
'@ 'ACCEPT'

# --- S4  A LET ANNOTATION ------------------------------------------------------
# A third site, and the one with no `->` and no parentheses at all.
Add-Case 'S4_let_double_optional' @'
///|
fn f() -> Unit {
  let x : String?? = Some(None)
  ignore(x)
}
'@ 'ACCEPT'

# --- S5  THREE OF THEM ---------------------------------------------------------
# The boundary. `Option<Option<Option<String>>>` is legal MoonBit or it is not, and the
# corpus cannot say: it has exactly one doubly-optional type and no triply-optional one.
# RECORDED, because a reader that stops at two is as wrong as a reader that stops at one,
# and only the toolchain can settle how many.
Add-Case 'S5_return_triple_optional' @'
///|
fn f() -> String??? {
  Some(Some(None))
}
'@ 'RECORD'

# --- S6  A BARE `?` WITH NOTHING TO WRAP ---------------------------------------
# This row is MISLABELLED IN ITS FIRST DRAFT and the run below is what caught it. It was
# written as "a bare `?` with nothing to wrap" and written as `-> Int?` with a body of
# `ignore(1)`, which measures nothing about a bare `?`: it REJECTs 4014 because the body
# yields Unit where the annotation promises `Int?`. That is a type error in the BODY and says
# nothing about nesting.
#
# It is kept rather than deleted, because a row that measures the wrong thing is worth having
# if its label says so -- and 4014 here is the reader correctly noticing that a return type and
# a body disagree, which is a different property entirely from the one the name claimed. A
# genuinely bare `-> ?` is left unanswered; the corpus has no instance of it and inventing a
# fixture for it would have been the better thing to do before the fact rather than after.
Add-Case 'S6_body_disagrees_with_optional_return' @'
///|
fn f() -> Int? {
  ignore(1)
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0481_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0481`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # REQUIRED. A MoonBit project with no package inside its source directory is not a
  # package, and `moon check` says "no work to do" and exits 0 -- which every ACCEPT row
  # would read as a pass.
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
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
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All three controls must behave.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

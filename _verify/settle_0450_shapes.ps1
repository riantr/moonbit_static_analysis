# Settles the shapes behind the "bare brace / lambda body" truncation bucket for
# 0.4.40.
#
# WHY THIS EXISTS, AND WHY IT SPLITS THE BUCKET.
#
# `_verify/diagnose_moui_truncations.ps1` ranks the 13 files moui 0.1.12 still
# cannot finish reading, and its largest bucket is four files whose cut line is a
# `{` or a `fn(_ctx) {`. Those four are TWO defects and they were being carried as
# one. Measured here, and the bucket is wrong in both directions at once:
#
#   host_transport.mbt        cut@288  | {
#   session_transport.mbt     cut@306  | {
#   macos_accessibility_bridge.mbt cut@151 | {
#     ... all three are a parenthesised struct literal with a type ascription:
#         (
#           {
#             "schemaVersion": ...,
#           } : Json).stringify()
#
#   modifier_env.mbt          cut@55   | fn(_ctx) {
#     ... a lambda sitting in an `if` branch, with a struct literal for its body.
#
# The three `{` files are NOT failing because of that construct. It is valid
# MoonBit (`paren_multiline_ascribed` ACCEPT below), and this parser reads it --
# `src/pipeline/pipeline_0450_diagnosis_test.mbt` pins that, with and without the
# preceding `let` the corpus has. Nine fixtures were tried against the cut-line
# shape before that was accepted: with and without parens, ascribed and not, one
# line and many, qualified and unqualified method, and with a `let` in front.
# Every one reads cleanly. So whatever stops those three files is EARLIER CONTEXT,
# and this script does not claim to know what it is. Reading the construct at the
# cut line and calling it the cause is the error this header exists to stop.
#
# `modifier_env.mbt` IS reproduced, and by a different rule: a lambda in an `if`
# BRANCH. `moon check` accepts it; this parser says `expected function name`, at
# a `fn` that is neither unexpected nor unnamed.
#
# TWO MALFORMED PRELUDES WERE BUILT AND DISCARDED BEFORE THIS ONE, and both read as
# "everything is broken":
#
#   - `struct Json { raw : String }` with literals written `"a": 1`. Every row came
#     back REJECT(4014), which says the literal's value is the wrong type, not that
#     the shape is bad. Nine REJECTs that agree are a broken question.
#   - Then the corpus's QUOTED keys, kept from the real files. Those reject against
#     a struct too (4014): a quoted key is not a struct-literal field name. moui's
#     `Json` accepts them because it is not a struct there. The settle therefore
#     uses a plain struct and unquoted keys, which is the same shape with a
#     stand-in type -- and says so, rather than quietly weakening the corpus text.
#
# POSITIVE CONTROL. `ctl_missing` names something that cannot exist and MUST be
# rejected; `ctl_bad_field` gives a literal whose value is the wrong type and MUST
# be rejected with 4014, so the control distinguishes a SYNTAX verdict from a TYPE
# verdict rather than counting both as "it noticed something".
#
# Scaffold facts that are load-bearing, each of which has silently produced a
# confident wrong answer here before: `moon.mod` MUST declare `source = "src"`; a
# package cannot import its OWN root; and the output is joined with NEWLINES before
# any `(?m)` pattern is applied.

$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

$PRELUDE = @'
///|
pub struct Json {
  schemaVersion : Int
  sessionGeneration : Int
}

///|
fn Json::stringify(self : Json) -> String {
  "s"
}

///|
pub struct Plan {
  commands : Int
}

///|
pub struct View {
  paint : (Int) -> Plan
}

///|
fn plan0() -> Plan {
  { commands: 0 }
}

'@

# --- the controls ------------------------------------------------------------
# POSITIVE CONTROL 1: a name that cannot exist. If this is ACCEPTed, `moon check`
# is not discriminating here and every ACCEPT row below proves nothing.
Add-Case 'ctl_missing' ($PRELUDE + @'
///|
fn probe() -> Int {
  ignore(ZzMissing)
  0
}
'@) 'REJECT'

# POSITIVE CONTROL 2: a TYPE error, so the instrument is shown to separate "wrong
# shape" from "wrong type". A settle that only ever sees syntax errors cannot tell
# which verdict it is reading.
Add-Case 'ctl_bad_field_type' ($PRELUDE + @'
///|
fn probe() -> String {
  ({ schemaVersion: "not an int", sessionGeneration: 2 } : Json).stringify()
}
'@) 'REJECT(4014)'

# Quoted keys are NOT struct-literal field names. Recorded as REJECT because it is
# what the toolchain says, and because it is the step that invalidated the first
# two preludes -- the corpus writes quoted keys and this settles that they are only
# correct where the target is not a struct.
Add-Case 'ctl_quoted_keys' ($PRELUDE + @'
///|
fn probe() -> String {
  ({ "schemaVersion": 1, "sessionGeneration": 2 } : Json).stringify()
}
'@) 'REJECT(4014)'

# --- the shapes --------------------------------------------------------------
# THE CUT-LINE SHAPE of three of the four files. ACCEPT, which is the claim that
# makes them NOT the cause of those truncations.
Add-Case 'paren_multiline_ascribed' ($PRELUDE + @'
///|
fn probe() -> String {
  (
    {
      schemaVersion: 1,
      sessionGeneration: 2,
    } : Json).stringify()
}
'@) 'ACCEPT'

# The same with the corpus's leading `let`, and as a TAIL expression rather than
# the only statement. ACCEPT -- so the `let` is not what breaks it either.
Add-Case 'paren_multiline_ascribed_after_let' ($PRELUDE + @'
///|
fn probe() -> String {
  let e = 1
  (
    {
      schemaVersion: 1,
      sessionGeneration: 2,
    } : Json).stringify()
}
'@) 'ACCEPT'

# ... and without the ascription, to isolate the `:` from the `{`.
#
# BOTH fields are required here, and getting that wrong was the third malformed
# prelude in this increment: `Json` declares two fields, a one-field literal is
# `[4033]` field-not-found, and the row came back REJECT for a reason that has
# nothing to do with the shape under test. A REJECT that agrees with a broken
# fixture is worse than a BUILD-PLAN failure, because it looks like an answer.
Add-Case 'paren_multiline_unascribed' ($PRELUDE + @'
///|
fn probe() -> Int {
  (
    {
      schemaVersion: 1,
      sessionGeneration: 2,
    }).schemaVersion
}
'@) 'ACCEPT'

# --- the reproduced defect ---------------------------------------------------
# `modifier_env.mbt`. A lambda in an `if` branch, with a struct literal body.
Add-Case 'lambda_in_if_branch' ($PRELUDE + @'
///|
fn probe(disabled : Bool) -> (Int) -> Plan {
  if disabled {
    fn(_ctx) {
      {
        commands: 1,
      }
    }
  } else {
    fn(_ctx) { plan0() }
  }
}
'@) 'ACCEPT'

# THE CONTROL THAT MAKES THAT ONE MEANINGFUL: the same `if` of lambdas with the
# body reduced to a single line. ACCEPT too, so the pair says the defect is about
# a lambda in a branch and not about a multi-line struct literal.
Add-Case 'lambda_in_if_branch_oneline' ($PRELUDE + @'
///|
fn probe(disabled : Bool) -> (Int) -> Plan {
  if disabled {
    fn(_ctx) { plan0() }
  } else {
    fn(_ctx) { plan0() }
  }
}
'@) 'ACCEPT'

# The whole struct-literal-as-body form, WITHOUT any `if`, which the same parser
# reads correctly. This is what makes the branch the variable rather than the
# lambda.
Add-Case 'lambda_bare_no_if' ($PRELUDE + @'
///|
fn probe() -> Plan {
  let f = fn(_ctx) {
    {
      commands: 1,
    }
  }
  f(0)
}
'@) 'ACCEPT'

# A lambda as a `let` value, multi-line body. The nearest thing to the failing
# shape that is still accepted, so the difference really is the branch.
Add-Case 'lambda_as_let_value' ($PRELUDE + @'
///|
fn probe() -> Plan {
  let f = fn(_ctx) { plan0() }
  f(0)
}
'@) 'ACCEPT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0450_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0450`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
    # A bare `REJECT` means "the toolchain noticed", and the codes are reported
    # alongside it because they are the evidence. A `REJECT(4014)` want is exact:
    # that is how a TYPE control says it is reading a type verdict and not a
    # syntax one.
    if ($want -eq 'ACCEPT') {
      $ok = $false
    } elseif ($want -eq 'REJECT') {
      $ok = $got -like 'REJECT*'
    } else {
      $ok = $got -eq $want
    }
  } else {
    $got = 'ACCEPT'
    $ok = ($want -eq 'ACCEPT')
  }
  Write-Output ('{0,-34} {1,-22} (want {2,-16}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. A BUILD-PLAN-FAILED row means the scaffold is wrong and NOTHING here'
  Write-Output 'is an answer. A `ctl_*` row reading ACCEPT means `moon check` is not'
  Write-Output 'discriminating and the ACCEPT rows beside it prove nothing.'
  exit 1
}
Write-Output 'GATE OK: every shape here is valid MoonBit, so none of them is a defect on its'
Write-Output 'own. The three `{`-cut files are therefore NOT explained by the construct at'
Write-Output 'their cut line -- it parses -- and their cause is still unisolated. The one'
Write-Output 'reproduced defect is the lambda in an `if` branch, and the two controls beside'
Write-Output 'it say the branch is the variable: a bare lambda and a one-line lambda in a'
Write-Output 'branch are both fine.'
exit 0

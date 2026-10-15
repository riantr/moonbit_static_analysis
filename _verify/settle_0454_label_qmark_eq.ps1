# Settles `label?=value` in a CALL ARGUMENT for 0.4.43.
#
# WHY THIS EXISTS. After 0453 moui 0.1.12 still cannot finish reading 6 files, and
# the largest by-reason bucket is `unexpected token `,``. Three of them are one
# construct -- `views/popover/sheet.mbt:25`, and
# `backend/host_text_field_test_helper_test.mbt:31` and
# `backend/common/input/text_field_test_helper_test.mbt:31`, which are the same
# helper written twice:
#
#     let normal = @views.new_control_state_style(
#       foreground=@core.Color::black(),
#       border?=normal_border,
#       radius=0.0,
#     )
#
# WHAT THE PARSER DOES WITH IT, and this is the diagnosis rather than a guess.
# `parse_call_args` already has TWO shorthands, both handled AFTER the argument is
# parsed: `f(x~)` at the `TTilde` test and `f(x?)` at the `TQuestion` test, each
# recording the label from `name_at(arg_start)`. Neither is followed by an `=`.
#
# So for `border?=normal_border`:
#   1. `peek_name()` is `border`, the cursor is bumped, and the test is
#      `self.at(TAssign)` -- FALSE, because the next token is `?`.
#   2. `p` is restored and the argument falls to the positional path, where
#      `parse_expr` reads `border` as a plain name.
#   3. The `TQuestion` shorthand fires: `?` is consumed, the label is recorded.
#   4. The loop then tests `self.at(TComma)` -- FALSE, because the cursor is on
#      the `=` that step 1 skipped over.
#   5. The loop BREAKS, and the caller demands `)` at an `=`.
#
# So `?` is consumed as if the argument ended there, and the `= value` behind it is
# orphaned. A precise complaint about an INCOMPLETE model: the shorthand family is
# missing a member.
#
# THE ROW THAT DECIDES THE FIX is `B`. A parameter declared `border? : Int` has
# type `Int?` -- the `?` is not decoration, and `border?=v` is only legal when the
# parameter was declared with `?`. Measured:
#
#     border?=v   against  border? : Int    ACCEPT
#     border?=v   against  border~ : Int    REJECT(4141) "this form of application
#                                           is invalid for argument border~, because
#                                           it is not declared with border? : _"
#
# So `?=` is NOT sugar for `=`. A fix that desugars `border?=v` into `border=v`
# would read illegal code as legal, which is the one failure mode a validator
# cannot afford. The fix has to carry the `?` through to the label it records.
#
# `D` is the other guard: `border?v` -- a `?` followed by a name -- is REJECT(3002)
# "unexpected token id, you may expect `,` or `)`". So `?` in argument position is
# either the end of an argument or the start of `?=`; it never prefixes an
# expression. That is what makes the two-token lookahead safe to use.
#
# SCAFFOLD FACTS, load-bearing, each of which has silently produced a confident
# wrong answer in this repository: `moon.mod` MUST declare `source = "src"`; a
# package cannot import its OWN root; a NAMED argument needs the parameter declared
# LABELED (`border~ : Int`, else 4085 "no parameter with label border~"); and the
# output is joined with NEWLINES before any `(?m)` pattern is applied.

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

# THE CONSTRUCT. The parameter is declared `border? : Int`, so its type is `Int?`,
# and the value supplied is an `Int?` -- which is what makes this row a measurement
# and not a coincidence: `border?=7` with a bare `7` is REJECT(4014) "wanted Int?".
Add-Case 'qmark_eq_on_optional_param' @'
///|
fn sink(border? : Int) -> Unit {
  ignore(border)
}

///|
fn probe() -> Unit {
  let v : Int? = Some(7)
  sink(border?=v)
}
'@ 'ACCEPT'

# THE THREE SIBLINGS, all of which parse today. They are here so that an ACCEPT on
# the construct cannot be an ACCEPT on everything.
Add-Case 'ctl_plain_eq' @'
///|
fn sink(border~ : Int) -> Unit {
  ignore(border)
}

///|
fn probe() -> Unit {
  sink(border=7)
}
'@ 'ACCEPT'

Add-Case 'ctl_tilde_shorthand' @'
///|
fn sink(border~ : Int) -> Unit {
  ignore(border)
}

///|
fn probe() -> Unit {
  let border = 7
  sink(border~)
}
'@ 'ACCEPT'

# `x?` forwards the ENCLOSING `x`, so the local must be NAMED after the parameter.
# The first version of this fixture declared `let v : Int? = ...` and called
# `sink(border?)`, which is REJECT(4021) `undefined name 'border'` -- the shorthand
# is a reference to a binding, not an assignment, and the fixture was asking a
# different question than the one it was written for.
Add-Case 'ctl_question_shorthand' @'
///|
fn sink(border? : Int) -> Unit {
  ignore(border)
}

///|
fn probe() -> Unit {
  let border : Int? = Some(7)
  sink(border?)
}
'@ 'ACCEPT'

# THE ROW THAT DECIDES THE FIX: `?=` against a REQUIRED parameter is REJECTed, so
# the `?` is carrying meaning and `?=` is not sugar for `=`.
Add-Case 'qmark_eq_on_required_param' @'
///|
fn sink(border~ : Int) -> Unit {
  ignore(border)
}

///|
fn probe() -> Unit {
  let v : Int? = Some(7)
  sink(border?=v)
}
'@ 'REJECT'

# THE VALUE IS REQUIRED. `border?=` names a parameter AND supplies it.
Add-Case 'qmark_eq_no_value' @'
///|
fn sink(border? : Int) -> Unit {
  ignore(border)
}

///|
fn probe() -> Unit {
  sink(border?=)
}
'@ 'REJECT'

# `?` NEVER PREFIXES AN EXPRESSION in argument position, which is what licenses the
# two-token lookahead the fix uses.
Add-Case 'qmark_then_name' @'
///|
fn sink(border? : Int) -> Unit {
  ignore(border)
}

///|
fn probe() -> Unit {
  let v : Int? = Some(7)
  sink(border?v)
}
'@ 'REJECT'

# THE CORPUS CALL, verbatim in shape: a generic callee whose parameters mix all
# FOUR argument spellings -- `~`, `?`, `?=value` and a plain positional -- in one
# call. This is what `views/popover/sheet.mbt:21-29` writes, and the reason a
# fixture that only exercises `?=` alone would not be the same measurement.
#
# `Msg` IS USED, in `on_dismiss? : Msg?`, because the first version left it in the
# signature unused and REJECTed 4027. A generic parameter that appears nowhere in
# the body is the toolchain's business, not the construct's.
Add-Case 'corpus_call_shape' @'
///|
fn[Msg] shell(
  content~ : Int,
  mode? : Int = 0,
  theme? : Int,
  background? : Int,
  radius? : Double,
  shadow~ : Int,
  on_dismiss? : Msg?,
) -> Unit {
  ignore(content)
  ignore(mode)
  ignore(theme)
  ignore(background)
  ignore(radius)
  ignore(shadow)
  ignore(on_dismiss)
}

///|
fn[Msg] probe(
  content : Int,
  mode : Int,
  theme : Int?,
  radius : Double?,
  shadow : Int,
  on_dismiss : Msg?,
) -> Unit {
  let background_brush : Int? = Some(2)
  shell(
    content~,
    mode~,
    theme?,
    background?=background_brush,
    radius?,
    shadow~,
    on_dismiss~,
  )
}
'@ 'ACCEPT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0454_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0454`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-30} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. A BUILD-PLAN-FAILED row means the scaffold is wrong and NOTHING here'
  Write-Output 'is an answer. A `ctl_*` row reading ACCEPT means `moon check` is not'
  Write-Output 'discriminating and the ACCEPT rows beside it prove nothing.'
  exit 1
}
Write-Output 'GATE OK: `label?=value` is a legal call argument, its three siblings all'
Write-Output 'parse today, the value is required, and `?` never prefixes an expression.'
Write-Output 'The row that decides the fix is `qmark_eq_on_required_param`: `?=` against a'
Write-Output 'REQUIRED parameter is REJECTed, so the `?` carries meaning and `?=` must not be'
Write-Output 'desugared to `=` -- doing so would read illegal code as legal.'
exit 0

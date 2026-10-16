# Settles `is @pkg.Type::Ctor` against the toolchain.
#
# WHY THIS EXISTS. `parse_is_pattern` gates its whole head on `peek_name() != ""`
# (parser.mbt:3011). A package-qualified head starts with `@`, so `peek_name()` is
# `""`, the reader returns at 3069 having consumed NOTHING, and the tokens walk back
# up to `parse_atom`'s catch-all. That is the KNOWN LIMIT pinned in
# `parser_0436_test.mbt`, and it blocks exactly one moui file.
#
# BUT "48 published corpus sites use it" is NOT the same as "the toolchain accepts
# it", and 0454 is the standing reminder of why that matters here: `?=` looked like
# harmless optional-argument sugar and REJECTed against a required parameter. A
# parser change that starts ACCEPTING illegal code is worse than the parse failure
# it replaces, because every later finding in that file inherits the fiction.
#
# SCAFFOLD ARCHAEOLOGY, because getting here cost five wrong layouts and each one
# produced a confident wrong answer rather than an obvious error:
#
#   1. `import` inside a `.mbt` file -- REJECT 3001 "Invalid import declaration
#      here. Move this declaration to `moon.pkg`." Imports go in `moon.pkg`.
#   2. `source = "src"` with a sub-package at `src/b/` -- "Failed to calculate build
#      plan: Cannot find import 'b'". Sub-packages are NOT under src/.
#   3. A root-level `.mbt` (the blackbox-test shape sqlite3 actually uses) -- every
#      row ACCEPTed, INCLUDING THE CANARY. `moon check` does not check those files,
#      so the fixture silently measured nothing. A canary that passes when it must
#      fail is the one signal that distinguishes this from a working scaffold.
#   4. Self-qualification by the package's own short name -- "Package not found".
#      `@sqlite3.` works in the corpus because that file IMPORTS the package, not
#      because it belongs to it.
#   5. A path-style package name with no `source = "src"` -- WORKS. This is the layout
#      moonbit-community/proton uses: root package at the project root, sub-packages
#      as sibling directories each with their own `moon.pkg`, imported as
#      `"<project name>/<dir>"`.
#
# The row that finally makes the ACCEPTs mean something is
# `ctl_boundary_is_real`: the root package referring to `Thing` WITHOUT the `@b.`
# prefix must REJECT. If that accepted, the `@b.` rows would prove only that a
# permissive compiler accepts anything.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# THE CANARY: a name that cannot exist. If this reads ACCEPT, every ACCEPT below
# proves nothing -- see scaffold item 3, where that is exactly what happened.
Add-Case 'ctl_missing' @'
///|
fn probe() -> Int {
  ignore(ZzMissing)
  0
}
'@ 'REJECT'

# THE BOUNDARY IS REAL. `Thing` is declared in package `b`, so the root package
# cannot see it unqualified. This is what makes the `@b.` rows attributable to the
# package qualifier rather than to a permissive compiler.
Add-Case 'ctl_boundary_is_real' @'
///|
fn probe(t : Thing) -> Int {
  0
}
'@ 'REJECT'

# THE CONTROL: the same pattern, unqualified, against an enum declared in THIS
# package. If this REJECTed then the `@b.` rows would be about the package rather
# than about the pattern head.
#
# The enum is declared in a ROOT-LEVEL file on purpose. The first version of this row
# put it inside package `b`, where it REJECTed with "The type Thing is undefined" --
# not because the pattern is wrong but because `moon check` at the project root checks
# the ROOT package and never visits `b`. The fixture was measuring nothing.
Add-Case 'ctl_same_package_unqualified' @'
///|
pub(all) enum Local {
  A(Int)
  B(Int)
}

///|
fn probe(t : Local) -> Int {
  if t is Local::A(r) {
    r
  } else {
    0
  }
}
'@ 'ACCEPT'

# `@pkg` RESOLVES OUTSIDE AN `is` PATTERN. Without this, an ACCEPT on the rows below
# could not be separated from "the compiler ignores the qualifier in patterns".
Add-Case 'ctl_qualified_plain_expression' @'
///|
fn probe(t : @b.Thing) -> Bool {
  t is @b.Thing::Small(0)
}
'@ 'ACCEPT'

# THE CONSTRUCT, on an `if` condition with a payload the pattern BINDS. `Small` is
# the positional constructor, so `r` binds without a label.
Add-Case 'at_head_if_binds' @'
///|
fn probe(t : @b.Thing) -> Int {
  if t is @b.Thing::Small(r) {
    r
  } else {
    0
  }
}
'@ 'ACCEPT'

# THE CORPUS SHAPE from `sqlite3 0.2.3 async_test.mbt:5`, which is
#
#     assert_true(statement.step_async() is @sqlite3.StepResult::Done(..))
#
# and `StepResult` is `Done(changes~ : Int64?)` -- a LABELED payload.
#
# The first version of this row declared `Big(Int)`, POSITIONAL, and REJECTed with
# Error [4080] "The constructor Big requires 1 arguments, but is given 0 arguments",
# plus "This `..` is useless, all fields are already matched". The fixture was wrong,
# not the expectation: `..` is legal exactly where it skips something, and a labeled
# payload is not matched by position. So the enum carries BOTH constructors, and
# `ctl_positional_dotdot_rejects` below pins the boundary from the other side.
Add-Case 'at_head_bare_wildcard_payload' @'
///|
fn probe(t : @b.Thing) -> Bool {
  let ok = t is @b.Thing::Big(..)
  ok
}
'@ 'ACCEPT'

# THE OTHER SIDE OF THAT BOUNDARY, and the row that keeps `at_head_bare_wildcard_payload`
# honest. `..` over a FULLY POSITIONAL payload is rejected by the compiler, so an
# ACCEPT on the row above cannot be "the compiler ignores `..` in patterns".
Add-Case 'ctl_positional_dotdot_rejects' @'
///|
fn probe(t : @b.Thing) -> Bool {
  let ok = t is @b.Thing::Small(..)
  ok
}
'@ 'REJECT'

# NO PAYLOAD at all -- `macos_services.mbt:405-406`,
# `menu.placement is @services.ApplicationMenuPlacement::MenuBar`.
Add-Case 'at_head_no_payload' @'
///|
fn probe(t : @b.Thing) -> Bool {
  let ok = t is @b.Thing::Small(0)
  ok
}
'@ 'ACCEPT'

# THE HEAD SPANS A LINE BREAK, because `macos_services.mbt:405-406` writes it as
#
#     let in_menu_bar = menu.placement
#       is @services.ApplicationMenuPlacement::MenuBar
#
# and 0455 measured that line-continuation questions are the ones that hide.
Add-Case 'at_head_newline_before_is' @'
///|
fn probe(t : @b.Thing) -> Bool {
  let ok = t
    is @b.Thing::Small(0)
  ok
}
'@ 'ACCEPT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0456_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

# Package `b`, written once and reused. `@pkg` names an IMPORT, so without a real
# second package the construct is not expressible -- and pointing at a package that
# was never imported would test nothing.
#
# TWO CONSTRUCTORS, and the difference is the measurement: `Big` takes a LABELED
# payload and `Small` a POSITIONAL one. `..` is legal over the first and rejected
# over the second, which is why the `..` rows are a pair rather than one row.
$pkgB = @'
///|
pub(all) enum Thing {
  Big(x~ : Int)
  Small(Int)
}
'@

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'b') | Out-Null
  # No `source = "src"`: the root package is the project root and sub-packages are
  # sibling directories. This is the proton layout; see scaffold item 5.
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0456`"`n`nversion = `"0.1.0`"`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'moon.pkg'), "import {`n  `"p0456/b`",`n}`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'main.mbt'), $cases[$k], $enc)
  [IO.File]::WriteAllText((Join-Path $d 'b\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'b\thing.mbt'), $pkgB, $enc)

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
  if (-not $ok) {
    $fail++
    ($joined -split "`n" | Where-Object { $_ -match '╰──' } | Select-Object -First 2) |
      ForEach-Object { Write-Output ('      ' + $_.Trim()) }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the grammar: the canary must REJECT, the boundary'
  Write-Output 'control must REJECT, and the same-package control must ACCEPT. Until all three'
  Write-Output 'hold, an ACCEPT on an `@pkg` row is not evidence about the pattern head.'
  exit 1
}
Write-Output 'GATE OK: `is @pkg.Type::Ctor` is legal MoonBit in every shape measured -- payload,'
Write-Output '`..` payload, no payload, and across a line break. The parser must CONSUME the'
Write-Output 'qualified path instead of leaving it in the token stream. The canary REJECTs and'
Write-Output 'the package boundary REJECTs, so the four ACCEPTs are discriminating.'
exit 0

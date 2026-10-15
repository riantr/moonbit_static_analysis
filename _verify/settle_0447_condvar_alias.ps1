# Settles the ALIASED-TYPE RE-EXPORT path for 0.4.37, by toolchain acceptance.
#
# THE QUESTION. proton 0.3.4 `facade_notification.mbt:12,14` writes
#
#     gate: @async.CondVar::Cond(),
#
# and the analyzer reports `undefined function '@async.CondVar::Cond'` on both. async
# 0.22.4 re-exports the type under that name in `src/pkg.generated.mbti:111`:
#
#     pub using @cond_var {type Cond as CondVar}
#
# and `@cond_var/pkg.generated.mbti` declares `type Cond` with `pub fn Cond::Cond() -> Self`.
# So: may a CONSTRUCTOR be called through an ALIASED type re-export?
#
# WHY `moon check` IS ENOUGH HERE, and it was NOT enough for 0.4.36. There every shape of
# a block string was accepted -- nine of nine -- so acceptance measured nothing and the
# rule had to be settled by printed VALUE. That was a property of that question, not of
# `moon check`. Here acceptance IS the claim, and what makes it trustworthy is that three
# of the six cases are deliberately invalid and MUST be rejected. `moon check` does
# discriminate on this: measured `[4029]` for a missing member through the alias, `[4029]`
# for a missing member without it, `[4032]` for a missing type.
#
# TWO SCAFFOLD FACTS, both paid for in a wasted run and recorded so nobody pays again:
#   1. `moon.mod` MUST declare `source = "src"` explicitly. Without it, `Cannot find
#      import 'p0447/cond_var' in p0447/src@0.1.0` -- the build plan fails, NOTHING is
#      compiled, and every case reads ACCEPT.
#   2. A package cannot import its OWN root package. `import { "p0447" }` from `cmd/main`
#      is `Cannot find import 'p0447' in p0447/cmd/main@0.1.0`, for the same reason.
#      The caller is therefore a SUB-PACKAGE, `src/app`, which imports `"p0447"` and is
#      resolved as `p0447/app` -- and that works.
#
# THE FIRST VERSION OF THIS SCRIPT REPORTED 3 MISMATCHES, all three controls coming back
# ACCEPT, for cause (1). It is left in the record because that is the failure this
# repository keeps producing: a probe whose instrument never engaged supports no
# conclusion, and here it would have reported "the alias works" -- which happens to be
# the answer, for entirely the wrong reason. The controls are what caught it.
#
# A NOTE ON THE SCAFFOLD'S OWN SYNTAX: `using @pkg {X as Y}` emits warning `[0027]`,
# deprecated_syntax. async 0.22.4 still writes it, proton still depends on it, and this
# settle does not use `--deny-warn` because a deprecation is not a rejection.

$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$fn, [string]$want) {
  $script:cases[$name] = $fn
  $script:expect[$name] = $want
}

# --- the controls ---------------------------------------------------------
# 1. THE un-aliased control. `@cond_var.Cond::Cond()` needs no re-export at all, so if
#    this fails the SKELETON is wrong and cases 3-6 measure the skeleton, not aliasing.
Add-Case 'direct_subpkg' 'pub fn f() -> Int {
  let c = @cond_var.Cond::Cond()
  c.n
}' 'ACCEPT'
# 2. A member that does not exist, without the alias. MUST be rejected.
Add-Case 'ctl_missing_direct' 'pub fn f() -> Int {
  let c = @cond_var.Cond::Nope()
  c.n
}' 'REJECT'
# 4. A member that does not exist THROUGH THE ALIAS. MUST be rejected -- this is the case
#    that would catch "fix it by silencing every `X::Y` that looks re-exported".
Add-Case 'ctl_missing_alias' 'pub fn f() -> Int {
  let c = @p0447.CondVar::Nope()
  c.n
}' 'REJECT'
# 6. A TYPE that does not exist. MUST be rejected.
Add-Case 'ctl_missing_type' 'pub fn f() -> @p0447.Nope {
  @p0447.CondVar::Cond()
}' 'REJECT'

# --- the claim ------------------------------------------------------------
# 3. THE SHAPE proton writes, cross-package: a constructor called through an aliased
#    type re-export, from a package that imports the re-exporting one.
Add-Case 'alias_qualified' 'pub fn f() -> Int {
  let c = @p0447.CondVar::Cond()
  c.n
}' 'ACCEPT'
# 5. The same with the alias used as a TYPE. proton annotates `gate : @async.CondVar` on
#    the struct field at line 4 and initializes it at line 12, so this one corpus line
#    uses both halves and both are settled here.
Add-Case 'alias_type_annot' 'pub fn f() -> @p0447.CondVar {
  @p0447.CondVar::Cond()
}' 'ACCEPT'

# --- run ------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0447_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src\cond_var') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src\app') | Out-Null

  # `source = "src"` is REQUIRED -- see fact (1) at the top.
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0447`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)

  # The sub-package: a type with an explicit constructor, which is how `@cond_var`
  # declares `Cond`.
  [IO.File]::WriteAllText((Join-Path $d 'src\cond_var\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\cond_var\cond_var.mbt'), "pub struct Cond {`n  n : Int`n}`n`npub fn Cond::Cond() -> Cond {`n  Cond::{ n: 0 }`n}`n", $enc)

  # The root package: imports its own sub-package by FULL PATH -- the form async's
  # `src/moon.pkg` uses for `"moonbitlang/async/cond_var"` -- and re-exports the type
  # under a second name.
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "import {`n  `"p0447/cond_var`",`n}`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\outer.mbt'), "pub using @cond_var {type Cond as CondVar}`n", $enc)

  # The caller: a SUB-PACKAGE, because a package cannot import its own root -- fact (2).
  [IO.File]::WriteAllText((Join-Path $d 'src\app\moon.pkg'), "import {`n  `"p0447`",`n  `"p0447/cond_var`",`n}`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\app\use.mbt'), $cases[$k] + "`n", $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  # JOIN WITH NEWLINES, NOT WITH SPACES, and do not collapse whitespace before matching.
  # The `(?m)^Error: \[` pattern needs line boundaries, and this script's second version
  # joined the whole output into ONE space-separated line before matching -- so the
  # pattern could never fire and every control read ACCEPT. That is the same class of
  # failure as the build-plan one above: the instrument was fine, the plumbing was not.
  # Three of the six rows are controls precisely so this cannot pass unnoticed.
  $joined = ($o -join "`n")
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  # 0027 (deprecated_syntax) and 0029 (unused_package) are warnings, not rejections.
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') |
    ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($plan) {
    $got = 'BUILD-PLAN-FAILED'
    $ok = $false
  } elseif ($want -eq 'REJECT') {
    $got = if ($errs.Count) { 'REJECT' } else { 'ACCEPT' }
    $ok = ($got -eq 'REJECT')
  } else {
    $got = if ($errs.Count) { 'REJECT(' + ($errs -join ',') + ')' } else { 'ACCEPT' }
    $ok = ($got -eq 'ACCEPT')
  }
  Write-Output ('{0,-20} {1,-20} (want {2,-6}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output "ABORT: $fail case(s) did not match."
  Write-Output 'If any row says BUILD-PLAN-FAILED the scaffold is wrong and NOTHING in this'
  Write-Output 'run is an answer -- that is the state the first version of this script was in.'
  Write-Output 'If `direct_subpkg` failed the skeleton is wrong; if a `ctl_*` row came back'
  Write-Output 'ACCEPT then `moon check` is not discriminating here and the ACCEPT rows'
  Write-Output 'beside it prove nothing.'
  exit 1
}
Write-Output 'GATE OK: a constructor IS callable through an aliased type re-export,'
Write-Output 'cross-package, and a name that does not exist is still rejected through it.'
Write-Output 'So the analyzer must LINK the alias -- silencing every `X::Y` that looks'
Write-Output 're-exported would trade a false positive for a false negative.'
exit 0

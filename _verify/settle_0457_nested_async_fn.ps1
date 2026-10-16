# Settles a nested `async fn` DECLARATION against the toolchain.
#
# WHY THIS EXISTS. Fixing 0456 (`is @pkg.Type::Ctor`) made
# `moonbitlang/async 0.22.4 src/fs/watch_test.mbt` parse for the first time, and
# that turned async's `actionable` count from 0 into 3. All three are the SAME false
# positive:
#
#     50:3 - error: undefined name 'async' (UndefinedName) [structural+type]
#     219:3 - ...  341:3 - ...
#
# and all three land on a nested DECLARATION:
#
#     async fn wait() {
#
# The parser has no `async fn` DECLARATION case in a statement list, so it reads
# `async` as a name expression -- `EName("async")`, parser.mbt:4516 -- and then
# `fn wait() { ... }` as a separate statement. The walker then resolves `async`
# against the frame, does not find it, and reports it. 0453 added `async fn` in
# EXPRESSION position (a literal); a declaration in a block is a different thing.
#
# SO TWO THINGS ARE SETTLED HERE, and the second is the one that matters:
#
#   1. `async fn name() { ... }` nested inside a block is LEGAL. Which is why the
#      parser must read it as a declaration rather than forgiving the name.
#   2. `async` CANNOT BE BOUND AS A NAME -- `let async = 1` is REJECT(3002).
#      Which is why "undefined name 'async'" is provably a false positive and not a
#      real finding the analyzer has no choice about.
#
# WITHOUT ROW 2 the parser change would be unfalsifiable: reading `async fn wait()`
# as a name would look like a legitimate (if unresolvable) reference. With it, the
# analyzer's finding is refuted by the toolchain, and the honest repair is on the
# parser's side.
#
# SCAFFOLD ARITHMETIC, learned the hard way here and in settle_0456. The fixture is a
# SINGLE package with `source = "src"` and NO `fn main` (a root-level `main` is
# "Unexpected main function in the non-main package", 4069). `async fn` propagates,
# so every enclosing signature needs `raise`; and an `async fn` can only be CALLED
# from async context -- Error [4149] "cannot call async function in non-async
# function". A raising body needs a DECLARED `priv suberror`, or `raise Boom` is
# Error [4014] "Expr Type Mismatch" on an unconstrained type.
#
# Each of those four was a fixture error that first read as a verdict about the
# grammar. None of them was a fact about MoonBit.
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

# THE ROW THAT REFUTES THE FALSE POSITIVE. `async` is a KEYWORD: it cannot be bound,
# so "undefined name `async`" describes code that cannot exist. This is what makes
# the parser change the honest repair rather than a suppression.
Add-Case 'ctl_async_cannot_be_bound' @'
///|
fn probe() -> Int {
  let async = 1
  async
}
'@ 'REJECT'

# THE CONSTRUCT: an `async fn` declared inside another function's body.
Add-Case 'async_fn_nested_decl' @'
///|
priv suberror Boom

///|
fn boom() -> Int raise {
  raise Boom
}

///|
async fn outer() -> Int raise {
  async fn inner() -> Int raise {
    boom()
  }
  inner()
}

///|
async fn probe() -> Int raise {
  outer()
}
'@ 'ACCEPT'

# DEEPER: the declaration inside an `if` body, which is the shape most of the 46
# async-corpus sites take (they live inside `test` / `wbtest` blocks).
Add-Case 'async_fn_nested_in_block' @'
///|
priv suberror Boom

///|
fn boom() -> Int raise {
  raise Boom
}

///|
async fn outer(flag : Bool) -> Int raise {
  if flag {
    async fn deep() -> Int raise {
      boom()
    }
    deep()
  } else {
    0
  }
}

///|
async fn probe() -> Int raise {
  outer(true)
}
'@ 'ACCEPT'

# THE CONTROL, and the row that makes the two above mean something: a PLAIN nested
# `fn` declaration. If this failed, the nested-declaration rows would be about
# `async` rather than about nesting.
Add-Case 'ctl_plain_fn_nested_decl' @'
///|
priv suberror Boom

///|
fn boom() -> Int raise {
  raise Boom
}

///|
fn outer() -> Int raise {
  fn inner() -> Int raise {
    boom()
  }
  inner()
}

///|
fn probe() -> Int raise {
  outer()
}
'@ 'ACCEPT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0457_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0457`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  if (-not $ok) {
    $fail++
    ($joined -split "`n" | Where-Object { $_ -match '╰──' } | Select-Object -First 2) |
      ForEach-Object { Write-Output ('      ' + $_.Trim()) }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the grammar: the canary must REJECT, and so must'
  Write-Output '`ctl_async_cannot_be_bound`. If that row ACCEPTs then `async` is bindable and the'
  Write-Output 'false positive this settles is a real finding the analyzer has no choice about.'
  exit 1
}
Write-Output 'GATE OK: a nested `async fn` declaration is legal MoonBit, so the parser must read'
Write-Output 'it as a declaration; and `async` CANNOT be bound as a name (REJECT 3002), so'
Write-Output '`undefined name `async`` is provably a false positive rather than a real finding.'
exit 0

# Settle 0471 -- what can sit between an ANONYMOUS `fn`'s parameter list and its body.
#
# WHY. `parse_fn_literal` reads a parameter list and then goes straight to the body:
#
#     let _ = self.parse_param_list()
#     let (_, _) = self.parse_block(false)
#
# A DECLARED `fn` reads the same tail with two more calls that the literal does not make:
#
#     let params = self.parse_param_list()
#     if self.at(TArrow) { retann = self.return_annotation() }
#     self.parse_raise_effect()
#
# Measured on the tree at 0470, the consequence is that an anonymous `fn` carrying EITHER
# `-> Type` OR `raise`/`noraise`/`nocancel` in its signature is unreadable, and it is
# unreadable for a message that names the wrong thing: `parse_block` looks for `{`, finds
# `->`, and reports `expected '{'` -- a complaint about a brace that was never the problem.
# That is the same shape as the `-> T raise E` clause whose absence once cost 24.5% of
# wzzc-dev/moui's 608 files.
#
# The position was ruled out by measurement rather than assumption, because the obvious
# reading ("anonymous fns only work as call arguments") is wrong in both directions:
#
#     let h = fn(x : Int) { x }          ACCEPTED by the analyzer
#     g(fn(x) { x })                     ACCEPTED by the analyzer
#     let h = fn(x : Int) -> Int { x }   PARSE ERROR
#     g(fn(x) -> Int { x })              PARSE ERROR
#
# so the variable is the RETURN ANNOTATION, not the position.
#
# => 判据: the two helpers already exist and a declared `fn` already calls them. The fix is
# to make the literal call the same two, not to write a third reader. This settle therefore
# only has to establish WHICH tails are legal, because `return_annotation` and
# `parse_raise_effect` already encode the answer for declared functions.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
#
# THE CONTROL. The bare literal is what already parses, so every ACCEPT below is about the
# tail and not about `fn` literals being illegal in expression position at all.
Add-Case 'ctl_bare_literal' @'
///|
fn f() -> Unit {
  let h = fn(x : Int) { x }
  ignore(h(1))
}
'@ 'ACCEPT'

# AND THE OTHER CONTROL: an undefined name must still be refused, so an ACCEPT below is
# about the tail rather than about this scaffold failing to compile for any other reason.
Add-Case 'ctl_undefined' @'
///|
fn f() -> Unit {
  ignore(zq_missing_tail)
}
'@ 'REJECT'

# --- THE CLAIMS. Gated. --------------------------------------------------------
#
# CLAIM 1. `-> Type` is legal on an anonymous fn. This is the whole of the labeler E shape
# (`let idx = fn(c : Char) -> Int { .. }`, `let measure = fn(constraints : ..) -> .. { .. }`).
Add-Case 'claim1_return_type' @'
///|
fn f() -> Unit {
  let h = fn(x : Int) -> Int { x }
  ignore(h(1))
}
'@ 'ACCEPT'

# CLAIM 2. `raise` with NO error type, which is `raise E` with an empty list.
#
# The `if` is on its OWN LINES. A one-line `{ if x < 0 { raise Boom } x }` is rejected by the
# toolchain with `unexpected token id`, which says nothing about the tail and everything
# about the fixture -- the first draft of this row had it inline and the row failed.
Add-Case 'claim2_bare_raise' @'
///|
suberror Boom

///|
fn f() -> Unit raise {
  let h = fn(x : Int) raise {
    if x < 0 {
      raise Boom
    }
    x
  }
  ignore(h(1))
}
'@ 'ACCEPT'

# CLAIM 3. `raise E` naming the error.
Add-Case 'claim3_raise_type' @'
///|
suberror Boom

///|
fn f() -> Unit raise Boom {
  let h = fn(x : Int) raise Boom {
    if x < 0 {
      raise Boom
    }
    x
  }
  ignore(h(1))
}
'@ 'ACCEPT'

# CLAIM 4. `noraise`.
Add-Case 'claim4_noraise' @'
///|
fn f() -> Unit {
  let h = fn(x : Int) noraise { x }
  ignore(h(1))
}
'@ 'ACCEPT'

# CLAIM 5. BOTH together, in the order the declared-fn path reads them. This is the shape
# at `proton/updater/channel.mbt` and `proton/updater/install.mbt`:
#
#     fetch(update.url, update.size, async fn(chunk) -> Unit raise UpdateError { .. })
#     fn() -> UInt64 raise UpdateError { .. }
Add-Case 'claim5_return_and_raise' @'
///|
suberror Boom

///|
fn f() -> Unit raise Boom {
  let h = fn(x : Int) -> Int raise Boom {
    if x < 0 {
      raise Boom
    }
    x
  }
  ignore(h(1))
}
'@ 'ACCEPT'

# CLAIM 6. THE FUNCTION-TYPE spelling of a return annotation, in its PARENTHESISED form.
# Settled for declared functions in settle_0427_retfn, and an anonymous literal is the same
# production -- but it is asserted here because the literal has never reached it.
Add-Case 'claim6_bracketed_return' @'
///|
fn f() -> Unit {
  let h = fn(x : Int) -> Array[Int] {
    [x]
  }
  ignore(h(1))
}
'@ 'ACCEPT'

# CLAIM 7. `async fn` with a tail, which is the same production behind the `async` keyword
# and takes the identical path once `parse_fn_literal` is entered.
#
# The literal is BOUND AND NOT CALLED. Calling an `async fn` without awaiting it is [4122],
# which the first draft did and which is a call-site error rather than a statement about
# the tail.
Add-Case 'claim7_async_literal' @'
///|
suberror Boom

///|
fn f() -> Unit {
  let h = async fn(x : Int) -> Unit raise Boom {
    ignore(x)
  }
  ignore(h)
}
'@ 'ACCEPT'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0471_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0471`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
    else { $ok = $got -like 'REJECT*' }
  } else {
    $got = 'ACCEPT'
    $ok = ($want -eq 'ACCEPT')
  }
  Write-Output ('{0,-30} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|reserved|shadow' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. Both controls must behave.'
  Write-Output 'A flipped CLAIM means the two helpers do not cover this tail -- re-read before shipping.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

# Settle 0463b -- WHAT IS A BODY-LESS suberror, actually?
#
# WHY. `settle_0463_suberror_bodyless.ps1` REJECTED both `of`-form cases:
#
#     of_payload_ct    REJECT(3002,4080)
#     of_payload_bare  REJECT(3002)
#         Parse error, unexpected token id (lowercase start), you may expect
#         `pub`, `priv`, `type`, `suberror`, `extenum`, `async`, `fn`, ...
#
# `of` is lowercase-start, so `of` is the unexpected token and the parse had ALREADY
# finished `suberror Timeout` before reaching it.
#
# That contradicts the parser, which documents this shape twice as legal:
#
#     parser.mbt:226  "A suberror has TWO shapes: `suberror Timeout of String` is
#                       one line, while `pub suberror DecodeError { ... }` is braced."
#     parser.mbt:692  "an unbraced header (`suberror Timeout of String`) must NOT be
#                       answered by a brace belonging to some later declaration"
#
# The rule at parser.mbt:235 DISCRIMINATES on `next_is_lbrace()`, and both comments
# use `of` as the example of the branch that must NOT open a brace. If the form does
# not exist, the discriminator is still correct -- but the two comments are teaching
# a grammar the toolchain does not have, which is a false claim in the file that
# explains why the code is the way it is.
#
# So: which body-less suberror headers EXIST? The fix has to be written against the
# real list, and the comments have to be corrected against it.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

Add-Case 'ctl_of_form' @'
///|
priv suberror Timeout of String

///|
fn probe() -> Int raise {
  1
}
'@ 'REJECT'

Add-Case 'of_form_pub' @'
///|
pub suberror Timeout of String

///|
fn probe() -> Int raise {
  1
}
'@ 'REJECT'

Add-Case 'of_form_bare' @'
///|
suberror Timeout of String

///|
fn probe() -> Int raise {
  1
}
'@ 'REJECT'

# If these are the payload forms, one of them has to be legal -- otherwise a
# suberror simply cannot carry a payload without braces, and `of` was never it.
Add-Case 'paren_payload' @'
///|
priv suberror Timeout(String)

///|
fn probe() -> Int raise {
  raise Timeout("x")
}
'@ 'ACCEPT'

Add-Case 'named_payload' @'
///|
priv suberror Timeout(msg : String)

///|
fn probe() -> Int raise {
  raise Timeout(msg="x")
}
'@ 'ACCEPT'

# The braced form, as the positive control for the whole branch: a suberror with a
# brace body must still be legal.
Add-Case 'braced_control' @'
///|
priv suberror Timeout {
  Slow(String)
}

///|
fn probe() -> Int raise {
  raise Slow("x")
}
'@ 'ACCEPT'

# The plain body-less form the fix is actually about, as the second control.
Add-Case 'bare_control' @'
///|
priv suberror Timeout

///|
fn probe() -> Int raise {
  raise Timeout
}
'@ 'ACCEPT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0463b_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0463b`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-20} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|constructor' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'MISMATCH against the EXPECTATION column. Read it: a REJECT where a'
  Write-Output 'REJECT was wanted is a SETTLEMENT, not a scaffold failure.'
  exit 1
}
Write-Output 'GATE OK.'
exit 0

# Settle 0461 -- are CONSTRUCTORS of an enum / suberror visible as bare names?
#
# WHY. The 0459 lexer work unblocked 45 files; 0460 cleared the array-pattern
# false positives. What is left of the 24 is one shape, 13 of it in two files:
#
#     async  decoder.mbt   x10  no visible binding for 'InvalidBlock'
#                                      ... 'InvalidTrailer', 'NeedMoreInput'
#     proton native.mbt    x3   undefined name 'RuntimeActive'
#                                      ... 'RuntimeDestroyed', 'WindowLive'
#
# and the declaration is a CONSTRUCTOR inside a brace body:
#
#     priv suberror FormatError {
#       InvalidHeader(String)
#       InvalidTrailer(String)
#       InvalidBlock(String)      <- used bare: raise InvalidBlock("...")
#     }
#
# So the analyzer registers the TYPE and not its CONSTRUCTORS, and a constructor
# is a perfectly good bare name in MoonBit -- that is the whole point of one.
#
# THE QUESTION THIS SETTLES, and it is narrower than it looks. The obvious
# assumption is "enum variants and suberror constructors are the same thing, so
# one row covers both". They are not obviously the same: `decoder.mbt` declares
# `priv enum DecodeMode { Header Blocks ... }` and USES those variants, and the
# file parses to line 285+ with NO findings about them. So either enum variants are
# already handled and suberror constructors are not, or something else separates
# these two cases. Guessing wrong means either a no-op "fix" or a change that
# breaks a working path -- so both are measured.
#
# => 判据: "they look like the same kind of declaration" is not a reason to write
# one test for them. The corpus already shows a case that works beside one that
# does not, and that difference is the measurement.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

Add-Case 'ctl_missing' @'
///|
fn probe() -> Int {
  ignore(ZzMissing)
  0
}
'@ 'REJECT'

# AN ENUM VARIANT, used bare. `DecodeMode`'s `Header` is the working case.
Add-Case 'enum_variant_bare' @'
///|
priv enum Color {
  Red
  Green
}

///|
fn probe() -> Int {
  let c = Red
  match c {
    Red => 0
    Green => 1
  }
}
'@ 'ACCEPT'

# A SUBERROR CONSTRUCTOR, used bare. The failing case: `InvalidBlock`.
Add-Case 'suberror_ctor_bare' @'
///|
priv suberror FormatError {
  InvalidHeader(String)
  InvalidBlock(String)
}

///|
fn probe() -> Int raise {
  raise InvalidBlock("bad")
}
'@ 'ACCEPT'

# THE CONTROL for the previous row: a name that is NOT any constructor must still
# be refused, so the ACCEPT above is about the constructor and not about `raise`.
Add-Case 'ctl_ctor_unbound' @'
///|
priv suberror FormatError {
  InvalidHeader(String)
}

///|
fn probe() -> Int raise {
  raise NotARealConstructor("bad")
}
'@ 'REJECT'

# A constructor declared on ONE line, to separate "constructors are invisible"
# from "multi-line brace bodies are invisible". If this accepts and the two above
# behave differently, the fault is in how the BODY is read.
Add-Case 'suberror_ctor_one_line' @'
///|
priv suberror Tiny {
  Oops(Int)
}

///|
fn probe() -> Int raise {
  raise Oops(1)
}
'@ 'ACCEPT'

# WITH AN EXPLICIT DISCRIMINANT, `RuntimeActive = 0`. This is the proton half of
# the 13, and it is a DIFFERENT gap from the two rows above: the harvest is armed
# and the name is well-formed, but `ends_variant` accepts only `(`, `,`, `}`, a
# newline or `;` after a variant name -- not `=`. Measured on
# `proton 0.3.4 internal/native/types.mbt:1409`:
#
#     priv enum RuntimeLifecycleState {
#       RuntimeActive = 0
#       RuntimeDestroyed = 2
#     }
#
# used bare 20 lines away in a SIBLING file (`native.mbt:578`).
Add-Case 'enum_variant_discriminant' @'
///|
priv enum State {
  Active = 0
  Gone = 2
}

///|
fn probe() -> Int {
  let s = Active
  match s {
    Active => 0
    Gone => 1
  }
}
'@ 'ACCEPT'

# THE CONTROL for that row: the same enum without a discriminant, so the ACCEPT
# above is about `= N` and not about enum variants in general.
Add-Case 'enum_variant_no_discriminant' @'
///|
priv enum State {
  Active
  Gone
}

///|
fn probe() -> Int {
  let s = Active
  match s {
    Active => 0
    Gone => 1
  }
}
'@ 'ACCEPT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0461_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0461`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-26} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 10, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|constructor' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the grammar. Both controls must REJECT.'
  exit 1
}
Write-Output 'GATE OK: an enum variant and a suberror constructor are both ordinary bare names.'
Write-Output 'So the 13 remaining findings are one gap -- a constructor inside a brace body is'
Write-Output 'never registered -- and not two separate declaration kinds.'
exit 0

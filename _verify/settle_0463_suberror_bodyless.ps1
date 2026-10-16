# Settle 0463 -- which token is a BODY-LESS suberror's constructor name?
#
# WHY. Three tests in `pipeline_0460_test.mbt` assert `UndefinedName == 0` and each
# reports exactly 1. The probe names it:
#
#     PROBE ln=4 fam=UndefinedName msg=undefined name 'Boom'
#
# and a five-shape probe separates the two competing explanations:
#
#     A body-less suberror, declared BEFORE the use      Undef=1   <- order is not it
#     B body-less suberror, declared AFTER  the use      Undef=1
#     C suberror WITH a body, declared AFTER             Undef=0   <- the body is it
#     D the TYPE name in a signature, body-less          Undef=0   <- the type resolves
#     E control, nothing declared                       Undef=1
#
# The mechanism, located rather than inferred: `harvest_ctors` is the only thing
# that fills `Parser::enum_ctors`, and `enum_ctors` is what seeds the module frame
# as VALUES (`walk.mbt:1197`, `infer.mbt:880`). A body-less suberror goes to
# `skip_decl_line` (`parser.mbt:238`), so `harvest_ctors` never runs for it and the
# suberror's OWN name never becomes a value -- while `suberror Boom` with a body
# contributes `InvalidBlock` and resolves.
#
# So the rule to settle is: for a suberror with no brace body, the constructor is
# the suberror's own name. That is only safe if the name is read correctly on EVERY
# body-less header MoonBit allows, and there are three of them:
#
#     priv suberror Boom
#     priv suberror Boom derive(Debug)
#     priv suberror Timeout of String
#
# A harvest that grabbed `derive` or `of` would be a new false negative wearing the
# costume of this fix, so each is measured -- including whether `raise Boom` is even
# legal under a `derive`.
#
# => 判据: "the name is right there after the keyword" is true of one header out of
# three. The other two put a second word there first.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# THE CONTROL. Every ACCEPT below is about the DECLARATION, not about `raise`.
Add-Case 'ctl_missing' @'
///|
fn probe() -> Int raise {
  raise ZzMissing
}
'@ 'REJECT'

# FORM 1, bare. The failing fixture.
Add-Case 'bare_bodyless' @'
///|
priv suberror Boom

///|
fn probe() -> Int raise {
  raise Boom
}
'@ 'ACCEPT'

# FORM 2, with a derive list. If the name after the keyword were read positionally
# this would harvest `derive` instead of `Boom`.
Add-Case 'derive_bodyless' @'
///|
priv suberror Boom derive(Debug)

///|
fn probe() -> Int raise {
  raise Boom
}
'@ 'ACCEPT'

# AND ITS CONTROL for the harvest: with `derive` on the header, is `derive` itself
# now something a user could write bare? If this REJECTs, `Boom` is the constructor.
Add-Case 'derive_word_not_ctor' @'
///|
priv suberror Boom derive(Debug)

///|
fn probe() -> Int raise {
  raise derive
}
'@ 'REJECT'

# FORM 3, `suberror E of T`. EXPECTED REJECT. This row is the one that settled the
# grammar: the `of` form does not exist, and `of` is lowercase-start, so the parse
# had already finished `suberror Timeout` before reaching it.
#
#     Parse error, unexpected token id (lowercase start), you may expect `pub`,
#     `priv`, `type`, `suberror`, `extenum`, `async`, `fn`, ...
#
# Carried forward from settle_0463b_bodyless_grammar.ps1, which established that a
# body-less suberror cannot carry a payload at all -- `suberror E(T)` and
# `suberror E(x : T)` are rejected the same way. The first draft of this row wanted
# ACCEPT and was wrong about the LANGUAGE, not about the analyzer.
Add-Case 'of_payload_ct' @'
///|
priv suberror Timeout of String

///|
fn probe() -> Int raise {
  raise Timeout("boom")
}
'@ 'REJECT'

# The bare half of the same non-existent form, for the same reason.
Add-Case 'of_payload_bare' @'
///|
priv suberror Timeout of String

///|
fn probe() -> Int raise {
  raise Timeout
}
'@ 'REJECT'

# AND ITS CONTROL for the harvest: `String` is the PAYLOAD TYPE and must not become
# a constructor of the suberror.
Add-Case 'of_payload_word' @'
///|
priv suberror Timeout of String

///|
fn probe() -> Int raise {
  raise of
}
'@ 'REJECT'

# THE SCOPE BOUNDARY, and the row that stops the fix from growing. A BRACED suberror
# declares its constructors in the body, and its own name is a TYPE -- is that name
# also raisable? If it is, the harvest belongs on the braced form too; if it is not,
# extending the rule to braced suberrors would suppress a real finding.
Add-Case 'braced_type_is_ctor' @'
///|
priv suberror FormatError {
  InvalidBlock(String)
}

///|
fn probe() -> Int raise {
  raise FormatError
}
'@ 'REJECT'

# THE CONTROL for that boundary: the body's own constructor IS raisable, so the
# REJECT above is about the TYPE name and not about `raise` inside a braced shape.
Add-Case 'braced_ctor_is_ctor' @'
///|
priv suberror FormatError {
  InvalidBlock(String)
}

///|
fn probe() -> Int raise {
  raise InvalidBlock("bad")
}
'@ 'ACCEPT'

# THE TYPE NAME is unaffected by all of this and must keep resolving -- the fix
# adds a VALUE and must not disturb the TYPE.
Add-Case 'type_name_still_type' @'
///|
priv suberror Boom derive(Debug)

///|
fn handler(e : Boom) -> Int {
  0
}
'@ 'ACCEPT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0463_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0463`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-22} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
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
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. Both controls must REJECT.'
  exit 1
}
Write-Output 'GATE OK. The harvest reads the DECLARED name on every body-less header,'
Write-Output 'not the word after the keyword: two headers, and the only word that can'
Write-Output 'follow the name is `derive`.'
Write-Output ''
Write-Output 'And the rule stops where it stops: a BRACED suberror''s own name is not'
Write-Output 'raisable, so extending the harvest to braced bodies would be a new false'
Write-Output 'negative rather than a completion.'
exit 0

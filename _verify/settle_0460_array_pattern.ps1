# Settle 0460 -- the ARRAY PATTERN, `is [ a, b, c ]`.
#
# WHY THIS EXISTS. The 0459 lexer work (single-quoted byte literals and `\u{...}`
# escapes) unblocked 45 files across four corpora -- async parsed 275 -> 297,
# moonbit_image 2 -> 15 -- and in doing so REACHED a gap that had never been
# reachable, exactly as 0456 reached the nested `async fn` declaration:
#
#     guard buf
#       is [
#         b'\x1f',
#         compression_method,     <- binds
#         flags,                  <- binds
#         u32le(mtime),           <- binds?
#         extra_flags,
#         operating_system,
#       ] else {
#       raise InvalidHeader("invalid gzip magic")
#     }
#     guard compression_method is b'\x08' else { ... }
#
# `parse_is_pattern` has a tuple branch (`(`) and a head branch, and NO array
# branch. The `[` fell through to the head branch, which read the FIRST ELEMENT as
# the head name and returned. Three consequences, all measured on
# `async 0.22.4 src/internal/gzip_internal/metadata.mbt`:
#
#   * the elements were read as EXPRESSIONS, so the four names the pattern binds
#     were reported `undefined name 'compression_method'` and then used 8 lines
#     later -- a confident false positive against legal MoonBit;
#   * the `]` was never consumed, so the token after the pattern was read as code:
#     `undefined name 'else'`, on a KEYWORD, which is the loudest possible tell
#     that the pattern never ended;
#   * `no visible binding for 'u32le'`, because `u32le(mtime)` was read as a call.
#
# All 14 async findings and all 9 proton findings from 0459 are of this shape. So
# 0459 cannot ship alone: a lexer fix that trades 45 blocked files for 23 confident
# false positives is a worse outcome than either. The 0456+0457 precedent applies.
#
# THE ROWS THAT DECIDE THE IMPLEMENTATION.
#   ctl_missing                     the canary
#   array_binds_bare                bare lowercase elements BIND. This is the whole
#                                   point of the fix.
#   array_no_binding_use            the CONTROL: use a name the pattern does NOT
#                                   bind, so an implementation that binds the whole
#                                   bracket indiscriminately is caught
#   array_binds_call_form           `u32le(mtime)` -- does a call-form pattern bind
#                                   its ARGUMENT? Guessing this wrong in either
#                                   direction produces a false positive or a
#                                   silently missing binding, and the corpus writes
#                                   this shape, so it is measured rather than
#                                   assumed
#   array_literals_only             `[1, 2, 3]` binds nothing and must still parse
#   array_nested                    `[[a], b]` -- a nested bracket, so the scan has
#                                   to count depth rather than stop at the first `]`
#   ctl_unbound_after_pattern        the canary for the CONTROL row: a name no
#                                   pattern mentions must still be refused
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

# Bare lowercase elements BIND. The corpus shape, with the payload read back
# afterwards so a binding that does not happen becomes a compile error.
Add-Case 'array_binds_bare' @'
///|
priv suberror Boom

///|
fn boom() -> Int raise {
  raise Boom
}

///|
fn probe(xs : Array[Int]) -> Int raise {
  guard xs is [first, second] else {
    raise Boom
  }
  first + second
}
'@ 'ACCEPT'

# THE CONTROL. The use is of a name the pattern does not bind, so it must be
# REFUSED. Without this, "the pattern binds" is satisfied by an implementation
# that binds every name it sees anywhere inside the brackets.
Add-Case 'array_no_binding_use' @'
///|
priv suberror Boom

///|
fn boom() -> Int raise {
  raise Boom
}

///|
fn probe(xs : Array[Int]) -> Int raise {
  guard xs is [first] else {
    raise Boom
  }
  ignore(first)
  second
}
'@ 'REJECT'

# THE ROW THAT DECIDES THE SHAPE OF THE REPAIR. Inside an array pattern, does a
# CONSTRUCTOR form bind its argument? `u32le(mtime)` is exactly this shape in the
# corpus, and an implementation that only handled bare elements would report
# `mtime` undefined -- trading one false positive for another.
#
# THE FIRST DRAFT OF THIS ROW USED A PLAIN FUNCTION and was REJECTed:
#
#     guard xs is [pair(head, _)]
#     ... The type Int does not have the constructor pair.
#
# So `name(args)` in a pattern is a CONSTRUCTOR pattern, not a call -- and `u32le`
# is a builtin constructor, which is why the corpus compiles. The row now uses a
# real constructor over an array whose element type HAS that constructor. Reading
# the corpus and guessing "it must be a call" would have produced an implementation
# that rejected valid code; the toolchain refused it and the fixture was wrong.
Add-Case 'array_binds_ctor_form' @'
///|
priv suberror Boom

///|
fn boom() -> Int raise {
  raise Boom
}

///|
fn probe(xs : Array[Option[Int]]) -> Int raise {
  guard xs is [Some(inner)] else {
    raise Boom
  }
  inner
}
'@ 'ACCEPT'

# Bracketed literals bind nothing and must still be accepted, so the fix cannot be
# "every name inside the brackets is a binding".
Add-Case 'array_literals_only' @'
///|
priv suberror Boom

///|
fn boom() -> Int raise {
  raise Boom
}

///|
fn probe(xs : Array[Int]) -> Int raise {
  guard xs is [1, 2, 3] else {
    raise Boom
  }
  0
}
'@ 'ACCEPT'

# A nested bracket, so the scan must count depth rather than stop at the first `]`.
# The scrutinee is `Array[Array[Int]]`, so BOTH elements are `Array[Int]` -- the
# return type is `Array[Int]` to match. Three earlier drafts of this row each
# failed on a type annotation of my own (`Array[Int]` summed with an `Int`,
# `ignore` on an array, `.length` which is not the method) and every one of those
# failures first looked like a verdict about nested patterns.
Add-Case 'array_nested' @'
///|
priv suberror Boom

///|
fn boom() -> Array[Int] raise {
  raise Boom
}

///|
fn probe(xs : Array[Array[Int]]) -> Array[Int] raise {
  guard xs is [[inner], tail] else {
    raise Boom
  }
  ignore(inner)
  tail
}
'@ 'ACCEPT'

# The canary for the control row: a name no pattern mentions must still be refused,
# or the `array_no_binding_use` REJECT could be an artefact of the fixture.
Add-Case 'ctl_unbound_after_pattern' @'
///|
priv suberror Boom

///|
fn boom() -> Int raise {
  raise Boom
}

///|
fn probe(xs : Array[Int]) -> Int raise {
  guard xs is [first] else {
    raise Boom
  }
  ignore(first)
  totally_unrelated
}
'@ 'REJECT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0460_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0460`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the grammar. Both canaries must REJECT, and so must'
  Write-Output '`array_no_binding_use` -- if a name the pattern never binds is accepted then the'
  Write-Output 'ACCEPT rows are not evidence that the pattern binds anything.'
  exit 1
}
Write-Output 'GATE OK: an array pattern binds its bare lowercase elements AND the arguments of a'
Write-Output 'call-form pattern, binds nothing for bracketed literals, and nests. So the parser'
Write-Output 'must read `is [ ... ]` as a pattern that introduces bindings -- which is what turns'
Write-Output 'the 23 findings 0459 surfaced back into zero.'
exit 0

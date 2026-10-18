# Settle 0480 -- the UNBRACED Unicode escape `'\uXXXX'` in a character literal.
#
# WHY. 0459 settled and implemented the BRACED form, `'\u{...}'`, together with `\xNN`.
# Its guard at lexer.mbt:1060-1065 requires `\u` to be followed by `{`:
#
#     if e == 'x' || (e == 'u' && ... self.chars[self.pos + 1] == '{') {
#
# so the UNBRACED spelling falls through to `other => other`, which writes the letter `u`,
# and the four hex digits are then appended by the ordinary character path. The payload
# becomes `u007f` -- five characters -- and the length check rejects it with "character
# literal must hold exactly one character". That is the exact reported reason, and it is a
# false refusal: the corpus writes this form and the compiler accepts it.
#
# IT IS NOT ONE FILE. A sweep of every `.mbt` under `.repos` for single-quoted literals
# holding an unbraced escape finds the form in `moonbitlang/core` `builtin/char.mbt` --
# about a hundred and fifty sites -- and again in `char/predicate_reference_test.mbt`,
# `x/json5`, `x/unicode`, `svg` and `sqlite3`. Two PINNED corpora are blocked by it:
# proton `internal/native/configuration.mbt:4` (`'\u007f'`) and moonbit_labeler
# `extensions/labeler/labeler.mbt:2741` (`'\u000C'`). The standard library's own source
# uses the form, so this is a grammar clause and not a local spelling quirk.
#
# THE QUESTION IS HOW MANY DIGITS, and that decides the guard. A reader that consumes any
# run of hex digits would make `'\u00007f'` one character, while a reader that insists on
# exactly four would leave it refused. S3, S4 and S5 exist to tell those apart, and the
# braced form must keep working for the code points that need more than four digits
# (`'\u{1F600}'` is astral and has no unbraced spelling at all).
#
# SCAFFOLD NOTES, CARRIED FROM 0479 BECAUSE BOTH BIT THE SAME WAY. Every row here is written
# to a project that HAS a `src/moon.pkg`, because a MoonBit project without a package inside
# its source directory is not a package: `moon check` prints "no work to do", exits 0, and
# every row reads ACCEPT. `ctl_must_reject` exists so a harness that cannot fail cannot look
# like a harness that found the corpus legal, and "no work to do" is matched by name so that
# specific no-op can never again pass silently.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
Add-Case 'ctl_no_escape' @'
///|
fn a() -> Char {
  'x'
}
'@ 'ACCEPT'

# ctl_must_reject proves the INSTRUMENT can fail. Everything else here wants ACCEPT, so a
# compiler that is not running looks exactly like a compiler that approves.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# ctl_braced_form IS THE 0459 BEHAVIOUR, unchanged. It is here so that widening the escape
# rule cannot silently cost the form that already worked: `'\u{1F600}'` is astral and has no
# unbraced spelling, so the brace form is the ONLY way to write it.
Add-Case 'ctl_braced_form' @'
///|
fn b() -> Char {
  '\u{1F600}'
}
'@ 'ACCEPT'

# --- S1  THE PROTON SHAPE -----------------------------------------------------
# `internal/native/configuration.mbt:4`: `c < '\u007f'`.
Add-Case 'S1_proton_shape' @'
///|
fn c() -> Char {
  '\u007f'
}
'@ 'ACCEPT'

# --- S2  THE LABELER SHAPE ----------------------------------------------------
# `extensions/labeler/labeler.mbt:2741`: `buf.write_char('\u000C')`, passed to a function
# taking a `Char`. The BYTE form `b'\u000C'` is a different question and is S4.
Add-Case 'S2_labeler_shape' @'
///|
fn d(ch : Char) -> Unit {
  ignore(ch)
}

///|
fn d2() -> Unit {
  d('\u000C')
}
'@ 'ACCEPT'

# --- S3  THREE HEX DIGITS -----------------------------------------------------
# If this ACCEPTs the rule is "any run of hex digits" and a reader must bound it by the
# code point instead. If it REJECTs the rule is "exactly four", which is a smaller change.
Add-Case 'S3_three_digits' @'
///|
fn e() -> Char {
  '\u07f'
}
'@ 'RECORD'

# --- S4  SIX HEX DIGITS -------------------------------------------------------
# The unbraced counterpart of `'\u{1F600}'`. Six digits with no braces is either an error or
# a wider rule, and the two readings differ in whether `'\u00007f'` is one character.
Add-Case 'S4_six_digits' @'
///|
fn f() -> Char {
  '\u01F600'
}
'@ 'RECORD'

# --- S5  THE BYTE FORM --------------------------------------------------------
# `b'\x00'` is a `Byte` and `b'ab'` is REJECT(3001) per 0459. Whether the UNBRACED escape
# is legal in that position decides whether the fix belongs in `lex_char` alone or in the
# byte-literal branch that also routes to it.
Add-Case 'S5_byte_form' @'
///|
fn g() -> Byte {
  b'\u000C'
}
'@ 'RECORD'

# --- S6  SIX DIGITS, BMP VALUE ------------------------------------------------
# S4 used `'\u01F600'`, an ASTRAL value, and that is the wrong fixture for the question "is a
# six-digit escape accepted?" -- the answer comes back as a refusal either way, because the
# 0459 test file records the same trap: asserting the LENGTH of a four-byte character through
# this token measures how the string builder counts astral characters, not whether the escape
# was recognised. This row is the same digit count with a BMP value, so a reader that accepts
# a run of hex digits produces a one-character payload with no report at all and the two
# readings cannot be confused.
Add-Case 'S6_six_digits_bmp' @'
///|
fn h() -> Char {
  '\u00007f'
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0480_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0480`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # REQUIRED. See the scaffold notes above.
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $noop = $joined -match 'no work to do'
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($noop) {
    $got = 'MOON-DID-NOT-RUN'; $ok = $false
  } elseif ($plan) {
    $got = 'BUILD-PLAN-FAILED'; $ok = $false
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'RECORD') { $ok = $true }
    elseif ($want -eq 'ACCEPT') { $ok = $false }
    else { $ok = $got -like 'REJECT*' }
  } else {
    $got = 'ACCEPT'
    if ($want -eq 'RECORD') { $ok = $true } else { $ok = ($want -eq 'ACCEPT') }
  }
  Write-Output ('{0,-42} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown|Unknown|unexpected|╰── ' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All three controls must behave.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

# Settle 0496 -- the CHARACTER LITERAL's escape, and the CHARACTER COUNT.
#
# WHY. 0459 settled the BRACED form `'\u{...}'` and 0480 the UNBRACED
# `'\uXXXX'`. Both guards were about the DIGIT COUNT, and both left the reader
# with a question they never asked: how many CHARACTERS does the literal hold?
#
# THE ANSWER WAS WRONG, AND NOT BECAUSE OF THE DIGITS. The reader took as many
# hex digits as there were -- `'\u{1F600}'` was read as U+1F600, not truncated
# -- and then the length check counted the payload with `s.length()`. MoonBit's
# `String::length()` counts UTF-16 CODE UNITS and `String::to_array()` counts
# CODE POINTS, and the two DISAGREE for every supplementary-plane character.
# Measured:
#
#     "\u{1F600}".to_string().length()            -> 2
#     "\u{1F600}".to_string().to_array().length() -> 1
#
# So U+1F600 -- ONE character, two units -- was counted as two and the literal
# was refused with "character literal must hold exactly one character". The
# standing note in `_verify/NARRATIVE.md` (the 0494 block) said the reader
# "takes at most FOUR hex digits, which is exactly the BMP", and THAT WAS THE
# WRONG EXPLANATION of a right observation: a fix written from it would have
# bounded the digits and still refused `'\u{10000}'`.
#
# THE WITNESS IS REAL CORPUS CODE. `moonbitlang/core`
# `string/quickcheck_test.mbt:138`:
#
#     let qc_boundary_chars : Array[Char] = [
#       '@', 'A', 'B', ..., '\u{7F}', ..., '\u{10000}', '\u{1F600}', '\u{10FFFF}',
#     ]
#
# `moon check` calls it legal MoonBit with 0 errors, and the frontend could not
# read it.
#
# THE SECOND DEFECT IS WORSE. `'\u{110000}'` -- a code point past the last one
# -- reached `v.unsafe_to_char()`, which is not a conversion but a TRAP: the
# scanner printed `RuntimeError: unreachable` and STOPPED, so every file after
# it in the scan went unread. A wrong answer is one finding; a crash is the
# loss of the run.
#
# SO THIS SETTLES THE WHOLE GRAMMAR THE TOOLCHAIN IMPLEMENTS, one form per row:
# the digit count of each form, the value's range, the byte form's refusal, and
# the fact that an astral character is ONE character.
#
# SCAFFOLD NOTES, CARRIED FROM 0480 BECAUSE BOTH BIT THE SAME WAY. Every row
# here is written to a project that HAS a `src/moon.pkg`, because a MoonBit
# project without a package inside its source directory is not a package: `moon
# check` prints "no work to do", exits 0, and every row reads ACCEPT.
# `ctl_must_reject` exists so a harness that cannot fail cannot look like a
# harness that found the corpus legal, and "no work to do" is matched by name so
# that specific no-op can never again pass silently.
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

# ctl_must_reject proves the INSTRUMENT can fail. Everything else here wants
# ACCEPT, so a compiler that is not running looks exactly like a compiler that
# approves.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# ctl_bmp_form IS THE 0459 BEHAVIOUR, unchanged, so that widening the escape
# rule cannot silently cost the form that already worked.
Add-Case 'ctl_bmp_form' @'
///|
fn b() -> Char {
  '\u{7F}'
}
'@ 'ACCEPT'

# ctl_unbraced_form IS THE 0480 BEHAVIOUR, unchanged, for the same reason.
Add-Case 'ctl_unbraced_form' @'
///|
fn b2() -> Char {
  '\u007f'
}
'@ 'ACCEPT'

# ctl_byte_form -- `b'\xNN'` is legal MoonBit (0459) and the corpus writes it
# 58 times.
Add-Case 'ctl_byte_form' @'
///|
fn b3() -> Byte {
  b'\x41'
}
'@ 'ACCEPT'

# --- THE SUPPLEMENTARY PLANE. The item this increment was named for. -------
Add-Case 'r01_two_digits' @'
///|
fn a() -> Char {
  '\u{7F}'
}
'@ 'ACCEPT'

Add-Case 'r02_four_digits' @'
///|
fn a() -> Char {
  '\u{FFFF}'
}
'@ 'ACCEPT'

# r03 IS THE WITNESS'S OWN SHAPE: `moonbitlang/core`
# `string/quickcheck_test.mbt:138` writes `'\u{10000}'`.
Add-Case 'r03_astral_first' @'
///|
fn a() -> Char {
  '\u{10000}'
}
'@ 'ACCEPT'

Add-Case 'r04_astral_emoji' @'
///|
fn a() -> Char {
  '\u{1F600}'
}
'@ 'ACCEPT'

Add-Case 'r05_astral_max' @'
///|
fn a() -> Char {
  '\u{10FFFF}'
}
'@ 'ACCEPT'

# r06 IS THE CRASH. A code point past the last one is REJECT(4064) by the
# toolchain, and it used to take the whole scan down with it.
Add-Case 'r06_above_max' @'
///|
fn a() -> Char {
  '\u{110000}'
}
'@ 'REJECT'

Add-Case 'r07_surrogate_lo' @'
///|
fn a() -> Char {
  '\u{D800}'
}
'@ 'REJECT'

Add-Case 'r08_surrogate_hi' @'
///|
fn a() -> Char {
  '\u{DFFF}'
}
'@ 'REJECT'

# r09 AND r10 ARE THE EDGES OF THE SURROGATE RANGE, and they are the control
# for r07 and r08: a guard that refused everything from U+D800 upwards would
# pass those two and fail these two.
Add-Case 'r09_below_surrogate' @'
///|
fn a() -> Char {
  '\u{D7FF}'
}
'@ 'ACCEPT'

Add-Case 'r10_above_surrogate' @'
///|
fn a() -> Char {
  '\u{E000}'
}
'@ 'ACCEPT'

Add-Case 'r11_six_digits_past_max' @'
///|
fn a() -> Char {
  '\u{FFFFFF}'
}
'@ 'REJECT'

# r12 AND r13 ARE THE DIGEST CEILING. r13's value is 0xFFFFFFFF, which does
# not fit in the reader's Int32 accumulator -- a reader that took every digit
# would overflow on the way to a value it was going to refuse anyway.
Add-Case 'r12_seven_digits' @'
///|
fn a() -> Char {
  '\u{1000000}'
}
'@ 'REJECT'

Add-Case 'r13_eight_digits' @'
///|
fn a() -> Char {
  '\u{FFFFFFFF}'
}
'@ 'REJECT'

Add-Case 'r14_empty_braces' @'
///|
fn a() -> Char {
  '\u{}'
}
'@ 'REJECT'

Add-Case 'r15_no_closer' @'
///|
fn a() -> Char {
  '\u{7F'
}
'@ 'REJECT'

Add-Case 'r16_zero' @'
///|
fn a() -> Char {
  '\u{0}'
}
'@ 'ACCEPT'

# --- THE UNBRACED FORM. 0480's rule, re-pinned here beside the braced one. ---
Add-Case 'r17_unbraced_four' @'
///|
fn a() -> Char {
  '\u007f'
}
'@ 'ACCEPT'

Add-Case 'r18_unbraced_three' @'
///|
fn a() -> Char {
  '\u07f'
}
'@ 'REJECT'

Add-Case 'r19_unbraced_six' @'
///|
fn a() -> Char {
  '\u00007f'
}
'@ 'REJECT'

# --- THE BYTE FORM. `b'\xNN'` is legal; a unicode escape is not. ------------
Add-Case 'r20_byte_braced' @'
///|
fn a() -> Byte {
  b'\u{41}'
}
'@ 'REJECT'

Add-Case 'r21_byte_unbraced' @'
///|
fn a() -> Byte {
  b'\u000C'
}
'@ 'REJECT'

# --- THE HEX ESCAPE TAKES EXACTLY TWO DIGITS. -------------------------------
# r25 is the one that matters: 0x4142 is a valid code point, so a reader that
# took a RUN of hex digits would produce a plausible-looking character rather
# than an obvious mistake.
Add-Case 'r23_hex_one_digit' @'
///|
fn a() -> Char {
  '\x4'
}
'@ 'REJECT'

Add-Case 'r24_hex_three_digits' @'
///|
fn a() -> Char {
  '\x414'
}
'@ 'REJECT'

Add-Case 'r25_hex_four_digits' @'
///|
fn a() -> Char {
  '\x4142'
}
'@ 'REJECT'

Add-Case 'r26_hex_not_hex' @'
///|
fn a() -> Char {
  '\xZZ'
}
'@ 'REJECT'

# --- A DIRECT ASTRAL CHARACTER, not an escape. -----------------------------
# The same length check refused it, and the toolchain accepts it.
#
# THE CHARACTER IS BUILT AT RUNTIME, not written into this file. PowerShell 5.1
# reads a BOM-less `.ps1` as the ANSI codepage, so a literal emoji in a
# here-string arrives as MOJIBAKE -- and the row then measures a file full of
# nonsense instead of the astral character. That is not a theory: the first
# version of this row had the emoji typed in, and it came back
# REJECT(3001,4021,3001) for a reason that had nothing to do with escapes.
$astral = [string][char]::ConvertFromUtf32(0x1F600)
Add-Case 'r27_direct_astral' ("///|`nfn a() -> Char {`n  '" + $astral + "'`n}`n") 'ACCEPT'

# --- AND THE LENGTH RULE STILL HAS TEETH. ----------------------------------
Add-Case 'r29_two_characters' @'
///|
fn a() -> Char {
  'ab'
}
'@ 'REJECT'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0496_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0496`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
    if ($want -eq 'ACCEPT') { $ok = $false } else { $ok = $true }
  } else {
    $got = 'ACCEPT'
    $ok = ($want -eq 'ACCEPT')
  }
  Write-Output ('{0,-42} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown|Unknown|unexpected' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All five controls must behave.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

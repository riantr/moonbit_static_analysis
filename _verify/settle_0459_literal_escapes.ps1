# Settle 0459 -- literal escapes: `b'...'` byte strings and `\u{...}` char literals.
#
# THE BLOCKER, ranked by files actually unblocked rather than by how often it was
# discussed. Across the six pinned corpora the NOTPARSE tally is:
#
#     46x  character literal must hold exactly one character   (28 async, 9 image,
#                                                           5 labeler, 4 proton)
#
# which is the largest single construct left. MEASURED cause, from five one-line
# probes run through the scanner itself rather than reasoned about:
#
#     let x = '\u{0}'     -> character literal must hold exactly one character
#     let x = b'\x00'     -> character literal must hold exactly one character
#     let x = '\\'        -> clean
#     let x = '\n'        -> clean
#     let x = 'ab'        -> character literal must hold exactly one character  (correct)
#
# Two distinct defects behind one message, and they have very different sizes:
#
#   b'\x..'   58 files  (async 32, image 15, labeler 6, proton 5, moui 0)
#   '\u{..}'  19 files  (async 11, moui 4, labeler 3, proton 1)
#
# `lex_string` HAS a byte-string caller, but it fires only on a DOUBLE quote
# (`lexer.mbt:353`, `self.chars[self.pos + 1] == '"'`). The corpus writes the
# single-quoted form, so `b` lexes as an identifier, the `'\x00'` becomes a
# character literal, and the payload is four characters long -- hence the message.
# That single double-quote test is the whole reason 58 files stop.
#
# `lex_char` handles `\n`, `\t`, `\r` and passes every other escape through as its
# own character, so `\u{0}` becomes the four-character string `u{0}`.
#
# => 判据: a file count is not a leverage count, but a BLOCKER MESSAGE is not
# necessarily a construct. One message here covers two unrelated lexer gaps of very
# different sizes, and only probing separated them. "46 files are blocked on
# character literals" would have been a correct statement and a useless one.
#
# SCAFFOLD, the same traps as settle_0456/0457/0458:
#   * single package, `source = "src"`, NO root-level `main` (4069)
#   * every fixture is a real `fn`, because a top-level `let` is not a declaration
#   * `ignore(x)` so the binding is used (unused is a warning, not an error, but a
#     warning-free fixture means a REJECT can only mean the construct)
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# THE CANARY.
Add-Case 'ctl_missing' @'
///|
fn probe() -> Int {
  ignore(ZzMissing)
  0
}
'@ 'REJECT'

# THE 58-FILE ROW: a single-quoted byte string with a hex escape.
Add-Case 'byte_single_hex' @'
///|
fn probe() -> Byte {
  b'\x00'
}
'@ 'ACCEPT'

# THE SAME BYTE STRING, DOUBLE QUOTED. This is the form `lexer.mbt:353` already
# handles and the corpus does not write, so it ACCEPTs today. It is here as the
# control that says the fixture is about the QUOTE and not about byte strings or
# about hex escapes: if this rejected, the 58-file row would be misattributed.
Add-Case 'byte_double_hex_control' @'
///|
fn probe() -> Bytes {
  b"\x00"
}
'@ 'ACCEPT'

# A single-quoted byte literal with NO escape, so the row above cannot be explained
# by `\x` alone.
#
# THE TYPE IS `Byte`, NOT `Bytes`, and the first draft of this row said `Bytes` and
# was REJECTed for it: `has type : Byte, wanted : Bytes`. A single-quoted `b'...'`
# is ONE byte; the double-quoted `b"..."` is the byte STRING. The distinction is
# why the two rows above it differ only by a quote and why the corpus writes the
# single-quoted form for NUL sentinels like `b'\x00'`.
Add-Case 'byte_single_one_char' @'
///|
fn probe() -> Byte {
  b'a'
}
'@ 'ACCEPT'

# The control that must keep rejecting: a single-quoted byte literal really does
# hold exactly one byte, so `b'ab'` is REJECT(3001). Without it, "the 58-file row
# accepts" could be a fact about byte literals being unchecked rather than about
# the lexer handling them.
Add-Case 'ctl_byte_single_two_chars' @'
///|
fn probe() -> Byte {
  b'ab'
}
'@ 'REJECT'

# THE 19-FILE ROW: a unicode escape in a character literal.
Add-Case 'char_u_brace' @'
///|
fn probe() -> Char {
  '\u{0}'
}
'@ 'ACCEPT'

# The escape is not just an ASCII code point, so the fix cannot be "read two hex
# digits after a backslash". This is the row that decides the shape of the repair.
Add-Case 'char_u_brace_wide' @'
///|
fn probe() -> Char {
  '\u{1F600}'
}
'@ 'ACCEPT'

# THE CONTROL THAT IS ALREADY CORRECT. A char literal really must hold one
# character, so this must keep rejecting. If it ACCEPTed, then the
# "character literal must hold exactly one character" message is not a check at
# all and the 46-file tally means nothing.
Add-Case 'ctl_multi_char_literal' @'
///|
fn probe() -> Char {
  'ab'
}
'@ 'REJECT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0459_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0459`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the grammar. The canary must REJECT, and so must'
  Write-Output '`ctl_multi_char_literal` -- if a two-character literal is accepted then the check'
  Write-Output 'behind the 46-file tally is not a check and the tally means nothing.'
  exit 1
}
Write-Output 'GATE OK: single-quoted byte strings and `\u{...}` escapes are both legal MoonBit,'
Write-Output 'while a genuinely two-character literal is still rejected. So the 46 blocked files'
Write-Output 'are two lexer gaps behind one message, not a rule the analyzer is applying.'
exit 0

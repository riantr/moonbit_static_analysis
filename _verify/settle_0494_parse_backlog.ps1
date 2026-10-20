# settle 0494 -- THE FOUR PARSE BACKLOG SHAPES, settled against the toolchain.
#
# WHAT THIS SETTLES. The async corpus is 415/419 readable; the four files it cannot
# read are each stopped by a SHAPE this frontend does not read yet. This script asks
# the TOOLCHAIN what those shapes are, because the analyzer's claim -- "I do not
# understand this" -- is only worth changing if the toolchain understands it.
#
# THE FOUR, and the corpus line each came from:
#
#   A  src/http/request.mbt:59        re"..." AND `=~`
#      if host =~ (
#          re"^" + (re".*" as host) + re":" + (re"[0-9]+" as port_str) + re"$"
#        ) {
#      The scanner says "expected ')'". Two constructs are involved, not one: the
#      REGEX LITERAL and the `=~` OPERATOR. Settling only the literal would leave
#      the file unreadable for a second reason.
#
#   B  src/http/utils.mbt:23          a for-header whose UPDATE clause is a LIST
#      for x = value, i = len - 1; i >= 0; x = x / base, i = i - 1 {
#      The scanner says "expected '{'". The INITIALIZER may already be a list
#      (settled at 0472); the UPDATE may not.
#
#   C  src/fs/watch_kqueue.mbt:240     a SHORTHAND struct pattern in `let` position
#      let { identity, .. } = self.watched[fd]
#      The scanner says "expected binding name". The braced pattern reader exists
#      (0485) but reads the KEYED spelling `{ "cmd": [cmd], .. }`; this one has a
#      bare name in FIELD position.
#
#   D  src/fs/watch_windows.mbt:320    a `>..` descending range AND `break <value>`
#      for i in path.length()>..0 {
#        if path[i] is ('/' | '\\') { break path[:i] }
#      } nobreak { "" }
#      The scanner says "unexpected token `.`". TWO shapes again: the descending
#      range operator and a `break` that carries a value.
#
# Every ACCEPT row below is code the toolchain must accept, and every REJECT row is
# a CONTROL -- a shape the toolchain must REFUSE, so that "the analyzer must stay
# silent on it" cannot be satisfied by silencing everything.
#
# A row whose Expect is '?' is MEASURED and not claimed: the author does not know
# the verdict, and the settle prints it rather than asserting it. Those rows are
# where a wrong guess would otherwise hide.
#
# `moon.mod` is NOT JSON. It is `key = "value"`. A package is a DIRECTORY:
# `src/<pkg>` with its own `moon.pkg`. A bare `moon.mod` plus a flat `src/*.mbt`
# is silently NOT a project the toolchain checks -- `moon check` prints "no work to
# do" and exits 0, which is a VACUOUS ACCEPT.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('parsebacklog_' + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$moon = 'C:\Users\31379\.moon\bin\moon.exe'

$rows = @(
  # ------------------------------------------------------------------ A: regex
  @{ Name = 'a1_regex_literal_and_match_op'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `re"..."` and `=~` together'
     Body = @'
fn probe(s : String) -> Bool {
  s =~ re"^a"
}
'@ }
  @{ Name = 'a2_regex_literal_alone'; Expect = 'ACCEPT'
     Note = 'the literal on its own -- a binding, no operator'
     Body = @'
fn probe() -> Regex {
  re"^a"
}
'@ }
  @{ Name = 'a3_match_result_is_bool'; Expect = 'ACCEPT'
     Note = 'the result of `=~` is a Bool'
     Body = @'
fn probe(s : String) -> Bool {
  let b : Bool = s =~ re"^a"
  b
}
'@ }
  @{ Name = 'a4_control_match_result_is_not_int'; Expect = 'REJECT'
     Note = 'the control on a3: the result is not an Int'
     Body = @'
fn probe(s : String) -> Int {
  let b : Int = s =~ re"^a"
  b
}
'@ }
  @{ Name = 'a5_control_regex_literal_is_not_a_string'; Expect = 'REJECT'
     Note = 'the control on a2: a Regex is not a String'
     Body = @'
fn probe() -> String {
  re"^a"
}
'@ }
  @{ Name = 'a6_regex_concatenation'; Expect = 'ACCEPT'
     Note = 'the corpus concatenation of two regex literals'
     Body = @'
fn probe(s : String) -> Bool {
  s =~ (re"^" + re".*")
}
'@ }
  @{ Name = 'a7_control_bare_regex_name'; Expect = 'REJECT'
     Note = '`re` alone is an ordinary name, not a literal'
     Body = @'
fn probe() -> Int {
  re
}
'@ }

  # ------------------------------------------------------------------ B: for update list
  @{ Name = 'b1_for_update_is_a_list'; Expect = 'ACCEPT'
     Note = 'the corpus shape: two assignments in the update clause'
     Body = @'
fn probe(value : Int, base : Int, len : Int) -> Unit {
  for x = value, i = len - 1; i >= 0; x = x / base, i = i - 1 {
    ignore(x)
  }
}
'@ }
  @{ Name = 'b2_for_update_is_one_assignment'; Expect = 'ACCEPT'
     Note = 'the shape that already works'
     Body = @'
fn probe(len : Int) -> Unit {
  for i = 0; i < len; i = i + 1 {
    ignore(i)
  }
}
'@ }
  @{ Name = 'b3_control_for_update_binds_a_new_name'; Expect = 'REJECT'
     Note = 'the update may only ASSIGN the declared names'
     Body = @'
fn probe(len : Int) -> Unit {
  for i = 0; i < len; j = j + 1 {
    ignore(i)
  }
}
'@ }
  @{ Name = 'b4_control_for_init_cannot_use_let'; Expect = 'REJECT'
     Note = 'the pre-existing rule (settled at 0470)'
     Body = @'
fn probe(len : Int) -> Unit {
  for let i = 0; i < len; i = i + 1 {
    ignore(i)
  }
}
'@ }

  # ------------------------------------------------------------------ C: shorthand struct pattern
  @{ Name = 'c1_let_shorthand_struct_pattern'; Expect = 'ACCEPT'
     Note = 'the corpus shape: a bare field name plus a rest'
     Body = @'
struct S {
  identity : Int
  other : Int
}

fn probe(s : S) -> Unit {
  let { identity, .. } = s
  ignore(identity)
}
'@ }
  @{ Name = 'c2_let_shorthand_without_rest'; Expect = 'ACCEPT'
     Note = 'the same without the rest'
     Body = @'
struct S {
  identity : Int
  other : Int
}

fn probe(s : S) -> Unit {
  let { identity } = s
  ignore(identity)
}
'@ }
  @{ Name = 'c3_control_let_keyed_struct_pattern'; Expect = 'REJECT'
     Note = 'the KEYED spelling is refused (0011, a `let` pattern must be irrefutable)'
     Body = @'
struct S {
  identity : Int
}

fn probe(s : S) -> Unit {
  let { "identity": identity, .. } = s
  ignore(identity)
}
'@ }
  @{ Name = 'c4_control_let_struct_pattern_unknown_field'; Expect = 'REJECT'
     Note = 'a field the struct does not have'
     Body = @'
struct S {
  identity : Int
}

fn probe(s : S) -> Unit {
  let { missing, .. } = s
  ignore(missing)
}
'@ }

  # ------------------------------------------------------------------ D: >.. and break <value>
  @{ Name = 'd1_descending_range'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `>..`'
     Body = @'
fn probe(n : Int) -> Unit {
  for i in n>..0 {
    ignore(i)
  }
}
'@ }
  @{ Name = 'd2_break_with_a_value'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `break path[:i]` -- path is a StringView there'
     Body = @'
fn probe(path : StringView) -> StringView {
  for i in path.length()>..0 {
    if path[i] is ('/' | '\\') {
      break path[:i]
    }
  } nobreak {
    ""
  }
}
'@ }
  @{ Name = 'd3_control_bare_range_is_rejected'; Expect = 'REJECT'
     Note = 'a bare `..` is not a range'
     Body = @'
fn probe(n : Int) -> Unit {
  for i in n..0 {
    ignore(i)
  }
}
'@ }
  @{ Name = 'd4_control_bare_break_is_accepted'; Expect = 'ACCEPT'
     Note = 'a `break` with no value -- the shape that already works'
     Body = @'
fn probe(n : Int) -> Int {
  for i in n..<10 {
    break
  }
  0
}
'@ }
  @{ Name = 'd5_control_descending_range_inclusive_spelling'; Expect = 'REJECT'
     Note = 'there is NO inclusive descending spelling -- MEASURED, not claimed'
     Body = @'
fn probe(n : Int) -> Unit {
  for i in n>..=0 {
    ignore(i)
  }
}
'@ }
  @{ Name = 'd6_regex_character_class_body'; Expect = 'ACCEPT'
     Note = 'the corpus own `re"[0-9]+"` -- a character class INSIDE a regex'
     Body = @'
fn probe(s : String) -> Bool {
  s =~ re"[0-9]+"
}
'@ }
  @{ Name = 'd7_control_bare_range_with_a_break_value'; Expect = 'REJECT'
     Note = 'a bare `..` makes the `nobreak` unexpected -- 4108'
     Body = @'
fn probe(path : StringView) -> StringView {
  for i in path.length()..0 {
    break path[:i]
  } nobreak {
    ""
  }
}
'@ }
)

Write-Output 'toolchain: ' ((& $moon version) | Out-String).Trim()
Write-Output ('scratch:    ' + $root)
Write-Output ''
Write-Output ('{0,-46} {1,-8} {2,-62} {3,-8} {4}' -f 'ROW', 'EXPECT', 'NOTE', 'ACTUAL', 'THE TOOLCHAIN SAYS')
Write-Output ('-' * 200)

$bad = 0
$rejects = 0
$measured = 0
foreach ($r in $rows) {
  $proj = Join-Path $root $r.Name
  $pkg  = Join-Path $proj 'src\main'
  New-Item -ItemType Directory -Force -Path $pkg | Out-Null
  $mod = "name = `"$($r.Name)`"`n`nversion = `"0.1.0`"`n"
  [System.IO.File]::WriteAllText((Join-Path $proj 'moon.mod'), $mod, (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $pkg 'moon.pkg'), "import {`n}`n", (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $pkg 'a.mbt'), $r.Body, (New-Object System.Text.UTF8Encoding($false)))

  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = (& $moon -C $proj check 2>&1 | Out-String)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $actual = if ($code -eq 0) { 'ACCEPT' } else { 'REJECT' }
  if ($actual -eq 'REJECT') { $rejects++ }
  $why = ''
  $codes = @()
  foreach ($ln in ($o -split "`r?`n")) {
    if ($ln -match '(?i)\berror\b' -and $ln -notmatch 'FullyQualifiedErrorId|NativeCommandError|CategoryInfo|^\s*\+|^At ') {
      $why = $ln.Trim()
    }
    foreach ($m in [regex]::Matches($ln, '\b(4\d{3})\b')) { $codes += $m.Groups[1].Value }
  }
  $codeStr = if ($codes.Count -gt 0) { ' [' + (($codes | Select-Object -Unique) -join ',') + ']' } else { '' }
  if ($why.Length -gt 90) { $why = $why.Substring(0, 90) + '...' }
  if ($r.Expect -eq '?') {
    $measured++
    $verdict = '  (measured)'
  } elseif ($actual -ne $r.Expect) {
    $bad++
    $verdict = '  <<< DIFFERS'
  } else {
    $verdict = ''
  }
  Write-Output ('{0,-46} {1,-8} {2,-62} {3,-8} {4}{5}{6}' -f $r.Name, $r.Expect, $r.Note, $actual, $why, $codeStr, $verdict)
}
Write-Output ''
Write-Output ("rows: " + $rows.Count + "   controls that REJECTED: " + $rejects + "   rows MEASURED: " + $measured)
if ($bad -eq 0) {
  Write-Output 'ALL EXPECTED ROWS MATCH THE EXPECTED VERDICT on the installed toolchain.'
} else {
  Write-Output ($bad.ToString() + ' ROW(S) DIFFER FROM THE EXPECTED VERDICT.')
}
if ($bad -gt 0) { exit 1 }
exit 0

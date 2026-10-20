# 0490 -- the INTRINSIC FAMILY under the RE-SPELLING. The generator's intrinsic
# list is HAND-WRITTEN, and the toolchain re-spelled two of the type names it
# names.
#
# THE SPELLING CHANGE, AND ITS VERSION. The canonical spelling of the two
# unsuffixed integer types changed on 0.1.20261012 -- `Int` is now `Int32`,
# `UInt` is now `UInt32` -- and the TYPE did not change: MoonBit's own Language
# Fundamentals page says "Int and UInt remain accepted as aliases of Int32 and
# UInt32. The formatter uses the explicit-width names Int32 and UInt32."
# (https://docs.moonbitlang.com/en/latest/language/fundamentals.html)
#
# WHY. The re-spelling is not confined to the interfaces. The generator keeps a
# hand-written list of the compiler intrinsics -- the names no `pkg.generated.mbti`
# declares, so no extraction can find them: `Array::make` among them, and the
# whole `T::to_json` family. That list is spelled with the OLD type names:
# `Int::to_json`, `UInt::to_json`, `Int::unsafe_to_char`.
#
# The regenerated table therefore has a HOLE that no amount of extraction can
# fill and no amount of carrying-forward can fill either -- the old table never
# had `Int32::to_json`, because `Int32` did not exist:
#
#     Int32::to_json   0   <- a valid call, and the table has never heard of it
#     UInt32::to_json  0
#
# The generator's own header says the intrinsic list is "transcribed, not
# composed", and that a first version of it GUESSED `UInt32::to_json` into
# existence and dropped `Unit::to_json`, which the superset check caught
# immediately. So the repaired list has to be SETTLED, not composed: every row
# below is its own package, the toolchain's own diagnostic is printed, and a
# control module that must be rejected sits beside them.
#
# `moon.mod` is NOT JSON. It is `key = "value"`, and a JSON body is a PARSE
# ERROR that the toolchain reports as "Failed to calculate build plan" -- a
# build failure that looks like a settle verdict and is neither.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP 'dir2intrinsic_rows'
if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }

$rows = @(
  @{ Name = 't1_int32_to_json';   Expect = '?'; Note = 'Int32::to_json -- the NEW spelling of the family'
     Body = @'
fn f(x : Int32) -> Json {
  Int32::to_json(x)
}
'@ }
  @{ Name = 't2_int_to_json';     Expect = '?'; Note = 'Int::to_json -- the OLD spelling'
     Body = @'
fn f(x : Int) -> Json {
  Int::to_json(x)
}
'@ }
  @{ Name = 't3_uint32_to_json';  Expect = '?'; Note = 'UInt32::to_json -- the NEW unsigned spelling'
     Body = @'
fn f(x : UInt32) -> Json {
  UInt32::to_json(x)
}
'@ }
  @{ Name = 't4_uint_to_json';    Expect = '?'; Note = 'UInt::to_json -- the OLD unsigned spelling'
     Body = @'
fn f(x : UInt) -> Json {
  UInt::to_json(x)
}
'@ }
  @{ Name = 't5_int32_unsafe';    Expect = '?'; Note = 'Int32::unsafe_to_char -- the NEW spelling'
     Body = @'
fn f(x : Int32) -> Char {
  Int32::unsafe_to_char(x)
}
'@ }
  @{ Name = 't6_int_unsafe';      Expect = '?'; Note = 'Int::unsafe_to_char -- the OLD spelling'
     Body = @'
fn f(x : Int) -> Char {
  Int::unsafe_to_char(x)
}
'@ }
  @{ Name = 't7_unit_to_json';    Expect = '?'; Note = 'Unit::to_json -- a name the first list DROPPED'
     Body = @'
fn f(x : Unit) -> Json {
  Unit::to_json(x)
}
'@ }
  @{ Name = 't8_control';         Expect = 'REJECT'; Note = 'Int32::to_jsonnope -- the CONTROL'
     Body = @'
fn f(x : Int32) -> Json {
  Int32::to_jsonnope(x)
}
'@ }
  @{ Name = 't9_uint32_unsafe';   Expect = '?'; Note = 'UInt32::unsafe_to_char -- does the UNSIGNED side have it?'
     Body = @'
fn f(x : UInt32) -> Char {
  UInt32::unsafe_to_char(x)
}
'@ }
  # The other intrinsics name types the re-spelling did NOT touch, so they are
  # here as the CONTROL that the re-spelling is NARROW: a list of names that must
  # keep working exactly as they did.
  @{ Name = 't10_untouched_intrinsics'; Expect = '?'; Note = 'Array::make / Map::new / Option::None / StringBuilder::new'
     Body = @'
fn f() -> Array[Int] {
  let a = Array::make(2, 0)
  let m = Map::new()
  let s = StringBuilder::new()
  let n = Option::None
  a
}
'@ }
)

foreach ($r in $rows) {
  $pkg = Join-Path $root $r.Name
  $src = Join-Path $pkg ('src\' + $r.Name)
  New-Item -ItemType Directory -Force -Path $src | Out-Null
  $mod = @"
name = "$($r.Name)"

version = "0.1.0"
"@
  [System.IO.File]::WriteAllText((Join-Path $pkg 'moon.mod'), $mod, (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $src 'moon.pkg'), "import {`n}`n", (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $src ($r.Name + '.mbt')), $r.Body, (New-Object System.Text.UTF8Encoding($false)))
}

$moon = 'C:\Users\31379\.moon\bin\moon.exe'
Write-Output ('toolchain: ' + (((& $moon version) | Out-String) -split "`r?`n")[0].Trim())
Write-Output ''
Write-Output ('{0,-28} {1,-8} {2,-52} {3,-8} {4}' -f 'ROW', 'EXPECT', 'NOTE', 'ACTUAL', 'THE TOOLCHAIN SAYS')
Write-Output ('-' * 170)

$bad = 0
foreach ($r in $rows) {
  $pkg = Join-Path $root $r.Name
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = (& $moon -C $pkg check 2>&1 | Out-String)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $actual = if ($code -eq 0) { 'ACCEPT' } else { 'REJECT' }
  $why = ''
  $codes = @()
  foreach ($ln in ($o -split "`r?`n")) {
    if ($ln -match '(?i)\berror\b' -and $ln -notmatch 'FullyQualifiedErrorId|NativeCommandError|CategoryInfo|^\s*\+|^At ') {
      $why = $ln.Trim()
    }
    foreach ($m in [regex]::Matches($ln, '\b(4\d{3})\b')) { $codes += $m.Groups[1].Value }
  }
  $codeStr = if ($codes.Count -gt 0) { ' [' + (($codes | Select-Object -Unique) -join ',') + ']' } else { '' }
  if ($why.Length -gt 80) { $why = $why.Substring(0, 80) + '...' }
  if ($r.Expect -ne '?') {
    if ($actual -ne $r.Expect) { $bad++ }
    $verdict = if ($actual -eq $r.Expect) { '' } else { '  <<< DIFFERS' }
  } else {
    $verdict = '  (measured)'
  }
  Write-Output ('{0,-28} {1,-8} {2,-52} {3,-8} {4}{5}{6}' -f $r.Name, $r.Expect, $r.Note, $actual, $why, $codeStr, $verdict)
}
Write-Output ''
if ($bad -eq 0) {
  Write-Output 'ALL EXPECTED ROWS MATCH THE EXPECTED VERDICT on the installed toolchain.'
} else {
  Write-Output ($bad.ToString() + ' ROW(S) DIFFER FROM THE EXPECTED VERDICT.')
}

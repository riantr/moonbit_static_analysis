# 0490 -- the `Int32` SPELLING: is it a type a user can WRITE, or only the
# spelling the toolchain EMITS?
#
# WHY THIS FILE EXISTS. The 0490 release gate failed its own self-scan with 37
# actionable findings, and every one of them was the SAME finding:
#
#     unknown type 'Int32' in interface signature
#
# in the analyzer's OWN `src/*/pkg.generated.mbti` files. The cause is not the
# analyzer's source -- it is that the toolchain CHANGED THE CANONICAL SPELLING
# of the two unsuffixed integer types, and the interfaces it generates say so:
#
#     -pub fn pos(Int, Int) -> Pos
#     +pub fn pos(Int32, Int32) -> Pos
#
# THE VERSION THAT DID IT IS 0.1.20261012, not 0.1.20261016 -- a distinction
# this file's own first draft got wrong, and the repository already had right
# in `src/types/types_0422_test.mbt`: "0.1.20261012 renamed the default integer
# type to `Int32`". The type did NOT change; the CANONICAL SPELLING did, and
# `Int` remains accepted as an alias. MoonBit's own Language Fundamentals page
# says so:
#
#     Int and UInt remain accepted as aliases of Int32 and UInt32.
#     The formatter uses the explicit-width names Int32 and UInt32.
#
# (https://docs.moonbitlang.com/en/latest/language/fundamentals.html)
# 0.1.20261016 is the version that started REWRITING this repository's own
# `src/*/pkg.generated.mbti` -- the upgrade was done by ANOTHER process on this
# machine at 2026-10-20 00:54:16, mid-gate (see the NARRATIVE) -- and that is
# what put the stale `Int` spelling in front of the analyzer's self-scan.
#
# The analyzer's `.mbti` frontend resolves a signature's type names against the
# builtin list, and that list carries `Int` and not `Int32`. So every interface
# the new toolchain generates produces a FALSE POSITIVE, on a type the
# toolchain itself just wrote. The type lens already knows the two are one
# type -- `src/types/types.mbt` maps `"Int" | "Int32" | "int"` to `TInt` -- so
# the interface lens is the odd one out.
#
# THE QUESTION THIS SETTLES. The fix has two possible shapes and they are not
# the same fix:
#
#   (a) `Int32` is a NAME A USER CAN WRITE. Then it belongs in the ambient
#       list beside `Int`, and the `.mbt` lenses need it too -- a user writing
#       `let x : Int32 = 1` would otherwise be told `no visible binding for
#       'Int32'` on code `moon check` accepts.
#   (b) `Int32` is only the spelling the toolchain EMITS and a user cannot
#       write it. Then it does NOT belong in the ambient list, and the fix
#       belongs in the `.mbti` frontend alone, as a canonicalisation of the
#       name it reads.
#
# (a) and (b) are answered by DIFFERENT rows, so they are different packages.
# A row that accepted a spelling the toolchain rejects would put `Int32` in
# the ambient list and SUPPRESS a true finding; a row that rejected a spelling
# the toolchain accepts would leave a false positive in place. The rows below
# are one package each so one row's error cannot mask another's, and the
# toolchain's OWN diagnostic text is printed -- "REJECT" on its own says
# nothing about WHICH rule rejected it.
#
# `moon.mod` is NOT JSON. It is `key = "value"`, and a JSON body is a PARSE
# ERROR: "unexpected token { at line 1, column 1", which the toolchain reports
# as "Failed to calculate build plan" -- a build failure that looks like a
# settle verdict and is neither.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP 'dir2int32_rows'
if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }

$rows = @(
  @{ Name = 's1_int_annotation';    Expect = '?'; Note = 'let x : Int = 1 -- the OLD spelling'
     Body = @'
fn take(x : Int) -> Int {
  x
}

fn use_int() -> Int {
  let x : Int = 1
  take(x)
}
'@ }
  @{ Name = 's2_int32_annotation';  Expect = '?'; Note = 'let x : Int32 = 1 -- the NEW spelling'
     Body = @'
fn take(x : Int32) -> Int32 {
  x
}

fn use_int32() -> Int32 {
  let x : Int32 = 1
  take(x)
}
'@ }
  @{ Name = 's3_control_bad_type';  Expect = 'REJECT'; Note = 'a type that cannot exist -- the CONTROL'
     Body = @'
fn take(x : NotATypeAtAll) -> NotATypeAtAll {
  x
}
'@ }
  @{ Name = 's4_int32_to_int';      Expect = '?'; Note = 'fn f(x : Int32) -> Int -- the two INTERCHANGEABLE?'
     Body = @'
fn widen(x : Int32) -> Int {
  x
}
'@ }
  @{ Name = 's5_int_to_int32';      Expect = '?'; Note = 'fn f(x : Int) -> Int32 -- the other direction'
     Body = @'
fn narrow(x : Int) -> Int32 {
  x
}
'@ }
  @{ Name = 's6_array_int32';       Expect = '?'; Note = 'Array[Int32] -- a GENERIC argument'
     Body = @'
fn count(xs : Array[Int32]) -> Int {
  xs.length()
}
'@ }
  @{ Name = 's7_map_int32';         Expect = '?'; Note = 'Map[String, Int32] -- a nested generic argument'
     Body = @'
fn size(m : Map[String, Int32]) -> Int {
  m.size()
}
'@ }
  @{ Name = 's8_int32_alias';       Expect = '?'; Note = 'type MyInt = Int32 -- an ALIAS of the new spelling'
     Body = @'
type MyInt = Int32

fn take(x : MyInt) -> MyInt {
  x
}
'@ }
  @{ Name = 's9_int32_value_use';   Expect = '?'; Note = 'a VALUE of type Int32 used as an Int'
     Body = @'
fn add(a : Int32, b : Int32) -> Int {
  a + b
}
'@ }
  @{ Name = 's10_const_shape_control'; Expect = 'REJECT'; Note = 'const in this package shape -- rejected for ANY annotation'
     Body = @'
const limit : Int32 = 10

fn read_limit() -> Int {
  limit
}
'@ }
  # --- the SAME rename, on the UNSIGNED side ---------------------------------
  # The toolchain renamed TWO types, not one: `UInt` is now `UInt32`, the same
  # way `Int` is now `Int32`. `Int16` and `UInt16` kept their names -- the
  # rename is of the UNSUFFIXED ones only, which is what makes it a rename
  # rather than a widening.
  @{ Name = 's11_uint_annotation';   Expect = '?'; Note = 'let x : UInt = 1 -- the OLD unsigned spelling'
     Body = @'
fn take(x : UInt) -> UInt {
  x
}

fn use_uint() -> UInt {
  let x : UInt = 1
  take(x)
}
'@ }
  @{ Name = 's12_uint32_annotation'; Expect = '?'; Note = 'let x : UInt32 = 1 -- the NEW unsigned spelling'
     Body = @'
fn take(x : UInt32) -> UInt32 {
  x
}

fn use_uint32() -> UInt32 {
  let x : UInt32 = 1
  take(x)
}
'@ }
  @{ Name = 's13_uint32_to_uint';   Expect = '?'; Note = 'fn f(x : UInt32) -> UInt -- the two INTERCHANGEABLE?'
     Body = @'
fn widen(x : UInt32) -> UInt {
  x
}
'@ }
  @{ Name = 's14_uint_to_uint32';   Expect = '?'; Note = 'fn f(x : UInt) -> UInt32 -- the other direction'
     Body = @'
fn narrow(x : UInt) -> UInt32 {
  x
}
'@ }
  @{ Name = 's15_int16_kept';       Expect = '?'; Note = 'Int16 -- a WIDTH-SUFFIXED name the rename did NOT touch'
     Body = @'
fn take(x : Int16) -> Int16 {
  x
}

fn use_int16() -> Int16 {
  let x : Int16 = 1
  take(x)
}
'@ }
  @{ Name = 's16_uint16_kept';      Expect = '?'; Note = 'UInt16 -- likewise'
     Body = @'
fn take(x : UInt16) -> UInt16 {
  x
}

fn use_uint16() -> UInt16 {
  let x : UInt16 = 1
  take(x)
}
'@ }
  # --- the METHOD table, which is the other face of the same rename ---------
  # The type name is one half. The other half is the METHODS: the toolchain
  # declares all 44 of the integer type's methods under `Int32::` and NONE
  # under `Int::`, so a user who writes `Int32::popcnt(x)` -- or whose
  # `moon fmt` rewrote `Int::popcnt` into `Int32::popcnt` -- is calling a
  # name the analyzer's table has never heard of.
  @{ Name = 's17_int32_method';    Expect = '?'; Note = 'Int32::popcnt -- a method under the NEW spelling'
     Body = @'
fn f(x : Int32) -> Int32 {
  Int32::popcnt(x)
}
'@ }
  @{ Name = 's18_int_method';      Expect = '?'; Note = 'Int::popcnt -- the same method under the OLD spelling'
     Body = @'
fn f(x : Int) -> Int {
  Int::popcnt(x)
}
'@ }
  @{ Name = 's19_control_method';  Expect = 'REJECT'; Note = 'Int32::popcntnope -- the CONTROL'
     Body = @'
fn f(x : Int32) -> Int32 {
  Int32::popcntnope(x)
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
Write-Output ('{0,-24} {1,-8} {2,-48} {3,-8} {4}' -f 'ROW', 'EXPECT', 'NOTE', 'ACTUAL', 'THE TOOLCHAIN SAYS')
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
  Write-Output ('{0,-24} {1,-8} {2,-48} {3,-8} {4}{5}{6}' -f $r.Name, $r.Expect, $r.Note, $actual, $why, $codeStr, $verdict)
}

Write-Output ''
Write-Output '=== does `moon fmt` REWRITE the spelling in SOURCE? ==='
$fmtPkg = Join-Path $root 's11_fmt_probe'
$fmtSrc = Join-Path $fmtPkg 'src\s11_fmt_probe'
New-Item -ItemType Directory -Force -Path $fmtSrc | Out-Null
[System.IO.File]::WriteAllText((Join-Path $fmtPkg 'moon.mod'), "name = `"s11_fmt_probe`"`n`nversion = `"0.1.0`"`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $fmtSrc 'moon.pkg'), "import {`n}`n", (New-Object System.Text.UTF8Encoding($false)))
$fmtBody = "fn take(x : Int) -> Int {`n  x`n}`n"
[System.IO.File]::WriteAllText((Join-Path $fmtSrc 's11_fmt_probe.mbt'), $fmtBody, (New-Object System.Text.UTF8Encoding($false)))
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $moon -C $fmtPkg fmt 2>&1 | Out-Null
$ErrorActionPreference = $prev
$after = [System.IO.File]::ReadAllText((Join-Path $fmtSrc 's11_fmt_probe.mbt'))
if ($after -match 'Int32') {
  Write-Output 'moon fmt REWROTE `Int` as `Int32` -- the NEW spelling is the toolchain''s own canonical form.'
} elseif ($after -match '\bInt\b') {
  Write-Output 'moon fmt KEPT `Int` -- the OLD spelling is the toolchain''s own canonical form.'
} else {
  Write-Output ('moon fmt produced something else: ' + $after.Replace("`n", '\n'))
}
Write-Output ''
if ($bad -eq 0) {
  Write-Output 'ALL EXPECTED ROWS MATCH THE EXPECTED VERDICT on the installed toolchain.'
} else {
  Write-Output ($bad.ToString() + ' ROW(S) DIFFER FROM THE EXPECTED VERDICT -- the fix must follow the MEASUREMENT, not the expectation.')
}

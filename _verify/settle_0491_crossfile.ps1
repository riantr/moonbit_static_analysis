# settle 0491 -- the SAME-PACKAGE CROSS-FILE shapes, settled against the toolchain.
#
# WHAT THIS SETTLES. The behavioral lens's READ path never consults the cross-file
# symbol table, so a name declared in a SIBLING file of the same package is
# reported `undefined variable` by that lens while the structural lens -- which
# DOES consult the same table -- stays silent on the same line. Measured on moui
# 0.1.12: 49 findings, of which 35 are `undefined variable 'Constant'` (an enum
# variant of `pub(all) enum DeclarationChannel` in `core/declaration.mbt`, read
# bare in `core/modifier_paint.mbt`).
#
# The claim being settled is the toolchain's, not the analyzer's: DOES MOONBIT
# ACCEPT these shapes? Every ACCEPT row below is code the toolchain must accept,
# and every REJECT row is a control -- a shape the toolchain must REFUSE, so
# that "the analyzer must stay silent" cannot be satisfied by silencing
# everything.
#
# The rows are built as a TWO-PACKAGE project: `src/pa` declares, `src/pb` is a
# DIFFERENT package that imports it. A package is a DIRECTORY, so a name in `pa`
# is visible to `pa`'s siblings and to nobody else. That is the rule the
# analyzer's per-package private table encodes, and the REJECT rows pin it.
#
# `moon.mod` is NOT JSON. It is `key = "value"`, and a JSON body is a PARSE
# ERROR that the toolchain reports as "Failed to calculate build plan" -- a
# build failure that looks like a settle verdict and is neither.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP 'xfile_rows'
if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
New-Item -ItemType Directory -Force -Path $root | Out-Null

# The DECLARING package. Every row uses the same one, so the only thing that
# varies between rows is the READER.
#
# `PubChan` is `pub(all)`, so its variant `Constant` is a package-visible name
# AND a cross-package one (`@pa.Constant`). `PrivChan` is `priv`, so `PLeft` is
# visible to `pa`'s siblings and to nobody else. `helper` and `secret` are
# package-private -- and NOTE THE SPELLING: a top-level `fn` and `let` are
# private BY DEFAULT, and `priv` is not a valid visibility for either. The
# toolchain says so: "No 'private' visibility for function." [3005]. The
# corpus writes them the same way -- `fn dispatch_web_open_url(...)` in
# `backend/web/web_host.mbt`, `fn clone_semantics_issue(...)` in
# `runtime/semantics_snapshot.mbt` -- with no keyword at all.
# `K` is `pub const`. `PubChan::twice` is a `pub fn`.
$decl = @'
pub(all) enum PubChan {
  Constant
}

priv enum PrivChan {
  PLeft
}

fn helper() -> Int {
  1
}

let secret : Int = 7

pub const K : Int = 3

pub fn PubChan::twice(x : Int) -> Int {
  x * 2
}
'@

$rows = @(
  @{ Name = 'xf1_sibling_bare_pub_variant'; Expect = 'ACCEPT'
     Note = 'a BARE unit variant of a pub(all) enum, read in a SIBLING file'
     Sib = @'
fn read_sibling() -> PubChan {
  Constant
}
'@ }

  @{ Name = 'xf2_sibling_bare_priv_variant'; Expect = 'ACCEPT'
     Note = 'a BARE unit variant of a PRIV enum, read in a SIBLING file'
     Sib = @'
fn read_sibling() -> PrivChan {
  PLeft
}
'@ }

  @{ Name = 'xf3_sibling_private_fn'; Expect = 'ACCEPT'
     Note = 'a package-private fn CALLED from a sibling file'
     Sib = @'
fn read_sibling() -> Int {
  helper()
}
'@ }

  @{ Name = 'xf4_sibling_private_let'; Expect = 'ACCEPT'
     Note = 'a package-private top-level let READ bare from a sibling file'
     Sib = @'
fn read_sibling() -> Int {
  secret
}
'@ }

  @{ Name = 'xf5_sibling_pub_const'; Expect = 'ACCEPT'
     Note = 'a pub const READ bare from a sibling file'
     Sib = @'
fn read_sibling() -> Int {
  K
}
'@ }

  @{ Name = 'xf6_sibling_qualified_fn'; Expect = 'ACCEPT'
     Note = 'a pub fn of a sibling type, QUALIFIED and called'
     Sib = @'
fn read_sibling() -> Int {
  PubChan::twice(2)
}
'@ }

  @{ Name = 'xf7_sibling_all_together'; Expect = 'ACCEPT'
     Note = 'every shape above in ONE sibling file -- they must not interact'
     Sib = @'
fn read_sibling() -> Int {
  let a = K
  let b = helper()
  let c = secret
  let d = PubChan::twice(2)
  let e = match Constant {
    Constant => 1
  }
  a + b + c + d + e
}
'@ }

  @{ Name = 'xf8_control_cross_package_private_fn'; Expect = 'REJECT'
     Note = 'a package-private fn from ANOTHER package -- the sibling-only rule'
     Other = @'
fn read_other() -> Int {
  helper()
}
'@ }

  @{ Name = 'xf9_control_cross_package_bare_variant'; Expect = 'REJECT'
     Note = 'a BARE variant of another package''s enum -- it must be qualified'
     Other = @'
fn read_other() -> Int {
  let a = Constant
  0
}
'@ }

  @{ Name = 'xf10_control_cross_package_public_qualified'; Expect = 'ACCEPT'
     Note = 'the SAME names, QUALIFIED, from another package -- the toolchain accepts THESE'
     Other = @'
fn read_other() -> Int {
  let a = @pa.K
  let b = @pa.PubChan::twice(2)
  a + b
}
'@ }

  @{ Name = 'xf11_control_missing_name'; Expect = 'REJECT'
     Note = 'a name that exists NOWHERE -- the control that the analyzer must keep reporting'
     Sib = @'
fn read_sibling() -> Int {
  no_such_name_anywhere
}
'@ }

  @{ Name = 'xf12_control_missing_cross_package'; Expect = 'REJECT'
     Note = 'a name that exists nowhere, read from another package'
     Other = @'
fn read_other() -> Int {
  no_such_name_anywhere
}
'@ }
)

foreach ($r in $rows) {
  $proj = Join-Path $root $r.Name
  $pa = Join-Path $proj 'src\pa'
  New-Item -ItemType Directory -Force -Path $pa | Out-Null
  $mod = @"
name = "$($r.Name)"

version = "0.1.0"
"@
  [System.IO.File]::WriteAllText((Join-Path $proj 'moon.mod'), $mod, (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $pa 'moon.pkg'), "import {`n}`n", (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $pa 'a.mbt'), $decl, (New-Object System.Text.UTF8Encoding($false)))
  if ($r.ContainsKey('Sib')) {
    [System.IO.File]::WriteAllText((Join-Path $pa 'b.mbt'), $r.Sib, (New-Object System.Text.UTF8Encoding($false)))
  }
  if ($r.ContainsKey('Other')) {
    $pb = Join-Path $proj 'src\pb'
    New-Item -ItemType Directory -Force -Path $pb | Out-Null
    $pkg = @"
import {
  "$($r.Name)/src/pa",
}
"@
    [System.IO.File]::WriteAllText((Join-Path $pb 'moon.pkg'), $pkg, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $pb 'c.mbt'), $r.Other, (New-Object System.Text.UTF8Encoding($false)))
  }
}

$moon = 'C:\Users\31379\.moon\bin\moon.exe'
Write-Output ('toolchain: ' + (((& $moon version) | Out-String) -split "`r?`n")[0].Trim())
Write-Output ''
Write-Output ('{0,-44} {1,-8} {2,-62} {3,-8} {4}' -f 'ROW', 'EXPECT', 'NOTE', 'ACTUAL', 'THE TOOLCHAIN SAYS')
Write-Output ('-' * 190)

$bad = 0
foreach ($r in $rows) {
  $proj = Join-Path $root $r.Name
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = (& $moon -C $proj check 2>&1 | Out-String)
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
  if ($why.Length -gt 90) { $why = $why.Substring(0, 90) + '...' }
  if ($r.Expect -ne '?') {
    if ($actual -ne $r.Expect) { $bad++ }
    $verdict = if ($actual -eq $r.Expect) { '' } else { '  <<< DIFFERS' }
  } else {
    $verdict = '  (measured)'
  }
  Write-Output ('{0,-44} {1,-8} {2,-62} {3,-8} {4}{5}{6}' -f $r.Name, $r.Expect, $r.Note, $actual, $why, $codeStr, $verdict)
}
Write-Output ''
if ($bad -eq 0) {
  Write-Output 'ALL EXPECTED ROWS MATCH THE EXPECTED VERDICT on the installed toolchain.'
} else {
  Write-Output ($bad.ToString() + ' ROW(S) DIFFER FROM THE EXPECTED VERDICT.')
}

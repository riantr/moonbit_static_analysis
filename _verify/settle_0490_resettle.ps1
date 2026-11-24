# 0490 toolchain re-settle -- MEASURE, DO NOT ASSUME, and keep the toolchain's
# OWN diagnostic text.
#
# WHY THIS FILE EXISTS AGAIN. 0490 settled four toolchain facts against `moon
# check` 0.1.20261012, and the source comments, the NARRATIVE and the commit
# message CITE THAT VERSION BY NUMBER. The installed toolchain is now
# 0.1.20261016 -- it was reinstalled at 2026-10-20 00:54:16, in the middle of
# the 0490 release gate, which is what broke gates 0459-0487 ("Cannot load the
# core file"). A fact settled against one version is a claim ABOUT that version,
# so it has to be re-checked against what is installed.
#
# Every row is its own package, so one row's error cannot mask another's, and
# the toolchain's OWN diagnostic text is printed -- "REJECT" on its own says
# nothing about WHICH rule rejected it, and 0490's comments name error codes.
#
# `moon.mod` is NOT JSON. It is `key = "value"`, and a JSON body is a PARSE
# ERROR: "unexpected token { at line 1, column 1", which the toolchain reports
# as "Failed to calculate build plan" -- a build failure that looks like a
# settle verdict and is neither.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP 'dir2settle3_rows'
if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }

$rows = @(
  @{ Name = 'r1_optional_q';         Expect = 'ACCEPT'; Note = 'fn opt(x, y?) called opt(1)'
     Body = @'
fn opt(x : Int, y? : Int) -> Int {
  x
}

fn call_opt() -> Int {
  opt(1)
}
'@ }
  @{ Name = 'r2_labelled_default';   Expect = 'ACCEPT'; Note = 'fn f(x, y~=0) called f(1)'
     Body = @'
fn labelled_default(x : Int, y~ : Int = 0) -> Int {
  x
}

fn call_labelled() -> Int {
  labelled_default(1)
}
'@ }
  @{ Name = 'r3_missing_required';   Expect = 'REJECT'; Note = 'omitting a REQUIRED parameter -> 4080'
     Body = @'
fn required(x : Int) -> Int {
  x
}

fn call_required() -> Int {
  required()
}
'@ }
  @{ Name = 'r4_positional_default'; Expect = 'REJECT'; Note = '= default on a POSITIONAL parameter -> 3010'
     Body = @'
fn positional_default(y : Int = 0) -> Int {
  y
}
'@ }
  @{ Name = 'r5_string_compare';      Expect = 'ACCEPT'; Note = 'a <= b on two Strings'
     Body = @'
fn cmp_string(a : String, b : String) -> Bool {
  a <= b
}
'@ }
  @{ Name = 'r6_tuple_arg';           Expect = 'ACCEPT'; Note = 'a tuple value against a tuple parameter'
     Body = @'
fn take_pair(p : (Int, Int)) -> Int {
  p.0 + p.1
}

fn call_pair() -> Int {
  take_pair((1, 2))
}
'@ }
  @{ Name = 'r7_tuple_control';       Expect = 'REJECT'; Note = 'an Int against a tuple parameter -> 4014'
     Body = @'
fn take_pair(p : (Int, Int)) -> Int {
  p.0 + p.1
}

fn call_bad_pair() -> Int {
  take_pair(1)
}
'@ }

  # --- the `~` question, in BOTH directions ---------------------------------
  # 0490's `n_omittable` comment says: "`fn f(x~ : Int)` called as `f(1)` is
  # accepted, but `f(x=1)` is rejected with 4085". The first re-settle row
  # MEASURED `f(x=1)` as ACCEPTED, which contradicts the comment. Either the
  # toolchain changed between 0.1.20261012 and 0.1.20261016, or the original
  # measurement had the direction backwards. These three rows settle WHICH,
  # and they are separate packages so one cannot mask another.
  @{ Name = 'r8_tilde_called_by_label'; Expect = '?'; Note = 'fn f(x~) called f(x=1) -- BY LABEL'
     Body = @'
fn labelled_only(x~ : Int) -> Int {
  x
}

fn call_labelled_only() -> Int {
  labelled_only(x=1)
}
'@ }
  @{ Name = 'r9_tilde_called_positional'; Expect = '?'; Note = 'fn f(x~) called f(1) -- POSITIONALLY'
     Body = @'
fn labelled_only(x~ : Int) -> Int {
  x
}

fn call_labelled_only() -> Int {
  labelled_only(1)
}
'@ }
  @{ Name = 'r10_positional_called_by_label'; Expect = '?'; Note = 'fn f(x) called f(x=1) -- label on a POSITIONAL param'
     Body = @'
fn positional(x : Int) -> Int {
  x
}

fn call_positional() -> Int {
  positional(x=1)
}
'@ }

  # --- the FULL omittable matrix --------------------------------------------
  # 0490 says the omittable spellings are TWO: `x?` and `x~ = default`. The
  # matrix below asks whether there are others -- `x? = default`, `x~?`, and a
  # `?` on a labelled parameter -- because "there are exactly two" is a claim
  # about a CLOSED set, and a closed set is exactly the kind of claim a matrix
  # is for.
  @{ Name = 'r11_qmark_with_default'; Expect = '?'; Note = 'fn f(x? : Int = 0) -- a `?` carrying a default'
     Body = @'
fn qmark_default(x? : Int = 0) -> Int {
  1
}

fn call_qmark_default() -> Int {
  qmark_default()
}
'@ }
  @{ Name = 'r12_tilde_qmark'; Expect = '?'; Note = 'fn f(x~? : Int) -- both markers at once'
     Body = @'
fn both_markers(x~? : Int) -> Int {
  1
}

fn call_both_markers() -> Int {
  both_markers()
}
'@ }
  @{ Name = 'r13_tilde_default_omitted'; Expect = '?'; Note = 'fn f(x~ : Int = 0) -- a LABELLED default, omitted'
     Body = @'
fn labelled_default(x~ : Int = 0) -> Int {
  1
}

fn call_labelled_default() -> Int {
  labelled_default()
}
'@ }
  @{ Name = 'r14_qmark_omitted'; Expect = '?'; Note = 'fn f(x? : Int) -- a `?`, omitted'
     Body = @'
fn qmark(x? : Int) -> Int {
  1
}

fn call_qmark() -> Int {
  qmark()
}
'@ }
  @{ Name = 'r15_tilde_default_by_label'; Expect = '?'; Note = 'fn f(x~ : Int = 0) called f(x=1) -- by label'
     Body = @'
fn labelled_default(x~ : Int = 0) -> Int {
  1
}

fn call_labelled_default() -> Int {
  labelled_default(x=1)
}
'@ }

  # --- THE DECISIVE ROW -----------------------------------------------------
  # 0490's `n_omittable` concludes "the `~` marker on its own does NOT make a
  # parameter omittable", and the CODE agrees: the parser sets `omittable` for
  # `?` and for `= default`, and for nothing else. But the EVIDENCE the comment
  # cites for that conclusion is INVERTED -- it says `f(1)` is accepted and
  # `f(x=1)` is rejected, and the measurement says the opposite.
  #
  # So the conclusion needs its OWN evidence, and the row that settles it is the
  # one the whole comment turns on: OMITTING a bare `x~` parameter entirely. If
  # that is ACCEPTed, the conclusion is wrong and the code is wrong with it.
  @{ Name = 'r16_tilde_omitted'; Expect = '?'; Note = 'fn f(x~ : Int) called f() -- a bare `~` OMITTED'
     Body = @'
fn labelled_only(x~ : Int) -> Int {
  x
}

fn call_labelled_only() -> Int {
  labelled_only()
}
'@ }
  @{ Name = 'r17_tilde_default_omitted_control'; Expect = '?'; Note = 'fn f(x~ : Int = 0) called f() -- a `~` WITH a default, omitted'
     Body = @'
fn labelled_default(x~ : Int = 0) -> Int {
  1
}

fn call_labelled_default() -> Int {
  labelled_default()
}
'@ }
  @{ Name = 'r18_positional_omitted'; Expect = '?'; Note = 'fn f(x : Int) called f() -- a POSITIONAL param, omitted'
     Body = @'
fn positional(x : Int) -> Int {
  x
}

fn call_positional() -> Int {
  positional()
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
Write-Output ('-' * 160)

$bad = 0
foreach ($r in $rows) {
  $pkg = Join-Path $root $r.Name
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = (& $moon -C $pkg check 2>&1 | Out-String)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $actual = if ($code -eq 0) { 'ACCEPT' } else { 'REJECT' }
  # The toolchain's OWN diagnostic, and its error code, if it has one.
  $why = ''
  $codes = @()
  foreach ($ln in ($o -split "`r?`n")) {
    if ($ln -match '(?i)\berror\b' -and $ln -notmatch 'FullyQualifiedErrorId|NativeCommandError|CategoryInfo|^\s*\+|^At ') {
      $why = $ln.Trim()
    }
    foreach ($m in [regex]::Matches($ln, '\b(4\d{3})\b')) { $codes += $m.Groups[1].Value }
  }
  $codeStr = if ($codes.Count -gt 0) { ' [' + (($codes | Select-Object -Unique) -join ',') + ']' } else { '' }
  if ($why.Length -gt 78) { $why = $why.Substring(0, 78) + '...' }
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
  Write-Output ($bad.ToString() + ' ROW(S) DIFFER FROM THE EXPECTED VERDICT -- the 0490 citations must be corrected in-repo.')
}

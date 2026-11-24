# 0.4.27 settle: is a PARENTHESISED FUNCTION TYPE valid in RETURN position?
#
# The probe says no -- every `fn f() -> (() -> Int) { ... }` dies on
# `expected '{'`, while the genuine tuple `fn f() -> (Int, String)` parses.
# Before anything is called a defect, `moon check` has to agree it is valid,
# because "the analyzer cannot read this" and "the compiler cannot read this"
# are different findings with opposite consequences.
#
# THE HARNESS IS HARDENED, and every hardening here was paid for in 0.4.26:
#
#   1. `moon check` only type-checks a body REACHED from `fn main`. Without the
#      call there is nothing to check and "0 errors" means nothing.
#   2. Clear only `*.mbt`. The 0.4.26 version cleared every file in `src` and
#      deleted `moon.pkg` with them, so `moon check` had no package and printed
#      nothing at all.
#   3. `moon` writes diagnostics to stderr and PowerShell turns a native command
#      writing to stderr into a `NativeCommandError`, so `2>&1 | Out-String` came
#      back EMPTY. The capture goes through the shell into a FILE.
#   4. Two NEGATIVE controls at the bottom. A settle that cannot go red is not
#      measuring.
#
# `3003` (about `fn main`'s signature) and `4069` (`main` in a non-main package)
# are harness artifacts of calling the function and are filtered out. `4014` --
# the type mismatch -- is NOT filtered, which is what the first control proves.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/settle_0427_retfn.ps1
$ErrorActionPreference = 'Stop'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$dir  = Join-Path $env:TEMP 'settle0427'
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0427`"`nversion = `"0.1.0`"`n", $enc)

$D = "suberror E {`n  E(Int)`n}`n"
$cases = [ordered]@{
  # THE SHAPE: a parenthesised function type in RETURN position.
  'retfn_plain.mbt'   = "fn f() -> (() -> Int) {`n  return 1`n}`nfn main() {`n  let _ = f`n}`n"
  # parameterised, and doubly parenthesised
  'retfn_paren.mbt'   = "fn f() -> ((Int) -> String) {`n  return `"a`"`n}`nfn main() {`n  let _ = f`n}`n"
  'retfn_nested.mbt'  = "fn f() -> ((String) -> (Int, Int)) {`n  return (1, 2)`n}`nfn main() {`n  let _ = f`n}`n"
  # the same clause with an effect, which 0.4.23 already taught in SIGNATURE
  # position -- if this dies too, the position is the whole story
  'retfn_raise.mbt'   = $D + "fn f() -> (() -> Int raise E) {`n  return 1`n}`nfn main raise {`n  let _ = f`n}`n"
  # CONTROL: a genuine TUPLE return. This one must keep parsing, or a fix that
  # reads every `(...)` as a function type would be trading one break for another.
  'ret_tuple.mbt'     = "fn f() -> (Int, String) {`n  return (1, `"a`")`n}`nfn main() {`n  let _ = f`n}`n"
  # CONTROL: a parenthesised single non-function type, `-> (Int)`. If THAT breaks
  # under the fix, the discrimination is not "function type vs tuple" but
  # something cruder.
  'ret_paren_scalar.mbt' = "fn f() -> (Int) {`n  return 1`n}`nfn main() {`n  let _ = f`n}`n"
  # CONTROL: a function type in PARAMETER position, which already works. It is
  # here so that "no errors" on it is evidence the harness can pass a function
  # type at all, rather than evidence the case never ran.
  'param_fn.mbt'      = "fn g(h : () -> Int) -> Int {`n  h()`n}`nfn main() {`n  let _ = g(fn { 1 })`n}`n"
  # NEGATIVE CONTROL 1: a mismatched tail is a real type error (4014). If this
  # comes back clean, the filter is hiding everything.
  'NEG_mismatch.mbt'  = "fn f() -> Int {`n  `"a`"`n}`nfn main() {`n  let _ = f()`n}`n"
  # NEGATIVE CONTROL 2: `-> ()` really is a parse error, so it must NOT be
  # accepted. This is the shape most likely to be "fixed" by making the return
  # annotation optional, and the one that would hide a real regression.
  'NEG_arrow_nothing.mbt' = "fn f() -> {`n  return 1`n}`nfn main() {`n  let _ = f()`n}`n"
  # THE SHAPE THE CORPUS ACTUALLY USES. Found by the A/B: three moui files go
  # from PARTIAL to fully parsed because of this, and the sites are written as
  #
  #     ) -> (() -> Unit)? {
  #
  # -- a parenthesised function type with an OPTIONAL `?` suffix, on its own
  # line at the end of a multi-line parameter list. The `?` is not in any fixture
  # above, and the fix has to consume the annotation without swallowing it.
  'retfn_opt.mbt'      = "fn f() -> (() -> Unit)? {`n  return (fn { () })`n}`nfn main() {`n  let _ = f`n}`n"
  # the multi-line spelling, with a generic and a qualified name -- the exact
  # shape that the PREVIOUS measurement regex could not match, which is how it
  # came to report zero for a corpus containing nine files of it.
  'retfn_multiline.mbt' = "pub fn[T] M::start(`n  self : M[T],`n  done : (Int) -> Unit,`n) -> (() -> Unit)? {`n  return (fn { () })`n}`nfn main() {`n  let _ = M::start`n}`n"
  # and a tuple whose ELEMENTS are function types, which is the tuple control
  # that must keep parsing now that a nested `->` is a signal.
  'ret_tuple_fn.mbt'   = "fn f() -> (() -> Int, (Int) -> String) {`n  return (fn { 1 }, fn { `"a`" })`n}`nfn main() {`n  let _ = f`n}`n"
}

$HARNESS_CODES = @('3003', '4069')
$outFile = Join-Path $dir 'check.out'
Push-Location $dir
foreach ($k in $cases.Keys) {
  Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File | Remove-Item -Force
  [System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir ('src\' + $k)), $cases[$k], $enc)
  & cmd.exe /c "moon check > `"$outFile`" 2>&1"
  $out = [System.IO.File]::ReadAllText($outFile)
  $all = @([regex]::Matches($out, 'Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $real = @($all | Where-Object { $HARNESS_CODES -notcontains $_ } | Sort-Object -Unique)
  $harness = @($all | Where-Object { $HARNESS_CODES -contains $_ } | Sort-Object -Unique)
  $tag = if ($real.Count -gt 0) { 'REAL [' + ($real -join ',') + ']' } else { 'accepted' }
  Write-Output ('{0,-22} {1,-18} (harness: {2})' -f $k, $tag, (($harness -join ',') -replace '^$', 'none'))
}
Pop-Location
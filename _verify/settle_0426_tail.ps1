# 0.4.26 settle: does a TAIL EXPRESSION really produce the declared return type?
#
# MEASURED FIRST, AND THE FIRST VERSION OF THIS SCRIPT WAS WRONG IN A WAY WORTH
# RECORDING. It settled twelve shapes with no `fn main`, and every one came back
# "0 errors" -- including `fn f() -> Int { "a" }`, which real MoonBit rejects.
#
# `moon check` type-checks a function body only when the function is REACHED from
# `main`. Without a `main` the body is never checked, so "0 errors" was measuring
# nothing about types. Every case here now has a `fn main` that CALLS the function,
# which is also the shape the analyzer's own behaviour lens needs (a body it never
# reaches is never analysed).
#
# What the no-main version did prove stands: the shapes PARSE. That is a real
# result for a parser, and it is kept -- the two questions are different.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/settle_0426_tail.ps1
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP 'settle0426'
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0426`"`nversion = `"0.1.0`"`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", $enc)

# Every case ends with a `main` that CALLS the function under test. Without the
# call there is nothing to check, which is how the first version passed.
$cases = [ordered]@{
  'tail_int.mbt'        = "fn f() -> Int {`n  1`n}`nfn main() {`n  let _ = f()`n}`n"
  'ret_int.mbt'         = "fn f() -> Int {`n  return 1`n}`nfn main() {`n  let _ = f()`n}`n"
  'tail_str.mbt'        = "fn f() -> String {`n  `"a`"`n}`nfn main() {`n  let _ = f()`n}`n"
  'tail_bool.mbt'       = "fn f() -> Bool {`n  true`n}`nfn main() {`n  let _ = f()`n}`n"
  'tail_unit.mbt'       = "fn f() -> Unit {`n  ()`n}`nfn main() {`n  f()`n}`n"
  'tail_after_stmt.mbt' = "fn f() -> Int {`n  let x = 1`n  x + 1`n}`nfn main() {`n  let _ = f()`n}`n"
  'tail_if_both.mbt'    = "fn f(n : Int) -> Int {`n  if n > 0 {`n    1`n  } else {`n    2`n  }`n}`nfn main() {`n  let _ = f(1)`n}`n"
  # `fn main raise`, not `fn main`: 4122 rejects a `fn main` that can propagate an
  # error, which is a fact about the HARNESS's call site, not about the shape.
  'tail_raise.mbt'      = "suberror E {`n  E(Int)`n}`nfn f(n : Int) -> Int raise E {`n  if n > 0 {`n    raise E(n)`n  }`n  1`n}`nfn main raise {`n  let _ = f(1)`n}`n"
  # A Unit CALL, not a literal. `while c { "b" }` is rejected with 4139 -- a loop
  # body's trailing expression is discarded, and only Unit may be discarded
  # silently -- which is the same fact `fn_body` encodes in the parser.
  'tail_while.mbt'      = "fn noop() -> Unit {`n  ()`n}`nfn f(s : String) -> Int {`n  while s == `"a`" {`n    noop()`n  }`n  7`n}`nfn main() {`n  let _ = f(`"a`")`n}`n"
  'tail_caller.mbt'     = "fn f() -> Int {`n  1`n}`nfn g() -> Int {`n  f() + 1`n}`nfn main() {`n  let _ = g()`n}`n"
  'tail_nested.mbt'     = "fn f(n : Int) -> Int {`n  fn h() -> Int {`n    2`n  }`n  h() + n`n}`nfn main() {`n  let _ = f(1)`n}`n"
  # NEGATIVE CONTROL 1: the tail really is type-checked, so a mismatched one is
  # rejected. If this ever comes back clean, every "no real errors" above is
  # meaningless.
  'NEG_mismatch.mbt'    = "fn f() -> Int {`n  `"a`"`n}`nfn main() {`n  let _ = f()`n}`n"
  # NEGATIVE CONTROL 2, and it is a fact about the LANGUAGE rather than about this
  # analyzer: a tail expression REQUIRES a declared return type. `fn f() { 1 }` is
  # 4074, "Missing type annotation for the return value."
  #
  # That is why the latent-surface measurement counted only functions that HAVE a
  # `-> T`: the population of functions this defect could touch is exactly the
  # population the compiler already forces you to annotate.
  'NEG_noann.mbt'       = "fn f() {`n  1`n}`nfn main() {`n  let _ = f()`n}`n"
}

# `moon check` only type-checks a body when the function is REACHED from `main`,
# and `main` has to be called to be reached -- so every case below has one. In a
# library package that placement itself is an error, and those two codes are
# filtered out here:
#
#   4069  Unexpected main function in the non-main package
#   3003  about `main`'s own signature
#
# The filter is safe because of the NEGATIVE CONTROL at the bottom: a real
# type error is `4014 Expr Type Mismatch`, which is NOT filtered. If the control
# ever comes back clean, the filter is hiding something and every "OK" above is
# meaningless.
$HARNESS_CODES = @('3003', '4069')

Push-Location $dir
# THE CAPTURE IS THE FIX, and it took a negative control to find it. The first
# two versions ran `moon check 2>&1 | Out-String` and reported "0 errors" for
# EVERY case -- including `NEG_mismatch`, which real MoonBit rejects. `moon`
# writes its diagnostics to stderr, PowerShell turns a native command writing to
# stderr into a `NativeCommandError` under `$ErrorActionPreference`, and the
# merged string came back empty.
#
# Redirecting through the shell's own `2>&1` into a FILE cannot be swallowed
# that way.
$outFile = Join-Path $dir 'check.out'
foreach ($k in $cases.Keys) {
  # ONLY the `.mbt` cases. The first version cleared every file in `src`, which
  # included `moon.pkg` -- so from the first case on there was no package, `moon
  # check` had nothing to check, and it printed nothing at all. Combined with the
  # stderr capture above, that is two independent ways for this settle to report
  # a clean bill of health for a program the compiler rejects.
  Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File | Remove-Item -Force
  [System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir ('src\' + $k)), $cases[$k], $enc)
  & cmd.exe /c "moon check > `"$outFile`" 2>&1"
  $out = [System.IO.File]::ReadAllText($outFile)
  $all = @([regex]::Matches($out, 'Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $real = @($all | Where-Object { $HARNESS_CODES -notcontains $_ } | Sort-Object -Unique)
  $harness = @($all | Where-Object { $HARNESS_CODES -contains $_ } | Sort-Object -Unique)
  $tag = if ($real.Count -gt 0) { 'REAL ERRORS [' + ($real -join ',') + ']' } else { 'no real errors' }
  Write-Output ('{0,-20} {1,-28} (harness noise: {2})' -f $k, $tag, (($harness -join ',') -replace '^$', 'none'))
}
Pop-Location
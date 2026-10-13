# 0.4.26 probe: does a function's TAIL EXPRESSION poison its callers?
#
# The hypothesis, traced from the source rather than guessed:
#
#   Interp::exec_stmt   `SExpr(e) => { let _ = self.eval(e, env) }`
#                      -- a tail expression's value is DISCARDED.
#   Interp::analyze_fn  `let ret = join_vals(self.ret_vals)`
#   join_vals           `if vals.length() == 0 { return AType("None") }`
#
# A tail expression is `SExpr`, not `SReturn`, so nothing is ever pushed. Every
# function whose body ends in a tail expression therefore reports its return type
# as `None` -- and that value lands in the call cache, so CALLERS see it too.
#
# This probe only uses FINDINGS, because findings are what the JSON bridge
# exposes; the signature line is checked separately by a test.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/api_probe_0426_tail.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wasm = Join-Path $root '_build\wasm\debug\build\src\jsoncli\jsoncli.wasm'
$tmp  = Join-Path $env:TEMP 'tail_probe'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)

# Each pair is (tail-expression version, explicit-return version) of the SAME
# shape. The explicit-return one is the control: it is the shape the analyzer
# already handles, so it must stay silent. If BOTH report, the finding is real
# MoonBit semantics rather than a tail-expression defect.
$cases = [ordered]@{
  # plain call, no arithmetic -- the sigs line is the only symptom here
  'a_tail_call.mbt'    = "fn f() -> Int {`n  1`n}`nlet x = f()`n"
  'a_ret_call.mbt'     = "fn f() -> Int {`n  return 1`n}`nlet x = f()`n"

  # THE SHARP ONE: the caller does arithmetic on the returned value. If f's
  # return type is `None` then `f() + 1` is `no method matching +(None, 1)` --
  # a false method error about code that compiles.
  'b_tail_arith.mbt'   = "fn f() -> Int {`n  1`n}`nfn g() -> Int {`n  f() + 1`n}`nlet x = g()`n"
  'b_ret_arith.mbt'    = "fn f() -> Int {`n  return 1`n}`nfn g() -> Int {`n  f() + 1`n}`nlet x = g()`n"

  # same, through two levels: the wrong type must survive the hop
  'c_tail_two_hops.mbt'= "fn f() -> Int {`n  1`n}`nfn g() -> Int {`n  f()`n}`nfn h() -> Int {`n  g() + 2`n}`nlet x = h()`n"

  # other element types, same shape
  'd_tail_str.mbt'     = "fn f() -> String {`n  `"a`"`n}`nfn g() -> String {`n  f()`n}`nlet x = g()`n"
  'e_tail_bool.mbt'    = "fn f() -> Bool {`n  true`n}`nfn g() -> Bool {`n  f()`n}`nlet x = g()`n"

  # the caller is ALSO a tail-expression function
  'f_tail_caller_tail.mbt' = "fn f() -> Int {`n  1`n}`nfn g() -> Int {`n  f()`n}`nlet x = g()`n"

  # UNIT-returning: a tail expression of Unit. `join_vals` of nothing is also
  # `None`, so this one may be right by accident -- the control for "is this
  # specific to non-Unit return types?"
  'g_unit_tail.mbt'    = "fn f() -> Unit {`n  ()`n}`nfn g() -> Unit {`n  f()`n}`nlet x = g()`n"

  # a call inside a CONTROLLED branch -- the wrong type also decides whether a
  # `guard`-shaped else reports dead code
  'h_tail_branch.mbt'  = "fn f() -> Int {`n  1`n}`nfn g(n : Int) -> Int {`n  if n > 0 {`n    f()`n  } else {`n    0`n  }`n}`nlet x = g(1)`n"
}

foreach ($k in $cases.Keys) {
  $req = @{ kind='program'; filename=$k; source=$cases[$k] } | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText((Join-Path $tmp 'req.json'), $req, $enc)
  $out = & C:\Users\31379\.moon\bin\moonrun.exe $wasm --file (Join-Path $tmp 'req.json') 2>&1 | Out-String
  Write-Output ('===== ' + $k + ' =====')
  try { $j = $out | ConvertFrom-Json } catch { Write-Output ('  RAW: ' + $out.Trim()); continue }
  $fs = @($j.findings)
  if ($fs.Count -eq 0) { Write-Output '  findings: 0' }
  foreach ($f in $fs) { Write-Output ('    L' + $f.line + ' [' + $f.family + '] ' + $f.message) }
}
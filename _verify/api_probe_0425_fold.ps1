# 0.4.25: which call arguments produce a NON-FOLDABLE condition?
#
# The mutation gate for 0.4.25 needs fixtures that reach the unknown-condition
# arm of `SIf`. `f(1)` does not: `n` binds to `AInt(1)`, `binop` folds `n > 0`
# to `ABool(true)`, and the `cv` arm -- where the join lives -- is never entered.
# Three mutations survived precisely because of this.
#
# Every candidate below is the SAME source with a different argument at the call
# site, so the counts are directly comparable. The discriminator is the PAIR
# `same_nofold_else` / `same_fold_else`: the sources are identical and only the
# argument differs, so if both report the same count the fixture is not
# separating "folded" from "cv arm" and is useless to the gate.
#
# 0 = falls through, 1 = real dead code.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wasm = Join-Path $root '_build\wasm\debug\build\src\jsoncli\jsoncli.wasm'
$tmp  = Join-Path $env:TEMP 'fold_probe'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)

# ONE source, five arguments. `if s == "a"` (string) / `if n > 0` (int).
$SRC_STR = "fn f(s : String) -> Int {`n  if s == `"a`" {`n    return 1`n  }`n  return 2`n}`n"
$SRC_INT = "fn f(n : Int) -> Int {`n  if n > 0 {`n    return 1`n  }`n  return 2`n}`n"
$SRC_INT_BOTH = "fn f(n : Int) -> Int {`n  if n > 0 {`n    return 1`n  } else {`n    return 2`n  }`n  return 3`n}`n"
$SRC_INT_EIF = "fn f(n : Int) -> Int {`n  if n > 0 {`n    return 1`n  } else if n < 0 {`n    return 2`n  } else {`n    return 3`n  }`n  return 4`n}`n"

$BOTH_STR = $SRC_INT_BOTH.Replace('n : Int', 's : String').Replace('n > 0', 's == "a"')
$EIF_STR  = $SRC_INT_EIF.Replace('n : Int', 's : String').Replace('n > 0', 's == "a"').Replace('n < 0', 's == "b"')

$cases = [ordered]@{
  # A — string parameter, `==` never folds (binop has no string arm at all)
  'A_str_arg_fold.mbt'   = $SRC_STR + "let x = f(`"a`")`n"
  'B_int_arg_fold.mbt'   = $SRC_INT + "let x = f(1)`n"
  'C_int_arg_any.mbt'    = $SRC_INT + "let x = f(@core.nothing)`n"
  'D_str_both_arg.mbt'   = $BOTH_STR + "let x = f(`"a`")`n"
  'E_str_eif_arg.mbt'    = $EIF_STR + "let x = f(`"a`")`n"
  # F — the discriminator PAIR: identical source, one folded argument, one not
  'F_pair_str_folded.mbt' = $SRC_STR + "let x = f(`"a`")`n"
  'G_pair_str_var.mbt'    = $SRC_STR + "let s = `"a`"`nlet x = f(s)`n"
  'H_pair_int_folded.mbt' = $SRC_INT + "let x = f(1)`n"
  'I_pair_int_bigint.mbt' = $SRC_INT + "let x = f(1L)`n"
}

foreach ($k in $cases.Keys) {
  $req = @{ kind='program'; filename=$k; source=$cases[$k] } | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText((Join-Path $tmp 'req.json'), $req, $enc)
  $out = & C:\Users\31379\.moon\bin\moonrun.exe $wasm --file (Join-Path $tmp 'req.json') 2>&1 | Out-String
  Write-Output ('===== ' + $k + ' =====')
  try { $j = $out | ConvertFrom-Json } catch { Write-Output ('  RAW: ' + $out.Trim()); continue }
  $fs = @($j.findings)
  $un = @($fs | Where-Object { $_.family -eq 'Unreachable' }).Count
  Write-Output ('  Unreachable = ' + $un + '   (all findings: ' + $fs.Count + ')')
  foreach ($f in $fs) { Write-Output ('    L' + $f.line + ' [' + $f.family + '] ' + $f.message) }
}
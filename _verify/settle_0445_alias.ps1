# Settles what `tools/gen_builtin_methods.ps1` is allowed to put in the table.
#
# THE DEFECT, and it is in the GENERATOR rather than in the analyzer. The
# extraction pattern demanded that the name come straight after `fn`:
#
#     (?m)^\s*(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)
#
# MoonBit's generated interfaces put type parameters there:
#
#     pub fn[K : Eq] Set::add(Self[K], K) -> Unit
#
# so every GENERIC method of every builtin type was invisible. Measured against
# the toolchain in hand the old pattern produced ZERO hits on
# `<core>/set/pkg.generated.mbti`, which alone declares 32 of them, and missed
# 445 names across the tree.
#
# WHY IT WAS INVISIBLE FOR SO LONG. `Array::add` was never reported on the
# corpora only because real MoonBit writes the METHOD form `a.add(x)`; the
# qualified form `Array::add(a, x)` is mostly used for constructors. The one
# finding that did surface is the same shape -- `Set::from_array` in async
# 0.22.4 `src/http/send.mbt:37` -- which is not even a declared `fn` at all. It
# is an ALIAS: `#alias(from_array)` sits above `type Set[K]`, and the directive,
# not a declaration, is where the name is written.
#
# WHAT THIS SCRIPT SETTLES. Not "the regex is better" -- that is a reading of a
# file. It settles, against `moon check`:
#
#   1. the new table's names are REAL and callable, for each SHAPE of name the
#      fix reaches: a generic method, an alias of a method, an alias of a type
#      constructor;
#   2. a near-miss is REJECTED, so "ACCEPTED" cannot mean "not checked";
#   3. the 17 `to_json` names the interface scan does NOT find are still real, so
#      dropping them would have been a regression rather than a cleanup.
#
# (3) is here because the first version of this script got it BACKWARDS and the
# wrong answer was confident. `Bool::to_json` has zero hits in any
# `<core>/**/pkg.generated.mbti`, and the toolchain in hand (0.1.20261012) is not
# the one the table was generated against (0.1.20260920), so the obvious reading
# was "stale, drop it". It is not stale: `Bool::to_json(true)` COMPILES today. It
# is an intrinsic member that no interface declares -- the same category as
# `Array::make`, which is why the generator carries a hand-settled intrinsic list
# at all.
#
# The follow-on sweep was worse. Calling `T::to_json(1)` for all 45 bare types
# reported 35 as nonexistent; every one of those was a TYPE mismatch, because `1`
# is not a `Bool`. A probe that is wrong about its own prelude yields a clean
# answer that is entirely false, and this script only survived it because the
# correctly-typed case sat next to the malformed one.
#
# WHAT IS NOT ESTABLISHED, and is not claimed anywhere: whether the `.mbti` fn-head
# FORMAT changed between 0.1.20260920 and 0.1.20261012, or whether this pattern was
# always blind to generic heads. The old toolchain is not installed, so the claim
# here is the gap against the toolchain in hand and nothing earlier.
#
# A probe whose positive control fails means the PROBE is wrong. The first draft
# of `settle_0444_is_head.ps1` failed three cases for that exact reason and the
# fix was a better prelude, never a revised expectation. The 45-type sweep above
# is the second instance of it in this repository.

$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP ('settle0445_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0445`"`nversion = `"0.1.0`"`n", $enc)

$cases = @{}
$expected = @{}

# --- the POSITIVE CONTROL: a broken program MUST be rejected --------------
# Without this, an `ACCEPTED` verdict below could equally mean "moon never ran".
# It is the case that makes every other verdict mean something.
$cases['canary_syntax.mbt']   = "fn main { let = 1 }`n"
$expected['canary_syntax.mbt'] = 'REJECTED'

# The alias names are real and callable -- the shape the corpus finding has.
$cases['a_alias_ctor.mbt']    = "fn main {`n  let s : Set[Int] = Set::from_array([1, 2, 3])`n  ignore(s)`n}`n"
$expected['a_alias_ctor.mbt'] = 'ACCEPTED'

# A GENERIC method the old pattern could not see.
$cases['b_generic_method.mbt'] = "fn main {`n  let a = Array::add([1, 2], [3])`n  ignore(a)`n}`n"
$expected['b_generic_method.mbt'] = 'ACCEPTED'

# An alias of a METHOD rather than of a type: #alias(clone, deprecated) above
# `pub fn[T] Array::copy`, so this name lives in a directive too.
$cases['c_alias_method.mbt'] = "fn main {`n  let a = Array::clone([1, 2])`n  ignore(a)`n}`n"
$expected['c_alias_method.mbt'] = 'ACCEPTED'

# The near-miss control. `from_arrray` is one letter off a name the table now
# holds; if this were ACCEPTED the alias would be being matched too loosely.
$cases['d_typo.mbt'] = "fn main {`n  let s : Set[Int] = Set::from_arrray([1, 2, 3])`n  ignore(s)`n}`n"
$expected['d_typo.mbt'] = 'REJECTED'

# A name NO interface declares, which the generator must therefore carry by hand.
# It is real: this compiles. Written type-correct on purpose -- see the 45-type
# sweep in the header for what passing `1` here instead would have claimed.
$cases['e_to_json_intrinsic.mbt'] = "fn main {`n  ignore(Bool::to_json(true))`n}`n"
$expected['e_to_json_intrinsic.mbt'] = 'ACCEPTED'

# And the near-miss beside it, so "it exists" is not "any spelling resolves".
$cases['f_to_json_typo.mbt'] = "fn main {`n  ignore(Bool::to_jsonx(true))`n}`n"
$expected['f_to_json_typo.mbt'] = 'REJECTED'

$outFile = Join-Path $dir 'check.out'
$fail = 0
Push-Location $dir
foreach ($k in $cases.Keys) {
  Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File | ForEach-Object { [System.IO.File]::Delete($_.FullName) }
  [System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir ('src\' + $k)), $cases[$k], $enc)
  $present = @(Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File)
  if ($present.Count -ne 1 -or $present[0].Name -ne $k) {
    Write-Output ("{0,-22} ABORT: src holds {1} file(s)" -f $k, $present.Count); $fail++; continue
  }
  & cmd.exe /c "moon check > `"$outFile`" 2>&1"
  $out = [System.IO.File]::ReadAllText($outFile)
  if ([string]::IsNullOrWhiteSpace($out)) {
    Write-Output ("{0,-22} ABORT: moon check produced no output at all" -f $k); $fail++; continue
  }
  if ($out -notmatch 'Finished\.\s*moon:\s*ran\s+\d+\s+task' -and
      $out -notmatch 'failed when checking project') {
    Write-Output ("{0,-22} ABORT: moon check did no work" -f $k); $fail++; continue
  }
  $errs = @([regex]::Matches($out, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $real = @($errs | Where-Object { $_ -notin @('4069') })
  $got = if ($real.Count -gt 0) { 'REJECTED' } else { 'ACCEPTED' }
  $want = $expected[$k]
  $ok = ($got -eq $want)
  Write-Output ('{0,-22} {1,-9} (want {2}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    ($out -split "`n" | Where-Object { $_ -match 'Parse error|Error: \[' } | Select-Object -First 3) |
      ForEach-Object { '      ' + $_.Trim() }
  }
}
Pop-Location
Write-Output ''
if ($fail -gt 0) { Write-Output "ABORT: $fail case(s) did not match the expected verdict."; exit 1 }
Write-Output 'GATE OK: generic methods and #alias directives are real callable names; the interface scan misses T::to_json, which still resolves.'
exit 0

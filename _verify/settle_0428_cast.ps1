# 0.4.28 settle: `expr as &Trait` is real MoonBit, and the analyzer calls it a name.
#
# THE FINDING. moui `runtime/view_tree.mbt:69:38`:
#
#     RuntimeViewAdapter::{ view, emit } as &RuntimeViewNode
#
# reported as `undefined name 'as'` (UndefinedName, actionable). Reproduced on a
# 16-line program that `moon check` accepts with ZERO errors:
#
#     14:17 - error: undefined name 'as' (UndefinedName) [structural+type]
#
# The message is wrong in a specific way worth separating: it is not that the
# analyzer misread the construct, it is that it lexes `as` as an IDENTIFIER and
# then reports the identifier as unbound. It names a binding that never existed.
#
# WHAT SETTLED IT. `moon check` says, verbatim:
#
#     `Int` is not a trait object type, it cannot be used on the right hand side of `as`.
#
# That sentence settles the whole question: `as` is an OPERATOR, the parser
# accepts it, and the only thing wrong with `1 as Int` is the RIGHT-HAND SIDE. A
# syntactic error would have been 3002. The rule is `as` requires a TRAIT OBJECT
# (`&T`), never a plain type name.
#
# TWO EARLIER DRAFTS OF THIS SETTLE SETTLED NOTHING, and both are the same failure:
#   draft 1 wrote `fn { _ => () }` as a lambda. MoonBit lambdas use BRACES
#           (`fn() { () }`); `fn() => 1` and `fn { .. }` are both 3002. Every case
#           was rejected by the lambda before the question about `as` was reached.
#   draft 2 used `as Int` / `as Box` as the right-hand side, so every case died on
#           4175 -- the trait-object rule -- and one case (`named_fn(x : Named) {
#           x.name() }`) additionally died on 4099 for reasons unrelated to `as`.
#
# => A settle case that fails for an UNRELATED reason settles nothing, whatever
#    else it prints. Every case below is a program that compiles, checked by
#    compiling it, and the control is one that must NOT.
#
# Harness: keys end in `.mbt` (a missing extension once made fifteen cases read
# "clean" while nothing was compiled), exactly one `.mbt` in `src` is asserted,
# `moon check` must have actually done work, and the negative control must be
# rejected or the whole run is void.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/settle_0428_cast.ps1
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP ('settle0428_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0428`"`nversion = `"0.1.0`"`n", $enc)

# The prelude carries the `impl`, without which every cast is rejected with 4018
# ("no `impl` is defined") -- the third way a case can fail for a reason that has
# nothing to do with the thing under test.
$PRE = @"
priv trait Sink {
  fn fire(Self) -> Unit
}

priv struct Box {
  n : Int
}

impl Sink for Box with fn fire(self) {
  let _ = self.n
}

"@

$cases = [ordered]@{
  # A cast on a plain identifier.
  'a_ident_cast.mbt'        = $PRE + "fn to_sink(b : Box) -> &Sink {`n  b as &Sink`n}`n`nfn main {`n  let _ = to_sink`n}`n"
  # THE CORPUS SHAPE: a struct literal, then a cast.
  'b_literal_cast.mbt'      = $PRE + "fn to_sink() -> &Sink {`n  Box::{ n: 2 } as &Sink`n}`n`nfn main {`n  let _ = to_sink`n}`n"
  # The struct-UPDATE shape (`..old`), which is a different token sequence again.
  'c_update_cast.mbt'       = $PRE + "fn bump(o : Box) -> &Sink {`n  Box::{ ..o, n: 9 } as &Sink`n}`n`nfn main {`n  let _ = bump`n}`n"
  # NO `as` AT ALL: "clean" here means the harness can pass a compiling program.
  'POS_no_as.mbt'           = $PRE + "fn to_sink(b : Box) -> Box {`n  b`n}`n`nfn main {`n  let _ = to_sink`n}`n"
  # NEGATIVE CONTROL 1: `as` with nothing after it. If this is accepted then `as`
  # is an ordinary identifier and every verdict above is void.
  'NEG_as_alone.mbt'        = $PRE + "fn to_sink(b : Box) -> Box {`n  b as`n}`n`nfn main {`n  let _ = to_sink`n}`n"
  # NEGATIVE CONTROL 2: the rule the compiler spelled out -- a NON-trait on the
  # right of `as` is rejected. This is what makes the three positives meaningful:
  # it shows the tool is rejecting casts for a REASON, not accepting everything.
  'NEG_as_plain_ty.mbt'     = $PRE + "fn to_sink(b : Box) -> Box {`n  b as Box`n}`n`nfn main {`n  let _ = to_sink`n}`n"
}

$outFile = Join-Path $dir 'check.out'
$fail = 0
$expected = @{
  'a_ident_cast.mbt'    = 'ACCEPTED'
  'b_literal_cast.mbt'  = 'ACCEPTED'
  'c_update_cast.mbt'   = 'ACCEPTED'
  'POS_no_as.mbt'       = 'ACCEPTED'
  'NEG_as_alone.mbt'    = 'REJECTED'
  'NEG_as_plain_ty.mbt' = 'REJECTED'
}
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
  if ([string]::IsNullOrWhiteSpace($out) -or $out -match 'now up to date|no work to do') {
    Write-Output ("{0,-22} ABORT: moon check did no work" -f $k); $fail++; continue
  }
  $errs = @([regex]::Matches($out, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $real = @($errs | Where-Object { $_ -notin @('4069') })   # 4069 = main in a non-main package
  $got = if ($real.Count -gt 0) { 'REJECTED' } else { 'ACCEPTED' }
  $want = $expected[$k]
  $ok = ($got -eq $want)
  Write-Output ('{0,-22} {1,-9} (want {2}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    ($out -split "`n" | Where-Object { $_ -match 'Parse error|╰───' } | Select-Object -First 3) |
      ForEach-Object { '      ' + $_.Trim() }
  }
}
Pop-Location
Write-Output ''
if ($fail -gt 0) { Write-Output "ABORT: $fail case(s) did not match the expected verdict."; exit 1 }
Write-Output 'GATE OK: three `as &Trait` forms compile, `as` alone and `as <plain type>` do not.'
exit 0
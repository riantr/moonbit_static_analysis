# Settle 0466b -- the `.. rest` BINDING in an array pattern.
#
# WHY. 0466 unblocked `moonbitlang/async 0.22.4 src/internal/event_loop/fs.mbt`, which
# had `-> Unit nocancel` on two function signatures, and the file then reported
#
#     109:3 - error: undefined name 'payload' (UndefinedName) [structural+type]
#     156:3 - error: undefined name 'payload' (UndefinedName) [structural+type]
#
# from
#
#     guard! buf is [u32le(_), u32le(mask), .. payload]
#     ...
#     payload
#
# => 判据: a false positive nobody can reach is not a false positive that does not
# exist. It is a finding whose file has not been read yet. The reach here was
# legitimate, so the GAP gets fixed rather than the reach given back.
#
# THE CAUSE, read from the parser rather than guessed. `parse_is_pattern`'s array
# branch pushes a `TName` when `pattern_binding_at(j)` says it is a binding, and that
# predicate refuses any name whose PREVIOUS token is a `TDot` -- correctly, because
# `Foo.bar` is a field path and not a binding. `.. payload` is two TDots, so `payload`
# is refused by the same rule that exists to catch the path case.
#
# Reach measured across the pinned corpora: async 9 sites in 4 files, and ZERO in
# moui, labeler, image, proton and proton_contract. Small, and it is what stands
# between 0466 and `actionable = 0`.
#
# The rows below are the questions the fix depends on. They are MEASURED rather than
# asserted, because "the corpus line compiles" proves the SHAPE is legal and says
# nothing about whether `rest` is a binding or a field name.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

Add-Case 'ctl_ok' @'
///|
fn f(xs : Array[Int]) -> Int {
  guard xs is [a, b]
  a + b
}
'@ 'ACCEPT'

Add-Case 'ctl_bad' @'
///|
fn f() -> Int {
  ZzMissing
}
'@ 'REJECT'

# THE CORPUS SHAPE, with `rest` USED. If `.. rest` were a field path rather than a
# binding, this would be `undefined name 'rest'` and the 0466b premise would be wrong.
Add-Case 'rest_binds' @'
///|
fn f(xs : Array[Int]) -> Int {
  guard xs is [a, .. rest]
  rest.length() + a
}
'@ 'ACCEPT'

# THE CANARY BESIDE IT, and this is the row that makes the one above mean something.
# Same pattern, but the use is of a name the pattern never mentions. If it ACCEPTS,
# something is inventing bindings and `rest_binds` proved nothing.
Add-Case 'rest_canary' @'
///|
fn f(xs : Array[Int]) -> Int {
  guard xs is [a, .. rest]
  nope
}
'@ 'REJECT'

# A BARE `..` with no name after it -- the spread the struct-literal syntax also uses.
Add-Case 'rest_bare' @'
///|
fn f(xs : Array[Int]) -> Int {
  guard xs is [a, ..]
  a
}
'@ 'MEASURE'

# AND THE NESTED form, because `parse_is_pattern`'s array branch tracks bracket depth
# and a fix that only looked at depth 1 would pass every corpus row.
Add-Case 'rest_nested' @'
///|
fn f(xs : Array[Array[Int]]) -> Int {
  guard xs is [[a, .. inner], b]
  inner.length() + a + b
}
'@ 'MEASURE'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0466b_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0466b`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($plan) {
    $got = 'BUILD-PLAN-FAILED'
    $ok = $false
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'ACCEPT') { $ok = $false }
    elseif ($want -eq 'REJECT') { $ok = $got -like 'REJECT*' }
    else { $ok = $true }
  } else {
    $got = 'ACCEPT'
    $ok = ($want -ne 'REJECT')
  }
  $tag = $(if ($want -eq 'MEASURE') { 'measured' } elseif ($ok) { 'OK' } else { '*** MISMATCH ***' })
  Write-Output ('{0,-16} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $tag)
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|constructor' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'GATE OK -- ctl_ok/rest_binds ACCEPT and ctl_bad/rest_canary REJECT.'
} else {
  Write-Output ("*** GATE FAILED: $fail asserted row(s) did not hold. ***")
}
exit $fail

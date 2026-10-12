# 0.4.25: fixtures for the `exec_alt` half of the join.
#
# `exec_alt` is reached ONLY from the `ABool(false)` arm of `SIf`, so every case
# here needs the OUTER condition to fold to false (`n > 0` with `n = -1`) and the
# else-if conditions to stay unfolded (`s == "a"` is a bare `OpEq => AType("bool")`
# with no string arm at all, so it can never fold).
#
# The three cases separate the three decisions `exec_alt` makes:
#   exec_alt_tail_falls   the LAST else-if falls through  -> must report fall-through
#   exec_alt_tail_returns every branch returns           -> must report termination
#   exec_alt_no_else      no else at all, elseif falls   -> must report fall-through
#
# `exec_alt_tail_returns` and `exec_alt_tail_falls` share a source shape and
# differ ONLY in the last else-if body, so their counts must differ. Equal counts
# would mean neither is reaching the branch it is named for.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wasm = Join-Path $root '_build\wasm\debug\build\src\jsoncli\jsoncli.wasm'
$tmp  = Join-Path $env:TEMP 'excalt_probe'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)

$cases = [ordered]@{
  # the LAST else-if falls through, everything else returns
  'exec_alt_tail_falls.mbt' = @(
    'fn f(n : Int, s : String) -> Int {'
    '  if n > 0 {'
    '    return 1'
    '  } else if s == "a" {'
    '    return 2'
    '  } else if s == "b" {'
    '    let z = 3'
    '  } else {'
    '    return 4'
    '  }'
    '  return 5'
    '}'
    'let x = f(-1, "a")'
  ) -join "`n"

  # every branch returns, INCLUDING the else -> real dead code
  'exec_alt_tail_returns.mbt' = @(
    'fn f(n : Int, s : String) -> Int {'
    '  if n > 0 {'
    '    return 1'
    '  } else if s == "a" {'
    '    return 2'
    '  } else {'
    '    return 4'
    '  }'
    '  return 5'
    '}'
    'let x = f(-1, "a")'
  ) -join "`n"

  # no else at all, and the only else-if falls through
  'exec_alt_no_else.mbt' = @(
    'fn f(n : Int, s : String) -> Int {'
    '  if n > 0 {'
    '    return 1'
    '  } else if s == "a" {'
    '    let _ = 2'
    '  }'
    '  return 3'
    '}'
    'let x = f(-1, "a")'
  ) -join "`n"

  # NO else-if AT ALL. `exec_alt` is entered with `elseifs = []`, so `idx <
  # elseifs.length()` is false and it falls to its TERMINAL `match els` -- a
  # different block from the one above, and the only place `exec_alt` can say
  # "terminated" about a plain `else`. M6 lives in the `Some` arm.
  'exec_alt_terminal_else.mbt' = @(
    'fn f(n : Int) -> Int {'
    '  if n > 0 {'
    '    return 1'
    '  } else {'
    '    return 2'
    '  }'
    '  return 3'
    '}'
    'let x = f(-1)'
  ) -join "`n"

  # and the terminal `None` arm: no else-if AND no else, condition folded false
  'exec_alt_terminal_none.mbt' = @(
    'fn f(n : Int) -> Int {'
    '  if n > 0 {'
    '    return 1'
    '  }'
    '  return 2'
    '}'
    'let x = f(-1)'
  ) -join "`n"
}

foreach ($k in $cases.Keys) {
  $req = @{ kind='program'; filename=$k; source=($cases[$k] + "`n") } | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText((Join-Path $tmp 'req.json'), $req, $enc)
  $out = & C:\Users\31379\.moon\bin\moonrun.exe $wasm --file (Join-Path $tmp 'req.json') 2>&1 | Out-String
  Write-Output ('===== ' + $k + ' =====')
  try { $j = $out | ConvertFrom-Json } catch { Write-Output ('  RAW: ' + $out.Trim()); continue }
  $fs = @($j.findings)
  $un = @($fs | Where-Object { $_.family -eq 'Unreachable' }).Count
  Write-Output ('  Unreachable = ' + $un + '   (all findings: ' + $fs.Count + ')')
  foreach ($f in $fs) { Write-Output ('    L' + $f.line + ' [' + $f.family + '] ' + $f.message) }
}
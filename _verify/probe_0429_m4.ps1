# 0.4.29 M4 probe: does dropping interp's `eval` of a cast operand change ANY
# analyzer output, and if not, why?
#
# This is a MEASUREMENT script, not a gate. M4 survived the mutation gate twice,
# both times for a different reason, and the two attempts to write a fixture that
# kills it were both wrong. Rather than write a third guess, this applies M4,
# rebuilds, and prints the analyzer's output on the candidate programs so the
# answer can be READ rather than inferred from a test count.
#
# Every case is run TWICE: once with M4 applied and once after restore, and the
# two outputs are diffed. A case where the diff is empty is a case with no
# observable difference -- which is the claim the write-up needs to support.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\probe_0429_m4.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$INTERP = Join-Path $root 'src\interp\interp.mbt'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$nl = [string][char]10
$enc = New-Object System.Text.UTF8Encoding($false)

$cases = [ordered]@{
  # The fixture the gate currently carries: an `is` binding introduced inside a
  # cast operand, read afterwards, all in `fn main` (which run_top executes).
  'is_binding_in_cast' = "fn main {`n  let x = 1`n  let c = (x is TName(t)) as &Sink`n  let _ = t`n  let _ = c`n}`n"
  # The same shape with NO cast, to establish that `t` really is a binding and the
  # parser really is reading the pattern.
  'is_binding_no_cast' = "fn main {`n  let x = 1`n  let c = x is TName(t)`n  let _ = t`n  let _ = c`n}`n"
  # A cast in a CALLED function, so the body is interpreted through `call`.
  'cast_in_called_fn'  = "fn go(x : Int) -> &Sink {`n  let c = (x is TName(t)) as &Sink`n  let _ = t`n  c`n}`nfn main {`n  let _ = go(1)`n}`n"
  # DIAGNOSTIC: does the interpreter report an unbound name inside a CALLED
  # function at all? If this is silent, `Interp::call` is not reaching the body
  # and every "the env side effect" argument above is unfounded.
  'undef_in_called_fn' = "fn go(x : Int) -> Int {`n  let y = zz`n  x`n}`nfn main {`n  let _ = go(1)`n}`n"
  # DIAGNOSTIC: the exact shape, with ONE extra unbound read (`qq`) beside the
  # `is`-bound `t`. If `qq` is reported and `t` is not, the binding survives M4
  # from somewhere other than the `ECast` arm and M4 is genuinely unobservable.
  'is_then_undef'      = "fn go(x : Int) -> Int {`n  let c = (x is TName(t)) as &Sink`n  let _ = t`n  let _ = qq`n  x`n}`nfn main {`n  let _ = go(1)`n}`n"
}

function Build-Wasm {
  $o = Join-Path $env:TEMP ('probe_build_' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.out')
  $e = $o + '.err'
  Start-Process -FilePath 'C:\Users\31379\.moon\bin\moon.exe' `
    -ArgumentList @('build','--target','wasm') -RedirectStandardOutput $o `
    -RedirectStandardError $e -NoNewWindow -Wait | Out-Null
}

function Run-Case([string]$dir) {
  $o = Join-Path $dir 'o.txt'; $e = Join-Path $dir 'e.txt'
  Start-Process -FilePath 'C:\Users\31379\.moon\bin\moonrun.exe' `
    -ArgumentList @($wasm, $dir) -RedirectStandardOutput $o -RedirectStandardError $e `
    -NoNewWindow -Wait | Out-Null
  return [System.IO.File]::ReadAllText($o)
}

# One directory per case, created ONCE and reused for both runs. Creating a fresh
# directory per run makes every output differ -- the TARGET/SCANNED/FOUND header
# lines all carry the absolute path -- and the first version of this probe
# therefore reported all three cases as "DIFFERS" when the findings were identical.
$dirs = @{}
foreach ($k in $cases.Keys) {
  $d = Join-Path $env:TEMP ('m4_' + $k + '_' + [guid]::NewGuid().ToString('N').Substring(0,6))
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"m4probe`"`nversion = `"0.1.0`"`n", $enc)
  [System.IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [System.IO.File]::WriteAllText((Join-Path $d 'src\t.mbt'), $cases[$k], $enc)
  $dirs[$k] = $d
}

# ---------------------------------------------------------------------------
# BASELINE: M4 applied (unmutated build first, so both sides are comparable)
# ---------------------------------------------------------------------------
Write-Output 'Building the UNMUTATED analyzer...'
Build-Wasm
$base = @{}
foreach ($k in $cases.Keys) { $base[$k] = Run-Case $dirs[$k] }

# ---------------------------------------------------------------------------
# APPLY M4
# ---------------------------------------------------------------------------
$bytes0 = [System.IO.File]::ReadAllBytes($INTERP)
$sha0 = (Get-FileHash -LiteralPath $INTERP -Algorithm SHA256).Hash
$text = [System.Text.Encoding]::UTF8.GetString($bytes0)
$eol = if ($text.Contains([string][char]13 + [char]10)) { [string][char]13 + [char]10 } else { $nl }
$findN = @'
    ECast(base) => {
      let _ = self.eval(base, env)
      AAny
    }
'@.Replace("`r`n", $nl)
$replN = '    ECast(_) => AAny'
if ($text.Replace($eol, $nl).IndexOf($findN, [System.StringComparison]::Ordinal) -lt 0) {
  Write-Output 'ABORT: the M4 pattern is absent from interp.mbt.'
  exit 1
}
Write-Output 'Applying M4 and rebuilding...'
[System.IO.File]::WriteAllText($INTERP, $text.Replace($eol, $nl).Replace($findN, $replN).Replace($nl, $eol), $enc)
Build-Wasm
$mut = @{}
foreach ($k in $cases.Keys) { $mut[$k] = Run-Case $dirs[$k] }

# ---------------------------------------------------------------------------
# RESTORE -- always, before anything is printed or judged
# ---------------------------------------------------------------------------
[System.IO.File]::WriteAllBytes($INTERP, $bytes0)
$same = ($sha0 -eq (Get-FileHash -LiteralPath $INTERP -Algorithm SHA256).Hash)
Write-Output ("Restored interp.mbt byte-identical: " + $same)
Write-Output 'Rebuilding the unmutated analyzer...'
Build-Wasm
if (-not $same) { Write-Output 'ABORT: restore mismatch.'; exit 1 }

# ---------------------------------------------------------------------------
# COMPARE
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== what the UNMUTATED analyzer reports for each case ==='
foreach ($k in $cases.Keys) {
  $verdict = if ($base[$k] -eq $mut[$k]) { 'IDENTICAL to M4' } else { 'DIFFERS from M4' }
  Write-Output ("  [{0}]  {1}" -f $verdict, $k)
  ($base[$k] -split "`r?`n" | Where-Object { $_ -match 'error:|warning:|SUMMARY' }) | ForEach-Object { '      ' + $_ }
}
exit 0
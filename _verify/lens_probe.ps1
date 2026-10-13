$ErrorActionPreference = 'Stop'
$probe = Join-Path $env:TEMP ('lens_probe_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $probe | Out-Null

# One file that exercises each of the three families the behavior lens is the ONLY
# emitter of, placed where the interpreter actually reaches: `Interp::run_top`
# skips every `SFunc` -- including `main` (interp.mbt:389) -- so a function body is
# interpreted only when a TOP-LEVEL statement calls it. A probe written as ordinary
# functions with no top-level driver would report nothing and prove nothing.
$src = @'
fn dead_after_return(x : Int) -> Int {
  return x
  let never = 2
  never
}

fn cond_of_int(x : Int) -> Bool {
  if x { true } else { false }
}

fn add_int_str(x : Int) -> Int {
  x + "not an int"
}

fn len_of_int(x : Int) -> Int {
  x.length()
}

fn main {
  ()
}

let a = dead_after_return(1)
let b = cond_of_int(2)
let c = add_int_str(3)
let d = len_of_int(4)
let _ = a
let _ = b
let _ = c
let _ = d

// POSITIVE CONTROL. Measured on three corpora, the one finding this lens emits
// is `undefined function '<name>'`, from a call it could not resolve. If this line
// does not come back tagged [behavior], then the interpreter did not run on this
// file at all and the zeros below measure the probe, not the lens.
let e = no_such_function_zzz(1)
let _ = e
'@
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $probe 'probe.mbt'), $src, $enc)

$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
if (-not (Test-Path $wasm)) { Write-Output 'ABORT: build the analyzer first.'; exit 1 }

$out = Join-Path $probe 'out.txt'
$err = Join-Path $probe 'out.err'
Start-Process -FilePath 'C:\Users\31379\.moon\bin\moonrun.exe' `
  -ArgumentList @($wasm, $probe) `
  -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null

$txt = [System.IO.File]::ReadAllText($out)
Write-Output '=== findings the behavior lens emits on a file that reaches it ==='
$lines = @($txt -split "`r?`n" | Where-Object { $_ -match '^\d+:\d+ - (error|warning|hint): ' })
foreach ($l in $lines) { Write-Output ('  ' + $l.Trim()) }

Write-Output ''
Write-Output '=== per-family tally ==='
foreach ($f in @('Unreachable','NonBooleanCond','MethodError','UndefinedName')) {
  $c = @($lines | Where-Object { $_ -match "\($f\)" }).Count
  $tag = if ($c -eq 0) { '   -- NOT PRODUCED' } else { '   -- produced' }
  Write-Output ("  {0,-16} {1}{2}" -f $f, $c, $tag)
}
Write-Output ''
Write-Output '=== SUMMARY ==='
Write-Output ('  ' + ([regex]::Match($txt, '(?m)^SUMMARY.*$')).Value)
Write-Output ("probe dir: " + $probe)

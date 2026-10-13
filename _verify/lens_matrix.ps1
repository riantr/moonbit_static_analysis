$ErrorActionPreference = 'Stop'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
if (-not (Test-Path $wasm)) { Write-Output 'ABORT: build the analyzer first.'; exit 1 }
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$repos = Join-Path $root '.repos'

# One case per file, each exercising a DIFFERENT shape. The point of the matrix is
# that a single probe cannot tell "this lens cannot fire" from "this probe never
# reached the lens" -- the 0.4.16 note at interp.mbt:1236 is exactly that mistake,
# made once already: every probe there defined a function and never called it.
$cases = [ordered]@{
  'A_bare_undefined_call' = @'
let x = no_such_function_zzz(1)
let _ = x
'@
  'B_qualified_call' = @'
let x = @async.CondVar::Cond()
let _ = x
'@
  'C_dead_code_in_called_fn' = @'
fn f(x : Int) -> Int {
  return x
  let never = 2
  never
}

let r = f(1)
let _ = r
'@
  'D_method_on_wrong_type' = @'
fn g(x : Int) -> Int {
  x.length()
}

let r = g(1)
let _ = r
'@
  'E_binop_wrong_types' = @'
fn h(x : Int) -> Int {
  x + "str"
}

let r = h(1)
let _ = r
'@
  'F_nonbool_cond' = @'
fn k(x : Int) -> Bool {
  if x { true } else { false }
}

let r = k(1)
let _ = r
'@
  'G_defn_not_called' = @'
fn never_called(x : Int) -> Int {
  return x
  let dead = 2
  dead
}

let r = 1
let _ = r
'@
}

Write-Output 'case                     behavior-tagged findings'
Write-Output '-----------------------  ----------------------------------------'
foreach ($name in $cases.Keys) {
  $dir = Join-Path $env:TEMP ('lenscase_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path $dir 'c.mbt'), $cases[$name], $enc)
  $out = Join-Path $dir 'out.txt'; $err = Join-Path $dir 'out.err'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $dir, '--extern-iface-dir', $repos) `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  $txt = [System.IO.File]::ReadAllText($out)
  $lines = @($txt -split "`r?`n" | Where-Object { $_ -match '^\d+:\d+ - (error|warning|hint): ' })
  $bh = @($lines | Where-Object {
    $tag = ([regex]::Match($_, '\[([^\]]*)\]\s*$')).Groups[1].Value
    ($tag -split '\+') -contains 'behavior'
  })
  $show = if ($bh.Count -eq 0) { '(none)' } else { ($bh | ForEach-Object { ($_ -split ' - ')[1] }) -join ' ; ' }
  Write-Output ("{0,-24} {1}" -f $name, $show)
  foreach ($l in $lines) { Write-Output ("      all: " + $l.Trim()) }
}

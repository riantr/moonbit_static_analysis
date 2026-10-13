# Settle AND probe the 0.4.27 fixtures in one run, with lambda-free bodies.
#
# WHY THE BODIES CHANGED. The first set of fixtures returned a function LITERAL,
# `return (fn() { 1 })`, which `moon check` accepts. But the ANALYZER reports a
# ParseError notice for a lambda it does not model ("short lambda is outside the
# analyzed subset"), so every one of those fixtures failed on a pre-existing,
# unrelated limitation and would have been testing two things at once.
#
# The substitute is a NAMED helper: `return g` where `g : () -> Int`. It is a
# real function value of exactly the right type, it needs no lambda, and it is
# accepted by both tools -- so a ParseError in these fixtures can only be about
# the return ANNOTATION, which is the thing under test.
#
# This script runs each case through BOTH:
#   moon check  -- does the compiler accept it?          (settle)
#   the analyzer -- does it report zero ParseErrors?     (probe)
# and a case is only called GOOD when both agree. A case the compiler rejects is
# a fixture that proves nothing; a case the analyzer rejects is a fixture that
# has not been fixed.
#
# GATE: the negative control must be rejected by BOTH. If it is not, the run is
# void -- the same failure that made an earlier settle report fifteen clean
# results while checking nothing.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/settle_probe_0427.ps1
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:TEMP ('sp0427_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"sp0427`"`nversion = `"0.1.0`"`n", $enc)

# `G` is the helper every case reuses: a zero-argument function returning Int,
# and `gi` returning String, `gp` a one-argument function.
$G   = "fn g() -> Int {`n  1`n}`n"
$GI  = "fn gi() -> Int -> Int {`n  g`n}`n"
$GS  = "fn gs() -> String {`n  `"a`"`n}`n"
$G1  = "fn g1(_n : Int) -> String {`n  `"a`"`n}`n"
$G2  = "fn g2(_s : String) -> (Int, Int) {`n  (1, 2)`n}`n"
$GU  = "fn gu() -> Unit {`n  ()`n}`n"

$cases = [ordered]@{
  'a_plain.mbt'      = $G   + "fn f() -> (() -> Int) {`n  return g`n}`nfn main {`n  let _ = f()`n}`n"
  'b_paren.mbt'      = $G1  + "fn f() -> ((Int) -> String) {`n  return g1`n}`nfn main {`n  let _ = f()`n}`n"
  'c_nested.mbt'     = $G2  + "fn f() -> ((String) -> (Int, Int)) {`n  return g2`n}`nfn main {`n  let _ = f()`n}`n"
  'd_opt.mbt'        = $G   + "fn f() -> (() -> Int)? {`n  return Some(g)`n}`nfn main {`n  let _ = f()`n}`n"
  'e_unparen.mbt'    = $G1  + "fn f() -> (Int) -> String {`n  return g1`n}`nfn main {`n  let _ = f()`n}`n"
  'f_tuple.mbt'      = "fn f() -> (Int, String) {`n  return (1, `"a`")`n}`nfn main {`n  let _ = f()`n}`n"
  'g_scalar.mbt'     = "fn f() -> (Int) {`n  return 1`n}`nfn main {`n  let _ = f()`n}`n"
  'h_tuple_fn.mbt'   = $G + $G1 + "fn f() -> (() -> Int, (Int) -> String) {`n  return (g, g1)`n}`nfn main {`n  let _ = f()`n}`n"
  # The helper has to CARRY the effect too. `fn g() -> Int` returned `() -> Int`
  # where `() -> Int raise E` was wanted -- which is itself the proof that the
  # annotation parsed exactly right, since the compiler quotes it back verbatim:
  #     has type : () -> Int
  #     wanted   : () -> Int raise E
  'i_raise.mbt'      = "suberror E {`n  E(Int)`n}`nfn g() -> Int raise E {`n  1`n}`nfn f() -> (() -> Int raise E) {`n  return g`n}`nfn main raise {`n  let _ = f()`n}`n"
  'j_multiline.mbt'  = "struct M {`n  x : Int`n}`n" + $GU + "pub fn M::start(`n  self : M,`n  done : (Int) -> Unit,`n) -> (() -> Unit)? {`n  return Some(gu)`n}`nfn main {`n  let _ = M::start`n}`n"
  # the negative control: broken in the language, so both tools must reject it
  'NEG_arrow_none.mbt' = "fn f() -> {`n  return 1`n}`nfn main {`n  let _ = f()`n}`n"
}

$root = Split-Path -Parent $PSScriptRoot
$jwasm = Join-Path $root '_build\wasm\debug\build\src\jsoncli\jsoncli.wasm'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'

$outFile = Join-Path $dir 'check.out'
$reqFile = Join-Path $dir 'req.json'
$fail = 0; $negOk = $false
Push-Location $dir
foreach ($k in $cases.Keys) {
  Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File | ForEach-Object { [System.IO.File]::Delete($_.FullName) }
  [System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir ('src\' + $k)), $cases[$k], $enc)
  $present = @(Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File)
  if ($present.Count -ne 1 -or $present[0].Name -ne $k) {
    Write-Output ("{0,-18} ABORT: src holds {1} file(s)" -f $k, $present.Count); $fail++; continue
  }

  # --- settle: does the compiler accept it? ---
  & cmd.exe /c "moon check > `"$outFile`" 2>&1"
  $out = [System.IO.File]::ReadAllText($outFile)
  if ([string]::IsNullOrWhiteSpace($out) -or $out -match 'now up to date|no work to do') {
    Write-Output ("{0,-18} ABORT: moon check did no work" -f $k); $fail++; continue
  }
  $errs = @([regex]::Matches($out, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $real = @($errs | Where-Object { $_ -notin @('4069') })
  $settle = if ($real.Count -gt 0) { 'REJ[' + ($real -join ',') + ']' } else { 'ok' }

  # --- probe: does the analyzer read it? ---
  $req = @{ kind = 'program'; filename = $k; source = $cases[$k] } | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText($reqFile, $req, $enc)
  $praw = & $moonrun $jwasm --file $reqFile 2>&1 | Out-String
  if ([string]::IsNullOrWhiteSpace($praw)) {
    Write-Output ("{0,-18} ABORT: analyzer produced no output" -f $k); $fail++; continue
  }
  $j = $praw | ConvertFrom-Json
  $pe = @(@($j.findings) | Where-Object { $_.family -eq 'ParseError' })
  $probe = if ($pe.Count -eq 0) { 'ok' } else { 'E[' + $pe.Count + ']' }
  $msgs = ($pe | Select-Object -First 2 | ForEach-Object { $_.message }) -join ' | '

  if ($k -like 'NEG_*') {
    $negOk = (($settle -ne 'ok') -and ($probe -ne 'ok'))
    Write-Output ('{0,-18} settle={1,-10} analyzer={2,-6} {3}' -f $k, $settle, $probe, $(if ($negOk) { 'CONTROL OK' } else { '*** CONTROL FAILED ***' }))
    if (-not $negOk) { $fail++ }
  } else {
    $good = ($settle -eq 'ok') -and ($probe -eq 'ok')
    Write-Output ('{0,-18} settle={1,-10} analyzer={2,-6} {3}' -f $k, $settle, $probe, $(if ($good) { 'GOOD' } else { 'NOT USABLE' }))
    if (-not $good) {
      $fail++
      # Both verdicts printed with their messages. A "NOT USABLE" line with only
      # error CODES is not diagnosable, and the first draft of this script had
      # three such lines that each needed a separate throwaway probe.
      if ($real.Count -gt 0) {
        ($out -split "`n" | Where-Object { $_ -match 'Parse error|Mismatch|not found|unbound|undefined|has type|wanted|^─|^\s*╭─' } | Select-Object -First 3) |
          ForEach-Object { '      compiler: ' + $_.Trim() }
      }
      if ($msgs) { Write-Output ('      analyzer: ' + $msgs) }
    }
  }
}
Pop-Location
Write-Output ''
if (-not $negOk) { Write-Output 'ABORT: negative control not rejected by both tools. Every verdict above is void.'; exit 1 }
Write-Output "GATE OK (negative control rejected by compiler and analyzer). Unusable cases: $fail"
exit 0
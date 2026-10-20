# Settle 0492 -- a PARAMETER that is re-assigned in the body, and the type lens.
#
# WHAT IS BEING SETTLED. `Infer::run_fn` seeds a function's frame from the
# structural lens's binding table. That table lists the function's PARAMETERS
# first and its BODY BINDINGS after, and the walk records an assignment
# `xs["k"] = "v"` as a RE-BINDING of the base name `xs`. So the table carries
# `xs` twice, and the body binding -- which carries no type of its own -- was
# declared LAST and OVERWROTE the parameter's annotation. The parameter's type
# was then gone for the WHOLE function body, and every check on that name
# degraded to "unknown".
#
# The case that made it visible:
#
#     fn h(xs : Array[String]) -> Unit { xs["k"] = "v" }
#
# The analyzer reported it CLEAN. The type lens has a gate for exactly this
# shape -- "list indices must be int" -- and the READ form of the same code
# (`xs["k"]`) IS reported. The source even says the two arms must agree: "Both
# arms must agree -- a check that fires on read and not on write is a claim
# about syntax, not about types."
#
# So: does the TOOLCHAIN reject these programs? If it does, the analyzer's
# silence is a FALSE NEGATIVE and the two arms are genuinely supposed to agree.
# If it does not, the analyzer is right to be silent and the write arm's premise
# is wrong.
#
# THE POSITIVE CONTROLS ARE THE POINT. An earlier version of this probe found
# the toolchain accepting `let x : Int = "s"`, and reported every row ACCEPTED
# -- because the probe's project was not a project the toolchain would check
# (no package directory, no `moon.pkg`), so `moon check` printed "no work to do"
# and exited 0. A settle that cannot reject is not a settle, so the two control
# rows come FIRST and must REJECT.
#
# THE RECIPE is this repository's own (see `_verify/settle_0491_crossfile.ps1`):
# a package directory under `src/` with its own `moon.pkg`, and `moon -C <proj>
# check`. `moon.mod` is `key = "value"`, NOT JSON.
$ErrorActionPreference = 'Continue'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$enc = New-Object System.Text.UTF8Encoding($false)

$rows = @(
  @{ Name = 'control_int_from_string'; Expect = 'REJECT'
     Note = 'a type error the toolchain cannot miss'
     Src  = "fn h() -> Int {`n  let x : Int = `"s`"`n  x`n}`n" }
  @{ Name = 'control_call_arity'; Expect = 'REJECT'
     Note = 'a call with the wrong arity'
     Src  = "fn g(a : Int) -> Int { a }`nfn h() -> Int {`n  g(1, 2)`n}`n`n" }
  @{ Name = 'read_string_index'; Expect = 'REJECT'
     Note = 'the READ form -- the analyzer already reports this one'
     Src  = "fn h(xs : Array[String]) -> String {`n  xs[`"k`"]`n}`n" }
  @{ Name = 'write_string_index'; Expect = 'REJECT'
     Note = 'the WRITE form, on a PARAMETER -- the analyzer was silent here'
     Src  = "fn h(xs : Array[String]) -> Unit {`n  xs[`"k`"] = `"v`"`n}`n" }
  @{ Name = 'write_list_local'; Expect = 'REJECT'
     Note = 'the WRITE form, on a local let -- the analyzer already reported this one'
     Src  = "fn h() -> Unit {`n  let xs = [`"a`"]`n  xs[`"k`"] = `"v`"`n}`n" }
  @{ Name = 'param_reassigned_wrong_type'; Expect = '?'
     Note = 'a parameter re-assigned a wrong-typed value'
     Src  = "fn h(xs : Int) -> Unit {`n  xs = `"s`"`n}`n" }
  @{ Name = 'write_int_index'; Expect = 'ACCEPT'
     Note = 'correct code: an int index into an int list'
     Src  = "fn h(xs : Array[Int]) -> Unit {`n  xs[0] = 1`n}`n" }
  @{ Name = 'write_map_key'; Expect = 'ACCEPT'
     Note = 'correct code: a Map is indexed by its KEY'
     Src  = "fn h(m : Map[String, Int]) -> Unit {`n  m[`"k`"] = 1`n}`n" }
  @{ Name = 'read_int_index'; Expect = 'ACCEPT'
     Note = 'correct code: an int index into an int list'
     Src  = "fn h(xs : Array[Int]) -> Int {`n  xs[0]`n}`n" }
)

$root = Join-Path $env:TEMP ('settle0492_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $root | Out-Null

foreach ($r in $rows) {
  $proj = Join-Path $root $r.Name
  $pa = Join-Path $proj 'src\pa'
  New-Item -ItemType Directory -Force -Path $pa | Out-Null
  $mod = "name = `"$($r.Name)`"`n`nversion = `"0.1.0`"`n"
  [System.IO.File]::WriteAllText((Join-Path $proj 'moon.mod'), $mod, $enc)
  [System.IO.File]::WriteAllText((Join-Path $pa 'moon.pkg'), "import {`n}`n`n", $enc)
  [System.IO.File]::WriteAllText((Join-Path $pa 'p.mbt'), $r.Src, $enc)
}

Write-Output ('toolchain: ' + (((& $moon version) | Out-String) -split "`r?`n")[0].Trim())
Write-Output ''
Write-Output ('{0,-32} {1,-8} {2,-58} {3,-8} {4}' -f 'ROW', 'EXPECT', 'NOTE', 'ACTUAL', 'THE TOOLCHAIN SAYS')
Write-Output ('-' * 200)

$bad = 0
foreach ($r in $rows) {
  $proj = Join-Path $root $r.Name
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = (& $moon -C $proj check 2>&1 | Out-String)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $actual = if ($code -eq 0) { 'ACCEPT' } else { 'REJECT' }
  $why = ''
  foreach ($ln in ($o -split "`r?`n")) {
    if ($ln -match '(?i)\berror\b' -and $ln -notmatch 'FullyQualifiedErrorId|NativeCommandError|CategoryInfo|^\s*\+|^At ') {
      $why = $ln.Trim()
    }
  }
  if ($why.Length -gt 80) { $why = $why.Substring(0, 80) + '...' }
  $verdict = ''
  if ($r.Expect -ne '?') {
    if ($actual -ne $r.Expect) { $bad++; $verdict = '  <<< DIFFERS' }
  } else {
    $verdict = '  (measured)'
  }
  Write-Output ('{0,-32} {1,-8} {2,-58} {3,-8} {4}{5}' -f $r.Name, $r.Expect, $r.Note, $actual, $why, $verdict)
}
Write-Output ''
Write-Output ('project root: ' + $root)
if ($bad -gt 0) {
  Write-Output ("SETTLE FAILED: " + $bad + " row(s) differ from the expectation.")
  exit 1
}
Write-Output 'SETTLE OK: every row matched, and the two controls REJECT.'
exit 0

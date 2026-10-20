# settle 0493 -- FOUR behavioral-lens false positives, settled against the toolchain.
#
# WHAT THIS SETTLES. The per-function view reports 7 actionable findings on
# wzzc-dev/moui 0.1.12 that the module view reports 0, and this script settles
# the TOOLCHAIN's verdict on each shape. The claim being settled is the
# toolchain's, not the analyzer's: DOES MOONBIT ACCEPT these shapes?
#
# Every ACCEPT row below is code the toolchain must accept, and every REJECT row
# is a CONTROL -- a shape the toolchain must REFUSE, so that "the analyzer must
# stay silent on it" cannot be satisfied by silencing everything.
#
# THE FOUR CLASSES, and the moui sites each came from:
#
#   B  the `is`-pattern binding introduced by an `else if` CONDITION
#      moui views/text/text_area_control.mbt:414 -> 426
#      `ctx.text_control.text_selection_anchor is Some(anchor)` binds `anchor`,
#      which is read 12 lines later. Reported `undefined variable 'anchor'`.
#
#   C  a function's VALUE when the body yields none
#      moui views/text/text_input_editing.mbt:42   `clamp_int(None, int, Any)`
#      moui backend/web/web_host.mbt:357, :359     `web_string_append_char(None, Any)`
#      moui backend/linux/linux_services.mbt:183   `>(None, float)`
#      Two mechanisms, both answering "None": an unmodelled `match` value, and
#      an extern function whose body is in another language.
#
#   D  a call that supplies its arguments BY LABEL
#      moui views/navigation/navigation_routing.mbt:157
#      `RouteHistoryState::from_routes(routes=snapshot.routes, title~, source~)`
#      Reported `no method matching RouteHistoryState::from_routes(Any, str, str)`.
#
#   E  a `while` loop whose body always terminates
#      moui core/unicode/grapheme_cluster.mbt:428
#      `false` after a `while` whose body ends in `return`. The loop may run
#      ZERO times, so the statement after it is reachable. Reported unreachable.
#
# `moon.mod` is NOT JSON. It is `key = "value"`, and a JSON body is a PARSE
# ERROR the toolchain reports as "Failed to calculate build plan" -- a build
# failure that looks like a settle verdict and is neither.
#
# A package is a DIRECTORY: `src/<pkg>` with its own `moon.pkg`. A bare
# `moon.mod` plus a flat `src/*.mbt` is silently NOT a project the toolchain
# checks -- `moon check` prints "no work to do" and exits 0, which is a
# vacuous ACCEPT and the reason this script puts every row in its own package.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('lensval_rows_' + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Force -Path $root | Out-Null

$rows = @(
  # ---------------------------------------------------------------- class B
  @{ Name = 'b1_is_binding_in_else_if'; Expect = 'ACCEPT'
     Note = 'the `is` binding in an `else if` condition is visible in its body'
     Body = @'
fn pick(x : Int?, c : Bool) -> Int {
  if c {
    1
  } else if x is Some(a) {
    a
  } else {
    0
  }
}
'@ }

  @{ Name = 'b2_is_binding_in_if_condition'; Expect = 'ACCEPT'
     Note = 'the same binding in a plain `if` condition -- the shape that works'
     Body = @'
fn pick(x : Int?, c : Bool) -> Int {
  if x is Some(a) {
    a
  } else {
    0
  }
}
'@ }

  @{ Name = 'b3_is_binding_used_in_else_if_body'; Expect = 'ACCEPT'
     Note = 'the binding is USED, not merely bound -- a binder that is never read is not the claim'
     Body = @'
fn pick(x : Int?, c : Bool) -> Int {
  if c {
    1
  } else if x is Some(a) {
    a + 1
  } else {
    0
  }
}
'@ }

  @{ Name = 'b4_control_binding_escapes_the_if'; Expect = 'REJECT'
     Note = 'the binding does NOT escape the `if` -- the control on the scope claim'
     Body = @'
fn pick(x : Int?, c : Bool) -> Int {
  if c {
    1
  } else if x is Some(a) {
    0
  } else {
    0
  }
  a
}
'@ }

  @{ Name = 'b5_control_binding_in_the_then_branch'; Expect = 'REJECT'
     Note = 'the binding is NOT in scope in the `then` branch -- the other half of the scope rule'
     Body = @'
fn pick(x : Int?, c : Bool) -> Int {
  if x is Some(a) {
    a
  } else {
    0
  }
  if c {
    a
  } else {
    0
  }
}
'@ }

  # ---------------------------------------------------------------- class C
  @{ Name = 'c1_match_branch_value_is_used'; Expect = 'ACCEPT'
     Note = 'a function whose value comes from a `match` inside an `if` branch'
     Body = @'
fn pick(x : Int?, c : Bool) -> Int {
  if c {
    1
  } else {
    match x {
      Some(a) => a
      None => 0
    }
  }
}

fn use_it() -> Int {
  pick(None, false) + 1
}
'@ }

  @{ Name = 'c2_match_is_the_function_value'; Expect = 'ACCEPT'
     Note = 'the `match` is the function''s own value -- the other shape of the same class'
     Body = @'
fn pick(x : Int?) -> Int {
  match x {
    Some(a) => a
    None => 0
  }
}

fn use_it() -> Int {
  pick(None) + 1
}
'@ }

  @{ Name = 'c3_extern_result_is_used'; Expect = 'ACCEPT'
     Note = 'an extern function''s result carries its DECLARED return type'
     Target = 'native'
     Body = @'
extern "C" fn ext_scale() -> Double = "moui_ext_scale"

fn use_it() -> Bool {
  let s = ext_scale()
  s > 0.0
}
'@ }

  @{ Name = 'c4_extern_int_result_is_used'; Expect = 'ACCEPT'
     Note = 'the same, with an Int -- the moui web_host.mbt shape'
     Body = @'
fn ext_handle() -> Int = "window_web" "begin_create_string"

fn use_it() -> Int {
  let h = ext_handle()
  h + 1
}
'@ }

  @{ Name = 'c5_control_int_from_string'; Expect = 'REJECT'
     Note = 'a REAL type mismatch -- the control that keeps the C rows meaningful'
     Body = @'
fn use_it() -> Int {
  let x : Int = "s"
  x
}
'@ }

  @{ Name = 'c6_control_string_from_int'; Expect = 'REJECT'
     Note = 'the other direction of the same control'
     Body = @'
fn use_it() -> String {
  let x : String = 5
  x
}
'@ }

  @{ Name = 'c7_control_unannotated_if_body'; Expect = 'REJECT'
     Note = 'a function with NO return annotation whose tail is an `if` -- 4074'
     Body = @'
fn pick(c : Bool) {
  if c {
    1
  } else {
    2
  }
}
'@ }

  @{ Name = 'c8_annotated_if_body'; Expect = 'ACCEPT'
     Note = 'the same function WITH the annotation -- the shape the corpus uses'
     Body = @'
fn pick(c : Bool) -> Int {
  if c {
    1
  } else {
    2
  }
}
'@ }

  # c9 AND c10 CLOSE A HOLE IN c7, and they are here because a claim that was
  # measured once and then found to be INCOMPLETE has to be corrected in the
  # artifact that carries it, not only in the commit message.
  #
  # c7 says: a function with NO return annotation whose tail is an `if` is
  # REJECTED (4074). That was read as "every if-tailed function the toolchain
  # accepts carries an annotation 0493 can READ". It is not true, and c9 is the
  # counterexample: `-> Int64` is an annotation the toolchain accepts and the
  # type model CANNOT read -- `ann_to_ty` maps it to TUnknown, so `cycle_ret` is
  # AAny and 0493's declared-return-type fallback does NOT fire.
  #
  # So the corner EXISTS. c10 is what makes it unobservable: the only program
  # in which the corner produces a DIFFERENT verdict passes an Int64 where an Int
  # is expected, and the toolchain REJECTS it (4014, Expr Type Mismatch). The
  # lens cannot read the value at a use site whose parameter it CAN read,
  # because the toolchain's nominal typing forbids the widening that would
  # separate the two.
  @{ Name = 'c9_unreadable_declared_type_is_accepted'; Expect = 'ACCEPT'
     Note = 'an `if` tail under a declared type the type model CANNOT read'
     Body = @'
fn pick(c : Bool) -> Int64 {
  if c {
    1L
  } else {
    2L
  }
}
'@ }
  @{ Name = 'c10_control_int64_into_an_int_param'; Expect = 'REJECT'
     Note = 'the only program whose verdict differs -- 4014, Expr Type Mismatch'
     Body = @'
fn pick(c : Bool) -> Int64 {
  if c {
    1L
  } else {
    2L
  }
}

fn want_int(x : Int) -> Unit {
  println(x)
}

fn use_it(c : Bool) -> Unit {
  let v = pick(c)
  want_int(v)
}
'@ }

  # ---------------------------------------------------------------- class D
  @{ Name = 'd1_labelled_call_omits_an_optional'; Expect = 'ACCEPT'
     Note = 'a labelled call that OMITS an optional parameter -- the moui shape'
     Body = @'
fn from_routes(
  routes~ : Array[String],
  cursor? : Int = -1,
  title? : String = "",
  source? : String = "app",
) -> Int {
  routes.length() + cursor
}

fn use_it(s : Array[String]) -> Int {
  from_routes(routes=s, title="x", source="y")
}
'@ }

  @{ Name = 'd2_labelled_call_reorders'; Expect = 'ACCEPT'
     Note = 'a labelled call may REORDER -- the labels decide, not the positions'
     Body = @'
fn from_routes(
  routes~ : Array[String],
  cursor? : Int = -1,
  title? : String = "",
  source? : String = "app",
) -> Int {
  routes.length() + cursor
}

fn use_it(s : Array[String]) -> Int {
  from_routes(source="y", routes=s, title="x")
}
'@ }

  @{ Name = 'd3_labelled_call_omits_a_required'; Expect = 'REJECT'
     Note = 'a LABELLED parameter is REQUIRED -- the control on the arity rule'
     Body = @'
fn from_routes(
  routes~ : Array[String],
  cursor? : Int = -1,
  title? : String = "",
) -> Int {
  routes.length() + cursor
}

fn use_it(s : Array[String]) -> Int {
  from_routes(title="x")
}
'@ }

  @{ Name = 'd4_control_unknown_label'; Expect = 'REJECT'
     Note = 'a label the callee does not have -- the control on the label matching'
     Body = @'
fn from_routes(
  routes~ : Array[String],
  title? : String = "",
) -> Int {
  routes.length()
}

fn use_it(s : Array[String]) -> Int {
  from_routes(routes=s, nope="x")
}
'@ }

  @{ Name = 'd5_control_too_many_arguments'; Expect = 'REJECT'
     Note = 'more arguments than the callee declares -- still an error'
     Body = @'
fn from_routes(
  routes~ : Array[String],
  title? : String = "",
) -> Int {
  routes.length()
}

fn use_it(s : Array[String]) -> Int {
  from_routes(routes=s, title="x", extra=1)
}
'@ }

  @{ Name = 'd6_control_positional_omits_a_labelled_param'; Expect = 'REJECT'
     Note = 'a POSITIONAL call cannot supply a `~` parameter -- it must be by label'
     Body = @'
fn from_routes(
  routes~ : Array[String],
  cursor? : Int = -1,
  title? : String = "",
) -> Int {
  routes.length() + cursor
}

fn use_it(s : Array[String]) -> Int {
  from_routes(s)
}
'@ }

  # ---------------------------------------------------------------- class E
  @{ Name = 'e1_code_after_a_while_that_may_run_zero_times'; Expect = 'ACCEPT'
     Note = 'the statement after a `while` is REACHABLE -- the loop may run zero times'
     Body = @'
fn f(c : Bool) -> Int {
  let mut i = 0
  while c {
    return 1
  }
  0
}
'@ }

  @{ Name = 'e2_code_after_a_while_true'; Expect = 'ACCEPT'
     Note = 'a `while true` whose body always returns -- the statement after it is still accepted'
     Body = @'
fn f() -> Int {
  while true {
    return 1
  }
  0
}
'@ }

  @{ Name = 'e3_control_code_after_a_return'; Expect = 'ACCEPT'
     Note = 'MoonBit ACCEPTS code after a `return` -- the toolchain does NOT settle reachability'
     Body = @'
fn use_it() -> Int {
  return 1
  0
}
'@ }

  @{ Name = 'e4_control_code_after_a_raise'; Expect = 'REJECT'
     Note = 'the same, with `raise`'
     Body = @'
fn use_it() -> Int {
  raise NotFound
  0
}
'@ }
)

foreach ($r in $rows) {
  $proj = Join-Path $root $r.Name
  $pkg = Join-Path $proj 'src\main'
  New-Item -ItemType Directory -Force -Path $pkg | Out-Null
  $mod = @"
name = "$($r.Name)"

version = "0.1.0"
"@
  [System.IO.File]::WriteAllText((Join-Path $proj 'moon.mod'), $mod, (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $pkg 'moon.pkg'), "import {`n}`n", (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $pkg 'a.mbt'), $r.Body, (New-Object System.Text.UTF8Encoding($false)))
}

$moon = 'C:\Users\31379\.moon\bin\moon.exe'
Write-Output ('toolchain: ' + (((& $moon version) | Out-String) -split "`r?`n")[0].Trim())
Write-Output ('scratch:    ' + $root)
Write-Output ''
Write-Output ('{0,-46} {1,-8} {2,-64} {3,-8} {4}' -f 'ROW', 'EXPECT', 'NOTE', 'ACTUAL', 'THE TOOLCHAIN SAYS')
Write-Output ('-' * 200)

$bad = 0
$rejects = 0
foreach ($r in $rows) {
  $proj = Join-Path $root $r.Name
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  # A PER-ROW TARGET. `extern "C"` is not supported on the wasm backend --
  # the toolchain says so with 4156 -- and that is a fact about the BACKEND,
  # not about the type, so the extern row is settled on the native target.
  $targs = @('check')
  if ($r.ContainsKey('Target')) { $targs += @('--target', $r.Target) }
  $o = (& $moon -C $proj @targs 2>&1 | Out-String)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $actual = if ($code -eq 0) { 'ACCEPT' } else { 'REJECT' }
  if ($actual -eq 'REJECT') { $rejects++ }
  $why = ''
  $codes = @()
  foreach ($ln in ($o -split "`r?`n")) {
    if ($ln -match '(?i)\berror\b' -and $ln -notmatch 'FullyQualifiedErrorId|NativeCommandError|CategoryInfo|^\s*\+|^At ') {
      $why = $ln.Trim()
    }
    foreach ($m in [regex]::Matches($ln, '\b(4\d{3})\b')) { $codes += $m.Groups[1].Value }
  }
  $codeStr = if ($codes.Count -gt 0) { ' [' + (($codes | Select-Object -Unique) -join ',') + ']' } else { '' }
  if ($why.Length -gt 90) { $why = $why.Substring(0, 90) + '...' }
  if ($r.Expect -ne '?') {
    if ($actual -ne $r.Expect) { $bad++ }
    $verdict = if ($actual -eq $r.Expect) { '' } else { '  <<< DIFFERS' }
  } else {
    $verdict = '  (measured)'
  }
  Write-Output ('{0,-46} {1,-8} {2,-64} {3,-8} {4}{5}{6}' -f $r.Name, $r.Expect, $r.Note, $actual, $why, $codeStr, $verdict)
}
Write-Output ''
Write-Output ("rows: " + $rows.Count + "   controls that REJECTED: " + $rejects)

# ---------------------------------------------------------------- class E, by RUNNING it
#
# WHY THIS SECTION EXISTS, and it is a measurement rather than an opinion.
#
# MoonBit ACCEPTS code after a `return` -- row `e3_control_code_after_a_return`
# above ACCEPTED, and the row before it accepted too. So the toolchain does
# NOT settle reachability by compiling: it accepts BOTH a reachable and an
# unreachable statement. A settle built on accept/reject cannot tell the
# analyzer's `Unreachable` family from the truth, and the analyzer's claim is
# the one under examination.
#
# What settles it is RUNNING the program. The statement after a `while` that
# may run zero times IS reached, and the program says so: it prints 42. The
# control is the same program with a `return` in place of the `while`, and it
# prints 1 -- so the two are distinguished by the OUTPUT, and neither is
# distinguished by the exit code.
#
# The package needs `pkgtype(kind: "executable")` for `moon run` to find it,
# and the run is `moon -C <project> run src/main`.
Write-Output ''
Write-Output '--- class E, settled by RUNNING the program ---'
$execs = @(
  @{ Name = 'x1_while_that_may_run_zero_times'
     Note = 'the statement after the `while` IS reached -- the loop runs zero times'
     Want = '42'
     Body = @'
fn f(c : Bool) -> Int {
  while c {
    return 1
  }
  42
}

fn main {
  println(f(false))
}
'@ }
  @{ Name = 'x2_control_after_a_return'
     Note = 'the statement after a `return` is NOT reached -- the control'
     Want = '1'
     Body = @'
fn f() -> Int {
  return 1
  42
}

fn main {
  println(f())
}
'@ }
)
foreach ($r in $execs) {
  $proj = Join-Path $root ('exec_' + $r.Name)
  $pkg = Join-Path $proj 'src\main'
  New-Item -ItemType Directory -Force -Path $pkg | Out-Null
  $mod = @"
name = "$($r.Name)"

version = "0.1.0"
"@
  [System.IO.File]::WriteAllText((Join-Path $proj 'moon.mod'), $mod, (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $pkg 'moon.pkg'), "pkgtype(kind: `"executable`")`n`nimport {`n}`n", (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $pkg 'a.mbt'), $r.Body, (New-Object System.Text.UTF8Encoding($false)))
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = (& $moon -C $proj run src/main 2>&1 | Out-String)
  $ErrorActionPreference = $prev
  $printed = (($o -split "`r?`n") | Where-Object { $_.Trim() -match '^\d+$' } | Select-Object -First 1)
  if ($null -eq $printed) { $printed = '<nothing printed>' }
  $actual = if ($printed.Trim() -eq $r.Want) { 'REACHED' } else { 'DID NOT REACH' }
  if ($actual -ne 'REACHED') { $bad++ }
  Write-Output ('{0,-46} {1,-12} {2,-64} {3,-12} printed {4}' -f $r.Name, ('want ' + $r.Want), $r.Note, $actual, $printed.Trim())
}
Write-Output ''
if ($bad -eq 0) {
  Write-Output 'ALL EXPECTED ROWS MATCH THE EXPECTED VERDICT on the installed toolchain.'
} else {
  Write-Output ($bad.ToString() + ' ROW(S) DIFFER FROM THE EXPECTED VERDICT.')
}
if ($bad -gt 0) { exit 1 }
exit 0

# settle 0495 -- THE PER-FUNCTION VIEW'S FALSE POSITIVES, settled against the toolchain.
#
# WHAT THIS SETTLES. The per-function view of the behavioural lens reported
# 116 actionable findings across four pinned corpora, and NOT ONE of them is a
# defect in the code being analysed: every one of the 116 sites is in a file
# that `moon check` accepts, in packages that are released and published.
#
#     moonbit_labeler  38      moonbit_image  35
#     async            40      proton          3
#
# So the 116 are an INVENTORY OF THE LENS, and this script settles each
# family's construct against the TOOLCHAIN: does MoonBit accept this shape?
# The claim being settled is the toolchain's, not the analyzer's.
#
# THE FAMILIES, and the count of findings each one explains:
#
#   A   61   a destructured name bound to the WHOLE TUPLE
#   B   25   a `continue`/`break` that CARRIES A VALUE
#   C    8   a statement after a loop whose body always terminates
#   D   10   a call to an `extern` / FFI declaration
#   E    5   a cross-package qualified associated / trait call
#   F    4   an integer `/` typed as `float`
#   G    2   a name bound by an `is`-pattern `as`-binding
#   H    1   a name bound by an ITERATOR expression
#
# Every ACCEPT row below is code the toolchain must accept, and every REJECT row
# is a CONTROL -- a shape the toolchain must REFUSE, so that "the analyzer must
# stay silent on it" cannot be satisfied by silencing everything.
#
# A row whose Expect is '?' is MEASURED and not claimed: the author does not
# know the verdict, and the settle prints it rather than asserting it.
#
# THREE FACTS ABOUT THE FIXTURES, all measured, all of which cost this script
# a wrong row before they were settled:
#
#   1. A PACKAGE IS A DIRECTORY. `src/<pkg>` with its own `moon.pkg`. A bare
#      `moon.mod` plus a flat `src/*.mbt` is silently NOT a project the
#      toolchain checks -- `moon check` prints "no work to do" and exits 0,
#      which is a VACUOUS ACCEPT: every row in this file would have read
#      ACCEPT while the compiler had read nothing. The runner below REFUSES
#      that verdict explicitly, and a separate probe run measured it: with the
#      fixture's `moon.pkg` written one level too high, 23 of 23 rows ACCEPTed
#      -- including a control whose whole job is to be refused.
#   2. `print` IS NOT A BUILTIN in a standalone project; `println` IS. The
#      execution rows below print with `println` and read STDOUT ONLY, with
#      stderr redirected to its own file, because the compiler's own warnings
#      share stdout with the program's output otherwise.
#   3. `pkgtype(kind: "executable")` belongs to the EXECUTION rows only. On a
#      check row it adds "Missing main function in the main package" (4067) to
#      every single row, which is how a first run of this script reported 23
#      REJECTs that were all the same unrelated error.
#
# THE LAST SECTION IS SETTLED BY RUNNING the program, and it is there because
# the toolchain does NOT settle reachability by compiling. MoonBit ACCEPTS
# code after a `return` (row `c4_control_code_after_a_return_is_accepted`
# below), so a settle built on accept/reject cannot tell the analyzer's
# `Unreachable` family from the truth -- and the analyzer's claim is the one
# under examination. What settles it is RUNNING the program and reading what
# it prints.
#
# `moon.mod` is NOT JSON. It is `key = "value"`.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('perfunction_' + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$enc = New-Object System.Text.UTF8Encoding($false)

# The reason line under a diagnostic is drawn with box characters; this script
# matches them BY CODE POINT so that the file stays pure ASCII and a text
# round-trip through a console code page cannot corrupt it. The characters are
# then STRIPPED from the reason, because a console that cannot render them
# turns them into mojibake that hides the sentence that matters.
$BOX = [char]0x2570
$BOXES = [regex]::new('[\u2500-\u257F]')

$rows = @(
  # ------------------------------------------------------------------ A: destructuring
  @{ Name = 'a1_tuple_destructuring_binds_each_name'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `let (a, b) = pair()` binds the two ELEMENTS'
     Files = @{ 'src/main/a.mbt' = @'
fn pair() -> (Int, Int) {
  (1, 2)
}

fn use_it() -> Int {
  let (a, b) = pair()
  a + b
}
'@ } }
  @{ Name = 'a2_ctrl_the_whole_tuple_is_not_an_int'; Expect = 'REJECT'
     Note = 'the control on a1: the TUPLE is not an Int'
     Files = @{ 'src/main/a.mbt' = @'
fn use_it() -> Int {
  let t = (1, 2)
  t
}
'@ } }
  @{ Name = 'a3_ctrl_a_destructured_name_is_not_the_tuple'; Expect = 'REJECT'
     Note = 'the control on a1 from the other side: the name holds an ELEMENT'
     Files = @{ 'src/main/a.mbt' = @'
fn take(x : Int) -> Int {
  x
}

fn use_it() -> Int {
  let (a, b) = ("x", "y")
  take(a)
}
'@ } }

  # ------------------------------------------------------------------ B: valued continue / break
  @{ Name = 'b1_continue_carries_one_value'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `continue i + 1`'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(n : Int) -> Int {
  for i = 0; i < n; i = i + 1 {
    continue i + 1
  }
  0
}
'@ } }
  @{ Name = 'b2_continue_carries_several_values'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `continue i + 1, i + 1` -- TWO values'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(n : Int) -> Int {
  for a = 0, b = 0; a < n; {
    continue a + 1, b + 1
  }
  0
}
'@ } }
  @{ Name = 'b3_break_carries_a_tuple'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `break (consumed, produced)` -- needs a `nobreak`'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(n : Int) -> (Int, Int) {
  for consumed = 0; consumed < n; {
    break (consumed + 1, 0)
  } nobreak {
    (consumed, 0)
  }
}
'@ } }
  @{ Name = 'b3_ctrl_break_with_a_value_needs_a_yielding_loop'; Expect = 'REJECT'
     Note = 'the control on b3: `break i` in a C-style for with NO nobreak -- 4110'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(n : Int) -> Int {
  for i = 0; i < n; i = i + 1 {
    break i
  }
  0
}
'@ } }
  @{ Name = 'b3_ctrl_break_with_a_value_in_a_for_in'; Expect = 'REJECT'
     Note = 'the control on b3 from the other side: a `for i in 0..<n` yields nothing'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(n : Int) -> Int {
  for i in 0..<n {
    break (i, i)
  }
  0
}
'@ } }
  @{ Name = 'b4_ctrl_a_bare_continue_carries_no_value'; Expect = 'ACCEPT'
     Note = 'the bare form is legal MoonBit and carries nothing'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(n : Int) -> Int {
  for i = 0; i < n; i = i + 1 {
    continue
  }
  0
}
'@ } }
  @{ Name = 'b5_ctrl_a_carried_value_must_name_something'; Expect = 'REJECT'
     Note = 'the failure-capable control on b1: the carried name does not exist'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(n : Int) -> Int {
  for i = 0; i < n; i = i + 1 {
    continue zz_not_a_name
  }
  0
}
'@ } }

  # ------------------------------------------------------------------ C: the update clause
  @{ Name = 'c1_c_for_with_an_update_clause'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `for i = 0; i < 8; i = i + 1 { .. }`'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(n : Int) -> Unit {
  for i = 0; i < n; i = i + 1 {
    ignore(i)
  }
}
'@ } }
  @{ Name = 'c2_ctrl_a_c_for_update_may_not_bind_a_new_name'; Expect = 'REJECT'
     Note = 'the update may only assign the DECLARED names -- 4106'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(n : Int) -> Unit {
  for i = 0; i < n; j = j + 1 {
    ignore(i)
  }
}
'@ } }

  # ------------------------------------------------------------------ D: the extern declaration
  # d1 is MEASURED, NOT CLAIMED, and the reason is the machine, not the
  # language: `extern "C"` is a NATIVE-backend construct. This machine cannot
  # run the native target at all ("failed to run check for target Native"), and
  # every backend it CAN run rejects the whole extern declaration with 4156.
  # The authority for the ACCEPT is the CORPUS: moonbitlang/async 0.22.4,
  # src/socket/ffi.mbt:16, `extern "C" fn make_tcp_socket_ffi(..)`, in a
  # released and published package.
  @{ Name = 'd1_extern_c_declaration'; Expect = '?'
     Note = 'MEASURED: extern "C" is native-only; the corpus is the authority'
     Files = @{ 'src/main/a.mbt' = @'
extern "C" fn make_socket_ffi(family : Int) -> Int = "moonbitlang_async_make_tcp_socket"

fn make_socket(family : Int) -> Int {
  let sock = make_socket_ffi(family)
  sock
}
'@ } }
  @{ Name = 'd2_extern_js_declaration'; Expect = 'ACCEPT'; Target = 'js'
     Note = 'the corpus shape: an `extern "js"` fn with a callback parameter'
     Files = @{ 'src/main/a.mbt' = @'
extern "js" fn set_timeout(duration : Int, f : () -> Unit) -> Int =
  #| (duration, f) => setTimeout(f, duration)

fn arm(duration : Int) -> Int {
  set_timeout(duration) <| () => { ignore(1) }
}
'@ } }
  @{ Name = 'd2_ctrl_extern_js_is_not_accepted_by_every_backend'; Expect = 'REJECT'
     Note = 'the control on d2: the SAME declaration on the wasm backend -- 4156'
     Files = @{ 'src/main/a.mbt' = @'
extern "js" fn set_timeout(duration : Int, f : () -> Unit) -> Int =
  #| (duration, f) => setTimeout(f, duration)

fn arm(duration : Int) -> Int {
  set_timeout(duration) <| () => { ignore(1) }
}
'@ } }
  # 0495: the PIPE WITH A CALL ON ITS LEFT. The pipe supplies the argument, so
  # the call it makes has ONE MORE argument than it reads -- and the arity
  # check has to see it.
  @{ Name = 'd3_the_pipe_supplies_the_argument'; Expect = 'ACCEPT'
     Note = '`add2(1) <| 2` is `add2(1, 2)`'
     Files = @{ 'src/main/a.mbt' = @'
fn add2(a : Int, b : Int) -> Int {
  a + b
}

fn probe() -> Int {
  add2(1) <| 2
}
'@ } }
  @{ Name = 'd3_ctrl_the_pipe_does_not_invent_an_argument'; Expect = 'REJECT'
     Note = 'the control on d3: `one` declares ONE parameter'
     Files = @{ 'src/main/a.mbt' = @'
fn one(a : Int) -> Int {
  a
}

fn probe() -> Int {
  one(1) <| 2
}
'@ } }
  # 0495: the OMITTABLE parameter is not a positional slot.
  @{ Name = 'd4_an_omittable_parameter_is_skipped_positionally'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `f(a, b? : Int = 0, c)` called with two arguments'
     Files = @{ 'src/main/a.mbt' = @'
fn f(a : Int, b? : Int = 0, c : Int) -> Int {
  c + a + b
}

fn probe() -> Int {
  f(1, 2)
}
'@ } }
  @{ Name = 'd4_the_omittable_parameter_may_be_supplied_by_label'; Expect = 'ACCEPT'
     Note = 'the same parameter, supplied BY LABEL'
     Files = @{ 'src/main/a.mbt' = @'
fn f(a : Int, b? : Int = 0, c : Int) -> Int {
  c + a + b
}

fn probe() -> Int {
  f(1, 2, b=3)
}
'@ } }
  @{ Name = 'd4_ctrl_a_positional_parameter_may_not_be_passed_by_label'; Expect = 'REJECT'
     Note = 'the failure-capable control on d4: `c` is POSITIONAL -- 4080/4085'
     Files = @{ 'src/main/a.mbt' = @'
fn f(a : Int, b? : Int = 0, c : Int) -> Int {
  c + a + b
}

fn probe() -> Int {
  f(1, c=2)
}
'@ } }
  @{ Name = 'd4_ctrl_a_required_parameter_may_not_be_omitted'; Expect = 'REJECT'
     Note = 'the second failure-capable control on d4: `c` is required -- 4080'
     Files = @{ 'src/main/a.mbt' = @'
fn f(a : Int, b? : Int = 0, c : Int) -> Int {
  c + a + b
}

fn probe() -> Int {
  f(1)
}
'@ } }
  # 0495: ONE NAME, TWO DECLARATIONS -- the `#cfg` pattern. The corpus shape is
  # moonbitlang/async src/socket/ffi.mbt:19-37, where `make_tcp_socket` has one
  # declaration under `#cfg(not(platform="windows"))` and another under
  # `#cfg(platform="windows")`, with the SAME signature in both.
  @{ Name = 'd5_two_cfg_variants_of_one_name'; Expect = 'ACCEPT'
     Note = 'the corpus shape: one name, two #cfg declarations, same signature'
     Files = @{ 'src/main/a.mbt' = @'
#cfg(not(platform="windows"))
fn close_ffi(fd : Int, context~ : String) -> Int {
  0 + fd
}

#cfg(platform="windows")
fn close_ffi(fd : Int, context~ : String) -> Int {
  1 + fd
}

fn probe(fd : Int) -> Int {
  let context = "x"
  close_ffi(fd, context~)
}
'@ } }
  @{ Name = 'd5_the_live_cfg_variant_is_the_one_the_call_matches'; Expect = 'ACCEPT'
     Note = 'two #cfg variants, DIFFERENT arity -- the live one is the not(windows) one'
     Files = @{ 'src/main/a.mbt' = @'
#cfg(not(platform="windows"))
fn close_ffi(fd : Int, is_socket~ : Bool) -> Int {
  0 + fd
}

#cfg(platform="windows")
fn close_ffi(fd : Int) -> Int {
  1 + fd
}

fn probe(fd : Int) -> Int {
  close_ffi(fd, is_socket=true)
}
'@ } }
  @{ Name = 'd5_ctrl_too_many_arguments'; Expect = 'REJECT'
     Note = 'the failure-capable control on d5: a call with more arguments than declared'
     Files = @{ 'src/main/a.mbt' = @'
fn one(a : Int) -> Int {
  a
}

fn probe(a : Int) -> Int {
  one(a, a)
}
'@ } }

  # ------------------------------------------------------------------ E: the qualified trait call
  # The CORPUS shape, in the corpus's own two-package shape: a `pub(open)`
  # trait in the `io` package, an impl for a type in the calling package, and
  # the call `@io.Writer::write(self, s)`.
  @{ Name = 'e1_qualified_trait_call_across_packages'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `@io.Writer::write(self, s)`'
     Files = @{
       'src/io/a.mbt' = @'
pub(open) trait Writer {
  fn write(Self, String) -> Unit = _
}

impl Writer with fn write(self, s) {
  ignore(s)
}
'@
       'src/main/a.mbt' = @'
pub struct Server {
  id : Int
}

impl @io.Writer for Server with fn write(self, s) {
  ignore(s)
}

pub fn Server::write_string(self : Server, s : String) -> Unit {
  @io.Writer::write(self, s)
}
'@
     } }
  @{ Name = 'e1_ctrl_the_trait_has_no_such_method'; Expect = 'REJECT'
     Note = 'the control on e1: `@io.Writer::wrtie(self, s)` -- 4039'
     Files = @{
       'src/io/a.mbt' = @'
pub(open) trait Writer {
  fn write(Self, String) -> Unit = _
}

impl Writer with fn write(self, s) {
  ignore(s)
}
'@
       'src/main/a.mbt' = @'
pub struct Server {
  id : Int
}

impl @io.Writer for Server with fn write(self, s) {
  ignore(s)
}

pub fn Server::write_string(self : Server, s : String) -> Unit {
  @io.Writer::wrtie(self, s)
}
'@
     } }
  @{ Name = 'e1_ctrl_a_trait_is_not_a_type'; Expect = 'REJECT'
     Note = 'the control on e1 from the other side: `Writer::write(w, s)` -- 4099'
     Files = @{ 'src/main/a.mbt' = @'
pub(open) trait Writer {
  fn write(Self, String) -> Unit = _
}

impl Writer with fn write(self, s) {
  ignore(s)
}

fn send_it(w : Writer, s : String) -> Unit {
  Writer::write(w, s)
}
'@ } }

  # ------------------------------------------------------------------ F: the integer division
  @{ Name = 'f1_int_divided_by_int_is_an_int'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `let hs = h / 2` with `h : Int`'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(h : Int) -> Int {
  let hs = h / 2
  hs
}
'@ } }
  @{ Name = 'f2_ctrl_int_divided_by_int_is_not_a_float'; Expect = 'REJECT'
     Note = 'the control on f1: the result is an Int, not a Float'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(h : Int) -> Float {
  let hs = h / 2
  hs
}
'@ } }

  # ------------------------------------------------------------------ G: the `as` binding
  @{ Name = 'g1_is_pattern_with_an_as_binding'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `is (HasReader(_) as reader)` -- reader is the WHOLE value'
     Files = @{ 'src/main/a.mbt' = @'
enum State {
  HasReader(Int)
  Closed
}

fn probe(s : State) -> State {
  if s is (HasReader(_) as reader) {
    reader
  } else {
    s
  }
}
'@ } }
  @{ Name = 'g1_ctrl_the_as_binding_is_not_the_payload'; Expect = 'REJECT'
     Note = 'the control on g1: the as-binding used as an Int -- 4014'
     Files = @{ 'src/main/a.mbt' = @'
enum State {
  HasReader(Int)
  Closed
}

fn probe(s : State) -> Int {
  if s is (HasReader(_) as reader) {
    reader
  } else {
    0
  }
}
'@ } }
  @{ Name = 'g2_ctrl_the_as_binding_is_scoped_to_the_pattern'; Expect = 'REJECT'
     Note = 'the control on g1 from the other side: `reader` outside the pattern'
     Files = @{ 'src/main/a.mbt' = @'
enum State {
  HasReader(Int)
  Closed
}

fn probe(s : State) -> Int {
  if s is (HasReader(_) as reader) {
    ignore(reader)
  }
  ignore(reader)
  0
}
'@ } }

  # ------------------------------------------------------------------ H: the iterator expression
  @{ Name = 'h1_comprehension_binds_its_pattern'; Expect = 'ACCEPT'
     Note = 'the corpus shape: `[ for handle in xs => f(handle) ]`'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(xs : Array[Int]) -> Array[String] {
  [
    for handle in xs => handle.to_string()
  ]
}
'@ } }
  @{ Name = 'h2_ctrl_the_comprehension_pattern_does_not_escape'; Expect = 'REJECT'
     Note = 'the control on h1: `handle` is scoped to the comprehension'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(xs : Array[Int]) -> Int {
  [
    for handle in xs => handle.to_string()
  ]
  ignore(handle)
  0
}
'@ } }

  # ------------------------------------------------------------------ the reachability controls
  @{ Name = 'c4_control_code_after_a_return_is_accepted'; Expect = 'ACCEPT'
     Note = 'the toolchain does NOT settle reachability: it accepts dead code'
     Files = @{ 'src/main/a.mbt' = @'
fn probe() -> Int {
  return 1
  0
}
'@ } }
  @{ Name = 'c5_control_a_for_in_may_run_zero_times'; Expect = 'ACCEPT'
     Note = 'the statement after a `for ... in` is reachable -- the sequence decides'
     Files = @{ 'src/main/a.mbt' = @'
fn probe(xs : Array[Int]) -> Int {
  for x in xs {
    return 1
  }
  0
}
'@ } }
)

# ---------------------------------------------------------------------------
# THE RUNNER. It writes a REAL project per row: `moon.mod`, one directory per
# package with its OWN `moon.pkg`, and the row's sources.
#
# The `moon.pkg` placement is the whole ballgame. A package is a DIRECTORY; a
# `moon.pkg` written one level too high makes `moon check` print "no work to
# do" and exit 0 -- a VACUOUS ACCEPT that would have turned this whole file
# green while the compiler read nothing. So:
#
#   - `moon.pkg` goes in `src/<pkg>/`, next to that package's sources;
#   - a row with two packages gets the `io` package's OWN `moon.pkg`, and
#     `main` imports it by path;
#   - and the runner REFUSES a verdict of ACCEPT that came with "no work to
#     do", so this trap cannot pass silently again.
# ---------------------------------------------------------------------------
function Write-RowProject {
  param([string]$Dir, [hashtable]$Files)
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  # The target is PINNED rather than left to the default, because one row's
  # verdict is target-dependent: an `extern` declaration is refused outright
  # by the wasm backend (4156) and accepted by the js one. A row that reads
  # "the default target" is a row that changes meaning when the toolchain's
  # default changes.
  [System.IO.File]::WriteAllText((Join-Path $Dir 'moon.mod'), "name = `"probe`"`n`nversion = `"0.1.0`"`n`npreferred_target = `"wasm`"`n", $enc)
  $pkgs = @()
  foreach ($rel in $Files.Keys) {
    $full = Join-Path $Dir $rel
    $d = Split-Path -Parent $full
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    [System.IO.File]::WriteAllText($full, $Files[$rel], $enc)
    $pkg = Split-Path -Leaf $d
    if ($pkgs -notcontains $pkg) { $pkgs += $pkg }
  }
  foreach ($pkg in $pkgs) {
    $pkgdir = Join-Path $Dir ('src\' + $pkg)
    $body = "import {`n}`n"
    if ($pkg -eq 'main' -and ($pkgs -contains 'io')) {
      $body = "import {`n  `"probe/src/io`",`n}`n"
    }
    [System.IO.File]::WriteAllText((Join-Path $pkgdir 'moon.pkg'), $body, $enc)
  }
}

Write-Output 'toolchain: ' ((& $moon version) | Out-String).Trim()
Write-Output ('scratch:    ' + $root)
Write-Output ''
Write-Output ('{0,-48} {1,-8} {2,-60} {3,-8} {4}' -f 'ROW', 'EXPECT', 'NOTE', 'ACTUAL', 'THE TOOLCHAIN SAYS')
Write-Output ('-' * 200)

$bad = 0
$rejects = 0
$measured = 0
$vacuous = 0
foreach ($r in $rows) {
  $proj = Join-Path $root $r.Name
  Write-RowProject -Dir $proj -Files $r.Files
  $margs = @('-C', $proj, 'check')
  if ($r.ContainsKey('Target') -and $r.Target -ne '') { $margs += @('--target', $r.Target) }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = (& $moon @margs 2>&1 | Out-String)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  # THE VACUOUS-ACCEPT GUARD. "no work to do" means the compiler read NOTHING,
  # so an exit code of 0 says nothing about the fixture. It is not an ACCEPT.
  $nothing = ($o -match 'no work to do')
  if ($nothing) { $vacuous++ }
  $actual = if ($code -eq 0 -and -not $nothing) { 'ACCEPT' } else { 'REJECT' }
  if ($actual -eq 'REJECT') { $rejects++ }
  $why = ''
  $codes = @()
  $lines = $o -split "`r?`n"
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Contains($BOX)) { $why = ($BOXES.Replace($lines[$i], '')).Trim() }
    foreach ($m in [regex]::Matches($lines[$i], '\b(4\d{3})\b')) { $codes += $m.Groups[1].Value }
  }
  $codeStr = if ($codes.Count -gt 0) { ' [' + (($codes | Select-Object -Unique) -join ',') + ']' } else { '' }
  if ($why.Length -gt 84) { $why = $why.Substring(0, 84) + '...' }
  if ($nothing) { $why = 'NO WORK TO DO -- VACUOUS ACCEPT, REFUSED' }
  if ($r.Expect -eq '?') {
    $measured++
    $verdict = '  (measured)'
  } elseif ($actual -ne $r.Expect) {
    $bad++
    $verdict = '  <<< DIFFERS'
  } else {
    $verdict = ''
  }
  Write-Output ('{0,-48} {1,-8} {2,-60} {3,-8} {4}{5}{6}' -f $r.Name, $r.Expect, $r.Note, $actual, $why, $codeStr, $verdict)
}
Write-Output ''
Write-Output ("rows: " + $rows.Count + "   controls that REJECTED: " + $rejects + "   rows MEASURED: " + $measured + "   vacuous: " + $vacuous)

# ------------------------------------------------------------------ settled by RUNNING
#
# WHY THIS SECTION EXISTS, and it is a measurement rather than an opinion.
#
# MoonBit ACCEPTS code after a `return` -- row `c4_control_code_after_a_return_is_accepted`
# above ACCEPTED, and so did the row before it. The toolchain therefore does NOT
# settle reachability by compiling: it accepts BOTH a reachable and an
# unreachable statement. A settle built on accept/reject cannot tell the
# analyzer's `Unreachable` family from the truth.
#
# What settles it is RUNNING the program.
#
#   x1  A `continue` IN A C-STYLE `for` RUNS THE UPDATE CLAUSE. The program
#       prints `i=0 i=1 i=2 i=3` and finishes. It could only finish if the
#       update ran on the `continue` -- without it, `i` would stay at 1 and
#       the loop would never end. The analyzer reported the update clause as
#       `unreachable code`.
#   x2  THE CONTROL FOR x1: the same loop with the `continue` removed also
#       finishes, so the two are distinguished by WHETHER THE CONTINUE IS
#       THERE and not by the exit code.
#   x3  THE STATEMENT AFTER A LOOP THAT MAY RUN ZERO TIMES IS REACHED: the
#       program prints 42.
#   x4  THE CONTROL FOR x3: the statement after a `return` is NOT reached --
#       the program prints 1. The two are distinguished by the OUTPUT, and
#       neither by the exit code.
#   x5  FAMILY U: THE STATEMENT AFTER A `while true` THAT BREAKS IS REACHED.
#       The program prints 42. The analyzer had reported it as unreachable,
#       because the join of a `break` and a `return` collapses to `FReturn`.
#   x6  THE CONTROL FOR x5: a `while true` whose body RETURNS does not reach
#       the statement after it -- the program prints 1.
#
# The program prints with `println` (a builtin; `print` is not), and the run
# reads STDOUT ONLY, with stderr redirected to a file of its own, so that the
# compiler's warnings cannot be mistaken for the program's output.
#
# The package needs `pkgtype(kind: "executable")` for `moon run` to find it,
# and the run is `moon -C <project> run src/main`.
Write-Output ''
Write-Output '--- reachability, settled by RUNNING the program ---'
$execs = @(
  @{ Name = 'x1_continue_in_a_c_for_runs_the_update_clause'
     Note = 'the update clause is REACHED -- the loop advances past the continue'
     Want = 'i=0 i=1 i=2 i=3'
     Body = @'
fn main {
  for i = 0; i < 4; i = i + 1 {
    println("i=\{i}")
    if i == 1 {
      continue
    }
  }
}
'@ }
  @{ Name = 'x2_control_the_same_loop_without_the_continue'
     Note = 'the control for x1 -- the loop ends the same way'
     Want = 'i=0 i=1 i=2 i=3'
     Body = @'
fn main {
  for i = 0; i < 4; i = i + 1 {
    println("i=\{i}")
  }
}
'@ }
  @{ Name = 'x3_the_statement_after_a_loop_that_may_run_zero_times'
     Note = 'the statement after the loop IS reached -- the loop runs zero times'
     Want = '42'
     Body = @'
fn f(xs : Array[Int]) -> Int {
  for x in xs {
    return 1
  }
  42
}

fn main {
  println(f([]))
}
'@ }
  @{ Name = 'x4_control_the_statement_after_a_return'
     Note = 'the control for x3 -- the statement after a return is NOT reached'
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
  @{ Name = 'x5_the_statement_after_a_while_that_breaks'
     Note = 'family U: a `while true` whose body BREAKS -- the next statement runs'
     Want = '42'
     Body = @'
fn f() -> Int {
  while true {
    break
  }
  42
}

fn main {
  println(f())
}
'@ }
  @{ Name = 'x6_control_the_statement_after_a_while_that_returns'
     Note = 'the control for x5 -- a `return` in the body does NOT reach it'
     Want = '1'
     Body = @'
fn f() -> Int {
  while true {
    return 1
  }
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
  $mod = "name = `"$($r.Name)`"`n`nversion = `"0.1.0`"`n`npreferred_target = `"wasm`"`n"
  [System.IO.File]::WriteAllText((Join-Path $proj 'moon.mod'), $mod, $enc)
  [System.IO.File]::WriteAllText((Join-Path $pkg 'moon.pkg'), "pkgtype(kind: `"executable`")`n`nimport {`n}`n", $enc)
  [System.IO.File]::WriteAllText((Join-Path $pkg 'a.mbt'), $r.Body, $enc)
  $oFile = Join-Path $root ($r.Name + '.stdout')
  $eFile = Join-Path $root ($r.Name + '.stderr')
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  Start-Process -FilePath $moon -ArgumentList @('-C', $proj, 'run', 'src/main') -RedirectStandardOutput $oFile -RedirectStandardError $eFile -NoNewWindow -Wait | Out-Null
  $ErrorActionPreference = $prev
  # STDOUT ONLY. The compiler's diagnostics go to stderr, and mixing them in
  # is how a run that printed 42 was read as printing something else.
  $stdout = ''
  try { $stdout = [System.IO.File]::ReadAllText($oFile) } catch { $stdout = '' }
  $printed = (($stdout -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }) -join ' '
  if ($printed -eq '') { $printed = '<nothing on stdout>' }
  $actual = if ($printed -eq $r.Want) { 'REACHED' } else { 'DID NOT REACH' }
  if ($actual -ne 'REACHED') { $bad++ }
  Write-Output ('{0,-48} {1,-12} {2,-60} {3,-12} printed {4}' -f $r.Name, ('want ' + $r.Want), $r.Note, $actual, $printed)
}
Write-Output ''
if ($bad -eq 0 -and $vacuous -eq 0) {
  Write-Output 'ALL EXPECTED ROWS MATCH THE EXPECTED VERDICT on the installed toolchain.'
} else {
  if ($bad -gt 0) { Write-Output ($bad.ToString() + ' ROW(S) DIFFER FROM THE EXPECTED VERDICT.') }
  if ($vacuous -gt 0) { Write-Output ($vacuous.ToString() + ' ROW(S) READ "no work to do" -- A VACUOUS ACCEPT.') }
}
if ($bad -gt 0 -or $vacuous -gt 0) { exit 1 }
exit 0

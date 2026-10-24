$ErrorActionPreference = 'Continue'
# Verify a `match`'s ARMS ARE READ, that the findings which come back are TRUE
# ones, and that a match whose arms the subset cannot read falls back to the
# old behaviour EXACTLY.
#
# WHY THIS EXISTS. Before 0502 a `match`'s arms were consumed whole by
# `skip_braces`, which left a HOLE in the frame of the enclosing function --
# and a hole silenced the unused-local and unused-parameter checks for that
# WHOLE function. Six of the seven pinned corpora measured ZERO actionable
# findings because of it.
#
# 0502 reads the arms: they are parsed, their pattern names are bound, their
# guards and their `with` constraints are walked, and their bodies are walked.
# The findings come back -- but only the true ones, and that is what this gate
# is about.
#
# WHAT IT CHECKS, and each item is a thing that can be WRONG:
#
#   1. THE OUTPUT CONTRACT, on the real scanner and not on the library. Each
#      fixture is scanned, each asserted on the family counts AND on the
#      notice count.
#
#   2. THE NEGATIVE DIRECTION, which is the one that matters. A binding read
#      ONLY inside an arm body must NOT be reported: the arm body is real code
#      that reads it, and reporting it would be a false positive on correct
#      code. That is the assertion that goes red if the rule is ever wrong in
#      the direction that hurts.
#
#   3. THE FALLBACK IS EXACT. A match whose arms the subset CANNOT read must
#      fall back to the old behaviour -- the notice comes back, the file stays
#      readable, and the frame is NOT judged -- rather than half-read.
#
#   4. THE SIX MECHANISMS. Reading the arms surfaced fourteen findings across
#      the seven corpora, and THIRTEEN of them were false positives, each one
#      from a different mechanism in the reader or the collector. Each
#      mechanism has a fixture here, and each fixture is the corpus shape that
#      produced the false positive.
#
#   5. THE FIXTURES ARE NOT VACUOUS. Every fixture is asserted to have been
#      read, so "nothing was reported" cannot be read as "nothing was looked
#      for".
#
# There is no -SelfTest switch, and that is deliberate: this gate is shown to go
# red by INJECTING a defect into the tree and running it, which is a stronger
# statement than a switch that reproduces the checker's own logic.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_match_arms.ps1
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$repos = Join-Path $root '.repos'
$fail = 0

if (-not (Test-Path -LiteralPath $wasm)) {
  Write-Output 'ABORT: no wasm artifact. Build it first.'
  exit 1
}

# --- the fixtures ------------------------------------------------------------
# Each is a whole file, so the counts are per file and cannot be confused with
# one another.
$FIXTURES = [ordered]@{
  # THE RECOVERY. A binding read NOWHERE in a function with a match is dead,
  # and before 0502 the match's hole hid that verdict for the whole function.
  'dead_local.mbt' = @(
    'fn f(z : Int) {'
    '  let dead = 1'
    '  match z {'
    '    0 => 1'
    '    _ => 0'
    '  }'
    '}'
  )
  # AND ITS COUNTERPART: the same shape with the read INSIDE the arm. The arm
  # body is real code that reads it, so it is not dead.
  'live_local.mbt' = @(
    'fn f(z : Int) {'
    '  let live = 1'
    '  match z {'
    '    0 => live'
    '    _ => 0'
    '  }'
    '}'
  )
  'dead_param.mbt' = @(
    'fn f(p : Int, z : Int) {'
    '  match z {'
    '    0 => 1'
    '    _ => 0'
    '  }'
    '}'
  )
  'live_param.mbt' = @(
    'fn f(p : Int, z : Int) {'
    '  match z {'
    '    0 => p'
    '    _ => 0'
    '  }'
    '}'
  )
  # A PATTERN'S NAMES ARE NOT AUDITABLE. `v` is bound by the pattern and never
  # read, and it is not an unused local: `Some` in `Some(v)` is a constructor
  # rather than a variable, and `v` is a pattern binding rather than a local.
  'pattern_binding.mbt' = @(
    'fn f(z : Int) {'
    '  match z {'
    '    Some(v) => 0'
    '    _ => 0'
    '  }'
    '}'
  )
  # THE ARM BODY IS ANALYSED, so a name nothing binds inside it is reported.
  'arm_undefined.mbt' = @(
    'fn f(z : Int) {'
    '  match z {'
    '    0 => nothing_binds_this'
    '    _ => 0'
    '  }'
    '}'
  )
  # AND A `let` INSIDE AN ARM BODY IS VISIBLE TO THAT ARM BODY -- the
  # collector's half of the change.
  'arm_let.mbt' = @(
    'fn f(z : Int) {'
    '  match z {'
    '    0 => {'
    '      let q = 1'
    '      q'
    '    }'
    '    _ => 0'
    '  }'
    '}'
  )
  # A GUARD IS READ TOO. `p` is read only by the guard, so it is not dead; and
  # the guard's own read of `z` is a read.
  'guard_live.mbt' = @(
    'fn f(p : Int, z : Int) {'
    '  match z {'
    '    0 if p > 0 => 1'
    '    _ => 0'
    '  }'
    '}'
  )
  'guard_dead.mbt' = @(
    'fn f(p : Int, z : Int) {'
    '  match z {'
    '    0 if z > 0 => 1'
    '    _ => 0'
    '  }'
    '}'
  )
  # AN ARM BODY THAT IS A STRUCT LITERAL. The brace is ambiguous in MoonBit --
  # a block and a literal look the same until the first field -- and reading it
  # as a block instead made `{ leading: 0.0, gap: base_gap }` a block whose
  # first statement is not a statement at all.
  'struct_literal_body.mbt' = @(
    'fn f(z : Int) {'
    '  match z {'
    '    0 => { leading: 0.0, gap: 1.0 }'
    '    _ => { leading: 2.0, gap: 3.0 }'
    '  }'
    '}'
  )
  # THE FALLBACK. An array literal with a `..` spread is MoonBit this frontend
  # does not model, so the arms cannot be read -- and the OLD behaviour must
  # come back exactly: the notice, and a file that is still readable.
  'unreadable_arms.mbt' = @(
    'fn f(z : Int) {'
    '  let arr = [1, 2]'
    '  match z {'
    '    0 => [1, ..arr]'
    '    _ => [2]'
    '  }'
    '}'
  )
  # THE CONTROL. No match, so the frame is judged whole, exactly as it always
  # was. Without this, a change that switched the family off everywhere would
  # make every assertion above pass.
  'no_match.mbt' = @(
    'fn f() {'
    '  let dead = 1'
    '}'
  )

  # --- THE SIX MECHANISMS. Each fixture is the corpus shape that produced a
  # --- false positive when the arms were first read.
  #
  # 1. `as` MAY START A NEW LINE. moonbitlang/async 0.22.4
  #    `src/fs/watch.mbt:216,222,233` -- the cast at the end of an arm's block
  #    body, on the line after its operand. The parser's postfix loop broke at
  #    the newline, so the `as` was read as a NAME.
  'm1_cast_next_line.mbt' = @(
    'fn f(x : Int) -> Int {'
    '  match 0 {'
    '    0 => {'
    '      x'
    '      as &Bar'
    '    }'
    '    _ => 0'
    '  }'
    '}'
  )
  # 2. A DESTRUCTURING LET'S INITIALISER IS NOT DISCARDED.
  #    moonbitlang/core `internal/regex_engine/shared_types/rechar_set/
  #    rechar_set.mbt:202,214` -- `let (lo, l) = { let p = ..; p }`, and the
  #    collector threw the initialiser away, so the frame never learned `p`.
  'm2_destruct_let.mbt' = @(
    'fn f(lo : Int) -> Int {'
    '  match 0 {'
    '    0 => {'
    '      let (lo, l) = {'
    '        let p = lo - 1'
    '        p'
    '      }'
    '      l'
    '    }'
    '    _ => 0'
    '  }'
    '}'
  )
  # 4. A STRUCT LITERAL'S FIELD VALUES ARE COLLECTED.
  #    wzzc-dev/moui 0.1.12 `views/text/text_input_apply.mbt:166` -- a `match`
  #    in a struct-literal field, and the collector never descended into the
  #    field, so the `let start` inside the arm body never reached the frame.
  'm4_struct_field_match.mbt' = @(
    'fn f(n : Int) -> Int {'
    '  match 0 {'
    '    0 => {'
    '      let c = {'
    '        cursor: match n {'
    '          Some(v) => {'
    '            let start = v'
    '            start'
    '          }'
    '          None => 0'
    '        },'
    '      }'
    '      c.cursor'
    '    }'
    '    _ => 0'
    '  }'
    '}'
  )
  # 5. AN ASSIGNMENT INTRODUCES NO BINDING. moonbitlang/async 0.22.4
  #    `src/process/windows.mbt:105` -- the local is read inside a NESTED
  #    LOCAL FUNCTION and assigned there too, and the collector gave the inner
  #    scope its own shadow of the name.
  'm5_nested_fn_assign.mbt' = @(
    'fn f(k : Int) -> Unit {'
    '  let mut x = 0'
    '  fn g() {'
    '    if k > x {'
    '      ignore(k)'
    '    }'
    '    x = 1'
    '  }'
    '  g()'
    '}'
  )
  # 6. A `with` CONSTRAINT READS. moonbitlang/core `builtin/option.mbt:50` --
  #    `Some(t) | (None with t = default) => t`, where `default` is a parameter
  #    and the only mention of it is inside the constraint.
  'm6_with_constraint.mbt' = @(
    'fn f(self : Int?, default : Int) -> Int {'
    '  match self {'
    '    Some(t) | (None with t = default) => t'
    '  }'
    '}'
  )
}

# what each fixture must produce: UnusedLocal, UnusedParam, UndefinedName, notices
$EXPECT = [ordered]@{
  'dead_local.mbt'          = @(1, 0, 0, 0)
  'live_local.mbt'          = @(0, 0, 0, 0)
  'dead_param.mbt'          = @(0, 1, 0, 0)
  'live_param.mbt'          = @(0, 0, 0, 0)
  'pattern_binding.mbt'     = @(0, 0, 0, 0)
  'arm_undefined.mbt'       = @(0, 0, 1, 0)
  'arm_let.mbt'             = @(0, 0, 0, 0)
  'guard_live.mbt'          = @(0, 0, 0, 0)
  'guard_dead.mbt'          = @(0, 1, 0, 0)
  'struct_literal_body.mbt' = @(0, 0, 0, 0)
  'unreadable_arms.mbt'     = @(0, 0, 0, 1)
  'no_match.mbt'            = @(1, 0, 0, 0)
  'm1_cast_next_line.mbt'   = @(0, 0, 0, 0)
  'm2_destruct_let.mbt'     = @(0, 0, 0, 0)
  'm4_struct_field_match.mbt' = @(0, 0, 0, 0)
  'm5_nested_fn_assign.mbt' = @(0, 0, 0, 0)
  'm6_with_constraint.mbt'  = @(0, 0, 0, 0)
}

# --- the PACKAGE fixture, in its own directory -------------------------------
# 3. A SAME-PACKAGE TYPE'S METHOD MAY BE CALLED UNQUALIFIED.
#    moonbitlang/core `immut/vector/vector.mbt:68` declares
#    `pub fn[A] Vector::makei(..)` and `immut/vector/invariants_wbtest.mbt`
#    calls it as `makei(..)` -- same package, same directory.
#
# IT IS IN ITS OWN DIRECTORY on purpose: the rule is PACKAGE-LOCAL, so the
# package table has to be built from a real package, and a fixture that shared
# a directory with the others could not prove the scoping. `pkg_call_bad.mbt`
# is the CONTROL: a name that is not a method of anything in the package is
# still reported.
$PKG = [ordered]@{
  'pkg_decl.mbt' = @(
    'pub fn[A] Vector::makei(n : Int) -> Int {'
    '  n'
    '}'
  )
  'pkg_call_ok.mbt' = @(
    'fn g() -> Int {'
    '  let v = makei(3)'
    '  v'
    '}'
  )
  'pkg_call_bad.mbt' = @(
    'fn g() -> Int {'
    '  not_a_method_of_anything'
    '}'
  )
}
$PKG_EXPECT = [ordered]@{
  'pkg_decl.mbt'     = @(0, 0, 0, 0)
  'pkg_call_ok.mbt'  = @(0, 0, 0, 0)
  'pkg_call_bad.mbt' = @(0, 0, 1, 0)
}

$dir = Join-Path $env:TEMP ('matcharms_' + [guid]::NewGuid().ToString('N').Substring(0,8))
$pkgdir = Join-Path $env:TEMP ('matchpkg_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
New-Item -ItemType Directory -Force -Path $pkgdir | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
foreach ($name in $FIXTURES.Keys) {
  [IO.File]::WriteAllText((Join-Path $dir $name), ($FIXTURES[$name] -join "`n") + "`n", $enc)
}
foreach ($name in $PKG.Keys) {
  [IO.File]::WriteAllText((Join-Path $pkgdir $name), ($PKG[$name] -join "`n") + "`n", $enc)
}

function Scan-Tree([string]$tree, [string]$tag) {
  $out = Join-Path $tree ('scan_' + $tag + '.txt')
  $errf = Join-Path $tree ('scan_' + $tag + '.err')
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $tree, '--extern-iface-dir', $repos, '--no-auto-fetch-deps',
                    '--findings-shown-per-file', '1000000') `
    -RedirectStandardOutput $out -RedirectStandardError $errf -NoNewWindow -Wait | Out-Null
  $t = [IO.File]::ReadAllText($out)
  $perFile = @{}
  $file = ''
  foreach ($ln in ($t -split "`r?`n")) {
    if ($ln -match '^(FOUND|CLEAN|PARTIAL|NOTPARSE)\t') {
      $parts = $ln -split "`t"
      $file = ($parts[$parts.Count - 1].Trim() -split '[\\/]')[-1]
      if (-not $perFile.ContainsKey($file)) { $perFile[$file] = @() }
      continue
    }
    if ($ln -match '^\d+:\d+ - (error|warning|hint|notice): (.*) \((\w+)\) \[([^\]]*)\]\s*$') {
      if (-not $perFile.ContainsKey($file)) { $perFile[$file] = @() }
      $perFile[$file] = $perFile[$file] + @($Matches[3])
    }
  }
  return $perFile
}

# The file comes from the header above the findings, and it is the LAST tab
# separated field of it: `FOUND <kind> <defects> <notices> <path>`.
#
# The file is keyed by its LEAF NAME, not by the path. The scanner writes the
# path with a FORWARD slash before the file name (`<dir>/dead_local.mbt`)
# while `Join-Path` produces a BACKSLASH, so a path comparison misses every
# file and every count comes out zero -- which reads as "nothing was found"
# rather than "nothing was looked for".
$perFile = Scan-Tree $dir 'main'
$pkgPerFile = Scan-Tree $pkgdir 'pkg'

Write-Output '=== 1. the output contract, on the real scanner ==='
foreach ($name in $FIXTURES.Keys) {
  $fams = @()
  if ($perFile.ContainsKey($name)) { $fams = $perFile[$name] }
  $ul = @($fams | Where-Object { $_ -eq 'UnusedLocal' }).Count
  $up = @($fams | Where-Object { $_ -eq 'UnusedParam' }).Count
  $un = @($fams | Where-Object { $_ -eq 'UndefinedName' }).Count
  $nt = @($fams | Where-Object { $_ -eq 'ParseError' }).Count
  $want = $EXPECT[$name]
  $ok = ($ul -eq $want[0]) -and ($up -eq $want[1]) -and ($un -eq $want[2]) -and ($nt -eq $want[3])
  $mark = if ($ok) { 'ok  ' } else { 'FAIL' }
  if (-not $ok) { $fail++ }
  Write-Output ("  {0} {1,-24} UnusedLocal={2} UnusedParam={3} UndefName={4} notices={5}   (want {6}/{7}/{8}/{9})" -f `
    $mark, $name, $ul, $up, $un, $nt, $want[0], $want[1], $want[2], $want[3])
}

Write-Output ''
Write-Output '=== 2. the negative direction: a binding read ONLY inside an arm body ==='
# The one assertion that must not be traded away. `live_local.mbt` has a
# binding that is read only by an arm body, so reporting it would be a false
# positive on correct code -- and the arm body IS read now, so the silence is
# a fact about the code rather than a hole in the coverage.
foreach ($pair in @(@('live_local.mbt', 'UnusedLocal'), @('live_param.mbt', 'UnusedParam'))) {
  $name = $pair[0]; $fam = $pair[1]
  $fams = @()
  if ($perFile.ContainsKey($name)) { $fams = $perFile[$name] }
  $n = @($fams | Where-Object { $_ -eq $fam }).Count
  if ($n -ne 0) {
    Write-Output ("  FAIL: a binding read only inside an arm body was reported ({0} {1})" -f $n, $fam)
    $fail++
  } else {
    Write-Output ("  ok   a binding read only inside an arm body is NOT reported ({0})" -f $fam)
  }
}

Write-Output ''
Write-Output '=== 3. the fallback is EXACT: arms the subset cannot read ==='
# A match whose arms hold MoonBit this frontend does not model must fall back
# to the old behaviour -- the notice comes back, and the frame is NOT judged.
# A half-read arm list is the arrangement that produced the false positive.
$uf = 'unreadable_arms.mbt'
$fams = @()
if ($perFile.ContainsKey($uf)) { $fams = $perFile[$uf] }
$nt = @($fams | Where-Object { $_ -eq 'ParseError' }).Count
$ul = @($fams | Where-Object { $_ -eq 'UnusedLocal' }).Count
if ($nt -ne 1) {
  Write-Output ("  FAIL: the fallback notice is not there ({0} notices) -- the arms were half-read" -f $nt)
  $fail++
} else {
  Write-Output '  ok   the fallback notice is back, so the arms were NOT half-read'
}
if ($ul -ne 0) {
  Write-Output ("  FAIL: the frame was judged although the arms were not read ({0} UnusedLocal)" -f $ul)
  $fail++
} else {
  Write-Output '  ok   and the frame is NOT judged, because the arms were not read'
}

Write-Output ''
Write-Output '=== 4. the six mechanisms: the findings that came back are true ones ==='
# Each of these is a corpus shape that produced a false positive when the arms
# were first read. They are asserted above; this section names them, because a
# fixture that fails is easier to diagnose when the section says which corpus
# finding it stands for.
$mech = [ordered]@{
  'm1_cast_next_line.mbt'     = 'as may start a new line -- async src/fs/watch.mbt:216,222,233'
  'm2_destruct_let.mbt'       = 'a destructuring let''s initialiser binds -- core rechar_set.mbt:202,214'
  'm4_struct_field_match.mbt' = 'a struct literal''s field values are collected -- moui text_input_apply.mbt:166'
  'm5_nested_fn_assign.mbt'   = 'an assignment introduces no binding -- async src/process/windows.mbt:105'
  'm6_with_constraint.mbt'    = 'a with constraint reads -- core builtin/option.mbt:50'
}
foreach ($k in $mech.Keys) {
  $fams = @()
  if ($perFile.ContainsKey($k)) { $fams = $perFile[$k] }
  $bad = @($fams | Where-Object { $_ -eq 'UnusedLocal' -or $_ -eq 'UnusedParam' -or $_ -eq 'UndefinedName' }).Count
  if ($bad -ne 0) {
    Write-Output ("  FAIL: {0} -- {1}" -f $k, $mech[$k])
    $fail++
  } else {
    Write-Output ("  ok   {0} -- {1}" -f $k, $mech[$k])
  }
}

Write-Output ''
Write-Output '=== 4b. the same-package method, in its own package ==='
foreach ($name in $PKG.Keys) {
  $fams = @()
  if ($pkgPerFile.ContainsKey($name)) { $fams = $pkgPerFile[$name] }
  $ul = @($fams | Where-Object { $_ -eq 'UnusedLocal' }).Count
  $up = @($fams | Where-Object { $_ -eq 'UnusedParam' }).Count
  $un = @($fams | Where-Object { $_ -eq 'UndefinedName' }).Count
  $nt = @($fams | Where-Object { $_ -eq 'ParseError' }).Count
  $want = $PKG_EXPECT[$name]
  $ok = ($ul -eq $want[0]) -and ($up -eq $want[1]) -and ($un -eq $want[2]) -and ($nt -eq $want[3])
  $mark = if ($ok) { 'ok  ' } else { 'FAIL' }
  if (-not $ok) { $fail++ }
  Write-Output ("  {0} {1,-18} UnusedLocal={2} UnusedParam={3} UndefName={4} notices={5}   (want {6}/{7}/{8}/{9})" -f `
    $mark, $name, $ul, $up, $un, $nt, $want[0], $want[1], $want[2], $want[3])
}

Write-Output ''
Write-Output '=== 5. the fixtures are not vacuous ==='
foreach ($name in $FIXTURES.Keys) {
  if (-not $perFile.ContainsKey($name)) {
    Write-Output ("  FAIL: " + $name + " produced no findings at all -- the scanner did not read it")
    $fail++
  }
}
foreach ($name in $PKG.Keys) {
  if (-not $pkgPerFile.ContainsKey($name)) {
    Write-Output ("  FAIL: " + $name + " produced no findings at all -- the scanner did not read it")
    $fail++
  }
}
if ($fail -eq 0) { Write-Output '  ok   every fixture was read' }

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'GATE OK: the arms are read, the findings that come back are true ones, and a match the subset cannot read falls back exactly.'
  exit 0
} else {
  Write-Output ("GATE FAILED: " + $fail + " check(s).")
  exit 1
}

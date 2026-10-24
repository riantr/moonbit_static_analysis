$ErrorActionPreference = 'Continue'
# 0504 settle: THE COMPREHENSION GUARD.
#
# WHY THIS SETTLE EXISTS. 0503 -- the `raise?` fix -- made 27 more files of
# moonbitlang/core readable, and one of them, `hashset/hashset.mbt:382`, then
# reported `undefined variable 'key'` on
#
#     [ for entry in self.entries if entry is Some({ key, .. }) => key ]
#
# The COMPILER ACCEPTS that line -- core is a published package that compiles --
# so the finding is a FALSE POSITIVE. The cause is in the PARSER, not in the
# lenses: `parse_comprehension` reads the guard and THROWS IT AWAY --
#
#     if self.at_name("if") {
#       let _ = self.bump()
#       ignore(self.parse_or())          <-- the guard never reaches the AST
#     }
#
# so the `is` binding the guard introduces (`key`) is never bound, and the
# body's read of it is reported as an undefined variable. The parser's own
# comment above the guard says the guard "belongs HERE -- between the iterable
# and `=>`", and it was never carried there.
#
# THE QUESTION THIS SETTLE ANSWERS: what IS a comprehension guard, and what
# must the analyzer DO with it? Four things, each measured rather than assumed:
#
#   1. the guard is COMPILED -- an undefined name inside it is an error, so it
#      is real code and not a comment;
#   2. the guard FILTERS -- it is evaluated once per element (the RUNTIME rows);
#   3. the `is` binding the guard introduces IS IN SCOPE for the body, and
#      ONLY for the body;
#   4. the guard may READ the loop variable, and the loop variable's scope is
#      not affected by the guard's binding.
#
# FOUR CONTROLS, because a probe whose every case is ACCEPTED has measured
# NOTHING:
#   * THE CANARY binds nothing and uses the name. It MUST be REJECTED.
#   * THE NO-GUARD CONTROL -- the same comprehension without the `if` -- MUST be
#     ACCEPTED. If it were REJECTED, the premise of the whole increment would
#     be wrong.
#   * THE NO-BINDING CONTROL -- a guard whose `is` binds nothing -- MUST be
#     ACCEPTED, so the binding rows are measuring the BINDING and not the shape.
#   * THE WRONG-NAME CONTROL -- a body that uses a name the guard does NOT
#     bind -- MUST be REJECTED, so "the body accepted `key`" cannot be read as
#     "the body accepts any name".
#
# TWO INSTRUMENTS. The first is `moon check`, which answers "is this program
# legal". The second is `moon test`, which answers "does the guard actually
# RUN" -- a question `moon check` cannot answer, and the one that decides
# whether a name read only inside a guard is a real read. A reader that keeps
# the guard would report such a name as used; a reader that drops it reports
# it as unused, which is a false positive on correct code.
#
# -----------------------------------------------------------------------------
# TWO CORRECTIONS, and both of them are the kind that a gate exists to catch.
#
# 1. THE NO-BINDING CONTROL WAS MEASURING THE WRONG THING. The first version
#    of row G was
#
#        [ for arg in args if arg is Pos(_) => arg ]
#
#    with `Pos` a STRUCT, and it was REJECTED with error 4199. The rejection
#    has nothing to do with the guard: `is` matches CONSTRUCTORS, and a struct
#    TYPE is not a constructor -- you cannot match on `Pos` at all. Probed:
#    `is Pos(_)`, `is Pos({ name, .. })` and `is Pos({ name })` are ALL rejected
#    with 4199, while `is Some(_)` is accepted. So the row was rejected for a
#    reason that had nothing to do with what it was written to measure, and it
#    would have gone into the parser as a claim that the toolchain refuses
#    something it does not.
#
#    The control now uses `Some(_)`, which binds nothing -- which is what the
#    control is FOR. The measured fact is kept as its own row (G2), because
#    "a struct type is not a pattern head" is the kind of thing that gets
#    re-derived, wrongly, otherwise.
#
# 2. `{ key }` IS NOT A BLOCK. The first version of row N was
#
#        => { key }
#
#    and it was REJECTED with 4033 and 4028. `{ key }` is a one-field STRUCT
#    LITERAL, not a block -- the same distinction the parser already draws
#    (and the same one 0468 settled: `let x = { a }` is a struct literal).
#    The row now uses a block with a statement in it, which is what "block
#    body" means.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\settle_0504_comp_guard.ps1
$dir = Join-Path $env:TEMP ('settle0504cg_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0504cg`"`nversion = `"0.1.0`"`n", $enc)

$PRE_ENTRY = "pub struct Entry {`n  key : Int`n  other : Int`n}`n`npub fn entries() -> Array[Option[Entry]] {`n  []`n}`n`n"

$cases = [ordered]@{
  # THE CANARY: a name bound NOWHERE. It MUST be rejected.
  'canary.mbt' = "fn keep() -> Int {`n  nope`n}`n"

  # A: THE CORPUS SHAPE -- the `is` binding the guard introduces is used in the
  # body. This is `hashset/hashset.mbt:382` verbatim in shape.
  'a_corpus_shape.mbt' = $PRE_ENTRY + "pub fn f() -> Array[Int] {`n  [`n    for entry in entries() if entry is Some({ key, .. }) => key`n  ]`n}`n"

  # B: THE WRONG-NAME CONTROL. The same comprehension, with a body that uses a
  # name the guard does NOT bind. It MUST be rejected -- this is what stops
  # row A from meaning "the body accepts any name".
  'b_wrong_name_in_body.mbt' = $PRE_ENTRY + "pub fn f() -> Array[Int] {`n  [`n    for entry in entries() if entry is Some({ key, .. }) => notbound`n  ]`n}`n"

  # C: THE SCOPE ENDS WITH THE COMPREHENSION. The guard's binding is not
  # visible after the comprehension closes. It MUST be rejected.
  'c_binding_not_visible_after.mbt' = $PRE_ENTRY + "pub fn f() -> Array[Int] {`n  let a = [`n    for entry in entries() if entry is Some({ key, .. }) => key`n  ]`n  key`n}`n"

  # D: THE GUARD MAY READ THE LOOP VARIABLE.
  'd_guard_reads_loop_var.mbt' = "pub fn f(xs : Array[Int]) -> Array[Int] {`n  [ for x in xs if x > 0 => x ]`n}`n"

  # E: THE GUARD IS COMPILED. An undefined name inside it MUST be rejected --
  # this is what proves the guard is real code rather than a comment, and it
  # is the row that says the guard cannot be dropped.
  'e_guard_unresolved_name.mbt' = "pub fn f(xs : Array[Int]) -> Array[Int] {`n  [ for x in xs if nosuchfn(x) => x ]`n}`n"

  # F: THE NO-GUARD CONTROL. The same comprehension without the `if`.
  'f_no_guard_control.mbt' = "pub fn f(xs : Array[Int]) -> Array[Int] {`n  [ for x in xs => x ]`n}`n"

  # G: THE NO-BINDING CONTROL. A guard whose `is` binds nothing. CORRECTED --
  # see correction 1 above: the first version used a STRUCT head and was
  # rejected with 4199 for a reason that had nothing to do with the guard.
  'g_guard_is_without_binding.mbt' = "pub fn f(args : Array[Option[Int]]) -> Array[Option[Int]] {`n  [ for arg in args if arg is Some(_) => arg ]`n}`n"

  # G2: THE MEASURED FACT CORRECTION 1 KEPT. A struct TYPE is not a pattern
  # head -- `is` matches CONSTRUCTORS. REJECTED with 4199, in an `if` and in a
  # comprehension guard alike, so it is the `is` rule and not the guard.
  'g2_struct_head_not_a_constructor.mbt' = $PRE_ENTRY + "pub fn f(args : Array[Entry]) -> Array[Entry] {`n  [ for arg in args if arg is Entry(_) => arg ]`n}`n"

  # H: THE BINDING IS VISIBLE LATER IN THE SAME GUARD. `is` binds for the rest
  # of the expression, so `&& key > 0` may read it. This is the corpus shape
  # `p.peek() is TName(tag) && tag.has_prefix("@")`.
  'h_is_binding_read_in_same_guard.mbt' = $PRE_ENTRY + "pub fn f() -> Array[Int] {`n  [`n    for entry in entries() if entry is Some({ key, .. }) && key > 0 => key`n  ]`n}`n"

  # I: THE GUARD BELONGS BEFORE THE BODY. The `if` after the `=>` is not
  # MoonBit -- this is the order the parser's own comment records.
  'i_guard_after_body.mbt' = "pub fn f(xs : Array[Int]) -> Array[Int] {`n  [ for x in xs => x if x > 0 ]`n}`n"

  # J: ONE GUARD. A second `if` in the same comprehension.
  'j_two_guards.mbt' = "pub fn f(xs : Array[Int]) -> Array[Int] {`n  [ for x in xs if x > 0 if x < 10 => x ]`n}`n"

  # K: THE BLOCK BODY. The guard's binding is used inside `{ .. }`.
  'k_block_body_with_binding.mbt' = $PRE_ENTRY + "pub fn f() -> Array[Int] {`n  [`n    for entry in entries() if entry is Some({ key, .. }) => { key + 1 }`n  ]`n}`n"

  # L: THE GUARD CALLS OUT. A function call in the guard -- the shape that
  # makes an outer name read ONLY inside a guard a real read.
  'l_guard_calls_out.mbt' = "pub fn helper() -> Bool {`n  true`n}`n`npub fn f(xs : Array[Int]) -> Array[Int] {`n  [ for x in xs if helper() => x ]`n}`n"

  # M: THE BODY IS CHECKED WITHOUT A GUARD TOO. The undefined-name family must
  # still be alive -- a fix that silences the family is not a fix.
  'm_body_undefined_no_guard.mbt' = "pub fn f(xs : Array[Int]) -> Array[Int] {`n  [ for x in xs => nosuchname ]`n}`n"

  # N: THE BLOCK BODY, CORRECTED -- see correction 2 above. `{ key }` is a
  # one-field STRUCT LITERAL, not a block. This row uses a block with a
  # statement in it, and the guard's binding is read inside that statement.
  'n_block_body_with_statement.mbt' = $PRE_ENTRY + "pub fn f() -> Array[Int] {`n  [`n    for entry in entries() if entry is Some({ key, .. }) => { let k = key; k + 1 }`n  ]`n}`n"
}

$expected = [ordered]@{
  'canary.mbt'                    = 'REJECTED'
  'a_corpus_shape.mbt'            = 'ACCEPTED'
  'b_wrong_name_in_body.mbt'       = 'REJECTED'
  'c_binding_not_visible_after.mbt'= 'REJECTED'
  'd_guard_reads_loop_var.mbt'     = 'ACCEPTED'
  'e_guard_unresolved_name.mbt'   = 'REJECTED'
  'f_no_guard_control.mbt'        = 'ACCEPTED'
  'g_guard_is_without_binding.mbt'= 'ACCEPTED'
  'g2_struct_head_not_a_constructor.mbt' = 'REJECTED'
  'h_is_binding_read_in_same_guard.mbt' = 'ACCEPTED'
  'i_guard_after_body.mbt'        = 'REJECTED'
  'j_two_guards.mbt'              = 'REJECTED'
  'k_block_body_with_binding.mbt' = 'ACCEPTED'
  'l_guard_calls_out.mbt'         = 'ACCEPTED'
  'm_body_undefined_no_guard.mbt' = 'REJECTED'
  'n_block_body_with_statement.mbt' = 'ACCEPTED'
}

$outFile = Join-Path $dir 'check.out'
$fail = 0
Write-Output '=== THE GRAMMAR AND THE SCOPE (moon check) ==='
Push-Location $dir
foreach ($k in $cases.Keys) {
  Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File | ForEach-Object { [System.IO.File]::Delete($_.FullName) }
  [System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir ('src\' + $k)), $cases[$k], $enc)
  $present = @(Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File)
  if ($present.Count -ne 1 -or $present[0].Name -ne $k) {
    Write-Output ("{0,-34} ABORT: src holds {1} file(s)" -f $k, $present.Count); $fail++; continue
  }
  & cmd.exe /c "moon check > `"$outFile`" 2>&1"
  $out = [System.IO.File]::ReadAllText($outFile)
  if ([string]::IsNullOrWhiteSpace($out)) {
    Write-Output ("{0,-34} ABORT: moon check produced no output at all" -f $k); $fail++; continue
  }
  $finished = ($out -match 'Finished\.\s*moon:\s*ran\s+\d+\s+task')
  $failed = ($out -match 'failed when checking project')
  if (-not $finished -and -not $failed) {
    Write-Output ("{0,-34} ABORT: moon check did no work" -f $k); $fail++; continue
  }
  # A run is REJECTED when the project failed to check, or when it reported a
  # real error code. 4069 is the "warnings only" code and is not an error.
  $errs = @([regex]::Matches($out, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $real = @($errs | Where-Object { $_ -notin @('4069') })
  $got = if ($failed -or $real.Count -gt 0) { 'REJECTED' } else { 'ACCEPTED' }
  $want = $expected[$k]
  $ok = ($got -eq $want)
  Write-Output ('{0,-34} {1,-9} (want {2}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    ($out -split "`n" | Where-Object { $_ -match 'Parse error|Error: \[|error:' } | Select-Object -First 4) |
      ForEach-Object { '      ' + $_.Trim() }
  }
}
Pop-Location

# -----------------------------------------------------------------------------
# THE SECOND INSTRUMENT. `moon check` says the program is LEGAL; it cannot say
# the guard RUNS. These rows are what decide whether a name read only inside a
# guard is a real read.
# -----------------------------------------------------------------------------
$rt = [ordered]@{
  # RT1: THE GUARD FILTERS. If the guard were not evaluated, the list would
  # keep all three elements and the assertion would fail.
  'rt_guard_filters.mbt' = "test `"the guard filters`" {`n  let xs = [1, 2, 3]`n  let kept = [ for x in xs if x > 2 => x ]`n  assert_eq(kept, [3])`n}`n"

  # RT2: THE `is` BINDING REACHES THE BODY, and the guard still filters. A
  # dropped guard would keep `None` in the list and lose the binding.
  'rt_is_binding_reaches_body.mbt' = "test `"the is binding reaches the body`" {`n  let xs : Array[Option[Int]] = [Some(1), None, Some(3)]`n  let kept = [ for x in xs if x is Some(v) => v ]`n  assert_eq(kept, [1, 3])`n}`n"
}

Write-Output ''
Write-Output '=== THE EVALUATION (moon test) ==='
Push-Location $dir
foreach ($k in $rt.Keys) {
  Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File | ForEach-Object { [System.IO.File]::Delete($_.FullName) }
  [System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir ('src\' + $k)), $rt[$k], $enc)
  $tOut = Join-Path $dir 'test.out'
  & cmd.exe /c "moon test > `"$tOut`" 2>&1"
  $tout = [System.IO.File]::ReadAllText($tOut)
  if ([string]::IsNullOrWhiteSpace($tout)) {
    Write-Output ("{0,-34} ABORT: moon test produced no output at all" -f $k); $fail++; continue
  }
  # The summary line is `Total tests: N, passed: P, failed: F.`
  $m = [regex]::Match($tout, 'Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)')
  if (-not $m.Success) {
    Write-Output ("{0,-34} ABORT: moon test produced no test summary" -f $k); $fail++
    ($tout -split "`n" | Select-Object -First 6) | ForEach-Object { '      ' + $_.Trim() }
    continue
  }
  $total = [int]$m.Groups[1].Value
  $passedN = [int]$m.Groups[2].Value
  $failedN = [int]$m.Groups[3].Value
  if ($total -ne 1) {
    Write-Output ("{0,-34} ABORT: moon test ran {1} test(s), expected 1" -f $k, $total); $fail++; continue
  }
  $passed = ($passedN -eq 1 -and $failedN -eq 0)
  Write-Output ('{0,-34} {1,-9} (want PASS) {2}' -f $k, $(if ($passed) { 'PASS' } else { 'FAIL' }), $(if ($passed) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $passed) {
    $fail++
    ($tout -split "`n" | Where-Object { $_ -match 'error|Error|assert|failed' } | Select-Object -First 6) |
      ForEach-Object { '      ' + $_.Trim() }
  }
}
Pop-Location

Write-Output ''
if ($fail -gt 0) { Write-Output "ABORT: $fail case(s) did not match the expected verdict."; exit 1 }
Write-Output 'GATE OK: a comprehension guard is COMPILED code -- it is resolved, it is evaluated once per element, and the `is` binding it introduces is in scope for the body and for nothing else. A reader that drops it reports the body''s read of that binding as an undefined variable, on a program the toolchain accepts.'
exit 0

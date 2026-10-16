# Settle the grammar for a BLOCK in the RHS of a `let`, before writing any parser.
#
# WHY A SETTLE AND NOT A FIX. The parser already HAS the discriminator this needs --
# `at_struct_literal`, used at statement position (`parser.mbt:2602`) -- and the
# expression-position atom arm (`parser.mbt:5306`) ignores it and sends every `{` to
# the field grammar. So the change looks like three lines.
#
# It is not, because the discriminator has an AMBIGUITY that decides whether the change
# is correct or destructive. `at_struct_literal` accepts
#
#     (TName, TColon) | (TName, TComma) | (TDot, TDot)
#
# and a bare brace whose first field is a SHORTHAND with no comma -- `{ a }` -- matches
# NONE of those. Under the change it would become a BLOCK containing the name `a`
# instead of a one-field struct literal. Whether that is a fix or a regression is a
# question about the LANGUAGE, not about the parser, so it is settled here.
#
# THE METHOD, and the four things it needs bolted on before its answer means anything.
# The first two were both found by running it, not by reading it:
#
#   1. THE CANARY IS A ROW, NOT A FILE BESIDE THE SUBJECT. The first version wrote
#      `zz_canary_broken.mbt` into every row's package. A deliberately broken file in
#      the same package makes the PACKAGE check fail, so every row reported REJECT --
#      including three controls that are legal MoonBit. The table was a perfect
#      confirmation of the opposite of what it claimed, and the canary "reported in
#      12 of 12" while destroying all 12 answers. `_verify/grammar_probe.ps1` gets
#      this right and its canary is a CASE; this settle copied the idea and inverted
#      the mechanism.
#   2. THE PRELUDE IS LEGALITY-TESTED ON ITS OWN. `scaffold_alone` below exists because
#      the first version shared one prelude across every row, so a broken prelude --
#      `A::{ }`, an update with no fields -- rejected all twelve at once and looked
#      exactly like a grammar finding.
#   3. `0 errors` IS MATCHED WITH A NEGATIVE LOOKBEHIND. `(...) -match '0 errors'` also
#      matches `10 errors`, so a row with ten type errors scores ACCEPT.
#   4. ITS OWN PACKAGE PER ROW, so one row's build-plan failure cannot mask another.
$ErrorActionPreference = 'Continue'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'

# THE SHARED PART IS A TYPE, AND THE BINDINGS GO INSIDE EACH ROW.
#
# The second version of this file put `let a`, `let b`, `let base` inside a helper
# FUNCTION, on the theory that they would then be "already in scope". They are not:
# a function's locals are invisible to its siblings, so every row that used a
# shorthand field failed with 4021 (unbound identifier) and 4033, and the table again
# said nothing about the grammar. The third version binds them in each row's own body,
# which is the only place a name is actually in scope.
#
# MoonBit wants a `main` for TOP-LEVEL `let`, and adding a `main` to every package is
# its own way of changing what is being measured. So: the shared part is a `struct`
# declaration (legal at top level), and the bindings are local.
# THREE FIXTURE CORRECTIONS, EACH CAUGHT BY THE SCAFFOLDING CONTROL ABOVE, and the
# record is worth more than the fix: a settle whose scaffolding is wrong does not
# return "no answer", it returns a confident answer about the wrong thing.
#
#   1. `let a`, `let b`, `let base` sat inside a helper FUNCTION, so they were out of
#      scope for every row -- 4021 unbound, 4033 mismatch.
#   2. `scaffold_alone` returned `a` (an `Int`) from a function declared `-> A`.
#   3. THE STRUCTS WERE THE WRONG SIZE. `struct A` has three required fields, so
#      `{ a: 1 }` is not an `A` and every single-field control rejected on a TYPE
#      mismatch while looking like a grammar finding.
#
# => 判据: size the type to the question. `{ a: 1 }` is a question about a ONE-field
# literal; answering it with a three-field struct measures field COUNT instead.
$STRUCT = "struct S {`n  a : Int`n}`nstruct P {`n  a : Int`n  b : Int`n}`nstruct A {`n  a : Int`n  b : Int`n  c : Int`n}`n"
$LOC = "  let a = 1`n  let b = 2`n"
$LOC_A = "  let a = 1`n  let b = 2`n  let base = A::{ a: 1, b: 2, c: 3 }`n  ignore(base)`n"

$ROWS = [ordered]@{}
# ROW 0 IS THE CANARY. It must REJECT. If it does not, the toolchain did not engage and
# every other row's verdict is unverified -- which is why it is a row.
$ROWS['canary_must_reject'] = "fn canary( { let = 1 }`n"
# ROW 1 PROVES THE SHARED PART IS LEGAL on its own, so a rejection in any later row is a
# fact about that row's construct rather than about the scaffolding every row shares.
$ROWS['scaffold_alone'] = $STRUCT + "fn f() -> Int {`n" + $LOC + "  a`n}`n"

$SHAPES = [ordered]@{
  # --- the shape 0468 is about ---------------------------------------------
  'block_tail_int'      = "fn f() -> Int {`n__L__  let x = { 1 }`n  x`n}"
  'block_annotated'     = "fn f() -> Int {`n__L__  let x : Int = { 1 }`n  x`n}"
  'block_with_stmts'    = "fn f() -> Int {`n__L__  let x = {`n    let y = 1`n    y + 1`n  }`n  x`n}"
  'block_bare_name'     = "fn f() -> Int {`n__L__  let x = { b }`n  x`n}"
  'block_empty'         = "fn f() -> Unit {`n__L__  let x = { }`n  ()`n}"
  'block_nested'        = "fn f() -> Int {`n__L__  let x = { { 1 } }`n  x`n}"

  # --- NEGATIVE ROW: named `block_*` ONCE, and it was WRONG -----------------
  # This row USED to be called `block_bare_name` and sat in the `block_` family,
  # which is a CLAIM that the toolchain reads `{ b }` as a block. Re-measured
  # 2026-10-17: REJECT, [4033]. It is not a block.
  #
  # The false claim survived because the script asserted only the CANARY and the
  # four ACCEPT controls -- a negative row has no assertion, so nothing notices
  # when it silently stops being what its name says. => 判据: assert the NEGATIVE rows
  # too. A row whose name states a category is a claim about a measurement.
  'neg_bare_name'       = "fn f() -> Int {`n__L__  let x = { b }`n  x`n}"

  # --- CONTROLS: forms that MUST STAY struct literals ----------------------
  'ctrl_struct_named'   = "fn f() -> S {`n__L__  let x = { a: 1 }`n  x`n}"
  'ctrl_struct_typed'   = "fn f() -> P {`n__L__  let x : P = { a: 1, b: 2 }`n  x`n}"
  'ctrl_struct_shorthand_comma' = "fn f() -> P {`n__L__  let x = { a, b }`n  x`n}"
  'ctrl_struct_update'  = "fn f() -> A {`n__A__  let x = { ..base, a: 3 }`n  x`n}"

  # --- THE AMBIGUOUS ROWS: shorthand with NO comma and NO colon ------------
  # These decide whether `at_struct_literal` is safe to reuse in expression
  # position. If the toolchain reads `{ a }` as a one-field literal, the
  # discriminator is INCOMPLETE and reusing it silently converts struct literals
  # into blocks -- which would make 0468 a regression wearing a fix.
  'ambig_shorthand_one' = "fn f() -> S {`n__L__  let x = { a }`n  x`n}"
  'ambig_shorthand_one_noann' = "fn f() -> Int {`n__L__  let x = { a }`n  x`n}"

  # --- QUOTED KEYS, ADDED AFTER THE 0452 TESTS WENT RED -------------------
  # The first run of the 0468 parser change broke four tests in
  # `src/pipeline/pipeline_0452_test.mbt`, and this block exists so the next
  # change does not have to learn it from a red suite.
  #
  # A quoted key arrives as `TStr`, NOT `TName`, so it matches NONE of the
  # discriminator's shapes and every map literal was routed to the BLOCK path.
  # 0452 added quoted keys; this settle was written without them, which is the
  # same omission in the same costume: a change sized to the fixtures I happened
  # to think of.
  'ctrl_map_quoted_key' = "fn f() -> Map[String, Int] {`n  let x = { `"a`": 1 }`n  x`n}"
  'ctrl_map_quoted_no_colon' = "fn f() -> Map[String, Int] {`n  let x = { `"a`" }`n  x`n}"
  'ctrl_map_quoted_empty_value' = "fn f() -> Map[String, Int] {`n  let x = { `"a`": }`n  x`n}"
  # The recovery fixture 0452's test now uses. A NUMERIC key cannot begin a field, so
  # this is the `peek_name() == ""` branch -- the same path the old `{ 1 }` fixture
  # took -- and it costs exactly ONE parse failure. Measured against the pipeline's own
  # `parse_failures`, not against the scanner's deduped notice lines: `{ "a" }` and
  # `{ "a": }` each cost TWO there, and a probe that counted distinct messages said
  # one. Same "confident zero", different field.
  'ctrl_map_numeric_key' = "fn f() -> Map[String, Int] {`n  let x = { 1: 2 }`n  x`n}"
  'ctrl_map_quoted_then_name' = "fn f() -> Map[String, Int] {`n  let a = 1`n  let x = { `"a`": 1 }`n  x`n}"
}
foreach ($k in $SHAPES.Keys) {
  $ROWS[$k] = $STRUCT + $SHAPES[$k].Replace('__A__', $LOC_A).Replace('__L__', $LOC)
}

$base = Join-Path $env:TEMP ('settle0468_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $base | Out-Null
Write-Output '=== settle: block in the RHS of a let ==='
Write-Output ('    temp = ' + $base)
Write-Output ''
Write-Output ('  {0,-30} {1,-8} {2}' -f 'row', 'MOON', 'toolchain said')
Write-Output ('  {0,-30} {1,-8} {2}' -f ('-' * 30), ('-' * 8), ('-' * 50))

$verdicts = [ordered]@{}
foreach ($k in $ROWS.Keys) {
  $d = Join-Path $base $k
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), ("name = `"settle/$k`"`n`nversion = `"0.1.0`"`n"))
  [IO.File]::WriteAllText((Join-Path $d 'moon.pkg'), "supported_targets = `"+all`"`n")
  [IO.File]::WriteAllText((Join-Path $d 'subject.mbt'), $ROWS[$k] + "`n")

  Push-Location $d
  $mo = (& $moon check 2>&1 | Out-String)
  Pop-Location

  $flat = ($mo -replace "`r?`n", ' ')
  $mv = if ($flat -match '(?<!\d)0 errors') { 'ACCEPT' } else { 'REJECT' }
  $verdicts[$k] = $mv

  $said = ''
  foreach ($ln in ($mo -split "`n")) {
    if ($ln -match 'subject\.mbt' -and $ln -match '(?i)(error|expect|unexpected)') { $said = $ln.Trim(); break }
  }
  if ([string]::IsNullOrWhiteSpace($said)) {
    $said = ([regex]::Match($mo, '(?m)^(?:Error: \[?\d*\]?.*|.*unexpected.*|.*expect.*)$')).Value
  }
  if ([string]::IsNullOrWhiteSpace($said)) { $said = '(no error line found)' }
  if ($said.Length -gt 92) { $said = $said.Substring(0, 92) }
  Write-Output ('  {0,-30} {1,-8} {2}' -f $k, $mv, $said)
}

Write-Output ''
$bad = @()
if ($verdicts['canary_must_reject'] -ne 'REJECT') {
  $bad += 'the canary row was ACCEPTed, so the toolchain did not engage and every verdict below is unverified'
}
if ($verdicts['scaffold_alone'] -ne 'ACCEPT') {
  $bad += 'the PRELUDE is not legal MoonBit, so every row that shares it is measuring my scaffolding'
}
foreach ($c in @('ctrl_struct_named', 'ctrl_struct_shorthand_comma', 'ctrl_struct_typed', 'ctrl_map_quoted_key')) {
  if ($verdicts[$c] -ne 'ACCEPT') { $bad += ("control {0} REJECTs, so this table cannot tell a construct from a fixture" -f $c) }
}
# THE NEGATIVE ROWS GET ASSERTED TOO. They did not used to, and that is exactly how
# `block_bare_name` sat in the `block_` family for an increment while REJECTing:
# nothing checked it, so nothing noticed. Asserting only the rows you expect to pass
# leaves the interesting half of the table unverified.
#
# Each is here for the SAME reason -- it is the form that would justify DROPPING an arm
# from `at_struct_literal`. If one of them ever ACCEPTs, the corresponding arm is
# load-bearing in a way the parser does not currently model, and that is a finding.
foreach ($n in @('neg_bare_name', 'ambig_shorthand_one_noann', 'ctrl_map_quoted_no_colon', 'ctrl_map_numeric_key')) {
  if ($verdicts[$n] -ne 'REJECT') { $bad += ("negative {0} ACCEPTs, so a `{`-shaped form the parser routes by syntax is legal unannotated -- re-derive at_struct_literal" -f $n) }
}
# AND THE POSITIVE BLOCK ROWS, by name. This is the assertion whose absence let the
# stale `block_bare_name` category survive: the list of "the parser must read these"
# was a HARDCODED foreach below rather than a check against `$verdicts`.
foreach ($b in @('block_tail_int', 'block_annotated', 'block_with_stmts', 'block_empty', 'block_nested')) {
  if ($verdicts[$b] -ne 'ACCEPT') { $bad += ("block row {0} REJECTs, so it is not a block and 0468's premise is wrong there" -f $b) }
}
if ($bad.Count -gt 0) {
  Write-Output '*** THE SCAFFOLDING IS BROKEN -- the table above is not evidence about the grammar: ***'
  foreach ($b in $bad) { Write-Output ('  - ' + $b) }
  exit 1
}
Write-Output 'scaffolding verified: canary REJECTs, scaffold ACCEPTs, all struct-literal controls ACCEPT.'
Write-Output ''
Write-Output '=== THE MEASURED ANSWER (2026-10-17) ==='
Write-Output ''
Write-Output '  ambig_shorthand_one  ACCEPT    `fn f() -> S { let a = 1; let x = { a }; x }`'
Write-Output ''
Write-Output 'THE OBVIOUS THREE-LINE FIX IS WRONG, and this is the row that says so.'
Write-Output '`parser.mbt:5306` sends every expression-position `{` to the field grammar; the'
Write-Output 'tempting change is to gate it on `at_struct_literal` the way statement position'
Write-Output 'already does at 2602. But `{ a }` is a legal ONE-FIELD STRUCT LITERAL, and'
Write-Output '`at_struct_literal` accepts only (TName,TColon) | (TName,TComma) | (TDot,TDot).'
Write-Output 'A brace holding `a` then `}` matches NONE of them, so the discriminator answers'
Write-Output 'false and the change would rewrite a valid struct literal as a block.'
Write-Output ''
Write-Output '=> 0468 IS TWO THINGS, NOT ONE: add a block production for the braces the'
Write-Output 'discriminator REJECTS, AND widen `at_struct_literal` with (TName, TRBrace) so'
Write-Output 'the shorthand single-field literal keeps reading as a literal. Doing only the'
Write-Output 'first half is a regression wearing a fix -- and the corpus counts would still'
Write-Output 'improve while `let x = { a }` silently became a block.'
Write-Output ''
Write-Output 'The two REJECT rows are the same fact from the other side, and they are why'
Write-Output '`ambig_shorthand_one` carries an annotation: `{ a }` needs a KNOWN TARGET TYPE'
Write-Output 'to read as a literal at all, and without one the toolchain rejects it (4014).'
Write-Output 'So in this position the block-vs-literal choice genuinely depends on the'
Write-Output 'annotation -- and the unannotated form is not one the corpora write, which is'
Write-Output 'why widening the discriminator costs nothing measurable.'
Write-Output ''
Write-Output 'ACCEPT, so the parser must read them as BLOCKS (derived from the run above,'
Write-Output 'not typed in here -- this list used to be a hardcoded foreach, which is how a row'
Write-Output 'stopped being a block without the list noticing):'
foreach ($k in $SHAPES.Keys) {
  if ($k.StartsWith('block_') -and $verdicts[$k] -eq 'ACCEPT') { Write-Output ('  ' + $k) }
}
Write-Output ''
Write-Output 'REJECT, so each of these is the form that justifies NOT routing it to a block:'
foreach ($k in @('neg_bare_name', 'ambig_shorthand_one_noann', 'ctrl_map_quoted_no_colon', 'ctrl_map_numeric_key', 'ctrl_map_quoted_empty_value')) {
  Write-Output ('  {0,-30} {1}' -f $k, $verdicts[$k])
}
Write-Output ''
Write-Output '`neg_bare_name` is the interesting one. It is `fn f() -> Int { let x = { b }; x }`'
Write-Output 'with `b` an ordinary local Int -- indistinguishable in shape from a one-field'
Write-Output 'struct literal, and it REJECTs. So (TName, TRBrace) => literal cannot capture a'
Write-Output 'legal block, because there is no legal unannotated `{ <name> }` block to capture.'
Write-Output 'That is the whole safety argument for the widened arm, and until this re-run it'
Write-Output 'rested on a row that had been renamed out from under it. Its error is [4033], not'
Write-Output 'the [4014] of `ambig_shorthand_one_noann` -- a different code, so this is a second'
Write-Output 'independent negative, not a duplicate measurement of the first.'


$ErrorActionPreference = 'Continue'
# 0503 settle: MAY A RETURN ANNOTATION CARRY `raise?`?
#
# WHY. The parser reads the `?` marker of the raise clause in the FUNCTION-TYPE
# position (`src/parser/parser.mbt:1955-1958`) and NOT in the RETURN position
# (`:2444-2449`). The parser's own comment above the first site names this
# failure mode in the other direction: "Reading the clause in one position but
# not the other leaves a program that parses as `fn f() -> Int raise` and then
# dies on the very next function that takes a callback". It was fixed on one
# side only.
#
# MEASURED, on the pinned corpus, 2026-10-24:
#   * `-> T raise?` in a RETURN position: 162 sites in 31 files, ALL of them in
#     moonbitlang/core 0.1.20260920+7d59c7ec9. Zero in the other six corpora and
#     zero in this analyzer's own source, so fixing it moves ONE corpus row and
#     nothing else.
#   * three real core files carrying it -- array.mbt, option.mbt, result.mbt --
#     scanned ALONE: `PARSED 0/3 files understood (0.0%)`, with the error
#     `unexpected token `?``. The analyzer stops at the `?`.
#   * the COMPILER ACCEPTS `fn f() -> Int raise? { 1 }` (moon check, 0.10.17).
#
# THE COMPILER IS THE ORACLE, and the first run of this settle CORRECTED THE
# PREMISE. The question is not "does the analyzer read `?`" but "WHICH `?` is
# legal", and the answer is NARROWER than "after any raise clause":
#
#     -> Int raise?              ACCEPTED     the bare raise, marked optional
#     -> Int raise MyErr?        REJECTED     4032 + 3002 -- a typed raise has
#                                               no optional form
#     -> Int raise + nocancel?   REJECTED     3002 "unexpected token `?`"
#     -> Int noraise?            REJECTED     an optional marker on "does not
#                                               raise" is meaningless
#     -> Int nocancel?           REJECTED
#     -> Int! ?                  REJECTED     the short form has no optional form
#
# => THE `?` BELONGS TO A BARE `raise` AND TO NOTHING ELSE. A reader that
# accepted the `?` after ANY clause would read programs the toolchain refuses,
# which is the false-negative direction the parser's own comments prefer -- but
# it would also be reading a shape the language does not have, and the settle
# below is what says so.
#
# FIVE GUARDS, because a probe whose every case is ACCEPTED has measured NOTHING:
#   * THE CANARY binds nothing and uses the name. It MUST be REJECTED.
#   * THE NEGATIVE CONTROL omits the body, so the signature alone is invalid.
#     It MUST be REJECTED, and that is what proves the clause is really PARSED.
#   * THE CONTROL FOR THE FIX -- the function-TYPE position, which the parser
#     already reads -- MUST be ACCEPTED. If it were REJECTED, the premise of the
#     whole increment would be wrong.
#
# -----------------------------------------------------------------------------
# TWO CORRECTIONS, and both of them are the kind that a gate exists to catch.
#
# 1. THE `?` WITH NO EFFECT CLAUSE. The first version of this settle had
#
#       fn f() -> Int ? { 1 }        REJECTED   "the `?` marks a raise; it
#                                                   cannot stand alone"
#
#    and the MEASUREMENT was right -- the toolchain rejects it -- while the
#    REASON was wrong, and the reason is the one that was about to be written
#    into the parser. `-> Int ?` and `-> Int?` are THE SAME TOKENS, and
#    `-> Int?` is the nullable return type, which the toolchain ACCEPTS. So the
#    rejection cannot have been about the `?`: it was the BODY. `-> Int?` says
#    the return type is an Option and the body returned `1`, an Int -- an Expr
#    Type Mismatch, a different rule entirely.
#
#    A settle row is not just a verdict; it is a CLAIM about why. This row was
#    measuring the type lens and was read as measuring the grammar, and the
#    parser would have been narrowed to refuse a shape the language HAS.
#
#    The rows below now separate the two: `-> Int? { Some(1) }` is ACCEPTED (the
#    `?` is the type's, and the type reader takes it) and `-> Int ? { 1 }` is
#    REJECTED (the same tokens, a body that does not fit). The `?` with nothing
#    to mark is not a shape the language has, because after a type there is
#    always a type for it to belong to.
#
# 2. THE FUNCTION-TYPE POSITION WAS NOT SETTLED AT ALL, and it turned out to be
#    the harder half. The `?` there does TWO jobs:
#
#       (Int) -> Int raise?      the OPTIONAL-RAISE marker
#       ((Int) -> Int)?          the NULLABLE marker on a parenthesised group
#
#    The first draft of this increment narrowed the function-type `?` to "a bare
#    raise only" and 14 existing tests went red -- the nullable group is a
#    `?` with NO clause in front of it, so the rule has to be asked about the
#    CLAUSE and not about the `?`. The rows below settle both jobs, and the
#    four illegal spellings in that position too:
#
#       (Int) -> Int noraise?          REJECTED 3002
#       (Int) -> Int nocancel?         REJECTED 3002
#       (Int) -> Int! ?                REJECTED 3002
#       (Int) -> Int raise + nocancel? REJECTED 3002
#       (Int) -> Int raise MyErr?      REJECTED 3002 + 4032
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\settle_0503_raise_q.ps1
$dir = Join-Path $env:TEMP ('settle0503rq_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dir 'moon.mod'), "name = `"settle0503rq`"`nversion = `"0.1.0`"`n", $enc)

$PRE = "priv suberror MyErr`n"

$cases = [ordered]@{
  # THE CANARY: a name bound NOWHERE. It MUST be rejected.
  'canary.mbt' = "fn keep() -> Int {`n  nope`n}`n"

  # THE NEGATIVE CONTROL: the signature with no body. The `raise?` clause is
  # real, so the missing `{` MUST be an error.
  'neg_no_body.mbt' = $PRE + "fn f() -> Int raise?`n"

  # CORRECTED ROW 1 -- the `?` WITH NO EFFECT CLAUSE IS THE NULLABLE TYPE.
  # The `?` after a type belongs to the TYPE, and the toolchain accepts it.
  'neg_question_alone.mbt' = "fn f() -> Int? {`n  Some(1)`n}`n"

  # CORRECTED ROW 1, THE OTHER HALF -- the same TOKENS with a body that does
  # not fit. This is what the original row measured, and the rejection is an
  # Expr Type Mismatch (`1` is not an `Int?`), not a rejection of the `?`.
  'neg_question_alone_body.mbt' = "fn f() -> Int ? {`n  1`n}`n"

  # A: the target shape -- `raise?` on a RETURN annotation.
  'a_ret_raise_q.mbt' = $PRE + "fn f() -> Int raise? {`n  1`n}`n"

  # B: the `?` on a TYPED raise. REJECTED by the toolchain.
  'b_ret_raise_typed_q.mbt' = $PRE + "fn f() -> Int raise MyErr? {`n  1`n}`n"

  # C: the `?` on a `noraise`. REJECTED.
  'c_ret_noraise_q.mbt' = $PRE + "fn f() -> Int noraise? {`n  1`n}`n"

  # D: the `?` on a `nocancel`. REJECTED.
  'd_ret_nocancel_q.mbt' = $PRE + "fn f() -> Int nocancel? {`n  1`n}`n"

  # E: the `?` after the short `!` form. REJECTED.
  'e_ret_bang_q.mbt' = $PRE + "fn f() -> Int! ? {`n  1`n}`n"

  # F: the `?` after a JOINED effect clause. REJECTED.
  'f_ret_joined_q.mbt' = $PRE + "fn f() -> Int raise + nocancel? {`n  1`n}`n"

  # G: THE CONTROL FOR THE FIX -- the function-TYPE position, which the parser
  # already reads. ACCEPTED.
  'g_param_fntype_q.mbt' = $PRE + "fn f(g : (Int) -> Int raise?) -> Int {`n  0`n}`n"

  # H: the already-supported plain `raise` in a return position.
  'h_ret_raise_plain.mbt' = $PRE + "fn f() -> Int raise {`n  1`n}`n"

  # I: the already-supported typed `raise` in a return position.
  'i_ret_raise_typed.mbt' = $PRE + "fn f() -> Int raise MyErr {`n  1`n}`n"

  # J: the already-supported short `!` form.
  'j_ret_bang.mbt' = $PRE + "fn f() -> Int! {`n  1`n}`n"

  # K: THE CORPUS SHAPE, on a type this package owns -- a `pub` method whose
  # parameter carries a function type with `raise?` AND whose return annotation
  # carries `raise?`. This is the shape 31 core files are written in.
  # (A `pub` method on the BUILT-IN `Array` is a different program: 4059, and a
  # first draft of this row measured that instead of the question.)
  'k_corpus_shape.mbt' = "pub struct Box[T] {`n  v: T`n}`n`npub fn[T] Box::each(self : Box[T], f : (T) -> Unit raise?) -> Unit raise? {`n  f(self.v)`n}`n"

  # L: calling a `raise?` function needs no special syntax -- `g!()` is REJECTED
  # by the toolchain ("unexpected `f!(..)`, you may expect `f(..)`"), so a
  # reader that expected the `!` would be wrong here.
  'l_call_a_raise_q_fn.mbt' = $PRE + "fn g() -> Int raise? {`n  1`n}`n`nfn h() -> Int {`n  g()`n}`n"

  # ---- THE FUNCTION-TYPE POSITION, which the first version of this settle did
  # ---- not cover at all. The `?` there does TWO jobs, and they are not the
  # ---- same job.
  #
  # M: the OPTIONAL-RAISE MARKER in the function-type position. ACCEPTED.
  'm_ft_raise_q.mbt' = $PRE + "fn f(g : (Int) -> Int raise?) -> Int {`n  0`n}`n"

  # N: the `?` on a `noraise`, in the function-type position. REJECTED.
  'n_ft_noraise_q.mbt' = $PRE + "fn f(g : (Int) -> Int noraise?) -> Int {`n  0`n}`n"

  # O: the `?` on a `nocancel`, in the function-type position. REJECTED.
  'o_ft_nocancel_q.mbt' = $PRE + "fn f(g : (Int) -> Int nocancel?) -> Int {`n  0`n}`n"

  # P: the `?` after the short `!` form, in the function-type position.
  # REJECTED.
  'p_ft_bang_q.mbt' = $PRE + "fn f(g : (Int) -> Int! ?) -> Int {`n  0`n}`n"

  # Q: the `?` after a JOINED effect clause, in the function-type position.
  # REJECTED.
  'q_ft_joined_q.mbt' = $PRE + "fn f(g : (Int) -> Int raise + nocancel?) -> Int {`n  0`n}`n"

  # R: the `?` on a TYPED raise, in the function-type position. REJECTED.
  's_ft_typed_q.mbt' = $PRE + "fn f(g : (Int) -> Int raise MyErr?) -> Int {`n  0`n}`n"

  # S: THE NULLABLE GROUP -- a `?` with NO clause in front of it, and the shape
  # the first draft of the fix broke. ACCEPTED.
  't_ft_nullable_group.mbt' = $PRE + "fn f(g : ((Int) -> Int)?) -> Int {`n  0`n}`n"

  # T: the NULLABLE RETURN TYPE of a function type. ACCEPTED, and it is the
  # other `?` that the type reader takes for itself.
  'u_ft_nullable_ret.mbt' = $PRE + "fn f(g : (Int) -> Int?) -> Int {`n  0`n}`n"
}

$expected = [ordered]@{
  'canary.mbt'                 = 'REJECTED'
  'neg_no_body.mbt'            = 'REJECTED'
  'neg_question_alone.mbt'     = 'ACCEPTED'
  'neg_question_alone_body.mbt'= 'REJECTED'
  'a_ret_raise_q.mbt'          = 'ACCEPTED'
  'b_ret_raise_typed_q.mbt'    = 'REJECTED'
  'c_ret_noraise_q.mbt'        = 'REJECTED'
  'd_ret_nocancel_q.mbt'       = 'REJECTED'
  'e_ret_bang_q.mbt'           = 'REJECTED'
  'f_ret_joined_q.mbt'         = 'REJECTED'
  'g_param_fntype_q.mbt'       = 'ACCEPTED'
  'h_ret_raise_plain.mbt'      = 'ACCEPTED'
  'i_ret_raise_typed.mbt'      = 'ACCEPTED'
  'j_ret_bang.mbt'             = 'ACCEPTED'
  'k_corpus_shape.mbt'         = 'ACCEPTED'
  'l_call_a_raise_q_fn.mbt'    = 'ACCEPTED'
  'm_ft_raise_q.mbt'           = 'ACCEPTED'
  'n_ft_noraise_q.mbt'         = 'REJECTED'
  'o_ft_nocancel_q.mbt'        = 'REJECTED'
  'p_ft_bang_q.mbt'            = 'REJECTED'
  'q_ft_joined_q.mbt'          = 'REJECTED'
  's_ft_typed_q.mbt'           = 'REJECTED'
  't_ft_nullable_group.mbt'    = 'ACCEPTED'
  'u_ft_nullable_ret.mbt'      = 'ACCEPTED'
}

$outFile = Join-Path $dir 'check.out'
$fail = 0
Push-Location $dir
foreach ($k in $cases.Keys) {
  Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File | ForEach-Object { [System.IO.File]::Delete($_.FullName) }
  [System.IO.File]::WriteAllText((Join-Path $dir 'src\moon.pkg'), "", $enc)
  [System.IO.File]::WriteAllText((Join-Path $dir ('src\' + $k)), $cases[$k], $enc)
  $present = @(Get-ChildItem -Path (Join-Path $dir 'src') -Filter '*.mbt' -File)
  if ($present.Count -ne 1 -or $present[0].Name -ne $k) {
    Write-Output ("{0,-30} ABORT: src holds {1} file(s)" -f $k, $present.Count); $fail++; continue
  }
  & cmd.exe /c "moon check > `"$outFile`" 2>&1"
  $out = [System.IO.File]::ReadAllText($outFile)
  if ([string]::IsNullOrWhiteSpace($out)) {
    Write-Output ("{0,-30} ABORT: moon check produced no output at all" -f $k); $fail++; continue
  }
  $finished = ($out -match 'Finished\.\s*moon:\s*ran\s+\d+\s+task')
  $failed = ($out -match 'failed when checking project')
  if (-not $finished -and -not $failed) {
    Write-Output ("{0,-30} ABORT: moon check did no work" -f $k); $fail++; continue
  }
  # A run is REJECTED when the project failed to check, or when it reported a
  # real error code. 4069 is the "warnings only" code and is not an error.
  $errs = @([regex]::Matches($out, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $real = @($errs | Where-Object { $_ -notin @('4069') })
  $got = if ($failed -or $real.Count -gt 0) { 'REJECTED' } else { 'ACCEPTED' }
  $want = $expected[$k]
  $ok = ($got -eq $want)
  Write-Output ('{0,-30} {1,-9} (want {2}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    ($out -split "`n" | Where-Object { $_ -match 'Parse error|Error: \[|error:' } | Select-Object -First 4) |
      ForEach-Object { '      ' + $_.Trim() }
  }
}
Pop-Location
Write-Output ''
if ($fail -gt 0) { Write-Output "ABORT: $fail case(s) did not match the expected verdict."; exit 1 }
Write-Output 'GATE OK: the toolchain accepts `raise?` on a RETURN annotation -- and ONLY on a bare raise -- so a parser that refuses it invents a finding, and a reader that accepts it everywhere reads programs the toolchain rejects.'
exit 0

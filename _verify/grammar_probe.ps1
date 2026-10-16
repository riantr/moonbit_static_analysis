# Settle a MoonBit grammar question, then ask the same question of THIS frontend.
#
# WHY THIS EXISTS. This repo's parser comments repeatedly say a form was "settled
# with `moon check`". That method needs three things bolted on before its answer
# means anything, and all three have bitten this repo before:
#
#   1. A DELIBERATELY BROKEN CANARY FILE alongside the subject. A directory the
#      toolchain has nothing to do in answers "no work to do" and exits 0 -- a
#      false green indistinguishable from "the form is legal". The canary makes
#      that impossible: if the canary is not reported, the probe did not run.
#   2. ITS OWN PACKAGE PER CASE. One case's build-plan failure otherwise masks
#      every other case, which reads as "all forms are illegal".
#   3. `moon check` IS NOT ENOUGH. It answers "is this legal MoonBit". The
#      question that matters is a PAIR: legal to the toolchain AND read by this
#      frontend. A form can be legal and still block 34 files here, and only the
#      second half of the pair finds that.
#
# So each case prints `MOON` (the grammar truth) beside `SELF` (what this
# analyzer does), and the interesting cells are the disagreements:
#
#   MOON-OK  SELF-OK     nothing to do
#   MOON-OK  SELF-FAIL   <- A REAL GAP: valid MoonBit this frontend cannot read
#   MOON-BAD SELF-OK     <- too permissive: this frontend reads invalid MoonBit
#   MOON-BAD SELF-FAIL   both wrong, in the harmless direction
#
# `MOON-OK SELF-FAIL` is the only cell that justifies work. `MOON-BAD SELF-OK` is
# worse and has shipped real false readings, so both are worth seeing.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\grammar_probe.ps1
#        [-Only <substring>] [-Cases <path-to-cases.ps1>] [-Keep]
param(
  [string]$Only = '',
  [string]$Cases = '',
  [switch]$Keep
)
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$wasm = Join-Path $repo '_build\wasm\debug\build\moonbit_static_analysis.wasm'
if (-not (Test-Path -LiteralPath $wasm)) { Write-Output 'ABORT: build first -- moon build --target wasm'; exit 1 }

# --- the cases -------------------------------------------------------------
# Sourced from a separate file when given, so a caller can sweep a family of
# forms without editing this script. Default: the forms this repo has an open
# question about.
if (-not [string]::IsNullOrEmpty($Cases)) {
  . $Cases
} else {
  $PROBE_CASES = [ordered]@{
    # --- `match` with its subject on the FOLLOWING line -------------------
    'match_subject_next_line_stmt' = "fn sub(x : Int) -> Int { x }`nfn caller(c : Int) -> Int {`n  let acc : Array[Int] = []`n  match`n    sub(c) {`n    1 => acc.push(2)`n    _ => acc.push(3)`n  }`n  acc.length()`n}"
    'match_subject_next_line_let'  = "fn sub(x : Int) -> Int { x }`nfn caller(c : Int) -> Int {`n  let v = match`n    sub(c) {`n    1 => 2`n    _ => 3`n  }`n  v`n}"
    'match_one_line_control'       = "fn sub(x : Int) -> Int { x }`nfn caller(c : Int) -> Int {`n  match sub(c) {`n    1 => 2`n    _ => 3`n  }`n}"
    # The spelling the parser comment says the TOOLCHAIN rejects. Recorded
    # because the comment asserts it: an assertion in prose that no case
    # exercises is the same defect the 0.4.30 doc audit found. MOON-BAD here is
    # the point; SELF-OK would mean this frontend is too permissive about it.
    'match_brace_on_its_own_line'  = "fn sub(x : Int) -> Int { x }`nfn caller(c : Int) -> Int {`n  match`n    sub(c)`n  {`n    1 => 2`n    _ => 3`n  }`n}"
    # --- the `?` optional-argument shorthand -----------------------------
    'optarg_question'              = "fn sink(theme? : Int = 0) -> Int { theme }`nfn pass(theme? : Int) -> Int { sink(theme?) }`n"
    'optarg_tilde_control'         = "fn sink(theme~ : Int = 0) -> Int { theme }`nfn pass(theme~ : Int) -> Int { sink(theme~) }`n"
    # --- a function-typed parameter with a lambda default -----------------
    'lambda_default_1line'         = "fn maker2(sync? : (Int) -> Unit = (_w) => ()) -> Int { 1 }`n"
    'lambda_default_multiline'     = "fn maker(`n  sync? : (Int, Int) -> Unit = (`n    _w,`n    _m,`n  ) => (),`n) -> Int { 1 }`n"
    'fntype_param_no_default'      = "fn taker(cb : (Int) -> Unit) -> Int { 1 }`n"
    # --- generic index type ----------------------------------------------
    'paren_scalar_return'          = "fn f() -> (Int) { 1 }`n"
    'generic_indexed_param'        = "fn g(a : FixedArray[Int]) -> Int { a[0] }`n"
    # --- `if` as a VALUE ---------------------------------------------------
    # moui writes this as a call argument, which is the shape that blocks.
    'ifexpr_let_value'             = "fn f(c : Bool) -> Int {`n  let d = if c { 1 } else { 2 }`n  d`n}`n"
    'ifexpr_call_arg_named'        = "fn g(variant? : Int = 0, other? : Int = 0) -> Int { variant + other }`nfn f(c : Bool) -> Int {`n  g(`n    variant=if c {`n      1`n    } else {`n      2`n    },`n    other=3,`n  )`n}`n"
    'ifexpr_call_arg_positional'   = "fn g(a : Int, b : Int) -> Int { a + b }`nfn f(c : Bool) -> Int {`n  g(if c { 1 } else { 2 }, 3)`n}`n"
    'ifexpr_elseif_chain'          = "fn f(c : Bool, d : Bool) -> Int {`n  let x = if c { 1 } else if d { 2 } else { 3 }`n  x`n}`n"
    'ifexpr_ternary_like_nested'   = "fn f(c : Bool) -> Int {`n  let x = if c { if c { 1 } else { 2 } } else { 3 }`n  x`n}`n"
    # --- a method chain whose `.` starts the NEXT line after the receiver ---
    # moui writes `rows.push(\n  @button.button(...)\n  .disabled(...)\n  .other(...),\n)`.
    #
    # Typed on ARRAYS, not on a made-up `.disabled` method: an unknown method is
    # a moon check ERROR, so the first draft of these three cases came back
    # MOON-BAD for a reason that had nothing to do with the chain, and the
    # verdict would have been about type checking rather than parsing.
    'chain_dot_next_line'          = "fn wrap(x : Array[Int]) -> Array[Int] { x }`nfn take(n : Int) -> Int { n }`nfn f(a : Array[Int]) -> Int {`n  take(`n    wrap(a)`n      .length(),`n  )`n}`n"
    'chain_dot_same_line_control'  = "fn wrap(x : Array[Int]) -> Array[Int] { x }`nfn take(n : Int) -> Int { n }`nfn f(a : Array[Int]) -> Int {`n  take(wrap(a).length())`n}`n"
    'chain_dot_next_line_plain'    = "fn f(a : Array[Int]) -> Int {`n  let v = a`n    .length()`n  v`n}`n"
    # --- `defer { ... }` and `defer <expr>` as a statement --------------------
    # BOTH bodies occur. proton 0.3.4 writes `defer {` in command.mbt:145 and
    # `defer host.close()` in typed_registrar_wbtest.mbt, so an arm that assumed
    # a block produced 8x `expected '{'` across that corpus on the first try.
    'defer_block_stmt'             = "fn f() -> Unit {`n  defer {`n    g()`n  }`n  g()`n}`nfn g() -> Unit { () }`n"
    'defer_expr_stmt'              = "fn g() -> Unit { () }`nfn f() -> Unit {`n  defer g()`n  g()`n}`n"
    # A first draft of the paren case deferred a non-Unit call and came back
    # MOON-BAD -- a TYPE error wearing a syntax verdict. `defer` takes Unit, so
    # the body must produce it. Fixed rather than reported: a probe source that
    # does not type-check answers nothing about the grammar.
    'defer_paren_expr_stmt'        = "fn g(x : Int) -> Unit { ignore(x) }`nfn f() -> Unit {`n  defer (g(1))`n  g(2)`n}`n"
    'defer_block_expr_control'     = "fn g() -> Unit { () }`nfn f() -> Unit {`n  g()`n  defer {`n    g()`n  }`n}`n"
    # The two forms that DOMINATE the six corpora, measured rather than assumed:
    # 1950 `defer` lines, of which 1534 are a method call, 18 an expression
    # with a trailing `catch`, 130 a block, 268 another expression. So the
    # method-call body is the shape this arm mostly has to get right.
    #
    # The type is spelled `struct`, not `class` -- this toolchain REJECTS
    # `class Box { ... }` ("unexpected token id (lowercase start)"), and the
    # method is `fn Box::bump(self : Box, ..)`, not `fn meth(self, ..)`
    # (deprecated_syntax). The first draft used both obsolete spellings, so it
    # came back MOON-BAD for a reason that had nothing to do with `defer`, and
    # SELF-FAIL because this frontend read the one-line `class` as a struct
    # literal. Both halves of the verdict were about my probe source.
    # Settled on this toolchain: 0 errors, 3 warnings, beside the canary.
    'defer_method_call_stmt'       = "struct Box {`n  n : Int`n}`nfn Box::bump(self : Box) -> Unit { ignore(self.n) }`nfn f(b : Box) -> Unit {`n  defer b.bump()`n  b.bump()`n}`n"
    'defer_expr_catch_stmt'        = "suberror E { Boom(Int) }`nfn boom(x : Int) -> Unit raise E { raise Boom(x) }`nfn f(p : String) -> Unit raise E {`n  defer (boom(p.length()) catch { _ => () })`n  boom(0)`n}`n"
    # --- the canary. MUST be rejected; if it is not, the probe is a no-op ---
    'zz_canary_must_be_rejected'   = "fn canary( { let = 1 }`n"
  }
}

$base = Join-Path $env:TEMP ('grammar_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $base | Out-Null

Write-Output '=== grammar probe: moon check (truth) vs this frontend (behaviour) ==='
Write-Output "    (each form in its own package; per-case isolation so one build-plan failure cannot mask another)"
Write-Output ''
Write-Output ('  {0,-30} {1,-9} {2,-10} {3}' -f 'case', 'MOON', 'SELF', 'self reason / note')
Write-Output ('  {0,-30} {1,-9} {2,-10} {3}' -f ('-' * 30), ('-' * 9), ('-' * 10), ('-' * 46))

$rows = @()
foreach ($k in $PROBE_CASES.Keys) {
  # The CANARY is exempt from -Only. Filtering it out was a defect found the
  # hard way: `-Only 'defer'` printed "[NO CANARY] ... Treat every SELF-OK above
  # as unverified", i.e. the flag that makes the tool convenient silently
  # removed the one thing that makes its answer mean anything -- and every
  # filtered run before that one was unverified too. A safety net that a
  # routine flag disarms is not a safety net.
  $isCanary = $k -like 'zz_canary*'
  if (-not $isCanary -and -not [string]::IsNullOrEmpty($Only) -and $k -notlike "*$Only*") { continue }
  $d = Join-Path $base $k
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  Set-Content -LiteralPath (Join-Path $d 'moon.mod') -Value "name = `"mbprobe/$k`"`n`nversion = `"0.1.0`"`n" -NoNewline
  Set-Content -LiteralPath (Join-Path $d 'moon.pkg') -Value "supported_targets = `"+all`"`n" -NoNewline
  Set-Content -LiteralPath (Join-Path $d 'subject.mbt') -Value $PROBE_CASES[$k] -NoNewline

  Push-Location $d
  $mo = (& $moon check 2>&1 | Out-String)
  Pop-Location
  # `(?<!\d)0 errors` and NOT `0 errors`. The old pattern was unanchored, so the
  # string `10 errors` CONTAINS `0 errors` and every case whose error count was a
  # multiple of ten scored MOON-OK. Measured on this toolchain, not reasoned: a
  # fixture with ten undefined names reports `Failed with 0 warnings, 10 errors`
  # and the old test answered True -- i.e. illegal MoonBit reported as LEGAL, which
  # promotes the row into the REAL GAP tally. This is the control's own failure
  # shape, one level down: a verdict that reads clean while the opposite is true.
  #
  # The count is a plausible fixture size, not an exotic one -- 10, 20, 30 all trip
  # it -- and the tally it corrupts is the one the control exists to police. The
  # negative lookbehind costs nothing and is pinned by `moonverdict_ten_errors` in
  # `_verify/grammar_probe_control.ps1`, which fails the release gate if this line
  # is reverted. A sweep over counts 0..25 is in that control's header.
  $mv = if (($mo -replace "`r?`n", ' ') -match '(?<!\d)0 errors') { 'MOON-OK' } else { 'MOON-BAD' }

  $so = (& $moonrun $wasm $d 2>&1 | Out-String)
  $parsed = [regex]::Match($so, 'parsed=(\d+)').Groups[1].Value
  $sv = if ($parsed -eq '1') { 'SELF-OK' } else { 'SELF-FAIL' }

  $reason = ([regex]::Match($so, '(?m)^\s+\d+x\s+(.+)$').Groups[1].Value)
  if ([string]::IsNullOrWhiteSpace($reason)) { $reason = '(parsed; no blocker)' }

  Write-Output ('  {0,-30} {1,-9} {2,-10} {3}' -f $k, $mv, $sv, $reason)
  $rows += [pscustomobject]@{ Case = $k; Moon = $mv; Self = $sv; Reason = $reason }
}

# --- the canary, which decides whether any of the above means anything ------
Write-Output ''
$canary = $rows | Where-Object { $_.Case -like 'zz_canary*' }
if ($null -eq $canary) {
  Write-Output '  [NO CANARY] this run reported nothing about whether the probe executed.'
  Write-Output '  Treat every SELF-OK above as unverified and re-run with a canary.'
} elseif ($canary.Moon -eq 'MOON-BAD' -and $canary.Self -eq 'SELF-FAIL') {
  Write-Output '  canary: REJECTED by both, as it must be -- the probe is live and this run is evidence.'
} else {
  Write-Output ("  [CANARY PROBLEM] canary came out {0} -- the toolchain did NOT engage." -f $canary.Moon)
  Write-Output '  A "no work to do" run exits 0 and looks exactly like a legal form.'
  Write-Output '  Treat every MOON-OK above as unverified.'
}

# Both tallies below are wrapped in @() ON PURPOSE, and this is the second
# defect found in this file while adding a case to it.
#
# `$x | Where-Object {...}` returns a BARE PSCustomObject when exactly one row
# matches. On Windows PowerShell 5.1 a scalar PSCustomObject has NO `.Count`
# property -- `$loose.Count` is $null, `$null -gt 0` is False, and the whole
# section is skipped. Measured: a run whose table showed
#
#   match_brace_on_its_own_line    MOON-BAD  SELF-OK
#
# printed `no gaps: every form moon accepts is a form this frontend reads` and
# then NOTHING for the too-permissive tally, which is the finding.
#
# The same line guards the REAL GAP tally, so the damage is worse than a missing
# section: with exactly ONE real gap the probe announced "no gaps" -- inverting
# its headline verdict in precisely the run that had something to report. A
# guard that cannot fire is worse than no guard, because its absence reads as
# evidence. Both are now arrays, and `_verify/grammar_probe_control.ps1` proves
# each section FIRES by feeding the probe one known MOON-BAD/SELF-OK row and
# one known MOON-OK/SELF-FAIL row and asserting both tallies appear.
$gaps = @($rows | Where-Object { $_.Moon -eq 'MOON-OK' -and $_.Self -eq 'SELF-FAIL' })
Write-Output ''
if ($gaps.Count -gt 0) {
  Write-Output ("  {0} REAL GAP(S) -- legal MoonBit this frontend cannot read:" -f $gaps.Count)
  foreach ($g in $gaps) { Write-Output ("    {0,-30} {1}" -f $g.Case, $g.Reason) }
} else {
  Write-Output '  no gaps: every form moon accepts is a form this frontend reads.'
}

$loose = @($rows | Where-Object { $_.Moon -eq 'MOON-BAD' -and $_.Self -eq 'SELF-OK' })
if ($loose.Count -gt 0) {
  Write-Output ''
  Write-Output ("  {0} TOO-PERMISSIVE -- this frontend reads MoonBit the toolchain rejects:" -f $loose.Count)
  foreach ($g in $loose) { Write-Output ("    {0}" -f $g.Case) }
}

if (-not $Keep -and (Test-Path -LiteralPath $base)) { Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue }
else { Write-Output ''; Write-Output "  probe tree kept at $base" }
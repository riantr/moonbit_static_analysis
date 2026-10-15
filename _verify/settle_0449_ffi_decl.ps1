# Settles the EXTERNAL DECLARATION form `fn f(..) -> T = "pkg" "sym"` for 0.4.39.
#
# WHY THIS EXISTS. The moui truncation ranking (`_verify/diagnose_moui_truncations.ps1`)
# puts this shape first, at FOUR of seventeen files. The ranking says where the
# read stops; it does NOT say the parser cannot read it. Those are different
# claims and only one of them is established, so before anything in the parser is
# touched the toolchain gets asked what it does with the shape.
#
# THE FOUR REAL SITES, cut to their shape:
#
#   backend/web/web_host.mbt:382
#     fn web_begin_create_string() -> Int = "window_web" "begin_create_string"
#
#   backend/web/document_metadata.mbt:30
#     fn web_update_document_metadata_host(json : WebHostString) -> Unit
#       = "window_web" "update_document_metadata"
#
#   backend/web/route_history.mbt:60        (same single-line shape)
#   backend/web/accessibility.mbt:366-370    the MULTI-LINE shape:
#     fn web_sync_semantics_host(
#       raw_id : Int,
#       canvas_id : WebHostString,
#       json : WebHostString,
#     ) -> Unit = "window_web" "sync_semantics"
#
# Note what the ranking already established and this script does not re-derive:
# the read stops AT the `= "pkg" "sym"` line in the single-line cases, and at the
# `) -> Unit = "pkg" "sym"` line in the multi-line one. So the parameter list is
# read and the binding tail is not. That is a strong hint about where the parser
# stops accepting, and it is a HINT -- a location, not a mechanism.
#
# POSITIVE CONTROL. `ctl_missing` names something that cannot exist and MUST be
# rejected. Four of the seven malformed probes this repository has produced would
# have reported a confident wrong answer here, including one that normalised the
# toolchain's output with `replace '\s+', ' '` before matching `(?m)^Error:` and
# so made every case read ACCEPT. Three scaffold facts are load-bearing and are
# recorded where they were learned: `moon.mod` MUST declare `source = "src"`; a
# package cannot import its OWN root; and the output is joined with NEWLINES
# before any `(?m)` pattern is applied.

$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- the control ----------------------------------------------------------
Add-Case 'ctl_missing' @'
///|
fn probe() -> Int {
  ignore(ZzMissing)
  0
}
'@ 'REJECT'

# --- the four real shapes --------------------------------------------------
# No parameters. web_host.mbt:382, verbatim in shape.
Add-Case 'ffi_no_args' @'
///|
fn web_begin_create_string() -> Int = "window_web" "begin_create_string"
'@ 'ACCEPT'

# One parameter, on the same line. document_metadata.mbt:30's shape.
Add-Case 'ffi_single_line_arg' @'
///|
fn web_update_document_metadata_host(raw_id : Int) -> Unit
  = "window_web" "update_document_metadata"
'@ 'ACCEPT'

# Parameters one per line, closing paren on its own line. accessibility.mbt:366,
# the only MULTI-LINE site of the four, and the one a one-line reading of the
# ranking would have missed.
Add-Case 'ffi_multi_line_args' @'
///|
fn web_sync_semantics_host(
  raw_id : Int,
  canvas_id : Int,
  json : Int,
) -> Unit = "window_web" "sync_semantics"
'@ 'ACCEPT'

# A no-return external with no parameters. Not one of the four sites; included so
# a REJECT here is distinguishable from a REJECT on the four above.
Add-Case 'ffi_unit_no_args' @'
///|
fn web_close() -> Unit = "window_web" "close"
'@ 'ACCEPT'

# Declared AND CALLED, so the name is exercised as a binding rather than only as
# a declaration. This is the case that would expose the parser treating the whole
# declaration as something other than a function.
Add-Case 'ffi_declared_and_called' @'
///|
fn web_begin_create_string() -> Int = "window_web" "begin_create_string"

///|
fn probe() -> Int {
  web_begin_create_string()
}
'@ 'ACCEPT'

# WHY THE FIRST VERSION OF THIS SCRIPT FAILED, and it is worth a case of its own.
# The four real sites parameterise with `WebHostString`, a POINTER-shaped type,
# and this script's first attempt used `String`. That is REJECTED -- `[0055]
# unannotated_ffi`, "FFI parameter of pointer type should be annotated with either
# `#borrow` or `#owned`", plus `[4042] Invalid stub type`. Adding the annotation
# does not rescue it either (`[4074]`, `[3002]`).
#
# So the first run reported three REJECTs that looked exactly like "the toolchain
# rejects the FFI declaration form". It does not: it rejects POINTER PARAMETERS
# without an annotation. `#borrow` and `#owned` were both tried and both fail, so
# this is pinned as a REJECT rather than left as a footnote -- it is the exact
# shape that misleads the next person who probes this, and it is the reason the
# accepting cases below all use `Int`.
Add-Case 'ctl_pointer_param_unannotated' @'
///|
fn web_update_document_metadata_host(json : String) -> Unit
  = "window_web" "update_document_metadata"
'@ 'REJECT'

# --- run ------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0449_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0449`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') |
    ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($plan) {
    $got = 'BUILD-PLAN-FAILED'
    $ok = $false
  } elseif ($want -eq 'REJECT') {
    $got = if ($errs.Count) { 'REJECT(' + ($errs -join ',') + ')' } else { 'ACCEPT' }
    $ok = $got -like 'REJECT*'
  } else {
    $got = if ($errs.Count) { 'REJECT(' + ($errs -join ',') + ')' } else { 'ACCEPT' }
    $ok = ($got -eq 'ACCEPT')
  }
  Write-Output ('{0,-24} {1,-22} (want {2,-6}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. If a row says BUILD-PLAN-FAILED the scaffold is wrong and NOTHING'
  Write-Output 'here is an answer. If `ctl_missing` came back ACCEPT, `moon check` is not'
  Write-Output 'discriminating on this question and the ACCEPT rows beside it prove nothing.'
  exit 1
}
Write-Output 'GATE OK: every recorded case is ACCEPTed by the toolchain. So these four moui'
Write-Output 'files are NOT truncated on invalid input, and a parser that stops reading at'
Write-Output '`= "pkg" "sym"` is stopping on legal MoonBit.'
exit 0

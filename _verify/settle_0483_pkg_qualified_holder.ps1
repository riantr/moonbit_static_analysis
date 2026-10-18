# Settle 0483 -- a PACKAGE-QUALIFIED METHOD HOLDER in a function declaration.
#
# WHY. After 0482 async stands at 403/419 and its sixteen unreadable files have NINE distinct
# first blockers. Ranking by the scanner's GROUPED message tally would have been the 0472
# mistake again -- that tally covers several constructs under one string. Ranking by what is
# actually ON each file's boundary line gives SEVEN distinct constructs in sixteen files,
# each measured against this analyzer's own parser:
#
#     fn @pkg.T::m(...)             transport.mbt:36, http/parser.mbt:440,
#                                   redirect.mbt:156         first_error 2  <- this settle
#     guard x is { "k": v, .. }     xargs/main.mbt:49, curl/main.mbt:53
#                                                          first_error 3
#     fn &Data::binary              io/data.mbt:77           first_error 4
#     `=~`                          http/request.mbt:59      first_error 3
#     `let { identity, .. }`        fs/watch_kqueue.mbt:240  first_error 3
#     `logger <+` on the next line  socket/addr_utils.mbt:297 first_error 4
#     `noraise + nocancel`          coroutine.mbt:100        first_error 2
#
# Three files is the largest measured cluster that is also precisely isolated, so it is this
# one. The others are listed so the next increment starts from numbers instead of re-deriving
# them -- the 0472 lesson was that a ranking which comes out of a report's LAYOUT rather than
# out of the files is a ranking of the report.
#
# THE BOUNDARY LINE NAMED TWO CONSTRUCTS AND ONLY ONE OF THEM IS BROKEN. All three files stop on
#
#     fn @io.ReaderBuffer::repr(buf : Self) -> @io_buffer.Buffer = "%identity"
#
# which reads like a foreign-function body -- a `= "string"` where a `{ }` would go. It is not.
# A nine-case probe against this analyzer's own parser, not inference:
#
#     fn Buf::repr(b : Buf) -> Int = "%identity"       first_error = 0   <- already works
#     fn Buf::repr(b : Buf) -> Int { 1 }               first_error = 0
#     extern "C" fn exit(code : Int) = "exit"          first_error = 0
#     type @pkg.Buf                                   first_error = 0   <- @pkg is fine
#     fn @pkg.Buf::repr(b : Buf) -> Int = "%identity"  first_error = 2   <- HERE
#     fn @pkg.Buf::repr(b : Buf) -> Int { 1 }          first_error = 2
#     fn @pkg.Buf::repr(b : Buf)                       first_error = 2
#     extern "C" fn @pkg.Buf::repr(...) = "x"          first_error = 2
#
# The body form is IRRELEVANT and the `@pkg.` prefix is decisive. Had this been settled by
# reading the boundary line -- which is what the last two increments did and got away with --
# the fix would have been an extern-body production for a body the parser already reads in every
# other spelling. `gzip/decoder.mbt:19` carries the identical line and is NOT blocked, which is
# the fifth piece of evidence: it is not in the scanned source set at all (platform gated), so
# "this file parses" could never have settled it either way.
#
# *** THE SCAFFOLD IS TWO PACKAGES AND IT COST THREE DRAFTS TO GET RIGHT. *** Kept here because
# the next settle that needs a qualified name will hit the same three walls:
#
#   1. `Buf` with no definition, and `@builtin.Int` which does not exist. Every row REJECTed --
#      4024 unknown package, 4032 "the type ... is undefined" -- and THREE CONTROLS WENT RED.
#      `moon check` reports undefined names BEFORE it reports anything about declarations, so
#      an unresolvable name looks exactly like a rejected grammar. This is the `src/moon.pkg`
#      lesson one level up: a scaffold that does not compile makes every row, including a
#      REJECT control, agree for the wrong reason.
#   2. `import "other"` written at the top of main.mbt. The toolchain said where it belongs:
#      `import { "path/to/package" } ... in moon.pkg`.
#   3. `src/other/` with a .mbt file and NO `moon.pkg` of its own. That directory is not a
#      package, so every row came back "Cannot find import 'other' in s0483@0.1.0" or "Package
#      'other' not found in the loaded packages". A DIRECTORY NEEDS ITS OWN moon.pkg.
#
# And the import PATH is `<module>/<dir relative to source>` -- `s0483/other`, NOT
# `s0483/src/other`. The root package of this repository imports `".../src/sa"` because it lives
# OUTSIDE the source directory, which is the one case where the prefix appears; copying that
# shape into a fixture is how draft 4 got "Cannot find import".
#
# Every row writes BOTH `src/moon.pkg` and `src/other/moon.pkg`, and `ctl_must_reject` proves
# the INSTRUMENT can fail. "no work to do" is matched by NAME rather than inferred from a zero
# exit code, because with this layout that is what a missing package marker produces.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# THE SECOND PACKAGE. `src/other` plus its own `moon.pkg` makes it package `other`, so
# `@other.Buf` is the same shape as async's `@io.ReaderBuffer` and `@fs.CreateMode`. A fixture
# cannot invent a name the toolchain does not know, and the only way to have a REAL qualified
# name is to make a real package.
$OTHER = @'
struct Buf {
  x : Int
}
'@

# --- CONTROLS. Gated. ---------------------------------------------------------

# THE CONTROL, and the row the whole diagnosis rests on: the SAME declaration with an
# UNQUALIFIED holder, and a locally defined type so nothing has to resolve across a package
# boundary. This analyzer already reads it, and C1 is the same line with `@other.` in front --
# so the pair is a single-token A/B. If the control ever goes red the defect moved rather than
# grew, and the fix above it is aimed at the wrong place.
Add-Case 'ctl_unqualified_holder' @'
///|
struct Buf {
  x : Int
}

fn Buf::repr(b : Buf) -> Int = "%identity"
'@ 'ACCEPT'

# AND THE OTHER CONTROL: an ordinary function body, because the argument being tested is that a
# foreign-function BODY is not what is unread. A reader that took that claim on faith from the
# boundary line would have built the wrong production and passed C1 as well.
Add-Case 'ctl_plain_body' @'
///|
fn f(x : Int) -> Int {
  x + 1
}
'@ 'ACCEPT'

# ctl_must_reject proves the INSTRUMENT can fail. Every other gated row here wants ACCEPT, so
# a compiler that is not running looks exactly like a compiler that approves the corpus.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# --- C1  THE CORPUS SHAPE ------------------------------------------------------
# transport.mbt:36, http/parser.mbt:440 and redirect.mbt:156. Ctl_unqualified_holder is this
# row without the `@other.` prefix, so the pair says the prefix is the whole difference.
Add-Case 'C1_pkg_holder_foreign_body' @'
///|
fn @other.Buf::repr(b : @other.Buf) -> Int = "%identity"

fn use_it(b : @other.Buf) -> Int {
  b.repr()
}
'@ 'ACCEPT'

# --- C2  THE BODY IS NOT THE POINT ---------------------------------------------
# The same declaration with an ordinary brace body. This is the row that makes C1 mean what it
# says: if the `= "string"` were the defect, C2 would ACCEPT for a reason that has nothing to do
# with it, and a reader could believe the extern-body story and pass both rows.
#
# NO PARAMETER AND NO FIELD ACCESS. The first draft read `b.x`, which REJECTs 4028 -- "has type
# @s0483/other.Buf, which is an abstract type and not a struct" -- because a cross-package type
# has no visible FIELDS without a generated `.mbti`. That is a fixture fault about field
# visibility wearing the costume of a grammar refusal, and it is worth naming because a
# parameterless declaration still tests the whole question: qualified holder, brace body.
Add-Case 'C2_pkg_holder_brace_body' @'
///|
fn @other.Buf::zero() -> Int {
  0
}
'@ 'ACCEPT'

# --- C3  THE LABELLED-PARAMETER SPELLING -----------------------------------------
# `redirect.mbt:156` is `fn @fs.CreateMode::to_int(self : @fs.CreateMode) -> Int`, and the
# other two are `self : Self` -- a LABELLED parameter, which is a different token path from the
# bare `b : @other.Buf` in C1 and C2. Gated rather than recorded: it is the shape the corpus
# writes at two of its three sites, so a settle that skipped it would leave the corpus variant
# unsettled.
Add-Case 'C3_labelled_self' @'
///|
fn @other.Buf::to_int(self : @other.Buf) -> Int = "%identity"

fn call_it(b : @other.Buf) -> Int {
  b.to_int()
}
'@ 'ACCEPT'

# --- RECORDED. Read the column, do not gate on it. ----------------------------

# `pub` IS NOT PART OF THIS GRAMMAR, and the toolchain says so in one line:
#
#     pub fn @other.Buf::to_int(self : @other.Buf) -> Int = "%identity"
#     4059  Cannot define method to_int for foreign type @s0483/other.Buf
#
# All three corpus sites are non-pub `fn`, so this row asks a question the corpus never asked,
# and its answer is a REFUSAL. Recorded rather than gated, because an analyzer that ACCEPTs this
# is more permissive than the compiler on a program nobody writes -- the same direction as the
# `for let` and one-line-header gaps, and worth naming as a category rather than as three
# unrelated footnotes. It also explains why `pub` did not appear in the nine-case probe: it is
# not a legal spelling here, so it is not a variant of the construct at all.
Add-Case 'record_pub_qualified_holder' @'
///|
pub fn @other.Buf::to_int(self : @other.Buf) -> Int = "%identity"
'@ 'RECORD'

# Whether the `extern` spelling composes with the qualified holder. This analyzer reads
# `extern "C" fn f(...) = "..."` and does NOT read the qualified holder, so until something says
# they are one they are two gaps; this row says what the TOOLCHAIN does, which is the half the
# analyzer cannot answer about itself.
Add-Case 'record_extern_and_qualified_holder' @'
///|
extern "C" fn @other.Buf::triple(b : @other.Buf) -> Int = "triple"
'@ 'RECORD'

# Whether an `async` qualified holder is legal -- nothing in the corpus writes one, and an
# increment that fixed only the synchronous spelling would leave this open with no row at all.
Add-Case 'record_async_pkg_holder' @'
///|
async fn @other.Buf::fetch(b : @other.Buf) -> @other.Buf = "%identity"
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0483_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src\other') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0483`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # REQUIRED, BOTH OF THEM. The package under test needs one or `moon check` prints "no work to
  # do" and exits 0 -- which every ACCEPT row would read as a pass. And `src/other` needs its
  # OWN marker or the directory is not a package at all and the qualified rows fail with
  # "Package 'other' not found in the loaded packages".
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), 'import { "s0483/other" }', $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\other\moon.pkg'), '', $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\other\buf.mbt'), $OTHER, $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $noop = $joined -match 'no work to do'
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import|not found in the loaded packages'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($noop) {
    $got = 'MOON-DID-NOT-RUN'; $ok = $false
  } elseif ($plan) {
    $got = 'BUILD-PLAN-FAILED'; $ok = $false
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'RECORD') { $ok = $true }
    elseif ($want -eq 'ACCEPT') { $ok = $false }
    else { $ok = $got -like 'REJECT*' }
  } else {
    $got = 'ACCEPT'
    if ($want -eq 'RECORD') { $ok = $true } else { $ok = ($want -eq 'ACCEPT') }
  }
  Write-Output ('{0,-38} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|other\\|expected|wanted|has type|undefined|declared|unknown|Unexpected|unexpected' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All three controls must behave.'
  Write-Output 'A flipped CLAIM means the analyzer change is aimed at something the toolchain refuses.'
  Write-Output 'A red CONTROL means the fixture does not compile -- that is a scaffold fault, and every'
  Write-Output 'row is then agreeing for the wrong reason. See the header: three of those are listed.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

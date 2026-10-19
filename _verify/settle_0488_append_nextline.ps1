# Settle 0488 -- `<+` across a newline, and the `$|...` interpolant as an operand.
#
# WHY, AND THE RANKING WAS RE-DERIVED FROM THE SCANNER FIRST. The list carried between increments
# had been wrong three separate ways, so async 0.22.4 was re-scanned and every file's BOUNDARY line
# read directly. Six files are unread; this is what is actually AT each boundary:
#
#   src/http/utils.mbt:23          for-header with a NON-EMPTY update clause
#   examples/http_file_server/main.mbt:24   `conn <+` , operand on the NEXT line      <- reads ZERO
#   src/http/request.mbt:59        `host =~ (re"^" + ...)`  regex literals, multi-line
#   src/fs/watch_kqueue.mbt:240     `let { identity, .. } = self.watched[fd]`
#   src/socket/addr_utils.mbt:297   `logger <+` , operand on the NEXT line
#   src/fs/watch_windows.mbt:320    `for i in path.length()>..0` and `break path[:i]`
#
# Ranked by MEASURED REACH rather than by depth, this construct wins: `<+` with a next-line operand
# blocks TWO files, and one of them reads ZERO lines. And `addr_utils.mbt:297` is a SECOND SITE for
# the same construct that the carried list never named -- the same "named the construct, under-counted
# the sites" failure as 0486, on the other half of that settle.
#
# ALREADY SETTLED BY 0486 (re-run and confirmed, not re-derived):
#   ACCEPT   `sb <+ "x"`                  on one line -- this reader already handles it
#   ACCEPT   `sb <+` NEWLINE `"x"`        <- the next-line operand IS legal MoonBit
#   ACCEPT   `sb <+ $|<html>`             <- the interpolant IS a legal operand, on ONE line
#   ACCEPT   `sb <+` NEWLINE `$|<a>` `$|</a>`
#
# *** THE QUESTION THIS SETTLE EXISTS TO ANSWER *** Our reader measured `a\n + b` at first_error 3,
# so binary operators do not continue across a newline in this reader -- while `.` chains DO, from
# the 0432 fix. Two possibilities, and they are opposite in direction:
#
#   (a) the TOOLCHAIN accepts `a` NEWLINE `+ b`, so the reader is missing newline continuation for
#       ordinary operators too and the fix should be general;
#   (b) the toolchain REFUSES it, and `<+` is a special grammar form that happens to permit the
#       break -- in which case a general newline-continuation rule would make this reader accept
#       programs the compiler rejects, the liberal direction this reader has never once taken.
#
# Nothing may be implemented until this is settled. It is the difference between a two-line fix and a
# parser-wide behaviour change.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------

Add-Case 'ctl_plain_body' @'
///|
fn f(x : Int) -> Int {
  x + 1
}
'@ 'ACCEPT'

# Proves the INSTRUMENT can fail. Every other gated row wants ACCEPT, so a compiler that is not
# running looks exactly like a compiler that approves the grammar.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# CONTROL FOR B: the `<+` on ONE LINE, which this reader already handles. If this ever goes red the
# construct moved rather than grew.
Add-Case 'ctl_append_sameline' @'
///|
fn f(sb : StringBuilder) -> Unit {
  sb <+ "x"
  ignore(sb)
}
'@ 'ACCEPT'

# CONTROL FOR B: the `.` chain across a newline, from the 0432 fix. It is the one operator known to
# continue, so it is the reference the other operators are measured against -- not against a guess.
Add-Case 'ctl_dot_chain_nextline' @'
///|
fn f(a : Array[Int]) -> Int {
  a
    .length()
}
'@ 'ACCEPT'

# --- A  THE TWO CORPUS SHAPES -------------------------------------------------

# A1 `addr_utils.mbt:297` EXACTLY: a `<+` then ONE plain double-quoted string on the next line,
# carrying `\{...}` interpolations. NOTE this one has NO `$|` at all -- so closing the next-line gap
# is a SEPARABLE defect from reading the interpolant, and one of the two files needs only this half.
#
# THE ELEMENT TYPE IS `Byte`, NOT `Int`, and that was the second bad-fixture round. The row came
# back REJECT(4015, 4015) reading "Type Int has no method to_int": the real `addr` is an IP
# address, so `addr[12]` is a `Byte`, and `Byte` is the type that HAS `to_int`. Typing the fixture
# `Array[Int]` produced two errors that had nothing to do with the construct under test -- which is
# the shape of a fixture fault: the errors are about a name the row never mentions.
Add-Case 'A1_addr_utils_shape' @'
///|
fn f(sb : StringBuilder, addr : Array[Byte]) -> Unit {
  sb <+
    "\{addr[12].to_int()}.\{addr[13].to_int()}"
  ignore(sb)
}
'@ 'RECORD'

# A2 `http_file_server/main.mbt:24` EXACTLY: `conn <+` then several `$|...` lines. Both defects at
# once, which is why it is RECORDed -- a gated row cannot say which half failed.
Add-Case 'A2_http_file_server_shape' @'
///|
fn f(conn : StringBuilder, path : String) -> Unit {
  conn <+
    $|<!DOCTYPE html><html><head></head><body>
    $|<h1>\{path}</h1>
  ignore(conn)
}
'@ 'RECORD'

# --- B  IS NEWLINE CONTINUATION SPECIAL TO `<+`, OR GENERAL? --------------------

# B1 THE ARITHMETIC OPERATORS, one variable each. These four are the whole question. If they are
# ACCEPT then the reader is missing a general rule; if REJECT then `<+` is the special form.
Add-Case 'B1_plus_nextline' @'
///|
fn f(a : Int, b : Int) -> Int {
  a
    + b
}
'@ 'RECORD'

Add-Case 'B2_minus_nextline' @'
///|
fn f(a : Int, b : Int) -> Int {
  a
    - b
}
'@ 'RECORD'

Add-Case 'B3_star_nextline' @'
///|
fn f(a : Int, b : Int) -> Int {
  a
    * b
}
'@ 'RECORD'

Add-Case 'B4_eqeq_nextline' @'
///|
fn f(a : Int, b : Int) -> Bool {
  a
    == b
}
'@ 'RECORD'

# B5 `<+` ITSELF, which is the case the corpus actually contains. If B1..B4 are REJECT and this is
# ACCEPT, the grammar has a special form and the fix must reproduce that form rather than a general
# newline rule.
Add-Case 'B5_append_plus_nextline' @'
///|
fn f(sb : StringBuilder) -> Unit {
  sb <+
    "x"
  ignore(sb)
}
'@ 'ACCEPT'

# B6 AND THE SAME BREAK WITH A NON-`<+` OPERATOR KIND, to separate "the break" from "the operator":
# a method call on the next line is the 0432 shape, an arithmetic operator is the B1 shape, and `<+`
# is B5. Three different answers to three different questions.
Add-Case 'B6_call_nextline_not_method' @'
///|
fn f(a : Int) -> Int {
  a.abs()
}
'@ 'ACCEPT'

# --- C  IS `$|...` AN OPERAND ONLY TO `<+`, OR A GENERAL EXPRESSION? ----------

# C1 THE INTERPOLANT ALONE. If a bare `$|...` is not an expression on its own, then the reader needs
# a slot for it in exactly one place and the fix stays local; if it IS, then it belongs in the
# expression grammar and this is a bigger increment than it looks.
Add-Case 'C1_interpolant_alone' @'
///|
fn f() -> Unit {
  let x = $|<a>
  ignore(x)
}
'@ 'RECORD'

# C2 THE INTERPOLANT AS AN OPERAND OF AN ARITHMETIC OPERATOR, which separates "an operand of `<+`"
# from "an operand of anything".
Add-Case 'C2_plus_interpolant' @'
///|
fn f(a : String) -> String {
  a + $|<b>
}
'@ 'RECORD'

# C3 MULTI-LINE INTERPOLANT ALONE, so the break is separated from the interpolant kind.
Add-Case 'C3_multiline_interpolant_alone' @'
///|
fn f() -> Unit {
  let x = $|
    <a>
    $|</a>
  ignore(x)
}
'@ 'RECORD'

# C4 AN EMPTY INTERPOLANT, `$|` with nothing after it. A canary: a reader that grabs "the rest of
# the line" would accept this, and `$|` with no content is worth knowing either way.
Add-Case 'C4_empty_interpolant' @'
///|
fn f(sb : StringBuilder) -> Unit {
  sb <+ $|
  ignore(sb)
}
'@ 'RECORD'

# C5 INTERPOLATION INSIDE the interpolant, on the same line, which is what both corpus sites do.
Add-Case 'C5_interpolant_with_interpolation' @'
///|
fn f(sb : StringBuilder, name : String) -> Unit {
  sb <+ $|<h1>\{name}</h1>
  ignore(sb)
}
'@ 'ACCEPT'

# C6 AND ACROSS THE BREAK, so the two defects are pinned separately rather than only together.
Add-Case 'C6_nextline_interpolant_with_interpolation' @'
///|
fn f(sb : StringBuilder, name : String) -> Unit {
  sb <+
    $|<h1>\{name}</h1>
  ignore(sb)
}
'@ 'ACCEPT'

# --- F  THE FINDING 0488 EXPOSED, SETTLED BEFORE IT IS FIXED --------------------
#
# Reading `addr_utils.mbt` whole for the first time (the file used to stop at line 297, and a
# finding on a PARTIAL file is WITHHELD rather than reported) turned up an ACTIONABLE false positive
# at `addr_utils.mbt:291`:
#
#     291:  logger <+ "\{value.to_string(radix=16)}"
#     no visible binding for 'radix'
#
# `radix` is a LABEL, not a read: `label=value` is MoonBit's labelled-argument syntax at a call
# site, the counterpart of `label~` in a parameter declaration (which this same corpus uses at
# `http/request.mbt:56`, `protocol~ : Protocol`). Nothing named `radix` is ever bound in that
# function. `copy_interp` accumulates the identifier and then flushes it on `=`, so the LABEL is
# recorded as a READ.
#
# So the reader invents an undefined name out of a call's own syntax. Fixing it is in this
# increment rather than the next because `actionable` going 0 -> 1 would otherwise PIN a known-false
# finding as though it were correct, which is worse than the finding itself.
#
# THE `==` CARVE-OUT IS THE PART THAT IS EASY TO GET WRONG, so it is settled rather than assumed:
# `\{a == b}` must still record `a` and `b` as reads, and `\{f(x => x)}` must still record `x`.
Add-Case 'F1_labelled_arg_in_interp' @'
///|
fn f(value : Int) -> Unit {
  let s = "\{value.to_string(radix=16)}"
  ignore(s)
}
'@ 'RECORD'

Add-Case 'F2_labelled_arg_plain' @'
///|
fn f(value : Int) -> String {
  value.to_string(radix=16)
}
'@ 'RECORD'

Add-Case 'F3_equality_in_interp' @'
///|
fn f(a : Int, b : Int) -> Unit {
  let s = "\{a == b}"
  ignore(s)
}
'@ 'ACCEPT'

Add-Case 'F4_lambda_in_interp' @'
///|
fn f(xs : Array[Int]) -> Unit {
  let s = "\{xs.map(x => x + 1).length()}"
  ignore(s)
}
'@ 'ACCEPT'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0488_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  # REQUIRED. Without the `src` DIRECTORY nothing is written, `moon check` has nothing to check,
  # and every row answers ACCEPT -- which is how the first four probes of settle_0485 all read
  # ACCEPT and none of them meant anything.
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0488`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # REQUIRED, or `moon check` prints "no work to do" and exits 0 -- which every ACCEPT row would
  # read as a pass.
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), '', $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $noop = $joined -match 'no work to do'
  $missing = -not (Test-Path (Join-Path $d 'src\main.mbt'))
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($noop -or $missing) {
    $got = 'MOON-DID-NOT-RUN'; $ok = $false
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'RECORD') { $ok = $true }
    elseif ($want -eq 'ACCEPT') { $ok = $false }
    else { $ok = $got -like 'REJECT*' }
  } else {
    $got = 'ACCEPT'
    if ($want -eq 'RECORD') { $ok = $true } else { $ok = ($want -eq 'ACCEPT') }
  }
  Write-Output ('{0,-40} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  # LOAD-BEARING. A gate that cannot fail reports the same verdict whether the grammar is legal or
  # not, and printed six MISMATCH rows into a `GATE OK` in 0485 because this line was dropped.
  if (-not $ok) {
    $fail++
  }
  # VERBOSE dumps the compiler's own WORDS. The error CODE alone is not the answer: `4040` meant
  # "Array expects 1 argument(s)" in one fixture and could mean a grammar refusal in the next.
  if ($env:SETTLE_VERBOSE -eq '1' -and $errs.Count) {
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        $slice = $lines[$j..([Math]::Min($j + 9, $lines.Count - 1))]
        $slice | ForEach-Object { Write-Output ('      | ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All four controls must behave.'
  Write-Output 'A red CONTROL means the fixture does not compile -- a scaffold fault, and every row'
  Write-Output 'is then agreeing for the wrong reason.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

# Settle 0485 -- a BRACED STRUCT PATTERN in `is` position, `x is { "k": [v], .. }`.
#
# WHY. After 0484 async stands at 408/419 and three files stop on
#
#     guard matches.values is { "cmd": [cmd], .. } else { fail("no command specified") }
#     examples/xargs/main.mbt:49, examples/curl/main.mbt:53,
#     examples/tcp_server_benchmark/main.mbt:98
#
# The boundary line named two constructs AGAIN, and the second one was the expensive one. Measured
# with first_error AND UndefinedName in the SAME run, because measuring them apart is what made
# the `if` row look unaffected when it had never been measured on the axis that mattered:
#
#     caller        { "cmd": [cmd] }      { "cmd": [cmd], .. }
#     match arm     fe=0  undef=0         fe=0  undef=0      <- ALREADY CORRECT
#     guard         fe=0  undef=2         fe=2  undef=0      <- parses, binds NOTHING
#     bare `is`     fe=0  undef=2         fe=2  undef=0      <- parses, binds NOTHING
#     if            fe=2  undef=0         fe=2  undef=0
#     while         fe=2  undef=0         fe=2  undef=0
#     let destr     fe=2  undef=0         fe=2  undef=0
#
# *** TWO DISTINCT OUTCOMES, AND THE QUIET ONE IS WORTH MORE THAN THE THREE BLOCKED FILES. *** The
# `guard` and bare-expression rows PARSE. Their leftovers happen to re-read as a BLOCK, so nothing
# stops, and then the names the pattern was supposed to bind are reported as undefined -- a FALSE
# POSITIVE on code `moon check` compiles, moving no parse-coverage number in either direction.
# That is why the three files that DO stop are the smaller half of this construct.
#
# THE MECHANISM, read from source rather than inferred: `parse_is_pattern` has branches for a `(`
# tuple, a `[` array, a name head and literals -- and NO `{` BRANCH AT ALL. A brace pattern falls
# to `else { return [] }`, which CONSUMES NOTHING. The match-arm path reads arms through
# `skip_pattern`, which is a different reader and already handles `..`.
#
# THE SUBJECT TYPE IS SETTLED FIRST, and the first four probes were fixture faults: `Array` needs
# a type argument (`4040`), so a struct subject, a `Map[String, Array]` subject and an unquoted-key
# row all reported a rejection that had nothing to do with the grammar. `Json` ACCEPTs.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------

# The construct the analyzer ALREADY gets right. If this ever goes red the defect moved rather
# than grew -- the match-arm reader is the reference implementation for `..` in a braced pattern.
Add-Case 'ctl_match_arm_dotdot' @'
///|
fn f(x : Json) -> Int {
  match x {
    { "cmd": [cmd], .. } => 1
    _ => 0
  }
}
'@ 'ACCEPT'

# An `is` pattern the analyzer reads today, so the fixture's `guard ... is ... else` shape is
# proven rather than assumed.
Add-Case 'ctl_is_some_pattern' @'
///|
fn f(x : Option[Int]) -> Int {
  if x is Some(v) { v } else { 0 }
}
'@ 'ACCEPT'

# An ordinary function body.
Add-Case 'ctl_plain_body' @'
///|
fn f(x : Int) -> Int {
  x + 1
}
'@ 'ACCEPT'

# ctl_must_reject proves the INSTRUMENT can fail. Every other gated row wants ACCEPT, so a
# compiler that is not running looks exactly like a compiler that approves the corpus. This row
# is the one that catches a missing `src` directory: with no source written, every other row
# answers ACCEPT and the whole settle agrees for the wrong reason.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# --- C1  THE CORPUS SHAPE ------------------------------------------------------
Add-Case 'C1_guard_corpus_shape' @'
///|
fn f(x : Json) -> Unit {
  guard x is { "cmd": [cmd], .. } else { return }
  ignore(cmd)
}
'@ 'ACCEPT'

# --- C2  WITHOUT THE REST ------------------------------------------------------
Add-Case 'C2_no_rest' @'
///|
fn f(x : Json) -> Unit {
  guard x is { "cmd": [cmd] } else { return }
  ignore(cmd)
}
'@ 'ACCEPT'

# --- C3  THE REST ALONE --------------------------------------------------------
# `{ .. }` matches anything and binds nothing. Nothing in the corpus writes one, and an
# increment that fixed only the key-bearing spelling would leave this open with no row at all.
Add-Case 'C3_rest_alone' @'
///|
fn f(x : Json) -> Bool {
  x is { .. }
}
'@ 'ACCEPT'

# --- C4  SEVERAL KEYS, WHICH IS WHAT tcp_server_benchmark/main.mbt:98 WRITES -----
Add-Case 'C4_multi_key' @'
///|
fn f(x : Json) -> Unit {
  guard x is { "addr": [addr], "port": [port], .. } else { return }
  ignore(addr)
  ignore(port)
}
'@ 'ACCEPT'

# --- C5  A NON-ARRAY VALUE -----------------------------------------------------
# The corpus binds an element of a one-element list; this asks whether a plain value binds too.
Add-Case 'C5_plain_value' @'
///|
fn f(x : Json) -> Json {
  guard x is { "n": n, .. } else { return x }
  n
}
'@ 'ACCEPT'

# --- C6  A NESTED ARRAY PATTERN ------------------------------------------------
Add-Case 'C6_nested_array' @'
///|
fn f(x : Json) -> Unit {
  guard x is { "m": [[inner]], .. } else { return }
  ignore(inner)
}
'@ 'ACCEPT'

# --- RECORDED. Read the column, do not gate on it. ----------------------------

# An UNQUOTED key. The corpus is entirely quoted, so this row asks a question no corpus asked, and
# the answer decides whether the reader needs a key-token branch at all or only a string one.
Add-Case 'record_unquoted_key' @'
///|
fn f(x : Json) -> Int {
  guard x is { cmd: [cmd], .. } else { return 0 }
  ignore(cmd)
}
'@ 'RECORD'

# The same braced pattern in `if` position, which the probe measured as fe=2 -- a hard parse
# error rather than a silent one. If this ACCEPTs, `if` needs no separate settle and the fix is
# one reader rather than four.
Add-Case 'record_if_position' @'
///|
fn f(x : Json) -> Unit {
  if x is { "cmd": [cmd], .. } { ignore(cmd) } else { () }
}
'@ 'RECORD'

# The same in `while` position.
Add-Case 'record_while_position' @'
///|
fn f(x : Json) -> Unit {
  while x is { "cmd": [cmd], .. } {
    ()
  }
}
'@ 'RECORD'

# LET DESTRUCTURING rather than `is`. A different reader entirely, and the probe measured it at
# fe=2 -- but `let { ... } = x` has its own history in this parser (the `..base` spread, gate
# 0436 M8) and the two are easy to confuse.
Add-Case 'record_let_destructure' @'
///|
fn f(x : Json) -> Unit {
  let { "cmd": [cmd], .. } = x
  ignore(cmd)
}
'@ 'RECORD'

# The pattern in BARE EXPRESSION position, which the probe measured as fe=0 with two false
# positives -- the quiet half of the construct, and the one no corpus number can see.
Add-Case 'record_bare_is_expression' @'
///|
fn f(x : Json) -> Bool {
  let y = x is { "cmd": [cmd], .. }
  y
}
'@ 'RECORD'

# A braced pattern whose body is NOT a key/value pair. If this is accepted the reader has to cope
# with something no corpus writes.
Add-Case 'record_bare_brace_pattern' @'
///|
fn f(x : Json) -> Bool {
  x is {}
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0485_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  # REQUIRED. Without the `src` DIRECTORY nothing is written, `moon check` has nothing to check,
  # and every row answers ACCEPT -- which is how the first four probes of this settle all read
  # ACCEPT and none of them meant anything.
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0485`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-38} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  # *** THIS INCREMENT HAD THE INCREMENT-ENDING BUG AND IT WAS WORTH FINDING. *** A first draft
  # printed the row and moved straight on, never incrementing `$fail`, so a run with six MISMATCH
  # rows still ended in `GATE OK`. A settle that cannot fail is worse than no settle: it reports
  # the same verdict whether the grammar is legal or not. The abort below is load-bearing and is
  # now exercised by `ctl_must_reject` going the other way.
  if (-not $ok) {
    $fail++
  }
  # VERBOSE dumps the compiler's own WORDS for every row, gated or not. The error CODE alone is
  # not the answer: `4040` meant "Array expects 1 argument(s)" in a fixture and could have meant
  # a grammar refusal in the next one, and reading which is which off the code is how a settle
  # ends up explaining a fixture fault as a rejected grammar.
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
  Write-Output 'A red CONTROL means the fixture does not compile -- that is a scaffold fault, and every'
  Write-Output 'row is then agreeing for the wrong reason.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

# Settle 0473 -- the `for` HEADER is ONE grammar, not two: a binder-or-init head
# followed by an OPTIONAL list of up to three C-style clauses.
#
# WHY. 0472 settled two shapes and left the connection between them open. Its B1 row is
# ACCEPT:
#
#     let total = for x in xs; acc = 0 {
#       continue acc + x
#     } nobreak {
#       acc
#     }
#
# So a BINDER head followed by a C-style init clause is ordinary MoonBit. The analyzer
# cannot read it, and the reason is not a missing production but a wrong DISCRIMINATOR.
#
# `Parser::is_c_style_for` (parser.mbt:2742) decides which of the two `for` forms this is by
# scanning forward for whichever of `;` and `{` arrives FIRST at depth 0. That test is wrong
# in BOTH directions, on two corpus files that each stop at the header:
#
#   - `for prefix in prefix_list; len = 0 {`   reader.mbt:176
#     has a `;` before its `{`, so it is called C-style. `parse_c_for` then runs
#     `c_for_init` over `prefix in prefix_list`, and `c_for_init` only converts a clause of
#     the shape TName followed by TAssign. `in` is neither, so the clause is handed back to
#     `parse_stmt`, which reads `prefix` as an expression statement, leaves `in` on the
#     cursor, and the unconditional `expect(TSemi)` fails.
#
#   - `for frame = self.recv_frame_header() {`   conn.mbt:486
#     has NO `;` before its `{`, so it is called the BINDER form. `parse_for_stmt` reads
#     `frame` as a loop variable and then demands `in`, finds `=`, and reports
#     `expected 'in'`. Everything after line 486 in that file goes unread.
#
# Neither is a missing feature. Both are one boolean reading the wrong token, which is the
# same failure 0470 already had: 0470's first `c_for_init` discriminated on the RESULT SHAPE
# instead of on the TOKEN and matched nothing at all, green-barred, 857/857.
#
# => judgement: the discriminator should ask ONE question -- does the head start with a
# binder pattern followed by `in`? -- rather than "which of `;` and `{` arrives first". That
# is a token question with a bounded scan, not a scan for a delimiter anywhere in the header.
#
# What this settle does NOT decide is the ANALYZER's plan; it is here because the two have
# already disagreed in this project, and because the previous ranking of these blockers came
# out of a report's LAYOUT rather than out of the files (settle_0472:34-40).
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
#
# THE CONTROL. The three-clause C-style form. Settled by 0470 claim 1 and read by the
# current `parse_c_for` unchanged, so a failure here means the SCAFFOLD, not the grammar.
Add-Case 'ctl_c_for_three_clause' @'
///|
fn f(n : Int) -> Unit {
  for i = 0; i < n; i = i + 1 {
    ignore(i)
  }
}
'@ 'ACCEPT'

# AND THE OTHER CONTROL: the plain binder form, which the OTHER branch of `is_c_style_for`
# exists to protect. A discriminator change that breaks this trades one class of unreadable
# file for another, and a corpus number alone would not show it.
Add-Case 'ctl_binder_plain' @'
///|
fn f(xs : Array[Int]) -> Unit {
  for x in xs {
    ignore(x)
  }
}
'@ 'ACCEPT'

# --- C1: the head with a SINGLE init clause and NO semicolons. -----------------
#
# conn.mbt:486, reduced to the smallest thing that still asks the question. `is_c_style_for`
# scans for `;` before `{`, finds none, and calls this the binder form -- so this single row
# is what says whether the `expected 'in'` finding on conn.mbt is a FALSE POSITIVE or a
# correct complaint about code that does not compile.
#
# `break n + 1` also asks the second half: whether a single-clause head yields a VALUE from
# `break`, which is how conn.mbt:486-518 produces its `MessageKind`.
Add-Case 'C1_single_clause_no_semicolons' @'
///|
fn step() -> Int { 1 }

fn f() -> Int {
  let kind = for n = step() {
    break n + 1
  }
  kind
}
'@ 'ACCEPT'

# --- C2: a BINDER head followed by one C-style clause. ------------------------
#
# This is reader.mbt:176 and unix.mbt:66. Settle 0472's B1 established the same shape and it
# ACCEPTED; it is re-asked here as a GATED claim rather than inherited as a fact, because
# this increment now LOADS on it: if the answer were REJECT the whole discriminator change
# would be aimed at something the toolchain refuses, and the two would have to be separated.
Add-Case 'C2_binder_then_one_clause' @'
///|
fn f(ps : Array[String]) -> Int {
  let total = for p in ps; len = 0 {
    continue len + p.length()
  } nobreak {
    len
  }
  total
}
'@ 'ACCEPT'

# --- C3: a binder head followed by TWO clauses. ------------------------------
#
# reader.mbt:186, which is the same file as C2 and a DIFFERENT question: whether the clause
# list after a binder can carry the update clause as well as the initializer. C2 does not
# answer this, and an implementation that stopped after the first `;` would pass C2.
Add-Case 'C3_binder_then_two_clauses' @'
///|
fn f(ps : Array[String]) -> Unit {
  for p in ps; len = 0; len = len + p.length() {
    ignore(len)
  }
}
'@ 'ACCEPT'

# --- C4: TWO binders and a clause. unix.mbt:66 verbatim in shape. -------------
#
# The binder head is a LIST, and 0472 established that the INIT clause is a list. Nothing
# establishes that the two are independent, so this asks it directly: one is a comma list in
# binder position, the other a comma list in init position, and a parser that shares the
# comma handling between them will misread at least one.
Add-Case 'C4_two_binders_then_clause' @'
///|
fn f(m : Map[String, String]) -> Unit {
  for k, v in m; i = 0 {
    ignore(k)
    ignore(v)
    continue i + 1
  }
}
'@ 'ACCEPT'

# --- RECORDED. Read the column, do not gate on it. ----------------------------
#
# Whether a binder head's clause list may be EMPTY -- `for x in xs; ; { .. }` -- is a
# question this increment does not need, and predicting it would only encode a guess. It is
# recorded because the implementation has to make a decision there either way, and an
# unrecorded decision is one nobody reviews.
Add-Case 'record_binder_empty_clauses' @'
///|
fn f(xs : Array[Int]) -> Unit {
  for x in xs; ; {
    ignore(x)
  }
}
'@ 'RECORD'

# AND: whether the single-clause head of C1 may also be EMPTY, `for ; { .. }`. Same reason.
Add-Case 'record_empty_single_clause' @'
///|
fn f() -> Unit {
  for ; {
    ignore(1)
  }
}
'@ 'RECORD'

# AND, recorded because the ANALYZER ACTED ON IT: `in` is a RESERVED word, so no legal
# program can put one in a `for` header without it being the binder keyword. This is why
# `is_c_style_for` needs no second lookahead on the token before `in`. A draft required
# that token to end a pattern, to keep `for i = some.in; ..` out; this row is what says
# that input is a program the toolchain refuses, so the predicate was unreachable and was
# removed rather than kept as decoration.
Add-Case 'record_field_named_in' @'
///|
struct S { in : Int }

fn f(n : Int, s : S) -> Unit {
  for i = s.in; i < n; i = i + 1 {
    ignore(i)
  }
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0473_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0473`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-32} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. Both controls must behave.'
  Write-Output 'A flipped CLAIM means the analyzer change is aimed at something the toolchain refuses.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0

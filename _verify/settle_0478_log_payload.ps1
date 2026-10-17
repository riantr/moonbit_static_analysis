# Settle 0478 -- the `<?` PAYLOAD, a JSON object literal built on the receiver.
#
# WHY. proton 0.3.4 carries 26 sites of `<expr> <? { "key": value, .. }` across 7 files
# (facade_logging_wbtest 7, logging_wbtest 5, facade_runtime 5, facade_session 4,
# facade_updater 2, facade_bridge 2, facade_locale 1) and NO other pinned corpus carries
# one. Inside a `catch { }` group the parser already skips it -- `catch_group_has_log_payload`
# at parser.mbt:543 has done since 0.4.x -- so the open sites are ordinary statement
# position, and the four files the backlog names are blocked by exactly this.
#
# THE GRAMMAR WAS ANSWERED BY READING THE SOURCE, NOT BY PROBING, and that is the whole
# reason this file is short. `@xlog` 0.4.2 `pkg.generated.mbti` says:
#
#     pub fn error(category? : String, loc~ : SourceLoc) -> Event?
#     type Event
#     pub fn Event::write_object_begin(Self) -> Unit
#     pub fn[T : ToJson] Event::write_object_field(Self, String, T) -> Unit
#     pub fn Event::write_object_end(Self) -> Unit
#
# So `x <? { "k": v, .. }` is a JSON OBJECT LITERAL COMPILED AS METHOD CALLS ON THE
# RECEIVER: `{` is `write_object_begin`, each `"key": value` is `write_object_field`, and `}`
# is `write_object_end`. The payload is NOT an argument of the callee -- `error` takes none
# -- and `<?` is NOT sugar for a trailing positional argument. Five probes were spent
# arriving at that, and three of them "refuted" a correct hypothesis because the fixture's
# receiver was typed `Json`, which has no `write_object_begin`. The instrument was wrong
# three times in a row and the compiler was right every time.
#
# => what the reader has to do is therefore NOT "read a payload argument" but "read an
# object literal whose entries are `STRING-LITERAL : EXPR`", and the receiver's type is
# invisible to a type-blind reader. The rows below pin which of those the toolchain cares
# about and which it does not.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# The RECEIVER PRELUDE. Every row below shares it, and it is deliberately a LOCAL type that
# declares the three methods by hand rather than an import of `@xlog`, so that the settle
# does not depend on a package version. A prelude that does NOT declare them would make every
# row below fail for a reason that has nothing to do with the question, which is the failure
# mode five probes already produced once.
$PRELUDE = @'
priv struct Ev {
  id : Int
}

///|
fn Ev::write_object_begin(self : Ev) -> Unit {
  ignore(self.id)
}

///|
fn Ev::write_object_end(self : Ev) -> Unit {
  ignore(self.id)
}

///|
fn[T : ToJson] Ev::write_object_field(self : Ev, k : String, v : T) -> Unit {
  ignore(self.id)
  ignore(k)
  ignore(v)
}

///|
fn emit() -> Ev? {
  Some({ id: 1 })
}

///|
fn go(d : Int) -> Unit {
'@

# --- CONTROLS. Gated. ---------------------------------------------------------
# ctl_no_payload is the shape the reader already handles, and it is here so that a settle
# which measures its own prelude still has a row that must not move.
Add-Case 'ctl_no_payload' ($PRELUDE + @'
  ignore(d)
  ignore(emit())
  ()
}
'@) 'ACCEPT'

# ctl_corpus_shape IS THE CORPUS LINE, with `@xlog.error(category="proton.command")`
# replaced by `emit()` -- the same receiver type and the same payload spelling, which is the
# only part of the syntax the parser can see. If this rejects, the prelude is wrong and every
# row below would be measuring a broken build.
Add-Case 'ctl_corpus_shape' ($PRELUDE + @'
  emit() <? { "message": "m", "detail": d }
  ()
}
'@) 'ACCEPT'

# --- S1  AN EXPRESSION AS THE VALUE -------------------------------------------
#
# `facade_bridge.mbt:11` writes `{ "message": "command dispatch failed", "detail": detail }`
# where `detail` is a lambda PARAMETER. The first draft of this file used a string literal
# for both values, which would have made "the value is an expression" untested -- and that is
# the property the reader actually needs, because a name read as a literal is never resolved.
Add-Case 'S1_expression_value' ($PRELUDE + @'
  emit() <? { "message": "m", "detail": d }
  ()
}
'@) 'ACCEPT'

# --- S2  A NON-LITERAL KEY ----------------------------------------------------
#
# `write_object_field` takes `String`, so an identifier key has to resolve to a String. The
# corpus only ever writes string-literal keys, so nothing in it will ever ask this, and the
# reader must not be built on a guess either way. RECORDED.
Add-Case 'S2_non_literal_key' ($PRELUDE + @'
  let k = "message"
  emit() <? { k: "m", "detail": d }
  ()
}
'@) 'RECORD'

# --- S3  A TRAILING COMMA IN THE PAYLOAD --------------------------------------
#
# Struct fields refuse one (`Expecting a newline or ';' here, but encountered ','`, 3800 --
# which is how three earlier preludes of mine were wrong). Whether a JSON object literal
# shares that rule is not visible in the corpus: all 26 sites have no trailing comma. A
# reader that refuses one would block no corpus file today and a reader that accepts one
# would be guessing. RECORDED, and it is the row most likely to become a KNOWN LIMIT rather
# than coverage.
Add-Case 'S3_trailing_comma' ($PRELUDE + @'
  emit() <? { "message": "m", "detail": d, }
  ()
}
'@) 'RECORD'

# --- S4  TWO PAYLOADS CHAINED -------------------------------------------------
#
# `emit() <? { .. } <? { .. }` would be two `write_object_begin` calls on one receiver, and
# whether that is legal decides whether the reader's `<?` arm is a LOOP or a single
# consumption. A reader written as a single consumption would leave the second `{` in the
# token stream and the statement after it would be read as code -- the same shape as the
# 0460 array-pattern failure. RECORDED because only the toolchain can say.
Add-Case 'S4_two_payloads' ($PRELUDE + @'
  emit() <? { "message": "m" } <? { "detail": d }
  ()
}
'@) 'RECORD'

# --- S5  AN EMPTY PAYLOAD -----------------------------------------------------
#
# `{ }` would be `write_object_begin` then `write_object_end` with no field between. The
# corpus writes at least one entry in all 26 sites, so this is a boundary the corpus never
# reaches, and a reader that special-cases it would be adding an unmeasured branch.
Add-Case 'S5_empty_payload' ($PRELUDE + @'
  emit() <? { }
  ()
}
'@) 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0478_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0478`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # `ToJson` comes from core/json, and the IMPORT BELONGS IN moon.pkg. Three probes were
  # lost to putting it in main.mbt, which the toolchain reports as 3001 "Invalid import
  # declaration here. Move this declaration to `moon.pkg`." followed by a cascade that looks
  # exactly like a refuted hypothesis.
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "import { `"moonbitlang/core/json`" }`n", $enc)
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
  Write-Output ('{0,-42} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown|Unknown|╰── ' }) |
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

# --- WHAT THE ROWS ANSWERED ------------------------------------------------------
#
# Read off the run above, GATE OK, 2 controls + 5 rows:
#
#   ACCEPT    ctl_no_payload         the prelude is sound and `<?` is not ambient
#   ACCEPT    ctl_corpus_shape       the corpus line, with `emit() -> Ev?` as the receiver
#   ACCEPT    S1_expression_value    a value may be an EXPRESSION (`"detail": detail`), which
#                                    is what facade_bridge.mbt:11 does and what a reader must
#                                    get right -- a value read as a literal never resolves
#   REJECT(3002)  S2_non_literal_key  the KEY must be a string literal
#   ACCEPT    S3_trailing_comma      a trailing comma is ALLOWED here, unlike a struct field
#                                    where it is 3800. Same `,`, two grammars.
#   REJECT(3002, 3002)  S4_two_payloads  AT MOST ONE payload; chaining is a parse error
#   ACCEPT    S5_empty_payload       `<? { }` is legal -- begin with no field between
#
# THE RECEIVER CONTRACT IS THE PART THAT COST SEVEN PRELUDES, and it is now measured rather
# than assumed: `<?` applies to an OPTIONAL. `emit() -> Ev` gives `has type _/0?, wanted Ev`
# at the method DEFINITIONS -- the compiler never resolved the receiver -- while
# `emit() -> Ev?` ACCEPTS. That is the whole reason `@xlog.error` works: it returns
# `Event?`, and `<?` is the syntax for filling that event's fields on the optional. An earlier
# version returned a bare struct literal from an `Ev?` function and got 4028, "variant type
# and not a struct" -- which was the compiler naming the missing `Some(...)`, not a new rule.
#
# => WHAT THE READER MUST DO. A `<?` after an expression: expect `{`, then a comma-separated
# list of `STRING-LITERAL : EXPRESSION`, then `}`, then stop. It is NOT a loop (S4), it is NOT
# a trailing-argument sugar (4080 in the 0477-era probe), and the value after each `:` is a
# real expression whose names must resolve. The receiver's optionality is a TYPE question and
# is invisible to a type-blind reader, so the reader must accept the postfix whatever the
# expression's type turns out to be.
#
# => A HARNESS GAP THIS FILE EXPOSED, and it is worth more than any single row. A `RECORD` row
# passes on ANY verdict, so all four RECORD rows above read `OK` while `ctl_corpus_shape` was
# still failing for a reason that had nothing to do with any of them. A settle can therefore
# look almost entirely green while measuring nothing, if the rows that would have complained
# are RECORD rows. ONLY AN ACCEPT CONTROL CAN DETECT A BROKEN PRELUDE, and this file needed
# two of them to find two distinct faults in its own scaffold.

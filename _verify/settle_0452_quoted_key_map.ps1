# Settles the QUOTED-KEY BRACE LITERAL for 0.4.41.
#
# WHY THIS EXISTS. `_verify/diagnose_moui_truncations.ps1` reported three moui
# 0.1.12 files truncated at a `{`, all of them this shape:
#
#     (
#       {
#         "schemaVersion": envelope.schema_version,
#       } : Json).stringify()
#
# and the bucket's label said "shape parses, cause UNISOLATED", on the evidence of
# NINE fixtures that all read cleanly. Those fixtures were WRONG, and the reason is
# written into every one of them: they use `key: value`.
#
#     0450's own settle, `settle_0450_shapes.ps1`, case `ctl_quoted_keys`:
#         REJECT(4014)
#
# That rejection was correct and it was the warning nobody acted on. A quoted key
# is not a struct-literal field name, so `{"a": 1}` is not a struct literal --
# against a `Map` it is a MAP LITERAL, a different construct. Every fixture after
# that point replaced the quoted keys with unquoted ones, which turned a
# map-literal probe into a struct-literal probe, and nine green results were
# nine results about the wrong shape.
#
# THIS SETTLE ANSWERS IT, and the answer is that the construct is legal:
#
#     { "a": 1, "b": 2 }   as Map[String, Int]   ACCEPT
#     { a: 1 }             as Map[String, Int]   REJECT(4033, 4028)
#     { a: 1 }             as a struct           ACCEPT
#
# The second and third rows are the pair that matters. The two spellings are not
# interchangeable and neither is a typo for the other: the toolchain ACCEPTS the
# quoted form against a Map and REFUSES the unquoted one there. So the fixtures
# were not a loosened approximation of the corpus, they were a different language
# form, and no amount of re-running them could have found this.
#
# The last row is the corpus declaration verbatim in shape -- qualified name,
# multi-line parameter list, a `let` holding a method call, then the parenthesised
# literal with an ascription and a method call on it. ACCEPT, so this is a defect
# in the analyzer and not a misreading of illegal code.
#
# WHAT THE PARSER DOES WITH IT, measured in the same increment:
#
#     {"a": 1} as a bare tail       -> `unexpected token ':'`
#     { "a": e } as a let value      -> `expected a struct literal field here`
#     { a: e } (unquoted control)    -> clean
#
# The parser reads `{` as a struct literal and then rejects the key, which is a
# PRECISE complaint about an INCOMPLETE model. It is not a mis-tokenisation and
# there is no off-by-one to find: the construct the corpus writes has no
# representation at all.
#
# COST. Three of the twelve files moui still cannot finish reading. Two of the
# other nine buckets are unaffected: their cut lines are `async fn(`,
# `border?=`, `is @pkg`, `x? : T` and `(if ..)`, none of which is a brace.
#
# SCAFFOLD FACTS, load-bearing, each of which has silently produced a confident
# wrong answer in this repository: `moon.mod` MUST declare `source = "src"`; a
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

# POSITIVE CONTROL. A name that cannot exist must be rejected; if it is accepted,
# `moon check` is not discriminating here and every ACCEPT below proves nothing.
Add-Case 'ctl_missing' @'
///|
fn probe() -> Int {
  ignore(ZzMissing)
  0
}
'@ 'REJECT'

# THE DEFECT. A map literal is legal MoonBit and this parser cannot read it.
Add-Case 'map_literal_quoted_keys' @'
///|
fn probe() -> Map[String, Int] {
  { "a": 1, "b": 2 }
}
'@ 'ACCEPT'

# THE PAIR THAT KILLS THE OLD FIXTURES. Same braces, same target type, unquoted
# keys -- and the toolchain REFUSES it. The two spellings are distinct forms, so
# "the construct parses" was never a statement about the corpus at all.
Add-Case 'map_literal_unquoted_keys' @'
///|
fn probe() -> Map[String, Int] {
  { a: 1 }
}
'@ 'REJECT'

# ... and the unquoted spelling IS a struct literal, so the control has to name
# the type it was measured against.
Add-Case 'struct_literal_unquoted' @'
///|
pub struct Json {
  a : Int
}

///|
fn probe() -> Json {
  { a: 1 }
}
'@ 'ACCEPT'

# THE CORPUS DECLARATION, verbatim in shape. This is the claim that makes the
# rest a defect rather than a curiosity.
Add-Case 'corpus_declaration_shape' @'
///|
pub struct Holder {
  a : Int
}

///|
fn Holder::take(self : Holder) -> Int {
  self.a
}

///|
fn Map::stringify(self : Map[String, Int]) -> String {
  "s"
}

///|
pub fn Holder::dump(self : Holder) -> String {
  let e = self.take()
  (
    {
      "a": e,
    } : Map[String, Int]).stringify()
}
'@ 'ACCEPT'

# --- run --------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0452_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0452`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'ACCEPT') { $ok = $false }
    elseif ($want -eq 'REJECT') { $ok = $got -like 'REJECT*' }
    else { $ok = $got -eq $want }
  } else {
    $got = 'ACCEPT'
    $ok = ($want -eq 'ACCEPT')
  }
  Write-Output ('{0,-30} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. A BUILD-PLAN-FAILED row means the scaffold is wrong and NOTHING here'
  Write-Output 'is an answer. A `ctl_*` row reading ACCEPT means `moon check` is not'
  Write-Output 'discriminating and the ACCEPT rows beside it prove nothing.'
  exit 1
}
Write-Output 'GATE OK: a quoted-key brace literal is a legal MAP literal, the unquoted'
Write-Output 'spelling is a struct literal and the toolchain refuses it against a Map, and'
Write-Output 'the corpus declaration is ACCEPTed verbatim. So the three truncated files'
Write-Output 'are a real defect in the analyzer, and the nine fixtures that said otherwise'
Write-Output 'were measuring the unquoted spelling.'
exit 0

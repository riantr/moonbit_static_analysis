# Settle 0477 -- the PATTERN on the left of a `let`'s `=`.
#
# WHY. The analyzer cannot read `async/src/os_error/error.mbt`, and the reason it reports is
# the whole of it:
#
#     1x  expected '='
#         e.g. .../async/0.22.4/src/os_error/error.mbt
#
# Line 79 of that file is
#
#     let OSError(errno, context~) = self
#
# and the reader stops at the `(`, because there is no pattern reader at all: a binding is
# read as a NAME followed by `=`. Every `let <Name>(...)` site in the corpus dies the same
# way, and there are 21 of them across async (os_error, pipe, js_async, process/redirect).
#
# So the question this settle answers is not "does a pattern parse" but WHICH patterns the
# left of a `let` may carry, because the analyzer's symbol table has to bind the names the
# pattern introduces -- `errno` and `context` are both read on the next line, and an
# analyzer that parses the file while binding nothing would report both as undefined.
#
# THE ROWS ARE THE CORPUS'S OWN. 0476's lesson was that a settle row written for
# convenience can be wrong while the corpus carries the verdict; every ACCEPT row below is a
# line the corpus already writes, and the shape list is taken from it rather than invented.
#
# WHAT THE SCAFFOLD COST, because it is the part that was wrong twice and it is worth
# having written down. The first version of this file declared its fixture as a `struct`
# and BOTH CONTROLS REJECTED, which is what the gate is for:
#
#     Error [4199]  The type `OSError` does not declare a custom constructor,
#                   so `OSError(..)` cannot be used.
#
# `let OSError(..) = e` is not a pattern over a struct. It is a pattern over a CONSTRUCTOR,
# and only an enum/suberror variant declares one. The corpus agrees --
# `async/src/os_error/pkg.generated.mbti:22`:
#
#     pub(all) suberror OSError {
#       OSError(Int, context~ : String)
#     } derive(ToJson)
#
# The second scaffold fault was the constructor's own field syntax. `Square(Int, side : Int)`
# is a parse error ("Expected upper case identifier for type name"); inside a variant the
# fields are POSITIONAL (`Int`) or LABELLED (`name~ : Type`), never `name : Type`. So the
# shape to copy out of the mbti is `Ctor(PosType, label~ : Type)`.
#
# Both faults were in the PRELUDE, not in a claim, and both were fixed by changing the
# fixture until the toolchain agreed. That is the discipline: a control that goes red means
# the scaffold is wrong, and "the analyzer would like this to be legal" is not a reason to
# keep an expectation the compiler rejects.
#
# NOTE ON WHAT IS NOT BEING ASKED. Whether a pattern is IRREFUTABLE -- whether `let C(x) = e`
# is legal when C has siblings -- is a TYPE question, and the toolchain's answer depends on
# the constructor's arity. It is RECORDED here rather than predicted, because the parser
# reader must accept the SYNTAX either way and leave exhaustiveness to `infer`. Settling it
# here would encode a guess about a check this increment does not perform.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
# ctl_plain is the shape the reader already handles. If it stops being ACCEPT the
# scaffold is wrong, not the claim, and every row below would be measuring a broken build.
Add-Case 'ctl_plain_name' @'
///|
fn f(a : Int) -> Int {
  let b = a + 1
  b
}
'@ 'ACCEPT'

# ctl_ctor_positional is the corpus's simplest pattern: js_async.mbt:50 and pipe.mbt:33 both
# write `let JsError(value) = self` and `let PipeWrite(io) = self`. It is the control
# because it is the MINIMUM the reader has to accept for error.mbt to be readable at all;
# if this is refused the increment is aimed wrong.
Add-Case 'ctl_ctor_positional' @'
priv enum Shape {
  Circle(Int)
}

///|
fn f(s : Shape) -> Int {
  let Circle(r) = s
  r
}
'@ 'ACCEPT'

# --- S1  A LABELED FIELD. THE CORPUS SHAPE AT error.mbt:79 AND :86 ------------
#
# `context~` is the labelled form: the name is both the constructor's field label and the
# binding's name. Line 80 reads `\{context}` immediately, so the settle has to establish that
# `~` introduces a NAME rather than merely matching a label -- if it only matched, `context`
# would be unbound on the next line and S2 below would be a false negative.
Add-Case 'S1_ctor_positional_plus_label' @'
priv enum Shape {
  Circle(Int, label~ : String)
}

///|
fn f(s : Shape) -> String {
  let Circle(r, label~) = s
  "\{label}: \{r}"
}
'@ 'ACCEPT'

# --- S2  A LABEL IS A BINDING. What S1 only shows is accepted ------------------
#
# If `context~` were a pure match with no binding, S1 would still ACCEPT and its second line
# would read an unbound name. This row has a ONE-FIELD constructor and names ONLY the
# labelled field, so it passes if and only if the label bound the name. That is the
# difference between "the pattern is legal" and "the pattern binds what the corpus reads".
Add-Case 'S2_the_label_binds_the_name' @'
priv enum Shape {
  Circle(label~ : String)
}

///|
fn f(s : Shape) -> String {
  let Circle(label~) = s
  label
}
'@ 'ACCEPT'

# --- S3  THE REST PATTERN. THE CORPUS SHAPE AT error.mbt:95 AND :101 ----------
#
# `..` absorbs the remaining fields. The corpus only ever ignores them (line 96 reads
# `errno` and nothing else), so whether `..` BINDS a name for the tail is the open
# question: if it does, a reader that ignores it is losing a binding; if it does not, a
# reader that invents one is inventing a name no field can supply.
Add-Case 'S3_ctor_positional_plus_rest' @'
priv enum Shape {
  Circle(Int, label~ : String)
}

///|
fn f(s : Shape) -> Int {
  let Circle(r, ..) = s
  r
}
'@ 'ACCEPT'

# --- S4  MAY A LABEL APPEAR AFTER A `..`? -------------------------------------
#
# If `..` absorbs the remaining fields then nothing can follow it; if the tail is bindable
# then a name can. The reader's loop has to know which, because `..` is the one token that
# ends the field list without being a field. RECORDED, because a reader that stops at `..`
# and one that continues past it disagree about this row and only the toolchain can say.
Add-Case 'S4_label_after_the_rest' @'
priv enum Shape {
  Circle(Int, label~ : String)
}

///|
fn f(s : Shape) -> String {
  let Circle(r, .., tail) = s
  "\{tail}"
}
'@ 'RECORD'

# --- S5  A LABEL THE CONSTRUCTOR DOES NOT HAVE --------------------------------
#
# The reader's name bookkeeping has to decide what to do with a label it cannot resolve.
# The toolchain's answer is the one that matters, because a reader that silently accepts
# `nope~` invents a binding no field can supply -- and the corpus's own rows are all
# well-formed, so nothing in the corpus will ever ask the reader to refuse one.
Add-Case 'S5_label_not_in_the_constructor' @'
priv enum Shape {
  Circle(Int, label~ : String)
}

///|
fn f(s : Shape) -> Int {
  let Circle(nope~) = s
  nope
}
'@ 'RECORD'

# --- S6  A POSITIONAL FIELD THE CONSTRUCTOR DOES NOT HAVE ---------------------
Add-Case 'S6_positional_not_in_the_constructor' @'
priv enum Shape {
  Circle(Int)
}

///|
fn f(s : Shape) -> Int {
  let Circle(r, nope) = s
  nope
}
'@ 'RECORD'

# --- S7  A NESTED PATTERN ------------------------------------------------------
#
# `Wrap(Some(x))` is the standard shape for an enum payload and the one place a
# single-level reader would have to recurse. The analyzer does not have to accept it to fix
# error.mbt -- every corpus site is one level deep -- so this is RECORDED to say the syntax
# is real and out of scope, not to imply the reader grows.
Add-Case 'S7_nested_constructor' @'
priv enum Shape {
  Wrap(Payload)
}

priv enum Payload {
  One(Int)
}

///|
fn f(s : Shape) -> Int {
  let Wrap(One(inner)) = s
  inner
}
'@ 'RECORD'

# --- S8  A TUPLE ON THE LEFT --------------------------------------------------
#
# `(a, b) = f()` is a pattern on the same position, and the reader's dispatch would have to
# choose between NAME and `(`. RECORDED for the same reason as S7: it decides whether the
# increment's dispatch is `at('(')`-aware or not, which is worth knowing BEFORE writing it.
Add-Case 'S8_tuple_on_the_left' @'
///|
fn f(p : (Int, Int)) -> Int {
  let (a, b) = p
  a + b
}
'@ 'RECORD'

# --- S9  A REFUTABLE PATTERN --------------------------------------------------
#
# Shape has two constructors and `let Wrap(inner) = s` matches only one. Whether the
# toolchain refuses it is the IRREFUTABILITY question, and it is the reason this settle
# cannot simply say "constructor patterns are fine". RECORDED deliberately: the parser is
# type-blind and must accept the syntax regardless, so a REJECT here is a finding for
# `infer`, not an argument against reading the pattern at all.
Add-Case 'S9_refutable_pattern' @'
priv enum Shape {
  Wrap(Int)
  Empty
}

///|
fn f(s : Shape) -> Int {
  let Wrap(inner) = s
  inner
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0477_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0477`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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
  Write-Output ('{0,-42} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown|Unknown' }) |
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

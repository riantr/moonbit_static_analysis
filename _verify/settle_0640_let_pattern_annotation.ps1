# Settle 0640 -- the TYPE ANNOTATION on the left of a `let` whose pattern binds SEVERAL names.
#
# WHY. The analyzer cannot read `riantr/pyroduct` 0.1.5's `evolution/gate.mbt` past line
# 113, and the reason it reports is the whole of it:
#
#     1x  expected '='
#         e.g. .../pyroduct/0.1.5/evolution/gate.mbt
#
# Line 113 of that file is
#
#     let (objective, causal) : (Objective, CausalPlan?) = match criterion {
#
# and the reader stops at the `:`, because the three PATTERN paths of the `let` reader go
# straight from the pattern to `expect(TAssign)` -- the plain binding path has read an
# annotation for a long time, and the rule "a `let` may carry a type annotation" was
# already in the parser and simply was not REACHED from those three paths.
#
# The cost of one unread line is the whole file: everything below line 113 -- the score,
# the constitutional check, the backdating branch -- was invisible to the analyzer. And an
# unreadable file is not a finding, it is a SILENCE, so the defect was invisible in the
# report that reports defects.
#
# So the question this settle answers is not "does an annotation parse" but WHICH `let`
# PATTERNS may carry one, because the analyzer has to read the whole right-hand side once
# and bind the names the pattern introduces.
#
# THE ROWS ARE THE CORPUS'S OWN. 0476's lesson was that a settle row written for
# convenience can be wrong while the corpus carries the verdict; every ACCEPT row below is
# a shape the corpus writes or a shape the toolchain's own grammar admits, and the shape
# list is taken from the corpus rather than invented.
#
# WHAT IS NOT BEING ASKED. Whether a pattern is IRREFUTABLE -- whether `let C(x) = e` is
# legal when C has siblings -- is a TYPE question, and it is 0477's subject. The row is
# RECORDED rather than predicted, because the parser reader must accept the SYNTAX either
# way and leave exhaustiveness to `infer`.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
# ctl_plain_name is the shape the reader ALREADY handled, with the annotation. If it stops
# being ACCEPT the scaffold is wrong, not the claim, and every row below would be measuring
# a broken build. It is the control that says this increment did not break the path that
# already worked.
Add-Case 'ctl_plain_name' @'
///|
fn f(a : Int) -> Int {
  let b : Int = a + 1
  b
}
'@ 'ACCEPT'

# ctl_unannotated_tuple is the tuple path WITHOUT an annotation -- the shape 0477 settled
# and the shape the corpus's other `let`s use. The increment adds a branch to this path,
# and a branch that fires on a path it was not meant for would turn every destructuring
# `let` in every corpus into a notice. The notice count is a pinned number.
Add-Case 'ctl_unannotated_tuple' @'
///|
fn f(p : (Int, Int)) -> Int {
  let (a, b) = p
  a + b
}
'@ 'ACCEPT'

# --- S1  THE TUPLE. THE CORPUS SHAPE AT gate.mbt:113 ----------------------------
#
# The annotation here is a TUPLE TYPE, `(Int, Int)`. It is not a function type: the `(`
# reaches the reader whose body makes the `-> R` optional. A reader that insisted on the
# `->` would report "expected ')'" -- a DIFFERENT failure from the one this increment
# fixes, and this row is what separates the two.
Add-Case 'S1_annotated_tuple' @'
///|
fn f(p : (Int, Int)) -> Int {
  let (a, b) : (Int, Int) = p
  a + b
}
'@ 'ACCEPT'

# --- S2  THE CONSTRUCTOR PATTERN -----------------------------------------------
#
# A SEPARATE call site: this path goes through the pattern reader rather than the tuple
# reader, so a fix that touched only the tuple path would leave this one reporting
# "expected '='". The type is SINGLE-constructor, because a refutable pattern is 0477's
# question and not this one's -- see S5.
Add-Case 'S2_annotated_constructor' @'
priv enum Shape {
  Circle(Int)
}

///|
fn f(s : Shape) -> Int {
  let Circle(r) : Shape = s
  r
}
'@ 'ACCEPT'

# --- S3  THE STRUCT PATTERN ---------------------------------------------------
#
# The THIRD call site, and the one a two-site fix would miss. `..` binds nothing, so the
# reader's count of the names stays at one.
Add-Case 'S3_annotated_struct' @'
priv struct Point {
  x : Int
  y : Int
}

///|
fn f(p : Point) -> Int {
  let { x, .. } : Point = p
  x
}
'@ 'ACCEPT'

# --- S4  THE CORPUS SHAPE, VERBATIM -------------------------------------------
#
# `evolution/gate.mbt:113` exactly, with the `?` on the second element and the `match` as
# the initialiser. The `?` is the nullable marker on the TYPE, and the whole thing is
# ACCEPT, which is the fact this increment was written for.
Add-Case 'S4_the_corpus_shape' @'
priv enum Criterion {
  Weighted(Objective)
  Causal(CausalPlan)
}

priv enum Objective {
  Normal
}

priv struct CausalPlan {
  objective : Objective
}

///|
fn judge(c : Criterion) -> (Objective, CausalPlan?) {
  let (objective, causal) : (Objective, CausalPlan?) = match c {
    Weighted(o) => (o, None)
    Causal(p) => (p.objective, Some(p))
  }
  (objective, causal)
}
'@ 'ACCEPT'

# --- S5  A REFUTABLE CONSTRUCTOR PATTERN --------------------------------------
#
# Shape has two constructors and `let Wrap(inner) = s` matches only one. RECORDED
# deliberately: the parser is type-blind and must accept the SYNTAX regardless, so a
# REJECT here is a finding for `infer`, not an argument against reading the pattern.
Add-Case 'S5_refutable_constructor' @'
priv enum Shape {
  Wrap(Int)
  Empty
}

///|
fn f(s : Shape) -> Int {
  let Wrap(inner) : Shape = s
  inner
}
'@ 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0640_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0640`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
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

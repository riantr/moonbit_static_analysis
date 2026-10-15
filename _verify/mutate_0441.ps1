# Mutation gate 0441 -- two top-level functions of the SAME NAME must not share
# one declaration table.
#
# On the harness: no runner of its own, all six rules from
# `_verify/mutate_lib.ps1` apply.
#
# THE CHANGE. `WalkResult.fn_bindings` was a `Map[String, Array[Binding]]` keyed
# by `f.name`, and BOTH consumers looked a function's declarations up by that
# name:
#
#     walk.mbt   fn_bindings.set(f.name, bs)        -> pass 3 fn_bindings.get(f.name)
#     infer.mbt  self.fn_bindings.get(f.name)       -> Infer::run_fn
#
# Two top-level functions of one name therefore shared ONE table and the second
# `set` overwrote the first, so every function of that name was analysed against
# the LAST one's parameters. It is now an `Array` parallel to `fns`, indexed by
# position, and `run_fn` takes its bindings as an argument because the position
# is the caller's to know.
#
# MEASURED, proton 0.3.4 `window_geometry.mbt:12` and `:13`:
#
#     pub fn window_size_in_screen_coordinates(width, height, scale_factor_percent)
#     pub fn window_size_in_screen_coordinates(width, height)
#
# reported `undefined name 'scale_factor_percent'` twice -- the parameter belongs
# to the `#cfg(platform="windows")` variant only.
#
# `#cfg` IS NOT THE CAUSE AND IS NOT THE FIX. MoonBit allows two top-level
# functions of one name when `#cfg` gates them per platform, and
# `Lexer::lex_attribute` deliberately emits NO token for an attribute -- so both
# variants are analysed together, a stated fidelity cost. `#cfg` appears 689
# times across 99 moonbitlang/async files; that is how real code REACHES the
# defect, not what causes it, and the reproduction below has no `#cfg` at all.
#
#   M1  every same-named function takes the LAST one's parameters -- the defect
#       itself. It is written as running code, not as `fn_bindings.set(f.name, bs)`:
#       the field is an `Array` now, so the literal old line cannot compile, and a
#       mutant that fails to build measures nothing (harness rule 2).
#   M2  the walk indexes the array but the TYPE LENS still looks up by name, so
#       `Infer::run_fn` keeps the defect after the walk is fixed. The two
#       consumers were separate bugs and a one-sided fix would have left half of
#       it standing, silently, because most findings come from one lens.
#   M3  the guard `i < fn_bindings.length()` becomes `i == 0`, so every function
#       past the first is analysed against the FIRST one's parameters -- "first
#       wins". Two-function tests cannot see this; the three-function one is the
#       whole reason it exists.
#   M4  the walk seeds the frame correctly but the TYPE LENS is handed the wrong
#       function's bindings, so the two lenses disagree about a parameter's type.
#       Distinct from M2: M2 loses the names, M4 keeps them and mistypes them.
#
# M3 and M4 are the quiet ones. Both keep every NAME resolvable, so a suite that
# only asserts "no UndefinedName" reports them as improvements.
#
#
# THE FIRST RUN OF THIS GATE FAILED, and the failure is the point of rule 6.
# All four mutations were KILLED -- 5, 12, 17 and 12 of 552 red -- and the gate
# still reported GATE FAILED, because M2 and M4 named
# `0441: the type lens also keeps the two variants apart` as the test that must
# go red and IT DID NOT. That test was documented as the pin for `Infer::run_fn`'s
# separate by-name lookup, so it was a guard claiming coverage it did not have.
#
# Its source was
#
#     pub fn g(w : Int, s : String) -> Int { w + 1 }
#     pub fn g(w : Int) -> Int { w + 1 }
#
# Under M2 -- the walk left CORRECT, only the type lens left sharing a table --
# every function is handed the last variant's `{ w : Int }`, `s` appears in no
# body, and `w + 1` is `int + int` either way. Nothing to report. The doc comment
# above it claimed this source reported `unsupported operand types for '+'` before
# the fix; it did not, under a type-lens-only mutation, and the claim is withdrawn.
#
# Re-anchoring M2 and M4 to some test that DID go red would have turned the gate
# green and left the test just as worthless. The test was rewritten instead --
# same parameter name, DIFFERENT type in the two variants -- and the rewrite was
# proved both ways before this file was run again:
# `_verify/prove_mustred.ps1` shows it green on clean code (6/6) and red under M2
# and under M4 (2/6). A test named after the defect is not a test OF the defect.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$BUILD = @'
  for f in fns {
    fn_bindings.push(collect_fn_bindings(f))
  }
'@.Replace("`r`n", "`n")

$CONSUME = @'
    let bs = if i < fn_bindings.length() { fn_bindings[i] } else { [] }
'@.Replace("`r`n", "`n")

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    # NOT `fn_bindings.set(f.name, bs)`. The field is an `Array` now, so that
    # replacement cannot compile, and a mutant that fails to build is a mutant
    # nobody measured (harness rule 2) -- it would land as COMPILE-ERR and say
    # nothing about whether the guard sees the defect. This reproduces the OLD
    # semantics in code that builds: a function takes the bindings of the LAST
    # function sharing its name, which is exactly what the second `set` did.
    Name = 'M1 every same-named function takes the LAST one''s parameters, which is the defect'
    File = 'src\walk\walk.mbt'
    Find = $BUILD
    Repl = @'
  for f in fns {
    let mut bs = collect_fn_bindings(f)
    for g in fns {
      if g.name == f.name {
        bs = collect_fn_bindings(g)
      }
    }
    fn_bindings.push(bs)
  }
'@.Replace("`r`n", "`n")
    MustRed = '0441: two same-named top-level functions each get their own parameters'
  },

  @{
    Name = 'M2 the walk is fixed but the type lens keeps its by-name lookup'
    File = 'src\types\infer.mbt'
    Find = @'
  for i, f in wr.fns {
    let bs = if i < wr.fn_bindings.length() { wr.fn_bindings[i] } else { [] }
    let _ = inf.run_fn(f, bs)
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  for f in wr.fns {
    let bs = if wr.fn_bindings.length() > 0 { wr.fn_bindings[wr.fn_bindings.length() - 1] } else { [] }
    let _ = inf.run_fn(f, bs)
  }
'@.Replace("`r`n", "`n")
    MustRed = '0441: the type lens also keeps the two variants apart'
  },

  @{
    Name = 'M3 the bounds guard becomes `i == 0`, so the FIRST function wins'
    File = 'src\walk\walk.mbt'
    Find = $CONSUME
    Repl = @'
    let bs = if i == 0 && fn_bindings.length() > 0 { fn_bindings[i] } else { [] }
'@.Replace("`r`n", "`n")
    MustRed = '0441: with three same-named functions each keeps its own parameters'
  },

  @{
    Name = 'M4 the type lens is given the WRONG function bindings, not none'
    File = 'src\types\infer.mbt'
    Find = @'
  for i, f in wr.fns {
    let bs = if i < wr.fn_bindings.length() { wr.fn_bindings[i] } else { [] }
    let _ = inf.run_fn(f, bs)
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  for i, f in wr.fns {
    let j = if i + 1 < wr.fn_bindings.length() { i + 1 } else { i }
    let bs = if j < wr.fn_bindings.length() { wr.fn_bindings[j] } else { [] }
    let _ = inf.run_fn(f, bs)
  }
'@.Replace("`r`n", "`n")
    MustRed = '0441: the type lens also keeps the two variants apart'
  }
)

Write-MutationGateVerdict -Name '0441'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

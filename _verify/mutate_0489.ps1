# Mutation gate 0489 -- the PER-FUNCTION ENTRY for the behavioral lens, and the
# four name-resolution rules the entry made necessary.
#
# WHAT THIS INCREMENT IS. The behavioral lens entered at the MODULE:
# `Interp::run_top` skips `SFunc` items, so a function body was executed only
# if something called it from a top-level statement. A library module does not
# call its own functions at top level, so on every pinned corpus the lens
# executed ZERO function bodies -- moui 4152 findings, proton 1062, async 1820,
# all of them tagged `structural`, and not one tagged `behavior`.
#
# MEASURED, the gap was the ENTRY and nothing else. The same defect, in the
# same body, three ways:
#
#   top     -- a top-level statement        -> [type+behavior]
#   incall  -- in a function CALLED at top  -> [type+behavior]
#   uncall  -- in a function NEVER called   -> [type]   <- behavior GONE
#
# for every defect kind tried. `Unreachable` is the family this gate pins
# with, because it is the one NO OTHER LENS SEES: the structural and type
# lenses both walk the body and find nothing there.
#
# THE ENTRY ALSO UNCOVERED FOUR LATENT DEFECTS IN THE LENS, which is the part
# that was worth the increment. Each is a case where the lens invented a
# finding the other two lenses contradicted:
#
#   M2  an ENUM CONSTRUCTOR read was `undefined variable` -- the lens never
#       received `ParseResult::enum_ctors`, the list the structural and type
#       lenses both get.
#   M3  a QUALIFIED CONSTRUCTOR read (`PixelFormat::RGBA8`) was `undefined
#       variable` -- the structural lens has the TAIL rule (`walk.mbt`'s
#       `tail_bound`) and this lens had none.
#   M4  a CALL TO A FUNCTION-TYPED PARAMETER was `undefined function` --
#       `Interp::call` dispatched only through the top-level method table and
#       never consulted the frame the parameter is bound in.
#   M5  the fresh value for a parameter IGNORED the declared type.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE. fmt both rewraps one
# line into several and collapses several into one, and either way a stale
# anchor is a PREFLIGHT MISS that runs no suite at all.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$INTERP = 'src\interp\interp.mbt'
$PIPE = 'src\pipeline\pipeline.mbt'

Invoke-MutationGate -Name '0489' -Target 'wasm' -Mutations @(

  # M1 THE ENTRY, THE INCREMENT. The per-function pass analyses nothing, so the
  # lens is back to entering at the module -- and the uncalled body is never
  # executed. This is the mutation the whole increment exists to prevent, and
  # it is the one that would make the flag a no-op.
  @{
    Name = 'M1 the per-function pass analyses no function at all'
    File = $INTERP
    Find = @'
  for f in wr.fns {
    it.analyze_entry(f, tr)
  }
  it.sink = saved_sink
  for f in wr.fns {
    it.analyze_entry(f, tr)
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  it.sink = saved_sink
'@.Replace("`r`n", "`n")
    MustRed = 'the per-function entry analyses a body'
  }

  # M2 THE CONSTRUCTOR TABLE. The lens never received `ParseResult::enum_ctors`
  # -- the list the structural and type lenses both get -- so every constructor
  # read was `undefined variable`.
  #
  # MEASURED, the first corpus the entry touched reported it as an ERROR:
  # `proton_contract 0.3.4 contract.mbt:261`, `ContractRoute::{ scope:
  # Application, name, }`, `undefined variable 'Application'`.
  @{
    Name = 'M2 an enum constructor is an undefined variable again'
    File = $INTERP
    Find = @'
              } else if self.ctors.contains(n) {
'@.Replace("`r`n", "`n")
    Repl = @'
              } else if false {
'@.Replace("`r`n", "`n")
    MustRed = 'an enum constructor read is not an undefined variable'
  }

  # M3 THE TAIL RULE. The structural lens resolves a qualified path whose TAIL
  # is bound -- `walk.mbt`: "a qualified path whose TAIL is bound is a real
  # name: `Layer::ReLU` is a unit enum variant, and the harvest binds `ReLU` but
  # not the whole path". This lens had no such rule, so a qualified constructor
  # read was reported here and not there.
  #
  # It is a TAIL rule and not a blanket "any qualified name is fine", because a
  # blanket silences real findings the repository pins on purpose: `Array::mkae`
  # (a builtin type with a method that does not exist) and `ZzMissing::nope`
  # (an unknown head) must both still be reported, and the tail of each is not
  # bound. M3 is therefore paired with a CONTROL in the test file, and the
  # control is what a blanket would fail.
  @{
    Name = 'M3 a qualified constructor read is an undefined variable again'
    File = $INTERP
    Find = @'
              } else if self.tail_bound(n, env) {
'@.Replace("`r`n", "`n")
    Repl = @'
              } else if false {
'@.Replace("`r`n", "`n")
    MustRed = 'a qualified constructor read is not an undefined variable'
  }

  # M4 THE FRAME. A call to a name bound in the current frame -- a
  # function-typed parameter, or a local `let f = fn(...)` -- is a call to a
  # BOUND name. `Interp::call` dispatched only through the top-level method
  # table, so the call was `undefined function 'cb'`.
  @{
    Name = 'M4 a call to a function-typed parameter is undefined again'
    File = $INTERP
    Find = @'
      if !self.methods.contains(name) && env.contains(name) {
'@.Replace("`r`n", "`n")
    Repl = @'
      if false {
'@.Replace("`r`n", "`n")
    MustRed = 'a call to a function-typed parameter is not an undefined function'
  }

  # M5 THE FRESH VALUE. The value a parameter is bound to comes from its
  # DECLARED type, and an unannotated parameter is `AAny` -- "some value we
  # know nothing about". A concrete type would be a CLAIM about a value the
  # analyzer has not seen, and a false claim produces a finding on correct
  # code.
  @{
    Name = 'M5 the fresh value ignores the declared parameter type'
    File = $INTERP
    Find = @'
    @types.TInt => AType("int")
    @types.TFloat => AType("float")
    @types.TBool => AType("bool")
'@.Replace("`r`n", "`n")
    Repl = @'
    @types.TInt => AAny
    @types.TFloat => AAny
    @types.TBool => AAny
'@.Replace("`r`n", "`n")
    MustRed = 'a declared parameter type reaches the behavior lens'
  }

  # M6 THE FLAG. `run_functions` falls back to the module entry, so the
  # per-function view and the module view are the same view and the flag is
  # decorative.
  @{
    Name = 'M6 the per-function view is the module view'
    File = $PIPE
    Find = @'
    @interp.analyze_functions(
'@.Replace("`r`n", "`n")
    Repl = @'
    @interp.analyze_module(
'@.Replace("`r`n", "`n")
    MustRed = 'the per-function entry analyses a body'
  }
)

Write-MutationGateVerdict -Name '0489'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

# Mutation gate 0492 -- the PARAMETER'S ANNOTATION, erased by a re-binding.
#
# WHAT THIS INCREMENT IS. `Infer::run_fn` seeds a function's frame from the
# structural lens's binding table. That table lists the function's PARAMETERS
# first and its BODY BINDINGS after, and the walk records an assignment
# `xs["k"] = "v"` as a RE-BINDING of the base name `xs`. So the table carried
# `xs` TWICE, and the body binding -- which carries no type of its own -- was
# declared LAST and OVERWROTE the parameter's annotation. The parameter's type
# was then gone for the WHOLE function body, and every check on that name
# degraded to "unknown".
#
# The case that made it visible:
#
#     fn h(xs : Array[String]) -> Unit { xs["k"] = "v" }
#
# The analyzer reported it CLEAN. The type lens has a gate for exactly this
# shape -- "list indices must be int" -- and the READ form of the same code IS
# reported. The source even says the two arms must agree: "Both arms must agree
# -- a check that fires on read and not on write is a claim about syntax, not
# about types." So the write arm was not merely untested: it could not fire,
# because the base's type was gone before it was consulted.
#
# SETTLED WITH THE TOOLCHAIN, `_verify/settle_0492_param_type.ps1`, 9 rows with
# two POSITIVE CONTROLS that must REJECT. The toolchain REJECTS the write form
# and the read form, and ACCEPTS the correct code.
#
# THE FIX is the ORDER of two loops: the body bindings are declared first and
# the parameters last, so a parameter's annotation is written over any re-binding
# of the same name. Among the body bindings themselves the LAST still wins, and
# that is load-bearing -- the walk's table is FLAT across nested scopes and
# lists the INNER binding first, so "last wins" is what keeps the 0468/0469
# binding-scope leak fixed.
#
# THE FOUR MUTATIONS below are the four ways this can be wrong. M1 reverts the
# order, M2 drops the parameter's TYPE, M3 drops its ANNOTATED flag, and M4
# attacks the OTHER half of the pair -- the write arm's own base-type
# condition, which was UNOBSERVABLE while the arm was dead and is observable
# now.
#
# => 判据: A PARAMETER'S ANNOTATION IS A FACT ABOUT THE VARIABLE. A RE-BINDING OF
# THAT VARIABLE IS NOT A NEW DECLARATION, AND IT MUST NOT ERASE THE FACT.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$TYPES = 'src\types\infer.mbt'

$mutations = @(
  # M1 -- THE ORDER. The pre-fix shape: the parameters first, the body bindings
  # after, so the re-binding overwrites the annotation and the defect returns.
  @{
    Name = 'M1 the parameters are declared before the body bindings again'
    File = $TYPES
    Find = @'
  for b in bs {
    if !b.param {
      // body bindings start Unknown; statements refine them
      self.declare_sym(b, TUnknown, false)
    }
  }
  for b in bs {
    if b.param {
      self.declare_sym(b, ann_to_ty(b.tyann), !(b.tyann == ""))
    }
  }
'@
    Repl = @'
  for b in bs {
    if b.param {
      self.declare_sym(b, ann_to_ty(b.tyann), !(b.tyann == ""))
    }
  }
  for b in bs {
    if !b.param {
      // body bindings start Unknown; statements refine them
      self.declare_sym(b, TUnknown, false)
    }
  }
'@
    MustRed = 'an indexed write through a PARAMETER reports the index type'
  }

  # M2 -- THE PARAMETER'S TYPE. The order is right and the annotation is
  # applied, but to the wrong value: the parameter is declared Unknown, so the
  # base's type is still gone when the write arm consults it.
  @{
    Name = 'M2 the parameter is declared Unknown'
    File = $TYPES
    Find = @'
      self.declare_sym(b, ann_to_ty(b.tyann), !(b.tyann == ""))
'@
    Repl = @'
      self.declare_sym(b, TUnknown, !(b.tyann == ""))
'@
    MustRed = 'an indexed write through a PARAMETER reports the index type'
  }

  # M3 -- THE ANNOTATED FLAG. The parameter's TYPE survives, but the flag that
  # says "this name has a declared type" is lost, and the flag is what the
  # assignment check consults: `annos[fi].get(n)` decides whether a new value
  # is CHECKED against the declared type or silently re-binds it.
  @{
    Name = 'M3 the parameter is declared unannotated'
    File = $TYPES
    Find = @'
      self.declare_sym(b, ann_to_ty(b.tyann), !(b.tyann == ""))
'@
    Repl = @'
      self.declare_sym(b, ann_to_ty(b.tyann), false)
'@
    MustRed = 'a parameter re-assigned a wrong-typed value is checked against its annotation'
  }

  # M4 -- THE OTHER HALF OF THE PAIR. The write arm's own base-type condition.
  # While the arm was dead this was UNOBSERVABLE -- no mutation inside it could
  # be killed, because the arm was never reached. Now that a parameter's type
  # reaches it, the condition is load-bearing: drop the base check and the gate
  # fires on a `Map` indexed by its KEY, which is correct code.
  @{
    Name = 'M4 the write arm fires on any base'
    File = $TYPES
    Find = @'
      if bt is TList(_) && !(it is TInt) && !(it is TUnknown) {
        self.report(
          @core.FOpMismatch,
          "list indices must be int, got '\{ty_name(it)}'",
          idx.span,
        )
      }
      let vt2 = self.ty_of(rhs, TUnknown)
'@
    Repl = @'
      if !(it is TInt) && !(it is TUnknown) {
        self.report(
          @core.FOpMismatch,
          "list indices must be int, got '\{ty_name(it)}'",
          idx.span,
        )
      }
      let vt2 = self.ty_of(rhs, TUnknown)
'@
    MustRed = 'a Map written through its key is not a finding'
  }
)

Invoke-MutationGate -Name '0492' -Target 'js' -Mutations $mutations
Write-MutationGateVerdict -Name '0492 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

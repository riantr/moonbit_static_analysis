# Mutation gate 0462 -- `let mut p = p` SHADOWS the parameter.
#
# WHAT THIS PINS. The corpus shape, `moonbitlang/async 0.22.4
# src/internal/gzip_internal/encoder.mbt:148-156`:
#
#     produced : Int,                    // the parameter
#     let mut produced = produced        // a NEW binding, shadowing it
#     produced = self.push_byte(...)     // assigns the SHADOW
#
# Reporting `parameter 'produced' changed by assignment` there is a false positive,
# and it was the last one between async and `actionable = 0`.
#
# THE DISCRIMINATOR IS AN ASYMMETRY BETWEEN TWO PROGRAMS, not one program's reading:
#
#     let mut p = p; p = 5; p     ->  moon check: 0 errors
#     p = 5; p                    ->  moon check: 1 error
#
# Assigning an unshadowed immutable parameter is ILLEGAL, so the assignment in the
# first program cannot be reaching the parameter.
#
# WHY IT LIVES IN THE `SLet` ARM AND NOT IN `bind`. `bind` cannot tell a `let` from
# an assignment target, a `for` binder or a destructuring name -- all four arrive as
# a non-parameter `Binding` with the same name -- and treating those as shadowing
# deletes the very finding the lens exists for. An attempt did exactly that and two
# existing tests said so. This is the mutation that would reintroduce it.
#
# => 判据: ORDERING is the whole content here. Clearing the flag AFTER walking the
# initialiser still stops `ParamChanged` -- the `SLet` arm above would go no red --
# and trades one false positive for another, because `let mut p = p` READS the
# parameter on the right-hand side. Move the read onto the new entry and the
# parameter sits at `varuses == 0`, and `FUnusedParam` fires on the same line. A
# mutation that only the ORDER can kill is the reason there are two tests here and
# not one.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$WALK = 'src\walk\walk.mbt'

Invoke-MutationGate -Name '0462' -Target 'js' -Mutations @(

  # M1 IS THE GATE. The unshadow call is gone, which is the pre-0462 walker: the
  # assignment is read as assigning the parameter.
  @{
    Name = 'M1 the unshadow call is removed'
    File = $WALK
    Find = "      self.unshadow_param(n)`n      self.walk_expr(init)"
    Repl = '      self.walk_expr(init)'
    MustRed = '0462: let mut p = p shadows the parameter, so the assignment is the local''s'
  }

  # M2 THE ORDER IS REVERSED -- the flag is cleared AFTER the initialiser is walked.
  #
  # DECLARED SURVIVED, and this row is why the ordering PARAGRAPH in `unshadow_param`
  # used to be wrong. It claimed the order was load-bearing: `let mut p = p` reads
  # the parameter, so clearing the flag afterwards would leave the parameter at
  # `varuses == 0` and fire `FUnusedParam`. 684/684 stayed green under the reversal,
  # including a row written specifically to catch it (an initialiser that shadows
  # the same name itself -- `let mut produced = if produced > 0 { let produced = 1
  # .. }` -- the shape that should have separated the two orders).
  #
  # THE CLAIM IS SETTLED BY CONSTRUCTION, not by the absence of a covering test:
  # `unshadow_param` copies `assigns` and `varuses` out of the entry it finds and
  # writes them back with `param` cleared. Walking first yields
  # `(true, a, v+1) -> (false, a, v+1)`; clearing first yields `(false, a, v)` and
  # the walk then makes it `(false, a, v+1)`. Identical, for any `a` and any `v`,
  # so no program can reach a difference.
  #
  # The original reasoning described a REPLACEMENT where the code performs a
  # field-wise update. That paragraph has been corrected in place.
  @{
    Name = 'M2 the flag is cleared AFTER walking the initialiser'
    File = $WALK
    Find = "      self.unshadow_param(n)`n      self.walk_expr(init)"
    Repl = "      self.walk_expr(init)`n      self.unshadow_param(n)"
    Expect = 'SURVIVED'
    Prove = 'Unreachable by construction: unshadow_param copies assigns and varuses out of the entry it reads and writes them back with param cleared, so both orders produce (param:false, assigns:a, varuses:v+1) for any a and any v. Measured 684/684 green, including a dedicated witness whose initialiser shadows the same name. The doc paragraph claiming order was load-bearing has been corrected in place.'
  }

  # M3 THE GUARD IS DROPPED, so `unshadow_param` rewrites ANY entry with the same
  # name rather than only a parameter's. `bind` cannot tell a `let` from an
  # assignment target, a `for` binder or a destructuring name -- all four arrive as
  # a non-parameter `Binding` -- and an unguarded rewrite was supposed to delete
  # the finding the lens exists for.
  #
  # DECLARED SURVIVED, and the claim is settled BY CONSTRUCTION rather than by
  # argument about the corpus: the body assigns `param: false`, so on an entry that
  # is already `param: false` it writes the value that is there. `if true` and
  # `if e.param` are the same function on every entry that can reach it, and no
  # input distinguishes them -- which is a stronger statement than "no test covers
  # this" and is exactly what rule 5 asks a survivor to be.
  #
  # The guard is kept anyway: it says the rule is about PARAMETERS, and a reader
  # who needs the non-parameter case to be a no-op should not have to derive that
  # from the assignment.
  @{
    Name = 'M3 the parameter guard is dropped'
    File = $WALK
    Find = "      if e.param {`n        frame.set(name, {"
    Repl = "      if true {`n        frame.set(name, {"
    Expect = 'SURVIVED'
    Prove = 'No program can reach a difference: the body assigns param: false, so on an entry whose param is already false the write is the identity. Measured 683/683 green under mutation as well. The guard is retained for legibility, not because it changes behaviour.'
  }

  # M4 AND THE REWRITE DOES NOT CLEAR THE FLAG, so `unshadow_param` is called,
  # finds the entry, and does nothing. The code reads as a rule that is enforced;
  # it is a rule that is written down.
  @{
    Name = 'M4 the rewrite keeps the parameter flag set'
    File = $WALK
    Find = "          param: false,`n          assigns: e.assigns,"
    Repl = "          param: e.param,`n          assigns: e.assigns,"
    MustRed = '0462: let mut p = p shadows the parameter, so the assignment is the local''s'
  }
)

Write-MutationGateVerdict -Name '0462'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

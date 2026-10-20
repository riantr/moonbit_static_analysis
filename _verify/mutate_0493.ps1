# Mutation gate 0493 -- FOUR behavioral-lens claims that were false, and the
# five ways this can go wrong again.
#
# WHAT THIS INCREMENT IS. The per-function view reported SEVEN actionable
# findings on wzzc-dev/moui 0.1.12 that the module view reports 0. They were
# not seven defects in the analysed code: they were an INVENTORY of four
# claims the behavioral lens made about programs the toolchain accepts.
#
#   B  the `is`-pattern binding introduced by an `else if` CONDITION
#      moui views/text/text_area_control.mbt:414 -> 426
#      `ctx.text_control.text_selection_anchor is Some(anchor)` binds
#      `anchor`, which is read twelve lines later. Reported
#      `undefined variable 'anchor'`.
#      CAUSE: the `else if` conditions were never EVALUATED outside the
#      constant-condition path, so the binding was never introduced -- and a
#      name read in a condition was never checked either, which is a false
#      NEGATIVE in the same line.
#
#   C  a function's VALUE when its body yields none
#      moui views/text/text_input_editing.mbt:42   `clamp_int(None, int, Any)`
#      moui backend/web/web_host.mbt:357, :359     `web_string_append_char(None, Any)`
#      moui backend/linux/linux_services.mbt:183   `>(None, float)`
#      CAUSE: "None" -- the Unit type -- was the answer for a body that
#      produced no value. That is false for an EXTERN function (its body is
#      in another language) and for a body whose last statement is an `if`
#      whose branch value is not modelled (a `match` inside a branch).
#
#   D  a call that supplies its arguments BY LABEL
#      moui views/navigation/navigation_routing.mbt:157
#      `RouteHistoryState::from_routes(routes=snapshot.routes, title~, source~)`
#      Reported `no method matching RouteHistoryState::from_routes(Any, str, str)`.
#      CAUSE: the dispatch compared arguments POSITIONALLY. The labels were in
#      the AST the whole time -- `ECall`'s third field -- and this lens
#      discarded them.
#
#   E  a `while` loop whose body always terminates
#      moui core/unicode/grapheme_cluster.mbt:428
#      `false` after a `while` whose body ends in `return`. Reported
#      `unreachable code`.
#      CAUSE: a loop may run ZERO times, so the body's flow is not the flow
#      after the loop.
#
# SETTLED WITH THE TOOLCHAIN, `_verify/settle_0493_lens_values.ps1`, 21 rows
# with TEN that REJECT, plus an EXECUTION section for class E (MoonBit
# ACCEPTS code after a `return`, so the toolchain does not settle
# reachability by compiling; the execution row does, and it prints 42).
#
# THE FIVE MUTATIONS below are the five ways this can be wrong again. M1
# reverts the `else if` condition evaluation, M2 reverts the declared return
# type, M3 makes the labels invisible again, M4 reverts the loop's flow, and
# M5 attacks the OTHER half of class E -- the `Unreachable` report itself --
# so the control row that says "code after a `return` is still unreachable"
# is pinned and not merely present.
#
# => 判据: A LENS CLAIM IS A CLAIM. "None" is not a synonym for "we do not
# know", and "unreachable" is not a synonym for "the loop above always
# returns".
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$INTERP = 'src\interp\interp.mbt'

$mutations = @(
  # M1 -- CLASS B. The `else if` condition is code, and it is not evaluated.
  # The `is` pattern in it never binds, and a name read in it is never
  # checked. Both directions are in the same line.
  @{
    Name = 'M1 the else-if conditions are not evaluated again'
    File = $INTERP
    Find = @'
            let cv = self.eval(ei.cond, env_ei)
            if !vboolean(cv) {
              self.report(
                @core.FCondBool,
                "condition must be bool, got '\{val_name(cv)}'",
                ei.cond.span,
              )
            }
            self.exec_block(ei.body, env_ei)
'@
    Repl = @'
            self.exec_block(ei.body, env_ei)
'@
    MustRed = '`is` binding in an else-if condition'
  }

  # M2 -- CLASS C. The declared return type is the answer for a body that
  # yields no value; "None" is the answer only for a body that says it
  # returns Unit. This reverts the whole chain to the pre-fix shape, so the
  # extern function and the `match`-in-a-branch both go back to "None".
  @{
    Name = 'M2 a body that yields no value answers None again'
    File = $INTERP
    Find = @'
    self.last_value
  } else if def.cycle_ret != AAny {
    def.cycle_ret
  } else {
    join_vals(self.ret_vals)
  }
'@
    Repl = @'
    self.last_value
  } else {
    join_vals(self.ret_vals)
  }
'@
    MustRed = 'a function whose value comes from a match in an if branch keeps its declared type'
  }

  # M3 -- CLASS D. The labels decide the binding, and the labels are read
  # from `ECall`'s third field. Making `any_label` false again is exactly the
  # pre-fix behaviour: the arguments are compared by position again.
  @{
    Name = 'M3 the argument labels are invisible again'
    File = $INTERP
    Find = @'
        if labels[li] != "" {
          any_label = true
        }
'@
    Repl = @'
        if labels[li] != "" {
          any_label = false
        }
'@
    MustRed = 'a labelled call that omits an optional parameter is accepted'
  }

  # M4 -- CLASS E. A loop may run zero times, so the body's flow is not the
  # flow after the loop. Removing the rule restores "the body always
  # terminates", and the statement after the loop is reported unreachable
  # again.
  @{
    Name = 'M4 a while loop is treated as always terminating again'
    File = $INTERP
    Find = @'
      let always = match cv {
        ABool(b) => b
        _ => false
      }
      let broke = match self.flow {
        FBreak | FContinue => true
        _ => false
      }
      self.flow = if always && !broke { self.flow } else { FNormal }
'@
    Repl = @'
'@
    MustRed = 'the statement after a while that may run zero times is reachable'
  }

  # M5 -- THE OTHER HALF OF CLASS E. The `Unreachable` report itself. Without
  # this mutation the control row -- "the statement after a `return` is still
  # unreachable" -- would be a row nobody had shown could go red, and the
  # class E fix would be indistinguishable from switching the family off.
  @{
    Name = 'M5 the unreachable report is switched off'
    File = $INTERP
    Find = @'
      self.report(@core.FUnreachable, "unreachable code", s.span)
'@
    Repl = @'
      let _ = s
'@
    MustRed = 'the statement after a return is still unreachable'
  }
)

Invoke-MutationGate -Name '0493' -Target 'js' -Mutations $mutations
Write-MutationGateVerdict -Name '0493 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

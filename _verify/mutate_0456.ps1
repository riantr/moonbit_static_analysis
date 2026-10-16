# Mutation gate 0456 -- the package-qualified `is` pattern head.
#
# WHAT THIS PINS. `parse_is_pattern` reads a `TName` head and then loops on `::`.
# `@pkg` lexes as ONE `TName` with the `@` INSIDE the name string (lexer.mbt:361),
# so the reader consumed `@pkg`, then met a `.` where the loop wanted a `:`, left
# `qualified` false, and returned with `.Type::Ctor` still in the token stream. The
# `::` reached `parse_atom`'s catch-all, which is why the scanner reported
# ``unexpected token `:` `` on a line whose `:` is a path marker rather than
# `unexpected token @``.
#
# THE PINNED REASON WAS WRONG, and that is most of what this gate exists to keep
# from being re-introduced. `parser_0436_test.mbt` recorded that "`peek_name()` is
# `""` for an `@` head, the reader returns without consuming anything". It does not:
# `peek_name()` returns `"@pkg"`. Both stories predict the same symptom and a
# DIFFERENT repair -- one says add a new head kind, the other says consume four more
# tokens -- and only the disagreement between the prediction and the measured reason
# string separated them.
#
# => 判据: two explanations of one symptom are not interchangeable. When they
# disagree about what the code CONSUMED, the disagreement is the cheapest available
# evidence about which one is true, and it should be chased before either is acted
# on. A pin that records a mechanism rather than a symptom is worth correcting in
# place even when the symptom it explains is already fixed.
#
# THE FIX, four tokens, at parser.mbt:3033:
#
#     if head.has_prefix("@") && self.at(TDot) {
#       let _ = self.bump()
#       if self.peek_name() != "" {
#         let _ = self.bump()
#       }
#     }
#
# Settled against the toolchain BEFORE implementing, not after --
# `_verify/settle_0456_at_is_head.ps1`, 9/9, with the canary REJECTing and the
# package boundary REJECTing so the four ACCEPTs are discriminating. Two of those
# rows are the reason this could not have been guessed: `..` over a LABELED payload
# is legal (`sqlite3 StepResult::Done(changes~ : Int64?)`) and over a POSITIONAL one
# is REJECT(4080) "This `..` is useless, all fields are already matched". The first
# fixture got that wrong and produced a confident wrong answer about the grammar.
#
# Corpus: moui 0.1.12 parsed 606 -> 607, and `backend/macos/macos_services.mbt`
# parses whole for the first time. 48 sites corpus-wide, 32 in moui across 16 files;
# `_verify/pkg_head_impact.ps1` is the probe that produced "one file blocked".
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0456' -Target 'js' -Mutations @(

  # M1 IS THE GATE. Without the branch the `.Type` segment survives, which is the
  # defect. Note that `first_error` is the WRONG witness on its own: a reader that
  # consumed nothing also reports an error, and that is how the original pinned
  # reason survived. The named test asserts the statements AFTER the pattern survive,
  # which no amount of consuming nothing can fake.
  @{
    Name = 'M1 the at-head consumes nothing, so .Type::Ctor survives'
    File = $PARSER
    Find = @'
    if head.has_prefix("@") && self.at(TDot) {
      let _ = self.bump()
      if self.peek_name() != "" {
        let _ = self.bump()
      }
    }
'@
    Repl = ''
    MustRed = 'package-qualified head costs no statement after it'
  }

  # M2 THE TRIGGER IS GONE. Same verdict as M1 by a different route -- the branch
  # still exists but never fires. Keeping both is what stops a later edit that
  # "simplifies" the condition into something equivalent-looking but inert.
  @{
    Name = 'M2 the at-head trigger no longer matches'
    File = $PARSER
    Find = 'if head.has_prefix("@") && self.at(TDot) {'
    Repl = 'if head.has_prefix("#") && self.at(TDot) {'
    MustRed = 'package-qualified is pattern head parses'
  }

  # M3 AND M4 ARE DECLARED SURVIVORS, and the reason is a property of the LEXER that
  # no test in this repository could have caught.
  #
  # `@pkg` lexes as ONE `TName` with the `@` inside the name string, so
  # `@pkg.Type::Ctor` reaches this branch as `TName("@pkg")`, `TDot`,
  # `TName("Type")`, `TColon`, `TColon`, `TName("Ctor")`. The token after an `@`-head
  # is therefore a `.` in every shape the grammar admits -- there is no
  # `@pkg` + `(` form, because a constructor written that way still has the dot.
  # `self.at(TDot)` is consequently always true here and cannot be made false.
  #
  # Same for the inner `peek_name() != ""`: it guards `@pkg.` followed by a
  # non-name, which no valid source contains.
  #
  # The first draft of this gate wrote M3 expecting the control
  # "an at-qualified head with no type segment is untouched" to kill it. That test
  # passes WITH the guard removed, and the reason it cannot discriminate is worth
  # recording rather than papering over with a second assertion that also passes.
  # Declared, argued, and kept -- the 0436 M3 precedent: a guard nothing can observe
  # should say so out loud instead of growing a test to make it look load-bearing.
  @{
    Name = 'M3 the type-segment guard is dropped'
    File = $PARSER
    Find = 'if head.has_prefix("@") && self.at(TDot) {'
    Repl = 'if head.has_prefix("@") {'
    Expect = 'SURVIVED'
    Prove = 'The lexer folds `@pkg` into ONE TName, so an at-head is always followed by a `.`; self.at(TDot) cannot be false here. Unobservable by construction, not under-tested.'
  }

  @{
    Name = 'M4 the empty-name guard after the dot is dropped'
    File = $PARSER
    Find = @'
      let _ = self.bump()
      if self.peek_name() != "" {
        let _ = self.bump()
      }
    }
'@
    Repl = @'
      let _ = self.bump()
      let _ = self.bump()
    }
'@
    Expect = 'SURVIVED'
    Prove = 'Guards `@pkg.` followed by a non-name, which no valid source contains. Unobservable by construction, not under-tested.'
  }
)

Write-MutationGateVerdict -Name '0456'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

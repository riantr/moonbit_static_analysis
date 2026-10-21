# 0.4.22 mutation gate.
#
# Eight mutations over the two changes, and the set is deliberately not
# one-per-fix: a gate that only removes each guard in turn cannot tell "this is
# the protection" from "something else happens to protect the same line".
#
#   M1  param_index never matches        -> named matching silently off, back to
#                                           positional; the corpus shape reports
#                                           three argument mismatches again
#   M2  `name = value` label not recorded-> the ordinary named-argument path stops
#                                           naming a parameter
#   M3  the `x~` label not recorded      -> the shorthand stops naming a parameter
#   M4  a positional argument pushes no label -> the two parallel arrays fall out
#                                           of step and every later argument
#                                           mis-indexes
#   M5  `Int32` dropped from ann_to_ty   -> the annotation reads Unknown, which is
#                                           always safe and always wrong
#   M6  the arity threshold loosened     -> the positional arity check goes quiet
#   M7  the `all_positional` gate removed-> EXPECTED TO SURVIVE. No unit test can
#                                           see it; see the note at M7.
#   M8  method-call labels dropped       -> EXPECTED TO SURVIVE. infer discards
#                                           EMethodCall labels entirely.
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as
# a failure so that a pattern that stops matching cannot pass silently.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0422.ps1

# -----------------------------------------------------------------------------
# CONVERTED to ``_verify/mutate_lib.ps1``. This gate carried its own runner with
# the SHA256 restore and the `Total tests:` COMPILE-ERR judgement; what it lacked
# was a green BASELINE, PRE-FLIGHT, and line-ending normalisation. The prose above
# is VERBATIM and each mutation keeps the comment block that argued for it.
#
# The call arguments were lifted out of the original file with the PowerShell AST
# parser, not retyped. The patterns are multi-line with load-bearing indentation,
# and a transcription slip would not fail loudly -- it would make the pattern stop
# matching, which this harness reports as a NO-OP on a mutation whose real anchor
# is fine. That is a bug indistinguishable from a rotted anchor, so the conversion
# does not create one.
#
# The target is now PINNED to wasm. This gate ran bare `moon test`, which resolved
# through `preferred_target = "wasm"` in `moon.mod` -- 514 tests rather than the
# 442 the js target runs. The scope of the whole gate therefore depended on a field
# in the module manifest rather than on anything in this script.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$mutations = @(
  # --- M1: param_index never finds its label ----------------------------------
  # The whole change in one edit: with no label ever resolving, every argument
  # falls back to its index and `moui core/gesture.mbt:754`'s shape reports three
  # argument mismatches -- `group` on `shortcut`, `description` on `enabled`, and
  # `shortcut` on `group`. This is the pre-0.4.22 behaviour, exactly.
  @{
    Name = 'M1 param_index never matches'
    File = 'src\types\infer.mbt'
    Find = @'
for i, n in pnames {
    if n == label {
      return Some(i)
    }
  }
  None
'@
    Repl = @'
for i, n in pnames {
    if n == "zzz_never_a_label" {
      return Some(i)
    }
  }
  None
'@
  }

  # --- M2: the `name = value` label is not recorded ---------------------------
  # The ordinary named-argument path, as opposed to the shorthand. Distinct from
  # M1 because it breaks the WRITER, not the reader: `param_index` is still
  # correct, it is simply handed `""` for every argument.
  @{
    Name = 'M2 name=value label not recorded'
    File = 'src\parser\parser.mbt'
    Find = @'
        } else {
          args.push(self.parse_expr())
          labels.push(arg_label)
        }
'@
    Repl = @'
        } else {
          args.push(self.parse_expr())
          labels.push("")
        }
'@
  }

  # --- M3: the `x~` shorthand label is not recorded ---------------------------
  # `f(x~)` still parses and still passes the argument, so nothing about the call
  # looks broken; it simply stops naming a parameter. The reordered-shorthand test
  # is the only thing that can see it, and only because that fixture puts the
  # shorthand at an index that does not belong to it.
  @{
    Name = 'M3 tilde shorthand label not recorded'
    File = 'src\parser\parser.mbt'
    Find = @'
if labels[labels.length() - 1] == "" {
        labels[labels.length() - 1] = self.name_at(arg_start)
      }
'@
    Repl = @'
if labels[labels.length() - 1] == "zzz_never_a_label" {
        labels[labels.length() - 1] = self.name_at(arg_start)
      }
'@
  }

  # --- M4: a positional argument pushes no label ------------------------------
  # The parallel-array invariant. `args` and `labels` must grow together at every
  # push; a shorter `labels` does not fail loudly, it makes `labels.get(i)` return
  # None for every argument after the gap, which reads as "positional". So the
  # fixture that only ever names arguments still catches it -- the second and
  # later arguments silently lose their labels.
  @{
    Name = 'M4 positional argument pushes no label'
    File = 'src\parser\parser.mbt'
    Find = @'
    } else {
      args.push(self.parse_expr())
      labels.push("")
    }
    // `f(x~)`
'@
    Repl = @'
    } else {
      args.push(self.parse_expr())
    }
    // `f(x~)`
'@
  }

  # --- M5: Int32 dropped from the annotation reader ---------------------------
  # The SAFE wrong answer. Unknown is assignable everywhere the lens is concerned,
  # so nothing reports, nothing crashes, and the reader looks like it is simply
  # conservative. Only the unit test that compares `ann_to_ty("Int32")` with
  # `TInt` directly can tell it apart from that.
  @{
    Name = 'M5 Int32 dropped from ann_to_ty'
    File = 'src\types\types.mbt'
    Find = @'
"Int" | "Int32" | "int" => TInt
'@
    Repl = @'
"Int" | "int" => TInt
'@
  }

  # --- M6: the arity threshold loosened ---------------------------------------
  # One extra argument of slack. Settled against `moon check`, which rejects a
  # call that passes more arguments than the function declares (error 4080), so
  # the check should be reporting the excess, not tolerating it.
  @{
    Name = 'M6 arity threshold loosened'
    File = 'src\types\infer.mbt'
    Find = @'
if all_positional && args.length() > params.length() {
'@
    Repl = @'
if all_positional && args.length() > params.length() + 1 {
'@
  }

  # --- M7: the `all_positional` gate removed ----------------------------------
  # EXPECTED TO SURVIVE, and this is a measured result rather than a missing test.
  #
  # The gate exempts label-addressed calls from the arity check. Removing it
  # cannot turn any unit test red, because no test -- and no VALID MoonBit
  # program -- passes MORE named arguments than the function declares. Settled
  # against `moon check` on 0.1.20261012: a duplicate label is error 4084 and a
  # label naming no parameter is error 4085, so every shape the gate covers is a
  # compile error the toolchain already reports.
  #
  # What the gate actually costs was measured on the six corpora rather than
  # assumed: across 12,428 files it changes exactly ONE finding, an arity report
  # in `moui backend/web/web_host.mbt` at a call past that file's
  # reliable-region boundary, so it lands in the `unreliable` bucket and is never
  # shown as a result. That one could not be confirmed as a true positive, and an
  # argument-COUNT check is exactly where a misread cross-file signature
  # manufactures a false positive.
  #
  # So: recorded honestly as SURVIVED. Writing a test that pins a behaviour no
  # valid program exhibits would make this gate green and the test suite weaker.
  @{
    Name = 'M7 all_positional arity gate removed'
    File = 'src\types\infer.mbt'
    Find = @'
let all_positional = labels.is_empty() ||
            labels.every(fn(l) { l == "" })
'@
    Repl = @'
let all_positional = true
'@
    Expect = 'SURVIVED'
    Prove = @'
Measured on the six corpora rather than assumed: across 12,428 files the arity gate
changes exactly ONE finding, an arity report in `moui backend/web/web_host.mbt` at a
call past that file's reliable-region boundary, so it lands in the `unreliable`
bucket and is never shown as a result. Every shape the gate covers is a compile
error the toolchain already reports (duplicate label 4084, unknown label 4085).
Writing a test that pins a behaviour no valid program exhibits would make this
gate green and the test suite weaker.
'@.Replace("`r`n", "`n")
  }

  # --- M8: method-call labels dropped -----------------------------------------
  # EXPECTED TO SURVIVE for a different reason, and this one is a real gap rather
  # than a deliberate leniency. `EMethodCall` carries labels now, but infer
  # discards them (`EMethodCall(base, _, args, _)`) because method arguments are
  # not type-checked at all in this model -- there is no receiver signature to
  # check them against. So the labels are parsed, carried, and ignored, and no
  # mutation of them is observable. Recorded rather than papered over: the way to
  # kill it is a method-receiver signature, which is a larger change than this
  # release.
  @{
    Name = 'M8 method-call labels dropped'
    File = 'src\parser\parser.mbt'
    Find = @'
e = { span: csp, kind: @ast.EMethodCall(base, m, args, labels), }
'@
    Repl = @'
e = { span: csp, kind: @ast.EMethodCall(base, m, args, ["", "", "", "", "", ""]), }
'@
    Expect = 'SURVIVED'
    Prove = @'
A real gap, not a deliberate leniency. `EMethodCall` carries labels now, but infer
discards them (`EMethodCall(base, _, args, _)`) because method arguments are not
type-checked at all in this model -- there is no receiver signature to check them
against. The labels are parsed, carried, and ignored, so no mutation of them is
observable. The way to kill it is a method-receiver signature, which is a larger
change than this release.
'@.Replace("`r`n", "`n")
  }

)

Invoke-MutationGate -Name '0422' -Target 'wasm' -Mutations $mutations
Write-MutationGateVerdict -Name '0422 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

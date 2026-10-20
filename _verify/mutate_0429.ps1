# 0.4.29 mutation gate.
#
# This file is DATA ONLY. The harness lives in `_verify/mutate_lib.ps1`, which is
# where the rules are enforced -- green baseline first, COMPILE-ERR judged by the
# absence of a `Total tests:` line, NO-OP counted as a failure, every restore proven
# by SHA256, and `Expect='SURVIVED'` for the one mutation that genuinely is
# unobservable. Thirteen of the fourteen gates in this repo did not have those
# guards, and 0429 once reported a false kill because its killing tests were failing
# on clean code; a gate that carries its own copy of the harness is a gate that can
# be written without them.
#
# The five mutations, over one idea: `as` is an OPERATOR in expression position, the
# parser must consume it, and the three lenses must each keep working on what is
# left. Each targets a DIFFERENT piece, because a gate that only reverts the whole
# fix cannot tell whether the tests pin the parser rule or the lens wiring.
#
#   M1  revert the parser branch          is the `as` production load-bearing?
#   M2  walk stops walking the operand    does the fix trade one FP for another?
#   M3  infer stops typing the operand    is checking inside a cast preserved?
#   M4  interp stops evaluating it        declared survivor -- argued below
#   M5  parser drops the target type      is the `as` rule bounded?
#
# M2 is the one that matters most. Removing the false positive is easy; doing it by
# not looking at the operand would also make every parameter read only inside a cast
# look unused. The suite must go red for the second reason too.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0429.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$WALK   = 'src\walk\walk.mbt'
$INFER  = 'src\types\infer.mbt'
$INTERP = 'src\interp\interp.mbt'

$mutations = @(
  # --- M1: revert the parser branch -------------------------------------------
  # The postfix loop breaks on `as` again, exactly as before 0.4.29. The leftover
  # `as` becomes the next statement and the binding walk resolves it as a name.
  @{
    Name = 'M1 revert: the parser has no production for `as`'
    File = $PARSER
    Find = @'
    if self.at_name("as") {
      let asp = self.span()
      let _ = self.bump()
      // THE REGEX CAPTURE, `re"..." as name`. The operand is a REGEX LITERAL,
      // and that is what tells a capture from a CAST: `x as Int` casts a value
      // to a type, and `re"^a" as cap` binds `cap` to the text the group
      // captured.
      //
      // The corpus shape is `async 0.22.4 src/http/request.mbt:59-65`:
      //
      //     (re".*" as host) + (re":" ...) + (re"[0-9]+" as port_str)
      //
      // and the names those two capture are READ ten lines later. Read as a
      // CAST -- which is what this arm did -- the name was consumed as a TYPE
      // and the binding was lost, so `port_str` was reported `undefined name`
      // on code `moon check` compiles.
      //
      // NOT DONE, AND SAID SO: the LABELLED capture, `as raw, after=rest`. It
      // is written in `moonbitlang/lexer 0.4.0` and `moonbitlang/json5 0.5.5`
      // -- neither is a PINNED corpus -- and adding a shape with no evidence of
      // it being in the measured corpora is the habit this increment exists to
      // avoid. Recorded as a gap rather than guessed at.
      let capture = match e.kind {
        @ast.ERegex(_) => self.peek_name() != ""
        _ => false
      }
      if capture {
        let (n, _) = self.expect_name("capture name")
        e = { span: asp, kind: @ast.EAsBind(e, n), }
        continue
      }
      let _ = self.type_annotation()
      e = { span: asp, kind: @ast.ECast(e), }
      continue
    }
'@
    Repl = ''
  }

  # --- M2: walk stops walking the operand -------------------------------------
  # The cast still parses and still silences `undefined name 'as'`; only the operand
  # is dropped. This is the mutation that would trade one false positive for another,
  # and only the "parameter read only inside a cast" test sees it.
  @{
    Name = 'M2 walk no longer walks the cast operand'
    File = $WALK
    Find = '    ECast(base) => self.walk_expr(base)'
    Repl = '    ECast(_) => ()'
  }

  # --- M3: infer stops typing the operand -------------------------------------
  # The cast returns TUnknown either way, so the RESULT is unchanged; what is lost
  # is every finding inside the operand. Only the ArgTypeMismatch test sees it.
  @{
    Name = 'M3 infer no longer types the cast operand'
    File = $INFER
    Find = @'
    ECast(base) => {
      let _ = self.ty_of(base, TUnknown)
      TUnknown
    }
'@
    Repl = '    ECast(_) => TUnknown'
  }

  # --- M4: interp stops evaluating the operand --------------------------------
  # DECLARED SURVIVOR, and it is not claimed equivalent over the input space -- that
  # was not proven and is not asserted. What is measured: `_verify/probe_0429_m4.ps1`
  # applies this mutation, rebuilds, and diffs the analyzer's real output on five
  # programs (an `is` binding inside a cast operand, the same without a cast, a cast
  # in a called function, an unbound read in a called function, and an `is` binding
  # plus an unbound read). All five are byte-identical with and without it.
  @{
    Name = 'M4 interp no longer evaluates the cast operand'
    File = $INTERP
    Expect = 'SURVIVED'
    Prove = 'probe_0429_m4.ps1: five programs, byte-identical output either way'
    Find = @'
    ECast(base) => {
      let _ = self.eval(base, env)
      AAny
    }
'@
    Repl = '    ECast(_) => AAny'
  }

  # --- M5: the parser drops the target type -----------------------------------
  # `as` is consumed but `&Trait` is not, so the stream is left mid-type. This is
  # the boundary the whole branch rests on.
  @{
    Name = 'M5 the parser stops consuming the cast target type'
    File = $PARSER
    Find = @'
      let _ = self.type_annotation()
      e = { span: asp, kind: @ast.ECast(e), }
'@
    Repl = @'
      e = { span: asp, kind: @ast.ECast(e), }
'@
  }
)

Invoke-MutationGate -Name '0.4.29' -Target 'js' -Mutations $mutations
Write-MutationGateVerdict -Name '0.4.29 mutation gate'
# The verdict function RETURNS NOTHING -- it writes its messages, and a function
# that both writes and returns hands the caller an Object[] instead of a boolean.
# So the exit status is decided from the failure list directly.
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
Write-Output ''
Write-Output 'ON THE SURVIVOR. M4 is expected to survive and is not counted as a failure.'
Write-Output 'It is NOT claimed equivalent over the whole input space. What is measured is that'
Write-Output 'the analyzer output is byte-identical either way on five programs, for the two'
Write-Output 'reasons recorded at the mutation. The `eval` is kept because every sibling arm'
Write-Output '(EField, ETupleField, EStruct, EComp, EMethodCall) evaluates its operands --'
Write-Output 'consistency with them is a reason, not a proof.'
exit 0
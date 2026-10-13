# 0.4.24 mutation gate.
#
# Seven mutations over one change: `raise` as an EXPRESSION. 0.4.23 handled the
# same clause in the two positions it appears on a FUNCTION (the signature
# annotation and a function type's return annotation); this release handles the
# statement that actually performs the raising.
#
# The set is deliberately spread across the four places the statement has to be
# right, because a raise can be "handled" in the parser and still be wrong in a
# lens -- and the failure modes are opposite. M3 and M4 each make the payload
# stop being analysed, which makes the analyzer QUIETER; M5 and M6 make it
# terminate when it should not (or with the wrong value), which makes it LOUDER
# and wrong. A gate that only tested the first kind would pass a change that had
# simply stopped looking inside error construction.
#
#   M1  the `raise` dispatch removed      -> back to `undefined name 'raise'`,
#                                             65 false positives across the six
#                                             corpora come straight back
#   M2  the payload never parsed          -> `SRaise(None)` always; the error
#                                             value is dropped at the cursor
#   M3  walk stops walking the payload    -> a real defect INSIDE a raise goes
#                                             silent (the quiet failure)
#   M4  the type lens stops type-checking the payload -> same, one lens down
#   M5  a raise does not terminate       -> the frame stays live and the
#                                             statements after a raise look
#                                             reachable (the loud failure)
#   M6  a raise pushes a value            -> the raise invents a return value
#                                             `raise` never produces
#   M7  the termination-set guard removed -> a bare `raise` at the end of a block
#                                             tries to read the NEXT statement
#                                             as its payload
#
# Same rules as every prior gate: COMPILE-ERR is the absence of a `Total tests:`
# line, never a grep; every restore is byte-identical by SHA256; NO-OP counts as
# a failure so that a pattern that stops matching cannot pass silently.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0424.ps1

# -----------------------------------------------------------------------------
# CONVERTED to ``_verify/mutate_lib.ps1``. Like 0.4.23's, this gate was already
# close -- its runner had the SHA256 restore, the ``Total tests:`` COMPILE-ERR
# judgement, NO-OP-as-failure and ``Expect`` support -- and was written as
# function-per-mutation rather than a table. The prose above is VERBATIM; the seven
# calls were transposed into a table, arguments unchanged.
#
# What it was missing, and what the harness adds:
#
#   - a green BASELINE, ASSERTED. The old runner went straight to the first
#     mutation. With no baseline, a suite that was already red produced seven
#     verdicts and -- because every mutation would then also be red -- seven
#     apparent kills. The same false-green shape 0.4.29 hit in the other direction.
#   - PRE-FLIGHT, so a pattern that no longer matches stops the gate before any
#     mutation is applied rather than being discovered one at a time.
#
# The original runner's line-ending handling is kept by the harness for the reason
# its comment gave: ``moon fmt`` rewrote the tree from LF to CRLF once, a literal
# multi-line pattern then matched NOTHING, and every mutation reported NO-OP. The
# harness normalises to LF and writes back in whatever style the file already used.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$WALK   = 'src\walk\walk.mbt'
$INFER  = 'src\types\infer.mbt'
$INTERP = 'src\interp\interp.mbt'

$mutations = @(
  # M1 -- the statement dispatch. Without it `raise` falls through to the expression
  # reader; 65 findings across the corpora, 56 of them proton's.
  @{
    Name = 'M1 raise statement dispatch removed'
    File = $PARSER
    Find = 'if self.at_name("raise") {
    return self.parse_raise_stmt()
  }
'
    Repl = ''
  }

  # M2 -- `SRaise(None)` unconditionally. The error value is left at the cursor and
  # the next statement gets read as if it were the payload.
  @{
    Name = 'M2 the raise payload never parsed'
    File = $PARSER
    Find = '{ span: sp, kind: @ast.SRaise(Some(self.parse_expr())), }
}'
    Repl = '{ span: sp, kind: @ast.SRaise(None), }
}'
  }

  # M3 -- THE QUIET FAILURE. `raise` must not become the one place in the language
  # where a real defect goes unnoticed, so `raise E(nosuchfunction())` still has to
  # find `nosuchfunction`. A mutation that merely stops looking is the failure mode
  # a coverage number cannot see, which is why this is its own gate rather than
  # folded into M2.
  @{
    Name = 'M3 walk stops walking the raise payload'
    File = $WALK
    Find = 'SRaise(e) =>
      match e {
        Some(x) => self.walk_expr(x)
        None => ()
      }'
    Repl = 'SRaise(_) => ()'
  }

  # M4 -- the same quiet failure one lens down. M3 and M4 are separate because a
  # change could plausibly fix one and not the other, and only one of them would
  # fail a test that looked at findings from a single lens.
  @{
    Name = 'M4 type lens stops checking the payload'
    File = $INFER
    Find = 'SRaise(e) =>
      match e {
        Some(x) => {
          let _ = self.ty_of(x, TUnknown)
        }
        None => ()
      }'
    Repl = 'SRaise(_) => ()'
  }

  # M5 -- THE LOUD FAILURE, and the one with real corpus consequences. `SRaise`
  # exists precisely because `SReturn` would be wrong here, and the observable
  # difference is the terminator: with this arm gutted the statements after a
  # `raise` look reachable and every dead-code report after a raise disappears.
  @{
    Name = 'M5 a raise does not terminate the frame'
    File = $INTERP
    Find = 'SRaise(_) => {
      self.ret_vals.push(ABottom)
      self.flow = FReturn
    }'
    Repl = 'SRaise(_) => ()'
  }

  # M6 -- a raise produces NO value. Pushing anything else invents a return value
  # the source never had, and it lands in `ret_vals`, which is where the rendered
  # signature's return type comes from.
  @{
    Name = 'M6 a raise pushes a value'
    File = $INTERP
    Find = 'SRaise(_) => {
      self.ret_vals.push(ABottom)
      self.flow = FReturn
    }'
    Repl = 'SRaise(_) => {
      self.ret_vals.push(AAny)
      self.flow = FReturn
    }'
  }

  # M7 -- the termination-set guard. A bare `raise` with nothing after it -- on its
  # own line, or closing a block with no semicolon -- must produce `SRaise(None)`.
  # Without the guard the reader goes on to parse whatever follows as the error
  # value, which in the corpus is the next real statement.
  @{
    Name = 'M7 the bare-raise termination guard removed'
    File = $PARSER
    Find = 'if self.at(TNewline) || self.at(TSemi) || self.at(TRBrace) || self.at(TEOF) {
    return { span: sp, kind: @ast.SRaise(None), }
  }
'
    Repl = ''
  }
)

Invoke-MutationGate -Name '0.4.24' -Target 'js' -Mutations $mutations
Write-MutationGateVerdict -Name '0.4.24 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

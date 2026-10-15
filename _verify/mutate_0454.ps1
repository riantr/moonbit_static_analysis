# Mutation gate 0454 -- `label?=value` in a call argument.
#
# On the harness: no runner of its own, all rules from `_verify/mutate_lib.ps1`.
# And rule 7 is the one to keep in mind here: nothing else may touch
# `src/parser/parser.mbt` while this runs.
#
# EVERY `Find`/`Repl` BELOW IS PURE ASCII, which is a constraint discovered the hard
# way in 0453: PowerShell 5.1 reads a BOM-less .ps1 as ANSI, so a non-ASCII literal
# inside a here-string is mangled on the way in and the PREFLIGHT reports a MISS for
# a pattern that is sitting in the source verbatim. The prose lives in the comments;
# the patterns stay ASCII.
#
# THE DEFECT. After 0453 moui 0.1.12 could not finish reading 6 files, and the
# largest by-reason bucket was `unexpected token `,``. Three of them were one
# construct -- `views/popover/sheet.mbt:25`, plus the same helper written twice at
# `backend/host_text_field_test_helper_test.mbt:31` and
# `backend/common/input/text_field_test_helper_test.mbt:31`:
#
#     border?=normal_border,
#
# The complaint named a COMMA, three tokens from the cause. `parse_call_args`
# handles two shorthands, both AFTER the argument is parsed: `f(x~)` at the `TTilde`
# test and `f(x?)` at the `TQuestion` test. Neither is followed by an `=`, so the
# sequence for `border?=normal_border` was: the `TAssign` test is FALSE (the next
# token is `?`), `p` is restored, `border` is read as a positional name, the
# `TQuestion` shorthand consumes the `?` as if the argument ENDED, the comma test
# finds the `=` that the first test skipped over, and the loop BREAKS.
#
# Settled in `_verify/settle_0454_label_qmark_eq.ps1`, 9/9 with a positive control.
# The row that decided the fix:
#
#     border?=v   against  border? : Int   ACCEPT
#     border?=v   against  border~ : Int   REJECT(4141) "this form of application
#                                            is invalid for argument border~, because
#                                            it is not declared with border? : _"
#
# The `?` CARRIES MEANING -- a `name? : T` parameter has type `T?` -- so `?=` is not
# sugar for `=`. M4 exists for exactly that.
#
#   M1  the branch is removed -- the original behaviour.
#   M2  the `=` is not required, so `border? value` reads as `border=value`.
#   M3  the value is consumed and DISCARDED: read past without being analysed.
#   M4  the `?` is dropped from the label, desugaring `?=` into `=`.
#   M5  the lookahead is widened to "a `?` means ?=", so `x?` no longer ends the
#       argument -- the over-correction the settle's `qmark_then_name` row forbids.
#
# M3 is the one worth having. M1, M2, M4 and M5 are all "the branch is wrong"; M3 is
# "the branch is right and the work behind it is skipped", and it produces neither a
# parse error nor a lost notice. Only the `UnusedLocal` assertion catches it.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name 'M1..M5' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the ?= branch is removed (the original behaviour)'
    File = 'src\parser\parser.mbt'
    Find = @'
      if self.at(TQuestion) && self.toks[self.p + 1] == TAssign {
        let _ = self.bump()
        let _ = self.bump()
        args.push(self.parse_expr())
        labels.push(arg_label)
      } else if self.at(TAssign) {
'@.Replace("`r`n", "`n")
    Repl = @'
      if self.at(TQuestion) && self.toks[self.p + 1] == TAssign {
        self.p = saved_p
        args.push(self.parse_expr())
        labels.push("")
      } else if self.at(TAssign) {
'@.Replace("`r`n", "`n")
    MustRed = '0454: a call mixing ~, ?, ?= and = arguments parses'
    Prove = @'
The state before this increment. Measured on moui 0.1.12 `views/popover/sheet.mbt`
and on two fixtures:

    border?=normal_border,   -> `unexpected token `,``

The complaint names a COMMA because that is where the loop finally notices it has
run out of argument, which is three tokens after the real failure and on the far
side of the `?` that caused it. The bucket label is a statement about where the
parser gave up, not about what was wrong -- the same shape as 0452's quoted-key
bucket and 0453's `expected ')'`.

`self.p = saved_p` rather than `if false`, so the code stays compiled and the
mutation measures the DECISION without leaving an arm the compiler can warn about.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M2 the = after ? is not required'
    File = 'src\parser\parser.mbt'
    Find = @'
      if self.at(TQuestion) && self.toks[self.p + 1] == TAssign {
        let _ = self.bump()
        let _ = self.bump()
'@.Replace("`r`n", "`n")
    Repl = @'
      if self.at(TQuestion) {
        let _ = self.bump()
'@.Replace("`r`n", "`n")
    MustRed = '0454: a question mark followed by a name is not ?='
    Prove = @'
THE TOLERANT IMPLEMENTATION, and it is the obvious one: a `?` introduces the
optional argument, whatever follows it.

The settle forbids it:

    border?v   REJECT(3002) "unexpected token id, you may expect `,` or `)`"

`?` in argument position is either the END of an argument (`x?`) or the start of
`?=value`. It never prefixes an expression, and that is precisely what makes the
two-token lookahead safe rather than clever.

It also breaks the sibling shorthand: `x?` would consume the `?`, then read the NEXT
argument's name as this argument's value.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M3 the value is consumed but not analysed'
    File = 'src\parser\parser.mbt'
    Find = @'
        let _ = self.bump()
        let _ = self.bump()
        args.push(self.parse_expr())
        labels.push(arg_label)
'@.Replace("`r`n", "`n")
    Repl = @'
        let _ = self.bump()
        let _ = self.bump()
        args.push({ span: self.span(), kind: @ast.EBigInt, })
        labels.push(arg_label)
'@.Replace("`r`n", "`n")
    MustRed = '0454: the value after ?= is analysed, not stepped over'
    Prove = @'
THE MUTATION THAT MATTERS MOST, because it is the only one a parse-error count
cannot see. The tokens are consumed in order, so there is no parse failure and no
lost notice -- the file reads clean and reports exactly what it reported before.

What is lost is the VALUE. The fixture binds `normal_border` and uses it only as the
`?=` value; read past rather than read, that binding is dead and the walk reports
`unused local` for a local the program uses. The test pins that count at zero,
which is why it exists.

This is the same shape as M3 of 0452 (the map literal's value discarded) and M3 of
0453 (the function literal's body skipped): the pipeline stays green and the
analyzer quietly stops looking at something.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M4 the ? is dropped from the label'
    File = 'src\parser\parser.mbt'
    Find = @'
        args.push(self.parse_expr())
        labels.push(arg_label)
      } else if self.at(TAssign) {
'@.Replace("`r`n", "`n")
    Repl = @'
        args.push(self.parse_expr())
        labels.push("")
      } else if self.at(TAssign) {
'@.Replace("`r`n", "`n")
    MustRed = '0454: the ?= argument carries the label ''border'', not a blank one'
    Prove = @'
THE OVER-CORRECTION, and the direction a reader reaches after reading the settle:
`?=` is just `=` with an optional target, so record the argument positionally.

THE MUST-RED IS NOT IN `src/pipeline`, AND THAT IS THE FINDING. This mutation
SURVIVED the first version of this gate: the 0454 tests were all written through
`@pipeline.run`, asserting findings, and nothing on the pipeline path READS the
label. `parse_call_args` returns `(args, labels)`, the labels go into `ECall`, and
neither the structural walk nor the type lens consults them for any finding these
fixtures trigger -- so a blank label changed no count and 623/623 stayed green.

That is a property of the ANALYZER, not of the parser: the parser's own tree carries
the label faithfully. So the assertion moved to `src/parser/parser_0454_test.mbt`
and reads `ECall`'s third field directly, the way `parser_0430_test.mbt` already
does for `x~` and `x?`.

THE SAME MUTATION UNDER A DIFFERENT MUST-RED IS WORTH NAMING, because it is the
shape that got the first version wrong twice over. Asserting "the call parses"
passes; asserting a finding COUNT passes. Neither is evidence about a label.

WHY THE LABEL MATTERS ANYWAY, which is the part the settle gives and the corpus does
not: the type lens maps arguments to parameters BY LABEL whenever any argument in
the call is named. `views/popover/sheet.mbt:21-29` mixes `~`, `?` and `?=value` in one
call, so a blank label here would be matched positionally against the wrong
parameter of a six-parameter function. That the lens does not yet consult labels
on this path is a known gap, not a reason to record the wrong value.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M5 the lookahead is widened to any question mark'
    File = 'src\parser\parser.mbt'
    Find = @'
      if self.at(TQuestion) && self.toks[self.p + 1] == TAssign {
'@.Replace("`r`n", "`n")
    Repl = @'
      if self.at(TQuestion) || self.toks[self.p + 1] == TAssign {
'@.Replace("`r`n", "`n")
    MustRed = '0454: the x~ and x? shorthands still parse'
    Prove = @'
THE SECOND OVER-CORRECTION, in the other direction: if `?=` is a real form, read a
`?` as one whenever it appears at all.

`x?` is then gone. The `TQuestion` shorthand further down the loop is what ends an
optional-argument shorthand, and this arm now consumes the `?` first -- so
`sink(border?)` reads whatever follows as a VALUE instead of forwarding the
enclosing `border`.

The settle row that forbids it is `ctl_question_shorthand`, which is ACCEPTed by the
toolchain. A fix that breaks it is not a more permissive parser; it is a different
language, and one this corpus uses constantly.
'@.Replace("`r`n", "`n")
  }
)

Write-MutationGateVerdict -Name '0454'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

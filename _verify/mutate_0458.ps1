# Mutation gate 0458 -- the ASYNC function type, `(async (A, B) -> R)?`.
#
# WHAT THIS PINS, AND WHY IT IS THE ONE THAT MATTERED. After 0456 and 0457,
# wzzc-dev/moui 0.1.12 stood at 607 of 608 files. This gate's increment takes it
# to 608/608 -- the last file that corpus could not finish reading.
#
#     PARSED 608/608 files understood (100.0%); 0 more read only up to their
#     first parse error
#     files=608 parsed=608 actionable=0 notices=4225 unreliable=0 withheld=0
#
# `unreliable` went 9 -> 0: the last PARTIAL file is gone, so every file in that
# corpus is now understood rather than read-until-some-error.
#
# THE DEFECT. `fn_type_annotation` bumped the `(` and handed `async` to
# `type_annotation()`, which took it as an ordinary type NAME. The parameter loop
# then broke on the `(` that followed it rather than on a comma, and
# `expect(TRParen)` reported `expected ')'`.
#
# THE GRAMMAR FACT, settled against the toolchain
# (`_verify/settle_0458_async_fn_type.ps1`, 7/7 with two failure-capable
# controls): the trailing `?` makes the RETURN type optional. It does NOT lift the
# group into a nullable function type:
#
#     fn build(f? : ((Int) -> Unit)? = None)                          ACCEPT
#     fn build(f? : ((Int) -> Unit)  = None)                          REJECT(4014)
#     fn build(launch_async? : (async (Int, Int) -> Unit)? = None)    ACCEPT
#
# => 判据: the obvious reading of a type annotation is not a measurement of it.
# `(async (A, B) -> R)?` reads like an optional async function and is not one; the
# toolchain reads `R?`. Three fixtures had to be corrected before any grammar was
# measured, and each correction first looked like a verdict ABOUT the grammar --
# two were call sites given the wrong return shape, and one confused an optional
# PARAMETER (`x?`) with a nullable TYPE (`T?`), which the corpus line has both of.
# The lesson is the one this repository keeps re-learning in a new costume: when a
# probe about the language disagrees with you, the probe is more likely to be right
# about the language and you are likely to be right about your fixture.
#
# THE `?` CLAUSE ALREADY EXISTED in this function before the increment. Only the
# `async` head was missing. That is worth writing down, because the tempting
# "fix" -- letting `async` fall through as any other type name -- is precisely the
# defect, and it would have left the corpus file unreadable while looking tidy.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

$HEAD = @'
  let mut out = if self.at_name("async") && self.lparen_at(self.p + 1) {
    let _ = self.bump() // async
    "async "
  } else {
    ""
  }
'@

Invoke-MutationGate -Name '0458' -Target 'js' -Mutations @(

  # M1 IS THE GATE. The head is gone, which is the pre-0458 parser verbatim.
  # `expected ')'` is a ParseError, which is exactly what `parse_failures` counts,
  # so the named test moves.
  @{
    Name = 'M1 the async head is removed entirely'
    File = $PARSER
    Find = $HEAD
    Repl = @'
  let mut out = ""
'@
    MustRed = '0458: an async function type is read as a type'
  }

  # M2 THE HEAD IS THERE BUT NEVER FIRES. Same verdict by a different route --
  # the code reads as correct and is inert. This is the mutation that catches an
  # edit which "simplifies" the lookahead into something equivalent-looking.
  @{
    Name = 'M2 the async head is inert'
    File = $PARSER
    Find = 'if self.at_name("async") && self.lparen_at(self.p + 1) {'
    Repl = 'if self.at_name("#async") && self.lparen_at(self.p + 1) {'
    MustRed = '0458: an async function type is read as a type'
  }

  # M3 THE LOOKAHEAD READS THE WRONG OFFSET. `self.p` is the cursor, on `async`;
  # `p + 1` is the `(` and `p + 2` is the first parameter. An off-by-one here is
  # the most likely way this head breaks later, and it compiles cleanly and reads
  # correctly -- the arithmetic is the whole content.
  @{
    Name = 'M3 the lookahead reads one token too far'
    File = $PARSER
    Find = 'self.lparen_at(self.p + 1)'
    Repl = 'self.lparen_at(self.p + 2)'
    MustRed = '0458: an async function type is read as a type'
  }

  # M4 THE NAME CHECK IS DROPPED, so the head keys on "the token after `(` is a
  # `(`" alone.
  #
  # DECLARED KILLED TO BE MEASURED, and the measurement is the interesting part:
  # the first run SURVIVED 648/648, which is what it would have taken to declare
  # this an unobservable guard. That declaration would have been wrong. A valid
  # MoonBit program satisfies the bracket-only shape --
  #
  #     fn f(g : (((Int)) -> Unit)) -> Unit { ignore(g) }
  #
  # ACCEPT, zero errors, `moon check` -- and after the outer `(` is bumped the
  # cursor is on `(` with the next token also `(`. The plain-fn control could not
  # see it, because in `((String) -> Int)?` the cursor lands on `String`.
  #
  # => 判据: "no test in the suite covers this" and "no program can reach this" are
  # different claims, and a survivor verdict is a claim about the second while the
  # evidence on hand only ever supports the first. When a mutation survives, the
  # question to ask is not "which test would catch this" but "is there an INPUT
  # that would" -- and here there was one, three parens deep.
  @{
    Name = 'M4 the head keys on the bracket alone, not on async'
    File = $PARSER
    Find = 'if self.at_name("async") && self.lparen_at(self.p + 1) {'
    Repl = 'if self.lparen_at(self.p + 1) {'
    MustRed = '0458: a nested parenthesised parameter is not read as an async head'
  }

  # M5 THE HEAD IS TAKEN BUT NOT RENDERED -- the `async ` prefix is dropped and the
  # token consumed all the same.
  #
  # DECLARED SURVIVED, and this time the claim behind it is measured rather than
  # asserted. The rendered annotation is consumed inside the parser and handed to
  # `ann_to_ty`, and it is not part of the pipeline result -- which is why two
  # end-to-end tests in this increment's first draft were deleted rather than
  # satisfied. The stronger question is whether the two renderings are
  # INDISTINGUISHABLE DOWNSTREAM, and `src/types/types_0458_test.mbt` answers it:
  # `ann_to_ty("async (Int, Int) -> Unit?")` is `TUnknown`, and a control in the
  # same file shows `ann_to_ty` does distinguish types, so the agreement is a
  # fact about this annotation rather than about the reader being the identity.
  #
  # Unknown silences every check downstream, so both renderings silence the same
  # checks and nothing observable can separate them. The day somebody teaches
  # `ann_to_ty` the `async` head, that test goes red ON PURPOSE and this row has
  # to become KILLED. The tripwire is the point; a survivor with no tripwire is
  # just an untested guard with a footnote.
  @{
    Name = 'M5 the head is consumed but the rendered prefix is dropped'
    File = $PARSER
    Find = $HEAD
    Repl = @'
  let mut out = if self.at_name("async") && self.lparen_at(self.p + 1) {
    let _ = self.bump() // async
    ""
  } else {
    ""
  }
'@
    Expect = 'SURVIVED'
    Prove = 'Unobservable by construction, and the claim is MEASURED, not argued: src/types/types_0458_test.mbt asserts ann_to_ty("async (Int, Int) -> Unit?") is TUnknown alongside a control showing ann_to_ty does distinguish types, so both renderings derive the same Ty and Unknown silences the same checks. The rendered string is not in the pipeline result at all. If an `async` case is ever added to ann_to_ty that test goes red and this row must become KILLED.'
  }
)

Write-MutationGateVerdict -Name '0458'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

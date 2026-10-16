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
#
# --- SUPERSEDED BY 0467, and the file now says so --------------------------
#
# 0467 found this head REDUNDANT and removed it, which cost this gate two rows and
# is the reason two of them are `Retired` rather than live. The history is worth
# keeping because the redundancy was not obvious -- it was a DEFECT that 0467's own
# mutation gate caught:
#
# The outer head consumed `async` and rendered the `async ` prefix into `out`,
# which was then handed on. 0467 added a shared `fn_type_body` and a new entry arm
# in `type_annotation` that reads the same forms -- so the parse reached the head
# twice and rendered it twice: `async (async (Int) -> Unit)?`. The pre-0458 fix had
# become an over-fix, and the second render is what 0467's M4 pins.
#
# => 判据: a gate row anchored to code a later increment DELETED must be retired with
# its successor named, not quietly re-aimed at whatever now happens to match. The
# reason strings below say where each property went, so a reader can tell "this guard
# moved" from "this guard quietly stopped existing".
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

  # M1 IS THE GATE, and it is RETIRED as of 0467 -- not because it stopped being
  # true, but because 0467 deleted the block it targeted.
  #
  # 0467 extracted `fn_type_body` and replaced this outer head with an entry arm in
  # `type_annotation` that RETURNS `fn_type_body("async ")` instead of accumulating
  # an `out` prefix string, so `$HEAD` no longer exists in that form. The gate's own
  # rule is to retire rather than invent an anchor to match, and there is nothing to
  # invent here: this row asked "what if the head were absent", and the head is now
  # the four-line arm at `src/parser/parser.mbt:1708`.
  #
  # THE PROPERTY IS NOT LOST, it moved, and it moved to a stronger pin than this row
  # was. M2, M3 and M4 below all anchor on that arm's condition line, so if the head
  # were ever deleted those anchors would miss and PREFLIGHT would fail the gate --
  # absence of the head is now a preflight failure rather than a mutation result.
  # 0467's own gate adds M1, "the bare `async (..)` entry arm is gone", KILLED by 20
  # named tests. Between the two, the head's existence is pinned three times over.
  @{
    Name = 'M1 the async head is removed entirely'
    File = $PARSER
    Retired = '0467 replaced the outer head this anchored to with an entry arm in type_annotation that returns fn_type_body("async ") directly, so the `let mut out = if ...` block no longer exists. The property moved rather than lapsed: M2/M3/M4 below anchor on that arm, so deleting the head now fails PREFLIGHT, and mutate_0467.ps1 M1 kills its removal against 20 named tests'
    Find = $HEAD
    Repl = @'
  let mut out = ""
'@
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
  #
  # NAMED-TEST POINTER RE-POINTED BY 0467, and the mutation is still KILLED. It kills
  # 2 tests either way; what 0467 changed is WHICH. This row's witness used to be the
  # three-paren form, and 0467 moved the head out of `fn_type_annotation` into
  # `type_annotation`, so a cursor sitting on `(` now goes down the parenthesised-fn-type
  # path and never reaches the mutated arm. The arm's live trigger became the case the
  # head is actually guarded on: a NAME followed by `(`. 0467's `canary_any_name` pins
  # exactly that -- `g : bogus (Int) -> Unit` must still be rejected with 3002, so a
  # head keyed on "any name then a parenthesised list" is caught there.
  #
  # So the witness that 0458 said was missing, three parens deep, arrived in the next
  # increment in a different spelling. The mutation is re-pointed at it, NOT retired:
  # a guard whose kill is still measured should keep being measured.
  @{
    Name = 'M4 the head keys on the bracket alone, not on async'
    File = $PARSER
    Find = 'if self.at_name("async") && self.lparen_at(self.p + 1) {'
    Repl = 'if self.lparen_at(self.p + 1) {'
    MustRed = '0467: a non-async name before a parameter list still reports'
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
  # M5 IS RETIRED AS OF 0467, and this one is worth reading twice, because its
  # PREMISE turned out to be false rather than merely stale.
  #
  # It was declared SURVIVED on the measured claim that the rendered `async `
  # prefix is unobservable downstream: `ann_to_ty("async (Int, Int) -> Unit?")` is
  # `TUnknown`, and Unknown silences the same checks either way. That was measured,
  # not argued, and it was correct WHEN IT WAS MEASURED.
  #
  # It is no longer true. The same prefix is now the ARGUMENT to `fn_type_body`, and
  # 0467's gate kills exactly this mutation: M4, "the new entry arm hands
  # `fn_type_body` an empty prefix", went red on 3 named tests in the release run
  # that retired this row. So the prefix became OBSERVABLE, and a row that declares
  # SURVIVED while the suite demonstrably kills the mutation is worse than no row --
  # it is a false "unobservable" sitting in a gate someone reads as evidence.
  #
  # This is also the answer to "the day somebody teaches `ann_to_ty` the `async`
  # head, that test goes red ON PURPOSE and this row has to become KILLED". Somebody
  # taught it, just not through `ann_to_ty`: the prefix is now read by the parser
  # itself, which is what made it observable.
  @{
    Name = 'M5 the head is consumed but the rendered prefix is dropped'
    File = $PARSER
    Retired = '0467 deleted the `let mut out` block this anchored to, and its declared SURVIVED verdict is now FALSE: the rendered prefix is the argument to fn_type_body and is observable, so mutate_0467.ps1 M4 (an empty prefix) is KILLED by 3 named tests. A retired row is not a weaker claim here -- the claim it made was superseded by a stronger pin'
    Find = $HEAD
    Repl = @'
  let mut out = if self.at_name("async") && self.lparen_at(self.p + 1) {
    let _ = self.bump() // async
    ""
  } else {
    ""
  }
'@
  }
)

Write-MutationGateVerdict -Name '0458'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

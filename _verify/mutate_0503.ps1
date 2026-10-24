# Mutation gate 0503 -- THE `?` MARKER ON A RAISE CLAUSE.
#
# WHAT THIS INCREMENT IS. `-> Int raise?` marks a raise as OPTIONAL, and the
# toolchain accepts it -- but the analyzer stopped at the `?` in every position
# except the function-TYPE one. The reach was 162 return-position sites in 31
# files, ALL of them in moonbitlang/core 0.1.20260920+7d59c7ec9, and zero in the
# other six corpora and zero in this analyzer's own source. Three real core
# files -- array.mbt, option.mbt, result.mbt -- scanned ALONE came back
# `PARSED 0/3 files understood (0.0%)` with the error `unexpected token `?``.
#
# THE RULE IS THE COMPILER'S, AND THE FIRST DRAFT OF THE SETTLE HAD IT WRONG.
# The question is not "does the analyzer read `?`" but "WHICH `?` is legal", and
# the answer is narrower than "after any raise clause":
#
#     -> Int raise?              ACCEPTED   the bare raise, marked optional
#     -> Int raise MyErr?        REJECTED   4032 + 3002 -- a typed raise has no
#                                               optional form
#     -> Int raise + nocancel?   REJECTED   3002 "unexpected token `?`"
#     -> Int noraise?            REJECTED   an optional marker on "does not
#                                               raise" is meaningless
#     -> Int nocancel?           REJECTED
#     -> Int! ?                  REJECTED   the short form has no optional form
#
# => THE `?` BELONGS TO A BARE `raise` AND TO NOTHING ELSE.
#
# THE SETTLE ITSELF CORRECTED ITS OWN PREMISE, twice, and both corrections are
# the reason this gate has the shape it has.
#
# 1. THE `?` WITH NO EFFECT CLAUSE. The first version of the settle had
#    `fn f() -> Int ? { 1 }` REJECTED and read that as "the toolchain refuses a
#    `?` with nothing to mark". The VERDICT was right and the REASON was wrong:
#    `-> Int ?` and `-> Int?` are THE SAME TOKENS, and `-> Int?` is the nullable
#    return type, which the toolchain ACCEPTS. The rejection was the BODY -- `1`
#    is not an `Int?` -- which is the type lens and not the grammar. A settle row
#    is not just a verdict; it is a CLAIM about why, and this one was measuring
#    the type lens while being read as measuring the grammar.
#
# 2. THE FUNCTION-TYPE POSITION WAS NOT SETTLED AT ALL, and it turned out to be
#    the harder half. The `?` there does TWO jobs:
#
#       (Int) -> Int raise?      the OPTIONAL-RAISE marker
#       ((Int) -> Int)?          the NULLABLE marker on a parenthesised group
#
#    The first draft of the fix narrowed the function-type `?` to "a bare raise
#    only" and FOURTEEN EXISTING TESTS WENT RED, because the nullable group is a
#    `?` with NO clause in front of it. So the rule is asked about the CLAUSE and
#    not about the `?`, and the nullable group is pinned here (M4) as well as in
#    `parser_0503_test.mbt`.
#
# EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED, and the tests named are
# the ones that pin the rule. A mutation that kills some other test is not
# evidence.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE and every one of them is
# UNIQUE in its file -- the harness mutates the FIRST match, and a second copy
# would never be verified. Three of them were re-anchored BY this increment, in
# gates 0423, 0453 and 0471, and the reasons are in those files.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0503' -Target 'wasm' -Mutations @(

  # M1 THE RETURN POSITION STOPS AT THE `?`. This is the increment itself: the
  # clause is read, the `?` is left in the token stream, and the body is read
  # against it -- `expected '{'`, the message that names a brace which was never
  # the problem. It is what made 162 return-position sites unreadable.
  @{
    Name = 'M1 the return position never consumes the `?`'
    File = $PARSER
    Find = @'
  let bare_raise = self.at_bare_raise()
  self.parse_raise_effect()
  if bare_raise && self.at(TQuestion) {
    let _ = self.bump()
  }
  (full, params, retann)
'@.Replace("`r`n", "`n")
    Repl = @'
  let bare_raise = self.at_bare_raise()
  self.parse_raise_effect()
  if bare_raise && self.at(TEOF) {
    let _ = self.bump()
  }
  (full, params, retann)
'@.Replace("`r`n", "`n")
    MustRed = '0503: a return annotation may carry `raise?`'
  }

  # M2 THE FUNCTION-LITERAL POSITION STOPS AT THE `?`. A third site, and not a
  # variant of the first: the literal's tail is read by `parse_fn_literal`, which
  # is a different function with its own reader. 0471's rows are the precedent --
  # the same construct spelled three ways is three places to forget it.
  @{
    Name = 'M2 the function-literal position never consumes the `?`'
    File = $PARSER
    Find = @'
  let bare_raise = self.at_bare_raise()
  self.parse_raise_effect()
  if bare_raise && self.at(TQuestion) {
    let _ = self.bump()
  }
  let (_, _) = self.parse_block(false)
'@.Replace("`r`n", "`n")
    Repl = @'
  let bare_raise = self.at_bare_raise()
  self.parse_raise_effect()
  if bare_raise && self.at(TEOF) {
    let _ = self.bump()
  }
  let (_, _) = self.parse_block(false)
'@.Replace("`r`n", "`n")
    MustRed = '0503: a function literal may carry `raise?`'
  }

  # M3 THE FUNCTION-TYPE POSITION STOPS AT THE `?`. This one removes BOTH jobs
  # the `?` does in that position -- the optional-raise marker AND the nullable
  # marker on a parenthesised group -- so TWO rows go red, and that is stated
  # here rather than left for the reader to work out from a count.
  @{
    Name = 'M3 the function-type position never consumes the `?`'
    File = $PARSER
    Find = @'
  let bare_raise = self.at_bare_raise()
  let clause_start = self.p
  self.parse_raise_effect()
  let no_clause = self.p == clause_start
  if (bare_raise || no_clause) && self.at(TQuestion) {
    let _ = self.bump()
    out = out + "?"
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  let bare_raise = self.at_bare_raise()
  let clause_start = self.p
  self.parse_raise_effect()
  let no_clause = self.p == clause_start
  if (bare_raise || no_clause) && self.at(TEOF) {
    let _ = self.bump()
    out = out + "?"
  }
'@.Replace("`r`n", "`n")
    MustRed = '0503: a function type may carry `raise?`'
  }

  # M4 THE "NO CLAUSE" MEASUREMENT IS ALWAYS TRUE, which is the OTHER direction:
  # the `?` is then accepted after ANY clause in the function-type position, and
  # four programs the toolchain rejects become readable. The measurement is
  # `self.p == clause_start` -- the cursor does not move when there is no clause
  # to read -- and `>=` is the same measurement with the comparison loosened.
  #
  # THIS IS THE MUTATION THAT MAKES THE NULLABLE GROUP WORTH A GATE. If the `?`
  # after a clause were the only `?` in that position, the rule would be one
  # line; the group is what makes it two.
  @{
    Name = 'M4 the function-type `?` is accepted after any clause'
    File = $PARSER
    Find = @'
  let no_clause = self.p == clause_start
  if (bare_raise || no_clause) && self.at(TQuestion) {
'@.Replace("`r`n", "`n")
    Repl = @'
  let no_clause = self.p >= clause_start
  if (bare_raise || no_clause) && self.at(TQuestion) {
'@.Replace("`r`n", "`n")
    MustRed = '0503: a function type may not carry `raise?` on a `noraise`'
  }

  # M5 THE RETURN POSITION ACCEPTS THE `?` AFTER ANY CLAUSE. The other
  # direction at the return site: `-> Int noraise?`, `-> Int nocancel?`,
  # `-> Int! ?` and `-> Int raise + nocancel?` all become readable, and the
  # toolchain rejects every one of them (3002).
  @{
    Name = 'M5 the return position accepts the `?` after any clause'
    File = $PARSER
    Find = @'
  if bare_raise && self.at(TQuestion) {
    let _ = self.bump()
  }
  (full, params, retann)
'@.Replace("`r`n", "`n")
    Repl = @'
  if (bare_raise || self.at(TQuestion)) && self.at(TQuestion) {
    let _ = self.bump()
  }
  (full, params, retann)
'@.Replace("`r`n", "`n")
    MustRed = '0503: the `?` on a `noraise` is still a parse error'
  }

  # M6 THE FUNCTION-LITERAL POSITION ACCEPTS THE `?` AFTER ANY CLAUSE. The same
  # direction at the third site, and it is a separate mutation because a
  # function literal reads its tail in its own function: a rule applied at the
  # other two sites says nothing about this one.
  @{
    Name = 'M6 the function-literal position accepts the `?` after any clause'
    File = $PARSER
    Find = @'
  if bare_raise && self.at(TQuestion) {
    let _ = self.bump()
  }
  let (_, _) = self.parse_block(false)
'@.Replace("`r`n", "`n")
    Repl = @'
  if (bare_raise || self.at(TQuestion)) && self.at(TQuestion) {
    let _ = self.bump()
  }
  let (_, _) = self.parse_block(false)
'@.Replace("`r`n", "`n")
    MustRed = '0503: a function literal may not carry `raise?` on a `noraise`'
  }

  # M7 THE JOINED-CLAUSE ARM OF THE GUARD IS DROPPED, so `raise + nocancel` is
  # mistaken for a bare raise and the `?` after it is taken. The toolchain
  # rejects `-> Int raise + nocancel?` with 3002.
  @{
    Name = 'M7 the joined-clause arm of the bare-raise guard is dropped'
    File = $PARSER
    Find = @'
    TName(_) | TLParen | TAmp => false
    TPlus => false
    _ => true
'@.Replace("`r`n", "`n")
    Repl = @'
    TName(_) | TLParen | TAmp => false
    _ => true
'@.Replace("`r`n", "`n")
    MustRed = '0503: the `?` on a joined effect clause is still a parse error'
  }

  # M8 THE GUARD ADMITS NOTHING, so the `?` is never taken and the one shape the
  # toolchain accepts is refused again -- the state before this increment, in
  # every position at once.
  @{
    Name = 'M8 the bare-raise guard admits nothing'
    File = $PARSER
    Find = @'
  match self.peek2() {
    TName(_) | TLParen | TAmp => false
    TPlus => false
    _ => true
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  match self.peek2() {
    _ => false
  }
'@.Replace("`r`n", "`n")
    MustRed = '0503: a return annotation may carry `raise?`'
  }

  # M9 THE GUARD'S "IS IT A RAISE AT ALL" TEST IS WIDENED, so `noraise` is
  # mistaken for a bare raise and the `?` after it is taken. The toolchain
  # rejects `-> Int noraise?`: an optional marker on "does not raise" says the
  # opposite of what it looks like.
  @{
    Name = 'M9 the guard mistakes `noraise` for a bare raise'
    File = $PARSER
    Find = @'
fn Parser::at_bare_raise(self : Parser) -> Bool {
  if !self.at_name("raise") {
    return false
  }
'@.Replace("`r`n", "`n")
    Repl = @'
fn Parser::at_bare_raise(self : Parser) -> Bool {
  if !self.at_name("raise") && !self.at_name("noraise") {
    return false
  }
'@.Replace("`r`n", "`n")
    MustRed = '0503: a function type may not carry `raise?` on a `noraise`'
  }

  # M10 THE TYPE-HEAD ARM OF THE GUARD IS DROPPED, so `raise E` is mistaken for
  # a bare raise.
  #
  # THIS ONE SURVIVES, and the argument is worth more than a kill.
  @{
    Name = 'M10 the type-head arm of the bare-raise guard is dropped'
    File = $PARSER
    Find = @'
    TName(_) | TLParen | TAmp => false
    TPlus => false
'@.Replace("`r`n", "`n")
    Repl = @'
    TName(_) | TLParen | TAmp => true
    TPlus => false
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = @'
THE `?` AFTER A TYPED RAISE NEVER REACHES THE QUESTION, and that is the whole
reason.

`-> Int raise MyErr?` is ILLEGAL -- the toolchain rejects it with 4032 + 3002
(settle row b_ret_raise_typed_q) -- and this analyzer ACCEPTS it. The reason is
that the `?` is taken by the TYPE reader first: `type_annotation` ends with a
`while self.at(TQuestion)` loop that folds the `?` into the name it returns, so
the clause is read as `raise MyErr?` -- a raise of the NULLABLE error type
`MyErr?` -- and the cursor is already past the `?` when the optional-raise
question is asked.

So the arm cannot change any outcome today, at any of the three sites. Dropping
it makes `at_bare_raise` answer "yes" for `raise E`, and the `?` that would have
been handed to the optional-raise rule is not there to hand over.

THE ARM IS KEPT ANYWAY, and the reason is the one 0466 recorded about an
unobservable call: keeping it means the helper ANSWERS THE QUESTION IT ASKS.
`at_bare_raise` asks whether the clause is a bare raise, and `raise E` names an
error type, so it is not one -- and the next person to read the helper should
not have to re-derive that from the absence of a symptom.

THE DIVERGENCE ITSELF IS A SEPARATE INCREMENT, and this is where it is
recorded. The analyzer accepts ONE SHAPE the toolchain rejects -- `raise E?`, in
all three positions -- and `parser_0503_test.mbt` pins that acceptance on
purpose, so that it is a FACT in this repository rather than a surprise. The fix
belongs in `parse_raise_effect`, which reports nothing about the type it reads,
and that function is pinned by gates 0466 and 0487 -- so it is the next
increment's work, not this one's.
'@.Replace("`r`n", "`n")
  }
)

Write-MutationGateVerdict -Name '0503'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

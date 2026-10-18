# Mutation gate 0484 -- a TRAIT METHOD WHOSE RECEIVER IS A REFERENCE, `fn &Trait::method`.
#
# WHAT THIS PINS. `fn &Data::binary(self : &Data) -> Bytes` is the boundary line of two of async's
# unreadable files -- `io/data.mbt:77` and `process/redirect.mbt:229` -- and `expect_name` was
# called with the cursor on a `TAmp`. A ten-case probe against this analyzer's own parser showed
# `fn Data::binary(self : Data)` already reads (first_error 0), and every one of the six failing
# cases fails because of the `&` IN FRONT OF THE HOLDER and not because of the body.
#
# *** THE FIRST FRAMING WAS WRONG AND THE TOOLCHAIN SAID SO. *** The obvious reading of
# `fn &Type::method` is "a method on Type, declared through a reference". It is a TRAIT's default
# method whose receiver is a reference. Two fixture drafts declared `Data` as a struct and every
# row came back 4100 "The type Data is not a trait"; the corpus said so at `io/data.mbt:23` and
# `process/redirect.mbt:212`, where `Data` and `ProcessInput` are declared with `trait`. A reader
# that got the tokens right and the meaning wrong would have passed every corpus number.
#
# THE TOKEN SHAPE IS NOT 0483's, and getting it wrong is silent. `Lexer::run` starts a name at
# `is_letter(c) || c == '@'`, so `@` glues INTO the name. `&` is not a name-start character: it
# falls through to `lex_op`, which maps `'&' => TAmp`, so here the `&` is a STANDALONE token in
# front of an ordinary `TName`. Copying 0483's shape would have produced a mutation-proof-looking
# fix that changed nothing.
#
# There are TWO readers of this grammar and the fix had to touch both, which is M1 and M2.
# `parse_fn_signature` consumes the `&` and folds the name; `declared_name_after_kw` skips it to
# HARVEST the name. Fixing only the first is the worst outcome available: the file PARSES (so
# `parsed` goes up, which is the number a corpus scan measures), `actionable` stays 0, and every
# call site reports `undefined name 'Trait::m'` -- ACTIONABLE, on code `moon check` compiles. A
# loud parse failure traded for a quiet false positive. M1 is the only mutation here that no
# corpus number in either direction could have found.
#
# Measured: async `parsed 406 -> 408`, `unreliable 100 -> 72`, `withheld 25 -> 25`,
# `notices 1783 -> 1807`, `actionable 0 -> 0`, `total 1883 -> 1879`. Two files closed outright --
# exactly the two predicted by the ranking, which had been made by looking at what is ON each
# boundary line rather than at the scanner's grouped message tally (the 0472 lesson).
#
# `_verify/settle_0484_ref_holder.ps1`, 19 rows / 3 controls, GATE OK:
#   ACCEPT  `fn &Trait::m(self : &Trait)`  with and without `pub`, with a `raise` tail,
#           called as `d.m()`, `= "%identity"` body, `async`, and `fn &@other.Trait::m`
#   REJECT(4100)  the same declaration on a STRUCT     <- the control that makes `trait` measured
#   REJECT(4032)  EVERY unqualified spelling            <- forces the `&` out of the AST name
#   REJECT(4099)  `Trait::m(x)` -- a trait is not a type, so there is no by-path call form
#   REJECT(4074)  `fn &&Trait::m`                       <- M5, the direction this project never takes
#   REJECT(4156)  `extern "C" fn &Trait::m`
#
# `&` IS DROPPED FROM THE RECORDED NAME, and that is a decision with a falsification condition
# rather than a convenience: `moon check` refuses both `Trait::m(x)` and every unqualified
# `Trait::m`, so `m()` is the only spelling on either side and nothing could ever look up
# `&Data::binary`. Falsified if either ever settles ACCEPT. M3 is the mutation that would do it.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0484' -Target 'wasm' -Mutations @(

  # M1 THE HARVEST DOES NOT SKIP THE `&`. This is the mutation the corpus could not have found in
  # either direction: `parsed` goes UP (the declaration reader still works), so a scan reading only
  # parse coverage would call it a fix, and `actionable` is 0 until someone calls the method. The
  # direct harvest row is the only thing that sees it -- which is why that row exists and asserts
  # through `collect_declared_names` instead of routing the claim through `@pipeline.run`, where a
  # resolution path that never consults the sibling table would make it vacuous.
  @{
    Name = 'M1 the harvest does not skip the &'
    File = $PARSER
    Find = @'
    if toks[i] is TAmp {
      i += 1
      moved = true
    } else if toks[i] is TLBracket {
'@.Replace("`r`n", "`n")
    Repl = '    if toks[i] is TLBracket {'
    MustRed = '0484: the harvest records the folded holder'
  }

  # M2 THE DECLARATION DOES NOT SKIP IT EITHER, so the file fails to parse again. The obvious
  # first mutation, and the reason M1 is the interesting one: this one is loud.
  @{
    Name = 'M2 the declaration reader does not consume the &'
    File = $PARSER
    Find = '  if self.at(TAmp) {'
    Repl = '  if false && self.at(TAmp) {'
    MustRed = '0484: an & trait holder reads whole'
  }

  # M3 THE `&` IS FOLDED INTO THE NAME, giving `&Data::binary`. Nothing about it is a crash: the
  # file parses, the tree is well formed, and `actionable` stays 0. The name simply becomes a
  # string nothing can ever look up, because the settle shows there is no `&Trait::m(x)` call and
  # no unqualified `Trait::m` declaration to match it against. This is the row that makes the
  # drop-a-decision falsifiable rather than taste.
  #
  # THE FIRST DRAFT OF THIS MUTATION WAS A NO-OP AND SURVIVED, which is worth recording rather than
  # quietly fixing: it introduced `amp_prefix` and then still built the name from `name`. A
  # mutation that does not change behaviour is indistinguishable from a test that cannot fail, and
  # the gate is right to report both the same way.
  @{
    Name = 'M3 the & is folded into the recorded name'
    File = $PARSER
    Find = @'
  if self.at(TAmp) {
    let _ = self.bump()
  }
  let (name, _) = self.expect_name("function name")
  let mut full = name
'@.Replace("`r`n", "`n")
    Repl = @'
  let mut amp_prefix = ""
  if self.at(TAmp) {
    let _ = self.bump()
    amp_prefix = "&"
  }
  let (name, _) = self.expect_name("function name")
  let mut full = amp_prefix + name
'@.Replace("`r`n", "`n")
    MustRed = '0484: the & is not part of the recorded name'
  }

  # M4 THE LOOP BECOMES A SINGLE PASS, which is the pre-0484 behaviour plus the `&`. `fn &T::m`
  # keeps working and `fn[T] name` keeps working -- and `fn[T] &T::m` silently harvests NOTHING,
  # because the two skips now contend for one iteration. No corpus writes that order, so no corpus
  # number moves and no error appears: the harvest just loses a name.
  @{
    Name = 'M4 the two skips contend for one pass, so fn[T] &Trait::m harvests nothing'
    File = $PARSER
    Find = '  while moved && i < toks.length() {'
    Repl = '  if i < toks.length() {'
    MustRed = '0484: fn[T] &Trait::m harvests'
  }

  # M5 THE SKIP IS WIDENED TO THE LOGICAL-AND TOKEN, which is the obvious over-correction: someone
  # reading `fn &&Trait::m` as "two borrows" and accepting it. The toolchain refuses it
  # (4074/3002), so reading it is a MISSED error -- the liberal direction, a false negative on
  # code nobody writes, which is the one direction this project has never taken.
  #
  # *** `&&` IS ONE `TAndAnd` TOKEN, NOT TWO `TAmp`s. *** The first draft of this mutation widened
  # the `if` to a `while` over `TAmp`, which SURVIVED and taught the wrong thing: it looked like a
  # vacuous guard test rather than a lexing fact. `lex_op` folds `&&` into a single token, so no
  # number of `TAmp` bumps can ever reach it -- and the guard row is falsifiable after all, by a
  # reader that accepts `TAndAnd` in holder position.
  @{
    Name = 'M5 the logical-and token is accepted as a holder marker, so fn &&Trait::m parses'
    File = $PARSER
    Find = @'
  if self.at(TAmp) {
    let _ = self.bump()
  }
  let (name, _) = self.expect_name("function name")
'@.Replace("`r`n", "`n")
    Repl = @'
  if self.at(TAmp) || self.at(TAndAnd) {
    let _ = self.bump()
  }
  let (name, _) = self.expect_name("function name")
'@.Replace("`r`n", "`n")
    MustRed = '0484: a double & holder is not read'
  }
)

Write-MutationGateVerdict -Name '0484'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

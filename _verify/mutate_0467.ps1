# Mutation gate 0467 -- the ASYNC function type with no parentheses of its own.
#
# WHAT THIS PINS. `async (A, B) -> R` is ONE construct with THREE spellings, and until
# this increment exactly one of them parsed. Measured by running the analyzer over one
# file per shape, not by reading the code:
#
#     (async (A, B) -> R)?      a parenthesised annotation   -- parsed=1
#     async (A, B) -> R         a bare parameter annotation  -- parsed=0
#     -> async (A, B) -> R      a bare return annotation    -- parsed=0
#
# The cause was an ORDERING fact rather than a missing keyword: the `async` lookahead in
# `fn_type_annotation` sat AFTER its `bump() // (`, so it could only ever see `async`
# when something had already put a `(` in front of it. The body is now shared
# (`fn_type_body`) and there are thin entry arms in front of it.
#
# Reach: 19 of the 57 files still unread, 11 async and 8 proton -- the largest single
# shape measured on the tree that shipped as 12b38a3, and a strict dependency for the
# effect-in-param-position files (`_verify/rank_0467_shapes.ps1`, members printed).
#
# THE GRAMMAR is settled in `_verify/settle_0467_async_param_type.ps1`, 17 rows, and
# two parts of it are not guessable from the symbol:
#
#     g : async               REJECT  "you may expect `(`"   -- the paren is REQUIRED
#     g : bogus (Int) -> Unit REJECT(3002)                   -- the head is a KEYWORD
#
# => the first is why M5's lookahead exists and the second is what makes M3 killable.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$WALK = 'src\walk\walk.mbt'

Invoke-MutationGate -Name '0467' -Target 'js' -Mutations @(

  # M1 THE INCREMENT ITSELF. The new entry arm in `type_annotation` is gone, so a
  # parameter annotation reads `async` as an ordinary type name and the `(` that follows
  # stops the parameter loop. This is the pre-0467 behaviour, restored.
  @{
    Name = 'M1 the bare `async (..)` entry arm is gone'
    File = $PARSER
    Find = @'
  if self.at_name("async") && self.lparen_at(self.p + 1) {
    let _ = self.bump() // async
    let _ = self.bump() // (
    return self.fn_type_body("async ")
  }
'@
    Repl = ''
    MustRed = '0467: `f : async (Int) -> Unit` parses'
  }

  # M2 THE BUG THIS INCREMENT ACTUALLY SHIPPED FOR AN HOUR. `fn_type_body` starts INSIDE
  # the parentheses, so dropping the `(` bump leaves the cursor sitting on it and the
  # body parses `(Int)` as a nested type, then trips over `->` with `expected ')'`.
  #
  # Worth its own mutation rather than being folded into M1: it is the state the first
  # working build was in, and M1 cannot reach it -- with the arm REMOVED the parse never
  # calls the body at all. A guard that only catches "the feature is missing" would have
  # shipped M2's bug.
  @{
    Name = 'M2 only `async` is consumed, so the cursor stops on the paren'
    File = $PARSER
    Find = @'
    let _ = self.bump() // async
    let _ = self.bump() // (
    return self.fn_type_body("async ")
'@
    Repl = @'
    let _ = self.bump() // async
    return self.fn_type_body("async ")
'@
    MustRed = '0467: `f : async (Int) -> Unit` parses'
  }

  # M3 THE SHORTCUT THE CANARY FORBIDS. Drop the keyword test and ANY name followed by a
  # parenthesised list becomes an async function type -- `Unit (Int) -> Int` included.
  # `moon check` REJECTs `g : bogus (Int) -> Unit` with 3002 (settle row
  # `canary_any_name`), so this is the canary's whole job.
  @{
    Name = 'M3 the head is not required to be the keyword `async`'
    File = $PARSER
    Find = '  if self.at_name("async") && self.lparen_at(self.p + 1) {'
    Repl = '  if self.lparen_at(self.p + 1) {'
    MustRed = '0467: a non-async name before a parameter list still reports'
  }

  # M4 THE SHARED BODY LOSES ITS HEAD. The new entry arm hands `fn_type_body` an empty
  # prefix, so a bare parameter annotation renders `(Int) -> Unit` instead of
  # `async (Int) -> Unit`.
  #
  # THIS ROW IS THE SECOND HALF OF A STORY THE FIRST RUN OF THIS GATE WROTE.
  # M4 originally targeted `fn_type_annotation`'s own `async` head detection and it
  # SURVIVED -- because 0467's new arm had made that detection redundant, so removing it
  # changed nothing observable. A surviving mutation is not "the property is untested",
  # it is "the property is not what I thought it was", and here the answer was worse:
  # the redundant detection was rendering the head TWICE, so `(async (Int) -> Unit)?`
  # became `async (async (Int) -> Unit)?` -- a string that parses, reports nothing, and
  # is wrong.
  #
  # NO PARSE-LEVEL ROW COULD SEE IT. Every `first_error == 0` row stayed green. The row
  # that kills it asserts the STRING (`parser_0467_test.mbt`, "renders as it is written"),
  # which is the 0465 lesson applied to a new place: a construct can parse perfectly
  # while carrying the wrong thing, so the control has to count what the tree CARRIES.
  #
  # The retired original is recorded above rather than deleted, because the gate is the
  # place a reader looks to find out why that detection is gone.
  @{
    Name = 'M4 the new entry arm hands `fn_type_body` an empty prefix'
    File = $PARSER
    Find = @'
    let _ = self.bump() // (
    return self.fn_type_body("async ")
  }
'@
    Repl = @'
    let _ = self.bump() // (
    return self.fn_type_body("")
  }
'@
    MustRed = '0467: a bare async function type renders as it is written'
  }

  # M5 THE LOOKAHEAD, DECLARED SURVIVOR. Dropping `lparen_at(self.p + 1)` means a bare
  # `async` in type position is consumed as a function type instead of reported.
  @{
    Name = 'M5 `async` needs no parameter list'
    File = $PARSER
    Find = '  if self.at_name("async") && self.lparen_at(self.p + 1) {'
    Repl = '  if self.at_name("async") {'
    Expect = 'SURVIVED'
    Prove = 'Unreachable by construction rather than untested: there is no `async` type without a parenthesised parameter list. The toolchain says so itself -- `fn f(g : async) -> Int { .. }` reports "Parse error, unexpected token `)`, you may expect `(`" (settle row `canary_bare_async`, REJECT 4041 + 3002). So the branch this mutation widens is only reachable from a program that does not compile, and no such program is in any pinned corpus. Kept as a separate lookahead anyway because the settle is what justifies it: without the settle row this mutation looks like an arbitrary narrowing.'
  }

  # ---------------------------------------------------------------------------
  # 0467b -- THE BINDING COLLECTOR. A different LAYER: no parser code at all, and the
  # finding it removes is an UndefinedName rather than a ParseError.
  #
  # Reaching `src/fs/dir.mbt` produced two actionable false positives on code `moon
  # check` compiles -- `49:26 no visible binding for 'last_path_sep_index'` and
  # `55:13 no visible binding for 'parent'` -- because `collect_fn_bindings` descends
  # into `SIf`/`SFor`/`SWhile`/`SBlock` and `catch` is an EXPRESSION, so no arm ever
  # scanned one. `walk_expr` has walked `arm.body` for years; only the collector was
  # missing, and `walk_stmt`'s `SLet` never binds anything itself.

  # M6 THE CATCH ARM IS NOT COLLECTED. Restores the false positives exactly.
  @{
    Name = 'M6 a catch arm body is never scanned for bindings'
    File = $WALK
    Find = @'
    ECatch(_, arms) =>
      for arm in arms {
        collect_stmt_bindings(bs, arm.body)
      }
'@
    Repl = ''
    MustRed = '0467b: a let inside a catch arm binds in that arm'
  }

  # M7 ONLY `ECatch`. The `ENoRaise` arm is one line of code beside it and a battery
  # that only exercises `ECatch` leaves it unmeasured -- which is why it is its own
  # mutation and its own row rather than a comment.
  @{
    Name = 'M7 a noraise arm body is never scanned for bindings'
    File = $WALK
    Find = @'
    ENoRaise(_, arms) =>
      for arm in arms {
        collect_stmt_bindings(bs, arm.body)
      }
'@
    Repl = ''
    MustRed = '0467b: a noraise arm body binds too'
  }

  # M8 THE TAIL POSITION ALONE. The first version of the 0467b fix handled `SExpr` and
  # changed nothing measurable, because `expr catch { .. }` as the last statement of a
  # function is a `STail`. A fix on ONE of the seven places a construct can appear is a
  # fix on one of seven, and this is the mutation that would have caught that.
  @{
    Name = 'M8 a catch in tail position is not reached'
    File = $WALK
    Find = '      STail(e) => collect_expr_bindings(bs, e)'
    Repl = '      STail(_) => ()'
    MustRed = '0467b: a let inside a catch arm binds in that arm'
  }
)

Write-MutationGateVerdict -Name '0467'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

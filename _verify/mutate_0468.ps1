# Mutation gate 0468 -- the BLOCK in the right-hand side of a `let`.
#
# WHAT THIS PINS. Until this increment every `{` in expression position reached the atom's
# TLBrace arm and went to the FIELD grammar, which rejected the content and reported
# `expected a struct literal field here` at the brace. A block -- `{ let y = 1; y + 1 }`,
# whose value is its TAIL -- was unreadable.
#
# Reach: async 352 -> 390 parsed (+38 of the 78 still unread), proton 121 -> 122,
# labeler 32 -> 33, image 15 -> 17. moui 608/608 and contract 4/4 UNCHANGED, and that is
# the control that makes the other four mean anything: both were already complete and so
# cannot have contributed a parse.
#
# 0468 IS TWO THINGS, NOT ONE, and M1/M2 are the two halves kept apart on purpose.
# `at_struct_literal` has to learn `(TName, TRBrace)`, or `let x = { a }` -- a legal
# ONE-FIELD struct literal -- is rewritten as a block. Doing only the block half is a
# regression WEARING A FIX: every corpus count above improves while the analyzer quietly
# starts saying something else.
#
# THE GRAMMAR is settled in `_verify/settle_0468_let_block_rhs.ps1`, 20 rows, and its
# negatives are ASSERTED -- which is new, and the reason `neg_bare_name` is not called
# `block_bare_name`. That row sat in the `block_` family, asserting the toolchain reads
# `{ b }` as a block, and REJECTed [4033] the whole time. Nothing asserted it.
#
# M4 IS THE MUTATION THAT MATTERS MOST, because it is not hypothetical: it is the state
# this increment was actually in when its own guard test caught it. `parse_block` marks a
# trailing expression as `STail` only under its flag, and BOTH block lenses key off
# `STail`. With the flag false, no `EBlock` body ever contained one, `Infer::ty_of`
# returned `TUnknown` for every block and `Interp::eval` returned `AAny` -- both arms dead
# code, with the corpus numbers completely unmoved by them, because `walk_stmt` reads an
# `SExpr` tail exactly as well as an `STail` one.
# => 判据: a construct can be READ correctly and still carry no value. Asserting the NODE
# is the only row that sees it.
#
# ONE ROW HAS NO MUTATION, and it is named here rather than left as an unverified guard.
# `0468: a lambda initialiser does NOT hoist its locals to module scope` pins a property
# the PARSER enforces structurally: an anonymous `fn` literal is read and its body is
# DISCARDED, leaving an opaque `EBigInt` that carries no statements. There is therefore no
# descent in `collect_top` that could be widened to hoist a lambda's locals -- the code
# that would have to change does not exist, and writing a mutation for it would mean
# inventing the defect rather than measuring it. The row stays because it is what catches
# the day the parser is taught to RETAIN lambda bodies.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$WALK = 'src\walk\walk.mbt'
$INFER = 'src\types\infer.mbt'
$INTERP = 'src\interp\interp.mbt'

Invoke-MutationGate -Name '0468' -Target 'wasm' -Mutations @(

  # M1 THE DISCRIMINATOR'S DECISION IS INVERTED. Every brace the discriminator calls a
  # literal is taken as a block and vice versa, which is the shape of the ORIGINAL bug in
  # reverse: blocks reach the field grammar and good literals get read as statement lists.
  #
  # It is not scoped to one row on purpose -- a mutation that kills only the block rows and
  # another that kills only the literal rows would be the same edit seen twice, and the
  # point of keeping them apart is to show the two halves of "0468 is two things".
  @{
    Name = 'M1 the block/literal discriminator is inverted'
    File = $PARSER
    Find = '  if self.at(TLBrace) && !self.at_struct_literal() {'
    Repl = '  if self.at(TLBrace) && self.at_struct_literal() {'
    MustRed = '0468: the corpus shape `let _unused : Unit = { .. }` parses at module level'
  }

  # M2 THE (TName, TRBrace) ARM IS GONE. `{ a }` matches no other shape, so the
  # discriminator answers false and a legal ONE-FIELD STRUCT LITERAL is rewritten as a
  # block. Settle row `ambig_shorthand_one`, ACCEPT.
  @{
    Name = 'M2 `(TName, TRBrace)` is no longer a literal'
    File = $PARSER
    Find = '    (TName(_), TRBrace) => true'
    Repl = ''
    MustRed = '0468: `{ a }` in a one-field literal stays a struct literal'
  }

  # M3 THE (TStr, _) ARM IS GONE -- the regression that cost FOUR `pipeline_0452` tests.
  # A quoted key arrives as `TStr`, not `TName`, so it matches none of the shapes above and
  # every map literal was routed to the block path. This arm is unconditional on the SECOND
  # token and M3 is why that is safe rather than lazy.
  @{
    Name = 'M3 a quoted key is no longer a literal'
    File = $PARSER
    Find = '    (TStr(_, _), _) => true'
    Repl = ''
    MustRed = '0468: a quoted-key map literal stays a struct literal'
  }

  # M4 THE TAIL FLAG, AND THE BUG THIS INCREMENT SHIPPED INTO ITS OWN TEST SUITE.
  @{
    Name = 'M4 the block is parsed without its tail marker'
    File = $PARSER
    Find = '    let (body, _) = self.parse_block(true)'
    Repl = '    let (body, _) = self.parse_block(false)'
    MustRed = '0468: a block''s last statement is its tail'
  }

  # M5 THE WALK DOES NOT DESCEND. The tail's reads stop being reads, so the name-resolution
  # walk stops reporting a name that is not bound.
  #
  # WHICH ROW THIS REDS IS MEASURED, NOT GUESSED, and it is not the obvious one. The
  # obvious candidate -- `0468: a name no block binds is still reported undefined` -- stays
  # GREEN, because in a block that is a direct `let` initialiser the TYPE lens reports the
  # same name and the walk's silence changes no count. The rows that do go red are the two
  # CALL-ARGUMENT canaries, where nothing but the walk is looking.
  #
  # => 判据: three lenses walk the same tree independently, so "is this name reported?" is
  # not one question. Removing one lens is observable only where the other two are not
  # already covering for it, and naming the wrong row credits this mutation with a kill
  # that belongs to the collector (M6).
  @{
    Name = 'M5 walk_expr never enters a block'
    File = $WALK
    Find = @'
    EBlock(body) =>
      for st in body {
        self.walk_stmt(st)
      }
'@
    Repl = '    EBlock(_) => ()'
    MustRed = '0468: an unbound name in a call argument is still reported'
  }

  # M6 THE COLLECTOR DOES NOT DESCEND -- the other half of the same property. M5 and M6 are
  # separate arms in separate functions, and a battery that only exercises one of them
  # leaves the other unmeasured.
  @{
    Name = 'M6 collect_expr_bindings never enters a block'
    File = $WALK
    Find = '    EBlock(body) => collect_stmt_bindings(bs, body)'
    Repl = '    EBlock(_) => ()'
    MustRed = '0468: a binding made inside a block is visible to its own tail'
  }

  # M7 ARGUMENTS ARE EXPRESSIONS. `gif.mbt:853,855` is
  # `Bytes::from_array({ let copy = ..; copy })`, two false `no visible binding` findings
  # before the arm existed.
  @{
    Name = 'M7 a block in a call argument is never scanned'
    File = $WALK
    Find = @'
    ECall(_, args, _) =>
      for a in args {
        collect_expr_bindings(bs, a)
      }
'@
    Repl = ''
    MustRed = '0468: a block passed as a call argument has its bindings collected'
  }

  # M8 AND THE RECEIVER FORM, WHICH IS A DIFFERENT VARIANT. M7's fixture is a QUALIFIED
  # name, which is an `ECall`; `s.contains(..)` is an `EMethodCall` and the M7 fixture does
  # not reach it. => 判据: two arms of one `match` are two arms.
  @{
    Name = 'M8 a block in a method argument is never scanned'
    File = $WALK
    Find = @'
    EMethodCall(_, _, args, _) =>
      for a in args {
        collect_expr_bindings(bs, a)
      }
'@
    Repl = ''
    MustRed = '0468: a block passed as a METHOD argument has its bindings collected'
  }

  # M9 THE MODULE-LEVEL DESCENT. `png.mbt:110` is `let fxl : HDecoder = {` with
  # `let ls = Array::make(288, 0)` on the next line, read at 113, 116, 119, 122 and 124 --
  # FIVE false `no visible binding for 'ls'` findings, and actionable 0 -> 15 on that corpus
  # with every one of the 15 tracing back to this single omission.
  @{
    Name = 'M9 a module-level block initialiser is never descended'
    File = $WALK
    Find = @'
          match init.kind {
            EBlock(body) => collect_top(body)
            _ => ()
          }
'@
    Repl = ''
    MustRed = '0468: a module-level block initialiser has its bindings collected'
  }

  # M10 THE TYPE LENS STOPS USING THE TAIL. It keeps its arm -- removing the arm outright
  # is a COMPILE ERROR, not a kill, because `ty_of`'s `match e.kind` is EXHAUSTIVE and a
  # missing variant is a `partial_match` warning that stops the suite before any test runs.
  # A mutation whose result is "the build broke" is not evidence that a row guards
  # anything, so this one removes the property from INSIDE the arm.
  #
  # It reaches the same TUnknown state M4 reaches from the parser side, and the two are
  # worth keeping apart: M4's row is a parse-level claim about the TAIL MARKER and M10's is
  # a type-level claim about the VALUE, and a future change could break either alone.
  @{
    Name = 'M10 Infer::ty_of types every block TUnknown'
    File = $INFER
    Find = '          @ast.STail(t) => tail_ty = self.ty_of(t, hint)'
    Repl = '          @ast.STail(_) => tail_ty = TUnknown'
    MustRed = '0468: the tail''s TYPE reaches the operator below'
  }

  # M11 THE BEHAVIOR LENS STOPS EVALUATING THE TAIL -- and this mutation had to be WRITTEN
  # twice, which is the most useful thing in this file.
  #
  # The first version replaced the tail's evaluation with `AAny`, and it SURVIVED 849/849.
  # The arm is not dead and the row is not weak; `AAny` is INVISIBLE TO THIS LENS BY
  # DESIGN. interp.mbt:1076 has `AAny => true` in `numeric`, and interp.mbt:1094 short-
  # circuits the whole operator arm on `if l is AAny || r is AAny` with the comment
  # "Any absorbs: conservative, keep inferring". Every binop therefore behaves identically
  # whether or not the block's tail was evaluated.
  #
  # => 判据: a survivor is not always an untested property. Sometimes it is a mutation whose
  # RESULT is unobservable, and the two demand opposite responses -- one wants a stronger
  # row, the other wants a mutation that produces a CONCRETE value. Check which you have
  # before you add a test. `AAny` was the wrong mutation; `AType("str")` is the right one,
  # because `strv` does NOT absorb and the operator arm reports on it.
  @{
    Name = 'M11 Interp::eval does not evaluate the tail'
    File = $INTERP
    Find = '          @ast.STail(t) => out = self.eval(t, env)'
    Repl = '          @ast.STail(_) => out = AType("str")'
    MustRed = '0468: the tail''s value reaches the behavior lens'
  }
)

Write-MutationGateVerdict -Name '0468'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

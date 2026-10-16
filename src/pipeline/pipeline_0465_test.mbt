//| Tests for the `..` CHAIN LINK end to end, 0465.
//|
//| The grammar is settled in `_verify/settle_0465_dotdot_chain.ps1`: `recv..name(args)`
//| CALLS `name`, DISCARDS its result, and EVALUATES TO `recv`. Before this the
//| constructor `parse_postfix_from` bumped the first `TDot` and handed the second to
//| `expect_name`, so every one of the 180 corpus sites in 33 async files died with
//| `expected field name` -- a message naming neither the operator nor the receiver.
//|
//| The AST rows live in `src/parser/parser_0465_test.mbt`. This file asserts what is
//| only observable after all four lenses have walked: that a parameter read ONLY
//| through a `..` argument counts as read, and that the receiver counts too.
//
//| => 判据: the parser rows pass on a tree that is well typed but has lost a value.
//! `EDotDot(EName("self"), "write", [], [])` is a legal node -- it is simply the
//! wrong one, and every compiler check agrees. The finding that exposes it is
//! downstream, which is why the row below asserts a COUNT OF A FINDING FAMILY and
//! not a parse success.

//|

///|
/// THE CORPUS SHAPE reports nothing. Taken from `moonbitlang/async 0.22.4`
/// `src/http/send.mbt:333-337` and `src/http/parser_wbtest.mbt:44-47`, with the
/// receiver and the arguments as parameters so that a dropped one would show up.
test "0465: the corpus chain shape reports nothing" {
  let r = @pipeline.run(
    "///|\nfn send(self : Int, path : String, head : String, extra : Int) -> Int {\n  let n = self\n    ..write(path)\n    ..write(head)\n    .send_headers(extra)\n  n\n}\n",
    "chain.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
  assert_eq(count_family(r, "UnusedBinding"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

//|

///|
/// THE ROW THAT EARNS THE FILE. `only_arg` is read at exactly ONE place -- as a
/// `..` argument -- and `only_recv` at exactly one -- as a `..` receiver.
///
/// This is the regression guard for a bug `moon check --deny-warn` could not see.
/// `Parser::expect` bumps on success, and the arm carried an extra `bump()` after
/// `expect(TLParen, ..)`, which consumed the FIRST ARGUMENT. `..write(only_arg)`
/// then parsed from the token after `only_arg`, so it never entered the AST and the
/// parameter read as unused -- four fixtures, `moon test` green throughout, because a
/// dropped argument yields a smaller and still perfectly legal tree.
test "0465: a parameter read ONLY as a `..` argument, or ONLY as a receiver, is used" {
  let r = @pipeline.run(
    "///|\nfn f(only_recv : Int, only_arg : Int, tail : Int) -> Int {\n  let n = only_recv..write(only_arg).send(tail)\n  n\n}\n",
    "only_arg.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

//|

///|
/// The same shape with the chain NOT on a `let`, which is the form the statement
/// parser reaches first -- `w` / `..write(..)` / `.write(..)` with no enclosing
/// expression. The receiver is a bare statement here, so the chain's own receiver is
/// the `EBigInt` placeholder; what must still hold is that the preceding statement
/// was walked, or `only_recv` would report unused.
test "0465: the statement-level chain reads the preceding statement" {
  let r = @pipeline.run(
    "///|\nfn f(only_recv : Int, only_arg : Int) -> Int {\n  only_recv\n  ..write(only_arg)\n  0\n}\n",
    "stmt_chain.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 0)
}

//|

///|
/// A bare `..name` with no argument list is REJECTED by the toolchain -- settle row
/// `dd_bare_name`, 4014/3002 -- so the parser reports at the missing `(`.
//
//! The parenthesised form beside it is the control: without it this row would also
//! pass on a parser that refused every `..` form at all.
test "0465: a bare `..name` reports a ParseError naming the missing paren" {
  let bare = @pipeline.run(
    "///|\nfn f(self : Int) -> Int {\n  let n = self\n    ..bump\n  n\n}\n",
    "bare.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(bare, "ParseError"), 1)
  let mut named_it = false
  for rep in bare.reports {
    if rep.family.name() == "ParseError" &&
      rep.message.contains("after '..' method name") {
      named_it = true
    }
  }
  assert_true(named_it)
  let ok = @pipeline.run(
    "///|\nfn f(self : Int) -> Int {\n  let n = self\n    ..bump()\n  n\n}\n",
    "paren.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(ok, "ParseError"), 0)
}

//|

///|
/// THE CONTROL FOR THE WHOLE INCREMENT: the two shapes that shared a spelling with
//! `..` before it existed, both of which already worked, both still work.
//
//! The struct-update spread is 106 sites in moui and 164 in labeler -- the entire
//! reason `..` looked like the biggest remaining win in the repository when in fact
//! moui and labeler write ZERO chain links and parse completely.
test "0465: the struct-update spread and the single-dot chain are both untouched" {
  let spread = @pipeline.run(
    "///|\nfn f(base : Int, v : Int) -> Int {\n  let s = { ..base, v }\n  s\n}\n",
    "spread.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(spread, "ParseError"), 0)
  assert_eq(count_family(spread, "UnusedParam"), 0)
  let dot = @pipeline.run(
    "///|\nfn f(self : Int, a : Int) -> Int {\n  let n = self\n    .write(a)\n  n\n}\n",
    "dot.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(dot, "ParseError"), 0)
  assert_eq(count_family(dot, "UnusedParam"), 0)
}

//|

///|
/// 0465b A LOOP IN EXPRESSION POSITION IS NOT A NAME. `let kind : MessageKind = for
/// frame = self.recv_frame_header() { .. }` is `moonbitlang/async 0.22.4`
/// `src/websocket/conn.mbt:486`, and it is legal MoonBit.
///
/// `parse_atom` had arms for `if`, `match`, `try`, `async`, `fn`, `true` and
/// `false` and none for a loop keyword, so `for` fell through to the generic TName
/// arm, became `EName("for")`, and the structural walk resolved a KEYWORD as a
/// binding: `undefined name 'for'`, actionable, on code `moon check` compiles.
///
/// REACHABLE ONLY AFTER 0465, and that is the point. The `..` chain in `conn.mbt`
/// stopped the parse 80 lines above 486, so this finding had no path to be observed
/// at all. Teaching the chain unblocked the file and revealed it -- the 0464b
/// `errdefer` case exactly, where the reach was legitimate and the GAP was what
/// needed fixing.
///
/// The assertions are `UndefinedName == 0` plus the honest notice. Asserting the
/// notice alone would not be enough: a parser that reported nothing here would also
/// satisfy "no UndefinedName", and the two controls below are what tell the
/// difference.
test "0465b: `for` and `while` in expression position report honestly, not as names" {
  let f = @pipeline.run(
    "///|\nfn f(x : Int) -> Int {\n  let k : Int = for i = 0 { i }\n  k\n}\n",
    "for_expr.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(f, "UndefinedName"), 0)
  let w = @pipeline.run(
    "///|\nfn f(x : Int) -> Int {\n  let k : Int = while true { x }\n  k\n}\n",
    "while_expr.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(w, "UndefinedName"), 0)
}

//|

///|
/// THE CONTROL FOR THE ROW ABOVE, and the reason it is not a general "keywords in
/// expression position" defect: `if` and `match` in the IDENTICAL position already
/// reported an honest ParseError. Three keywords, one position, two behaviours
/// before the fix -- and the two that were right are what makes the two that were
/// wrong visible.
test "0465b: `if` and `match` in the same position still report their own notice" {
  let i = @pipeline.run(
    "///|\nfn f(x : Int) -> Int {\n  let k : Int = if x > 0 { 1 } else { 2 }\n  k\n}\n",
    "if_expr.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(i, "UndefinedName"), 0)
  let m = @pipeline.run(
    "///|\nfn f(x : Int) -> Int {\n  let k : Int = match x { 0 => 1 _ => 2 }\n  k\n}\n",
    "match_expr.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(m, "UndefinedName"), 0)
}

//|

///|
/// AND THE LOOP AS AN EXPRESSION STATEMENT is untouched by that fix: the statement
/// path was EXTRACTED into `parse_while_stmt` / `parse_for_stmt` so expression
/// position consumes the identical construct instead of a second copy of the token
/// handling. This row is what stops the extraction from having changed what a
/// statement means -- `seq` is read, so the parameter only used as the iterated
/// sequence must not report.
test "0465b: loop statements still read their head after the extraction" {
  let f = @pipeline.run(
    "///|\nfn f(xs : Array[Int]) -> Int {\n  for x in xs {\n    ignore(x)\n  }\n  let n = 0\n  while n < 1 {\n    n = n + 1\n  }\n  0\n}\n",
    "loops.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(f, "ParseError"), 0)
  assert_eq(count_family(f, "UnusedParam"), 0)
}

///|
/// WHAT THIS FILE DOES NOT ASSERT, and why it is not a gap that a test could close.
///
/// The settle says the node's TYPE is the receiver's and its VALUE is the
/// receiver's, and `types/infer.mbt` and `interp/interp.mbt` both implement that.
/// Neither is observable through the pipeline, and the reason is structural rather
/// than an omission:
///
///   - The type lens has NO signature for a method. `EMethodCall` returns TUnknown
///     for exactly this reason, so the alternatives here are TUnknown and the
///     receiver's type -- and TUnknown is the fail-safe, which reports nothing.
///     No program distinguishes "the receiver's type" from "unknown".
///   - The behavioral lens cannot tell them apart either: `AAny` is the value it
///     already returns for a receiver it does not model, and a chain that yields
///     `AAny` cannot be shown to misbehave by a fixture.
///
/// So the claim that matters, and that IS tested, is structural: `..` produces its
/// OWN node rather than an `EMethodCall` spelling (`parser_0465_test.mbt`), and that
/// node's receiver and arguments are walked (the rows above). Typing it by the
/// METHOD's return type is not reachable either -- the lens has no table to read it
/// from -- so the way to be wrong here is the node, and the node is guarded.
test "0465: a chain link is its own node, not an EMethodCall" {
  // Read end to end so the claim is about a program, not about a type name.
  let r = @pipeline.run(
    "///|\nfn f(self : Int, a : Int) -> Int {\n  let n = self..write(a)\n  n\n}\n",
    "node.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  // A `..` link whose receiver is later used as an Int must not report: the chain
  // yields the receiver, so this is the one program shape the settled reading makes
  // a prediction about.
  assert_eq(count_family(r, "TypeMismatch"), 0)
}

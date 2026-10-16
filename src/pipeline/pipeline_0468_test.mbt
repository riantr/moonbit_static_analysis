//| Tests for 0468, the BLOCK in the RHS of a `let`, END TO END.
//|
//| `parser_0468_test.mbt` pins what the NODE is. This file pins what the analyzer SAYS
//| about it, and the difference is not academic: the increment's two block lenses --
//! `Infer::ty_of` and `Interp::eval` -- both key off `@ast.STail`, and the first version
//! of the parser passed `parse_block(false)`, so no `EBlock` body ever contained one.
//! Both arms were dead code and the corpus numbers were completely unmoved by them,
//! because `walk_stmt` reads an `SExpr` tail exactly as well as an `STail` one.
//!
//| => 判据: a construct can be READ correctly and still carry no value. The tree was walked,
//! the files were parsed, every measured number came out the same -- and the block's type
//! was `TUnknown` for every block in the corpus. `0468: the tail's TYPE reaches the
//! operator below` is the row that sees it, and it is the reason that row is not a
//! "does it parse" test.
//|
//| THREE of the rows below are regressions against defects this increment caused and then
//! fixed. They are kept as tests because each one cost real corpus findings first:
//!
//!   module-level `let x : T = { .. }`   5 false `no visible binding for 'ls'` on
//!                                        moonbit_image 0.3.7 png.mbt:113..124
//!   call arguments are expressions       2 false on the same corpus, gif.mbt:853,855
//!   `collect_top` never descended        the cause of the 5 above
//|
//! All three sat behind `_ => ()` catch-alls whose comment claimed "only `ECatch` and
//! `ENoRaise` carry a statement list inside an expression" -- true when written, false
//! the moment the type grew. The comment is corrected in place at walk.mbt:1043.

//|

///|
/// THE BINDING THE BLOCK MAKES IS VISIBLE TO ITS OWN TAIL. This is the row that says the
/// statements were KEPT. Collapsing `{ let y = 1; y + 1 }` to `y + 1` at parse time would
/// parse perfectly and report `no visible binding for 'y'` -- an invented finding on code
/// `moon check` compiles. `EBlock` exists rather than that collapse precisely so this
/// passes.
test "0468: a binding made inside a block is visible to its own tail" {
  let r = @pipeline.run(
    "///|\nfn f() -> Int {\n  let x = {\n    let y = 1\n    y + 1\n  }\n  x\n}\n",
    "blockbind.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CANARY BESIDE IT. If `UndefinedName` were zero because the lens had stopped looking,
/// the row above would prove nothing at all -- it is the row that says the count is real.
///
/// MEASURED DETAIL, because it decides which mutation this row can kill. A name inside a
/// block that is a DIRECT `let` initialiser is reported by the TYPE lens as well as by the
/// walk, so deleting `walk_expr`'s `EBlock` arm leaves this row GREEN. The two
/// call-argument canaries below are the rows a walk-only mutation reds. => 判据: three
/// lenses walk one tree, so "is this name reported?" is not one question, and the row that
/// looks like the natural guard for a lens may be carried by the other two.
test "0468: a name no block binds is still reported undefined" {
  let r = @pipeline.run(
    "///|\nfn f() -> Int {\n  let x = {\n    let y = 1\n    y + nope\n  }\n  x\n}\n",
    "blockcanary.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// KNOWN FALSE NEGATIVE -- PINNED, NOT ENDORSED. This row was written expecting
/// `UndefinedName == 1` and measured `0`, and the measurement is right: `moon check`
/// REJECTs this file with [4021] "The value identifier y is unbound" at line 6. A block
/// scopes lexically in MoonBit and this analyzer does not model that.
///
/// IT IS NOT A 0468 REGRESSION. The identical shape written with an `if` body -- an
/// `SBlock`, which predates this increment by a long way -- is measured the same way:
/// `moon check` reports `z` unbound at line 14, this analyzer reports nothing. `EBlock`
/// copies `SBlock`'s rule exactly, which is what walk.mbt:669 says it does ("CURRENT frame,
/// no new scope -- the SAME rule `SBlock` gets at walk_stmt").
///
/// => PINNED BECAUSE THE TWO NODES MUST MOVE TOGETHER. If a future increment teaches
/// blocks to scope, this row goes red and names the `SBlock` half that has to change with
/// it. Fixing it is its own increment: `SBlock` covers every `if` arm, loop body and
/// bare block in the corpus, so the corpus-wide finding count moves with it.
test "0468: a block's bindings do not scope (KNOWN FALSE NEGATIVE, pinned)" {
  let r = @pipeline.run(
    "///|\nfn f() -> Int {\n  let x = {\n    let y = 1\n    y\n  }\n  x + y\n}\n",
    "blockleak.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND THE CONSISTENCY HALF OF THAT ROW, stated on its own so it is not lost behind the
/// word "false negative". A block used as a `for` body (`SBlock`) and the same block used
/// as an expression (`EBlock`) must produce the SAME name count, because they are the same
/// scope rule in this analyzer. A change that taught one of them to scope and not the other
/// is the failure this row catches.
test "0468: an EBlock and an SBlock agree on scoping" {
  let asBlock = @pipeline.run(
    "///|\nfn h(c : Bool) -> Int {\n  if c {\n    let z = 1\n    z\n  }\n  z\n}\n",
    "scopeblock.mbt",
    @core.IfaceSymTab::empty(),
  )
  let asExpr = @pipeline.run(
    "///|\nfn h() -> Int {\n  let q = {\n    let z = 1\n    z\n  }\n  z\n}\n",
    "scopeexpr.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(
    count_family(asBlock, "UndefinedName"),
    count_family(asExpr, "UndefinedName"),
  )
}

///|
/// REGRESSION, the module-level descent -- `moonbit_image 0.3.7 png.mbt:110` is
/// `let fxl : HDecoder = {` with `let ls = Array::make(288, 0)` on the next line, read at
/// 113, 116, 119, 122 and 124. Collected without descending the initialiser, that is FIVE
/// false `no visible binding for 'ls'` findings, and `actionable` on that corpus went
/// 0 -> 15 with every one of the 15 tracing back to this single omission.
test "0468: a module-level block initialiser has its bindings collected" {
  let r = @pipeline.run(
    "///|\nlet fxl = {\n  let ls = 288\n  ls\n}\n",
    "blockmod.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE SAFETY ARGUMENT FOR THAT DESCENT, as a test. `collect_top` descends into an
/// `EBlock` and into NOTHING ELSE, precisely so it cannot hoist a lambda's function-local
/// names into the module frame. An anonymous `fn` initialiser is an `EBigInt` carrying a
/// skip note -- never an `EBlock` -- so this row cannot take the descent. If a future
/// change widened that `match` to "descend into any initialiser", this goes to zero and
/// the guard is the thing that notices.
///
/// `ParseError` IS NOT ASSERTED ZERO HERE, and only here. A module-level anonymous `fn`
/// necessarily produces `anonymous function literal is outside the analyzed subset; its
/// parameters were read but the body was not analysed [structural]` -- a DESIGNED
/// limitation that the family counter files under `ParseError`. Asserting zero would be
/// asserting the analyzer analyses lambda bodies, which it does not. `moon check` agrees
/// `hidden` is unbound at line 7, so the assertion that carries meaning is the
/// `UndefinedName` one.
test "0468: a lambda initialiser does NOT hoist its locals to module scope" {
  let r = @pipeline.run(
    "///|\nlet f = fn() {\n  let hidden = 1\n  hidden\n}\n\n///|\nfn g() -> Int {\n  hidden\n}\n",
    "blocklambda.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// REGRESSION, arguments are expressions -- `moonbit_image 0.3.7 gif.mbt:853,855` is
/// `Bytes::from_array({ let copy = ..; copy })`. `collect_expr_bindings` had no `ECall` or
/// `EMethodCall` arm, so a block reached as an ARGUMENT was never scanned and `copy` read
/// as undefined. Two false findings, one missing pair of arms.
///
/// This row is why the fix was an arm and not a widening of the `_ => ()`: a call argument
/// can hold any expression, including one that binds.
test "0468: a block passed as a call argument has its bindings collected" {
  let r = @pipeline.run(
    "///|\nfn f() -> Unit {\n  ignore(Bytes::from_array({\n    let copy = 1\n    copy\n  }))\n}\n",
    "blockarg.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CANARY BESIDE THAT ONE, for the same reason as every other canary row in this repo:
/// a `UndefinedName` count of zero is only evidence if the same harness reports a non-zero
/// for an identical shape with one name changed.
test "0468: an unbound name in a call argument is still reported" {
  let r = @pipeline.run(
    "///|\nfn f() -> Unit {\n  ignore(Bytes::from_array({\n    let copy = 1\n    nope\n  }))\n}\n",
    "blockargcanary.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE ROW THAT SEES THE `parse_block(false)` BUG -- the one that made both block lenses
/// dead code. A block's type is its tail's, so `!{ 1 }` is `!` applied to an Int, and the
/// operator lens says so. With the tail typed `TUnknown` -- the state the first version of
/// this increment actually shipped into the test suite -- this is ZERO, and the file is
/// `parsed=1` and perfectly clean.
///
/// This is the same observable that exposed the `match` defect at png.mbt:980, which is
/// why it is used here: it is a finding class this analyzer is MEASURED to emit, not one
/// inferred from the grammar.
test "0468: the tail's TYPE reaches the operator below" {
  let r = @pipeline.run(
    "///|\nfn f() -> Bool {\n  let vok = { 1 }\n  !vok\n}\n",
    "blocktailtype.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "OperatorMismatch"), 1)
}

///|
/// THE CONTROL: the same file with the block replaced by the literal it is equivalent to.
/// If this reported zero then the block was never typed and the row above proved nothing;
/// if it reported one then `!` on a Bool is somehow flagged and the row above proved
/// nothing either. It has to be zero.
test "0468: `!` on a Bool-valued block is not a mismatch" {
  let r = @pipeline.run(
    "///|\nfn f() -> Bool {\n  let vok = { true }\n  !vok\n}\n",
    "blocktailbool.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "OperatorMismatch"), 0)
}

///|
/// AND THE LITERAL CONTROL, which is the positive half: `!` on an Int that is NOT a block
/// is already reported by the pre-existing operator lens, so the row above's finding is
/// attributable to the block's type rather than to `!` itself.
test "0468: `!` on a plain Int is still a mismatch" {
  let r = @pipeline.run(
    "///|\nfn f() -> Bool {\n  let vok = 1\n  !vok\n}\n",
    "blocktailcanary.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "OperatorMismatch"), 1)
}

///|
/// THE `EMethodCall` HALF, WHICH IS A SEPARATE ARM. The row above uses
/// `Bytes::from_array(..)`, a QUALIFIED name, which is an `ECall`. A receiver call --
/// `s.contains(..)` -- is an `EMethodCall`, and the fixture above does not reach it.
/// => 判据: two arms of the same `match` are two arms. A battery that only exercises one
/// of them leaves the other unmeasured, which is the whole of 0467's M7 lesson and the
/// reason this row exists rather than a comment.
test "0468: a block passed as a METHOD argument has its bindings collected" {
  let r = @pipeline.run(
    "///|\nfn f() -> Unit {\n  let s = \"a\"\n  ignore(s.contains({\n    let t = 1\n    t\n  }))\n}\n",
    "blockmetharg.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CANARY BESIDE IT, for the same reason: this count of zero is only evidence if the
/// identical shape with one name changed reports one.
test "0468: an unbound name in a method argument is still reported" {
  let r = @pipeline.run(
    "///|\nfn f() -> Unit {\n  let s = \"a\"\n  ignore(s.contains({\n    let t = 1\n    nope\n  }))\n}\n",
    "blockmethcanary.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE THIRD BLOCK LENS -- `Interp::eval`, the BEHAVIOR lens -- and this row is scoped to
/// that lens on purpose. `count_family` merges three lenses walking the tree
/// independently, so a claim like "the behavior lens reached the block's tail" is only
/// observable on the lens that does it. The other two still find everything here.
///
/// IT IS A NEGATIVE ASSERTION, and that is the only shape that works for this lens. A
/// working `EBlock` evaluates the tail to `int`, `+` sees two numerics and reports
/// nothing; a broken one leaves `AAny` and the operator arm reports. So the mutation turns
/// this 0 into a 1 and the row goes red -- a negative assertion is still a guard when the
/// thing it forbids is an introduced finding.
///
/// THE TRAILING CALL IS NOT DECORATION. The first version of this row omitted it, the
/// count came back 0, and the obvious conclusion -- "the behavior lens is silent here" --
/// was WRONG. It is an abstract interpreter with an ENTRY POINT: it executes what `main()`
/// reaches, and a function nothing calls is never executed. `pipeline_test.mbt:945-958`
/// is the existing pair that gets this right, and it ends each fixture with a call.
/// => 判据: a zero from an interpreter is evidence about what you fed it. Before reading
/// a silent lens, check that the lens was given anything to run.
test "0468: the tail's value reaches the behavior lens" {
  let r = @pipeline.run(
    "///|\nfn f() -> Int {\n  let n = { 1 }\n  n + 1\n}\n\n///|\nf()\n",
    "blockbehav.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family_in(r, "MethodError", @core.LBehavior), 0)
}

///|
/// AND THE CONTROL THAT GIVES THAT ROW ITS MEANING, on the same lens and through the same
/// entry point: `+` on an Int and a String IS a behavior-lens finding, so the count the row
/// above asserts is zero is a count this lens can and does produce. Without it, "zero
/// MethodError" could mean the behavior lens is silent on this file for unrelated reasons
/// -- the mistake the row above's first version actually made.
test "0468: the behavior lens does report an operator mismatch" {
  let r = @pipeline.run(
    "///|\nfn g() -> Int {\n  let n = 1\n  n + \"s\"\n}\n\n///|\ng()\n",
    "blockbehavcanary.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "MethodError", @core.LBehavior), 1)
}

///|
/// THE CORPUS SHAPE END TO END -- `moonbitlang/async 0.22.4 src/tls/tls.wasm.mbt:655`,
/// five files with this line verbatim. Module level, a `Unit` annotation, and a body of
/// `ignore(..)` calls. It is the shape behind async 352 -> 390 parsed, and it is here
/// because "the corpus got 38 files further" is a claim about the corpus while this is a
/// claim about one file that is in the corpus.
test "0468: the async `let _unused : Unit = { .. }` shape analyses clean" {
  let r = @pipeline.run(
    "///|\nlet _unused : Unit = {\n  ignore(1)\n  ignore(2)\n}\n",
    "blockunused.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

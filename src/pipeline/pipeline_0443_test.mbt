///|
/// 0443: `loop nobreak { .. }` is a postfix block on a LOOP, not a name.
///

///|
/// THE DEFECT. There was no production for `nobreak`, so the bare token was
/// resolved as an ordinary identifier. Measured, one site that reaches the
/// actionable set:
///
///     proton internal/bridge_admission_test/main.mbt:20
///     20:5 - error: undefined name 'nobreak' (UndefinedName)
///
/// and the measured source is
///
///     while true {
///       while runtime.poll_event() is Some(event) {
///         if event.bridge_request() is Some(request) {
///           assert_eq(request.op, "app:probe")
///           return request
///         }
///       }
///       @async.sleep(5)
///     } nobreak {
///       fail("unreachable")
///     }
///
/// It is a FALSE POSITIVE: proton 0.3.4 compiles, and
/// `_verify/settle_0443_nobreak.ps1` settles the grammar with the compiler, 10/10
/// as predicted with the positive control green.
///
/// The corpus carries 34 `nobreak` lines in moonbitlang/async and 2 in proton,
/// and one of them reaches the actionable set. A census number is not a finding
/// count, which is the same reason `noraise` sat at the top of the todo list on a
/// stale note before it was measured.
test "0443: a `nobreak` block on a `while` is read, not read as a name" {
  let r = @pipeline.run(
    "fn keep(a : Int) -> Int {\n  while a < 0 {\n    ignore(0)\n  } nobreak {\n    fail(\"unreachable\")\n  }\n  0\n}\n",
    "nb.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND THE DIRECTION THAT PRODUCES A FALSE POSITIVE, which is the reason the
/// block is walked rather than consumed and thrown away: a parameter read ONLY
/// inside a `nobreak` body. Had the parser consumed the block without reading it,
/// this read would be invisible and `p` would report unread.
///
/// Every other parameter in this source is read in ordinary position, so the only
/// thing that can produce a finding is the `nobreak` body.
test "0443 control: a read only inside a `nobreak` body is still a read" {
  let r = @pipeline.run(
    "fn keep(a : Int, p : String) -> Int {\n  while a < 0 {\n    ignore(0)\n  } nobreak {\n    p.length()\n  }\n  0\n}\n",
    "ctl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE `for` FORM. The settle says `nobreak` is accepted on `while` AND `for`, and
/// the corpus site happens to be a `while` -- so a parser written for `while`
/// alone would have passed the corpus measurement while being wrong, and this is
/// the only thing that notices.
///
/// MoonBit's `for` is `for x in <iterable> { .. }` over something iterable; the
/// settle's first `for` case used `0..n` and the compiler rejected it with 3801,
/// which would have been read as "`nobreak` is not allowed on `for`" had the case
/// not been split from a control that measures only the loop.
test "0443: a `nobreak` block on a `for` loop is read" {
  let r = @pipeline.run(
    "fn keep(xs : Array[Int]) -> Int {\n  for x in xs {\n    ignore(x)\n  } nobreak {\n    ignore(1)\n  }\n  0\n}\n",
    "for.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE C-STYLE `for`, which is a DIFFERENT parse path -- `Parser::parse_c_for`
/// returns an `SBlock` wrapping the desugared `SWhile`, not a bare loop -- and so
/// is a third place the wrap has to be applied.
test "0443: a `nobreak` block on a C-style `for` is read" {
  let r = @pipeline.run(
    "fn keep(n : Int) -> Int {\n  for i = 0; i < n; i = i + 1 {\n    ignore(i)\n  } nobreak {\n    ignore(1)\n  }\n  0\n}\n",
    "cfor.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE EMPTY BLOCK, WHICH IS LEGAL HERE AND IS NOT LEGAL FOR `noraise`.
/// `settle_0443_nobreak.ps1` case `empty_block`: ACCEPTED, where the same spelling
/// on `noraise` is rejected. A parser that copied `noraise`'s "at least one arm"
/// shape would reject valid MoonBit here, and `first_error_line == 0` is the
/// assertion that says the whole source was still read.
test "0443: an empty `nobreak` block is legal, unlike an empty `noraise` block" {
  let r = @pipeline.run(
    "fn keep(a : Int) -> Int {\n  while a < 0 {\n    ignore(0)\n  } nobreak { }\n  0\n}\n",
    "empty.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
}

///|
/// AND THE SHAPE THE COMPILER REJECTS. `expr nobreak { .. }` with no loop is not
/// MoonBit (`settle_0443_nobreak.ps1`, `nr_without_loop`, REJECTED), so reporting
/// it is CORRECT, and pinning it is what keeps the production from being loosened
/// into a bare keyword match that would swallow a user's own `nobreak` function.
test "0443: `nobreak` with no loop is still reported, as the compiler rejects it" {
  let r = @pipeline.run(
    "fn keep(a : Int) -> Int {\n  let x = a\n  nobreak {\n    ignore(1)\n  }\n  x\n}\n",
    "noloop.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE LOOP HALF, so that the two halves of the node are killed by DIFFERENT
/// tests. The control above reads a name only in the `nobreak` body; this one
/// reads a name only in the LOOP, and the block reads nothing at all.
///
/// `walk_stmt` learning `SNoBreak` and the COLLECTORS not learning it is not a
/// hypothetical pair. It is exactly what happened: the first run of this file
/// failed with `no visible binding for 'x'` and `no visible binding for 'i'` --
/// the `for` binders, not `nobreak` -- because both collector matches have a
/// `_ => ()` catch-all and the compiler said nothing about the missing arm.
test "0443: a read inside the loop stays read through the `nobreak` wrapper" {
  let r = @pipeline.run(
    "fn keep(a : Int, p : String) -> Int {\n  while a < 0 {\n    p.length()\n  } nobreak {\n  }\n  0\n}\n",
    "loopread.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// AT MODULE LEVEL, which is a SECOND collector. `collect_fn_bindings` gathers a
/// function's own declarations and `collect_top` gathers the module frame's, and
/// they are different functions with different `SFor` arms. Teaching one and
/// leaving the other is the same mistake one function lower down, and the module
/// collector is the one that matters for a top-level loop, which executes at
/// module level and so puts its binder there.
///
/// The source has no `fn` at all on purpose: everything is top level.
test "0443: a module-level `for` binder still binds through a `nobreak` block" {
  let r = @pipeline.run(
    "fn items() -> Array[Int] {\n  [1, 2]\n}\n\nfor x in items() {\n  ignore(x)\n} nobreak {\n  ignore(1)\n}\n",
    "modlevel.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

//| Tests for 0474 -- what a loop in EXPRESSION position actually contributes to the tree.
//|
//| THE FIX MAKES THE FILE PARSE. `conn.mbt` (blocked at line 486 since forever) and
//| `internal/event_loop/io.mbt` both parse after it, which is two more files read end to
//| end. That is the whole of what it buys, and saying so precisely matters more than the
//| count.
//!
//! IT DOES NOT ANALYSE THE LOOP BODY. `parse_loop_as_expr` consumes the loop through the
//| statement-position readers -- so the token stream is right and the file survives -- and
//: then DISCARDS the statement, returning an opaque `EBigInt`. Its own comment says "the
//: body is skipped whole", and that is literal: the body is parsed and thrown away.
//!
//| The first draft of this file asserted the opposite and two rows came back
//! `0 != 1`. That is the right way to find out, and it is also why the zero row about an
//! unused parameter was DELETED rather than kept: its control could not turn it red either,
//! so it was not a test at all. 0470 left four vacuous rows in this suite by accident; this
//! one was caught by running it.

///|
/// THE BODY IS NOT ANALYSED. A name that does not exist, used only inside a loop
/// expression's body, is not reported -- the body never reaches the walk.
test "0474: a name inside a loop-expression body is not analysed" {
  let r = @pipeline.run(
    "///|\nfn f(a : Int) -> Unit {\n  let k : Unit = while a > 0 {\n    ignore(probe_0474_nowhere)\n  }\n  ignore(k)\n}\n",
    "loopexprbody.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CONTROL FOR THAT ZERO, and the reason the zero is worth anything: the SAME name in a
/// loop in STATEMENT position IS reported. Without this row the row above would pass on a
/// lens that had stopped resolving names altogether, and would mean nothing.
test "0474 control: the same name in a statement-position loop body is reported" {
  let r = @pipeline.run(
    "///|\nfn f(a : Int) -> Unit {\n  while a > 0 {\n    ignore(probe_0474_nowhere)\n  }\n}\n",
    "loopstmtbody.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE OTHER CONTROL, which is the one that says the loop consumed EXACTLY ITSELF. The
/// statement after a loop expression is ordinary code and must be analysed; a cursor left
/// anywhere but on the closing brace would make this row 0 while the file still parsed,
/// which is precisely the failure the increment had.
test "0474 control: the statement after a loop expression is analysed" {
  let r = @pipeline.run(
    "///|\nfn f(a : Int) -> Unit {\n  let k : Unit = while a > 0 {\n    ignore(1)\n  }\n  ignore(probe_0474_after)\n}\n",
    "loopexprafter.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

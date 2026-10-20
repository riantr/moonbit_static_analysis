//| 0492: a PARAMETER that is re-assigned in the body kept NO type at all, and
//| the type lens was SILENT on a program the toolchain REJECTS.
//|
//| THE DEFECT. `Infer::run_fn` seeds a function's frame from the structural
//| lens's binding table. That table lists the function's PARAMETERS first and
//| its BODY BINDINGS after -- and the walk records an assignment
//| `xs["k"] = "v"` as a RE-BINDING of the base name `xs`. So the table carried
//| `xs` TWICE, and the body binding -- which carries no type of its own -- was
//| declared LAST and OVERWROTE the parameter's annotation.
//|
//| The parameter's type was then gone for the WHOLE function body, and every
//| check on that name degraded to "unknown". That is a broad silence, not a
//| narrow one: "unknown" is assignable to anything and matches nothing.
//|
//| THE CASE THAT MADE IT VISIBLE.
//!
//|     fn h(xs : Array[String]) -> Unit { xs["k"] = "v" }
//!
//| The analyzer reported it CLEAN. The type lens has a gate for exactly this
//| shape -- "list indices must be int" -- and the READ form of the same code
//| (`xs["k"]`) IS reported. The source even says the two arms must agree:
//! `infer.mbt` "Both arms must agree -- a check that fires on read and not on
//| write is a claim about syntax, not about types."
//!
//| So the write arm was not merely untested -- it could not fire, because the
//| base's type was gone before it was consulted.
//!
//| SETTLED WITH THE TOOLCHAIN, `_verify/settle_0492_param_type.ps1`, 9 rows
//! with two POSITIVE CONTROLS that must REJECT (an earlier probe reported every
//! row ACCEPTED, because its project was not a project the toolchain would
//! check, and a settle that cannot reject is not a settle):
//!
//!   read_string_index        REJECT   the analyzer already reported this one
//!   write_string_index       REJECT   the analyzer was SILENT here
//!   write_list_local         REJECT   the analyzer already reported this one
//!   param_reassigned_wrong_type REJECT  the analyzer was SILENT here
//!   write_int_index          ACCEPT   correct code
//!   write_map_key            ACCEPT   correct code
//!
//! => 判据: A PARAMETER'S ANNOTATION IS A FACT ABOUT THE VARIABLE. A RE-BINDING OF
//| THAT VARIABLE IS NOT A NEW DECLARATION, AND IT MUST NOT ERASE THE FACT.
//|
//| => 判据: A GATE THAT CANNOT FIRE IS NOT A GATE. The write arm's guard was
//| unreachable in the only case it was written for, and nothing said so,
//! because the arm it belonged to was never the one that answered.

///|
/// THE DEFECT, and the only row in this file that is new behaviour. A parameter
/// of a list type, an index that is not an int, and the index written rather
/// than read.
test "0492: an indexed write through a PARAMETER reports the index type" {
  let r = @pipeline.run(
    "fn h(xs : Array[String]) -> Unit {\n  xs[\"k\"] = \"v\"\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "OperatorMismatch", @core.LType), 1)
}

///|
/// THE CONTROL, and it is the row that makes the row above mean something: the
/// SAME defect written against a LOCAL `let` instead of a parameter. The local
/// was always typed -- the `let` arm of the statement walk refines the frame as
/// it walks -- so this row was GREEN before the fix and must STAY green. A test
/// that only asserts the new behaviour cannot tell a fix from a change of
/// noise.
test "0492: the same indexed write through a LOCAL let still reports" {
  let r = @pipeline.run(
    "fn h() -> Unit {\n  let xs = [\"a\"]\n  xs[\"k\"] = \"v\"\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "OperatorMismatch", @core.LType), 1)
}

///|
/// CORRECT CODE, and the control for the control. An int index into an int
/// list is fine, and the gate must not fire on it.
test "0492: an indexed write with an int index is not a finding" {
  let r = @pipeline.run(
    "fn h(xs : Array[Int]) -> Unit {\n  xs[0] = 1\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "OperatorMismatch", @core.LType), 0)
}

///|
/// CORRECT CODE, and the 0.4.13 false positive must stay fixed: a `Map` is
/// indexed by its KEY, so `m["k"] = 1` is right. The type model has no `Map`,
/// so `Map[String, Int]` reads as Unknown and the base-type gate cannot fire.
/// This row is the reason the gate asks for the BASE and not just the index.
test "0492: a Map written through its key is not a finding" {
  let r = @pipeline.run(
    "fn h(m : Map[String, Int]) -> Unit {\n  m[\"k\"] = 1\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "OperatorMismatch", @core.LType), 0)
}

///|
/// THE BROAD FORM OF THE SAME DEFECT, and the row that shows the silence was
/// never about subscripts. A parameter re-assigned a value of the wrong type:
/// the parameter's annotation is the only fact about `xs`, and the assignment
/// is checked AGAINST it.
///
/// The toolchain REJECTS this program (settle row
/// `param_reassigned_wrong_type`), and it rejects it for the same reason the
/// type lens does: the value does not fit the declared type.
///
/// The other two lenses answer here too -- "parameter 'xs' changed by
/// assignment" and "parameter 'xs' may not be used" -- so the count is BY
/// FAMILY and BY LENS, or the other lenses would answer for the type lens's
/// decision.
test "0492: a parameter re-assigned a wrong-typed value is checked against its annotation" {
  let r = @pipeline.run(
    "fn h(xs : Int) -> Unit {\n  xs = \"s\"\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "AssignTypeMismatch", @core.LType), 1)
}

///|
/// THE PER-FUNCTION VIEW, because it is a SEPARATE entry and not the module
/// entry with a different flag: `run_functions` reports the per-function
/// findings and NOT the module entry's. A defect that only one entry can see
/// is half a defect, and the two views have disagreed before (0489, 0490).
test "0492: the per-function view reports the indexed write through a parameter" {
  let r = @pipeline.run_functions(
    "fn h(xs : Array[String]) -> Unit {\n  xs[\"k\"] = \"v\"\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "OperatorMismatch", @core.LType), 1)
}

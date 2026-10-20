//| 0493: FOUR behavioral-lens false positives, each one a CLAIM the analyzer
//| made about a program the toolchain accepts.
//|
//| THE CONTEXT. 0489 gave the behavioral lens a per-function entry, and 0490
//| and 0491 fixed five of the classes it made visible. What was left on
//| wzzc-dev/moui 0.1.12 was SEVEN actionable findings, and this file pins the
//| four classes they belonged to.
//!
//! MEASURED, the per-function view on moui 0.1.12, BEFORE this increment:
//!
//!   views/text/text_area_control.mbt:426   undefined variable 'anchor'
//!   views/text/text_input_editing.mbt:42   no method matching clamp_int(None, int, Any)
//!   views/navigation/navigation_routing.mbt:157
//!                                          no method matching RouteHistoryState::from_routes(Any, str, str)
//!   core/unicode/grapheme_cluster.mbt:428  unreachable code
//!   backend/web/web_host.mbt:357           no method matching web_string_append_char(None, Any)
//!   backend/web/web_host.mbt:359           no method matching web_finish_create_string(None)
//!   backend/linux/linux_services.mbt:183    no method matching >(None, float)
//!
//! AFTER it: ZERO. The per-function view on moui 0.1.12 reports
//! `actionable=0 notices=4225`, and the notices count did not move -- so
//! nothing was traded away to get there.
//!
//! SETTLED WITH THE TOOLCHAIN, `_verify/settle_0493_lens_values.ps1`, 21 rows
//! with TEN that REJECT. The controls are what make the ACCEPT rows mean
//! something: a blanket "stay silent" would pass them too.
//!
//!   b1_is_binding_in_else_if              ACCEPT  the `is` binding reaches the else-if body
//!   b4_control_binding_escapes_the_if     REJECT  the binding does not escape the `if`
//!   b5_control_binding_in_the_then_branch  REJECT  the binding is not in the then branch
//!   c1_match_branch_value_is_used          ACCEPT  a `match` inside an `if` branch
//!   c5_control_int_from_string             REJECT  a real type mismatch
//!   d1_labelled_call_omits_an_optional     ACCEPT  a labelled call that omits an optional
//!   d3_labelled_call_omits_a_required      REJECT  a labelled parameter is required
//!   d4_control_unknown_label               REJECT  a label the callee does not have
//!   e1_code_after_a_while_that_may_run_zero_times  ACCEPT
//!
//! => 判据: A CONTROL THAT CANNOT REJECT IS NOT A CONTROL. Every class below
//| has a row that says "the analyzer must still report this", and a row that
//| says "the analyzer must NOT report this", and the two are what make the
//| first one mean anything.
//!
//| => 判据: A LOOP MAY RUN ZERO TIMES. The analyzer's reachability rule was
//| "the statement after a terminator is unreachable", and it applied it to a
//| `while` whose BODY terminates. The loop itself may not run at all.
//|
//| => 判据: THE LABELS DECIDE THE BINDING, NOT THE POSITIONS. MoonBit lets a
//| call supply its arguments by name and reorder them; the type lens was
//| fixed for that in 0.4.5 and this lens never was.
//|
//| => 判据: "None" IS A CLAIM, AND IT WAS FALSE FOUR TIMES. A function whose
//| body yields no value was reported as returning Unit, and the four sites
//| where that showed up are four programs the toolchain accepts.

///|
/// CLASS B, THE POSITIVE ROW. The `is` pattern in an `else if` CONDITION
/// binds a name, and the name is in scope in that branch's body.
///
/// The analyzer evaluated the `else if` conditions in NO path that a library
/// module ever takes, so the binding was never introduced and the name was
/// reported `undefined variable` in the body that uses it.
test "0493: an `is` binding in an else-if condition reaches the branch body" {
  let r = @pipeline.run_functions(
    "fn f(x : Int?, c : Bool) -> Int {\n  if c {\n    1\n  } else if x is Some(a) {\n    a\n  } else {\n    0\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "UndefinedName", @core.LBehavior), 0)
}

///|
/// CLASS B, THE CONTROL. The same binding in a plain `if` condition worked
/// before this increment and must STAY working: a test that only asserts the
/// new behaviour cannot tell a fix from a change of noise.
test "0493: an `is` binding in an if condition still reaches the branch body" {
  let r = @pipeline.run_functions(
    "fn f(x : Int?) -> Int {\n  if x is Some(a) {\n    a\n  } else {\n    0\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "UndefinedName", @core.LBehavior), 0)
}

///|
/// CLASS B, THE OTHER DIRECTION. The `else if` condition is CODE, and it is
/// now evaluated -- so a name that exists NOWHERE in an `else if` condition is
/// REPORTED, where it was silently skipped before.
///
/// This is a false NEGATIVE that the fix removes, and it is the row that
/// shows the fix is not "evaluate nothing more loudly".
test "0493: an undefined name in an else-if condition is reported" {
  let r = @pipeline.run_functions(
    "fn f(c : Bool) -> Int {\n  if c {\n    1\n  } else if no_such_name_anywhere {\n    2\n  } else {\n    0\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "UndefinedName", @core.LBehavior), 1)
}

///|
/// CLASS C, THE POSITIVE ROW. A function whose body's value comes from a
/// `match` inside an `if` branch.
///
/// The `match` has no value this lens can name, so the branch's value was
/// bottom, and a function that yields no value was reported as returning
/// "None" -- a CONCRETE type, which then failed the callee's parameter check.
/// The toolchain ACCEPTS this program (settle row
/// `c1_match_branch_value_is_used`).
///
/// The CALL is in the fixture on purpose. The defect only shows at a CALL
/// SITE, because the branch is only taken when the condition is CONSTANTLY
/// false -- and at a call site the condition is a literal. Analysed as an
/// entry point the condition is unknown, both branches are explored, and the
/// join is the other branch's value.
test "0493: a function whose value comes from a match in an if branch keeps its declared type" {
  let r = @pipeline.run_functions(
    "fn take(n : Int) -> Int {\n  n\n}\n\nfn f(x : Int?, focused~ : Bool) -> Int {\n  if !focused {\n    0\n  } else {\n    match x {\n      Some(b) => b\n      None => 0\n    }\n  }\n}\n\nfn g() -> Int {\n  take(f(None, focused=true))\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "MethodError", @core.LBehavior), 0)
}

///|
/// CLASS C, THE EXTERN ROW. An extern function's body is written in another
/// language, so there is nothing here to execute -- and the DECLARED return
/// type is the only statement about what it returns that the file makes.
///
/// The toolchain ACCEPTS this program (settle row
/// `c3_extern_result_is_used`, on the native target -- `extern "C"` is not
/// supported on wasm, which is a fact about the BACKEND and not about the
/// type).
test "0493: an extern function's result carries its declared return type" {
  let r = @pipeline.run_functions(
    "extern \"C\" fn ext_scale() -> Double = \"moui_ext_scale\"\n\nfn g() -> Bool {\n  let s = ext_scale()\n  s > 0.0\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "MethodError", @core.LBehavior), 0)
}

///|
/// CLASS C, THE CONTROL, and the row that makes the two above mean
/// something: a REAL type mismatch is still reported. The toolchain REJECTS
/// this program (settle row `c5_control_int_from_string`).
test "0493: a real type mismatch is still a method error" {
  let r = @pipeline.run_functions(
    "fn take(n : Int) -> Int {\n  n\n}\n\nfn g() -> Int {\n  take(\"s\")\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "MethodError", @core.LBehavior), 1)
}

///|
/// CLASS D, THE POSITIVE ROW. A call that supplies its arguments BY LABEL,
/// and omits an optional one.
///
/// The callee declares FOUR parameters and the call supplies three. Compared
/// by position, the second argument -- a string -- was checked against the
/// second parameter, an Int, and the call was rejected. The toolchain
/// ACCEPTS this program (settle row `d1_labelled_call_omits_an_optional`).
test "0493: a labelled call that omits an optional parameter is accepted" {
  let r = @pipeline.run_functions(
    "fn from_routes(\n  routes~ : Array[String],\n  cursor? : Int = -1,\n  title? : String = \"\",\n  source? : String = \"app\",\n) -> Int {\n  routes.length() + cursor\n}\n\nfn g(s : Array[String]) -> Int {\n  from_routes(routes=s, title=\"x\", source=\"y\")\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "MethodError", @core.LBehavior), 0)
}

///|
/// CLASS D, THE CONTROL on the type check. A labelled argument of the WRONG
/// type is still a method error -- the label decides WHICH parameter the
/// argument belongs to, not whether the type fits.
test "0493: a labelled argument of the wrong type is still a method error" {
  let r = @pipeline.run_functions(
    "fn from_routes(\n  routes~ : Array[String],\n  cursor? : Int = -1,\n  title? : String = \"\",\n  source? : String = \"app\",\n) -> Int {\n  routes.length() + cursor\n}\n\nfn g(s : Array[String]) -> Int {\n  from_routes(routes=s, title=5, source=\"y\")\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "MethodError", @core.LBehavior), 1)
}

///|
/// CLASS D, THE CONTROL on the arity rule. A labelled parameter is REQUIRED
/// unless it has a default, and a call that omits it is an error. The
/// toolchain REJECTS this program with 4086 (settle row
/// `d3_labelled_call_omits_a_required`).
test "0493: a labelled call that omits a required parameter is a method error" {
  let r = @pipeline.run_functions(
    "fn from_routes(\n  routes~ : Array[String],\n  cursor? : Int = -1,\n  title? : String = \"\",\n) -> Int {\n  routes.length() + cursor\n}\n\nfn g(s : Array[String]) -> Int {\n  from_routes(title=\"x\")\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "MethodError", @core.LBehavior), 1)
}

///|
/// CLASS D, THE CONTROL on the label set. A label the callee does not have
/// is an error. The toolchain REJECTS this program with 4085 (settle row
/// `d4_control_unknown_label`).
test "0493: a label the callee does not have is a method error" {
  let r = @pipeline.run_functions(
    "fn from_routes(\n  routes~ : Array[String],\n  title? : String = \"\",\n) -> Int {\n  routes.length()\n}\n\nfn g(s : Array[String]) -> Int {\n  from_routes(routes=s, nope=\"x\")\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "MethodError", @core.LBehavior), 1)
}

///|
/// CLASS E, THE POSITIVE ROW. The statement after a `while` whose body always
/// terminates IS reachable: the loop may run ZERO times.
///
/// The toolchain does not settle reachability -- it ACCEPTS code after a
/// `return` as well (settle row `e3_control_code_after_a_return`, which
/// ACCEPTED), so the `Unreachable` family is a lint the toolchain does not
/// share. What settles THIS claim is the EXECUTION row of the same script:
/// the program prints 42, so the statement after the `while` really is
/// reached.
test "0493: the statement after a while that may run zero times is reachable" {
  let r = @pipeline.run_functions(
    "fn f(c : Bool) -> Int {\n  while c {\n    return 1\n  }\n  0\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "Unreachable", @core.LBehavior), 0)
}

///|
/// CLASS E, THE CONTROL. Code after a `return` is unreachable, and the
/// analyzer still says so. Without this row the row above would also pass if
/// the `Unreachable` family had simply been switched off.
test "0493: the statement after a return is still unreachable" {
  let r = @pipeline.run_functions(
    "fn f() -> Int {\n  return 1\n  0\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "Unreachable", @core.LBehavior), 1)
}

// pipeline_0555_test.mbt -- THE `if` PATH-JOIN AUDIT (0555).
//
// THE DEFECT. The behavioral lens joined the paths of an `if` WITHOUT the
// path that takes no branch, and based the alternative branches on the
// THEN-branch's environment. So a variable assigned only inside a branch read
// as DEFINITELY assigned after the `if`:
//
//     let mut x = false
//     if c { x = true }     // x is NOT true on every path
//     if x { return 1 }
//     2                      // reported `unreachable code` -- wrongly
//
// WHY IT MATTERS. The `Unreachable` family is the tool's reachability claim,
// and this defect made it report statements that ARE reached. It was found
// by a CROSS-CHECK: riantr/LunaFlow 0.1.3 -- an independent MoonBit analyzer
// -- was pointed at this module as a black box, and the two tools disagreed
// on the same tree. This file's own source is where the disagreement was
// measured: `src/sa/main.mbt:1729` in `parse_moon_mod_imports`.
//
// WHAT IS PINNED HERE. Four shapes that the defect reported wrongly, and one
// control: the code that really is unreachable is STILL reported. The control
// is the half that matters -- a fix that silenced the family would pass the
// four shape tests and would be a fix that removes the tool's claim instead of
// correcting it.
//
// The sixth row is the THIRD MECHANISM -- a `match`'s arms -- which 0555
// pinned as a defect and 0557 FIXED. That row asserts the fix now, and it is
// kept rather than deleted for 0524's reason: a deleted test cannot catch the
// defect coming back.

///|
/// Count findings of one family by its stable id.
fn count0555(rs : Array[@report.Report], id : String) -> Int32 {
  let mut n = 0
  for r in rs {
    if r.family.id() == id {
      n += 1
    }
  }
  n
}

///|
/// THE MINIMAL FORM: no `else`, so the fall-through path was the one left out
/// of the join.
test "0555: a value assigned only inside a branch is not taken as assigned after the if" {
  let src = "fn f(c : Bool) -> Int {\n  let mut x = false\n  if c {\n    x = true\n  }\n  if x {\n    return 1\n  }\n  2\n}\nlet y = f(true)\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0555(r.reports, "MSA-011"), 0)
}

///|
/// WITH AN `else`. The else branch ran when the condition was FALSE, so the
/// then-branch's assignment of `x` was not the value it started from -- and
/// the join of the two branches is what `x` is after the `if`.
test "0555: the same defect, with an else branch" {
  let src = "fn f(c : Bool) -> Int {\n  let mut x = false\n  if c {\n    x = true\n  } else {\n    let y = 1\n  }\n  if x {\n    return 1\n  }\n  2\n}\nlet z = f(true)\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0555(r.reports, "MSA-011"), 0)
}

///|
/// WITH AN `else if`. The alternative branch is reached when the earlier
/// conditions are false, so it starts from the state the `if` was reached in.
test "0555: the same defect, with an else if branch" {
  let src = "fn f(c : Bool, d : Bool) -> Int {\n  let mut x = false\n  if c {\n    x = true\n  } else if d {\n    let y = 1\n  }\n  if x {\n    return 1\n  }\n  2\n}\nlet z = f(true, true)\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0555(r.reports, "MSA-011"), 0)
}

///|
/// THE SHAPE THAT WAS FOUND ON THIS PROJECT'S OWN SOURCE. The flag is set on
/// one path and read on the next, through a loop, and the statement the old
/// code reported dead is the one that uses the flag.
test "0555: a flag set on one path of a loop is not read as set on every path" {
  let src = "fn g(items : Array[Int]) -> Int {\n  let mut inside = false\n  let mut n = 0\n  for raw in items {\n    if raw == 1 {\n      inside = false\n      continue\n    }\n    if !inside {\n      inside = true\n      continue\n    }\n    n += 1\n  }\n  n\n}\nlet m = g([1, 2, 3])\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0555(r.reports, "MSA-011"), 0)
}

///|
/// THE CONTROL. A statement after an unconditional `return` cannot run, and
/// the family says so. This row is the half of the audit that keeps the other
/// four honest: a fix that turned the family off would pass them.
test "0555: the control -- code that really is unreachable is still reported" {
  let src = "fn h() -> Int {\n  return 1\n  return 2\n}\nlet k = h()\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0555(r.reports, "MSA-011"), 1)
}

///|
/// THE THIRD MECHANISM -- FIXED IN 0557, AND THIS ROW NOW ASSERTS THE FIX.
///
/// A `match`'s arms are NOT evaluated by the behavioral lens -- 0469 and 0502
/// decided that on purpose, because the lens has no notion of which arm a
/// subject selects and evaluating one would be evaluating a path that may not
/// happen. The consequence was that a variable assigned ONLY inside an arm
/// read as DEFINITELY unassigned after the match:
///
///     let mut plain = false
///     if t > 0 {
///       match t {
///         1 => plain = true
///         _ => ()
///       }
///     }
///     if !plain { return st }
///     match st { ... }        // reported UNREACHABLE -- wrongly
///
/// MEASURED on this project's own source, `src/parser/parser.mbt:4221` in
/// `Parser::c_for_init` -- the tail `match st.kind` was reported unreachable,
/// and it is reached on the path where `plain_decl` is true.
///
/// THIS ROW USED TO ASSERT THE WRONG ANSWER ON PURPOSE, and its own
/// instruction was to be deleted when it went red. It went red in 0557. It is
/// kept and INVERTED rather than deleted, for 0524's reason: the defect is
/// exactly the kind that comes back -- a regression here is silent, and a
/// deleted test cannot catch it.
///
/// 0557's rule, and it is NOT "evaluate the arms": what an arm's body MAY
/// WRITE is collected SYNTACTICALLY -- the names, and nothing else -- and a
/// name an arm writes is no longer definitely known after the match. The arms
/// are still not evaluated, so 0469 and 0502 stand: an arm's READS are not
/// evaluated either, and an arm's `return` still does not make the match
/// return.
test "0555: a match arm that is never evaluated no longer over-reports (FIXED in 0557)" {
  // THE SHAPE 0555 PINNED. The published 0.4.45 artifact reports it -- one
  // MSA-011, on the tail `match` -- and this build reports none.
  let src = "fn k(t : Int) -> Int {\n  let mut plain = false\n  if t > 0 {\n    match t {\n      1 => plain = true\n      _ => ()\n    }\n  }\n  let st = t\n  if !plain {\n    return st\n  }\n  match st {\n    1 => 1\n    _ => 2\n  }\n}\nlet m = k(1)\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0555(r.reports, "MSA-011"), 0)
  // THE NESTED SHAPE -- the one measured on this project's own source, where
  // the write is in the arm of a match that is itself an arm.
  let src2 = "fn p(t : Int) -> Int {\n  let mut plain_decl = false\n  if t > 0 {\n    match t {\n      1 =>\n        match t {\n          2 => plain_decl = true\n          _ => ()\n        }\n      _ => ()\n    }\n  }\n  if !plain_decl {\n    return t\n  }\n  match t {\n    1 => 1\n    _ => 2\n  }\n}\nlet m = p(1)\n"
  let r2 = @pipeline.run(src2, "u.mbt", empty_iface())
  assert_eq(count0555(r2.reports, "MSA-011"), 0)
  // AND THE SAME RULE ON A `catch` ARM, whose body is not evaluated either.
  // `moon check --target all` accepts all three sources: a fixture the
  // toolchain rejects would be testing the wrong thing.
  let src3 = "fn c(t : Int) -> Int {\n  let mut flag = false\n  let r = t catch {\n    _ => {\n      flag = true\n      0\n    }\n  }\n  if !flag {\n    return r\n  }\n  r + 1\n}\nlet m = c(1)\n"
  let r3 = @pipeline.run(src3, "u.mbt", empty_iface())
  assert_eq(count0555(r3.reports, "MSA-011"), 0)
}

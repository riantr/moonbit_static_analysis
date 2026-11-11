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
/// THE THIRD MECHANISM, PINNED AS A DEFECT AND NOT AS A FEATURE.
///
/// A `match`'s arms are NOT evaluated by the behavioral lens -- 0469 and 0502
/// decided that on purpose, because the lens has no notion of which arm a
/// subject selects and evaluating one would be evaluating a path that may not
/// happen. The consequence is that a variable assigned ONLY inside an arm
/// reads as DEFINITELY unassigned after the match:
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
/// `Parser::c_for_init` -- the tail `match st.kind` is reported unreachable,
/// and it is reached on the path where `plain_decl` is true.
///
/// THIS IS NOT THE DEFECT 0555 FIXED. The defect 0555 fixed was the `if`'s
/// PATH JOIN: the fall-through path was missing from it, and an alternative
/// branch started from the then-branch's environment. Both are fixed and
/// pinned above. THIS ONE is the modelling limit underneath: the arm never
/// runs, so its write never happens.
///
/// THIS ROW ASSERTS THE WRONG ANSWER ON PURPOSE, and it is the audit's
/// record: the over-report exists, it is anchored on a line the next caller
/// runs, and the family's `excluded` contract now names it. WHEN THIS GOES
/// RED, the defect has been fixed -- delete this test, update NARRATIVE 0555,
/// and remove the `excluded` clause that names it. 0524's row, same rule.
test "0555: a match arm that is never evaluated still over-reports (NOT YET FIXED)" {
  let src = "fn k(t : Int) -> Int {\n  let mut plain = false\n  if t > 0 {\n    match t {\n      1 => plain = true\n      _ => ()\n    }\n  }\n  let st = t\n  if !plain {\n    return st\n  }\n  match st {\n    1 => 1\n    _ => 2\n  }\n}\nlet m = k(1)\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0555(r.reports, "MSA-011"), 1)
}

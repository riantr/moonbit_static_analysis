///|
/// 0501: THE SUPPRESSION IS PER BINDING, NOT PER FUNCTION.
///

///|
///
/// THE THING THAT WAS WRONG. `Walker::audit_suppressed` was a single Bool over
/// a function's extent: one region the frontend did not analyse anywhere in
/// the function switched off EVERY conclusion the frame could support. So a
/// `match` at the end of a function took the unused-local verdict away from a
/// binding declared at the top of it — a binding the unread region cannot
/// possibly have read, because the region comes later.
///

///|
///
/// WHAT IS ASSERTED HERE, and each assertion is a thing that can be WRONG:
///
///   1. A BINDING DECLARED AFTER THE REGION IS JUDGED. It could not have been
///      read inside a region that began before it existed. This is the
///      behaviour 0501 adds, and it is the whole point of it.
///   2. A BINDING DECLARED BEFORE THE REGION IS NOT JUDGED. The region's
///      content was never read and might use it — this is the old behaviour,
///      preserved, and it is the guard against a false positive.
///   3. THE FALSE-POSITIVE GUARD, spelled out: a binding declared BEFORE the
///      region and read ONLY inside it must NOT be reported. If the narrowing
///      were wrong in the direction that matters, THIS is the assertion that
///      goes red.
///   4. A PARAMETER IS STILL NOT JUDGED IN A FUNCTION WITH A REGION. A
///      parameter is in scope for the whole body, so any region can read it.
///   5. THE CONTROL: a binding in a function with NO region is judged, exactly
///      as it always was.
///   6. THE REGION IS STILL RECORDED. The narrowing changes what is concluded
///      about the frame; it must not change what is said about the coverage.
///      A `notice` that disappears is a coverage loss dressed as a fix.
///
test "0501: a local declared after a match is reported unused" {
  let src = "fn f(z : Int) {\n  match z {\n    0 => 1\n    _ => 0\n  }\n  let never_read = 1\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 1)
}

///|
/// The same shape with an `if`, which is a different region and a different
/// parser arm. One shape would pass while the other was broken.
///
/// THE `if` IS IN EXPRESSION POSITION, and that is not a detail. A
/// STATEMENT-position `if` is parsed into the tree and its branches are
/// analysed, so it creates NO region at all -- the next test says so
/// explicitly, because this one was written with a statement-position `if`
/// first and was passing for the wrong reason: it asserted the verdict, and
/// the verdict was the same with and without the narrowing.
test "0501: a local declared after an if expression is reported unused" {
  let src = "fn f(z : Int) {\n  let _ = if z > 0 {\n    1\n  } else {\n    0\n  }\n  let never_read = 1\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 1)
  assert_eq(count_family(r, "ParseError"), 1)
}

///|
/// WHY THE POSITION MATTERS, stated as a test. A statement-position `if` is
/// NOT a region: the parser reads its branches into the tree and the walker
/// analyses them, so there is no hole and nothing is suppressed.
///
/// This is the assertion that makes the test above mean something. Without it,
/// "a local declared after an `if` is reported" could be true of a
/// statement-position `if` -- where there is no region and no narrowing
/// involved -- and the narrowing would never have been tested at all.
test "0501: an if in statement position is not a region" {
  let src = "fn f(z : Int) {\n  if z > 0 {\n    1\n  } else {\n    0\n  }\n  let never_read = 1\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 1)
}

///|
/// THE GUARD. The binding is declared before the region, so the region could
/// have read it. It must not be reported.
test "0501: a local declared before a match is not reported" {
  let src = "fn f(z : Int) {\n  let maybe_used = 1\n  match z {\n    0 => 1\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// THE FALSE-POSITIVE GUARD, spelled out. `maybe_used` is read ONLY inside the
/// match arms, and the arms were never read, so the analyzer cannot see the
/// read. The verdict must be silence, not "unused" — the binding is used.
///
/// This is the assertion that goes red if the narrowing ever judges a binding
/// an unread region might have read. It is the one that matters.
test "0501: a local read only inside a match is not reported unused" {
  let src = "fn f(z : Int) {\n  let maybe_used = 1\n  match z {\n    0 => maybe_used\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// A PARAMETER is in scope for the whole body, so any region in the function
/// can read it. The narrowing reaches LOCALS; it must not reach parameters.
test "0501: a parameter in a function with a match is not reported" {
  let src = "fn f(unused_param : Int, z : Int) {\n  match z {\n    0 => 1\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE CONTROL. No region, so the frame is judged whole, exactly as it always
/// was. Without this, a change that switched the family off everywhere would
/// make every assertion above pass.
test "0501: a local in a function with no match is reported unused" {
  let src = "fn f() {\n  let never_read = 1\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 1)
}

///|
/// THE REGION IS STILL RECORDED. The narrowing changes what is concluded about
/// the frame; it must not change what is said about the coverage. A `notice`
/// that disappears is a coverage loss dressed as a fix.
test "0501: the match is still reported as a notice" {
  let src = "fn f(z : Int) {\n  match z {\n    0 => 1\n    _ => 0\n  }\n  let never_read = 1\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "ParseError"), 1)
}

///|
/// THE EXTENT FILTER, which nothing else here exercises. The region is in the
/// SECOND function and the binding is in the FIRST. A region in another
/// function cannot have read this binding -- and before 0501 the check was a
/// line-range overlap against the function's whole extent, so the two were
/// already told apart by that. This pins that they still are.
test "0501: a region in another function does not silence this function's binding" {
  let src = "fn first() {\n  let never_read = 1\n}\nfn second(z : Int) {\n  match z {\n    0 => 1\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 1)
  assert_eq(count_family(r, "ParseError"), 1)
}

///|
/// AND THE TWO TOGETHER, which is the shape the corpora are full of: a region
/// in the middle of a function, a binding after it, and a binding before it
/// that the region could have read. One verdict, one silence, one notice.
test "0501: a frame with a region judges the binding after it and spares the one before" {
  let src = "fn f(z : Int) {\n  let maybe_used = 1\n  match z {\n    0 => maybe_used\n    _ => 0\n  }\n  let never_read = 1\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 1)
  assert_eq(count_family(r, "ParseError"), 1)
}

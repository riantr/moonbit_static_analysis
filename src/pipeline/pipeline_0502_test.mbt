///|
/// 0502: A `match`'s ARMS ARE WALKED, SO THE FAMILIES COME BACK.
///
/// The rule these rows hold is one sentence: the arms of a `match` are real
/// code, and this frontend now reads them.
///
/// Before this increment the arms were consumed whole, which left a HOLE in
/// the frame of the enclosing function -- and a hole silenced `UnusedLocal` and
/// `UnusedParam` for that WHOLE function. The corpora measured ZERO actionable
/// findings across six of seven pinned trees because of it.
///
/// => 判据: A FIX THAT MAKES A FINDING APPEAR MUST BE CHECKED AGAINST THE FINDING
/// IT MAKES APPEAR. Reading the arms is what makes these findings TRUE: a binding
/// read only inside an arm body is read, and one read nowhere is dead. The first
/// row below is the one that says the arms were read, and every other row is
/// meaningless without it.

///|
/// THE FALSE-POSITIVE GUARD, and the one that matters. `maybe_used` is read
/// ONLY inside the match's arm body, and the arm body is walked now -- so the
/// analyzer SEES the read and the binding is not dead. Before this increment the
/// verdict was the same (silence) for the opposite reason: the arm body was
/// never read, and the match's HOLE silenced the whole frame.
///
/// The two reasons are indistinguishable from the verdict and opposite in
/// meaning, so this row is paired with the row below it: if the arm body were
/// NOT walked, the row below would report a finding that does not exist.
test "0502: a local read only inside a match arm is not reported" {
  let src = "fn f(z : Int) {\n  let maybe_used = 1\n  match z {\n    0 => maybe_used\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// AND ITS COUNTERPART: the same shape with the read REMOVED. `dead` is
/// declared and never read anywhere -- not in the subject, not in an arm body
/// -- so it is dead, and it is reported.
///
/// This is the finding the match's hole was hiding, and it is the reason the
/// hole had to go: the hole could not tell the two apart.
test "0502: a local read nowhere in a function with a match is reported" {
  let src = "fn f(z : Int) {\n  let dead = 1\n  match z {\n    0 => 1\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 1)
}

///|
/// A PARAMETER read only inside an arm body is not reported, for the same
/// reason a local is not.
test "0502: a parameter read only inside a match arm is not reported" {
  let src = "fn f(p : Int, z : Int) {\n  match z {\n    0 => p\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// AND ITS COUNTERPART: a parameter read NOWHERE in a function with a match is
/// reported. This is the second half of what the hole was hiding -- 801 of the
/// 1098 findings the probe measured were `UnusedParam`.
test "0502: a parameter read nowhere in a function with a match is reported" {
  let src = "fn f(p : Int, z : Int) {\n  match z {\n    0 => 1\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// A PATTERN'S NAMES ARE NOT AUDITABLE, and this row is what says so. `v` is
/// bound by the pattern and never read, and it is NOT reported as an unused
/// local: a pattern binding is not an ordinary local, and `Some` in `Some(v)`
/// is a constructor rather than a variable.
///
/// THE MECHANISM IS `Walker::bind_pattern`, which puts a name in the frame
/// WITHOUT putting it in the audit list. If the arm's names went through
/// `bind` instead, this row would report two unused locals -- `v` and `Some` --
/// on code `moon check` accepts. That is the same trade `ECatch` makes for its
/// handler patterns.
test "0502: a pattern's names are not reported as unused locals" {
  let src = "fn f(z : Int) {\n  match z {\n    Some(v) => 0\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THERE IS NO NOTICE ANY MORE, and the absence is the point. The notice said
/// "read but not analysed", which was TRUE when the arms were skipped and is
/// FALSE now: the arms are analysed.
///
/// The `n_subset` assertion is what makes this non-vacuous in the other
/// direction -- a build where the arms were skipped again would carry the
/// notice AND would report no findings, and the row above would fail.
test "0502: a match is no longer a deliberate exclusion" {
  let src = "fn f(z : Int) {\n  let dead = 1\n  match z {\n    0 => 1\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(r.n_subset, 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// THE ARM BODY IS ANALYSED, so a name NOTHING binds inside it is reported.
/// This is a class of finding that did not exist before this increment: the
/// arm body was never read, so a name in it could not be reported.
///
/// The row is here because it is the OTHER direction of the same claim. The
/// rows above say the arm body does not make a LIVE binding look dead; this one
/// says the arm body does make a DEAD name look dead.
test "0502: a name nothing binds inside an arm body is reported" {
  let src = "fn f(z : Int) {\n  match z {\n    0 => nothing_binds_this\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND A `let` INSIDE AN ARM BODY IS VISIBLE TO THAT ARM BODY, which is the
/// COLLECTOR's half of the change. `walk_expr` finds things and
/// `collect_expr_bindings` makes a BINDING visible -- they are different jobs,
/// and a row that only exercises the first leaves the second unmeasured.
///
/// So the arm body binds `q` and then reads it. If the collector never entered
/// the arm body, `q` would be bound nowhere and the arm would report it
/// undefined -- a false positive on correct code.
test "0502: a binding made inside an arm body is visible to that arm body" {
  let src = "fn f(z : Int) {\n  match z {\n    0 => {\n      let q = 1\n      q\n    }\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND ITS CANARY, which is what makes the row above a measurement rather than
/// a hope: the identical shape with the binding's name changed to one nothing
/// binds.
test "0502: a name nothing binds inside an arm body is still reported (canary)" {
  let src = "fn f(z : Int) {\n  match z {\n    0 => {\n      let q = 1\n      nope\n    }\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// A GUARD IS READ TOO. `pattern if cond => body` -- the condition is an
/// EXPRESSION, it runs before the body, and it is real code whose reads are
/// real. A parameter read ONLY by a guard is not dead.
///
/// The guard is not a statement of the enclosing function, and it is not part
/// of the arm's body either: it is the arm's own CONDITION, and it is carried
/// apart from the body for that reason.
test "0502: a parameter read only inside a match arm's guard is not reported" {
  let src = "fn f(p : Int, z : Int) {\n  match z {\n    0 if p > 0 => 1\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// AND ITS CANARY: the same shape with the guard reading something else, so
/// the parameter really is dead. Without this row the one above would also
/// pass on a build where unused parameters are not reported at all.
test "0502: a parameter read by no guard is reported (canary)" {
  let src = "fn f(p : Int, z : Int) {\n  match z {\n    0 if z > 0 => 1\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// AND THE GUARD CAN READ THE ARM'S OWN BINDING, which pins the ORDER: the
/// pattern's names are bound BEFORE the guard is walked, because the guard
/// comes after the pattern in the source and reads what the pattern binds.
///
/// A walk that read the guard first would report `v` as undefined -- a false
/// positive on correct code, and one that would only show up on an arm whose
/// guard mentions the pattern's own name.
test "0502: an arm's guard can read the arm's own binding" {
  let src = "fn f(z : Int?) -> Int {\n  match z {\n    Some(v) if v > 0 => v\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

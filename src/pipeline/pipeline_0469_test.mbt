//| Tests for 0469, a `match` whose ARMS are skipped -- and what its value is.
//|
//| Until this increment `parser.mbt`'s `TName("match")` arm read the subject and YIELDED
//| IT. That is the one place in the parser where "the expression I had to parse to keep
//| the token stream in step" and "the value this expression produces" are different
//| things: a `match`'s value is the join of its arms, and the arms are what this analyzer
//! skips.
//!
//| Measured on moonbit_image 0.3.7 `png.mbt:980`:
//!
//!     operand of '!' must be bool, got 'int'
//!
//| for `!vok`, because `let vok = match bd { .. }` typed `vok` as `bd`'s type. That was
//! moonbit_image's `actionable`, and 0468 only made the file readable -- it did not cause
//! it.
//!
//| THE OBVIOUS FIX WAS WRONG AND WAS WRITTEN FIRST. Yielding the bare `EBigInt` the
//! anonymous-`fn` arm uses fixes the type and LOSES THE SUBJECT'S READS, which turns two
//! TRUE positives in `pipeline_0433_test.mbt` into false negatives. A true positive traded
//! for the absence of a false one is not a trade worth making. `EMatch(subject)` carries
//! the subject and says nothing about the value -- see `@ast.EMatch` for why it cannot be
//! folded into `ECatch`.
//!
//! => 判据: "the fix removed the finding" is not the same claim as "the fix removed the
//! defect". Only the second one is worth shipping, and telling them apart costs one test
//! run. Every row here exists because the cheap version passed the corpus and failed two
//! unit tests.
//!
//! EVERY ROW BELOW ASSERTS `ParseError == 1`, and that is not sloppiness -- it is the skip
//! notice `match expression is outside the analyzed subset`, which the family counter
//! files under `ParseError`. The first version of this file asserted zero and six rows
//! went red on it. Asserting one is STRONGER than omitting the assertion: it pins that the
//! match is still deliberately skipped rather than silently analysed as though it were
//! read. The one row with no `match` in its fixture asserts zero, and the contrast is the
//! point.

///|
/// THE DEFECT, AS IT WAS. `!vok` where `vok` is bound to a `match` is NOT an operator
/// error: `vok`'s type is unknown, because the arms that would decide it are skipped.
/// Before 0469 this reported `operand of '!' must be bool, got 'int'` on code
/// `moon check` compiles -- a manufactured finding, on the analyzer's own blindness.
test "0469: `!` on a match-bound value is not an operator mismatch" {
  let r = @pipeline.run(
    "///|\nfn f(bd : Int) -> Bool {\n  let vok = match bd {\n    1 => true\n    _ => false\n  }\n  !vok\n}\n",
    "matchnot.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
  assert_eq(count_family(r, "OperatorMismatch"), 0)
}

///|
/// THE CONTROL THAT GIVES THAT ROW ITS MEANING. The identical file with `let vok = bd`
/// instead of a `match` IS an Int where a Bool is required, and must still say so. If this
/// went to zero, the operator lens had stopped looking and the row above proved nothing.
test "0469: `!` on a plain Int is still an operator mismatch" {
  let r = @pipeline.run(
    "///|\nfn f(bd : Int) -> Bool {\n  let vok = bd\n  !vok\n}\n",
    "matchcanary.mbt",
    @core.IfaceSymTab::empty(),
  )
  // ZERO here, and the contrast with every other row in this file is the point: there is
  // no `match` in this fixture, so there is no skip notice. `ParseError == 1` everywhere
  // else in this file is that notice and nothing else -- `match expression is outside the
  // analyzed subset; it was read but not analysed` -- which is a DESIGNED limitation
  // counted under this family, exactly as the anonymous-`fn` notice is.
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "OperatorMismatch"), 1)
}

///|
/// THE OTHER HALF, AND THE REASON THE FIRST FIX WAS REJECTED. The subject is real,
/// analysed code: an undefined name used ONLY as a match subject is still reported.
/// Dropping the subject would have made this zero, and zero here is a FALSE NEGATIVE.
///
/// `pipeline_0433_test.mbt` already pins this from the parser side; it is restated here
/// because the two rows failed TOGETHER when the subject was dropped, and a guard that
/// exists only in one file is one refactor away from moving.
test "0469: an undefined name in a match subject is still reported" {
  let r = @pipeline.run(
    "///|\nfn f(c : Int) -> Int {\n  match\n    missing(c) {\n    1 => 2\n    _ => 3\n  }\n}\n",
    "matchsubj.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE CANARY BESIDE THAT, which is what a zero in the row above has to be measured
/// against. Identical except for the name.
test "0469: a defined name in a match subject is not reported" {
  let r = @pipeline.run(
    "///|\nfn sub(x : Int) -> Int {\n  x\n}\n\n///|\nfn f(c : Int) -> Int {\n  match\n    sub(c) {\n    1 => 2\n    _ => 3\n  }\n}\n",
    "matchsubjok.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// A ROW THAT WAS HERE AND WAS VACUOUS, recorded because deleting a row silently is how a
/// coverage hole becomes permanent. This asserted `UnusedParam == 0` for a parameter read
/// only inside a match subject, on the claim that removing the walk would move it to 1.
///
/// It is 0 whether or not the subject is walked, and the reason is in `pipeline_0433`:
/// A `match` SILENCES `UnusedParam` for its whole enclosing function by design. So the row
/// could not fail, and a row that cannot fail is not a guard -- it is a comment with an
/// `assert_eq` in it. M2 of `mutate_0469.ps1` measured this: deleting `walk_expr`'s
/// `EMatch` arm reddened three rows and not this one.
///
/// => 判据: before keeping a negative row, ask whether ANY mutation can turn it red. If the
/// mechanism that makes it pass is the same one that suppresses the finding regardless of
/// the property, the row is decoration.
///
/// The property it meant to pin is pinned by the row above: an undefined name in the
/// subject is reported, which is only possible if the subject is walked.
test "0469: without any match, an unread parameter is still reported unused" {
  let r = @pipeline.run(
    "///|\nfn sub(x : Int) -> Int {\n  x\n}\n\n///|\nfn f(c : Int) -> Int {\n  0\n}\n",
    "matchunused.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// A MATCH IN STATEMENT POSITION, which is where moui writes it throughout and where the
/// value was never the issue -- `match .. { }` as a statement throws the result away, so
/// the arms being unknown cannot mislead anything. The row exists because statement and
/// `let` position share one arm, and this is what says the shared claim is safe in the
/// position where the old behaviour happened to be harmless.
test "0469: a match in statement position is still read and reported no error" {
  let r = @pipeline.run(
    "///|\nfn sub(x : Int) -> Int {\n  x\n}\n\n///|\nfn f(c : Int) -> Unit {\n  match\n    sub(c) {\n    1 => ()\n    _ => ()\n  }\n}\n",
    "matchstmt.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE COLLECTOR DESCENT, which is a SEPARATE ARM from the walker's and the only thing
/// this row can see. `walk_expr` finds things; `collect_expr_bindings` makes a BINDING
/// visible. Those are different jobs and a row that only exercises the first leaves the
/// second unmeasured -- the 0467 M7 and 0468 M8 lesson, a third time.
///
/// So the subject here contains a `catch` arm with a `let` in it, and the arm's own tail
/// reads that binding. If the collector never enters the match subject, `recovered` is
/// bound nowhere and the arm tail reports it undefined. The first version of this row put
/// a `catch` in the subject and asserted zero UndefinedNames, which is 0 whether or not
/// the collector descends -- and M3 survived 857/857 because of it.
test "0469: a binding made inside a match subject is visible to the subject" {
  let r = @pipeline.run(
    "///|\nfn fallible() -> Int {\n  1\n}\n\n///|\nfn f() -> Int {\n  let v = match\n    fallible() catch {\n    _ => {\n      let recovered = 1\n      recovered\n    }\n  } {\n    1 => 2\n    _ => 3\n  }\n  v\n}\n",
    "matchbind.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND ITS CANARY, which is what makes the row above a measurement rather than a hope: the
/// identical shape with the binding's name changed to one nothing binds.
test "0469: a name nothing binds inside a match subject is still reported" {
  let r = @pipeline.run(
    "///|\nfn fallible() -> Int {\n  1\n}\n\n///|\nfn f() -> Int {\n  let v = match\n    fallible() catch {\n    _ => {\n      let recovered = 1\n      nope\n    }\n  } {\n    1 => 2\n    _ => 3\n  }\n  v\n}\n",
    "matchbindcanary.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

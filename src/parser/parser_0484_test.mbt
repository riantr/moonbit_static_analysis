//| Tests for 0484 -- a TRAIT METHOD WHOSE RECEIVER IS A REFERENCE, `fn &Trait::method`.
//
//| THE DEFECT. `fn &Data::binary(self : &Data) -> Bytes` is the boundary line of two of async's
//| unreadable files -- `io/data.mbt:77` and `process/redirect.mbt:229` -- and it read as an
//| unexpected `TAmp` where the function name belonged. Measured against this analyzer's own parser
//| with a ten-case probe, not inferred:
//
//|     fn Data::binary(self : Data)            -> Bytes { }        first_error = 0  <- already works
//|     impl Data with fn binary(_)             { }                  first_error = 0  <- already works
//|     type Ref = &Data                                             first_error = 0  <- `&` is fine
//|     fn @other.Buf::repr(b : @other.Buf)     -> Int = "%identity" first_error = 0  <- 0483 control
//|     fn &Data::binary(self : &Data)          -> Bytes { }        first_error = 2  <- HERE
//|     pub fn &Data::binary(self : &Data)      -> Bytes { }        first_error = 2
//|     pub fn &Data::text(self : &Data)        -> String raise { } first_error = 2
//|     fn &Data::binary(self : &Data)          -> Bytes = "%id"     first_error = 2
//|     extern "C" fn &Data::binary(...)        = "x"                first_error = 2
//|     fn &&Data::binary(self : &&Data)        -> Bytes { }        first_error = 2
//
//| The body is IRRELEVANT and the `&` IN FRONT OF THE HOLDER is decisive. Same shape as 0483:
//| reading the boundary line would have built an extern-body production for a body this parser
//! already reads in every other spelling.
//!
//| *** THE FIRST FRAMING WAS WRONG AND `moon check` SAID SO. *** The obvious reading of
//| `fn &Type::method` is "a method on Type, declared through a reference". It is a TRAIT's default
//!| method whose receiver is a reference. Both fixture drafts declared `Data` as a struct and every
//!| row came back 4100 "The type Data is not a trait" -- and the corpus said so all along, at
//!| `io/data.mbt:23` and `process/redirect.mbt:212`, where `Data` and `ProcessInput` are declared
//!| with `trait`. A reader that got the tokens right and the meaning wrong would have passed every
//!| corpus number.
//!
//| THE TOKEN SHAPE IS NOT 0483's. `Lexer::run` starts a name at `is_letter(c) || c == '@'`, so `@`
//! glues INTO the name and `@other` is ONE `TName`. `&` is not a name-start character: it falls
//! through to `lex_op`, which maps `'&' => TAmp`. So the `&` here is a STANDALONE token in front of
//!| an ordinary `TName` -- copying 0483's shape would have produced a fix that silently does
//!| nothing.
//!
//| Settled in `_verify/settle_0484_ref_holder.ps1`, 19 rows / 3 controls, GATE OK:
//!   ACCEPT  `fn &Trait::m(self : &Trait)`              the corpus shape, with and without `pub`
//!   ACCEPT  the same with a `-> T raise` tail
//!   ACCEPT  called as `d.m()` through a `&Trait`       so `m` IS a method of the trait
//!   ACCEPT  `fn &Trait::m(...) = "%identity"`          so the body really is not the point
//!   ACCEPT  `fn &@other.Trait::m(...)`                 0483's prefix and this one COMPOSE
//!   ACCEPT  `async fn &Trait::m(...)`
//!   REJECT(4100)  the same declaration on a STRUCT      <- the control that makes `trait` measured
//!   REJECT(4032)  EVERY unqualified spelling            <- forces the `&` out of the AST name
//!   REJECT(4099)  `Trait::m(x)` -- a trait is not a type, so there is no by-path call form
//!   REJECT(4074)  `fn &&Trait::m` -- read deliberately? NO: not read, see the guard test below
//!   REJECT(4156)  `extern "C" fn &Trait::m`

///|
/// THE DECLARATION IS READ, AND THE NAME IS THE FOLDED HOLDER.
test "0484: an & trait holder reads whole" {
  let r = @parser.parse(
    "///|\npub fn &Data::binary(self : &Data) -> Int {\n  1\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(name, _, _, _, _) => assert_eq(name, "Data::binary")
    _ => assert_true(false)
  }
}

///|
/// THE `&` IS DROPPED FROM THE NAME, which is a DECISION and not a convenience.
///
/// The name could have been recorded as `&Data::binary`. It is not, and the settle is what forces
/// it: `moon check` refuses `Trait::m(x)` (4099 "`Data` is a trait, not a type") and refuses every
/// unqualified `Trait::m` declaration (4032), so `m()` is the only spelling on BOTH sides and
/// `Data::binary` is the only name anything could ever look up. Keeping the `&` would have made
/// the name unmatchable rather than more precise.
///
/// This row is what makes the decision falsifiable: if the name ever became `&Data::binary` this
/// goes red, which is the point -- the alternative would have been invisible.
test "0484: the & is not part of the recorded name" {
  let r = @parser.parse(
    "///|\nfn &Data::binary(self : &Data) -> Int {\n  1\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(name, _, _, _, _) => {
      assert_eq(name, "Data::binary")
      assert_true(name != "&Data::binary")
    }
    _ => assert_true(false)
  }
}

///|
/// THE HARVEST, ASSERTED DIRECTLY rather than inferred from a downstream finding.
///
/// This is the row 0483's memory is about. A harvest-shaped claim routed through `@pipeline.run`
/// can be VACUOUS: the lens may resolve the name through a path that never consulted the sibling
/// table, the row goes green, and the harvest is still broken. `@parser.collect_declared_names`
/// hands back the table itself, so the claim is asked of the component that holds it.
test "0484: the harvest records the folded holder" {
  let tab = @parser.collect_declared_names(
    "///|\nfn &Data::binary(self : &Data) -> Int {\n  1\n}\n",
  )
  assert_true(tab.has_value("Data::binary"))
}

///|
/// BOTH PREFIXES AT ONCE, and this is the row with NO corpus instance anywhere.
///
/// 0483 settled `@other.Trait::m` and 0484 settles `&Trait::m`; the toolchain ACCEPTs
/// `fn &@other.Trait::m(b : &@other.Trait) -> Int`, and nothing in six corpora writes one. Two
/// fixes that each pass their own rows can still disagree here, because the `&` is consumed BEFORE
/// the name is read while the `@` lives INSIDE the name token -- the two prefixes are adjacent in
/// the source and on opposite sides of the reader's cursor.
///
/// Asserted on BOTH readers: the AST name AND the harvest entry, because a disagreement between
/// them is not a parse error and is not a finding -- it is a missing sibling-table row that
/// surfaces much later as a false `undefined name`.
test "0484: & and @pkg compose, on both readers" {
  let src = "///|\nfn &@other.Trait::m(b : &@other.Trait) -> Int {\n  1\n}\n"
  let r = @parser.parse(src)
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(name, _, _, _, _) => assert_eq(name, "@other.Trait::m")
    _ => assert_true(false)
  }
  let tab = @parser.collect_declared_names(src)
  assert_true(tab.has_value("@other.Trait::m"))
}

///|
/// THE TYPE-PARAMETER LIST ON THE OTHER SIDE OF THE `&`.
///
/// `fn[T] &Trait::m` puts the `&` after the `[...]` rather than before it. `declared_name_after_kw`
/// used to skip exactly one thing -- the `[...]` -- and this fix adds a second skip. Two skips in
/// sequence is exactly the kind of change that handles the first order and quietly keeps the
/// second, because nothing in the corpus writes it and no error appears either way: the harvest
//! simply loses the name.
test "0484: fn[T] &Trait::m harvests" {
  let tab = @parser.collect_declared_names(
    "///|\nfn[T] &Data::binary(self : &Data) -> Int {\n  1\n}\n",
  )
  assert_true(tab.has_value("Data::binary"))
}

///|
/// THE `&`-FIRST ORDER STILL WORKS, so the loop above did not replace the behaviour it extended.
test "0484: & before the type-parameter list also harvests" {
  let tab = @parser.collect_declared_names(
    "///|\nfn &Data::binary(self : &Data) -> Int {\n  1\n}\n",
  )
  assert_true(tab.has_value("Data::binary"))
}

///|
/// THE GUARD: `&&Trait::m` IS NOT READ.
///
/// The settle says `fn &&Data::deep` is refused 4074/3002 -- a reference to a reference is not a
/// thing. A reader that accepted the `&&` token in holder position would parse it, which is the
/// liberal direction: a false NEGATIVE (a missed error) on code nobody writes.
///
/// *** THE FIRST DRAFT OF THIS ROW WAS NOT ISOLATING THE CONSTRUCT, AND THE MUTATION GATE CAUGHT
/// IT. *** The fixture was `fn &&Data::deep(self : &&Data)`, which carries `&&` in TWO places. The
/// mutation that widens the holder to the logical-and token left the suite green, because the
/// PARAMETER TYPE `&&Data` fails on its own whether or not the holder was read -- so the row was
/// green for a reason that had nothing to do with what it claimed to guard. The parameter is `Int`
/// now, so the only `&&` in the fixture is the one this row is about.
///
/// `&&` IS ONE TOKEN, and that is why the mutation has to name it rather than count `&`s:
/// `lex_op` folds `&&` into a single logical-and token, so no number of `TAmp` bumps can reach it.
/// The first draft of M5 widened the `if` to a `while` over `TAmp`, SURVIVED, and looked like a
/// vacuous guard rather than a lexing fact.
///
/// The lesson is the one 0483's harvest rows turned on: a row is vacuous when you cannot say
/// WHICH thing would make it red -- and a GUARD row is vacuous in the same way when it cannot be
/// red for a reason of its own.
test "0484: a double & holder is not read" {
  let r = @parser.parse("///|\nfn &&Data::deep(x : Int) -> Int {\n  1\n}\n")
  assert_true(r.first_error > 0)
}

///|
/// AN ORDINARY SIGNATURE IS UNTOUCHED, so the `&` skip did not leak into ordinary declarations.
test "0484: an ordinary fn is unaffected" {
  let r = @parser.parse("///|\nfn Data::binary(self : Data) -> Int {\n  1\n}\n")
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(name, _, _, _, _) => assert_eq(name, "Data::binary")
    _ => assert_true(false)
  }
}

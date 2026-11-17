// pipeline_0603_test.mbt -- the TARGETS THE ANALYZER COULD NOT RESOLVE, and
// the pair that says how many of them it can now.
//
// 0603. The `.mbti` reader used to throw the parameter list away, so a
// cross-file call had no arity to check against and was "unchecked" with
// nothing to check it against. The deck's p.32 names the shape of that problem
// -- "Reflection targets cannot be resolved if the string values are statically
// unknown" -- and p.35 names the answer: "When string arguments cannot be
// resolved statically, infer the reflective targets at their usage points!"
//
// SO THE TARGETS ARE INFERRED HERE, and these tests pin two numbers:
//
//   n_sig_available   the unchecked calls whose callee the interface declares
//                     a signature for -- the targets that CAN be resolved
//   n_arity_agrees    of those, the ones whose declared arity matches the
//                     call's own argument count -- how many of the inferences
//                     are RIGHT
//
// AND IT IS THE DECK'S p.40 PAIR: "Infer 50 reflective target methods and 48
// methods are true!" An inference with no precision is a guess, so the two are
// counted together.
//
// IT IS A COUNT, NOT A CHECK. The analyzer still does not check a cross-file
// call's arguments: enforcing the arity is a change to what the analyzer
// FINDS, and that belongs to a release that re-measures the corpora.

///|
/// THE TARGET IS RESOLVABLE. `helper` is known only by NAME from another
/// package's interface, so the call is real and its arguments were not
/// checked -- and the interface declares ONE parameter, so the target's arity
/// is known and it agrees with the call.
test "a cross-file call whose .mbti declares a signature has a resolvable target" {
  let tab = @core.IfaceSymTab::empty()
  tab.add_value("helper")
  tab.add_sig("helper", @core.IfaceSig::{ params: [["UInt"]], ret: ["Unit"], })
  let src = "fn main() -> Unit {\n  let x = helper(1)\n  ignore(x)\n}\n"
  let r = @pipeline.run(src, "u.mbt", tab)
  // The call is still UNCHECKED: the analyzer did not check the arguments.
  assert_eq(r.n_unchecked, 1)
  // And the target is now RESOLVABLE, and its arity agrees.
  assert_eq(r.n_sig_available, 1)
  assert_eq(r.n_arity_agrees, 1)
}

///|
/// AND THE DISAGREEMENT IS COUNTED, not hidden. A signature that declares TWO
/// parameters against a call with ONE argument is a signature the analyzer
/// would have MIS-checked -- which is the whole reason the deck counts the
/// inferences and then counts how many were right.
test "a signature whose arity disagrees with the call is counted as a disagreement" {
  let tab = @core.IfaceSymTab::empty()
  tab.add_value("helper")
  tab.add_sig("helper", @core.IfaceSig::{
    params: [["UInt"], ["Action"]],
    ret: ["Unit"],
  })
  let src = "fn main() -> Unit {\n  let x = helper(1)\n  ignore(x)\n}\n"
  let r = @pipeline.run(src, "u.mbt", tab)
  assert_eq(r.n_unchecked, 1)
  assert_eq(r.n_sig_available, 1)
  assert_eq(r.n_arity_agrees, 0)
}

///|
/// THE CONTROL: a name-only callee with NO signature in the table is the state
/// the analyzer was in before 0603, and it must still count as no target at
/// all. A zero here is not "the analyzer stopped looking" -- the unchecked
/// count beside it says the call was still seen.
test "a name-only callee with no declared signature has no resolvable target" {
  let tab = @core.IfaceSymTab::empty()
  tab.add_value("helper")
  let src = "fn main() -> Unit {\n  let x = helper(1)\n  ignore(x)\n}\n"
  let r = @pipeline.run(src, "u.mbt", tab)
  assert_eq(r.n_unchecked, 1)
  assert_eq(r.n_sig_available, 0)
  assert_eq(r.n_arity_agrees, 0)
}

///|
/// AND THE EMPTY CASE, so that "0 of 0" cannot be read as "the analyzer
/// resolved nothing and found nothing wrong". A file with no call at all has
/// no target to infer.
test "a body with no call at all resolves no target" {
  let src = "fn main() -> Unit {\n  let x = 1\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_sig_available, 0)
  assert_eq(r.n_arity_agrees, 0)
}

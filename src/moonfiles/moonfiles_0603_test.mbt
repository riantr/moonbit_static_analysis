// moonfiles_0603_test.mbt -- the `.mbti` READER KEEPS THE PARAMETER LIST it
// used to throw away.
//
// 0603. `src/types/infer.mbt` used to say, as a fact, "a `.mbti` gives us the
// NAME, never the parameter list". It is false. The interface declares
//
//     pub fn action_mask_to_action_vec(UInt) -> Array[Action]
//
// and the reader parsed that parameter list -- and then kept only the SET of
// type names the whole line mentions, which cannot say WHICH parameter has
// which type, and cannot say how many there are.
//
// So every cross-file call was "unchecked" with nothing to check it against.
// That is the deck's p.32 in this tree's own words: "Problem: Reflection
// targets cannot be resolved if the string values are statically unknown" --
// except that here the name WAS resolvable and the thing that was missing was
// the TARGET's shape.
//
// THE DECK'S ANSWER, p.35: "When string arguments cannot be resolved
// statically, infer the reflective targets at their usage points!" So the
// reader keeps the signature, and these tests pin that it does.

///|
/// THE PARAMETER LIST IS KEPT, with its ORDER and its TYPES.
///
/// The arity is the deck's p.39 question ("The reflective target method at
/// line 175 must have one parameter and its declared type must be
/// FrameworkCommandInterpreter or its sub/supertypes"), and the declared type
/// of a parameter is the other half of it.
test "the .mbti reader keeps the parameter list it used to throw away" {
  let mbti = "pub fn action_mask_to_action_vec(UInt) -> Array[Action]\n"
  let tab = @moonfiles.collect_iface_names(mbti)
  match tab.sig("action_mask_to_action_vec") {
    Some(sig) => {
      assert_eq(sig.arity(), 1)
      assert_true(sig.param_types(0).contains("UInt"))
      assert_true(sig.ret.contains("Action"))
    }
    None => assert_true(false)
  }
}

///|
/// TWO PARAMETERS, in order, with DIFFERENT types -- which is the case the
/// set of type names could not express at all. A set says "this function
/// mentions UInt and Action"; the list says "the first argument is a UInt and
/// the second is an Action".
test "the kept parameter list keeps the order and each parameter's own types" {
  let mbti = "pub fn take(UInt, Action) -> Unit\n"
  let tab = @moonfiles.collect_iface_names(mbti)
  match tab.sig("take") {
    Some(sig) => {
      assert_eq(sig.arity(), 2)
      assert_true(sig.param_types(0).contains("UInt"))
      assert_true(sig.param_types(1).contains("Action"))
    }
    None => assert_true(false)
  }
}

///|
/// A METHOD'S SIGNATURE IS KEPT TOO, under the QUALIFIED name -- because that
/// is the name a use site resolves to. The receiver is the FIRST parameter,
/// which is what makes the declared arity and a qualified call's argument
/// count the same quantity on both sides.
test "a method's signature is kept under its qualified name, receiver first" {
  let mbti = "pub fn Type::method(Self, UInt) -> Unit\n"
  let tab = @moonfiles.collect_iface_names(mbti)
  match tab.sig("Type::method") {
    Some(sig) => assert_eq(sig.arity(), 2)
    None => assert_true(false)
  }
}

///|
/// A CONSTANT HAS NO PARAMETER LIST, and the reader must not invent one. Its
/// declared type is kept, and its arity is zero.
test "a constant keeps its declared type and has no arity" {
  let mbti = "pub const HEADER_SIZE : Int = 10\n"
  let tab = @moonfiles.collect_iface_names(mbti)
  match tab.sig("HEADER_SIZE") {
    Some(sig) => {
      assert_eq(sig.arity(), 0)
      assert_true(sig.ret.contains("Int"))
    }
    None => assert_true(false)
  }
}

///|
/// THE TABLE SAYS HOW MANY TARGETS IT RESOLVES TO A SIGNATURE, which is the
/// census the deck's p.35 asks for: the reflective targets that can be
/// inferred at their usage points.
test "the table counts the targets it resolves to a signature" {
  let mbti = "pub fn a(UInt) -> Unit\npub fn b(Action) -> Unit\npub fn c() -> Unit\n"
  let tab = @moonfiles.collect_iface_names(mbti)
  assert_eq(tab.n_sigs(), 3)
}

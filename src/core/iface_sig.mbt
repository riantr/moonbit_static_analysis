// 0603: THE SIGNATURE A `.mbti` DECLARES -- kept, not thrown away.
//
// THE DECK. `Soundiness` (Yue Li and Tian Tan, Nanjing University, 2021 Fall),
// p.32, on Java reflection:
//
//     Problem: Reflection targets cannot be resolved if the string values are
//     statically unknown
//
// and p.35, the answer:
//
//     When string arguments cannot be resolved statically, infer the reflective
//     targets at their usage points!
//
// THE ANALOGUE IN THIS TREE. A `.mbti` IS THE INTERFACE OF ANOTHER PACKAGE, and
// the analyzer reads it to learn which names exist across the package boundary.
// What it did NOT keep is the PARAMETER LIST. The line
//
//     pub fn action_mask_to_action_vec(UInt) -> Array[Action]
//
// says exactly how many arguments the callee takes and what their types are,
// and the reader parsed that list and then dropped it, keeping only the SET of
// type names the line mentions.
//
// THE CLAIM THAT DROPPED IT WAS WRONG, and it was written down as a fact.
// `src/types/infer.mbt` said "a `.mbti` gives us the NAME, never the parameter
// list", and that sentence is the reason. The corpus says otherwise, and the
// correction is in place with the measurement that refutes it.
//
// SO THE SIGNATURE IS KEPT HERE, and the lens asks the table whether the callee
// it could not check has a signature to check it against -- which is the deck's
// p.40 shape: "Infer 50 reflective target methods and 48 methods are true!"

///|
/// THE SIGNATURE of one value, as a `.mbti` declares it.
///
/// AND THIS IS THE PART THAT WAS THROWN AWAY. The `.mbti` line
///
///     pub fn action_mask_to_action_vec(UInt) -> Array[Action]
///
/// says how many arguments the callee takes and what their types are, and the
/// reader used to parse that and keep only the SET of type names the line
/// mentions.
pub(all) struct IfaceSig {
  /// The parameter types: ONE ARRAY PER PARAMETER, in order.
  ///
  /// AND THE ORDER IS THE POINT. A set of type names cannot say "the first
  /// argument is a `UInt` and the second is an `Action`", which is exactly what
  /// an argument check needs.
  params : Array[Array[String]]
  /// The return type's referenced type names.
  ret : Array[String]
}

///|
/// THE NUMBER OF PARAMETERS this signature declares.
///
/// AND IT IS THE ARITY THE DECK'S p.39 ASKS FOR: "The reflective target method
/// at line 175 must have one parameter and its declared type must be
/// FrameworkCommandInterpreter or its sub/supertypes."
///
/// AND THE RECEIVER COUNTS. A `.mbti` declares a method as
/// `pub fn Type::method(Self, x : Int) -> Int`, and a qualified call
/// `Type::method(recv, x)` passes the receiver as its first argument -- so the
/// declared arity and the call's argument count are the same quantity on both
/// sides, and comparing them is a comparison of like with like.
pub fn IfaceSig::arity(self : IfaceSig) -> Int32 {
  self.params.length()
}

///|
/// THE DECLARED TYPES of one parameter, in order.
pub fn IfaceSig::param_types(self : IfaceSig, index : Int32) -> Array[String] {
  match self.params.get(index) {
    Some(t) => t
    None => []
  }
}

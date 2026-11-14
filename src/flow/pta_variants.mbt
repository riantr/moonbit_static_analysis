// 0582: THE THREE CONTEXT-SENSITIVITY VARIANTS, COMPARED -- deck 11-12
// p.165-178.
//
// THE DECK'S THREE VARIANTS, and the pages that say what each one is:
//
//   p.99    "Call-site sensitivity / Object sensitivity / Type sensitivity"
//   p.100   OBJECT SENSITIVITY -- "Select(c, l, c': o_i)": the receiver object,
//           "with heap context".
//   p.103   CALL-SITE SENSITIVITY -- "Select(c, l, _) = [l_1, ..., l_k]";
//           "Each context consists of a list of call sites (call chain)".
//   p.165-166 CALL-SITE vs OBJECT -- "In theory, their precision is
//           incomparable" and "In practice, object sensitivity generally
//           outperforms call-site sensitivity for OO languages (like Java)".
//   p.170-171 TYPE SENSITIVITY -- "Each context consists of a list of types";
//           "At a method call, use the type containing the allocation site of
//           the receiver object with its heap context as callee context"; "A
//           coarser abstraction over object sensitivity"; the formula
//           "Select _, _, c: o_i = [t_1, ..., t_k, InType(o_i)]"; and the
//           worked note "InType(o3) = X (not Y!)".
//   p.172-175 TYPE vs OBJECT -- the three-allocations example: "Contexts of
//           foo(): Object-sensitivity: o3, o5, [o7]; Type-sensitivity: [X]";
//           "Under the same k-limiting, the precision of type sensitivity is
//           no better than object sensitivity"; "Type sensitivity is a coarser
//           abstraction over object sensitivity"; "Compared to object
//           sensitivity, type sensitivity trades precision for better
//           efficiency, by merging the allocation sites in the same type in
//           contexts".
//   p.177-178 THE THREE TOGETHER -- "Precision: object > type > call-site" and
//           "Efficiency: type > object > call-site", measured on ten Java
//           programs by Yue Li, Tian Tan, Anders Møller and Yannis Smaragdakis,
//           "A Principled Approach to Selective Context Sensitivity for Pointer
//           Analysis", TOPLAS 2020.
//
// THE MEASUREMENT THIS TREE CAN MAKE, AND THE ONE IT CANNOT.
//
//   * THE CONTEXTS are this tree's own measurement, and it is the deck's own
//     measurement too: p.174 prints "Contexts of foo()" and compares them.
//   * THE PRECISION is measured as well, and the way the deck states it --
//     as whether two invocations of the same method are kept apart.  The
//     merging is visible in the POINTS-TO sets, which is where a may-analysis
//     shows what it has merged.
//   * THE ORDERING "object > type > call-site" IS NOT REPRODUCIBLE HERE, and
//     the reason is worth stating rather than hiding: it is an EMPIRICAL
//     finding on ten Java programs, measured in seconds of analysis time and
//     in the number of may-fail casts and call-graph edges. This tree analyses
//     MoonBit, has no Java corpus, and has no may-fail-cast notion. What IS
//     reproduced is the RELATIONSHIP the ordering rests on: type sensitivity
//     is a coarser abstraction over object sensitivity, and the call-site and
//     object abstractions are incomparable in theory.
//
// THE BOUNDARY OF THE TYPE VARIANT, STATED PLAINLY. The deck's context is
// `InType(o_i)` -- the type CONTAINING the allocation site, and p.171 is
// emphatic about it: "InType(o3) = X (not Y!)", where the object is a `Y` and
// the containing class is `X`. THAT TYPE IS NOT READABLE HERE: it is the class
// a method's body sits in, and this tree's AST HAS NO METHOD BODIES -- the
// parser reads past `impl`, `trait`, `struct` and `enum` declarations whole
// (`src/parser/parser.mbt`), so a method's body is not in the tree at all.
//
// So the tree's type context is the RECEIVER'S DECLARED TYPE. It is the same
// KIND of abstraction -- a type instead of an object -- and it merges the same
// way: three receivers of one type give ONE context, where object sensitivity
// gives three. The NAME of that context differs from the deck's (`Y` here, `X`
// there), and the difference is the boundary above, not a second opinion.

///|
/// The three readings of one program, side by side.
pub(all) struct CtxVariants {
  /// the call-site variant: the context is the call site.
  call_site : PtaCtxResult
  /// the object variant: the context is the receiver's object.
  object : PtaCtxResult
  /// the type variant: the context is the receiver's type.
  ///
  /// IT IS NOT CALLED `type` BECAUSE `type` IS A RESERVED KEYWORD in MoonBit,
  /// and a field name is not a place to fight the language.
  type_ctx : PtaCtxResult
}

///|
/// The three readings, side by side.
///
/// THE SELECTOR IS THE CALLER'S for the call-site and object variants, and the
/// type variant is at k = 1 -- the deck's own reading of it: p.170's formula
/// truncated to the last `k` is `[InType(o_i)]`.
pub fn pta_variants_compare(
  fns : Array[CgFn],
  tab : TraitTable,
  main : String,
  sel : CtxSelect,
) -> CtxVariants {
  {
    call_site: pta_ctx_run(fns, tab, main, sel),
    object: pta_ctx_run(fns, tab, main, CtxSelect::Object),
    type_ctx: pta_ctx_run(fns, tab, main, CtxSelect::Type(1)),
  }
}

///|
/// The contexts ONE function was analysed under, as the deck prints them: a
/// list in brackets.
///
/// IT IS THE DECK'S OWN SPELLING -- p.105-107 print "Context: [3]" and
/// "Context: [3,9]" -- and the contexts are the LABELS the deck's slides use
/// (a call site's line, an object's name).
pub fn pta_ctx_contexts_text(res : PtaCtxResult, fname : String) -> String {
  let xs = pta_ctx_contexts(res, fname)
  "[" + xs.join(", ") + "]"
}

///|
/// The three variants' contexts of one function, printed side by side.
///
/// THIS IS THE DECK'S p.174 TABLE -- "Contexts of foo()" -- with the third
/// column the deck does not have there: the call-site variant's contexts, so
/// the three abstractions can be read against each other.
pub fn pta_variants_text(c : CtxVariants, fname : String) -> String {
  let call = "call-site: " + pta_ctx_contexts_text(c.call_site, fname)
  let obj = "object: " + pta_ctx_contexts_text(c.object, fname)
  let ty = "type: " + pta_ctx_contexts_text(c.type_ctx, fname)
  call + " | " + obj + " | " + ty
}

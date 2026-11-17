/// 0604: THE HAND-MODELLED NATIVE SURFACE, MEASURED AGAINST THE DECLARED ONE.
///
/// THE DECK'S p.57 says the practice is to MODEL THE CRITICAL NATIVE CODE BY
/// HAND, and p.60-61 gives the alternative -- write the behaviour out in the
/// high-level language and let the analyser read it. This tree does the first
/// one (`src/core/builtin_methods.mbt` is a hand-carried table of the
/// built-in methods) and, for the part the interfaces cover, it can do the
/// second one. So the question these rows answer is the one p.57 leaves open:
/// HOW MUCH OF THE HAND-MODELLED SURFACE IS THE INTERFACES ALREADY CARRYING?

///|
/// A DECLARED NAME OF A MODELLED TYPE IS COUNTED, and the one the table does
/// not hold is the FALSE POSITIVE that would follow if the interfaces were
/// not there to carry it.
test "0604: the declared methods of the modelled types are counted, covered and missing" {
  let declared = ["Array::make", "Array::mkae", "HashMap::new"]
  let ns = @core.native_surface_coverage(declared)
  // `HashMap` is not one of the modelled types, so it is not part of the
  // built-in surface at all and it is not counted.
  assert_true(ns.declared == 2)
  // `Array::make` is in the table.
  assert_true(ns.covered == 1)
  // `Array::mkae` stands for a declared method the table has not caught up
  // with: it is the FALSE POSITIVE direction.
  assert_true(ns.missing == 1)
}

///|
/// THE TABLE'S OWN SIZE IS PART OF THE MEASUREMENT, and it is a CONSTANT of
/// the analyzer rather than of the target: the same table is measured against
/// every tree.
test "0604: the hand-modelled table's size is measured, not assumed" {
  let ns = @core.native_surface_coverage([])
  assert_true(ns.modelled == @core.builtin_method_names().length())
  assert_true(ns.modelled > 0)
  // AND THE TWO DIRECTIONS ADD UP: every modelled name either the target
  // declares or it does not.
  assert_true(ns.covered + ns.modelled_only == ns.modelled)
}

///|
/// A TARGET THAT DECLARES NOTHING OF THE BUILT-IN SURFACE MEASURES ZERO
/// COVERAGE, and that is a measurement, not a failure.
test "0604: a target that declares none of the modelled types has no coverage" {
  let ns = @core.native_surface_coverage([])
  assert_true(ns.declared == 0)
  assert_true(ns.covered == 0)
  assert_true(ns.missing == 0)
  assert_true(ns.modelled_only == ns.modelled)
}

///|
/// A NAME WITH NO `::` IS NOT A METHOD OF A TYPE, and the surface is made of
/// methods of types.
test "0604: a name with no type is not part of the built-in surface" {
  let ns = @core.native_surface_coverage(["Array", "make", ""])
  assert_true(ns.declared == 0)
  assert_true(ns.covered == 0)
}

///|
/// THE HEAD OF A `::` NAME, and the tail of one is `path_tail` -- two halves
/// of a spelling, not two implementations of one idea.
test "0604: the head of a qualified name is its type" {
  assert_true(@core.type_prefix("Array::make") == "Array")
  assert_true(@core.type_prefix("Array::make::inner") == "Array")
  assert_true(@core.type_prefix("Array") == "")
  assert_true(@core.type_prefix("") == "")
}

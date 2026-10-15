//| Tests for 0.4.35: the builtin-method TABLE could not see generic methods.
//
//| THE DEFECT IS IN THE GENERATOR, not in the analyzer. `tools/gen_builtin_methods.ps1`
//| extracted methods with
//|
//|     (?m)^\s*(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)
//|
//| which demands the name come STRAIGHT AFTER `fn`. MoonBit's generated interfaces
//| put type parameters there:
//
//|     pub fn[K : Eq] Set::add(Self[K], K) -> Unit
//|
//| so every generic method of every builtin type was invisible. Measured against
//| the toolchain in hand, the old pattern produced ZERO hits on
//| `<core>/set/pkg.generated.mbti`, which alone declares 32 of them, and missed
//| 445 names across the tree -- `Array::add` among them. The committed table held
//| 656 names; it now holds 1265, verified a STRICT SUPERSET with nothing lost.
//
//| WHY IT WAS INVISIBLE FOR SO LONG. `Array::add` was never reported on the
//| corpora only because real MoonBit writes the METHOD form `a.add(x)`. The
//| qualified form `Array::add(a, x)` is mostly used for constructors, and the one
//| finding that did surface had exactly that shape -- `Set::from_array` in async
//| 0.22.4 `src/http/send.mbt:37`, reported `undefined function` on code `moon check`
//| accepts.
//
//| IT IS NOT EVEN A DECLARED `fn`. `#alias(from_array)` sits above `type Set[K]`,
//| and the DIRECTIVE, not a declaration, is where the name is written. So the
//| generator now carries pending aliases to whatever declaration follows them, and
//| keeps only identifier-shaped ones: `#alias("_[_:_]")` is a quoted operator and is
//| not a qualified name this table can hold.

///|
/// THE CORPUS SHAPE. `Set::from_array` is a constructor alias reached through a
/// `#alias` directive, so it is the name the old generator was blindest to.
test "0445: a builtin method behind a #alias directive is not an undefined function" {
  let r = @pipeline.run(
    "fn build() -> Set[Int] {\n  Set::from_array([1, 2, 3])\n}\nlet top = build()\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// A GENERIC method, which is the shape the pattern was blind to. `Array::add` is
/// declared `pub fn[T] Array::add(Self[T], Self[T]) -> Self[T]`, so nothing between
/// `fn` and the name.
test "0445: a generic builtin method is not an undefined function" {
  let r = @pipeline.run(
    "fn build() -> Array[Int] {\n  Array::add([1, 2], [3])\n}\nlet top = build()\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CONTROL, and the one that keeps the two tests above honest. A table that
/// suppresses qualified calls on ambient types would make them silent too, so "no
/// finding" has to be distinguishable from "not checked". One letter off a real
/// name, and it must still be reported.
///
/// This is the same control 0.4.16 settled, with `Array::mkae` replaced by a
/// near-miss of a name the fix ADDED rather than one it inherited. A guard that
/// only covers names that were already in the table would pass the original
/// control and fail this one.
test "0445: a misspelled alias is still an undefined function" {
  let r = @pipeline.run(
    "fn build() -> Set[Int] {\n  Set::from_arrray([1, 2, 3])\n}\nlet top = build()\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// `T::to_json` is the case that nearly went the wrong way. It is declared in NO
/// `pkg.generated.mbti` in the tree, so a generator that reads only the interfaces
/// concludes it does not exist and drops it -- which puts every `Bool::to_json`
/// call site on the corpora straight back into `undefined function`.
///
/// It was assumed to be stale, left over from when the table was generated against
/// a toolchain that is no longer installed. That was WRONG, and
/// `_verify/settle_0445_alias.ps1` is what proved it: `Bool::to_json(true)`
/// compiles. It is an intrinsic member, the same category as `Array::make`, which
/// is why the generator carries a hand-settled intrinsic list at all.
///
/// This test is here so that dropping it again is a RED suite rather than a quiet
/// regression -- the 18 names live in a source comment, which is exactly the kind
/// of thing that gets tidied away.
test "0445: T::to_json resolves even though no interface declares it" {
  let r = @pipeline.run(
    "fn build() -> Json {\n  Bool::to_json(true)\n}\nlet top = build()\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// The near-miss beside the intrinsic, so "it exists" is not "any spelling
/// resolves" -- the same distinction `d_typo` and `f_to_json_typo` make in the
/// settle, kept here because the table is the thing under test and a table has no
/// other observable.
test "0445: a misspelled intrinsic is still an undefined function" {
  let r = @pipeline.run(
    "fn build() -> Json {\n  Bool::to_jsonx(true)\n}\nlet top = build()\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// The table's own membership, so a name silently dropped by a regeneration is
/// caught here rather than on a corpus. This is the cheapest of the six and the
/// only one that fails the moment the GENERATOR regresses rather than the analyzer.
test "0445: the builtin method table carries the generic and aliased names" {
  let a = @core.ambient_names()
  // Reached through a GENERIC head: `pub fn[T] Array::add(..)`.
  assert_true(a.contains("Array::add"))
  assert_true(a.contains("Set::add"))
  // Reached through a `#alias` DIRECTIVE, on a type constructor and on a method.
  assert_true(a.contains("Set::from_array"))
  assert_true(a.contains("Array::clone"))
  // Declared by no interface; carried by hand.
  assert_true(a.contains("Bool::to_json"))
  // The negatives. One near-miss per mechanism, so a loosened pattern that
  // matched too much would show up as these quietly turning true.
  assert_false(a.contains("Set::from_arrray"))
  assert_false(a.contains("Bool::to_jsonx"))
}

// Tests for the 0.4.17 fixes.
//
//   A  The METHODS of the builtin types were missing from the ambient table, so
//      `Array::make(total, Byte::default())` was reported as an undefined
//      function — on a line `moon check` accepts.
//
// The corpus finding is riantr/moonbit_labeler 0.2.13,
// `app_moui/rasterizer.mbt:74`. Two things about reproducing it were wrong in
// 0.4.16 and are worth stating before the tests, because every test below
// depends on them and neither is visible from the finding itself.
//
// REACHABILITY. The behavioral lens analyzes a function body only when the body
// is REACHED from a top-level statement. The real file calls `PixelBuffer::new`
// at line 1379. Every 0.4.16 probe copied the definition without the call, so
// nothing ran and no rule could show itself — which is why a fix there was
// declared unobservable and reverted.
//
// MASKING. A call that reports returns ABottom, and the enclosing call is then
// never reached. A nested chain therefore reports only its INNERMOST unknown
// callee. That is why the labeler line reports ONE name and not two, and why
// "adding `Byte::default` exposed `Array::make`" looked like whack-a-mole with
// no termination. It was a mask lifting. Fixing the over-report RAISES the
// count on such a line, which is uncovering and not regression — see the last
// test in this file.

///|
/// A — the actual finding, in the shape the corpus has.
///
/// The fixture is the corpus line, its enclosing function, and a top-level call
/// that reaches it. Without the call this test would pass for the wrong reason,
/// so the next test proves the call is what makes it bite.
test "0417: a builtin type method call is not an undefined function" {
  let r = @pipeline.run(
    "pub(all) struct PixelBuffer {\n  width : Int\n  pixels : Array[Byte]\n}\nfn PixelBuffer::new(width : Int) -> PixelBuffer {\n  let total : Int = width * 4\n  let pixels : Array[Byte] = Array::make(total, Byte::default())\n  { width, pixels }\n}\nlet scratch : Ref[PixelBuffer] = { val: PixelBuffer::new(1) }\n",
    "rasterizer.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CONTROL THAT MAKES THE TEST ABOVE MEANINGFUL.
///
/// Same source, same reached body, one callee changed to a method that does not
/// exist. If this stayed at zero, the test above would be passing because the
/// fixture never runs — which is precisely the defect that hid this finding for
/// a release. It is also the control that chooses a generated TABLE over the
/// one-line RULE that 0.4.16 wrote and reverted: the rule silences `mkae` too.
test "0417: a builtin type with a method that does not exist is still reported" {
  let r = @pipeline.run(
    "pub(all) struct PixelBuffer {\n  width : Int\n  pixels : Array[Byte]\n}\nfn PixelBuffer::new(width : Int) -> PixelBuffer {\n  let total : Int = width * 4\n  let pixels : Array[Byte] = Array::mkae(total, Byte::default())\n  { width, pixels }\n}\nlet scratch : Ref[PixelBuffer] = { val: PixelBuffer::new(1) }\n",
    "rasterizer.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// A head that is not a builtin type is untouched by any of this. Without it,
/// the table could be doing something as blunt as "ignore any qualified call".
test "0417: an unknown head is reported whatever it is qualified on" {
  let r = @pipeline.run(
    "fn build() -> Int {\n  ZzMissing::nope(1)\n}\nlet top = build()\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// A spread of real names from the four sibling corpora, so the fix is not
/// resting on the single pair that was measured. `Float::from_int` and
/// `Map::from_array` are declared in `moonbitlang/core/*.mbti`; `StringBuilder::
/// new` and `Int::unsafe_to_char` are compiler builtins that no interface
/// declares, settled with `moon check`.
test "0417: builtin type methods from the sibling corpora all resolve" {
  let r = @pipeline.run(
    "fn a() -> Float {\n  Float::from_int(3)\n}\nfn b() -> Map[Int, Int] {\n  Map::from_array([(1, 2)])\n}\nfn c() -> StringBuilder {\n  StringBuilder::new()\n}\nfn d() -> Bytes {\n  Bytes::from_array([1])\n}\nfn e() -> Int {\n  Int::unsafe_to_char(65).to_int()\n}\nlet t = a() + b().size() + c().length() + d().length() + e()\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE DATA ITSELF, asserted directly rather than only through the pipeline.
///
/// A regeneration that silently drops entries would fail here first, naming the
/// table instead of some pipeline count. `mkae` is asserted ABSENT for the
/// second half of the reason the fix is a table: what is not in it must still
/// be reportable.
test "0417: the ambient table carries the methods and not the mistakes" {
  let a = @core.ambient_names()
  assert_true(a.contains("Array"))
  assert_true(a.contains("Array::make"))
  assert_true(a.contains("Byte::default"))
  // Compiler builtins, no interface declares them.
  assert_true(a.contains("StringBuilder::new"))
  assert_true(a.contains("Int::unsafe_to_char"))
  // The negative: a name that was never in any toolchain file.
  assert_false(a.contains("Array::mkae"))
}

///|
/// MASKING, made observable, because the fix's side effect is counter-intuitive
/// and would otherwise be reported as a regression.
///
/// `ZzMissing::nope(4, Byte::default())` at 0.4.16 reported `Byte::default` and
/// said nothing about the outer callee, which is a genuinely undefined name.
/// Now that `Byte::default` is known the outer one surfaces. One finding
/// became one different finding, and the count did not move — but if the outer
/// name had been real before, teaching the lens the inner one has to cost it
/// nothing.
test "0417: knowing the inner callee uncovers the outer one, it does not hide it" {
  let r = @pipeline.run(
    "fn build() -> Int {\n  ZzMissing::nope(4, Byte::default())\n}\nlet top = build()\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
  // And it is the OUTER one being reported, not the inner one again.
  let mut said_outer = false
  for rep in r.reports {
    if rep.family.name() == "UndefinedName" &&
      rep.message.contains("ZzMissing::nope") {
      said_outer = true
    }
  }
  assert_true(said_outer)
}

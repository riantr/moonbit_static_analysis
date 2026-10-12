// Tests for the 0.4.20 fix.
//
// Corpus: wzzc-dev/moui 0.1.12, carried from 0.4.19.
//
// A  `impl T for U with fn m(...) { ... }` put its `fn` where the declaration
//    body's brace should be, so the `fn` sentinel in `skip_decl_braced` fired,
//    the body was left behind, and the method's own parameters were never
//    bound.
//
// Files understood 432 -> 436, withheld 176 -> 172, unreliable 3193 -> 3025,
// and actionable 14 -> 10: the four `undefined name 'self'` findings are gone.

///| The corpus shape, verbatim in structure from

///| THE SHARP ONE, and the first version of this test was hollow. It asserted

///| only that `self` was not reported undefined — which is green either way,

///| and mutation M1 proved it: removing the `with` exception left the suite

///| green. The reason is that `Parser::skip` records a note and CONSUMES

///| NOTHING, so before the fix the cursor stopped ON `fn` and the top-level loop

///| re-read `with fn identity(self) { ... }` as an ordinary top-level FUNCTION.

///| `self` was bound all along; the corpus finding was never about a binding.

///|

///| The property that actually changed is the HARVEST: a method must not be

///| harvested as a package-level function. Before, `collect_declared_names` saw

///| a phantom top-level `identity`, so every caller in the package resolved

///|
/// `identity` to "defined". After, the impl is skipped whole.
test "0420: an impl method is not harvested as a top-level function" {
  let decl = @parser.collect_declared_names(
    "pub(all) struct S {\n  view : Int\n}\nimpl[Msg] T for S with fn identity(self) {\n  self.view + 1\n}\n",
  )
  assert_eq(decl.values.contains("identity"), false)
}

///| The same property through the pipeline: the impl is skipped WHOLE, so a

///| name used only inside its body is not analyzed. That is what makes the

///|
/// harvest test above observable end to end.
test "0420: an impl body is skipped whole, not re-read as a function" {
  let r = @pipeline.run(
    "pub(all) struct S {\n  view : Int\n}\nimpl[Msg] T for S with fn identity(self) {\n  zzz_inside_impl(self.view)\n}\n",
    "view_tree.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// And `self` is not reported either — the finding the corpus actually had.
test "0420: impl ... with fn (self) reports nothing for self" {
  let r = @pipeline.run(
    "pub(all) struct S {\n  view : Int\n}\nimpl[Msg] T for S with fn identity(self) {\n  self.view + 1\n}\n",
    "view_tree2.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///| THE CONTROL, and the one that makes the fix safe. The `fn` sentinel exists

///| for a REAL shape: `pub impl Eq for T` with no body, whose methods live in a

///| separate block. If `with` were ignored, the scan would run past that

///| top-level `fn` and swallow the rest of the file. So the following

///| top-level function must still be parsed — and its body must still be

///|
/// analyzed, which is what `zzz_after_impl` proves.
test "0420: a bodiless impl still stops at the next top-level fn (control)" {
  let r = @pipeline.run(
    "pub(all) struct S {\n  n : Int\n}\npub(all) trait E {\n  eq(Self) -> Bool\n}\npub impl E for S\nfn real_top_level(x : Int) -> Int {\n  zzz_after_impl(x + 1)\n}\n",
    "bodiless.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///| The second control: the 177 `with` headers in moui that OMIT `fn`

///| (`pub impl ToJson for Affine with to_json(self : Affine)`) never met the

///|
/// sentinel and were never wrong. They must stay right.
test "0420: impl ... with (no fn) still skips its body" {
  let r = @pipeline.run(
    "pub(all) struct S {\n  n : Int\n}\npub(all) trait J {\n  to_json(Self) -> String\n}\npub impl J for S with to_json(self) -> String {\n  self.n.to_string()\n}\n",
    "withnofn.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

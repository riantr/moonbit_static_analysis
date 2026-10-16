// Tests for the 0.4.17 fixes.
//
//   A  collect_declared_names did not harvest ENUM VARIANTS. A variant is a
//      brace-declared value, so the depth-0 rule could never see it, and a
//      sibling file's bare reference to one was reported as an undefined name.
//      Measured on riantr/moonbit_labeler 0.2.13,
//      `app_moui/canvas_view_test.mbt:4917` — `Mode` and its five variants live
//      in `app_moui/app.mbt`, the same package directory.

///|
/// A — the corpus shape, exactly as it is written in the two files.
test "0417: unit enum variants are harvested for the package" {
  let t = @parser.collect_declared_names(
    "pub(all) enum Mode {\n  Select\n  Rect\n  Polygon\n  Keypoint\n  EditBinding\n} derive(Debug, Eq)\n",
  )
  assert_true(t.has_type("Mode"))
  assert_true(t.has_value("Select"))
  assert_true(t.has_value("Rect"))
  assert_true(t.has_value("Polygon"))
  assert_true(t.has_value("Keypoint"))
  assert_true(t.has_value("EditBinding"))
}

///|
/// THE CONTROL THAT KEEPS THE RULE FROM BECOMING "EVERYTHING IN THE BRACES".
///
/// A payload's TYPE is a brace-declared name too, and harvesting it would make
/// a type that exists only as a payload parameter package-visible — silencing a
/// real finding in an unrelated file. `Params` must stay out of the table.
test "0417: a payload type is not a variant" {
  let t = @parser.collect_declared_names(
    "pub(all) enum Shape {\n  Rect(Params)\n  Empty\n}\n",
  )
  assert_true(t.has_value("Rect"))
  assert_true(t.has_value("Empty"))
  assert_false(t.has_value("Params"))
  // And it is not mistaken for a type either.
  assert_false(t.has_type("Params"))
}

///|
/// The case a line-start rule alone gets wrong, and the reason this rule also
/// tracks parentheses: a payload laid out one parameter per line puts its type
/// at the start of a line too.
test "0417: a multi-line payload type is not a variant" {
  let t = @parser.collect_declared_names(
    "pub(all) enum Shape {\n  Conv(\n    Params,\n  )\n  Empty\n}\n",
  )
  assert_true(t.has_value("Conv"))
  assert_true(t.has_value("Empty"))
  assert_false(t.has_value("Params"))
}

///|
/// The comma-separated one-line body. This form is here because it was nearly
/// missed: neither variant starts a line, so a line-start rule alone collects
/// `A` (it follows `{`) and silently drops `B`.
///
/// The SPACED one-line form `enum E { A B }` is deliberately absent — it is a
/// parse error, settled with `moon check` ("unexpected token id (uppercase
/// start), you may expect `;` or `}`"), so there is no legal source it could
/// describe. An earlier draft of this test asserted it and failed, which is
/// what prompted the probe rather than a guess at the grammar.
test "0417: a comma-separated one-line enum body yields every variant" {
  let t = @parser.collect_declared_names("pub enum E { A, B }\n")
  assert_true(t.has_value("A"))
  assert_true(t.has_value("B"))
}

///|
/// THE NEGATIVE CONTROL for the whole change.
///
/// A `match` arm is a name in braces too, and it is not a variant. If the
/// harvest leaked past the enum's closing brace it would start collecting
/// these — and `Select` in the function below is exactly the shape it would
/// wrongly learn from a real file.
test "0417: match arms in a function body are not harvested" {
  let t = @parser.collect_declared_names(
    "pub fn mode_label(mode : Mode) -> String {\n  match mode {\n    Select => \"Select\"\n    Rect => \"Rect\"\n  }\n}\n",
  )
  assert_false(t.has_value("Select"))
  assert_false(t.has_value("Rect"))
  assert_true(t.has_value("mode_label"))
}

///|
/// Nor does an ordinary block inside a function start an enum body, and a name
/// that merely follows the keyword `enum` in a string or a comment is not a
/// declaration.
test "0417: a block in a body does not start an enum body" {
  let t = @parser.collect_declared_names(
    "fn f() -> Int {\n  let t = { let g = 1; g }\n  t\n}\n",
  )
  assert_true(t.has_value("f"))
  assert_false(t.has_value("g"))
  assert_false(t.has_value("t"))
}

///|
/// Everything the pre-0.4.17 harvest collected is still collected. A rule that
/// fixes a brace-declared value by re-reading the brace counter could easily
/// cost a top-level name, and those are the ones pyroduct's 26 findings rested
/// on.
test "0417: top-level declarations are still harvested" {
  // The `suberror` fixture was `suberror Bad of String` until 0.4.30. That is not
  // a suberror header -- `moon check` rejects it, as it does `suberror E(T)` and
  // `suberror E(x : T)` (`_verify/settle_0463b_bodyless_grammar.ps1`, 7/7) -- so
  // the harvest was being asserted against a grammar that does not exist. The
  // assertion is unchanged in meaning and now runs on the real body-less form.
  let t = @parser.collect_declared_names(
    "fn helper() -> Int {\n  1\n}\nlet top : Int = 2\nconst K : Int = 3\nstruct Pos {\n  line : Int\n}\ntype Alias = Int\nsuberror Bad\nextern \"c\" fn ext_fn(Int) -> Int\nfn Pos::shift(Self) -> Pos\n",
  )
  assert_true(t.has_value("helper"))
  assert_true(t.has_value("top"))
  assert_true(t.has_value("K"))
  assert_true(t.has_type("Pos"))
  assert_true(t.has_value("Pos::shift"))
  assert_true(t.has_type("Alias"))
  assert_true(t.has_value("Alias"))
  assert_true(t.has_value("Bad"))
  assert_true(t.has_value("ext_fn"))
}

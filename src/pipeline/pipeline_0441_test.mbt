///|
/// 0441: two top-level functions with the SAME NAME must not share a frame.
///

///|
/// THE DEFECT. `WalkResult.fn_bindings` was a `Map` keyed by `f.name`, and both
/// the structural walk (pass 3) and the type lens (`Infer::run_fn`) looked a
/// function's declarations up by that name. Two top-level functions of one name
/// therefore shared ONE table, and the second `set` overwrote the first — so
/// every function of that name was analysed against the LAST one's parameters:
///
///     pub fn g(w : Int, s : Int) -> Int { w + s }
///     pub fn g(w : Int) -> Int { w }
///
/// reported `undefined name 's'` in the first body (the parameter is not in the
/// table the frame was seeded from) and `parameter 't' may not be used` in a
/// second variant that has its own third parameter.
///

///|
/// `#cfg` IS HOW REAL CODE REACHES IT, AND IT IS NOT THE CAUSE. MoonBit allows
/// two top-level functions of one name when `#cfg` gates them for platforms, and
/// `Lexer::lex_attribute` deliberately emits NO token for an attribute, so both
/// variants are analysed together — a stated fidelity cost, not an accident.
/// Measured on proton 0.3.4 `window_geometry.mbt:12` and `:13`, where
/// `scale_factor_percent` belongs to the `#cfg(platform="windows")` variant of
/// `window_size_in_screen_coordinates` only.
///
/// `#cfg` appears 689 times across 99 moonbitlang/async files. The fix is NOT
/// "handle `#cfg`": it is to stop keying a table by a name that is not unique.
///

///|
/// THE PRIMARY TEST BELOW HAS NO `#cfg` AT ALL, deliberately. A test written on
/// the `#cfg` spelling would pass against a parser that still collapsed
/// duplicate names as long as someone kept the attribute in front — and the
/// defect has nothing to do with the attribute.

///|
/// THE MINIMAL REPRODUCTION: no attribute, two same-named functions, different
/// parameters. Both bodies must be clean.
test "0441: two same-named top-level functions each get their own parameters" {
  let r = @pipeline.run(
    "pub fn g(w : Int, s : Int) -> Int {\n  w + s\n}\n\npub fn g(w : Int, t : Int) -> Int {\n  w + t\n}\n",
    "dup.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// AND THE ASYMMETRIC SHAPE, which is the one that actually produced both
/// findings in the corpus: the two variants have DIFFERENT parameter lists, so
/// a shared table shows up as a parameter that exists in one body and not the
/// other. This is the `window_geometry.mbt` case — `scale_factor_percent` exists
/// in the windows variant only.
test "0441: same name with different parameter lists keeps both sets" {
  let r = @pipeline.run(
    "pub fn g(w : Int, s : Int) -> Int {\n  w + s\n}\n\npub fn g(w : Int) -> Int {\n  w\n}\n",
    "asym.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE `#cfg` SPELLING, pinned because it is the shape 99 real files use and
/// because the attribute's own doc says it emits no token — so this test is the
/// one that would notice if that ever changed. It asserts the same thing as the
/// test above; it is not a substitute for it.
test "0441: `#cfg`-gated variants of one function are analysed independently" {
  let r = @pipeline.run(
    "#cfg(platform=\"windows\")\npub fn g(w : Int, s : Int) -> Int {\n  w + s\n}\n\n#cfg(not(platform=\"windows\"))\npub fn g(w : Int) -> Int {\n  w\n}\n",
    "cfg.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE CONTROL, and it is the one that says a shared table would be VISIBLE —
/// but it had to be written the OTHER WAY ROUND from the first draft, which
/// failed for a reason that had nothing to do with collisions.
///
/// The first draft was
///
///     pub fn g(a : Int) -> Int { a }
///     pub fn g(a : Int, b : Int) -> Int { b }
///
/// and `a` in the second body really IS an unread parameter, so the expected 0
/// was simply wrong. It measured an honest finding.
///
/// The shape below reads every parameter in every body, so the ONLY thing that
/// can produce a finding is the collision. And it shows the collision from the
/// other direction: the LAST variant has the extra parameter, so under
/// last-wins the FIRST body is seeded with a parameter it never reads and
/// reports `UnusedParam` — where the corpus case (`window_geometry.mbt`)
/// reported `UndefinedName` because its EXTRA parameter was in the first body.
///
/// Both directions, one rule, and neither is visible without a negative
/// control.
test "0441 control: each same-named body reads all of its own parameters" {
  let r = @pipeline.run(
    "pub fn g(a : Int) -> Int {\n  a\n}\n\npub fn g(a : Int, b : Int) -> Int {\n  a + b\n}\n",
    "ctl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  // Under last-wins the first frame is seeded with {a, b} and reads only `a`,
  // so this is the assertion that actually kills the defect.
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE TYPE LENS HALF. `Infer::run_fn` had its OWN by-name lookup, separate from
/// the walk's, so fixing only the walk would have left half the defect standing
/// -- silently, because most findings come from one lens. It is pinned with a
/// source whose two variants bind the SAME name to DIFFERENT types, so a shared
/// table mistypes a parameter instead of losing it.
///
/// THE FIRST DRAFT OF THIS TEST WAS WORTHLESS, and mutation gate 0441 is what
/// proved it. It read:
///
///     pub fn g(w : Int, s : String) -> Int { w + 1 }
///     pub fn g(w : Int) -> Int { w + 1 }
///
/// and the doc above it claimed it "reported `unsupported operand types for '+'`
/// before the fix". Under M2 -- the walk left CORRECT and only the type lens left
/// sharing one table -- that source reports NOTHING. Every function is handed the
/// last variant's `{ w : Int }`, `s` appears in no body, and `w + 1` is `int +
/// int` either way. The test stayed green through a mutation aimed straight at
/// the code it was written to pin.
///
/// The lesson is the one the harness exists for: a test named after the defect is
/// not a test OF the defect. `MustRed` is the only thing that distinguishes the
/// two, which is why M2 and M4 name this test and why the gate failed on the
/// first attempt rather than reporting four kills.
///
/// What changed is that `x` now has a DIFFERENT TYPE in the two variants, so
/// mistyping `x` is visible as an `OperatorMismatch` and no body needs a String
/// method to read its parameter.
test "0441: the type lens also keeps the two variants apart" {
  let r = @pipeline.run(
    "pub fn g(x : Int) -> Int {\n  x + 1\n}\n\npub fn g(x : String) -> Int {\n  0\n}\n",
    "types.mbt",
    @core.IfaceSymTab::empty(),
  )
  // Asserted on the one family this lens can produce here, and NOT on
  // `first_error_line`: the second variant's `x` is genuinely unread, and
  // MEASURED `UnusedParam` is 1 on this source, so pinning 0 for it would be
  // pinning a lie -- the same mistake the control test below records in its own
  // history. The claim under test is about MISTYPING, not about tidiness.
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "OperatorMismatch"), 0)
}

///|
/// THREE OR MORE, because a collision of two is a special case of N and the fix
/// is positional — the LAST one must not win, and neither must the first. This
/// is the shape that distinguishes "indexed" from "first wins" and "last wins",
/// both of which would have passed the two-function tests.
///
/// Every body reads every parameter it is given, so a finding can only come
/// from the collision. The first draft had `-> Int { b }` in the two-parameter
/// variant, which is an honest `UnusedParam` and had nothing to do with this.
test "0441: with three same-named functions each keeps its own parameters" {
  let r = @pipeline.run(
    "pub fn g(a : Int) -> Int {\n  a\n}\n\npub fn g(a : Int, b : Int) -> Int {\n  a + b\n}\n\npub fn g(a : Int, b : Int, c : Int) -> Int {\n  a + b + c\n}\n",
    "three.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

// Tests for the 0.4.18 fixes.
//
// The corpus is wzzc-dev/moui 0.1.12 (608 files), a package the toolchain
// accepts — `moon check` runs through it to warnings only. It was chosen
// because every defect below is a shape that SHAPE-READS as valid MoonBit and
// that `moon check` accepts, so none of them is a "does it compile" question.
// Each fix is settled with the compiler first and measured on the corpus after.
//
//   measured, before the six fixes below          files understood  withheld
//   ---------------------------------------------------------------------
//   starting point                                 193 (31.7%)       415
//   after `&T`                                     195               413
//   after `~`                                      313 (51.4%)       295
//   after `fn[T]`                                  342 (56.2%)       266
//   after `{ ..base }`                             373 (61.3%)       235
//   after leading-dot chains                       389 (63.9%)       219
//
// `~`, `fn[T]`, the struct spread and the leading-dot chain each moved the
// count; `b"..."` did NOT (see its test) and is kept because its gate is
// load-bearing anyway. That asymmetry is stated rather than smoothed over.
//
// Two rules hold throughout, and each has a control test that fails without it:
//   * a construct that becomes readable must not cost a reading — the byte
//     string, the spread base and the chain arguments all carry reads, and a
//     parameter used only inside one must not be reported unused;
//   * a fix must not widen what it claims to fix — every one has a negative
//     control shaped like the thing it must NOT touch.

// ---------------------------------------------------------------------------
// `&T` — a Ref[T] annotation in a parameter list
// ---------------------------------------------------------------------------

///| A six-parameter declaration with one reference, verbatim from

///| `runtime/text_input_state.mbt:42`. The `&` reached `expect_name` first, so

///| the file reported 15 ParseErrors and the call was scored against a

///|
/// two-parameter signature — "expected 2, got 6" on a call that passes six.
test "0418: &T in a parameter type is not a parse error" {
  let r = @pipeline.run(
    "fn view_text_input_state(\n  element : ElementNode,\n  data : &RuntimeViewNode,\n  render : RenderNode,\n  text_system : TextSystem,\n  environment : Environment,\n  style : ViewStyle,\n) -> TextInputState? {\n  data\n}\nlet s = view_text_input_state(1, 2, 3, 4, 5, 6)\n",
    "text_input_state.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///|
/// The arity itself, which is what the corpus user saw. Six in, six declared.
test "0418: a &T parameter list keeps its arity" {
  let r = @pipeline.run(
    "fn f(a : &Node, b : &Node, c : &Node) -> Int {\n  1\n}\nlet s = f(1, 2, 3)\n",
    "arity.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

///| THE NEGATIVE CONTROL. `&` in an EXPRESSION is bitwise and and must stay

///| that way. If the type fix had eaten the operator, `h & 1023` would stop

///|
/// being a binary op — this is the check that says the fix is narrow.
test "0418: bitwise & in an expression is untouched (negative control)" {
  let r = @pipeline.run(
    "fn mask(h : Int) -> Int {\n  h & 1023\n}\nlet m = mask(7)\n",
    "mask.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

// ---------------------------------------------------------------------------
// `~` — the label sigil
// ---------------------------------------------------------------------------

///| Both sides of `~` in one fixture: `label~ : T` declares a parameter that

///| must be passed by label, and `x~` is the shorthand for `x=x`. Settled by

///| `moon check`, which rejects a positional pass with "The labels f~ are

///|
/// required by this function".
test "0418: label~ declaration and value~ call both parse" {
  let r = @pipeline.run(
    "fn f(a~ : Int, b : Int) -> Int {\n  a + b\n}\nlet a = 1\nlet s = f(a~, 2)\n",
    "label.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// The multi-line call shape, which is 341 of the corpus occurrences.
test "0418: ~ on a multi-line argument list" {
  let r = @pipeline.run(
    "fn f(a~ : Int, b~ : Int, c : Int) -> Int {\n  a + b + c\n}\nlet a = 1\nlet b = 2\nlet s = f(\n  a~,\n  b~,\n  3,\n)\n",
    "multiline.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///| `~` must NOT change the parameter's NAME — `f~ : T` is still one parameter

///| called `f`, so a call passing three arguments to three parameters is not

///|
/// an arity error.
test "0418: ~ does not add a parameter" {
  let r = @pipeline.run(
    "fn f(a~ : Int, b : Int) -> Int {\n  a + b\n}\nlet s = f(1, 2)\n",
    "arity.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

// ---------------------------------------------------------------------------
// `fn[T]` — type parameters
// ---------------------------------------------------------------------------

///| `pub fn[Msg] PresentationSpec::new(` killed

///| `views/presentation.mbt` dead at line 152: the `[` reached `expect_name`.

///|
/// 1563 occurrences across 266 corpus files.
test "0418: a generic function declaration parses" {
  let r = @pipeline.run(
    "pub(all) struct Spec {\n  id : String\n}\npub fn[Msg] Spec::new(id~ : String) -> Spec {\n  { id }\n}\nlet s = Spec::new(id=\"a\")\n",
    "generic.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///| A BOUNDED type parameter, and the `extern fn[T]` form, which shares the

///|
/// signature parser.
test "0418: bounded and extern generic signatures parse" {
  let r = @pipeline.run(
    "fn[T : Eq] same(a : T, b : T) -> Bool {\n  a == b\n}\nextern \"c\" fn[Msg] ffi_open(id : Int) -> Int = \"ffi_open\"\nlet r = same(1, 1)\n",
    "bounded.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///| THE NEGATIVE CONTROL for the skip. `skip_indexed` consumes a balanced

///| `[...]`; if it were reachable from expression position it would eat a

///|
/// subscript, so this asserts `xs[0]` still reads.
test "0418: an array subscript is not eaten (negative control)" {
  let r = @pipeline.run(
    "fn first(xs : Array[Int]) -> Int {\n  xs[0]\n}\nlet f = first([1, 2])\n",
    "subscript.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///| A generic function must reach the SIBLING table, not just its own file.

///| This is the false-positive fix: `feedback_panel.mbt` declares

///| `fn[Msg] feedback_panel(` and all four of its call sites in two other

///|
/// files of the same package were reported "no visible binding".
test "0418: a generic function's name reaches a sibling file" {
  let decl = @parser.collect_declared_names(
    "fn[Msg] feedback_panel(message : String) -> Int {\n  1\n}\n",
  )
  assert_eq(decl.values.contains("feedback_panel"), true)
}

///| THE CONTROL for the one above: the NON-generic form must still be

///| collected, so the sibling-table change did not come at the cost of the

///|
/// plain case.
test "0418: a non-generic function's name still reaches a sibling file" {
  let decl = @parser.collect_declared_names(
    "fn feedback_panel(message : String) -> Int {\n  1\n}\n",
  )
  assert_eq(decl.values.contains("feedback_panel"), true)
}

// ---------------------------------------------------------------------------
// `b"..."` — byte-string literals
// ---------------------------------------------------------------------------

///| The `b` lexed as an identifier and the string became a second atom, so

///|
/// the pair ended the file at `views/date_picker_control.mbt:40`.
test "0418: a byte-string literal is one token" {
  let r = @pipeline.run(
    "fn is_nul(bytes : Bytes) -> Bool {\n  bytes == b\"\\x00\"\n}\nlet r = is_nul(b\"\\x00\")\n",
    "bytes.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///| THE NEGATIVE CONTROL, and the reason the rule is "the character AFTER the

///| `b`" rather than "an identifier starting with b". If the test were looser,

///|
/// `bbox` would split into `b` and `box` and this would report `b` undefined.
test "0418: an identifier starting with b stays one name (negative control)" {
  let r = @pipeline.run(
    "fn bbox(box : Int) -> Int {\n  box + 1\n}\nlet r = bbox(1)\n",
    "bbox.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///| Folding `b"..."` into a string literal must not INVENT a type mismatch.

///| The literal is `Bytes` and the analyzer models no Bytes, so both sides are

///| unknown and the comparison is silent. If the fold had claimed "String",

///|
/// this would fire on a comparison the compiler accepts.
test "0418: a byte string against an unmodelled Bytes is silent" {
  let r = @pipeline.run(
    "fn cmp(bytes : Bytes) -> Bool {\n  bytes == b\"\\x01\"\n}\nlet r = cmp(b\"\\x01\")\n",
    "cmp.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

// ---------------------------------------------------------------------------
// `{ ..base }` — the struct update form
// ---------------------------------------------------------------------------

///| `{ ..self, cursor: n }` — `views/navigation/navigation_routing.mbt:252`.

///| The load-bearing part is the READ: `self` is used only by the spread, so

///|
/// dropping the base would report it unused.
test "0418: a struct spread keeps its base's reads" {
  let r = @pipeline.run(
    "pub(all) struct St {\n  cursor : Int\n}\nfn step(self : St, n : Int) -> St {\n  { ..self, cursor: n }\n}\nlet s = step({ cursor: 0 }, 1)\n",
    "spread.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///| THE NEGATIVE CONTROL for `at_struct_literal`. That function exists to tell

///| a block from a struct literal, and the spread arm is a new way for a `{`

///| to open. This asserts both answers are unchanged: a statement-position

///|
/// block stays a block, and a name-led literal stays a literal.
test "0418: a statement block and a name-led literal still differ (negative control)" {
  let r = @pipeline.run(
    "fn block_stmt(x : Int) -> Int {\n  if x > 0 {\n    let w = x + 1\n    w\n  } else {\n    0\n  }\n}\nfn lit_tail(x : Int) -> Int {\n  { x, y: 2 }\n}\nlet r = block_stmt(1)\n",
    "brace.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///| A spread whose base is NOT the parameter must still report it unused.

///| Without this the test above would also pass if the spread simply silenced

///|
/// every `self` — the two together pin the behavior to the actual read.
test "0418: a spread of something else still reports the parameter unused" {
  let r = @pipeline.run(
    "pub(all) struct St {\n  cursor : Int\n}\nfn b(self : St) -> St {\n  { ..@core.ViewPaintPlan::empty(), cursor: 1 }\n}\nlet s = b({ cursor: 0 })\n",
    "spread2.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 1)
}

// ---------------------------------------------------------------------------
// leading-dot chains
// ---------------------------------------------------------------------------

///| A `.` in statement position continues the PREVIOUS line's expression:

///| 1124 such lines across 131 corpus files. The load-bearing part is the

///|
/// argument read — `self` is used only inside `.unwrap_or(...)`.
test "0418: a leading-dot chain keeps its argument reads" {
  let r = @pipeline.run(
    "pub(all) struct S {\n  style : Int\n}\nfn make() -> Int {\n  1\n}\nfn f(self : S) -> Int {\n  make()\n    .unwrap_or(self.style)\n}\nlet x = f({ style: 1 })\n",
    "chain.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///| THE REWIND CONTROL, and the sharpest test in this file. A chain is ended

///| by a newline UNLESS the next line also opens with `.`, so the separators

///| are consumed speculatively and rewound. If the rewind were missing, the

///| following statement would be absorbed into the chain and the undefined

///|
/// name below would NOT be reported — the assertion is that it IS.
test "0418: a statement after a chain is not swallowed" {
  let r = @pipeline.run(
    "fn make() -> Int {\n  1\n}\nfn g(x : Int) -> Int {\n  make()\n    .plus(1)\n  zzz_after_chain(x)\n}\n",
    "rewind.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///| THE NEGATIVE CONTROL: this fix is about a `.` at STATEMENT position, not

///|
/// about chains. A single-line chain must be untouched.
test "0418: a single-line chain is unchanged (negative control)" {
  let r = @pipeline.run(
    "fn h(x : Int) -> Int {\n  x\n}\nfn f(x : Int) -> Int {\n  h(x).plus(1).minus(2)\n}\nlet r = f(1)\n",
    "single.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// A chain as an `else` block tail — `views/text/text.mbt:82`.
test "0418: a chain as a block tail parses" {
  let r = @pipeline.run(
    "fn f(env : Bool, fg : Int) -> Int {\n  if env {\n    fg\n  } else {\n    fg\n      .multiply_alpha(0.7)\n  }\n}\nlet r = f(true, 1)\n",
    "tail.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

// ---------------------------------------------------------------------------
// ambient builtin types
// ---------------------------------------------------------------------------

///| `Buffer` was reported "no visible binding for 'Buffer'" at

///| `core/view_state_slot_test.mbt:16`, and the token there is a CONSTRUCTOR

///| CALL — `Buffer(size_hint=12)` — not a type annotation. That distinction is

///| load-bearing for this gate: an earlier version of this test only mentioned

///| `Buffer` in an annotation and passed whether or not the name was ambient,

///| so mutation M12 (removing it) survived it. The annotation is not reported

///|
/// by the `.mbt` frontend at all; the call is.
test "0418: Buffer is an ambient name at its constructor call" {
  let r = @pipeline.run(
    "fn f(n : Int) -> Int {\n  let output = Buffer(size_hint=n)\n  1\n}\nlet x = f(12)\n",
    "ambient.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///| THE CONTROL for the one above. Change only the callee to a name that

///| cannot exist. If the assertion above were passing for the wrong reason —

///| because the `.mbt` frontend never reports unknown names at all — this

///|
/// would stay at zero and the test would be hollow.
test "0418: the ambient gate can still see an unknown name (control)" {
  let r = @pipeline.run(
    "fn f(n : Int) -> Int {\n  let output = Zz_not_a_builtin(size_hint=n)\n  1\n}\nlet x = f(12)\n",
    "ambient2.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

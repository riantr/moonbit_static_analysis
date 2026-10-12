// Tests for the 0.4.19 fixes.
//
// Corpus: wzzc-dev/moui 0.1.12, carried over from 0.4.18. Files understood
// 389 -> 432 (63.9% -> 71.1%), withheld 219 -> 176, unreliable 4388 -> 3193.
//
//   A  a literal inside an `is` pattern was bound as a variable
//   B  a function type in a parameter annotation ended the file
//
// B is the larger of the two by an order of magnitude — 845 annotations across
// 171 files — and it is also the one that RAISES the actionable count, from 4
// to 14, because 43 more files became readable. Seven of those new findings
// are false positives from three classes that B merely made visible; they are
// measured and written down in README/SKILL rather than papered over.

// ---------------------------------------------------------------------------
// A — a literal in an `is` pattern is not a binding
// ---------------------------------------------------------------------------

///| `if info.required is Some(true)` bound the literal `true` and reported

///| `local variable 'true' assigned but may not be used`, on

///| `views/form/form_field_semantics_test.mbt:42` and `:58` — lines `moon check`

///| accepts. A pattern binding is a name that INTRODUCES A VARIABLE, and a

///|
/// keyword is not one.
test "0419: a literal inside an is-pattern is not a binding" {
  let r = @pipeline.run(
    "fn f(x : Bool?) -> Int {\n  if x is Some(true) {\n    1\n  } else {\n    0\n  }\n}\nlet r = f(Some(true))\n",
    "is_literal.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///| THE CONTROL, and the one that keeps the test above honest. `Some(y)` DOES

///| bind `y`, and that binding is load-bearing: if the keyword test were too

///| broad it would swallow every binding, `y` would go unbound, and the read

///|
/// below would be reported instead. So both directions are pinned.
test "0419: a name inside an is-pattern still binds (control)" {
  let r = @pipeline.run(
    "fn f(x : Int?) -> Int {\n  if x is Some(y) {\n    y + 1\n  } else {\n    0\n  }\n}\nlet r = f(Some(1))\n",
    "is_binding.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedLocal"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///| `self` is a CONVENTIONAL PARAMETER NAME, not a keyword, and

///| `is_moonbit_keyword` deliberately excludes it with a long comment saying

///|
/// why. So `if x is Some(self)` must still bind, and the read must count.
test "0419: self still binds inside an is-pattern (control)" {
  let r = @pipeline.run(
    "fn f(x : Int?, self : Int) -> Int {\n  if x is Some(self) {\n    self\n  } else {\n    0\n  }\n}\nlet r = f(Some(1), 2)\n",
    "is_self.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

// ---------------------------------------------------------------------------
// B — a function type in an annotation
// ---------------------------------------------------------------------------

///| The corpus shape: `on_input~ : ((String) -> Msg)?` and `emit : (Msg) ->

///| Unit`. The `(` used to reach `expect_name`, which reported "expected type

///|
/// name" and ended the file.
test "0419: a function-type parameter annotation parses" {
  let r = @pipeline.run(
    "pub(all) struct S {\n  emit : (Msg) -> Unit\n}\nfn wire(on_input~ : ((String) -> Msg)?) -> Int {\n  1\n}\nlet r = wire(None)\n",
    "fn_type.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///| The nested form needs the annotation parser to recurse into itself, which

///| is the whole reason the elements are read by `type_annotation` rather than

///| by a flat token scan. `((String) -> Msg)?` is a function type returning a

///|
/// function type.
test "0419: a nested function-type annotation parses" {
  let r = @pipeline.run(
    "fn wire(on_input~ : ((String) -> Msg)?, on_select~ : (String) -> Msg) -> Int {\n  1\n}\nlet r = wire(None, on_select)\n",
    "nested.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///| A function type in RETURN position, `-> (Int) -> String`. The tuple arm in

///| `return_annotation` accepts any `(`, so this shape needs the matching-close

///| scan. The fixture is an `extern fn` on purpose: it exercises exactly the

///| same `parse_fn_signature` path with no body to parse. A body-carrying

///| fixture was the first attempt and it failed for an unrelated reason — a

///| bare `n => { ... }` at STATEMENT position is its own unimplemented shape,

///|
/// and fixing the fixture is not the same as fixing this.
test "0419: a function-type return annotation parses" {
  let r = @pipeline.run(
    "extern \"c\" fn f() -> (Int) -> String = \"f\"\nlet r = f\n",
    "fn_ret.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///| THE CONTROL for that lookahead: a REAL tuple return must still take the

///| tuple arm and still be read whole. If the matching-close scan matched too

///| eagerly this would stop being a tuple. Also an `extern fn`, so the only

///|
/// thing under test is how the annotation was read.
test "0419: a tuple return is still a tuple (negative control)" {
  let r = @pipeline.run(
    "extern \"c\" fn f() -> (Int, String) = \"f\"\nlet r = f\n",
    "tuple.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
}

///| THE CONTROL for the whole change: a function type must not become a

///| SILENT one. The lens models no function types, so the honest answer is

///| unknown — and unknown must stay quiet. This is what stops the annotation

///|
/// from being "handled" by pretending it is a String.
test "0419: a function-typed parameter is not given a primitive type" {
  let r = @pipeline.run(
    "fn apply(cb : (Int) -> Int, n : Int) -> Int {\n  1\n}\nlet r = apply(2, 1)\n",
    "fn_arity.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

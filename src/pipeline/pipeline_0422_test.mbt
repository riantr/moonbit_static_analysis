// Tests for the 0.4.22 fixes.
//
// Two independent changes:
//
//   A  a named argument is matched to its parameter by LABEL, not by index
//   B  `Int32` reads as `Int` (0.1.20261012 renamed the default integer type)
//
// Corpus: wzzc-dev/moui 0.1.12. actionable 8 -> 1; the seven that disappear are
// all one shape, `action 4 ... has incompatible type 'str'; expected 'bool'`,
// starting at `core/gesture.mbt:754`. The other five corpora are unchanged:
//   moonbit_labeler  24 parsed, actionable 0
//   async            206 parsed, actionable 17
//   proton            72 parsed, actionable 43
//   moonbit_image     1 parsed, actionable 0
//   proton_contract   3 parsed, actionable 1
//
// EVERY fixture below was settled against `moon check` on 0.1.20261012 before
// it was written, and the settle verdicts are cited per test. That is the rule
// this project keeps re-learning: a fixture that "looks like" the corpus but was
// never checked is how a test pins a behaviour MoonBit does not have.
//
// The single most important test in this file is A2. A1 alone would also pass
// if the argument-type check had been switched off entirely, because a check
// that never fires also produces zero findings. A2 is the negative control that
// makes A1 mean anything.

// ---------------------------------------------------------------------------
// A — a named argument is matched by NAME
// ---------------------------------------------------------------------------

///| A NOTE ON THE FIXTURE SHAPE, measured rather than discovered by accident.
///

///| The positive tests below end at the function declaration on purpose — there
///

///| is no top-level `let r = build()` calling them. Adding one changes the
///

///| FAMILY, not just the count: the behavioral lens then re-reports the same
///

///| call as `no method matching two(int, str)` (`MethodError`), which merges
///

///| with the type lens's `ArgTypeMismatch` under the shared merge group
///

///| "arg-type", and the surviving finding is phrased as a `MethodError`. The
///

///| type check still ran and still fired; `count_family(r,
///

///| "ArgTypeMismatch")` simply reads 0. Verified through the JSON API on six
///

///| fixture shapes before this shape was chosen.
///

///| So these tests pin the type lens ALONE. That is a deliberate choice, not a
///

///| convenience: the thing under test is which parameter an argument is matched

///| to, and a merge that hides the message behind another lens's phrasing is

///| exactly what would stop a regression here from being noticed.
///

///| THIS IS NOT A MATTER OF STYLE. The mutation gate caught it: with the
///

///| top-level `let` left in, `param_index` could be broken outright -- made to
///

///| never match -- and all 430 tests still passed, because every finding the
///

///| broken matcher produced was re-phrased as a `MethodError` before anyone
///

///| counted it. Four of the eight mutations survived that way. A zero-count
///

///| assertion is only able to fail if the finding it is counting actually
///

///| arrives as the family it is counting, so the shape that hides the family
///

///| also hides the regression.

///| THE SHARP ONE, and the headline change. The declaration is the moui
///

///| `.mbti` line, `core/pkg.generated.mbti:92`:
///

///|   ActionCommand::new(intent~ : CommandIntent, label? : String,

///|                      shortcut? : KeyboardShortcut?, enabled? : Bool,

///|                      group? : String, description? : String,

///|                      context_menu? : Bool)
///

///| The call is `core/gesture.mbt:754` onward, which passes them in a
///

///| DIFFERENT order:
///

///|   ActionCommand::new(intent=..., label=..., group=...,

///|                      description=..., shortcut=...)
///

///| Matched by index, `description` (a String) lands on `enabled` (a Bool) and
///

///| reports; matched by name it lands on `description`. Settled: accepted, no
///

///| type error. Before the change this fixture reported THREE argument-type
///

///| mismatches, not one — `group` on `shortcut`, `description` on `enabled`,
///

///|
/// and `shortcut` on `group`.
test "0422: named arguments are matched by name, not by position" {
  let r = @pipeline.run(
    "fn make(intent~ : Int, label? : String, shortcut? : Int, enabled? : Bool, group? : String, description? : String) -> Int {\n  intent\n}\nfn build() -> Int {\n  make(intent=1, label=\"Copy\", group=\"Edit\", description=\"Copy the current selection.\", shortcut=2)\n}\n",
    "named_order.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

// ---------------------------------------------------------------------------

///| THE REVERSE CONTROL, and the one that makes the test above non-vacuous.

///|
///

///| `description=7` where `description? : String`. Settled against `moon check`
///

///| (Expr Type Mismatch, Int -> String), so it is a REAL error and this
///

///| analyzer is supposed to report it.
///

///|
///

///| If the argument-type check had been deleted rather than fixed, A1 would
///

///| still be green — zero findings from zero checks — and this test is what
///

///| catches that. It is deliberately the opposite assertion direction: same
///

///| function shape, same named-argument syntax, one finds nothing and one
///

///|
/// finds exactly one thing.
test "0422: a named argument of the WRONG type is still reported" {
  let r = @pipeline.run(
    "fn make(intent~ : Int, label? : String, description? : String) -> Int {\n  intent\n}\nfn build() -> Int {\n  make(intent=1, description=7)\n}\n",
    "named_wrong.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ArgTypeMismatch"), 1)
}

// ---------------------------------------------------------------------------

///| POSITIONAL arguments still match by index. This is the pre-existing
///

///| behaviour the change must not disturb, and it is the fallback path for any
///

///| argument whose label names no parameter. Settled against `moon check`:
///

///|
/// rejected, String -> Bool.
test "0422: a positional argument of the wrong type is still reported" {
  let r = @pipeline.run(
    "fn two(a : Int, b : Bool) -> Int {\n  a\n}\nfn build() -> Int {\n  return two(1, \"not a bool\")\n}\n",
    "positional_wrong.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 1)
}

// ---------------------------------------------------------------------------

///| A LABEL THAT NAMES NO PARAMETER falls back to the positional check rather
///

///| than being skipped. This is `param_index`'s `None` arm, and it is the one
///

///| place where a "match by name, else trust the index" implementation could
///

///| quietly stop reporting: if the label lookup returned early instead of
///

///| falling back, `zzz=` would match nothing and the wrong type would pass.
///

///|
///

///| `moon check` rejects this program (error 4085, "This function has no
///

///| parameter with label a~"), so reporting it is correct and the fallback is
///

///|
/// the conservative choice.
test "0422: a label matching no parameter falls back to the index" {
  let r = @pipeline.run(
    "fn one(a : Int) -> Int {\n  a\n}\nfn build() -> Int {\n  one(zzz=\"not an int\")\n}\n",
    "label_no_param.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 1)
}

// ---------------------------------------------------------------------------

///| The `x~` SHORTHAND is a label too, and this is the shape that proves it.

///|
///

///| Corpus sites — `moui backend/web/web_host.mbt:31-34` and `:52` — pass the
///

///| shorthand in DECLARATION order, so they would pass either way and prove
///

///| nothing. This fixture puts the shorthand first against a declaration whose
///

///| first parameter is the other one:
///

///|   from_logical(size? : Int, scale? : Bool)  called as  from_logical(scale~, size=size)
///

///| Settled against `moon check`: accepted, no type error. Matched by index the
///

///| Bool lands on `size` (Int) and the Int lands on `scale` (Bool) — two
///

///| findings. `scale~` is recorded as the label "scale", read back out of the
///

///|
/// token stream by `Parser::name_at` after the value has already been parsed.
test "0422: the tilde shorthand carries a label and can be reordered" {
  let r = @pipeline.run(
    "fn from_logical(size? : Int, scale? : Bool) -> Int {\n  size\n}\nfn build(size : Int, scale : Bool) -> Int {\n  from_logical(scale~, size=size)\n}\n",
    "tilde_label.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

// ---------------------------------------------------------------------------

///| AND THE REVERSE for the shorthand: when the types really are wrong, BOTH
///

///| arguments are reported. Declared `(size? : Bool, scale? : Bool)` and called
///

///| with two `Int` locals, so neither argument matches its parameter — the point
///

///| being that reading the shorthand's label must not become a reason to skip
///

///| an argument. Without this, "the `~` form never reports anything" would pass
///

///| the test above for the wrong reason.
///

///|
///

///| The call is spread over three lines on purpose. `merge_findings` groups by
///

///| `(merge family, LINE)` — deliberately, so the type lens pinning the argument
///

///| and the behavior lens pinning the call collapse into one finding — and two
///

///| mismatching arguments written on ONE line would therefore come back as one
///

///| finding however many the type lens actually produced. Written this way both
///

///|
/// survive, so the assertion really is "both arguments were checked".
test "0422: a reordered tilde shorthand of the wrong type is reported" {
  let r = @pipeline.run(
    "fn from_logical(size? : Bool, scale? : Bool) -> Int {\n  0\n}\nfn build(size : Int, scale : Int) -> Int {\n  from_logical(\n    scale~,\n    size=size,\n  )\n}\n",
    "tilde_wrong.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 2)
}

// ---------------------------------------------------------------------------

///| MIXED: a named argument and a positional one in the same call. The named
///

///| one is matched by label, the positional one by index, and neither may be
///

///| shifted by the other's presence. Settled against `moon check` on the
///

///|
/// in-order form; the argument TYPE mismatch is what is under test.
test "0422: a positional and a named argument in one call are both checked" {
  let r = @pipeline.run(
    "fn mixed(flag? : Bool, size? : Int) -> Int {\n  size\n}\nfn build(flag : Bool, size : Int) -> Int {\n  mixed(true, flag)\n}\n",
    "mixed_args.mbt",
    @core.IfaceSymTab::empty(),
  )
  // `flag` (Bool) is the second argument and lands on `size` (Int)
  assert_eq(count_family(r, "ArgTypeMismatch"), 1)
}

// ---------------------------------------------------------------------------

///| THE ARITY PATH, which is positional and stays that way. Settled against
///

///| `moon check` (error 4080, "requires 2 arguments, but is given 3"). This is
///

///| the counterpart to the `all_positional` gate in infer.mbt: the gate exempts
///

///| label-addressed calls only, and this test is what pins the other direction
///

///|
/// so that gate cannot be widened by accident.
test "0422: too many positional arguments are still reported" {
  let r = @pipeline.run(
    "fn g(a : Int, b : Bool) -> Int {\n  a\n}\nfn build() -> Int {\n  g(1, true, 3)\n}\n",
    "arity_positional.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 1)
}

// ---------------------------------------------------------------------------

///| THE OMITTED OPTIONAL PARAMETER, which is why the count is not a bound in
///

///| the first place. `fn f(a~ : Int, b? : Int, c? : Int)` called with two
///

///| named arguments is ordinary MoonBit — `c` keeps its default. Settled: no
///

///| arity finding, and the arguments still match by name. This is the case that
///

///| a naive "count > count means too many" reading of a label-addressed call
///

///|
/// gets wrong in the other direction.
test "0422: omitted optional parameters are not an arity error" {
  let r = @pipeline.run(
    "fn f(a~ : Int, b? : Int, c? : Int) -> Int {\n  a\n}\nfn build() -> Int {\n  f(b=2, a=1)\n}\n",
    "omitted_optional.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

// ---------------------------------------------------------------------------

///| THE PARALLEL-ARRAY INVARIATE, and the fixture the mutation gate had to ask

///| for. `parse_call_args` grows `args` and `labels` at four separate sites,

///| and the site for an argument with no leading NAME token is a different one

///| from the site for a leading name. If that site stops pushing, `labels` ends

///| up SHORTER than `args` — which does not fail loudly. `labels.get(i)` simply

///| returns the label belonging to some LATER argument, so every argument after

///| the gap is matched to the wrong parameter, and the ones past the end read

///| as positional.
///

///|
///

///| `g(1, b=true)` is that shape: `1` has no leading name, `b=true` does. With

///| the label list dense this is zero findings. With the gap, argument 1 reads

///| the label "b" and is matched against `b? : Bool` while carrying an `Int`.
///

///|
///

///| Settled against `moon check`: accepted. The parameter KINDS matter and the

///| first attempt at this fixture got them wrong — `?` optional parameters may

///| NOT be passed positionally at all ("requires 0 positional arguments"), nor

///| may `~` required-label ones; only a bare `a : Int` may. That is also why

///| named arguments are so common in real MoonBit, and why the old positional

///|
/// matcher produced so many false positives.
test "0422: a positional argument followed by a named one keeps its labels" {
  let r = @pipeline.run(
    "fn g(a : Int, b? : Bool) -> Int {\n  a\n}\nfn build() -> Int {\n  g(1, b=true)\n}\n",
    "gap_labels.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

// ---------------------------------------------------------------------------

///| AND THE REVERSE, so the test above is not satisfied by "never report

///| anything". Both arguments are genuinely wrong; they are written on separate

///| lines because `merge_findings` groups by `(merge family, LINE)` and would

///|
/// otherwise collapse them into one.
test "0422: both arguments of a positional-then-named call are checked" {
  let r = @pipeline.run(
    "fn g(a : Bool, b? : Int) -> Int {\n  0\n}\nfn build() -> Int {\n  g(\n    1,\n    b=true,\n  )\n}\n",
    "gap_labels_wrong.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 2)
}

// ---------------------------------------------------------------------------
// B — `Int32` reads as `Int`
// ---------------------------------------------------------------------------

///| 0.1.20261012 renamed the default integer type. The formatter rewrote this
///

///| project's OWN source from `Int` to `Int32`, which the annotation reader
///

///| did not know, so every `Int32` parameter read as Unknown and the
///

///| argument-type check went quiet on it.
///

///|
///

///| Settled against `moon check`: an `Int` is accepted by an `Int32` parameter
///

///| and an `Int32` is accepted by an `Int` parameter. Both directions, so it is
///

///|
/// a synonym and not a subtype.
test "0422: Int32 and Int are interchangeable as parameter types" {
  let r = @pipeline.run(
    "fn takes_i32(a : Int32) -> Int32 {\n  a\n}\nfn takes_int(a : Int) -> Int {\n  a\n}\nfn forward(x : Int) -> Int {\n  takes_i32(x)\n}\nfn backward(x : Int32) -> Int {\n  takes_int(x)\n}\n",
    "int32_synonym.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

// ---------------------------------------------------------------------------

///| AND THE REVERSE. If `Int32` had been wired to Unknown instead of to `Int`,
///

///| this would be 0 as well — so again the direction matters: the fix has to
///

///|
/// make the two interchangeable, not merely quiet.
test "0422: Int32 does not swallow a genuine mismatch" {
  let r = @pipeline.run(
    "fn takes_i32(a : Int32) -> Int32 {\n  a\n}\nfn build() -> Int {\n  takes_i32(\"not an integer\")\n}\n",
    "int32_wrong.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 1)
}

// ---------------------------------------------------------------------------

///| THE DECISION THIS FILE IS NOT MAKING, pinned so it cannot be made by

///| accident. `Int64` and `UInt` are NOT synonyms for `Int`: settled against

///| `moon check`, passing a `UInt` to an `Int` parameter is an Expr Type

///| Mismatch, and so is the reverse, and so is `Int64` against either.
///

///|
///

///| Mapping them onto `TInt` would therefore not be a harmless widening — it

///| would silence this check on exactly the mismatches `moon check` reports,

///| which is the 0.4.5 failure (a check whose precondition nothing ever

///| satisfies) with the sign flipped. They read as Unknown until they get their

///| own `Ty` variants. Corpus weight for whoever sizes that: 122 `: Int64` and

///| 23 `: UInt` annotations across proton + async + moui.
///

///|
///

///| So this asserts ZERO findings, and that is the correct answer, not a gap:

///|
/// Unknown is not assignable-into `Int` in a way that would be honest.
test "0422: Int64 and UInt are not treated as Int (control)" {
  let r = @pipeline.run(
    "fn takes_int(a : Int) -> Int {\n  a\n}\nfn from_i64(x : Int64) -> Int {\n  takes_int(x)\n}\nfn from_u64(x : UInt) -> Int {\n  takes_int(x)\n}\n",
    "int64_uint.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

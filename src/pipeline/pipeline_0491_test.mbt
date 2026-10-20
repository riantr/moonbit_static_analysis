//| 0491: the CROSS-FILE NAME gap -- the behavioral lens's READ path never asked
//| the table the other two lenses ask.
//|
//| THE DEFECT. A name declared in ANOTHER file -- a sibling of this one in the
//| same package, or a dependency -- is bound. The STRUCTURAL lens knows it: its
//| "no visible binding" gate has consulted the cross-file symbol table since
//| 0.4.3 (`walk.mbt`, `!self.extern_iface.has_type(name) &&
//| !self.extern_iface.has_value(name)`). The TYPE lens knows it: the same table,
//| `infer.mbt`'s `extern_iface.has_value(name)`.
//|
//| And the BEHAVIORAL lens's CALL path knows it: `Interp::call` asks the same
//| two questions, and its own comment says why -- "the alternative is
//| reporting the name as undefined, which CONTRADICTS the structural and type
//| lenses (both of which consult the same table and stay silent)".
//|
//| The READ path did not ask. So a name that IS bound elsewhere was reported
//| `undefined variable` by one lens and silent by the other two, on the same
//| line. Two lenses, one line, opposite answers.
//|
//| MEASURED, wzzc-dev/moui 0.1.12, the per-function view: 51 findings of this
//| shape -- 49 PRINTED, plus 2 the scanner's per-file print cap hides -- of
//| which 35 are `undefined variable 'Constant'` -- an enum variant of
//| `pub(all) enum DeclarationChannel` in `core/declaration.mbt`, read bare in
//| `core/modifier_paint.mbt`. The rest are the same shape:
//| `MoveLeft`/`MoveRight`/`MoveStart`/`MoveEnd` (variants of a `priv enum` in a
//| sibling file), `Up`, `view_size_key`, `DeclarationKey::double`, and the
//| package-private `dispatch_web_*`, `web_active_app`,
//| `clone_semantics_issue` and `macos_perf_now_ms`.
//|
//| SETTLED WITH THE TOOLCHAIN, `_verify/settle_0491_crossfile.ps1`, 12/12: the
//| toolchain ACCEPTS every same-package sibling shape and REFUSES the
//| cross-package ones and a name that exists nowhere.

///|
/// The table a `.mbti` scan produces. The `bool` is `is_const`, and a name in
/// `values` is a VALUE -- a function, a constant, or an enum constructor.
fn value_tab() -> @core.IfaceSymTab {
  let t = @core.IfaceSymTab::empty()
  t.values.set("Constant", true)
  t.values.set("helper", false)
  t
}

///|
/// The same table with a TYPE in it. A `.mbti` declares types and values
/// separately, and the structural lens's gate asks BOTH halves.
fn type_tab() -> @core.IfaceSymTab {
  let t = @core.IfaceSymTab::empty()
  t.types.set("SomeType", true)
  t
}

///|
/// A CROSS-FILE NAME READ IN A FUNCTION BODY IS NOT UNDEFINED.
///
/// The read is a READ, not a call: `let g = helper` binds the function as a
/// value, which is the shape `host_runtime.mbt:71` has
/// (`open_url=dispatch_web_open_url,`) and `macos_timer_host.mbt:26` has
/// (`clock=Some(macos_perf_now_ms),`). A CALL of a cross-file name was already
/// resolved -- `Interp::call` has asked the table since 0.4.3 -- so a test that
/// called one would pass before the fix and prove nothing.
test "0491: a cross-file name read in a function body is not undefined" {
  let src = "fn f() -> Int {\n  let g = helper\n  0\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", value_tab())
  assert_eq(count_family(perfn, "UndefinedName"), 0)
}

///|
/// THE CONTROL, and it is the row that makes the row above mean something.
///
/// The same source, with an EMPTY table: the name is bound nowhere, so it is
/// reported. A fix that silenced every undefined name would pass the row above
/// and fail this one -- and the toolchain's verdict on a name that exists
/// nowhere is REJECT (`_verify/settle_0491_crossfile.ps1`, rows xf11 and
/// xf12).
///
/// AND THE COUNT IS PER LENS, because the family-level count has no teeth here.
/// BOTH lenses report this name -- the structural lens says "no visible binding
/// for 'helper'", the behavioral lens says "undefined variable 'helper'" -- at
/// the same span, so the merge collapses them into ONE finding whose lens list
/// is the union. `count_family(perfn, "UndefinedName") == 1` is therefore
/// satisfied by the STRUCTURAL lens alone, and a blanket that silenced only the
/// BEHAVIORAL lens still passes it. Measured: mutation gate 0491's M4 -- the
/// blanket -- was killed by a pre-existing merge test rather than by this row,
/// for exactly this reason.
/// => 判据: a merged finding is counted by family, but a claim about ONE lens's
/// decision has to be counted by lens, or the other lens answers for it.
test "0491: the same name with an empty table is still reported" {
  let src = "fn f() -> Int {\n  let g = helper\n  0\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 1)
  assert_eq(count_family_in(perfn, "UndefinedName", @core.LBehavior), 1)
}

///|
/// A CROSS-FILE TYPE READ IS NOT UNDEFINED EITHER.
///
/// The structural lens's gate asks `has_type` as well as `has_value`, and a
/// lens that asked only one of the two would still contradict it. This row is
/// the only thing that pins the second half.
test "0491: a cross-file type read in a function body is not undefined" {
  let src = "fn f() -> Int {\n  let t = SomeType\n  0\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", type_tab())
  assert_eq(count_family(perfn, "UndefinedName"), 0)
}

///|
/// The CONTROL for the row above: the same read with an empty table.
test "0491: a cross-file type read with an empty table is still reported" {
  let src = "fn f() -> Int {\n  let t = SomeType\n  0\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 1)
}

///|
/// THE VALUE OF A CROSS-FILE NAME IS UNKNOWN, and the lens must not claim
/// otherwise.
///
/// The table says a name IS bound; it says nothing about what the name is. The
/// honest answer is "a value of unknown type", which absorbs -- and the
/// alternative, typing it as a function, would report a METHOD ERROR on
/// ordinary arithmetic. This is the row that distinguishes "the name resolves"
/// from "the name resolves to something specific".
///
/// The name is a CONST in the table (`is_const` true), and that is what makes
/// the row measure the BEHAVIORAL lens: the type lens types a cross-file const
/// as `TUnknown` and absorbs on its own, so the only thing that can produce a
/// mismatch here is the behavioral lens's own answer. With `helper` (a
/// non-const) the TYPE lens reports the mismatch first -- it types the name
/// `TUnknownFn` -- and the row would be measuring the wrong lens.
///
/// AND THE FAMILY IS `MethodError`, NOT `OperatorMismatch` -- measured, because
/// the first version of this row asserted the wrong one and so had no teeth at
/// all. `Interp::binop`'s fallback arm reports `FMethodError` ("no method
/// matching +(...)"); `FOpMismatch` is the TYPE lens's family. The two share a
/// merge GROUP -- `Family::merge_group` puts `FArgType | FMethodError |
/// FOpMismatch` under "arg-type" -- but a merge group is not a family, and a
/// count BY FAMILY cannot see the other one. Asserting `OperatorMismatch` here
/// counted zero findings of a family this lens never emits, and it stayed zero
/// while the mutant answered `AType("Function")` and produced a real
/// `MethodError`.
/// => 判据: two families that share a merge group are still two families.
/// Asserting the wrong one is not a weak assertion -- it is an assertion about
/// a finding this lens never emits, and it is green forever.
test "0491: a cross-file name's value absorbs instead of claiming a type" {
  let src = "fn f() -> Int {\n  let g = Constant\n  g + 1\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", value_tab())
  assert_eq(count_family(perfn, "UndefinedName"), 0)
  // The TYPE lens's own family, asserted so the row also says the type lens
  // absorbs on a cross-file const. It has no teeth for this increment: the
  // fix cannot reach the type lens.
  assert_eq(count_family(perfn, "OperatorMismatch"), 0)
  // The BEHAVIORAL lens's family, and the one with the teeth.
  assert_eq(count_family_in(perfn, "MethodError", @core.LBehavior), 0)
}

///|
/// THE MODULE VIEW IS UNCHANGED BY THIS FIX.
///
/// The module entry never executes a function body in a library module, so it
/// never reached the read path this fix touches. The two views are separate by
/// construction, and this row is what keeps them separate: the per-function
/// view's cross-file fix must not move the module view's numbers.
test "0491: the module view is unchanged by the cross-file fix" {
  let src = "fn f() -> Int {\n  let g = helper\n  0\n}\n"
  let modview = @pipeline.run(src, "x.mbt", value_tab())
  let perfn = @pipeline.run_functions(src, "x.mbt", value_tab())
  assert_eq(perfn.n_structural, modview.n_structural)
  assert_eq(perfn.n_type, modview.n_type)
}

// 0575: the CONTEXT-SENSITIVE pointer analysis, pinned to the decks' own
// examples.
//
// THE DECKS, AND WHAT EACH ROW HERE IS PINNED TO.
//
//   11-12_PTA-CS.pdf p.3-6   "Problem of Context-Insensitive Pointer Analysis":
//                            the identity function called with two different
//                            objects, and the question the deck leaves for the
//                            lecturer -- "Context insensitivity, x.get():".
//   11-12_PTA-CS.pdf p.99-115 the context abstraction functions: the three
//                            variants (call-site, object, type), context
//                            insensitivity as the special case, k-limiting,
//                            and the 1-CFA example with its call chain.
//
// THE TWO ANSWERS ARE THE POINT. The deck's program is small on purpose: one
// identity function, two call sites, two objects. Analysed ONCE, `id`'s
// parameter holds both objects, so `x` holds both, so `x.get()` may dispatch to
// `One::get` AND to `Two::get`. Analysed ONCE PER CALL SITE, `x` holds only
// `o1`. Both are measurable here, and both are measured.
//
// THE OBJECTS ARE NAMED THE DECK'S WAY -- by their allocation site's line --
// so `o1` is the `One` of line 1 and `o2` is the `Two` of line 2, exactly as
// deck 8 p.77 prints them. The CONTEXTS are named the deck's way too: a
// context is a list of call sites, and the call sites are lines, so the context
// of `id` under 1-CFA is "3" and "4" -- the two lines the calls are on.
//
// THE FIXTURES ARE HAND-BUILT ASTs, like every other row in this package's
// pointer-analysis tests, and for the same reason `pta_test.mbt` gives: the
// CFG is built by `cfg_of`, which allocates its nodes BACK TO FRONT, so a
// hand-built node list would not exercise the ordering the analysis reads.

///|
fn cx_name(x : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EName(x), }
}

///|
fn cx_struct(ty : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EStruct(ty, []), }
}

///|
fn cx_call(f : String, args : Array[@ast.Expr]) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.ECall(f, args, []), }
}

///|
fn cx_method(recv : String, m : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EMethodCall(cx_name(recv), m, [], []), }
}

///|
/// A span ON A LINE, because the line is what the analysis reads: an
/// allocation site is named by the line of its statement (deck 8 p.45-47,
/// p.77) and a call site is labelled by the line of its call (deck 11-12
/// p.104-115).
fn cx_span(line : Int32) -> @core.Span {
  { start: @core.pos(line, 1), end: @core.pos(line, 1), }
}

///|
fn cx_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: cx_span(line), kind: @ast.SLet(x, "", e), }
}

///|
/// A `let` WITH ITS ANNOTATION, because the receiver's declared type is what
/// the dispatch is resolved through (deck 7 p.33-39) and an unannotated
/// receiver has none.
fn cx_let_ann(
  line : Int32,
  x : String,
  ann : String,
  e : @ast.Expr,
) -> @ast.Stmt {
  { span: cx_span(line), kind: @ast.SLet(x, ann, e), }
}

///|
fn cx_tail(line : Int32, e : @ast.Expr) -> @ast.Stmt {
  { span: cx_span(line), kind: @ast.STail(e), }
}

///|
fn cx_param(name : String, ann : String) -> @ast.Param {
  { name, tyann: ann, omittable: false, span: @flow.no_span(), }
}

///|
fn cx_fn(
  name : String,
  params : Array[@ast.Param],
  body : Array[@ast.Stmt],
) -> @flow.CgFn {
  { name, params, body, }
}

///|
/// The deck 11-12 p.3-6 program, as the two functions the analysis sees.
///
///     void main() {
///       Number n1, n2, x, y;
///       n1 = new One();     // o1
///       n2 = new Two();     // o2
///       x = id(n1);
///       y = id(n2);
///       int i = x.get();
///     }
///     Number id(Number n) { return n; }
///
/// `id` RETURNS ITS PARAMETER, so the deck's program is the one where the
/// difference between one analysis and many shows up in the CALLER's map and
/// not only in the callee's.
fn cx_merged_program() -> Array[@flow.CgFn] {
  [
    cx_fn("main", [], [
      cx_let(1, "n1", cx_struct("One")),
      cx_let(2, "n2", cx_struct("Two")),
      cx_let(3, "x", cx_call("id", [cx_name("n1")])),
      cx_let(4, "y", cx_call("id", [cx_name("n2")])),
      cx_let(5, "i", cx_method("x", "get")),
    ]),
    cx_fn("id", [cx_param("n", "Number")], [cx_tail(7, cx_name("n"))]),
  ]
}

///|
/// The deck 11-12 p.104-115 call chain, as the three functions it has:
///
///     1  void main() {
///     2    …
///     3    a.foo();
///     4    …
///     5  }
///     7  void foo() {
///     8    …
///     9    b.bar();
///    10    …
///    11  }
///    13  void bar() {
///    14    …
///    15    bar();
///    16    …
///    17  }
///
/// THE CALLS ARE STATIC HERE, and that is the tree's boundary and not the
/// deck's: `a.foo()` is a VIRTUAL call, and a method body is not in this
/// tree's AST (the parser reads past `impl` declarations whole), so a virtual
/// call has no body to analyse. The CHAIN is the deck's, and the CONTEXTS the
/// chain produces are what the deck's slides show.
fn cx_chain_program() -> Array[@flow.CgFn] {
  [
    cx_fn("main", [], [cx_let(3, "a", cx_call("foo", []))]),
    cx_fn("foo", [], [cx_let(9, "b", cx_call("bar", []))]),
    cx_fn("bar", [], [cx_let(15, "c", cx_call("bar", []))]),
  ]
}

///|
/// The context-sensitive run of the merged program, under one abstraction.
fn cx_merged(sel : @flow.CtxSelect) -> @flow.PtaCtxResult {
  @flow.pta_ctx_run(cx_merged_program(), @flow.TraitTable::empty(), "main", sel)
}

///|
/// The CONTEXT INSENSITIVITY of deck 11-12 p.102 -- "Select _, _, _ = [ ]" --
/// merges the two call sites, and the merged parameter is what deck 11-12
/// p.6 is asking about.
test "0575: context insensitivity merges the two call sites -- deck 11-12 p.3-6, p.102" {
  let res = cx_merged(@flow.CtxSelect::Insensitive)
  let x = @flow.pta_ctx_of(res, "main", "", "x")
  let y = @flow.pta_ctx_of(res, "main", "", "y")
  // `x` HOLDS BOTH OBJECTS, and so does `y`: `id` was analysed ONCE.
  assert_true(x.length() == 2)
  assert_true(y.length() == 2)
  assert_true(x.contains("o1"))
  assert_true(x.contains("o2"))
  assert_true(y.contains("o1"))
  assert_true(y.contains("o2"))
  // AND `id` WAS ANALYSED ONCE: one context, the empty one.
  let ctxs = @flow.pta_ctx_contexts(res, "id")
  assert_true(ctxs.length() == 1)
  assert_true(ctxs[0] == "")
}

///|
/// THE DECK'S OTHER COLUMN. 11-12 p.49-53: "Analyze each method multiple
/// times, once for each context" -- and p.112-115's 1-CFA, "Select _, l, _ =
/// [ l ]".
///
/// THE TWO MAPS DIFFER IN EXACTLY ONE POINTER, and that is the whole difference
/// the deck's example is about: `x` and `y` each hold ONE object instead of two.
test "0575: 1-CFA analyses `id` once per call site -- deck 11-12 p.49-53, p.112-115" {
  let res = cx_merged(@flow.CtxSelect::CallSite(1))
  let x = @flow.pta_ctx_of(res, "main", "", "x")
  let y = @flow.pta_ctx_of(res, "main", "", "y")
  assert_true(x.length() == 1)
  assert_true(x.contains("o1"))
  assert_true(y.length() == 1)
  assert_true(y.contains("o2"))
  // AND `id` WAS ANALYSED TWICE, once per call site, and the contexts are the
  // CALL SITES -- the lines the calls are on, which is how the deck labels
  // them (p.104-115).
  let ctxs = @flow.pta_ctx_contexts(res, "id")
  assert_true(ctxs.length() == 2)
  assert_true(ctxs.contains("3"))
  assert_true(ctxs.contains("4"))
}

///|
/// THE CONTEXT IS THE CALLEE'S OWN MAP, and the two maps are printed side by
/// side -- which is how the deck compares its two columns (p.61-64 against
/// p.68).
test "0575: the two columns, printed -- one analysis and many" {
  let insensitive = cx_merged(@flow.CtxSelect::Insensitive)
  let sensitive = cx_merged(@flow.CtxSelect::CallSite(1))
  // THE MERGED COLUMN: `id`'s parameter holds both objects.
  let merged = @flow.pta_ctx_text(insensitive, "id", "")
  assert_true(merged.contains("n -> {o1,o2}"))
  // AND THE SPLIT COLUMN: one object per context.
  let first = @flow.pta_ctx_text(sensitive, "id", "3")
  let second = @flow.pta_ctx_text(sensitive, "id", "4")
  assert_true(first.contains("n -> {o1}"))
  assert_true(second.contains("n -> {o2}"))
}

///|
/// THE CALL CHAIN OF DECK 11-12 p.104-115, and the context each function is
/// analysed under.
///
/// p.105-107 print the chain as it grows -- "Context: [ ]", "Context: [3]",
/// "Context: [3,9]" -- and p.113-115 print the 1-CFA reading of it: "Context:
/// [ ]", "Context: [3]", and then the call chain TRUNCATED to its last call
/// site.
test "0575: the call chain's contexts -- deck 11-12 p.105-107 and p.113-115" {
  let res = @flow.pta_ctx_run(
    cx_chain_program(),
    @flow.TraitTable::empty(),
    "main",
    @flow.CtxSelect::CallSite(1),
  )
  // THE ENTRY IS THE EMPTY CONTEXT.
  let main_ctxs = @flow.pta_ctx_contexts(res, "main")
  assert_true(main_ctxs.length() == 1)
  assert_true(main_ctxs[0] == "")
  // `foo` IS CALLED AT LINE 3.
  let foo_ctxs = @flow.pta_ctx_contexts(res, "foo")
  assert_true(foo_ctxs.length() == 1)
  assert_true(foo_ctxs[0] == "3")
  // AND `bar` IS CALLED AT LINE 9 AND AT LINE 15, so under 1-CFA it has TWO
  // contexts -- the two call sites, each alone.
  let bar_ctxs = @flow.pta_ctx_contexts(res, "bar")
  assert_true(bar_ctxs.length() == 2)
  assert_true(bar_ctxs.contains("9"))
  assert_true(bar_ctxs.contains("15"))
}

///|
/// TWO-CFA, and the difference between it and 1-CFA IS THE TRUNCATION.
///
/// p.115 prints the two formulas side by side: "Select(c, l, _) = [l_{n-k+1},
/// ..., l_n]" for the general k, and "Select _, l, _ = [ l ]" for k = 1. So
/// under 2-CFA the chain's LAST TWO call sites survive.
test "0575: 2-CFA keeps the last two call sites -- deck 11-12 p.115" {
  let res = @flow.pta_ctx_run(
    cx_chain_program(),
    @flow.TraitTable::empty(),
    "main",
    @flow.CtxSelect::CallSite(2),
  )
  let bar_ctxs = @flow.pta_ctx_contexts(res, "bar")
  // THREE CONTEXTS, measured: the chain is 3-9, then 9-15, then 15-15. The
  // chain is the deck's own (p.104-115) and it GROWS, which is exactly why
  // the deck bounds it (p.110-111).
  assert_true(bar_ctxs.length() == 3)
  // THE CALL FROM `foo`: the chain is 3 then 9.
  assert_true(bar_ctxs.contains("3,9"))
  // AND THE CALL FROM `bar`: the chain is 9 then 15.
  assert_true(bar_ctxs.contains("9,15"))
  // AND `bar` CALLING ITSELF: the chain is 15 then 15.
  assert_true(bar_ctxs.contains("15,15"))
}

///|
/// WHY THE LIMIT EXISTS. Deck 11-12 p.110-111: "Ensure termination of pointer
/// analysis" and "Avoid too many contexts (long call chains) in real-world
/// programs blow up the pointer analysis".
///
/// THE DECK'S OWN CHAIN IS THE ARGUMENT: `bar` calls `bar`, so the chain grows
/// by one call site at every step. Under a LARGE k the number of contexts
/// grows with the chain, and under a SMALL k it does not.
test "0575: the k-limit is what stops the chain -- deck 11-12 p.110-111" {
  let one = @flow.pta_ctx_run(
    cx_chain_program(),
    @flow.TraitTable::empty(),
    "main",
    @flow.CtxSelect::CallSite(1),
  )
  let ten = @flow.pta_ctx_run(
    cx_chain_program(),
    @flow.TraitTable::empty(),
    "main",
    @flow.CtxSelect::CallSite(10),
  )
  let one_ctxs = @flow.pta_ctx_contexts(one, "bar").length()
  let ten_ctxs = @flow.pta_ctx_contexts(ten, "bar").length()
  // UNDER 1-CFA THE CHAIN IS CUT AT EVERY STEP, so there are only TWO
  // contexts no matter how long the chain gets.
  assert_true(one_ctxs == 2)
  // AND UNDER A LARGER LIMIT THE CHAIN GROWS -- the blow-up the deck's slide
  // warns about. ELEVEN, measured: the chain is two labels long at the first
  // step, and it grows by one label at every step until the window is full,
  // and then the window SLIDES over the fifteens.
  assert_true(ten_ctxs > one_ctxs)
  assert_true(ten_ctxs == 11)
}

///|
/// A CALL WHOSE TARGET HAS NO BODY IN THIS TREE IS COUNTED, not skipped
/// silently.
///
/// `x.get()` is a VIRTUAL call, and a trait method's body is not in this
/// tree's AST (the parser reads past `impl` and `trait` declarations whole),
/// so the target cannot be analysed. The run says so.
test "0575: a call that resolves to nothing is counted -- the tree's boundary" {
  let res = cx_merged(@flow.CtxSelect::CallSite(1))
  // `x.get()` IS A VIRTUAL CALL AND `x` HAS NO DECLARED TYPE, so it resolves
  // to NOTHING -- and the run says so rather than guessing a target. The
  // call to `id` resolved, and the analysis carried on.
  assert_true(res.unresolved >= 1)
  assert_true(res.no_body == 0)
  // AND THE ANALYSED PART IS STILL ANALYSED: `id`'s two contexts are there.
  assert_true(@flow.pta_ctx_contexts(res, "id").length() == 2)
}

///|
/// THE OBJECT-SENSITIVE VARIANT, deck 11-12 p.100: the RECEIVER'S OBJECT is
/// the callee's context.
///
/// The receiver here is a plain name whose points-to set is known, so the
/// context is that object's allocation site -- and TWO receivers with TWO
/// objects give TWO contexts, which is the same split the call-site variant
/// gives and for the same reason.
test "0575: the object-sensitive variant uses the receiver's object -- deck 11-12 p.100" {
  let fns = [
    cx_fn("main", [], [
      cx_let_ann(1, "a", "Number", cx_struct("One")),
      cx_let_ann(2, "b", "Number", cx_struct("Two")),
      cx_let(3, "r", cx_method("a", "get")),
      cx_let(4, "s", cx_method("b", "get")),
    ]),
  ]
  // A TRAIT, so the call resolves to the trait's own method -- a name with no
  // body in this tree, which the count above reports.
  let tab = @flow.collect_trait_table(
    "trait Number {\n  fn get(self) -> Int\n}\n",
  )
  let res = @flow.pta_ctx_run(fns, tab, "main", @flow.CtxSelect::Object)
  // THE CONTEXTS ARE THE RECEIVERS' OBJECTS: the allocation sites.
  let ctxs = @flow.pta_ctx_contexts(res, "Number::get")
  assert_true(ctxs.length() == 2)
  assert_true(ctxs.contains("o1"))
  assert_true(ctxs.contains("o2"))
  // AND THE TARGET HAS NO BODY IN THIS TREE -- a trait method's body is not
  // in the AST -- so the run says so instead of analysing nothing silently.
  assert_true(res.no_body == 2)
  // THE CONTEXT IS STILL THERE, because the context is a fact about the CALL
  // and not about an analysis that did not happen.
  assert_true(res.edges.length() == 2)
}

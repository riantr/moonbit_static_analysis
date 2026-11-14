// 0582: the THREE CONTEXT-SENSITIVITY VARIANTS, pinned to the deck's own
// examples -- deck 11-12 p.165-178.
//
// THE DECK'S EXAMPLE FOR TYPE vs OBJECT (p.172-175):
//
//      1  class X {
//      2   void main() {
//      3    Y y1 = new Y();
//      4    y1.foo();
//      5    Y y2 = new Y();
//      6    y2.foo();
//      7    Y y3 = new Y();
//      8    y3.foo();
//      9   }
//     10  }
//     11  class Y {
//     12   void foo() {}
//     13  }
//
// and the deck's measurement of it:
//
//     "Contexts of foo():
//        Object-sensitivity: o3, o5, [o7]
//        Type-sensitivity: [X]"
//
// THE LINE NUMBERS ARE THE DECK'S, so the objects are named the deck's way:
// the allocations are on lines 3, 5 and 7, so the objects are o3, o5 and o7.
//
// THE SPELLING IS THIS TREE'S, because this tree's AST HAS NO CLASSES: `new
// Y()` is the allocation `Y::{}`, `foo()` is a method call, and the class `X`
// that the deck's allocation sites sit in is not in the tree at all -- which is
// exactly why the type context is the receiver's DECLARED type and not the
// deck's `InType` (see `pta_variants.mbt`).
//
// THE FIXTURES ARE HAND-BUILT ASTs, like every other row in this package's
// pointer-analysis tests: the CFG is built by `cfg_of`, which allocates its
// nodes BACK TO FRONT, so a hand-built node list would not exercise the ordering
// the analysis reads.

///|
fn tv_name(x : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EName(x), }
}

///|
fn tv_struct(ty : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EStruct(ty, []), }
}

///|
fn tv_method(recv : String, m : String, args : Array[@ast.Expr]) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EMethodCall(tv_name(recv), m, args, []), }
}

///|
fn tv_span(line : Int32) -> @core.Span {
  { start: @core.pos(line, 1), end: @core.pos(line, 1), }
}

///|
fn tv_let(line : Int32, x : String, ann : String, e : @ast.Expr) -> @ast.Stmt {
  { span: tv_span(line), kind: @ast.SLet(x, ann, e), }
}

///|
fn tv_tail(line : Int32, e : @ast.Expr) -> @ast.Stmt {
  { span: tv_span(line), kind: @ast.STail(e), }
}

///|
fn tv_param(name : String, ann : String) -> @ast.Param {
  { name, tyann: ann, omittable: false, span: @flow.no_span(), }
}

///|
fn tv_fn(
  name : String,
  params : Array[@ast.Param],
  body : Array[@ast.Stmt],
) -> @flow.CgFn {
  { name, params, body, }
}

///|
/// The deck's p.172-175 program: three receivers of one type, three calls.
fn tv_program() -> Array[@flow.CgFn] {
  [
    tv_fn("main", [], [
      tv_let(3, "y1", "Y", tv_struct("Y")),
      tv_let(4, "r1", "", tv_method("y1", "foo", [])),
      tv_let(5, "y2", "Y", tv_struct("Y")),
      tv_let(6, "r2", "", tv_method("y2", "foo", [])),
      tv_let(7, "y3", "Y", tv_struct("Y")),
      tv_let(8, "r3", "", tv_method("y3", "foo", [])),
    ]),
  ]
}

///|
/// The trait table the deck's `Y` needs: a CONCRETE type, so the virtual call
/// resolves to `Y::foo` (deck 7's `Dispatch`, p.33-39).
fn tv_tab() -> @flow.TraitTable {
  @flow.collect_trait_table("struct Y { }\nstruct X { }\n")
}

///|
/// The deck's p.172-175 program, read three ways.
fn tv_compare() -> @flow.CtxVariants {
  @flow.pta_variants_compare(
    tv_program(),
    tv_tab(),
    "main",
    @flow.CtxSelect::CallSite(1),
  )
}

///|
/// THE OBJECT-SENSITIVE VARIANT (deck 11-12 p.100): the context is the
/// RECEIVER'S OBJECT, and the deck's three objects are three contexts.
test "0582: the object-sensitive variant's contexts are the receiver's objects -- deck 11-12 p.172-174" {
  let c = tv_compare()
  let ctxs = @flow.pta_ctx_contexts(c.object, "Y::foo")
  // THE DECK'S OWN THREE: o3, o5, o7.
  assert_true(ctxs.length() == 3)
  assert_true(ctxs.contains("o3"))
  assert_true(ctxs.contains("o5"))
  assert_true(ctxs.contains("o7"))
  // AND THE TARGET HAS NO BODY IN THIS TREE -- a method's body is not in the
  // AST -- so the run counts it instead of analysing nothing silently.
  assert_true(c.object.no_body == 3)
}

///|
/// THE TYPE-SENSITIVE VARIANT (deck 11-12 p.170-171): the context is a TYPE,
/// and the deck's three objects of one type give ONE context.
test "0582: the type-sensitive variant's context is the receiver's type -- deck 11-12 p.170-171, p.174" {
  let c = tv_compare()
  let ctxs = @flow.pta_ctx_contexts(c.type_ctx, "Y::foo")
  // ONE CONTEXT FOR THREE RECEIVERS: the deck's "[X]", and the tree's "Y".
  assert_true(ctxs.length() == 1)
  assert_true(ctxs.contains("Y"))
}

///|
/// THE DECK'S CLAIM, AS A MEASUREMENT: "Type sensitivity is a coarser
/// abstraction over object sensitivity" (p.172-175), and "Compared to object
/// sensitivity, type sensitivity trades precision for better efficiency, by
/// merging the allocation sites in the same type in contexts" (p.175).
///
/// THE MERGING IS THE MEASUREMENT: the type variant has ONE context where the
/// object variant has THREE.
test "0582: type sensitivity is a coarser abstraction over object sensitivity -- deck 11-12 p.174-175" {
  let c = tv_compare()
  let objs = @flow.pta_ctx_contexts(c.object, "Y::foo")
  let tys = @flow.pta_ctx_contexts(c.type_ctx, "Y::foo")
  assert_true(objs.length() == 3)
  assert_true(tys.length() == 1)
  assert_true(tys.length() < objs.length())
  // AND THE CALL-SITE VARIANT HAS THREE AS WELL -- the three call sites.
  let sites = @flow.pta_ctx_contexts(c.call_site, "Y::foo")
  assert_true(sites.length() == 3)
  assert_true(sites.contains("4"))
  assert_true(sites.contains("6"))
  assert_true(sites.contains("8"))
}

///|
/// THE DECK'S CALL-SITE vs OBJECT CLAIM (p.165): "In theory, their precision
/// is incomparable".
///
/// WHAT IS MEASURED HERE IS THE ABSTRACTION, and it is the checkable form of
/// the claim: the two variants produce DIFFERENT context sets for the same
/// program, and NEITHER IS A REFINEMENT OF THE OTHER -- so neither answer can
/// be read as the other's more precise version.
test "0582: call-site and object sensitivity give different contexts -- deck 11-12 p.165" {
  let c = tv_compare()
  let sites = @flow.pta_ctx_contexts(c.call_site, "Y::foo")
  let objs = @flow.pta_ctx_contexts(c.object, "Y::foo")
  // NEITHER SET CONTAINS THE OTHER.
  let mut sites_in_objs = 0
  for s in sites {
    if objs.contains(s) {
      sites_in_objs = sites_in_objs + 1
    }
  }
  assert_true(sites_in_objs == 0)
  let mut objs_in_sites = 0
  for o in objs {
    if sites.contains(o) {
      objs_in_sites = objs_in_sites + 1
    }
  }
  assert_true(objs_in_sites == 0)
}

///|
/// THE THREE VARIANTS' CONTEXTS, PRINTED -- the deck's p.174 table with the
/// call-site column the deck does not print there.
test "0582: the three variants, printed" {
  let c = tv_compare()
  let text = @flow.pta_variants_text(c, "Y::foo")
  assert_true(text.contains("call-site: [4, 6, 8]"))
  assert_true(text.contains("object: [o3, o5, o7]"))
  assert_true(text.contains("type: [Y]"))
}

///|
/// THE PRECISION, MEASURED: what the merging COSTS.
///
/// THE PROGRAM IS THE DECK'S SHAPE with an argument added, because the deck's
/// example has no arguments and this tree's model has no `this` -- a method
/// call's receiver does not flow into the callee. The argument is what makes
/// the two invocations distinguishable INSIDE the callee, and the callee
/// returns it, so the caller's two names show what the analysis merged:
///
///      1  fn main() {
///      2    let y1 : Y = Y::{};
///      3    let a = One::{};
///      4    let r1 = y1.foo(a);
///      5    let y2 : Y = Y::{};
///      6    let b = Two::{};
///      7    let r2 = y2.foo(b);
///      8  }
///
/// THE THREE READINGS:
///
///   * CALL-SITE -- `Y::foo` is analysed under the call site's context, so the
///     two invocations are TWO states, the parameter holds one object each, and
///     `r1` and `r2` hold DIFFERENT objects.
///   * OBJECT -- the same: the receiver's objects are two contexts, so the
///     two invocations are two states and the two results differ.
///   * TYPE -- the receiver's type is ONE context, so the two invocations are
///     ONE state, the parameter holds BOTH objects, and `r1` and `r2` hold the
///     SAME objects.
///
/// THAT IS THE DECK'S "merging the allocation sites in the same type in
/// contexts" (p.175) MADE VISIBLE IN THE POINTS-TO SETS.
test "0582: the type variant merges the two invocations -- deck 11-12 p.175" {
  let fns = [
    tv_fn("main", [], [
      tv_let(2, "y1", "Y", tv_struct("Y")),
      tv_let(3, "a", "One", tv_struct("One")),
      tv_let(4, "r1", "", tv_method("y1", "foo", [tv_name("a")])),
      tv_let(5, "y2", "Y", tv_struct("Y")),
      tv_let(6, "b", "Two", tv_struct("Two")),
      tv_let(7, "r2", "", tv_method("y2", "foo", [tv_name("b")])),
    ]),
    // THE CALLEE, WITH A BODY -- a method body is not in this tree's AST, but
    // the fixture is hand-built, so the target can have one. It returns its
    // parameter, so the caller's two names show what was merged.
    tv_fn("Y::foo", [tv_param("p", "Number")], [tv_tail(9, tv_name("p"))]),
  ]
  let tab = tv_tab()
  // THE CALL-SITE READING: TWO STATES, TWO DIFFERENT RESULTS.
  let sites = @flow.pta_ctx_run(fns, tab, "main", @flow.CtxSelect::CallSite(1))
  let r1 = @flow.pta_ctx_of(sites, "main", "", "r1")
  let r2 = @flow.pta_ctx_of(sites, "main", "", "r2")
  assert_true(r1.length() == 1)
  assert_true(r2.length() == 1)
  assert_true(r1.contains("o3"))
  assert_true(r2.contains("o6"))
  assert_true(!r1.contains("o6"))
  // THE OBJECT READING: THE SAME, FOR THE SAME REASON.
  let objs = @flow.pta_ctx_run(fns, tab, "main", @flow.CtxSelect::Object)
  let or1 = @flow.pta_ctx_of(objs, "main", "", "r1")
  let or2 = @flow.pta_ctx_of(objs, "main", "", "r2")
  assert_true(or1.length() == 1)
  assert_true(or2.length() == 1)
  assert_true(or1.contains("o3"))
  assert_true(or2.contains("o6"))
  // AND THE TYPE READING: ONE STATE, AND THE TWO RESULTS ARE THE SAME.
  let tys = @flow.pta_ctx_run(fns, tab, "main", @flow.CtxSelect::Type(1))
  let tr1 = @flow.pta_ctx_of(tys, "main", "", "r1")
  let tr2 = @flow.pta_ctx_of(tys, "main", "", "r2")
  assert_true(tr1.length() == 2)
  assert_true(tr2.length() == 2)
  assert_true(tr1.contains("o3"))
  assert_true(tr1.contains("o6"))
  assert_true(tr2.contains("o3"))
  assert_true(tr2.contains("o6"))
  // AND THE MERGED STATE IS ONE STATE, which is where the merging shows.
  assert_true(@flow.pta_ctx_contexts(tys, "Y::foo").length() == 1)
  assert_true(@flow.pta_ctx_contexts(sites, "Y::foo").length() == 2)
  assert_true(@flow.pta_ctx_contexts(objs, "Y::foo").length() == 2)
}

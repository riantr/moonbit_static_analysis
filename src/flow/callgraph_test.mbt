// 0574: THE CALL GRAPH -- deck 7_Inter §2 -- pinned to the deck's own
// algorithms.
//
// THE NUMBERS ARE THE SLIDES', NOT THE IMPLEMENTATION'S. `Interprocedural
// Analysis` (Tian Tan, Nanjing University, 2021) prints `Resolve(call)` on
// p.33-39, `BuildCallGraph(main)` on p.52-56, a CHA example on p.40-46 and
// the features of CHA on p.47-49. Every row below asserts one of those.
//
// WHY HAND-BUILT AND NOT PARSED: the same reason `cprop_intra_test.mbt` and
// `reaching_test.mbt` give. This package does not depend on the PARSER, so a
// test builds an `Expr` without reaching for it; the one frontend dependency
// it has is the LEXER, and `callgraph.mbt` says why.
//
// THE ONE PART THAT IS NOT HAND-BUILT IS THE TRAIT HIERARCHY, and it is read
// from a SOURCE STRING on purpose: the hierarchy is a fact about the source
// text, and reading it with the same reader the analyzer uses is what makes
// the row an end-to-end claim rather than a claim about a hand-made table.

///|
/// A name.
fn cg_name(x : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EName(x), }
}

///|
/// A call `f()`.
fn cg_call(name : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.ECall(name, [], []), }
}

///|
/// A method call `recv.m()`.
fn cg_method(recv : String, name : String) -> @ast.Expr {
  {
    span: @flow.no_span(),
    kind: @ast.EMethodCall(cg_name(recv), name, [], []),
  }
}

///|
/// A statement whose kind is `SExpr` -- an expression statement.
fn cg_stmt(e : @ast.Expr) -> @ast.Stmt {
  { span: @flow.no_span(), kind: @ast.SExpr(e), }
}

///|
/// A parameter.
fn cg_param(name : String, tyann : String) -> @ast.Param {
  { name, tyann, omittable: false, span: @flow.no_span(), }
}

///|
/// A function, as the call graph takes it.
fn cg_fn(
  name : String,
  params : Array[@ast.Param],
  body : Array[@ast.Stmt],
) -> @flow.CgFn {
  { name, params, body, }
}

///|
/// The deck's hierarchy, in MoonBit's terms.
///
/// THE DECK'S p.40-46 EXAMPLE IS A CLASS HIERARCHY -- `A`, `B extends A`,
/// `C extends B`, `D extends B` -- and MoonBit has no classes. What MoonBit
/// has is a TRAIT and the types that implement it, and that is the whole of
/// the hierarchy CHA needs: the receiver's declared type is the trait, and
/// the "subclasses of c or c itself" are the types that implement it plus the
/// trait itself.
fn cg_hierarchy_src() -> String {
  "trait Marker {\n  fn foo(self) -> Int\n}\n\nstruct A {}\nimpl Marker for A {\n  fn foo(self) -> Int { 0 }\n}\n\nstruct B {}\nimpl Marker for B {\n  fn foo(self) -> Int { 0 }\n}\n\nstruct C {}\nderive(Debug, Eq)\n"
}

// ---------------------------------------------------------------------------
// A -- the trait hierarchy, which is the deck's CLASS HIERARCHY
// ---------------------------------------------------------------------------

///|
/// THE HIERARCHY IS READ, not asserted: a trait, its methods, the types that
/// implement it, and a `derive`.
///
/// THE `derive` ROW IS THE ONE THAT NEEDS THE SHAPE: MoonBit writes
/// `derive(Debug, Eq)` RIGHT AFTER the type's own declaration, so the reader
/// has to remember the last type it saw. It is a different fact from "which
/// names does this file declare", which is the parser's harvest, and it is
/// the only fact that says WHICH TYPE IMPLEMENTS WHICH TRAIT.
test "0574: the trait hierarchy -- a trait, its implementors, and a derive" {
  let tab = @flow.collect_trait_table(cg_hierarchy_src())
  // THE TRAIT AND ITS METHODS.
  assert_true(tab.traits.contains("Marker"))
  assert_true(tab.has_method("Marker", "foo"))
  // THE IMPLEMENTORS: the two `impl` blocks.
  assert_true(tab.implementors("Marker").contains("A"))
  assert_true(tab.implementors("Marker").contains("B"))
  assert_true(tab.implementors("Marker").length() == 2)
  // AND THE DERIVE, which is how a type implements a trait without an impl.
  assert_true(tab.implementors("Debug").contains("C"))
  assert_true(tab.implementors("Eq").contains("C"))
  // THE TYPE ITSELF IS A TYPE, and the trait is one too.
  assert_true(tab.types.contains("A"))
  assert_true(tab.types.contains("Marker"))
  // AND AN IMPL'S OWN METHODS ARE NOT THE TRAIT'S METHODS: `impl Marker for A`
  // gives `A::foo`, not `Marker::foo`.
  assert_false(tab.has_method("Marker", "bar"))
}

// ---------------------------------------------------------------------------
// B -- Resolve, the deck's p.33-39
// ---------------------------------------------------------------------------

///|
/// THE STATIC CASE: `T = { m }`.
///
/// The callee's name IS the target, and nothing else is consulted -- no
/// hierarchy, no receiver.
test "0574: Resolve -- a static call is the callee's own name" {
  let call = @flow.CgCall::{
    kind: @flow.CallKind::Static,
    name: "foo",
    receiver: "",
    args: [],
    lhs: "",
  }
  let declared : Map[String, String] = Map([])
  let t = @flow.resolve_call(call, declared, @flow.TraitTable::empty())
  assert_true(t.length() == 1)
  assert_true(t[0] == "foo")
}

///|
/// THE SPECIAL CASE: `cm = class type of m; T = { Dispatch(cm, m) }`.
///
/// The parser folds `::` into the name, so `Type::m(x)` arrives as the name
/// `Type::m` -- and that name IS the deck's `Dispatch(cm, m)` already spelled.
test "0574: Resolve -- a special call names its type in the call" {
  let call = @flow.CgCall::{
    kind: @flow.CallKind::Special,
    name: "A::foo",
    receiver: "",
    args: [],
    lhs: "",
  }
  let declared : Map[String, String] = Map([])
  let t = @flow.resolve_call(call, declared, @flow.TraitTable::empty())
  assert_true(t.length() == 1)
  assert_true(t[0] == "A::foo")
}

///|
/// THE VIRTUAL CASE: the declared type of the receiver, and every type that
/// implements it, plus the trait itself.
///
/// "c = declared type of receiver variable at call; foreach c' that is a
/// subclass of c or c itself do add Dispatch(c', m) to T" (p.33-39).
///
/// THE RECEIVER'S DECLARED TYPE IS `&Marker`, and the `&` is dropped: a
/// trait object is written `&T`, and `moon check` answers 4100 "The type Node
/// is not a trait" for `&Node` on a struct -- so the `&` means the type is
/// the TRAIT, which is the case CHA answers.
test "0574: Resolve -- a virtual call is the trait and every type that implements it" {
  let tab = @flow.collect_trait_table(cg_hierarchy_src())
  let declared : Map[String, String] = Map([("x", "&Marker")])
  let call = @flow.CgCall::{
    kind: @flow.CallKind::Virtual,
    name: "foo",
    receiver: "x",
    args: [],
    lhs: "",
  }
  let t = @flow.resolve_call(call, declared, tab)
  // THE TRAIT ITSELF -- the deck's "or c itself".
  assert_true(t.contains("Marker::foo"))
  // AND EVERY TYPE THAT IMPLEMENTS IT -- the deck's "a subclass of c".
  assert_true(t.contains("A::foo"))
  assert_true(t.contains("B::foo"))
  // AND NOTHING ELSE: `C` implements `Debug` and `Eq`, not `Marker`.
  assert_true(t.length() == 3)
}

///|
/// THE VIRTUAL CASE THROUGH A CONCRETE TYPE: one target.
///
/// MoonBit has no subclasses of a struct, so a receiver whose declared type
/// is a struct dispatches to that struct's own method.
test "0574: Resolve -- a virtual call through a concrete type is that type's method" {
  let tab = @flow.collect_trait_table(cg_hierarchy_src())
  let declared : Map[String, String] = Map([("s", "A")])
  let call = @flow.CgCall::{
    kind: @flow.CallKind::Virtual,
    name: "foo",
    receiver: "s",
    args: [],
    lhs: "",
  }
  let t = @flow.resolve_call(call, declared, tab)
  assert_true(t.length() == 1)
  assert_true(t[0] == "A::foo")
}

///|
/// THE VIRTUAL CASE WITH NO DECLARED TYPE: NO TARGET, AND A COUNT.
///
/// An unannotated receiver has no declared type, and a receiver whose type
/// this file does not declare has no hierarchy to look up. Neither is
/// connected to a guess: the target set is EMPTY, and the caller COUNTS the
/// site as unresolved. That is the same contract `icfg.mbt`'s `unresolved`
/// carries, and it is the direction the deck's own p.47-49 points at --
/// CHA is an approximation, and an approximation that counts what it did not
/// resolve is honest about it.
test "0574: Resolve -- a virtual call with no declared type resolves to nothing" {
  let tab = @flow.collect_trait_table(cg_hierarchy_src())
  let call = @flow.CgCall::{
    kind: @flow.CallKind::Virtual,
    name: "foo",
    receiver: "x",
    args: [],
    lhs: "",
  }
  // NO DECLARATION AT ALL.
  let none : Map[String, String] = Map([])
  assert_true(@flow.resolve_call(call, none, tab).length() == 0)
  // AN UNANNOTATED DECLARATION.
  let blank : Map[String, String] = Map([("x", "")])
  assert_true(@flow.resolve_call(call, blank, tab).length() == 0)
  // AND A TYPE NOBODY DECLARED.
  let ghost : Map[String, String] = Map([("x", "Ghost")])
  assert_true(@flow.resolve_call(call, ghost, tab).length() == 0)
}

// ---------------------------------------------------------------------------
// C -- BuildCallGraph, the deck's p.52-56
// ---------------------------------------------------------------------------

///|
/// THE DECK'S WORK LIST, from `main`.
///
/// THE DECK'S EXAMPLE (p.57-72) is `A.main` calling `A.foo`, which calls
/// `a.bar()` on a receiver whose declared type is `A` -- and the hierarchy
/// says `bar` may be `A`'s own, `B`'s or `C`'s. In MoonBit the receiver's
/// declared type is the TRAIT `Marker`, and the hierarchy says the same
/// thing: `Marker`'s own method, and one for every type that implements it.
///
/// THE WORK LIST'S SHAPE IS THE DECK'S: `WL` starts with the entry method,
/// a method is added to `RM` the first time it is taken off the list, and
/// every resolved target is put back on the list.
test "0574: BuildCallGraph -- the deck's work list, from main" {
  let tab = @flow.collect_trait_table(cg_hierarchy_src())
  let fns = [
    cg_fn("main", [], [cg_stmt(cg_call("foo"))]),
    cg_fn("foo", [cg_param("x", "&Marker")], [cg_stmt(cg_method("x", "foo"))]),
  ]
  let g = @flow.build_call_graph("main", fns, tab)
  // THE REACHABLE SET: the entry, the function it calls, and the three
  // implementations the hierarchy allows.
  assert_true(g.reachable.contains("main"))
  assert_true(g.reachable.contains("foo"))
  assert_true(g.reachable.contains("Marker::foo"))
  assert_true(g.reachable.contains("A::foo"))
  assert_true(g.reachable.contains("B::foo"))
  assert_true(g.reachable.length() == 5)
  // AND THE EDGES.
  assert_true(g.edges.length() == 4)
  assert_true(g.edges.contains({ caller: "main", callee: "foo", }))
  assert_true(g.edges.contains({ caller: "foo", callee: "Marker::foo", }))
  assert_true(g.edges.contains({ caller: "foo", callee: "A::foo", }))
  assert_true(g.edges.contains({ caller: "foo", callee: "B::foo", }))
  // AND NOTHING WAS UNRESOLVED.
  assert_true(g.resolved == 2)
  assert_true(g.unresolved == 0)
}

///|
/// AN UNRESOLVED CALL SITE IS COUNTED, NOT DROPPED.
///
/// The receiver has no declared type, so the site resolves to nothing and the
/// graph says so. The count is the point: a graph that silently omitted the
/// site would look exactly like a graph in which the call was not there.
test "0574: BuildCallGraph -- an unresolved call site is counted" {
  let tab = @flow.collect_trait_table(cg_hierarchy_src())
  let fns = [
    cg_fn("main", [], [cg_stmt(cg_call("foo"))]),
    cg_fn("foo", [cg_param("x", "")], [cg_stmt(cg_method("x", "foo"))]),
  ]
  let g = @flow.build_call_graph("main", fns, tab)
  assert_true(g.unresolved == 1)
  assert_true(g.resolved == 1)
  // AND THE EDGE TO THE STATIC CALL IS STILL THERE.
  assert_true(g.edges.contains({ caller: "main", callee: "foo", }))
}

///|
/// THE ENTRY METHOD IS A NAME, AND A NAME WITH NO BODY IS AN EDGE AND NOT A
/// SOURCE.
///
/// MoonBit's method bodies are not in this tree's AST -- the parser reads
/// past `impl` declarations whole -- so a target like `A::foo` cannot be
/// expanded further. The graph carries the edge and stops, and the reachable
/// set says which names it reached.
test "0574: BuildCallGraph -- a method target is reached but not expanded" {
  let tab = @flow.collect_trait_table(cg_hierarchy_src())
  let fns = [
    cg_fn("main", [], [cg_stmt(cg_call("foo"))]),
    cg_fn("foo", [cg_param("x", "&Marker")], [cg_stmt(cg_method("x", "foo"))]),
  ]
  let g = @flow.build_call_graph("main", fns, tab)
  // `A::foo` IS reachable, and it is NOT a source of edges: there is no
  // function by that name, so there are no call sites under it.
  assert_true(g.reachable.contains("A::foo"))
  let mut out_of_a = 0
  let mut i = 0
  while i < g.edges.length() {
    if g.edges[i].caller == "A::foo" {
      out_of_a = out_of_a + 1
    }
    i = i + 1
  }
  assert_true(out_of_a == 0)
}

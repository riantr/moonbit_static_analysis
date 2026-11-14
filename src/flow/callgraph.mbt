// 0574: THE CALL GRAPH -- deck 7_Inter §2 -- and the TRAIT HIERARCHY it resolves
// against.
//
// THE DECK. `Interprocedural Analysis` (Tian Tan, Nanjing University, 2021) is
// 108 pages and its second section is "Call Graph Construction", p.15-72. It
// has two algorithms and one idea:
//
//   p.30-31  THE IDEA. "Require the class hierarchy information (inheritance
//            structure) of the whole program. Resolve a virtual call based on
//            the declared type of receiver variable of the call site."
//            CHA = Class Hierarchy Analysis (Dean, Grove, Chambers, ECOOP 1995).
//   p.33-39  `Resolve(call)` -- the three cases: STATIC, SPECIAL, VIRTUAL.
//   p.52-56  `BuildCallGraph(main)` -- the work list.
//
// THE ALGORITHMS, VERBATIM:
//
//     Resolve(call)
//       T = {}
//       m = method signature at call
//       if call is a static call then
//         T = { m }
//       if call is special call then
//         cm = class type of m
//         T = { Dispatch(cm, m) }
//       if call is a virtual call then
//         c = declared type of receiver variable at call
//         foreach c' that is a subclass of c or c itself do
//           add Dispatch(c', m) to T
//       return T
//
//     BuildCallGraph(main)
//       WL = [main], CG = {}, RM = {}
//       while WL is not empty do
//         remove m from WL
//         if m not in RM then
//           add m to RM
//           foreach call site cs in m do
//             T = Resolve(cs)
//             foreach target method m' in T do
//               add cs -> m' to CG
//               add m' to WL
//       return CG
//
// WHY MOONBIT NEEDS A TRANSLATION AND NOT A COPY.
//
// MoonBit HAS NO CLASS INHERITANCE. It has TRAITS: a trait declares methods,
// and a type implements a trait with `impl Trait for Type` or with
// `derive(Trait)`. A value whose DECLARED TYPE is a trait dispatches
// dynamically to whichever implementation it holds -- which is exactly the
// situation CHA answers, and exactly the situation `icfg.mbt` had to decline:
// its header names the boundary, "METHOD CALLS. `x.foo()` is `EMethodCall`,
// whose target depends on the receiver's type ... a method call is NOT a call
// site here."
//
// So THE CLASS HIERARCHY IS THE TRAIT HIERARCHY, and the three cases map:
//
//   static   `f(x)`              -> T = { "f" }          (the deck's T = { m })
//   special  `Type::m(x)`        -> T = { "Type::m" }    (the deck's Dispatch(cm, m))
//   virtual  `recv.m(x)`         -> the receiver's DECLARED TYPE, and every
//                                    type that implements it, plus the trait
//                                    itself (the deck's "c' that is a subclass
//                                    of c or c itself")
//
// THE TARGET OF A VIRTUAL CALL IS A NAME -- `X::m` -- and the name is what the
// call graph carries. A method's BODY is not in this tree's AST (the parser
// reads past `impl`, `trait`, `struct` and `enum` declarations whole), so the
// graph's edges name the implementations and the graph STOPS there: the calls
// INSIDE an implementation are not visible. That boundary is measured and
// recorded, not assumed -- see the chapter.
//
// WHAT THE RECEIVER'S DECLARED TYPE IS, AND WHERE IT COMES FROM.
//
// The deck needs "the declared type of receiver variable at call". This tree
// has exactly one source for a local's declared type: the ANNOTATION in the
// AST -- `SLet(name, ann, init)`'s second field and `Param.tyann`. The type
// lens publishes only the MODULE frame (`TypeResult.syms` is built from
// `inf.frames[0]`), so a function's LOCAL types are not published anywhere, and
// the annotation is the only thing that can answer the question. An
// UNANNOTATED receiver has no declared type, and its call site is COUNTED as
// unresolved rather than connected to a guess.
//
// THE DECLARED TYPES ARE FLAT, and that is the deck's own approximation: CHA
// "ignore[s] data- and control-flow information" (p.47-48), so a name bound
// twice in one body keeps the LAST annotation, and no shadowing is modelled.
//
// THE TRAIT HIERARCHY IS READ FROM THE SOURCE, and the reader is HERE rather
// than in the parser because it answers ONE question -- "which type implements
// which trait" -- that nothing else in this tree answers, and because it lives
// next to the only thing that consumes it. It reads HEADERS, not bodies: an
// `impl[T] Trait for Type` names its trait and its type before any brace, and
// a trait's own methods are one level inside its braces, so the scan is a
// token scan with a brace-depth counter and never has to find a matching close
// brace to know which declaration it is inside.
//
// IT IS A PER-FILE TABLE, and the caller merges the files' tables the same way
// the package's name tables are merged. A trait declared in ANOTHER file is
// therefore not in the table, and a call through it is counted as unresolved.

///|
/// The TRAIT HIERARCHY of one file: which traits exist, which types implement
/// them, and what methods each trait declares.
pub(all) struct TraitTable {
  /// The traits this file DECLARES.
  traits : Map[String, Bool]
  /// The types this file declares -- `struct`, `enum` and `trait` alike.
  types : Map[String, Bool]
  /// trait -> the types that implement it.
  impls : Map[String, Array[String]]
  /// trait -> the methods the trait itself declares.
  methods : Map[String, Array[String]]
}

///|
/// The empty table, which is also the table of a file with no traits.
pub fn TraitTable::empty() -> TraitTable {
  { traits: Map([]), types: Map([]), impls: Map([]), methods: Map([]), }
}

///|
/// Is this name a TRAIT for the purposes of a dispatch?
///
/// A trait this file declares is one. A trait this file only IMPLEMENTS is
/// one too: `derive(Eq)` says the file's type implements `Eq`, and `Eq` is a
/// trait whether or not it is declared here.
pub fn TraitTable::is_trait(self : TraitTable, name : String) -> Bool {
  self.traits.contains(name) || self.impls.contains(name)
}

///|
/// Does this trait declare this method?
pub fn TraitTable::has_method(
  self : TraitTable,
  trait_name : String,
  m : String,
) -> Bool {
  match self.methods.get(trait_name) {
    Some(ms) => ms.contains(m)
    None => false
  }
}

///|
/// The types that implement this trait.
pub fn TraitTable::implementors(
  self : TraitTable,
  trait_name : String,
) -> Array[String] {
  match self.impls.get(trait_name) {
    Some(xs) => xs
    None => []
  }
}

///|
/// Merge another file's table into this one.
///
/// THE MERGE IS THE SAME SHAPE AS THE NAME TABLES' (`sa/main.mbt` builds the
/// package's sibling table out of the files' tables), and it is what makes a
/// hierarchy a PROGRAM-WIDE fact rather than a per-file one. An implementor
/// already present is not added twice.
///
/// THE TABLE IS A VALUE AND THE MAPS INSIDE IT ARE REFERENCES, so a merge
/// that adds to `self.impls` is visible through every copy of the table: the
/// maps are shared, not copied.
pub fn TraitTable::merge(self : TraitTable, other : TraitTable) -> TraitTable {
  for t, _ in other.traits {
    self.traits.set(t, true)
  }
  for t, _ in other.types {
    self.types.set(t, true)
  }
  for t, xs in other.impls {
    match self.impls.get(t) {
      Some(mine) => {
        let mut i = 0
        while i < xs.length() {
          if !mine.contains(xs[i]) {
            mine.push(xs[i])
          }
          i = i + 1
        }
      }
      None => self.impls.set(t, xs)
    }
  }
  for t, ms in other.methods {
    match self.methods.get(t) {
      Some(mine) => {
        let mut i = 0
        while i < ms.length() {
          if !mine.contains(ms[i]) {
            mine.push(ms[i])
          }
          i = i + 1
        }
      }
      None => self.methods.set(t, ms)
    }
  }
  self
}

///|
/// The name right after a keyword, if there is one.
fn cg_name_after(toks : Array[@lexer.Tok], i : Int32) -> String? {
  if i >= toks.length() {
    return None
  }
  match toks[i] {
    @lexer.TName(n) => Some(n)
    _ => None
  }
}

///|
/// The `Trait` and the `Type` of an `impl` header.
///
/// THE HEADER IS ENOUGH, and this is why the reader does not have to match
/// braces to find a declaration's end: `impl[T] Trait for Type` names both
/// before the first brace, and the type-parameter list is the only thing
/// between the keyword and the trait's name.
///
/// The forms that are NOT `impl ... for ...` -- an `impl` with no `for`, a
/// name where the trait's name should be -- answer `None`, and the caller
/// counts them as unreadable rather than guessing.
fn cg_impl_header(toks : Array[@lexer.Tok], i : Int32) -> (String, String)? {
  let mut j = i
  // an optional type-parameter list: `impl[T] Trait for Type`
  if j < toks.length() {
    match toks[j] {
      @lexer.TLBracket => {
        let mut d = 0
        let mut k = j
        let mut done = false
        while k < toks.length() && !done {
          match toks[k] {
            @lexer.TLBracket => d = d + 1
            @lexer.TRBracket => {
              d = d - 1
              if d == 0 {
                done = true
              }
            }
            _ => ()
          }
          k = k + 1
        }
        j = k
      }
      _ => ()
    }
  }
  // the trait's name
  let mut trait_name = ""
  match cg_name_after(toks, j) {
    Some(n) => {
      trait_name = n
      j = j + 1
    }
    None => return None
  }
  // the `for`
  match cg_name_after(toks, j) {
    Some(n) => {
      if n != "for" {
        return None
      }
      j = j + 1
    }
    None => return None
  }
  // the type
  match cg_name_after(toks, j) {
    Some(n) => Some((trait_name, n))
    None => None
  }
}

///|
/// The traits in a `derive(...)` list.
fn cg_derive_list(toks : Array[@lexer.Tok], i : Int32) -> Array[String] {
  let out : Array[String] = []
  let mut j = i
  if j < toks.length() {
    match toks[j] {
      @lexer.TLParen => j = j + 1
      _ => return out
    }
  }
  let mut go = true
  while j < toks.length() && go {
    match toks[j] {
      @lexer.TRParen => go = false
      @lexer.TComma => ()
      @lexer.TName(n) => out.push(n)
      _ => ()
    }
    j = j + 1
  }
  out
}

///|
/// Record that `ty` implements `tr`.
///
/// THE TABLE IS PASSED BY VALUE AND THE MAPS INSIDE IT ARE REFERENCES, so
/// the record lands in the caller's table: `Map.set` mutates the map in
/// place, and the array inside it is shared with the caller too.
fn cg_add_impl(tab : TraitTable, tr : String, ty : String) -> Unit {
  match tab.impls.get(tr) {
    Some(xs) => if !xs.contains(ty) { xs.push(ty) }
    None => {
      let xs : Array[String] = [ty]
      tab.impls.set(tr, xs)
    }
  }
}

///|
/// Record that `tr` declares the method `m`.
fn cg_add_method(tab : TraitTable, tr : String, m : String) -> Unit {
  match tab.methods.get(tr) {
    Some(ms) => if !ms.contains(m) { ms.push(m) }
    None => {
      let ms : Array[String] = [m]
      tab.methods.set(tr, ms)
    }
  }
}

///|
/// Read the TRAIT HIERARCHY of one source file.
///
/// THE SCAN, and what each level of it means:
///
///   * at depth 0, `trait T` declares a trait; `struct T` and `enum T`
///     declare a type; `impl ... for T` says a type implements a trait; and a
///     `derive(A, B)` says the LAST type declared implements A and B -- which
///     is where MoonBit puts it, right after the type's own declaration;
///   * at depth 1 inside a TRAIT, `fn m` declares one of the trait's methods;
///   * at depth 1 inside an `impl`, the methods belong to the IMPLEMENTED
///     TYPE and not to the trait -- `impl Eq for Locale` gives `Locale::equal`,
///     not `Eq::equal` -- so they are not the trait's methods and are not
///     recorded as such. The call graph wants the IMPLEMENTATION, and it
///     carries that as the target's NAME (`Locale::equal`), so the method list
///     of an impl is not needed to name the target.
///
/// THE METHOD LIST OF A TRAIT IS WHAT MAKES THE DEFAULT-METHOD TARGET
/// POSSIBLE: the deck's "c' that is a subclass of c or c ITSELF" means the
/// trait itself is a target, and a trait's own method is the one that target
/// dispatches to.
pub fn collect_trait_table(src : String) -> TraitTable {
  let (toks, _, _) = @lexer.lex(src)
  let tab = TraitTable::empty()
  let mut depth = 0
  let mut cur_trait = ""
  let mut last_type = ""
  let mut i = 0
  while i < toks.length() {
    match toks[i] {
      @lexer.TLBrace => depth = depth + 1
      @lexer.TRBrace => {
        depth = depth - 1
        if depth == 0 {
          cur_trait = ""
        }
      }
      @lexer.TName(n) =>
        if depth == 0 {
          if n == "trait" {
            match cg_name_after(toks, i + 1) {
              Some(t) => {
                tab.traits.set(t, true)
                tab.types.set(t, true)
                cur_trait = t
              }
              None => ()
            }
            i = i + 1
          } else if n == "struct" || n == "enum" {
            match cg_name_after(toks, i + 1) {
              Some(t) => {
                tab.types.set(t, true)
                last_type = t
              }
              None => ()
            }
            i = i + 1
          } else if n == "impl" {
            match cg_impl_header(toks, i + 1) {
              Some((tr, ty)) => {
                cg_add_impl(tab, tr, ty)
                tab.types.set(ty, true)
              }
              None => ()
            }
          } else if n == "derive" {
            if last_type != "" {
              let ts = cg_derive_list(toks, i + 1)
              let mut k = 0
              while k < ts.length() {
                cg_add_impl(tab, ts[k], last_type)
                k = k + 1
              }
            }
          }
        } else if depth == 1 && cur_trait != "" && n == "fn" {
          match cg_name_after(toks, i + 1) {
            Some(m) => cg_add_method(tab, cur_trait, m)
            None => ()
          }
          i = i + 1
        }
      _ => ()
    }
    i = i + 1
  }
  tab
}

///|
/// One function, as the call graph needs it.
pub(all) struct CgFn {
  name : String
  params : Array[@ast.Param]
  body : Array[@ast.Stmt]
}

///|
/// The KIND of a call site -- the deck's three cases.
#derive(Eq)
pub(all) enum CallKind {
  /// `f(x)` -- a call to a named function.
  Static
  /// `Type::m(x)` -- the type is named IN the call, so the target is known.
  Special
  /// `recv.m(x)` -- the target depends on the receiver's type.
  Virtual
}

///|
/// A call site, as far as the AST can express it.
#derive(Eq)
pub(all) struct CgCall {
  kind : CallKind
  /// The callee's name: `f`, `Type::m`, or the method's name `m`.
  name : String
  /// The receiver's BASE name, for a virtual call whose receiver is a plain
  /// name. Empty when the receiver is an expression, which has no declared
  /// type this tree can read.
  receiver : String
  /// The ARGUMENTS of the call, in order.
  ///
  /// 0575: the context-sensitive pointer analysis needs them -- the deck's call
  /// rule moves the arguments to the callee's parameters -- and a call site
  /// that cannot say what it passes cannot be propagated.
  args : Array[@ast.Expr]
  /// The name the call's RESULT is bound to; empty when the result is
  /// discarded.
  ///
  /// 0575: the same rule moves the callee's result to this name.
  lhs : String
}

///|
/// One edge of the call graph: a caller and a callee.
#derive(Eq)
pub(all) struct CgEdge {
  caller : String
  callee : String
}

///|
/// The call sites of a module's TOP-LEVEL functions.
///
/// THE AST HAS NO METHODS, and this is the whole reason the call graph stops
/// where it does: the parser reads past `impl`, `trait`, `struct` and `enum`
/// declarations whole, so a method's body is not in the tree and the calls
/// inside it are not visible. What IS in the tree is the set of top-level
/// functions, and the graph's edges out of those are real.
pub fn cg_fns_of(decls : Array[@ast.Stmt]) -> Array[CgFn] {
  let out : Array[CgFn] = []
  let mut i = 0
  while i < decls.length() {
    match decls[i].kind {
      @ast.SFunc(name, params, _, body, _) => out.push({ name, params, body, })
      _ => ()
    }
    i = i + 1
  }
  out
}

///|
/// The DECLARED types of the names a function binds: its parameters and its
/// `let`s.
///
/// THE ANNOTATION IS THE ONLY SOURCE, and this is measured rather than
/// assumed: `TypeResult.syms` is built from the type lens's MODULE frame
/// (`inf.frames[0]`), so a function's local types are not published anywhere,
/// and `SLet`'s second field and `Param.tyann` are what is left.
pub fn declared_types(f : CgFn) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  let mut i = 0
  while i < f.params.length() {
    out.set(f.params[i].name, f.params[i].tyann)
    i = i + 1
  }
  cg_collect_lets(f.body, out)
  out
}

///|
/// Collect the `let` annotations of a statement list, at every nesting level.
fn cg_collect_lets(stmts : Array[@ast.Stmt], out : Map[String, String]) -> Unit {
  let mut i = 0
  while i < stmts.length() {
    cg_collect_stmt(stmts[i], out)
    i = i + 1
  }
}

///|
/// Collect the `let` annotations of ONE statement and of the bodies it holds.
fn cg_collect_stmt(s : @ast.Stmt, out : Map[String, String]) -> Unit {
  match s.kind {
    @ast.SLet(n, ann, _) => out.set(n, ann)
    @ast.SIf(_, then_body, elifs, else_body) => {
      cg_collect_lets(then_body, out)
      let mut j = 0
      while j < elifs.length() {
        cg_collect_lets(elifs[j].body, out)
        j = j + 1
      }
      match else_body {
        Some(b) => cg_collect_lets(b, out)
        None => ()
      }
    }
    @ast.SWhile(_, body) => cg_collect_lets(body, out)
    @ast.SFor(_, _, _, body) => cg_collect_lets(body, out)
    @ast.SBlock(inner) => cg_collect_lets(inner, out)
    @ast.SNoBreak(inner, body) => {
      cg_collect_stmt(inner, out)
      cg_collect_lets(body, out)
    }
    @ast.SForUpdate(body) => cg_collect_lets(body, out)
    _ => ()
  }
}

///|
/// The call sites of one function, in the order the CFG numbers them.
pub fn call_sites_of(f : CgFn) -> Array[CgCall] {
  let g = cfg_of(f.body)
  let out : Array[CgCall] = []
  let mut v = 0
  while v < g.kinds.length() {
    match cg_node_call(g.kinds[v]) {
      Some(c) => out.push(c)
      None => ()
    }
    v = v + 1
  }
  out
}

///|
/// The call a node's payload carries, if it carries one.
///
/// ONLY A PAYLOAD THAT IS ITSELF A CALL COUNTS, the same rule `icfg.mbt`'s
/// `call_shape` uses and for the same reason: the deck's node and edge split
/// needs a node that IS the call.
///
/// THE LEFT-HAND SIDE IS PART OF THE CALL SITE, because the deck's call rule
/// (11-12 p.67-71) has two halves: the arguments go to the parameters, and the
/// result comes back to a NAME. A call whose result is discarded has no such
/// name, and its `lhs` is empty.
pub fn cg_node_call(kind : NodeKind) -> CgCall? {
  match kind {
    Assign(x, e) => cg_expr_call(e, x)
    Store(x, e) => cg_expr_call(e, x)
    Eval(e) => cg_expr_call(e, "")
    _ => None
  }
}

///|
/// The call an expression carries, if it is one, bound to the name that
/// receives its result.
fn cg_expr_call(e : @ast.Expr, lhs : String) -> CgCall? {
  match e.kind {
    @ast.ECall(name, args, _) =>
      if name.contains("::") {
        Some({ kind: Special, name, receiver: "", args, lhs, })
      } else {
        Some({ kind: Static, name, receiver: "", args, lhs, })
      }
    @ast.EMethodCall(recv, name, args, _) => {
      let r = match recv.kind {
        @ast.EName(n) => n
        _ => ""
      }
      Some({ kind: Virtual, name, receiver: r, args, lhs, })
    }
    _ => None
  }
}

///|
/// The TYPE NAME of an annotation: `&Writer` is `Writer`, `Array[Int]` is
/// `Array`.
///
/// A TRAIT OBJECT IS WRITTEN `&T` -- `moon check` answers 4100 "The type
/// Node is not a trait" for `&Node` on a struct, so the `&` means the
/// receiver's type is the TRAIT and not a type that implements it. That is
/// exactly the case CHA answers, so the `&` is dropped rather than kept.
fn base_type_name(ann : String) -> String {
  let buf = StringBuilder()
  let mut state = 0
  for c in ann {
    if state == 0 {
      if c == '&' {
        state = 1
      } else {
        state = 2
        buf.write_char(c)
      }
    } else if state == 1 {
      state = 2
      buf.write_char(c)
    } else if c == '[' {
      break
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// `Resolve(call)` -- the deck's p.33-39, in MoonBit's terms.
///
/// THE THREE CASES, and what each one answers:
///
///   * a STATIC call names its callee, so the target is that name;
///   * a SPECIAL call names its TYPE as well -- the parser folds `::` into the
///     name, so `Type::m(x)` arrives as the name `Type::m` -- and the target
///     is that name, which is the deck's `Dispatch(cm, m)` already spelled;
///   * a VIRTUAL call is resolved through the receiver's DECLARED TYPE: if
///     that type is a TRAIT, the targets are the trait's own method plus one
///     for every type that implements it -- the deck's "c' that is a subclass
///     of c or c itself"; if it is a CONCRETE type, the target is that type's
///     method; and if the receiver has no declared type, or its type is
///     neither a trait nor a type this table knows, the target set is EMPTY.
///
/// AN EMPTY TARGET SET IS NOT AN ERROR, it is a MEASUREMENT: the caller
/// counts it as an unresolved call site, so the graph says how much of the
/// program it is entitled to a claim about. That is the same contract
/// `icfg.mbt`'s `unresolved` carries.
pub fn resolve_call(
  call : CgCall,
  declared : Map[String, String],
  tab : TraitTable,
) -> Array[String] {
  let out : Array[String] = []
  match call.kind {
    Static => out.push(call.name)
    Special => out.push(call.name)
    Virtual =>
      if call.receiver != "" {
        match declared.get(call.receiver) {
          None => ()
          Some(ann) =>
            if ann != "" {
              let t = base_type_name(ann)
              if tab.is_trait(t) {
                // THE TRAIT ITSELF, which is the deck's "or c itself".
                if tab.has_method(t, call.name) {
                  out.push(t + "::" + call.name)
                }
                // AND EVERY TYPE THAT IMPLEMENTS IT.
                let xs = tab.implementors(t)
                let mut i = 0
                while i < xs.length() {
                  out.push(xs[i] + "::" + call.name)
                  i = i + 1
                }
              } else if tab.types.contains(t) {
                out.push(t + "::" + call.name)
              }
            }
        }
      }
  }
  out
}

///|
/// The CALL GRAPH the deck's p.52-56 builds.
pub(all) struct CallGraph {
  /// The edges: one per resolved call site and target.
  edges : Array[CgEdge]
  /// The reachable names, in the order the work list reached them.
  reachable : Array[String]
  /// The call sites that resolved to at least one target.
  resolved : Int32
  /// The call sites that resolved to NOTHING.
  unresolved : Int32
}

///|
/// `BuildCallGraph(main)` -- the deck's p.52-56.
///
/// THE WORK LIST IS THE DECK'S: `WL` starts with the entry method, a method
/// is added to `RM` the first time it is taken off the list, and every target
/// a call site resolves to is put back on the list -- so a method is
/// processed once, and the graph grows until nothing new is discovered.
///
/// THE ENTRY IS A NAME, and a name with no body is a name the graph carries
/// but cannot expand: MoonBit's method bodies are not in this tree's AST (the
/// parser reads past `impl` declarations), so a target like `A::foo` is an
/// edge and not a source of further edges. That is the boundary, and it is
/// counted rather than hidden.
pub fn build_call_graph(
  main : String,
  fns : Array[CgFn],
  tab : TraitTable,
) -> CallGraph {
  let by_name : Map[String, CgFn] = Map([])
  let mut i = 0
  while i < fns.length() {
    if !by_name.contains(fns[i].name) {
      by_name.set(fns[i].name, fns[i])
    }
    i = i + 1
  }
  let edges : Array[CgEdge] = []
  let reachable : Array[String] = []
  let rm : Map[String, Bool] = Map([])
  let mut resolved = 0
  let mut unresolved = 0
  // WL = [main]
  let wl : Array[String] = [main]
  let mut head = 0
  while head < wl.length() {
    let m = wl[head]
    head = head + 1
    if !rm.contains(m) {
      rm.set(m, true)
      reachable.push(m)
      match by_name.get(m) {
        None => ()
        Some(f) => {
          let sites = call_sites_of(f)
          let declared = declared_types(f)
          let mut s = 0
          while s < sites.length() {
            let targets = resolve_call(sites[s], declared, tab)
            if targets.length() == 0 {
              unresolved = unresolved + 1
            } else {
              resolved = resolved + 1
              let mut k = 0
              while k < targets.length() {
                edges.push({ caller: m, callee: targets[k], })
                wl.push(targets[k])
                k = k + 1
              }
            }
            s = s + 1
          }
        }
      }
    }
  }
  { edges, reachable, resolved, unresolved, }
}

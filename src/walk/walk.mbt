// walk: lens 1 — the structural lens. Binding accounting on the
// mini language: two passes per scope (findLocals then
// collectUsage), assignment forms bind, complex targets peel to the base
// name, `for` variables bind, and constant folding prunes dead branches so
// the whole pipeline never sees them.
//
// The binding tables this lens produces ARE the type lens's declaration
// source (assembly point 1): the type checker never rediscovers bindings.

///|
/// One declared binding: from `let`, from a bare assignment, from a `for`
/// variable, or from a parameter (param = true).
pub(all) struct Binding {
  name : String
  tyann : String
  param : Bool
  decl_span : @core.Span
} derive(Eq)

///|
pub(all) struct FnInfo {
  name : String
  params : Array[@ast.Param]
  retann : String
  body : Array[@ast.Stmt]
  span : @core.Span
} derive(Eq)

///|
pub(all) struct WalkResult {
  fns : Array[FnInfo]
  /// top-level `let`/assignments, in source order
  module_bindings : Array[Binding]
  /// per function: params + all body bindings (params first)
  fn_bindings : Map[String, Array[Binding]]
  /// structural findings (lens = LStructural)
  findings : Array[@report.Report]
}

///|
/// Constants representable by the folder: the foldFuns subset.
pub(all) enum Const {
  CInt(Int)
  CBool(Bool)
} derive(Eq)

///|
/// Constant folding. Not an
/// independent pass: its only consumers are the condition checks of the
/// walkers — a literal-true/false condition makes the dead branch invisible
/// to every lens downstream.
pub fn const_eval(e : @ast.Expr) -> Const? {
  match e.kind {
    EInt(i) => Some(CInt(i))
    EBool(b) => Some(CBool(b))
    EUnary(op, a) =>
      match (op, const_eval(a)) {
        (UNeg, Some(CInt(i))) => Some(CInt(-i))
        (UNot, Some(CBool(b))) => Some(CBool(!b))
        _ => None
      }
    EBin(op, a, b) =>
      match (const_eval(a), const_eval(b)) {
        (Some(CInt(i)), Some(CInt(j))) =>
          match op {
            OpAdd => Some(CInt(i + j))
            OpSub => Some(CInt(i - j))
            OpMul => Some(CInt(i * j))
            OpMod => Some(CInt(i % j))
            // `/` widens to Float at runtime — outside the int folder
            OpDiv => None
            OpLt => Some(CBool(i < j))
            OpLe => Some(CBool(i <= j))
            OpGt => Some(CBool(i > j))
            OpGe => Some(CBool(i >= j))
            OpEq => Some(CBool(i == j))
            OpNe => Some(CBool(i != j))
            _ => None
          }
        (Some(CBool(i)), Some(CBool(j))) =>
          match op {
            OpAnd => Some(CBool(i && j))
            OpOr => Some(CBool(i || j))
            OpEq => Some(CBool(i == j))
            OpNe => Some(CBool(i != j))
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
priv struct Entry {
  param : Bool
  mut assigns : Int
  mut varuses : Int
  decl_span : @core.Span
}

///|
priv struct Walker {
  /// frame 0 = module frame, frame 1.. = function frames
  frames : Array[Map[String, Entry]]
  orders : Array[Array[String]]
  builtins : Map[String, Bool]
  /// names declared in `.mbti` files of OTHER modules/packages; a hit
  /// suppresses the "no visible binding" finding because the binding lives
  /// outside the file under analysis but IS a real binding
  extern_iface : @core.IfaceSymTab
  findings : Array[@report.Report]
  vst : Array[@core.Frame]
}

///|
fn new_walker(extern_iface : @core.IfaceSymTab) -> Walker {
  Walker::{
    frames: [Map([])],
    orders: [[]],
    builtins: builtin_table(),
    extern_iface,
    findings: [],
    vst: [],
  }
}

///|
fn builtin_table() -> Map[String, Bool] {
  let m : Map[String, Bool] = Map([])
  m.set("print", true)
  m.set("len", true)
  m.set("abs", true)
  m
}

///|
fn Walker::push_frame(self : Walker) -> Unit {
  self.frames.push(Map([]))
  self.orders.push([])
}

///|
fn Walker::pop_frame(self : Walker) -> Unit {
  let _ = self.frames.pop()
  let _ = self.orders.pop()
}

///|
fn Walker::bind(self : Walker, b : Binding) -> Unit {
  let fi = self.frames.length() - 1
  let frame = self.frames[fi]
  if !frame.contains(b.name) {
    frame.set(b.name, {
      param: b.param,
      assigns: 0,
      varuses: 0,
      decl_span: b.decl_span,
    })
    self.orders[fi].push(b.name)
  }
}

///|
fn Walker::resolve(self : Walker, name : String, sp : @core.Span) -> Unit {
  // innermost -> outermost
  let mut i = self.frames.length() - 1
  let mut hit = false
  while i >= 0 && !hit {
    match self.frames[i].get(name) {
      Some(e) => {
        e.varuses += 1
        hit = true
      }
      None => i -= 1
    }
  }
  if !hit &&
    !self.builtins.contains(name) &&
    !self.extern_iface.has_type(name) &&
    !self.extern_iface.has_value(name) {
    self.findings.push(@report.Report::{
      family: @core.FUndefinedName,
      lenses: [@core.LStructural],
      message: "no visible binding for '\{name}'",
      span: sp,
      vst: @core.snapshot_vst(self.vst),
    })
  }
}

///|
fn Walker::assign_to(self : Walker, name : String) -> Unit {
  let fi = self.frames.length() - 1
  match self.frames[fi].get(name) {
    Some(e) => e.assigns += 1
    None => ()
  }
}

///|
/// Audit a function frame on exit (usage accounting for locals).
fn Walker::audit_frame(self : Walker) -> Unit {
  let fi = self.frames.length() - 1
  for n in self.orders[fi] {
    match self.frames[fi].get(n) {
      Some(e) =>
        if e.param {
          if e.assigns > 0 {
            self.findings.push(@report.Report::{
              family: @core.FParamChanged,
              lenses: [@core.LStructural],
              message: "parameter '\{n}' changed by assignment",
              span: e.decl_span,
              vst: @core.snapshot_vst(self.vst),
            })
          }
          if e.varuses == 0 {
            self.findings.push(@report.Report::{
              family: @core.FUnusedParam,
              lenses: [@core.LStructural],
              message: "parameter '\{n}' may not be used",
              span: e.decl_span,
              vst: @core.snapshot_vst(self.vst),
            })
          }
        } else if e.varuses == 0 {
          self.findings.push(@report.Report::{
            family: @core.FUnusedLocal,
            lenses: [@core.LStructural],
            message: "local variable '\{n}' assigned but may not be used",
            span: e.decl_span,
            vst: @core.snapshot_vst(self.vst),
          })
        }
      None => ()
    }
  }
}

///|
fn Walker::walk_expr(self : Walker, e : @ast.Expr) -> Unit {
  match e.kind {
    EName(n) => self.resolve(n, e.span)
    EList(elems) =>
      for x in elems {
        self.walk_expr(x)
      }
    EUnary(_, a) => self.walk_expr(a)
    EBin(_, a, b) => {
      self.walk_expr(a)
      self.walk_expr(b)
    }
    ECall(name, args) => {
      self.resolve(name, e.span)
      for a in args {
        self.walk_expr(a)
      }
    }
    EField(base, _) =>
      // the `$` rule: walk the object only — the
      // field name is a column/tag, not a variable
      self.walk_expr(base)
    EIndex(base, idx) => {
      // the `[[` rule: the index IS an evaluated expression
      self.walk_expr(base)
      self.walk_expr(idx)
    }
    EComp(vars, sources, body) => {
      // The loop variables are bound for the whole comprehension, including
      // its own iterables: a later generator's iterable may read an earlier
      // one (`[ for x in a, y in pairs_of(x) => ... ]`). The over-approximation
      // this allows — a variable also visible in an EARLIER iterable — fails
      // toward silence on a name that should have been reported, which is the
      // safe direction for a suppression-shaped decision.
      self.push_frame()
      for v in vars {
        self.bind({ name: v, tyann: "", param: false, decl_span: e.span, })
      }
      for s in sources {
        self.walk_expr(s)
      }
      self.walk_expr(body)
      self.pop_frame()
    }
    EInt(_) | EFloat(_) | EBool(_) | EStr(_) => ()
  }
}

///|
fn Walker::walk_target(self : Walker, target : @ast.Expr) -> Unit {
  match target.kind {
    EName(n) => self.assign_to(n)
    // A field or index write is peeled to the base for ASSIGNMENT tracking,
    // but the base is still READ to reach it: `self.inner = 1` has to
    // evaluate `self` to find where the field lives. Counting only the
    // assignment made a base that is never read anywhere else look unused,
    // and the analyzer then said two things that cannot both be true about
    // the same parameter —
    //     parameter 'self' changed by assignment (ParamChanged)
    //     parameter 'self' may not be used (UnusedParam)
    // Measured on moonbitlang/async: `semaphore.mbt` reports that pair for
    // all three of its `with fn set_index(self, value)` style impls. The
    // same base written where the right-hand side also reads it
    // (`self.inner = self.other + 1`) already produced only the
    // ParamChanged, which is the intended shape.
    EField(base, _) => {
      match base.assigned_base() {
        Some(b) => self.assign_to(b)
        None => ()
      }
      self.walk_expr(base)
    }
    EIndex(base, idx) => {
      match base.assigned_base() {
        Some(b) => self.assign_to(b)
        None => ()
      }
      self.walk_expr(base)
      self.walk_expr(idx)
    }
    _ => ()
  }
}

///|
fn Walker::walk_stmt(self : Walker, s : @ast.Stmt) -> Unit {
  match s.kind {
    SExpr(e) => self.walk_expr(e)
    SLet(_, _, init) => self.walk_expr(init)
    SAssign(target, rhs) => {
      self.walk_target(target)
      self.walk_expr(rhs)
    }
    SIf(cond, then, elseifs, els) =>
      // constant folding prunes dead branches
      match const_eval(cond) {
        Some(CInt(_)) => self.walk_conditional(cond, then, elseifs, els)
        Some(CBool(true)) =>
          for st in then {
            self.walk_stmt(st)
          }
        Some(CBool(false)) =>
          match self.walk_else(elseifs, els) {
            Some(live) =>
              for st in live {
                self.walk_stmt(st)
              }
            None => ()
          }
        None => self.walk_conditional(cond, then, elseifs, els)
      }
    SWhile(cond, body) => {
      self.walk_expr(cond)
      for st in body {
        self.walk_stmt(st)
      }
    }
    SFor(_, _, seq, body) => {
      self.walk_expr(seq)
      for st in body {
        self.walk_stmt(st)
      }
    }
    SReturn(e) =>
      match e {
        Some(x) => self.walk_expr(x)
        None => ()
      }
    SBreak | SContinue => ()
    SFunc(_, _, _, _, _) => ()
  }
}

///|
fn Walker::walk_else(
  self : Walker,
  elseifs : Array[@ast.ElseIf],
  els : Array[@ast.Stmt]?,
) -> Array[@ast.Stmt]? {
  match (elseifs.get(0), els) {
    (Some(ei), _) =>
      match const_eval(ei.cond) {
        Some(CInt(_)) => Some(ei.body)
        Some(CBool(true)) => Some(ei.body)
        Some(CBool(false)) => self.walk_else(as_array(elseifs, 1), els)
        None => Some(ei.body)
      }
    (None, Some(e)) => Some(e)
    (None, None) => None
  }
}

///|
fn as_array(a : Array[@ast.ElseIf], from : Int) -> Array[@ast.ElseIf] {
  let out : Array[@ast.ElseIf] = []
  let mut i = from
  while i < a.length() {
    out.push(a[i])
    i += 1
  }
  out
}

///|
fn Walker::walk_conditional(
  self : Walker,
  cond : @ast.Expr,
  then : Array[@ast.Stmt],
  elseifs : Array[@ast.ElseIf],
  els : Array[@ast.Stmt]?,
) -> Unit {
  self.walk_expr(cond)
  for st in then {
    self.walk_stmt(st)
  }
  for ei in elseifs {
    self.walk_expr(ei.cond)
    for st in ei.body {
      self.walk_stmt(st)
    }
  }
  match els {
    Some(e) =>
      for st in e {
        self.walk_stmt(st)
      }
    None => ()
  }
}

///|
/// Pass 1 for one function: params first, then every binding in the body
/// (findLocals): `let`, bare assignments peeled to the base name, `for`
/// variables. Dead branches are still collected (the binding analysis is
/// not flow-sensitive).
fn collect_fn_bindings(f : FnInfo) -> Array[Binding] {
  let out : Array[Binding] = []
  fn add(bs : Array[Binding], b : Binding) -> Unit {
    if !bs.contains(b) {
      bs.push(b)
    }
  }

  for p in f.params {
    add(out, { name: p.name, tyann: p.tyann, param: true, decl_span: p.span, })
  }
  fn scan(bs : Array[Binding], stmts : Array[@ast.Stmt]) -> Unit {
    for s in stmts {
      match s.kind {
        SLet(n, ann, _) =>
          add(bs, { name: n, tyann: ann, param: false, decl_span: s.span, })
        SAssign(target, _) =>
          match target.assigned_base() {
            Some(b) =>
              add(bs, {
                name: b,
                tyann: "",
                param: false,
                decl_span: target.span,
              })
            None => ()
          }
        SFor(v, vsp, _, body) => {
          add(bs, { name: v, tyann: "", param: false, decl_span: vsp, })
          scan(bs, body)
        }
        SIf(_, then, elseifs, els) => {
          scan(bs, then)
          for ei in elseifs {
            scan(bs, ei.body)
          }
          match els {
            Some(e) => scan(bs, e)
            None => ()
          }
        }
        SWhile(_, body) => scan(bs, body)
        _ => ()
      }
    }
  }

  scan(out, f.body)
  out
}

///|
/// Structural walk over the whole module. Produces the binding tables the
/// type lens consumes plus the structural findings.
///
/// `extern_iface` is the cross-file symbol table built from `.mbti` files
/// outside the file under analysis (other modules in the same package, or
/// dependencies). A name that appears there is treated as a valid binding,
/// so the "no visible binding" finding is suppressed for it. Pass an empty
/// table to recover the single-file behavior.
pub fn walk_module(
  m : @ast.Module,
  file : String,
  extern_iface : @core.IfaceSymTab,
) -> WalkResult {
  let w = new_walker(extern_iface)
  let fns : Array[FnInfo] = []
  let module_bindings : Array[Binding] = []
  let fn_bindings : Map[String, Array[Binding]] = Map([])
  // pass 1: module bindings + function registration (forward references OK)
  for s in m.body {
    match s.kind {
      SLet(n, ann, _) =>
        if !module_bindings.contains(name_binding(n)) {
          module_bindings.push({
            name: n,
            tyann: ann,
            param: false,
            decl_span: s.span,
          })
        }
      SAssign(target, _) =>
        match target.assigned_base() {
          Some(b) =>
            if !module_bindings.contains(name_binding(b)) {
              module_bindings.push({
                name: b,
                tyann: "",
                param: false,
                decl_span: target.span,
              })
            }
          None => ()
        }
      SFunc(name, params, retann, body, sp) => {
        fns.push({ name, params, retann, body, span: sp, })
        if !module_bindings.contains(name_binding(name)) {
          module_bindings.push({ name, tyann: "", param: false, decl_span: sp, })
        }
      }
      _ => ()
    }
  }
  for b in module_bindings {
    w.bind(b)
  }
  for f in fns {
    let bs = collect_fn_bindings(f)
    fn_bindings.set(f.name, bs)
  }
  // pass 2: module-level uses (function definitions are tables, not flow)
  for s in m.body {
    match s.kind {
      SFunc(_, _, _, _, _) => ()
      _ => w.walk_stmt(s)
    }
  }
  // pass 3: each function in its own frame
  for f in fns {
    w.push_frame()
    let bs = or_empty(fn_bindings.get(f.name))
    for b in bs {
      w.bind(b)
    }
    w.vst.push({ func: f.name, file, line: f.span.start.line, })
    for st in f.body {
      w.walk_stmt(st)
    }
    w.audit_frame()
    let _ = w.vst.pop()
    w.pop_frame()
  }
  WalkResult::{ fns, module_bindings, fn_bindings, findings: w.findings, }
}

///|
fn name_binding(n : String) -> Binding {
  { name: n, tyann: "", param: false, decl_span: @core.zero_span(), }
}

///|
fn or_empty(a : Array[Binding]?) -> Array[Binding] {
  match a {
    Some(bs) => bs
    None => []
  }
}

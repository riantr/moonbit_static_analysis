// interp: lens 3 — the behavioral lens. Abstract
// interpretation over a reduced lattice; the method table comes
// from the type lens's signatures (assembly point 2 — the "host inference"
// is the type stage); `ABool`
// constants prune dead branches the same way the structural lens's folder
// does (assembly point 3, the folding insight ported into the lattice).
//
// Every report carries a virtual stack trace: entry frame first, error
// point last.

///|
/// The abstract value lattice: Bottom < Const < Type < Union < Any.
pub(all) enum AbsVal {
  ABottom
  AInt(Int)
  ABool(Bool)
  AType(String)
  AUnion(Array[String])
  AAny
} derive(Eq, Debug)

///|
pub fn val_name(v : AbsVal) -> String {
  match v {
    ABottom => "Union{}"
    AInt(_) => "int"
    ABool(_) => "bool"
    AType(t) => t
    AUnion(xs) => "Union{\{xs.join(", ")}}"
    AAny => "Any"
  }
}

///|
/// lub: Bottom absorbs; equal constants stay constants; disagreeing
/// constants widen to their type (the standard tmerge/widen).
pub fn vjoin(a : AbsVal, b : AbsVal) -> AbsVal {
  match (a, b) {
    (ABottom, x) => x
    (x, ABottom) => x
    (AAny, _) => AAny
    (_, AAny) => AAny
    (AInt(i), AInt(j)) => if i == j { AInt(i) } else { AType("int") }
    (ABool(i), ABool(j)) => if i == j { ABool(i) } else { AType("bool") }
    (AType(t1), AType(t2)) =>
      if t1 == t2 {
        AType(t1)
      } else {
        AUnion(union_names(t1, t2))
      }
    (AType(t), AUnion(xs)) | (AUnion(xs), AType(t)) => {
      let out : Array[String] = []
      for x in xs {
        out.push(x)
      }
      if !out.contains(t) {
        out.push(t)
      }
      out.sort()
      AUnion(out)
    }
    (AUnion(xs), AUnion(ys)) => {
      let out : Array[String] = []
      for x in xs {
        out.push(x)
      }
      for y in ys {
        if !out.contains(y) {
          out.push(y)
        }
      }
      out.sort()
      AUnion(out)
    }
    (AInt(_), _) => vjoin(AType("int"), b)
    (_, AInt(_)) => vjoin(a, AType("int"))
    (ABool(_), _) => vjoin(AType("bool"), b)
    (_, ABool(_)) => vjoin(a, AType("bool"))
  }
}

///|
fn union_names(t1 : String, t2 : String) -> Array[String] {
  if t1 < t2 {
    [t1, t2]
  } else {
    [t2, t1]
  }
}

///|
/// Widen constants to types (loop fixpoints / abstract time).
pub fn widen(v : AbsVal) -> AbsVal {
  match v {
    AInt(_) => AType("int")
    ABool(_) => AType("bool")
    other => other
  }
}

///|
/// Can value `v` be an argument for a parameter declared `ty`?
/// Bottom is vacuously applicable; Any matches everything (keep
/// inferring under Any — conservative).
pub fn vmatches(v : AbsVal, ty : String) -> Bool {
  match v {
    ABottom => true
    AAny => true
    AInt(_) => ty == "int" || ty == "float" || ty == "Any"
    ABool(_) => ty == "bool" || ty == "Any"
    AType(t) => t == ty || ty == "Any"
    AUnion(xs) => {
      let mut any = false
      for x in xs {
        if x == ty || ty == "Any" {
          any = true
        }
      }
      any
    }
  }
}

///|
/// Is the value a usable boolean condition? (non-boolean condition error)
pub fn vboolean(v : AbsVal) -> Bool {
  match v {
    ABool(_) => true
    AInt(_) => false
    AType(t) => t == "bool"
    AUnion(xs) => xs.contains("bool")
    ABottom => true
    AAny => true
  }
}

///|
priv enum Flow {
  FNormal
  FReturn
  FBreak
  FContinue
}

///|
priv struct MethodDef {
  name : String
  /// declared/inferred parameter types ("" = Any)
  ptypes : Array[String]
  /// parameter names, in order (from the walk table)
  pnames : Array[String]
  /// the partial return used on recursive cycles (from the signature)
  cycle_ret : AbsVal
  body : Array[@ast.Stmt]
  line : Int
}

///|
priv struct Interp {
  methods : Map[String, MethodDef]
  /// Names that exist but whose body is not analysed — the cross-file symbol
  /// table. A call to one of these is dispatched as an unknown-returning call
  /// instead of an undefined function, because the callee IS defined; it is
  /// defined in a file this single-file interpreter cannot read.
  ///
  /// Without this, the behavioral lens contradicted the structural and type
  /// lenses on every cross-package call: those two consult the symtab and
  /// stay silent, while this one reported `undefined function '@core.T::m'`.
  /// The self-scan surfaced it on this repository's own test helper
  /// (`@core.IfaceSymTab::empty()`), which is exactly the shape the table
  /// exists to answer.
  ///
  /// The whole TABLE, not just its `values` half. A `.mbti` declares
  /// `type Builder` and `pub fn Builder::new()`, so a constructor call
  /// `Builder()` lands in `types` and never in `values` — the table records
  /// declarations, and a constructor is not one. Measured on 0.4.4 against
  /// moonbitlang/core: the behavioral lens reported `undefined function
  /// 'Builder'` on code `moon check` accepts with 0 errors, while the
  /// structural and type lenses, which both check `has_type` as well, stayed
  /// silent. Three lenses, two consulted the table, and the third invented a
  /// finding the other two contradicted.
  extern_iface : @core.IfaceSymTab
  /// Names a file may use without importing anything, the same list the
  /// structural lens consults (`@core.ambient_names()`).
  ///
  /// Without it this lens reported `undefined function 'StringBuilder'` on
  /// `StringBuilder()` while the structural lens stayed silent on the same line
  /// — the identical shape of contradiction the `extern_iface` note above
  /// describes, reached through the wrong table. A builtin *type* constructor
  /// is a call in this lens (there is no separate constructor node) and a
  /// binding in the other one, so without this the two lenses answered the same
  /// line differently for the same reason.
  ambient : Map[String, Bool]
  /// Names of local functions defined in this file (`fn add(t : Ty) { ... }`
  /// inside a body). The behavioral lens does not execute their bodies —
  /// they capture the enclosing frame, which analyze_fn's environment cannot
  /// model — so references to them resolve and calls to them are dispatched
  /// as unknown-returning calls instead of being reported as undefined.
  /// Same fail-toward-silence trade as EMethodCall.
  local_fns : Map[String, Bool]
  file : String
  /// signature cache: key -> return value
  cache : Map[String, AbsVal]
  /// signatures currently being analyzed (cycle detection)
  in_progress : Map[String, Bool]
  /// partial returns of in-progress signatures (cached partials)
  partials : Map[String, AbsVal]
  mut sink : Array[@report.Report]
  vst : Array[@core.Frame]
  mut ret_vals : Array[AbsVal]
  mut flow : Flow
  mut globals : Map[String, AbsVal]
}

///|
fn new_interp(file : String, extern_iface : @core.IfaceSymTab) -> Interp {
  let ambient : Map[String, Bool] = Map([])
  for n in @core.ambient_names() {
    ambient.set(n, true)
  }
  Interp::{
    methods: Map([]),
    extern_iface,
    ambient,
    local_fns: Map([]),
    file,
    globals: Map([]),
    cache: Map([]),
    in_progress: Map([]),
    partials: Map([]),
    sink: [],
    vst: [],
    ret_vals: [],
    flow: FNormal,
  }
}

///|
fn sig_key(name : String, args : Array[AbsVal]) -> String {
  let parts : Array[String] = []
  for v in args {
    parts.push(val_name(v))
  }
  "\{name}(\{parts.join(", ")})"
}

///|
fn Interp::report(
  self : Interp,
  family : @core.Family,
  msg : String,
  sp : @core.Span,
) -> Unit {
  self.sink.push(@report.Report::{
    family,
    lenses: [@core.LBehavior],
    message: msg,
    span: sp,
    vst: @core.snapshot_vst(self.vst),
  })
}

///|
fn copy_env(e : Map[String, AbsVal]) -> Map[String, AbsVal] {
  let out : Map[String, AbsVal] = Map([])
  for k, v in e {
    out.set(k, v)
  }
  out
}

///|
fn Interp::merge_env(
  self : Interp,
  base : Map[String, AbsVal],
  other : Map[String, AbsVal],
) -> Map[String, AbsVal] {
  ignore(self)
  let out = copy_env(base)
  for k, v in other {
    match out.get(k) {
      Some(old) => out.set(k, vjoin(old, v))
      None => out.set(k, v)
    }
  }
  out
}

///|
fn widen_all(e : Map[String, AbsVal]) -> Map[String, AbsVal] {
  let out : Map[String, AbsVal] = Map([])
  for k, v in e {
    out.set(k, widen(v))
  }
  out
}

///|
/// Analyze a whole module. Phase 1 registers methods (from the signature
/// table — assembly point 2); phase 2 runs a dry top-level pass to populate
/// the signature cache (fixpoint for recursion via partials); phase 3 is the
/// report pass with complete virtual stacks.
pub fn analyze_module(
  m : @ast.Module,
  tr : @types.TypeResult,
  wr : @walk.WalkResult,
  file : String,
  extern_iface : @core.IfaceSymTab,
) -> Array[@report.Report] {
  let it = new_interp(file, extern_iface)
  // method table from the type lens's signatures (assembly point 2)
  for f in wr.fns {
    let sig : @types.Sig? = find_sig(tr, f.name)
    let ptypes : Array[String] = []
    let pts = match sig {
      Some(s) => s.param_tys
      None => []
    }
    for t in pts {
      let n = @types.ty_name(t)
      ptypes.push(if n == "Unknown" { "" } else { n })
    }
    let cycle_ret = match sig {
      Some(s) =>
        match s.declared_ret {
          @types.TUnknown => AAny
          t => AType(ret_name(t))
        }
      None => AAny
    }
    it.methods.set(f.name, {
      name: f.name,
      ptypes,
      pnames: fn_pnames(f),
      cycle_ret,
      body: f.body,
      line: f.span.start.line,
    })
  }
  // phase 2 (dry): populate the cache. Local fn names are collected first:
  // their bodies are not executed (they capture the enclosing frame), but
  // their names must resolve and their calls must not report undefined.
  collect_local_fns(m.body, it.local_fns)
  let itg = it
  itg.run_top(m, true)
  // phase 3 (report): replay with complete stacks
  itg.run_top(m, false)
  itg.sink
}

///|
fn ret_name(t : @types.Ty) -> String {
  match t {
    @types.TUnknown => "Any"
    @types.TNone => "None"
    @types.TInt => "int"
    @types.TFloat => "float"
    @types.TBool => "bool"
    @types.TStr => "str"
    @types.TList(_) => "List"
    @types.TFunc(n, _, _) => "fn \{n}"
    @types.TUnknownFn(n) => "fn \{n}"
    @types.TUnion(_) => "Any"
  }
}

///|
fn find_sig(tr : @types.TypeResult, name : String) -> @types.Sig? {
  for s in tr.sigs {
    if s.name == name {
      return Some(s)
    }
  }
  None
}

///|
fn Interp::run_top(self : Interp, m : @ast.Module, dry : Bool) -> Unit {
  let saved_sink = self.sink
  let saved_ret = self.ret_vals
  let saved_flow = self.flow
  if dry {
    self.sink = []
  }
  self.globals = Map([])
  self.flow = FNormal
  for s in m.body {
    match s.kind {
      SFunc(_, _, _, _, _) => ()
      _ => {
        self.vst.push({
          func: "main()",
          file: self.file,
          line: s.span.start.line,
        })
        self.exec_stmt(s, self.globals)
        let _ = self.vst.pop()
        self.flow = FNormal
      }
    }
  }
  if dry {
    self.sink = saved_sink
  }
  self.ret_vals = saved_ret
  self.flow = saved_flow
}

///|
fn Interp::exec_block(
  self : Interp,
  body : Array[@ast.Stmt],
  env : Map[String, AbsVal],
) -> Unit {
  for s in body {
    let terminated = match self.flow {
      FNormal => false
      FReturn | FBreak | FContinue => true
    }
    if terminated {
      // behavior lens's flow insight: statements after a terminator are
      // unreachable (reportUnreachable)
      self.report(@core.FUnreachable, "unreachable code", s.span)
      break
    }
    self.exec_stmt(s, env)
  }
}

///|
fn Interp::exec_stmt(
  self : Interp,
  s : @ast.Stmt,
  env : Map[String, AbsVal],
) -> Unit {
  match s.kind {
    SExpr(e) => {
      let _ = self.eval(e, env)
    }
    SLet(n, _, init) => {
      let v = self.eval(init, env)
      env.set(n, v)
    }
    SAssign(target, rhs) => {
      let v = self.eval(rhs, env)
      match target.kind {
        EName(n) =>
          if env.contains(n) {
            env.set(n, v)
          } else if self.globals.contains(n) {
            self.globals.set(n, v)
          } else {
            env.set(n, v)
          }
        EField(base, _) => {
          let _ = self.eval(base, env)
        }
        EIndex(base, idx) => {
          let _ = self.eval(base, env)
          let _ = self.eval(idx, env)
        }
        // `pair.0 = v`: a write reaches through the base, so the base is
        // evaluated; there is no tuple value in the lattice, so nothing is
        // assigned.
        ETupleField(base, _) => {
          let _ = self.eval(base, env)
        }
        EComp(_, sources, body) => {
          for s in sources {
            let _ = self.eval(s, env)
          }
          let _ = self.eval(body, env)
        }
        _ => ()
      }
    }
    SIf(cond, then, elseifs, els) =>
      // ABool constants prune dead branches (assembly point 3)
      match self.eval(cond, env) {
        ABool(true) => self.exec_block(then, env)
        ABool(false) => self.exec_alt(elseifs, els, env, 0)
        ABottom => ()
        cv => {
          if !vboolean(cv) {
            self.report(
              @core.FCondBool,
              "condition must be bool, got '\{val_name(cv)}'",
              cond.span,
            )
          }
          let env_then = copy_env(env)
          self.exec_block(then, env_then)
          let acc = env_then
          for ei in elseifs {
            let env_ei = copy_env(acc)
            self.exec_block(ei.body, env_ei)
            let merged = Interp::merge_env(self, acc, env_ei)
            acc.clear()
            for k, v in merged {
              acc.set(k, v)
            }
          }
          match els {
            Some(e) => {
              let env_e = copy_env(acc)
              self.exec_block(e, env_e)
              let merged = Interp::merge_env(self, acc, env_e)
              acc.clear()
              for k, v in merged {
                acc.set(k, v)
              }
            }
            None => ()
          }
          env.clear()
          for k, v in acc {
            env.set(k, v)
          }
        }
      }
    SWhile(cond, body) => {
      let cv = self.eval(cond, env)
      if !vboolean(cv) {
        self.report(
          @core.FCondBool,
          "condition must be bool, got '\{val_name(cv)}'",
          cond.span,
        )
      }
      // widening: run the body once in a widened copy; the pre-loop state
      // is the sound meet (the loop may run zero times)
      let wenv = widen_all(env)
      self.exec_block(body, wenv)
      let merged = Interp::merge_env(self, env, wenv)
      env.clear()
      for k, v in merged {
        env.set(k, v)
      }
    }
    SFor(v, _, seq, body) => {
      let sv = self.eval(seq, env)
      let elem = match sv {
        AType("str") => AType("str")
        ABottom => ABottom
        AAny => AAny
        AType("List") => AAny
        AUnion(_) => AAny
        _ => AAny
      }
      let wenv = widen_all(env)
      wenv.set(v, elem)
      self.exec_block(body, wenv)
      let merged = Interp::merge_env(self, env, wenv)
      env.clear()
      for k, v in merged {
        env.set(k, v)
      }
    }
    SReturn(e) => {
      let v = match e {
        Some(x) => self.eval(x, env)
        None => ABottom
      }
      self.ret_vals.push(v)
      self.flow = FReturn
    }
    SBreak => self.flow = FBreak
    SContinue => self.flow = FContinue
    SFunc(_, _, _, _, _) => ()
    // `let (a, b) = pair`: the initializer is evaluated ONCE (a second eval
    // would re-report the same finding), and every destructured name is set.
    SLetDestruct(names, init) => {
      let v = self.eval(init, env)
      for n in names {
        env.set(n, v)
      }
    }
    // A local function definition. Its body is NOT executed here — it
    // captures the enclosing frame, which the abstract environment cannot
    // model — so the statement is a no-op, exactly like SFunc above. Calls
    // to it are dispatched from the local_fns table (see Interp::call).
    SLocalFunc(_, _, _, _, _) => ()
    // A nested `{ ... }` block introduces no new scope in this AST, so the
    // statements run in the SAME environment (bindings escape the block,
    // exactly as the walk's SBlock arm models them). exec_block carries the
    // flow-termination check, so a terminator inside the block still marks
    // the following statement unreachable.
    SBlock(body) => self.exec_block(body, env)
  }
}

///|
fn Interp::exec_alt(
  self : Interp,
  elseifs : Array[@ast.ElseIf],
  els : Array[@ast.Stmt]?,
  env : Map[String, AbsVal],
  idx : Int,
) -> Unit {
  if idx < elseifs.length() {
    match self.eval(elseifs[idx].cond, env) {
      ABool(true) => self.exec_block(elseifs[idx].body, env)
      ABool(false) => self.exec_alt(elseifs, els, env, idx + 1)
      ABottom => ()
      cv => {
        if !vboolean(cv) {
          self.report(
            @core.FCondBool,
            "condition must be bool, got '\{val_name(cv)}'",
            elseifs[idx].cond.span,
          )
        }
        self.exec_block(elseifs[idx].body, env)
      }
    }
  } else {
    match els {
      Some(e) => self.exec_block(e, env)
      None => ()
    }
  }
}

///|
fn Interp::eval(
  self : Interp,
  e : @ast.Expr,
  env : Map[String, AbsVal],
) -> AbsVal {
  match e.kind {
    EInt(i) => AInt(i)
    // No value to abstract: not folding to AInt(0) would be a lie that the
    // lattice could then compare, and folding to 0 would make `x + literal`
    // look like arithmetic on a known number.
    EBigInt => AAny
    EFloat(_) => AType("float")
    EBool(b) => ABool(b)
    EStr(_, _) => AType("str")
    EList(_) => AType("List")
    EName(n) =>
      match env.get(n) {
        Some(v) => v
        None =>
          match self.globals.get(n) {
            Some(v) => v
            None =>
              if self.local_fns.contains(n) ||
                self.methods.contains(n) ||
                n == "print" ||
                n == "len" ||
                n == "abs" {
                AType("Function")
              } else if n.has_prefix("@") {
                // A cross-package reference (`@pkg.fn`, `@pkg.T::m`). The
                // walk and the type lens both refuse to resolve `@`-prefixed
                // names and stay silent — `@pkg` is a package, not a
                // variable — and the interpreter must not contradict them.
                AAny
              } else {
                // UndefVarErrorReport (jetanalyzer.jl:862)
                self.report(
                  @core.FUndefinedName,
                  "undefined variable '\{n}'",
                  e.span,
                )
                ABottom
              }
          }
      }
    EUnary(op, a) => {
      let v = self.eval(a, env)
      match (op, v) {
        (UNeg, AInt(i)) => AInt(-i)
        (UNeg, AType(t)) => AType(t)
        (UNot, ABool(b)) => ABool(!b)
        (UNot, AType(t)) => AType(t)
        (_, AAny) => AAny
        (_, ABottom) => ABottom
        _ => ABottom
      }
    }
    EBin(op, a, b) => {
      let l = self.eval(a, env)
      let r = self.eval(b, env)
      self.binop(op, l, r, e.span)
    }
    ECall(name, args) => {
      let vals : Array[AbsVal] = []
      for a in args {
        vals.push(self.eval(a, env))
      }
      self.call(name, vals, e.span)
    }
    // A method call. The receiver and every argument are EVALUATED, not skipped:
    // an undefined name inside `x.f(y)` is a real undefined name, and a branch
    // inside the receiver expression can still be unreachable. The result is
    // AAny because no method is modelled — returning the receiver's value would
    // invent arithmetic the analyzer cannot justify.
    //
    // A qualifier receiver (`@core.f(x)`) is not evaluated, for the same reason
    // the walk does not resolve it: `@core` is a package, and evaluating it
    // would report an undefined variable that does not exist.
    EMethodCall(base, _, args) => {
      if !base.is_qualifier() {
        let _ = self.eval(base, env)
      }
      for a in args {
        let _ = self.eval(a, env)
      }
      AAny
    }
    EField(base, _) => {
      let _ = self.eval(base, env)
      AAny
    }
    EIndex(base, idx) => {
      let b = self.eval(base, env)
      let _ = self.eval(idx, env)
      match b {
        AType("str") => AType("str")
        AType("List") => AAny
        AAny => AAny
        _ => AAny
      }
    }
    // A comprehension builds a list, but the lens does not model iteration,
    // so the result is unknown. The sources and the body are still EVALUATED,
    // so a call with a side effect inside a comprehension is not skipped.
    EComp(_, sources, body) => {
      for s in sources {
        let _ = self.eval(s, env)
      }
      let _ = self.eval(body, env)
      AAny
    }
    // A struct literal. Field VALUES are evaluated (an undefined name inside
    // them is a real undefined name), but the lens models no struct types,
    // so the result is the type name — the same trade as EComp above.
    EStruct(_, fields) => {
      for f in fields {
        let (_, v) = f
        let _ = self.eval(v, env)
      }
      AType("Struct")
    }
    // A tuple literal; `(e)` grouping is folded at parse time, so every
    // ETuple is a real tuple. Elements are evaluated; there is no tuple
    // value in the lattice, so the result is the type name.
    ETuple(elems) => {
      for x in elems {
        let _ = self.eval(x, env)
      }
      AType("Tuple")
    }
    // A range. Both ends are evaluated; the lens models no range value, so
    // the result is the type name (SFor's element therefore stays Any).
    ERange(a, b) => {
      let _ = self.eval(a, env)
      let _ = self.eval(b, env)
      AType("Range")
    }
    // `pair.0`: the base is evaluated (an undefined name inside it is a real
    // undefined name); there is no tuple value in the lattice, so the result
    // is unknown.
    ETupleField(base, _) => {
      let _ = self.eval(base, env)
      AAny
    }
    // An `is` pattern test. The base is evaluated and the binding a
    // successful match introduces is set to Any. The result is AAny
    // deliberately, NOT ABool: an ABool would prune one branch of an
    // enclosing `if` and drop the bindings that branch was analyzed with,
    // while AAny keeps both branches live (SIf's unknown-condition arm) and
    // vboolean(AAny) is true so a `while` still runs once. The branch env
    // copies are taken AFTER the condition eval, so the binding survives
    // into both branches.
    EIs(base, binding) => {
      let _ = self.eval(base, env)
      if binding != "" {
        env.set(binding, AAny)
      }
      AAny
    }
  }
}

///|
fn Interp::binop(
  self : Interp,
  op : @ast.BOp,
  l : AbsVal,
  r : AbsVal,
  sp : @core.Span,
) -> AbsVal {
  match (l, r) {
    (AInt(i), AInt(j)) =>
      match op {
        OpAdd => AInt(i + j)
        OpSub => AInt(i - j)
        OpMul => AInt(i * j)
        // Defence in depth. The lexer fix (block strings are strings, not code)
        // removed the known way a zero divisor reached here, but MoonBit's
        // compiler inserts a divide-by-zero guard here, so a stray zero would
        // abort the whole scan rather than produce a finding. An analyzer that
        // dies on one line is worse than one that says "unknown".
        OpMod => if j == 0 { ABottom } else { AInt(i % j) }
        OpDiv => AType("float")
        OpLt => ABool(i < j)
        OpLe => ABool(i <= j)
        OpGt => ABool(i > j)
        OpGe => ABool(i >= j)
        OpEq => ABool(i == j)
        OpNe => ABool(i != j)
        // The bitwise ops get explicit arms on PURPOSE, though the wildcard
        // below would keep this compiling: the wildcard returns
        // AType("bool"), and `1 + (h & 1023)` (the measured Class F death,
        // statecheck.mbt:275) would then flow a bool-typed operand into the
        // type-level OpAdd branch and report a FALSE method error —
        // trading a parse death for a wrong finding. Two ints bitwise'd are
        // an int.
        OpBitAnd => AInt(i & j)
        OpBitOr => AInt(i | j)
        OpBitXor => AInt(i ^ j)
        OpShl => AInt(i << j)
        OpShr => AInt(i >> j)
        _ => AType("bool")
      }
    (ABool(i), ABool(j)) =>
      match op {
        OpAnd => ABool(i && j)
        OpOr => ABool(i || j)
        OpEq => ABool(i == j)
        OpNe => ABool(i != j)
        _ => AType("bool")
      }
    (ABottom, _) | (_, ABottom) => ABottom
    _ => {
      // type-level arithmetic; mismatch = method error on `+`
      // (keep inferring under Any — conservative, no report)
      let numeric = fn(v : AbsVal) -> Bool {
        match v {
          AType("int") | AType("float") => true
          AInt(_) => true
          AAny => true
          _ => false
        }
      }
      let boolean = fn(v : AbsVal) -> Bool {
        match v {
          AType("bool") => true
          ABool(_) => true
          AAny => true
          _ => false
        }
      }
      let strv = fn(v : AbsVal) -> Bool {
        match v {
          AType("str") => true
          _ => false
        }
      }
      if l is AAny || r is AAny {
        // Any absorbs: conservative, keep inferring (the basic analyzer)
        return match op {
          OpLt | OpLe | OpGt | OpGe | OpEq | OpNe | OpAnd | OpOr =>
            AType("bool")
          OpDiv => AType("float")
          _ => AAny
        }
      }
      match op {
        OpAdd =>
          if (numeric(l) && numeric(r)) || (strv(l) && strv(r)) {
            AType(bin_widen(op, l, r))
          } else {
            self.report(
              @core.FMethodError,
              "no method matching +(\{val_name(l)}, \{val_name(r)})",
              sp,
            )
            ABottom
          }
        OpSub | OpMul | OpDiv | OpMod =>
          if numeric(l) && numeric(r) {
            if op == OpDiv {
              AType("float")
            } else {
              AType(bin_widen(op, l, r))
            }
          } else {
            self.report(
              @core.FMethodError,
              "no method matching \{op.symbol()}(\{val_name(l)}, \{val_name(r)})",
              sp,
            )
            ABottom
          }
        OpLt | OpLe | OpGt | OpGe =>
          if numeric(l) && numeric(r) {
            AType("bool")
          } else {
            self.report(
              @core.FMethodError,
              "no method matching \{op.symbol()}(\{val_name(l)}, \{val_name(r)})",
              sp,
            )
            ABottom
          }
        OpEq | OpNe => AType("bool")
        OpAnd | OpOr =>
          if boolean(l) && boolean(r) {
            AType("bool")
          } else {
            self.report(
              @core.FMethodError,
              "no method matching \{op.symbol()}(\{val_name(l)}, \{val_name(r)})",
              sp,
            )
            ABottom
          }
        OpBitAnd | OpBitOr | OpBitXor | OpShl | OpShr =>
          // Int-on-Int at the type level too, matching binop_result. This
          // match has no wildcard, so the arms are also what lets new BOp
          // variants compile at all.
          if numeric(l) && numeric(r) {
            AType("int")
          } else {
            self.report(
              @core.FMethodError,
              "no method matching \{op.symbol()}(\{val_name(l)}, \{val_name(r)})",
              sp,
            )
            ABottom
          }
      }
    }
  }
}

///|
fn bin_widen(op : @ast.BOp, l : AbsVal, r : AbsVal) -> String {
  let lname = val_name(l)
  let rname = val_name(r)
  if op == OpDiv {
    return "float"
  }
  if lname == "float" || rname == "float" {
    return "float"
  }
  if lname == "Any" || rname == "Any" {
    return "Any"
  }
  "int"
}

///|
fn Interp::call(
  self : Interp,
  name : String,
  vals : Array[AbsVal],
  sp : @core.Span,
) -> AbsVal {
  // builtins first (len's applicability is checked like a method)
  if name == "print" {
    return AType("None")
  }
  if name == "len" {
    match vals.get(0) {
      Some(v) =>
        match v {
          AType("str") | AType("List") => return AType("int")
          AAny | ABottom => return AType("int")
          _ => {
            self.report(
              @core.FMethodError,
              "no method matching len(\{val_name(v)})",
              sp,
            )
            return ABottom
          }
        }
      None => return AType("int")
    }
  }
  if name == "abs" {
    match vals.get(0) {
      Some(AInt(i)) => return AInt(if i < 0 { -i } else { i })
      Some(v) =>
        match v {
          AType("int") | AType("float") => return v
          AAny | ABottom => return AType("int")
          _ => {
            self.report(
              @core.FMethodError,
              "no method matching abs(\{val_name(v)})",
              sp,
            )
            return ABottom
          }
        }
      None => return ABottom
    }
  }
  match self.methods.get(name) {
    Some(def) => {
      // dispatch: every declared parameter type must accept its argument
      // (union-splitting lite; Any parameters accept everything)
      let mut ok = true
      for i, pt in def.ptypes {
        let arg = match vals.get(i) {
          Some(v) => v
          None => ABottom
        }
        if !(pt == "" || pt == "Any") && !vmatches(arg, pt) {
          ok = false
        }
      }
      if vals.length() != def.ptypes.length() {
        ok = false
      }
      if !ok {
        // MethodErrorReport (jetanalyzer.jl:652)
        let parts : Array[String] = []
        for v in vals {
          parts.push(val_name(v))
        }
        self.report(
          @core.FMethodError,
          "no method matching \{name}(\{parts.join(", ")})",
          sp,
        )
        return ABottom
      }
      self.analyze_fn(def, vals)
    }
    None => {
      // A name the cross-file table knows: the callee exists, in a file this
      // interpreter cannot read. Dispatching it as an unknown-returning call
      // is the honest answer — the alternative is reporting the name as
      // undefined, which contradicts the structural and type lenses (both of
      // which consult the same table and stay silent).
      // Both halves of the table, and both spellings — `has_value` /
      // `has_type` each try the exact key and then the bare one, which is the
      // same order the structural and type lenses use.
      if self.extern_iface.has_value(name) || self.extern_iface.has_type(name) {
        return AAny
      }
      // An ambient name — `StringBuilder()`, `Map([])`, `Int::max`. Same rule
      // as the line above, same reason: the name IS bound, just not in a file
      // this lens can read. Its value is unknown to us, so AAny.
      if self.ambient.contains(name) {
        return AAny
      }
      // A local function defined in this file but outside the top-level
      // method table. Its body captures the enclosing frame, which the
      // params-only env of analyze_fn cannot model, so it dispatches as an
      // unknown-returning call — the same fail-toward-silence trade as the
      // two checks above. Dispatching it as undefined would contradict the
      // structural and type lenses, both of which see its binding.
      if self.local_fns.contains(name) {
        return AAny
      }
      // callee existence was the structural/type lenses' finding; here it
      // is a runtime UndefVarError — the pipeline merges all three
      self.report(@core.FUndefinedName, "undefined function '\{name}'", sp)
      ABottom
    }
  }
}

///|
fn Interp::analyze_fn(
  self : Interp,
  def : MethodDef,
  vals : Array[AbsVal],
) -> AbsVal {
  // no cache short-circuit: the dry pass populates the cache for the
  // summary and converges recursion via partials, but the report pass must
  // re-execute every body so findings are emitted with full stacks
  let key = sig_key(def.name, vals)
  if self.in_progress.contains(key) {
    // recursion: consult the partial (cached partial results);
    // declared return types make the cycle converge
    match self.partials.get(key) {
      Some(v) => return v
      None => {
        self.partials.set(key, def.cycle_ret)
        return def.cycle_ret
      }
    }
  }
  self.in_progress.set(key, true)
  let env : Map[String, AbsVal] = Map([])
  for i, pt in def.ptypes {
    let name = "arg\{i}"
    env.set(
      name,
      if pt == "" {
        AAny
      } else {
        match vals.get(i) {
          Some(v) => v
          None => ABottom
        }
      },
    )
  }
  // bind parameter NAMES properly: walk the def's params? The method table
  // stores types only; recover names from the first statement scan
  let saved_sink = self.sink
  let saved_ret = self.ret_vals
  let saved_flow = self.flow
  self.ret_vals = []
  self.flow = FNormal
  self.vst.push({ func: def.name, file: self.file, line: def.line, })
  // body uses parameter names; map them from the stored def body params
  self.bind_params(def, vals, env)
  self.exec_block(def.body, env)
  let ret = join_vals(self.ret_vals)
  let _ = self.vst.pop()
  self.sink = saved_sink
  self.ret_vals = saved_ret
  self.flow = saved_flow
  self.in_progress.remove(key)
  // join the declared partial into the computed return: recursion returns
  // the partial, so the finished analysis is the join of both (partials are
  // refined by later passes; one round converges here)
  let refined = match self.partials.get(key) {
    Some(p) => vjoin(ret, p)
    None => ret
  }
  self.partials.remove(key)
  self.cache.set(key, refined)
  refined
}

///|
fn join_vals(vals : Array[AbsVal]) -> AbsVal {
  if vals.length() == 0 {
    return AType("None")
  }
  let mut acc = ABottom
  for v in vals {
    acc = vjoin(acc, v)
  }
  acc
}

///|
fn Interp::bind_params(
  self : Interp,
  def : MethodDef,
  vals : Array[AbsVal],
  env : Map[String, AbsVal],
) -> Unit {
  ignore(self)
  for i, name in def.pnames {
    env.set(
      name,
      match vals.get(i) {
        Some(v) => v
        None => ABottom
      },
    )
  }
}

///|
fn fn_pnames(f : @walk.FnInfo) -> Array[String] {
  let out : Array[String] = []
  for p in f.params {
    out.push(p.name)
  }
  out
}

///|
/// Index every locally-defined function name (`fn helper(...) { }` inside a
/// body) reachable from `stmts`, including nested ones. The interpreter uses
/// this table to know that a bare-name callee is DEFINED in this file even
/// though it is not in the top-level method table — see eval (name
/// resolution) and call (unknown-returning dispatch). Local fn bodies are NOT
/// executed here or anywhere in this lens: they capture the enclosing frame,
/// which the params-only env of analyze_fn cannot model, so calls to them
/// dispatch as unknown-returning instead of being abstractly run.
fn collect_local_fns(stmts : Array[@ast.Stmt], out : Map[String, Bool]) -> Unit {
  for s in stmts {
    match s.kind {
      SFunc(_, _, _, body, _) => collect_local_fns(body, out)
      SLocalFunc(n, _, _, body, _) => {
        out.set(n, true)
        collect_local_fns(body, out)
      }
      SIf(_, then, elseifs, els) => {
        collect_local_fns(then, out)
        for ei in elseifs {
          collect_local_fns(ei.body, out)
        }
        match els {
          Some(e) => collect_local_fns(e, out)
          None => ()
        }
      }
      SWhile(_, body) => collect_local_fns(body, out)
      SFor(_, _, _, body) => collect_local_fns(body, out)
      SBlock(body) => collect_local_fns(body, out)
      _ => ()
    }
  }
}

///|
fn Interp::summarize_sigs(self : Interp) -> Array[String] {
  let out : Array[String] = []
  for name, def in self.methods {
    let parts : Array[String] = []
    for pt in def.ptypes {
      parts.push(if pt == "" { "Any" } else { pt })
    }
    let key = sig_key(name, arg_placeholders(def))
    // refined where abstract execution reached the call; otherwise the
    // type lens's declared/inferred return (assembly point 2)
    let ret = match self.cache.get(key) {
      Some(v) => val_name(v)
      None => val_name(def.cycle_ret)
    }
    out.push("\{name}(\{parts.join(", ")}) -> \{ret}")
  }
  out.sort()
  out
}

///|
fn arg_placeholders(def : MethodDef) -> Array[AbsVal] {
  let out : Array[AbsVal] = []
  for pt in def.ptypes {
    out.push(if pt == "" { AAny } else { AType(pt) })
  }
  out
}

///|
/// Signatures analyzed by abstract interpretation, for the pipeline
/// summary (`f(::int) -> int` style).
pub fn analyzed_sigs(
  m : @ast.Module,
  tr : @types.TypeResult,
  wr : @walk.WalkResult,
  file : String,
  extern_iface : @core.IfaceSymTab,
) -> Array[String] {
  let it = new_interp(file, extern_iface)
  for f in wr.fns {
    let sig : @types.Sig? = find_sig(tr, f.name)
    let ptypes : Array[String] = []
    let pts = match sig {
      Some(s) => s.param_tys
      None => []
    }
    for t in pts {
      let n = @types.ty_name(t)
      ptypes.push(if n == "Unknown" { "" } else { n })
    }
    let cycle_ret = match sig {
      Some(s) =>
        match s.declared_ret {
          @types.TUnknown => AAny
          t => AType(ret_name(t))
        }
      None => AAny
    }
    it.methods.set(f.name, {
      name: f.name,
      ptypes,
      pnames: fn_pnames(f),
      cycle_ret,
      body: f.body,
      line: f.span.start.line,
    })
  }
  collect_local_fns(m.body, it.local_fns)
  it.run_top(m, true)
  it.run_top(m, false)
  it.summarize_sigs()
}

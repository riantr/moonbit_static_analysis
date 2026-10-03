// infer: the type lens's expression walk. Scopes mirror the structural
// lens's frames (module frame 0, function frames 1..) — but the tables were
// already built by `walk`, so this is annotation + inference only.

///|
priv struct Infer {
  fn_bindings : Map[String, Array[@walk.Binding]]
  /// per-frame symbol types; frame 0 = module
  frames : Array[Map[String, Ty]]
  annos : Array[Map[String, Bool]]
  builtins : Map[String, Ty]
  sigs : Array[Sig]
  findings : Array[@report.Report]
  vst : Array[@core.Frame]
}

///|
fn new_infer(fn_bindings : Map[String, Array[@walk.Binding]]) -> Infer {
  let builtins : Map[String, Ty] = Map([])
  builtins.set("print", TFunc("print", [TUnknown], TNone))
  builtins.set("len", TFunc("len", [TUnknown], TInt))
  builtins.set("abs", TFunc("abs", [TInt], TInt))
  Infer::{
    fn_bindings,
    frames: [Map([])],
    annos: [Map([])],
    builtins,
    sigs: [],
    findings: [],
    vst: [],
  }
}

///|
fn Infer::declare_sym(
  self : Infer,
  b : @walk.Binding,
  ty : Ty,
  annotated : Bool,
) -> Unit {
  let fi = self.frames.length() - 1
  self.frames[fi].set(b.name, ty)
  self.annos[fi].set(b.name, annotated)
}

///|
fn Infer::lookup(self : Infer, name : String) -> Ty? {
  let mut i = self.frames.length() - 1
  while i >= 0 {
    match self.frames[i].get(name) {
      Some(t) => return Some(t)
      None => i -= 1
    }
  }
  match self.builtins.get(name) {
    Some(t) => Some(t)
    None => None
  }
}

///|
fn Infer::report(
  self : Infer,
  family : @core.Family,
  msg : String,
  sp : @core.Span,
) -> Unit {
  self.findings.push(@report.Report::{
    family,
    lenses: [@core.LType],
    message: msg,
    span: sp,
    vst: @core.snapshot_vst(self.vst),
  })
}

///|
/// Expression typing. `hint` is the expected type from an annotation.
fn Infer::ty_of(self : Infer, e : @ast.Expr, hint : Ty) -> Ty {
  match e.kind {
    EInt(_) => TInt
    EFloat(_) => TFloat
    EBool(_) => TBool
    EStr(_) => TStr
    EList(elems) => {
      let mut elem : Ty = TUnknown
      for x in elems {
        elem = ty_join(elem, self.ty_of(x, TUnknown))
      }
      TList(elem)
    }
    EName(n) =>
      // unresolved names surface as FUndefinedName from THIS lens too —
      // they merge with the structural/behavioral echoes at the same span
      match self.lookup(n) {
        Some(t) => t
        None => {
          self.report(@core.FUndefinedName, "undefined name '\{n}'", e.span)
          hint
        }
      }
    EUnary(op, a) =>
      match op {
        UNeg => self.ty_of(a, TUnknown)
        UNot =>
          match self.ty_of(a, TUnknown) {
            TBool => TBool
            other => {
              self.report(
                @core.FOpMismatch,
                "operand of '!' must be bool, got '\{ty_name(other)}'",
                e.span,
              )
              TUnknown
            }
          }
      }
    EBin(op, a, b) => {
      let lt = self.ty_of(a, TUnknown)
      let rt = self.ty_of(b, TUnknown)
      match binop_result(op, lt, rt) {
        Some(t) => t
        None => {
          self.report(
            @core.FOpMismatch,
            "unsupported operand types for '\{op.symbol()}': '\{ty_name(lt)}' and '\{ty_name(rt)}'",
            e.span,
          )
          TUnknown
        }
      }
    }
    ECall(name, args) =>
      match self.lookup(name) {
        Some(TFunc(fn_name, params, ret)) => {
          // argument type check (reportCallIssue / reportArgumentType)
          for i, arg in args {
            let at = self.ty_of(arg, TUnknown)
            let want = match params.get(i) {
              Some(p) => p
              None => TUnknown
            }
            if !ty_assignable(at, want) {
              self.report(
                @core.FArgType,
                "argument \{i + 1} to '\{fn_name}' has incompatible type '\{ty_name(at)}'; expected '\{ty_name(want)}'",
                arg.span,
              )
            }
          }
          if args.length() > params.length() {
            self.report(
              @core.FArgType,
              "too many arguments to '\{fn_name}': expected \{params.length()}, got \{args.length()}",
              e.span,
            )
          }
          ret
        }
        Some(t) => {
          self.report(
            @core.FOpMismatch,
            "'\{name}' has type '\{ty_name(t)}' and is not callable",
            e.span,
          )
          TUnknown
        }
        None => TUnknown
      }
    EField(base, _) => self.ty_of(base, TUnknown)
    EIndex(base, idx) => {
      let bt = self.ty_of(base, TUnknown)
      let it = self.ty_of(idx, TUnknown)
      if !(it is TInt) && !(it is TUnknown) {
        self.report(
          @core.FOpMismatch,
          "list indices must be int, got '\{ty_name(it)}'",
          idx.span,
        )
      }
      match bt {
        TList(elem) => elem
        _ => TUnknown
      }
    }
  }
}

///|
fn Infer::assign_check(
  self : Infer,
  target : @ast.Expr,
  rhs : @ast.Expr,
) -> Unit {
  let vt = self.ty_of(rhs, TUnknown)
  match target.kind {
    EName(n) => {
      let fi = self.frames.length() - 1
      match self.frames[fi].get(n) {
        Some(old) =>
          match self.annos[fi].get(n) {
            Some(true) =>
              if !ty_assignable(vt, old) {
                self.report(
                  @core.FAssignType,
                  "cannot assign '\{ty_name(vt)}' to annotated name '\{n}: \{ty_name(old)}'",
                  target.span,
                )
              }
            _ => {
              // re-binding without annotation: widen through
              // gradual binding
              let joined = ty_join(old, vt)
              self.frames[fi].set(n, joined)
            }
          }
        None => self.frames[fi].set(n, vt)
      }
    }
    EField(base, _) => {
      let _ = self.ty_of(base, TUnknown)
    }
    EIndex(base, idx) => {
      let bt = self.ty_of(base, TUnknown)
      let it = self.ty_of(idx, TUnknown)
      if !(it is TInt) && !(it is TUnknown) {
        self.report(
          @core.FOpMismatch,
          "list indices must be int, got '\{ty_name(it)}'",
          idx.span,
        )
      }
      let vt2 = self.ty_of(rhs, TUnknown)
      match bt {
        TList(elem) =>
          if !ty_assignable(vt2, elem) {
            self.report(
              @core.FAssignType,
              "cannot assign '\{ty_name(vt2)}' into '[\{ty_name(elem)}]'",
              target.span,
            )
          }
        _ => ()
      }
    }
    _ => ()
  }
}

///|
fn Infer::walk_stmt(self : Infer, s : @ast.Stmt) -> Unit {
  match s.kind {
    SExpr(e) => {
      let _ = self.ty_of(e, TUnknown)
    }
    SLet(n, ann, init) => {
      let hint = ann_to_ty(ann)
      let vt = self.ty_of(init, hint)
      let fi = self.frames.length() - 1
      let resolved = if hint is TUnknown {
        vt
      } else {
        // annotation wins; value must fit it
        if !ty_assignable(vt, hint) {
          self.report(
            @core.FAssignType,
            "cannot assign '\{ty_name(vt)}' to annotated name '\{n}: \{ty_name(hint)}'",
            s.span,
          )
        }
        hint
      }
      self.frames[fi].set(n, resolved)
      self.annos[fi].set(n, !(hint is TUnknown))
    }
    SAssign(target, rhs) => self.assign_check(target, rhs)
    SIf(cond, then, elseifs, els) => {
      let ct = self.ty_of(cond, TUnknown)
      if !(ct is TBool) && !(ct is TUnknown) {
        self.report(
          @core.FCondBool,
          "condition must be bool, got '\{ty_name(ct)}'",
          cond.span,
        )
      }
      for st in then {
        self.walk_stmt(st)
      }
      for ei in elseifs {
        let _ = self.ty_of(ei.cond, TUnknown)
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
    SWhile(cond, body) => {
      let ct = self.ty_of(cond, TUnknown)
      if !(ct is TBool) && !(ct is TUnknown) {
        self.report(
          @core.FCondBool,
          "condition must be bool, got '\{ty_name(ct)}'",
          cond.span,
        )
      }
      for st in body {
        self.walk_stmt(st)
      }
    }
    SFor(v, _, seq, body) => {
      let st = self.ty_of(seq, TUnknown)
      let elem = match st {
        TList(e) => e
        _ => TUnknown
      }
      let fi = self.frames.length() - 1
      self.frames[fi].set(v, elem)
      self.annos[fi].set(v, false)
      for x in body {
        self.walk_stmt(x)
      }
    }
    SReturn(e) =>
      match e {
        Some(x) => {
          let _ = self.ty_of(x, TUnknown)
        }
        None => ()
      }
    SBreak | SContinue => ()
    SFunc(_, _, _, _, _) => ()
  }
}

///|
/// Analyze one function body; returns the joined return type of all
/// `return` expressions (Unknown when none).
fn Infer::run_fn(self : Infer, f : @walk.FnInfo) -> Ty {
  self.frames.push(Map([]))
  self.annos.push(Map([]))
  self.vst.push({ func: f.name, file: "ml", line: f.span.start.line, })
  // declarations come from the structural lens's table
  let bs = match self.fn_bindings.get(f.name) {
    Some(v) => v
    None => []
  }
  for b in bs {
    if b.param {
      self.declare_sym(b, ann_to_ty(b.tyann), !(b.tyann == ""))
    } else {
      // body bindings start Unknown; statements refine them
      self.declare_sym(b, TUnknown, false)
    }
  }
  for st in f.body {
    self.walk_stmt(st)
  }
  // collect returns by re-walking (small subsets: direct scan)
  let ret = self.scan_returns(f.body)
  self.sigs.push({
    name: f.name,
    param_tys: fn_param_tys(f),
    ret,
    declared_ret: ann_to_ty(f.retann),
    line: f.span.start.line,
  })
  let _ = self.vst.pop()
  let _ = self.frames.pop()
  let _ = self.annos.pop()
  ret
}

///|
fn fn_param_tys(f : @walk.FnInfo) -> Array[Ty] {
  let out : Array[Ty] = []
  for p in f.params {
    out.push(ann_to_ty(p.tyann))
  }
  out
}

///|
fn Infer::scan_returns(self : Infer, stmts : Array[@ast.Stmt]) -> Ty {
  let mut acc : Ty = TUnknown
  for s in stmts {
    match s.kind {
      SReturn(Some(e)) => acc = ty_join(acc, self.ty_of(e, TUnknown))
      SIf(_, then, elseifs, els) => {
        acc = ty_join(acc, self.scan_returns(then))
        for ei in elseifs {
          acc = ty_join(acc, self.scan_returns(ei.body))
        }
        match els {
          Some(e) => acc = ty_join(acc, self.scan_returns(e))
          None => ()
        }
      }
      SWhile(_, body) => acc = ty_join(acc, self.scan_returns(body))
      SFor(_, _, _, body) => acc = ty_join(acc, self.scan_returns(body))
      _ => ()
    }
  }
  acc
}

///|
/// Run the type lens over a full module (the pipeline entry).
pub fn infer_full(m : @ast.Module, wr : @walk.WalkResult) -> TypeResult {
  let inf = new_infer(wr.fn_bindings)
  for s in m.body {
    match s.kind {
      SLet(n, ann, init) => {
        let hint = ann_to_ty(ann)
        let vt = inf.ty_of(init, hint)
        let resolved = if hint is TUnknown { vt } else { hint }
        inf.frames[0].set(n, resolved)
        inf.annos[0].set(n, !(hint is TUnknown))
      }
      SAssign(target, rhs) =>
        match target.kind {
          EName(n) =>
            match inf.frames[0].get(n) {
              Some(old) => {
                let vt = inf.ty_of(rhs, TUnknown)
                match inf.annos[0].get(n) {
                  Some(true) =>
                    if !ty_assignable(vt, old) {
                      inf.report(
                        @core.FAssignType,
                        "cannot assign '\{ty_name(vt)}' to annotated name '\{n}: \{ty_name(old)}'",
                        target.span,
                      )
                    }
                  _ => inf.frames[0].set(n, ty_join(old, vt))
                }
              }
              None => {
                let vt = inf.ty_of(rhs, TUnknown)
                inf.frames[0].set(n, vt)
              }
            }
          _ => inf.assign_check(target, rhs)
        }
      SFunc(name, params, retann, body, sp) => {
        let ft = TFunc(
          name,
          fn_param_tys({ name, params, retann, body, span: sp, }),
          ann_to_ty(retann),
        )
        inf.frames[0].set(name, ft)
      }
      // every other top-level statement type-checks in the module frame
      // (calls, conditions, returns — module-level code is checked too)
      _ => inf.walk_stmt(s)
    }
  }
  for f in wr.fns {
    let _ = inf.run_fn(f)
  }
  let syms : Array[TypedSym] = []
  for n, t in inf.frames[0] {
    let annotated = match inf.annos[0].get(n) {
      Some(a) => a
      None => false
    }
    syms.push({
      name: n,
      ty: t,
      annotated,
      fn_scope: "",
      decl_span: @core.zero_span(),
    })
  }
  TypeResult::{ syms, sigs: inf.sigs, findings: inf.findings, }
}

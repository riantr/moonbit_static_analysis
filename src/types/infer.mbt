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
  /// names declared in `.mbti` files of OTHER modules/packages; a hit
  /// returns TUnknown (types) or TFunc(name, [TUnknown], TUnknown) (values)
  /// so the type lens does not also fire FUndefinedName
  extern_iface : @core.IfaceSymTab
  /// Same rule as the structural lens: on a file the frontend did not finish,
  /// an unresolved name proves nothing. This lens keeps its OWN frame copy, so
  /// without the flag it would report the same unprovable name the structural
  /// lens has already decided to stay silent about.
  partial : Bool
  sigs : Array[Sig]
  findings : Array[@report.Report]
  vst : Array[@core.Frame]
}

///|
fn new_infer(
  fn_bindings : Map[String, Array[@walk.Binding]],
  extern_iface : @core.IfaceSymTab,
  partial : Bool,
) -> Infer {
  // Every ambient name seeds the table as TUnknown. The three that follow are
  // then overwritten with their real signatures so `len(x)` still infers Int
  // and a bad call to `abs` is still caught. Before this, the table held only
  // those three and the type lens re-reported the ambient names the walk
  // already suppressed, from its own private copy of the list.
  let builtins : Map[String, Ty] = Map([])
  for n in @core.ambient_names() {
    if !builtins.contains(n) {
      builtins.set(n, TUnknown)
    }
  }
  builtins.set("print", TFunc("print", [], [TUnknown], TNone))
  builtins.set("len", TFunc("len", [], [TUnknown], TInt))
  builtins.set("abs", TFunc("abs", [], [TInt], TInt))
  Infer::{
    fn_bindings,
    frames: [Map([])],
    annos: [Map([])],
    builtins,
    extern_iface,
    partial,
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
    None =>
      // Cross-file names from .mbti: a type hit returns TUnknown (the
      // annotation `let x : Foo = ...` parses `Foo` as TUnknown anyway, so
      // this keeps the type lens's treatment of unknown types consistent);
      // a value hit returns TUnknownFn — we know the name IS a value but not
      // what it takes, so the call handler must check neither the argument
      // types nor the arity against it. Names present in BOTH sets are
      // returned as values, because the call shape (`Foo(...)`) is the user's
      // actual intent and the ECall handler is the one that would otherwise
      // fire FOpMismatch on a TUnknown type.
      //
      // Measured on 0.4.4 against moonbitlang/core: this used to return
      // `TFunc(name, [TUnknown], TUnknown)`, and the one-element parameter
      // list was documented as deliberate ("the arity check still fires past
      // 1 arg"). It is not sound — a `.mbti` gives us the NAME, never the
      // parameter list — so every cross-file call with two or more arguments
      // reported "too many arguments to 'f': expected 1, got 2". 12 of those
      // on a clean 882-file stdlib that `moon check` accepts with 0 errors.
      if self.extern_iface.has_value(name) {
        // A cross-file CONSTANT is a value we know is not callable. Typing it as
        // `TUnknownFn` made ordinary arithmetic on it an operator mismatch —
        // `3.0F * hz` on a `const hz` from another package, reported as
        // "unsupported operand types for '*': 'float' and 'fn hz (signature not
        // read)'". `TUnknown` still claims no type; it just does not claim
        // callability, and it absorbs instead of firing.
        if self.extern_iface.is_const(name) {
          Some(TUnknown)
        } else {
          Some(TUnknownFn(name))
        }
      } else if self.extern_iface.has_type(name) {
        Some(TUnknown)
      } else {
        // A qualified path whose TAIL is a known name. `Layer::ReLU` is a unit
        // enum variant: the harvest binds the bare `ReLU`, not the whole path,
        // so the full-name lookup above misses it while the payload variant
        // beside it (`Layer::Conv2d(p)`) resolves. Reached only after the whole
        // path failed, so it cannot shadow a name that resolves on its own.
        let tail = @core.path_tail(name)
        if tail == "" || tail == name {
          None
        } else {
          self.lookup(tail)
        }
      }
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
    // TUnknown, not TInt. The literal is a real integer, but it may be an
    // Int64 or UInt64 that this analyzer does not model, and calling
    // `f(0xffffffffUL)` where `f` takes Int64 an Int-shaped argument wrong
    // would be a false positive on correct code. Unknown suppresses the
    // check in both directions, which is the right trade.
    EBigInt => TUnknown
    EFloat(_) => TFloat
    EBool(_) => TBool
    EStr(_, _) => TStr
    EList(elems) => {
      // An empty literal says nothing about its element type, so it must not
      // claim one: `[]` alone is `TList(TUnknown)`.
      //
      // It does NOT adopt the hint here, and that was a deliberate measurement.
      // An earlier version of this arm did `return match hint { TList(_) =>
      // hint; _ => TList(TUnknown) }` to avoid a mismatch against an
      // `Array[String]` annotation — and the branch turned out to be
      // UNOBSERVABLE: muting it changed nothing in the finding stream on either
      // this repository's own source or riantr/pyroduct 0.1.29 (byte-identical
      // output, 496 and 528 findings), and no test could kill it.
      //
      // The reason is `ty_assignable`: it recurses into `TList`, so
      // `TList(TUnknown)` IS assignable to `TList(TStr)` and the mismatch never
      // fires anyway. The two fixes covered the same ground, one of them with a
      // killing mutation and one without. Only the one that can be killed stays:
      // a guard that no test can fail and no corpus can distinguish is not
      // insurance, it is untested code that looks like a decision.
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
          // An `@`-prefixed name is an import alias, not a binding in this
          // file — the same reason walk's resolve gate skips it. Reporting
          // it here would contradict the structural lens on code `moon
          // check` accepts.
          if !self.partial && !n.has_prefix("@") {
            self.report(@core.FUndefinedName, "undefined name '\{n}'", e.span)
          }
          hint
        }
      }
    EUnary(op, a) =>
      match op {
        UNeg => self.ty_of(a, TUnknown)
        UNot =>
          match self.ty_of(a, TUnknown) {
            TBool => TBool
            // Same guard as SIf / SWhile below: an unknown operand is not
            // evidence of a non-bool operand. This branch was the one bool
            // check in this file without it, and the method-call work exposed
            // it — `Map::contains` is not in the type lens's signature table,
            // so its result is TUnknown and `!m.contains(k)` read as a mismatch
            // on code `moon check` accepts.
            TUnknown => TBool
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
    ECall(name, args, labels) =>
      match self.lookup(name) {
        Some(TFunc(fn_name, pnames, params, ret)) => {
          // argument type check (reportCallIssue / reportArgumentType)
          //
          // An argument's INDEX is not its parameter's index as soon as any
          // argument is named: MoonBit accepts `f(label=…, shortcut=…,
          // intent=…)` for `fn f(intent~, label?, shortcut?)`, settled against
          // `moon check`. So each argument is matched by LABEL when it has
          // one, and only falls back to position when it does not or when the
          // label names no parameter (a signature whose names were never
          // read, e.g. a builtin). Comparing `args[3]` to `params[3]` is what
          // produced `argument 4 … has incompatible type 'str'; expected
          // 'bool'` six times on `moui core/gesture.mbt:754` onward, where
          // `description` is passed fourth and `enabled` is declared fourth.
          for i, arg in args {
            let at = self.ty_of(arg, TUnknown)
            let label = match labels.get(i) {
              Some(l) => l
              None => ""
            }
            let pos = match param_index(pnames, label) {
              Some(k) => k
              None => i
            }
            let want = match params.get(pos) {
              Some(p) => p
              None => TUnknown
            }
            if !ty_assignable(at, want) {
              self.report(
                @core.FArgType,
                "argument \{pos + 1} to '\{fn_name}' has incompatible type '\{ty_name(at)}'; expected '\{ty_name(want)}'",
                arg.span,
              )
            }
          }
          // The arity check is POSITIONAL, and it stays that way only for positional
          // calls. Named arguments are label-addressed, so an argument's index is not
          // its parameter's index (the reason the whole change exists) and the COUNT is
          // not a bound on the parameter count either. Measured before this comment was
          // written, not assumed:
          //
          //   - `moon check` REJECTS every shape where a named call exceeds the
          //     parameter count: a duplicate label is error 4084, a label matching no
          //     parameter is 4085. So on code that compiles this check can never fire,
          //     and dropping the gate would not surface any real defect.
          //   - Across the six corpora (12,428 files) the gate changes exactly ONE
          //     finding: `moui backend/web/web_host.mbt`, an arity report at a call past
          //     the file's reliable-region boundary, so it lands in the `unreliable`
          //     bucket and is never shown as a result. That one could not be confirmed
          //     as a true positive, and an argument-COUNT check is precisely where a
          //     misread cross-file signature produces a false positive.
          //
          // The gate is therefore kept as a deliberate leniency on label-addressed
          // calls, not as a fix. The positional path below is unchanged and still
          // tested.
          let all_positional = labels.is_empty() ||
            labels.every(fn(l) { l == "" })
          if all_positional && args.length() > params.length() {
            self.report(
              @core.FArgType,
              "too many arguments to '\{fn_name}': expected \{params.length()}, got \{args.length()}",
              e.span,
            )
          }
          ret
        }
        Some(TUnknownFn(_)) => {
          // Known to be a value, signature not read: the call is real, the
          // arguments are unchecked, and the result is unknown. Deliberately
          // does NOT fall through to the "not callable" arm below.
          for arg in args {
            ignore(self.ty_of(arg, TUnknown))
          }
          TUnknown
        }
        Some(t) => {
          // `TUnknown` here means the name resolved to something whose type
          // we could not determine — a cross-file type hit, most often.
          // Calling it is therefore not evidence of anything. Reporting
          // "not callable" about a type we do not know is the one claim this
          // lens cannot make. Measured on 0.4.4: 12 findings of the form
          // "'StringBuilder' has type 'Unknown' and is not callable" on
          // moonbitlang/core, a package `moon check` accepts with 0 errors —
          // every one of them a constructor call on a type the analyzer
          // merely could not resolve.
          if !(t is TUnknown) {
            self.report(
              @core.FOpMismatch,
              "'\{name}' has type '\{ty_name(t)}' and is not callable",
              e.span,
            )
          }
          TUnknown
        }
        None => TUnknown
      }
    // A method call. The receiver and every argument are typed, so a wrong
    // receiver or an undefined name inside an argument is still found. The
    // METHOD itself is not checked at all: this lens has no signature for it,
    // so an arity error or a "not callable" claim would be the tool asserting
    // something about a signature it never read. Same reason the TUnknownFn arm
    // above deliberately does not fall through.
    //
    // The result is TUnknown rather than the receiver's type. `x.f()` is not
    // necessarily an `x`.
    EMethodCall(base, _, args, _) => {
      if !base.is_qualifier() {
        ignore(self.ty_of(base, TUnknown))
      }
      for arg in args {
        ignore(self.ty_of(arg, TUnknown))
      }
      TUnknown
    }
    EField(base, _) => self.ty_of(base, TUnknown)
    EIndex(base, idx) => {
      let bt = self.ty_of(base, TUnknown)
      let it = self.ty_of(idx, TUnknown)
      // Only a LIST is indexed by int. `Map` is indexed by its key type, and
      // the type model has no `Map` — `Map[String, Int]` reads as TUnknown, so
      // this used to assert "list indices must be int" about a subscript whose
      // base we had not identified as a list at all.
      //
      // Measured on riantr/pyroduct 0.1.29: 2 false positives on `src/paths.mbt`
      // (`color[u] = 1` and `color[u] = 2`, where `color : Map[String, Int]` and
      // `u : String`), reported at `error:` severity on a file `moon check`
      // accepts with zero errors.
      //
      // The claim needs the base: an unknown base is not evidence of a list,
      // and reporting there would be inventing a type error out of a type this
      // analyzer never read.
      if bt is TList(_) && !(it is TInt) && !(it is TUnknown) {
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
    // A comprehension yields a list, but its element type is the body's type
    // under an iterable we may not model, so `TUnknown` is the honest answer.
    // The sources and the body are still TYPED, so the argument-type and
    // index checks inside them still run.
    EComp(vars, sources, body) => {
      self.frames.push(Map([]))
      self.annos.push(Map([]))
      let fi = self.frames.length() - 1
      for v in vars {
        self.frames[fi].set(v, TUnknown)
        self.annos[fi].set(v, false)
      }
      for s in sources {
        let _ = self.ty_of(s, TUnknown)
      }
      let _ = self.ty_of(body, TUnknown)
      let _ = self.frames.pop()
      let _ = self.annos.pop()
      TUnknown
    }
    // A struct literal `{ field : value, shorthand, }` or `Type::{ ... }`.
    // The path is NOT resolved as a binding (parse guarantees the shorthand
    // form re-binds existing names instead). Field VALUES are typed, so a
    // wrong argument or an undefined name inside them is still found; the
    // constructor's own field types are not modelled, so the literal's type
    // is unknown — the honest answer, same trade as EComp above.
    EStruct(_, fields) => {
      for f in fields {
        let (_, v) = f
        let _ = self.ty_of(v, TUnknown)
      }
      TUnknown
    }
    // A tuple literal; `(e)` grouping is folded away at parse time, so every
    // ETuple is a real tuple. Elements are typed; there is no tuple Ty to
    // name, so the result is unknown.
    ETuple(elems) => {
      for x in elems {
        let _ = self.ty_of(x, TUnknown)
      }
      TUnknown
    }
    // A range `a..<b`. Both ends are typed; there is no range Ty, so the
    // result is unknown (SFor's loop variable therefore starts Unknown too).
    ERange(a, b) => {
      let _ = self.ty_of(a, TUnknown)
      let _ = self.ty_of(b, TUnknown)
      TUnknown
    }
    // `pair.0`: there is no tuple Ty to per-element, so the element is
    // unknown; the base is still TYPED, so a wrong name inside it is still
    // found. The int-index check EIndex runs does not apply here — the
    // position is a literal Int by construction.
    ETupleField(base, _) => {
      let _ = self.ty_of(base, TUnknown)
      TUnknown
    }
    // `e is Pattern`: the base is typed, a pattern binding starts Unknown
    // in the current frame for the uses that follow, and the test itself
    // is boolean. TBool is safe even though the pattern is not modelled:
    // an `is` test IS bool in MoonBit, and the operators it feeds
    // (`&&`, `||`, `!`) check bool against bool.
    EIs(base, bindings) => {
      let _ = self.ty_of(base, TUnknown)
      let fi = self.frames.length() - 1
      for b in bindings {
        if b != "" {
          self.frames[fi].set(b, TUnknown)
          self.annos[fi].set(b, false)
        }
      }
      TBool
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
      // the same base-type gate as the READ arm above, and for the same
      // measured reason: `color[u] = 1` on a `Map[String, Int]` is not a list
      // subscript. Both arms must agree — a check that fires on read and not
      // on write is a claim about syntax, not about types.
      if bt is TList(_) && !(it is TInt) && !(it is TUnknown) {
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
    // The payload IS type-checked. What it must NOT do is join into the
    // function's return type, which is what the `SReturn(Some(e))` arm below
    // does -- a raise produces no value, so `raise E` would otherwise
    // contribute `E`'s type to what the function returns.
    SRaise(e) =>
      match e {
        Some(x) => {
          let _ = self.ty_of(x, TUnknown)
        }
        None => ()
      }
    SBreak | SContinue => ()
    SFunc(_, _, _, _, _) => ()
    // `let (a, b) = pair`: tuple element types are not modelled (no tuple
    // Ty), so every destructured name starts Unknown in the current frame
    // and statements refine them — exactly how body bindings from walk's
    // table are seeded. The initializer is typed ONCE: a second ty_of would
    // re-report the same finding from this lens.
    SLetDestruct(names, init) => {
      let _ = self.ty_of(init, TUnknown)
      let fi = self.frames.length() - 1
      for n in names {
        self.frames[fi].set(n, TUnknown)
        self.annos[fi].set(n, false)
      }
    }
    // A named local function gets its own frame: recursive calls inside the
    // body resolve (and are arity-checked) against the local's own signature
    // instead of reporting FUndefinedName. The name is ALSO bound in the
    // enclosing frame by walk's collect_fn_bindings, so run_fn seeds it
    // there and outer calls resolve too. Its returns do not join the
    // enclosing return scan (scan_returns excludes it) and its own return
    // type stays unknown to callers — same policy as EMethodCall above.
    // The "ml" file marker matches run_fn's frames.
    SLocalFunc(name, params, _, body, sp) => {
      self.frames.push(Map([]))
      self.annos.push(Map([]))
      self.vst.push({ func: name, file: "ml", line: sp.start.line, })
      let fi = self.frames.length() - 1
      let ptys : Array[Ty] = []
      let pnames : Array[String] = []
      for p in params {
        ptys.push(ann_to_ty(p.tyann))
        pnames.push(p.name)
      }
      self.frames[fi].set(name, TFunc(name, pnames, ptys, TUnknown))
      for p in params {
        self.frames[fi].set(p.name, ann_to_ty(p.tyann))
        self.annos[fi].set(p.name, !(p.tyann == ""))
      }
      for st in body {
        self.walk_stmt(st)
      }
      let _ = self.vst.pop()
      let _ = self.frames.pop()
      let _ = self.annos.pop()
    }
    // A bare block is a plain statement list in the CURRENT frame — no new
    // scope, same policy as an `if` body.
    SBlock(body) =>
      for st in body {
        self.walk_stmt(st)
      }
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
    param_names: fn_param_names(f),
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
/// The parameter names, parallel to `fn_param_tys`. Read from the SAME loop
/// over `f.params` for the same reason the two are parallel at all: two
/// readers over one list is how the 0.4.18/0.4.20 "name readers drift" lesson
/// repeats, and a name list that drifts from its type list would mis-index
/// every argument.
fn fn_param_names(f : @walk.FnInfo) -> Array[String] {
  let out : Array[String] = []
  for p in f.params {
    out.push(p.name)
  }
  out
}

///|
/// Which parameter does this argument LABEL name? `None` for a positional
/// argument (`label == ""`), and `None` when the name matches nothing — which
/// covers a builtin, whose `TFunc` carries no parameter names at all. The
/// caller falls back to position in both cases, so this can only ever make the
/// check weaker than before, never stronger on bad evidence.
///
/// A FREE function, not a method: it reads nothing from the inference state,
/// and leaving `self` in the signature would be an unused parameter.
fn param_index(pnames : Array[String], label : String) -> Int32? {
  if label == "" {
    return None
  }
  for i, n in pnames {
    if n == label {
      return Some(i)
    }
  }
  None
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
      // A bare block is a plain statement list; its returns belong to the
      // enclosing function's join, same as an `if` body's.
      SBlock(body) => acc = ty_join(acc, self.scan_returns(body))
      _ => ()
    }
  }
  acc
}

///|
/// Run the type lens over a full module (the pipeline entry).
///
/// `extern_iface` is the cross-file symbol table; the type lens consults
/// it after its own builtins so names that live in another file's `.mbti`
/// resolve to `TUnknown` (type) or a single-`TUnknown`-param `TFunc` (value)
/// instead of reporting FUndefinedName. Empty table = single-file behavior.
///
/// `enum_ctors` are constructor names harvested from enum bodies this frontend
/// did not parse. They seed the module frame as `TUnknown` for exactly the
/// same reason a cross-file name does: the name is real and the type is not
/// known, so the lens must neither report it nor infer a shape for it.
pub fn infer_full(
  m : @ast.Module,
  wr : @walk.WalkResult,
  extern_iface : @core.IfaceSymTab,
  enum_ctors : Array[String],
) -> TypeResult {
  let inf = new_infer(wr.fn_bindings, extern_iface, wr.partial)
  for c in enum_ctors {
    if !inf.frames[0].contains(c) {
      inf.frames[0].set(c, TUnknown)
    }
  }
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
          fn_param_names({ name, params, retann, body, span: sp, }),
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

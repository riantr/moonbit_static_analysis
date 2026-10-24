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
  /// per function: params + all body bindings (params first), PARALLEL to
  /// `fns` — indexed by position, NOT keyed by name.
  ///
  /// KEYED BY NAME WAS THE BUG, and it cost a corpus. MoonBit allows two
  /// top-level functions of the same name when `#cfg` gates them for different
  /// platforms, and `Lexer::lex_attribute` emits no token for an attribute, so
  /// both variants are analysed together by design. A `Map` keyed by `f.name`
  /// let the SECOND overwrite the FIRST, and pass 3 then bound every function
  /// of that name to the last one's parameters:
  ///
  ///     pub fn g(w : Int, s : Int) -> Int { w + s }
  ///     pub fn g(w : Int) -> Int { w }
  ///
  /// reported `undefined name 's'` in the first body and
  /// `parameter 't' may not be used` in the second. Measured on proton 0.3.4
  /// `window_geometry.mbt:12` and `:13` (`scale_factor_percent`, two `#cfg`
  /// variants of `window_size_in_screen_coordinates`), and reproducible with
  /// no `#cfg` at all — the attribute is only how real code reaches it.
  fn_bindings : Array[Array[Binding]]
  /// structural findings (lens = LStructural)
  findings : Array[@report.Report]
  /// True when the frontend gave up partway through the file. The module
  /// frame is then provably incomplete, so "this name is not bound" is not
  /// evidence of anything. Carried here because the type lens keeps its OWN
  /// frame copy and would otherwise report the same unprovable name from its
  /// own table — three lenses, one rule. See `fn Walker::resolve`.
  partial : Bool
}

///|
/// Constants representable by the folder: the foldFuns subset.
pub(all) enum Const {
  CInt(Int32)
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
    // Past the `Int` bound the literal is a DIFFERENT NODE, and it must not
    // fold. It would fall into the catch-all below and return `None` anyway,
    // which is the right answer — but only by accident, and an accident is not
    // a decision. Written out, so that adding arms below cannot quietly start
    // folding a value this analyzer never read.
    EBigInt => None
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
            // Int/Int is INTEGER division in MoonBit — `7 / 2` is 3, verified
            // by running it, not 3.5. So the comment that used to sit here
            // ("`/` widens to Float at runtime") was simply wrong.
            //
            // The value is still left unfolded on purpose. Folding it is
            // correct and was implemented in 0.4.14, then measured: enabling it
            // changed NOTHING in the emitted findings over 933 files across
            // riantr/snn_mbt, moonbit_doubleML, moonbit_labeler and
            // moonbit_image — byte-identical report streams. No test could
            // kill the change either, so shipping it would have meant claiming
            // a fix with no way to demonstrate it. Deferred until the
            // constant-evaluation layer has observable teeth.
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
  mut assigns : Int32
  mut varuses : Int32
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
  /// True when the frontend gave up partway through this file
  /// (`trusted_line > 0`). On such a file the module frame is provably
  /// incomplete: every top-level declaration after the cut was never read, so
  /// "no visible binding" carries no information. See `fn Walker::resolve`.
  partial : Bool
  findings : Array[@report.Report]
  vst : Array[@core.Frame]
  /// The file under analysis. A local function pushes its own VST frame from
  /// inside the walk, where `walk_module`'s `file` parameter is out of reach;
  /// carrying it here keeps that frame honest instead of dropping provenance.
  file : String
  /// Lines the frontend deliberately did NOT analyse, taken from the skip
  /// markers the parser emitted. A frame containing one of these has a hole
  /// in it, so the conclusions `audit_frame` draws are limited to the
  /// bindings such a hole cannot reach — see `Walker::holes_in` and
  /// `hole_can_reach`.
  unread : Array[@core.Span]
}

///|
fn new_walker(
  extern_iface : @core.IfaceSymTab,
  partial : Bool,
  file : String,
  unread : Array[@core.Span],
) -> Walker {
  Walker::{
    frames: [Map([])],
    orders: [[]],
    builtins: builtin_table(),
    extern_iface,
    partial,
    findings: [],
    vst: [],
    file,
    unread,
  }
}

///|
/// Names a file may use without importing anything. The table used to hold
/// three entries — `print`, `len`, `abs` — and no type names at all, so
/// `Map([])` in expression position reported "no visible binding for 'Map'".
/// The list now lives in `@core` because the `.mbti` frontend needs the same
/// answer and the two had drifted apart.
fn builtin_table() -> Map[String, Bool] {
  let m : Map[String, Bool] = Map([])
  for n in @core.ambient_names() {
    m.set(n, true)
  }
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
/// 0462 -- stop treating a name as a PARAMETER from the point a `let` shadows it.
///
/// The measured shape, on `moonbitlang/async 0.22.4
/// src/internal/gzip_internal/encoder.mbt:148-156`:
///
///     produced : Int,                    // the parameter
///     ...
///     let mut produced = produced        // a NEW binding, shadowing it
///     produced = self.push_byte(...)     // assigns the SHADOW
///
/// and it settled against the toolchain rather than being inferred, because the
/// discriminator is an ASYMMETRY between two programs:
///
///     let mut p = p; p = 5; p     ->  moon check: 0 errors
///     p = 5; p                    ->  moon check: 1 error
///
/// Assigning an unshadowed immutable parameter is ILLEGAL, so the assignment in
/// the first program cannot be reaching the parameter. Reporting
/// `parameter 'produced' changed by assignment` there is a false positive, and
/// it was the last one between async and `actionable = 0`.
///
/// WHY IT LIVES HERE AND NOT IN `bind`. `bind` cannot tell a `let` from an
/// assignment target, a `for` binder or a destructuring name -- all four arrive
/// as a non-parameter `Binding` with the same name -- and treating those as
/// shadowing deletes the very finding the lens exists for. An attempt did
/// exactly that and two tests said so: "a bare-name assignment to a parameter is
/// still a rebinding" and "an underscore-prefixed parameter changed by
/// assignment still reports". So this is called from the `SLet` arm only.
///
/// ORDERING WAS WRONG AND THE GATE CAUGHT IT. This comment used to claim that
/// clearing the flag must happen BEFORE the initialiser is walked, because
/// `let mut produced = produced` READS the parameter on the right-hand side and a
/// later entry would leave the parameter at `varuses == 0`, firing `FUnusedParam`
/// on the same line. Gate 0462's M2 reverses the order and 684/684 stayed green,
/// including a test written specifically to catch it -- an initialiser that shadows
/// the same name itself, `let mut produced = if produced > 0 { let produced = 1
/// ... }`, which is the shape that should have separated the two orders.
///
/// The reason the argument was wrong is one line: `unshadow_param` COPIES
/// `assigns` and `varuses` out of the entry it finds and writes them back with
/// `param` cleared. Reading the parameter after the walk gives
/// `(param: true, a, v+1)` and writing it back gives `(param: false, a, v+1)`;
/// clearing first gives `(param: false, a, v)` and the walk then makes it
/// `(param: false, a, v+1)`. The same fields either way, so the order is not
/// load-bearing and the original reasoning described a REPLACEMENT where the code
/// performs a field-wise update.
///
/// What IS load-bearing is the ARM, not the order: `bind` cannot tell a `let` from
/// an assignment target, a `for` binder or a destructuring name -- all four arrive
/// as a non-parameter `Binding` with the same name -- and demoting there deleted
/// the very finding the lens exists for. An attempt did exactly that and two
/// existing tests said so.
///
/// WHAT THIS COSTS, stated rather than hidden. A `let` that shadows a parameter
/// WITHOUT reading it -- `fn f(x : Int) -> Int { let mut x = 5; x }` -- now
/// suppresses that parameter's `FUnusedParam`. It is a false NEGATIVE, it needs a
/// `let` that reuses the parameter's own name without touching it, and telling
/// the two apart would mean reading the initialiser before deciding, which is
/// what the flag ordering above deliberately does not do.
fn Walker::unshadow_param(self : Walker, name : String) -> Unit {
  let fi = self.frames.length() - 1
  let frame = self.frames[fi]
  match frame.get(name) {
    Some(e) =>
      if e.param {
        frame.set(name, {
          param: false,
          assigns: e.assigns,
          varuses: e.varuses,
          decl_span: e.decl_span,
        })
      }
    None => ()
  }
}

///|
/// Whether `name` resolves in any frame. Used only to avoid rebinding a name
/// the module already declared — a real declaration must win over a harvested
/// enum constructor of the same name, or the enum's (entirely unknown) shape
/// would silently replace the function's real signature.
fn Walker::is_bound(self : Walker, name : String) -> Bool {
  for i in 0..<self.frames.length() {
    if self.frames[i].contains(name) {
      return true
    }
  }
  false
}

///|
/// Record a read of `name`, or report that nothing visible binds it.
///
/// The finding is gated on `partial`, and the gate is the point. When the
/// frontend gave up partway through the file, the module frame is missing
/// every top-level declaration after the cut — and a use of one of those looks
/// exactly like a use of a name that does not exist anywhere. A forward
/// reference to a `fn` defined further down the file is ordinary code, and the
/// scanner reported it as a defect:
///
///    fn render(...) -> String {
///      ...
///      pick_files(verdicts, max)   <- line 73, before the cut
///    }
///    ...
///    fn pick_files(...) { }       <- line 108, in the unread tail
///
/// reported `73:26 no visible binding for 'pick_files'` on code `moon check`
/// accepts with 0 errors. `truncated_fn` already refuses the frame audit of the
/// one cut function for the same reason; this is the module-frame version, and
/// the module frame is the outermost one, so it is the frame most likely to be
/// incomplete. The finding stays exactly as loud on a whole file.
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
    !self.partial &&
    // An `@`-prefixed name is an import alias, not a binding in this file
    // — the same reason a method-call receiver is skipped when
    // `is_qualifier()`. `@core` reaching resolve through a field-chain
    // base is correct code reporting as undefined.
    !name.has_prefix("@") &&
    !self.builtins.contains(name) &&
    !self.extern_iface.has_type(name) &&
    !self.extern_iface.has_value(name) &&
    // A qualified path whose TAIL is bound is a real name: `Layer::ReLU` is a
    // unit enum variant, and the harvest binds `ReLU` but not the whole path.
    // Without this, every unit variant read in value position was reported as
    // undefined while the payload variants beside it were silent.
    !self.tail_bound(name) {
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
/// True when the last segment of a qualified `name` is bound somewhere.
///
/// Only consulted once the whole path has failed to resolve, so this can never
/// turn a resolvable path into an unresolved one. See `@core.path_tail` for why
/// a unit enum variant lands in this situation at all.
fn Walker::tail_bound(self : Walker, name : String) -> Bool {
  let tail = @core.path_tail(name)
  if tail == "" || tail == name {
    return false
  }
  if self.builtins.contains(tail) ||
    self.extern_iface.has_type(tail) ||
    self.extern_iface.has_value(tail) {
    return true
  }
  let mut i = self.frames.length() - 1
  while i >= 0 {
    match self.frames[i].get(tail) {
      Some(_) => return true
      None => i -= 1
    }
  }
  false
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
/// The regions the frontend chose NOT to analyse that fall inside one
/// function's extent `sp`.
///
/// This is the second half of `truncated_fn`'s argument, and it exists because
/// a skip is not a read failure. A parse failure moves `first_error_line` and
/// names the one function it could have cut; a `match`, a `try`, or a fn
/// literal is a DECLARED scope limit — it moves no boundary, it leaves the
/// rest of the file readable, and it cost the file nothing on the coverage
/// counter. But it still leaves a hole inside whatever function encloses it.
///
/// Overlap is by LINE range against the function's full extent, which is why
/// the 5th field of `SFunc` / `SLocalFunc` is the closing brace and not the
/// header. A skip on a line outside every function (a top-level `test` block,
/// a struct declaration) is in no function's list, and a `partial` walk is
/// unaffected — the two are independent guards on independent facts.
///
/// 0501. This used to be a Bool named `audit_suppressed`, and the BOOL is what
/// made the suppression a blanket: one region anywhere in the function
/// switched off EVERY conclusion the frame could support, so a function with a
/// `match` at its end lost the unused-local verdict on a binding declared at
/// its top. The LIST is what lets the decision be made per binding — see
/// `hole_can_reach`.
///
fn Walker::holes_in(self : Walker, sp : @core.Span) -> Array[@core.Span] {
  let out : Array[@core.Span] = []
  for t in self.unread {
    if t.start.line >= sp.start.line && t.start.line <= sp.end.line {
      out.push(t)
    }
  }
  out
}

///|
/// Could one of these regions have READ this binding?
///
/// A region can only read a binding that was already in scope when the region
/// began. The region's own EXTENT is the threshold, and the END of it is the
/// side that matters, because a region's span can cover code that WAS read:
/// the `if` CONDITION and the `match` SUBJECT are parsed, and only the
/// branches and the arms are not. A binding declared inside that read part is
/// in scope for the unread part, so the threshold cannot be the region's
/// START.
///
/// The rule is therefore: a binding declared after a region's extent ENDS was
/// not in scope when the region was skipped, so nothing inside it could have
/// referred to that binding, and the binding is safe to judge.
///
/// The LAMBDA is the case that makes the end line the only sound choice. Its
/// region's span is the head token, one line, while its body runs on to later
/// lines — but a binding declared inside that body was never walked, because
/// the body was never read, so a binding the walker DID walk is either before
/// the head or after the body. Either way it is outside the region's reach.
///
/// => 判据: A NARROWING IS ONLY SOUND IF IT CANNOT JUDGE A BINDING THAT AN
/// UNREAD REGION MIGHT HAVE READ. The question "could this region have read
/// this binding" is answered by the region's GEOMETRY — where it ended — and
/// not by a guess about what it contains, because what it contains is exactly
/// what nobody read.
///
fn hole_can_reach(e : Entry, holes : Array[@core.Span]) -> Bool {
  for h in holes {
    if e.decl_span.start.line <= h.end.line {
      return true
    }
  }
  false
}

///|
/// True for a binding name the language itself treats as a DISCARD: the bare
/// `_`, and any name STARTING with one.
///
/// This was `_`-exact until 0.4.13, on the stated reasoning that "a name is
/// not a discard pile" — but that was an argument, not a measurement, and the
/// toolchain disagrees. Probe (0.4.13), all in one file so one run settles it:
///
///     fn is_known(_f : Int) -> Bool { false }
///     let (count, _classes) = refine()
///     let (c2, _ok3) = refine()
///     let (c3, plain) = refine()      <- the control: NOT underscore-prefixed
///
/// `moon check` warns on `plain` and on nothing else — so the `_` prefix is
/// the language's own discard convention, for parameters and destructured
/// locals alike, and reporting `_f` / `_classes` / `_ok3` was this analyzer
/// contradicting a rule it had never checked. The control matters: without it
/// the probe would also have passed on a compiler that warns about nothing.
///
/// Measured on riantr/pyroduct 0.1.29: 2 of the 5 actionable findings left
/// after 0.4.12 were exactly this — `_classes` in `src/algebra.mbt` (`let
/// (count, _classes) = refine()`, the second half intentionally unused) and
/// `_f` in `audit/mbti.mbt` (`fn is_known_iface(_f : Report)`, a parameter
/// kept for signature shape and deliberately unread).
///
/// `FParamChanged` is deliberately NOT gated on this: an underscore-prefixed
/// name that is assigned is still being mutated, which is a different question
/// from whether it was ever read.
fn is_discard_name(n : String) -> Bool {
  n.has_prefix("_")
}

///|
/// Put `name` in the current frame WITHOUT putting it in the audit list.
///
/// `bind` does both, and the second half is what makes this a separate
/// function. A name that reaches `orders[fi]` is examined by `audit_frame`,
/// which reports a non-parameter binding with no reads as
/// `FUnusedLocal` — so a catch pattern's constructor heads would each be
/// reported as an unused local. `catch Some({ x })` binds `x`; `Some` is a
/// variant, not a variable, and warning about it would be the analyzer
/// contradicting the compiler on the language's own spelling.
///
/// So these names are resolvable and countable as READS, and are not
/// themselves auditable. That is also the direction the superset in
/// `Parser::parse_catch_pattern` needs: a name that binds when it should not
/// costs silence, and a name that fails to bind when it should costs a false
/// `no visible binding` on correct code.
///
/// An existing binding WINS and is left alone, exactly as in `bind` — a
/// parameter named `e` must keep reporting as a parameter.
fn Walker::bind_pattern(self : Walker, name : String, sp : @core.Span) -> Unit {
  let fi = self.frames.length() - 1
  let frame = self.frames[fi]
  if !frame.contains(name) {
    frame.set(name, { param: false, assigns: 0, varuses: 0, decl_span: sp, })
  }
}

///|
/// Audit a function frame on exit (usage accounting for locals).
///
/// Every finding here is function-scoped, so the caller skips this entirely
/// for the one function a read failure could have truncated — see
/// `truncated_fn` for why a positional boundary filter cannot do it.
///
/// 0501. The frame audit is no longer skipped WHOLE when the function contains
/// an unread region. It used to be: `audit_suppressed` was a single Bool over
/// the function's extent, so one `match` anywhere switched off every
/// conclusion the frame could support.
///
/// The three findings do not depend on the unread region equally:
///
///   FParamChanged  an OBSERVED assignment. A region that was not read cannot
///                  un-observe it, so this conclusion does not depend on the
///                  region at all. It is left exactly as it was anyway: the
///                  corpora produce none, and a change that cannot be
///                  measured is a change that cannot be shown.
///   FUnusedParam   a parameter is in scope for the WHOLE body, so any region
///                  in this function can read it. Unchanged: suppressed while
///                  a region exists.
///   FUnusedLocal   a local is in scope only from its own declaration
///                  onwards, so only a region that ENDS while the local is
///                  already dead can hide a read of it. This is the one the
///                  narrowing reaches, and `hole_can_reach` is all of it.
fn Walker::audit_frame(self : Walker, sp : @core.Span) -> Unit {
  let fi = self.frames.length() - 1
  let holes = self.holes_in(sp)
  for n in self.orders[fi] {
    match self.frames[fi].get(n) {
      Some(e) =>
        // A discard name is exempt from both USAGE findings: it exists to be
        // discarded (`for k, _ in`, `let _ = f(x)`, `_classes` in a tuple
        // destructuring), and warning on the language's own spelling is the
        // analyzer contradicting the compiler. See `is_discard_name` for the
        // probe that settled the prefix question.
        if e.param {
          if holes.length() == 0 {
            if e.assigns > 0 {
              self.findings.push(@report.Report::{
                family: @core.FParamChanged,
                lenses: [@core.LStructural],
                message: "parameter '\{n}' changed by assignment",
                span: e.decl_span,
                vst: @core.snapshot_vst(self.vst),
              })
            }
            if e.varuses == 0 && !is_discard_name(n) {
              self.findings.push(@report.Report::{
                family: @core.FUnusedParam,
                lenses: [@core.LStructural],
                message: "parameter '\{n}' may not be used",
                span: e.decl_span,
                vst: @core.snapshot_vst(self.vst),
              })
            }
          }
        } else if e.varuses == 0 && !is_discard_name(n) {
          if !hole_can_reach(e, holes) {
            self.findings.push(@report.Report::{
              family: @core.FUnusedLocal,
              lenses: [@core.LStructural],
              message: "local variable '\{n}' assigned but may not be used",
              span: e.decl_span,
              vst: @core.snapshot_vst(self.vst),
            })
          }
        }
      None => ()
    }
  }
}

///|
fn Walker::walk_expr(self : Walker, e : @ast.Expr) -> Unit {
  match e.kind {
    EName(n) => self.resolve(n, e.span)
    // Literals have nothing to resolve. A literal too large for `Int` is a
    // distinct node for a reason: a sentinel VALUE would be folded as a
    // number, so `const_eval` would return a wrong number instead of "I do
    // not know". See `EBigInt` in `@ast`.
    EBigInt => ()
    EList(elems) =>
      for x in elems {
        self.walk_expr(x)
      }
    EUnary(_, a) => self.walk_expr(a)
    EBin(_, a, b) => {
      self.walk_expr(a)
      self.walk_expr(b)
    }
    ECall(name, args, _) => {
      // A `::` path is not a binding in this file. `parse_postfix` flattens
      // `@debug.Repr::opaque_(v)` into ECall("@debug.Repr::opaque_", ...), and
      // that string resolves against nothing: `opaque_` is a member of `Repr`,
      // and `Repr` is a member of `@debug`. Same rule as the field and method
      // names below — a member of a type is not a binding in the file.
      //
      // This is not a corner case. It was 27 of the 64 undefined-name findings
      // on moonbitlang/core, all on code `moon check` accepts with 0 errors.
      if !name.contains("::") {
        self.resolve(name, e.span)
      }
      for a in args {
        self.walk_expr(a)
      }
    }
    // The receiver is an evaluated expression and MUST be read:
    // `out.write_string(s)` evaluates `out`. Skipping it would make a local
    // that exists only to be written to look unused — the same defect the
    // field-write path documents at `walk_target`.
    //
    // The method NAME is not resolved, for the same reason a field name is
    // not: it is a member of the receiver's type, not a binding in this file.
    //
    // One exception, and it is not cosmetic: `@alias.f(...)` is a qualified
    // call, not a call on a variable. `@core` is a package, so resolving it
    // would report `no visible binding for '@core'` on perfectly good code.
    EMethodCall(base, _, args, _) => {
      if !base.is_qualifier() {
        self.walk_expr(base)
      }
      for a in args {
        self.walk_expr(a)
      }
    }
    // A `..` CHAIN LINK, walked exactly as a method call is, and for the same two
    // reasons: the receiver is an evaluated expression -- so a name read only there
    // counts, and `output..write(name)` being a use of `output` is the same
    // half-vanishing defect `ECatch` and `EComp` were built to stop -- and a
    // qualifier receiver is a package rather than a binding.
    //
    // The method NAME is not resolved, for the `EMethodCall` reason: it is a member
    // of the receiver's type, not a name in this file.
    EDotDot(base, _, args, _) => {
      if !base.is_qualifier() {
        self.walk_expr(base)
      }
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
    EStruct(_, fields) =>
      // The PATH is a type name, not a binding: `Infer::{ ... }` opens the
      // definition of `ty_of` in this analyzer's own source, and resolving
      // the path would report the analyzer on itself. Only the field VALUES
      // are evaluated. A shorthand field is stored as (name, EName(name)) —
      // the value is a real expression, so the shorthand still counts as a
      // use of the name.
      for f in fields {
        let (_, v) = f
        self.walk_expr(v)
      }
    // A block in EXPRESSION position, `let x = { .. }`. The statements are the
    // whole point: `let y = 1` inside the block is a real binding, and skipping
    // the body would leave the tail reading names nothing declares -- which is
    // the 0467b defect arriving from a new direction, an invented finding on
    // code `moon check` compiles.
    //
    // CURRENT frame, no new scope -- the SAME rule `SBlock` gets at walk_stmt
    // (walk.mbt:951) and at the collectors (walk.mbt:1189, 1301). A new frame
    // here would make the block's own bindings unreadable to the `let` that
    // consumes its value, which is the mirror image of the bug above.
    EBlock(body) =>
      for st in body {
        self.walk_stmt(st)
      }
    // 0469. A `match`. The SUBJECT is real analysed code: `match compute(x) { .. }`
    // still counts `compute` and `x` as reads. Without this arm the walk would lose
    // them and an undefined name used only as a match subject would stop being
    // reported -- a true positive traded for the absence of a false one.
    //
    // 0502. THE ARMS ARE WALKED, and they are walked in the SAME frame as the
    // enclosing function, for the same reason `ECatch` walks its arms there: the
    // frame is flat and not flow-scoped, so the flat frame can only ever make a
    // name visible EARLIER than it should be. A match arm's pattern names are
    // used only inside that arm's own body, so the direction of the error is
    // fixed -- it is silence where a false finding would be.
    //
    // THE BINDINGS ARE BOUND BEFORE THEY WALK, and through `bind_pattern` rather
    // than `bind`: a pattern's names are not auditable, and a constructor head
    // (`Some(x)`) is not a variable at all. See `Walker::bind_pattern`.
    //
    // AN EMPTY ARM LIST IS A `lexmatch`, whose arms were not read. The subject is
    // walked and nothing else, exactly as before.
    EMatch(subject, arms) => {
      self.walk_expr(subject)
      for arm in arms {
        for b in arm.bindings {
          if b != "" {
            self.bind_pattern(b, arm.span)
          }
        }
        // A `with` CONSTRAINT READS the names of its right-hand side. Measured on
        // moonbitlang/core `builtin/option.mbt:50` --
        //
        //     Some(t) | (None with t = default) => t
        //
        // `default` is the parameter of `unwrap_or` and the only mention of it
        // in the function. A reader that swept the constraint up as pattern
        // bindings would leave it with no read and report
        // `parameter 'default' may not be used`.
        //
        // The constraint's LEFT-HAND side is a pattern binding and rides in
        // `arm.bindings`, so it is bound above and is not auditable.
        for r in arm.reads {
          self.resolve(r, arm.span)
        }
        // THE GUARD IS WALKED BEFORE THE BODY, because it comes first in the
        // source and because it READS the arm's own bindings: `Some(v) if v > 0
        // => v` reads `v` twice. An arm whose guard was not walked would report
        // a live binding as dead.
        match arm.cond {
          Some(g) => self.walk_expr(g)
          None => ()
        }
        for st in arm.body {
          self.walk_stmt(st)
        }
      }
    }
    ETuple(elems) =>
      for x in elems {
        self.walk_expr(x)
      }
    ERange(a, b) => {
      self.walk_expr(a)
      self.walk_expr(b)
    }
    // A REGEX LITERAL, `re"^a"`. A LEAF: the pattern text is carried, not
    // analysed, and there is nothing inside it to walk.
    ERegex(_) => ()
    // A REGEX CAPTURE, `re"..." as name`. The base is walked and the name is
    // BOUND, exactly as an `is` binding is: `bind_pattern` and not `bind`,
    // because a capture that is never read is legal MoonBit and must not be
    // reported as an unused local.
    EAsBind(base, name) => {
      self.walk_expr(base)
      self.bind_pattern(name, e.span)
    }
    // `pair.0`: only the base is read; the position is a column, not a
    // variable — the same rule as EField's name above.
    ETupleField(base, _) => self.walk_expr(base)
    // An `is` test: the base is read, and a pattern binding binds in the
    // CURRENT frame for the uses that follow (`p.peek() is TName(tag) &&
    // tag.has_prefix("@")` resolves `tag` on the rhs because EBin walks
    // lhs before rhs, and SIf walks its condition before its branches).
    // A use BEFORE the test is the accepted known limitation: the frame is
    // flat, not flow-scoped.
    EIs(base, bindings) => {
      self.walk_expr(base)
      for b in bindings {
        if b != "" {
          // `bind_pattern`, NOT `bind`. An `is` binding that is never read is
          // LEGAL MoonBit -- `_verify/settle_0444_is_head.ps1`, 9/9: both
          // `if probe() is err { 1 } else { 0 }` and `if opt() is Some(v) { 1 }
          // else { 0 }` compile. `bind` puts the name on the audit list and
          // `audit_frame` then reports `assigned but may not be used`, which on
          // correct code is a false positive.
          //
          // This is the same trade `ECatch` makes for its arm patterns, and it is
          // why the head and the payload can share one `bind_pattern` call: the
          // settle measures BOTH as exempt, so the AST does not have to
          // distinguish them.
          //
          // It became reachable in 0.4.34 rather than being new: before it, a
          // BARE head bound nothing at all, so the only names reaching here were
          // payload names, and this was a pre-existing false positive on
          // `is Some(v)` with `v` unread.
          self.bind_pattern(b, e.span)
        }
      }
    }
    // `base as &Trait`: only the base is walked. The target is a TYPE NAME,
    // not a binding — the same rule that keeps `EStruct`'s path from being
    // resolved, and the reason `Infer::{ ... }` does not report the type's
    // own name as undefined.
    //
    // The operand is walked rather than discarded, and that is the whole
    // reason this arm exists: `fn f(b : Box) -> &Sink { b as &Sink }` reads
    // `b` and nothing else does. An arm that returned without walking would
    // report the parameter as never read — a NEW false positive introduced by
    // the fix, in exchange for removing an old one. The `EComp` lesson, in its
    // exact form: the half that is not walked is the half that vanishes.
    ECast(base) => self.walk_expr(base)
    // `expr catch { p => body }`: the base is the call — read, because its
    // arguments are reads — and then every arm binds its pattern and walks its
    // body.
    //
    // Both halves are walked, and the reason is the same one `ECast` records:
    // the half that is not walked is the half that vanishes. Walking the base
    // alone left the body invisible, which is how `prefix` in moui
    // `macos_native_ime.mbt:437` was reported as never read when its only
    // mention is on line 442 inside the handler.
    //
    // The arms bind BEFORE they walk, in the CURRENT frame, because the frame
    // is flat and not flow-scoped — the same trade `EIs` makes. That is sound
    // here in a way it is not for `EIs`: a catch arm's bindings are used only
    // inside that arm's own body, so the flat frame can only ever make a name
    // visible EARLIER than it should be, and the body that walks with it is
    // the body it belongs to.
    ECatch(base, arms) => {
      self.walk_expr(base)
      for arm in arms {
        for b in arm.bindings {
          if b != "" {
            self.bind_pattern(b, arm.span)
          }
        }
        for st in arm.body {
          self.walk_stmt(st)
        }
      }
    }
    // `noraise { ... }` — the same frame trade as `ECatch`, and for the same
    // reason: the arm's pattern names are used only inside that arm's own body,
    // so a flat frame can only make a name visible EARLIER than it should be.
    //
    // The pattern binds the BASE'S RESULT VALUE (settled by the compiler), not
    // the error, so `bind_pattern` is the right call and not a special case —
    // the mechanism does not care which value arrived, only that the name is
    // visible in the body that uses it.
    //
    // What this fixes is measured, not assumed: `identifier => Ok(identifier)` is
    // the ONLY mention of `identifier` in proton `facade_identity.mbt:100`, and
    // before this arm the block was consumed by `skip_braces`, so the name in its
    // body was invisible AND the bare token `noraise` beside it resolved as an
    // undefined name.
    ENoRaise(base, arms) => {
      self.walk_expr(base)
      for arm in arms {
        for b in arm.bindings {
          if b != "" {
            self.bind_pattern(b, arm.span)
          }
        }
        for st in arm.body {
          self.walk_stmt(st)
        }
      }
    }
    // A string's INTERPOLATED names are real reads, and they are resolved here
    // rather than ignored. `println("k=\{k}")` is the only mention of `k` in
    // the function, and treating the literal as opaque made every such name
    // look unread — the false positive this arm's second field exists to
    // remove, measured on this analyzer's own source (all 8 remaining
    // self-scan findings).
    //
    // The other direction matters just as much: resolving them means a name
    // that does NOT exist inside an interpolation is reported, where before
    // it was invisible. The span is the whole literal because the lexer
    // records names, not their columns — and a finding pinned to the string
    // that contains the reference is honest about where the reader can see it.
    EStr(_, names) =>
      for n in names {
        self.resolve(n, e.span)
      }
    EInt(_) | EFloat(_) | EBool(_) => ()
  }
}

///|
fn Walker::walk_target(self : Walker, target : @ast.Expr) -> Unit {
  match target.kind {
    EName(n) => self.assign_to(n)
    // Writing THROUGH a base is NOT rebinding that base — it is a read.
    // MoonBit structs are references, so `self.inner = 1` mutates the object
    // the parameter points at; the parameter still holds exactly what the
    // caller passed. Counting it as an assignment produced two false
    // positives per write-through:
    //
    //     parameter 'self' changed by assignment (ParamChanged)
    //     parameter 'self' may not be used (UnusedParam)
    //
    // The first is wrong by construction ("no longer holds the value the
    // caller passed" — it does), and the second was the count of an
    // assignment made before the base was also walked as a read. Measured on
    // moonbitlang/async: `semaphore.mbt` reports the pair for all three of its
    // `with fn set_index(self, value)` impls.
    //
    // What survives is the READ, and it is load-bearing: `self.pos += 1` in a
    // state machine is written this way everywhere, and the base must count
    // as used or every such parameter reports unused.
    //
    // The companion consequence: a parameter that is ONLY ever written
    // through is no longer reported at all. That is the honest outcome — the
    // signature is load-bearing for the call, the analyzer cannot see
    // through the reference, and silence beats a claim it cannot support.
    EField(base, _) => self.walk_expr(base)
    EIndex(base, idx) => {
      self.walk_expr(base)
      self.walk_expr(idx)
    }
    // `pair.0 = v`: the position is a column, not a variable — same rule.
    ETupleField(base, _) => self.walk_expr(base)
    _ => ()
  }
}

///|
fn Walker::walk_stmt(self : Walker, s : @ast.Stmt) -> Unit {
  match s.kind {
    SExpr(e) => self.walk_expr(e)
    // The tail expression is walked exactly like the expression statement it
    // used to be. Nothing about BINDINGS changes -- only what the other two
    // lenses do with the value afterwards, which is the whole reason it is its
    // own node rather than a flag on `SExpr`.
    STail(e) => self.walk_expr(e)
    SLet(n, _, init) => {
      // 0462 -- BEFORE walking the initialiser, so the right-hand side of
      // `let mut p = p` still counts as a read of the entry it finds. See
      // `unshadow_param` for why the order is load-bearing.
      self.unshadow_param(n)
      self.walk_expr(init)
    }
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
    // `loop nobreak { .. }` -- the loop, then the block that runs when it
    // finishes without a `break`.
    //
    // BOTH ARE WALKED, and the block's statements are ordinary reads. That is
    // the whole reason the node exists rather than the parser consuming the block
    // and discarding it: `nobreak` bodies contain real code, and a name read only
    // in one is a read. The block runs AFTER the loop, not per iteration, but for
    // binding purposes both orders give the same frame contents, and splicing the
    // statements into the loop body would have modelled an execution order this
    // analyzer does not make a claim about anywhere else.
    SNoBreak(loop_stmt, block) => {
      self.walk_stmt(loop_stmt)
      for st in block {
        self.walk_stmt(st)
      }
    }
    SReturn(e) =>
      match e {
        Some(x) => self.walk_expr(x)
        None => ()
      }
    // The payload IS walked. `raise E(undeclared_fn)` must still report the
    // undefined function -- dropping it here would make the raise path the one
    // place in the language where a real defect goes silent.
    SRaise(e) =>
      match e {
        Some(x) => self.walk_expr(x)
        None => ()
      }
    // The carried VALUES are walked. `continue m >> 60, i + 1` carries two
    // expressions, and a name inside one is a real name: `continue
    // undefined_name` must still report. Before 0495 the values were SIBLING
    // STATEMENTS, and the walk treated them as statements -- which is how they
    // came to be read as unreachable code.
    SBreak(vals) =>
      for v in vals {
        self.walk_expr(v)
      }
    SContinue(vals) =>
      for v in vals {
        self.walk_expr(v)
      }
    SFunc(_, _, _, _, _) => ()
    SLetDestruct(_, init) => self.walk_expr(init)
    // A local function owns a scope exactly like a top-level one. It is
    // walked HERE, inside the enclosing walk, because pass 3 of walk_module
    // only knows the top-level list. Its own name is NOT bound in the inner
    // frame on purpose: a self-call must resolve against the ENCLOSING
    // binding, or a recursive local whose only caller is outside itself
    // would be reported unused by its own frame audit.
    SLocalFunc(name, params, _, body, sp) => {
      let lf : FnInfo = { name, params, retann: "", body, span: sp, }
      let bs = collect_fn_bindings(lf)
      self.push_frame()
      for b in bs {
        self.bind(b)
      }
      self.vst.push({ func: name, file: self.file, line: sp.start.line, })
      for st in body {
        self.walk_stmt(st)
      }
      // Same guard as pass 3, and for the same reason: `sp` here is the local
      // function's whole extent, so a `match` inside ITS body puts a hole in
      // ITS frame the same way. A local function is not reachable through
      // `fns` and so was never covered by `truncated_fn` either.
      //
      // 0501. The audit is no longer skipped when the frame has a hole: it
      // decides each binding against the holes that can reach it.
      self.audit_frame(sp)
      let _ = self.vst.pop()
      self.pop_frame()
    }
    // A bare block is a plain statement list in the CURRENT frame — no new
    // scope, the same treatment SIf bodies get. The binding analysis is not
    // flow-scoped anywhere else either, and a new frame here would make
    // bindings declared in the block unreadable to the statements after it.
    //
    // MEASURED WRONG AGAINST THE TOOLCHAIN, 2026-10-17, and recorded here rather than
    // left as a design choice. A block scopes LEXICALLY in MoonBit. `moon check`
    // REJECTs both of these with [4021] "The value identifier is unbound":
    //
    //   fn f() -> Int { let x = { let y = 1  y };  x + y }   y unbound at line 6
    //   fn h(c : Bool) -> Int { if c { let z = 1  z };  z }   z unbound at line 14
    //
    // and this analyzer reports NEITHER. So the paragraph above describes an intentional
    // approximation that is measurably wrong in the direction of a false NEGATIVE.
    //
    // 0468 found this while testing `EBlock`, which copies this rule on purpose (see
    // `EBlock` in `walk_expr` and walk.mbt:669). It is NOT a 0468 regression and it was
    // deliberately not fixed here: `SBlock` covers every `if` arm, loop body and bare
    // block on every corpus, so teaching blocks to scope moves the whole corpus-wide
    // finding count and is its own increment.
    //
    // => The argument "a new frame here would make bindings declared in the block
    // unreadable to the statements after it" is TRUE of THIS analyzer and FALSE of
    // MoonBit, which scopes the other way. It is a reason the rule is wrong, not a
    // reason it is right. Pinned both ways in `pipeline_0468_test.mbt`.
    SBlock(body) =>
      for st in body {
        self.walk_stmt(st)
      }
    // A C-style `for`'s UPDATE clause. Its statements are ordinary reads --
    // `i = i + 1` READS `i` -- and they used to be walked as part of the loop
    // body, which is where they still are: the node changed their SHAPE, not
    // their place.
    //
    // The binding collector below does not need an arm for it: the clause may
    // only ASSIGN the loop's declared names (settled, `_verify/
    // settle_0494_parse_backlog.ps1` row `b3_control_for_update_binds_a_new_name`),
    // and an assignment declares nothing.
    SForUpdate(updates) =>
      for u in updates {
        self.walk_stmt(u)
      }
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
fn as_array(a : Array[@ast.ElseIf], from : Int32) -> Array[@ast.ElseIf] {
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
/// Add one binding, skipping a duplicate.
fn bind_add(bs : Array[Binding], b : Binding) -> Unit {
  if !bs.contains(b) {
    bs.push(b)
  }
}

///|
/// 0467b -- the expression side of the collector's gap. Only `ECatch` and `ENoRaise`
/// carry a STATEMENT LIST inside an expression, so those two are the whole of it; every
/// other `E*` variant is inert as far as binding collection goes.
///
/// THAT SENTENCE WAS TRUE AND IS NOW FALSE TWICE OVER, and both corrections are 0468.
/// It was the reasoning that let this function grow a `_ => ()` catch-all and stop.
///
///   1. `EBlock` also carries a statement list -- it is a block, that is what it is.
///   2. An expression that merely CONTAINS one does not need a new variant. An
///      `ECall`'s arguments are expressions, so `{ let copy = ..; copy }` passed as
///      `Bytes::from_array({ ... })` is reachable without any new node at all.
///
/// The second one cost two false `no visible binding for 'copy'` findings on
/// `riantr/moonbit_image 0.3.7 gif.mbt:853,855` before it was found, and the first
/// cost five on `png.mbt:113..124`. => 判据: a `_ => ()` arm is a CLAIM that nothing
/// else in the type matters. Here it was a claim nobody checked, made while the type
/// was smaller, and it stayed true-looking for exactly as long as the type stayed small.
///
/// WHY THIS IS TOP-LEVEL AND NOT NESTED IN `collect_fn_bindings`. It and
/// `collect_stmt_bindings` are mutually recursive -- a catch arm body is statements, and
/// a `let` initialiser is an expression, so either can contain the other -- and MoonBit
/// does NOT forward-reference between nested `fn`s. Written as nested functions, the
/// first build failed with `Error: [4021] The value identifier scan_expr is unbound` at
/// every call site inside `scan`. Hoisting both to the top level is the fix, and it is
/// why `bind_add` is here too rather than a closure over `out`.
fn collect_expr_bindings(bs : Array[Binding], e : @ast.Expr) -> Unit {
  match e.kind {
    ECatch(_, arms) =>
      for arm in arms {
        collect_stmt_bindings(bs, arm.body)
      }
    ENoRaise(_, arms) =>
      for arm in arms {
        collect_stmt_bindings(bs, arm.body)
      }
    // A block in EXPRESSION position, `let x = { let y = 1; y + 1 }`. The
    // `_ => ()` catch-all below would skip the body and the frame would never
    // learn `y` -- so the tail would report a name nothing binds. This arm is
    // the whole reason the node exists rather than collapsing to its tail at
    // parse time.
    EBlock(body) => collect_stmt_bindings(bs, body)
    // 0502. A STRUCT LITERAL's FIELD VALUES, for the same reason `walk_expr`
    // walks them: a field value is an expression, and an expression can carry
    // a binding inside it.
    //
    // The gap was invisible until 0502 read match arms, because a match
    // nested inside a struct-literal field is the shape that puts a binding
    // under a collector that never descends. MEASURED: wzzc-dev/moui 0.1.12
    // `views/text/text_input_apply.mbt:166` --
    //
    //     let next_control = {
    //       composition_cursor: match update.cursor() {
    //         Some(cursor) => {
    //           let start = clamp_int(normalized.start, 0, length)
    //           Some(@core.TextRange::new(start~))
    //         }
    //         None => None
    //       },
    //     }
    //
    // reported `no visible binding for 'start'`. The walk READS the field
    // values, so `start` was read; the COLLECTOR never descended, so the `let
    // start` that binds it never reached the frame. The two halves had
    // drifted apart, and only one of them was wrong.
    //
    // ONLY THE VALUES. The PATH is a type name and is not a binding -- the
    // same rule `walk_expr` applies at its own `EStruct` arm, and the reason
    // `Infer::{ .. }` does not report the analyzer's own type as undefined.
    //
    // => 判据: the collector must reach everything the walker reaches. A
    // construct the walker descends into and the collector does not is a hole
    // whose shape is the construct, and it shows up as a false positive.
    EStruct(_, fields) =>
      for f in fields {
        let (_, v) = f
        collect_expr_bindings(bs, v)
      }
    // 0469. The match SUBJECT, for the same reason `walk_expr` walks it: it is an
    // expression and it can carry a binding inside a `catch` or a block.
    //
    // 0502. And the match ARMS' BODIES, for the reason `ECatch` collects its arms'
    // bodies: a `let` inside an arm body is a real binding, and the pre-pass is
    // what fills the frame (`walk_stmt`'s `SLet` arm never binds anything -- it
    // walks the initialiser).
    //
    // `arm.bindings` is deliberately NOT added here, for the reason `ECatch`'s are
    // not: the walk binds those through `bind_pattern` at the `EMatch` arm of
    // `walk_expr`, and adding them to the pre-pass as well would put them into the
    // frame BEFORE that call, where `bind` is a no-op because it is guarded on
    // `frame.contains` -- which would silently move a pattern name off the binding
    // path `unshadow_param` accounts for.
    EMatch(subject, arms) => {
      collect_expr_bindings(bs, subject)
      for arm in arms {
        // The GUARD's bindings are collected for the same reason the body's are:
        // a `let` inside a guard is a real binding, and the pre-pass is what
        // fills the frame.
        match arm.cond {
          Some(g) => collect_expr_bindings(bs, g)
          None => ()
        }
        // A `with` CONSTRAINT READS names; it does not bind any, so the
        // collector has nothing to do for it.
        collect_stmt_bindings(bs, arm.body)
      }
    }
    // 0468. ARGUMENTS ARE EXPRESSIONS, so a block -- or a `catch`, or anything
    // else that binds -- can sit in one. `Bytes::from_array({ let copy = ..;
    // copy })` in `gif.mbt` is the measured case.
    ECall(_, args, _) =>
      for a in args {
        collect_expr_bindings(bs, a)
      }
    EMethodCall(_, _, args, _) =>
      for a in args {
        collect_expr_bindings(bs, a)
      }
    _ => ()
  }
}

///|
/// Pass 1 for one function: params first, then every binding in the body
/// (findLocals): `let`, bare assignments peeled to the base name, `for`
/// variables. Dead branches are still collected (the binding analysis is
/// not flow-sensitive).
fn collect_fn_bindings(f : FnInfo) -> Array[Binding] {
  let out : Array[Binding] = []
  for p in f.params {
    bind_add(out, {
      name: p.name,
      tyann: p.tyann,
      param: true,
      decl_span: p.span,
    })
  }
  collect_stmt_bindings(out, f.body)
  out
}

///|
/// Every binding a statement list introduces. Top-level for the reason on
/// `collect_expr_bindings`: the two are mutually recursive.
fn collect_stmt_bindings(bs : Array[Binding], stmts : Array[@ast.Stmt]) -> Unit {
  for s in stmts {
    match s.kind {
      // 0467b -- A CATCH ARM'S BODY IS A STATEMENT LIST, AND THE COLLECTOR WAS NEVER
      // TAUGHT IT. `walk_expr` learned `ECatch` and `ENoRaise` long ago and walks
      // `arm.body` there; this pre-pass did not, and it is the pre-pass that fills the
      // frame (`walk_stmt`'s `SLet` arm never binds anything -- it walks the
      // initialiser). So every `let` inside a catch arm was invisible, and every use
      // of it reported `no visible binding`.
      //
      // This is the SAME defect 0443 recorded one level up for `SNoBreak` -- "walk_stmt
      // was taught `SNoBreak` and the COLLECTOR was not, and the compiler is silent
      // about a missing arm in a match that has a catch-all" -- one statement kind
      // further out, and for the same reason nobody noticed: `Walker::resolve` is
      // gated on `!self.partial`, and every file containing one was unread.
      //
      // Measured, not assumed. `moonbitlang/async 0.22.4 src/fs/dir.mbt` in `mkdir`:
      //
      //     let last_path_sep_index = match path.rev_find("/") { .. }   // line 43
      //     let parent = path[:last_path_sep_index].trim_end(chars="/") // line 49
      //     let parent = if @event_loop.platform is Windows { .. }    // line 50
      //     mkdir(parent, permission~, recursive=true, ..)              // line 55
      //
      // reported `49:26 no visible binding for 'last_path_sep_index'` and
      // `55:13 no visible binding for 'parent'` -- two actionable false positives on
      // code `moon check` compiles, from a file that only became readable at 0467
      // (it carried `f : async (String, Array[String]) -> Unit` at line 433).
      //
      // EVERY statement that carries an expression routes through `collect_expr_bindings`,
      // not just `SExpr`. The first version of this fix handled `SExpr` alone and
      // changed nothing measurable -- because `expr catch { .. }` as the last thing in a
      // function is a `STail`, not an `SExpr`, and that is the shape `dir.mbt` writes.
      // A fix on one of the seven positions a construct can appear in is a fix on one
      // of seven.
      //
      // `arm.bindings` is deliberately NOT added here. The walk binds those through
      // `bind_pattern` at the `ECatch` arm of `walk_expr`, and adding them to the
      // pre-pass as well would put `err` into the frame BEFORE that call, where
      // `bind` is a no-op because it is guarded on `frame.contains` -- which would
      // silently move `err` off the binding path `unshadow_param` accounts for.
      // Scanning the bodies is the whole of the gap.
      SExpr(e) => collect_expr_bindings(bs, e)
      STail(e) => collect_expr_bindings(bs, e)
      SReturn(e) =>
        match e {
          Some(x) => collect_expr_bindings(bs, x)
          None => ()
        }
      SRaise(e) =>
        match e {
          Some(x) => collect_expr_bindings(bs, x)
          None => ()
        }
      // ---------------------------------------------------------------------------
      // 0468/0469 MEASURED DEFECT: EVERY NESTED BODY SHARES `bs`.
      //
      // Each arm below passes the SAME `bs` into its body, so a `let` written inside an
      // `if` arm, a `while` body, a `for` body or a bare block outlives the construct and
      // lands in the ENCLOSING function's table. `Infer::run_fn` seeds its frame from
      // that table.
      //
      // THE ORDER THAT TABLE IS SEEDED IN, and this block got it WRONG until 0492. IT
      // USED TO SAY: "`Infer::run_fn` seeds its frame 0 from that table
      // (infer.mbt:816-819) and `declare_sym` is guarded on `frame.contains`, so the
      // FIRST binding for a name wins -- and a flat table makes the INNER one first."
      //
      // BOTH CLAIMS WERE FALSE. `Infer::declare_sym` has NO guard -- it overwrites, so
      // the LAST binding for a name wins -- and it never had one: `git log -S
      // 'frame.contains' -- src/types/infer.mbt` finds no such guard anywhere in the
      // file's history. And `run_fn` does not seed frame 0: it PUSHES a frame and seeds
      // the top one, so the table lands in the function's own scope.
      //
      // 0492 made the rule explicit, and the rule in force now is:
      //
      //   A PARAMETER WINS over a re-binding of the same name, and among body
      //   bindings the LAST wins.
      //
      // The first half was a real defect, and a false NEGATIVE. The walk records an
      // assignment `xs["k"] = "v"` as a re-binding of the base name `xs`, so the table
      // carried a PARAMETER twice, and the second (Unknown) erased the parameter's
      // annotation for the WHOLE function body. `fn h(xs : Array[String]) -> Unit {
      // xs["k"] = "v" }` was reported clean, and `moon check` REJECTS that program.
      //
      // The second half is load-bearing: the table is FLAT across nested scopes, so
      // "last wins" is what keeps the INNER binding from taking over the function.
      //
      // THE FALSE POSITIVE THIS BLOCK DESCRIBED IS NOT IN THE SCAN ANY MORE, and that
      // is a change to the record, measured 2026-10-20: moonbit_labeler 0.2.13 scans
      // 37 files with actionable=0, and not one line mentions `blend_pixel` or
      // `incompatible type`. The CODE is exactly as described below --
      // rasterizer.mbt:1196 writes `let x : Double = ...` inside a `for i` body, 1217
      // binds `x` as a `for` header over an `Int`, 1218 passes it to an `Int` parameter
      // -- so the finding is absent because the type lens's OWN statement walk
      // re-declares each binding as it walks the body that owns it, and the seeded
      // value only survives until the first statement that binds the name.
      //
      //   FALSE NEGATIVE, STILL OPEN, and still the open increment. 0468's
      //   `0468: a block's bindings do not scope (KNOWN FALSE NEGATIVE, pinned)` is
      //   this same frame: `let y` inside a block stayed visible afterwards, where
      //   `moon check` reports [4021] unbound. That one is NOT fixed, and the row is
      //   the pin.
      //
      // => 判据: one mechanism, two directions. A leaked name only becomes a FALSE
      // POSITIVE when something later binds the same name -- which is why this sat
      // latent for so long and why "the blocks do not scope" and "labeler:1218" were
      // filed as two separate items.
      //
      // NOT FIXED HERE. The change is small in this function and large everywhere else:
      // `bs` also seeds the type lens's frame, so removing nested contributions is only
      // safe if the type lens DECLARES each binding as it walks the body that owns it.
      // Every corpus's finding count moves. It is its own increment, and 0468's two rows
      // that PIN this false negative are expected to go red when it lands -- which is what
      // "pinned, not endorsed" was for.
      SWhile(e, body) => {
        collect_expr_bindings(bs, e)
        collect_stmt_bindings(bs, body)
      }
      SFor(v, vsp, e, body) => {
        bind_add(bs, { name: v, tyann: "", param: false, decl_span: vsp, })
        collect_expr_bindings(bs, e)
        collect_stmt_bindings(bs, body)
      }
      SIf(e, then, elseifs, els) => {
        collect_expr_bindings(bs, e)
        collect_stmt_bindings(bs, then)
        for ei in elseifs {
          collect_stmt_bindings(bs, ei.body)
        }
        match els {
          Some(b) => collect_stmt_bindings(bs, b)
          None => ()
        }
      }
      SLet(n, ann, init) => {
        bind_add(bs, { name: n, tyann: ann, param: false, decl_span: s.span, })
        collect_expr_bindings(bs, init)
      }
      // 0502. AN ASSIGNMENT INTRODUCES NO BINDING, and it used to introduce one.
      //
      // The arm this replaces added the assigned name to the scope's bindings.
      // In the scope that DECLARED the name that is a no-op -- `bind` skips a
      // name the frame already holds -- so the arm only ever did something in
      // the one case where it was wrong: an assignment to a name bound in an
      // ENCLOSING scope.
      //
      // MEASURED, and the mechanism is exact. moonbitlang/async 0.22.4
      // `src/process/windows.mbt:105-116`:
      //
      //     let mut segment_start = 0
      //     fn flush(skip : Int) {
      //       if index > segment_start { .. }        // a READ
      //       segment_start = index + skip          // an ASSIGNMENT
      //     }
      //
      // The collector gave `flush` its OWN binding for `segment_start`, so the
      // read inside `flush` counted against that shadowing copy and the
      // enclosing binding kept zero reads. The finding was
      // `local variable 'segment_start' assigned but may not be used` -- on
      // code `moon check` accepts, and on a name that IS read.
      //
      // It reported the finding TWICE, once for each frame that held a copy of
      // the name, and that second copy is the tell: a shadow that the
      // language does not have.
      //
      // THE TOOLCHAIN SETTLED THE LANGUAGE, not the analyzer: a local `fn` CAPTURES
      // the enclosing scope. `moon check` accepts
      //
      //     fn f() -> Int { let mut x = 0  fn g() -> Unit { x = x + 1 }  g()  x }
      //
      // with zero errors, so `x` in `g` IS the enclosing `x` and reading it is
      // a read of the enclosing binding.
      //
      // => 判据: an assignment MUTATES a binding; it does not create one. A
      // scope that collects an assignment target as a binding of its own
      // invents a shadow the language does not have, and every read that
      // crosses the boundary is then counted against the shadow.
      SAssign(_, rhs) => collect_expr_bindings(bs, rhs)
      // `loop nobreak { .. }` -- BOTH halves are descended into, and the loop
      // half is the one that matters here: its `for` BINDER is collected by the
      // `SFor` arm above, so wrapping the loop without descending would drop
      // `for x in xs` on the floor and report its own binder as unbound.
      //
      // That is not hypothetical. The first run of the 0443 tests failed with
      // `no visible binding for 'x'` and `no visible binding for 'i'` -- not
      // `no visible binding for 'nobreak'`, which is the finding this increment
      // set out to remove. `walk_stmt` was taught `SNoBreak` and the COLLECTOR
      // was not, and the compiler is silent about a missing arm in a match that
      // has a catch-all.
      SNoBreak(loop_stmt, block) => {
        collect_stmt_bindings(bs, [loop_stmt])
        collect_stmt_bindings(bs, block)
      }
      // 0502. THE INITIALISER IS COLLECTED, and it was NOT: `SLetDestruct(names, _)`
      // threw the initialiser away, so a `let (a, b) = { let p = ..; p }` never
      // learned `p`, and the tail of that block reported
      // `no visible binding for 'p'` -- on code `moon check` compiles.
      //
      // `walk_stmt` WALKS the initialiser, so the names inside it are read,
      // and `walk_stmt` binds nothing: the PRE-PASS is what fills the frame,
      // and `SLet` right above has always collected its own initialiser. The
      // two halves had drifted apart, which is the 0467b defect arriving from
      // a new direction -- the same shape as the `SNoBreak` arm above.
      //
      // MEASURED: moonbitlang/core
      // `internal/regex_engine/shared_types/rechar_set/rechar_set.mbt:202,214`
      // -- `let (lo, l) = { let p = lo - 1; if p >= lo { .. } else { .. } }` --
      // two false positives, both inside a match arm body, which 0502 is the
      // first release to read.
      //
      // => 判据: the collector and the walker must agree about what a
      // statement's initialiser binds. One of them reading it and the other
      // dropping it is not a modelling choice; it is a hole with a name.
      SLetDestruct(names, init) => {
        for n in names {
          bind_add(bs, { name: n, tyann: "", param: false, decl_span: s.span, })
        }
        collect_expr_bindings(bs, init)
      }
      // A local function's OWN name is a binding of the ENCLOSING scope —
      // its calls there must resolve, and a self-call resolves through it
      // too (the inner frame deliberately does not hold the name). Its
      // BODY is not collected here: it owns a frame of its own, walked at
      // the SLocalFunc arm of walk_stmt.
      SLocalFunc(n, _, _, _, _) =>
        bind_add(bs, { name: n, tyann: "", param: false, decl_span: s.span, })
      // A bare block is a plain statement list: its bindings join the
      // enclosing frame, same as an `if` body's.
      SBlock(body) => collect_stmt_bindings(bs, body)
      _ => ()
    }
  }
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
///
/// `trusted_line` is the line of the first genuine read failure, or 0 when
/// the whole file was understood. It is NOT a filter on findings — the
/// scanner does that — because one class of finding cannot be filtered by
/// position. See `fn Walker::audit_frame`.
///
/// `enum_ctors` are constructor names harvested from `enum` bodies the parser
/// skipped, plus the ones `.mbti` files declared. They are module-level VALUES
/// and their names are visible to every function in the file; without them
/// writing one reads as an unbound name, which is the analyzer's blindness
/// showing up as a defect in the code. Only the NAMES are collected — no
/// shape, no arity, nothing inferred from the payload.
///
/// `unread` are the spans of regions the frontend deliberately did not
/// analyse — the skip markers the parser recorded for a `match`, a `try`, an
/// unmodelled declaration. They are a SECOND trust boundary, independent of
/// `trusted_line`: a skip costs no coverage and moves no error line, but it
/// still leaves a hole in whichever function encloses it, so the frame audit
/// can only judge the bindings that hole cannot reach. See
/// `Walker::holes_in` and `hole_can_reach`.
pub fn walk_module(
  m : @ast.Module,
  file : String,
  extern_iface : @core.IfaceSymTab,
  trusted_line : Int32,
  enum_ctors : Array[String],
  extern_fns : Array[String],
  unread : Array[@core.Span],
) -> WalkResult {
  let w = new_walker(extern_iface, trusted_line > 0, file, unread)
  let fns : Array[FnInfo] = []
  let module_bindings : Array[Binding] = []
  let fn_bindings : Array[Array[Binding]] = []
  // pass 1: module bindings + function registration (forward references OK)
  fn collect_top(stmts : Array[@ast.Stmt]) -> Unit {
    for s in stmts {
      match s.kind {
        SLet(n, ann, init) => {
          if !module_bindings.contains(name_binding(n)) {
            module_bindings.push({
              name: n,
              tyann: ann,
              param: false,
              decl_span: s.span,
            })
          }
          // 0468. A module-level `let x : T = { ... }` RUNS the block at module
          // init, so every binding inside it lives in the module frame -- the same
          // rule the `SBlock` arm below already follows.
          //
          // This arm was MISSING and the corpus charged for it the moment 0468 made
          // the block parse: `src/../png.mbt:110` is `let fxl : HDecoder = {` with
          // `let ls = Array::make(288, 0)` on the very next line, read at 113, 116,
          // 119, 122 and 124. Collected without this descent, those are five false
          // `no visible binding for 'ls'` findings on code `moon check` compiles --
          // the 0467b defect arriving through a construct that did not exist in the
          // AST until 0468 added it. `actionable` went 0 -> 15 on that corpus alone,
          // and every one of the 15 traced back to this one omission.
          //
          // ONLY `EBlock`, and that is the whole safety argument. A `let f = fn() {
          // .. }` initialiser is an `EBigInt` carrying a skip note, never an
          // `EBlock`, so this cannot hoist a lambda's function-local names into the
          // module frame. `SBlock` stays the same arm it was.
          match init.kind {
            EBlock(body) => collect_top(body)
            _ => ()
          }
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
        SLetDestruct(names, _) =>
          for n in names {
            if !module_bindings.contains(name_binding(n)) {
              module_bindings.push({
                name: n,
                tyann: "",
                param: false,
                decl_span: s.span,
              })
            }
          }
        SFunc(name, params, retann, body, sp) => {
          fns.push({ name, params, retann, body, span: sp, })
          if !module_bindings.contains(name_binding(name)) {
            module_bindings.push({
              name,
              tyann: "",
              param: false,
              decl_span: sp,
            })
          }
        }
        // A top-level `for` executes at module level: its binder — the
        // desugared `$pair` head among them — and every binding inside its
        // body live in the module frame, so pass 1 must descend. Without
        // the descent, the destructuring let of a multi-binder head reads
        // `$pair` and the analyzer reports its own desugar as an undefined
        // name.
        SFor(v, vsp, _, body) => {
          if !module_bindings.contains(name_binding(v)) {
            module_bindings.push({
              name: v,
              tyann: "",
              param: false,
              decl_span: vsp,
            })
          }
          collect_top(body)
        }
        SBlock(body) => collect_top(body)
        // `loop nobreak { .. }` at module level. The SAME omission as the
        // per-function collector, with the same consequence: this match has a
        // `_ => ()` catch-all, so a missing arm compiles silently and the
        // `for` binder inside the wrapped loop never reaches the module frame.
        SNoBreak(loop_stmt, block) => {
          collect_top([loop_stmt])
          collect_top(block)
        }
        _ => ()
      }
    }
  }

  collect_top(m.body)
  for b in module_bindings {
    w.bind(b)
  }
  // Enum constructors join the module frame as ordinary top-level bindings —
  // but only after every real declaration, and `is_bound` keeps it that way.
  // A real `fn TFunc` must win over a harvested constructor of the same name,
  // or the enum's (entirely unknown) shape would silently replace a real
  // signature that the type lens can actually check.
  for c in enum_ctors {
    if !w.is_bound(c) {
      w.bind({ name: c, tyann: "", param: false, decl_span: @core.zero_span(), })
    }
  }
  for f in fns {
    fn_bindings.push(collect_fn_bindings(f))
  }
  // pass 2: module-level uses (function definitions are tables, not flow)
  for s in m.body {
    match s.kind {
      SFunc(_, _, _, _, _) => ()
      _ => w.walk_stmt(s)
    }
  }
  // pass 3: each function in its own frame
  // An `extern "C"` / `extern "wasm"` function is skipped by the audit below.
  // Its frame can only hold PARAMETERS (the body is in another language and was
  // never read), and those parameter names belong to the foreign ABI — so the
  // only thing the audit could say about them is "unused", which the compiler
  // does not say. Skipping the audit is precise here precisely because there is
  // nothing else in the frame to audit.
  let suspect = truncated_fn(fns, trusted_line)
  for i in 0..<fns.length() {
    let f = fns[i]
    w.push_frame()
    // Indexed by position, not by name — see `WalkResult.fn_bindings`. The
    // bound is a defensive `i < ...` rather than a trust: the two arrays are
    // built in lockstep in this function, and a walk result assembled anywhere
    // else must not index past its own table.
    let bs = if i < fn_bindings.length() { fn_bindings[i] } else { [] }
    for b in bs {
      w.bind(b)
    }
    w.vst.push({ func: f.name, file, line: f.span.start.line, })
    for st in f.body {
      w.walk_stmt(st)
    }
    // 0501. `audit_suppressed` used to be the second guard here, and it was a
    // BLANKET: one unread region anywhere in the function switched off every
    // conclusion the frame could support. The audit now runs and decides each
    // binding against the holes that can reach it.
    if i != suspect && !extern_fns.contains(f.name) {
      w.audit_frame(f.span)
    }
    let _ = w.vst.pop()
    w.pop_frame()
  }
  WalkResult::{
    fns,
    module_bindings,
    fn_bindings,
    findings: w.findings,
    partial: w.partial,
  }
}

///|
/// Index of the one function whose frame audit cannot be trusted, or -1.
///
/// `UnusedLocal`, `UnusedParam` and `ParamChanged` are not statements about a
/// LINE, they are conclusions about a WHOLE FUNCTION: "this binding was never
/// read" is only true if the reader saw every statement. When the frontend
/// gave up at `trusted_line`, the function containing that line was cut in
/// half — the statements after the cut were never parsed, so a binding
/// declared before the cut and read after it looks unread.
///
/// The scanner's boundary filter drops findings AT OR AFTER `trusted_line`,
/// which does not help here: these findings are reported at the DECLARATION,
/// which is before the cut. That is exactly how a real use-after-truncation
/// reached a user as an actionable defect.
///
///    fn probe(n : Int) -> Int {
///      let used_later = n + 1     <- line 2, before the boundary
///      try {                      <- line 3, where the parse gives up
///        1
///      }
///      used_later                 <- line 6, never parsed
///    }
///
/// reported `2:3 local variable 'used_later' assigned but may not be used`.
///
/// Only one function can be affected. Parsing is sequential and stops at the
/// first failure, so every function that started before `trusted_line` and is
/// not the last such function was closed before the parser reached the error.
/// We cannot see a function's closing brace (the `fn` span covers the
/// signature only), so this is the conservative identification: when the
/// error is at top level between two complete functions the last one before
/// it is skipped too. That costs one frame audit per partial file and can
/// never invent a finding.
fn truncated_fn(fns : Array[FnInfo], trusted_line : Int32) -> Int32 {
  if trusted_line <= 0 {
    return -1
  }
  let mut suspect = -1
  for i in 0..<fns.length() {
    if fns[i].span.start.line < trusted_line {
      suspect = i
    }
  }
  suspect
}

///|
fn name_binding(n : String) -> Binding {
  { name: n, tyann: "", param: false, decl_span: @core.zero_span(), }
}

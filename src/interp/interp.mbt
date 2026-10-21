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
  AInt(Int32)
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
/// Is `name` a LIST name, in EITHER of the two spellings this repository uses?
///
/// The TYPE lens writes a list type as `[int]` -- `ty_name`'s `TList` arm -- and
/// the BEHAVIORAL lens writes a list VALUE as `List` -- `abs_of`'s `TList` arm and
/// `eval`'s `EList`. `vmatches` compares a VALUE name against a TYPE name, so the
/// two spellings have to MEET, or every list is a type error.
///
/// MEASURED, they did not meet, and the cost was a false positive on every call
/// that passes a list: a fresh `Array[Int]` parameter bound to `AType("List")`
/// and passed to an `Array[Int]` parameter spelled `[int]` was reported
///
///     no method matching take(List)
///
/// on code `moon check` accepts, because "List" is not "[int]".
///
/// THE ELEMENT TYPE IS NOT COMPARED, and that is the right side to err on: this
/// lens models no list element types at all (a list LITERAL is `List` whatever
/// its elements are), so claiming that one list is not another would be a CLAIM
/// the lens cannot support. The same reasoning the `AAny` arm already uses.
fn is_list_name(name : String) -> Bool {
  if name == "List" {
    return true
  }
  let chars = name.to_array()
  if chars.length() < 2 {
    return false
  }
  chars[0] == '[' && chars[chars.length() - 1] == ']'
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
    AType(t) => t == ty || ty == "Any" || (is_list_name(t) && is_list_name(ty))
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
} derive(Eq)

///|
/// The flow after an `if` whose branches were all explored.
///
/// IT FALLS THROUGH if any branch does -- the standard join, and the whole
/// point: a terminating `else` can no longer make the statements after the
/// `if` unreachable when the then-branch reaches them.
///
/// WHEN EVERY BRANCH REALLY DOES TERMINATE, the flow is the terminator they
/// AGREE on. It used to be `FReturn` unconditionally, and that was a claim
/// about the FUNCTION -- "control leaves here" -- which a branch ending in
/// `continue` or `break` does not make: those leave the LOOP.
///
/// MEASURED, moonbit_image 0.3.7 `bmp.mbt:353-423`:
///
///     for pos = 0, row = 0, col = 0, valid_row = true {
///       if count == 0 {
///         ...
///         continue p, r, c, vr
///       } else {
///         ...
///         continue p, r, c, vr
///       }
///     }
///     Image::new(...)
///
/// Both arms end in `continue`, so the join claimed `FReturn` -- and the
/// statement after the loop was reported `unreachable code`. It IS reached:
/// the loop's `break` arm reaches it.
///
/// WHY IT MATTERS DOWNSTREAM, and this is not a detail. The `while` arm asks
/// whether the loop was exited by a `break` or a `continue` -- that question
/// is `FBreak | FContinue`, not `FReturn` -- and the `nobreak` arm asks
/// whether the loop finished normally, which is `FNormal` and nothing else.
/// A join that always said `FReturn` answered BOTH questions wrongly.
///
/// THE MIXED CASE -- one arm returns and another continues -- has no single
/// answer, and `FReturn` is the honest one to report there: it is the flow
/// that ends the frame.
fn join_flow(flows : Array[Flow]) -> Flow {
  if flows.length() == 0 {
    return FNormal
  }
  let mut all_return = true
  let mut all_continue = true
  let mut all_break = true
  let mut any_normal = false
  for f in flows {
    if f == FNormal {
      any_normal = true
    }
    if f != FReturn {
      all_return = false
    }
    if f != FContinue {
      all_continue = false
    }
    if f != FBreak {
      all_break = false
    }
  }
  // FALLS THROUGH IF ANY BRANCH DOES. This is the rule the old `falls` flag
  // carried, and it comes FIRST: a branch that falls through reaches the
  // statements after the `if`, whatever the other branches do.
  if any_normal {
    return FNormal
  }
  if all_return {
    return FReturn
  }
  if all_continue {
    return FContinue
  }
  if all_break {
    return FBreak
  }
  // A MIX: one arm returns and another leaves the loop. There is no single
  // answer, and `FReturn` is the honest one to report -- it is the flow that
  // ends the frame.
  FReturn
}

///|
priv struct MethodDef {
  name : String
  /// declared/inferred parameter types ("" = Any)
  ptypes : Array[String]
  /// parameter names, in order (from the walk table)
  pnames : Array[String]
  /// which parameters a call may OMIT, one flag per parameter, parallel to
  /// `pnames` and `ptypes`.
  ///
  /// The COUNT (`nopt`) cannot answer the question a label-matched dispatch
  /// has to ask, which is per parameter: a call that supplies a labelled
  /// parameter and omits a REQUIRED one is an error, and a count cannot tell
  /// that from a call that omits an optional one.
  pomittable : Array[Bool]
  /// how many of the parameters a call may OMIT (declared `name? : T`, or
  /// declared `name~ : T = default`). See `n_omittable`.
  nopt : Int32
  /// the partial return used on recursive cycles (from the signature)
  cycle_ret : AbsVal
  /// IS THIS NAME DECLARED MORE THAN ONCE IN THE FILE?
  ///
  /// A name with two declarations has NO SINGLE SIGNATURE, and the lens cannot
  /// know which one is live -- the `#cfg` predicate decides, and this frontend
  /// does not evaluate it. So the arity and parameter-type checks must not run
  /// against either of them. See `duplicate_names`.
  ambiguous : Bool
  body : Array[@ast.Stmt]
  line : Int32
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
  /// ENUM CONSTRUCTOR names, harvested from enum bodies this frontend did not
  /// parse (`ParseResult::enum_ctors`).
  ///
  /// The structural and type lenses BOTH receive that list, and the type lens
  /// seeds each name into the module frame as `TUnknown` -- "a value of unknown
  /// type" -- so neither of them reports it. This lens had no such table, so
  /// every constructor read was "undefined variable".
  ///
  /// MEASURED, the per-function entry surfaced it on the first corpus it
  /// touched: `proton_contract 0.3.4 contract.mbt:261`,
  ///
  ///     ContractRoute::{ scope: Application, name, }
  ///
  /// reported `undefined variable 'Application'` (an ERROR) on code `moon
  /// check` accepts. `Application` is a constructor of the `ContractScope`
  /// enum, whose BRACED body this frontend skips -- so the name arrives in
  /// `enum_ctors` and the lens simply never asked.
  ///
  /// It was invisible before because the lens never executed a function body
  /// in a library module, and a library module's top level is definitions
  /// only. The defect was in the lens, not in the entry; the entry only made
  /// it visible.
  ctors : Map[String, Bool]
  /// THE VALUE OF THE STATEMENT LAST EXECUTED, if it has one.
  ///
  /// This is how a function whose body's last statement is an `if` gets the
  /// BRANCH's value: the branch's trailing expression is an `SExpr`, and the
  /// `SExpr` arm used to throw the value away. `ret_vals` -- the other route to
  /// a function's value -- only carries a `return` and a `STail`, so an `if`
  /// body left it empty and `join_vals([])` answered "None".
  ///
  /// It is reset at the top of every `exec_stmt`, so a statement with no value
  /// leaves ABottom rather than a stale value from the statement before it.
  mut last_value : AbsVal
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
  /// DID THE BODY BEING EXECUTED REACH A `break`?
  ///
  /// THE QUESTION THE JOIN CANNOT ANSWER. A loop asks two things about its
  /// body: "did it end by returning?" and "could it have left the loop?". The
  /// second one is what decides whether the code AFTER the loop is reachable
  /// when the loop's condition is constantly true -- a `for` with no condition
  /// never ends on its own, so a `break` is the only way out.
  ///
  /// The JOINED FLOW cannot answer it, because the join collapses a MIX of
  /// terminators into `FReturn`: a body with one branch that `break`s, one
  /// that `continue`s and one that `return`s joins to `FReturn`, and the `break`
  /// is gone.
  ///
  /// MEASURED, moonbitlang/async 0.22.4 `src/http/cookie.mbt:88`:
  ///
  ///     if attr_end == line.length() {
  ///       break
  ///     } else {
  ///       continue attr_end + 1
  ///     }
  ///   }
  ///   { name, value, path, .. }
  ///
  /// The block after the loop was reported `unreachable code`, on code `moon
  /// check` accepts -- and the `break` reaches it. The same shape is
  /// moonbit_image 0.3.7 `bmp.mbt:423` and `:533`.
  ///
  /// So the flag is set where the `break` is, and the loop reads it. It is
  /// saved and restored around each loop body, so a nested loop's `break` is
  /// not mistaken for the outer one's.
  mut broke : Bool
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
    ctors: Map([]),
    last_value: ABottom,
    file,
    globals: Map([]),
    cache: Map([]),
    in_progress: Map([]),
    partials: Map([]),
    sink: [],
    vst: [],
    ret_vals: [],
    flow: FNormal,
    broke: false,
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
/// Build the interpreter and register every method (from the signature
/// table -- assembly point 2) plus the local-function names.
///
/// SHARED by the module entry and the per-function entry. The two MUST agree
/// about which names exist and what their parameters are: a per-function
/// entry that dispatched against a different method table would report "no
/// method matching" for a call the module entry accepts, and the
/// contradiction would read as a finding.
fn setup_interp(
  m : @ast.Module,
  tr : @types.TypeResult,
  wr : @walk.WalkResult,
  file : String,
  extern_iface : @core.IfaceSymTab,
  enum_ctors : Array[String],
) -> Interp {
  let it = new_interp(file, extern_iface)
  for c in enum_ctors {
    it.ctors.set(c, true)
  }
  // method table from the type lens's signatures (assembly point 2)
  // The names declared more than once have no single signature; see
  // `duplicate_names`.
  let dupes = duplicate_names(wr.fns)
  for i, f in wr.fns {
    let sig : @types.Sig? = sig_at(tr, i)
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
      pomittable: fn_pomittable(f),
      nopt: n_omittable(f),
      cycle_ret,
      ambiguous: match dupes.get(f.name) {
        Some(d) => d
        None => false
      },
      body: f.body,
      line: f.span.start.line,
    })
  }
  // Local fn names are collected first: their bodies are not executed (they
  // capture the enclosing frame), but their names must resolve and their
  // calls must not report undefined.
  collect_local_fns(m.body, it.local_fns)
  it
}

///|
/// Analyze a whole module. Phase 1 registers methods (from the signature
/// table -- assembly point 2); phase 2 runs a dry top-level pass to populate
/// the signature cache (fixpoint for recursion via partials); phase 3 is the
/// report pass with complete virtual stacks.
pub fn analyze_module(
  m : @ast.Module,
  tr : @types.TypeResult,
  wr : @walk.WalkResult,
  file : String,
  extern_iface : @core.IfaceSymTab,
  enum_ctors : Array[String],
) -> Array[@report.Report] {
  let it = setup_interp(m, tr, wr, file, extern_iface, enum_ctors)
  // phase 2 (dry): populate the cache
  it.run_top(m, true)
  // phase 3 (report): replay with complete stacks
  it.run_top(m, false)
  it.sink
}

///|
/// THE PER-FUNCTION ENTRY: analyze each function AS IF it were the program's
/// entry point.
///
/// WHY THIS EXISTS. `Interp::run_top` SKIPS `SFunc` items, so a function body
/// is only ever executed if something CALLS it from a top-level statement.
/// A library module does not call its own functions at top level, so this
/// lens never executed a single body on any pinned corpus: moui 4152
/// findings, proton 1062, async 1820 -- every one of them tagged
/// `structural`, and not one tagged `behavior`.
///
/// MEASURED, the gap is the ENTRY and nothing else. The same defect, in the
/// same body, three ways:
///
///   top     -- a top-level statement        -> [type+behavior]
///   incall  -- in a function CALLED at top  -> [type+behavior]
///   uncall  -- in a function NEVER called   -> [type]   <- behavior GONE
///
/// for every defect kind tried, and `unreachable code` is the cleanest case:
/// `[behavior]` alone when the function is called, and nothing at all when it
/// is not, because no other lens sees it.
///
/// The parameters are bound to fresh abstract values of their DECLARED types.
/// The declared type is the only sound choice for an entry point: the
/// parameter's runtime value is unknown, so the lens must assume the
/// declared type and nothing more. An unannotated parameter becomes `AAny`,
/// which every operation accepts -- an unannotated parameter must not
/// manufacture a finding.
pub fn analyze_functions(
  m : @ast.Module,
  tr : @types.TypeResult,
  wr : @walk.WalkResult,
  file : String,
  extern_iface : @core.IfaceSymTab,
  enum_ctors : Array[String],
) -> Array[@report.Report] {
  let it = setup_interp(m, tr, wr, file, extern_iface, enum_ctors)
  // The MODULE FRAME. A function body may read a module-level binding, and
  // `analyze_fn` gives it a FRESH environment holding only the parameters --
  // so without this pass every such read would be "undefined variable". The
  // pass is DRY: the module entry reports the top-level findings, and this
  // entry must not report them a second time.
  it.run_top(m, true)
  // dry, then report, exactly as the module entry does: the dry pass is what
  // makes the report pass's virtual stacks complete.
  let saved_sink = it.sink
  it.sink = []
  for i, f in wr.fns {
    it.analyze_entry(f, tr, i)
  }
  it.sink = saved_sink
  for i, f in wr.fns {
    it.analyze_entry(f, tr, i)
  }
  it.sink
}

///|
/// Analyze ONE function as an entry point: bind its parameters to fresh
/// abstract values and execute its body.
fn Interp::analyze_entry(
  self : Interp,
  f : @walk.FnInfo,
  tr : @types.TypeResult,
  idx : Int32,
) -> Unit {
  let sig : @types.Sig? = sig_at(tr, idx)
  let ptypes : Array[String] = []
  let vals : Array[AbsVal] = []
  // `sig.param_tys` is parallel to `f.params` BY CONSTRUCTION -- the type
  // lens builds both from the same loop over `f.params` -- so the index
  // alignment below is not an assumption. The `None` arms are there because
  // `find_sig` can return None: a function the type lens did not infer.
  //
  // All three arrays are built from `f.params` and NOT from the signature, so
  // `ptypes`, `vals` and the parameter NAMES always have the same length. A
  // shorter `vals` would bind the trailing names to `ABottom` -- "no value" --
  // and an unreachable value manufactures findings.
  for i, _ in f.params {
    let t = match sig {
      Some(s) =>
        match s.param_tys.get(i) {
          Some(t) => t
          None => @types.TUnknown
        }
      None => @types.TUnknown
    }
    let n = @types.ty_name(t)
    ptypes.push(if n == "Unknown" { "" } else { n })
    vals.push(abs_of(t))
  }
  let cycle_ret = match sig {
    Some(s) =>
      match s.declared_ret {
        @types.TUnknown => AAny
        t => AType(ret_name(t))
      }
    None => AAny
  }
  let def : MethodDef = {
    name: f.name,
    ptypes,
    pnames: fn_pnames(f),
    pomittable: fn_pomittable(f),
    nopt: n_omittable(f),
    cycle_ret,
    // The entry function is not a CALL, so no arity check is made against it.
    // The flag that matters for a call is on the TABLE's entry, and that is
    // built by `setup_interp` -- where the duplicate names are known.
    ambiguous: false,
    body: f.body,
    line: f.span.start.line,
  }
  let _ = self.analyze_fn(def, vals)
}

///|
/// A fresh abstract value for a parameter of the declared type `t`.
///
/// The names here are the LENS's value names, not the type lens's DISPLAY
/// names: `ty_name` writes a list as `[int]` and a union as `Union[int, str]`,
/// while the lens's values are `List` and `Any`. The two must not be mixed --
/// `vmatches` compares a value name against a type name, and `AType("List")`
/// does not equal `"[int]"`.
/// THE WAY OUT IS `is_list_name`, NOT A DIFFERENT SPELLING HERE: a value that is
/// spelled `AType("[int]")` would no longer be the `List` the lens's own
/// `EList` / `EIndex` / `len` arms recognise, so the two vocabularies would
/// still disagree -- just with the disagreement moved. `is_list_name` is where
/// the two spellings MEET, and it is the only place that has to know about
/// both.
fn abs_of(t : @types.Ty) -> AbsVal {
  match t {
    @types.TInt => AType("int")
    @types.TFloat => AType("float")
    @types.TBool => AType("bool")
    @types.TStr => AType("str")
    @types.TNone => AType("None")
    @types.TList(_) => AType("List")
    // A function value, a union and an unknown type are all "some value we
    // know nothing about" here. `AAny` is the only sound choice: a concrete
    // name would be a CLAIM, and a false one produces a finding.
    _ => AAny
  }
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
    @types.TFunc(n, _, _, _) => "fn \{n}"
    @types.TUnknownFn(n) => "fn \{n}"
    @types.TUnion(_) => "Any"
  }
}

///|
/// THE SIGNATURE OF THE `i`-TH DECLARED FUNCTION, BY POSITION.
///
/// The lookup used to be BY NAME, and that is wrong for a file that declares the
/// same name twice. MoonBit allows it -- `#cfg` is how real code reaches it --
/// and moonbitlang/async 0.22.4 `src/internal/fd_util/fd_util.mbt` declares
/// `close_ffi` twice:
///
///     #cfg(not(platform="windows"))
///     extern "C" fn close_ffi(fd : Fd) -> Int = "close"
///     #cfg(platform="windows")
///     extern "C" fn close_ffi(fd : Fd, is_socket~ : Bool) -> Int = "moonbitlang_async_close_fd"
///
/// A name lookup returned the FIRST declaration's signature, while the
/// parameter NAMES came from the walk's `FnInfo` for the declaration being
/// registered -- the LAST one. The two halves of ONE method definition then
/// described TWO different functions, and the arity check compared the call
/// against the wrong one:
///
///     no method matching close_ffi(Any, Any)
///
/// on code `moon check` accepts. The call supplies two arguments; the first
/// declaration declares one.
///
/// THE TYPE LENS'S `sigs` ARE PARALLEL TO THE WALK'S `fns` BY CONSTRUCTION: the
/// type lens runs `run_fn` once per function in `wr.fns`, in order, and
/// `run_fn` pushes exactly one signature. So the position IS the identity, and
/// no name is needed.
fn sig_at(tr : @types.TypeResult, i : Int32) -> @types.Sig? {
  if i < 0 || i >= tr.sigs.length() {
    return None
  }
  Some(tr.sigs[i])
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
      // THE LOOP'S UPDATE CLAUSE IS NOT DEAD CODE. A `continue` in a
      // C-style `for` RUNS the update clause and repeats the loop, and a
      // `break` skips it and leaves the loop -- so the clause is reached on
      // one path and skipped on the other, and neither makes it unreachable.
      //
      // MEASURED, by RUNNING it: `_verify/settle_0495_perfunction.ps1` prints
      // `i=0 i=1 i=2 i=3` and finishes, which is only possible if the update
      // ran on the `continue`. Before this, the update clause was appended to
      // the loop body as ordinary statements and was reported `unreachable
      // code` -- `async 0.22.4 src/socket/addr_utils.mbt:262`.
      match s.kind {
        SForUpdate(updates) =>
          if self.flow == FContinue {
            // A `continue` runs the update and repeats the loop, so the loop
            // is still live.
            for u in updates {
              self.exec_stmt(u, env)
            }
            self.flow = FNormal
          } else if self.flow == FBreak {
            // A `break` leaves the loop: the update does NOT run, and the
            // code after the loop is reached.
            self.flow = FNormal
          }
        // A `return` ends the frame: the update does not run and the flow
        // stays FReturn.
        _ => {
          // behavior lens's flow insight: statements after a terminator are
          // unreachable (reportUnreachable)
          self.report(@core.FUnreachable, "unreachable code", s.span)
          break
        }
      }
      continue
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
  // THE VALUE OF THIS STATEMENT, if it has one. Reset FIRST, so a statement
  // with no value leaves ABottom rather than a stale value from the statement
  // before it.
  //
  // WHY IT EXISTS. A function whose body's last statement is an `if` returns
  // the BRANCH's value, and the branch's value was being evaluated and
  // DISCARDED: the `SIf` arm ran the branch, and the branch's trailing
  // expression was an `SExpr`, whose value nothing kept. So `ret_vals` stayed
  // empty and `join_vals([])` answered "None" -- and every operator applied
  // to that result was reported as a method error:
  //
  //     no method matching +(None, int)
  //
  // on code `moon check` accepts. Measured on moui 0.1.12: `clamp_double` is
  // an `if` body, and every call site of it inherited the "None".
  self.last_value = ABottom
  match s.kind {
    SExpr(e) => self.last_value = self.eval(e, env)
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
        // 0495 AND THE DEAD ARM THAT WAS HERE. This `match` is over the
        // ASSIGNMENT'S TARGET, and a target is a name, a field, an index or a
        // tuple field -- never a comprehension. An `EComp` arm could not fire.
        //
        // It was not harmless: it held a COPY of the comprehension-binding
        // rule, and the mutation gate found it -- M8 (`a comprehension in an
        // assignment binds no names`) SURVIVED, because no program reaches the
        // arm. A surviving mutation of a rule nobody can reach is the rule
        // being dead, and the honest response is to DELETE IT rather than to
        // keep a copy of a rule in a place it cannot apply.
        //
        // THE RULE ITSELF IS NOT LOST: the right-hand side of the assignment
        // is evaluated by `self.eval(rhs, env)` above, and the `EComp` arm of
        // `eval` binds the pattern names while the body is evaluated. That is
        // the arm gate 0495's M8 mutates, and it is the one that fires.
        _ => ()
      }
    }
    SIf(cond, then, elseifs, els) =>
      // ABool constants prune dead branches (assembly point 3)
      match self.eval(cond, env) {
        ABool(true) => self.exec_block(then, env)
        ABool(false) =>
          // Same join as the unknown-condition arm below, for the same reason:
          // the then-branch is not taken, so the `if` falls through exactly when
          // the elseifs/else chain does.
          self.flow = self.exec_alt(elseifs, els, env, 0)
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
          // The branches below are explored ONE AFTER ANOTHER in this same
          // `Interp`, so the flow state used to simply carry over between them:
          // a branch that terminated made the NEXT branch's first statement
          // look unreachable, and whatever the LAST branch left behind was
          // what survived past the whole `if`.
          //
          // The entry flow is always FNormal here -- `exec_block` only calls
          // `exec_stmt` when the frame is live and reports otherwise -- so each
          // branch starts from FNormal and the results are joined at the end.
          self.flow = FNormal
          self.exec_block(then, env_then)
          // THE VALUE OF THE `if`. Every branch is explored (the condition is
          // unknown), so the value is their JOIN -- the same join the bindings
          // get, applied to the value instead of the environment.
          let mut val = self.last_value
          // 0495 AND THE JOIN. The branch FLOWS are collected rather than a
          // `falls` flag, because the terminator they agree on is what the
          // join has to report -- and `FReturn` was not it. See `join_flow`.
          let flows : Array[Flow] = [self.flow]
          let acc = env_then
          for ei in elseifs {
            let env_ei = copy_env(acc)
            self.flow = FNormal
            // THE CONDITION IS CODE, AND IT WAS NOT EVALUATED HERE. Two
            // consequences, and they point in opposite directions.
            //
            // A name read in the condition was never checked, so a real
            // undefined name went unreported -- a false NEGATIVE.
            //
            // And an `is` pattern in the condition never bound, so the name it
            // introduces was reported `undefined variable` in the branch's own
            // body -- a false POSITIVE. MEASURED, wzzc-dev/moui 0.1.12,
            // `views/text/text_area_control.mbt:414`:
            //
            //     ctx.text_control.text_selection_anchor is Some(anchor)
            //
            // binds `anchor`, which is read twelve lines later at `:426`, and
            // the per-function view reported `undefined variable 'anchor'`.
            // The same binding in a plain `if` condition worked, and the same
            // binding in an `else if` condition did not -- and the difference
            // is exactly this line.
            //
            // The condition is evaluated in the SAME environment the branch's
            // body runs in, so the binding it introduces is in scope for that
            // body, which is the claim being made. The binding then joins the
            // merged environment, so it stays visible to the branches after
            // it -- a leak in the SILENT direction, which is the safe one:
            // MoonBit scopes the binding to the `if`, and this lens scopes
            // bindings flat everywhere else (see `SBlock`).
            let cv = self.eval(ei.cond, env_ei)
            if !vboolean(cv) {
              self.report(
                @core.FCondBool,
                "condition must be bool, got '\{val_name(cv)}'",
                ei.cond.span,
              )
            }
            self.exec_block(ei.body, env_ei)
            val = vjoin(val, self.last_value)
            flows.push(self.flow)
            let merged = Interp::merge_env(self, acc, env_ei)
            acc.clear()
            for k, v in merged {
              acc.set(k, v)
            }
          }
          match els {
            Some(e) => {
              let env_e = copy_env(acc)
              self.flow = FNormal
              self.exec_block(e, env_e)
              val = vjoin(val, self.last_value)
              flows.push(self.flow)
              let merged = Interp::merge_env(self, acc, env_e)
              acc.clear()
              for k, v in merged {
                acc.set(k, v)
              }
            }
            // A MISSING else always falls through: when no branch is taken,
            // nothing runs and control continues, so it must not make the
            // statements after the `if` look dead either.
            None => flows.push(FNormal)
          }
          env.clear()
          for k, v in acc {
            env.set(k, v)
          }
          self.last_value = val
          // The join. Falls through if ANY branch does, which is the standard
          // join and the whole point: a terminating `else` can no longer make
          // the statements after the `if` unreachable when the then-branch
          // reaches them. When every branch really does terminate, the code
          // after the `if` IS dead -- and the flow that says so is the one the
          // branches AGREE on, not always `FReturn`. See `join_flow`.
          self.flow = join_flow(flows)
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
      // THE LOOP'S OWN `break`. Saved and restored around the body so a
      // NESTED loop's `break` is not mistaken for this loop's -- the nested
      // loop consumes its own, and the flag this loop reads is the one that
      // was set when this loop's body began.
      let saved_broke = self.broke
      self.broke = false
      self.exec_block(body, wenv)
      let body_broke = self.broke
      self.broke = saved_broke || body_broke
      let merged = Interp::merge_env(self, env, wenv)
      env.clear()
      for k, v in merged {
        env.set(k, v)
      }
      // A LOOP MAY RUN ZERO TIMES, so the body's flow is not the flow AFTER
      // the loop. `while cond` is not guaranteed to run at all, and the
      // statement after it is reachable whenever the condition is false on
      // the first test.
      //
      // MEASURED, wzzc-dev/moui 0.1.12,
      // `core/unicode/grapheme_cluster.mbt:428`: a `while cursor >= 0` whose
      // body ends in `return`, followed by `false`. The per-function view
      // reported `unreachable code` on the `false` -- but `cursor` is
      // `index - 1`, so `cursor` is `-1` when `index` is `0`, the loop runs
      // ZERO times, and the `false` is the function's value on that path.
      //
      // THE TOOLCHAIN DOES NOT SETTLE REACHABILITY, and that is measured
      // rather than assumed: MoonBit ACCEPTS code after a `return`
      // (`_verify/settle_0493_lens_values.ps1`, row `e3`), so the
      // `Unreachable` family is a lint the toolchain does not share. What
      // settles THIS claim is the EXECUTION row of the same script: the
      // program prints 42, so the statement after the `while` really is
      // reached.
      //
      // The body's flow is kept in exactly one case: a condition that is
      // constantly true, where the body is guaranteed to run at least once.
      // A `break` or a `continue` leaves the loop, so the flow after it is
      // ordinary in every case.
      let always = match cv {
        ABool(b) => b
        _ => false
      }
      let broke = match self.flow {
        FBreak | FContinue => true
        _ => false
      }
      // `body_broke` is the OTHER half of the question: the joined flow says
      // the body ended in ONE terminator, and a body whose branches end in
      // DIFFERENT ones joins to `FReturn` -- which loses the `break` that
      // reaches the code after this loop.
      //
      // MEASURED, moonbitlang/async 0.22.4 `src/http/cookie.mbt:88`: the
      // `break`/`continue` pair joins to `FReturn`, the statement after the
      // loop was reported `unreachable code`, and the `break` reaches it.
      self.flow = if always && !broke && !body_broke {
        self.flow
      } else {
        FNormal
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
      // A `for ... in` LOOP MAY RUN ZERO TIMES, so the statement after it is
      // reachable whatever the body did. This is the same rule the `while` arm
      // applies, and the reason it is stated here rather than inherited: the
      // `while` arm resets the flow unless the condition is constantly TRUE,
      // and a `for ... in` loop has no condition at all -- the sequence decides
      // whether it runs, and an empty sequence is a sequence.
      //
      // MEASURED, proton 0.3.4 `internal/locale/locale.mbt:301`:
      //
      //     fn starts_with_ascii_digit(value : String) -> Bool {
      //       for character in value {
      //         return is_ascii_digit(character)
      //       }
      //       false
      //     }
      //
      // The `false` is the function's value for an EMPTY string, and the
      // per-function view reported `unreachable code` on it. The `while` arm
      // had already been fixed for this reason at 0493 (class E); the `for ...
      // in` arm was left with the body's flow intact, so a body that ends in
      // `return` still marked the code after the loop as dead.
      self.flow = FNormal
    }
    // `loop nobreak { .. }` -- execute the loop, then the block, in the SAME
    // environment the loop merged into. The block runs when the loop finished
    // without a `break`, and the analyzer does not model which loops do; running
    // it unconditionally is the sound approximation and matches what the other
    // two lenses do with the same node. Widening is NOT re-applied: the loop arm
    // has already widened, and widening twice would lose more than it keeps.
    SNoBreak(loop_stmt, block) => {
      self.exec_stmt(loop_stmt, env)
      if self.flow == FNormal {
        self.exec_block(block, env)
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
    // The body's trailing expression is what the function RETURNS, so its value
    // is recorded exactly like an explicit `return` of the same expression --
    // and the flow is left ALONE, because a tail expression is the last thing
    // in the block either way: there is nothing after it that could be
    // unreachable. Setting FReturn here would be harmless inside a function
    // body and wrong everywhere else, which is why the node exists only in one.
    //
    // The measured consequence of getting this wrong, and it is not cosmetic:
    // `ret_vals` stayed empty, `join_vals([])` answered `None`, that `None` went
    // into the call cache, and a caller doing arithmetic on the result got
    //
    //     no method matching +(None, int)
    //
    // for a program `moon check` accepts with zero errors. It also made the
    // analyzer's own signature output claim `f() -> None` for
    // `fn f() -> Int { 1 }` -- a false statement about what it understood.
    //
    // Unlike a raise, the expression IS evaluated: it is the return value, not
    // an operand after the end of the frame.
    STail(e) => {
      self.last_value = self.eval(e, env)
      self.ret_vals.push(self.last_value)
    }
    // A raise terminates the frame exactly as a return does, so the flow is
    // `FReturn` -- there is deliberately no separate `FRaise`, because from
    // inside this frame the two are indistinguishable and a third state would
    // mean every "is this frame dead yet" test had to learn about it.
    //
    // The pushed value is ABOTTOM, not the payload: `raise E` produces no value
    // at all. And the payload is NOT evaluated. Everything after a terminator is
    // dead, so evaluating an expression whose result is discarded could only
    // perturb the abstract value stack for no observable gain; the payload is
    // still walked and type-checked by the other two lenses.
    SRaise(_) => {
      self.ret_vals.push(ABottom)
      self.flow = FReturn
    }
    // A `break`/`continue` THAT CARRIES VALUES. The values are EVALUATED --
    // a name inside one is a real name -- and they are the TERMINATOR'S OWN
    // PAYLOAD, not statements after it.
    //
    // 0495 AND THE 25 FINDINGS THIS REMOVES. The values used to be sibling
    // statements inside a block, so the interpreter read the terminator, saw
    // the flow end, and reported the first carried value as `unreachable
    // code` -- on code `moon check` accepts:
    //
    //     moonbit_image  bmp.mbt:373   `continue p, r, c, vr`
    //     async          conn.mbt:389  `continue received + n`
    //
    // WHAT IS NOT MODELLED, stated rather than claimed: the values are the
    // loop variables' NEW values, and the interpreter does not assign them.
    // It cannot: which names a `continue` refers to is a property of the loop
    // HEADER, and the interpreter does not carry the header's declarations
    // into the body. The loop's EXIT value is not modelled either, for the
    // reason the parser records -- a `break` value would have to be JOINED
    // with the `nobreak` block's value, and this subset makes no such claim.
    SBreak(vals) => {
      for v in vals {
        let _ = self.eval(v, env)
      }
      // THE LOOP'S WAY OUT. The joined flow cannot say whether the body could
      // have left the loop -- see the `broke` field.
      self.broke = true
      self.flow = FBreak
    }
    SContinue(vals) => {
      for v in vals {
        let _ = self.eval(v, env)
      }
      self.flow = FContinue
    }
    SFunc(_, _, _, _, _) => ()
    // `let (a, b) = pair`: the initializer is evaluated ONCE (a second eval
    // would re-report the same finding), and every destructured name is set.
    SLetDestruct(names, init) => {
      let _ = self.eval(init, env)
      // A DESTRUCTURED NAME HOLDS AN ELEMENT, NOT THE TUPLE. Binding the
      // initializer's value to every name in the pattern was a CLAIM -- "this
      // name holds a Tuple" -- and it is false for every name in the pattern.
      //
      // MEASURED, four corpora, the per-function view: 61 findings, every one
      // of them a false positive on code `moon check` accepts. The tainted
      // name reached a call as `Tuple` and the call's declared parameter type
      // did not match it:
      //
      //     no method matching derive_label_dir_from_image_dir(Tuple)
      //     no method matching lzw_read_code(Any, Tuple, Tuple, int)
      //     no method matching -(Tuple, Tuple)
      //
      // The TYPE LENS already answers "Unknown" for a destructured name --
      // "tuple element types are not modelled (no tuple Ty), so every
      // destructured name starts Unknown in the current frame"
      // (`src/types/infer.mbt`). This lens binding the whole tuple was
      // contradicting its own sibling on the same line.
      //
      // `AAny` is the honest answer, and it is the answer the lens already
      // gives a cross-file name, an enum constructor and an unknown type: the
      // lens knows the name is BOUND and does not know what it holds.
      // `vmatches` accepts `AAny` for every declared type, which is what
      // removes the findings.
      //
      // THE COST, stated rather than hidden: the lens can no longer see a
      // type error in a destructured element -- and it never could, because
      // what it saw was a Tuple, not the element. A tuple-element type is
      // recorded as a limit, not claimed as a capability.
      for n in names {
        env.set(n, AAny)
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
    // A C-style `for`'s UPDATE clause. It runs at the end of an iteration, and
    // `exec_block` runs it when a `continue` reached it.
    SForUpdate(updates) =>
      for u in updates {
        self.exec_stmt(u, env)
      }
  }
}

///|
fn Interp::exec_alt(
  self : Interp,
  elseifs : Array[@ast.ElseIf],
  els : Array[@ast.Stmt]?,
  env : Map[String, AbsVal],
  idx : Int32,
) -> Flow {
  if idx < elseifs.length() {
    match self.eval(elseifs[idx].cond, env) {
      ABool(true) => {
        self.flow = FNormal
        self.exec_block(elseifs[idx].body, env)
        self.flow
      }
      ABool(false) => self.exec_alt(elseifs, els, env, idx + 1)
      // A BOTTOM condition reports nothing and, as before this join existed,
      // leaves the flow alone -- so it falls through. Whether a bottom
      // condition should suppress everything downstream is a separate question
      // and this fix does not answer it either way.
      ABottom => FNormal
      cv => {
        if !vboolean(cv) {
          self.report(
            @core.FCondBool,
            "condition must be bool, got '\{val_name(cv)}'",
            elseifs[idx].cond.span,
          )
        }
        // Same join as the then/elseif arms: fall through if ANY branch does.
        self.flow = FNormal
        self.exec_block(elseifs[idx].body, env)
        // The VALUE of the chain, joined across the branches -- the same join
        // the `if` arm does, for the same reason.
        let mut val = self.last_value
        // 0495 AND THE JOIN: the branch FLOWS, not a `falls` flag. See
        // `join_flow`.
        let flows : Array[Flow] = [self.flow]
        let mut j = idx + 1
        // A `while` and not `for j in (idx + 1)..elseifs.length()`: the range
        // operator binds tighter than the call after it, so that expression
        // parses as `(idx + 1)..elseifs` and then `.length()`.
        while j < elseifs.length() {
          self.flow = FNormal
          // THE CONDITION IS CODE, and it was not evaluated here -- the same
          // omission as the unknown-condition path in the `if` arm, and the
          // same two consequences. The comment there says why; this is the
          // second of the two paths that reach an `else if` body, so it needs
          // the same rule. An `is` pattern in the condition must bind before
          // the body runs.
          let cv = self.eval(elseifs[j].cond, env)
          if !vboolean(cv) {
            self.report(
              @core.FCondBool,
              "condition must be bool, got '\{val_name(cv)}'",
              elseifs[j].cond.span,
            )
          }
          self.exec_block(elseifs[j].body, env)
          val = vjoin(val, self.last_value)
          flows.push(self.flow)
          j += 1
        }
        match els {
          Some(e) => {
            self.flow = FNormal
            self.exec_block(e, env)
            val = vjoin(val, self.last_value)
            flows.push(self.flow)
          }
          // A MISSING else always falls through: when no condition holds,
          // nothing runs and control continues.
          None => flows.push(FNormal)
        }
        self.last_value = val
        join_flow(flows)
      }
    }
  } else {
    match els {
      Some(e) => {
        self.flow = FNormal
        self.exec_block(e, env)
        self.flow
      }
      None => FNormal
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
              } else if self.ambient.contains(n) {
                // An ambient NAME read as a VALUE. `Interp::call` has consulted
                // this table since 0.4.4 and this branch did not, so every
                // ambient value read outside a call position was invented
                // here while the structural lens — which does consult the
                // table — stayed silent on the same line. Measured on
                // wzzc-dev/moui 0.1.12 `backend/wechat/host_runtime.mbt:16`:
                // `driver: None,` inside a struct literal, 5 findings.
                //
                // It is not only the struct-literal shape: an ambient name used
                // as an ARGUMENT is evaluated here too, so `use_it(None)`
                // reported exactly as `{ a: None }` did, even though `None` is
                // a compiler constructor on the ambient list. That pair is
                // what rules out "call handles it" as the explanation.
                AAny
              } else if self.ctors.contains(n) {
                // An ENUM CONSTRUCTOR read as a value. Its type is unknown --
                // the type lens seeds the same names as `TUnknown` -- so the
                // honest answer is "a value of unknown type", exactly as for
                // a cross-file name. The structural and type lenses both have
                // this table and both stay silent on the same line.
                AAny
              } else if self.extern_iface.has_value(n) ||
                self.extern_iface.has_type(n) {
                // A CROSS-FILE NAME read as a value: a function, a constant, or
                // an enum constructor declared in ANOTHER file -- a sibling of
                // this one, or a dependency.
                //
                // THE READ PATH DID NOT ASK THE TABLE, and the CALL path has
                // asked it since 0.4.3 -- `Interp::call` below asks the same
                // two questions, for the same reason, in the same words. So a
                // name that IS bound elsewhere was reported `undefined
                // variable` here, while the structural lens -- whose "no
                // visible binding" gate has consulted the same table since
                // 0.4.3 -- stayed silent on the same line. Two lenses, one
                // line, opposite answers.
                //
                // MEASURED, wzzc-dev/moui 0.1.12, the per-function view: 51
                // findings of this shape -- 49 PRINTED, plus 2 the scanner's
                // per-file print cap hides -- of which 35 are `undefined
                // variable 'Constant'` -- an enum variant of `pub(all) enum
                // DeclarationChannel` in `core/declaration.mbt`, read bare in
                // `core/modifier_paint.mbt`. The rest are the same shape:
                // `MoveLeft`/`MoveRight`/`MoveStart`/`MoveEnd` (variants of a
                // `priv enum` in a sibling file), `Up`, `view_size_key`,
                // `DeclarationKey::double`, and the package-private
                // `dispatch_web_*`, `web_active_app`, `clone_semantics_issue`
                // and `macos_perf_now_ms`.
                //
                // SETTLED WITH THE TOOLCHAIN, `_verify/settle_0491_crossfile.ps1`,
                // 12/12: the toolchain ACCEPTS every same-package sibling
                // shape -- a bare unit variant of a `pub(all)` enum, a bare
                // unit variant of a `priv` enum, a package-private `fn`, a
                // package-private `let`, a `pub const`, a qualified `pub fn`,
                // and all of them in one file -- and REFUSES the cross-package
                // ones (a package-private `fn`, a bare variant of another
                // package's enum) and a name that exists nowhere. The
                // controls are what make the ACCEPT rows mean something: a
                // blanket "any name is bound" would pass them too.
                //
                // The VALUE is unknown -- we know the name is bound and we do
                // not know its type -- so the honest answer is `AAny`, exactly
                // as for the constructor above and as for a cross-file name
                // in the type lens (`TUnknown`). `AType("Function")` would
                // claim more than the table knows: `has_value` cannot tell a
                // function from a constant, and the table records that
                // difference only in a flag this lens has no reason to read.
                AAny
              } else if self.tail_bound(n, env) {
                // A QUALIFIED name read as a value whose TAIL is bound:
                // `PixelFormat::RGBA8`. The qualifier is a TYPE, so the name is
                // a constructor -- and the harvest binds `RGBA8` but not the
                // whole path. This is the structural lens's own rule (see
                // `Interp::tail_bound`), and this lens had no such rule, so
                // every qualified constructor read was reported here while the
                // structural lens stayed silent on the same line.
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
      // THE PIPE WITH A CALL ON ITS LEFT. `f <| x` applies `f` to `x`, and when
      // `f` is a CALL, the right operand becomes an ARGUMENT of that call.
      //
      // SETTLED against the toolchain rather than assumed: `add2(1) <| 2`
      // ACCEPTs where `add2` declares two parameters, so the pipe supplies the
      // second; and `one(1) <| 2` REJECTs, where `one` declares one, so the
      // pipe does not invent an argument. The direction is the settled one --
      // `f <| x` applies the LEFT to the RIGHT -- see
      // `_verify/settle_0464_pipe_operators.ps1`.
      //
      // MEASURED, moonbitlang/async 0.22.4
      // `src/internal/event_loop/timer.js.mbt:25`:
      //
      //     set_timeout(duration) <| () => { .. }
      //
      // The call was checked with ONE argument against a two-parameter
      // declaration, and reported:
      //
      //     no method matching set_timeout(int)
      //
      // on code `moon check` accepts. The pipe is the second argument.
      if op == OpPipe {
        match a.kind {
          ECall(name, cargs, clabels) => {
            let pvals : Array[AbsVal] = []
            for x in cargs {
              pvals.push(self.eval(x, env))
            }
            pvals.push(self.eval(b, env))
            let plabels : Array[String] = []
            for x in clabels {
              plabels.push(x)
            }
            plabels.push("")
            return self.eval_call(name, pvals, plabels, env, e.span)
          }
          _ => ()
        }
      }
      let l = self.eval(a, env)
      let r = self.eval(b, env)
      self.binop(op, l, r, e.span)
    }
    ECall(name, args, labels) => {
      let vals : Array[AbsVal] = []
      for a in args {
        vals.push(self.eval(a, env))
      }
      self.eval_call(name, vals, labels, env, e.span)
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
    EMethodCall(base, _, args, _) => {
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
    // A `..` CHAIN LINK. The arguments and the receiver are evaluated, and the
    // VALUE IS THE RECEIVER'S -- the one place this lens does not return AAny
    // where `EMethodCall` does.
    //
    // That is not optimism, it is the settled reading
    // (`_verify/settle_0465_dotdot_chain.ps1`): `recv..name(args)` calls `name`,
    // discards its result, and evaluates to `recv`. `S::new()..get().v` is accepted
    // where `S::new().get().v` REJECTs with 4028, and `get` returns Int, so the `..`
    // link demonstrably did not produce an Int. Handing back the receiver is the
    // claim the settle licenses; AAny would be discarding a fact the language
    // guarantees, and the method's return value would be inventing one.
    //
    // WHAT IS NOT MODELLED is the write a mutating method performs. `w..write(b"x")`
    // hands on the receiver as it was read, and no mutation is recorded -- the same
    // fail-toward-silence trade `EMethodCall` makes, and a statement about what is
    // untracked rather than a guess about the result.
    //
    // A qualifier receiver is not evaluated, for the same reason the walk does not
    // resolve it, and yields AAny because a package has no value.
    EDotDot(base, _, args, _) => {
      let mut out : AbsVal = AAny
      if !base.is_qualifier() {
        out = self.eval(base, env)
      }
      for a in args {
        let _ = self.eval(a, env)
      }
      out
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
    //
    // 0495 AND THE PATTERN NAMES. The comprehension BINDS its parameter, and the
    // body reads it. This arm dropped the names -- `EComp(_, sources, body)` --
    // so every read of the bound name inside the body was an undefined
    // variable.
    //
    // MEASURED, moonbitlang/async 0.22.4
    // `src/internal/event_loop/event_loop.mbt:260`:
    //
    //     let leaked_handles = [
    //       for handle in self.fds.values() => @debug.to_string(handle.kind)
    //     ].join(", ")
    //
    // `handle` was reported `undefined variable 'handle'` -- on code `moon
    // check` accepts.
    //
    // THE STRUCTURAL LENS ALREADY BINDS IT, and the type lens binds it too:
    // `walk.mbt`'s `EComp` arm pushes a frame and binds each name before
    // walking the sources and the body. This lens was the only one of the
    // three that did not, so it contradicted the other two on the same line.
    //
    // The binding is in a COPY of the environment, because the comprehension's
    // parameter is scoped to the body and does not outlive it.
    EComp(vars, sources, body) => {
      for s in sources {
        let _ = self.eval(s, env)
      }
      let cenv = copy_env(env)
      for v in vars {
        cenv.set(v, AAny)
      }
      let _ = self.eval(body, cenv)
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
    // A block used as an EXPRESSION, `let x = { .. }`. The earlier statements
    // run for their effects and the TAIL is the value, so the tail is routed
    // to `eval` rather than to `exec_stmt` — executing it would discard the
    // value the `let` exists to capture.
    EBlock(body) => {
      let mut out = AAny
      for st in body {
        match st.kind {
          @ast.STail(t) => out = self.eval(t, env)
          _ => self.exec_stmt(st, env)
        }
      }
      out
    }
    // 0469. A `match` whose arms were skipped. The subject is evaluated for its
    // EFFECTS -- it is real code that runs -- and its value is discarded, because the
    // match's value comes from the arms and the arms are not modelled. `ABottom` rather
    // than `AAny`: `AAny` is absorbed by every operator arm (interp.mbt:1076, :1094),
    // which would make this indistinguishable from evaluating the subject.
    EMatch(subject) => {
      let _ = self.eval(subject, env)
      ABottom
    }
    // A tuple literal; `(e)` grouping is folded at parse time, so every
    // ETuple is a real tuple. Elements are evaluated; there is no tuple
    // value in the lattice, so the result is the type name.
    //
    // `()` IS NOT A ZERO-ELEMENT TUPLE: it is the unit value, type `Unit`, and
    // this branch said `Tuple` for it. That was invisible until 0.4.26 made the
    // tail expression a real return value, at which point `fn f() -> Unit { () }`
    // started reporting `f() -> Tuple` -- trading a wrong-but-harmless `None`
    // for a wrong-and-contradictory `Tuple`. The empty case is therefore Unit,
    // spelled `None` the way `join_vals` already spells it.
    ETuple(elems) => {
      if elems.length() == 0 {
        return AType("None")
      }
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
    // A REGEX LITERAL, `re"^a"`. The pattern text is carried, not analysed, and
    // this lattice has no Regex value -- so the answer is AAny, "a value of a
    // type this lens does not name". It is deliberately NOT AType("None"):
    // "None" is a claim that the value is Unit, and a Regex is not Unit.
    ERegex(_) => AAny
    // A REGEX CAPTURE, `re"..." as name`. The base is evaluated and the name
    // is BOUND in the environment, exactly as an `is` binding is -- the captured
    // text is a value the body reads, and the corpus reads it ten lines later
    // (`async 0.22.4 src/http/request.mbt:66`).
    //
    // The value bound is AAny: this lattice has no String-view value for a
    // captured group, and the name's USE is what matters -- whether the read
    // resolves, not what it holds.
    EAsBind(base, name) => {
      let _ = self.eval(base, env)
      env.set(name, AAny)
      AAny
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
    EIs(base, bindings) => {
      let _ = self.eval(base, env)
      for b in bindings {
        if b != "" {
          env.set(b, AAny)
        }
      }
      AAny
    }
    // `base as &Trait`: the base is evaluated, the result is AAny.
    //
    // AAny rather than the base's abstract value on purpose. The abstract
    // interpreter prunes on concrete booleans and folds on concrete ints, so
    // passing a value through would let a cast on a literal (`1 as &Trait`
    // is a type error, but `x + 1 as &Trait` is not) fold and prune a branch
    // the compiler never prunes. AAny keeps the path live — the same reason
    // `EIs` above returns AAny instead of ABool.
    ECast(base) => {
      let _ = self.eval(base, env)
      AAny
    }
    // `expr catch { ... }`: the base is evaluated and the result is AAny.
    //
    // AAny rather than the base's value, for the reason `ECast` gives — the
    // abstract interpreter prunes on concrete booleans, and a `catch` whose
    // arms are not modelled must not let a folded base decide which branch a
    // later condition takes. The arms are not evaluated: they are alternative
    // control paths, and the interpreter has no notion of which one an error
    // would select.
    ECatch(base, _) => {
      let _ = self.eval(base, env)
      AAny
    }
    // `noraise { .. }` prunes for the same reason and on the same grounds as the
    // `catch` it is attached to: the base here is the `ECatch` node, so evaluating
    // it already evaluates the try expression, and a `noraise` block whose arms
    // are not modelled must not let a folded value decide a later branch either.
    ENoRaise(base, _) => {
      let _ = self.eval(base, env)
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
        // Int / Int IS Int. `7 / 2` is 3 -- MEASURED by running it -- and the
        // "/ is always a float" rule was a false claim about MoonBit.
        //
        // IT WAS KEPT FOR A MEASURED REASON, and the reason is now OVER:
        // "returning AInt(i / j) here was implemented in 0.4.14 and measured
        // across 933 files on four corpora: the report streams came out
        // byte-identical, and no test could tell the two apart". The
        // difference could not be OBSERVED then. IT CAN NOW BE OBSERVED, and
        // the measurement that shows it is moonbit_image 0.3.7 `fim.mbt`:
        //
        //     let hs = h / 2              h : Int
        //     fim_gray_a8(w, hs, even)    the parameter is `h : Int`
        //
        // reported `no method matching fim_gray_a8(Any, float, Any)` -- four
        // findings, all of them false positives on code `moon check` accepts.
        //
        // The divide-by-zero guard is the one `OpMod` already has, for the
        // same reason: MoonBit's compiler inserts one, so folding `1 / 0`
        // here would abort the whole scan rather than produce a finding.
        OpDiv => if j == 0 { ABottom } else { AInt(i / j) }
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
          // A division with an UNKNOWN operand has an UNKNOWN result. "float"
          // was a claim here, and it was the wrong one in both directions:
          // `x / 2` where `x` is an `Int` is an `Int`, and `x / 2` where `x`
          // is a `Float` is a `Float`. `AAny` claims neither.
          OpDiv => AAny
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
              // Int / Int IS Int. See the `OpDiv` arm of the constant-fold
              // above and `div_type` below for the measurement that shows it.
              AType(div_type(l, r))
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
          // TWO STRINGS COMPARE. The arm accepted only `numeric(l) &&
          // numeric(r)`, and a String comparison is legal MoonBit -- settled
          // with the toolchain: `fn cmp_string(a : String, b : String) -> Bool
          // { a <= b }` COMPILES, with no error.
          //
          // MEASURED, the corpus paid for the missing case: proton 0.3.4
          // reported `no method matching <=(str, str)` and
          // `>=(str, str)` -- eight findings, on code `moon check` accepts.
          //
          // The `strv(l) && strv(r)` test is the same one the `OpAdd` arm
          // uses, and it is as narrow: a MIXED comparison (`int <= str`) still
          // fails both halves and is still reported.
          if (numeric(l) && numeric(r)) || (strv(l) && strv(r)) {
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
        OpPipe =>
          // The PIPE IS A CALL, and this analyzer does not know a callee's return
          // type, so the result is `Any`. Not `ABottom` and not a method error:
          // every arm above would report "no method matching <|(l, r)" against
          // code `moon check` compiles, and the operands of a pipe are an Int and
          // a FUNCTION on purpose -- `1 |> inc` -- so no arithmetic predicate here
          // could match. `Any` keeps inferring, which is the same treatment a
          // cross-package value gets.
          AAny
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
        OpMatch =>
          // THE REGEX MATCH. Its result is a Bool -- settled against the
          // toolchain (`_verify/settle_0494_parse_backlog.ps1`, row `a3`, with
          // the control `a4` REJECTing the same expression against an Int) --
          // and its RIGHT operand is a Regex, which this lattice cannot name.
          //
          // So the operand types are NOT checked, and the result is the answer.
          // A method error here would be a claim about a Regex this lens does
          // not have, and every arm above would report one against code
          // `moon check` compiles.
          AType("bool")
      }
    }
  }
}

///|
/// The type of a division, given the two operand types.
///
/// MoonBit's `/` on two INTEGERS is INTEGER division -- `7 / 2` is 3 -- and
/// only a `Float` operand makes the result a `Float`. The rule used to be "a
/// division is always a float", and it was kept for a MEASURED reason: the
/// difference could not be observed. It can be observed now, and the
/// measurement that shows it is moonbit_image 0.3.7 `fim.mbt` -- four false
/// positives, `no method matching fim_gray_a8(Any, float, Any)` and its
/// siblings, on code `moon check` accepts.
///
/// The unknown case is `AAny`, and it is handled by the CALLER: this function
/// is only reached with concrete operand types.
fn div_type(l : AbsVal, r : AbsVal) -> String {
  let lname = val_name(l)
  let rname = val_name(r)
  if lname == "float" || rname == "float" {
    return "float"
  }
  "int"
}

///|
/// The result type of a binary operator.
///
/// The `/` arm used to return "float" unconditionally, which is wrong for
/// Int/Int (`7 / 2` is 3). It was measured in 0.4.14: removing that arm
/// changed nothing across 933 files on four corpora, byte for byte, so it
/// stayed until the difference could be OBSERVED. IT CAN NOW BE OBSERVED --
/// see `div_type` -- and the arm follows the same rule.
fn bin_widen(op : @ast.BOp, l : AbsVal, r : AbsVal) -> String {
  let lname = val_name(l)
  let rname = val_name(r)
  if op == OpDiv {
    return div_type(l, r)
  }
  if lname == "float" || rname == "float" {
    return "float"
  }
  if lname == "Any" || rname == "Any" {
    return "Any"
  }
  // A STRING CONCATENATION IS A STRING. The arm was missing, and the `+` on
  // two strings fell through to the "int" below -- so `"a" + "b"` evaluated to
  // the type "int".
  //
  // MEASURED, and the consequence was a false positive on the OUTER `+` of a
  // concatenation: `("a" + "b") + "c"` has an "int" left operand and a "str"
  // right one, and the operator check reported
  //
  //     no method matching +(int, str)
  //
  // on code `moon check` accepts. moui 0.1.12
  // `render/common/provider_shell.mbt:10` is one of the sites.
  //
  // The arm is placed HERE, after the "Any" arm and before the "int" fallback,
  // and that position is the point: `bin_widen` is reached with two STRINGS
  // only from the `OpAdd` arm's `strv(l) && strv(r)` test, so this arm cannot
  // touch the arithmetic path. It is not a general "strings are not ints" rule
  // -- it is the one missing case of a function whose every other case was
  // already there.
  if lname == "str" && rname == "str" {
    return "str"
  }
  "int"
}

///|
/// THE CALL DISPATCH, shared by an ordinary call and by the pipe's
/// `call <| argument` shape.
///
/// It is ONE function because the two paths must agree: the pipe's shape is a
/// call with one more argument, and a check that the ordinary call made and
/// the piped call did not would report the same program twice or not at all.
fn Interp::eval_call(
  self : Interp,
  name : String,
  vals : Array[AbsVal],
  labels : Array[String],
  env : Map[String, AbsVal],
  sp : @core.Span,
) -> AbsVal {
  // A call to a name BOUND IN THIS FRAME -- a function-typed parameter, or
  // a local `let f = fn(...)`. The name IS bound: the walk sees the
  // binding, and the type lens types it. This lens used to dispatch only
  // through the top-level method table, so a call to a callback parameter
  // was reported as `undefined function 'on_select'` -- an ERROR, on code
  // `moon check` accepts, and a finding the structural lens contradicted.
  //
  // The value of such a binding is unknown here (the fresh value for a
  // function-typed parameter is `AAny`), so the honest answer for the
  // call's RESULT is "a value of unknown type".
  //
  // The method table is consulted first, so a top-level function is still
  // dispatched as one.
  if !self.methods.contains(name) && env.contains(name) {
    return AAny
  }
  // A qualified call whose TAIL is bound: `PixelFormat::RGBA8`. Same rule
  // as the qualified READ above, and the same reason.
  //
  // NOT "any `@`-prefixed call is fine": the repository pins the opposite,
  // because a cross-package CALL is a name the table must carry. With an
  // empty table `@core.IfaceSymTab::empty()` is reported, and with the
  // table carrying the full qualified name it is not
  // (`pipeline_test.mbt`, "an extern_iface carrying the names removes the
  // self-scan findings" and its negative control). The `@`-prefixed NAME
  // read above is a different case, and it is not this one.
  if !self.methods.contains(name) && self.tail_bound(name, env) {
    return AAny
  }
  self.call(name, vals, labels, sp)
}

///|
/// THE NAMES DECLARED MORE THAN ONCE IN THIS FILE.
///
/// MoonBit allows two top-level functions of the same name, and `#cfg` is how
/// real code reaches it. moonbitlang/async 0.22.4
/// `src/internal/fd_util/fd_util.mbt:58,71`:
///
///     #cfg(not(platform="windows"))
///     extern "C" fn close_ffi(fd : Fd) -> Int = "close"
///     #cfg(platform="windows")
///     extern "C" fn close_ffi(fd : Fd, is_socket~ : Bool) -> Int = "moonbitlang_async_close_fd"
///
/// A name with two declarations has NO SINGLE SIGNATURE, and the lens cannot
/// know which one is live. So the arity and parameter-type checks must not run
/// against either of them.
///
/// MEASURED, what happens when they do. The two call sites disagree about the
/// arity, so whichever declaration the lens picks, ONE of them is reported:
///
///     close_ffi(fd, is_socket=kind is Socket)   -- fd_util.mbt:76
///     no method matching close_ffi(Any, Any)
///
///     close_ffi(fd)                             -- fd_util.mbt:64
///     no method matching close_ffi(Any)
///
/// Both are false positives on code `moon check` accepts, and the two
/// findings are the SAME defect seen from the two sides: the lens picked one
/// declaration and compared the other call site against it.
///
/// The dispatch for an ambiguous name is the one a cross-file name gets: an
/// unknown-returning call. The name IS defined -- the file says so twice --
/// and what the lens cannot say is which signature it has.
fn duplicate_names(fns : Array[@walk.FnInfo]) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  for f in fns {
    match out.get(f.name) {
      Some(_) => out.set(f.name, true)
      None => out.set(f.name, false)
    }
  }
  out
}

///|
fn Interp::call(
  self : Interp,
  name : String,
  vals : Array[AbsVal],
  labels : Array[String],
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
      // A NAME DECLARED TWICE HAS NO SINGLE SIGNATURE, so the arity and the
      // parameter types cannot be checked against either declaration. The
      // dispatch is the one a cross-file name gets: an unknown-returning call.
      //
      // The name IS defined -- the file says so twice -- and what the lens
      // cannot say is WHICH signature it has. See `duplicate_names` for the
      // corpus sites and for the two findings this removes.
      if def.ambiguous {
        return AAny
      }
      // THE ARGUMENT -> PARAMETER MAP.
      //
      // MoonBit lets a call supply its arguments BY LABEL, and when it does the
      // LABELS decide the binding, not the positions. This dispatch compared
      // POSITIONALLY, which is the type lens's mistake -- fixed there, but
      // never here -- and it showed up as
      //
      //     no method matching RouteHistoryState::from_routes(Any, str, str)
      //
      // MEASURED, wzzc-dev/moui 0.1.12,
      // `views/navigation/navigation_routing.mbt:157`:
      //
      //     RouteHistoryState::from_routes(routes=snapshot.routes, title~, source~)
      //
      // The callee declares FOUR parameters -- `routes~`, `cursor?`, `title?`,
      // `source?` -- and the call supplies three, by label, omitting the
      // optional `cursor?`. Compared by position, the second argument (`title~`,
      // a string) was checked against `cursor?` (an Int), and the call was
      // rejected.
      //
      // The labels were IN THE AST the whole time -- `ECall`'s third field is
      // the label list, parallel to the arguments -- and this lens DISCARDED
      // them. The `x~` shorthand is a label too: it is the same field.
      //
      // The labels are only usable when the parameter NAMES are known, and
      // they are known for a callee in THIS file (`def.pnames`). A callee in
      // another file never reaches this branch at all: the method table is
      // per file, and a name the table does not hold is dispatched as an
      // unknown-returning call.
      let declared = def.ptypes.length()
      // param index -> argument index; -1 means "not supplied"
      let by_param : Array[Int32] = []
      let mut k = 0
      while k < declared {
        by_param.push(-1)
        k += 1
      }
      let mut any_label = false
      let mut li = 0
      while li < labels.length() {
        if labels[li] != "" {
          any_label = true
        }
        li += 1
      }
      // The names and the types must be the SAME function's, or the index of a
      // label would mean nothing. They come from the same source when the
      // signature lookup found this function; when it did not, the label map
      // is not built and the call is compared positionally, which is what
      // happened before.
      let aligned = def.pnames.length() == declared
      let mut ok = true
      if any_label && aligned {
        // 1. THE LABELLED ARGUMENTS, by name.
        let mut i = 0
        while i < vals.length() && i < labels.length() {
          let lab = labels[i]
          if lab != "" {
            let mut found = -1
            let mut j = 0
            while j < declared {
              if def.pnames[j] == lab {
                found = j
                break
              }
              j += 1
            }
            if found < 0 {
              // A LABEL THE CALLEE DOES NOT HAVE. The toolchain rejects this
              // with 4085; settled in `_verify/settle_0493_lens_values.ps1`,
              // row `d4_control_unknown_label`.
              ok = false
            } else if by_param[found] >= 0 {
              // THE SAME LABEL TWICE.
              ok = false
            } else {
              by_param[found] = i
            }
          }
          i += 1
        }
        // 2. THE POSITIONAL ARGUMENTS, in order, into the parameters that no
        //    label has claimed.
        let mut next = 0
        let mut i2 = 0
        while i2 < vals.length() {
          let mut claimed = false
          let mut c = 0
          while c < declared {
            if by_param[c] == i2 {
              claimed = true
            }
            c += 1
          }
          if !claimed {
            while next < declared &&
                  (by_param[next] >= 0 || omittable_at(def, next)) {
              next += 1
            }
            if next >= declared {
              // MORE ARGUMENTS THAN THE CALLEE DECLARES.
              ok = false
            } else {
              by_param[next] = i2
              next += 1
            }
          }
          i2 += 1
        }
        // 3. A PARAMETER THAT WAS NOT SUPPLIED must be one a call may omit.
        //    The toolchain rejects a call that omits a required one with
        //    4086; settled in the same script, row
        //    `d3_labelled_call_omits_a_required`.
        let mut j2 = 0
        while j2 < declared {
          if by_param[j2] < 0 {
            let may_omit = j2 < def.pomittable.length() && def.pomittable[j2]
            if !may_omit {
              ok = false
            }
          }
          j2 += 1
        }
      } else {
        // 1'. THE POSITIONAL COMPARISON: every POSITIONAL parameter type must
        //     accept its argument (union-splitting lite; Any parameters accept
        //     everything).
        //
        //     AND THE ARGUMENTS FILL THE POSITIONAL PARAMETERS -- NOT ALL OF
        //     THEM. A parameter a call may OMIT is not filled positionally;
        //     see `omittable_at` for the measurement and the corpus site.
        let mut argi = 0
        let mut pi = 0
        while pi < declared {
          if !omittable_at(def, pi) {
            let pt = def.ptypes[pi]
            let arg = match vals.get(argi) {
              Some(v) => v
              None => ABottom
            }
            if !(pt == "" || pt == "Any") && !vmatches(arg, pt) {
              ok = false
            }
            argi += 1
          }
          pi += 1
        }
      }
      // THE TYPE CHECK, per PARAMETER, for the labelled call. The positional
      // call did it above.
      if any_label && aligned {
        let mut j3 = 0
        while j3 < declared {
          let ai = by_param[j3]
          if ai >= 0 {
            let pt = def.ptypes[j3]
            let arg = vals[ai]
            if !(pt == "" || pt == "Any") && !vmatches(arg, pt) {
              ok = false
            }
          }
          j3 += 1
        }
      }
      // THE ARITY RULE. A call may OMIT the parameters the function declares
      // optional, and it may not supply more arguments than the function
      // declares:
      //
      //     declared - nopt  <=  arguments  <=  declared
      //
      // The rule used to be `arguments == declared`, which rejected every
      // call that omitted an optional parameter -- measured on moui 0.1.12:
      // `control_state` declares SEVEN parameters and is called with THREE
      // arguments, and `wire_string` declares two and is called with one.
      //
      // It is NOT a blanket "any count is fine": supplying MORE arguments than
      // the function declares is still an error, and the floor is the number
      // of REQUIRED parameters, so a call that omits a required one is still
      // reported.
      if vals.length() > declared || vals.length() < declared - def.nopt {
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
      // THE VALUES IN PARAMETER ORDER. A labelled call supplies them in the
      // CALL's order, and the callee's body reads them by the PARAMETER's
      // name -- so the body would read the wrong values without this.
      let ordered : Array[AbsVal] = []
      if any_label && aligned {
        let mut j4 = 0
        while j4 < declared {
          let ai = by_param[j4]
          ordered.push(
            match vals.get(ai) {
              Some(v) => v
              None => ABottom
            },
          )
          j4 += 1
        }
      } else {
        let mut j5 = 0
        while j5 < declared {
          ordered.push(
            match vals.get(j5) {
              Some(v) => v
              None => ABottom
            },
          )
          j5 += 1
        }
      }
      self.analyze_fn(def, ordered)
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
      // HISTORY (0.4.16 -> 0.4.17). A rule used to sit here: "a call
      // qualified on an AMBIENT TYPE — `Array::make`, `Byte::default`,
      // `Int::max` — is a builtin method, so do not report it undefined." It
      // was written for a real finding (riantr/moonbit_labeler 0.2.13,
      // `rasterizer.mbt:74`) and then REVERTED, on the grounds that it was
      // unobservable: two of its mutations survived and it changed nothing in
      // a hand-built probe.
      //
      // Both of those grounds were wrong, and the second one explains the
      // first. This lens analyzes a body only when the body is REACHED from a
      // top-level statement, and every probe copied the `fn PixelBuffer::new`
      // DEFINITION without ever calling it — so nothing here ran, and a rule
      // that would have fired could not show itself. The real file calls it at
      // line 1379. With the call restored the finding reproduces, and the rule
      // is observable.
      //
      // It is still not what shipped, because the TABLE is better: the rule
      // also silences `Array::mkae`, and there is a control for exactly that.
      // `@core.builtin_method_names()` carries the measured names, so a builtin
      // type with a method that does not exist is still reported. See
      // src/core/builtin_methods.mbt.
      //
      // One consequence worth knowing, because it will look like a new bug and
      // is the opposite. A call that reports returns ABottom, and the enclosing
      // call is then never reached — so a nested chain reported only its
      // INNERMOST name. `ZzMissing::nope(4, Byte::default())` reported
      // `Byte::default` and hid `ZzMissing::nope`. Teaching the lens
      // `Byte::default` therefore REVEALED the outer one, which is a real
      // missing name and is now correctly reported. Fixing an over-report can
      // raise the count on a file; it is uncovering, not inventing.
      self.report(@core.FUndefinedName, "undefined function '\{name}'", sp)
      ABottom
    }
  }
}

///|
/// True when the TAIL of a qualified `name` is bound somewhere.
///
/// THE SAME RULE THE STRUCTURAL LENS USES, and the reason the two lenses must
/// agree: `walk.mbt`'s `tail_bound` says "a qualified path whose TAIL is bound
/// is a real name -- `Layer::ReLU` is a unit enum variant, and the harvest
/// binds `ReLU` but not the whole path". This lens had no such rule, so every
/// qualified read of a constructor was `undefined variable 'PixelFormat::RGBA8'`
/// while the structural lens -- which has the rule -- stayed silent on the same
/// line. Two lenses, one line, opposite answers.
///
/// The rule is a TAIL rule and not a blanket "any qualified name is fine",
/// because a blanket silences real findings the repository pins on purpose:
/// `Array::mkae` (a builtin type with a method that does not exist) and
/// `ZzMissing::nope` (an unknown head) must both still be reported. The tail
/// of each is not bound, so the rule does not touch them.
///
/// Only consulted once the whole path has failed to resolve, so it can never
/// turn a resolvable path into an unresolved one.
fn Interp::tail_bound(
  self : Interp,
  name : String,
  env : Map[String, AbsVal],
) -> Bool {
  let tail = @core.path_tail(name)
  if tail == "" || tail == name {
    return false
  }
  if self.ambient.contains(tail) ||
    self.extern_iface.has_type(tail) ||
    self.extern_iface.has_value(tail) ||
    self.ctors.contains(tail) {
    return true
  }
  if env.contains(tail) || self.globals.contains(tail) {
    return true
  }
  false
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
  // THE FUNCTION'S VALUE. `ret_vals` carries the `return`s and the body's
  // trailing expression, and it is the right answer whenever it is not empty.
  //
  // When it IS empty, the body's last statement had no value of its own --
  // and the one case that HAS a value the `ret_vals` route cannot see is an
  // `if`, whose branch's value `exec_stmt` records in `last_value`. Without
  // that, `join_vals([])` answered "None" and every operator applied to the
  // result was reported as a method error.
  //
  // ABottom is NOT substituted for "None" here: a function whose body's last
  // statement is a `let` returns UNIT, and "None" says that, while ABottom
  // says "no value at all" -- a different claim, and a stronger one.
  //
  // BUT "None" IS A CLAIM, AND THERE ARE TWO SITUATIONS WHERE IT IS FALSE.
  //
  //   - an EXTERN function. Its body is written in another language, so there
  //     is nothing here to execute, and the DECLARED return type is the only
  //     statement about what it returns that the file makes.
  //   - a body whose last statement is an `if` whose branch value is not
  //     modelled. A `match` inside a branch has no value this lens can name,
  //     and "no value" is not "the value None".
  //
  // MEASURED, wzzc-dev/moui 0.1.12, the per-function view, FOUR findings of
  // this shape:
  //
  //     no method matching clamp_int(None, int, Any)
  //     no method matching web_string_append_char(None, Any)
  //     no method matching web_finish_create_string(None)
  //     no method matching >(None, float)
  //
  // on code `moon check` accepts. The first is the `match` inside an `if`
  // branch (`views/text/text_input_editing.mbt:42`); the last three are
  // extern functions (`backend/web/web_host.mbt:357` and `:359`,
  // `backend/linux/linux_services.mbt:183`).
  //
  // The DECLARED return type is used only when the declaration says something
  // concrete. A function with no return annotation keeps the "None" answer,
  // because "it returns Unit" is the only claim an unannotated body makes,
  // and `cycle_ret` is `AAny` for exactly that case.
  //
  // 0495 AND THE EXTERN. There is ONE case where the body was never read and
  // the "None" answer is therefore not a claim about Unit either: a function
  // with NO BODY. An `extern "C"` declaration has no MoonBit body to execute,
  // and a stub (`= "moonbitlang/async" "thread_pool/make_open_job"`) has none
  // either. "None" says "the value None", which is a claim about a value the
  // file never mentions.
  //
  // MEASURED, moonbitlang/async 0.22.4 `src/socket/ffi.mbt:16`:
  //
  //     extern "C" fn make_tcp_socket_ffi(family : AddrFamily) -> @fd_util.Fd = "..."
  //
  // The declared return type `@fd_util.Fd` is a CROSS-PACKAGE type, so the type
  // lens cannot name it and `cycle_ret` is `AAny`. The extern's result was
  // therefore "None", and the comparison two lines later read it as such:
  //
  //     no method matching <(None, int)
  //
  // on code `moon check` accepts -- the comparison is `if sock < 0`, and `sock`
  // is a file descriptor.
  //
  // THE HONEST ANSWER IS `AAny`: the lens knows the call has a value and does
  // not know what it holds. That is the same answer a cross-package name gets,
  // and the operator arms already absorb it (`binop` returns early when either
  // operand is `AAny`), so the comparison is no longer reported.
  let ret = if self.ret_vals.length() > 0 {
    join_vals(self.ret_vals)
  } else if self.last_value != ABottom {
    self.last_value
  } else if def.cycle_ret != AAny {
    def.cycle_ret
  } else if def.body.length() == 0 {
    AAny
  } else {
    join_vals(self.ret_vals)
  }
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
/// Which parameters a call may OMIT, one flag per parameter.
///
/// PARALLEL TO `fn_pnames` AND `fn_param_tys`, and it is read from the SAME
/// loop over `f.params` for the same reason they are parallel at all: two
/// readers over one list is how the 0.4.18/0.4.20 "name readers drift" lesson
/// repeats, and a flag list that drifts from the name list would mis-index
/// every argument of every labelled call.
///
/// `n_omittable` is the COUNT of these flags, and the count is not enough for
/// the dispatch: a call that supplies a labelled parameter and omits a
/// REQUIRED one has to be told apart from a call that omits an optional one,
/// and only the per-parameter flag can do that.
fn fn_pomittable(f : @walk.FnInfo) -> Array[Bool] {
  let out : Array[Bool] = []
  for p in f.params {
    out.push(p.omittable)
  }
  out
}

///|
/// MAY PARAMETER `i` BE OMITTED BY A CALL?
///
/// This is the question the positional alignment asks, and the answer is what
/// separates a POSITIONAL parameter from an OMITTABLE one.
///
/// A parameter a call may OMIT (`name? : T`, or `name~ : T = default`) is NOT
/// filled positionally: MoonBit binds it by label, or leaves it at its
/// default. Counting it as a positional slot shifts every later argument one
/// to the left.
///
/// MEASURED, moonbitlang/async 0.22.4
/// `src/internal/event_loop/thread_pool.wasm.mbt:703`:
///
///     fn JobHandle::inotify_add_watch(
///       inotify : @fd_util.Fd,
///       path : @os_string.OsString,
///       path_len? : Int = path.to_string().length(),
///       is_dir : Bool,
///     ) -> JobHandle
///
/// and the call `JobHandle::inotify_add_watch(inotify, path, is_dir)` -- three
/// arguments, and the third was compared against `path_len? : Int`, so a Bool
/// was checked against an Int:
///
///     no method matching JobHandle::inotify_add_watch(Any, Any, bool)
///
/// on code `moon check` accepts. The toolchain is the authority here and the
/// corpus is the proof: it binds `is_dir` to `is_dir` and leaves `path_len?` at
/// its default, which is only possible if the omittable parameter is not a
/// positional slot.
///
/// Six sites in that one file share the shape, and the labelled call path has
/// the same defect: a positional argument was matched against the omittable
/// parameter and the parameter AFTER it was left unsupplied, which the
/// dispatch then reported as a missing required argument.
fn omittable_at(def : MethodDef, i : Int32) -> Bool {
  if i < 0 || i >= def.pomittable.length() {
    return false
  }
  def.pomittable[i]
}

///|
/// How many of a function's parameters a call may OMIT -- the ones declared
/// `name? : T`, and the ones declared `name~ : T = default`.
///
/// MEASURED, the arity check used to compare the argument count against the
/// DECLARED count, so every call that omitted an omittable parameter was
/// reported as a method error. `fn control_state(foreground~ : @core.Color,
/// background~ : @core.Brush, border? : @core.BorderStyle, radius? : Double = 0.0,
/// ...)` declares SEVEN parameters and is called with THREE arguments
/// throughout moui 0.1.12, and every one of those calls was reported `no
/// method matching control_state(Any, Any, Any)` -- on code `moon check`
/// accepts.
///
/// The count is of OMITTABLE parameters wherever they sit, not of a trailing
/// run: a parameter that may be omitted reduces the floor by one, and a
/// parameter that may not raises it by one. The rule is therefore
///
///     required <= arguments <= declared
///
/// which is the whole of what the AST can say.
///
/// THE `~` MARKER ON ITS OWN IS NOT OMISSIBLE, and the toolchain settles it.
/// A `~` parameter is a LABEL: it must be supplied BY LABEL, and a call that
/// omits it is rejected -- so it is REQUIRED, and it does not reduce the floor.
///
///     REJECT 4086   `fn f(x~ : Int)` called as `f()`
///                    "The labels x~ are required by this function, but not
///                     supplied."
///     REJECT 4086   `fn f(x~ : Int)` called as `f(1)` -- a POSITIONAL pass
///                    also fails, with 4080 as well: the function "requires 0
///                    positional arguments, but is given 1".
///     ACCEPT         `fn f(x~ : Int)` called as `f(x=1)` -- by LABEL.
///
/// So `~` alone contributes NOTHING to the omittable count, and the two
/// spellings that do are `name? : T` (the `?` marker) and `name~ : T = default`
/// (a default value, which the toolchain allows only on a `~` -- a default on
/// a POSITIONAL parameter is rejected with 3010).
///
/// THIS COMMENT WAS WRONG AND SAID SO, and the wrongness is worth keeping.
/// It used to read: "`fn f(x~ : Int)` called as `f(1)` is accepted, but
/// `f(x=1)` is rejected with 4085, 'This function has no parameter with label
/// x~'." That is INVERTED on both halves, and the 4085 belongs to a different
/// row entirely -- it is the error for a label on a POSITIONAL parameter
/// (`fn f(x : Int)` called as `f(x=1)`), not for a label on a `~` one.
///
/// The conclusion the wrong evidence was offered for -- "`~` does not make a
/// parameter omittable" -- was RIGHT, and the code was right with it, because
/// the parser sets `omittable` only for `?` and for a default value. So this
/// was a false STATEMENT in a comment, not a false rule in the analyzer.
///
/// It survived because it was read as a settled fact rather than as a
/// measurement, and the repository already had the CORRECT version of it in a
/// different file: `src/lexer/lexer.mbt`'s `TTilde` note (0.4.18) says a `~`
/// parameter "must be supplied BY LABEL" and that the compiler "rejects a
/// positional pass with 'The labels f~ are required by this function, but not
/// supplied.'" That is exactly right, and it was written before 0490.
///
/// The toolchain was UPGRADED (0.1.20261012 -> 0.1.20261016) in the middle of
/// the 0490 release gate, which is what forced every settled fact to be
/// re-checked against what is actually installed -- and this one was found
/// inverted by that re-check rather than by the upgrade: the old toolchain
/// agrees with the new one on all eighteen rows of
/// `_verify/_settle_0490_resettle.ps1`.
///
/// => 判据: A SETTLED FACT IS A CLAIM ABOUT A TOOLCHAIN, AND THE CLAIM HAS TO NAME
/// THE VERSION. A comment that says "the toolchain settles that" and then
/// states the OPPOSITE of what the toolchain says is worse than no comment at
/// all, because the next reader inherits it as a premise. And the two ways a
/// fact like this rots are BOTH live here: the toolchain moves, and the
/// evidence gets written down backwards. The re-settle that caught it was
/// fifteen rows and one package each -- cheap.
fn n_omittable(f : @walk.FnInfo) -> Int32 {
  let mut n = 0
  for p in f.params {
    if p.omittable {
      n += 1
    }
  }
  n
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
  enum_ctors : Array[String],
) -> Array[String] {
  let it = new_interp(file, extern_iface)
  for c in enum_ctors {
    it.ctors.set(c, true)
  }
  let dupes = duplicate_names(wr.fns)
  for i, f in wr.fns {
    let sig : @types.Sig? = sig_at(tr, i)
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
      pomittable: fn_pomittable(f),
      nopt: n_omittable(f),
      cycle_ret,
      ambiguous: match dupes.get(f.name) {
        Some(d) => d
        None => false
      },
      body: f.body,
      line: f.span.start.line,
    })
  }
  collect_local_fns(m.body, it.local_fns)
  it.run_top(m, true)
  it.run_top(m, false)
  it.summarize_sigs()
}

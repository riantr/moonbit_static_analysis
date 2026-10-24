// core: the unified report model. Every finding carries the lens(es) that
// saw it — LStructural (binding walk), LType (symbols + inference),
// LBehavior (abstract execution) — so the pipeline can merge complementary
// detections of the same defect into one report instead of three echoes.

///|
pub(all) struct Pos {
  line : Int32
  col : Int32
} derive(Eq)

///|
pub(all) struct Span {
  start : Pos
  end : Pos
} derive(Eq)

///|
#proof_pure
pub fn pos(line : Int32, col : Int32) -> Pos {
  { line, col, }
}

///|
#proof_pure
pub fn span_at(line : Int32, col : Int32, len : Int32) -> Span {
  { start: pos(line, col), end: pos(line, col + len), }
}

///|
#proof_pure
pub fn zero_span() -> Span {
  span_at(1, 1, 0)
}

///|
/// The LAST segment of a qualified path: `Layer::ReLU` -> `ReLU`. Returns `""`
/// when the name is not qualified.
///
/// Why this exists. `Layer::ReLU` names an enum's unit variant, and this
/// analyzer harvests enum constructor names into the module frame — but only
/// the BARE name (`ReLU`), because the harvest sees tokens, not paths. A
/// lookup of the whole path therefore failed, while the same variant written
/// as a call (`Layer::Conv2d(p)`, a payload variant) resolved, because the
/// bare name inside it is what got bound. The result was that payload variants
/// worked and unit variants did not, inside the same enum in the same file
/// (measured: 4 findings on riantr/snn_mbt 0.155.0, `src/chain.mbt`).
///
/// Only the tail is offered as a fallback, and only when the whole path has
/// already failed to resolve, so this can never turn a resolvable path into an
/// unresolved one. It can only rescue a path whose tail names something real —
/// which is precisely what a unit enum variant is.
// NOT `#proof_pure`: like `unqualified` below, the body builds a string with a
// `StringBuilder`, which the prover rejects (error 4207). Two annotations on
// two string-building functions, and both of them made the whole file stop
// proving.
pub fn path_tail(name : String) -> String {
  let mut out = ""
  let mut i = 0
  let chars = name.to_array()
  let n = chars.length()
  while i + 1 < n {
    if chars[i] == ':' && chars[i + 1] == ':' {
      out = ""
      let mut j = i + 2
      let buf = StringBuilder()
      while j < n {
        buf.write_char(chars[j])
        j += 1
      }
      out = buf.to_string()
    }
    i += 1
  }
  out
}

///|
/// Cross-file symbol table built from `.mbti` interface files. A name that
/// appears here is one the analyzer cannot see in the file under analysis
/// (it lives in another file, in another package, or in the stdlib) but which
/// IS a valid binding; the structural walk suppresses its "no visible
/// binding" finding and the type lens returns the shape the rest of the
/// pipeline needs to keep going.
///
/// Two name sets, because the AST cannot tell value calls from type
/// references apart by position (the type annotation lives in `SLet.ann`,
/// not in the expression tree), and the existing `lookup` returns one `Ty?`
/// for both. The walker needs only the names; the type lens wants
/// `TUnknown` for a type hit and `TUnknownFn` for a value hit — a call to a
/// known value must not fire "not callable", and its arity is unknown, so no
/// arity or argument check may run against it either.
///
/// Lives in `core` because both `walk` and `types` consume it; placing it
/// in either would create an import cycle (the type lens already takes
/// `Binding` / `FnInfo` from the structural walk).
pub struct IfaceSymTab {
  /// Declared type names: `struct Foo`, `enum Bar`, `trait Baz`, `type Quux`.
  /// A hit returns `TUnknown` (we know it is a type, we do not model its shape).
  types : Map[String, Bool]
  /// Declared value names: `pub fn new(...) -> ...`, `pub const X : ... = ...`.
  ///
  /// A hit returns `TUnknownFn` (we know it is a value; we do not model its
  /// signature, so no arity or argument check may run against it). A `.mbti`
  /// gives us the declaration name and never the parameter list, so any
  /// arity invented here would be a guess the checks would then report as
  /// fact.
  ///
  /// THE BOOL IS `is_const` (since 0.4.16). It used to be written `true` and
  /// read by nobody. It carries a distinction the type lens needs: a `const`
  /// is not a function, so typing it as `TUnknownFn` made ordinary arithmetic
  /// on it an operator mismatch. `3.0F * hz`, with `hz` a cross-package
  /// `const`, was reported `unsupported operand types for '*': 'float' and
  /// 'fn hz (signature not read)'` — measured on riantr/snn_mbt 0.155.0
  /// (`istdp.mbt`, `tripod_current_test.mbt`) and riantr/moonbit_doubleML
  /// 0.139.0 (`N_RIDGE_CASES`), four findings in total.
  ///
  /// A const gets `TUnknown` instead: we do not know its type, but we DO know
  /// it is not callable, and `TUnknown` absorbs without claiming anything.
  values : Map[String, Bool]
  /// Types a module RE-EXPORTS under a different name, mapped to the qualified
  /// name they really are: `CondVar` -> `@cond_var.Cond`, written by async
  /// 0.22.4 `src/pkg.generated.mbti:111` as
  /// `pub using @cond_var {type Cond as CondVar}`.
  ///
  /// Without this the table holds `CondVar` (from the re-export) and
  /// `Cond::Cond` (from `@cond_var`'s own interface) with nothing connecting
  /// them, so a caller writing the constructor through the re-exported name --
  /// `@async.CondVar::Cond()`, proton 0.3.4 `facade_notification.mbt:12,14` --
  /// resolves to `CondVar::Cond`, finds nothing, and is reported
  /// `undefined function`.
  ///
  /// It is a LINK, not a suppression. Settled with the toolchain in
  /// `_verify/settle_0447_condvar_alias.ps1`, 6/6, three negative controls
  /// firing: a constructor is callable through an aliased re-export, and a name
  /// that does not exist is STILL rejected through it. So the entry has to name
  /// the real type, and `alias_forms` has to re-ask the table for the member
  /// under that name. Silencing every `@mod.X::m` that looks re-exported would
  /// trade this false positive for a false negative.
  ///
  /// KNOWN LIMIT, measured rather than assumed: the key is the bare re-exported
  /// name, because `collect_iface_names` reads interface TEXT and is not told
  /// which module the text came from. Two modules that re-export different
  /// types under one name would collide, and the first one read would win. The
  /// whole table is already flat in exactly this way -- every `.mbti` name is
  /// merged unqualified -- so this is the existing design's limit and not a new
  /// one, but it is a limit and not a claim that the mapping is sound.
  aliases : Map[String, String]
}

///|
pub fn IfaceSymTab::empty() -> IfaceSymTab {
  IfaceSymTab::{ types: Map([]), values: Map([]), aliases: Map([]), }
}

///|
/// The `values` set as a plain `Map[String, Bool]`, for a caller that wants
/// the set rather than the table.
///
/// NO LENS USES THIS ANY MORE, and that is worth recording rather than
/// quietly deleting. The behavioral lens used to hold this map, and holding
/// the `values` half alone was itself a defect: a `.mbti` declares
/// `type Builder` and `pub fn Builder::new()`, so a constructor call
/// `Builder()` is in `types` and never in `values`, and the lens reported
/// `undefined function 'Builder'` while the other two stayed silent. It holds
/// the whole table now and asks both halves through `has_value` / `has_type`.
/// Kept as public API rather than removed in a 0.x.
pub fn IfaceSymTab::all_values(self : IfaceSymTab) -> Map[String, Bool] {
  self.values
}

///|
/// Record a VALUE name this table has not seen yet, as a function rather than
/// a constant.
///
/// 0502. A TYPE'S METHOD MAY BE CALLED UNQUALIFIED, inside the package that
/// declares the type: `moonbitlang/core` `immut/vector/vector.mbt:68`
/// declares `pub fn[A] Vector::makei(..)`, and
/// `immut/vector/invariants_wbtest.mbt:354` calls it as `makei(..)` — the
/// same package, the same directory, the type in scope. The toolchain accepts
/// it (core's own `moon.mod` turns the `unqualified_local_using` warning ON,
/// which is a warning about the SPELLING, not a refusal).
///
/// The harvest keeps the QUALIFIED name (`Vector::makei`, because
/// `declared_name_at` follows the `::`), so the bare `makei` was in no table
/// and the call was reported `no visible binding for 'makei'` — a false
/// positive on code `moon check` compiles. Six of them: three in
/// `invariants_wbtest.mbt` at lines 227, 229, 230 before 0502 read the match
/// arms, and three more at 354, 363, 366 after it did.
///
/// IT IS THE CALLER'S JOB TO KEEP THIS PACKAGE-LOCAL. The table this writes
/// into is the one `collect_private_symtabs` builds PER PACKAGE DIRECTORY, and
/// it is unioned only into the files of that same directory — so a method of
/// a type in package A cannot silence a name in package B. Adding the method
/// segment to the SHARED cross-file table instead would let any method name in
/// the world resolve anywhere, which is a different rule from the language's.
///
/// => 判据: a name the toolchain resolves is not a finding. The question is
/// never "is the name in the table" but "does the toolchain accept it", and
/// the answer here was measured with the compiler as the oracle.
pub fn IfaceSymTab::add_value(self : IfaceSymTab, name : String) -> Unit {
  if !self.values.contains(name) {
    // FALSE is "not a const": the bool in `values` is `is_const`, and a method
    // is a function.
    self.values.set(name, false)
  }
}

///|
/// Merge another table into this one. A name present on both sides of
/// the merge ends up in BOTH sets — the analyzer's lookup prefers
/// `values` over `types` when a name is in both, so the call shape wins
/// over the type-position read. Returns the receiver so calls can be
/// chained.
pub fn IfaceSymTab::merge(
  self : IfaceSymTab,
  other : IfaceSymTab,
) -> IfaceSymTab {
  for k, _ in other.types {
    if !self.types.contains(k) {
      self.types.set(k, true)
    }
  }
  for k, v in other.values {
    if !self.values.contains(k) {
      self.values.set(k, v)
    }
  }
  // FIRST ONE WINS, deliberately: two modules re-exporting the same bare name
  // under different types is the collision the `aliases` note records, and
  // overwriting would make the outcome depend on directory-walk order rather
  // than on the first thing that claimed the name.
  for k, v in other.aliases {
    if !self.aliases.contains(k) {
      self.aliases.set(k, v)
    }
  }
  self
}

///|
/// True when `name` is a declared value that is a CONSTANT (`pub const X : T`)
/// rather than a function.
///
/// The type lens asks this to decide between `TUnknown` and `TUnknownFn` for a
/// cross-file value. It answers `false` for a name that is not a value at all,
/// so callers must gate on `has_value` first.
pub fn IfaceSymTab::is_const(self : IfaceSymTab, name : String) -> Bool {
  match self.values.get(name) {
    Some(v) => v
    None => false
  }
}

///|
/// A NEW table holding the union of `self` and `other`, leaving BOTH
/// untouched.
///
/// `merge` mutates its receiver, which is the right shape for building one
/// table and the wrong one for combining two that are each still needed: the
/// caller that merges package B's names into the shared cross-file table gets
/// a table where package A can see package B's private names, and a genuinely
/// undefined name in A goes unreported because B declares it. Every name in a
/// symbol table is a suppression, so leaking one across a package boundary
/// silences a finding rather than producing one.
///
/// Measured context: on riantr/pyroproduct 0.1.29 the 26 false positives this
/// fixed were all package-private top-level `fn`s, and they are only correct
/// to suppress WITHIN their own package.
pub fn IfaceSymTab::union(
  self : IfaceSymTab,
  other : IfaceSymTab,
) -> IfaceSymTab {
  let out = IfaceSymTab::empty()
  for k, _ in self.types {
    out.types.set(k, true)
  }
  for k, v in self.values {
    out.values.set(k, v)
  }
  for k, v in self.aliases {
    out.aliases.set(k, v)
  }
  for k, _ in other.types {
    if !out.types.contains(k) {
      out.types.set(k, true)
    }
  }
  for k, v in other.values {
    if !out.values.contains(k) {
      out.values.set(k, v)
    }
  }
  for k, v in other.aliases {
    if !out.aliases.contains(k) {
      out.aliases.set(k, v)
    }
  }
  out
}

///|
/// The bare spelling of a name, with any leading `@pkg.` qualifier removed:
/// `@core.IfaceSymTab::empty` becomes `IfaceSymTab::empty`. A name that is
/// not qualified is returned unchanged.
///
/// This exists because the two sides of the cross-file table spell the same
/// name differently, and the difference is invisible unless you measure it.
/// A `.mbti` declares names bare — `pub fn IfaceSymTab::empty() -> Self` —
/// because that is how the declaration is written, while a use site must
/// qualify anything from another package, so the parser folds it into a
/// single string `@core.IfaceSymTab::empty` (`dotted()` in `parser`). A
/// `.mbti` never produces the qualified spelling and a use site never
/// produces the bare one, so an exact-match table entry is unreachable for
/// precisely the case the table was added for.
///
/// Measured on 0.4.4: `collect_iface_names` over a `.mbti` holding
/// `pub fn IfaceSymTab::empty()` answered `has_value("IfaceSymTab::empty")
/// = true` and `has_value("@core.IfaceSymTab::empty") = false`. Every
/// qualified cross-package reference — the normal way MoonBit code refers to
/// another package — missed, and the 0.4.3 feature was silent no-op for it.
///
/// The qualifier is dropped rather than checked, so `@a.T` matches a `T`
/// declared by any `.mbti` in the table. The table is a union over every
/// root passed to `--extern-iface-dir`, so it cannot attribute a declaration
/// to the package that made it anyway; this widens an existing looseness
/// rather than introducing one. It fails toward silence on a name that only
/// some other package declares, which is the right side to err on for a
/// table whose entire job is suppressing "no visible binding".
// NOT `#proof_pure`, and the reason is the body, not the signature: it
// allocates a `StringBuilder` and writes into it, so it is not a pure
// function and the prover rejects it (error 4207, "unsupported expression in
// pure function body"). The annotation arrived with this function, and it made
// `moon prove src/core` fail from that commit on -- a proof obligation on a
// function that cannot discharge it, so the whole file stopped proving.
//
// The other `String` function in this file, `path_tail`, is the same shape and
// carries the same note: a string in, a string built out.
//
// The six contracts that REMAIN are the ones the skill records: `pos`,
// `span_at`, `zero_span`, `Lens::rank`, `Lens::lower`, `Family::severity`.
pub fn unqualified(name : String) -> String {
  if !name.has_prefix("@") {
    return name
  }
  let chars = name.to_array()
  let mut i = 2
  while i < chars.length() && chars[i] != '.' {
    i += 1
  }
  if i >= chars.length() {
    return name
  }
  let buf = StringBuilder()
  i += 1
  while i < chars.length() {
    buf.write_char(chars[i])
    i += 1
  }
  buf.to_string()
}

///|
pub fn IfaceSymTab::has_type(self : IfaceSymTab, name : String) -> Bool {
  if self.types.contains(name) || self.types.contains(unqualified(name)) {
    return true
  }
  for alt in self.alias_forms(name) {
    if self.types.contains(alt) || self.types.contains(unqualified(alt)) {
      return true
    }
  }
  false
}

///|
pub fn IfaceSymTab::has_value(self : IfaceSymTab, name : String) -> Bool {
  if self.values.contains(name) || self.values.contains(unqualified(name)) {
    return true
  }
  for alt in self.alias_forms(name) {
    if self.values.contains(alt) || self.values.contains(unqualified(alt)) {
      return true
    }
  }
  false
}

///|
/// The spelling of `name` that reaches the same member THROUGH a re-exported
/// type alias, and nothing else.
///
/// `CondVar::Cond` with `CondVar` an alias for `@cond_var.Cond` yields
/// `@cond_var.Cond::Cond`.
///
/// ONE form is returned, not two, and the reason is worth writing down because
/// the obvious second entry is dead code: both callers apply `unqualified` to
/// every candidate (`contains(alt) || contains(unqualified(alt))`), and
/// `unqualified("@cond_var.Cond::Cond")` IS `Cond::Cond`. A bare form in the
/// list can therefore never be reached. Gate 0447's M5 re-adds it and is
/// declared SURVIVED with that measurement, rather than a test being invented
/// for behaviour the code does not have.
///
/// This is deliberately narrow. It fires only when the HEAD of the path is a
/// recorded alias, and it re-asks the table for a MEMBER of that type, so a
/// member that does not exist still misses: the settle's three negative controls
/// are exactly that case. A name with no `::`, or whose head is not an alias,
/// yields nothing and the lookup is unchanged.
fn IfaceSymTab::alias_forms(self : IfaceSymTab, name : String) -> Array[String] {
  let out : Array[String] = []
  match unqualified(name).split_once("::") {
    // `split_once` hands back two `StringView`s, and `Map::get` and `+` both
    // want a `String`. `to_owned` rather than `to_string`, which is deprecated
    // on a `StringView` and which `moon check --deny-warn` rejects.
    Some((head_view, tail_view)) => {
      let head = head_view.to_owned()
      let tail = tail_view.to_owned()
      if head != "" && tail != "" {
        match self.aliases.get(head) {
          Some(target) => {
            let full = target + "::" + tail
            if !out.contains(full) {
              out.push(full)
            }
          }
          None => ()
        }
      }
    }
    None => ()
  }
  out
}

///|
pub fn IfaceSymTab::n_types(self : IfaceSymTab) -> Int32 {
  self.types.length()
}

///|
pub fn IfaceSymTab::n_values(self : IfaceSymTab) -> Int32 {
  self.values.length()
}

///|
pub(all) enum Severity {
  Error
  Warning
  Hint
} derive(Eq)

///|
/// The three analysis lenses, in pipeline order. Ranks order merged lens
/// lists and pick the representative (most specific) message.
pub(all) enum Lens {
  LStructural
  LType
  LBehavior
} derive(Eq)

///|
pub fn Lens::name(self : Lens) -> String {
  match self {
    LStructural => "structural"
    LType => "type"
    LBehavior => "behavior"
  }
}

///|
#proof_pure
pub fn Lens::rank(self : Lens) -> Int32 {
  match self {
    LStructural => 0
    LType => 1
    LBehavior => 2
  }
}

///|
#proof_pure
pub fn Lens::lower(self : Lens, other : Lens) -> Bool {
  self.rank() < other.rank()
}

///|
/// The unified finding taxonomy. Families sharing a merge_group are treated
/// as the same defect when they fire at the same span: an undefined name
/// seen by all three lenses is one finding with the union of lenses;
/// an argument mismatch and a method error likewise.
pub(all) enum Family {
  FParse
  FUndefinedName
  FUnusedLocal
  FUnusedParam
  FParamChanged
  FAssignType
  FArgType
  FOpMismatch
  FMethodError
  FCondBool
  FUnreachable
} derive(Eq)

///|
pub fn Family::name(self : Family) -> String {
  match self {
    FParse => "ParseError"
    FUndefinedName => "UndefinedName"
    FUnusedLocal => "UnusedLocal"
    FUnusedParam => "UnusedParam"
    FParamChanged => "ParamChanged"
    FAssignType => "AssignTypeMismatch"
    FArgType => "ArgTypeMismatch"
    FOpMismatch => "OperatorMismatch"
    FMethodError => "MethodError"
    FCondBool => "NonBooleanCond"
    FUnreachable => "Unreachable"
  }
}

///|
#proof_pure
pub fn Family::severity(self : Family) -> Severity {
  match self {
    FParse | FUndefinedName | FArgType | FOpMismatch | FMethodError => Error
    FAssignType | FCondBool | FUnreachable => Warning
    FUnusedLocal | FUnusedParam | FParamChanged => Warning
  }
}

///|
/// Canonical merge family: findings in the same group at the same span are
/// echoes of one defect across lenses.
pub fn Family::merge_group(self : Family) -> String {
  match self {
    FUndefinedName => "undef"
    FArgType | FMethodError | FOpMismatch => "arg-type"
    FCondBool => "cond"
    other => other.name()
  }
}

///|
/// One virtual-stack frame: enclosing function + source location
/// (entry frame and error point, unified).
pub(all) struct Frame {
  func : String
  file : String
  line : Int32
} derive(Eq)

///|
/// Reports must own their virtual stack: lenses keep mutating their live
/// stack (push/pop per call), so a finding snapshots the frames at report
/// time.
pub fn snapshot_vst(vst : Array[Frame]) -> Array[Frame] {
  let out : Array[Frame] = []
  for fr in vst {
    out.push(fr)
  }
  out
}

// core: the unified report model. Every finding carries the lens(es) that
// saw it — LStructural (binding walk), LType (symbols + inference),
// LBehavior (abstract execution) — so the pipeline can merge complementary
// detections of the same defect into one report instead of three echoes.

///|
pub(all) struct Pos {
  line : Int
  col : Int
} derive(Eq)

///|
pub(all) struct Span {
  start : Pos
  end : Pos
} derive(Eq)

///|
#proof_pure
pub fn pos(line : Int, col : Int) -> Pos {
  { line, col, }
}

///|
#proof_pure
pub fn span_at(line : Int, col : Int, len : Int) -> Span {
  { start: pos(line, col), end: pos(line, col + len), }
}

///|
#proof_pure
pub fn zero_span() -> Span {
  span_at(1, 1, 0)
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
  /// A hit returns `TUnknownFn` (we know it is a value; we do not model its
  /// signature, so no arity or argument check may run against it). A `.mbti`
  /// gives us the declaration name and never the parameter list, so any
  /// arity invented here would be a guess the checks would then report as
  /// fact.
  values : Map[String, Bool]
}

///|
pub fn IfaceSymTab::empty() -> IfaceSymTab {
  IfaceSymTab::{ types: Map([]), values: Map([]), }
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
  for k, _ in other.values {
    if !self.values.contains(k) {
      self.values.set(k, true)
    }
  }
  self
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
#proof_pure
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
  self.types.contains(name) || self.types.contains(unqualified(name))
}

///|
pub fn IfaceSymTab::has_value(self : IfaceSymTab, name : String) -> Bool {
  self.values.contains(name) || self.values.contains(unqualified(name))
}

///|
pub fn IfaceSymTab::n_types(self : IfaceSymTab) -> Int {
  self.types.length()
}

///|
pub fn IfaceSymTab::n_values(self : IfaceSymTab) -> Int {
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
pub fn Lens::rank(self : Lens) -> Int {
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
  line : Int
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

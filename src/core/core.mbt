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

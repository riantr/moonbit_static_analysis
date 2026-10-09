// ast: the MoonBit-subset frontend. The target
// language is MoonBit itself — fast-evolving — and this module consumes its
// current working subset: the shape the three inspections need, tracking
// the language as it moves. Statements are brace-blocked,
// `let`/assignment both bind (assignment-as-binding),
// and function parameters carry optional type annotations
// (the type/behavior seam).

///|
pub(all) enum BOp {
  OpAdd
  OpSub
  OpMul
  OpDiv
  OpMod
  OpEq
  OpNe
  OpLt
  OpLe
  OpGt
  OpGe
  OpAnd
  OpOr
} derive(Eq)

///|
pub fn BOp::symbol(self : BOp) -> String {
  match self {
    OpAdd => "+"
    OpSub => "-"
    OpMul => "*"
    OpDiv => "/"
    OpMod => "%"
    OpEq => "=="
    OpNe => "!="
    OpLt => "<"
    OpLe => "<="
    OpGt => ">"
    OpGe => ">="
    OpAnd => "&&"
    OpOr => "||"
  }
}

///|
pub(all) enum UOp {
  UNeg
  UNot
} derive(Eq)

///|
pub(all) enum EKind {
  EInt(Int)
  EFloat(Double)
  EBool(Bool)
  EStr(String)
  EName(String)
  EList(Array[Expr])
  EUnary(UOp, Expr)
  EBin(BOp, Expr, Expr)
  ECall(String, Array[Expr])
  EField(Expr, String)
  EIndex(Expr, Expr)
  /// A list/set comprehension: `[ for pat in <sources> => body ]` and its
  /// block-bodied sibling `[ for pat in <sources> { body } ]`.
  ///
  /// This node exists because the two halves must BOTH be walked. Modelling a
  /// comprehension as a plain `EList` of the body alone leaves the iterable
  /// unvisited, so the parameter a comprehension most often iterates over
  /// (`[ for x in self => ... ]`) is never read and is reported unused. The
  /// `sources` are kept separate from `body` for the same reason: a
  /// comprehension is not a two-element list, and folding it into one would
  /// hand the type lens and the interpreter a list that never existed.
  EComp(Array[String], Array[Expr], Expr)
} derive(Eq)

///|
pub(all) struct Expr {
  span : @core.Span
  kind : EKind
} derive(Eq)

///|
pub(all) struct Param {
  name : String
  tyann : String
  span : @core.Span
} derive(Eq)

///|
pub(all) struct ElseIf {
  cond : Expr
  body : Array[Stmt]
} derive(Eq)

///|
pub(all) enum SKind {
  SExpr(Expr)
  /// let name (: T)? = init — tyann "" means unannotated
  SLet(String, String, Expr)
  /// assignment; target is EName / EField / EIndex
  SAssign(Expr, Expr)
  SIf(Expr, Array[Stmt], Array[ElseIf], Array[Stmt]?)
  SWhile(Expr, Array[Stmt])
  SFor(String, @core.Span, Expr, Array[Stmt])
  SReturn(Expr?)
  SBreak
  SContinue
  /// top-level only: fn name(params) -> T { body }
  SFunc(String, Array[Param], String, Array[Stmt], @core.Span)
} derive(Eq)

///|
pub(all) struct Stmt {
  span : @core.Span
  kind : SKind
} derive(Eq)

///|
/// One `.mbtx` script import entry. The official entry grammar (script-mode
/// docs) is `"path" [@alias] [*]` — a quoted path with two optional TRAILING
/// modifiers, in that order. The docs also state the alias stays available
/// alongside import-all (both `Queue` and `@q.Queue` resolve), so alias+star is
/// its own shape rather than "an alias then a star".
pub(all) enum ImportSpec {
  /// "moonbitlang/core/list"
  IImport(String)
  /// "moonbitlang/core/list" @ls
  IAliased(String, String)
  /// "moonbitlang/core/queue" * — import-all, script-only per the docs
  IStar(String)
  /// "moonbitlang/core/queue" @q *
  IAliasedStar(String, String)
} derive(Eq)

///|
/// The quoted package path, whichever modifiers follow it.
pub fn ImportSpec::path(self : ImportSpec) -> String {
  match self {
    IImport(p) | IStar(p) => p
    IAliased(p, _) | IAliasedStar(p, _) => p
  }
}

///|
/// The `@alias`, or "" when the entry carries none (default alias).
/// Named `alias_name` because `alias` is a reserved keyword in MoonBit.
pub fn ImportSpec::alias_name(self : ImportSpec) -> String {
  match self {
    IAliased(_, a) | IAliasedStar(_, a) => a
    IImport(_) | IStar(_) => ""
  }
}

///|
/// Whether the entry is import-all (`*`), which brings every definition of the
/// package into scope.
pub fn ImportSpec::is_star(self : ImportSpec) -> Bool {
  match self {
    IStar(_) | IAliasedStar(_, _) => true
    IImport(_) | IAliased(_, _) => false
  }
}

///|
/// Canonical rendering — the path, then the alias as `@alias`, then ` *`.
/// Deterministic, so it can be compared and re-parsed safely.
pub fn ImportSpec::render(self : ImportSpec) -> String {
  match self {
    IImport(p) => p
    IStar(p) => "\{p} *"
    IAliased(p, a) => "\{p} @\{a}"
    IAliasedStar(p, a) => "\{p} @\{a} *"
  }
}

///|
pub(all) struct Module {
  body : Array[Stmt]
  /// `.mbtx` script imports from the leading `import { ... }` block(s),
  /// recorded but NOT resolved — the subset analyzes one self-contained file
  /// at a time. Empty for package sources (`.mbt`).
  imports : Array[ImportSpec]
} derive(Eq)

///|
/// The base symbol of an assignment target:
/// `a.b.c = v` / `a[i] = v` peel to `a`; the field/index positions are not
/// variables.
pub fn Expr::assigned_base(self : Expr) -> String? {
  match self.kind {
    EName(n) => Some(n)
    EField(base, _) => base.assigned_base()
    EIndex(base, _) => base.assigned_base()
    _ => None
  }
}

///|
pub fn Expr::is_valid_target(self : Expr) -> Bool {
  match self.kind {
    EName(_) | EField(_, _) | EIndex(_, _) => true
    _ => false
  }
}

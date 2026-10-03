// ast: the MoonBit-subset frontend (internal name MLang). The target
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
pub(all) struct Module {
  body : Array[Stmt]
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

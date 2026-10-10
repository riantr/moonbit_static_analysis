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
  /// The bitwise family, added for the measured Class F deaths
  /// (`h & 1023`, `(h >> 10) & 63` — statecheck.mbt:275): before these
  /// existed, the characters died in the lexer's unknown-char arm and the
  /// whole file went partial. Typed Int-on-Int in `types.binop_result`,
  /// evaluated in `Interp::binop`. `walk.const_eval` deliberately does NOT
  /// fold them: the dead-branch lens gains nothing from folding mask
  /// arithmetic that is never literal-keyed in the corpus, and shift
  /// folding would be a new overflow surface for nothing.
  OpBitAnd
  OpBitOr
  OpBitXor
  OpShl
  OpShr
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
    OpBitAnd => "&"
    OpBitOr => "|"
    OpBitXor => "^"
    OpShl => "<<"
    OpShr => ">>"
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
  /// An integer literal with NO value attached: it exceeded the analyzer's
  /// fixed bound, or it carried an `L` / `U` / `UL` suffix for a wider type.
  ///
  /// This is a separate node rather than an `EInt` with a sentinel, because a
  /// sentinel would be a number and would be folded on. `walk.const_eval`
  /// returns nothing for it, so a dead branch keyed on `0xFFFFFFFF` is NOT
  /// pruned; the type lens returns TUnknown, so it does not report a mismatch
  /// it cannot justify. Both are the failure-safe direction.
  EBigInt
  EFloat(Double)
  EBool(Bool)
  /// A string literal, plus the names it REFERENCES inside `\{...}`
  /// interpolations. The payload alone cannot answer that: the interpolation
  /// body is copied raw, so `"\{v}"` and `"no interpolation"` are both just a
  /// string to every lens. The second field is what lets the structural walk
  /// count a read that happens only inside an interpolation, and lets it
  /// report a name that does not exist inside one. See `@lexer`'s `TStr`,
  /// which is where these are collected.
  EStr(String, Array[String])
  EName(String)
  EList(Array[Expr])
  EUnary(UOp, Expr)
  EBin(BOp, Expr, Expr)
  ECall(String, Array[Expr])
  EField(Expr, String)
  EIndex(Expr, Expr)
  /// A METHOD call: `receiver.name(args)`.
  ///
  /// This node exists because `ECall` cannot hold it. `ECall`'s callee is a
  /// `String`, so it can name `f` but not `receiver.f`; and `EField(Expr,
  /// String)` is a field READ, which has no place to put the arguments. The
  /// receiver is therefore kept as a separate `Expr` rather than flattened
  /// into a name, and that is not cosmetic: the receiver is an evaluated
  /// expression and the whole binding analysis depends on reading it. Writing
  /// `out.write_string(s)` as `ECall("out.write_string", args)` would make the
  /// write to `out` invisible, and a local that exists only to be written to
  /// would then be reported unused.
  ///
  /// Until this existed, `parse_postfix` accepted only `EName` as a callee and
  /// reported `only named functions can be called` on `m.set(k, v)`, which is
  /// how a method call stopped the parse in most real files.
  EMethodCall(Expr, String, Array[Expr])
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
  /// A struct literal: `path { field: value, shorthand, }` where `path` is
  /// either empty (a plain literal) or a type name accumulated from the `::`
  /// fold — `Infer::{ ... }`, `Lexer::{ ... }`, `@report.Report::{ ... }`.
  ///
  /// The path is a TYPE NAME, not a binding, and walk must not resolve it as
  /// one: `Infer::{` opens the very definition of `ty_of` in this analyzer's
  /// own source, and reporting the type's own name as an undefined binding is
  /// exactly the class of self-report this node exists to stop. Shorthand
  /// fields are stored as `(name, EName(name))` — the value is a real
  /// expression, so a shorthand read still counts as a use of the name.
  EStruct(String, Array[(String, Expr)])
  /// A tuple expression, or the unit value: `(a, b)` is two elements and `()`
  /// is `ETuple([])`. A parenthesized GROUPING `(e)` is not a tuple and never
  /// becomes one — it yields `e` itself, so precedence and spans stay honest.
  ETuple(Array[Expr])
  /// An exclusive range expression `a..<b`, from the single `TRange` token.
  /// Bare `..` and `..=` are not modelled and still error.
  ERange(Expr, Expr)
  /// A tuple field access `pair.0`. The position is an Int literal the
  /// lexer emits as one token — the float probe means `x.0.1` arrives as a
  /// TFloat and reports honestly instead of misparsing. There is no tuple
  /// Ty to per-element, so the lenses type the base and leave the element
  /// unknown.
  ETupleField(Expr, Int)
  /// An `is` test `base is Pattern`. The pattern is reduced AT PARSE TIME
  /// to the binding name it introduces — `TName(tag)` -> "tag", `TEOF` ->
  /// "" — and no lens ever sees pattern text: MoonBit string indexing is
  /// by byte, so pattern text would have to be re-lexed to be sliced
  /// safely. A pattern without a binding ("") is a pure test; or-patterns
  /// never reach here because match bodies are skipped whole.
  EIs(Expr, String)
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
  /// assignment; target is EName / EField / EIndex / ETupleField
  SAssign(Expr, Expr)
  SIf(Expr, Array[Stmt], Array[ElseIf], Array[Stmt]?)
  SWhile(Expr, Array[Stmt])
  SFor(String, @core.Span, Expr, Array[Stmt])
  SReturn(Expr?)
  SBreak
  SContinue
  /// top-level only: fn name(params) -> T { body }
  SFunc(String, Array[Param], String, Array[Stmt], @core.Span)
  /// `let (a, b) = expr` — a tuple destructuring let. FLAT only: a nested
  /// pattern like `let (a, (b, c)) = ...` is not modelled and still errors.
  /// Each name binds the type of the init expression as a whole; the subset
  /// has no tuple types, so per-element types are unknown and no claim is
  /// made that would need one.
  SLetDestruct(Array[String], Expr)
  /// A named function defined INSIDE a block: `fn go(n : Int) -> Int { ... }`.
  /// It owns a scope exactly like SFunc but lives in a statement list, so it
  /// is its own statement kind rather than an SFunc (whose contract says
  /// top-level only) smuggled into a body.
  SLocalFunc(String, Array[Param], String, Array[Stmt], @core.Span)
  /// A bare `{ ... }` block in statement position — an inner block of a
  /// `fn main` body, a test block. It is a plain statement list: the
  /// lenses treat it exactly like an `if` body (no new scope), because
  /// the binding analysis is not flow-scoped anywhere else either.
  SBlock(Array[Stmt])
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
    ETupleField(base, _) => base.assigned_base()
    _ => None
  }
}

///|
pub fn Expr::is_valid_target(self : Expr) -> Bool {
  match self.kind {
    EName(_) | EField(_, _) | EIndex(_, _) | ETupleField(_, _) => true
    _ => false
  }
}

///|
/// Whether this expression names a PACKAGE rather than a value.
///
/// `@core` has no binding in the file under analysis: it is an import alias.
/// So `@core.snapshot_vst(self.vst)` is a qualified call, and resolving the
/// receiver would report `no visible binding for '@core'` on correct code.
/// The walk consults this before reading a method-call receiver; the `@`
/// prefix is what distinguishes the two, because a bare name is always a
/// binding and `@`-prefixed is always an import.
pub fn Expr::is_qualifier(self : Expr) -> Bool {
  match self.kind {
    EName(n) => n.has_prefix("@")
    EField(base, _) => base.is_qualifier()
    _ => false
  }
}

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
  /// The PIPE, `f <| x` and its mirror `x |> f`. Both spellings are one operator
  /// in meaning -- each applies a function to a value -- and they are ONE variant
  /// for the same reason `<` and `>` are two: the node records what the ANALYZER
  /// concluded, and both directions conclude "a call whose result is unknown".
  ///
  /// It is a binary operator rather than a call because the corpus's right-hand
  /// side is almost always a LAMBDA -- `@async.with_task_group() <| group => { .. }`,
  /// `Promise::from_async(abort_signal~) <| () => { .. }` -- and every lambda site
  /// in this parser deliberately SKIPS its body into an opaque node. A call needs
  /// a callee NAME and there is none, so building one would be claiming a shape
  /// the parse does not have.
  ///
  /// Precedence is the LOWEST binary level and it is left-associative; both are
  /// settled (`_verify/settle_0464_pipe_operators.ps1`, 14/14) rather than assumed
  /// from the symbol. See `Parser::parse_pipe`.
  OpPipe
  /// The REGEX MATCH, `string =~ regex`. Its result is a Bool -- settled against
  /// the toolchain in `_verify/settle_0494_parse_backlog.ps1`, row `a3`, with the
  /// control `a4` REJECTing the same expression assigned to an Int.
  ///
  /// Its RIGHT operand is a Regex, a type this model does not have, so the
  /// operand types are not checked and the result type alone is the answer. That
  /// is the same trade the PIPE makes one level down, for the same reason: a
  /// claim the model cannot support is worse than an answer it can.
  OpMatch
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
    OpPipe => "<|"
    OpMatch => "=~"
  }
}

///|
pub(all) enum UOp {
  UNeg
  UNot
} derive(Eq)

///|
pub(all) enum EKind {
  EInt(Int32)
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
  /// A call `f(args)`. The third field is the ARGUMENT LABELS, one per
  /// argument, parallel to `args`: the parameter name for `f(name=…)` and for
  /// the `x~` shorthand, and `""` for a positional argument.
  ///
  /// This exists because MoonBit lets a call reorder named arguments freely,
  /// settled against `moon check`: given `fn f(intent~, label?, shortcut?,
  /// enabled?)`, the call `f(label=…, shortcut=…, intent=…)` is accepted. So
  /// the argument's INDEX is not the parameter's index whenever any argument
  /// is named. Without the labels the type lens compared `args[3]` against
  /// `params[3]` and reported `argument 4 … has incompatible type 'str';
  /// expected 'bool'` six times on `wzzc-dev/moui core/gesture.mbt:754`
  /// onward, where `description` is passed fourth and `enabled` is declared
  /// fourth.
  ECall(String, Array[Expr], Array[String])
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
  ///
  /// The labels are `ECall`'s, carried for the same reason.
  EMethodCall(Expr, String, Array[Expr], Array[String])
  /// A `..` CHAIN LINK: `recv..name(args)`.
  ///
  /// THIS IS NOT A SPELLING OF `recv.name(args)`, and treating it as one was the
  /// reading the symbol's shape suggested and the corpus cannot refute. Settled
  /// against the toolchain in `_verify/settle_0465_dotdot_chain.ps1`, 13 rows,
  /// all controls held:
  ///
  ///     S::new()..get().v   ACCEPT      <- `get` returns Int, and this is S.v
  ///     S::new().get().v    REJECT(4028)  <- the `.` spelling of the same thing
  ///
  /// So `recv..name(args)` CALLS `name`, DISCARDS its result, and EVALUATES TO
  /// `recv`. The two rows above are the same expression spelled two ways and they
  /// disagree, which is the only thing that settles it: real code only chains
  /// methods that RETURN the receiver, so all 180 corpus sites are consistent with
  /// both readings and cannot tell them apart. `dd_arity` REJECTs with 4080, so the
  /// arguments are really bound and this is a call and not a projection;
  /// `dd_field` REJECTs `..v` on a field, so the link must be callable.
  ///
  /// IT CANNOT BE `EMethodCall` with the result ignored, and cannot be `EBin`
  /// either. Both would type the node by the METHOD's return type, and the settled
  /// value is the receiver's -- so every lens would be wrong about every one of the
  /// 33 corpus files while parsing all of them, which is worse than not reading
  /// them. The type lens returns the RECEIVER's type and the behavioral lens
  /// returns the RECEIVER's value; that is the claim, and the settle is the reason.
  ///
  /// WHAT IT DOES NOT COVER: the statement-level form
  ///
  ///     w
  ///     ..write(b"GET / HTTP/1.1\r\n")
  ///     ..write(self.headers)
  ///     .send_headers(extra)
  ///
  /// arrives with the receiver already consumed by the previous statement, so the
  /// parser can only offer `EBigInt` there -- the same stated limit the single-dot
  /// form at `parse_postfix_from`'s caller already carries. The receiver is still
  /// READ, because the previous statement walked it, so no name goes unreported; what
  /// is lost is its TYPE. The inline form (`output..write(name).write(":")`, 65
  /// sites across 29 files) goes through the ordinary postfix loop and keeps it.
  ///
  /// A MUTATING method is not modelled -- the value handed on is the receiver as it
  /// was read, and no write is recorded. That is the fail-toward-silence direction
  /// and is shared with `EMethodCall`.
  EDotDot(Expr, String, Array[Expr], Array[String])
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
  /// A block used as an EXPRESSION: `let x = { .. }`. The block's value is its
  /// TAIL, so this is not the same node as `SBlock` — that one is a statement
  /// list with no value.
  ///
  /// WHY THE STATEMENTS ARE KEPT RATHER THAN COLLAPSED TO THE TAIL. Reducing
  /// `{ let y = 1; y + 1 }` to `y + 1` would delete the binding of `y`, and the
  /// name-resolution lens would then report `no visible binding for 'y'` on code
  /// `moon check` compiles. That is the 0467b defect arriving from a new
  /// direction: a finding invented by the reader, on a program that is fine.
  ///
  /// Settled in `_verify/settle_0468_let_block_rhs.ps1`: `{ 1 }`,
  /// `{ let y = 1; y + 1 }`, `{ }` and the nested `{ { 1 } }` are all ACCEPTed by
  /// the toolchain, and `{ a }` is a legal one-field struct literal — which is
  /// why the parser distinguishes the two BEFORE building either node.
  EBlock(Array[Stmt])
  /// A tuple expression, or the unit value: `(a, b)` is two elements and `()`
  /// is `ETuple([])`. A parenthesized GROUPING `(e)` is not a tuple and never
  /// becomes one — it yields `e` itself, so precedence and spans stay honest.
  ETuple(Array[Expr])
  /// An exclusive range expression `a..<b`, from the single `TRange` token.
  /// Bare `..` and `..=` are not modelled and still error.
  ERange(Expr, Expr)
  /// A REGEX LITERAL, `re"^a"`. The pattern text is carried, not analysed.
  ///
  /// It is its own node rather than a `TStr`-shaped string because a Regex is
  /// NOT a String: `let r : String = re"^a"` is REJECTed by the toolchain with
  /// 4014 (`_verify/settle_0494_parse_backlog.ps1` row `a5`), while
  /// `let r : Regex = re"^a"` is ACCEPTed (row `a2`). A literal spelled as a
  /// string would make the analyzer claim a type the toolchain refuses.
  ///
  /// The text is carried so that a reader can say WHAT was read, and the lenses
  /// treat it as a leaf of unknown type -- this model has no Regex type, and the
  /// honest answer for a type it cannot name is "unknown", not "String".
  ERegex(String)
  /// A REGEX CAPTURE, `re"..." as name`. The name is bound to the text the
  /// capture group matched.
  ///
  /// It is its own node rather than an `ECast` because the two are different
  /// claims: a cast says "this value has that type", and a capture says "this
  /// NAME is bound here". Read as a cast, the name was consumed as a TYPE and
  /// the binding was lost -- so `port_str` was reported `undefined name` at its
  /// use, on code `moon check` compiles
  /// (`async 0.22.4 src/http/request.mbt:59-65`).
  EAsBind(Expr, String)
  /// A tuple field access `pair.0`. The position is an Int literal the
  /// lexer emits as one token — the float probe means `x.0.1` arrives as a
  /// TFloat and reports honestly instead of misparsing. There is no tuple
  /// Ty to per-element, so the lenses type the base and leave the element
  /// unknown.
  ETupleField(Expr, Int32)
  /// An `is` test `base is Pattern`. The pattern is reduced AT PARSE TIME
  /// to the binding name it introduces — `TName(tag)` -> "tag", `TEOF` ->
  /// "" — and no lens ever sees pattern text: MoonBit string indexing is
  /// by byte, so pattern text would have to be re-lexed to be sliced
  /// safely. A pattern without a binding ("") is a pure test; or-patterns
  /// never reach here because match bodies are skipped whole.
  EIs(Expr, Array[String])
  /// A trait-object cast `base as &Trait`.
  ///
  /// Without this node the parser had no production for `as` at all: the
  /// postfix loop broke on it, the tail-expression reader then took `as` as
  /// the next statement, and the binding walk resolved it as an ordinary
  /// identifier and reported `undefined name 'as'` — a name that never
  /// existed, on a program `moon check` accepts with zero errors. Settled
  /// against the compiler in `_verify/settle_0428_cast.ps1`: three forms of
  /// `as &Trait` compile, while a bare `as` and `as <plain type>` do not.
  ///
  /// THE TARGET TYPE IS DELIBERATELY NOT CARRIED. `as` requires a trait
  /// object (`moon check` verbatim: "`Int` is not a trait object type, it
  /// cannot be used on the right hand side of `as`"), which makes the type
  /// look checkable — and it is not, because `IfaceSymTab` cannot tell a
  /// trait from a struct: `using @pkg { type View }`, a `trait` declaration
  /// and a `struct` declaration all land in the same `types` set. A check
  /// built on that table would report every cast to a struct type, and the
  /// only way to avoid that is to keep the type and not read it. Carrying
  /// it would be a field no lens can consult, so the node holds the operand
  /// alone — the same reason `ETupleField` keeps only the base. (`catch` no
  /// longer discards its handler; see `ECatch`.)
  ///
  /// The operand is NOT optional to the lenses: it is the evaluated
  /// expression, and walking it is what keeps `b as &Sink` from reporting
  /// the parameter `b` as never read. This is the `EComp` lesson — both
  /// halves must be walked or the side that is walked is the side that
  /// vanishes.
  ECast(Expr)
  /// `expr catch { pattern => body, ... }` — MoonBit's postfix error handling
  /// on a call, with the handler arms carried instead of discarded.
  ///
  /// THE BASE ALONE WAS NOT ENOUGH, and the measured cost of that is the only
  /// actionable finding wzzc-dev/moui had:
  ///
  ///     backend/macos/macos_native_ime.mbt:437:3
  ///     parameter 'prefix' may not be used (UnusedParam)
  ///
  /// `prefix` is read at line 442, inside `catch { err => { ... } }`. The
  /// postfix arm consumed the handler with `skip_braces`, so the only mention
  /// of `prefix` in the whole function was invisible and the parameter read as
  /// unused. `ECast` had already established the rule this node follows: the
  /// half that is not walked is the half that vanishes.
  ///
  /// THE ARMS ARE PARSED, NOT SKIPPED, and that is forced by the lenses rather
  /// than chosen. A handler body introduces pattern bindings; reading the body
  /// without introducing them manufactures `no visible binding for 'err'` on
  /// correct code, which is why the `try` arm in `parse_atom` skips its
  /// handlers whole. So each arm carries `bindings` and a real statement list,
  /// and the walker binds before it walks.
  ///
  /// WHAT THIS DOES NOT COVER: the STATEMENT-level `try { } catch { }`, which
  /// also skips its try body and is still `EBigInt` + a skip notice. Fixing
  /// that is a separate problem — it needs the try body's error semantics, not
  /// just its syntax — and conflating the two would have meant shipping a fix
  /// measured on the easy half only.
  ///
  /// THE NODE HAS THE BASE'S TYPE, NOT THE ARMS', and the compiler says so in
  /// one line of MoonBit (`_verify/settle_0439_catch.ps1`, case
  /// `NEG_arm_type`): `fallible(n) catch { _ => () }` is an `Int`, so wrapping
  /// it in `ignore(..)` is handed an Int where Unit is wanted and is rejected
  /// with 4014. That is why `types/infer.mbt` types the node as its base
  /// rather than joining the arms' types in — the join would be a claim about
  /// a value the language does not produce.
  ECatch(Expr, Array[CatchArm])
  ///
  /// `try expr catch { .. } noraise { pattern => body, .. }` — a SECOND handler
  /// block attached to a completed `try ... catch`.
  ///
  /// This is not a function, a macro or a decorator, and reading it as a name was
  /// producing `undefined name 'noraise'` on four sites: proton
  /// `facade_identity.mbt:99` and `:136`, `protocol_wbtest.mbt:5`, and async
  /// `network.mbt:68`. The measured corpus shape is
  ///
  ///     try validate_application_identifier(identifier) catch {
  ///       InvalidField(expectation~, ..) =>
  ///         Err(InvalidSetting(name="identifier", message=expectation))
  ///       error => Err(InvalidSetting(name="identifier", message=error.message()))
  ///     } noraise {
  ///       identifier => Ok(identifier)
  ///     }
  ///
  /// The grammar is SETTLED by the compiler rather than assumed --
  /// `_verify/settle_0441_noraise.ps1`, 8/8 as predicted with the positive
  /// control green:
  ///
  ///   - `noraise` REQUIRES a preceding `catch`. `try expr noraise { .. }` is
  ///     REJECTED. So the parser nests this inside its `catch` arm rather than
  ///     matching a bare keyword anywhere, which is both faithful and safe: a
  ///     user function named `noraise` cannot be swallowed by it.
  ///   - the arm list is the SAME grammar as `catch`: several arms, block or
  ///     expression bodies, optional `=>`.
  ///   - an empty `noraise { }` is REJECTED.
  ///   - `noraise`'s pattern binds the BASE'S RESULT VALUE, not the error --
  ///     `fallible(n) catch { _ => 0 } noraise { x => x + 1 }` type-checks, so
  ///     `x` is the `Int` the base produced on the no-raise path.
  ///
  /// The base is the `ECatch` node, not the original try expression, so this
  /// composes with the catch reading rather than re-walking it. It has the
  /// BASE's type for the same reason `ECatch` does -- the arms are alternative
  /// control paths, not extra operands.
  ENoRaise(Expr, Array[CatchArm])
  /// A `match` whose ARMS were skipped: `match subject { pattern => value, .. }`.
  ///
  /// ONLY THE SUBJECT IS CARRIED, and carrying it is the whole point. Until 0469 the
  /// parser yielded the subject as the match's own VALUE, which was wrong twice over:
  ///
  ///   - the VALUE is the join of the arms, not the subject, so
  ///     `let vok = match bd { .. }` typed `vok` as the subject's type. Measured on
  ///     moonbit_image 0.3.7 `png.mbt:980`: `operand of '!' must be bool, got 'int'`
  ///     on code `moon check` compiles.
  ///   - dropping the subject instead fixes that but LOSES ITS READS, so an undefined
  ///     name used only as a match subject stops being reported -- a true positive
  ///     traded for the absence of a false one, which is not a trade worth making.
  ///
  /// So this variant carries the subject and says nothing about the value. `walk_expr`
  /// descends into it (the subject is real, analysed code), `ty_of` answers `Unknown`
  /// (the arms' join is not available and guessing it is the bug this node exists to
  /// end), and `eval` evaluates the subject for its effects.
  ///
  /// THE PRECEDENT IS `ECatch`, and the two differ in exactly the place that matters:
  /// `ECatch` TYPES as its base because `expr catch { .. }` really does produce the
  /// base's value when no arm matches. A `match` does NOT -- its value comes from the
  /// arms, which are the part this analyzer does not model. Same shape, opposite answer,
  /// and the reason they cannot share one variant.
  EMatch(Expr)
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
  /// True when a call may OMIT this parameter.
  ///
  /// TWO SPELLINGS MAKE A PARAMETER OMITTABLE, and both are settled against
  /// the toolchain (`moon check` 0.1.20261012, re-settled on 0.1.20261016 --
  /// see `_verify/_settle_0490_resettle.ps1`):
  ///
  ///   - `name? : T` -- the OPTIONAL spelling. Settled ACCEPT: a call that
  ///     omits it compiles.
  ///   - `name~ : T = default` -- a LABELLED parameter with a DEFAULT value.
  ///     Settled ACCEPT: a call that omits it compiles. (The `= default` on a
  ///     POSITIONAL parameter is a different thing: the toolchain REJECTS it
  ///     with 3010, "Only labelled arguments can have default value".)
  ///
  /// The `~` on its own does NOT make a parameter omittable -- it changes HOW
  /// the parameter is passed, not WHETHER it is passed. A `~` parameter is a
  /// LABEL: it must be supplied BY LABEL, and a call that omits it is
  /// REJECTED with 4086, "The labels x~ are required by this function, but
  /// not supplied." A POSITIONAL pass is rejected too, with 4080 as well --
  /// the function "requires 0 positional arguments, but is given 1". Only
  /// `f(x=1)` is accepted.
  ///
  /// The `?` used to be consumed and discarded, and so was the default value,
  /// and the consequence was that the arity check could not tell "the call
  /// passed too few arguments" from "the call omitted the ones it may omit".
  /// Those are different things, and only the second one is legal MoonBit:
  /// `fn wire_string(value : Json?, allow_empty? : Bool = false)` is called
  /// as `wire_string(value)` throughout moui 0.1.12, and the check reported it
  /// as `no method matching wire_string(Any)`.
  omittable : Bool
  span : @core.Span
} derive(Eq)

///|
pub(all) struct ElseIf {
  cond : Expr
  body : Array[Stmt]
} derive(Eq)

///|
/// One `catch` handler arm: `pattern => body`.
///
/// `bindings` are the names the PATTERN introduces, and they are a SUPERSET on
/// purpose. A constructor head (`Some(x)`), a tuple pattern (`(a, b)`) and an
/// alternate (`A | B`) all yield more names than they bind, and the extra ones
/// cannot produce a finding — `Walker::bind_pattern` puts them in the frame
/// without putting them in the audit list. The direction that matters is which
/// way the error goes: a name that should have bound and did not yields a false
/// `no visible binding`, and a name that bound and should not have yields
/// silence. Only one of those is a defect the user can hit.
///
/// `body` is a statement list even for `e => 0`, because the arm body may be a
/// block (`=> { ... }`) or a single statement (`=> return ""`, `=> 0`), and the
/// census says the single-statement form is the COMMON one — 45 of 54 handler
/// sites in moui, 273 of 323 in proton (`_verify/census_catch.ps1`). A
/// block-only representation would have modelled the rare form.
pub(all) struct CatchArm {
  span : @core.Span
  bindings : Array[String]
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
  ///
  /// `while cond { .. } nobreak { .. }` -- a block that runs when the loop
  /// finishes WITHOUT taking a `break`.
  ///
  /// Measured false positive: proton `internal/bridge_admission_test/main.mbt:20`
  /// reported `undefined name 'nobreak'`, on code `moon check` accepts.
  ///
  ///     while true {
  ///       while runtime.poll_event() is Some(event) {
  ///         if event.bridge_request() is Some(request) {
  ///           assert_eq(request.op, "app:probe")
  ///           return request
  ///         }
  ///       }
  ///       @async.sleep(5)
  ///     } nobreak {
  ///       fail("unreachable")
  ///     }
  ///
  /// The grammar is SETTLED by the compiler, `_verify/settle_0443_nobreak.ps1`,
  /// 10/10 with the positive control green:
  ///
  ///   - it is a postfix on a LOOP -- `while` and `for` both accept it, and the
  ///     compiler REJECTS `expr nobreak { .. }` with no loop at all.
  ///   - the body is a STATEMENT LIST, not an expression: `nobreak { 1 }` is
  ///     rejected with 4139, a value in statement position cannot be dropped.
  ///     This is a different shape from `noraise`, which takes an arm list.
  ///   - an EMPTY `nobreak { }` is ACCEPTED -- unlike `noraise { }`, which is
  ///     rejected. The two constructs are easy to assume identical and are not.
  ///
  /// The loop is carried as a CHILD rather than flattened, because the block runs
  /// once AFTER the loop completes, not on each iteration. Splicing its
  /// statements into the loop body would model it as per-iteration, which is a
  /// claim about execution the analyzer does not make anywhere else.
  SNoBreak(Stmt, Array[Stmt])
  SReturn(Expr?)
  /// `raise E` / `raise E(payload)` / bare `raise` — a statement that
  /// propagates an error and never produces a value.
  ///
  /// Deliberately NOT `SReturn`: three lenses would read it wrongly. `infer`
  /// joins a returned expression's type into the inferred return type
  /// (`SReturn(Some(e)) => acc = ty_join(acc, self.ty_of(e, TUnknown))`), so
  /// the error CONSTRUCTOR's type would be joined into what the function
  /// returns. `interp` pushes the operand into `ret_vals`, inventing a value
  /// that `raise` never produces. What a raise shares with a bare `return` is
  /// only the divergence, which is exactly what `SRaise` keeps and nothing
  /// else. The operand is still walked and type-checked, so a real defect
  /// inside `raise E(bad_call)` still reports.
  SRaise(Expr?)
  SBreak
  SContinue
  /// The body's OWN trailing expression — MoonBit's tail value.
  /// `fn f() -> Int { 1 }` is a function that RETURNS 1; before this node it
  /// was an `SExpr`, and `SExpr` discards its value (`Interp::exec_stmt`
  /// evaluates it and drops the result into `let _`). So `ret_vals` stayed
  /// empty, `join_vals([])` returned `None`, and the function reported itself
  /// as `f() -> None` — a claim about understanding that was simply false.
  ///
  /// Its own node rather than a flag on `SExpr`, for the `SRaise` reason: the
  /// two statements are read by different lenses in different ways. Walking is
  /// identical, but the type lens must JOIN a tail expression into the
  /// inferred return type and the behaviour lens must RECORD its value, while
  /// neither may do either for a non-final expression statement. A flag would
  /// have to be threaded through all three anyway, and the moment one of them
  /// forgets to check it, the failure is silent: `None` is a perfectly
  /// well-formed return type.
  ///
  /// Only a FUNCTION body has one. `parse_block` takes `fn_body` for exactly
  /// that reason: the same block parser reads loop bodies, `if` arms and bare
  /// blocks, and a trailing expression in any of those is an ordinary
  /// expression statement whose value goes nowhere.
  STail(Expr)
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

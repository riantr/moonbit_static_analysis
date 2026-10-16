//| Tests for 0467, the ASYNC function type without parentheses of its own, end to
//| end, 0467-1.
//|
//| `async (A, B) -> R` was readable in only one of its three spellings. This file
//| exists because "it parses" and "the parameter was really read" are different claims,
//| and the difference is the whole class of bug 0465 hit: its mutation M3 dropped the
//| `..` argument list, the tree stayed perfectly well typed -- `EDotDot(EName("self"),
//! "write", [], [])` is a LEGAL node, just the wrong one -- and only a row that counts
//! what the tree CARRIES could see it.
//|
//| Reach, measured as per-FILE first blocker on the tree that shipped as 12b38a3, with
//| every member printed (`_verify/rank_0467_shapes.ps1`): 19 of 57 unread files stop
//| on this shape, 11 in moonbitlang/async 0.22.4 and 8 in moonbit-community/proton
//| 0.3.4 -- the largest single group, and a strict dependency for the effect-in-param
//| position files.
//!
//! 判据: a false positive nobody can reach is not a false positive that does not exist.
//! It is a finding whose file has not been read yet, and the only way to tell the two
//! apart is to unblock the corpus and look.

//|

///|
/// THE ROW THAT SAYS THE PARAMETER WAS REGISTERED, which is not the same as saying the
/// text was consumed. The parameter is never used, so a parser that SKIPPED the async
/// type would leave no parameter behind and report nothing -- and the file would still
/// be `parsed=1`. Asserting the unused parameter EXISTS is what a skip cannot pass.
test "0467: an async-typed parameter is registered as a parameter" {
  let r = @pipeline.run(
    "///|\nfn f(g : async (Int) -> Unit) -> Unit {\n  ()\n}\n",
    "asyncparam.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// THE ROW THAT SAYS IT IS USABLE. The two above can both pass on a parser that reads
/// the annotation and throws the parameter away; this one cannot.
test "0467: an async-typed parameter resolves where it is used" {
  let r = @pipeline.run(
    "///|\nfn f(g : async (Int) -> Unit) -> Unit {\n  ignore(g)\n}\n",
    "asyncuse.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE CANARY BESIDE IT. Identical except for the name: if `nope` reported zero
/// undefined names, something was inventing bindings and the row above proved nothing.
test "0467: a name that is not a parameter is still reported undefined" {
  let r = @pipeline.run(
    "///|\nfn f(g : async (Int) -> Unit) -> Unit {\n  ignore(g)\n  ignore(nope)\n}\n",
    "asynccanary.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE EFFECT ON THE ASYNC TYPE, in a parameter -- proton facade_context.mbt:137 spells
/// `emit_event : async (@proton_contract.ContractRoute, String, Json) -> Unit noraise`.
/// Both halves have to work at once here: 0466 added the effect and 0467 added the
/// type, and neither is observable without the other.
test "0467: `async (Int) -> Unit noraise` in a parameter resolves" {
  let r = @pipeline.run(
    "///|\nfn f(g : async (Int) -> Unit noraise) -> Unit {\n  ignore(g)\n}\n",
    "asynceff.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// A PARAMETER LIST WITH AN ASYNC TYPE IN THE MIDDLE of it, which is where the corpus
/// puts it -- `src/task_group.mbt:50` has `self`, then `f : async () -> Unit`, then two
/// ordinary parameters after. This is the row for the parameter loop keeping step: an
/// entry arm that consumed one token too few or too many would register `no_wait` as
/// the type and lose the parameter that follows it.
test "0467: parameters after an async-typed one still register" {
  let r = @pipeline.run(
    "///|\nfn f(a : Int, g : async () -> Unit, b : Int) -> Unit {\n  ignore(a)\n  ignore(g)\n  ignore(b)\n}\n",
    "asyncmid.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE RETURN SPELLING, which was ALSO broken and is fixed by the same shared body.
///
/// The `async fn` is DECLARED rather than written as an `async fn (x) { .. }` literal.
/// The literal form reports `anonymous function literal is outside the analyzed
/// subset`, and that report's family is ParseError -- so a literal here would fail this
/// row for a reason that has nothing to do with the type under test. The declaration is
/// the same type, the same parse, and no lambda in the file.
test "0467: `-> async (Int) -> Unit` reads a whole function" {
  let r = @pipeline.run(
    "///|\nasync fn g(x : Int) -> Unit {\n  ()\n}\n\n///|\nfn f() -> async (Int) -> Unit {\n  g\n}\n",
    "asyncret.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// THE KEYWORD-SLOT CANARY through the whole pipeline. `bogus (Int) -> Unit` is
/// REJECTed by `moon check` with 3002, so if this produced no parse error at all the
/// entry arm would have widened from "the keyword `async`" into "a name followed by a
/// parenthesised list".
test "0467: a non-async head before a parameter list is a parse error" {
  let r = @pipeline.run(
    "///|\nfn f(g : bogus (Int) -> Unit) -> Unit {\n  ()\n}\n",
    "asyncbogus.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_true(count_family(r, "ParseError") >= 1)
}

///|
/// REGRESSION for 0458, whose spelling is the only async type wzzc-dev/moui writes and
/// the reason that corpus is 608/608 parsed. If the shared body broke this, moui would
/// go unread and nothing in this file would say so.
test "0467: the parenthesised async function type still reads a parameter" {
  let r = @pipeline.run(
    "///|\nfn f(g : (async (Int) -> Unit)?) -> Unit {\n  ()\n}\n",
    "asyncparen.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UnusedParam"), 1)
}

//| ---------------------------------------------------------------------------
//| 0467b -- the binding COLLECTOR, which is a different layer from the parser.
//|
//| Reaching `src/fs/dir.mbt` exposed two ACTIONABLE false positives on code
//| `moon check` compiles, and they were not about `async` at all:
//!
//!   49:26 no visible binding for 'last_path_sep_index'
//!   55:13 no visible binding for 'parent'
//!
//| Both names are bound by a `let` INSIDE a catch arm. `collect_fn_bindings` -- the
//| pre-pass that fills the frame -- descends into `SIf`, `SFor`, `SWhile` and
//| `SBlock`, but `catch` is an EXPRESSION, so no arm ever scanned one. The walk
//! (`walk_expr`'s `ECatch`) has walked `arm.body` for a long time; only the collector
//! was missing, and `walk_stmt`'s `SLet` never binds anything itself.
//|
//| Nothing noticed for years because `Walker::resolve` is gated on `!self.partial`,
//| and every file containing a catch arm was unread. This is the 0464b / 0465b /
//| 0466b shape for the FOURTH time: a finding nobody can reach is not a finding that
//| does not exist, it is a finding whose file has not been read yet.

//|

///|
/// THE SHAPE, and the TAIL POSITION is load-bearing. `expr catch { .. }` as the last
/// thing in a function parses as `STail`, not `SExpr` -- the first version of the fix
/// handled `SExpr` alone and changed nothing measurable at all.
///
/// `g` is DECLARED in every fixture below rather than invented at the call site. The
/// first version called an undeclared `g(x)` and each row counted it: the binding row
/// reported `1 != 0` and the canary `2 != 1`, both of which are `g`, not the thing
/// under test. An unresolved name in a fixture is indistinguishable from the finding it
/// is supposed to be counting.
test "0467b: a let inside a catch arm binds in that arm" {
  let r = @pipeline.run(
    "///|\nfn g(x : Int) -> Unit {\n  ()\n}\n\n///|\nfn f(x : Int) -> Unit {\n  g(x) catch {\n    e => {\n      let inner = x + 1\n      ignore(inner)\n      ignore(e)\n    }\n  }\n}\n",
    "catchtail.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CANARY BESIDE IT. Same arm, a name the arm never binds. If this reported zero,
/// something was inventing bindings and the row above proved nothing -- which is the
/// failure mode a collector bug can hide behind, since "report fewer undefined names"
/// is exactly what a fix that stops collecting looks like.
test "0467b: a name no arm binds is still reported undefined" {
  let r = @pipeline.run(
    "///|\nfn g(x : Int) -> Unit {\n  ()\n}\n\n///|\nfn f(x : Int) -> Unit {\n  g(x) catch {\n    e => {\n      ignore(e)\n      ignore(nope)\n    }\n  }\n}\n",
    "catchcanary.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// A CATCH IN AN INITIALISER rather than in tail position -- `let y = g(x) catch { .. }`
/// -- because the collector reaches expressions from several statement kinds and each
/// one is a place the fix could have missed. The `STail` row above covers one of them.
test "0467b: a catch in a let initialiser binds in its arm" {
  let r = @pipeline.run(
    "///|\nfn g(x : Int) -> Unit {\n  ()\n}\n\n///|\nfn f(x : Int) -> Unit {\n  let y = g(x) catch {\n    e => {\n      let inner = x + 1\n      ignore(inner)\n      ignore(e)\n    }\n  }\n  ignore(y)\n}\n",
    "catchinit.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// A NESTED ARM, because the collector's `ENoRaise` arm is a separate line of code from
/// its `ECatch` one and a row that only exercises `ECatch` leaves the other unmeasured.
test "0467b: a noraise arm body binds too" {
  let r = @pipeline.run(
    "///|\nfn g(x : Int) -> Unit {\n  ()\n}\n\n///|\nfn f(x : Int) -> Unit {\n  g(x) catch {\n    _ => ()\n  } noraise {\n    e => {\n      let inner = x + 2\n      ignore(inner)\n      ignore(e)\n    }\n  }\n}\n",
    "noraisebody.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

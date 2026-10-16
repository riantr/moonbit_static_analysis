//| Tests for 0468, the BLOCK in the right-hand side of a `let`.
//|
//| Until this increment every `{` in expression position reached the atom's TLBrace arm
//| and went to the FIELD grammar, which rejected the content and reported `expected a
//| struct literal field here` at the brace. A block -- `{ let y = 1; y + 1 }`, whose value
//| is its TAIL -- was therefore unreadable, and the FIELD grammar was the wrong grammar
//| for it.
//!
//| Reach, measured as per-FILE first blocker (`_verify/rank_0468_first_blocker.ps1`):
//| async 352 -> 390 parsed (+38 of the 78 still unread), unreliable 373 -> 285,
//! proton 121 -> 122, labeler 32 -> 33, image 15 -> 17. moui 608/608 and contract 4/4 are
//| UNCHANGED, and that is the control that makes the other five mean something: both were
//| already complete, so they cannot have contributed a single parse.
//!
//| The grammar is settled in `_verify/settle_0468_let_block_rhs.ps1`, 20 rows,
//! scaffolding-verified. FIVE NEGATIVE ROWS ARE ASSERTED TOO, which is new and is the
//| reason `neg_bare_name` exists: that row was called `block_bare_name`, sat in the
//| `block_` family -- asserting the toolchain reads `{ b }` as a block -- and REJECTed
//| [4033] the whole time. Nothing asserted it, so nothing noticed. => 判据: assert the
//| negative rows; asserting only the ones you expect to pass leaves the interesting half
//! of a table unverified.
//!
//! 0468 IS TWO THINGS, NOT ONE. `at_struct_literal` has to learn (TName, TRBrace), or
//! `let x = { a }` -- a legal ONE-FIELD struct literal -- is rewritten as a block. That
//! regression would have IMPROVED every corpus number in the paragraph above while the
//! analyzer quietly started saying something else, which is why the controls below are
//! tests and not a comment.
//!
//| The `EBlock` arms live in five `Expr` matches -- `walk_expr`, `collect_expr_bindings`,
//| `collect_top`, `Infer::ty_of` and `Interp::eval`. Only `walk_expr` is exhaustive; the
//! other four carry `_ => ()` catch-alls that would have done the wrong thing silently.
//! The rows that pin those are in `pipeline_0468_test.mbt`, because "the node was built
//| correctly" and "the analyzer said the right thing about it" are different claims.

//|

///|
/// THE CORPUS SHAPE, verbatim from `moonbitlang/async 0.22.4 src/tls/tls.wasm.mbt:655`
/// and `schannel.mbt:583` -- five files share this line exactly:
///     let _unused : Unit = {
/// MODULE level, not inside a function. Asserting only that it parses is the weak form;
/// the row that says the right NODE was built is below.
test "0468: the corpus shape `let _unused : Unit = { .. }` parses at module level" {
  let r = @parser.parse(
    "///|\nlet _unused : Unit = {\n  ignore(f)\n  ignore(g)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE ROW THAT SAYS IT IS A BLOCK AND NOT A STRUCT LITERAL. "It parses" is satisfied by
/// `EStruct` just as well as by `EBlock` -- both consume the braces and both leave a
/// legal tree -- so this is the row that gives every parse row above its meaning. A parser
/// that built an `EStruct` here would parse the entire corpus and be wrong.
test "0468: a block in the RHS of a let is built as EBlock, not EStruct" {
  let r = @parser.parse("///|\nlet x : Int = {\n  1\n}\n")
  match r.tree.body[0].kind {
    @ast.SLet(name, _, init) => {
      assert_eq(name, "x")
      match init.kind {
        @ast.EBlock(body) => assert_eq(body.length(), 1)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// AND THE TAIL IS A `STail` INSIDE IT, not a statement. The block's value is its last
/// statement, and the three places that have to know that -- `Infer::ty_of` returns
/// `tail_ty`, `Interp::eval` assigns `out` from it -- all of them key off `STail`. A
/// parser that dropped the tail marker would leave the block typed `TUnknown` and
/// evaluated `AAny`, which parses perfectly and reports nothing.
test "0468: a block's last statement is its tail" {
  let r = @parser.parse("///|\nlet x : Int = {\n  1\n}\n")
  match r.tree.body[0].kind {
    @ast.SLet(_, _, init) =>
      match init.kind {
        @ast.EBlock(body) =>
          match body[body.length() - 1].kind {
            @ast.STail(_) => ()
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// A BLOCK WITH A BINDING IN IT -- settle row `block_with_stmts`. This is the row that
/// justifies keeping the statements rather than collapsing the block to its tail at parse
/// time: reducing `{ let y = 1; y + 1 }` to `y + 1` deletes the binding of `y`, and the
/// name-resolution lens then reports `no visible binding for 'y'` on code `moon check`
/// compiles. That is the 0467b defect arriving from a new direction.
test "0468: a block containing a `let` parses" {
  let r = @parser.parse(
    "///|\nfn f() -> Int {\n  let x = {\n    let y = 1\n    y + 1\n  }\n  x\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.EBlock(inner) => assert_eq(inner.length(), 2)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE EMPTY BLOCK, `{ }` -- settle row `block_empty`, ACCEPT. It is the shape most likely
/// to be lost by a rule that requires a tail, and `async` writes it.
test "0468: the empty block `{ }` parses" {
  let r = @parser.parse("///|\nfn f() -> Unit {\n  let x = { }\n  ()\n}\n")
  assert_eq(r.first_error, 0)
}

///|
/// A NESTED BLOCK, `{ { 1 } }` -- settle row `block_nested`, ACCEPT. The inner brace is
/// read by `parse_atom` recursively, so it is the only row here that exercises the new
/// production from inside itself. If the guard consumed the brace before recursing, the
/// outer would hold a malformed inner and this would report.
test "0468: a nested block `{ { 1 } }` parses" {
  let r = @parser.parse("///|\nfn f() -> Int {\n  let x = { { 1 } }\n  x\n}\n")
  assert_eq(r.first_error, 0)
}

///|
/// THE ANNOTATED FORM, `let x : Int = { 1 }` -- settle row `block_annotated`. It is the
/// shape every corpus site uses (`let _unused : Unit = {`, `let fxl : HDecoder = {`,
/// `let y_cover : Double = {`), so it is the one with the most files behind it.
test "0468: an annotated block `let x : Int = { 1 }` parses" {
  let r = @parser.parse(
    "///|\nfn f() -> Int {\n  let x : Int = { 1 }\n  x\n}\n",
  )
  assert_eq(r.first_error, 0)
}

//| ---------------------------------------------------------------------------
//| THE TWO WIDENED DISCRIMINATOR ARMS. Every row below this line is a regression row,
//| and every one of them is a shape that 0468 could have broken while making the
//| corpus numbers go UP. That is the specific hazard of this increment: the obvious
//| three-line fix improves all five corpus counts and silently rewrites good code.
//| ---------------------------------------------------------------------------

///|
/// THE `(TName, TRBrace)` ARM -- settle row `ambig_shorthand_one`, ACCEPT. `{ a }` is a
/// legal ONE-FIELD struct literal, indistinguishable in shape from a one-statement block.
/// Without the widened arm the discriminator answers false, the expression path stops
/// treating it as a literal, and a perfectly good literal is rewritten as a block.
///
/// `struct S` is at `body[0]`-NOT-`body[1]` because there is no `SStruct` in this AST at
/// all: the parser skips struct declarations whole. The first version of this row indexed
/// `[1]` and threw `Error` rather than failing an assertion, which is why the index is
/// worth a note -- a hardcoded offset is a claim about the tree's shape.
test "0468: `{ a }` in a one-field literal stays a struct literal" {
  let r = @parser.parse(
    "///|\nstruct S {\n  a : Int\n}\n\n///|\nfn f() -> S {\n  let a = 1\n  let x = { a }\n  x\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[1].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.EStruct(_, fields) => assert_eq(fields.length(), 1)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE `(TName, TRBrace)` ARM HAS A PRICE, PINNED HERE RATHER THAN LEFT IMPLICIT.
/// Settle row `ambig_shorthand_one_noann` is `fn f() -> Int { let x = { a }; x }` -- the
/// identical brace with NO target type -- and `moon check` REJECTs it [4014]. This parser
/// ACCEPTS it, because `at_struct_literal` decides on shape alone and the parser has no
/// type context to consult.

///|
/// => THAT IS A REAL DIVERGENCE FROM THE TOOLCHAIN AND IT IS NOT AN ACCIDENT. The
/// grammar probe scores exactly this kind of row in its TOO-PERMISSIVE tally, and this is
/// one of the two rows it counts there. The alternative -- reading `{ a }` as a block when
/// unannotated -- needs type-directed parsing to get right and would cost the accepted
/// literal above. `let x = { a }` with no annotation does not occur on any pinned corpus.
test "0468: an unannotated `{ a }` is read as a literal even though moon rejects it" {
  let r = @parser.parse(
    "///|\nfn f() -> Int {\n  let a = 1\n  let x = { a }\n  x\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE `(TStr, _)` ARM -- settle row `ctrl_map_quoted_key`, ACCEPT. A quoted key arrives
/// as `TStr`, not `TName`, so it matched NONE of the discriminator's shapes and every map
/// literal was routed to the BLOCK path. This arm was added AFTER FOUR
/// `pipeline_0452_test.mbt` TESTS WENT RED, which is the whole reason this row exists
/// rather than a comment at the arm.
test "0468: a quoted-key map literal stays a struct literal" {
  let r = @parser.parse(
    "///|\nfn f() -> Map[String, Int] {\n  let x = { \"a\": 1 }\n  x\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.EStruct(_, fields) => assert_eq(fields.length(), 1)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE `(TStr, _)` ARM IS UNCONDITIONAL ON THE SECOND TOKEN, SO THIS ROW IS WHAT MAKES
/// THAT SAFE -- settle row `ctrl_map_quoted_no_colon`, REJECT [4014]. `{ "a" }` has no
/// colon, so it is not a map literal, and if the arm swallowed it the file would be
/// silently READ rather than reported. "Parsed" and "correctly read" are different claims
/// and a recovery path is where the second one is easiest to lose.
test "0468: a quoted key with no colon is still reported" {
  let r = @parser.parse(
    "///|\nfn f() -> Map[String, Int] {\n  let x = { \"a\" }\n  x\n}\n",
  )
  assert_true(r.first_error > 0)
}

///|
/// THE CANARY BESIDE IT, and it is the row that gives that one its meaning: if `{ "a" }`
/// reported zero errors for a reason other than the colon, then `first_error > 0` is
/// measuring the wrong thing. Settle row `ctrl_map_quoted_empty_value`, REJECT [3002].
test "0468: a quoted key with an empty value is still reported" {
  let r = @parser.parse(
    "///|\nfn f() -> Map[String, Int] {\n  let x = { \"a\": }\n  x\n}\n",
  )
  assert_true(r.first_error > 0)
}

///|
/// REGRESSION, the four shapes `at_struct_literal` already accepted before 0468. The
/// widened arm is added to a `match`, and a mutation that drops any EXISTING arm looks
/// exactly like a mutation that adds a new one to the corpus. These four are what stops
/// that swap from passing.
test "0468: named, typed, comma-shorthand and update struct literals all still parse" {
  let pre = "///|\nstruct P {\n  a : Int\n  b : Int\n}\n\n///|\n"
  let cases = [
    "fn f() -> P {\n  let a = 1\n  let x = { a: 1, b: 2 }\n  x\n}\n", "fn f() -> P {\n  let a = 1\n  let b = 2\n  let x = { a, b }\n  x\n}\n",
    "fn f() -> P {\n  let base = P::{ a: 1, b: 2 }\n  let x = { ..base, a: 3 }\n  x\n}\n",
    "fn f() -> P {\n  let a = 1\n  let x = P { a, b: 2 }\n  x\n}\n",
  ]
  for c in cases {
    let r = @parser.parse(pre + "///|\n" + c)
    assert_eq(r.first_error, 0)
  }
}

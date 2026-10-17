//| Tests for 0473 -- the `for` HEADER: a binder head, or an initializer head carrying
//| zero to three clauses.
//|
//| THE DEFECT. `is_c_style_for` decided the form by asking which of `;` and `{` arrives
//| first at depth 0. That is wrong in BOTH directions, because the header is variable
//| length:
//|
//|   `for n = step() { break n + 1 }`          no `;` before `{`, so it was read as a
//|                                            BINDER head and died on `expected 'in'`.
//|                                            async/src/websocket/conn.mbt:486.
//!
//|   `for p in ps; len = 0 { .. }`             a `;` before `{`, so it was read as
//|                                            C-style; `c_for_init` cannot read
//|                                            `p in ps` and `expect(TSemi)` failed.
//|                                            async/src/io/reader.mbt:176.
//!
//| Settled in `_verify/settle_0473_for_header_forms.ps1`: 6 gated rows (2 controls,
//! 4 claims), all ACCEPT against `moon check`.
//!
//| => 判据: THE SECOND FAILURE WAS NOT FIXED HERE, and 0475 has since fixed it. The binder head with
//| C-style clauses now
//| routes CORRECTLY -- to the binder reader -- and that reader stopped at the `;`, so
//| reader.mbt:176 still failed, with `expected 'in'` where it used to say `expected ';'`.
//| Moving an error is not the same as removing it, and the gate below said so explicitly
//| rather than leaving the improvement to be discovered later. 0475 settled the shape against
//| the toolchain, taught the reader to read it, and INVERTED the pin -- the increment number
//| moved 0474 -> 0475 once it was clear the blocker needed an AST decision rather than a
//| discriminator: the grammar is ONE declaration and no condition, not the C-style list.

///|
/// THE HEADER, ONE INITIALIZER AND NO SEMICOLON AT ALL. This is conn.mbt:486 in the
/// smallest form that still asks the question. A row asserting only "it parses" is
/// satisfied by a parser that consumed the tokens and threw the loop away, so this reads
/// the desugaring: one `SLet` for the clause and an `SWhile` whose condition is the
/// CONSTANT TRUE that an absent condition desugars to.
test "0473: a for head with one initializer and no semicolons desugars to SLet + SWhile(true)" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  for n = step() {\n    break n + 1\n  }\n}\n\nfn step() -> Int { 1 }\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          assert_eq(stmts.length(), 2)
          match (stmts[0].kind, stmts[1].kind) {
            (@ast.SLet("n", _, _), @ast.SWhile(c, _)) =>
              match c.kind {
                @ast.EBool(true) => ()
                _ => assert_true(false)
              }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE ABSENT INITIALIZER, and it is a separate claim from the row above. `for ; n > 0 { .. }`
/// is accepted by the toolchain, and the two `expect(TSemi)` this increment removed were
/// rejecting it. Nothing may be pushed for a clause that is not there, so the block carries
/// ONLY the `SWhile` -- a parser that read an empty initializer here would leave an extra
/// statement behind.
test "0473: a for head with no initializer carries no statement for one" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for ; n > 0 {\n    ignore(n)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          assert_eq(stmts.length(), 1)
          match stmts[0].kind {
            @ast.SWhile(_, loop_body) => assert_eq(loop_body.length(), 1)
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL, AND IT IS THE ROW THAT MATTERS MOST. The binder form has a decade of tests
/// behind it, and a discriminator change is exactly the kind of edit that quietly steals
/// it. If `for x in xs` came back as an `SBlock` this increment has traded one class of
/// unreadable file for another, and the corpus numbers alone would not show it.
test "0473 control: a plain binder head is still read as SFor, not as the C-style form" {
  let r = @parser.parse(
    "///|\nfn f(xs : Array[Int]) -> Unit {\n  for x in xs {\n    ignore(x)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SFor("x", _, _, _) => ()
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE SAME CONTROL FOR A TWO-BINDER head, which reader.mbt:186 and unix.mbt:66 both
/// write. The comma is what makes this a different shape, and the desugaring is what makes
/// it a different NODE: a multi-binder head has to be rewritten before the lenses see it.
test "0473 control: a two-binder head is still read as a for" {
  let r = @parser.parse(
    "///|\nfn f(m : Map[String, String]) -> Unit {\n  for k, v in m {\n    ignore(k)\n    ignore(v)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SFor(_, _, _, _) => ()
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE THREE-CLAUSE FORM, which is what `mutate_0470` M1 and `mutate_0472`'s header
/// mutation are both pinned on. It is the shape 0470 settled and 0472 extended, and it has
/// to keep reading exactly as it did: the update clause belongs INSIDE the loop body, so
/// the body carries one statement more than the source block did.
test "0473 control: a three-clause head still appends the update clause to the body" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match stmts[1].kind {
            @ast.SWhile(_, loop_body) => assert_eq(loop_body.length(), 2)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE DEPTH GUARD, on the side that a wrong discriminator would get wrong first. The head
/// of a C-style `for` is an EXPRESSION, so it contains parentheses, and the scan has to
/// step over them rather than treat the `;` inside `f(0, 0)` as a clause separator. Both
/// halves are here because either one alone is satisfied by a scan that does neither:
/// a group in the INITIALIZER and a group in the CONDITION.
test "0473: parentheses inside the head do not split the clause list" {
  let r = @parser.parse(
    "///|\nfn f(xs : Array[Int], n : Int) -> Unit {\n  for i = xs.length(); i < n; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => assert_eq(stmts.length(), 2)
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE BINDER SIDE OF THE SAME GUARD: a call in the sequence, `for x in g(xs)`, must
/// still be a binder. The `(` raises the depth and the scan must not read anything past
/// the `in` it already found.
test "0473: a binder head whose sequence is a call is still a binder head" {
  let r = @parser.parse(
    "///|\nfn f(xs : Array[Int]) -> Unit {\n  for x in g(xs) {\n    ignore(x)\n  }\n}\n\nfn g(xs : Array[Int]) -> Array[Int] { xs }\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SFor("x", _, _, _) => ()
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE ABSENT UPDATE CLAUSE, which is the third way the list can stop. `for i = 0; i < n; {`
/// ends the header with a `;` and no third clause, and it is legal -- reader.mbt:176 and
/// async/src/http/parser.mbt:73 both write it. The test is the LENGTH: the update belongs
/// inside the loop body, so a reader that consumed one anyway leaves a statement behind
/// that nobody wrote, and `loop_body.length()` is where that shows up.
test "0473: an absent update clause leaves the body exactly as written" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match stmts[1].kind {
            @ast.SWhile(_, loop_body) => assert_eq(loop_body.length(), 1)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE UPDATE CLAUSE THAT IS THERE, as the control for the row above: same program, one
/// clause more, one statement more in the body. Without this pair the absent-update test
/// could pass because the update is never appended at all.
test "0473 control: a present update clause is appended to the body" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match stmts[1].kind {
            @ast.SWhile(_, loop_body) => assert_eq(loop_body.length(), 2)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// WHAT THIS INCREMENT DID NOT FIX, and what 0475 then DID. Pinned as a FAILING test rather
/// than a note, so the improvement could not be mistaken for the fix later; the pin has now
/// been INVERTED, which is the only honest thing to do with it once the shape is read.
///
/// 0473 made the BINDER head with C-style clauses -- reader.mbt:176, unix.mbt:66,
/// windows.mbt:57 -- route CORRECTLY, to the binder reader, and that reader stopped at the
/// `;`. The error moved from `expected ';'` to `expected 'in'` and the file stayed unread.
/// 0475 settled the shape against the toolchain and taught the reader to read it, so this
/// now PARSES. The name keeps the 0475 marker so the history stays readable from a failure
/// report.
///
/// It is not merely "it parses": 0475's grammar is ONE declaration and no condition, which
/// is NOT the C-style variable-length list, and `parser_0475_test.mbt` is what holds that.
test "0473: a binder head followed by a C-style clause is now READ (fixed by 0475)" {
  let r = @parser.parse(
    "///|\nfn f(ps : Array[String]) -> Int {\n  let total = for p in ps; len = 0 {\n    continue len + p.length()\n  } nobreak {\n    len\n  }\n  total\n}\n",
  )
  assert_eq(r.first_error, 0)
}

//| Tests for 0476 -- the single STEP that may follow a binder head's initialization clause.
//|
//| WHY. 0475 taught the binder head to read `; <one declaration>` and its settle REJECTed the
//| whole clause, on the evidence of one row: `for p in ps; len = 0; n = 1 { .. }` is
//| REJECT(4106). 0476 chased the next corpus blocker and found reader.mbt:186 writing
//|
//|     for prefix in prefix_list; len = 0; len = len + prefix.length() { .. }
//|
//| which `moon check` COMPILES. The settle was the thing that had to give, and the reason is
//| in the compiler's own sentence rather than in either program:
//|
//|     Unknown binder n in the for-loop steps.
//|     Binders in the steps must be declared in the initialization block of the for-loop.
//|
//| 4106 was never about the NUMBER of clauses. It was about WHERE THE BINDER WAS DECLARED:
//| `n` is declared nowhere, `len` is declared two tokens earlier. 0475's row generalised from
//: one program to a rule about clause count, and a hand-written fixture is a thin thing to
//| generalise a grammar from -- the corpus carries a compiler's verdict on real code.
//|
//| SETTLED, `_verify/settle_0476_for_steps.ps1`, 2 controls + 7 rows, GATE OK:
//!
//!   for p in ps; len = 0; len = len + p.length() { .. }  ACCEPT   the corpus shape
//!   for p in ps; len = 0; n = 1 { .. }                    REJECT(4106)  a binder nothing declares
//!   for p in ps; len = 0; len = p.length() { .. }         ACCEPT       the LOOP BINDER is in scope
//!   a bare expression in a step                            REJECT(3002)
//!   two steps                                              REJECT
//!   a step with no initialization clause                   REJECT(4021, 4018)
//!   `;` immediately followed by `{` (an empty step list)   ACCEPT
//!
//| => NO NEW NODE, and the placement is not a choice: a step runs at the END of each
//| iteration, which is where `parse_c_for` already puts the C-style update clause. So the step
//| is APPENDED to the loop body, and appending it before the multi-binder path builds its
//| `$pair` destructuring is what puts it after that destructuring -- which is the order that
//! path needs, and it falls out of doing it once instead of at two return sites.

///|
/// THE CORPUS SHAPE, and the row that says the step is a STATEMENT INSIDE THE LOOP rather than
/// a sibling of it. `body.length()` is the instrument: a reader that ran the step before the
/// body, or dropped it, gives 1; only the append gives 2.
test "0476: the step is appended to the end of the loop body" {
  let r = @parser.parse(
    "///|\nfn f(prefix_list : Array[String]) -> Unit {\n  for prefix in prefix_list; len = 0; len = len + prefix.length() {\n    ignore(prefix)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          assert_eq(stmts.length(), 2)
          match stmts[0].kind {
            @ast.SLet("len", _, _) =>
              match stmts[1].kind {
                @ast.SFor("prefix", _, _, lbody) => {
                  assert_eq(lbody.length(), 2)
                  match lbody[1].kind {
                    @ast.SAssign(_, _) => ()
                    _ => assert_true(false)
                  }
                }
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
/// THE CONTROL, and the row that says the step is not added when there is none. 0475's shape
/// and 0476's differ by one clause, so without this the increment's own test would pass on a
/// reader that appends a phantom statement to every binder head with a declaration.
test "0476 control: a declaration with no step leaves the body exactly as written" {
  let r = @parser.parse(
    "///|\nfn f(ps : Array[String]) -> Unit {\n  for p in ps; len = 0 {\n    ignore(p)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match stmts[1].kind {
            @ast.SFor("p", _, _, lbody) => assert_eq(lbody.length(), 1)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE EMPTY STEP LIST, which the settle records as ACCEPT and which is the row a naive
/// reader breaks hardest. `;` then `{` -- if the step reader takes the body's own brace as a
/// step, a legal header stops parsing. This is why the guard tests the token AFTER the `;`.
test "0476: an empty step list between the declaration and the body is accepted" {
  let r = @parser.parse(
    "///|\nfn f(ps : Array[String]) -> Unit {\n  for p in ps; len = 0; {\n    ignore(p)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match stmts[1].kind {
            @ast.SFor("p", _, _, lbody) => assert_eq(lbody.length(), 1)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE TWO ROWS THAT ARE STILL REFUSED, which are 0475's negative rows and now have teeth.
/// 0475 kept them with the admission that NO MUTATION IN THAT GATE could turn them red; this
/// increment is the risk they were naming, arriving one increment later. The reader checks the
/// step's token shape AND that its target is the declared binder, so both of these are refused
/// in the same direction the toolchain refuses them.
test "0476: a step must be an assignment to the declared binder" {
  let bare = @parser.parse(
    "///|\nfn f(ps : Array[String]) -> Unit {\n  for p in ps; len = 0; len > 0 {\n    ignore(p)\n  }\n}\n",
  )
  assert_true(bare.first_error != 0)
  let undeclared = @parser.parse(
    "///|\nfn f(ps : Array[String]) -> Unit {\n  for p in ps; len = 0; n = 1 {\n    ignore(p)\n  }\n}\n",
  )
  assert_true(undeclared.first_error != 0)
}

///|
/// AND THE MULTI-BINDER PATH WITH A STEP, which is where the append has to land AFTER the
/// `$pair` destructuring. If it landed before, the destructuring would read the step's value as
/// the pair; if it were applied at the two return sites separately, this path would be the one
/// missed. The row asserts the ORDER, which is the whole claim.
test "0476: a two-binder head puts the step after the pair destructuring" {
  let r = @parser.parse(
    "///|\nfn f(m : Map[String, Int]) -> Unit {\n  for k, v in m; n = 0; n = n + 1 {\n    ignore(k)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match stmts[1].kind {
            @ast.SFor("$pair", _, _, lbody) => {
              // $pair destructuring, the body statement, then the step.
              assert_eq(lbody.length(), 3)
              match lbody[0].kind {
                @ast.SLetDestruct(_, _) => ()
                _ => assert_true(false)
              }
              match lbody[2].kind {
                @ast.SAssign(_, _) => ()
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

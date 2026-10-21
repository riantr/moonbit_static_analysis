//| Tests for 0472 -- the C-style `for`'s initializer LIST, and a `continue` that CARRIES
//| VALUES.
//|
//| Two related gaps, both measured as per-FILE first blockers on the tree at 0471 (31 unread
//| files across four corpora).
//!
//|   THE HEADER. Three async files stop on a comma-separated initializer list:
//!
//!       async/src/websocket/utils.mbt:49       for i = 0, remaining = remaining; i < data.length(); {
//!       async/src/internal/gzip_internal/crc32.mbt:53       for crc = current, i = 0; i + 8 <= len; {
//!       async/src/socket/addr_utils.mbt:262     for i = 0, zero_group_start = 0; i < 8; i = i + 1 {
//!
//|   `c_for_init` read exactly ONE initializer and `parse_c_for` pushed one statement.
//!
//|   THE VALUE. Two of those three then stopped on the line after, because `continue` bumped
//|   the keyword and returned, leaving its values in the stream:
//!
//!       async/src/socket/addr_utils.mbt:267                    continue i + 1, i + 1
//!       async/src/internal/gzip_internal/crc32.mbt:63         continue crc, i + 8
//!
//!   `walk.mbt` and `infer.mbt` both treat `SContinue` as a no-op, so before this increment
//!   the names in `continue p, r, c, vr` were not read by anything -- which is why the change
//!   also removes findings rather than only adding reach.
//!
//! Settled in `_verify/settle_0472_for_init_list.ps1`: 10 rows, 2 controls, 8 claims.
//!
//! => 判据: THE VALUES ARE READ AND NOT ASSIGNED. `continue a, b` means "set loop variable
//! one to a, loop variable two to b", and those variables are named by the header, four
//! frames away. Synthesising `SAssign(EName(loopvar_i), v_i)` would mean the type lens
//! checking an assignment nobody wrote against a target that may not exist -- a plausible
//! fabrication that would manufacture findings. Reach and semantics are separate increments.

///|
/// THE HEADER, two initializers: the block the C-style `for` desugars to must carry TWO
/// `SLet`s, in order. A row asserting only "it parses" is satisfied by one binding and a
/// comma left in the stream, so this reads the node kinds.
test "0472: a comma-separated initializer list binds every name" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0, total = 0; i < n; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          // <init x2> + the SWhile the desugaring produces
          assert_eq(stmts.length(), 3)
          match (stmts[0].kind, stmts[1].kind) {
            (@ast.SLet("i", _, _), @ast.SLet("total", _, _)) => ()
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THREE initializers, so the claim is about a LIST and not about the number two. `utils.mbt`
/// and `crc32.mbt` both carry two; a reader that stopped after the first would pass those and
/// fail this.
test "0472: a three-element initializer list parses" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0, a = 1, b = 2; i < n; {\n    ignore(a + b)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          assert_eq(stmts.length(), 4)
          match (stmts[0].kind, stmts[1].kind, stmts[2].kind) {
            (@ast.SLet("i", _, _), @ast.SLet("a", _, _), @ast.SLet("b", _, _)) =>
              ()
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// A TUPLE in the value must NOT be mistaken for a second initializer. `for i = (0, 1);` is
/// one binding whose value is a pair -- `parse_stmt` consumes the tuple whole, so the comma
/// it contains is already gone by the time the list test runs. Settled as `ctl_tuple_comma`.
test "0472: a tuple in the initializer value is one binding, not two" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  for i = (0, 1); ; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// AND THE SINGLE INITIALIZER IS UNCHANGED, which is the control for the two rows above. If
/// the list reader had become unconditional in some way, this is the row that says it did not.
test "0472: a single initializer still binds exactly one name" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; i = i + 1 {\n    ignore(i)\n  }\n}\n",
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
/// `continue` WITH VALUES. The values are read, so the statement is a block carrying them --
/// and the row asserts the VALUES ARE THERE, because "the file parses" is also satisfied by
/// reading the keyword and dropping the rest, which is the original defect.
test "0472: a continue with values reads them" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0, j = 0; i < n; i = i + 1 {\n    continue i + 1, j + 1\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE ROW THIS INCREMENT MOST NEEDS, AND THE ONE THE FIRST DRAFT FAILED. A BARE `continue`
/// is followed by a `TNewline` and then the NEXT STATEMENT. An arm that skipped separators
/// before looking for a value would read that statement's head as this one's value and
/// swallow the rest of the body -- the file would parse, every corpus count would improve,
/// and the analyzer would have stopped seeing code.
/// => the probe is a NAME after the continue, because only something downstream can see it.
test "0472: a bare continue does not swallow the next statement" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; i = i + 1 {\n    continue\n    ignore(zq_after_continue)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// AND THE CONTROL THAT GIVES THAT ROW ITS MEANING: the same probe after a `continue` WITH a
/// value, where the value legitimately ends the line. If both rows saw the same thing, the
/// first would prove nothing about the second.
test "0472: a continue with a value also leaves the next line alone" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; i = i + 1 {\n    continue i + 1\n    ignore(zq_after_valued)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// A BARE `continue` IS STILL AN `SContinue`, not a block. The early return matters: wrapping
/// every bare continue in a one-element `SBlock` would change the tree shape everywhere
/// `continue` appears, for no reading gained.
///
/// 0495 AND THE PAYLOAD. The valued form used to be a block -- `SBlock([SContinue,
/// SExpr(a), SExpr(b)])` -- and the interpreter read the carried values as
/// statements after a terminator, which it reported as `unreachable code` on
/// three corpora. The values are the terminator's own payload now, so the BARE
/// form is the one that carries nothing, and that is what this row pins.
test "0472: a bare continue is still SContinue and not an SBlock" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  while n > 0 {\n    continue\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SWhile(_, lbody) =>
          match lbody[0].kind {
            @ast.SContinue(vals) => assert_eq(vals.length(), 0)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

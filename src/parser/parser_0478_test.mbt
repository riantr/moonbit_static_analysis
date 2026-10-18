//| Tests for 0478 -- the `<?` PAYLOAD on an expression.
//|
//| WHY. proton 0.3.4 carries 26 sites of `expr <? { "key": value, .. }` across 7 files and
//| no other pinned corpus carries one. Four of those files were unreadable for it, which is
//| what the backlog entry named. Measured: `parsed` 131 -> 135, `unreliable` 186 -> 37,
//| `actionable` still 0.
//|
//| WHAT THE PAYLOAD IS, and why it leaves no node. `@xlog` 0.4.2's `pkg.generated.mbti`:
//!
//!     pub fn error(category? : String, loc~ : SourceLoc) -> Event?
//!     type Event
//!     pub fn Event::write_object_begin(Self) -> Unit
//!     pub fn[T : ToJson] Event::write_object_field(Self, String, T) -> Unit
//!     pub fn Event::write_object_end(Self) -> Unit
//!
//! The payload is a JSON object literal DESUGARED TO METHOD CALLS ON THE RECEIVER, and the
//| receiver is an OPTIONAL -- which is why the return type is `Event?`. The subset has no
//| `Event`, so there is nothing to attach fields to and the payload is consumed and
//| DISCARDED. That is a deliberate loss and the first row below pins it.
//|
//| WHAT IS NOT LOST is the VALUE: each value after a `:` is read with `parse_expr`, so the
//| names in it resolve. `facade_bridge.mbt:11` writes `{ "message": "command dispatch
//| failed", "detail": detail }` where `detail` is a lambda parameter.
//|
//| SETTLED, `_verify/settle_0478_log_payload.ps1`, 2 controls + 5 rows, GATE OK:
//!
//!   ACCEPT             the corpus shape
//!   ACCEPT             a value may be an EXPRESSION (`"detail": detail`)
//!   ACCEPT             a TRAILING COMMA is legal here, unlike a struct field (3800)
//!   ACCEPT             `<? { }` with no field at all
//!   REJECT(3002)       the KEY must be a string literal
//!   REJECT(3002, 3002) AT MOST ONE payload
//!
//! The last one shapes the reader rather than bounding it: a LOOP would absorb a second
//! `<?` that the toolchain refuses, so the refusal would disappear. That row and the `a < ?`
//| control below BOTH failed on the first run of the reader, which is why it carries
//! `had_payload` and why the brace is checked before a token is consumed.

///|
/// THE CORPUS SHAPE, and the row that says the payload is consumed rather than left in the
/// token stream. `first_error == 0` is half the claim: a reader that consumed `<` and `?`
/// but not the `{ .. }` would leave a brace for the statement reader and the file would die.
///
/// The other half is `stmts.length() == 1`. The payload is DISCARDED, so the body is still
/// one statement; a reader that KEPT it would have to invent a node and a statement for it.
/// WHICH expression node a bare call becomes is deliberately not pinned here -- that is a
/// parser decision this increment does not make, and pinning it is how a test starts
/// failing for a reason that has nothing to do with what it is for.
test "0478: the payload is consumed and leaves no node behind" {
  let r = @parser.parse(
    "///|\nfn emit(d : Int) -> Unit {\n  ignore(d)\n  ignore(d)\n}\n\n///|\nfn go(d : Int) -> Unit {\n  emit(d) <? { \"message\": \"m\", \"detail\": d }\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  let stmts = match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(inner) => inner
        _ => body
      }
    _ => []
  }
  assert_eq(stmts.length(), 1)
  match stmts[0].kind {
    @ast.SExpr(_) => ()
    @ast.STail(_) => ()
    _ => assert_true(false)
  }
}

///|
/// THE EMPTY PAYLOAD and THE TRAILING COMMA, which are the two ACCEPT rows the corpus
/// cannot witness: all 26 sites have at least one field and none has a trailing comma. Both
/// are boundaries a reader written for the corpus alone would get wrong, and a trailing comma
/// is 3800 in a struct field -- the same character, two grammars.
test "0478: an empty payload and a trailing comma are both consumed" {
  let empty = @parser.parse(
    "///|\nfn emit(d : Int) -> Unit {\n  ignore(d)\n  ignore(d)\n}\n\n///|\nfn go(d : Int) -> Unit {\n  emit(d) <? { }\n}\n",
  )
  assert_eq(empty.first_error, 0)
  let comma = @parser.parse(
    "///|\nfn emit(d : Int) -> Unit {\n  ignore(d)\n  ignore(d)\n}\n\n///|\nfn go(d : Int) -> Unit {\n  emit(d) <? { \"detail\": d, }\n}\n",
  )
  assert_eq(comma.first_error, 0)
}

///|
/// AT MOST ONE PAYLOAD. This is the row that separates a LOOP from a single consumption, and
/// the settle is what says which: REJECT(3002, 3002). The reader must stop at the first
/// closing brace and leave the second `<?` for the statement reader to report, so the file
/// does NOT parse. A loop would make this ACCEPT and quietly delete a refusal the toolchain
/// makes. It failed on the first run of the reader, which is the whole reason `had_payload`
/// exists in `parse_postfix_from`.
test "0478: a second payload is a parse error, not a second consumption" {
  let r = @parser.parse(
    "///|\nfn emit(d : Int) -> Unit {\n  ignore(d)\n  ignore(d)\n}\n\n///|\nfn go(d : Int) -> Unit {\n  emit(d) <? { \"a\": d } <? { \"b\": d }\n}\n",
  )
  assert_true(r.first_error != 0)
}

///|
/// THE KEY REFUSAL. A non-literal key is REJECT(3002) and the reader leaves the cursor on it
/// rather than consuming it, so the refusal is reported against the offending token. This
/// row is what says the key is matched as a STRING LITERAL and not merely skipped -- a reader
/// that skipped arbitrary tokens would ACCEPT here, discarding exactly the information the
/// settle says must not be discarded.
test "0478: a key that is not a string literal is refused" {
  let r = @parser.parse(
    "///|\nfn emit(d : Int) -> Unit {\n  ignore(d)\n  ignore(d)\n}\n\n///|\nfn go(d : Int, k : String) -> Unit {\n  emit(d) <? { k: d }\n}\n",
  )
  assert_true(r.first_error != 0)
}

///|
/// THE CONTROL, and it is the reason the rows above mean anything. A call with NO payload has
/// to keep parsing, and `a < ?` -- the other reading of the same two tokens -- has to stay a
/// parse error rather than being swallowed. The second half is the one that matters, and it
/// also failed on the first run: a guard that consumed `<` and `?` and then found no `{`
/// left the flag to be read as a fresh statement, and the file parsed. A brace AFTER the
/// pair is what makes the operator exist at all, so the brace is checked before a single
/// token is consumed.
test "0478 control: no payload parses, and `a < ?` stays refused" {
  let plain = @parser.parse(
    "///|\nfn emit(d : Int) -> Unit {\n  ignore(d)\n  ignore(d)\n}\n\n///|\nfn go(d : Int) -> Unit {\n  emit(d)\n}\n",
  )
  assert_eq(plain.first_error, 0)
  let lessThan = @parser.parse(
    "///|\nfn emit(d : Int) -> Unit {\n  ignore(d)\n  ignore(d)\n}\n\n///|\nfn go(d : Int, flag : Bool) -> Unit {\n  emit(d) < ?flag\n}\n",
  )
  assert_true(lessThan.first_error != 0)
}

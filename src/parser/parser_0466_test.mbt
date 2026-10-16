//| Tests for 0466, the return-type EFFECT annotation, and 0466b the `.. rest` binding.
//
//| 0466 -- `-> T noraise` and `-> T nocancel` had no production, so every one of them
//| stopped the parse at the keyword and reported `expected '{'` AT THE BODY: a message
//| about a brace standing where a keyword is. Reach, measured as per-FILE first
//| blocker over the files still unread: 16 of them (async 11, proton 5).
//|
//| The grammar is settled in `_verify/settle_0466_effect_annotation.ps1`, 17 rows,
//| all controls and canaries held. Two of its results would have been implemented
//| wrong on the symbol alone:
//!
//!   `-> T !`            ACCEPT     -- `!` is in the same slot as `noraise`; it is
//!                                     the effect-ROW operator 0.4.23-0.4.29 read
//!   `-> T noraise raise` REJECT(3002) -- effects do NOT stack, so a LOOP is wrong
//!
//| 0466b -- `guard! buf is [u32le(_), u32le(mask), .. payload]` at
//| `moonbitlang/async 0.22.4 src/internal/event_loop/fs.mbt:105` and `:152`, both
//| reported `undefined name 'payload'` -- a name the PATTERN ITSELF introduces.
//| Settled in `_verify/settle_0466b_rest_binding.ps1`, with a canary beside the
//| positive row because "the name is in scope" and "the name was invented" are not
//| distinguishable by the positive row alone.

//|

///|
/// THE CORPUS SHAPE: `-> Unit noraise` on an async fn, and `-> Unit nocancel`.
/// Asserting only that these PARSE would be weak, so the rows beside these assert
/// that a non-effect is still refused.
test "0466: `-> T noraise` and `-> T nocancel` parse" {
  let a = @parser.parse(
    "///|\nasync fn acquire(self : Int) -> Unit noraise {\n  ()\n}\n",
  )
  assert_eq(a.first_error, 0)
  assert_eq(a.reports.length(), 0)
  let b = @parser.parse(
    "///|\nasync fn remove(path : String) -> Unit nocancel {\n  ()\n}\n",
  )
  assert_eq(b.first_error, 0)
  assert_eq(b.reports.length(), 0)
}

//|

///|
/// THE CANARY, and it is the row that gives the two above meaning. `-> Unit bogus`
/// is REJECTed by the toolchain (settle row `ret_bogus_effect`, 3002), so a parser
/// that consumed "whatever sits between the return type and `{`" would accept a
/// program `moon check` refuses.
test "0466: a non-effect word after the return type still reports" {
  let r = @parser.parse("///|\nfn f() -> Unit bogus {\n  ()\n}\n")
  assert_true(r.first_error > 0)
}

//|

///|
/// `-> T !` and `-> T raise` ALREADY worked, and they are here as regression guards
/// for the clause this increment extended. `ret_bang` and `ctl_raise` are settle rows;
/// these are the parser rows. If either ever stops parsing, the extension broke a
/// construct that was working rather than adding one.
test "0466: the `!` and `raise` spellings are untouched by the extension" {
  let bangCase = @parser.parse("///|\nfn f() -> Unit ! {\n  ()\n}\n")
  assert_eq(bangCase.first_error, 0)
  // `raise` is a KEYWORD, so the binding cannot be named `raise`.
  let raiseCase = @parser.parse("///|\nfn f() -> Unit raise {\n  ()\n}\n")
  assert_eq(raiseCase.first_error, 0)
}

//|

///|
/// A NON-Unit return type carries the effect too. All 16 reachable corpus sites are
/// `-> Unit`, so a parser that only matched `Unit` would pass every one of them and
/// still be wrong.
test "0466: the effect sits after any return type, not only `Unit`" {
  let r = @parser.parse("///|\nfn f() -> ArrayView[Byte] noraise {\n  []\n}\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

//|

///|
/// 0466b -- `.. rest` in an ARRAY pattern BINDS, and the tree says so.
///
/// The row asserts the BINDING LIST, not just that the file parsed: a parser that
/// skipped the pattern and left `rest` unbound still parses, and the finding it
/// produces is an `UndefinedName` downstream rather than a parse error here.
test "0466b: `.. rest` in an array pattern is pushed as a binding" {
  let r = @parser.parse(
    "///|\nfn f(xs : Array[Int]) -> Bool {\n  xs is [a, .. rest]\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[body.length() - 1].kind {
        // `STail`, not `SExpr`: a function's last expression is its RETURN value and
        // gets its own statement kind.
        @ast.STail(e) =>
          match e.kind {
            @ast.EIs(_, bindings) => {
              assert_true(bindings.contains("rest"))
              assert_true(bindings.contains("a"))
              // `_` binds nothing -- it is the discard, and the audit exempts it.
              assert_false(bindings.contains("_"))
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

//|

///|
/// AND THE PATH RULE IS STILL A PATH RULE. `pattern_binding_at` refuses a name
/// preceded by ONE dot, which is what keeps `Foo.bar` from binding `bar`. The 0466b
/// predicate checks TWO dots for exactly this reason.
///
/// WHAT THIS ROW DOES AND DOES NOT PIN, because it was written claiming more than it
/// can see. Mutation M3 widens `rest_binding_at` from two dots to one, and M3 was
/// first declared against THIS row -- and the harness reported a MUST-RED MISS, which
/// was correct: `Some(v)` contains no dot at all, so the row cannot distinguish one
/// dot from two. It pins that a CONSTRUCTOR head is not a binding, which is worth
/// pinning, and that is all.
///
/// The two-dot WIDTH is pinned by a settle rather than by a test: `is Foo.bar` is
/// REJECTed by the toolchain (4021 + 3002), so a one-dot name cannot occur in a valid
/// pattern at all and the width is unobservable from the outside. See M3's Prove.
test "0466b: a constructor head in a pattern is not bound" {
  let r = @parser.parse("///|\nfn f(x : Int) -> Bool {\n  x is Some(v)\n}\n")
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[body.length() - 1].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.EIs(_, bindings) => {
              assert_true(bindings.contains("v"))
              // `Some` is a CONSTRUCTOR head, not a binding. Settled 7/7 in
              // `_verify/settle_0460_array_pattern.ps1`; binding it would report two
              // unused locals that do not exist.
              assert_false(bindings.contains("Some"))
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

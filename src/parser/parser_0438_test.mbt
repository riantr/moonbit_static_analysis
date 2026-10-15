///|
/// `value[:]` — a slice whose bounds may be EMPTY.
///
/// The biggest remaining blocker cause on wzzc-dev/moui 0.1.12, at 6 of the 25
/// files. `parse_postfix_from`'s bracket branch called `parse_expr()` for the
/// START bound and only afterwards asked `at(TColon)`, so a `[` sitting directly
/// on a `:` handed the colon to the expression parser and the file died with
/// ``unexpected token `:` ``. That is the reason string on eight of the blocked
/// files, and on every one of those the `:` is a bound marker, not a stray token.
///
/// Two shapes, both real, both in the corpus:
///   `value[:]`        both bounds empty    core/semantics.mbt:71,
///                      core/declaration.mbt:102, `bytes[:]` at
///                      backend/windows/windows_accessibility_bridge.mbt:490
///   `chars[:index]`   open start, real end core/unicode/grapheme_cluster.mbt:248
///
/// The parser's comment here used to read "an open START (`[:n]`) is not in the
/// corpus and reports honestly". True when written; `chars[:index]` made it
/// stale, and "reports honestly" was doing a good deal of work to disguise a
/// blocker. Corrected in the source comment too.
///
/// Settled with the toolchain, one form per package with a broken canary beside
/// each (`_verify/probe_sweep_0434.ps1`, canary firing):
///   `let s = value[:]`    MOON-OK
///   `let s = value[:2]`   MOON-OK
///   `let c = xs[0]`       MOON-OK   (the control)
///   `fn canary( { let = 1 }`  MOON-BAD, as it must be
/// and all three SELF-OK after the change.
///
/// The third case was `value[0]` on a String at first and came back MOON-BAD,
/// which the probe reports as "this frontend reads MoonBit the toolchain
/// rejects" -- a verdict about MY probe, since a String is not indexable in
/// MoonBit. It now uses an Array. ⇒ 判据: a MOON-BAD cell is a question about
/// the probe source first and about the grammar second.
///

///|
/// WHAT THESE TESTS ASSERT. The observable is the SHAPE of the index, and the
/// distinction that matters is `opaque` versus `int`: a missing bound becomes
/// `EBigInt`, the same placeholder the open END already used, because
/// `const_eval` must not fold a bound it never read. A fix that read the
/// missing side as, say, `EInt(0)` would satisfy every `first_error == 0` here
/// and silently invent a bound. `describe_shape` exists so the four shapes --
/// `index`, `range(opaque,opaque)`, `range(opaque,int)`, `range(int,opaque)` --
/// can be compared as strings, which a parser test can do and which no family
/// count can.
///
/// (It returns a string rather than asserting because `assert_*` is
/// error-raising: a plain helper calling it needs an error type and cannot be
/// called from a `test` body at all. The test body raises.)

///|
/// Describes a bracket expression as `index` or `range(start,end)`.
fn describe_shape(e : @ast.Expr) -> String {
  match e.kind {
    @ast.EIndex(_, ix) =>
      match ix.kind {
        @ast.ERange(a, b) =>
          "range(" + describe_bound(a) + "," + describe_bound(b) + ")"
        _ => "index(" + describe_bound(ix) + ")"
      }
    _ => "not-an-index"
  }
}

///|
/// `opaque` for a bound that was never written, and something else for one that
/// was. `int` is deliberately not the literal's VALUE: what these tests claim is
/// that a bound was read, not what it was.
fn describe_bound(e : @ast.Expr) -> String {
  match e.kind {
    @ast.EBigInt => "opaque"
    @ast.EInt(_) => "int"
    _ => "other"
  }
}

///|
/// The shape of the first statement's value, whether that statement BINDS it
/// (`let s = value[:]`) or IS it (`value[:]`). Both spellings occur in the
/// corpus -- `let byte_length = @utf8.encode(value[:], ...)` on one line,
/// `chars[:index]` inside a call on another -- and a helper that understood only
/// one spelling made the first draft of these tests report `no-STail` for every
/// fixture. That reads like the parser producing something unfamiliar, when it
/// was the test looking in the wrong place.
fn first_stmt_shape(src : String) -> String {
  let r = @parser.parse(src)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(v) => describe_shape(v)
        @ast.SLet(_, _, v) => describe_shape(v)
        _ => "neither-STail-nor-SLet"
      }
    _ => "no-SFunc"
  }
}

///|
/// THE SHAPE, verbatim from `core/semantics.mbt:71`:
/// `let byte_length = @utf8.encode(value[:], bom=false).length()`
test "0438: a slice with both bounds empty is read" {
  let r = @parser.parse(
    "fn f(value : String) -> Int {\n  let s = value[:]\n  s.length()\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(
    first_stmt_shape(
      "fn f(value : String) -> Int {\n  let s = value[:]\n  s.length()\n}\n",
    ),
    "range(opaque,opaque)",
  )
}

///|
/// The open-start shape, `grapheme_cluster.mbt:248`. This is the one the stale
/// comment claimed was not in the corpus, and asserting it is what stops that
/// claim from coming back.
test "0438: an open start bound with a real end is read" {
  let r = @parser.parse(
    "fn f(value : String) -> Int {\n  let s = value[:2]\n  s.length()\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(
    first_stmt_shape(
      "fn f(value : String) -> Int {\n  let s = value[:2]\n  s.length()\n}\n",
    ),
    "range(opaque,int)",
  )
}

///|
/// CONTROL, and the one that decides whether the new branch is narrow. The fix
/// asks `at(TColon)` immediately after `[`, which is a condition a plain index
/// could be diverted by -- and a plain index is not a range. If the branch fired
/// unconditionally, `xs[0]` would come back as `index(opaque)` (the placeholder
/// standing in for the index that was dropped) instead of `index(int)`.
test "0438 control: a plain index keeps its real operand and is not a range" {
  let src = "fn f(xs : Array[Int]) -> Int {\n  let c = xs[0]\n  c\n}\n"
  let r = @parser.parse(src)
  assert_eq(r.first_error, 0)
  assert_eq(first_stmt_shape(src), "index(int)")
}

///|
/// CONTROL: the open END already worked and must be untouched. It is the mirror
/// of the new case, and the two together are what say the placeholder treatment
/// is symmetric rather than the new shape having been special-cased.
test "0438 control: an open end bound is unchanged" {
  let r = @parser.parse(
    "fn f(value : String) -> Int {\n  let s = value[2:]\n  s.length()\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(
    first_stmt_shape(
      "fn f(value : String) -> Int {\n  let s = value[2:]\n  s.length()\n}\n",
    ),
    "range(int,opaque)",
  )
}

///|
/// CONTROL: a two-sided slice with BOTH bounds real is the ordinary case, and it
/// must produce two real bounds rather than two placeholders.
test "0438 control: a two-sided slice keeps both real bounds" {
  let r = @parser.parse(
    "fn f(value : String) -> Int {\n  let s = value[1:2]\n  s.length()\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(
    first_stmt_shape(
      "fn f(value : String) -> Int {\n  let s = value[1:2]\n  s.length()\n}\n",
    ),
    "range(int,int)",
  )
}

///|
/// The statement after the slice has to survive. The blocking source line in
/// every one of the six files is inside a longer expression --
/// `@utf8.encode(value[:], bom=false).length()` -- so this is the fixture that
/// exercises the chain the real files carry, and `first_error == 0` alone is
/// what a fix that stopped one token early would also report.
test "0438: a slice with empty bounds does not cost the statements after it" {
  let r = @parser.parse(
    "fn g() -> Int {\n  7\n}\nfn f(value : String) -> Int {\n  let s = value[:]\n  let n = s.length()\n  g()\n  n\n}\n",
  )
  assert_eq(r.first_error, 0)
  // `enum`-free, so `body[0]` is `fn g` and `body[1]` is `fn f`: four statements.
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 4)
    _ => assert_true(false)
  }
}

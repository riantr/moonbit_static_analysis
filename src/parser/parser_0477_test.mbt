//| Tests for 0477 -- the CONSTRUCTOR PATTERN on the left of a `let`.
//|
//| WHY. `async/src/os_error/error.mbt` was the whole of one corpus file's report:
//|
//|     1x  expected '='
//|
//| at line 79, `let OSError(errno, context~) = self`. There is no `parse_pattern` in the
//| parser: a binding was read as a NAME followed by `=`, so `OSError` was consumed as the bound
//| variable and the reader then met `(` where it wanted `=`. 21 such sites in that corpus.
//|
//| The reader itself already existed -- `parse_is_pattern` has read constructor patterns for
//| `is` since 0444 -- so this increment is a CALL SITE, and the thing worth testing is that
//| the call site reads the right token range and produces the node that BINDS.
//|
//| SETTLED, `_verify/settle_0477_let_pattern.ps1`, 2 controls + 9 rows, GATE OK:
//|
//!   ACCEPT    let Circle(r) = s             positional
//!   ACCEPT    let Circle(r, label~) = s     labeled
//!   ACCEPT    let Circle(label~) = s        the label BINDS the name
//!   ACCEPT    let Circle(r, ..) = s         `..` absorbs the rest
//!   ACCEPT    let Wrap(One(inner)) = s      nested
//!   ACCEPT    let (a, b) = p                a tuple
//!   REJECT(4080, 3007)  anything after `..`      NOT this reader's check
//!   REJECT(4080, 4085)  an unknown label         NOT this reader's check
//!   REJECT(4080)       too many positionals     NOT this reader's check
//!   REJECT(0011)       a refutable pattern      NOT this reader's check
//|
//| The four refusals are TYPE questions and the parser is type-blind. Refusing them here would
//| mean refusing the corpus on a check this reader is not equipped to make.
//|
//| => NO NEW NODE. `SLetDestruct(Array[String], Expr)` is already the node for a `let` that
//| binds several names at once -- it is what `let (a, b) = pair` produces, and walk, infer
//| and interp already bind every name in it. `names.length()` is therefore the instrument in
//| every row below: a reader that bound nothing, or bound the head, would give the wrong
//| count and these rows would say so.
//|
//| A NOTE ON NAVIGATION, because it cost this file its first run and it will cost the next
//| one too. A function body is wrapped in `SBlock` ONLY when it is a single statement.
//| `parser_0476_test.mbt` navigates `body[0].kind` -> `SBlock(stmts)` because its fixture is
//| one `for` loop; `parser_0432_test.mbt` navigates `body[0].kind` -> `SLet` directly because
//| its fixture is two statements. Both are right. Every fixture below has two or three
//| statements and goes direct -- and the first version of this file navigated through
//| `SBlock` on that assumption, so all FIVE tests failed, controls included. Five failures
//| including the controls is the signature of a wrong NAVIGATION rather than a wrong reader,
//| and the corpus scan had already measured the reader working.

///|
/// THE CORPUS SHAPE, verbatim from `error.mbt:79`. Two names, one positional and one labeled,
/// and the LABEL is the one the settle's S2 row exists for: `context` is read on the next line
/// of the real file, so a reader that matched the label without binding it would leave the file
/// reporting `undefined name 'context'` against code `moon check` compiles.
test "0477: a labeled constructor pattern binds both names" {
  let r = @parser.parse(
    "///|\nfn f(self : OSError) -> String {\n  let OSError(errno, context~) = self\n  ignore(errno)\n  context\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLetDestruct(names, init) => {
          assert_eq(names.length(), 2)
          assert_eq(names[0], "errno")
          assert_eq(names[1], "context")
          // The initialiser must be the WHOLE RIGHT-HAND SIDE, read once. A reader
          // that consumed the pattern but then re-read from the head would give an
          // ECall here, and the node would look superficially right.
          match init.kind {
            @ast.EName(n) => assert_eq(n, "self")
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE REST PATTERN, `error.mbt:95`. The settle's S4 row established that nothing may follow
/// `..`, and this row pins the half of that which IS the reader's: the names BEFORE it bind and
/// the `..` itself binds nothing. A reader that treated `..` as a binding would report a third
/// name, and one that stopped AT the `..` would leave the `)` in the stream and the file would
/// not parse at all -- which `first_error` above is what would catch.
test "0477: `..` absorbs the rest and binds nothing itself" {
  let r = @parser.parse(
    "///|\nfn f(err : OSError) -> Int {\n  let OSError(errno, ..) = err\n  errno\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLetDestruct(names, _) => {
          assert_eq(names.length(), 1)
          assert_eq(names[0], "errno")
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// A NESTED CONSTRUCTOR, the settle's S7 row. `Wrap` binds nothing and `One` binds nothing;
/// only the name at the bottom is a binding. This is the row that would fail on a reader that
/// read the payload with a single depth instead of counting parens, which is the bug the
/// `parse_is_pattern` payload loop's own history records.
test "0477: a nested constructor binds only the innermost name" {
  let r = @parser.parse(
    "///|\nfn f(s : Shape) -> Int {\n  let Wrap(One(inner)) = s\n  inner\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLetDestruct(names, _) => {
          assert_eq(names.length(), 1)
          assert_eq(names[0], "inner")
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// CONTROLS, and they are controls rather than decoration. Without the first, the three rows
/// above would pass on a reader that turned EVERY `let` into an `SLetDestruct` -- a plain
/// binding has one name, which is what `SLet` is for, and walk/infer read the type annotation
/// off it. Without the second, the new branch could be stealing the tuple path: `(` and
/// `Name(` are mutually exclusive, but a branch placed before the tuple branch rather than
/// after it would still have to be shown not to take `let (a, b)`.
test "0477 control: a plain binding is still SLet, not SLetDestruct" {
  let r = @parser.parse(
    "///|\nfn f(a : Int) -> Int {\n  let b : Int = a + 1\n  b\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(name, ann, _) => {
          assert_eq(name, "b")
          assert_eq(ann, "Int")
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "0477 control: a tuple pattern still goes through the tuple branch" {
  let r = @parser.parse(
    "///|\nfn f(p : (Int, Int)) -> Int {\n  let (a, b) = p\n  a + b\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLetDestruct(names, _) => {
          assert_eq(names.length(), 2)
          assert_eq(names[0], "a")
          assert_eq(names[1], "b")
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

//| Tests for 0640 -- the TYPE ANNOTATION on the left of a `let` whose pattern
//| binds SEVERAL names.
//|
//| WHY. `riantr/pyroduct` 0.1.5 writes this at `evolution/gate.mbt:113`:
//|
//|     let (objective, causal) : (Objective, CausalPlan?) = match criterion {
//|       Weighted(o) => (o, None)
//|       Causal(p) => (p.objective, Some(p))
//|     }
//|
//| and the analyzer could not read the file. It reported `expected '='` and
//| STOPPED at line 113, so the whole of that file was unreadable -- and an
//| unreadable file is not a finding, it is a silence. Under this analyzer that
//| ONE line was the whole of pyroduct's unreadable-file count.
//|
//| THE DEFECT WAS AN ENTRY POINT, NOT A RULE. The plain binding path has read
//| an annotation since long before this: `let b : Int = a + 1` gives
//| `SLet("b", "Int", ..)`. The three PATTERN paths -- the tuple, the struct and
//| the constructor -- went straight from the pattern to `expect(TAssign)`,
//| with no room for a `:` between them. So the rule "a `let` may carry a type
//| annotation" was already in the parser and simply was not reached from the
//| three pattern paths.
//|
//| SETTLED, `_verify/settle_0640_let_pattern_annotation.ps1`, 3 rows + 3
//| controls, GATE OK, against `moon check` 0.1.20261117:
//|
//!   ACCEPT    let (a, b) : (Int, Int) = p       the tuple
//!   ACCEPT    let C(r) : Shape = s              the constructor
//!   ACCEPT    let { x, .. } : Point = p         the struct
//!   ACCEPT    let b : Int = a + 1              the plain binding (unchanged)
//!   REJECT(0011)  a refutable pattern          NOT this reader's check
//!   REJECT(4080)  a labelled constructor       NOT this reader's check
//!
//| The two refusals are TYPE questions and the parser is type-blind, for the
//! reason 0477 settled.
//!
//| => NO NEW NODE, AND NO NEW AST FIELD. `SLetDestruct(Array[String], Expr)` is
//| public (`src/ast/pkg.generated.mbti`), and a `pub` enum gaining a field
//| breaks every consumer that constructs it. The annotation has no consumer
//| here to break -- the subset has no tuple types to per-element it -- so it
//| is not given one. It is READ (which is what finds the `=` and makes the
//| file readable) and then DROPPED, and a skip is recorded so that a reader of
//| the report cannot come away believing it was checked.
//|
//| A NOTE ON NAVIGATION, because it cost 0477's file its first run and it will
//| cost this one too. A function body is wrapped in `SBlock` ONLY when it is a
//| single statement. Every fixture below has two or more statements and goes
//| direct -- `body[0].kind` -> `SLetDestruct`.

///|
/// THE CORPUS SHAPE, verbatim from `gate.mbt:113`. This is the row that was
/// worth the increment: the file is 62 lines long and everything below line
/// 113 -- the score, the constitutional check, the backdating branch -- was
/// invisible to the analyzer. The instrument is `first_error`, and it is 0
/// only when the annotation was read AND the `=` was found.
test "0640: an annotated tuple pattern parses, and the file below it is read" {
  let r = @parser.parse(
    "///|\nfn judge(c : Criterion) -> Int {\n  let (objective, causal) : (Int, Int?) = match c {\n    Weighted(o) => (o, None)\n    Causal(p) => (p, None)\n  }\n  objective\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLetDestruct(names, _) => {
          assert_eq(names.length(), 2)
          assert_eq(names[0], "objective")
          assert_eq(names[1], "causal")
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
  // THE STATEMENT BELOW THE ANNOTATED LET IS STILL READ. A reader that stopped
  // at the `:` would leave the `=` in the token stream, and the body would
  // then carry a parse error instead of the binding that follows -- so the
  // body must have MORE than the one statement.
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => assert_true(body.length() >= 2)
    _ => assert_true(false)
  }
}

///|
/// THE TUPLE, without the `match`. The annotation is a TUPLE TYPE here, and
/// `type_annotation()` reads one: the `(` reaches the function-type reader,
/// whose body makes the `-> R` optional. A reader that insisted on the `->`
/// would report "expected ')'" and end the file, which is a DIFFERENT failure
/// from the one this increment fixes, and this row is what separates them.
test "0640: an annotated tuple pattern reads a tuple type" {
  let r = @parser.parse(
    "///|\nfn f(p : (Int, Int)) -> Int {\n  let (a, b) : (Int, Int) = p\n  a + b\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 1)
  assert_eq(r.skips.length(), 1)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLetDestruct(names, init) => {
          assert_eq(names.length(), 2)
          assert_eq(names[0], "a")
          assert_eq(names[1], "b")
          // The initialiser is the WHOLE RIGHT-HAND SIDE, read once. A reader
          // that consumed the pattern and then re-read from the head would give
          // an ECall here, and the node would look superficially right.
          match init.kind {
            @ast.EName(n) => assert_eq(n, "p")
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE CONSTRUCTOR PATTERN, `let C(r) : Shape = s`. This path was 0477's, and
/// it goes through `parse_is_pattern` rather than the tuple reader -- so it is
/// a SEPARATE call site, and a fix that touched only the tuple path would
/// leave this one reporting `expected '='`.
test "0640: an annotated constructor pattern parses" {
  let r = @parser.parse(
    "///|\nfn f(s : Shape) -> Int {\n  let Circle(r) : Shape = s\n  r\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.skips.length(), 1)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLetDestruct(names, _) => {
          assert_eq(names.length(), 1)
          assert_eq(names[0], "r")
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE STRUCT PATTERN, `let { x, .. } : Point = p`. The THIRD call site, and
/// the one a two-site fix would miss. `parse_is_pattern` reads the names, and
/// `..` binds nothing -- so the count stays at one.
test "0640: an annotated struct pattern parses" {
  let r = @parser.parse(
    "///|\nfn f(p : Point) -> Int {\n  let { x, .. } : Point = p\n  x\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.skips.length(), 1)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLetDestruct(names, _) => {
          assert_eq(names.length(), 1)
          assert_eq(names[0], "x")
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// CONTROL: an UNANNOTATED pattern records NO skip. This is the row that kills
/// a reader that notes a skip for every `let` pattern it sees -- which would
/// have turned every destructuring `let` in every corpus into a notice, and
/// the notice count is a pinned number.
test "0640 control: an unannotated pattern records no skip" {
  let r = @parser.parse(
    "///|\nfn f(p : (Int, Int)) -> Int {\n  let (a, b) = p\n  a + b\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  assert_eq(r.skips.length(), 0)
}

///|
/// CONTROL: the plain binding still reads its annotation and is still `SLet`.
/// Without this, a branch placed BEFORE the plain path would swallow it, and
/// the type lens would lose every `SLet` annotation in every corpus -- a
/// quiet loss, because the name would still bind.
test "0640 control: a plain binding is still SLet, with its annotation" {
  let r = @parser.parse(
    "///|\nfn f(a : Int) -> Int {\n  let b : Int = a + 1\n  b\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  assert_eq(r.skips.length(), 0)
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
/// THE SKIP IS A NOTICE, AND IT IS THE ONE THE PARSER REALLY EMITS. The
/// message is not spelled out here: a test that compares a literal with a
/// literal proves only that a literal agrees with a literal. The predicate is
/// asked about the report the parser really built, and the skip list and the
/// notice predicate have to agree -- which is 0500's invariant, read here
/// through the shape this increment introduced.
test "0640: the annotation exclusion is a notice, and the skip list agrees" {
  let r = @parser.parse(
    "///|\nfn f(p : (Int, Int)) -> Int {\n  let (a, b) : (Int, Int) = p\n  a + b\n}\n",
  )
  assert_eq(r.first_error, 0)
  let fps = fparse_reports(r.reports)
  assert_eq(fps.length(), 1)
  for rep in fps {
    assert_true(rep.is_notice())
    assert_eq(rep.severity_label(), "notice")
    assert_true(rep.render().contains(" - notice: "))
    assert_false(rep.render().contains(" - error: "))
    // AND THE CLAIM THE MESSAGE MAKES IS TRUE: it says the annotation was READ
    // and NOT analysed. Read is `first_error == 0` -- a file that failed to
    // parse would have moved it -- and the annotation is not analysed because
    // the subset has no tuple types to per-element it.
    assert_true(rep.message.contains("type annotation"))
  }
  for rep in fparse_reports(r.reports) {
    assert_eq(r.skips.contains(rep.message), rep.is_notice())
  }
}

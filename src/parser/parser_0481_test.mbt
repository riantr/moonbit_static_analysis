///|
/// 0481 -- a NESTED optional type. `String??` is `Option[Option[String]]`, and the reader
/// consumed ONE `?` and left the second in the stream, so the function reader met a `?` where
/// it wanted a body and the report landed on a `:` eight tokens EARLIER. proton
/// `internal/native/types.mbt:1351` is the site, and after 0480 it was that corpus's only
/// unreadable file.
///
/// Settled before implementing (`_verify/settle_0481_nested_optional_type.ps1`, 3 controls +
/// 6 rows, GATE OK):
///
///   ACCEPT  `-> String?` / `-> String??` / `(x : String??)` / `let x : String??`
///   ACCEPT  `-> String???`   the nesting is UNBOUNDED, which is why this is a LOOP
///   ACCEPT  `self : String`  labelled parameters, so the reported `:` was a red herring
///
/// The assertions are on the RENDERED ANNOTATION rather than on the parse succeeding. A type
/// annotation is carried as a string and folded into the name, so `String??` has to come back
/// as `String??`: a reader that consumed both `?` and discarded one would parse the same line
/// perfectly, report nothing, and carry a claim about the program that is false.
test "0481: a doubly-optional return type reads whole" {
  let r = @parser.parse("///|\nfn f() -> String?? {\n  Some(None)\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, retann, _, _) => assert_eq(retann, "String??")
    _ => assert_true(false)
  }
}

///|
/// THE UNBOUNDED ROW, and it is what makes this a LOOP rather than two bumps. A fix that
/// handled exactly the corpus's shape -- consume a second `?` -- would pass the row above and
/// every corpus file, and would refuse `-> String???` for no reason the toolchain shares.
/// The settle says ACCEPT, so the reader has to keep going while the `?` keeps coming.
test "0481: nesting is not capped at two (control)" {
  let r = @parser.parse("///|\nfn f() -> String??? {\n  Some(Some(None))\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, retann, _, _) => assert_eq(retann, "String???")
    _ => assert_true(false)
  }
}

///|
/// THE UNNESTED CASE. `String?` must still render as `String?` and no longer: a loop that ran
/// past the end of the type would not change this row, and a reader that gave up on the first
/// `?` would not change it either. Only having it here shows the loop STOPS where the type
/// stops -- which is the half of a loop nobody tests.
test "0481: a singly-optional return type is unchanged (control)" {
  let r = @parser.parse("///|\nfn f() -> String? {\n  Some(\"\")\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, retann, _, _) => assert_eq(retann, "String?")
    _ => assert_true(false)
  }
}

///|
/// A PARAMETER, not a return. `type_annotation` is reached from a `let` annotation, a
/// parameter list, a return type and a nested position inside a function type, and a rule that
/// held only after `->` would be a rule a quarter of the grammar does not have. The corpus line
/// is a return, so nothing in the corpus would ever ask this question.
test "0481: a doubly-optional parameter reads whole" {
  let r = @parser.parse("///|\nfn g(x : String??) -> Unit {\n  ignore(x)\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, params, _, _, _) => assert_eq(params[0].tyann, "String??")
    _ => assert_true(false)
  }
}

///|
/// AND THE THIRD SITE, with no `->` and no parentheses at all: a `let` annotation inside a
/// body. All the rows above would pass a reader that only taught the RETURN-type path, which
/// is the shape of most of the narrowing fixes this project has already made and reversed.
test "0481: a doubly-optional let annotation reads whole" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  let x : String?? = Some(None)\n  ignore(x)\n}\n",
  )
  assert_eq(r.reports.length(), 0)
}

///|
/// A PLAIN TYPE STAYS PLAIN, which is the control for the loop from the other side. `Int` with
/// nothing after it must render as `Int`; a reader that appended a `?` unconditionally, or one
/// that carried a `?` left over from a previous annotation, would render `Int?` here and every
/// type in the program would be quietly wrong while every parse still succeeded.
test "0481: a plain parameter type does not gain a question mark (control)" {
  let r = @parser.parse("///|\nfn h(x : Int) -> Unit {\n  ignore(x)\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, params, _, _, _) => assert_eq(params[0].tyann, "Int")
    _ => assert_true(false)
  }
}

///|
/// A method chain that CONTINUES on the next line.
///
/// Settled with the toolchain: `_verify/grammar_probe.ps1` case
/// `chain_dot_next_line` is 0 errors from `moon check`, with
/// `chain_dot_same_line_control` beside it. Before the fix this frontend
/// dropped the chain SILENTLY in a `let` -- the receiver was kept and `.length()`
/// discarded -- and died on the call's own `)` in ARGUMENT position.
///
/// moui 0.1.12 writes the argument form in 17 of its 86 unreadable files:
///
///   rows.push(
///     @button.button(...)
///     .disabled(disabled=!item.enabled)
///     .semantics_selected(...),
///   )
///
/// The test that matters here is the one that asserts the CHAIN WAS APPLIED,
/// not merely that the file parsed. A silent drop parses clean, so
/// `first_error == 0` alone would pass on the broken behaviour.
test "0432: a chain continuing on the next line keeps the REAL receiver" {
  let r = @parser.parse(
    "fn f(a : Array[Int]) -> Int {\n  let v = a\n    .length()\n  v\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  // v must be the `.length()` result, not the receiver.
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(name, _, init) => {
          assert_eq(name, "v")
          // EMethodCall is what a `.name(args)` produces. EName would mean the
          // chain was dropped and `v` holds the bare receiver.
          match init.kind {
            @ast.EMethodCall(base, meth, _, _) => {
              assert_eq(meth, "length")
              match base.kind {
                @ast.EName(_) => ()
                _ => assert_true(false)
              }
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
/// The same chain in ARGUMENT position, which is the shape that blocked files.
/// The `.disabled`-style member in the argument test keeps the trailing comma,
/// so the argument loop has to resume after the chain rather than break at the
/// newline.
test "0432: a chain continuing on the next line inside a call argument" {
  let r = @parser.parse(
    "fn wrap(x : Array[Int]) -> Array[Int] { x }\nfn take(n : Int) -> Int { n }\nfn f(a : Array[Int]) -> Int {\n  take(\n    wrap(a)\n      .length(),\n  )\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// CONTROL -- the same source with the chain on one line. If this went red the
/// two-line failures would have been about something else entirely.
test "0432 control: the same chain on one line was always read" {
  let r = @parser.parse(
    "fn wrap(x : Array[Int]) -> Array[Int] { x }\nfn take(n : Int) -> Int { n }\nfn f(a : Array[Int]) -> Int {\n  take(wrap(a).length())\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// CONTROL -- a plain newline that is NOT a chain continuation must still END
/// the expression. This is the whole cost of the fix: the separators are
/// consumed speculatively and rewound, and without the rewind the next
/// statement would be fused into this one.
test "0432 control: a newline that does not continue the chain still ends it" {
  let r = @parser.parse("fn f(a : Int) -> Int {\n  let v = a\n  v + 1\n}\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  // Two statements, not one expression folded together.
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}

///|
/// A suberror's variants are CONSTRUCTORS, and `raise Variant(...)` builds
/// one. Until 0.4.30 only `enum` bodies were harvested, so every `raise` of a
/// variant declared in the SAME FILE was reported:
///
///   no visible binding for 'InvalidPathOverride'   x5
///   no visible binding for 'InvalidIdentifier'
///   no visible binding for 'MissingEnvironmentPath'
///   undefined name 'MissingExecutablePath'
///
/// measured on moonbit-community/proton 0.3.4 `facade_paths.mbt`, whose
/// suberror `AppPathError` is declared in that same file -- so this was never a
/// cross-file resolution problem, only a missing harvest.
///
/// Settled with the toolchain: `pub suberror AppPathError { ... }` followed by
/// `raise AppPathError::Variant(...)`-shaped use is ordinary MoonBit, and the
/// existing `enum` harvest is the same scan applied to the same body shape.
test "0432: a suberror variant is a constructor, not an undefined name" {
  let r = @parser.parse(
    "suberror AppPathError {\n  InvalidPathOverride(kind : String)\n  MissingExecutablePath\n}\nfn f() -> String raise AppPathError {\n  raise InvalidPathOverride(\"x\")\n}\n",
  )
  assert_eq(r.first_error, 0)
  // The variant head must be harvested as a module-level VALUE.
  assert_true(r.enum_ctors.contains("InvalidPathOverride"))
  assert_true(r.enum_ctors.contains("MissingExecutablePath"))
  // And the payload PARAMETER is not mistaken for a variant: it is nested one
  // level deep inside the parentheses.
  assert_false(r.enum_ctors.contains("kind"))
}

///|
/// CONTROL -- an `enum` body was already harvested. If this went red, the
/// `enum` arm had regressed and the suberror fix would be blamed for it.
test "0432 control: an enum variant is still harvested" {
  let r = @parser.parse("enum Shape {\n  Circle(radius : Int)\n  Square\n}\n")
  assert_true(r.enum_ctors.contains("Circle"))
  assert_true(r.enum_ctors.contains("Square"))
  assert_false(r.enum_ctors.contains("radius"))
}

///|
/// A KNOWN LIMITATION, pinned so it cannot be rediscovered as a new bug.
///     @native.system_path(kind) catch {
///       error => raise SystemPath(kind=label, ...)
///     }
///   }
///
///   fn resolve(kind : Int, label : String) -> String raise AppPathError {
///     @native.system_path(kind) catch {
///       error => raise SystemPath(kind=label, ...)
///     }
///   }
///
/// `label` IS read, inside the `catch` block, and this frontend reports
/// `parameter 'label' may not be used`: the postfix `catch` arm consumes the
/// block with `skip_braces`, so the read is invisible. proton 0.3.4
/// `facade_paths.mbt:473` is the measured instance, newly visible because the
/// chain fix above made that file readable for the first time.
///
/// It is pinned as DOCUMENTED rather than suppressed. Suppressing it would mean
/// treating every function containing a `catch` as if all its parameters were
/// read, which trades one false positive for an unbounded number of missed true
/// ones. That is the worse failure, and the honest record of it is this note.
///
/// FIXED IN 0439, so the note above is now history. The postfix `catch` arm
/// parses its handler instead of skipping it, so `label` is read and the false
/// positive is gone — without the blanket suppression this note rejected. What
/// is asserted below is therefore no longer the interesting half: it pins only
/// that the shape still parses, which it also did before the fix and which is
/// why this test alone could never have caught the defect. The finding-level
/// assertion is `pipeline_0439_test.mbt`, and the tree-level one is
/// `parser_0439_test.mbt`.
test "0432 the `catch`-arm shape still parses (read assertion: pipeline_0439)" {
  let r = @parser.parse(
    "fn resolve(kind : Int, label : String) -> String {\n  call(kind) catch {\n    error => label\n  }\n}\n",
  )
  // Parses clean -- the chain fix did not cause this, and the parse is fine.
  assert_eq(r.first_error, 0)
}

///|
/// The STATEMENT-level shape of the same chain, pinned because gate 0418's M10
/// is declared unobservable on the strength of it.
///
/// `parse_stmt` has its own leading-dot continuation (the block at its
/// `if self.at(TDot)`), which used to be the only thing that read a chain
/// starting on the next line. The 0432 block in `parse_postfix_from` now
/// performs that work during the expression parse, so the statement-level block
/// is never reached for this shape -- verified by applying M10 and re-running
/// exactly these two parses, both still clean. That is what the M10 `Prove`
/// says, and this is the evidence for it.
///
/// These two are the ONLY places M10's argument is used, so if they ever go red
/// the claim needs re-measuring rather than re-asserting.
test "0432: a leading-dot chain in STATEMENT position still parses" {
  let r = @parser.parse(
    "fn g(x : Array[Int]) -> Int { x.length() }\nfn f(a : Array[Int]) -> Int {\n  g(a)\n    .to_string()\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// CONTROL for the one above: the same statement with a value-bearing chain, so
/// the two differ in what the chain RETURNS rather than only in spelling.
test "0432 control: a leading-dot chain after a plain receiver still parses" {
  let r = @parser.parse(
    "fn f(a : Array[Int]) -> Int {\n  let v = a\n    .length()\n  v\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

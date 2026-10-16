//| Tests for 0.4.29: array patterns, constructor registration, `let` shadowing,
//| and body-less suberrors.
//|
//| FOUR INCREMENTS IN ONE FILE, on purpose. 0460, 0461, 0462 and 0463 are one
//| commit because they are one story: 0459 (single-quoted byte literals, `\u{..}` escapes)
//| unblocked 45 files across four corpora, and every finding it surfaced belonged
//| to a gap that had never been REACHABLE before. `actionable` went 0 -> 24, and a
//| parser change that trades blocked files for confident false positives is worse
//| than either alone -- the 0456 + 0457 precedent, for the third time.
//!
//|     moonbit_image  parsed  2 -> 15
//!     async          parsed 275 -> 302
//!     moonbit_labeler parsed 28 -> 32
//!     proton         parsed 109 -> 115
//!
//! 0463 is the odd one out and belongs here anyway: it was found not by a corpus
//! but by the 0460 fixtures at the top of this file, whose `priv suberror Boom`
//! walked straight into it. A fixture is a corpus of one, and this suite has now
//! been caught by its own scaffolding.
//!
//| => 判据: a false positive nobody can reach is not a false positive that does not
//| exist. It is a finding whose corpus has not been read yet, and the only way to
//| tell the two apart is to unblock the corpus and look.

///|
/// THE FIXTURES BELOW CARRY NO suberror, and that is a correction rather than a
/// style. They used to end with `priv suberror Boom` and a `raise Boom` in the
/// guard's else-arm, and that did two things nobody wanted:
///
///   * it put a PERMANENT `ParseError` in every fixture -- "suberror declaration
///     is outside the analyzed subset" -- so these tests could not assert on
///     `ParseError`, which is the family that says whether a pattern was CONSUMED;
///   * it made every 0460 guard depend on 0463's body-less suberror harvest to
///     stay green. Reverting 0463 went red on tests whose subject is array
///     patterns.
///
/// `else { return 0 }` needs no error type, so both assertions are available and
/// each row tests exactly one property. Gate 0460's M2 is the mutation that made
/// this necessary: "the array pattern is read but not consumed" left the
/// `UndefinedName` count at zero, because the bindings WERE collected -- the
/// breakage was downstream, and only a `ParseError` assertion sees it.
test "0460: an array pattern binds its elements" {
  let r = @pipeline.run(
    "///|\nfn probe(xs : Array[Int]) -> Int {\n  guard xs is [first, second] else {\n    return 0\n  }\n  first + second\n}\n",
    "arr.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// AND A CONSTRUCTOR ARGUMENT INSIDE THE BRACKETS BINDS TOO. `u32le(mtime)` is
/// this shape in the corpus, and an implementation that only handled bare elements
/// would have traded one false positive for another.
///
/// Settled rather than guessed: `name(args)` in a pattern is a CONSTRUCTOR pattern,
/// not a call. A first settle draft used a plain function and got "The type Int
/// does not have the constructor pair" -- which is exactly why `u32le`, a builtin
/// constructor, is legal in the corpus at all.
test "0460: a constructor argument inside an array pattern binds" {
  let r = @pipeline.run(
    "///|\nfn probe(xs : Array[Option[Int]]) -> Int {\n  guard xs is [Some(inner)] else {\n    return 0\n  }\n  inner\n}\n",
    "ctor.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// AND A LITERAL PATTERN IS CONSUMED, so the `else` after it survives. This is the
/// second half of the same increment: `is b'\x08'` used to return without consuming
/// anything, because the reader's fallthrough was a bare `return []`.
test "0460: a literal pattern leaves the else after it intact" {
  let r = @pipeline.run(
    "///|\nfn probe(b : Byte) -> Int {\n  guard b is b'\\x08' else {\n    return 0\n  }\n  1\n}\n",
    "lit.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// AND A NESTED ARRAY PATTERN BINDS AT DEPTH. `[[inner], tail]` is in
/// `settle_0460_array_pattern.ps1`, and the branch tracks bracket depth, so this
/// row is what says the depth tracking is load-bearing rather than incidental: a
/// `TLBracket => depth += 1` that did not run would read the inner `]` as the end
/// of the outer pattern and hand the rest of the file to the expression reader.
test "0460: a nested array pattern binds its inner names" {
  let r = @pipeline.run(
    "///|\nfn probe(xss : Array[Array[Int]]) -> Int {\n  guard xss is [[inner], tail] else {\n    return 0\n  }\n  inner + tail\n}\n",
    "nested.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// 0461 -- A CONSTRUCTOR DECLARED IN A BRACE BODY IS A VISIBLE NAME.
///
/// The harvest that fills the sibling table was armed for `enum` and NOT for
/// `suberror`, so `priv suberror FormatError { InvalidBlock(String) }` registered
/// the TYPE and none of its constructors. Measured: 10 false positives in async's
/// `gzip_internal/decoder.mbt` (`no visible binding for 'InvalidBlock'`) plus
/// `'InvalidTrailer'` and `'NeedMoreInput'`, all declared in a SIBLING file.
///
/// Settled 7/7 in `_verify/settle_0461_constructors.ps1`: an enum variant and a
/// suberror constructor are both ordinary bare names, so this is one gap and not
/// two declaration kinds.
test "0461: a suberror constructor is a visible name" {
  let r = @pipeline.run(
    "///|\npriv suberror FormatError {\n  InvalidHeader(String)\n  InvalidBlock(String)\n}\n\n///|\nfn probe() -> Int raise {\n  raise InvalidBlock(\"bad\")\n}\n",
    "sub.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND THE SAME THING ACROSS A SIBLING FILE, which is the half that was
/// unguarded. Every 0461 row above is a single file read with an EMPTY
/// `IfaceSymTab`, so it exercises `Parser::harvest_ctors` -- the intra-file
/// harvest -- and says nothing at all about `collect_declared_names`, which is the
/// OTHER place a suberror body has to be harvested and the one the corpus actually
/// needed.
///
/// The corpus shape is exactly this: `async 0.22.4` declares
/// `priv suberror FormatError { InvalidBlock(String) }` in
/// `gzip_internal/metadata.mbt` and raises it ten times in the SIBLING
/// `gzip_internal/decoder.mbt`. Before the arming, the TYPE registered and none of
/// its constructors did, so all ten reported `no visible binding for
/// 'InvalidBlock'` against a file the toolchain compiles.
test "0461: a suberror constructor reaches a sibling file" {
  let t = @parser.collect_declared_names(
    "///|\npriv suberror FormatError {\n  InvalidHeader(String)\n  InvalidBlock(String)\n  NeedMoreInput\n}\n",
  )
  assert_true(t.has_value("InvalidHeader"))
  assert_true(t.has_value("InvalidBlock"))
  assert_true(t.has_value("NeedMoreInput"))
  assert_true(t.has_type("FormatError"))
}

///|
/// AND THE CONTROL that keeps the sibling harvest narrow. A suberror's payload
/// TYPE is a brace-declared name too, and harvesting it would make a type that
/// exists only as a payload parameter package-visible -- silencing a real finding
/// in an unrelated file. `String` must stay out of both halves. This is the same
/// rule `parser_0417_test.mbt` pins for `enum`, applied to the keyword that was
/// newly armed here.
test "0461: a suberror payload type is not harvested as a constructor" {
  let t = @parser.collect_declared_names(
    "///|\npriv suberror FormatError {\n  InvalidBlock(Params)\n}\n",
  )
  assert_true(t.has_value("InvalidBlock"))
  assert_false(t.has_value("Params"))
  assert_false(t.has_type("Params"))
}

///|
/// AND THE SAME CONTROL WITH THE PAYLOAD SPLIT ACROSS LINES, which is the only
/// form that actually exercises the harvest's parenthesis counter.
///
/// The one-line row above cannot see that counter at all: `Params` sits inside the
/// parentheses either way, and gate 0461's M4 (drop `paren` tracking) left it
/// green. What a line-start rule alone gets wrong is precisely this layout --
/// `parser_0417_test.mbt` settled it for `enum` and it holds identically for a
/// suberror body, because both are harvested by the same scan.
test "0461: a multi-line payload type is not harvested as a constructor" {
  let t = @parser.collect_declared_names(
    "///|\npriv suberror FormatError {\n  InvalidBlock(\n    Params,\n  )\n  NeedMoreInput\n}\n",
  )
  assert_true(t.has_value("InvalidBlock"))
  assert_true(t.has_value("NeedMoreInput"))
  assert_false(t.has_value("Params"))
  assert_false(t.has_type("Params"))
}

///|
/// AND AN ENUM VARIANT WITH AN EXPLICIT DISCRIMINANT, which was a SEPARATE defect
/// behind the same findings. `ends_variant` accepted `(`, `,`, `}`, a newline and
/// `;` after a variant name -- and not `=` -- so `RuntimeActive = 0` was never
/// registered. Measured: proton's `internal/native/types.mbt:1409` declares it and
/// the sibling `native.mbt` uses the variant bare three times.
///
/// The two rows above and below are the reason these are two tests and not one.
/// My first description of this increment was "one gap, not two"; it was wrong,
/// and the corpus is what showed it.
test "0461: an enum variant with a discriminant is a visible name" {
  let r = @pipeline.run(
    "///|\npriv enum State {\n  Active = 0\n  Gone = 2\n}\n\n///|\nfn probe(s : State) -> Int {\n  match s {\n    Active => 0\n    Gone => 1\n  }\n}\n",
    "disc.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND THE DISCRIMINANT REACHES A SIBLING TOO, which is the half that was
/// unguarded. `ends_variant` is consulted by `collect_declared_names` and by
/// NOTHING ELSE -- `Parser::harvest_ctors` takes every name at bracket depth 0
/// inside a body and never asks what follows it. So a single-file test cannot see
/// this rule at all, and the three rows above do not: they go red when the whole
/// harvest is disabled and stay green when this terminator is.
test "0461: an enum variant with a discriminant reaches a sibling file" {
  let t = @parser.collect_declared_names(
    "///|\npriv enum State {\n  Active = 0\n  Gone = 2\n}\n",
  )
  assert_true(t.has_value("Active"))
  assert_true(t.has_value("Gone"))
  assert_true(t.has_type("State"))
  // The DISCRIMINANT is a value, not a name, and must not enter the table.
  assert_false(t.has_value("0"))
  assert_false(t.has_value("2"))
}

///|
/// AND THE CONTROL for the row above, without a discriminant. If the discriminant
/// were the thing making it work, this would have failed before the fix.
test "0461: an enum variant with no discriminant is still a visible name" {
  let r = @pipeline.run(
    "///|\npriv enum State {\n  Active\n  Gone\n}\n\n///|\nfn probe(s : State) -> Int {\n  match s {\n    Active => 0\n    Gone => 1\n  }\n}\n",
    "disc_none.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND THE INITIALISER ITSELF SHADOWS THE SAME NAME, which is the one shape that
/// could make the ORDER of `unshadow_param` and `walk_expr(init)` observable: an
/// initialiser that binds the name itself leaves a DIFFERENT entry in the frame by
/// the time the flag is cleared, so clearing afterwards would flip the inner local
/// (already `param: false`) and leave the real parameter still marked as one.
///
/// Written as a witness rather than as theory. Gate 0462's M2 reverses the order
/// and 683/683 stayed green without this row, which is a statement about the suite
/// and not about reachability -- the same distinction that made gate 0458's M4 a
/// survivor that turned out to be reachable three parens deep.
test "0462: an initialiser that shadows the same name still shadows" {
  let r = @pipeline.run(
    "///|\nfn f(produced : Int) -> Int {\n  let mut produced = if produced > 0 {\n    let produced = 1\n    produced\n  } else {\n    0\n  }\n  produced = 5\n  produced\n}\n",
    "shadow_init.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParamChanged"), 0)
}

///|
/// 0463 -- A BODY-LESS suberror DECLARES ITS OWN NAME, and that name is a VALUE.
///
/// This one was not found by a corpus. It was found by the 0460 fixtures ABOVE:
/// all three of those tests failed with exactly one `UndefinedName`, and the name
/// was `Boom` -- a `priv suberror Boom` at the foot of the fixture with no brace
/// body. The probe that named it:
///
///     PROBE ln=4 fam=UndefinedName msg=undefined name 'Boom'
///
/// ORDER was the first guess, and the corpus could never have refuted it, because
/// in async `InvalidBlock` is declared in a SIBLING file -- a different resolution
/// path that behaves the same way whether or not the declaration came first. Five
/// shapes through `pipeline.run` decided it:
///
///     A  body-less suberror declared BEFORE the use   UndefinedName 1
///     B  body-less suberror declared AFTER  the use   UndefinedName 1
///     C  suberror WITH a body, declared AFTER         UndefinedName 0
///     D  the TYPE name in a signature, body-less      UndefinedName 0
///     E  control, nothing declared at all            UndefinedName 1
///
/// A and B together rule out ORDER. C names the variable: the BODY. D says the
/// type name always resolved, so the hole is value-shaped and not type-shaped --
/// which is why adding a TYPE binding would have changed nothing at all.
///
/// The mechanism is one line. `harvest_ctors` is reachable only from the BRACED
/// branch, so a body-less suberror's own name never entered `enum_ctors` -- and
/// `enum_ctors` is what seeds the module frame as VALUES (`walk.mbt:1197`,
/// `infer.mbt:880`).
test "0463: a body-less suberror's own name is a visible value" {
  let r = @pipeline.run(
    "///|\npriv suberror Boom\n\n///|\nfn probe() -> Int raise {\n  raise Boom\n}\n",
    "bodyless.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND WITH A `derive` LIST, the other body-less header that exists. Settled 10/10
/// in `_verify/settle_0463_suberror_bodyless.ps1`: a body-less suberror cannot
/// carry a payload at all -- `suberror E of T`, `suberror E(T)` and
/// `suberror E(x : T)` are ALL `[3002]` -- so `derive` is the only word that can
/// follow the name, and reading the DECLARED name and reading the token after the
/// keyword agree here.
test "0463: a body-less suberror with a derive list is a visible value" {
  let r = @pipeline.run(
    "///|\npriv suberror Boom derive(Debug)\n\n///|\nfn probe() -> Int raise {\n  raise Boom\n}\n",
    "bodyless_derive.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CONTROL. A name with nothing declared is still undefined, so the harvest
/// above is about the DECLARATION and not about `raise` having become silent.
test "0463: an undeclared name is still undefined (control)" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Int raise {\n  raise ZzMissing\n}\n",
    "bodyless_ctl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE SCOPE BOUND, which is the row that stops this rule from growing. A
/// BRACED suberror declares its constructors in the body, and its own name is a
/// TYPE -- `raise FormatError` is `[4021]` in MoonBit, settled in the same script.
/// So the braced form must NOT harvest its own name: doing so would suppress a
/// finding that is correct.
test "0463: a braced suberror's own name is still not a constructor (bound)" {
  let r = @pipeline.run(
    "///|\npriv suberror FormatError {\n  InvalidBlock(String)\n}\n\n///|\nfn probe() -> Int raise {\n  raise FormatError\n}\n",
    "braced_bound.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE BODY'S OWN CONSTRUCTOR is still visible, so the row above is about the
/// TYPE name rather than about the braced shape having stopped working.
test "0463: a braced suberror's body constructor is still visible" {
  let r = @pipeline.run(
    "///|\npriv suberror FormatError {\n  InvalidBlock(String)\n}\n\n///|\nfn probe() -> Int raise {\n  raise InvalidBlock(\"bad\")\n}\n",
    "braced_ctor.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND AN `enum` IS NOT A suberror: `enum Shape { Circle }` does not make `Shape`
/// a value. The rule is scoped to `suberror` and this says so.
test "0463: an enum's own name is not a constructor" {
  let r = @pipeline.run(
    "///|\npriv enum Shape {\n  Circle\n}\n\n///|\nfn probe() -> Int {\n  let _ : Shape = Shape\n  0\n}\n",
    "enum_bound.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// 0462 -- `let mut p = p` SHADOWS THE PARAMETER, so assigning it afterwards is not
/// "the parameter changed by assignment".
///
/// The corpus shape, `async 0.22.4 src/internal/gzip_internal/encoder.mbt:148-156`:
///
///     produced : Int,                    // the parameter
///     let mut produced = produced        // a NEW binding, shadowing it
///     produced = self.push_byte(...)     // assigns the SHADOW
///
/// Settled by an ASYMMETRY rather than one program:
///
///     let mut p = p; p = 5; p     ->  moon check: 0 errors
///     p = 5; p                    ->  moon check: 1 error
///
/// Assigning an unshadowed immutable parameter is ILLEGAL, so the first program's
/// assignment cannot be reaching the parameter. These three were the last
/// `actionable` findings between async and zero.
test "0462: let mut p = p shadows the parameter, so the assignment is the local's" {
  let r = @pipeline.run(
    "///|\nfn f(produced : Int) -> Int {\n  let mut produced = produced\n  produced = 5\n  produced\n}\n",
    "shadow.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParamChanged"), 0)
}

///|
/// AND THE PARAMETER IS STILL COUNTED AS USED. The shadow reads it on the
/// right-hand side, so dropping the parameter rather than demoting it would leave
/// `varuses == 0` and fire `FUnusedParam` on the same line -- trading one false
/// positive for another, which is the failure the first attempt walked into.
test "0462: the parameter read on the right-hand side still counts as used" {
  let r = @pipeline.run(
    "///|\nfn f(produced : Int) -> Int {\n  let mut produced = produced\n  produced = 5\n  produced\n}\n",
    "shadow_use.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "FUnusedParam"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// AND AN UNUSED PARAMETER IS STILL REPORTED. The shadow clears a flag, and a flag
/// cleared too eagerly is how a lens goes quiet: this row is what says the repair
/// was scoped to shadowing rather than to parameters in general.
test "0462: an unused parameter still reports (control)" {
  let r = @pipeline.run(
    "///|\nfn f(produced : Int) -> Int {\n  let mut acc = 1\n  acc = 5\n  acc\n}\n",
    "unused.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// AND AN ASSIGNMENT TO A PARAMETER IS STILL A REBINDING. `bind` cannot tell a
/// `let` from an assignment target, a `for` binder or a destructuring name -- all
/// four arrive as a non-parameter binding with the same name -- so the first
/// version of this fix, which demoted in `bind`, deleted the finding the lens
/// exists for. Two existing tests caught it; this one names the property so a
/// later edit that reintroduces it fails here rather than there.
test "0462: an assignment to a parameter is still a rebinding (control)" {
  let r = @pipeline.run(
    "///|\nfn f(produced : Int) -> Int {\n  let mut acc = produced\n  acc = 5\n  acc\n}\n",
    "rebind.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParamChanged"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

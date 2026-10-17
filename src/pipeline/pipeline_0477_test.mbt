//| Tests for 0477 -- that a constructor pattern BINDS, not merely parses.
//|
//| WHY THIS FILE EXISTS SEPARATELY FROM `parser_0477_test.mbt`. The parser rows can only
//| assert the SHAPE: that the node is `SLetDestruct` and that `names` reads `errno, context`.
//| The claim that matters is one layer down -- that a use of `context` on the next line is
//| not reported `undefined name` -- and the corpus file that motivated the increment cannot
//| demonstrate it. `error.mbt:79` sits inside an `impl` body, and impl bodies are outside the
//| analyzed subset, so that file proves the PARSE and leaves the binding untested.
//|
//| A file that parses while binding nothing is the worst outcome available here: it converts
//| a coverage blocker into a confident false positive against code the compiler accepts,
//!| which is exactly what 0460's comment records happening when an array pattern was read as
//| expressions (`undefined name 'compression_method'`, then used eight lines later).
//|
//| EVERY POSITIVE ROW HAS A CANARY BESIDE IT, and that pairing is the whole design. A row
//| asserting `UndefinedName == 0` passes just as well on a lens that has stopped resolving
//| names altogether. "The name is in scope" and "the name was never invented" are the same
//| zero unless something beside it reports a name that genuinely does not exist -- so the
//| canaries are the rows that give the zeros meaning.

///|
/// THE CORPUS SHAPE, `error.mbt:79` and `:86`, with both names read on the following line
/// exactly as the real file reads them. Zero `UndefinedName` is the claim.
test "0477: both names a constructor pattern binds resolve on the next line" {
  let r = @pipeline.run(
    "///|\nfn f(self : OSError) -> String {\n  let OSError(errno, context~) = self\n  ignore(errno)\n  context\n}\n",
    "letpattern.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CANARY for the row above, and it is the same file with ONE NAME CHANGED. `nowhere`
/// is not mentioned by the pattern and is not bound by anything else, so it must be reported.
/// Without this row the zero above would be equally consistent with a name lens that had
/// stopped working.
test "0477 canary: a name the pattern does not mention is still reported" {
  let r = @pipeline.run(
    "///|\nfn f(self : OSError) -> String {\n  let OSError(errno, context~) = self\n  ignore(errno)\n  nowhere\n}\n",
    "letpattern.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE SETTLE'S S2 ROW, as a finding rather than a verdict: a constructor whose ONLY field is
/// labeled, and a body that reads exactly that label. This is the narrowest form of the claim
/// -- if `label~` matched without binding, this is the row that fails, and S1 would still have
/// passed because `errno` would have carried it.
test "0477: a lone labeled field binds the name it labels" {
  let r = @pipeline.run(
    "///|\npriv enum Shape {\n  Circle(label~ : String)\n}\n\n///|\nfn f(s : Shape) -> String {\n  let Circle(label~) = s\n  label\n}\n",
    "letpattern_label.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE REST PATTERN, `error.mbt:95`, which binds `errno` and absorbs the fields the corpus
/// never mentions. The canary matters more here than anywhere else in this file: `..` is two
/// dots, and a reader that bound the rest as a name would produce a name the corpus does not
/// have. The canary reads a name nothing mentions, so a spurious extra binding cannot mask it.
test "0477: the rest pattern binds the names before it and resolves them" {
  let r = @pipeline.run(
    "///|\nfn f(err : OSError) -> Int {\n  let OSError(errno, ..) = err\n  errno\n}\n",
    "letpattern_rest.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
test "0477 canary for the rest pattern: an unbound name beside `..` is reported" {
  let r = @pipeline.run(
    "///|\nfn f(err : OSError) -> Int {\n  let OSError(errno, ..) = err\n  ignore(errno)\n  elsewhere\n}\n",
    "letpattern_rest.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

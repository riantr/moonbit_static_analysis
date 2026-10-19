//| Tests for 0488 -- defect C, a LABEL read as a NAME, which is only observable here.
//
//| WHY IT LIVES IN THIS PACKAGE. `copy_interp` decides which identifiers inside `\{...}` are READS,
//| and a wrong decision produces no parse error -- it produces an UNDEFINED-NAME FINDING from the
//| name lens. `src/lexer` cannot see `@pipeline`, so the parser-level rows for defects A and B are in
//| `src/lexer/lexer_0488_test.mbt` and these two are here.
//
//| THE DEFECT. `label=value` at a call site is MoonBit's labelled-argument syntax -- the counterpart
//| of the `protocol~ : Protocol` declaration moonbitlang/async itself writes at
//| `src/http/request.mbt:56`. So `\{value.to_string(radix=16)}` supplies 16 to the parameter named
//: `radix`; it does not reference a binding, and nothing named `radix` is ever declared. `copy_interp`
//| accumulated the identifier and flushed it on `=` exactly as it would flush `value`.
//
//| WHAT IT COST, and this is the part worth recording: `no visible binding for 'radix'` at
//| moonbitlang/async `src/socket/addr_utils.mbt:291`. That finding sat WITHHELD for as long as the
//| file stopped at line 297 -- findings on a partial file are withheld rather than reported -- and
//| became ACTIONABLE the moment the append fix let the file be read whole. async went 0 -> 1
//| actionable on an increment whose stated job was to add no findings at all. The inventory had been
//| hiding a false positive behind a truncation, and only the truncation moving revealed it.
//
//| => 判据: A WITHHELD FINDING IS NOT A FINDING THAT DOES NOT EXIST. `withheld` counts findings on
//| files this reader could not finish, so a corpus can sit at `actionable=0` with a defect in it.
//> Reading a file for the first time is therefore a FALSE-POSITIVE DISCOVERY event as much as a
//> false-negative one, and the increment that unblocks the file owns the findings it uncovers.

///|
/// Count findings of one family, so a row can say "this name produced NO finding" rather than
/// asserting a total it would also satisfy for the wrong reason.
fn count_undefined(src : String) -> Int32 {
  let r = @pipeline.run(src, "t.mbt", @core.IfaceSymTab::empty())
  let mut n = 0
  for rep in r.reports {
    if rep.family.name() == "UndefinedName" {
      n += 1
    }
  }
  n
}

///|
/// THE ROW DEFECT C IS WRITTEN FOR. `value` is a parameter, so it resolves; `radix` is a label, so
/// there is nothing to resolve and nothing to report. Before the fix this counted 1.
test "0488: a labelled argument inside an interpolation is not a read" {
  assert_eq(
    count_undefined(
      "///|\nfn f(value : Int) -> Unit {\n  let s = \"\\{value.to_string(radix=16)}\"\n  ignore(s)\n}\n",
    ),
    0,
  )
}

///|
/// *** THE POSITIVE CONTROL FOR THE ROW ABOVE, AND IT IS THE POINT OF THE PAIR. ***
///
/// `==` and `=>` are NOT labels. `\{a==1}` must still record `a`, and `\{xs.map(x=>1).length()}` must
/// still record `xs` and `x`. Without this row the row above would pass on a `copy_interp` that
/// records NOTHING at all -- which is the instrument broken, not the defect fixed. The carve-out is
/// settled (`settle_0488_append_nextline.ps1` rows F3 and F4, both ACCEPT), not guessed.
///
/// *** THERE MUST BE NO SPACE, AND THAT TOOK TWO ATTEMPTS TO LEARN. *** The control was written as
/// `\{a == b}`, then as `\{a == 1}`, and mutation M6 -- which treats EVERY `=` as a label --
/// SURVIVED against both.
///
/// The reason is that the identifier is flushed by whatever comes first, and in both of those
/// spellings a SPACE comes first. `a == b` flushes `a` on the space and then reads `b`, so the row
/// still finds an undefined name; `a == 1` flushes `a` on the space and finds nothing after it, but
/// `a` was already recorded. Only the UNSPACED form `a==1` leaves the identifier pending when the
/// `=` arrives, which is precisely the shape the defect lives in -- `to_string(radix=16)`.
///
/// => 判据: A POSITIVE CONTROL MUST FAIL FOR THE ONE REASON IT EXISTS, AND THE WAY TO FIND THAT OUT
/// IS TO ASK WHICH TOKEN DISPOSES OF THE THING. Spacing is not cosmetic here: it decides whether the
/// identifier reaches the guard under test at all.
test "0488: equality and a lambda still read their names inside an interpolation" {
  // UNSPACED -- the identifier is still pending when the operator arrives.
  assert_true(
    count_undefined(
      "///|\nfn f() -> Unit {\n  let s = \"\\{a==1}\"\n  ignore(s)\n}\n",
    ) >
    0,
  )
  assert_true(
    count_undefined(
      "///|\nfn f() -> Unit {\n  let s = \"\\{xs.map(x=>1).length()}\"\n  ignore(s)\n}\n",
    ) >
    0,
  )
  // SPACED -- same property, and kept because the spaced form is what a person actually writes.
  assert_true(
    count_undefined(
      "///|\nfn f() -> Unit {\n  let s = \"\\{a == 1}\"\n  ignore(s)\n}\n",
    ) >
    0,
  )
}

///|
/// AND AN ORDINARY READ STILL REPORTS, so the control above is not the only thing proving the
/// instrument works. `missing` is a bare name with no declaration anywhere in the file.
test "0488: an ordinary undefined name inside an interpolation is still reported" {
  assert_true(
    count_undefined(
      "///|\nfn f() -> Unit {\n  let s = \"\\{missing}\"\n  ignore(s)\n}\n",
    ) >
    0,
  )
}

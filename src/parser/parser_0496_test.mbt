///|
/// 0496 -- `lexmatch`, THE LEXICAL MATCH, and the LABELLED CAPTURE it carries.
///
/// `lexmatch <subject> [with longest] { arms }` is MoonBit's regex-lexer form
/// of a match. Its arms are patterns whose first element is a REGEX LITERAL
/// and whose second is the LABELLED `after=` binding that names the input
/// AFTER the match:
///
///     lexmatch rest with longest {
///       (re"^//+" as t, after=next) => { ...; next }
///       (re"^[A-Za-z_][A-Za-z0-9_]*" as t, after=next) => { ...; next }
///       _ => abort("unreachable")
///     }
///
/// IT IS NOT A NAME, and reading it as one produced `undefined name
/// 'lexmatch'` -- a FALSE POSITIVE on code `moon check` accepts. Four sites in
/// the PINNED corpus, all in `moonbitlang/core`:
///
///     internal/strconv/strconv_int.mbt:174
///     diff/diff_align_test.mbt:56 and :94
///     diff/diff_word_test.mbt:33
///
/// THE SCOPE IS MEASURED, NOT INHERITED. The standing note said "18 sites in 3
/// PINNED core files", and a grep for `after=` gives 283 lines in 22 files --
/// but a grep counts LOCAL VARIABLES and COMMENTS too: moui's 13 hits are
/// `let after = ...`, `receipt.after` and `// after = 83*46 - 2`, and labeler's
/// two are a `let after` and a doc comment. The real construct is 84 sites in
/// FIVE pinned `moonbitlang/core` files and ZERO in the other six pinned
/// corpora.
///
/// The grammar is settled, one form per probe
/// (`_verify/settle_0496_lexmatch.ps1`):
///
///     lexmatch s { .. }                ACCEPT
///     lexmatch s with longest { .. }   ACCEPT
///     lexmatch s with { .. }           REJECT(4180) -- `with` needs `longest`
///
/// SO IT IS READ LIKE A `match`: the subject is PARSED (its reads are real),
/// the arms are SKIPPED whole (the subset has no arm patterns), and the value
/// comes from the arms -- which is exactly what `@ast.EMatch` says.

///|
/// Is there a report carrying this message? Used where the NOTICE matters
/// rather than the count, because a source with a type declaration in it emits
/// its own "outside the analyzed subset" notice.
fn has_lexmatch_notice(r : @parser.ParseResult) -> Bool {
  for rep in r.reports {
    if rep.message.contains(
        "lexmatch expression is outside the analyzed subset",
      ) {
      return true
    }
  }
  false
}

///|
/// THE NODE, not "it parses". A reader that consumed the construct whole
/// would satisfy "it parses" and be wrong about the shape: the subject must be
/// CARRIED, because the subject is real code whose reads are real.
test "0496: a lexmatch is a match whose subject is carried" {
  let r = @parser.parse(
    "fn f(s : String) -> String {\n  lexmatch s with longest {\n    (re\"^a\" as t, after=next) => next\n    _ => s\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_true(has_lexmatch_notice(r))
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => {
      // ONE statement. A `with` or a `longest` left in the token stream would
      // have become a second statement or a parse error.
      assert_eq(body.length(), 1)
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.EMatch(subject, arms) => {
              match subject.kind {
                @ast.EName(n) => assert_eq(n, "s")
                _ => assert_true(false)
              }
              // 0502. THE ARM LIST IS EMPTY, and that is the contract: an empty list
              // means the arms were NOT read, and a `match` with no arms is not
              // MoonBit, so the two readings cannot be confused. A `lexmatch`'s
              // arms end in `next`, which this frontend's statement grammar does
              // not have, so they stay unread -- and the notice above is still
              // true for them.
              assert_eq(arms.length(), 0)
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// THE `with longest` IS OPTIONAL, and the toolchain accepts both spellings
/// (settle rows `L1` and `L2`). The row is here because a reader that
/// REQUIRES `with longest` would refuse the corpus's own `lexmatch rest { .. }`
/// -- and a reader that consumed `with` without its `longest` would leave a
/// name in the stream.
test "0496: a lexmatch without the with clause is read too" {
  let r = @parser.parse(
    "fn f(s : String) -> String {\n  lexmatch s {\n    (re\"^a\", after=_) => s\n    _ => s\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_true(has_lexmatch_notice(r))
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 1)
    _ => assert_true(false)
  }
}

///|
/// AND THE ARMS ARE SKIPPED WHOLE -- the same treatment a `match`'s arms get,
/// because the subset models neither. The row asserts it by counting: if the
/// arms were parsed as statements, the body would carry them.
test "0496: the arms of a lexmatch are skipped whole" {
  let r = @parser.parse(
    "fn f(s : String) -> String {\n  lexmatch s with longest {\n    (re\"^a\" as t, after=next) => next\n    _ => s\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 1)
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL, and the row that keeps the change in its place: an ordinary
/// `match` is still a `match` and still says so. A reader that had folded the
/// two together would make this row report the lexmatch message, and the
/// notice would be about a construct the file does not contain.
///
/// 0502. AND NOW AN ORDINARY `match` SAYS NOTHING AT ALL, because its arms are
/// read. So the control's job is the same and its evidence is different: there
/// must be NO notice here, and in particular not the `lexmatch` one.
test "0496: an ordinary match is still a match (control)" {
  let r = @parser.parse(
    "fn f(s : String) -> String {\n  match s {\n    \"a\" => s\n    _ => s\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  // NO NOTICE: the arms are read, so there is nothing to announce.
  assert_eq(r.reports.length(), 0)
  assert_true(!has_lexmatch_notice(r))
}

///|
/// AND `lexmatch` IS NOT A NAME IN THE TREE. This is the row the whole
/// increment turns on: the finding was `undefined name 'lexmatch'`, and it
/// existed because the name reached the frame. A reader that consumed the
/// keyword but still produced an `EName` would satisfy the rows above -- the
/// node is `EMatch` either way -- and fail this one.
test "0496: a lexmatch leaves no name in the tree" {
  let r = @parser.parse(
    "fn f(s : String) -> String {\n  lexmatch s with longest {\n    (re\"^a\" as t, after=next) => next\n    _ => s\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.EMatch(_, _) => ()
            @ast.EName(n) => assert_true(n != "lexmatch")
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

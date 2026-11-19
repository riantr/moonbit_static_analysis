///|
/// 0615 -- `lexscan`, THE LEXICAL SCAN, and the ARMS it carries.
///
/// `lexscan <subject> [with <strategy>] { arms }` is MoonBit's STREAMING
/// regex-lexer form of a match. The subject is a SCANNER -- a `Lexbuf`, a
/// `StringScanner`, or anything implementing `Scannable` -- and the arms are
/// patterns whose first element is a REGEX LITERAL:
///
///     lexscan self {
///       (re"^[^\n]*" as line) + re"\r\n" => Some(line)
///       _ => None
///     }
///
/// IT IS NOT A NAME, and reading it as one produced `undefined variable
/// 'lexscan'` -- a FALSE POSITIVE on code `moon check` accepts. MEASURED on the
/// re-pinned corpus (`moonbitlang/core` `0.1.20261117+06da1ed44`), three sites,
/// and every one of them in ORDINARY CODE rather than in a test body:
///
///     lexbuf/read_line.mbt:37
///     lexbuf/read_line_test.mbt:53
///     lexbuf/async_read_line_test.mbt:29
///
/// WHY IT LIVED SO LONG, and this is the part worth keeping. The OLD corpus
/// (`0.1.20261105+65efd5b93`) DID use `lexscan` -- six files of it -- and the
/// analyzer reported nothing at all, because every one of those uses was in a
/// place the analyzer never reads: a `test` body (`lexbuf/lexbuf_test.mbt:18`,
/// `string_scanner/string_scanner_test.mbt:29`) or a DOC COMMENT
/// (`string_scanner/string_scanner.mbt:35`). The construct was in the corpus the
/// whole time and in no analysed code at all.
///
/// That is the same shape the 0496 note records for `radix`: a real false
/// positive that an inventory of the files the analyzer CAN read cannot see.
/// The corpus moving is what put the construct into ordinary code.
///
/// The grammar is settled against the toolchain, one form per probe
/// (`_verify/settle_0615_lexscan.ps1`):
///
///     lexscan s { .. }                ACCEPT
///     lexscan s with longest { .. }   ACCEPT
///     lexscan s with { .. }           REJECT(4180) -- `with` needs a strategy
///     lexscan s                       REJECT(3002) -- the arms are not optional
///
/// IT IS READ LIKE A `match`, and that is a CHANGE from `lexmatch`: the subject
/// is PARSED (its reads are real), the arms are READ (their reads are real
/// too), and the value comes from the arms -- which is exactly what
/// `@ast.EMatch` says. A `lexmatch`'s arms are SKIPPED, because an arm body
/// ends in `next` and `next` is not in this frontend's statement grammar; a
/// `lexscan` arm body is an ordinary expression, so there is nothing to stop
/// the arms from being read.

///|
/// The corpus's own shape of the construct. `lexscan` with a REGEX LITERAL arm
/// and a WILDCARD arm, and a body that reads the arm's own binding -- so a
/// reader that read the arms but did not bind the pattern's name would report
/// `line` as unbound.
fn lexscan_src(with_clause : String) -> String {
  "fn f(s : String) -> String? {\n  lexscan s " +
  with_clause +
  "{\n    (re\"^[^\\n]*\" as line) + re\"\\r\\n\" => Some(line)\n    _ => None\n  }\n}\n"
}

///|
/// Is there a report carrying this message? Used where the NOTICE matters
/// rather than the count.
fn has_lexscan_notice(r : @parser.ParseResult) -> Bool {
  for rep in r.reports {
    if rep.message.contains("lexscan expression is outside the analyzed subset") {
      return true
    }
  }
  false
}

///|
/// THE NODE, not "it parses". A reader that consumed the construct whole would
/// satisfy "it parses" and be wrong about the shape: the subject must be
/// CARRIED, because the subject is real code whose reads are real.
test "0615: a lexscan is a match whose subject is carried" {
  let r = @parser.parse(lexscan_src(""))
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => {
      // ONE statement. A `with` or a `longest` left in the token stream would
      // have become a second statement or a parse error.
      assert_eq(body.length(), 1)
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.EMatch(subject, _) =>
              match subject.kind {
                @ast.EName(n) => assert_eq(n, "s")
                _ => assert_true(false)
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
/// AND THE ARMS ARE READ, which is the difference from a `lexmatch` and the
/// difference that keeps the enclosing function's frame whole. A `lexmatch`'s
/// arms end in `next`, which this frontend's statement grammar does not have;
/// a `lexscan` arm body is an ordinary expression, so the arms are read.
///
/// The row counts them, and it counts the arm's OWN BINDING: the pattern
/// `(re"^[^\n]*" as line) + re"\r\n"` binds `line`, and the arm body reads it.
/// A reader that skipped the arms would carry zero of them.
test "0615: the arms of a lexscan are read" {
  let r = @parser.parse(lexscan_src(""))
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.EMatch(_, arms) => {
              assert_eq(arms.length(), 2)
              // THE BINDING IS THE PATTERN'S, and the arm body reads it. The
              // binding list is the arm's, and the corpus's own shape is the
              // fixture: `as line` in the pattern, `Some(line)` in the body.
              assert_true(arms[0].bindings.contains("line"))
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE ARMS BEING READ MEANS NO NOTICE. The notice says "read but not
/// analysed"; a construct whose arms WERE analysed must not say it, or a
/// reader would be told the arms were skipped when they were not.
///
/// This is the row that would go red if the transaction's fast path were
/// removed, because the fallback is the one that emits the notice.
test "0615: a lexscan whose arms were read says nothing" {
  let r = @parser.parse(lexscan_src(""))
  assert_eq(r.first_error, 0)
  assert_true(!has_lexscan_notice(r))
}

///|
/// THE `with` CLAUSE IS OPTIONAL, and the toolchain accepts the bare form
/// (settle row `L1`). The corpus uses the bare form at all three sites, so a
/// reader that REQUIRED the clause would pass every row above and fail on the
/// corpus.
test "0615: a lexscan without the with clause is read too" {
  let r = @parser.parse(lexscan_src(""))
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 1)
    _ => assert_true(false)
  }
}

///|
/// AND THE CLAUSE IS READ WHEN IT IS THERE. `with longest` is the toolchain's
/// second strategy (settle row `L2`), and a reader that left `longest` in the
/// token stream would either make a parse error or a second statement -- and
/// the row above, which counts the statements, is what catches it.
test "0615: a lexscan with a strategy clause is read" {
  let r = @parser.parse(lexscan_src("with longest "))
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 1)
    _ => assert_true(false)
  }
}

///|
/// AND `with first` IS READ AS WELL. The toolchain's own error message says
/// "Only `first` (the default one) and `longest` match strategies are
/// supported", so the two strategies are the two words -- and a reader that
/// knew only `longest` would leave `first` in the stream. Settled as row `L3`.
test "0615: a lexscan with the first strategy is read" {
  let r = @parser.parse(lexscan_src("with first "))
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 1)
    _ => assert_true(false)
  }
}

///|
/// AND `lexscan` IS NOT A NAME IN THE TREE. This is the row the whole
/// increment turns on: the finding was `undefined variable 'lexscan'`, and it
/// existed because the name reached the frame. A reader that consumed the
/// keyword but still produced an `EName` would satisfy the rows above -- the
/// node is `EMatch` either way -- and fail this one.
test "0615: a lexscan leaves no name in the tree" {
  let r = @parser.parse(lexscan_src(""))
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.EMatch(_, _) => ()
            @ast.EName(n) => assert_true(n != "lexscan")
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND AN ORDINARY `match` IS STILL A `match`. The control that keeps the
/// change in its place: a reader that had folded the two together would make
/// this row report the lexscan message, and the notice would be about a
/// construct the file does not contain.
test "0615: an ordinary match is still a match (control)" {
  let r = @parser.parse(
    "fn f(s : String) -> String {\n  match s {\n    \"a\" => s\n    _ => s\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  assert_true(!has_lexscan_notice(r))
}

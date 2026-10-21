# Mutation gate 0494 -- THE FOUR SHAPES THAT STOPPED THE ASYNC CORPUS.
#
# WHAT THIS INCREMENT IS. The async corpus was 415/419 readable, and the four
# files it could not read each stopped on a SHAPE this frontend did not read.
# 0494 reads all four, and the corpus is 419/419 with `actionable=0` and
# `unreliable` 23 -> 0.
#
# THE FOUR, and the shape each one turned out to need:
#
#   M1  THE REGEX LITERAL, `re"..."`, and the `=~` that consumes it.
#       `async 0.22.4 src/http/request.mbt:59` reported "expected ')'". TWO
#       constructs, not one: the literal AND the operator. Settling only the
#       literal would have left the file unreadable for a second reason.
#   M2  THE DESCENDING RANGE, `>..`.
#       `async 0.22.4 src/fs/watch_windows.mbt:320` reported "unexpected token
#       `.`" -- the `>` was read as a comparison and the two dots were left
#       behind.
#   M3  THE `for` UPDATE LIST. `for x = v, i = n; i >= 0; x = x / b, i = i - 1`.
#       `async 0.22.4 src/http/utils.mbt:23` reported "expected '{'". The
#       INITIALIZER could already be a list (settled at 0472); the update could
#       not.
#   M4  THE SHORTHAND STRUCT PATTERN, `let { identity, .. } = x`.
#       `async 0.22.4 src/fs/watch_kqueue.mbt:240` reported "expected binding
#       name". The braced pattern reader existed (0485) but read the KEYED
#       spelling.
#   M5  A `break` THAT CARRIES A VALUE, `break path[:i]`.
#       The same corpus file, one line down: the value was left in the token
#       stream.
#   M6  THE REGEX CAPTURE, `re"..." as name`.
#       Reading the capture as a CAST consumed the name as a TYPE, so
#       `port_str` was reported `undefined name` at its use -- a false positive
#       on code `moon check` compiles, and the one actionable finding the first
#       version of this increment produced.
#
# SETTLED BEFORE IMPLEMENTING, not after:
# `_verify/settle_0494_parse_backlog.ps1`, 22 rows with TEN that REJECT.
#
# TWO OF MY OWN EXPECTATIONS WERE WRONG and the toolchain was right in both, and
# both are recorded in the settle:
#
#   - `break path[:i]` was expected to be ACCEPTed and it was REJECTed with
#     4014, "Expr Type Mismatch": the corpus's `path` is a StringView, and
#     `path[:i]` on a String is a StringView. The row now says StringView.
#   - `re"[0-9]+"` was written as a CONTROL that must be REJECTed, and it was
#     ACCEPTed -- because it is a perfectly good regex. The row was a bad
#     expectation, not a toolchain disagreement, and it is now an ACCEPT row.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE, and every one of them
# is UNIQUE in its file -- the harness refuses an ambiguous anchor, because it
# mutates the FIRST match and the second copy would never be verified.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$LEXER  = 'src\lexer\lexer.mbt'
$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0494' -Target 'wasm' -Mutations @(

  # M1 THE REGEX LITERAL. Without the dispatch hook, `re"^a"` lexes as the
  # name `re` followed by a string, and the `=~` operator is left to the
  # statement reader -- which reads `=` as an ASSIGNMENT.
  @{
    Name = 'M1 the regex literal is not lexed'
    File = $LEXER
    Find = @'
      if t == TName("re") &&
'@.Replace("`r`n", "`n")
    Repl = @'
      if t == TName("re_NEVER") &&
'@.Replace("`r`n", "`n")
    MustRed = '0494: the regex match is an operator and the literal is a regex'
  }

  # M2 THE DESCENDING RANGE. Without the token, `n>..0` lexes as `>` followed
  # by two dots -- which is the error the corpus reported.
  @{
    Name = 'M2 the descending range is not lexed'
    File = $LEXER
    Find = @'
  if c == '>' &&
    next == Some('.') &&
    self.pos + 2 < self.chars.length() &&
    self.chars[self.pos + 1] == '.' &&
    self.chars[self.pos + 2] == '.' {
'@.Replace("`r`n", "`n")
    Repl = @'
  if c == '>' &&
    next == Some('.') &&
    self.pos + 2 < self.chars.length() &&
    self.chars[self.pos + 1] == '.' &&
    self.chars[self.pos + 2] == 'x' {
'@.Replace("`r`n", "`n")
    MustRed = '0494: a descending range is a range and not a comparison'
  }

  # M3 THE UPDATE LIST. The reader took ONE statement and left the comma in
  # the token stream, so the parser reported "expected '{'".
  @{
    Name = 'M3 the for update clause is not a list'
    File = $PARSER
    Find = @'
  while self.at(TComma) {
    let _ = self.bump()
    self.skip_seps()
    out.push(self.parse_stmt())
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  while self.at(TName("NEVER")) {
    let _ = self.bump()
    self.skip_seps()
    out.push(self.parse_stmt())
  }
'@.Replace("`r`n", "`n")
    MustRed = '0494: a comma-separated update list reaches the loop body'
  }

  # M4 THE SHORTHAND STRUCT PATTERN. Without it, the `{` fell to the plain
  # binding path, which expected a NAME and reported "expected binding name".
  @{
    Name = 'M4 the shorthand struct pattern is not read'
    File = $PARSER
    Find = @'
    if self.at(TLBrace) && self.at_shorthand_struct_pattern() {
'@.Replace("`r`n", "`n")
    Repl = @'
    if self.at(TLBrace) && self.at_name("NEVER") {
'@.Replace("`r`n", "`n")
    MustRed = '0494: a shorthand struct pattern binds the field it names'
  }

  # M5 A `break` THAT CARRIES A VALUE. The value used to be left in the token
  # stream, where the parser died on it.
  #
  # THE ANCHOR SPANS THE `bare` TEST AND THE RETURN, because the `bare` test
  # on its own appears in the `continue` arm too -- and an anchor that matches
  # two sites mutates the FIRST one, which is the wrong arm.
  #
  # RE-ANCHORED AT 0495. The return used to read `@ast.SBreak`; the break now
  # carries its values as its own payload, so the bare form reads
  # `@ast.SBreak([])`. The MUTATION IS THE SAME ONE -- "the `bare` test is
  # always true, so a valued break is read as a bare one and its value is left
  # in the token stream" -- and it still kills on the same named test.
  @{
    Name = 'M5 a break that carries a value is read as a bare break'
    File = $PARSER
    Find = @'
    let bare = match self.peek() {
      TNewline | TSemi | TRBrace | TLBrace | TEOF => true
      _ => false
    }
    if bare {
      return { span: sp, kind: @ast.SBreak([]), }
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    let bare = match self.peek() {
      TNewline | TSemi | TRBrace | TLBrace | TEOF => true
      _ => true
    }
    if bare {
      return { span: sp, kind: @ast.SBreak([]), }
    }
'@.Replace("`r`n", "`n")
    MustRed = '0494: a break may carry a value and the value is read'
  }

  # M6 THE REGEX CAPTURE. Read as a CAST, the name was consumed as a TYPE and
  # the binding was lost -- so `port_str` was reported `undefined name` at its
  # use, on code `moon check` compiles.
  @{
    Name = 'M6 the regex capture is read as a cast'
    File = $PARSER
    Find = @'
      let capture = match e.kind {
        @ast.ERegex(_) => self.peek_name() != ""
        _ => false
      }
      if capture {
        let (n, _) = self.expect_name("capture name")
        e = { span: asp, kind: @ast.EAsBind(e, n), }
        continue
      }
      let _ = self.type_annotation()
'@.Replace("`r`n", "`n")
    Repl = @'
      let _ = self.type_annotation()
'@.Replace("`r`n", "`n")
    MustRed = '0494: a regex capture binds the name it names'
  }
)

Write-MutationGateVerdict -Name '0494'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

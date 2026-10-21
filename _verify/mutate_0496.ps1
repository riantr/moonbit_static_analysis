# Mutation gate 0496 -- THE CHARACTER LITERAL'S ESCAPE, THE LEXICAL MATCH, AND
# THE LAMBDA THAT BINDS INSIDE AN INTERPOLATION.
#
# WHAT THIS INCREMENT IS. Three readers, three measured defects, and one crash:
#
#   A  the CHARACTER LITERAL's escape. The reader took as many hex digits as
#      there were -- `'\u{1F600}'` was read as U+1F600, not truncated -- and then
#      counted the payload with `s.length()`. MoonBit's `String::length()` counts
#      UTF-16 CODE UNITS and `String::to_array()` counts CODE POINTS, so an
#      astral character was counted as TWO and a legal literal was refused. The
#      standing note in `_verify/NARRATIVE.md` said the reader "takes at most
#      FOUR hex digits, which is exactly the BMP"; that was the WRONG
#      EXPLANATION of a right observation, and a fix written from it would have
#      bounded the digits and still refused `'\u{10000}'`.
#
#   A2 THE CRASH. `'\u{110000}'` -- a code point past the last one -- reached
#      `v.unsafe_to_char()`, which is not a conversion but a TRAP: the scanner
#      printed `RuntimeError: unreachable` and STOPPED, so every file after it
#      went unread. A wrong answer is one finding; a crash is the loss of the
#      run.
#
#   B  `lexmatch`, MoonBit's LEXICAL MATCH, read as an ordinary NAME -- so
#      `undefined name 'lexmatch'` at four sites in the pinned corpus
#      `moonbitlang/core`, on code `moon check` accepts.
#
#   C  A LAMBDA PARAMETER inside an interpolation, recorded as a READ of the
#      enclosing frame -- so `no visible binding for 'sb'` at
#      `moonbitlang/core` `builtin/autoloc.mbt:83`. This one was UNCOVERED by
#      B: the file stopped at line 74 -- where the `lexmatch` at line 63 used
#      to stop the reader -- so the finding was withheld until B made the file
#      readable. It is the same uncovering the 0488 comment records for
#      `radix`: a real false positive that an inventory of PARTIAL files could
#      not see, and shipping the increment without fixing it would have pinned
#      `actionable` as though the finding were correct.
#
# EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED. A mutation that kills
# some other test is not evidence: the test named here is the one that pins the
# rule, so the kill is the rule's own.
#
# TWO MUTATIONS ARE ABOUT THE CRASH AND CANNOT BE "REMOVE THE GUARD". A
# mutation that lets an out-of-range code point through does not make a test go
# red -- it makes the SUITE DIE, and a suite that dies is COMPILE-ERR and not a
# kill. So the guard is mutated on its BOUND: an off-by-one still refuses the
# value (so nothing crashes) and refuses the LAST LEGAL CODE POINT as well,
# which is a red test.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE, and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$LEXER = 'src\lexer\lexer.mbt'
$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0496' -Target 'wasm' -Mutations @(

  # M1 THE CHARACTER COUNT IS A CHARACTER COUNT. This is THE old bug, written
  # as a mutation: counting the payload by its UTF-16 length instead of by the
  # characters written into it. The astral escape becomes two, the literal is
  # refused, and the test that says an astral escape is ONE character goes red.
  @{
    Name = 'M1 the escape counts UTF-16 units instead of characters'
    File = $LEXER
    Find = @'
          buf.write_char(v.unsafe_to_char())
          chars += 1
'@.Replace("`r`n", "`n")
    Repl = @'
          buf.write_char(v.unsafe_to_char())
          chars += buf.to_string().length()
'@.Replace("`r`n", "`n")
    MustRed = '0496: an astral escape is ONE character'
  }

  # M2 THE LENGTH CHECK COUNTS CHARACTERS. `||` instead of `&&`: the literal is
  # now refused when EITHER the character count or the UTF-16 length is wrong,
  # and an astral character has a length of two. The same row as M1 goes red
  # for the second reason, which is why the two are separate mutations: M1
  # breaks the COUNT and M2 breaks the CHECK, and only one of them would be
  # found by a reader that had fixed the other.
  @{
    Name = 'M2 the length check also consults the UTF-16 length'
    File = $LEXER
    Find = @'
  } else if chars != 1 {
'@.Replace("`r`n", "`n")
    Repl = @'
  } else if chars != 1 || s.length() != 1 {
'@.Replace("`r`n", "`n")
    MustRed = '0496: an astral escape is ONE character'
  }

  # M3 THE LAST CODE POINT IS LEGAL. The bound is off by one, so U+10FFFF --
  # the last code point, and six hex digits -- is refused. Nothing crashes:
  # the value is still REJECTED, just one code point too early.
  @{
    Name = 'M3 the last code point is refused'
    File = $LEXER
    Find = @'
        } else if v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF) {
'@.Replace("`r`n", "`n")
    Repl = @'
        } else if v > 0x10FFFE || (v >= 0xD800 && v <= 0xDFFF) {
'@.Replace("`r`n", "`n")
    MustRed = '0496: the last code point is one character'
  }

  # M4 A SURROGATE IS NOT A SCALAR VALUE. The range's lower bound is moved
  # past the surrogates, so U+D800..U+DFFF is accepted. A surrogate does not
  # crash the writer -- it is the out-of-range value that does -- so this
  # mutation fails cleanly.
  @{
    Name = 'M4 a surrogate is accepted'
    File = $LEXER
    Find = @'
        } else if v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF) {
'@.Replace("`r`n", "`n")
    Repl = @'
        } else if v > 0x10FFFF || (v >= 0xE000 && v <= 0xDFFF) {
'@.Replace("`r`n", "`n")
    MustRed = '0496: a surrogate is not a valid code point'
  }

  # M5 THE BRACED FORM TAKES SIX DIGITS. Five is one too few, so
  # `'\u{10FFFF}'` -- six digits, the last code point -- is refused as a
  # malformed escape.
  @{
    Name = 'M5 the braced form takes five digits'
    File = $LEXER
    Find = @'
        } else if braced {
          (1, 6)
        } else {
'@.Replace("`r`n", "`n")
    Repl = @'
        } else if braced {
          (1, 5)
        } else {
'@.Replace("`r`n", "`n")
    MustRed = '0496: the last code point is one character'
  }

  # M6 THE HEX ESCAPE TAKES TWO DIGITS. Three is one too many, so `'\x414'`
  # -- which the toolchain REJECTs with 3001 -- becomes one character.
  @{
    Name = 'M6 the hex escape takes three digits'
    File = $LEXER
    Find = @'
        let (lo, hi) = if e == 'x' {
          (2, 2)
        } else if braced {
'@.Replace("`r`n", "`n")
    Repl = @'
        let (lo, hi) = if e == 'x' {
          (2, 3)
        } else if braced {
'@.Replace("`r`n", "`n")
    MustRed = '0496: the hex escape takes exactly two digits'
  }

  # M7 A BYTE LITERAL TAKES NO UNICODE ESCAPE. The guard's letter is changed,
  # so `b'\u000C'` -- which the toolchain REJECTs with 3001 and which 0480
  # already refused in its unbraced form -- is read as a character.
  @{
    Name = 'M7 a byte literal takes a unicode escape'
    File = $LEXER
    Find = @'
        if byte_form && e == 'u' {
'@.Replace("`r`n", "`n")
    Repl = @'
        if byte_form && e == 'x' {
'@.Replace("`r`n", "`n")
    MustRed = '0496: the byte form takes no unicode escape'
  }

  # M8 THE LAMBDA HEAD IS A BINDING. The lookahead stops recognising the
  # arrow, so the parameter is recorded as a read of the enclosing frame and
  # the finding comes back.
  @{
    Name = 'M8 the arrow is not recognised'
    File = $LEXER
    Find = @'
  j + 1 < self.chars.length() &&
  self.chars[j] == '=' &&
  self.chars[j + 1] == '>'
'@.Replace("`r`n", "`n")
    Repl = @'
  j + 1 < self.chars.length() &&
  self.chars[j] == '=' &&
  self.chars[j + 1] == 'x'
'@.Replace("`r`n", "`n")
    MustRed = '0496: a lambda parameter inside an interpolation is not a read'
  }

  # M9 THE BOUND NAME IS NOT READ ANYWHERE. The use of the parameter inside
  # the lambda's body is recorded, and the finding comes back -- even though
  # the HEAD is still recognised as a binding.
  @{
    Name = 'M9 a bound name is still recorded as a read'
    File = $LEXER
    Find = @'
  if self.interp_bound.contains(name) {
'@.Replace("`r`n", "`n")
    Repl = @'
  if self.interp_bound.contains(name + "!") {
'@.Replace("`r`n", "`n")
    MustRed = '0496: a lambda parameter inside an interpolation is not a read'
  }

  # M9b THE TIGHT ARROW IS NOT RECOGNISED. This is the third half of the trio, and it
  # is the half M8 and M9 cannot see.
  #
  # The collector has TWO paths for a lambda head. The TIGHT spelling -- `sb=>sb`, no
  # space -- reaches the `=>` branch of the collector, because the name is still pending
  # when the `=` arrives. The SPACED spelling -- `sb => sb` -- reaches the lookahead in
  # `at_lambda_head_after`, because the space already flushed the name.
  #
  # M8 breaks the LOOKAHEAD and M9 breaks the BOUND-NAME skip, and NEITHER OF THEM
  # PROVES THE `=>` BRANCH EXISTS. Delete that branch and M8's mutation changes
  # nothing at all -- the tight spelling no longer reaches the lookahead either -- and
  # M9's mutation changes nothing either, because the bound name is never bound. Both
  # would SURVIVE a deleted branch, and a survivor that cannot see a deletion is not
  # guarding the thing it names.
  #
  # THIS ONE SEES IT. The arrow's `== '>'` test becomes `== 'x'`, so the branch stops
  # firing for `=>`: the name falls through to the LABEL branch, is dropped as a label
  # instead of being BOUND, and the USE of it later in the same interpolation is
  # recorded as a read of the enclosing frame. `sb` comes back, and the row that
  # names the tight spelling goes red.
  @{
    Name = 'M9b the tight arrow is not recognised'
    File = $LEXER
    Find = @'
    } else if c == '=' &&
      self.pos < self.chars.length() &&
      self.chars[self.pos] == '>' {
'@.Replace("`r`n", "`n")
    Repl = @'
    } else if c == '=' &&
      self.pos < self.chars.length() &&
      self.chars[self.pos] == 'x' {
'@.Replace("`r`n", "`n")
    MustRed = '0496: a tight arrow binds the same way'
  }

  # M10 `lexmatch` IS A CONSTRUCT, NOT A NAME. The arm stops matching, so the
  # keyword is read as an identifier and the false positive comes back.
  @{
    Name = 'M10 a lexmatch is read as a name'
    File = $PARSER
    Find = @'
    TName("lexmatch") => {
'@.Replace("`r`n", "`n")
    Repl = @'
    TName("lexmatch_disabled") => {
'@.Replace("`r`n", "`n")
    MustRed = '0496: a lexmatch is not an undefined name'
  }

  # M11 THE `with longest` CLAUSE IS READ. Without it, `longest` is left in
  # the token stream, the arms are not skipped, and the parse breaks.
  @{
    Name = 'M11 the with-longest clause is not consumed'
    File = $PARSER
    Find = @'
        if self.at_name("longest") {
'@.Replace("`r`n", "`n")
    Repl = @'
        if self.at_name("longest_disabled") {
'@.Replace("`r`n", "`n")
    MustRed = '0496: a lexmatch is a match whose subject is carried'
  }

  # M12 THE NOTICE SAYS WHAT WAS READ. The message becomes the `match` one,
  # so a `lexmatch` is reported as a `match` -- and the row that says the two
  # are told apart goes red.
  @{
    Name = 'M12 a lexmatch says it was a match'
    File = $PARSER
    Find = @'
        "lexmatch expression is outside the analyzed subset; it was read but not analysed",
'@.Replace("`r`n", "`n")
    Repl = @'
        "match expression is outside the analyzed subset; it was read but not analysed",
'@.Replace("`r`n", "`n")
    MustRed = '0496: a lexmatch is a match whose subject is carried'
  }

  # M13 THE KEYWORD LIST. `lexmatch` IS SYNTAX, NOT A NAME, and the lexer
  # keyword list is where the codebase says so -- it is the one place that
  # asks "is this a name to resolve?".
  #
  # IT SURVIVES, and the argument is that the ENTRY IS DEFENSIVE while the
  # ARM is load-bearing. Every `lexmatch` in the pinned corpus is in
  # EXPRESSION position, where M10's arm consumes it, so no name ever reaches
  # the frame and the list cannot change a finding: the corpus's 4
  # `undefined name 'lexmatch'` findings stay at 4 with the entry removed.
  # The entry is kept because `is_moonbit_keyword` is the one predicate that
  # says "this word is syntax", and a keyword that is not on it would be
  # resolved as a binding in a pattern or an interpolation.
  #
  # FALSIFIED IF a `lexmatch` ever appears outside expression position -- a
  # pattern head, or inside a `\{...}` interpolation -- because then the entry
  # would be the only thing standing between the word and a finding.
  @{
    Name = 'M13 the keyword list loses lexmatch'
    File = $LEXER
    Find = @'
    | "lexmatch"
'@.Replace("`r`n", "`n")
    Repl = @'
    | "lexmatch_disabled"
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = 'Defensive. Every `lexmatch` in the pinned corpus is in expression position, where the parser arm (M10) consumes it, so no name reaches the frame and the list cannot change a finding. Falsified if a `lexmatch` ever appears in a pattern or inside an interpolation.'
  }
)

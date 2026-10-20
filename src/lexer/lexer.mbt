// lexer for the MoonBit-subset frontend: newline-sensitive rules —
// suppressed after openers/binary operators/assignment so expressions can
// span lines; otherwise a newline terminates the statement.

///|
pub(all) enum Tok {
  TInt(Int32)
  /// An integer literal this analyzer gives no value to: it did not fit the
  /// fixed `lit_max` bound, or it carried an `L` / `U` / `UL` suffix naming a
  /// wider type. It is a real integer, not an error — the point is that
  /// `const_eval` must not fold a dead branch on a number it could not read,
  /// and the type lens must not claim a mismatch it cannot justify.
  TBigInt
  TFloat(Double)
  /// A string literal. The second field carries the names REFERENCED inside
  /// `\{...}` interpolations, in source order.
  ///
  /// It exists because the interpolation body is copied raw into the payload,
  /// so nothing downstream can see it: a name read ONLY inside a
  /// interpolation looked unread, and a name that does not exist inside one
  /// was never reported. Both directions were wrong, and the false positive
  /// fired on this analyzer's own source — every one of the 8 remaining
  /// findings in the 0.4.7 self-scan was a name read solely via `\{...}`
  /// (`mermaid.mbt` `anchor`, `pipeline.mbt` `i`/`s`/`r`, `parser.mbt` `what`
  /// twice, `interp.mbt` `name`, `cli/main.mbt` `live`).
  ///
  /// This is the lexer's exact answer, not a re-scan of the payload: only
  /// here is it known that a `{` came from an interpolation rather than being
  /// an ordinary brace in the string content.
  TStr(String, Array[String])
  /// A REGEX LITERAL, `re"..."`. Its own token rather than a `TStr`, because a
  /// Regex is NOT a String: `let r : String = re"^a"` is REJECTed by the
  /// toolchain with 4014 while `let r : Regex = re"^a"` is ACCEPTed
  /// (`_verify/settle_0494_parse_backlog.ps1`, rows `a2` and `a5`).
  ///
  /// The prefix is the WHOLE identifier `re` and the quote must follow it with
  /// nothing between: `re"^a"` is a literal and `re` alone is an ordinary name
  /// (the same settle, row `a7`, REJECTs `re` used as a value).
  TRegex(String)
  TName(String)
  TPlus
  TMinus
  TStar
  TSlash
  TPercent
  TAssign
  /// `+=` `-=` `*=` `/=` `%=` — compound assignment, one token each, so the
  /// statement parser can desugar `lhs op= rhs` into
  /// `SAssign(lhs, EBin(op, lhs, rhs))`. Before this, `i += 1` lexed as
  /// TPlus then TAssign and the statement parser died on the `=`; that one
  /// shape blocked main.mbt, moonfiles.mbt, pipeline.mbt and their tests.
  TPlusEq
  TMinusEq
  TStarEq
  TSlashEq
  TPercentEq
  TEqEq
  /// `=~` — the REGEX MATCH operator. One token, because `=` and `~` are two
  /// tokens otherwise and the statement reader would read the `=` as an
  /// ASSIGNMENT: `host =~ re"^"` became `host =` followed by a stray `~`, and
  /// the `~` died in the expression reader.
  ///
  /// Its result is a Bool -- settled in `_verify/settle_0494_parse_backlog.ps1`,
  /// row `a3`, with the control `a4` REJECTing the same expression against an Int.
  TEqTilde
  TNe
  TLt
  TLe
  TGt
  TGe
  TAndAnd
  TOrOr
  /// The bitwise operators, one token each: `&` / `^` single-character,
  /// `<<` / `>>` two-character (checked in lex_op's two-char chain, before
  /// the single-char table). Before these existed, `h & 1023` reported
  /// "unexpected character '&'" and marked the whole file partial — the
  /// measured Class F blocker at statecheck.mbt:275. Compound bit
  /// assignment (`&=`, `<<=`) is deliberately NOT modelled: it was not
  /// measured in the corpus, and a wrong token for it would be invented
  /// behavior rather than fidelity.
  TAmp
  TCaret
  TShl
  TShr
  /// A lone `|` — TWO roles, and the second one was missed for a long time.
  ///
  /// The first role is the or-pattern separator inside match arms
  /// (`SAssign(_) | SLet(_) => ...`). Match bodies are skipped whole, so no pattern
  /// grammar is needed; the token exists so the CHARACTER stops reaching lex_op's
  /// unknown-char arm, whose FParse report marked whole files partial on an
  /// or-pattern they could otherwise read.
  ///
  /// The second role is the BITWISE-OR OPERATOR, and it is a real one:
  /// `parse_bitor` consumes `TBar` and builds `EBin(OpBitOr, ...)` (parser.mbt:3134).
  /// This comment used to claim "the parser never sees one", which stopped being true
  /// when that tier was added. The cost of the stale claim was concrete: because `|`
  /// was understood as bitwise-or but was MISSING from `newline_suppressed_after`, an
  /// expression could not continue across a line break after it, and
  /// `input_dispatch_result.mbt` died on `(if self.handled { 1 } else { 0 }) |` with
  /// "unexpected end of line" while `+`, `&` and `||` all continued correctly.
  /// Settled in `_verify/settle_0455_paren_if.ps1`, 20/20 with a positive control.
  TBar
  TBang
  /// `?` — real MoonBit (optional types `T?`, optional parameters `x? : T`),
  /// so it must not be reported by the lexer. This frontend consumes it in the
  /// annotation positions above; anywhere else it reaches the parser.
  TQuestion
  /// `~` — the LABEL sigil, and it has two settled sides (0.4.18, both
  /// confirmed by `moon check` on wzzc-dev/moui 0.1.12):
  ///
  ///   - DECLARATION `f~ : T` declares a parameter that must be supplied BY
  ///     LABEL. The compiler rejects a positional pass with "The labels f~ are
  ///     required by this function, but not supplied."
  ///   - CALL `f(x~)` is the shorthand for `f(x=x)`. The compiler rejects a
  ///     wrong label with "This function has no parameter with label x~."
  ///
  /// Before this existed `~` reached lex_op's unknown-char arm: 60 of the 415
  /// files wzzc-dev/moui could not read reported "unexpected character '~'"
  /// as their FIRST error, and the character occurs in 594 of its .mbt files
  /// — 407 in a `~ :` declaration, 341 in a `~,` argument. It is deliberately
  /// NOT in the expression-terminator list above: `~` never ends a line, since
  /// it is written tight against the name it qualifies.
  TTilde
  /// `..<` — the EXCLUSIVE range operator, one token. A bare `..` stays two
  /// TDots, which is what the toolchain wants: `moon check` REJECTS `a..b` with
  /// "Missing `=` after `..` in range expression" and names both real forms in
  /// its hint.
  TRange
  /// `..<=` — the INCLUSIVE range operator, four characters. Settled the same
  /// way, one form per package beside a broken canary: `0..<=n` is 0 errors and
  /// `0..=<n` is rejected, so this is the spelling and not `..=`.
  ///
  /// A separate token rather than another `TRange` because the parser turns it
  /// into the same `ERange` node but says out loud that the INCLUSIVE end is
  /// not analysed. Reusing `TRange` would make the two indistinguishable in the
  /// tree, and the difference between iterating `n` and `n+1` times is not
  /// something to lose silently.
  TRangeIncl
  /// `>..` — the DESCENDING range operator, three characters, one token.
  ///
  /// It is its own token rather than a `TGt` followed by two dots, because the
  /// parser reads `TGt` as a COMPARISON and `a>..b` would die in the comparison
  /// reader with "unexpected token `.`" -- which is the error the corpus file
  /// `async 0.22.4 src/fs/watch_windows.mbt:320` reported.
  ///
  /// There is NO inclusive descending spelling: `n>..=0` is REJECTed by the
  /// toolchain (`_verify/settle_0494_parse_backlog.ps1`, row `d5`), so this
  /// three-character form is the whole of it.
  TRangeDesc
  /// `<|` — the PIPE operator. One token, because two tokens is what the corpus
  /// trips over: `f <| x` lexed as `f`, `<`, `|`, `x` and the parser then reported
  /// the `|` -- "unexpected token `|`", 22 sites, a message that names neither the
  /// operator nor the problem.
  ///
  /// DIRECTIONAL, and measured rather than assumed
  /// (`_verify/settle_0464_pipe_operators.ps1`, 14/14): `f <| x` is `f(x)` and
  /// ACCEPTs, while `x <| f` is REJECT(4101). A single token that accepted both
  /// readings would accept code the toolchain refuses, and one that guessed the
  /// other direction would bind every corpus line backwards.
  TPipeLt
  /// `|>` — the MIRROR of `<|`, and deliberately its own token rather than a flag
  /// on `TPipeLt`. Same settle: `x |> f` ACCEPTs, `f |> x` is REJECT(4101).
  ///
  /// Keeping them distinct is what lets the parser say which reading it took, and
  /// therefore report `unexpected token` honestly when neither applies.
  TPipeGt
  /// `<+` — a StringBuilder/Array APPEND, three characters including the `+`.
  ///
  /// It is NOT "pipe or append", which is what this was assumed to be on the first
  /// pass, and it is NOT String concatenation: `"a" <+ "b"` is REJECT(4015) while
  /// `sb <+ "b"` is ACCEPT. Both readings came from the symbol's shape and both
  /// were wrong; the corpus line `logger <+ "\{k}: \{v}\n"` is a string BUILD.
  TAppendPlus
  TLParen
  TRParen
  TLBrace
  TRBrace
  TLBracket
  TRBracket
  TComma
  TColon
  TArrow
  TDot
  TSemi
  TNewline
  TEOF
} derive(Eq)

///|
priv struct Lexer {
  chars : Array[Char]
  mut pos : Int32
  mut line : Int32
  mut col : Int32
  toks : Array[Tok]
  spans : Array[@core.Span]
  reports : Array[@report.Report]
  /// Names referenced by `\{...}` interpolations of the string literal being
  /// lexed RIGHT NOW. Reset per string; handed to that string's `TStr`.
  mut interp_names : Array[String]
}

///|
pub fn lex(
  src : String,
) -> (Array[Tok], Array[@core.Span], Array[@report.Report]) {
  let lx = Lexer::{
    chars: [],
    pos: 0,
    line: 1,
    col: 1,
    toks: [],
    spans: [],
    reports: [],
    interp_names: [],
  }
  for c in src {
    lx.chars.push(c)
  }
  lx.run()
  lx.toks.push(TEOF)
  lx.spans.push(@core.span_at(lx.line, lx.col, 0))
  (lx.toks, lx.spans, lx.reports)
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// Newline suppression: after openers,
/// binary operators, assignment and arrows an expression continues across
/// lines; after `}` it does not.
///
/// `TBar` belongs in this set because `|` is the BITWISE-OR operator as well as the
/// or-pattern separator, and the operator reading is the one that reaches the parser
/// (`parse_bitor`, parser.mbt:3134). Its absence was not visible as long as every
/// `|` in the corpus sat on one line: `+`, `&` and `||` were all listed here, so
/// `a +\n b` and `a &\n b` parsed and only `a |\n b` failed. Measured in
/// `_verify/settle_0455_paren_if.ps1`, which also pins that the or-pattern role is
/// unaffected -- suppression drops the `TNewline` TOKEN, `TBar` itself still reaches
/// the stream, and match bodies are skipped whole so no pattern parser can be
/// confused by the missing line break.
///
/// `TAppendPlus` joined the set in 0488, and the settle is what says it belongs here AND what
/// says nothing else does. `_verify/settle_0488_append_nextline.ps1`, 16 rows / 4 controls:
///
///     ACCEPT      sb <+ NEWLINE "x"      <- the corpus shape, at TWO sites
///     REJECT 4139 a NEWLINE + b
///     REJECT 4139 a NEWLINE - b
///     REJECT 4139 a NEWLINE * b
///     REJECT 4139 a NEWLINE == b
///
/// => THE BREAK IS LEGAL *AFTER* THE OPERATOR AND NOT BEFORE IT, and this function looks only at
/// the PRECEDING token -- so listing `TAppendPlus` grants `a +\n b` and leaves `a\n + b` refused.
/// That is why the fix is one line rather than a general "continue across line breaks" rule: this
/// reader's `first_error 3` on `a\n + b` was CORRECT, and a general rule would have made it accept
/// four programs the toolchain rejects. The measured corpus reach is what argued against it.
fn newline_suppressed_after(prev : Tok) -> Bool {
  match prev {
    TPlus
    | TMinus
    | TStar
    | TSlash
    | TPercent
    | TAssign
    | TEqEq
    | TNe
    | TLt
    | TLe
    | TGt
    | TGe
    | TAndAnd
    | TOrOr
    | TAmp
    | TCaret
    | TShl
    | TShr
    | TBar
    | TBang
    | TComma
    | TColon
    | TArrow
    | TDot
    | TRange
    | TLParen
    | TLBracket
    | TLBrace
    | TAppendPlus
    | TSemi => true
    _ => false
  }
}

///|
/// A newline directly before a closing `)` or `]` is not a statement
/// separator — it is the tail of a multi-line parenthesised expression or
/// list (`(\n  a == 1 ||\n  a == 2\n)`). The lexer scans past whitespace and
/// line comments from the newline; when the first significant character
/// closes a group, the newline is dropped. Without this the analyzer's own
/// moonfiles.mbt died at the newline before the `)` of its
/// prev_is_cmp group, and every call/list written one-argument-per-line
/// with the closer on its own line would die the same way. A `)`/`]` can
/// only ever close the group the current expression is inside, so no
/// well-formed statement boundary is lost to this suppression.
fn closer_ahead(chars : Array[Char], start : Int32) -> Bool {
  let n = chars.length()
  let mut i = start
  let mut scanning = true
  while scanning {
    while i < n &&
          (
            chars[i] == ' ' ||
            chars[i] == '\t' ||
            chars[i] == '\r' ||
            chars[i] == '\n'
          ) {
      i += 1
    }
    if i + 1 < n && chars[i] == '/' && chars[i + 1] == '/' {
      while i < n && chars[i] != '\n' {
        i += 1
      }
    } else {
      scanning = false
    }
  }
  i < n && (chars[i] == ')' || chars[i] == ']')
}

///|
fn Lexer::emit(
  self : Lexer,
  t : Tok,
  line : Int32,
  col : Int32,
  len : Int32,
) -> Unit {
  self.toks.push(t)
  self.spans.push(@core.span_at(line, col, len))
}

///|
fn Lexer::run(self : Lexer) -> Unit {
  let mut last : Tok = TSemi
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    // 0479 -- U+FEFF, the BYTE-ORDER MARK, is skipped here beside the other characters that
    // separate tokens. It reached `lex_op`'s catch-all before and came back as "unexpected
    // character '<U+FEFF>'", refusing a file the toolchain accepts.
    //
    // This is NOT a "strip a three-byte preamble" change, and the settle row that decided it
    // is S4. `moon check` ACCEPTS a mark at offset 0, before a declaration, before a `///|`,
    // on an empty file, and -- the discriminator -- MIDFILE, where `1 <mark> + 2` is simply
    // `1 + 2`. A preamble-only fix would have passed the corpus file and failed the corpus
    // it was written for. A sweep of every `.mbt` under `.repos` finds exactly one file that
    // starts with one, `riantr/moonbit_labeler/0.2.13/app_moui/labeler_ui_test.mbt`, and a
    // refusal of valid code is never coverage and always wrong -- one file is a reason to fix
    // it rather than to skip it.
    //
    // STRING CONTENTS ARE UNAFFECTED, and not by luck: `run` dispatches to `lex_string` when
    // it sees `"`, and that reader consumes the whole literal, so a mark inside one is never
    // offered to this branch. S5 is satisfied by where the skip lives rather than by a second
    // guard, and a second guard would be a way to change a string's value by accident.
    if c == ' ' || c == '\t' || c == '\r' || c == '\u{FEFF}' {
      self.pos += 1
      self.col += 1
      continue
    }
    if c == '/' &&
      self.pos + 1 < self.chars.length() &&
      self.chars[self.pos + 1] == '/' {
      while self.pos < self.chars.length() && self.chars[self.pos] != '\n' {
        self.pos += 1
        self.col += 1
      }
      continue
    }
    if c == '\n' {
      self.pos += 1
      self.line += 1
      self.col = 1
      if !newline_suppressed_after(last) && !closer_ahead(self.chars, self.pos) {
        self.emit(TNewline, self.line - 1, 1, 1)
        last = TNewline
      }
      continue
    }
    if is_digit(c) {
      last = self.lex_number()
      continue
    }
    if c == '"' {
      last = self.lex_string()
      continue
    }
    if c == '\'' {
      // A character literal, lexed to a TStr. Before this branch existed the
      // quote fell to lex_op's catch-all, which reported "unexpected character"
      // and emitted TBang — so every file containing `'\n'` stopped there.
      last = self.lex_char(false)
      continue
    }
    if c == '#' &&
      self.pos + 1 < self.chars.length() &&
      self.chars[self.pos + 1] == '|' {
      // A `#| ... #|` block string is a STRING LITERAL, not code. Without this
      // branch its contents were lexed as ordinary tokens, so a bare `%` inside
      // prose became a binary operator with no right operand, and the compiler's
      // own divide-by-zero guard in Interp.binop panicked — killing the whole
      // scan. Found by reducing a real crash in moonbitlang/async's test files.
      last = self.lex_block_string()
      continue
    }
    if c == '$' &&
      self.pos + 1 < self.chars.length() &&
      self.chars[self.pos + 1] == '|' {
      // A `$|...` template string is a STRING LITERAL, not code, and it is a
      // GENERAL one -- settled in `_verify/settle_0488_append_nextline.ps1` that `let x = $|<a>`
      // and `a + $|<b>` both ACCEPT, so this is not a slot only `<+` can fill. Without this
      // branch the `$` fell to lex_op's catch-all and reported "unexpected character", which is
      // what made moonbitlang/async `examples/http_file_server/main.mbt` read ZERO lines.
      last = self.lex_template_string()
      continue
    }
    // An attribute (`#cfg(...)`, `#borrow(...)`, `#[derive(...)]`, `#deprecated`).
    // Not a block string: `#` is only a block-string opener when `|` follows it.
    if c == '#' && self.pos + 1 < self.chars.length() {
      let nx = self.chars[self.pos + 1]
      if nx == '[' || is_letter(nx) {
        self.lex_attribute()
        continue
      }
    }
    // A byte literal `b"\x00"` / `b'\x00'`. Real MoonBit, and 878 of the
    // double-quoted form appear in wzzc-dev/moui 0.1.12 across 134 files. Without
    // this branch the `b` lexed as an identifier and the string after it became a
    // second atom, so the pair hit `parse_atom`'s catch-all and ended the file at
    // `views/date_picker_control.mbt:40` (`if bytes == b"\x00"`).
    //
    // 0459 -- the SINGLE-QUOTED form is a different construct, not a spelling of
    // this one: `b"\x00"` is a `Bytes` string while `b'\x00'` is a single `Byte`
    // (settled, `_verify/settle_0459_literal_escapes.ps1`: `b'\x00'` accepts
    // against a `-> Byte` annotation and `b'ab'` is REJECT(3001)). 58 files write
    // the single-quoted form and every one of them stopped at
    // "character literal must hold exactly one character", because `b` lexed as
    // a name and `'\x00'` then became a character literal four characters long.
    //
    // So the two forms take DIFFERENT readers: `lex_string` for the double-quoted
    // Bytes, and `lex_char` for the single-quoted Byte -- which is exactly the
    // reader whose length check rejects `b'ab'` the way the toolchain does.
    //
    // The test is the character AFTER the `b`, so an identifier that merely
    // starts with `b` — `box`, `b2` — still lexes as one name.
    if c == 'b' &&
      self.pos + 1 < self.chars.length() &&
      (self.chars[self.pos + 1] == '"' || self.chars[self.pos + 1] == '\'') {
      let quoted = self.chars[self.pos + 1] == '"'
      self.pos += 1
      self.col += 1
      if quoted {
        last = self.lex_string()
      } else {
        last = self.lex_char(true)
      }
      continue
    }
    if is_letter(c) || c == '@' {
      // '@' starts a package alias token ("@q") so `.mbtx` import blocks lex
      let (t, l, cl, len) = self.lex_name()
      // THE REGEX LITERAL, `re"..."`. The prefix is the WHOLE identifier `re`,
      // so `re` on its own stays an ordinary name -- the toolchain REJECTs it
      // used as a value (`_verify/settle_0494_parse_backlog.ps1`, row `a7`) --
      // and the quote must follow it with nothing between.
      if t == TName("re") &&
        self.pos < self.chars.length() &&
        self.chars[self.pos] == '"' {
        last = self.lex_regex(l, cl)
        continue
      }
      last = t
      self.emit(t, l, cl, len)
      continue
    }
    last = self.lex_op()
  }
}

///|
/// An attribute: `#cfg(target="native")`, `#borrow(a, b)`, `#[derive(Eq)]`, a
/// bare `#deprecated`, or several in a row. Consumed whole, no token emitted.
///
/// Discarded rather than parsed because an attribute decides what the
/// toolchain COMPILES, not what the code inside means, and every declaration
/// form an attribute can precede is one this frontend skips anyway. The one
/// fidelity cost is real and worth stating: `#cfg` can hide a declaration from
/// the build for a given target, and dropping the attribute means that
/// declaration is still analyzed. Recorded here rather than papered over.
fn Lexer::lex_attribute(self : Lexer) -> Unit {
  let n = self.chars.length()
  // `#`
  self.pos += 1
  self.col += 1
  // the attribute name, when it is not `#[...]`
  while self.pos < n &&
        (is_letter(self.chars[self.pos]) || is_digit(self.chars[self.pos])) {
    self.pos += 1
    self.col += 1
  }
  // then any number of `[...]` / `(...)` argument groups, in either order
  while self.pos < n {
    let open = self.chars[self.pos]
    if open != '[' && open != '(' {
      break
    }
    let close = if open == '[' { ']' } else { ')' }
    let mut depth = 0
    while self.pos < n {
      let c = self.chars[self.pos]
      if c == '\n' {
        self.line += 1
        self.col = 1
      } else {
        self.col += 1
      }
      self.pos += 1
      if c == open {
        depth += 1
      } else if c == close {
        depth -= 1
        if depth <= 0 {
          break
        }
      }
    }
  }
}

///|
/// The largest integer literal this analyzer will give a VALUE to.
///
/// Fixed on purpose rather than taken from the target's `Int`: `Int` is 32-bit
/// on wasm and 64-bit on js/native, so a bound derived from it would make the
/// same source analyse differently on different backends, and this tool's
/// findings are consumed by a program that compares them. A literal past this
/// bound still lexes, still parses and still types as an integer — it just
/// carries no value, which is what stops `const_eval` from folding a dead
/// branch on a number it could not read. See `TBigInt`.
let lit_max : Int32 = 2147483647

///|
/// `acc * base + d`, or `ok = false` rather than a wrapped answer.
///
/// The overflow check happens BEFORE the arithmetic, so nothing is ever
/// computed in the first place. That matters because `Int` is 32-bit on wasm:
/// a plain `acc * 16 + 15` on `0xFFFFFFFF` would trap the whole scan instead of
/// degrading to "no value".
fn lit_step(acc : Int32, base : Int32, d : Int32) -> (Int32, Bool) {
  if acc > (lit_max - d) / base {
    (-1, false)
  } else {
    (acc * base + d, true)
  }
}

///|
/// Digit value for a base, or -1 when the character is not a digit of it.
fn digit_value(c : Char, base : Int32) -> Int32 {
  let mut v = -1
  let ci = c.to_int()
  if is_digit(c) {
    v = ci - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    v = ci - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    v = ci - 'A'.to_int() + 10
  }
  if v >= base {
    -1
  } else {
    v
  }
}

///|
/// One integer literal: an optional `0x` / `0b` / `0o` base prefix, digits with
/// optional `_` separators, and an optional `L` / `U` / `UL` suffix.
///
/// Which forms exist is measured, not assumed — each was compiled by this
/// toolchain before being written here:
///
///     0xFF   0x8000_0000   0b1010   0o17   1_000_000   0x1000L   1U   0xffffffffUL   all compile
///     1U as UInt64                                                                          does not
///
/// Before this, `0x7FF8...UL` lexed as the number `0` followed by the names
/// `x7FF8`, `000` and `L`, and each of those names was then reported as an
/// unbound binding. That is how 54 of the 55 false positives a scan of
/// moonbitlang/core gained from teaching the parser method calls came to exist:
/// the parse had moved past them and they were suddenly visible.
fn Lexer::lex_number(self : Lexer) -> Tok {
  let l = self.line
  let c0 = self.col
  let start = self.pos
  let n = self.chars.length()
  // Consume a base prefix only when a digit OF THAT BASE follows it. Without
  // that lookahead `0` followed by a variable named `x` would be read as a hex
  // literal and the variable would vanish.
  let mut base = 10
  let mut digits_from = self.pos
  if self.pos + 1 < n && self.chars[self.pos] == '0' {
    let p = self.chars[self.pos + 1]
    let b = if p == 'x' || p == 'X' {
      16
    } else if p == 'b' || p == 'B' {
      2
    } else if p == 'o' || p == 'O' {
      8
    } else {
      0
    }
    if b > 0 &&
      self.pos + 2 < n &&
      digit_value(self.chars[self.pos + 2], b) >= 0 {
      base = b
      digits_from = self.pos + 2
    }
  }
  self.pos = digits_from
  let mut value = 0
  let mut exact = true
  let mut any = false
  while self.pos < n {
    let c = self.chars[self.pos]
    if c == '_' {
      // A separator, not a digit. `0x_FF` is a leading separator and is
      // harmless; what it must never be is a reason to stop consuming.
      self.pos += 1
      self.col += 1
      continue
    }
    let d = digit_value(c, base)
    if d < 0 {
      break
    }
    any = true
    if exact {
      let (v, ok) = lit_step(value, base, d)
      if ok {
        value = v
      } else {
        exact = false
      }
    }
    self.pos += 1
    self.col += 1
  }
  // A fractional part makes this a float, and a float literal has no base.
  // Checked only when digits were actually consumed, so `0.foo` is not read as
  // a float.
  let mut is_float = false
  if any && base == 10 && self.pos < n && self.chars[self.pos] == '.' {
    let mut probe = self.pos + 1
    while probe < n && is_digit(self.chars[probe]) {
      probe += 1
    }
    // `1.to_string()` — a `.` that is NOT followed by a digit is field access,
    // not a decimal point.
    if probe > self.pos + 1 {
      is_float = true
      self.pos += 1
      self.col += 1
      while self.pos < n &&
            (is_digit(self.chars[self.pos]) || self.chars[self.pos] == '_') {
        self.pos += 1
        self.col += 1
      }
    }
  }
  // The exponent, which belongs to the literal for VALUES. It is only claimed
  // when digits actually follow the (optional) sign, because `1.0echo` is the
  // float `1.0` followed by the name `echo` — swallowing the `e` there would
  // invent a number the source does not contain. `1.0e-12` and `2e8` are
  // numbers; `x.e` never reaches here because the `.` was field access.
  if self.pos < n &&
    (self.chars[self.pos] == 'e' || self.chars[self.pos] == 'E') {
    let mut probe = self.pos + 1
    if probe < n && (self.chars[probe] == '+' || self.chars[probe] == '-') {
      probe += 1
    }
    let digits_at = probe
    while probe < n && is_digit(self.chars[probe]) {
      probe += 1
    }
    if probe > digits_at {
      is_float = true
      // Advance the column by exactly what was consumed, so a diagnostic after
      // the literal still points at the right character.
      self.col += probe - self.pos
      self.pos = probe
    }
  }
  // `0.0F` is a float32 literal. Only meaningful once the literal IS a float:
  // `7F` is a parse error in MoonBit (verified), so the suffix must not be
  // accepted on a bare integer, or `7F` would silently read as the number 7.
  if is_float && self.pos < n && self.chars[self.pos] == 'F' {
    self.pos += 1
    self.col += 1
  }
  // The slice bound is `self.pos`, NOT a bound captured before the fraction was
  // consumed. Slicing to the integer part alone made every float literal fold
  // to its truncated whole number (`1.5` -> 1, `0.25` -> 0), which is invisible
  // unless a test reads the VALUE rather than the token kind.
  let text = self.slice(start, self.pos)
  let len = self.pos - start
  if is_float {
    let f = parse_double(text)
    self.emit(TFloat(f), l, c0, len)
    TFloat(f)
  } else {
    // The suffix, only when the literal actually had digits. `L` is Int64,
    // `U` is UInt and `UL` is UInt64; the order matters because `UL` starts
    // with `U`.
    let mut suffixed = false
    if any && self.pos < n {
      let c = self.chars[self.pos]
      if c == 'U' {
        suffixed = true
        self.pos += 1
        self.col += 1
        if self.pos < n && self.chars[self.pos] == 'L' {
          self.pos += 1
          self.col += 1
        }
      } else if c == 'L' {
        suffixed = true
        self.pos += 1
        self.col += 1
      }
    }
    let total = self.pos - start
    if !exact || suffixed {
      // No value: either it did not fit, or it is a wider type this analyzer
      // does not model. `const_eval` sees TBigInt and refuses to fold, and the
      // type lens treats it as TUnknown so it never claims a mismatch it
      // cannot justify.
      self.emit(TBigInt, l, c0, total)
      TBigInt
    } else {
      self.emit(TInt(value), l, c0, total)
      TInt(value)
    }
  }
}

///|
fn Lexer::slice(self : Lexer, from : Int32, to : Int32) -> String {
  let buf = StringBuilder()
  let mut i = from
  while i < to {
    buf.write_char(self.chars[i])
    i += 1
  }
  buf.to_string()
}

///|
fn Lexer::lex_string(self : Lexer) -> Tok {
  let l = self.line
  let c0 = self.col
  self.pos += 1
  self.col += 1
  let buf = StringBuilder()
  // Names referenced by this literal's `\{...}` interpolations, collected by
  // copy_interp below. Reset here so a previous string's names cannot leak
  // into this one.
  self.interp_names = []
  while self.pos < self.chars.length() && self.chars[self.pos] != '"' {
    let c = self.chars[self.pos]
    if c == '\\' && self.pos + 1 < self.chars.length() {
      self.pos += 1
      self.col += 1
      let e = self.chars[self.pos]
      if e == '{' {
        // `\{expr}` — string interpolation. The body is consumed whole by
        // copy_interp, which counts brace depth and hands nested string /
        // character literals to their own whole-token copiers. That is what
        // stops a `"` INSIDE the interpolation (a `.join(" ")` argument —
        // the measured Class B deaths at sa/main.mbt:225 and
        // interp/interp.mbt:244) from ending the OUTER string early: the
        // old loop saw that quote as the closer and fed the rest of the
        // line to the token stream as code. The payload shape for the
        // simple form is unchanged: `\{x}` copies through as `{x}`,
        // exactly what the old escape-mapping loop produced.
        self.copy_interp(buf)
        continue
      }
      buf.write_char(
        match e {
          'n' => '\n'
          't' => '\t'
          'r' => '\r'
          other => other
        },
      )
    } else {
      buf.write_char(c)
    }
    self.pos += 1
    self.col += 1
  }
  if self.pos < self.chars.length() {
    self.pos += 1
    self.col += 1
  } else {
    self.reports.push(@report.Report::{
      family: @core.FParse,
      lenses: [@core.LStructural],
      message: "unterminated string literal",
      span: @core.span_at(l, c0, 1),
      vst: [],
    })
  }
  let s = buf.to_string()
  let names = self.interp_names
  self.interp_names = []
  self.emit(TStr(s, names), l, c0, self.col - c0)
  TStr(s, names)
}

///|
/// A REGEX LITERAL, `re"..."`. 0494.
///
/// The body is read RAW -- no escape table and no interpolation -- because a
/// regex body is not a MoonBit string: the escape meanings belong to the
/// string lexer, and a second table here would be claiming VALUES the analyzer
/// does not have. The one thing that IS handled is the escaped quote, so that
/// `\"` cannot end the literal early; the backslash and the character after it
/// are both carried.
///
/// The literal also STOPS at a newline, like a string: a regex that ran to the
/// end of the file would swallow every file after it, and "unterminated" is a
/// report the reader can make honestly.
///
/// The pattern TEXT is carried, not analysed. The lenses treat the literal as a
/// leaf of unknown type, because this model has no Regex type -- and the
/// honest answer for a type it cannot name is "unknown", not "String".
fn Lexer::lex_regex(self : Lexer, start_line : Int32, start_col : Int32) -> Tok {
  self.pos += 1 // the opening quote
  self.col += 1
  let buf = StringBuilder()
  let mut terminated = false
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    if c == '\\' && self.pos + 1 < self.chars.length() {
      buf.write_char(c)
      buf.write_char(self.chars[self.pos + 1])
      self.pos += 2
      self.col += 2
      continue
    }
    if c == '"' {
      self.pos += 1
      self.col += 1
      terminated = true
      break
    }
    if c == '\n' {
      break
    }
    buf.write_char(c)
    self.pos += 1
    self.col += 1
  }
  if !terminated {
    self.reports.push(@report.Report::{
      family: @core.FParse,
      lenses: [@core.LStructural],
      message: "unterminated regex literal",
      span: @core.span_at(start_line, start_col, 1),
      vst: [],
    })
  }
  let s = buf.to_string()
  self.emit(TRegex(s), start_line, start_col, self.col - start_col)
  TRegex(s)
}

///|
/// A TEMPLATE STRING, `$|...`, lexed as `TStr`. 0488.
///
/// Settled in `_verify/settle_0488_append_nextline.ps1` (16 rows / 4 controls, GATE OK) to be a
/// GENERAL EXPRESSION rather than a slot only `<+` can fill:
///
///     ACCEPT      let x = $|<a>             <- bare, so it belongs to the expression grammar
///     ACCEPT      a + $|<b>                 <- and is an operand of an ordinary operator too
///     ACCEPT      sb <+ $|<h1>\{name}</h1>   <- and it is the operand `<+` asks for
///     ACCEPT      sb <+ $|                  <- empty is legal
///     REJECT 3002 let x = $| NEWLINE <a> NEWLINE $|</a>   <- ONE interpolant does NOT span lines
///
/// That last row is why this stops at the newline: the corpus writes SEVERAL one-line `$|` lines
/// joined by a single `<+`, so a multi-line reading would swallow the rest of the file.
///
/// THE BODY IS COPIED RAW, and only `\{` is treated structurally. Every other character --
/// including a backslash that does not open an interpolation -- is content. Nothing here
/// interprets `\n` or any other escape, because that was NOT settled, and inventing an escape
/// table is how a reader starts claiming string VALUES it cannot justify. The one thing that IS
/// claimed is the same thing `lex_string` claims: the names referenced inside `\{...}`, as READS.
fn Lexer::lex_template_string(self : Lexer) -> Tok {
  let l = self.line
  let c0 = self.col
  // Step past the opening `$|`, which is NOT part of the payload.
  self.pos += 2
  self.col += 2
  let buf = StringBuilder()
  self.interp_names = []
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    if c == '\n' {
      // Leave it for run(): it still has to advance the line, and it separates this
      // statement from the next one. An UNTERMINATED `$|` is therefore not a report here --
      // an empty one is legal (settle row C4), so there is no "missing closer" to complain about.
      break
    }
    if c == '\\' &&
      self.pos + 1 < self.chars.length() &&
      self.chars[self.pos + 1] == '{' {
      // Same contract as `lex_string`: step onto the `{` and hand it to copy_interp, which
      // returns just past the matching `}`. The `continue` is load-bearing -- it skips this
      // loop's own `pos += 1`, which would otherwise step one character past the body.
      self.pos += 1
      self.col += 1
      self.copy_interp(buf)
      continue
    }
    buf.write_char(c)
    self.pos += 1
    self.col += 1
  }
  let s = buf.to_string()
  let names = self.interp_names
  self.interp_names = []
  self.emit(TStr(s, names), l, c0, self.col - c0)
  TStr(s, names)
}

///|
/// Consume one `\{ ... }` interpolation body, copying it RAW into the string
/// payload. Called with `pos` ON the opening `{`; returns with `pos` just
/// past the matching `}`, which the caller's own loop consumes from there.
/// Depth counting treats every `{`/`}` at interpolation level as a brace —
/// including the `{` of a nested `\{` — while a `"` or `'` hands off to
/// copy_nested_string / copy_nested_char, so the quotes and braces INSIDE a
/// nested literal are string content, not structure, and never touch the
/// depth counter. EOF falls out of the loop; the OUTER string's own
/// unterminated report covers it.
///
/// Every identifier at interpolation level is recorded in `interp_names` as a
/// READ (see `TStr`). Only the outermost level is scanned: a nested `\{...}`
/// belongs to the nested string literal, which records its own names — and
/// that nested literal is not emitted as a token, so its names would
/// otherwise be lost entirely. Members after a `.` are not bindings and are
/// skipped by the same rule the expression walker uses, so `\{m.length()}`
/// records `m` and not `length`.
///
/// This is a name-level read, not a parse: the body is never modelled as an
/// expression, so `\{a + b}` records both names and makes no claim about the
/// addition.

///|
fn Lexer::copy_interp(self : Lexer, buf : StringBuilder) -> Unit {
  let mut depth = 0
  // The identifier being read at this level, if any. Names are recorded when
  // the identifier ENDS, which is what keeps `m.length` from being recorded
  // as one name `mlength` — and, separately, keeps `length` from being
  // recorded at all, since a member of a path is not a binding.
  let mut cur = ""
  // True when the identifier currently being read directly follows a `.`.
  let mut cur_is_member = false
  // True immediately after a `.`, before the member name starts.
  let mut after_dot = false
  // True immediately after an `@`, before the alias name starts.
  let mut after_at = false
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    buf.write_char(c)
    self.pos += 1
    self.col += 1
    if c == '{' {
      depth += 1
    } else if c == '}' {
      depth -= 1
      if depth == 0 {
        self.flush_interp_name(cur, cur_is_member, after_at)
        return
      }
    } else if c == '"' {
      self.flush_interp_name(cur, cur_is_member, after_at)
      cur = ""
      self.copy_nested_string(buf)
    } else if c == '\'' {
      self.flush_interp_name(cur, cur_is_member, after_at)
      cur = ""
      self.copy_nested_char(buf)
    } else if c == '@' {
      // An `@`-prefixed name is an IMPORT ALIAS, not a binding in this file —
      // `@core`, `@sm`, `@multi`. The walker already refuses to resolve those
      // (`!name.has_prefix("@")`), but that guard cannot help here: `@` is not
      // an identifier character, so without this branch the scan records the
      // alias WITHOUT its `@` and the guard sees an ordinary bare name.
      // Measured on riantr/pyroduct 0.1.29: 6 `no visible binding for 'sm'` /
      // `'multi'` findings on `\{@sm.all_states()}`, manufactured by the
      // interpolation support itself.
      self.flush_interp_name(cur, cur_is_member, after_at)
      cur = ""
      after_at = true
    } else if is_ident_char(c) && !(is_digit(c) && cur == "") {
      // A number is a literal, never a binding: an identifier may CONTINUE
      // with a digit (`xs0`) but cannot START with one. This was written the
      // other way first, and the next self-scan reported
      // `no visible binding for '1'` and `'no visible binding for '10''` on
      // `\{i + 1}` and `\{pct / 10}` in this repo's own source — a fix for
      // false positives that manufactured two of its own. Only the rescan
      // over real code found them.
      if cur == "" {
        cur_is_member = after_dot
        after_dot = false
      }
      cur = cur + Char::to_string(c)
    } else if c == '.' {
      // `a.b.c`: `a` is the binding and every later head is a member, so
      // flush the identifier that just ended with ITS OWN member flag —
      // `a` records, `b` does not — then mark the next one as a member.
      self.flush_interp_name(cur, cur_is_member, after_at)
      cur = ""
      cur_is_member = false
      after_dot = true
    } else if c == '=' &&
      self.pos < self.chars.length() &&
      self.chars[self.pos] != '=' &&
      self.chars[self.pos] != '>' {
      // A LABEL, NOT A READ. 0488. `\{value.to_string(radix=16)}` supplies 16 to the
      // parameter named `radix` -- MoonBit's labelled-argument call syntax, the
      // counterpart of the `protocol~ : Protocol` declaration this same corpus writes
      // at `http/request.mbt:56`. Nothing named `radix` is ever bound there, and the
      // identifier was being flushed by the generic `else` below exactly as if it were.
      //
      // WHAT IT COST: `no visible binding for 'radix'` at moonbitlang/async
      // `src/socket/addr_utils.mbt:291`. That finding sat WITHHELD for as long as the
      // file stopped at line 297 -- findings on a partial file are withheld, not
      // reported -- and became ACTIONABLE the moment 0488 read the file whole. So the
      // inventory hid a real false positive, and shipping the increment without
      // fixing it would have pinned `actionable=1` as though the finding were correct.
      //
      // THE `==` AND `=>` CARVE-OUTS ARE SETTLED, NOT GUESSED --
      // `_verify/settle_0488_append_nextline.ps1` rows F3 and F4: `\{a == b}` must
      // still record both names, and `\{xs.map(x => x + 1).length()}` must still
      // record `x`. Only a BARE `=` names a label. `self.pos` already points PAST
      // this `=`, so the lookahead sees the character after it.
      cur = ""
    } else {
      self.flush_interp_name(cur, cur_is_member, after_at)
      cur = ""
    }
  }
  self.flush_interp_name(cur, cur_is_member, after_at)
}

///|
/// Record one interpolation-level identifier, unless it is a member of a path,
/// an import alias, or a keyword.
///

///|
fn Lexer::flush_interp_name(
  self : Lexer,
  name : String,
  is_member : Bool,
  is_alias : Bool,
) -> Unit {
  if name == "" || is_member || is_alias {
    return
  }
  if is_moonbit_keyword(name) {
    return
  }
  if !self.interp_names.contains(name) {
    self.interp_names.push(name)
  }
}

///|
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// The words that are language syntax rather than bindings. A `\{...}` body is
/// expression context, so these can appear in one and none of them is a name
/// to resolve. `true` / `false` matter here: they arrive as ordinary
/// identifiers to the lexer and would otherwise be reported as unbound.

///|
pub fn is_moonbit_keyword(s : String) -> Bool {
  match s {
    "if"
    | "else"
    | "match"
    | "fn"
    | "let"
    | "return"
    | "while"
    | "for"
    | "break"
    | "continue"
    | "true"
    | "false"
    | "try"
    | "catch"
    | "finally"
    | "struct"
    | "enum"
    | "trait"
    | "impl"
    | "derive"
    | "test"
    | "type"
    | "const"
    | "suberror"
    | "extern"
    | "pub"
    | "priv"
    | "as"
    | "in"
    | "mut"
    | "and"
    | "or"
    | "new"
    | "init" => true
    // NOT `self`. `self` is a CONVENTIONAL PARAMETER NAME in MoonBit, not a
    // keyword: `pub fn Slot::qualified(self : Slot) -> String` binds it like
    // any other name. Listing it here meant `\{self.designation()}` recorded
    // no read, so a parameter read ONLY inside an interpolation was reported
    // as never used — measured on riantr/pyroduct 0.1.29 at `src/slot.mbt`
    // 127:24 (`parameter 'self' may not be used`, on a file `moon check`
    // accepts). The same read outside an interpolation was already silent,
    // so this was the interpolation path alone disagreeing with itself.
    //
    // It entered this list in 0.4.8 alongside interpolation tracking, as a
    // guess that `self` was syntax; nothing had been measured. Removing it
    // cannot invent an undefined-name finding here, because a `self` with no
    // binding is reported as such by the frame lookup — which is the correct
    // outcome, and is what already happens outside an interpolation.
    _ => false
  }
}

///|
/// The inside of an interpolation is expression context, so a `"` there
/// opens a real string literal. The OPENING quote was already written and
/// stepped past by copy_interp's dispatch, so this walks the content and
/// copies it raw, honouring `\` escapes (an escaped quote must not end the
/// literal) and returning just past the closing quote, which it writes.
fn Lexer::copy_nested_string(self : Lexer, buf : StringBuilder) -> Unit {
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    buf.write_char(c)
    self.pos += 1
    self.col += 1
    if c == '\\' {
      if self.pos < self.chars.length() {
        buf.write_char(self.chars[self.pos])
        self.pos += 1
        self.col += 1
      }
    } else if c == '"' {
      return
    }
  }
}

///|
/// Character-literal counterpart of copy_nested_string: the opening `'` was
/// consumed by copy_interp, this copies content plus escapes and returns
/// past the closing `'` — so `c == '\''` inside an interpolation body
/// copies whole instead of stranding the handler on a stray quote.
fn Lexer::copy_nested_char(self : Lexer, buf : StringBuilder) -> Unit {
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    buf.write_char(c)
    self.pos += 1
    self.col += 1
    if c == '\\' {
      if self.pos < self.chars.length() {
        buf.write_char(self.chars[self.pos])
        self.pos += 1
        self.col += 1
      }
    } else if c == '\'' {
      return
    }
  }
}

///|
/// The value of a hex digit, or -1 for anything else. Used by the `\xNN` and
/// `\u{...}` escapes in `lex_char`, where "stop at the first non-digit" is the
/// whole termination condition -- so the sentinel has to be distinguishable from
/// the digit `0`, which is why this returns -1 rather than 0.
///
/// `unsafe_to_char` rather than `to_char`: `b'\x00'` and `'\u{0}'` are NUL, and
/// `to_char` REJECTS a code point outside the printable range. Those are the
/// literals the corpus is full of, so the safe conversion cannot be the one that
/// runs here. The value is bounded by the digits actually consumed, and an escape
/// with no digits writes nothing at all.
fn hex_value(c : Char) -> Int32 {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
/// A character literal, `'x'`, lexed as `TStr(payload)`: the analyzer has no
/// separate character value, and since types come from annotations only, no
/// claim can be keyed off the difference.
///
/// The payload is an escape (`n`/`t`/`r` map, anything else maps to itself,
/// exactly like `lex_string`) or the characters up to the closing quote.
/// Unterminated input (EOF or a newline) is reported and the newline is NOT
/// consumed, so `run()` keeps counting lines correctly. A closed literal
/// whose payload is not exactly one character is also reported, but the
/// payload is still emitted: a report alone would leave the file's remaining
/// code to be swallowed by the next quote.
fn Lexer::lex_char(self : Lexer, byte_form : Bool) -> Tok {
  let l = self.line
  let c0 = self.col
  self.pos += 1
  self.col += 1
  let buf = StringBuilder()
  let mut terminated = false
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    if c == '\n' {
      // Leave the newline for run(): it still has to advance the line.
      break
    }
    if c == '\'' {
      self.pos += 1
      self.col += 1
      terminated = true
      break
    }
    if c == '\\' && self.pos + 1 < self.chars.length() {
      self.pos += 1
      self.col += 1
      let e = self.chars[self.pos]
      // 0459 -- `\xNN` and `\u{...}` produce ONE character from several source
      // characters. Every other escape passed through as `other => other`, so
      // `\x00` became the three-character payload `x00` and `'\u{0}'` became
      // `u{0}`; both then failed the "must hold exactly one character" check
      // below. 58 files corpus-wide write `b'\x..'` and 19 write `'\u{..}'`.
      //
      // Settled before implementing (`_verify/settle_0459_literal_escapes.ps1`,
      // 8/8): both are legal MoonBit, `'\u{1F600}'` is as legal as `'\u{0}'` so
      // the brace form is NOT "two hex digits", and `b'ab'` is REJECT(3001) so the
      // one-character rule still has teeth.
      // 0480 -- AND THE UNBRACED SPELLING, `'\uXXXX'`. 0459's guard required `\u` to be
      // followed by `{`, so `'\u007f'` fell through to `other => other`, which wrote the
      // letter `u`, and the four hex digits were then appended by the ordinary character
      // path. The payload became `u007f` -- five characters -- and the length check refused
      // it with "character literal must hold exactly one character". A FALSE refusal: the
      // corpus writes this form and the compiler accepts it.
      //
      // This is not one file. `moonbitlang/core` `builtin/char.mbt` writes it about a
      // hundred and fifty times and `char/predicate_reference_test.mbt` as many again, and
      // two PINNED corpora are blocked by it -- proton `internal/native/configuration.mbt:4`
      // (`'\u007f'`) and moonbit_labeler `extensions/labeler/labeler.mbt:2741` (`'\u000C'`).
      // The standard library's own source uses the spelling, so this is a grammar clause.
      //
      // EXACTLY FOUR DIGITS, and the settle is what says so
      // (`_verify/settle_0480_unbraced_unicode_escape.ps1`, 3 controls + 6 rows):
      //   ACCEPT           `'\u007f'`  the proton shape        ACCEPT  `'\u000C'`  labeler
      //   ACCEPT           `'\u{1F600}'`  the braced form, which has no unbraced spelling
      //   REJECT(3001)     `'\u07f'`     three digits          REJECT(3001)  `'\u01F600'`
      //   REJECT(3001)     `'\u00007f'`   six digits, BMP value
      //   REJECT(3001)     `b'\u000C'`   a BYTE literal takes `b'\xNN'`, not this
      //
      // The fifth-character test is what makes six digits refuse rather than truncate:
      // `'\u00007f'` must not lex as `'\u0000'` followed by the literal text `7f`. Both
      // readings refuse it -- one character or seven -- so the choice is about which
      // refusal, and requiring a NON-HEX follower keeps the digit count honest. The settle
      // carries the same six digits with an ASTRAL value too (`'\u01F600'`); it is in the
      // settle and not in the test because a test on an astral fixture measures how the
      // string builder counts astral characters, which is 0459's trap written down and
      // repeated once. See `lexer_0480_test.mbt`.
      let braced_u = e == 'u' &&
        self.pos + 1 < self.chars.length() &&
        self.chars[self.pos + 1] == '{'
      // The UNBRACED spelling is a CHARACTER literal escape and not a BYTE one. The byte
      // branch above routes `b'...'` into this same reader, so without the context flag a
      // guard widened here would silently widen it there as well -- and the toolchain
      // disagrees: `b'\x0C'` ACCEPTs and `b'\u000C'` is REJECT(3001), measured, while
      // `'\u000C'` ACCEPTs. Two literals, one reader, one flag.
      let bare_u = !byte_form &&
        e == 'u' &&
        self.pos + 5 < self.chars.length() &&
        hex_value(self.chars[self.pos + 1]) >= 0 &&
        hex_value(self.chars[self.pos + 2]) >= 0 &&
        hex_value(self.chars[self.pos + 3]) >= 0 &&
        hex_value(self.chars[self.pos + 4]) >= 0 &&
        hex_value(self.chars[self.pos + 5]) < 0
      if e == 'x' || braced_u || bare_u {
        // NOT `e == 'u'`: that was true for the unbraced form too, and this branch
        // consumes a `{` when it is set. 0459 got away with it because the `u` arm was
        // only reachable when a brace actually followed.
        let braced = braced_u
        if braced {
          self.pos += 1
          self.col += 1
        }
        let mut v = 0
        let mut digits = 0
        while self.pos + 1 < self.chars.length() {
          let h = hex_value(self.chars[self.pos + 1])
          if h < 0 {
            break
          }
          self.pos += 1
          self.col += 1
          v = v * 16 + h
          digits += 1
        }
        if braced &&
          self.pos + 1 < self.chars.length() &&
          self.chars[self.pos + 1] == '}' {
          self.pos += 1
          self.col += 1
        }
        // A malformed escape writes nothing rather than the source characters:
        // falling through to `other => other` is what turned one escape into a
        // three-character payload in the first place, and the payload is now
        // checked for length. Digits are still consumed so a bad escape does not
        // leak its characters into the literal as a second payload.
        if digits > 0 {
          buf.write_char(v.unsafe_to_char())
        }
      } else {
        buf.write_char(
          match e {
            'n' => '\n'
            't' => '\t'
            'r' => '\r'
            other => other
          },
        )
      }
    } else {
      buf.write_char(c)
    }
    self.pos += 1
    self.col += 1
  }
  let s = buf.to_string()
  if !terminated {
    self.reports.push(@report.Report::{
      family: @core.FParse,
      lenses: [@core.LStructural],
      message: "unterminated character literal",
      span: @core.span_at(l, c0, 1),
      vst: [],
    })
  } else if s.length() != 1 {
    self.reports.push(@report.Report::{
      family: @core.FParse,
      lenses: [@core.LStructural],
      message: "character literal must hold exactly one character",
      span: @core.span_at(l, c0, self.col - c0),
      vst: [],
    })
  }
  self.emit(TStr(s, []), l, c0, self.col - c0)
  TStr(s, [])
}

///|
/// A block string. `#|` opens it; the string ends at the next LINE-LEADING `#|`
/// **whose rest of line is blank**, and that closer contributes an empty final
/// segment. Measured against the toolchain by VALUE, in
/// `_verify/settle_0446_block_string.ps1`:
///
///   #|abc / #|def            -> "abc def"        `#|def` is CONTENT
///   #|abc / #|def / #|       -> "abc def "       the bare `#|` closes
///   #|AAA / #|BBB trailing   -> "AAA BBB trailing "   also content
///   #|abc / #|   (blanks)    -> "abc "           trailing blanks are blank
///   #|one #|two / #|         -> "one #|two "     a mid-line `#|` is content
///   no closer at all         -> ends at EOF, no trailing space
///
/// So each line-leading `#|` is a SEGMENT: the text after it, trimmed, joined to
/// its neighbours by a single SPACE. Newlines are not in the value.
///
/// THIS HEADER USED TO STATE THE OPPOSITE, and the old claim is recorded here
/// rather than deleted, because "a reason string is not a reason" has cost this
/// repository several rankings in a row. It claimed the closer is "a `#|` with
/// only whitespace BEFORE it on its line", and listed `#|AAA\n#|BBB trailing ->
/// "AAA\nBBB trailing"` among its measurements. Under that rule `#|BBB trailing`
/// is the closer. It is not: the value above shows it contributing a segment,
/// and the string carrying on to the next line. The join is a space, not a
/// newline. That rule paired markers as opener/closer alternately.
///
/// WHAT THAT COST, and why it stayed invisible for so long: an ODD count of
/// `#|` lines ran to EOF and was reported "unterminated block string literal" --
/// a finding the toolchain does not make, on valid MoonBit. Four files across
/// the six corpora carried it. One of them, proton 0.3.4 `facade_types.mbt`,
/// writes its block string with content on every `#|` line, so the file was cut
/// at line 246 while the enum declaring `CookieWaiting` and `CookieCompleted`
/// sat at 589 -- and a file truncated past its declarations contributes nothing
/// to the cross-file symbol table, so the sibling that USES those names was told
/// they were undefined.
///
/// `moon check` accepts every shape of this construct, so "does the toolchain
/// accept the file" cannot settle any of it. Only the value can. That is the
/// whole reason this table exists and why a reader should be suspicious of any
/// future edit here that is justified by acceptance alone.
///
/// End of input also closes the block, as the toolchain's tolerance for an
/// unclosed one shows, and the file is still reported: whatever followed the
/// last `#|` was never lexed, so every span past it would be wrong.
///
/// Newlines inside the body advance the line counter (so every span after it
/// stays correct) but are NOT emitted as `TNewline` -- they are string contents,
/// not statement separators.
fn Lexer::lex_block_string(self : Lexer) -> Tok {
  let l = self.line
  let c0 = self.col
  // SEGMENTS, not one buffer. Each line-leading `#|` opens a segment; the value
  // is those segments trimmed and joined by a single space. Accumulating raw
  // characters cannot produce that, because the newline between two segments is
  // not in the value at all.
  let segs : Array[String] = []
  let mut cur = StringBuilder()
  let n = self.chars.length()
  // step past the opening `#|`, which opens the FIRST segment
  self.pos += 2
  self.col += 2
  let mut closed = false
  let mut ended_at_code = false
  let mut at_line_start = false
  while self.pos < n {
    let c = self.chars[self.pos]
    if c == '#' &&
      at_line_start &&
      self.pos + 1 < n &&
      self.chars[self.pos + 1] == '|' {
      // THE CLOSER, and requiring the REST OF ITS LINE TO BE BLANK is the whole
      // of 0.4.36. A `#|` with anything after it on the line is a CONTENT LINE,
      // not a closer.
      //
      // Settled by VALUE, not by whether `moon check` accepts the file -- every
      // shape of this construct is accepted, so acceptance measures nothing here.
      // `_verify/settle_0446_block_string.ps1` runs each shape and compares what
      // the toolchain actually produced:
      //
      //     #|abc / #|def            -> "abc def"     <- NO trailing space, so
      //                                                       `#|def` is content
      //     #|abc / #|def / #|       -> "abc def "    <- the bare `#|` closes
      //                                                       and contributes an
      //                                                       empty final segment
      //     #|AAA / #|BBB trailing   -> "AAA BBB trailing "  <- content
      //     #|abc / #|   (spaces)    -> "abc "        <- trailing blanks are blank
      //     #|one #|two              -> "one #|two "  <- a mid-line `#|` is content
      //     (no closer at all)       -> ends at EOF, no trailing space
      //
      // THE HEADER OF THIS FUNCTION WAS WRONG AND SAID SO. It claimed the closer
      // is "a `#|` with only whitespace BEFORE it on its line" and listed
      // `#|AAA\n#|BBB trailing -> "AAA\nBBB trailing"` as a measurement. Under
      // that rule `#|BBB trailing` closes the string; it does not. It is the
      // SECOND measurement above that settles it, and the join is a space rather
      // than a newline. The old rule paired markers as opener/closer alternately,
      // so an ODD count of `#|` lines ran to EOF and was reported "unterminated"
      // -- a finding the toolchain does not make, on valid MoonBit.
      //
      // Cost of getting it wrong, measured rather than imagined: proton 0.3.4
      // `facade_types.mbt` writes its block string at lines 236-245 with content
      // on every `#|` line and a bare `#|` at 246. The old rule closed at 236, so
      // 246 opened a second string that ran to EOF, the file was reported
      // unterminated, and the scan stopped at line 246 -- while the enum
      // declaring `CookieWaiting` and `CookieCompleted` sits at 589. A file
      // truncated past its declarations contributes nothing to the cross-file
      // symbol table, so the sibling that USES those names was told they were
      // undefined: three findings, in three files, from one.
      let mut j = self.pos + 2
      while j < n && (self.chars[j] == ' ' || self.chars[j] == '\t') {
        j += 1
      }
      if j >= n || self.chars[j] == '\n' {
        // The closer, and it contributes an EMPTY final segment -- which is why
        // every closed value ends in a space and no EOF-terminated one does.
        // Measured: `#|abc / #|def / #|` gives "abc def " while `#|abc / #|def`
        // gives "abc def". That difference is why the value is built from
        // SEGMENTS rather than accumulated raw.
        segs.push(cur.to_string().trim().to_owned())
        segs.push("")
        closed = true
        while self.pos < j {
          self.pos += 1
          self.col += 1
        }
        break
      }
      // NOT a closer: this line begins a new SEGMENT and its text is content.
      segs.push(cur.to_string().trim().to_owned())
      cur = StringBuilder()
      self.pos += 2
      self.col += 2
      at_line_start = false
      continue
    }
    // A line whose first NON-BLANK character is not `#|` ENDS the block, and the
    // toolchain does not report that as unterminated. Measured: `#|abc` / `plain`
    // / `#|` reports `plain` as an UNBOUND IDENTIFIER (4021) -- so `plain` is
    // CODE, and the trailing `#|` is a second, separate string expression (4139).
    //
    // A BLANK line does NOT end it. `#|abc` / <blank> / `#|def` / `#|` is
    // "abc def ", and so is the same shape with a whitespace-only line.
    //
    // `at_line_start` is still true here precisely when only whitespace has been
    // seen on this line, so this fires on the first real character, not before.
    if at_line_start &&
      c != ' ' &&
      c != '\t' &&
      c != '\n' &&
      !(c == '#' && self.pos + 1 < n && self.chars[self.pos + 1] == '|') {
      segs.push(cur.to_string().trim().to_owned())
      ended_at_code = true
      break
    }
    if c == '\n' {
      self.line += 1
      self.col = 1
      at_line_start = true
    } else {
      if c != ' ' && c != '\t' {
        at_line_start = false
      }
      self.col += 1
    }
    cur.write_char(c)
    self.pos += 1
  }
  if !closed && !ended_at_code {
    segs.push(cur.to_string().trim().to_owned())
    self.reports.push(@report.Report::{
      family: @core.FParse,
      lenses: [@core.LStructural],
      message: "unterminated block string literal (expected a line-leading `#|`)",
      span: @core.span_at(l, c0, 1),
      vst: [],
    })
  }
  // SEGMENTS JOINED BY A SINGLE SPACE. Newlines are not in the value: measured,
  // `#|one` / `  #|two` / `#|` is "one two " and not "one\ntwo". Building the
  // value segment-wise is what makes that fall out, and it is why the closer has
  // to push an empty segment rather than simply stop.
  let s = segs.join(" ")
  self.emit(TStr(s, []), l, c0, 1)
  TStr(s, [])
}

///|
fn Lexer::lex_name(self : Lexer) -> (Tok, Int32, Int32, Int32) {
  let l = self.line
  let c0 = self.col
  let start = self.pos
  if self.chars[self.pos] == '@' {
    self.pos += 1
    self.col += 1
  }
  while self.pos < self.chars.length() &&
        (is_letter(self.chars[self.pos]) || is_digit(self.chars[self.pos])) {
    self.pos += 1
    self.col += 1
  }
  let s = self.slice(start, self.pos)
  (TName(s), l, c0, self.pos - start)
}

///|
fn Lexer::lex_op(self : Lexer) -> Tok {
  let l = self.line
  let c0 = self.col
  let c = self.chars[self.pos]
  let next = if self.pos + 1 < self.chars.length() {
    Some(self.chars[self.pos + 1])
  } else {
    None
  }
  // FOUR-CHAR OPERATOR FIRST, and `..<=` has to be tested before `..<`.
  //
  // The comment that stood here until 0.4.30 said "`..=` is not modelled: it was
  // not measured in the blocked corpus this token was added for". That was true
  // when written and is now stale in a way that cost four files. Settled against
  // the toolchain, one form per package with a broken canary beside each:
  //
  //   `0..n`    REJECTED -- "Missing `=` after `..` in range expression. Hint:
  //              use `a..<=b` for inclusive range or `a..<b` for exclusive"
  //   `0..<n`   accepted -- exclusive, already one TRange token
  //   `0..<=n`  accepted -- INCLUSIVE. This is the form, not `..=`.
  //   `0..=<n`  REJECTED
  //
  // So the inclusive operator is four characters, and `..<` is a PREFIX of it.
  // Testing the three-char rule first would lex `0..<=n` as `0..<` followed by
  // `=n`, which is the bare-`..`-then-`=` shape the toolchain explicitly
  // rejects -- so the order here is load-bearing, not tidiness.
  if c == '.' &&
    next == Some('.') &&
    self.pos + 3 < self.chars.length() &&
    self.chars[self.pos + 2] == '<' &&
    self.chars[self.pos + 3] == '=' {
    self.pos += 4
    self.col += 4
    self.emit(TRangeIncl, l, c0, 4)
    return TRangeIncl
  }
  // three-char operators: `..<` is ONE token (an exclusive range). Without
  // this, `.` and `<` lex separately and `1..<chars.length()` dies in the
  // parser's postfix chain. A bare `..` stays two TDots, which is correct:
  // the toolchain REJECTS a bare `..` and says so in its own hint.
  if c == '.' &&
    next == Some('.') &&
    self.pos + 2 < self.chars.length() &&
    self.chars[self.pos + 2] == '<' {
    self.pos += 3
    self.col += 3
    self.emit(TRange, l, c0, 3)
    return TRange
  }
  // `>..` — the DESCENDING range, three characters, one token.
  //
  // It belongs with the other range operators and it is tested BEFORE the
  // two-char `>=` below, because the two-char section would otherwise read the
  // `>` as a comparison and leave the two dots behind -- which is exactly the
  // "unexpected token `.`" the corpus reported at
  // `async 0.22.4 src/fs/watch_windows.mbt:320`.
  //
  // The two forms are disjoint by their second character (`=` against `.`), so
  // the order between them is a readability choice rather than a correctness
  // one; what IS load-bearing is that this test comes before the single-char
  // `>` at the bottom of this function.
  if c == '>' &&
    next == Some('.') &&
    self.pos + 2 < self.chars.length() &&
    self.chars[self.pos + 1] == '.' &&
    self.chars[self.pos + 2] == '.' {
    self.pos += 3
    self.col += 3
    self.emit(TRangeDesc, l, c0, 3)
    return TRangeDesc
  }
  // two-char operators first
  if c == '=' && next == Some('=') {
    self.pos += 2
    self.col += 2
    self.emit(TEqEq, l, c0, 2)
    return TEqEq
  }
  // `=~` — the REGEX MATCH. Tested next to `==` because both start with `=`,
  // and disjoint from it by their second character.
  if c == '=' && next == Some('~') {
    self.pos += 2
    self.col += 2
    self.emit(TEqTilde, l, c0, 2)
    return TEqTilde
  }
  if c == '!' && next == Some('=') {
    self.pos += 2
    self.col += 2
    self.emit(TNe, l, c0, 2)
    return TNe
  }
  if c == '<' && next == Some('=') {
    self.pos += 2
    self.col += 2
    self.emit(TLe, l, c0, 2)
    return TLe
  }
  if c == '>' && next == Some('=') {
    self.pos += 2
    self.col += 2
    self.emit(TGe, l, c0, 2)
    return TGe
  }
  if c == '&' && next == Some('&') {
    self.pos += 2
    self.col += 2
    self.emit(TAndAnd, l, c0, 2)
    return TAndAnd
  }
  if c == '|' && next == Some('|') {
    self.pos += 2
    self.col += 2
    self.emit(TOrOr, l, c0, 2)
    return TOrOr
  }
  // the shifts, before the single-char table can split them into a
  // comparison plus a stray `<`/`>`; mutually exclusive with `<=`/`>=` by
  // their second character
  if c == '<' && next == Some('<') {
    self.pos += 2
    self.col += 2
    self.emit(TShl, l, c0, 2)
    return TShl
  }
  if c == '>' && next == Some('>') {
    self.pos += 2
    self.col += 2
    self.emit(TShr, l, c0, 2)
    return TShr
  }
  if c == '-' && next == Some('>') {
    self.pos += 2
    self.col += 2
    self.emit(TArrow, l, c0, 2)
    return TArrow
  }
  // 0464 -- the PIPE family. Placed after the shifts and before compound
  // assignment; mutually exclusive with all of them by their SECOND character
  // (`|`, `>`, `+` against `|`, `>`, `=`), so the order carries no meaning and
  // this is only where they read together.
  if c == '<' && next == Some('|') {
    self.pos += 2
    self.col += 2
    self.emit(TPipeLt, l, c0, 2)
    return TPipeLt
  }
  if c == '|' && next == Some('>') {
    self.pos += 2
    self.col += 2
    self.emit(TPipeGt, l, c0, 2)
    return TPipeGt
  }
  if c == '<' && next == Some('+') {
    self.pos += 2
    self.col += 2
    self.emit(TAppendPlus, l, c0, 2)
    return TAppendPlus
  }
  // compound assignment: two-char checks. Mutually exclusive with `->` by
  // their second character (`=` vs `>`), so the order against TArrow is free.
  if c == '+' && next == Some('=') {
    self.pos += 2
    self.col += 2
    self.emit(TPlusEq, l, c0, 2)
    return TPlusEq
  }
  if c == '-' && next == Some('=') {
    self.pos += 2
    self.col += 2
    self.emit(TMinusEq, l, c0, 2)
    return TMinusEq
  }
  if c == '*' && next == Some('=') {
    self.pos += 2
    self.col += 2
    self.emit(TStarEq, l, c0, 2)
    return TStarEq
  }
  if c == '/' && next == Some('=') {
    self.pos += 2
    self.col += 2
    self.emit(TSlashEq, l, c0, 2)
    return TSlashEq
  }
  if c == '%' && next == Some('=') {
    self.pos += 2
    self.col += 2
    self.emit(TPercentEq, l, c0, 2)
    return TPercentEq
  }
  self.pos += 1
  self.col += 1
  let t = match c {
    '+' => TPlus
    '-' => TMinus
    '*' => TStar
    '/' => TSlash
    '%' => TPercent
    '=' => TAssign
    '<' => TLt
    '>' => TGt
    '!' => TBang
    '(' => TLParen
    ')' => TRParen
    '{' => TLBrace
    '}' => TRBrace
    '[' => TLBracket
    ']' => TRBracket
    ',' => TComma
    ':' => TColon
    '.' => TDot
    ';' => TSemi
    // A lone `|` — the or-pattern separator of match arms. The parser never
    // sees one (match bodies are skipped whole), so the token only has to
    // EXIST; what matters is that the character stops reporting
    // "unexpected character" and marking the file partial.
    '|' => TBar
    // A lone `?` (optional-type suffix, option parameter). Where it is legal
    // the parser consumes it; where it is not, the parser reports it honestly.
    // The lexer only stops flagging the character itself as unexpected.
    '?' => TQuestion
    // A lone `&` or `^` — bitwise and/xor. Same reasoning as TBar: the
    // character must stop reporting "unexpected character" and marking the
    // file partial; the PARSER owns whether the operator is legal here.
    '&' => TAmp
    '^' => TCaret
    // `~` — the label sigil. Real MoonBit, so it must not be reported by the
    // lexer; the PARSER owns the two positions it can appear in.
    '~' => TTilde
    other => {
      self.reports.push(@report.Report::{
        family: @core.FParse,
        lenses: [@core.LStructural],
        message: "unexpected character '\{other}'",
        span: @core.span_at(l, c0, 1),
        vst: [],
      })
      TBang
    }
  }
  self.emit(t, l, c0, 1)
  t
}

///|
/// 10^k by repeated multiplication.
///
/// A bounded loop rather than a library `pow`: the exponents that occur in
/// practice are small, and this way a hostile or accidental literal such as
/// `1.0e999999` cannot run the scan long. Past this cap the result is already 0
/// or infinity as a Double anyway.
fn pow10(k : Int32) -> Double {
  let cap = 400
  let mut r = 1.0
  let mut i = 0
  let lim = if k > cap { cap } else { k }
  while i < lim {
    r = r * 10.0
    i += 1
  }
  r
}

///|
/// Parse a float literal, exponent included.
///
/// The mantissa scan STOPS at `e`/`E` and skips only the digit separator `_`.
/// Skipping every non-digit instead is the subtle version of this bug: it
/// quietly swallows the `e` and the digits after it into the mantissa, so
/// `2e8` came out as 28 and `1.0e-12` as 1.012.
fn parse_double(s : String) -> Double {
  let chars = s.to_array()
  let n = chars.length()
  let mut whole = 0.0
  let mut frac = 0.0
  let mut div = 1.0
  let mut seen_dot = false
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '.' {
      seen_dot = true
      i += 1
      continue
    }
    if c == 'e' || c == 'E' {
      break
    }
    if is_digit(c) {
      let d = (c.to_int() - '0'.to_int()).to_double()
      if seen_dot {
        frac = frac * 10.0 + d
        div = div * 10.0
      } else {
        whole = whole * 10.0 + d
      }
      i += 1
      continue
    }
    // The digit separator in `1_000.5`, and anything else the lexer passed on.
    i += 1
  }
  let base = whole + frac / div
  if i >= n {
    return base
  }
  let c = chars[i]
  if c != 'e' && c != 'E' {
    return base
  }
  i += 1
  let mut neg = false
  if i < n && (chars[i] == '+' || chars[i] == '-') {
    neg = chars[i] == '-'
    i += 1
  }
  let mut exp = 0
  let mut any = false
  while i < n && is_digit(chars[i]) {
    if exp < 1000000 {
      exp = exp * 10 + (chars[i].to_int() - '0'.to_int())
    }
    any = true
    i += 1
  }
  if !any {
    return base
  }
  if neg {
    exp = -exp
  }
  if exp > 0 {
    base * pow10(exp)
  } else if exp < 0 {
    base / pow10(-exp)
  } else {
    base
  }
}

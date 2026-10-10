// lexer for the MoonBit-subset frontend: newline-sensitive rules —
// suppressed after openers/binary operators/assignment so expressions can
// span lines; otherwise a newline terminates the statement.

///|
pub(all) enum Tok {
  TInt(Int)
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
  /// A lone `|` — the or-pattern separator inside match arms
  /// (`SAssign(_) | SLet(_) => ...`). Match bodies are skipped whole, so no
  /// pattern grammar is needed; the token exists so the CHARACTER stops
  /// reaching lex_op's unknown-char arm, whose FParse report marked whole
  /// files partial on an or-pattern they could otherwise read.
  TBar
  TBang
  /// `?` — real MoonBit (optional types `T?`, optional parameters `x? : T`),
  /// so it must not be reported by the lexer. This frontend consumes it in the
  /// annotation positions above; anywhere else it reaches the parser.
  TQuestion
  /// `..<` — the exclusive range operator, one token. A bare `..` stays two
  /// TDots, and `..=` is not modelled: it was not measured in the blocked
  /// corpus this token was added for (`1..<chars.length()`).
  TRange
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
  mut pos : Int
  mut line : Int
  mut col : Int
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
    | TBang
    | TComma
    | TColon
    | TArrow
    | TDot
    | TRange
    | TLParen
    | TLBracket
    | TLBrace
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
fn closer_ahead(chars : Array[Char], start : Int) -> Bool {
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
fn Lexer::emit(self : Lexer, t : Tok, line : Int, col : Int, len : Int) -> Unit {
  self.toks.push(t)
  self.spans.push(@core.span_at(line, col, len))
}

///|
fn Lexer::run(self : Lexer) -> Unit {
  let mut last : Tok = TSemi
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    if c == ' ' || c == '\t' || c == '\r' {
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
      last = self.lex_char()
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
    // An attribute (`#cfg(...)`, `#borrow(...)`, `#[derive(...)]`, `#deprecated`).
    // Not a block string: `#` is only a block-string opener when `|` follows it.
    if c == '#' && self.pos + 1 < self.chars.length() {
      let nx = self.chars[self.pos + 1]
      if nx == '[' || is_letter(nx) {
        self.lex_attribute()
        continue
      }
    }
    if is_letter(c) || c == '@' {
      // '@' starts a package alias token ("@q") so `.mbtx` import blocks lex
      let (t, l, cl, len) = self.lex_name()
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
let lit_max : Int = 2147483647

///|
/// `acc * base + d`, or `ok = false` rather than a wrapped answer.
///
/// The overflow check happens BEFORE the arithmetic, so nothing is ever
/// computed in the first place. That matters because `Int` is 32-bit on wasm:
/// a plain `acc * 16 + 15` on `0xFFFFFFFF` would trap the whole scan instead of
/// degrading to "no value".
fn lit_step(acc : Int, base : Int, d : Int) -> (Int, Bool) {
  if acc > (lit_max - d) / base {
    (-1, false)
  } else {
    (acc * base + d, true)
  }
}

///|
/// Digit value for a base, or -1 when the character is not a digit of it.
fn digit_value(c : Char, base : Int) -> Int {
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
  let int_part = self.pos
  // A fractional part makes this a float, and a float literal has no suffix
  // and no base. Checked only when digits were actually consumed, so `0.foo`
  // is not read as a float.
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
  let text = self.slice(start, int_part)
  let len = int_part - start
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
fn Lexer::slice(self : Lexer, from : Int, to : Int) -> String {
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
        self.flush_interp_name(cur, cur_is_member)
        return
      }
    } else if c == '"' {
      self.flush_interp_name(cur, cur_is_member)
      cur = ""
      self.copy_nested_string(buf)
    } else if c == '\'' {
      self.flush_interp_name(cur, cur_is_member)
      cur = ""
      self.copy_nested_char(buf)
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
      self.flush_interp_name(cur, cur_is_member)
      cur = ""
      cur_is_member = false
      after_dot = true
    } else {
      self.flush_interp_name(cur, cur_is_member)
      cur = ""
    }
  }
  self.flush_interp_name(cur, cur_is_member)
}

///|
/// Record one interpolation-level identifier, unless it is a member of a path
/// or a keyword.

///|
fn Lexer::flush_interp_name(
  self : Lexer,
  name : String,
  is_member : Bool,
) -> Unit {
  if name == "" || is_member {
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
fn is_moonbit_keyword(s : String) -> Bool {
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
    | "init"
    | "self" => true
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
fn Lexer::lex_char(self : Lexer) -> Tok {
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
/// A block string. `#|` opens it; a line-leading `#|` closes it and the string
/// ends at the end of THAT line.
///
/// Measured against the toolchain rather than assumed, with `moon run` printing
/// the resulting value:
///
///   #|AAA\n#|BBB            -> "AAA\nBBB"
///   #|AAA\n  #|BBB         -> "AAA\nBBB"        (the closer may be indented)
///   #|AAA\n#|BBB trailing   -> "AAA\nBBB trailing"
///   #|one #|two\n#|three    -> "one #|two\nthree"  (mid-line `#|` is content)
///   #|AAA\n|#BBB            -> not closed        (`|#` is content)
///   #|AAA\n#|BBB\nCCC       -> "AAA\nBBB", and CCC is parsed as CODE
///
/// So: the closer is a `#|` with only whitespace before it on its line; the
/// text after the closer on that line stays inside the string, and the newline
/// does not. An earlier version of this file looked for `|#`, which never
/// appears in real code -- it reported "unterminated block string" on anything
/// containing a block string at all.
///
/// That report was NOT a false positive to be chased: when it was written, this
/// module's own src/samples/samples.mbt had 107 `#|` markers, an odd count, so
/// its last block really did run to end of input and the report was true. I
/// took the self-scan output as evidence that the closer was wrong and it was
/// not -- the closer WAS wrong, but for the five measured reasons above, not
/// for that. A truthful "unterminated" is not a bug report, and treating it as
/// one wasted a cycle. (The file has since gained one marker and parses clean.)
///
/// End of input also closes the block, as the toolchain's tolerance for an
/// odd count shows, but the file is still reported: whatever followed the last
/// `#|` was never lexed, so every span past it would be wrong.
///
/// Newlines inside the body advance the line counter (so every span after it
/// stays correct) but are NOT emitted as `TNewline` — they are string contents,
/// not statement separators.
fn Lexer::lex_block_string(self : Lexer) -> Tok {
  let l = self.line
  let c0 = self.col
  let buf = StringBuilder()
  let n = self.chars.length()
  // step past the opening `#|`
  self.pos += 2
  self.col += 2
  let mut closed = false
  let mut at_line_start = false
  while self.pos < n {
    let c = self.chars[self.pos]
    if c == '#' &&
      at_line_start &&
      self.pos + 1 < n &&
      self.chars[self.pos + 1] == '|' {
      // The closer is stripped, and the string then ends at the END of that line:
      // whatever follows the closer on it is still content, the newline after it
      // is not.
      self.pos += 2
      self.col += 2
      closed = true
      while self.pos < n && self.chars[self.pos] != '\n' {
        buf.write_char(self.chars[self.pos])
        self.pos += 1
        self.col += 1
      }
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
    buf.write_char(c)
    self.pos += 1
  }
  if !closed {
    self.reports.push(@report.Report::{
      family: @core.FParse,
      lenses: [@core.LStructural],
      message: "unterminated block string literal (expected a line-leading `#|`)",
      span: @core.span_at(l, c0, 1),
      vst: [],
    })
  }
  let s = buf.to_string()
  self.emit(TStr(s, []), l, c0, 1)
  TStr(s, [])
}

///|
fn Lexer::lex_name(self : Lexer) -> (Tok, Int, Int, Int) {
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
  // three-char operators: `..<` is ONE token (an exclusive range). Without
  // this, `.` and `<` lex separately and `1..<chars.length()` dies in the
  // parser's postfix chain. A bare `..` stays two TDots; `..=` is not modelled.
  if c == '.' &&
    next == Some('.') &&
    self.pos + 2 < self.chars.length() &&
    self.chars[self.pos + 2] == '<' {
    self.pos += 3
    self.col += 3
    self.emit(TRange, l, c0, 3)
    return TRange
  }
  // two-char operators first
  if c == '=' && next == Some('=') {
    self.pos += 2
    self.col += 2
    self.emit(TEqEq, l, c0, 2)
    return TEqEq
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
fn parse_double(s : String) -> Double {
  let mut whole = 0
  let mut frac = 0
  let mut div = 1
  let mut seen_dot = false
  for c in s {
    if c == '.' {
      seen_dot = true
      continue
    }
    if is_digit(c) {
      let d = c.to_int() - '0'.to_int()
      if seen_dot {
        frac = frac * 10 + d
        div *= 10
      } else {
        whole = whole * 10 + d
      }
    }
  }
  whole.to_double() + frac.to_double() / div.to_double()
}

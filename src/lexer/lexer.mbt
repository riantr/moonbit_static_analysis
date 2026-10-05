// lexer for the MoonBit-subset frontend: newline-sensitive rules —
// suppressed after openers/binary operators/assignment so expressions can
// span lines; otherwise a newline terminates the statement.

///|
pub(all) enum Tok {
  TInt(Int)
  TFloat(Double)
  TStr(String)
  TName(String)
  TPlus
  TMinus
  TStar
  TSlash
  TPercent
  TAssign
  TEqEq
  TNe
  TLt
  TLe
  TGt
  TGe
  TAndAnd
  TOrOr
  TBang
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
    | TBang
    | TComma
    | TColon
    | TArrow
    | TDot
    | TLParen
    | TLBracket
    | TLBrace
    | TSemi => true
    _ => false
  }
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
      if !newline_suppressed_after(last) {
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
fn Lexer::lex_number(self : Lexer) -> Tok {
  let l = self.line
  let c0 = self.col
  let start = self.pos
  let mut is_float = false
  while self.pos < self.chars.length() && is_digit(self.chars[self.pos]) {
    self.pos += 1
    self.col += 1
  }
  if self.pos < self.chars.length() && self.chars[self.pos] == '.' {
    is_float = true
    self.pos += 1
    self.col += 1
    while self.pos < self.chars.length() && is_digit(self.chars[self.pos]) {
      self.pos += 1
      self.col += 1
    }
  }
  let text = self.slice(start, self.pos)
  let len = self.pos - start
  if is_float {
    self.emit(TFloat(parse_double(text)), l, c0, len)
    TFloat(parse_double(text))
  } else {
    self.emit(TInt(parse_int(text)), l, c0, len)
    TInt(parse_int(text))
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
  while self.pos < self.chars.length() && self.chars[self.pos] != '"' {
    let c = self.chars[self.pos]
    if c == '\\' && self.pos + 1 < self.chars.length() {
      self.pos += 1
      self.col += 1
      let e = self.chars[self.pos]
      buf.write_char(
        match e {
          'n' => '\n'
          't' => '\t'
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
  self.emit(TStr(s), l, c0, self.col - c0)
  TStr(s)
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
  if c == '-' && next == Some('>') {
    self.pos += 2
    self.col += 2
    self.emit(TArrow, l, c0, 2)
    return TArrow
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
fn parse_int(s : String) -> Int {
  let mut v = 0
  for c in s {
    if is_digit(c) {
      v = v * 10 + (c.to_int() - '0'.to_int())
    }
  }
  v
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

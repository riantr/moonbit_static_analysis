// parser for the MoonBit-subset frontend: precedence climbing;
// assignment targets validated to
// name/field/index; function definitions restricted to the top level.

///|
pub(all) struct ParseResult {
  tree : @ast.Module
  reports : Array[@report.Report]
  /// Messages of the `reports` entries that are DELIBERATE subset exclusions —
  /// a declaration form the frontend chose not to analyse, as opposed to one it
  /// failed to read. They stay in `reports` (a caller printing findings should
  /// still see "this struct was not analysed"), but the scanner must not
  /// mistake them for a file it could not parse: skipping a `test` block leaves
  /// the rest of the file perfectly readable.
  skips : Array[String]
  /// Earliest line at which the source genuinely failed to read; 0 when it read
  /// all of it. Deliberate subset exclusions do not move it, so this marks the
  /// boundary of the region where findings can still be trusted.
  first_error : Int
}

///|
priv struct Parser {
  toks : Array[@lexer.Tok]
  spans : Array[@core.Span]
  mut p : Int
  reports : Array[@report.Report]
  /// Messages of the deliberate subset exclusions among `reports`
  skips : Array[String]
  /// Earliest line at which the source genuinely failed to read; 0 if it read
  /// all of it. Deliberate exclusions do not move it.
  mut first_error : Int
}

///|
/// strip the leading '@' the lexer glued onto an alias token (`@q` -> `q`)
fn alias_of(tag : String) -> String {
  if tag.has_prefix("@") {
    let chars = tag.to_array()
    let buf = StringBuilder()
    for i in 1..<chars.length() {
      buf.write_char(chars[i])
    }
    buf.to_string()
  } else {
    tag
  }
}

///|
pub fn parse(src : String) -> ParseResult {
  let (toks, spans, reports) = @lexer.lex(src)
  // Seed from the LEXER's own reports (unterminated strings, stray characters):
  // those are genuine read failures and arrive before the parser runs.
  let mut first_error = 0
  for r in reports {
    let l = r.span.start.line
    if first_error == 0 || l < first_error {
      first_error = l
    }
  }
  let p = Parser::{ toks, spans, p: 0, reports, skips: [], first_error, }
  let imports : Array[@ast.ImportSpec] = []
  let import_seen : Map[String, Bool] = Map([])
  let body : Array[@ast.Stmt] = []
  p.skip_seps()
  // `.mbtx` script imports. The official entry grammar is `"path" [@alias] [*]`
  // — the modifiers TRAIL the quoted path, in that order, and import-all is
  // script-only. Recorded, not resolved; a repeated path is a parse-class
  // defect (the second and later entries are the ones reported).
  while p.at_name("import") {
    let _ = p.bump()
    if !p.at(TLBrace) {
      p.err("import needs a '{' block (script-form imports)", p.span())
    } else {
      let _ = p.bump()
      p.skip_seps()
      while !p.at(TRBrace) && !p.at(TEOF) {
        let sp = p.span()
        match p.bump() {
          TStr(path) => {
            let mut alias_name = ""
            // the lexer glues '@' into the alias name: `@q` is ONE TName
            if p.peek() is TName(tag) && tag.has_prefix("@") {
              let _ = p.bump()
              alias_name = alias_of(tag)
            }
            let mut star = false
            if p.at(TStar) {
              let _ = p.bump()
              star = true
            }
            match import_seen.get(path) {
              Some(_) =>
                p.err("duplicate import of '\{path}' in this script", sp)
              None => {
                import_seen.set(path, true)
                imports.push(
                  if star {
                    if alias_name == "" {
                      @ast.IStar(path)
                    } else {
                      @ast.IAliasedStar(path, alias_name)
                    }
                  } else if alias_name == "" {
                    @ast.IImport(path)
                  } else {
                    @ast.IAliased(path, alias_name)
                  },
                )
              }
            }
          }
          _ => p.err("expected a quoted package path in an import block", sp)
        }
        p.skip_seps()
        if p.at(TComma) {
          let _ = p.bump()
          p.skip_seps()
        } else {
          break
        }
      }
      p.expect(TRBrace, "'}'")
    }
    p.skip_seps()
  }
  while !(p.peek() is TEOF) {
    let sp = p.span()
    p.skip_modifiers()
    // Read the keyword AFTER the modifiers: `pub struct X` is `pub` then
    // `struct`, and reading it first would classify the declaration as `pub`.
    let kw = p.peek_name()
    if p.at_name("fn") {
      body.push(p.parse_fn())
    } else if kw == "struct" ||
      kw == "enum" ||
      kw == "trait" ||
      kw == "impl" ||
      kw == "derive" ||
      kw == "test" {
      p.skip_decl_braced(kw, sp)
    } else if kw == "type" ||
      kw == "const" ||
      kw == "suberror" ||
      kw == "extern" {
      p.skip_decl_line(kw, sp)
    } else {
      body.push(p.parse_stmt())
    }
    p.skip_seps()
  }
  ParseResult::{
    tree: { body, imports, },
    reports: p.reports,
    skips: p.skips,
    first_error: p.first_error,
  }
}

///|
fn Parser::peek(self : Parser) -> @lexer.Tok {
  self.toks[self.p]
}

///|
fn Parser::span(self : Parser) -> @core.Span {
  self.spans[self.p]
}

///|
fn Parser::bump(self : Parser) -> @lexer.Tok {
  let t = self.toks[self.p]
  if !(t is TEOF) {
    self.p += 1
  }
  t
}

///|
fn Parser::at(self : Parser, t : @lexer.Tok) -> Bool {
  self.peek() == t
}

///|
fn Parser::at_name(self : Parser, n : String) -> Bool {
  match self.peek() {
    TName(s) => s == n
    _ => false
  }
}

///|
/// The current token's name, or "" when it is not a name.
fn Parser::peek_name(self : Parser) -> String {
  match self.peek() {
    TName(s) => s
    _ => ""
  }
}

///|
fn Parser::err(self : Parser, msg : String, sp : @core.Span) -> Unit {
  // A genuine read failure: it moves the trusted-region boundary.
  let l = sp.start.line
  if self.first_error == 0 || l < self.first_error {
    self.first_error = l
  }
  self.reports.push(@report.Report::{
    family: @core.FParse,
    lenses: [@core.LStructural],
    message: msg,
    span: sp,
    vst: [],
  })
}

///|
fn Parser::skip_seps(self : Parser) -> Unit {
  while self.at(TNewline) || self.at(TSemi) {
    let _ = self.bump()
  }
}

///|
/// Consume a balanced `( ... )`, starting at the open paren.
fn Parser::skip_parens(self : Parser) -> Unit {
  let mut depth = 0
  while !self.at(TEOF) {
    if self.at(TLParen) {
      depth += 1
    } else if self.at(TRParen) {
      depth -= 1
    }
    let _ = self.bump()
    if depth <= 0 {
      break
    }
  }
}

///|
/// Consume a balanced `( ... )` if one starts here, else do nothing.
fn Parser::skip_parens_if_present(self : Parser) -> Unit {
  if self.at(TLParen) {
    self.skip_parens()
  }
}

///|
/// Visibility and calling-convention modifiers that may precede a `fn`:
/// `pub`, `pub(all)`, `priv`, `async`. Consume them and keep dispatching, so
/// `pub async fn f()` is still parsed as a function instead of turning `pub`
/// into an undefined variable.
///
/// `extern` is deliberately NOT here: its body is a raw string (`= "..."`), not
/// a MoonBit block, so it is a declaration form the frontend does not model and
/// is skipped as one.
fn Parser::skip_modifiers(self : Parser) -> Unit {
  let mut again = true
  while again {
    again = false
    if self.at_name("pub") || self.at_name("priv") {
      let _ = self.bump()
      self.skip_parens_if_present()
      again = true
      continue
    }
    if self.at_name("async") {
      let _ = self.bump()
      again = true
    }
  }
}

///|
/// A brace-bodied declaration the frontend does not model (struct / enum /
/// trait / impl). Consume the whole declaration and report it **once**.
///
/// Parsing it statement-by-statement is what produced the false-positive
/// cascades: every field line became its own UndefinedName plus a ParseError
/// echo, and the fields then counted as dead top-level statements. A top-level
/// `fn` cannot legally appear inside a declaration, so meeting one means the
/// declaration has no body (e.g. `pub impl Eq for T` with its methods in a
/// separate impl block) — stop there instead of swallowing the rest of the file.
fn Parser::skip_decl_braced(
  self : Parser,
  what : String,
  sp : @core.Span,
) -> Unit {
  let mut found = false
  while !self.at(TEOF) {
    if self.at(TLBrace) {
      found = true
      break
    }
    if self.at_name("fn") {
      break
    }
    let _ = self.bump()
  }
  if found {
    let mut depth = 0
    while !self.at(TEOF) {
      if self.at(TLBrace) {
        depth += 1
      } else if self.at(TRBrace) {
        depth -= 1
        let _ = self.bump()
        if depth <= 0 {
          break
        }
        continue
      }
      let _ = self.bump()
    }
  }
  self.skip(what, true, sp)
}

///|
/// A line-terminated declaration the frontend does not model (type / const /
/// suberror). One finding, no cascade.
fn Parser::skip_decl_line(
  self : Parser,
  what : String,
  sp : @core.Span,
) -> Unit {
  while !self.at(TEOF) && !self.at(TNewline) && !self.at(TSemi) {
    let _ = self.bump()
  }
  self.skip(what, false, sp)
}

///|
/// Record a deliberate subset exclusion: one report for the reader, and one
/// entry in `skips` so the scanner can tell it apart from a read failure.
///
/// Both facts arrive as FParse, and only the read failure should cost the file
/// its coverage. Skipping a `test` block leaves the rest of the file perfectly
/// readable; failing to lex a string does not.
fn Parser::skip(
  self : Parser,
  what : String,
  braced : Bool,
  sp : @core.Span,
) -> Unit {
  self.note_skip(skip_msg(what, braced), sp)
}

///|
/// The message a deliberate subset exclusion carries.
///
/// It is recorded in `skips` as well as reported, because "this declaration was
/// not analysed" and "this file could not be read" are DIFFERENT facts that both
/// arrive as FParse -- and only the second one should cost the file its
/// coverage. Skipping a `test` block leaves the rest of the file perfectly
/// readable; failing to lex a string does not.
fn skip_msg(what : String, braced : Bool) -> String {
  if braced {
    "\{what} declaration is outside the analyzed subset; its body was not analyzed"
  } else {
    "\{what} declaration is outside the analyzed subset"
  }
}

///|
fn Parser::expect_name(self : Parser, what : String) -> (String, @core.Span) {
  let sp = self.span()
  match self.bump() {
    TName(n) => (n, sp)
    other => {
      self.err("expected \{what}", sp)
      (
        match other {
          TStr(s) => s
          _ => "?"
        },
        sp,
      )
    }
  }
}

///|
/// A type annotation: a head name, then any number of `[...]` argument
/// lists and `.Tail` segments.
///
/// `Array[Double]` was the single largest parse blocker measured across real
/// projects: 74 of 84 blocked files stopped on it, counting the tuple returns
/// that contain one (`-> (Matrix, Array[Double])`).
///
/// `-> @pkg.T` (a qualified package type with a `.Tail`, as in
/// `-> @argparse.Command`) is the second-most-common shape in real code
/// and was a blocker before: the head name and the `.Tail` are emitted as
/// separate tokens, and the parser had no path to consume the `.` and the
/// tail name after the head. Fixed by accepting one or more `.Name` tails
/// and folding them into the returned name. Only the joined name is kept,
/// and that is not a compromise: the type lens does not model containers or
/// qualified paths, so `@pkg.T` and `@pkg` reach it identically, both
/// Unknown. What matters here is that the parser stops failing at the `.`,
/// which is the difference between a real file being readable and being
/// discarded.
///
/// Only the head is kept, and that is not a compromise: the type lens does not
/// model containers. `ann_to_ty` recognises `int` / `float` / `bool` / `str` /
/// `None` and list literals, and falls back to Unknown otherwise -- so
/// `Array[Double]` and `Array` reach it identically, both Unknown. What matters
/// here is that the parser stops failing at the `[`, which is the difference
/// between a real file being readable and being discarded.
fn Parser::type_annotation(self : Parser) -> String {
  let (name, _) = self.expect_name("type name")
  self.skip_indexed()
  // Consume a `.Tail` chain. `@pkg.T.U.V` becomes "@pkg.T.U.V" in the name
  // returned to the caller; the lexer does not include the `.` in TName.
  let mut n = name
  while self.at(TDot) {
    let _ = self.bump()
    let (tail, _) = self.expect_name("type tail")
    n = n + "." + tail
    self.skip_indexed()
  }
  n
}

///|
/// Consume balanced `[ ... ]` groups, keeping nothing.
fn Parser::skip_indexed(self : Parser) -> Unit {
  while self.at(TLBracket) {
    let _ = self.bump()
    let mut depth = 1
    while depth > 0 && !self.at(TEOF) {
      if self.at(TLBracket) {
        depth += 1
      } else if self.at(TRBracket) {
        depth -= 1
      }
      let _ = self.bump()
    }
  }
}

///|
/// A return type: `Name`, `Name[...]`, or a tuple `(A, B[...], ...)`.
///
/// A tuple is recorded as "" — that is `TUnknown` for the type lens, which is
/// the honest answer rather than pretending the first component is the whole
/// return type.
fn Parser::return_annotation(self : Parser) -> String {
  if self.at(TLParen) {
    let _ = self.bump()
    while !self.at(TRParen) && !self.at(TEOF) {
      if !self.at(TComma) {
        let _ = self.bump()
      }
      self.skip_indexed()
      if self.at(TComma) {
        let _ = self.bump()
      }
    }
    self.expect(TRParen, "')'")
    return ""
  }
  self.type_annotation()
}

///|
fn Parser::expect(self : Parser, t : @lexer.Tok, what : String) -> Unit {
  if !self.at(t) {
    self.err("expected \{what}", self.span())
  } else {
    let _ = self.bump()
  }
}

///|
fn Parser::parse_fn(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  let _ = self.bump() // fn
  let (name, _) = self.expect_name("function name")
  self.expect(TLParen, "'('")
  let params : Array[@ast.Param] = []
  while !self.at(TRParen) && !self.at(TEOF) {
    let (pname, psp) = self.expect_name("parameter name")
    let mut ann = ""
    if self.at(TColon) {
      let _ = self.bump()
      ann = self.type_annotation()
    }
    params.push({ name: pname, tyann: ann, span: psp, })
    if self.at(TComma) {
      let _ = self.bump()
    } else {
      break
    }
  }
  self.expect(TRParen, "')'")
  let mut retann = ""
  if self.at(TArrow) {
    let _ = self.bump()
    retann = self.return_annotation()
  }
  let body = self.parse_block()
  { span: sp, kind: @ast.SFunc(name, params, retann, body, sp), }
}

///|
fn Parser::parse_block(self : Parser) -> Array[@ast.Stmt] {
  self.expect(TLBrace, "'{'")
  let body : Array[@ast.Stmt] = []
  while !self.at(TRBrace) && !self.at(TEOF) {
    self.skip_seps()
    if self.at(TRBrace) {
      break
    }
    if self.at_name("fn") {
      self.err("function definitions must be top-level", self.span())
      let _ = self.bump()
      self.skip_seps()
      continue
    }
    body.push(self.parse_stmt())
    self.skip_seps()
  }
  self.expect(TRBrace, "'}'")
  body
}

///|
fn Parser::parse_stmt(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  if self.at_name("let") {
    let _ = self.bump()
    let (name, _) = self.expect_name("binding name")
    let mut ann = ""
    if self.at(TColon) {
      let _ = self.bump()
      ann = self.type_annotation()
    }
    self.expect(TAssign, "'='")
    let init = self.parse_expr()
    return { span: sp, kind: @ast.SLet(name, ann, init), }
  }
  if self.at_name("return") {
    let _ = self.bump()
    if self.at(TNewline) || self.at(TSemi) || self.at(TRBrace) || self.at(TEOF) {
      return { span: sp, kind: @ast.SReturn(None), }
    }
    return { span: sp, kind: @ast.SReturn(Some(self.parse_expr())), }
  }
  if self.at_name("break") {
    let _ = self.bump()
    return { span: sp, kind: @ast.SBreak, }
  }
  if self.at_name("continue") {
    let _ = self.bump()
    return { span: sp, kind: @ast.SContinue, }
  }
  if self.at_name("if") {
    return self.parse_if()
  }
  if self.at_name("while") {
    let _ = self.bump()
    let cond = self.parse_expr()
    let body = self.parse_block()
    return { span: sp, kind: @ast.SWhile(cond, body), }
  }
  if self.at_name("for") {
    let _ = self.bump()
    let (v, vsp) = self.expect_name("loop variable")
    if !self.at_name("in") {
      self.err("expected 'in'", self.span())
    } else {
      let _ = self.bump()
    }
    let seq = self.parse_expr()
    let body = self.parse_block()
    return { span: sp, kind: @ast.SFor(v, vsp, seq, body), }
  }
  // expression or assignment
  let e = self.parse_expr()
  if self.at(TAssign) {
    let asp = self.span()
    let _ = self.bump()
    if !e.is_valid_target() {
      self.err("invalid assignment target", asp)
    }
    let rhs = self.parse_expr()
    return { span: sp, kind: @ast.SAssign(e, rhs), }
  }
  { span: sp, kind: @ast.SExpr(e), }
}

///|
fn Parser::parse_if(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  let _ = self.bump() // if
  let cond = self.parse_expr()
  let then = self.parse_block()
  let elseifs : Array[@ast.ElseIf] = []
  let mut els : Array[@ast.Stmt]? = None
  let mut going = true
  while going {
    going = false
    self.skip_seps()
    if self.at_name("else") {
      let _ = self.bump()
      if self.at_name("if") {
        let _ = self.bump()
        let c2 = self.parse_expr()
        let b2 = self.parse_block()
        elseifs.push({ cond: c2, body: b2, })
        going = true
      } else {
        els = Some(self.parse_block())
      }
    }
  }
  { span: sp, kind: @ast.SIf(cond, then, elseifs, els), }
}

///|
fn Parser::parse_expr(self : Parser) -> @ast.Expr {
  self.parse_or()
}

///|
fn Parser::parse_or(self : Parser) -> @ast.Expr {
  let mut l = self.parse_and()
  while self.at(TOrOr) {
    let sp = self.span()
    let _ = self.bump()
    let r = self.parse_and()
    l = { span: l.span, kind: @ast.EBin(OpOr, l, r), }
    ignore(sp)
  }
  l
}

///|
fn Parser::parse_and(self : Parser) -> @ast.Expr {
  let mut l = self.parse_eq()
  while self.at(TAndAnd) {
    let _ = self.bump()
    let r = self.parse_eq()
    l = { span: l.span, kind: @ast.EBin(OpAnd, l, r), }
  }
  l
}

///|
fn Parser::parse_eq(self : Parser) -> @ast.Expr {
  let mut l = self.parse_cmp()
  while self.at(TEqEq) || self.at(TNe) {
    let op = if self.at(TEqEq) { @ast.OpEq } else { @ast.OpNe }
    let _ = self.bump()
    let r = self.parse_cmp()
    l = { span: l.span, kind: @ast.EBin(op, l, r), }
  }
  l
}

///|
fn Parser::parse_cmp(self : Parser) -> @ast.Expr {
  let mut l = self.parse_add()
  while self.at(TLt) || self.at(TLe) || self.at(TGt) || self.at(TGe) {
    let op = match self.peek() {
      TLt => @ast.OpLt
      TLe => @ast.OpLe
      TGt => @ast.OpGt
      _ => @ast.OpGe
    }
    let _ = self.bump()
    let r = self.parse_add()
    l = { span: l.span, kind: @ast.EBin(op, l, r), }
  }
  l
}

///|
fn Parser::parse_add(self : Parser) -> @ast.Expr {
  let mut l = self.parse_mul()
  while self.at(TPlus) || self.at(TMinus) {
    let op = if self.at(TPlus) { @ast.OpAdd } else { @ast.OpSub }
    let _ = self.bump()
    let r = self.parse_mul()
    l = { span: l.span, kind: @ast.EBin(op, l, r), }
  }
  l
}

///|
fn Parser::parse_mul(self : Parser) -> @ast.Expr {
  let mut l = self.parse_unary()
  while self.at(TStar) || self.at(TSlash) || self.at(TPercent) {
    let op = match self.peek() {
      TStar => @ast.OpMul
      TSlash => @ast.OpDiv
      _ => @ast.OpMod
    }
    let _ = self.bump()
    let r = self.parse_unary()
    l = { span: l.span, kind: @ast.EBin(op, l, r), }
  }
  l
}

///|
fn Parser::parse_unary(self : Parser) -> @ast.Expr {
  let sp = self.span()
  if self.at(TMinus) {
    let _ = self.bump()
    let e = self.parse_unary()
    return { span: sp, kind: @ast.EUnary(UNeg, e), }
  }
  if self.at(TBang) {
    let _ = self.bump()
    let e = self.parse_unary()
    return { span: sp, kind: @ast.EUnary(UNot, e), }
  }
  self.parse_postfix()
}

///|
fn Parser::parse_postfix(self : Parser) -> @ast.Expr {
  let mut e = self.parse_atom()
  while true {
    if self.at(TDot) {
      let _ = self.bump()
      let (f, fsp) = self.expect_name("field name")
      e = { span: e.span, kind: @ast.EField(e, f), }
      ignore(fsp)
      continue
    }
    if self.at(TLBracket) {
      let _ = self.bump()
      let idx = self.parse_expr()
      self.expect(TRBracket, "']'")
      e = { span: e.span, kind: @ast.EIndex(e, idx), }
      continue
    }
    // `Name::Name` — a path reference, and usually a path CALL when a `(` follows.
    //
    // A column-aware census of real code puts this at roughly 45 of 111 first
    // blockers, the largest single gap in the `.mbt` subset; the earlier
    // line-based census hid it by crediting those lines to the indexed-type
    // annotation sitting further left on the same line.
    //
    // ECall's name is a String, so a qualified name fits without touching the
    // AST: `Array::make(n, 0.0)` becomes ECall("Array::make", args), which is
    // all the structural and type lenses compare against.
    //
    // The whole leading path is flattened, not just an EName. The `.` branch
    // above turns `@pkg.Type` into EField(EName("@pkg"), "Type") BEFORE this
    // branch ever sees it, so a two-segment path (`@pkg.Type::single`,
    // `A.B::m`) used to arrive here as an EField and hit the `break` below,
    // leaving `::m()` unconsumed — four parse errors for a shape the toolchain
    // compiles. Measured on 0.4.3: `Foo(name=@argparse.ValueRange::single())`
    // produced 4 errors, `A.B::m()` produced 2, while `A::m()` parsed clean.
    // `::` is an unambiguous path marker, so folding the chain back into one
    // name loses no information; `dotted` returns "" for anything that is not a
    // name-rooted field chain (a call result, an index) and those still break.
    if self.at(TColon) && self.at_next(TColon) {
      let path = dotted(e)
      if path == "" {
        break
      }
      let _ = self.bump()
      let _ = self.bump()
      let (m, _) = self.expect_name("name after '::'")
      e = { span: e.span, kind: @ast.EName(path + "::" + m), }
      continue
    }
    if self.at(TLParen) {
      let csp = self.span()
      let _ = self.bump()
      let args : Array[@ast.Expr] = []
      while !self.at(TRParen) && !self.at(TEOF) {
        // A named argument `name = value`. The label is dropped: the call
        // lens does not consume labels, and the value expression is the
        // one that matters for binding-table and finding purposes. Before
        // this, a function call with any named arg — `Command(name=...)`
        // is the canonical case from argparse-derived packages — would
        // trip `parse_expr()` on the `=` and stop the whole file. Caught
        // by scanning `moonbitlang/pdf2md@0.1.1`, whose `pdf2md_command`
        // signature parses cleanly only after this loop accepts `name=value`.
        // No two-token lookahead is available, so save `p`, consume the
        // name, and check the next token. If it isn't `=`, restore `p`
        // and fall back to a normal `parse_expr()`. If it is `=`, consume
        // it and parse the value.
        if self.peek_name() != "" {
          let saved_p = self.p
          let _ = self.bump()
          if self.at(TAssign) {
            let _ = self.bump()
            args.push(self.parse_expr())
          } else {
            self.p = saved_p
            args.push(self.parse_expr())
          }
        } else {
          args.push(self.parse_expr())
        }
        if self.at(TComma) {
          let _ = self.bump()
        } else {
          break
        }
      }
      self.expect(TRParen, "')'")
      match e.kind {
        @ast.EName(n) => e = { span: csp, kind: @ast.ECall(n, args), }
        _ => self.err("only named functions can be called", csp)
      }
      continue
    }
    break
  }
  e
}

///|
/// True when the CURRENT token is `t` and the one after it is `u`. Used to
/// recognise `::`, which the lexer emits as two `TColon` tokens rather than one.
fn Parser::at_next(self : Parser, t : @lexer.Tok) -> Bool {
  self.p + 1 < self.toks.length() && self.toks[self.p + 1] == t
}

///|
/// A `[` has been consumed and the current token is the name `for`. Parse the
/// whole comprehension: generators, the `=>` / `{ }` body, and any `if`
/// guard, then the closing `]`.
///
/// Why this is not just left to the list branch: the lexer has no `=>` token,
/// so `=>` arrives as `TAssign` followed by `TGt` (lexer maps `'='` to
/// `TAssign`). A comprehension parsed as a list therefore ran off the end of
/// the element list, and the statement parser then saw `self => ...` as
/// `self = ...` — an assignment. Measured on 0.4.4: the single line
/// `[ for x in self => x + 1 ]` produced "parameter 'self' changed by
/// assignment" AND "parameter 'self' may not be used" on the same token, two
/// findings that contradict each other, and neither true. 13 such
/// ParamChanged findings on moonbitlang/core, a package `moon check` accepts
/// with 0 errors.
///
/// The iterable is kept in `sources` rather than folded into the body: it is
/// the only read of `self` in the common `[ for x in self => ... ]` shape, so
/// dropping it would trade the phantom assignment for a phantom "unused".
fn Parser::parse_comprehension(self : Parser, sp : @core.Span) -> @ast.Expr {
  let sources : Array[@ast.Expr] = []
  let vars : Array[String] = []
  let mut body : @ast.Expr = { span: sp, kind: @ast.EInt(0), }
  let mut seen = false
  // The grammar is
  //   'for' pat 'in' src (',' pat 'in' src)* ( '=>' body | '{' body } )
  // — `for` is written ONCE and every following generator repeats only its
  // pattern and iterable. Two mistakes here, both measured against
  // moonbitlang/core on 0.4.5:
  //   * parsing the body per-generator made `[ for x in a, y in b => x + y ]`
  //     look for `=>` right after `a`, find a comma, and bail;
  //   * accepting only a comma-then-`for` for the next generator missed the
  //     form entirely, because the comma is followed by the next PATTERN.
  // Both were chasing a form that does not exist. A comprehension has
  // exactly ONE generator; there is no loop here to get wrong.
  if self.at_name("for") {
    let _ = self.bump()
  }
  // The pattern may destructure: `[ for k, v in entries => ... ]`.
  // `sorted_map/debug.mbt`, `hashmap/debug.mbt`, `immut/hashmap/debug.mbt`
  // and `hashmap/json.mbt` in moonbitlang/core all use this form.
  let (pat, _) = self.expect_name("comprehension variable")
  vars.push(pat)
  while self.at(TComma) && self.peek2_is_pattern_name() {
    let _ = self.bump()
    let (more_name, _) = self.expect_name("comprehension variable")
    vars.push(more_name)
  }
  if self.at_name("in") {
    let _ = self.bump()
  } else {
    self.err("expected 'in' in comprehension", self.span())
  }
  sources.push(self.parse_expr())
  // The guard belongs HERE — between the iterable and `=>`.
  //
  // This was written backwards first, on the strength of a probe whose
  // error line was read as the other form. Re-probed one form per file,
  // with a `moon.pkg` present and a deliberately-broken canary file
  // alongside (without a `moon.pkg`, or off a stale build, `moon check`
  // answers "no work to do" and exits 0 — a false green, not a pass):
  //
  //   [ for x in a if x > 0 => x ]   0 errors
  //   [ for x in a => x if x > 0 ]   E3002 Parse error, unexpected token
  //                                  `if`, you may expect `]`
  //
  // moonbitlang/core uses the guard-before form in 9 comprehensions across
  // 5 files, so reading it the other way left all of them unparsed.
  if self.at_name("if") {
    let _ = self.bump()
    ignore(self.parse_expr())
  }
  // NO comma continuation: a comprehension has exactly ONE generator.
  // Both candidate spellings are rejected by the toolchain —
  //   [ for x in a, for y in b => x + y ]   E3002 unexpected token `,`
  //   [ for x in a, y in b => x + y ]       E3002 unexpected token `,`
  // An earlier version consumed the comma and read a second generator,
  // which silently DROPPED the first iterable (`a`) rather than reporting
  // anything. The destructuring comma is unaffected: it comes BEFORE the
  // `in`, and this one comes after it.
  if self.at(TComma) {
    self.err(
      "a comprehension has one generator; `,` here is not MoonBit",
      self.span(),
    )
    let _ = self.bump()
    ignore(self.parse_expr())
  }
  if self.at(TAssign) && self.peek2() == TGt {
    // `=>` is lexed as `=` then `>`
    let _ = self.bump()
    let _ = self.bump()
    if self.at(TLBrace) {
      // The block body is `[ ... => { stmts } ]`, NOT `[ ... { stmts } ]`.
      // Probed: the first is 0 errors, the second is `E3002 Parse error,
      // unexpected token '{', you may expect '=>'`. An earlier version
      // handled the second (invalid) form and left the first unparsed.
      // `core/from_json.mbt` and `core/help_render.mbt` use the valid one.
      //
      // The block yields statements, not an expression. The last one, when it
      // is an expression, is the value.
      let stmts = self.parse_block()
      let exprs : Array[@ast.Expr] = []
      for st in stmts {
        match st.kind {
          @ast.SExpr(e) => exprs.push(e)
          _ => ()
        }
      }
      body = match exprs {
        [] => { span: sp, kind: @ast.EInt(0), }
        [last, .. rest] => {
          for e in rest {
            ignore(e)
          }
          last
        }
      }
    } else {
      body = self.parse_expr()
    }
    seen = true
  } else {
    self.err("expected '=>' in comprehension", self.span())
  }
  if !seen {
    self.err("comprehension has no body", sp)
  }
  self.expect(TRBracket, "']'")
  { span: sp, kind: @ast.EComp(vars, sources, body), }
}

///|
/// The token after the current one, TEOF at the end of input.
fn Parser::peek2(self : Parser) -> @lexer.Tok {
  if self.p + 1 < self.toks.length() {
    self.toks[self.p + 1]
  } else {
    TEOF
  }
}

///|
/// Is the token after the current one a name that can continue a
/// destructuring pattern? This is only consulted immediately after a pattern
/// has been read, where `for` would mean something else entirely.
fn Parser::peek2_is_pattern_name(self : Parser) -> Bool {
  match self.peek2() {
    TName(n) => n != "for"
    _ => false
  }
}

///|
/// Flatten a name-rooted field chain into its dotted spelling:
/// `EName("a") -> "a"`, `EField(EField(EName("a"), "b"), "c") -> "a.b.c"`.
/// Returns "" for anything that does not bottom out in a name — an index, a
/// call result, a literal — because such an expression has no name a `::`
/// could extend.
///
/// This is what lets the `::` branch in `parse_postfix` accept a path of any
/// length. Before it existed, the branch only matched a bare `EName`, so the
/// `.` branch's own `EField` output fell through to `break` and the rest of
/// the line cascaded.
fn dotted(e : @ast.Expr) -> String {
  match e.kind {
    @ast.EName(n) => n
    @ast.EField(base, f) => {
      let head = dotted(base)
      if head == "" {
        ""
      } else {
        head + "." + f
      }
    }
    _ => ""
  }
}

///|
fn Parser::note_skip(self : Parser, msg : String, sp : @core.Span) -> Unit {
  self.skips.push(msg)
  // Deliberately NOT routed through err(): a skip must not move first_error,
  // which is the boundary of the region where findings stay trustworthy.
  self.reports.push(@report.Report::{
    family: @core.FParse,
    lenses: [@core.LStructural],
    message: msg,
    span: sp,
    vst: [],
  })
}

///|
fn Parser::parse_atom(self : Parser) -> @ast.Expr {
  let sp = self.span()
  match self.bump() {
    TInt(i) => { span: sp, kind: @ast.EInt(i), }
    TFloat(f) => { span: sp, kind: @ast.EFloat(f), }
    TStr(s) => { span: sp, kind: @ast.EStr(s), }
    TName("true") => { span: sp, kind: @ast.EBool(true), }
    TName("false") => { span: sp, kind: @ast.EBool(false), }
    // `if` in expression position: `let d = if a { x } else { y }`. Measured as
    // the first blocker on 10 of 111 blocked real files.
    //
    // Parsed and consumed rather than added to the Expr enum, on the same
    // grounds as `test` blocks and `const`: the AST has no conditional node,
    // adding one would mean teaching all three lenses about it, and a value we
    // cannot model is exactly the case that should not cascade. The expression
    // yields 0 and a notice; the rest of the line stays readable.
    //
    // This arm must sit ABOVE the `TName(n)` catch-all below, which matches
    // every TName including "if".
    TName("if") => {
      let _ = self.parse_expr()
      let _ = self.parse_block()
      self.skip_seps()
      if self.at_name("else") {
        let _ = self.bump()
        let _ = self.parse_block()
      }
      self.note_skip(
        "if expression is outside the analyzed subset; it was read but not analysed",
        sp,
      )
      { span: sp, kind: @ast.EInt(0), }
    }
    TName(n) => { span: sp, kind: @ast.EName(n), }
    TLParen => {
      let e = self.parse_expr()
      self.expect(TRParen, "')'")
      e
    }
    TLBracket =>
      if self.at_name("for") {
        self.parse_comprehension(sp)
      } else {
        let elems : Array[@ast.Expr] = []
        while !self.at(TRBracket) && !self.at(TEOF) {
          elems.push(self.parse_expr())
          if self.at(TComma) {
            let _ = self.bump()
          } else {
            break
          }
        }
        self.expect(TRBracket, "']'")
        { span: sp, kind: @ast.EList(elems), }
      }
    TNewline => {
      self.err("unexpected end of line", sp)
      { span: sp, kind: @ast.EInt(0), }
    }
    other => {
      self.err("unexpected token", sp)
      ignore(other)
      { span: sp, kind: @ast.EInt(0), }
    }
  }
}

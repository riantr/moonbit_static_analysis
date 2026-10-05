// parser for the MoonBit-subset frontend: precedence climbing;
// assignment targets validated to
// name/field/index; function definitions restricted to the top level.

///|
pub(all) struct ParseResult {
  tree : @ast.Module
  reports : Array[@report.Report]
}

///|
priv struct Parser {
  toks : Array[@lexer.Tok]
  spans : Array[@core.Span]
  mut p : Int
  reports : Array[@report.Report]
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
  let p = Parser::{ toks, spans, p: 0, reports, }
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
    if p.at_name("fn") {
      body.push(p.parse_fn())
    } else {
      body.push(p.parse_stmt())
    }
    p.skip_seps()
  }
  ParseResult::{ tree: { body, imports, }, reports: p.reports, }
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
fn Parser::err(self : Parser, msg : String, sp : @core.Span) -> Unit {
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
      let (a, _) = self.expect_name("type name")
      ann = a
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
    let (r, _) = self.expect_name("return type")
    retann = r
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
      let (a, _) = self.expect_name("type name")
      ann = a
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
    if self.at(TLParen) {
      let csp = self.span()
      let _ = self.bump()
      let args : Array[@ast.Expr] = []
      while !self.at(TRParen) && !self.at(TEOF) {
        args.push(self.parse_expr())
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
fn Parser::parse_atom(self : Parser) -> @ast.Expr {
  let sp = self.span()
  match self.bump() {
    TInt(i) => { span: sp, kind: @ast.EInt(i), }
    TFloat(f) => { span: sp, kind: @ast.EFloat(f), }
    TStr(s) => { span: sp, kind: @ast.EStr(s), }
    TName("true") => { span: sp, kind: @ast.EBool(true), }
    TName("false") => { span: sp, kind: @ast.EBool(false), }
    TName(n) => { span: sp, kind: @ast.EName(n), }
    TLParen => {
      let e = self.parse_expr()
      self.expect(TRParen, "')'")
      e
    }
    TLBracket => {
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

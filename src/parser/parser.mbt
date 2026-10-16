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
  first_error : Int32
  /// Constructor names harvested from `enum` bodies this frontend did not
  /// analyse, as module-level VALUES.
  ///
  /// The body of an `enum` is skipped, not parsed, so its members never become
  /// bindings. Writing one of them — `TFunc` in `TFunc("f", [TInt], TInt)` —
  /// is ordinary MoonBit, and with no binding for it the structural walk
  /// reports `no visible binding for 'TFunc'`. That is a false positive about
  /// the analyzer, not about the code: the same file also carries the notice
  /// saying the enum body was not analysed.
  ///
  /// Harvesting the NAMES is much cheaper than modelling the body, and it is
  /// the only part of a constructor a name lookup needs. A name found this way
  /// resolves to "a value of unknown type" — the same shape the cross-file
  /// symbol table gives a type from another package — so nothing downstream
  /// infers a type or arity it has not read.
  enum_ctors : Array[String]
  /// Functions declared `extern "C"` / `extern "wasm"`.
  ///
  /// Their bodies are empty because the body is written in another language, so
  /// an unused PARAMETER of one is not an unread binding — the name is part of
  /// the foreign ABI. The walker must not run a frame audit on them.
  ///
  /// Probed against the toolchain: `pub extern "C" fn expf(x : Float) -> Float`
  /// produces no unused warning, while a control `pub fn p6(y : Float) -> Float
  /// { 1.0 }` in the same file does. An empty BODY is not a usable proxy — a
  /// normal `fn p7(z : Float) -> Float { }` warns too — so the declaration has
  /// to be recognised as extern rather than inferred from its shape.
  extern_fns : Array[String]
}

///|
priv struct Parser {
  toks : Array[@lexer.Tok]
  spans : Array[@core.Span]
  mut p : Int32
  reports : Array[@report.Report]
  /// Messages of the deliberate subset exclusions among `reports`
  skips : Array[String]
  /// Earliest line at which the source genuinely failed to read; 0 if it read
  /// all of it. Deliberate exclusions do not move it.
  mut first_error : Int32
  /// Constructor names seen while skipping an `enum` body. See the field of
  /// the same name on `ParseResult`.
  enum_ctors : Array[String]
  /// Names declared by an `extern "C"` / `extern "wasm"` function. The
  /// implementation lives in another language, so the parameter names are part
  /// of that language's ABI and not bindings this analyzer may judge as unread.
  extern_fns : Array[String]
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
  let p = Parser::{
    toks,
    spans,
    p: 0,
    reports,
    skips: [],
    first_error,
    enum_ctors: [],
    extern_fns: [],
  }
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
          TStr(path, _) => {
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
    } else if kw == "extern" {
      body.push(p.parse_extern_fn(sp))
    } else if kw == "struct" && p.at_tuple_struct() {
      // A TUPLE struct has no body to skip, so the braced skipper would invent
      // one out of the next declaration's `{`. See `at_tuple_struct` for the
      // two false positives that produced.
      //
      // The notice is the UNBRACED wording, and that is the same correction the
      // `derive` branch below already carries: "its body was not analyzed"
      // claims a body this declaration does not have.
      p.skip_decl_line(kw, sp)
    } else if kw == "struct" ||
      kw == "enum" ||
      kw == "trait" ||
      kw == "impl" ||
      kw == "extend" ||
      kw == "test" {
      p.skip_decl_braced(kw, sp)
    } else if kw == "type" || kw == "const" || kw == "derive" {
      // `derive` IS NOT BRACED. `derive(Debug, Eq, Clone)` is a parenthesised
      // trait list with no body, so the braced skipper claimed one it does not
      // have: the notice read "its body was not analyzed", which is false — a
      // derive has no body to analyze.
      //
      // It was also wrong in a way that could bite. `skip_decl_braced` scans
      // forward for `{`, breaking only at a `fn`, so a `derive` line followed by
      // any braced declaration consumed THAT declaration's braces as its own and
      // the second declaration's exclusion notice was never emitted — a silent
      // loss of the very fact the notice exists to record. Demonstrated on
      //
      //     derive(Debug, Eq)
      //     struct Box { n : Int }
      //
      // which produced ONE notice (derive) instead of two, the struct's
      // exclusion vanishing with it.
      //
      // MEASURED, not assumed: zero occurrences of that ordering in moui 0.1.12,
      // so this is a latent bug with no corpus impact today. It is fixed because
      // it is wrong, not because it costs anything yet — a silent exclusion is
      // the failure this file has been bitten by before.
      //
      // The notice itself STAYS: the analyzer genuinely does not model derived
      // implementations, so a reader is right to be told. Only the false claim
      // about a body is removed. This does not reduce the notice COUNT.
      p.skip_decl_line(kw, sp)
    } else if kw == "suberror" {
      // A suberror has TWO shapes: `priv suberror Boom` is one line, while
      // `pub suberror DecodeError { UnsupportedFormat(String) ... }` is braced.
      // Sending the braced shape to the LINE skipper stopped the skip
      // at the newline and left `{ ... }` to be parsed as an expression block,
      // so every payload type inside it was reported as an undefined name —
      // `String` four times over in riantr/moonbit_image 0.3.7's `types.mbt`.
      //
      // This comment used to give the unbraced example as `suberror Timeout of
      // String`. THAT FORM DOES NOT EXIST — `moon check` rejects it with `[3002]`,
      // and so do `suberror E(T)` and `suberror E(x : T)`
      // (`_verify/settle_0463b_bodyless_grammar.ps1`, 7/7). A body-less suberror
      // cannot carry a payload at all: braces are the only way to give it one, so
      // the two surviving shapes are `suberror E` and `suberror E derive(...)`.
      // The discriminator below is unchanged and still correct — it asks whether a
      // brace follows, not what the keyword is — but the example that explained it
      // taught a grammar the toolchain does not have.
      //
      // Same split `struct` / `enum` already get, decided by what actually
      // follows the keyword rather than by the keyword's name.
      if p.next_is_lbrace() {
        p.skip_decl_braced(kw, sp)
      } else {
        // The body-less branch is the one that leaves the suberror's OWN name
        // unregistered as a value. See `harvest_bodyless_suberror`.
        p.harvest_bodyless_suberror()
        p.skip_decl_line(kw, sp)
      }
    } else if kw == "using" {
      // A RE-EXPORT: `pub using @core { type View, ... }`. Its effect — the
      // named items become visible in this package — is recorded by
      // `collect_declared_names`; what the PARSER owes the rest of the file is
      // a correct skip, so the brace block is consumed whole instead of being
      // parsed as expressions.
      //
      // Before 0.4.18 this line fell through to the statement parser, `using`
      // was read as an ordinary identifier, and every re-export in the corpus
      // reported it: 73 `undefined variable 'using'` across the 19 files of
      // wzzc-dev/moui 0.1.12 that use the form (115 lines). The `.mbti`
      // frontend has understood `using` since 0.4.8 — `moonfiles.mbt:1185`.
      let _ = p.bump()
      // The package qualifier between the keyword and the brace. It is NOT
      // parsed: `@wzzc-dev/moui/core` glues and splits in ways this frontend
      // does not model, and nothing downstream needs it — the re-export names a
      // symbol into THIS package, and the referenced package is out of scope by
      // the same rule that silences every `@`-prefixed name.
      while !p.at(TLBrace) && !p.at(TEOF) && !p.at(TNewline) {
        let _ = p.bump()
      }
      p.skip_braces()
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
    enum_ctors: p.enum_ctors,
    extern_fns: p.extern_fns,
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
/// Whether the next token is a string literal, whatever its contents. `at`
/// takes a bare token and `Tok` cannot be compared for equality here, so the
/// payload-carrying kinds need this form — the same reason `at_name` exists.
fn Parser::at_str(self : Parser) -> Bool {
  match self.peek() {
    TStr(_) => true
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
/// Consume a balanced `{ ... }` if one starts here, else do nothing. Used
/// where the subset skips a whole brace group it does not model — a `match`
/// expression's arms — so the group's tokens cannot cascade.
fn Parser::skip_braces(self : Parser) -> Unit {
  if !self.at(TLBrace) {
    return
  }
  let mut depth = 0
  while !self.at(TEOF) {
    if self.at(TLBrace) {
      depth += 1
    } else if self.at(TRBrace) {
      depth -= 1
    }
    let _ = self.bump()
    if depth <= 0 {
      break
    }
  }
}

///|
/// Defensive scan for a malformed `try` whose body block is missing — input
/// valid MoonBit never reaches (`try {` is required), so this only runs on
/// text `moon check` itself would reject. Walk forward WITHOUT consuming
/// until a top-level `catch` keyword, a closer, or EOF: the caller's catch
/// loop takes a `catch` stopped at, and a closer is left for the enclosing
/// grammar so the scan never eats a bracket it did not open.
fn Parser::skip_to_catch(self : Parser) -> Unit {
  let mut depth = 0
  while !self.at(TEOF) {
    if self.at(TLBrace) || self.at(TLParen) || self.at(TLBracket) {
      depth += 1
    } else if self.at(TRBrace) || self.at(TRParen) || self.at(TRBracket) {
      if depth == 0 {
        return
      }
      depth -= 1
    } else if depth == 0 && self.at_name("catch") {
      return
    }
    let _ = self.bump()
  }
}

///|
/// Consume the pattern after a `catch` keyword, up to (not past) the handler
/// body's `{`. Patterns may bind struct fields (`catch Some({ x }) {`),
/// destructure a tuple (`catch (a, b) {`), or alternate (`catch Some(_) |
/// None {`) — none modelled by the subset, all read past so the handler body
/// the caller skips next stays balanced.
///
/// THIS IS THE `try` ARM'S PATTERN SCANNER, and it deliberately stays a SCAN.
/// The `try` arm skips its handler bodies whole, so it has nothing to bind the
/// names into. The postfix `catch` arm now parses its arms for real and uses
/// `parse_catch_pattern` instead; the two disagreeing about what a pattern
/// means is deliberate, because the alternative is the `try` arm manufacturing
/// `no visible binding` for a name it never bound.
fn Parser::skip_pattern(self : Parser) -> Unit {
  let mut depth = 0
  while !self.at(TEOF) {
    if self.at(TLBrace) {
      if depth == 0 {
        return
      }
      depth += 1
    } else if self.at(TRBrace) || self.at(TRParen) || self.at(TRBracket) {
      if depth == 0 {
        return
      }
      depth -= 1
    } else if self.at(TLParen) || self.at(TLBracket) {
      depth += 1
    }
    let _ = self.bump()
  }
}

///|
/// Is the fat arrow at the current position?
///
/// THERE IS NO FAT-ARROW TOKEN, and reading one off the token names is what
/// cost this fix its first attempt. `TArrow` exists and is `->`; `=>` has no
/// production at all. Measured by dumping the stream rather than by reading the
/// rules — `cancel() catch { _ => () }` lexes to
///
///     NAME(cancel) ( ) NAME(catch) { NAME(_) TAssign TGt ( ) }
///
/// so a `catch` arm's `=>` arrives as `TAssign` followed by `TGt`, and a check
/// for `TArrow` simply never fires. The parser then walked off the end of the
/// arm, consumed the catch's `}` as part of the body, and reported
/// `expected '}'` at EOF.
///
/// This is the same shape as `::`, which is two `TColon` and which
/// `parse_is_pattern` already consumes as a pair. Fixed on the parser side for
/// the same reason: a lexer token would mean every match on `Tok` had to learn
/// a variant, for one call site.
fn Parser::at_fat_arrow(self : Parser) -> Bool {
  self.at(TAssign) && self.peek2() == TGt
}

///|
/// Consume the fat arrow, on the `at_fat_arrow` spelling only.
fn Parser::eat_fat_arrow(self : Parser) -> Unit {
  let _ = self.bump()
  let _ = self.bump()
}

///|
/// The names a `catch` pattern introduces, consumed up to (not past) the `=>`.
///
/// THIS IS A SUPERSET, AND THE EXTRA NAMES ARE THE POINT. Every identifier in
/// the pattern text is returned: `Some({ x })` gives `["Some", "x"]`,
/// `(a, b)` gives `["a", "b"]`, `Boom(n) | Nope` gives `["Boom", "n", "Nope"]`.
/// Two of those three list a name the pattern does not bind.
///
/// Telling them apart needs a pattern grammar the subset does not have, and the
/// cost of guessing wrong is asymmetric. A name that SHOULD have bound and did
/// not is reported as `no visible binding for 'x'` — a false positive on
/// correct code. A name that bound and should not have produces silence, and
/// silence is not a defect anyone can file. `Walker::bind_pattern` therefore
/// puts every one of these in the frame WITHOUT putting it in the audit list,
/// so the superset cannot produce a finding in either direction.
///
/// The wildcard `_` is not a `TName`, so it never reaches the list — which is
/// correct, because `_` binds nothing and an empty list already says so.
///
/// Balanced brackets are tracked so `Wrap({ inner })` does not stop at the
/// `{` of its inner brace: the `{` that ends the pattern is one at depth 0 with
/// no bracket open.
fn Parser::parse_catch_pattern(self : Parser) -> Array[String] {
  let names : Array[String] = []
  let mut depth = 0
  while !self.at(TEOF) {
    if self.at_fat_arrow() {
      break
    }
    if self.at(TLBrace) && depth == 0 {
      break
    }
    match self.peek() {
      TName(n) => names.push(n)
      TLParen | TLBracket => depth += 1
      TRParen | TRBracket => if depth == 0 { break } else { depth -= 1 }
      _ => ()
    }
    let _ = self.bump()
  }
  names
}

///|
/// Does this `catch { ... }` group contain a `<?` log payload?
///
/// `<?` IS NOT IN THE SUBSET, and this guard is what stops reading a handler
/// from costing a file. Measured: proton 0.3.4 `facade_locale.mbt:63` read
/// cleanly at every release up to 0.4.29, because the postfix `catch` arm
/// consumed the handler with `skip_braces` and never saw line 65 —
///
///     @xlog.warn(category="proton.locale") <?
///       { "message": "system locale query failed; falling back to en-US" }
///     []
///
/// Parsing the handler turned that into a hard parse error and the file went
/// from `parsed` to `not-parsed`. A fix that fixes one corpus and breaks
/// another is not a fix, and the number that matters — `parsed=` — had gone
/// DOWN.
///
/// `?>` OCCURS ZERO TIMES in proton, so this is not a paired operator with a
/// findable end: it is the `xlog` payload suffix, and its payload is an
/// open-ended run of expressions (`{ ... }` then `[]` above). There is no
/// structural way to find where one stops, which is why the guard is per GROUP
/// and not per arm.
///
/// The guard scans the whole group and, on a hit, restores the prior behaviour
/// EXACTLY — `skip_braces`, no arms, no read. Deliberately the old state rather
/// than a half-measure: a handler group is read or it is not, and a partial
/// read is the arrangement that produced the original false positive.
///
/// Called with `self.p` ON the group's `{`.
fn Parser::catch_group_has_log_payload(self : Parser) -> Bool {
  let mut i = self.p
  let mut depth = 0
  while i < self.toks.length() {
    match self.toks[i] {
      TLBrace => depth += 1
      TRBrace => {
        depth -= 1
        if depth <= 0 {
          return false
        }
      }
      TEOF => return false
      TLt =>
        // `<` THEN `?` -- the order is the source's. Getting it backwards is
        // what the first draft of this guard did: it looked for `TQuestion`
        // followed by `TLt`, never fired, and proton's `facade_locale.mbt`
        // stayed blocked with `unexpected token `?``. `a < ?` is not MoonBit,
        // so the adjacent pair can only be the log payload.
        if i + 1 < self.toks.length() {
          match self.toks[i + 1] {
            TQuestion => return true
            _ => ()
          }
        }
      _ => ()
    }
    i += 1
  }
  false
}

///|
/// `catch { pattern => body, ... }` — the handler list, as statements.
///
/// Both arm-body shapes are real and the census says which one matters:
/// `_verify/census_catch.ps1` counts 45 expr-bodied against 9 block-bodied
/// handler sites in moui, and 273 against 29 in proton. A block-only reading
/// would have modelled the rare form and left the common one to whatever
/// `skip_braces` did with it.
///
/// The `=>` is optional. MoonBit accepts `catch { e => 0 }` and
/// `catch { _ => () }`, and the settle probe (`_verify/settle_0439_catch.ps1`)
/// is what settles the no-arrow spelling rather than a guess — so this reads
/// the arrow if one is there and does not insist on it, which keeps a
/// differently-spelled handler from becoming a parse error that the old
/// `skip_braces` could not produce.
///
/// NO SKIP NOTICE IS EMITTED, and that is the whole point of the change. A
/// `note_skip` here would put a hole in the frame and silence `UnusedParam` for
/// the entire enclosing function — the `match` treatment, which `pipeline_0433`
/// already records as making the family unobservable. The arms are read, so
/// the frame has no hole.
fn Parser::parse_catch_arms(self : Parser) -> Array[@ast.CatchArm] {
  let arms : Array[@ast.CatchArm] = []
  if self.catch_group_has_log_payload() {
    // A `<?` log payload is inside this group and is not in the subset. The
    // whole group goes back to being skipped, which is what every release did
    // before the handler was parsed at all. See `catch_group_has_log_payload`.
    self.skip_braces()
    return arms
  }
  self.expect(TLBrace, "'{'")
  while !self.at(TRBrace) && !self.at(TEOF) {
    self.skip_seps()
    if self.at(TRBrace) || self.at(TEOF) {
      break
    }
    let asp = self.span()
    let bindings = self.parse_catch_pattern()
    if self.at_fat_arrow() {
      self.eat_fat_arrow()
    }
    self.skip_seps()
    let body = if self.at(TLBrace) {
      // A block body is its own statement list. `fn_body` is FALSE: a
      // handler's trailing expression is the arm's value, but this node's
      // type is the BASE's type (the base is what the catch produces on the
      // non-error path), so no lens joins the arm's value into anything.
      let (b, _) = self.parse_block(false)
      b
    } else if self.at(TEOF) || self.at(TRBrace) {
      // `pattern =>` with no body at all. The grammar rejects it; refusing
      // to guess here keeps a malformed handler from consuming the next arm's
      // pattern as a body.
      break
    } else {
      let st = self.parse_stmt()
      [st]
    }
    arms.push({ span: asp, bindings, body, })
    self.skip_seps()
  }
  self.expect(TRBrace, "'}'")
  arms
}

///|
/// Visibility and calling-convention modifiers that may precede a `fn`:
/// `pub`, `pub(all)`, `priv`, `async`. Consume them and keep dispatching, so
/// `pub async fn f()` is still parsed as a function instead of turning `pub`
/// into an undefined variable.
///
/// `extern` is deliberately NOT here: its body is a raw string (`= "..."`), not
/// a MoonBit block, so it is dispatched to `parse_extern_fn`, which models the
/// signature and leaves the body empty.
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

///|
/// True when the declaration whose header starts at the current token opens a
/// `{ ... }` body.
///
/// It scans a bounded number of tokens AHEAD rather than only looking at the
/// keyword, because the parser is positioned at the keyword itself: a braced
/// declaration reads `suberror DecodeError {`, three tokens in. The bound is
/// what keeps the question answerable — an unbraced header (`suberror Timeout`,
/// with or without a `derive(...)` list) must NOT be answered by a brace
/// belonging to some later declaration, and a header is never longer than a
/// handful of tokens.
///
/// This comment used to give `suberror Timeout of String` as the unbraced
/// example. That is not a suberror header; `moon check` rejects it, and so does
/// `suberror E(T)` and `suberror E(x : T)`
/// (`_verify/settle_0463b_bodyless_grammar.ps1`, 7/7). The bound is still doing
/// the work it was written to do, but the example that justified it was a
/// grammar that does not exist.
fn Parser::next_is_lbrace(self : Parser) -> Bool {
  let mut i = self.p
  let mut scanned = 0
  while i < self.toks.length() && scanned < 8 {
    match self.toks[i] {
      TLBrace => return true
      TEOF => return false
      _ => ()
    }
    i += 1
    scanned += 1
  }
  false
}

///|
/// Whether the declaration at the cursor is a TUPLE struct -- `struct Name(T)`,
/// `struct Name { .. } derive(Eq)` is not one -- which has a parenthesised field
/// list and NO body.
///
/// `skip_decl_braced` scans forward for the `{` that opens a body and stops only
/// at a `fn` or at EOF. A tuple struct has no brace to find, so it swallows
/// everything up to the NEXT declaration's brace. Measured, in moonbitlang/async
/// 0.22.4 `src/process/cancellation.mbt`:
///
///     pub(all) struct CancellationHandler(async (Int) -> Unit)
///
///     ///|
///     let default_signal : @signal.Signal = if @event_loop.platform is Windows {
///       SIGBREAK
///     } else {
///       SIGTERM
///     }
///
/// The brace it finds belongs to the `if`. The `let` and the `if` go with it, and
/// what is left reads as a block containing the words `else` and `SIGTERM` --
/// reported as `undefined variable 'else'` and `undefined variable 'SIGTERM'`.
/// Two false positives on correct code, blamed on a declaration that is not the
/// one being complained about.
///
/// FALSIFIED EN route, because each of these looked like the cause and was not:
/// the `is` pattern (`if Windows is Windows { .. } else { .. }` is clean), a
/// qualified receiver (`if h.platform is Windows { .. } else { .. }` is clean),
/// and the cross-package `@event_loop.platform` receiver (also clean). It is
/// neither the `if` nor the `is` nor the package: it is that the thing BEFORE the
/// `if` had no `{` for the skipper to stop at.
///
/// The scan stops at the first `(` or at anything else, and that "anything else"
/// is a plain-name rule rather than a token list. It USED to walk through `::`
/// to reach the `(`, on the reasoning that a qualified name should still be
/// reached. Measured, and the reasoning is wrong in both directions: neither
/// `pub struct Outer::Inner(Int)` nor `pub struct Outer::Inner { .. }` is
/// MoonBit, both are `[3002]` at the declaration
/// (`_verify/settle_0449b_tuple_struct.ps1`). So walking through `::` reached a
/// form that does not exist, and a bounded token count would have reached the
/// same nothing while ALSO misreading a long ordinary header. A plain-name rule
/// answers `false` for both unbuildable forms, which is the only thing they can
/// be, and needs no bound at all.
fn Parser::at_tuple_struct(self : Parser) -> Bool {
  let mut i = self.p + 1 // past `struct`
  while i < self.toks.length() {
    match self.toks[i] {
      TName(_) => i += 1
      TLParen => return true
      _ => return false
    }
  }
  false
}

///|
/// Skipping a braced declaration body whole.
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
  // `impl T for U with fn m(...) { ... }` puts a `fn` INSIDE the declaration, and
  // that `fn` is followed by the body brace. The `fn` sentinel below exists for
  // the OTHER shape — `pub impl Eq for T` with its methods in a separate block —
  // so the two have to be told apart or the first one leaves its body behind.
  //
  // `with` is the marker: it cannot appear in the bodiless shape. The measured
  // shapes agree: 1224 `impl ... with` headers in wzzc-dev/moui 0.1.12, of which
  // 1047 write `with fn` and the other 177 omit `fn` entirely
  // (`pub impl ToJson for Affine with to_json(self : Affine)`). The 177 never met
  // the sentinel and were never wrong; the 1047 all were.
  //
  // None of the 1047 headers carries more than one `fn`, so stopping after the
  // first body leaves nothing dangling.
  let mut saw_with = false
  while !self.at(TEOF) {
    if self.at(TLBrace) {
      found = true
      break
    }
    if self.at_name("with") {
      saw_with = true
    }
    if self.at_name("fn") && !saw_with {
      break
    }
    let _ = self.bump()
  }
  if found {
    let open_p = self.p
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
    // `enum` and `suberror` bodies both declare CONSTRUCTORS, and the harvest
    // is the same scan for both: a member is a NAME at depth 0 followed by an
    // optional `(...)` payload, and every token of a payload is nested at least
    // one level deep. `suberror` was missing here until 0.4.30, which made
    // every `raise Variant(...)` a false positive:
    //
    //   no visible binding for 'InvalidPathOverride'   x5
    //   no visible binding for 'InvalidIdentifier'
    //   no visible binding for 'MissingEnvironmentPath'
    //   undefined name 'MissingExecutablePath'
    //
    // measured on moonbit-community/proton 0.3.4 `facade_paths.mbt`, where the
    // suberror `AppPathError` is declared in the SAME FILE that raises it — so
    // this was not a cross-file resolution problem at all, only a missing
    // harvest. `raise` produces a value, so these are constructors exactly as
    // `enum` variants are, and they resolve to the same unknown-typed value an
    // enum variant does.
    if what == "enum" || what == "suberror" {
      self.harvest_ctors(open_p, self.p)
    }
  }
  self.skip(what, true, sp)
}

///|
/// A BODY-LESS `suberror` DECLARES ITS OWN NAME as its only constructor.
///
/// `priv suberror Boom` is a complete declaration and `raise Boom` is how one
/// raises it; `moon check` accepts both (settled,
/// `_verify/settle_0463_suberror_bodyless.ps1`, 7/7). But `harvest_ctors` is
/// reachable only from the BRACED branch, so a body-less suberror's own name
/// never entered `enum_ctors` — and `enum_ctors` is what seeds the module frame
/// as VALUES (`walk.mbt:1197`, `infer.mbt:880`).
///
/// Measured, five shapes through `pipeline.run`, the finding counted per shape:
///
///     A  body-less suberror declared BEFORE the use   UndefinedName 1
///     B  body-less suberror declared AFTER  the use   UndefinedName 1
///     C  suberror WITH a body, declared AFTER         UndefinedName 0
///     D  the TYPE name in a signature, body-less      UndefinedName 0
///     E  control, nothing declared at all            UndefinedName 1
///
/// A and B together rule out ORDER, which was the first guess and the one the
/// corpus could never have separated: in async `InvalidBlock` is declared in a
/// SIBLING file, a different resolution path entirely. C says the variable is the
/// BODY. D says the type name always resolved, so the hole is value-shaped and not
/// type-shaped — which is why adding a TYPE binding would have changed nothing.
///
/// THE NAME IS THE DECLARED NAME, not "the token after the keyword", and on this
/// grammar those happen to agree — the settled list of body-less headers is short
/// enough to state in full (`_verify/settle_0463b_bodyless_grammar.ps1`, 7/7):
///
///     priv suberror Boom                    ACCEPT
///     priv suberror Boom derive(Debug)      ACCEPT
///     priv suberror Boom of String          REJECT [3002]
///     priv suberror Boom(String)            REJECT [3002]
///     priv suberror Boom(msg : String)      REJECT [3002]
///
/// A body-less suberror cannot carry a payload at all, so `derive` is the only
/// word that can follow the name. `declared_name_after_kw` is used rather than a
/// positional read because it already encodes the `[...]` and path cases; the
/// grammar does not currently need that, and a positional read would be reading a
/// property of today's grammar rather than of the declaration.
///
/// NOT AN `enum`. An enum's type name is not a constructor — `enum Shape { Circle }`
/// does not make `Shape` a value — so this rule is scoped to `suberror` alone.
///
/// WHY NO CORPUS NUMBER MOVED, measured rather than assumed. moonbitlang/async
/// 0.22.4 has 12 body-less suberror declarations and 10 bare `raise Name` sites
/// across 7 files, and this fix left all six corpus summaries byte-identical. The
/// reason is that `collect_declared_names` has ALWAYS carried the name: a
/// body-less suberror's name is the token right after the keyword, and
/// `declares_value("suberror")` is true, so it has always been written into
/// `tab.values` (the sibling table, built per directory at `sa/main.mbt:1188`).
/// Probed directly:
///
///     collect_declared_names("priv suberror Boom ...")
///       Boom.value = Some(true)   Boom.type = Some(true)
///
/// So a PACKAGE scan always resolved the name from the sibling table and never
/// reached `enum_ctors` at all. Only the intra-file path was missing it, which is
/// what a single-file run with an empty table sees — and what three tests in
/// `pipeline_0460_test.mbt` see, by handing `IfaceSymTab::empty()`.
///
/// This is also exactly why 0461 was needed and 0463 was not. A braced suberror's
/// CONSTRUCTORS live in the BODY, which `declared_name_after_kw` never sees, so
/// both tables missed them and 13 corpus findings were real. 0463's name is right
/// after the keyword, so the sibling table was never wrong about it.
///
/// => 判据: do NOT remove this harvest on the reasoning that the sibling table
/// already covers the name. It does — for a package scan. This is the intra-file
/// table, it is the one `pipeline.run` is given an EMPTY `IfaceSymTab` with, and
/// "no corpus number moved" is the strongest possible argument that this gap is
/// invisible to measurement, which is not the same as the gap being absent.
fn Parser::harvest_bodyless_suberror(self : Parser) -> Unit {
  match declared_name_after_kw(self.toks, self.p) {
    Some(d) => if !self.enum_ctors.contains(d) { self.enum_ctors.push(d) }
    None => ()
  }
}

///|
/// Collect the constructor names of an `enum` body that is being skipped,
/// scanning the token range `from ..< to` — the inside of the braces.
///
/// A member of an enum body is a name followed by an optional payload
/// `(...)` or `{ ... }`. Every token of a payload is nested at least one level
/// deep, so a NAME at depth 0 is a member head and nothing else. A NAME
/// directly after `::` or `.` is the tail of a qualified path and is skipped,
/// because `A::B` names `A`.
///
/// This is deliberately not a parse. The body is still reported as not
/// analysed, and a harvested name resolves to "a value whose type is
/// unknown" — the same shape a name from another package gets. What is
/// recovered is the one thing a name lookup needs and nothing more.
fn Parser::harvest_ctors(self : Parser, from : Int32, to : Int32) -> Unit {
  let mut depth = 0
  let mut i = from + 1
  while i < to && i < self.toks.length() {
    match self.toks[i] {
      TLBrace | TLParen | TLBracket => depth += 1
      TRBrace | TRParen | TRBracket => depth -= 1
      TName(n) =>
        if depth == 0 &&
          !self.after_path_marker(i) &&
          !self.enum_ctors.contains(n) {
          self.enum_ctors.push(n)
        }
      _ => ()
    }
    i += 1
  }
}

///|
/// True when the token before `i` is a `.`, i.e. the name at `i` is the tail
/// of a field or package path rather than a member head. `::` arrives as two
/// `TColon` tokens, but a name after a colon is a type parameter in the
/// payload and always nested, so depth 0 already excludes it.
fn Parser::after_path_marker(self : Parser, i : Int32) -> Bool {
  if i <= 0 {
    return false
  }
  match self.toks[i - 1] {
    TDot => true
    _ => false
  }
}

///|
/// Collect the names a `.mbt` source declares at the TOP LEVEL, as an
/// `IfaceSymTab`: `fn` / `let` / `const` / `extern` declare values,
/// `struct` / `enum` / `trait` declare types, and `type` / `suberror` are
/// usable as either.
///
/// A MoonBit package is a DIRECTORY — every `.mbt` in it is one compilation
/// unit — so a top-level name declared in one file is visible in its siblings.
/// This analyzer resolved cross-file names only through `.mbti`, and a
/// generated interface carries `pub` items alone, so every package-private
/// top-level name came out invisible. Measured on riantr/pyroduct 0.1.29:
/// 26 of that scan's 31 actionable findings were exactly this, all of them
/// package-private top-level `fn`s in the SAME directory as their call site
/// (`sieve`, `ridge_fit`, `ridge_predict`, `ols_core`, `normal_cdf`, `fmt`,
/// `claim_code`, `claim_of`, `phase_code`, `contains_state`, `has_state`). A
/// toolchain probe settled that the language accepts them — `moon check` and
/// `moon test` both pass on a two-file package where one file calls the
/// other's private `fn`, including across `_test.mbt` — so every one was a
/// false positive about this analyzer.
///
/// Deliberately a token scan, not a parse, for the reason `harvest_ctors` is:
/// the caller needs the NAMES and nothing more, and lexing is the cheap half
/// of a parse. This runs once per file under the target.
///
/// The depth-0 rule is what keeps this a harvest rather than a suppressor: a
/// binding inside a function, a `test`, an `extend` or an `impl` block sits at
/// least one brace deep and is never collected, so a local `let` cannot make
/// itself visible package-wide. The name must be the token IMMEDIATELY after
/// the keyword, which is what excludes a destructuring `let (a, b) = ...` —
/// `(` follows the keyword, not a name, so nothing is collected.
///
/// Best-effort by construction: an unbalanced brace drifts the depth counter
/// and the remainder of the file contributes nothing. That is the trust level
/// of any partially-read file, and it errs toward silence, not toward a false
/// finding.
///
/// ENUM VARIANTS (0.4.17). A variant is a brace-declared value, so the depth-0
/// rule above cannot see it: `enum Mode { Select Rect }` declares five names
/// that no sibling file could resolve, and one of them was reported on
/// riantr/moonbit_labeler 0.2.13 `app_moui/canvas_view_test.mbt:4917` —
///
///     fn every_mode() -> Array[Mode] {
///       [Select, Rect, Polygon, Keypoint, EditBinding]
///     }
///
/// `Mode` and all five variants live in `app_moui/app.mbt`, the same package
/// directory, and `moon check` accepts the file. This is the cross-file twin of
/// the in-file unit-variant gap 0.4.15 closed with a path-tail fallback, and it
/// is what a bare reference exercises: `Mode::Select` resolves through that
/// fallback, `[Select, ...]` does not.
///
/// The rule is deliberately narrow, because the whole enum body is not safe to
/// harvest: a payload's TYPE is also a brace-declared name, and
/// `Conv2d(Params)` must not make `Params` package-visible. A name is a variant
/// only when it starts a line (or follows `{` or `|`) AND is not inside
/// parentheses AND is followed by `(`, `,`, `}`, a newline or `;`. A payload
/// type fails the parenthesis test even when it is laid out on its own line,
/// which is the one case a line-start rule alone would get wrong.
pub fn collect_declared_names(src : String) -> @core.IfaceSymTab {
  let (toks, spans, _) = @lexer.lex(src)
  let tab = @core.IfaceSymTab::empty()
  let mut depth = 0
  let mut i = 0
  // `enum` has been seen at depth 0 and the body has not opened yet.
  let mut enum_pending = false
  // Inside the braces of that enum, and only those braces.
  let mut enum_body = false
  let mut paren = 0
  // An `impl` / `trait` / `extend` has been seen at depth 0 and its body has not
  // closed yet. Everything declared in that span is a METHOD.
  let mut in_holder = false
  while i < toks.length() {
    match toks[i] {
      TLBrace => {
        if enum_pending && depth == 0 {
          enum_body = true
        }
        enum_pending = false
        depth += 1
      }
      TRBrace =>
        // clamped at zero: a stray `}` must not make every later top-level
        // declaration look nested, which would silently drop the rest of the
        // file rather than mis-name one binding
        if depth > 0 {
          depth -= 1
          if depth == 0 {
            enum_body = false
            in_holder = false
          }
        }
      TLParen => if enum_body && depth == 1 { paren += 1 }
      TRParen => if enum_body && depth == 1 && paren > 0 { paren -= 1 }
      TName(n) =>
        if depth == 0 && method_holder(n) {
          // The holder's OWN name is still a package-level binding when the
          // holder declares it: `trait Marker { ... }` declares the type
          // `Marker`, and dropping it broke "collect_declared_names: every
          // top-level form pyroduct actually uses".
          //
          // `impl` and `extend` declare NOTHING — `impl Eq for T` names the
          // trait being implemented, which is declared somewhere else — so
          // only `trait` contributes a name.
          if n == "trait" {
            match declared_name_after_kw(toks, i) {
              Some(d) => tab.types.set(d, true)
              None => ()
            }
          }
          in_holder = true
        } else if depth == 0 && n == "using" {
          // A re-export block. Collected here because this is where the
          // package's top-level names are enumerated, and a re-export is a
          // declaration: the names it lists ARE bound in this package.
          //
          // Measured on wzzc-dev/moui 0.1.12: 115 such lines across 19 files,
          // and before this none of the names reached a sibling file, so
          // `views_ambient_theme`, `max_view_double`, `view_record_key`,
          // `view_double_option_key` and `view_layout_declaration` were each
          // reported as undefined variable by their own package.
          i = collect_using(toks, i, tab) - 1
        } else if depth == 0 &&
          !in_holder &&
          (declares_value(n) || declares_type(n)) {
          if n == "enum" || n == "suberror" {
            // 0461 -- `suberror` ARMS THE SAME BODY HARVEST as `enum`, and did not.
            // A suberror's constructors are declared inside a brace body exactly
            // like an enum's variants, they are ordinary bare names in MoonBit
            // (settled, `_verify/settle_0461_constructors.ps1`, 5/5:
            // `raise InvalidBlock("bad")` compiles against
            // `priv suberror FormatError { InvalidBlock(String) }`), and without
            // this the TYPE was registered while every CONSTRUCTOR was not.
            //
            // Measured cost of the omission, 13 false positives in two files:
            // async `gzip_internal/decoder.mbt` x10 `no visible binding for
            // 'InvalidBlock'` (declared in `metadata.mbt`, used in `decoder.mbt`
            // -- a SIBLING, which is why this harvest is the one that matters),
            // plus `'InvalidTrailer'` and `'NeedMoreInput'`; proton
            // `native.mbt` x3 `'RuntimeActive'`, `'RuntimeDestroyed'`,
            // `'WindowLive'`.
            //
            // `ends_variant` already accepted `(`, so a constructor with a payload
            // was not the missing half -- the arming was.
            enum_pending = true
          }
          match declared_name_after_kw(toks, i) {
            Some(d) => {
              if declares_value(n) {
                tab.values.set(d, true)
              }
              if declares_type(n) {
                tab.types.set(d, true)
              }
            }
            None => ()
          }
        } else if enum_body &&
          depth == 1 &&
          paren == 0 &&
          starts_variant(toks, spans, i) &&
          ends_variant(toks, i + 1) {
          tab.values.set(n, true)
        }
      TNewline => enum_pending = false
      _ => ()
    }
    i += 1
  }
  tab
}

///|
/// The names inside one `using @pkg { ... }` block, recorded into `tab`.
/// Returns the index just past the closing brace.
///
/// The rule mirrors what the `.mbti` frontend does at `moonfiles.mbt:1185`, and
/// the two halves of the alias rule are the `.mbti` frontend's:
///
///   - `type X` and `trait X` bind a TYPE. `pub using @core {type View}` is 41
///     of moui's 115 lines and this is what makes `View` resolvable.
///   - a BARE `x` binds something whose kind this scanner cannot know, so it
///     goes into BOTH halves — the same thing `type` and `suberror` already do
///     in `declares_value` / `declares_type`, and the same trade: a name in the
///     table is a name that is not reported, never one that is.
///   - `X as Y` exports Y. X lives in the other package and is NOT visible here,
///     which `moonfiles_test.mbt` already pins for the `.mbti` side
///     (`type Iter as Iterator` records `Iterator` and not `Iter`).
///
/// The package qualifier between `using` and `{` is stepped over rather than
/// read: nothing downstream needs it, and `@wzzc-dev/moui/core` does not
/// tokenize the way this frontend would have to model to read it correctly.
fn collect_using(
  toks : Array[@lexer.Tok],
  i : Int32,
  tab : @core.IfaceSymTab,
) -> Int32 {
  let n = toks.length()
  let mut j = i + 1
  // step to the brace
  while j < n && !(toks[j] is TLBrace) {
    j += 1
  }
  if j >= n {
    return n
  }
  j += 1
  let mut is_type = false
  while j < n && !(toks[j] is TRBrace) {
    match toks[j] {
      TName(kw) =>
        if kw == "type" || kw == "trait" {
          is_type = true
        } else if kw == "as" {
          // the next name is the exported one
          if j + 1 < n {
            match toks[j + 1] {
              TName(exported) =>
                if is_type {
                  tab.types.set(exported, true)
                } else {
                  tab.values.set(exported, true)
                  tab.types.set(exported, true)
                }
              _ => ()
            }
            j += 1
          }
        } else if is_type {
          tab.types.set(kw, true)
        } else {
          tab.values.set(kw, true)
          tab.types.set(kw, true)
        }
      TComma => is_type = false
      TNewline => ()
      _ => ()
    }
    j += 1
  }
  if j < n {
    j + 1
  } else {
    n
  }
}

///|
/// Does the name at `i` sit where a variant is written?
///
/// Line-start is the MoonBit convention and is read from the spans rather than
/// from a newline token, because the lexer suppresses newlines after openers
/// and binary operators. `{`, `,` and `|` join it as variant positions because
/// the comma-separated one-line body `enum E { A, B }` is legal and would
/// otherwise yield only its first variant.
fn starts_variant(
  toks : Array[@lexer.Tok],
  spans : Array[@core.Span],
  i : Int32,
) -> Bool {
  if i == 0 {
    return true
  }
  match toks[i - 1] {
    TBar | TLBrace | TComma => return true
    _ => ()
  }
  if i - 1 >= spans.length() || i >= spans.length() {
    return false
  }
  spans[i].start.line != spans[i - 1].end.line
}

///|
/// What may follow a variant name.
///
/// The set is the grammar's, not a guess: a variant either takes a payload
/// (`Conv2d(`), is separated from the next by `,`, ends the body with `}`, or
/// simply ends the line. A bare name followed by something else is an
/// expression inside the enum body, which MoonBit has none of — so refusing it
/// is what keeps the harvest from walking off into unrelated text.
fn ends_variant(toks : Array[@lexer.Tok], i : Int32) -> Bool {
  if i >= toks.length() {
    return false
  }
  match toks[i] {
    // 0461 -- `TAssign` is the DISCRIMINANT: `RuntimeActive = 0`. Accepted only
    // after the toolchain said so (`_verify/settle_0461_constructors.ps1` 7/7,
    // `enum_variant_discriminant`), not because a variant plausibly has one.
    //
    // Measured cost of its absence: proton 0.3.4 declared
    //     priv enum RuntimeLifecycleState { RuntimeActive = 0 ... }
    // in `internal/native/types.mbt:1409` and used the variants bare in the
    // SIBLING `internal/native/native.mbt`, which reported
    // `undefined name 'RuntimeActive'` and two siblings. The harvest was armed
    // and the names were well-formed -- only the token after them was refused.
    TLParen | TComma | TRBrace | TNewline | TSemi | TAssign => true
    _ => false
  }
}

///|
/// The declaration name starting at token `i`, following `::` so a top-level
/// `fn Foo::new(...)` is collected as `Foo::new` rather than as a `Foo` that
/// may not exist at all. `::` arrives as two `TColon` tokens.
///
/// Returns `None` unless a name starts exactly at `i`. That immediacy is the
/// guard described on `collect_declared_names`: a keyword whose next token is
/// a `(` or a string declares nothing this harvest can name.
fn declared_name_at(toks : Array[@lexer.Tok], i : Int32) -> String? {
  if i >= toks.length() {
    return None
  }
  match toks[i] {
    TName(n) => {
      if i + 3 < toks.length() {
        match (toks[i + 1], toks[i + 2], toks[i + 3]) {
          (TColon, TColon, TName(m)) => return Some(n + "::" + m)
          _ => ()
        }
      }
      Some(n)
    }
    _ => None
  }
}

///|
/// A top-level keyword whose next name is a VALUE binding. `type` and
/// `suberror` are here as well as in `declares_type` because both are usable
/// in value position — `Alias(1)` for `type Alias = Int`, and a suberror's
/// constructor.
fn declares_value(kw : String) -> Bool {
  kw == "fn" ||
  kw == "let" ||
  kw == "const" ||
  kw == "extern" ||
  kw == "type" ||
  kw == "suberror"
}

///|
/// A top-level keyword whose next name is a TYPE binding.
fn declares_type(kw : String) -> Bool {
  kw == "struct" ||
  kw == "enum" ||
  kw == "trait" ||
  kw == "type" ||
  kw == "suberror"
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
          TStr(s, _) => s
          _ => "?"
        },
        sp,
      )
    }
  }
}

///|

///|
/// How a token is NAMED inside a diagnostic.
///
/// WHY THIS EXISTS. `parse_atom`'s catch-all used to emit a bare "unexpected
/// token". That sentence is true and useless: on wzzc-dev/moui 0.1.12 it was the
/// recorded reason for 110 of the 122 files the frontend cannot read at all --
/// 90% of every coverage blocker in the corpus behind a message that does not say
/// which token stopped the parse. The scanner tallies partial files BY REASON
/// MESSAGE, so the message is the ranking key: naming the token turns one
/// anonymous `110x` row into a distribution, with no change to any other layer.
///
/// The wording follows the toolchain's own -- `moon check` says "Parse error,
/// unexpected token `,`, you may expect ..." -- so a reader can put the two
/// side by side on the same file without translating vocabularies.
///
/// EXHAUSTIVE OVER ALL 46 `Tok` VARIANTS ON PURPOSE. There is no `_ =>` arm. A
/// new variant must break the build here rather than land in a fallback that
/// names nothing, which is the defect being fixed.
///
/// Compound spellings are assembled from the tokens the lexer really emits
/// rather than from a table, because the lexer has no compound-operator tokens
/// for them: `>>=` arrives as `TGt`, `TAssign`. Rendering from the tokens keeps
/// the two in step by construction.
fn tok_desc(t : @lexer.Tok) -> String {
  match t {
    TInt(i) => "integer `\{i}`"
    TBigInt => "an integer literal too wide to read"
    TFloat(f) => "float `\{f}`"
    TStr(_, _) => "a string literal"
    TName(n) => "`\{n}`"
    TPlus => "`+`"
    TMinus => "`-`"
    TStar => "`*`"
    TSlash => "`/`"
    TPercent => "`%`"
    TAssign => "`=`"
    TPlusEq => "`+=`"
    TMinusEq => "`-=`"
    TStarEq => "`*=`"
    TSlashEq => "`/=`"
    TPercentEq => "`%=`"
    TEqEq => "`==`"
    TNe => "`!=`"
    TLt => "`<`"
    TLe => "`<=`"
    TGt => "`>`"
    TGe => "`>=`"
    TAndAnd => "`&&`"
    TOrOr => "`||`"
    TAmp => "`&`"
    TCaret => "`^`"
    TShl => "`<<`"
    TShr => "`>>`"
    TPipeLt => "`<|`"
    TPipeGt => "`|>`"
    TAppendPlus => "`<+`"
    TBar => "`|`"
    TBang => "`!`"
    TQuestion => "`?`"
    TTilde => "`~`"
    TRange => "`..`"
    TRangeIncl => "`..<=`"
    TLParen => "`(`"
    TRParen => "`)`"
    TLBrace => "`{`"
    TRBrace => "`}`"
    TLBracket => "`[`"
    TRBracket => "`]`"
    TComma => "`,`"
    TColon => "`:`"
    TArrow => "`->`"
    TDot => "`.`"
    TSemi => "`;`"
    TNewline => "a line break"
    TEOF => "end of file"
  }
}

///|
/// A FUNCTION TYPE: `( A, B, ... ) -> C`, with `?` allowed after either half.
///
/// Each element is read by `type_annotation` itself, which is what makes the
/// nesting work — `((String) -> Msg)?` is a function type returning a function
/// type, and it appears 169 files' worth more often than the flat form. The
/// result is RENDERED faithfully rather than flattened, so the string handed to
/// the type lens still says what it said. `ann_to_ty` has no case for a `(`-
/// leading annotation and returns `TUnknown`, which is the honest answer: the
/// lens models no function types, and an unknown is what keeps every operation
/// on one silent.
///
/// A bare `(A)` with no `->` is not a function type and renders as `(A)`, which
/// is also `TUnknown` — the same answer it had before this existed, so nothing
/// becomes quieter than it was.
fn Parser::fn_type_annotation(self : Parser) -> String {
  let _ = self.bump() // (
  // 0458 -- the ASYNC function type, `(async (A, B) -> R)?`.
  //
  // Without this, `async` was read as an ordinary type NAME by the first
  // `type_annotation()` below, the parameter loop then broke on the `(` that
  // followed it rather than on a comma, and `expect(TRParen)` reported
  // `expected ')'` -- which is what stopped wzzc-dev/moui 0.1.12
  // `runtime/app_builder.mbt:47`, the last file that corpus could not finish.
  //
  // `async` IS followed by `(` in every shape the grammar admits, the same
  // argument 0456 made for the `@`-qualified `is` head: there is no `async` type
  // without a parenthesised parameter list. So the lookahead is a discriminator
  // rather than a guard -- but it is still written as one, because a reader who
  // has not read the settle should not have to take that on faith. The settle
  // (`_verify/settle_0458_async_fn_type.ps1`, 7/7) also pins the part that is NOT
  // obvious: the trailing `?` makes the RETURN type optional, it does not lift
  // the group into a nullable function type. `async (A, B) -> R?` is the reading,
  // and the `?` is emitted below by the clause that already existed.
  // 0467 -- THE HEAD IS NO LONGER DETECTED HERE, and removing it is the fix rather than
  // a tidy-up.
  //
  // This function used to look for `async` itself, which it had to: `fn_type_body`'s
  // parameter loop routes every element through `type_annotation()`, and back then
  // `type_annotation()` had no `async` arm, so an inner `async` arrived as an ordinary
  // type name. 0467 gave `type_annotation()` that arm, so the head is now found on the
  // way in -- and detecting it a SECOND time here did not merely duplicate work, it
  // duplicated the HEAD: `(async (Int) -> Unit)?` rendered
  // `async (async (Int) -> Unit)?`, which parses, reports nothing, and is the wrong
  // string.
  //
  // The mutation gate is what found it: M4 removed exactly these six lines and SURVIVED
  // every parse-level row, because "it parses" cannot see a doubled annotation. The
  // row that kills it is in `parser_0467_test.mbt`, and it asserts the STRING.
  self.fn_type_body("")
}

///|
/// The `( Args ) -> R [effect] [?]` body of a function type, with the head already
/// decided by the caller.
///
/// 0467. This was the tail of `fn_type_annotation`, extracted because the SAME
/// construct is spelled three ways and only one of them worked:
///
///     (async (A, B) -> R)?        a parenthesised annotation   -- WORKED (0458)
///     async (A, B) -> R           a bare parameter annotation  -- parsed=0
///     -> async (A, B) -> R        a bare return annotation    -- parsed=0
///
/// The second reading is `moon check`'s own verdict on the third spelling, measured
/// by running this analyzer over one file containing each shape, not by reading the
/// code: `parsed=1` for the parenthesised form and `parsed=0` for both bare ones.
/// The cause is an ORDERING fact, not a missing keyword: the `async` lookahead in
/// `fn_type_annotation` sits AFTER its `let _ = self.bump() // (`, so it can only
/// ever see `async` when something already put a `(` in front of it.
///
/// => 判据: a construct that is correct in one position and absent in another is
/// usually an ENTRY POINT, not a rule. Keeping one body and three thin entry points
/// is what stops the three from drifting again -- a second copy of the parameter
/// loop would have been the tidier-looking edit and would have been a fourth
/// spelling to keep in step.
fn Parser::fn_type_body(self : Parser, prefix : String) -> String {
  let mut out = prefix
  let params : Array[String] = []
  while !self.at(TRParen) && !self.at(TEOF) {
    self.skip_seps()
    if self.at(TRParen) || self.at(TEOF) {
      break
    }
    params.push(self.type_annotation())
    self.skip_seps()
    if self.at(TComma) {
      let _ = self.bump()
    } else {
      break
    }
  }
  self.skip_seps()
  self.expect(TRParen, "')'")
  // `out` already carries the `async ` head if there was one, so this appends to
  // it rather than re-declaring it.
  out = out + "("
  let mut first = true
  for p in params {
    if first {
      first = false
    } else {
      out = out + ", "
    }
    out = out + p
  }
  out = out + ")"
  if self.at(TArrow) {
    let _ = self.bump()
    let ret = self.type_annotation()
    out = out + " -> " + ret
  }
  // A function type may carry its OWN raise effect, and this is the same clause
  // as the signature form -- `() -> Int raise`, `() -> Int raise E`. Settled
  // valid in a parameter position and in a return position, both with zero
  // errors from `moon check`. Reading the clause in one position but not the
  // other leaves a program that parses as `fn f() -> Int raise` and then dies
  // on the very next function that takes a callback: 29 files of
  // wzzc-dev/moui 0.1.12 and 33 of moonbit-community are exactly that shape.
  self.parse_raise_effect()
  if self.at(TQuestion) {
    let _ = self.bump()
    out = out + "?"
  }
  out
}

///|
/// A type annotation: an optional `&`, a head name, then any number of
/// `[...]` argument lists and `.Tail` segments.
///
/// `&T` is NOT a reference type — it is `Ref[T]`, a container whose element
/// type must be a TRAIT. Settled with `moon check` (0.4.18), which reports
/// `x : &Node` as "The type Node is not a trait" and gives `x` the type
/// `@moonbitlang/core/ref.Ref[Node]`; wzzc-dev/moui only ever writes it on a
/// trait (`data : &RuntimeViewNode`), which is the shape that typechecks. The
/// `&` used to reach `expect_name` first, so it reported "expected type name"
/// and then lost the rest of the token stream: a six-parameter declaration with
/// one reference produced 15 ParseErrors, which is how
/// `runtime/text_input_state.mbt:42` was reported as "expected 2, got 6"
/// arguments when the call site passes six.
///
/// The `&` is FOLDED into the returned name rather than dropped, for the same
/// reason `Int?` is: dropping it would claim `&T` was read as bare `T`, which
/// it was not. `ann_to_ty` has no case for a `&` head, so it returns
/// `TUnknown` — the honest answer, and the same one `Map[K, V]` already gets.

///|
/// `Array[Double]` was the single largest parse blocker measured across real
/// projects: 74 of 84 blocked files stopped on it, counting the tuple returns
/// that contain one (`-> (Matrix, Array[Double])`).
///
/// `-> @pkg.T` (a qualified package type with a `.Tail`, as in
/// `-> @argparse.Command`) is the second-most-common shape in real code
/// and was a blocker before: the head name and the `.Tail` are emitted as
/// separate tokens, and the parser had no path to consume the `.` and the
/// tail name after the head. Fixed by accepting one or more `.Name` tails
/// and folding them into the returned name.
///
/// **The head's `[...]` arguments are now KEPT rather than discarded** (0.4.13),
/// which reverses the note that stood here before: "the type lens does not
/// model containers, so `Array[Double]` and `Array` reach it identically".
/// The type lens DOES model `Array[T]` now, and it has to: the subscript check
/// fires only when the base is known to be a list, so `xs["k"]` on an
/// `Array[String]` PARAMETER — where the annotation was arriving as bare
/// `"Array"` — stopped being reported at all. Two real errors, both confirmed
/// by `moon check` as "Expr Type Mismatch", silently lost because the
/// precondition was narrowed while the thing it depends on was still thrown
/// away upstream. Keeping the arguments restores them AND keeps the
/// false-positive side fixed (`Map[String, Int]` is still Unknown, so a map
/// subscript stays silent).
///
/// The arguments are re-rendered from TOKENS, not copied from source: the
/// parser holds no source text. Names, brackets, commas, dots, colons and
/// `?` are rendered; anything else inside an argument list is dropped. That is
/// lossless for the type spellings this lens reads, and `ann_to_ty` returns
/// Unknown for anything it does not recognise — so a dropped token can only
/// cost precision, never invent a type. A `.Tail` argument list
/// (`@pkg.T[X]`) is still discarded, since the head is already qualified.
fn Parser::type_annotation(self : Parser) -> String {
  // `(A, B) -> C` — a FUNCTION TYPE, and the single largest remaining parse
  // blocker: 845 parameter annotations of this shape across 171 files of
  // wzzc-dev/moui 0.1.12 (`on_input~ : ((String) -> Msg)?`, `key : (T) ->
  // String`, `measure~ : (@core.Constraints) -> @core.Size`). The `(` used to
  // reach `expect_name`, which reported "expected type name" and ended the file.
  if self.at(TLParen) {
    return self.fn_type_annotation()
  }
  // 0467 -- the ASYNC function type with NO parentheses of its own, which is how a
  // parameter writes it and how a return type writes it:
  //
  //     f : async () -> Unit,                             src/task_group.mbt:50
  //     f : async (Tcp, Addr) -> Unit,                    src/socket/tcp.mbt:143
  //     f : async (Request, &@io.Reader, ServerConn) -> Unit   src/http/server.mbt:294
  //     -> async (Int) -> Unit                            the return spelling
  //
  // 19 unread files across the two corpora stop on this shape -- 11 async, 8 proton --
  // and it is the largest single group measured on the tree that shipped as 12b38a3.
  //
  // `lparen_at(self.p + 1)` is not a stylistic choice, it is the settled grammar. The
  // toolchain's own diagnostic for a bare `async` is the whole argument:
  //
  //     fn f(g : async) -> Int { .. }
  //     Parse error, unexpected token `)`, you may expect `(`.
  //
  // `_verify/settle_0467_async_param_type.ps1`, row `canary_bare_async`. So there is no
  // `async` type without a parameter list, and the lookahead is a discriminator rather
  // than a guard -- written as one anyway, for the same reason 0458 wrote its own as
  // one. The companion canary is `canary_any_name`: `bogus (Int) -> Unit` REJECTs with
  // 3002, so this is a KEYWORD slot and not "a name followed by a parenthesised list".
  // BOTH bumps below, and not one. `fn_type_body` starts INSIDE the parentheses --
  // `fn_type_annotation` has already consumed the `(` by the time it calls it -- so a
  // single bump here leaves the cursor sitting ON the `(` and the body reads `(Int)`
  // as a nested type before tripping over `->` with `expected ')'`. Measured, not
  // reasoned: the first version bumped only `async` and every one of these shapes
  // reported `expected ')'` twice.
  //
  // The explanation lives HERE rather than inside the arm so that the arm is four lines
  // of code, which is what makes it a usable mutation anchor. A comment inside it made
  // the anchor depend on prose, and a mutation anchor that depends on prose is one
  // `moon fmt` reflow away from being silently retired -- which is exactly what happened
  // to gate 0460's M4 in the same increment.
  if self.at_name("async") && self.lparen_at(self.p + 1) {
    let _ = self.bump() // async
    let _ = self.bump() // (
    return self.fn_type_body("async ")
  }
  // `&T` = `Ref[T]`. Consumed here, folded into the name below, so the head
  // name is still a TName and the rest of the parameter list stays in step.
  let amp = if self.at(TAmp) {
    let _ = self.bump()
    "&"
  } else {
    ""
  }
  let (name, _) = self.expect_name("type name")
  let mut n = amp + name + self.indexed_suffix()
  // Consume a `.Tail` chain. `@pkg.T.U.V` becomes "@pkg.T.U.V" in the name
  // returned to the caller; the lexer does not include the `.` in TName.
  while self.at(TDot) {
    let _ = self.bump()
    let (tail, _) = self.expect_name("type tail")
    n = n + "." + tail
    self.skip_indexed()
  }
  // `Int?` — an optional/nullable type. Folded into the name rather than
  // dropped: `ann_to_ty` maps it to Unknown either way, but dropping the `?`
  // would claim `Int?` was read as plain `Int`, which it was not.
  if self.at(TQuestion) {
    let _ = self.bump()
    n = n + "?"
  }
  n
}

///|
/// The `[...]` argument list at the cursor, rendered into a string, or `""`
/// when the cursor is not on a `[`. Returns with the cursor past the group.
///
/// Nesting is tracked, so `Array[Array[Int]]` renders whole. An unterminated
/// group (EOF reached first) still returns whatever was read — the same
/// best-effort contract as the rest of the parser, and the enclosing file is
/// already partial in that case.
fn Parser::indexed_suffix(self : Parser) -> String {
  if !self.at(TLBracket) {
    return ""
  }
  // Starts EMPTY, not "[": the loop below writes the opening bracket itself
  // when it sees the `[`. Seeding it here duplicated the bracket —
  // `Array[String]` rendered as `Array[[String]]`, whose element slice came
  // out as the unterminated `"[String"` and so typed as `TUnknown`. That single
  // character turned every annotated `Array[T]` into an unknown-element list
  // and produced 58 fresh false positives on this repo and pyroproduct, which
  // is how it was found: a narrowing change that made the type lens speak up
  // about a string it was never supposed to see.
  let mut out = ""
  let mut depth = 0
  while !self.at(TEOF) {
    let t = self.peek()
    if self.at(TLBracket) {
      depth += 1
      out = out + "["
    } else if self.at(TRBracket) {
      depth -= 1
      out = out + "]"
    } else {
      match t {
        TName(n) => out = out + n
        TComma => out = out + ","
        TDot => out = out + "."
        TColon => out = out + ":"
        TArrow => out = out + "->"
        TQuestion => out = out + "?"
        _ => ()
      }
    }
    let _ = self.bump()
    if depth == 0 {
      break
    }
  }
  out
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
  // A FUNCTION TYPE, in either of the two spellings MoonBit accepts. Both are
  // settled valid with zero real errors from `moon check` (settle_0427_retfn):
  //
  //   UNPARENTHESISED   `-> (Int) -> String`    the `->` is AFTER the parens
  //   PARENTHESISED     `-> (() -> Int)`        the `->` is INSIDE them
  //
  // The original test only looked for the first, so the second fell into the
  // tuple arm below. That arm consumes to the first `)` with no comma, which
  // here is the one closing the EMPTY parameter list — so the annotation ended
  // at `()`, and `-> Int)` was left in the token stream. `parse_block` then
  // looked for `{`, found `->`, and reported `expected '{'`; after that the file
  // died. A false positive about code the compiler accepts, and a misleading
  // one: the message names a brace that was never the problem.
  //
  // So the test is "is there a `->` associated with these parens", and there are
  // exactly two places it can be — inside them, or immediately after the
  // matching `)`. One nesting-tracking scan answers both.
  //
  // (An earlier version of this test looked only at the three tokens `(`, `)`,
  // `->`, which is the shape of `() -> T` and nothing else: `(Int) -> String`
  // has `Int` between the brackets, so it missed and its own fixture failed
  // with 4 parse errors. Real annotations have a parameter.)
  let fn_type = if self.at(TLParen) {
    let mut depth = 0
    let mut j = self.p
    let mut is_fn = false
    let mut arrow_inside = false
    while j < self.toks.length() {
      match self.toks[j] {
        TLParen => depth += 1
        TRParen => {
          depth -= 1
          if depth == 0 {
            is_fn = j + 1 < self.toks.length() && self.toks[j + 1] == TArrow
            break
          }
        }
        // `depth` is already 1 here -- the scan starts ON the opening paren --
        // so a `->` reaching this arm is inside the parentheses, which is the
        // parenthesised spelling. It must NOT fire on `(Int, String)` or
        // `(Int)`: measure_0427_retfn.ps1 counts 179 comma-bearing `-> (...)`
        // groups and 6 with neither a comma nor an arrow across the six corpora,
        // and every one of them has to keep parsing as what it is.
        //
        // (That measurement reported 0 sites of the shape ABOVE, twice, before it
        // was corrected -- see the script's header. The count of the look-alikes
        // came from the same corrected run.)
        TArrow => arrow_inside = true
        TEOF => break
        _ => ()
      }
      j += 1
    }
    arrow_inside || is_fn
  } else {
    false
  }
  if self.at(TLParen) && !fn_type {
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
    // `(A, B)?` — an optional tuple. The `?` must go, or the `{` that opens
    // the body is never reached; the tuple is "" (Unknown) either way.
    if self.at(TQuestion) {
      let _ = self.bump()
    }
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
/// The external BINDING tail of a `fn` declaration: `= "module" "symbol"`.
///
/// A `fn` whose body lives in another language is declared, not defined:
///
///     fn web_begin_create_string() -> Int = "window_web" "begin_create_string"
///     fn web_sync_semantics_host(
///       raw_id : Int,
///       canvas_id : WebHostString,
///       json : WebHostString,
///     ) -> Unit = "window_web" "sync_semantics"
///
/// Settled against `moon check` on 0.1.20261012 in
/// `_verify/settle_0449_ffi_decl.ps1`, 7/7 with BOTH negative controls firing.
/// All three shapes are ACCEPTed -- no parameters, a single-line parameter list,
/// and the multi-line one -- so the fourth site, which is the only multi-line
/// one, is settled by the same measurement as the other three rather than by
/// analogy with them.
///
/// WHY IT COST FOUR FILES. Without this the parser finished the signature, found
/// `=` where it wanted `{`, and reported `expected '{'` -- which is the parser
/// naming a token that was never the problem. Measured on the settled shapes, it
/// reports `2x expected '{'` and marks both files NOTPARSE. No FALSE POSITIVE
/// comes with it: the findings land in `unreliable`/`withheld`, because a file
/// the reader could not parse is reported as unread rather than as wrong, and
/// that is the honest classification.
///
/// Measured cost, on wzzc-dev/moui 0.1.12: FOUR of the seventeen files the
/// truncation ranking reports
/// (`_verify/diagnose_moui_truncations.ps1`), the largest single shape there.
/// `backend/web/accessibility.mbt` cut at line 370 hides 7 further lines,
/// `web_host.mbt` at 382 hides 80.
///
/// ONE OR TWO STRINGS, COUNTED RATHER THAN ASSUMED. `= "exit"` names a bare
/// symbol; `= "window_web" "sync_semantics"` names a MODULE and a symbol inside
/// it. `parse_extern_fn` already consumed exactly one string, which is right for
/// its `extern "c"` shape and leaves the second dangling on this one -- so this
/// helper consumes up to two and both call sites share it. Two sites implementing
/// one rule is the drift this repository has been bitten by before, and the fix
/// is the shared helper rather than a second careful inline block.
///
/// The `=` is consumed unconditionally once seen, because in signature position
/// nothing else can follow the return annotation before the body's `{`. That is
/// a claim about the grammar, so it is worth stating rather than leaving
/// implicit: there is no `fn` form where an `=` appears here and means anything
/// else. A `=` followed by NO string is not a binding and this returns false, but
/// the `=` is already gone -- `parse_block` will report `expected '{'` there,
/// which is the right complaint about a malformed declaration.
fn Parser::parse_external_binding(self : Parser, name : String) -> Bool {
  if !self.at(TAssign) {
    return false
  }
  let _ = self.bump()
  let mut seen = 0
  while seen < 2 && self.at_str() {
    let _ = self.bump()
    seen += 1
  }
  if seen == 0 {
    return false
  }
  // The name BINDS. A call to it must not read as an undefined function, and the
  // registration `parse_extern_fn` already does is what makes that true.
  if !self.extern_fns.contains(name) {
    self.extern_fns.push(name)
  }
  true
}

///|
fn Parser::parse_fn(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  let _ = self.bump() // fn
  let (name, params, retann) = self.parse_fn_signature()
  // Header-only, and not an inconsistency: this body lives in another language
  // and was never read, so there is nothing inside it that could carry an
  // unanalysed region, and `sp` is the whole extent there is. Same shape, same
  // reason, as the `extern` form in `parse_extern_fn`.
  if self.parse_external_binding(name) {
    return { span: sp, kind: @ast.SFunc(name, params, retann, [], sp), }
  }
  let (body, endsp) = self.parse_block(true)
  // The statement span stays the header (it is what `FUnreachable` and the
  // binding decl_spans localize against), while the SFunc's 5th field is now
  // the WHOLE function: header start to closing brace. See `parse_block`.
  {
    span: sp,
    kind: @ast.SFunc(name, params, retann, body, {
      start: sp.start,
      end: endsp.end,
    }),
  }
}

///|
/// `NAME ( params ) [ -> Type ]` — the part a `fn` and an `extern fn` share.
/// They differ only in what follows: a MoonBit block, or the raw symbol string
/// after `=`. Splitting it out is what lets the extern form carry a REAL
/// signature instead of being skipped as an unmodelled declaration.
///
/// The name may be qualified — `fn Queue::from_iter(...)` — and folds into
/// one name, exactly as the expression-side `::` fold does. The parameter
/// list may be absent — `fn main { ... }` — and is then empty: a paren-less
/// function's braces open its BODY, not a second parameter list.
///
/// A leading `[...]` is the TYPE-PARAMETER list of `fn[T]` / `fn[T : Bound]`
/// / `fn[+A]`. It is consumed and DISCARDED, because nothing downstream reads
/// it: the lenses this frontend models key off parameter types and call
/// arity, and a type variable is not either. That is the same trade the tuple
/// return type already makes below, and it is deliberately not a notice —
/// wzzc-dev/moui 0.1.12 writes `fn[` 1563 times across 266 files, so a
/// per-occurrence notice would bury every real finding under subset noise.
/// The cost is stated rather than hidden: `Msg` in `fn[Msg]` is not a known
/// type to the type lens, so it reads as `TUnknown`, exactly as an unmodelled
/// base type does.
///
/// Before this, the `[` reached `expect_name` and reported "unexpected token",
/// which ends the file: `views/presentation.mbt` stopped dead at line 152 on
/// `pub fn[Msg] PresentationSpec::new(`.
fn Parser::parse_fn_signature(
  self : Parser,
) -> (String, Array[@ast.Param], String) {
  self.skip_indexed()
  let (name, _) = self.expect_name("function name")
  let mut full = name
  if self.at(TColon) && self.at_next(TColon) {
    let _ = self.bump()
    let _ = self.bump()
    let (m, _) = self.expect_name("name after '::'")
    full = full + "::" + m
  }
  let params = self.parse_param_list()
  let mut retann = ""
  if self.at(TArrow) {
    let _ = self.bump()
    retann = self.return_annotation()
  }
  self.parse_raise_effect()
  (full, params, retann)
}

///|
/// The `raise` effect clause that may follow a function's return annotation:
/// `-> T raise`, `-> T raise E`, and the short form `-> T!`. All three are
/// settled valid MoonBit against `moon check` on 0.1.20261012.
///
/// Without this the parser stopped at the `raise` and reported "expected '{'"
/// at the body, which is the parser reporting a token it does not know rather
/// than a real syntax error. Measured cost: `wzzc-dev/moui` 0.1.12 has 149 files
/// with `-> T raise E` and EVERY ONE of them failed to parse at all -- not
/// partially, completely -- so this single clause was 24.5% of that corpus's
/// 608 files.
///
/// `raise` is not in the lexer's keyword list, so it arrives as a `TName` and is
/// matched with `at_name` here. The short form `!` is `TBang`, which the lexer
/// also uses for the boolean NOT operator; position is what tells them apart,
/// since this runs only just after a return annotation.
///
/// Nothing consumes the effect yet, and that is deliberate: the AST has no
/// field for it and no lens reads one. Adding a field to `SFunc` would ripple
/// through walk / types / infer / interp and the `.mbti` for a check that does
/// not exist. Consuming it is what makes the file readable; recording it is a
/// separate decision to take when something needs it.
fn Parser::parse_raise_effect(self : Parser) -> Unit {
  if self.at(TBang) {
    let _ = self.bump()
    return
  }
  // 0466 -- `noraise` and `nocancel`. Same slot, and the parser stopped at them, so
  // every one of them reported `expected '{'` at the body: a message about a brace
  // standing where a keyword is.
  //
  //   pub async fn Mutex::acquire(self : Mutex) -> Unit noraise {
  //   pub async fn remove(path : StringView) -> Unit nocancel {
  //
  // Measured reach is per-FILE first blocker over the files still unread: 16 files
  // (async 11, proton 5) of the 64 NOTPARSE files across the two corpora.
  //
  // THEY DO NOT CARRY AN ERROR TYPE, and that is the whole reason this is not folded
  // into the `raise` arm below. `-> T raise E` names one and the guard further down
  // is careful about where that type stops; `-> T noraise E` and `-> T nocancel E`
  // are both REJECTed with 3002 by the toolchain
  // (`_verify/settle_0466_effect_annotation.ps1`, rows `ret_noraise_with_type` and
  // `ret_nocancel_with_type`). So a shared tail would read a token that is not there
  // -- a SILENT misparse, which is the exact direction the guard's own comment says
  // to avoid, and the failure would land somewhere else in the file entirely.
  //
  // `raise` is the control for the gap being two keywords and not one: proton has 781
  // `-> T raise` sites and is not blocked at any of them, while the 16 files here are
  // blocked at exactly these two words.
  if self.at_name("noraise") || self.at_name("nocancel") {
    let _ = self.bump()
    return
  }
  if !self.at_name("raise") {
    return
  }
  let _ = self.bump()
  // `-> T raise` names NO error type. A bare `raise` must stop here, and what
  // follows it depends on which position the clause appeared in: the body's `{`
  // after a signature, or the `)` / `,` / `?` that closes a function type.
  // Settled: core/error/error_test.mbt uses the bare signature form
  // (`fn f(b : Bool) -> String raise {`) and `moon check` accepts
  // `fn f(g : () -> Int raise) -> Int` with zero errors.
  //
  // The guard asks "can this token begin a type at all" rather than listing
  // the tokens that terminate, because the safe direction is asymmetric.
  // Reading one token too many here is a SILENT misparse: the body gets
  // swallowed into the type annotation and nothing reports. Stopping one token
  // early is a loud `expected '{'`. So the guard admits exactly the heads
  // `type_annotation` accepts -- `TName`, `TLParen`, `TAmp` -- and nothing else.
  let type_head = match self.peek() {
    TName(_) | TLParen | TAmp => true
    _ => false
  }
  if !type_head {
    return
  }
  // No `skip_indexed()` here, and that is a measured decision rather than an
  // oversight. There was one, it was removed, and the mutation gate showed the
  // whole suite still green (371/371) with it gone: `type_annotation` already
  // calls `indexed_suffix()` on the name it reads, so `raise E[Int]` is consumed
  // whole without it. An `E[T]` that this line was credited with handling is in
  // fact handled one line down. Keeping an unobservable call would have made the
  // reader look responsible for a case it is not, and the next person to delete
  // it would have had no evidence that anything checked it.
  let _ = self.type_annotation()
}

///|
/// The parameter list of a function, shared by every `fn` form so the shapes
/// cannot drift: `( name (: Type)? (= default)?, ... )`.
///
/// A paren-less function has an EMPTY list — `fn main { ... }` opens its body
/// where the old parser demanded a `(`, and that was a measured blocker on
/// this analyzer's own source. `name?` is an optional parameter: the `?` is
/// consumed and the parameter stays a plain name, which is the same string
/// the type lens reads. `name = default` has its value parsed to keep the
/// token stream in step and then dropped: no lens reads defaults.
fn Parser::parse_param_list(self : Parser) -> Array[@ast.Param] {
  let params : Array[@ast.Param] = []
  if !self.at(TLParen) {
    return params
  }
  let _ = self.bump()
  while !self.at(TRParen) && !self.at(TEOF) {
    let (pname, psp) = self.expect_name("parameter name")
    // `name~` (must be passed BY LABEL) and `name?` (optional) are
    // independent modifiers written tight against the name. Either order is
    // accepted, and so is both at once (`name~? : T`). Neither changes the
    // parameter's NAME, so the binding table and the arity check are
    // unchanged — `f~ : T` is still one parameter called `f`.
    let mut more_mods = true
    while more_mods {
      more_mods = false
      if self.at(TQuestion) {
        let _ = self.bump()
        more_mods = true
      } else if self.at(TTilde) {
        let _ = self.bump()
        more_mods = true
      }
    }
    let mut ann = ""
    if self.at(TColon) {
      let _ = self.bump()
      ann = self.type_annotation()
    }
    if self.at(TAssign) {
      let _ = self.bump()
      // `= <lambda>` — a function-typed parameter whose default is a lambda.
      // `parse_expr` reads `(` as a parenthesised expression and then dies on the
      // `=>`, so the whole file stopped with `expected ')'`.
      //
      // Settled with the toolchain, not inferred — `_verify/grammar_probe.ps1`,
      // one form per package with a broken canary alongside:
      //   fn maker(sync? : (Int, Int) -> Unit = (_w, _m,) => (),) -> Int { 1 }
      //   fn maker2(sync? : (Int) -> Unit = (_w) => ()) -> Int { 1 }
      // both 0 errors from `moon check`. The control beside them —
      // `fn taker(cb : (Int) -> Unit) -> Int` with NO default — already parsed,
      // which is what makes this specific: a function-typed parameter is fine,
      // and only the `= <lambda>` default broke.
      //
      // The head/body split and the "do not PARSE the parameters" rule are the
      // call-argument path's (`at_lambda_head`, `skip_lambda_head`,
      // `skip_braces`, `skip_to_arg_boundary`) rather than a second
      // implementation: a parsed lambda parameter would bind in the ENCLOSING
      // scope and report a phantom unused, and the two sites drifting apart is
      // the failure mode worth spending the shared helper on.
      //
      // Measured cost on wzzc-dev/moui 0.1.12: this one shape is the blocker
      // behind the `expected ')'`, `unexpected token ':'`,
      // `expected a struct literal field here`, `expected '{'` and
      // `unexpected token ')'` rows of the NOTPARSE tally — the blocker reasons
      // differ per file because the cascade lands somewhere different, which is
      // precisely why the tally alone understates the class.
      if self.at_lambda_head() {
        let lsp = self.span()
        self.skip_lambda_head()
        if self.at(TLBrace) {
          self.skip_braces()
        } else {
          self.skip_to_arg_boundary()
        }
        self.note_skip(
          "short lambda is outside the analyzed subset; it was read but not analysed",
          lsp,
        )
      } else {
        ignore(self.parse_expr())
      }
    }
    params.push({ name: pname, tyann: ann, span: psp, })
    if self.at(TComma) {
      let _ = self.bump()
    } else {
      break
    }
  }
  self.expect(TRParen, "')'")
  params
}

///|
/// `extern "c" fn name(params) -> Ret = "symbol"`
///
/// This used to be skipped as an unmodelled declaration form, which was the
/// right call while it was unmodelled — but skipping it loses the NAME, and
/// every call site of an extern function was then reported as an unbound name:
///
///    extern "c" fn runtime_native_exit(code : Int) = "exit"
///    fn runtime_exit_success() -> Unit {
///      runtime_native_exit(0)          <- reported 'no visible binding'
///    }
///
/// 16 of moonbitlang/core's 882 `.mbt` files declare one. The implementation is
/// in another language, so the body is empty — which asserts nothing about what
/// the callee does while still binding the name and carrying the signature the
/// type lens needs.
fn Parser::parse_extern_fn(self : Parser, sp : @core.Span) -> @ast.Stmt {
  let _ = self.bump() // extern
  // `extern "c"` / `extern "wasm"` — an ABI name, not a type.
  if self.at_str() {
    let _ = self.bump()
  }
  if self.at_name("fn") {
    let _ = self.bump()
  }
  if self.at_name("async") {
    let _ = self.bump()
  }
  let (name, params, retann) = self.parse_fn_signature()
  if !self.extern_fns.contains(name) {
    self.extern_fns.push(name)
  }
  // `= "exit"` — the raw symbol in the target language, or `= "mod" "sym"` for a
  // two-part one. Nothing to model either way, and the SHARED helper is what
  // keeps this from becoming a third spelling of one rule: it used to be an
  // inline block here consuming exactly one string, which left the second
  // dangling on the JS form `parse_fn` now also accepts.
  let _ = self.parse_external_binding(name)
  // Header-only on purpose, and it is not an inconsistency: this body lives in
  // another language and was never read, so there is nothing inside it that
  // could carry an unanalysed region. `sp` is therefore already the whole
  // extent there is.
  { span: sp, kind: @ast.SFunc(name, params, retann, [], sp), }
}

///|
/// Parse a `{ ... }` block and return its statements TOGETHER WITH the span of
/// the closing brace.
///
/// `value_block` marks the block whose VALUE is its tail, and it is the only
/// thing that distinguishes a tail expression from an ordinary one. In a
/// function body a trailing expression is what the function returns;
/// `fn f() -> Int { 1 }` returns 1, while `fn g() -> Int { while c { 1 } }`
/// returns nothing at all. The same block parser reads loop bodies, `if` arms
/// and bare blocks, so without the flag it cannot tell those apart -- and
/// guessing wrong is silent, because a discarded value looks exactly like a
/// returned one until a caller tries to use it.
///
/// RENAMED FROM `fn_body` BY 0468, and the rename is the fix's other half. The
/// flag does not mean "this is a function body" -- it means "this block's last
/// statement is its value" -- and a block in the RHS of a `let` is a second
/// place that is true. Leaving the name alone would have let the next reader
/// read `parse_block(false)` at the `EBlock` call site as a considered
/// decision, when it was actually the bug: the block's two lenses key off
/// `STail`, so with the flag false no `EBlock` body ever contained one,
/// `Infer::ty_of` returned `TUnknown` for every block and `Interp::eval`
/// returned `AAny`. Both arms were dead code and the corpus numbers were
/// unmoved by them.
///
/// The span is why the return is a tuple. `SFunc` / `SLocalFunc` used to carry
/// the header span only, so a function's extent was unknown to everything
/// downstream — and a body the reader did not analyse (a `match`, a `try`, a
/// fn literal; see `Parser::note_skip`) could sit anywhere inside it without
/// the walk being able to tell "this frame was fully read" from "this frame
/// has a hole in it". `audit_suppressed` needs that extent.
///
/// The EOF path yields the EOF span: an unterminated block was not closed, and
/// claiming a span it does not have would invent coverage.

///|
fn Parser::parse_block(
  self : Parser,
  value_block : Bool,
) -> (Array[@ast.Stmt], @core.Span) {
  self.expect(TLBrace, "'{'")
  let body : Array[@ast.Stmt] = []
  while !self.at(TRBrace) && !self.at(TEOF) {
    self.skip_seps()
    if self.at(TRBrace) {
      break
    }
    // A `fn` in statement position is one of TWO things, and the token right
    // after `fn` is the whole discriminator:
    //
    //     fn name(t : T) { .. }   a NAMED function declared inside this block
    //     fn(t) { .. }            an ANONYMOUS function literal -- a LAMBDA,
    //                              which is an EXPRESSION, not a declaration
    //
    // Routing both to the declaration path is what made a lambda fail wherever
    // it sat in statement position. `parse_fn_signature` asks for a name, finds
    // `(`, and reports `expected function name` at a `fn` that is neither
    // unexpected nor unnamed -- so the complaint names the wrong thing, and
    // `parse_block` goes on from a cursor that never moved.
    //
    // It only showed up in a BRANCH, and that is not an accident of the corpus.
    // In expression position (`let f = fn(x) { .. }`) `parse_primary` has always
    // had a lambda branch, so those always worked. A block statement is the one
    // place the two forms share a token and a cursor, and moui's `modifier_env`
    // is written with a lambda as the tail of an `if` branch.
    if self.at_name("fn") && self.name_at(self.p + 1) != "" {
      // A named function INSIDE a block: `fn add(t : Ty) { ... }`. Ordinary
      // MoonBit — this analyzer's own types.mbt defines one — so it is parsed
      // as its own statement kind instead of being rejected. Rejection used
      // to cost the whole file: the error moved first_error, and everything
      // after the local function went unread.
      let fsp = self.span()
      let _ = self.bump()
      let (fname, fparams, fret) = self.parse_fn_signature()
      let (fbody, fendsp) = self.parse_block(true)
      body.push({
        span: fsp,
        kind: @ast.SLocalFunc(fname, fparams, fret, fbody, {
          start: fsp.start,
          end: fendsp.end,
        }),
      })
      self.skip_seps()
      continue
    }
    let st = self.parse_stmt()
    // The body's own trailing expression is its value. Tested BEFORE
    // `skip_seps`, because that is what consumes the newline or `;` in front of
    // `}` — after it, every final statement looks like the last one, including
    // one followed by several blank lines or a stray separator.
    if value_block && self.at(TRBrace) {
      match st.kind {
        SExpr(e) => {
          body.push({ span: st.span, kind: @ast.STail(e), })
          self.skip_seps()
          continue
        }
        _ => ()
      }
    }
    body.push(st)
    self.skip_seps()
  }
  let endsp = self.span()
  self.expect(TRBrace, "'}'")
  (body, endsp)
}

///|

///|
/// The declaration name for the top-level keyword at `kw_i`, tolerating a
/// type-parameter list BETWEEN the keyword and the name — `fn[Msg] name(...)`.
///
/// `fn` is the only declaration form that takes one, and it is 1563 occurrences
/// across 266 files in wzzc-dev/moui 0.1.12. This matters more than its share:
/// the harvest is what fills the SIBLING table, so before this a generic
/// function was invisible to every other file in its own package. Measured:
/// `views/feedback/feedback_panel.mbt` declares `fn[Msg] feedback_panel(`, and
/// all four of its call sites in `feedback_guidance.mbt` and
/// `feedback_transient.mbt` were reported "no visible binding", while
/// `runtime/view_tree.mbt:9` lost `modifier_view` the same way.
///
/// The `[` is only skipped when it sits IMMEDIATELY after the keyword. Every
/// other shape reaches `declared_name_at` at exactly the index it did before.

///| Declaration keywords whose braced body holds METHODS rather than

///| package-level bindings. `struct` and `enum` are not here: a struct field

///| already sits inside braces, and an enum's variants ARE package-level values

///|
/// harvested by their own path.
fn method_holder(kw : String) -> Bool {
  kw == "impl" || kw == "trait" || kw == "extend"
}

///|
fn declared_name_after_kw(toks : Array[@lexer.Tok], kw_i : Int32) -> String? {
  let mut i = kw_i + 1
  if i < toks.length() && toks[i] is TLBracket {
    let mut depth = 0
    while i < toks.length() {
      match toks[i] {
        TLBracket => depth += 1
        TRBracket => {
          depth -= 1
          if depth == 0 {
            i += 1
            break
          }
        }
        TEOF => break
        _ => ()
      }
      i += 1
    }
  }
  declared_name_at(toks, i)
}

///|
fn Parser::parse_stmt(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  // A `.` in STATEMENT position CONTINUES the previous line's expression:
  //
  //   button(
  //     label,
  //   )
  //   .semantics_role(@core.SemanticsRole::Group)
  //
  // It used to reach `parse_atom`'s catch-all and end the file. wzzc-dev/moui
  // 0.1.12 writes 1124 such lines across 131 files.
  //
  // The BASE is on the previous line and is already parsed, so this loop
  // starts from an opaque placeholder and lets the real postfix builder grow
  // the chain from there. That is what keeps the ARGUMENT reads: the segments
  // become `EMethodCall`s whose arguments are ordinary expressions, so a
  // parameter used only inside `.unwrap_or(self.style)` is still seen used.
  //
  // The base being a PLACEHOLDER rather than the previous expression is a
  // stated limit: the chain's receiver is not re-attached, so the value is
  // "some method result", not the true type. That costs precision and nothing
  // else — no lens can be handed a receiver it did not read.
  //
  // The newline case is the whole difficulty. A newline ends the chain unless
  // the NEXT line also opens with `.`, so the separators are consumed
  // speculatively and rewound when the continuation does not follow. Swallowing
  // them unconditionally would fuse the next real statement into this one.
  if self.at(TDot) {
    let sp0 = sp
    let mut e : @ast.Expr = { span: sp0, kind: @ast.EBigInt, }
    while self.at(TDot) {
      e = self.parse_postfix_from(e)
      if self.at(TNewline) {
        let save = self.p
        self.skip_seps()
        if !self.at(TDot) {
          self.p = save
          break
        }
      }
    }
    return { span: sp, kind: @ast.SExpr(e), }
  }
  if self.at_name("let") {
    let _ = self.bump()
    // `let mut x = ...` — the mutability marker is consumed and dropped. The
    // subset treats assignment as binding, so a mutable binding is the same
    // shape here as an ordinary one.
    if self.at_name("mut") {
      let _ = self.bump()
    }
    if self.at(TLParen) {
      // `let (a, b) = expr` — tuple destructuring. FLAT only: the names are
      // read, the init is parsed once, and each name binds the type of the
      // whole init — the subset has no tuple types to per-element it.
      let _ = self.bump()
      let names : Array[String] = []
      while !self.at(TRParen) && !self.at(TEOF) {
        let (n, _) = self.expect_name("destructured name")
        names.push(n)
        if self.at(TComma) {
          let _ = self.bump()
        } else {
          break
        }
      }
      self.expect(TRParen, "')'")
      self.expect(TAssign, "'='")
      let init = self.parse_expr()
      return { span: sp, kind: @ast.SLetDestruct(names, init), }
    }
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
  if self.at_name("raise") {
    return self.parse_raise_stmt()
  }
  if self.at_name("break") {
    let _ = self.bump()
    return { span: sp, kind: @ast.SBreak, }
  }
  if self.at_name("continue") {
    let _ = self.bump()
    return { span: sp, kind: @ast.SContinue, }
  }
  // `defer { ... }` and `defer <expr>` — a statement deferred to scope exit.
  //
  // BOTH bodies occur, and an arm that assumed only the block form was wrong on
  // the first try: it produced 8x `expected '{'` across proton 0.3.4. Counted
  // across the six corpora rather than sampled -- 1950 `defer` lines, of which
  // 1534 are a method call, 268 another expression, 130 a block, and 18 an
  // expression with a trailing `catch`:
  //
  //   command/command.mbt:145         defer {            (block)
  //   facade_logging_wbtest.mbt:169   defer ignore(...)  (expression)
  //   facade_bridge.mbt:584           defer (window.cancel_dialog(dialog) catch { _ => () })
  //
  // So the arm has to take an ordinary EXPRESSION, not a block, to get the
  // common case right. Settled with the toolchain: `_verify/grammar_probe.ps1`
  // cases `defer_block_stmt`, `defer_expr_stmt`, `defer_paren_expr_stmt`,
  // `defer_method_call_stmt` and `defer_expr_catch_stmt`, each 0 errors from
  // `moon check` in its own package beside a broken canary.
  //
  // The keyword plus a block is exactly what the bare-brace statement arm below
  // already turns into an `SBlock`, and `SBlock` was already modelled through
  // walk / types / infer / interp -- so nothing downstream needed teaching. The
  // expression form becomes a `STail`, which is how the same block's trailing
  // expression is represented.
  //
  // Without the arm the keyword was read as an ordinary identifier and reported
  // `undefined name 'defer'` — a false positive about the analyzer, on code
  // `moon check` accepts. Measured on moonbit-community/proton 0.3.4
  // `command/command.mbt:145`, newly visible only because the 0433 `match`
  // fix made that file readable.
  //
  // WHAT IS NOT MODELLED: the body is walked as an ordinary one, so a `return`
  // inside a `defer` reads as a return from the enclosing function where it
  // would run later at scope exit. That is the same flattening `if` bodies get,
  // and no lens has a use for the difference yet.
  // 0464 -- `errdefer <expr>` / `errdefer <block>`, the DEFERRED ERROR CLEANUP
  // statement. Same grammar as `defer` with an error handler, and it was reaching
  // the expression reader as a plain NAME.
  //
  // It became REACHABLE in this increment rather than being new: `src/socket/udp.mbt`
  // was blocked earlier at a `|>` on line 548, so its three `errdefer` lines had
  // never been read. Teaching the pipe unblocked the file and surfaced them as
  // `undefined name 'errdefer'` -- three confident false positives against code
  // `moon check` compiles, from a file the analyzer had never finished reading.
  //
  // => 判据: a false positive nobody can reach is not a false positive that does
  // not exist. It is a finding whose file has not been read yet, and the only way
  // to tell the two apart is to unblock the corpus and look. This is the 0459
  // story with a different ending: the reachability was legitimate, so the gap it
  // uncovered is fixed here rather than the reach being given back.
  //
  // Measured reach: 33 sites across 18 files of moonbitlang/async 0.22.4 and 2 in
  // proton 0.3.4. The argument is parsed, not skipped -- a `defer`/`errdefer` whose
  // action is never read would turn every variable it mentions into a false
  // `FUnusedBinding`.
  if self.at_name("errdefer") {
    let _ = self.bump()
    if self.at(TLBrace) {
      let (body, _) = self.parse_block(false)
      return { span: sp, kind: @ast.SBlock(body), }
    }
    return { span: sp, kind: @ast.STail(self.parse_expr()), }
  }
  if self.at_name("defer") {
    let _ = self.bump()
    if self.at(TLBrace) {
      let (body, _) = self.parse_block(false)
      return { span: sp, kind: @ast.SBlock(body), }
    }
    return { span: sp, kind: @ast.STail(self.parse_expr()), }
  }
  if self.at_name("if") {
    return self.parse_if()
  }
  if self.at_name("guard") {
    return self.parse_guard()
  }
  if self.at_name("while") {
    return self.parse_while_stmt(sp)
  }
  if self.at_name("for") {
    return self.parse_for_stmt(sp)
  }
  if self.at(TLBrace) && !self.at_struct_literal() {
    // A bare `{ ... }` block in statement position — `fn main`'s inner
    // block, a test block. It is a plain statement list: parse_block reads
    // it whole and the lenses treat SBlock exactly like an `if` body (no
    // new scope). Without this arm the brace reached parse_atom's struct
    // literal arm, whose field grammar rejects statements and cascaded —
    // cli/main.mbt:28 was blocked on exactly that.
    //
    // The lookahead guard is the other half: `{ line, col, }` in statement
    // or tail position is a STRUCT LITERAL, not a block — MoonBit's own
    // tail-value style. Sending it to parse_block made the field `name:`
    // read as `expr : type` and the shorthand `line,` as a tuple, and the
    // block grammar died at the first colon. When at_struct_literal says
    // literal, fall through to the expression path below: parse_atom's
    // TLBrace arm produces EStruct there. Measured deaths: core/walk/
    // parser/jsoncli/mermaid_test all blocked on exactly this brace.
    let (body, _) = self.parse_block(false)
    return { span: sp, kind: @ast.SBlock(body), }
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
  // Compound assignment `lhs op= rhs`, desugared to `lhs op rhs` on the
  // right-hand side: the lenses only know SAssign + EBin, so the sugar is
  // expanded here rather than taught to every lens. `i += 1` becomes
  // SAssign(i, EBin(OpAdd, i, 1)) — the walk counts the read of `i` through
  // EBin's left operand, and the type lens checks the same operator it
  // would check for `i = i + 1`. The target expression is aliased into both
  // positions on purpose: it is an immutable struct.
  if self.at(TPlusEq) ||
    self.at(TMinusEq) ||
    self.at(TStarEq) ||
    self.at(TSlashEq) ||
    self.at(TPercentEq) {
    let op = match self.peek() {
      TPlusEq => @ast.OpAdd
      TMinusEq => @ast.OpSub
      TStarEq => @ast.OpMul
      TSlashEq => @ast.OpDiv
      _ => @ast.OpMod
    }
    let asp = self.span()
    let _ = self.bump()
    if !e.is_valid_target() {
      self.err("invalid assignment target", asp)
    }
    let rhs = self.parse_expr()
    return {
      span: sp,
      kind: @ast.SAssign(e, { span: e.span, kind: @ast.EBin(op, e, rhs), }),
    }
  }
  { span: sp, kind: @ast.SExpr(e), }
}

///|
/// Is the `for` at the current position the C-style three-clause form?
///
/// Decided by scanning tokens, NOT by parsing: the two forms differ in what
/// follows `for`, and the binder path is the one with a decade of tests behind
/// it, so it must not be disturbed by a lookahead that guesses.
///
/// Whichever of `;` and `{` arrives FIRST at depth 0 decides the form, and the
/// scan STOPS there. That stop is the whole test: an earlier version kept
/// scanning past the body's closing brace, so a plain `for entry in xs { ... }`
/// followed anywhere later in the file by a `;` was misread as C-style and died
/// on `expected ';'` further down. Measured on riantr/pyroduct 0.1.29, that
/// turned a clean recovery into 4 files instead of 15 and moved the error rather
/// than removing it.
///
/// Called with `self.p` ON `for`.
fn Parser::is_c_style_for(self : Parser) -> Bool {
  let mut i = self.p + 1
  let mut depth = 0
  while i < self.toks.length() {
    match self.toks[i] {
      TSemi => if depth == 0 { return true } else { i += 1 }
      TLParen | TLBracket => {
        depth += 1
        i += 1
      }
      TRParen | TRBracket => {
        depth -= 1
        i += 1
      }
      // The body's opening brace, still at depth 0: the head had no `;`, so
      // this is the binder form. Do not look past it.
      TLBrace =>
        if depth == 0 {
          return false
        } else {
          depth += 1
          i += 1
        }
      TRBrace => {
        depth -= 1
        i += 1
      }
      TEOF => return false
      _ => i += 1
    }
  }
  false
}

///|
/// The C-style three-clause loop: `for i = 0; i < n; i = i + 1 { ... }`.
///
/// Desugared to `[init, while (cond) { body; update }]` — an `SBlock` around an
/// `SWhile`, both of which already exist and are already walked. A dedicated
/// node would be more honest about the shape, but every lens matches `SKind`
/// exhaustively, so adding one is a change in four packages to buy a
/// distinction no lens currently draws.
///
/// One deliberate inexactness: the update runs ONCE after the loop rather than
/// once per iteration, because this is a static read analysis and the loop is
/// walked once anyway. It is kept rather than dropped on purpose — `i = i + 1`
/// is where `i` is READ, and a dropped update clause makes every loop counter
/// look like an unused local. Wrong in the loud direction is not an option
/// here; this is wrong in the quiet one, and only for a loop's exit value.

///|
/// `loop nobreak { .. }` -- wrap a loop statement when a `nobreak` block follows.
///
/// The grammar is SETTLED by the compiler, `_verify/settle_0443_nobreak.ps1`, 10/10
/// with the positive control green:
///
///   - `nobreak` is a postfix ON A LOOP. The compiler REJECTS `expr nobreak {..}`
///     with no loop, and rejects it on a `let`. Matching it as a bare keyword
///     anywhere would therefore accept programs the compiler refuses and would
///     swallow a user's own function named `nobreak`.
///   - it is accepted on `while` AND `for`, so this is called from all three loop
///     forms -- the binder `for`, the C-style `for`, and `while`. Writing it for
///     `while` alone would have been a silent gap the settle would not have
///     caught, because the corpus site is a `while`.
///   - the body is a STATEMENT LIST: `nobreak { 1 }` is rejected with 4139, a
///     value in statement position cannot be dropped.
///   - an EMPTY `nobreak { }` is ACCEPTED, unlike `noraise { }` which is rejected.
///     The two constructs are easy to assume identical and are not.
///
/// The empty-block case is why this uses `parse_block` and not a loop that
/// requires at least one statement: rejecting `nobreak { }` would reject valid
/// MoonBit, and the probe that says so is above.

///|
/// `while cond { body }`, as a STATEMENT. Extracted from `parse_stmt` in 0465b so
/// that expression position can consume the identical construct -- see
/// `parse_loop_as_expr`, which is the whole reason this exists.
fn Parser::parse_while_stmt(self : Parser, sp : @core.Span) -> @ast.Stmt {
  let _ = self.bump()
  let cond = self.parse_expr()
  let (body, _) = self.parse_block(false)
  self.maybe_nobreak({ span: sp, kind: @ast.SWhile(cond, body), })
}

///|
/// `for` as a STATEMENT, in all three of its forms. Extracted from `parse_stmt` in
/// 0465b for the reason `parse_while_stmt` was.
fn Parser::parse_for_stmt(self : Parser, sp : @core.Span) -> @ast.Stmt {
  // MoonBit has TWO for forms. `for x in xs` reads a binder; the C-style
  // three-clause form does not, and reading its head as a binder made the
  // parser demand `in` right after it — `expected 'in'`, the error that
  // stopped 15 of riantr/pyroduct's 32 unreadable files (600+ occurrences of
  // `for i = 0; i < n; i = i + 1` in that one corpus).
  //
  // Which form it is is decided by LOOKING, not by parsing, so the binder
  // path below keeps every test it has.
  if self.is_c_style_for() {
    return self.parse_c_for()
  }
  let _ = self.bump()
  // One binder, or a comma-separated list of them: `for x in xs` is the
  // common form, `for k, v in entries { ... }` is pair destructuring
  // (measured blockers: `for k, _ in other.types {`, `for i, _ in
  // verdicts {`). A tuple-paren pattern `for (a, b) in ...` is not
  // modelled and still reports. The comma is only another binder when a
  // pattern name follows it — `peek2_is_pattern_name` also refuses `in`,
  // so a malformed `for k, in` cannot eat the keyword.
  let (first, vsp) = self.expect_name("loop variable")
  let names : Array[String] = [first]
  while self.at(TComma) && self.peek2_is_pattern_name() {
    let _ = self.bump()
    let (n, _) = self.expect_name("loop variable")
    names.push(n)
  }
  if !self.at_name("in") {
    self.err("expected 'in'", self.span())
  } else {
    let _ = self.bump()
  }
  let seq = self.parse_expr()
  let (body, _) = self.parse_block(false)
  if names.length() == 1 {
    return self.maybe_nobreak({
      span: sp,
      kind: @ast.SFor(names[0], vsp, seq, body),
    })
  }
  // Multi-binder desugar. The lenses only know single-binder SFor, so
  // the sugar is expanded here rather than taught to every lens:
  //   for k, v in entries { body }
  // becomes
  //   for $pair in entries { let (k, v) = $pair; body }
  // `$` never lexes into a name, so the head binder cannot collide with
  // user code; a `_` binder is covered by the audit's discard exemption.
  let body2 : Array[@ast.Stmt] = []
  body2.push({
    span: sp,
    kind: @ast.SLetDestruct(names, { span: sp, kind: @ast.EName("$pair"), }),
  })
  for st in body {
    body2.push(st)
  }
  { span: sp, kind: @ast.SFor("$pair", vsp, seq, body2), }
}

///|
/// A LOOP IN EXPRESSION POSITION -- `let kind : MessageKind = for frame = .. { .. }`
/// at `moonbitlang/async 0.22.4 src/websocket/conn.mbt:486`.
///
/// THE LOOP IS CONSUMED AND REPORTED HONESTLY, AND NEVER TURNED INTO A NAME. That
/// last part is the fix. `parse_atom` had arms for `if`, `match`, `try`, `async`,
/// `fn`, `true` and `false` and none for a loop keyword, so `for` fell through to
/// the generic `TName` arm, became `EName("for")`, and the structural walk resolved
/// it as a binding: `undefined name 'for'`, ACTIONABLE, on code `moon check`
/// compiles. `while` did the same. `match` and `if` in the very same position
/// already reported "X expression is outside the analyzed subset", which is what
/// makes this a gap in two keywords rather than a general one.
///
/// REACHABLE ONLY AFTER 0465. The `..` chain in `conn.mbt` used to stop the parse
/// 80 lines above line 486, so the finding had no path to be observed. Teaching the
/// chain unblocked the file and revealed it, which is the 0464b `errdefer` case
/// again: unblocking a file does not create findings, it reveals ones whose reach
/// was previously blocked, and the honest response is to fix the gap rather than
/// give the reach back.
///
/// The loop body is SKIPPED WHOLE and the value is `EBigInt` -- the same treatment
/// `if` and `match` get, because the subset has no loop-valued expression and no
/// node to put one in. The STATEMENT is parsed by the same routines statement
/// position uses, so the token consumption is identical and cannot drift; only the
/// result is discarded. `EBigInt` rather than a guessed value is the existing
/// rule: const_eval must not fold a bound it never read.
fn Parser::parse_loop_as_expr(self : Parser, sp : @core.Span) -> @ast.Expr {
  if self.at_name("while") {
    let _ = self.parse_while_stmt(sp)
  } else {
    let _ = self.parse_for_stmt(sp)
  }
  self.note_skip(
    "loop expression is outside the analyzed subset; it was read but not analysed",
    sp,
  )
  { span: sp, kind: @ast.EBigInt, }
}

///|
fn Parser::maybe_nobreak(self : Parser, loop_stmt : @ast.Stmt) -> @ast.Stmt {
  if !self.at_name("nobreak") {
    return loop_stmt
  }
  let nsp = self.span()
  let _ = self.bump()
  let (block, _) = self.parse_block(false)
  { span: nsp, kind: @ast.SNoBreak(loop_stmt, block), }
}

///|
/// The C-style `for` init clause is a DECLARATION, and `parse_stmt` cannot see that.
///
/// Settled against the toolchain (`_verify/settle_0470_c_for_init.ps1`), three rows:
///
///   for i = 0; i < n; i = i + 1 { .. }      ACCEPT   -- so `i = 0` DECLARES `i`
///   for let i = 0; i < n; i = i + 1 { .. }  REJECT    -- `let` is FORBIDDEN here
///   for j = n; j < 1; j = j - 1 { .. } ignore(j)   REJECT -- `j` does not outlive it
///
/// The sharpest row is RECORDed rather than predicted, because predicting it would only
/// encode a guess. An enclosing `let x : Int = 99`, then `for x = 0; ..`, then `ignore(x)`
/// AFTER the loop, ACCEPTs: the init clause SHADOWS the enclosing binding for the loop and
/// the enclosing one is still visible afterwards. An assignment would have collided or
/// overwritten; only a declaration both shadows and ends. That is the behaviour `SLet`
/// models, and it is why the node below is a declaration and not a rebinding.
///
/// The clause has no `let` keyword, so `parse_stmt` read `x = xs` as an ASSIGNMENT and
/// built an `SAssign`. That is the wrong node twice over: it is a declaration, and it is
/// scoped to the loop rather than assigned onto the enclosing frame.
///
/// The observable cost was moonbit_labeler 0.2.13 app_moui/rasterizer.mbt:1218, the last
/// `actionable` on any corpus:
///
///     argument 2 to 'blend_pixel' has incompatible type 'float'; expected 'int'
///
/// `Infer::assign_check` REPORTS a mismatch but does not rebind, so the `x : Double`
/// leaked from an enclosing body survived and the loop's own `x` never replaced it. The
/// three-way bisect is what located this: the same file with a plain `let x : Int = xs`
/// in place of the `for` header is CLEAN, and with no inner `x` at all it is CLEAN.
fn Parser::parse_c_for(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  let _ = self.bump() // for
  let stmts : Array[@ast.Stmt] = []
  // init may be empty: `for ; i < n; i = i + 1`
  if !self.at(TSemi) {
    stmts.push(self.c_for_init(sp))
  }
  self.expect(TSemi, "';'")
  // An absent condition is a constant-true loop, not a missing one.
  let mut cond : @ast.Expr = { span: sp, kind: @ast.EBool(true), }
  if !self.at(TSemi) {
    cond = self.parse_expr()
  }
  self.expect(TSemi, "';'")
  let update = if self.at(TLBrace) { None } else { Some(self.parse_stmt()) }
  let (body, _) = self.parse_block(false)
  let loop_body : Array[@ast.Stmt] = []
  for st in body {
    loop_body.push(st)
  }
  match update {
    Some(u) => loop_body.push(u)
    None => ()
  }
  stmts.push({ span: sp, kind: @ast.SWhile(cond, loop_body), })
  self.maybe_nobreak({ span: sp, kind: @ast.SBlock(stmts), })
}

///|
/// Read the C-style `for` init clause as the DECLARATION it is. See `parse_c_for` for the
/// settle that establishes this.
///
/// The clause is `name = value` with no `let`, so the ordinary statement reader returns an
/// `SAssign`. That is the wrong node here for two independently measured reasons: the
/// clause DECLARES rather than assigns, and the name does not outlive the loop.
///
/// The test is made on the TOKEN, before the clause is parsed, and never on the shape of the
/// node that comes back. An earlier version unwrapped an `EBin` out of the right-hand side
/// and matched nothing at all -- silently, because `EBin` is what the COMPOUND branch
/// produces, while the plain `=` branch stores the value DIRECTLY. `moon check --deny-warn`
/// was 0 and all 857 tests stayed green while this function returned every statement
/// unchanged and the corpus finding it was written to clear stayed.
///
/// The node shape cannot discriminate either, which is why it was the wrong test: in
/// `for i = j + 1; ..` a plain `=` legitimately carries an `EBin` value, and `x += 1` wraps
/// its value in one. `TName(_)` followed by `TAssign` is the only reading that separates the
/// two, and it excludes `TPlusEq` and its siblings for free rather than by exclusion.
///
/// Anything that is not exactly that shape is handed back untouched, so a form this does not
/// model is READ exactly as before rather than silently rewritten into something it is not --
/// the rule every other arm in this file follows.
fn Parser::c_for_init(self : Parser, _sp : @core.Span) -> @ast.Stmt {
  // Separators first: in `for\n  i = 0; ..` the clause's first real token is not at `self.p`.
  let mut i = self.p
  while i < self.toks.length() {
    match self.toks[i] {
      TNewline | TSemi => i += 1
      _ => break
    }
  }
  let mut plain_decl = false
  if i + 1 < self.toks.length() {
    match self.toks[i] {
      TName(_) =>
        match self.toks[i + 1] {
          TAssign => plain_decl = true
          _ => ()
        }
      _ => ()
    }
  }
  let st = self.parse_stmt()
  if !plain_decl {
    return st
  }
  // The token test has already established the plain `=` branch, so the right-hand side IS
  // the value and there is nothing to unwrap.
  match st.kind {
    SAssign(target, value) =>
      match target.kind {
        @ast.EName(n) => { span: st.span, kind: @ast.SLet(n, "", value), }
        _ => st
      }
    _ => st
  }
}

///|
fn Parser::parse_if(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  let _ = self.bump() // if
  let cond = self.parse_expr()
  let (then, _) = self.parse_block(false)
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
        let (b2, _) = self.parse_block(false)
        elseifs.push({ cond: c2, body: b2, })
        going = true
      } else {
        let (eb, _) = self.parse_block(false)
        els = Some(eb)
      }
    }
  }
  { span: sp, kind: @ast.SIf(cond, then, elseifs, els), }
}

///|
/// `raise E` / `raise E(payload)` / a bare `raise` — a STATEMENT, and the third
/// position the `raise` clause appears in after the signature annotation
/// (0.4.23) and a function type's return annotation (also 0.4.23).
///
/// Measured cost of not having it: `raise` was read as an ordinary identifier,
/// so every one of these reported `undefined name 'raise'` — a confidently false
/// finding about code that compiles. The scan classified every `UndefinedName`
/// in the six corpora and 65 of them were the literal name `raise` (56 in
/// `moonbit-community/proton` alone). The construct itself: 585 sites across 54
/// files of proton, 427 / 90 of async, 180 / 16 of moonbit_image.
///
/// The payload is read as a full expression and kept, so a real defect INSIDE a
/// raise still reports (`raise E(undeclared_fn)` must not go quiet). Settled
/// against `moon check` on 0.1.20261012, all zero errors: the bare form, the
/// payload form, the form inside a `guard ... else` block, the form as a tail
/// expression, and the form under a `-> T!` signature.
///
/// `SRaise` rather than `SReturn`: see the node's own doc comment for the three
/// lenses that would misread it as a return of the error value.
fn Parser::parse_raise_stmt(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  let _ = self.bump() // raise
  // Same termination set as `return`: a raise with nothing after it is
  // `raise` on its own line, or `raise` closing a block with no semicolon.
  if self.at(TNewline) || self.at(TSemi) || self.at(TRBrace) || self.at(TEOF) {
    return { span: sp, kind: @ast.SRaise(None), }
  }
  { span: sp, kind: @ast.SRaise(Some(self.parse_expr())), }
}

///|
/// `guard COND else { ... }` — MoonBit's early-exit form, and the handler of
/// 550 statements across 126 files of wzzc-dev/moui 0.1.12, the largest
/// remaining unimplemented statement shape.
///
/// It was not merely unimplemented: `guard` is not in the lexer's keyword list,
/// so it was read as an ordinary IDENTIFIER and reported as an undefined name —
/// measured on `runtime/devtools_runtime.mbt:372`
/// (`guard nodes.get(id) is Some(node) else { return [] }`).
///
/// It is represented as an `SIf` with an empty `then`, which is the honest
/// mapping for a frame model that is not flow-scoped: the condition is walked
/// first, so an `is` pattern in it binds in the CURRENT frame exactly where the
/// rest of the block will look for it — which is what a guard binding does. The
/// `else` block is analyzed like any other.
///
/// The one thing this deliberately does NOT model: in MoonBit the else block
/// runs only when the guard FAILS, and the pattern name is not in scope there.
/// This frontend's frame is flat (the same limitation `EIs` documents), so the
/// name resolves in the else block too. That can only ever make an analysis
/// quieter about a name that really is bound later, never invent a finding.
fn Parser::parse_guard(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  let _ = self.bump() // guard
  // `guard!` is the raising sibling of `guard`: same condition, same `else`,
  // but it propagates an error instead of returning. Both arrive as the name
  // `guard` followed by a separate `!` token, because `!` is not part of a
  // name in the lexer.
  //
  // Without this the `!` was parsed as the boolean NOT operator applied to the
  // CONDITION, which is a false positive with a confident message:
  // `moonbitlang/async` 0.22.4 `src/internal/fd_util/pipe.mbt:31` reads
  // `guard! fds is [r, w]` and was reported as
  // "operand of '!' must be bool, got '[int]'".
  //
  // The two forms are still modelled identically below, which is the same
  // deliberate flattening the guard already documents: neither raises nor
  // returns in this frame model.
  if self.at(TBang) {
    let _ = self.bump()
  }
  let cond = self.parse_expr()
  let mut els : Array[@ast.Stmt]? = None
  if self.at_name("else") {
    let _ = self.bump()
    let (eb, _) = self.parse_block(false)
    els = Some(eb)
  }
  { span: sp, kind: @ast.SIf(cond, [], [], els), }
}

///|

///|
/// Whether the token at the cursor is a LITERAL, in the sense that it can be the
/// whole of a pattern: `is b'\x08'`, `is 0`, `is 1.5`. `at` takes a bare token and
/// cannot compare the payload-carrying kinds, so the payload-bearing literals need
/// this form -- the same reason `at_str` and `at_name` exist.
fn Parser::at_pattern_literal(self : Parser) -> Bool {
  match self.peek() {
    TInt(_) => true
    TBigInt => true
    TFloat(_) => true
    TStr(_, _) => true
    _ => false
  }
}

///|
/// An expression. The entry for every position an expression can appear, and
/// therefore the place a lambda has to be recognised: the three sites that
/// already knew about lambdas were `parse_call_args`' POSITIONAL branch (bare
/// `x => body` only), `parse_call_args`' NAMED branch, and a parameter's
/// default. Everything else fell through to `parse_or`, which read the
/// parameter list as an expression and then stopped dead on `=>`.
///
/// The parenthesised and typed spellings were the expensive part, and the
/// parser's own comment recorded the cause without noticing it was a gap: "The
/// arrow check below only runs on the positional path". `at_arrow_lambda`
/// matches `name =>`; `at_lambda_head` matches `(a, b) =>`, `(_n : T) =>` and
/// the bare spelling, and was reachable only AFTER a `name =`. So
///
///   g((a, b) => a + b)          -- positional, parenthesised -> dead on `)`
///   let h = (a, b) => a + b     -- `let` right-hand side   -> dead on `=`
///
/// both failed, while `g(a => a)` and `children=_node => [child]` worked. All
/// four spellings are legal MoonBit (`moon check` 0 errors, with a broken canary
/// beside them, in `_verify/probe_sweep_0434.ps1`).
///
/// The body is SKIPPED, never parsed, for the reason every other lambda site
/// gives: the parameters are not bound, so parsing the body would resolve names
/// that only the lambda's own parameters can bind, and report each as undefined
/// -- trading one blocker for a stream of false positives. The lambda yields an
/// opaque `EBigInt` plus a notice, and the parse stays in step so everything
/// after it is analysed.
fn Parser::parse_expr(self : Parser) -> @ast.Expr {
  if self.at_lambda_head() {
    let lsp = self.span()
    self.skip_lambda_head()
    if self.at(TLBrace) {
      self.skip_braces()
    } else {
      self.skip_lambda_body()
    }
    self.note_skip(
      "short lambda is outside the analyzed subset; it was read but not analysed",
      lsp,
    )
    return { span: lsp, kind: @ast.EBigInt, }
  }
  self.parse_pipe()
}

///|
/// THE PIPE TIER -- the LOOSEST binary level, above `parse_or`, and
/// left-associative.
///
/// BOTH PROPERTIES ARE SETTLED, not read off the symbol
/// (`_verify/settle_0464_pipe_operators.ps1`, 14/14):
///
///     `2 * 3 |> inc`    ACCEPT  ->  the LEFT operand is `(2 * 3)`
///     `2 |> inc * 3`    REJECT  ->  the RIGHT operand is `inc * 3`, a type error
///                                rather than `(2 |> inc) * 3`
///     `1 |> inc |> inc` ACCEPT  ->  left-associative
///
/// The middle row is the one that pins it. Read as `(2 |> inc) * 3` it would be 9
/// and would accept; the toolchain rejects it, so the pipe's right operand is the
/// whole of `inc * 3`. An implementation that grabbed only the following ATOM
/// would pass both direction rows above and fail both of these, binding corpus
/// code into a different tree while reporting nothing wrong anywhere.
///
/// `f <| x` and `x |> f` are the SAME operator to this analyzer and produce the
/// same node. The two are separate TOKENS because the toolchain refuses the
/// reversed reading of each (`x <| f` and `f |> x` are both REJECT(4101)), and a
/// token that accepted both would accept code the compiler rejects.
///
/// `<+` PRODUCES THE SAME NODE, and that is a recorded limitation rather than a
/// claim of equivalence. `sb <+ "b"` is a StringBuilder append and `f <| x` is
/// application; this analyzer models neither a builder nor a call result, so both
/// are "read both operands, result unknown". The settle is what says `<+` is NOT
/// a pipe -- `inc <+ 1` is refused with "you may expect template string" -- so
/// nothing here claims the two behave alike, only that this reader cannot tell
/// them apart and does not pretend to.
fn Parser::parse_pipe(self : Parser) -> @ast.Expr {
  let mut l = self.parse_or()
  while self.at(TPipeLt) || self.at(TPipeGt) || self.at(TAppendPlus) {
    let sp = self.span()
    let _ = self.bump()
    // The RIGHT OPERAND MAY BE A LAMBDA, and that is not a rare spelling: it is
    // the corpus shape in all 13 of the files this unblocks --
    // `Promise::from_async(abort_signal~) <| () => { .. }`,
    // `@async.with_task_group() <| group => { .. }`, `Lazy() <| () => { .. }`.
    //
    // `parse_expr` recognises a lambda head only at ITS OWN cursor, and a pipe's
    // right operand never passes through `parse_expr` -- it goes straight to
    // `parse_or`. So `parse_atom` stopped at the `(` of `()`, the `=>` was left in
    // the stream, and the STATEMENT parser then read that `=` as an assignment to
    // `EBin(OpPipe, ..)`: "invalid assignment target", which is a message about a
    // pipe and blames neither of the things that are actually in the source.
    //
    // Skipped, not parsed, for the reason every other lambda site gives: the
    // parameters are not bound, so parsing the body would report each of them as
    // undefined.
    let r : @ast.Expr = if self.at_lambda_head() {
      self.skip_lambda_head()
      if self.at(TLBrace) {
        self.skip_braces()
      } else {
        self.skip_lambda_body()
      }
      self.note_skip(
        "short lambda is outside the analyzed subset; it was read but not analysed",
        sp,
      )
      { span: sp, kind: @ast.EBigInt, }
    } else {
      self.parse_or()
    }
    l = { span: l.span, kind: @ast.EBin(@ast.OpPipe, l, r), }
  }
  l
}

///|
/// Skip a short lambda's NON-BRACE body up to, but not consuming, whatever ends
/// it in the position the lambda was found.
///
/// `skip_to_arg_boundary` cannot be reused here: it stops only at a depth-0 `,`
/// or `)`, so in a `let` right-hand side it would run on to the next unmatched
/// `)` anywhere in the file and swallow the rest of the function. This stops
/// also at a newline, the enclosing `}`, and `;` -- the other three ways an
/// expression ends in this grammar.
///
/// NO TRUNCATION FOUND, and that is a measurement rather than an assumption.
/// A depth-0 newline looks like the obvious hole -- it stops a body that
/// continues onto the next line -- and three drafts of a KNOWN LIMIT test were
/// written and deleted for it before the shapes were actually run. All of them
/// measure `PARSED 1/1`: the lexer already suppresses a newline that follows an
/// infix operator (`=> a +\n  b`), bracket depth covers a call or chain that
/// opens on one line and closes on the next, and a body that starts on the line
/// after the arrow has no newline between the arrow and the body to stop at.
/// If a shape ever does truncate, it belongs here as a test rather than as a
/// comment.
fn Parser::skip_lambda_body(self : Parser) -> Unit {
  let mut depth = 0
  while !self.at(TEOF) {
    if depth == 0 &&
      (
        self.at(TComma) ||
        self.at(TRParen) ||
        self.at(TNewline) ||
        self.at(TRBrace) ||
        self.at(TSemi)
      ) {
      return
    }
    if self.at(TLParen) || self.at(TLBrace) || self.at(TLBracket) {
      depth += 1
    } else if self.at(TRParen) || self.at(TRBrace) || self.at(TRBracket) {
      depth -= 1
    }
    let _ = self.bump()
  }
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
/// The `is` test tier: `e is Pattern`. It sits between comparison and the
/// bitwise tiers — tighter than `<`, looser than `| ^ & << >>`, which sit
/// just above `+` — because
/// every measured use feeds a boolean operator or a negation
/// (`p.peek() is TName(tag) && tag.has_prefix("@")`, `!(m is TInt)`), and
/// no corpus line puts a comparison on an `is` result. The pattern is
/// reduced to the BINDINGS it introduces (none when it has none); the
/// TEXT is consumed and discarded, so no lens ever parses strings (MoonBit
/// string indexing is by byte, and pattern text would have to be re-lexed
/// to be sliced safely).
fn Parser::parse_is(self : Parser) -> @ast.Expr {
  let mut l = self.parse_bitor()
  // `is` CONTINUES an expression across a newline. A guard writes its whole
  // condition over several lines:
  //
  //   guard (self.frame, self.image, self.host_bridge)
  //     is (Some(frame_state), Some(image_state), Some(host_bridge)) &&
  //     !self.disposed else { ... }
  //
  // and without this the line break ended the expression, `is` was read as an
  // ordinary identifier, and the file parsed WITHOUT an error into a tree where
  // every name after that point was wrong — 15 findings on
  // `backend/common/embedded/embedded_runtime_backend.mbt`, none of them
  // reported as unreliable because nothing failed.
  //
  // Same rule the lexer already applies for a newline before a closing bracket.
  //
  // Only TNewline is skipped, NOT `skip_seps` — that also eats `;`, and a
  // semicolon is STRUCTURAL in a C-style `for` (`for i = 0; i < n; i = i + 1`).
  // Using `skip_seps` here broke "a C-style three-clause for loop parses".
  while self.at(TNewline) {
    let _ = self.bump()
  }
  while self.at_name("is") {
    let _ = self.bump()
    let binding = self.parse_is_pattern()
    l = { span: l.span, kind: @ast.EIs(l, binding), }
    while self.at(TNewline) {
      let _ = self.bump()
    }
  }
  l
}

///|
/// The pattern of an `is` test, reduced to the BINDINGS it introduces: the
/// head is one constructor name (`TName`, `Some`, `ABool`), an optional
/// payload follows in one paren group, and every non-`_` name in that group
/// is a binding — `TName(tag)` -> ["tag"], `TEOF` -> [], `Some(_)` -> []. A
/// name immediately followed by `(` inside the payload is a nested
/// constructor, not a binding (`Some(Some(x))` binds nothing here and
/// reports honestly at the `x` use). Unmodelled shapes stay in step as far
/// as the balanced paren and report at the first token they cannot place.
///
/// A binding must also be a NAME THAT INTRODUCES A VARIABLE, and a keyword is
/// not one: `if info.required is Some(true)` bound the literal `true` and
/// reported `local variable 'true' assigned but may not be used` — twice, on
/// `wzzc-dev/moui 0.1.12` `views/form/form_field_semantics_test.mbt:42` and
/// `:58`, lines `moon check` accepts. The test is `@lexer.is_moonbit_keyword`,
/// not a second list here: that list already carries `true` and `false`, it
/// already documents why `self` is deliberately NOT in it, and a private copy
/// in this file is exactly how the two would drift apart. `self` therefore
/// still binds, which is what `if x is Some(self)` means.
///
/// A pattern can introduce SEVERAL bindings at once (`is (Some(a), Some(b))`),
/// so this returns all of them and `EIs` carries a list. It returned one name
/// until 0.4.21; the tuple branch below already consumed the whole group then,
/// so the other names were silently dropped and each reported as an undefined
/// name — 7 findings on
/// `backend/common/embedded/embedded_runtime_backend.mbt`.

///|
/// Is the pattern token at index `j` a NAME THAT INTRODUCES A VARIABLE?
///
/// ONE reader, called from BOTH branches of `parse_is_pattern`, written
/// index-based so each branch can scan at its own pace. 0.4.18 and 0.4.20 each
/// shipped a SECOND name reader that drifted from the first; a predicate with a
/// single index parameter cannot drift that way.
///
///   - not `_`, and not a keyword (`is_moonbit_keyword`, not a second list)
///   - the token after it is not `(` — a nested CONSTRUCTOR, not a binding
///   - neither neighbour is `.` — `@core.Role::Checkbox` is a qualified PATH,
///     and `is Some(@core.Role::Checkbox)` binds `@core` as a local today
///
/// The callers additionally stop at the first `:`, because the rest of the
/// payload is then a TYPE ANNOTATION and `Int` is not a binding. A qualified
/// path's `::` reaches that same rule, which is why every segment of
/// `@core.Role::Checkbox` stops being collected. The TUPLE branch also requires
/// `depth >= 2`, because its outer `(` is a grouping paren rather than a
/// constructor payload — see the note there.
///
/// Dropping the old `depth == 1` restriction is what unlocks the nested shapes,
/// and both are settled against `moon check`: `guard ... is Some(Os(error))`
/// then `error + 1` at `moui .../macos/event_loop_wbtest.mbt:6`, and
/// `is Some(DragLeft(Some(event_position)))` then `event_position + 1` at
/// `.../event_wbtest.mbt:25`. Both bind their inner name; both reported
/// `undefined variable` while only depth 1 was read.
fn Parser::pattern_binding_at(self : Parser, j : Int32) -> Bool {
  if j >= self.toks.length() {
    return false
  }
  let n = match self.toks[j] {
    TName(s) => s
    _ => return false
  }
  if n == "_" || @lexer.is_moonbit_keyword(n) {
    return false
  }
  let after = j + 1
  if after < self.toks.length() &&
    (self.toks[after] == TLParen || self.toks[after] == TDot) {
    return false
  }
  if j > 0 && self.toks[j - 1] == TDot {
    return false
  }
  true
}

///|
/// 0466b -- a `.. rest` in an ARRAY pattern BINDS, and it is not a field path.
///
/// `pattern_binding_at` refuses any name whose previous token is a `TDot`. That rule
/// is right and gives the wrong answer here: `Foo.bar` is a path, but `.. rest` is
/// TWO dots and the name after them is exactly what the pattern binds.
///
///     guard! buf is [u32le(_), u32le(mask), .. payload]
///     payload
///
/// at `moonbitlang/async 0.22.4 src/internal/event_loop/fs.mbt:105` and `:152`, both
/// reported `undefined name 'payload'` -- a name the pattern itself introduced, on
/// code `moon check` compiles.
///
/// THE PREDICATE CHECKS TWO DOTS, NOT ONE. Widening `pattern_binding_at` to accept a
/// single preceding `TDot` would bind every segment of every `Foo.bar` in every
/// pattern, which is the rule's whole purpose. `.. rest` and `.field` are
/// distinguishable here and only here.
///
/// Settled, `_verify/settle_0466b_rest_binding.ps1`: `rest_binds` ACCEPT with
/// `rest` USED, a canary beside it REJECTing a name the pattern never mentions, and
/// `rest_bare` ACCEPT -- a bare `..` with no name after it is legal too.
///
/// NOT DONE, AND MEASURED BEFORE IT COULD BE: the TUPLE branch above. No pinned
/// corpus writes `is (a, .. rest)`, and adding a shape with no evidence of it being
/// written is the habit this increment exists to avoid.
fn Parser::rest_binding_at(self : Parser, j : Int32) -> Bool {
  if j < 2 || j >= self.toks.length() {
    return false
  }
  if self.toks[j - 1] != TDot || self.toks[j - 2] != TDot {
    return false
  }
  let n = match self.toks[j] {
    TName(s) => s
    _ => return false
  }
  n != "_" && !@lexer.is_moonbit_keyword(n)
}

///|
/// The same predicate at the CURSOR, for the branch that parses rather than
/// scans.
fn Parser::at_pattern_binding(self : Parser) -> Bool {
  self.pattern_binding_at(self.p)
}

///|

///|
/// Is this pattern HEAD a VARIABLE BINDING rather than a constructor?
///
/// MoonBit constructors are Capitalised and variables are not, and that is the
/// whole rule. It is SETTLED rather than assumed -- `_verify/settle_0444_is_head.ps1`
/// measures both halves with the same instrument:
///
///   - `if probe() is err && err != 0 { err }` COMPILES, so a lowercase head
///     binds and the name is in scope afterwards.
///   - `if opt() is Some && Some != 0` is REJECTED by the compiler, and the only
///     reading that explains a rejection is `Some` being the constructor -- a
///     function compared with an integer -- rather than a binding of the
///     element's type.
///
/// The probe's own first draft got this backwards by accident and is worth
/// recording: it asked the same question with `probe() -> Int` as the base, so
/// every case using `Some`/`Err` failed with 4014, a plain Int/Option type
/// mismatch. Three "verdicts" about the grammar were really about the prelude.
/// A positive control that fails means the probe is wrong, and the fix was a
/// second `opt() -> Option[Int]`, not a revised expectation.
///
/// `_` and keywords are refused here as well as by `pattern_binding_at`, because
/// this predicate is the one deciding whether the head binds at all.
fn is_binding_head_name(s : String) -> Bool {
  if s == "" || s == "_" || @lexer.is_moonbit_keyword(s) {
    return false
  }
  for ch in s.iter() {
    return ch >= 'a' && ch <= 'z'
  }
  false
}

///|
fn Parser::parse_is_pattern(self : Parser) -> Array[String] {
  // A TUPLE pattern: `is (Some(a), Some(b), None)`. The head is `(`, not a
  // name, so the name-only guard below returned "" without consuming anything
  // and the rest of the pattern was left to be read as an expression. This is
  // the shape on `backend/common/embedded/embedded_runtime_backend.mbt:228`.
  //
  // EVERY binding in the group is collected, not just the first. The group is
  // consumed either way — a pattern left in the token stream desynchronises
  // every statement after it — but dropping the names leaves the frame unable
  // to resolve them at their uses.
  if self.at(TLParen) {
    let found : Array[String] = []
    let mut depth = 0
    let mut j = self.p
    let mut in_type = false
    while j < self.toks.length() {
      match self.toks[j] {
        TLParen => depth += 1
        TRParen => {
          depth -= 1
          if depth == 0 {
            j += 1
            break
          }
        }
        TEOF => break
        TColon => in_type = true
        // `depth >= 2`, NOT `>= 1`: the outer `(` here is a GROUPING paren, not a
        // constructor payload, so a bare name directly inside it is a
        // CONSTRUCTOR of an or-pattern — `proton internal/bridge_admission_test/
        // main.mbt:93`, `... is (Gone | PageUnavailable)`, where binding `Gone`
        // and `PageUnavailable` reports two unused locals that do not exist.
        // A tuple pattern's bindings are one level in, inside `Some(`.
        TName(n) =>
          if !in_type && depth >= 2 && self.pattern_binding_at(j) {
            found.push(n)
          }
        _ => ()
      }
      j += 1
    }
    self.p = j
    return found
  }
  // 0460 -- an ARRAY PATTERN, `is [ a, b, c ]`. Without this branch the `[` fell
  // through to the head branch below, which read the FIRST ELEMENT as the head
  // name and returned. Three consequences, measured on `async 0.22.4
  // src/internal/gzip_internal/metadata.mbt`:
  //
  //   * the elements were read as EXPRESSIONS, so the four names the pattern binds
  //     were reported `undefined name 'compression_method'` and then used eight
  //     lines later -- a confident false positive against legal MoonBit;
  //   * the `]` was never consumed, so the token after the pattern was read as
  //     code: `undefined name 'else'`, ON A KEYWORD, which is the loudest possible
  //     tell that the pattern never ended;
  //   * `no visible binding for 'u32le'`, because `u32le(mtime)` was read as a call.
  //
  // All 14 async and all 9 proton findings the 0459 lexer work surfaced are this
  // shape, which is why 0459 could not ship alone.
  //
  // WHY EVERY LOWERCASE NAME BINDS HERE, AT ANY DEPTH -- unlike the tuple branch
  // just above, which needs `depth >= 2` because a bare name directly inside `(`
  // is a CONSTRUCTOR of an or-pattern. An array element IS a binding: settled 7/7
  // in `_verify/settle_0460_array_pattern.ps1`, where `[Some(v)]` binds `v` (a
  // name inside constructor parens, depth 2) and `[[inner], tail]` binds `inner`
  // (depth 2, inside a NESTED bracket) while `[1, 2, 3]` binds nothing and a
  // pattern that does not mention a name leaves it unbound.
  //
  // The settle also refused the obvious guess: `name(args)` in a pattern is a
  // CONSTRUCTOR pattern, not a call. A first draft used a plain function and got
  // "The type Int does not have the constructor pair" -- which is why `u32le`, a
  // builtin constructor, is legal in the corpus at all.
  if self.at(TLBracket) {
    let _ = self.bump()
    let found : Array[String] = []
    let mut depth = 1
    let mut j = self.p
    while j < self.toks.length() {
      match self.toks[j] {
        TLBracket => depth += 1
        TRBracket => {
          depth -= 1
          if depth == 0 {
            j += 1
            break
          }
        }
        TEOF => break
        // 0466b: `.. rest` inside the bracket is a BINDING. `pattern_binding_at`
        // refuses any name preceded by a `TDot` -- correctly, for `Foo.bar` -- and
        // `.. rest` is two dots. The corpus shape is
        // `[u32le(_), u32le(mask), .. payload]`, whose `payload` then reads as an
        // ordinary local. See `rest_binding_at`.
        TName(n) =>
          if self.pattern_binding_at(j) || self.rest_binding_at(j) {
            found.push(n)
          }
        _ => ()
      }
      j += 1
    }
    self.p = j
    return found
  }
  let mut head = ""
  let mut qualified = false
  if self.peek_name() != "" {
    head = self.peek_name()
    let _ = self.bump()
    // A PACKAGE-qualified head: `@pkg.Type::Ctor`. `@pkg` already lexed as ONE
    // `TName`, with the `@` INSIDE the name string (lexer.mbt:361, "a lone `@`
    // starts a package alias token") -- so `peek_name()` returns `"@pkg"`, NOT
    // `""`, and the `::` loop below never sees anything because the token after
    // the head is a `.` and not a `:`.
    //
    // THE PINNED REASON WAS WRONG about this, and 0455 is the precedent for
    // distrusting one. `parser_0436_test.mbt` recorded that "`parse_is_pattern`
    // reads a `TName` head, and this head starts with `@`, so `peek_name()` is
    // `\"\"`, the reader returns without consuming anything". It does not: the
    // reader consumes `@pkg` and returns with `.Type::Ctor` still in the token
    // stream, which is why the scanner reported `unexpected token `:` `` on a
    // line whose `:` is a path marker rather than `unexpected token @``. Same
    // symptom, and the fix this needs is four tokens instead of a new head kind.
    //
    // Settled with the toolchain before implementing, not after -- see
    // `_verify/settle_0456_at_is_head.ps1`, 9/9 with the canary REJECTing and the
    // package boundary REJECTing. `is @pkg.Type::Ctor` is legal MoonBit, so the
    // parser must CONSUME the path rather than leave it behind.
    if head.has_prefix("@") && self.at(TDot) {
      let _ = self.bump()
      if self.peek_name() != "" {
        let _ = self.bump()
      }
    }
    // A QUALIFIED constructor: `is St::Shutdown`. There is no `TColonColon` in
    // the lexer -- `::` is two `TColon` tokens -- so the path tail has to be
    // consumed HERE or the second `:` survives the pattern, walks back up
    // through parse_cmp and lands in `parse_atom`'s catch-all.
    //
    // Settled with the toolchain, not inferred -- `_verify/probe_sweep_0434.ps1`
    // case `is_expr_if_cond`, one form per package with a broken canary
    // alongside: `if self is St::Shutdown { 1 } else { 2 }` is 0 errors from
    // `moon check`. The unqualified `is Shutdown` beside it already parsed, which
    // is what makes this specific to the QUALIFIED form.
    //
    // Consuming the tail BEFORE the payload test is also what makes
    // `is St::Some(x)` bind `x` for free: the two `::` tokens are gone by the
    // time the `TLParen` branch below runs, so a qualified constructor with a
    // payload takes the same path as an unqualified one.
    //
    // `while`, not `if` -- and the honest reason is NOT the one first written
    // here, which was wrong. It said "the head may be `@pkg.Type::Ctor`, which is
    // three segments". That is false for this loop: such a head begins with `@`,
    // so `peek_name()` is "" and the branch below never reaches this code at all.
    // `@pkg.Type::Ctor` is a SEPARATE gap: 48 corpus SITES, 32 of them in
    // wzzc-dev/moui across 16 files -- but only ONE file is actually blocked by
    // it today (`backend/macos/macos_services.mbt`, measured file-by-file by
    // `_verify/pkg_head_impact.ps1`), because the other 15 keep the site inside a
    // skipped `test` block. Pinned as a KNOWN LIMIT in `parser_0436_test.mbt`.
    //
    // `while` and `if` actually differ on is a head with TWO or more `::`
    // after the first segment, and there are ZERO such sites in any corpus here:
    // `Select-String '\bis\s+(?!@)\w+(\w*::\w*){2,}'` over every `.mbt`/`.mbti`
    // in `.repos` returns nothing. So the loop is unobservable on everything
    // measured, which makes `while` defensiveness rather than a measured
    // requirement -- and gate 0436's M3 declares exactly that rather than
    // inventing a test to make a stylistic branch look load-bearing.
    //
    // It is kept anyway, and the reason is the cheap direction: narrowing to `if`
    // would be a change justified by NO measurement, while the cost of keeping a
    // loop that iterates once is one comparison. When a multi-`::` pattern head
    // does show up, M3 turns red and the question gets answered by evidence.
    //
    // NOT shared with the other two qualified-path readers
    // (`parse_fn_signature`, `parse_postfix_from`) on purpose: those need the
    // NAME and fold it into what they return, while a pattern's text is
    // discarded and only its bindings survive. A shared helper would have to
    // return the tail for the other two and ignore it here, which is a worse
    // shape than three short loops that do visibly different things.
    while self.at(TColon) && self.at_next(TColon) {
      qualified = true
      let _ = self.bump()
      let _ = self.bump()
      if self.peek_name() == "" {
        break
      }
      let _ = self.bump()
    }
  } else if self.at_pattern_literal() {
    // 0460 -- a LITERAL PATTERN: `guard compression_method is b'\x08' else { .. }`.
    //
    // This branch used to be the bare `return []` below, which CONSUMED NOTHING.
    // A literal is a complete pattern that binds no name, so returning immediately
    // left both the literal and everything after it in the stream -- and the
    // token after a guard's pattern is `else`. The measured result was
    // `undefined name 'else'` ON A KEYWORD, in `async 0.22.4
    // src/internal/gzip_internal/metadata.mbt:69` and `:72`.
    //
    // The keyword is the tell. A pattern that did not end cannot report anything
    // more specific than "there is a name I cannot resolve here", and the one
    // name it cannot resolve is `else`.
    let _ = self.bump()
    return []
  } else {
    return []
  }
  let binding : Array[String] = []
  // A BARE LOWERCASE HEAD IS A VARIABLE BINDING, and the first draft consumed it
  // as a constructor and discarded it. `expr is err && err != 0` then bound
  // nothing and every later `err` was an undefined name.
  //
  // SETTLED, not inferred -- `_verify/settle_0444_is_head.ps1`, 9/9 with the
  // positive control AND a canary green:
  //
  //   - a lowercase head binds: `if probe() is err && err != 0 { err }` compiles.
  //   - an uppercase head is a CONSTRUCTOR TEST: `if opt() is Some` is legal, and
  //     `if opt() is Some && Some != 0` is REJECTED -- a function compared with an
  //     integer, possible only if `Some` is the constructor and not a binding.
  //   - `_` still binds nothing.
  //
  // The three exclusions are the settled grammar rather than caution: a payload
  // follows (`Some(x)` -- a constructor taking arguments), a QUALIFIED head
  // (`is St::Shutdown` -- the constructor is the last segment), and a keyword
  // (`is true` bound the literal `true` once already). `is @pkg.Type::Ctor` never
  // reaches here at all, because `peek_name()` is "" for an `@` head.
  if !qualified && !self.at(TLParen) && is_binding_head_name(head) {
    binding.push(head)
  }
  if self.at(TLParen) {
    let _ = self.bump()
    let mut depth = 1
    let mut in_type = false
    while depth > 0 && !self.at(TEOF) {
      if self.at(TLParen) {
        depth += 1
      } else if self.at(TRParen) {
        depth -= 1
        if depth == 0 {
          // Consume the closing paren BEFORE leaving the loop: returning
          // while still sitting on it makes the caller's next token a `)`,
          // which is how `v is Some(k)` died at line 2 while `v is Int`
          // parsed fine. Inner closes of `Some(Some(x))` fall through to
          // the loop-bottom bump, so every `)` is eaten exactly once.
          let _ = self.bump()
          break
        }
      } else if self.at(TColon) {
        in_type = true
      } else if !in_type && self.at_pattern_binding() {
        let (n, _) = self.expect_name("pattern binding")
        binding.push(n)
        continue
      }
      let _ = self.bump()
    }
  }
  binding
}

///|
/// The bitwise tiers, loosest to tightest: `|`, then `^`, then `&`, then the
/// shifts — the standard precedence-climbing shape of parse_or/parse_and,
/// each delegating one tier down and looping on its own token. They sit
/// between `is` and additive, matching real MoonBit: every bitwise op binds
/// tighter than comparison and `is`, looser than `+`, so `1 + (h & 1023)`
/// (the measured Class F death at statecheck.mbt:275) parses as
/// `1 + (h & 1023)` with the mask applied to `h`. Before these tiers the
/// tokens existed only to stop the lexer reporting, and one reaching
/// expression position broke the parse.
fn Parser::parse_bitor(self : Parser) -> @ast.Expr {
  let mut l = self.parse_bitxor()
  while self.at(TBar) {
    let _ = self.bump()
    let r = self.parse_bitxor()
    l = { span: l.span, kind: @ast.EBin(OpBitOr, l, r), }
  }
  l
}

///|
fn Parser::parse_bitxor(self : Parser) -> @ast.Expr {
  let mut l = self.parse_bitand()
  while self.at(TCaret) {
    let _ = self.bump()
    let r = self.parse_bitand()
    l = { span: l.span, kind: @ast.EBin(OpBitXor, l, r), }
  }
  l
}

///|
fn Parser::parse_bitand(self : Parser) -> @ast.Expr {
  let mut l = self.parse_shift()
  while self.at(TAmp) {
    let _ = self.bump()
    let r = self.parse_shift()
    l = { span: l.span, kind: @ast.EBin(OpBitAnd, l, r), }
  }
  l
}

///|
fn Parser::parse_shift(self : Parser) -> @ast.Expr {
  let mut l = self.parse_add()
  while self.at(TShl) || self.at(TShr) {
    let op = if self.at(TShl) { @ast.OpShl } else { @ast.OpShr }
    let _ = self.bump()
    let r = self.parse_add()
    l = { span: l.span, kind: @ast.EBin(op, l, r), }
  }
  l
}

///|
fn Parser::parse_cmp(self : Parser) -> @ast.Expr {
  let mut l = self.parse_is()
  while self.at(TLt) || self.at(TLe) || self.at(TGt) || self.at(TGe) {
    let op = match self.peek() {
      TLt => @ast.OpLt
      TLe => @ast.OpLe
      TGt => @ast.OpGt
      _ => @ast.OpGe
    }
    let _ = self.bump()
    let r = self.parse_is()
    l = { span: l.span, kind: @ast.EBin(op, l, r), }
  }
  l
}

///|
fn Parser::parse_add(self : Parser) -> @ast.Expr {
  let mut l = self.parse_mul()
  while self.at(TPlus) ||
        self.at(TMinus) ||
        self.at(TRange) ||
        self.at(TRangeIncl) {
    if self.at(TRange) || self.at(TRangeIncl) {
      // `a..<b` exclusive, `a..<=b` INCLUSIVE. The right side is read at UNARY
      // precedence on purpose: ranges occur almost only in `for i in a..<b`
      // heads, where both this reading and the strict reading parse and walk
      // identically, and `1..<n*2` reading as `(1..<n)*2` costs nothing — the
      // walk visits every operand either way. A whole precedence tier for one
      // operator would be the dearer mistake.
      let incl = self.at(TRangeIncl)
      let sp = self.span()
      let _ = self.bump()
      let r = self.parse_unary()
      // No lens models inclusivity: `walk`, `types::infer` and `interp` all
      // treat `ERange(a, b)` the same, reading both operands and nothing else.
      // So the inclusive end is READ and NOT ANALYSED, and says so. Folding
      // `a..<=b` into `ERange` without a notice would make it indistinguishable
      // from `a..<b` in the tree -- and iterating n times versus n+1 times is
      // not a difference to lose silently.
      if incl {
        self.note_skip(
          "inclusive range end is outside the analyzed subset; it was read but the bound was not analysed",
          sp,
        )
      }
      l = { span: l.span, kind: @ast.ERange(l, r), }
    } else {
      let op = if self.at(TPlus) { @ast.OpAdd } else { @ast.OpSub }
      let _ = self.bump()
      let r = self.parse_mul()
      l = { span: l.span, kind: @ast.EBin(op, l, r), }
    }
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
  self.parse_postfix_from(self.parse_atom())
}

///| The postfix LOOP, split out so a caller that already holds an expression

///| can KEEP EXTENDING it. `parse_postfix` is exactly this loop applied to a

///|
/// freshly parsed atom and nothing else, so the two forms cannot drift.
///
/// The caller that needs it is the leading-dot continuation in `parse_stmt`,
/// where the BASE is the expression on the PREVIOUS line — already parsed, and
/// owned by the preceding statement. Rebuilding that chain by hand here would
/// have meant re-implementing `.field`, `.field(args)`, `::path`, `[i]` and
/// `catch`, and every one of those is a shape real code writes.
fn Parser::parse_postfix_from(self : Parser, start : @ast.Expr) -> @ast.Expr {
  let mut e = start
  while true {
    // `recv..name(args)` -- the `..` CHAIN LINK, 180 sites in 33 corpus files.
    //
    // CHECKED BEFORE THE SINGLE-DOT BRANCH BELOW, and that ordering is the whole
    // fix: `..` arrives as TWO TDot tokens (the lexer has `..<` and `..<=` but no
    // bare `..` one), so the single-dot branch used to bump the first and hand
    // the second to `expect_name`, which reported `expected field name` -- a
    // message naming neither the operator nor the receiver. Measured on fixtures:
    // all six double-dot shapes NOTPARSE that way while the spread and the
    // single-dot chain stayed CLEAN.
    //
    // NOT A SPELLING OF `recv.name(args)`. `recv..name(args)` calls `name`,
    // discards its result, and evaluates to `recv`, so the node is `EDotDot` and
    // not `EMethodCall` -- see `@ast.EDotDot` and
    // `_verify/settle_0465_dotdot_chain.ps1`.
    //
    // THE PARENTHESES ARE REQUIRED, measured rather than assumed: `dd_bare_name`
    // writes `..bump` with no argument list over a real method and is REJECTed
    // (4014, 3002). So this is not a shortcut for a common case, it is the
    // grammar, and a missing `(` reports here instead of producing a node the
    // toolchain would not accept.
    if self.at(TDot) && self.at_next(TDot) {
      let csp = self.span()
      let _ = self.bump()
      let _ = self.bump()
      let (m, _) = self.expect_name("method name after '..'")
      // STOP AT A MISSING `(`, do not fall through to parsing arguments.
      //
      // `expect` only bumps when the token matches, so on a bare `..name` the
      // cursor is still sitting on the line break and `parse_call_args` runs at
      // the wrong token. That produced a CASCADE -- `..bump` reported twice, once
      // as `expected '(' after '..' method name` and once more from the argument
      // loop -- and a cascade is not cosmetic: the NOTPARSE message tally is what
      // ranks the remaining work, so one defect counted as two messages would
      // send the next increment after a shape that does not exist. This file
      // reproduces it: 1x in the tally, 2 findings withheld.
      if !self.at(TLParen) {
        self.err("expected '(' after '..' method name", self.span())
        break
      }
      // The `(` is bumped HERE rather than by an `expect`, because `expect` bumps
      // only on success and this arm needs to know whether it did. Written the other
      // way round it consumed the FIRST ARGUMENT: `..write(path)` parsed from the
      // token after `path`, so `path` never reached the AST and `parameter 'path' may
      // not be used` fired on four fixtures with `moon check --deny-warn` completely
      // clean -- a dropped argument still yields a well-typed tree.
      let _ = self.bump()
      let (args, labels) = self.parse_call_args()
      self.expect(TRParen, "')'")
      e = { span: csp, kind: @ast.EDotDot(e, m, args, labels), }
      continue
    }
    if self.at(TDot) {
      let _ = self.bump()
      // `pair.0` — a tuple FIELD is an Int literal, not a name. The number
      // lexer makes the forms honest: `pair.0` is TDot + TInt(0), while
      // `x.0.1` lexes `0.1` as one TFloat, which refuses to be a field and
      // reports here. `pair.0(` is not a call form — only named functions
      // and methods can be called — and reports at the TLParen branch
      // below. Measured blocker: statecheck.mbt:76 `pair.0 == trigger`.
      if self.peek() is TInt(_) {
        let i = match self.peek() {
          TInt(n) => n
          _ => 0
        }
        let _ = self.bump()
        e = { span: e.span, kind: @ast.ETupleField(e, i), }
        continue
      }
      let (f, fsp) = self.expect_name("field name")
      e = { span: e.span, kind: @ast.EField(e, f), }
      ignore(fsp)
      continue
    }
    if self.at(TLBracket) {
      let _ = self.bump()
      // `[a:b]` — a colon-slice is an index with a range: it reuses
      // EIndex(base, ERange(a, b)), the one shape the lenses already walk
      // and type, instead of a new node. An open END (`s[n:]`) yields
      // EBigInt for the missing side — the opaque placeholder, not a
      // value: const_eval must not fold a bound it never read. A list
      // literal cannot misfire here: its commas make `at(TColon)` false,
      // and colons inside string elements are inside TStr tokens.
      //
      // AN EMPTY START BOUND IS CHECKED FIRST, and that ordering is the whole
      // fix. This used to call `parse_expr()` for the start and only then ask
      // `at(TColon)`, so a `[` sitting directly on a `:` handed the colon to
      // the expression parser and the file died with ``unexpected token `:` ``.
      // That is the reason string on eight of the blocked corpus files, and the
      // `:` is a bound marker, not a stray token.
      //
      // Two shapes, both real and both in the corpus:
      //   `value[:]`         both bounds empty   -- core/semantics.mbt:71,
      //                       core/declaration.mbt:102, and `bytes[:]` at
      //                       backend/windows/windows_accessibility_bridge.mbt:490
      //   `chars[:index]`    open start, real end -- core/unicode/grapheme_cluster.mbt:248
      //
      // The comment here used to say an open START "is not in the corpus and
      // reports honestly". That was true when written; `chars[:index]` made it
      // stale, and "reports honestly" was doing a lot of work to disguise a
      // blocker. EBigInt for the missing side is the same treatment the open END
      // already got, for the same reason: a bound that was never read must not
      // be folded as if it had been.
      //
      // Settled with the toolchain, one form per package with a broken canary
      // beside each (`_verify/probe_sweep_0434.ps1`, case `slice_empty_bounds`
      // and the `slice_open_start` added beside it, canary firing):
      // `let s = value[:]` and `let s = value[:2]` are both 0 errors.
      let first : @ast.Expr = if self.at(TColon) {
        let zsp = self.span()
        { span: zsp, kind: @ast.EBigInt, }
      } else {
        self.parse_expr()
      }
      if self.at(TColon) {
        let _ = self.bump()
        let end : @ast.Expr = if self.at(TRBracket) {
          { span: first.span, kind: @ast.EBigInt, }
        } else {
          self.parse_expr()
        }
        self.expect(TRBracket, "']'")
        e = {
          span: e.span,
          kind: @ast.EIndex(e, {
            span: first.span,
            kind: @ast.ERange(first, end),
          }),
        }
        continue
      }
      self.expect(TRBracket, "']'")
      e = { span: e.span, kind: @ast.EIndex(e, first), }
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
      if self.at(TLBrace) {
        // `Type::{ field: value, shorthand, }` — a struct literal. MoonBit
        // marks the literal with `::`, and that mark is what makes the brace
        // safe to consume HERE: nothing but a struct literal follows a
        // `Type::` path, unlike a bare `{ ... }` block, which can appear in
        // plain expression position. The brace's span is captured before
        // the bump — it is where a non-literal block reports, at the brace
        // the misparse began at.
        let brace_sp = self.span()
        let _ = self.bump()
        let fields = self.parse_struct_fields(brace_sp)
        e = { span: e.span, kind: @ast.EStruct(path, fields), }
        continue
      }
      let (m, _) = self.expect_name("name after '::'")
      e = { span: e.span, kind: @ast.EName(path + "::" + m), }
      continue
    }
    if self.at(TLParen) {
      let csp = self.span()
      let _ = self.bump()
      let (args, labels) = self.parse_call_args()
      self.expect(TRParen, "')'")
      match e.kind {
        @ast.EName(n) => e = { span: csp, kind: @ast.ECall(n, args, labels), }
        // A method call. `receiver.name` was an EField up to this point; the
        // `(` is what makes it a call, and only now are the arguments known.
        @ast.EField(base, m) =>
          e = { span: csp, kind: @ast.EMethodCall(base, m, args, labels), }
        _ => self.err("only named functions and methods can be called", csp)
      }
      continue
    }
    // `expr catch { pattern => handler }` — MoonBit's postfix error
    // handling on a call. The `catch { ... }` group is PARSED into
    // `@ast.CatchArm`s rather than consumed by `skip_braces`.
    //
    // The call — whose arguments ARE read — has always survived here, and that
    // was the reason this arm existed at all: without it the loop broke on the
    // `catch` keyword and every line shaped like
    // `@process.collect_output(cmd) catch { _ => return "" }` (the measured
    // Class E deaths at provenance.mbt:416 and jsoncli/main.mbt:252) died at
    // the keyword instead of yielding its call. `catch` is a keyword in
    // MoonBit, so at_name here can never capture an identifier.
    //
    // WHAT CHANGED, AND WHY IT WAS NOT OPTIONAL. `skip_braces` also threw away
    // the handler BODY, and a body is where the reads of the enclosing
    // function's parameters live. The measured cost was wzzc-dev/moui
    // `backend/macos/macos_native_ime.mbt:437`:
    //
    //     fn native_ime_content_view_handle(..., prefix~ : String) -> UInt64? {
    //       Some(...) catch { err => { println(prefix + " ... \{err}") ; None } }
    //     }
    //
    // reported as `parameter 'prefix' may not be used`. `prefix` is read only
    // inside the handler, so the only mention of it in the function was
    // invisible and the parameter read as unused — the corpus's only
    // actionable finding.
    //
    // Reading the body is only safe if the PATTERN is read too, which is why
    // this calls `parse_catch_arms` and not `skip_braces`: the body would
    // otherwise resolve `err` as an unbound name. See `@ast.ECatch`.
    if self.at_name("catch") {
      let csp = self.span()
      let _ = self.bump()
      let arms = self.parse_catch_arms()
      // The span is the `catch` TOKEN, for the `ECast` reason: the base
      // survives as a child and stays reachable through it, while the position
      // of `catch` itself is recorded nowhere else.
      e = { span: csp, kind: @ast.ECatch(e, arms), }
      // `noraise { ... }` -- a SECOND handler block on the completed catch.
      //
      // IT IS NESTED HERE RATHER THAN MATCHED AS A BARE KEYWORD, and that is
      // the settled grammar doing the work: `try expr noraise { .. }` with no
      // catch is REJECTED by the compiler
      // (`_verify/settle_0441_noraise.ps1`, case `nr_without_catch`). A parser
      // that matched `noraise` anywhere would accept a program the compiler
      // rejects, and would swallow a user's own function named `noraise`.
      //
      // `parse_catch_arms` is reused unchanged, and that carries two things
      // rather than one: the arm grammar is the same (settled: several arms,
      // block or expression bodies), and so is the `<?` log-payload guard. A
      // `noraise` group containing an `@xlog` payload goes back to
      // `skip_braces` exactly as a `catch` group does, rather than becoming a
      // new way for `facade_locale.mbt` to fall out of `parsed`.
      if self.at_name("noraise") {
        let nsp = self.span()
        let _ = self.bump()
        let narms = self.parse_catch_arms()
        e = { span: nsp, kind: @ast.ENoRaise(e, narms), }
      }
      continue
    }
    // `expr as &Trait` — a trait-object cast, and the postfix keyword that
    // had NO production until 0.4.29. Without this arm the loop broke on the
    // `as`, the statement reader took it as the start of the next expression,
    // and the binding walk resolved it as an identifier: `undefined name 'as'`
    // on a program `moon check` accepts with zero errors. Measured at
    // wzzc-dev/moui `runtime/view_tree.mbt:69:38`, and it was the corpus's
    // only actionable finding.
    //
    // The target type is read by `type_annotation` and DISCARDED. It is not
    // carried because nothing can check it: the trait-object rule `as`
    // obeys needs to tell a trait from a struct, and `IfaceSymTab` keeps no
    // such distinction. The operand is kept — `ECast(base)` — and walked, so
    // a parameter read only inside a cast still counts as read.
    //
    // THE SPAN IS THE `as` TOKEN, not the operand's. Every other extension in
    // this loop keeps the base span, but those nodes flatten the base into a
    // name or a field and the base's own span would otherwise be lost; here
    // the operand survives as a child, so its position is still reachable
    // through `ECast`, while the position of `as` itself is recorded nowhere
    // else. Losing the operand's span would lose nothing; losing this one
    // would make the node unplaceable.
    if self.at_name("as") {
      let asp = self.span()
      let _ = self.bump()
      let _ = self.type_annotation()
      e = { span: asp, kind: @ast.ECast(e), }
      continue
    }
    // A chain CONTINUING on the next line: `expr` newline `.method(...)`.
    //
    // Until now this only worked in STATEMENT position, where `parse_stmt` has
    // its own leading-dot continuation (the block at its `if self.at(TDot)`).
    // Everywhere else the postfix loop simply broke at the newline, which is
    // SILENT in the two positions that matter most:
    //
    //   let v = wrap(a)
    //     .length()
    //
    // parses, and `v` is typed `[int]` — the `.length()` is discarded and the
    // type lens then reports a mismatch on correct code. Measured with a
    // positive control: `let v = wrap(a).length()` gives `int`, the two-line
    // form gives `[int]`.
    //
    // In ARGUMENT position the same drop leaves the chain's tokens unconsumed
    // and the file dies on the call's own `)`. That was 17 of wzzc-dev/moui
    // 0.1.12's 86 unreadable files at 0.4.30 — the whole shape being
    //
    //   rows.push(
    //     @button.button(...)
    //     .disabled(disabled=!item.enabled)
    //     .semantics_selected(...),
    //   )
    //
    // Settled with the toolchain: `_verify/grammar_probe.ps1` case
    // `chain_dot_next_line` is 0 errors from `moon check`, with
    // `chain_dot_same_line_control` beside it already parsing.
    //
    // The separators are consumed SPECULATIVELY and rewound when the
    // continuation does not follow -- the same trade `parse_stmt` documents,
    // for the same reason: swallowing them unconditionally would fuse the next
    // real statement into this one. Here it can also keep the REAL receiver,
    // because the loop still holds it; the statement-level path can only offer
    // an `EBigInt` placeholder there, which is a stated limit of that block.
    if self.at(TNewline) {
      let save = self.p
      self.skip_seps()
      if self.at(TDot) {
        continue
      }
      self.p = save
    }
    break
  }
  e
}

///|
/// The argument list of a call, up to but NOT including the closing `)`, and
/// the LABELS parallel to it: the parameter name for `f(name=…)` and for the
/// `x~` shorthand, `""` for a positional argument.
///
/// The two arrays must stay the same length at every push, which is why they
/// are pushed together below rather than at the end; a shorter `labels` array
/// would silently mis-index every argument after the first positional one.
/// Shared by `f(args)` and `receiver.f(args)` so the two forms cannot drift.
fn Parser::parse_call_args(self : Parser) -> (Array[@ast.Expr], Array[String]) {
  let args : Array[@ast.Expr] = []
  let labels : Array[String] = []
  while !self.at(TRParen) && !self.at(TEOF) {
    // Where this argument's text starts, so the `x~` shorthand below can read
    // the argument's own name back out of the stream once `parse_expr` has
    // moved the cursor past it.
    let arg_start = self.p
    // A short lambda `param => body`, detected BEFORE the named-argument
    // path below — whose `=` check would otherwise swallow the arrow, since
    // `=>` is not a lexer token and arrives as TAssign + TGt, and
    // `name = >...` is not an expression anyone writes. Both corpus body
    // shapes are handled: a brace body (`frame => { ... }`) is skipped
    // balanced; a bare expression body (`lens => lens.name()`) is skipped
    // token-wise to the depth-0 comma or the call's own `)`, which is left
    // for the comma handling below. The parameters are NOT parsed: a parsed
    // param would bind in the ENCLOSING scope and report a phantom unused.
    // The lambda yields an opaque EBigInt and a note; findings after it
    // stay trustworthy because the parse stayed in step.
    if self.at_arrow_lambda() {
      let lsp = self.span()
      let _ = self.bump()
      let _ = self.bump()
      let _ = self.bump()
      if self.at(TLBrace) {
        self.skip_braces()
      } else {
        self.skip_to_arg_boundary()
      }
      self.note_skip(
        "short lambda is outside the analyzed subset; it was read but not analysed",
        lsp,
      )
      args.push({ span: lsp, kind: @ast.EBigInt, })
      labels.push("")
      if self.at(TComma) {
        let _ = self.bump()
      } else {
        break
      }
      continue
    }
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
      let arg_label = self.peek_name()
      let _ = self.bump()
      // `name?=value` -- the OPTIONAL-NAMED argument, the member this family was
      // missing. moui 0.1.12 `views/popover/sheet.mbt:25` writes
      // `background?=background_brush,` and three files died on it, all reported as
      // `unexpected token `,``.
      //
      // THE DIAGNOSIS, which is about the loop and not about brackets. `f(x?)` and
      // `f(x~)` are both handled AFTER the argument has been parsed, by the
      // `TTilde` and `TQuestion` tests further down. For `border?=normal_border`
      // the sequence was: the `TAssign` test below is FALSE (the next token is
      // `?`), so `p` is restored and `border` is read as a positional name; the
      // `TQuestion` shorthand then consumes the `?` as if the argument ENDED; the
      // loop tests for a comma, finds the `=` that the first test skipped over, and
      // BREAKS. The `= value` behind the `?` was orphaned.
      //
      // THE `?` IS NOT DECORATION, so this cannot be desugared into `name=value`.
      // Settled in `_verify/settle_0454_label_qmark_eq.ps1`, 9/9 with a positive
      // control: `border?=v` against a parameter declared `border? : Int` ACCEPTS,
      // and against `border~ : Int` is REJECT(4141) "this form of application is
      // invalid for argument border~, because it is not declared with border? : _".
      // A `name? : T` parameter has type `T?` -- that is what the settle's bare
      // `border?=7` measured, as REJECT(4014) "wanted Int?". So the `?` names the
      // optionality of the TARGET and a fix that drops it reads illegal code as
      // legal.
      //
      // The label recorded is the BARE name, without the `?`. The type lens
      // maps arguments to parameters by label, and both spellings name the
      // same parameter; the `?` lives in the PARAMETER's declaration
      // (`border? : Int`), which is why the settle above has to reject
      // `border?=v` against `border~ : Int` for that rejection to mean
      // anything at all.
      if self.at(TQuestion) && self.toks[self.p + 1] == TAssign {
        let _ = self.bump()
        let _ = self.bump()
        args.push(self.parse_expr())
        labels.push(arg_label)
      } else if self.at(TAssign) {
        let _ = self.bump()
        if self.at_lambda_head() {
          // A lambda as a NAMED argument's VALUE. The arrow check below only
          // runs on the positional path, so `event=(node, ctx) => f(...)` and
          // `children=_node => [child]` reached `parse_expr`, which read the
          // parameters as an expression and then tripped on `=>`.
          let lsp = self.span()
          self.skip_lambda_head()
          if self.at(TLBrace) {
            self.skip_braces()
          } else {
            self.skip_to_arg_boundary()
          }
          self.note_skip(
            "short lambda is outside the analyzed subset; it was read but not analysed",
            lsp,
          )
          args.push({ span: lsp, kind: @ast.EBigInt, })
          labels.push(arg_label)
        } else {
          args.push(self.parse_expr())
          labels.push(arg_label)
        }
      } else {
        self.p = saved_p
        args.push(self.parse_expr())
        labels.push("")
      }
    } else {
      args.push(self.parse_expr())
      labels.push("")
    }
    // `f(x~)` — the shorthand for `f(x=x)`, settled by `moon check` (0.4.18):
    // it passes the local `x` under its own label. The label is recorded for
    // the same reason `name = value` above records it, because the `~` form
    // names a parameter too — the argument's index is not the parameter's
    // index whenever any argument is named. Only reached after a real
    // argument, so the short-lambda branch above (which `continue`s) is
    // unaffected, and `labels` is non-empty by then.
    if self.at(TTilde) {
      let _ = self.bump()
      if labels[labels.length() - 1] == "" {
        labels[labels.length() - 1] = self.name_at(arg_start)
      }
    }
    // `f(x?)` — the OPTIONAL-PARAMETER shorthand, the `~` sibling above.
    // `x?` passes the enclosing `x` onward only if the caller has one, so it
    // names the same label `x~` does and is recorded the same way: the type
    // lens maps arguments to parameters BY LABEL whenever any argument is
    // named (see the `ECall` note in ast.mbt), and a blank label here would
    // send it back to positional index matching.
    //
    // Settled with the toolchain, not inferred — `_verify/grammar_probe.ps1`
    // case `optarg_question`, one form per package with a broken canary
    // alongside: `fn sink(theme? : Int = 0)` + `sink(theme?)` is 0 errors from
    // `moon check`. The `~` form beside it is the control that already parsed.
    //
    // What this cost before the fix: `f(x?)` left the `?` unconsumed, the
    // argument loop broke on "not a comma", and the caller then demanded a `)`
    // that was not there — so the whole file died with `expected ')'`. On
    // wzzc-dev/moui 0.1.12 that was 34 files, the largest single named blocker
    // in the corpus, and the cascade surfaced as ``unexpected token `,` ``
    // wherever a further argument followed.
    //
    // Safe because MoonBit has no ternary `?:` and no postfix `?`, so a `?`
    // directly after an argument is always this sigil. `x?` in TYPE position
    // (`(v : Int?)`) never reaches here: that is consumed by the type
    // annotation reader.
    if self.at(TQuestion) {
      let _ = self.bump()
      if labels[labels.length() - 1] == "" {
        labels[labels.length() - 1] = self.name_at(arg_start)
      }
    }
    if self.at(TComma) {
      let _ = self.bump()
    } else {
      break
    }
  }
  (args, labels)
}

///|
/// Is the cursor at the HEAD of a short lambda, in any of the three spellings a
/// named argument's value takes?
///
///   `(node, ctx) => f(...)`   — a parenthesised parameter list
///   `_node => [child]`         — one bare name
///   `(node : Flow) => ...`    — a typed parameter, via the parenthesised form
///
/// The `=>` is `TAssign` followed by `TGt`; there is no `=>` token. The
/// parenthesised form must SCAN to its matching `)` and check the two tokens
/// after it — looking only at `(`, a name, `=>` would miss it, which is the
/// same trap `return_annotation` fell into in 0.4.19.
fn Parser::at_lambda_head(self : Parser) -> Bool {
  if self.at(TLParen) {
    let mut depth = 0
    let mut j = self.p
    while j < self.toks.length() {
      match self.toks[j] {
        TLParen => depth += 1
        TRParen => {
          depth -= 1
          if depth == 0 {
            return j + 2 < self.toks.length() &&
              self.toks[j + 1] == TAssign &&
              self.toks[j + 2] == TGt
          }
        }
        TEOF => return false
        _ => ()
      }
      j += 1
    }
    return false
  }
  if self.peek_name() == "" {
    return false
  }
  // One bare parameter, optionally modified and optionally typed: `x?`, `x~`,
  // `x : T`, `x? : T`. The `:` arm scans to the `=` at depth 0.
  //
  // TWO BOUNDS ON THAT SCAN, both added in 0.4.30 because without them the arm
  // matched things that are not lambdas AT ALL. It was only reachable from a
  // named argument's value and a parameter's default, where a `:` really is an
  // annotation; putting it in `parse_expr` put it in front of every expression,
  // and two shapes it had never been asked about turned up:
  //
  //   * `::` IS a path separator and starts with the same `:` token, so
  //     `T::{}` -- a struct literal, a very ordinary expression -- read as "the
  //     bare parameter `T`, annotated". Rejected below by refusing to treat a
  //     doubled colon as an annotation.
  //   * The scan then ran to the NEXT `=` in the file with no stopping
  //     condition, and `=>` is `TAssign` + `TGt`. So `T::{}` followed anywhere
  //     later by a `match` arm was read as one enormous lambda head: the parser
  //     ate the struct literal, the function that followed, and the match, and
  //     the file died reporting `expected type name`. Measured on this repo's own
  //     `src/core/core.mbt`, where `T::{}` in `IfaceSymTab::empty()` sat 60 lines
  //     before `match self.values.get(name) { Some(v) => v ... }`.
  //
  //     The self-scan is what found it, and it is worth recording WHY it could:
  //     the suite was green, because no test had a `::` expression and a `=>`
  //     in the same file. A regression test that only exercises the fix in
  //     isolation would have missed it again, so the test pairs them.
  //
  // So the scan stops at the first `=` AND refuses to leave the construct: a
  // doubled colon, or a depth-0 `,` `)` or newline, ends the search.
  let mut j = self.p + 1
  while j < self.toks.length() &&
        (self.toks[j] == TQuestion || self.toks[j] == TTilde) {
    j += 1
  }
  let annotated = j < self.toks.length() &&
    self.toks[j] == TColon &&
    !(j + 1 < self.toks.length() && self.toks[j + 1] == TColon)
  if annotated {
    let mut d = 0
    while j < self.toks.length() && self.toks[j] != TAssign {
      if d == 0 &&
        (
          self.toks[j] == TComma ||
          self.toks[j] == TRParen ||
          self.toks[j] == TNewline ||
          self.toks[j] == TRBrace ||
          self.toks[j] == TEOF
        ) {
        return false
      }
      if self.toks[j] == TLParen || self.toks[j] == TLBracket {
        d += 1
      } else if self.toks[j] == TRParen || self.toks[j] == TRBracket {
        d -= 1
      }
      j += 1
    }
  }
  j + 1 < self.toks.length() &&
  self.toks[j] == TAssign &&
  self.toks[j + 1] == TGt
}

///|
/// Consume the head of a short lambda — its parameters and the `=>` — leaving
/// the cursor on the BODY, which the caller skips.
///
/// The parameters are consumed, never PARSED, for the reason the positional
/// path already gives: a parsed parameter would bind in the ENCLOSING scope and
/// report a phantom unused, because the lambda itself is never walked.
fn Parser::skip_lambda_head(self : Parser) -> Unit {
  if self.at(TLParen) {
    let mut depth = 0
    while !self.at(TEOF) {
      if self.at(TLParen) {
        depth += 1
      } else if self.at(TRParen) {
        depth -= 1
        let _ = self.bump()
        if depth == 0 {
          break
        }
        continue
      }
      let _ = self.bump()
    }
  } else {
    let _ = self.bump() // the parameter name
    if self.at(TQuestion) || self.at(TTilde) {
      let _ = self.bump()
    }
    if self.at(TColon) {
      let _ = self.bump()
      ignore(self.type_annotation())
    }
  }
  if self.at(TAssign) {
    let _ = self.bump()
  }
  if self.at(TGt) {
    let _ = self.bump()
  }
}

///|
/// Is the current argument position the head of a short lambda
/// `param => body`? The arrow is a TAssign immediately followed by TGt —
/// the lexer has no `=>` token — and the head must be a name. `name = x`
/// never matches (the token after `=` is the value, not `>`), and
/// `a >= b` never matches either (`>=` is its own token).
fn Parser::at_arrow_lambda(self : Parser) -> Bool {
  self.peek_name() != "" &&
  self.peek2() == TAssign &&
  self.p + 2 < self.toks.length() &&
  self.toks[self.p + 2] == TGt
}

///|
/// Skip a short lambda's bare expression body up to, but not consuming, the
/// depth-0 `,` that starts the next argument or the `)` that closes the
/// call. Bracket depth keeps nested calls, blocks and lists inside the
/// body; string literals are single tokens, so their contents cannot fool
/// the depth count.
fn Parser::skip_to_arg_boundary(self : Parser) -> Unit {
  let mut depth = 0
  while !self.at(TEOF) {
    if depth == 0 && (self.at(TComma) || self.at(TRParen)) {
      return
    }
    if self.at(TLParen) || self.at(TLBrace) || self.at(TLBracket) {
      depth += 1
    } else if self.at(TRParen) || self.at(TRBrace) || self.at(TRBracket) {
      depth -= 1
    }
    let _ = self.bump()
  }
}

///|
/// The fields of a struct literal, from the first field through the closing
/// `}`. The opening brace is consumed by the caller — the `Type::` fold or
/// the atom arm — and `open_sp` is that brace's span.
///
/// Only two field shapes exist in this subset: `name : value` and a
/// bare-NAME shorthand, separated by commas (newlines tolerated), trailing
/// comma fine. Anything else means the braces were never a struct literal —
/// a real case is a plain block in expression position (`let x = { 1 }`),
/// which arrives through the bare-brace atom arm. That is reported ONCE, at
/// the opening brace: the misparse began there, and the brace's line is the
/// boundary the scanner records. The rest of the braces is then skipped
/// whole, so one strange token cannot cascade and the file stays readable
/// past it.
fn Parser::parse_struct_fields(
  self : Parser,
  open_sp : @core.Span,
) -> Array[(String, @ast.Expr)] {
  let fields : Array[(String, @ast.Expr)] = []
  while !self.at(TRBrace) && !self.at(TEOF) {
    self.skip_seps()
    if self.at(TRBrace) || self.at(TEOF) {
      break
    }
    // `{ ..base, f: v }` — the struct UPDATE syntax, and the only field shape
    // that does not start with a name. `..` arrives as TWO TDot tokens: the
    // lexer has a `..<` token but no bare `..` one.
    //
    // The base is pushed under an EMPTY name rather than dropped. All three
    // consumers (`walk`, `types::infer`, `interp`) destructure the field as
    // `let (_, v) = f` and only ever traverse the VALUE, so an empty name is
    // invisible to them — while keeping the expression alive is what stops
    // `{ ..self, cursor: c }` from reporting `self` as an unused parameter.
    // wzzc-dev/moui 0.1.12 writes `{ ..` 370 times across 88 files.
    if self.at(TDot) && self.at_next(TDot) {
      let _ = self.bump()
      let _ = self.bump()
      let base = self.parse_expr()
      fields.push(("", base))
      if self.at(TComma) {
        let _ = self.bump()
      }
      continue
    }
    // A QUOTED key -- `{ "a": 1 }`. This is a MAP literal, not a struct literal,
    // and the two are different language forms rather than two spellings of one:
    // `moon check` ACCEPTs the quoted form against `Map[String, Int]` and REFUSES
    // the unquoted one there with `[4033, 4028]`, while the unquoted form IS
    // accepted against a struct. Settled in
    // `_verify/settle_0452_quoted_key_map.ps1`, 5/5 with a positive control.
    //
    // SO THIS IS NOT A COSMETIC ACCEPT. It is read into the SAME field list with
    // the key as the name, because every consumer (`walk`, `types::infer`,
    // `interp`) already destructures `let (_, v) = f` and only ever traverses the
    // value -- so a map literal reached through the struct path costs nothing and
    // keeps the token stream in step with what follows the braces.
    //
    // A quoted key REQUIRES a `:`. The shorthand form has no meaning here: there
    // is no field named by a string, and accepting one would let `{ "a" }` parse
    // as something the toolchain rejects. `expect(TColon)` is therefore load
    // bearing rather than defensive, and the recovery below it is what keeps a
    // genuinely malformed literal from costing the rest of the file.
    if self.at_str() {
      let key = match self.peek() {
        TStr(s, _) => s
        _ => ""
      }
      let _ = self.bump()
      self.expect(TColon, "':'")
      let v = self.parse_expr()
      fields.push((key, v))
      if self.at(TComma) {
        let _ = self.bump()
      }
      continue
    }
    // A field starts with a name. Anything else here — a number (`{ 1 }`),
    // a punctuation token — is not a struct literal at all.
    if self.peek_name() == "" {
      self.err("expected a struct literal field here", open_sp)
      self.skip_rest_of_block()
      return fields
    }
    let (fname, fsp) = self.expect_name("field name")
    // Shorthand: the bare name is both the field and its value, so the read
    // still counts as a use of the name.
    let mut value : @ast.Expr = { span: fsp, kind: @ast.EName(fname), }
    if self.at(TColon) {
      let _ = self.bump()
      value = self.parse_expr()
    }
    fields.push((fname, value))
    if self.at(TComma) {
      let _ = self.bump()
    } else if !self.at(TRBrace) &&
      !self.at(TEOF) &&
      !self.at(TNewline) &&
      !self.at(TSemi) &&
      self.peek_name() == "" {
      // After a field, only a comma, a close brace, a separator, or the next
      // field's name can follow. A plain block holding a call (`{ f(1) }`)
      // lands here on the `(`.
      self.err("expected a struct literal field here", open_sp)
      self.skip_rest_of_block()
      return fields
    }
  }
  self.expect(TRBrace, "'}'")
  fields
}

///|
/// Skip the remainder of a `{ ... }` block whose opening brace is already
/// consumed: read to the token that closes those braces. Used to recover
/// from content inside braces that is not what the surrounding parse
/// expected, so the rest of the file stays readable.
fn Parser::skip_rest_of_block(self : Parser) -> Unit {
  let mut depth = 1
  while !self.at(TEOF) && depth > 0 {
    if self.at(TLBrace) {
      depth += 1
    } else if self.at(TRBrace) {
      depth -= 1
    }
    let _ = self.bump()
  }
}

///|
/// True when the CURRENT token is `t` and the one after it is `u`. Used to
/// recognise `::`, which the lexer emits as two `TColon` tokens rather than one.
fn Parser::at_next(self : Parser, t : @lexer.Tok) -> Bool {
  self.p + 1 < self.toks.length() && self.toks[self.p + 1] == t
}

///|
/// The `TName` text at index `j`, or `""` if that token is not a name. Used to
/// recover an argument's own name after it has already been parsed, which the
/// `x~` shorthand needs: the `~` is only visible once the cursor is past the
/// value, so the name has to be read back out of the token stream.
fn Parser::name_at(self : Parser, j : Int32) -> String {
  if j < 0 || j >= self.toks.length() {
    return ""
  }
  match self.toks[j] {
    TName(n) => n
    _ => ""
  }
}

///|
/// Whether the token `j` positions ahead is `(`. `at(TLParen)` only reads the
/// CURSOR, and the async head of a function type has to be recognised BEFORE it
/// is consumed -- a parameter list that does not begin with `async` must be left
/// exactly as it was, so the test cannot go through a bump and a retreat.
fn Parser::lparen_at(self : Parser, j : Int32) -> Bool {
  if j < 0 || j >= self.toks.length() {
    return false
  }
  match self.toks[j] {
    TLParen => true
    _ => false
  }
}

///|
/// Whether the `{` at the current token opens a STRUCT LITERAL rather than a
/// block — the one brace ambiguity MoonBit carries at statement/tail
/// position (`fn pos(...) -> Position { { line, col, } }`). The grammar is
/// resolved by content: a block's first statement never reaches a bare
/// `NAME :` or ends at a bare `NAME ,`, while a literal's first field is
/// exactly one of those (`name: value` or a shorthand `name,`), possibly one
/// or two newlines deeper when the brace stands alone on its own line.
/// Every other opening — `let`, a keyword, a call, a lone expression —
/// stays a block. Measured: without this the analyzer's OWN core, walk,
/// parser, jsoncli and mermaid_test all died at the closing brace line of
/// their tail literals.
fn Parser::at_struct_literal(self : Parser) -> Bool {
  let mut i = self.p + 1
  while i < self.toks.length() && self.toks[i] is TNewline {
    i += 1
  }
  if i + 1 >= self.toks.length() {
    return false
  }
  match (self.toks[i], self.toks[i + 1]) {
    (TName(_), TColon) | (TName(_), TComma) => true
    // `{ a }` — a literal whose ONLY field is the shorthand, so the brace holds a
    // name and then the close brace and matches none of the other shapes.
    //
    // ADDED BY 0468, and it is not optional. Settled against the toolchain in
    // `_verify/settle_0468_let_block_rhs.ps1`: `fn f() -> S { let a = 1
    // let x = { a } x }` is ACCEPTed as a one-field `S`. Without this arm the
    // discriminator answers false for that brace, the expression path stops
    // treating it as a literal, and a perfectly good struct literal is rewritten
    // as a block -- a regression that would have IMPROVED every corpus count
    // while quietly changing what the analyzer means.
    //
    // It costs nothing, and that is MEASURED rather than argued. The settle carries
    // two independent negatives, and they are the whole safety argument:
    //
    //   neg_bare_name            REJECT [4033]   fn f() -> Int { let x = { b }; x }
    //   ambig_shorthand_one_noann REJECT [4014]  the same with the name `a`
    //
    // The first is the one that matters. `{ b }` with `b` an ordinary local Int is
    // INDISTINGUISHABLE in shape from a one-field struct literal -- there is no
    // annotation, no comma, no colon -- and the toolchain refuses it. So there is no
    // legal unannotated `{ <name> }` BLOCK for this arm to capture: every brace it
    // matches really is a literal. (It was once called `block_bare_name` and sat in the
    // `block_` family, which asserted the opposite; it REJECTed the whole time and
    // nothing asserted it. Re-measured 2026-10-17 and renamed.)
    //
    // A block can never begin with a bare name either -- every statement form starts
    // with a keyword or `(` -- which is why the widened pattern costs nothing a second
    // way.
    (TName(_), TRBrace) => true
    // A QUOTED KEY, `{ "a": 1 }` — 0452's map literal. Added by 0468 AFTER FOUR
    // 0452 TESTS WENT RED, and the reason is worth keeping: a quoted key arrives
    // as `TStr`, not `TName`, so it matches none of the shapes above and every map
    // literal was being routed to the BLOCK path.
    //
    // The arm is unconditional on the SECOND token, and that is not laziness. A
    // statement can never begin with a string literal -- every statement form
    // starts with a keyword or `(` -- so a brace whose first token is a string is
    // a literal whatever follows it. Settled, not assumed: `_verify/settle_0468_
    // let_block_rhs.ps1` measures `{ "a": 1 }` as ACCEPT and `{ "a" }` as REJECT
    // (4014), and BOTH must reach the field grammar -- the second so the missing
    // colon is still reported instead of the file being silently read.
    (TStr(_, _), _) => true
    // `{ ..base, ... }` — the struct update form, whose first field starts with
    // the two TDot tokens of a bare `..` rather than with a name.
    (TDot, TDot) => true
    _ => false
  }
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
  // `parse_or`, NOT `parse_expr`: a comprehension's own `=>` is spelled exactly
  // like a lambda's -- `=` then `>` -- so with the lambda branch in `parse_expr`
  // the SOURCE is read as a bare-parameter lambda (`for x in a => ...`) and the
  // comprehension dies on its own arrow. The three call sites in this function
  // that can be followed by that `=>` -- the source here, the guard below, and
  // the body further down -- are the only places in the grammar where a `=>` is
  // not a lambda's.
  sources.push(self.parse_or())
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
    // `parse_or` again: the guard is also followed by the comprehension's `=>`.
    ignore(self.parse_or())
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
      let (stmts, _) = self.parse_block(false)
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
      // `parse_or`, for the reason the generator's source gives above.
      body = self.parse_or()
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
/// destructuring pattern? Consulted immediately after a pattern has been
/// read, where `for` means the pattern list is over and `in` means a
/// malformed `for k, in` — either way the comma is not another binder.
fn Parser::peek2_is_pattern_name(self : Parser) -> Bool {
  match self.peek2() {
    TName(n) => n != "for" && n != "in"
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
/// Read an anonymous function literal whose `fn` keyword has ALREADY been
/// consumed, from the parameter list through the body.
///
/// Extracted so that `fn(a) { .. }` and `async fn(a) { .. }` cannot drift: the
/// two differ only in the keyword in front of them, and the parameter parser and
/// the block parser are the same two calls either way. A fix that copied the
/// eight lines would be a second place to forget something.
///
/// 0471. THE TAIL BETWEEN `)` AND `{`, which is `-> Type raise E` and was not read
/// here at all. This function went from the parameter list straight to the body, so
/// a literal carrying either clause left the cursor on `->` or on `raise`, and
/// `parse_block` -- looking for `{` -- reported `expected '{'`. A complaint about a
/// brace that was never the problem, which is the same shape as the declared-`fn`
/// `-> T raise E` clause whose absence once cost 24.5% of wzzc-dev/moui's 608 files.
///
/// THE POSITION WAS RULED OUT BY MEASUREMENT, because the obvious reading ("literals
/// only work as call arguments") is wrong in both directions:
///
///     let h = fn(x : Int) { x }          ACCEPTED by the analyzer
///     g(fn(x) { x })                     ACCEPTED by the analyzer
///     let h = fn(x : Int) -> Int { x }   PARSE ERROR
///     g(fn(x) -> Int { x })              PARSE ERROR
///
/// so the variable is the RETURN ANNOTATION and not where the literal sits. Two of
/// the six corpora' first blockers were exactly this: `moonbit_labeler` 0.2.13
/// app_moui/canvas_view.mbt:350 and component_blackbox_test.mbt:662, and five proton
/// files whose literals carry `raise`.
///
/// THE TWO CALLS ARE THE DECLARED-FN PATH'S, not a third reader. `return_annotation`
/// already knows both spellings of a function-type return (settle_0427_retfn) and
/// `parse_raise_effect` already knows `raise E`, `!`, `noraise` and `nocancel`; a
/// literal and a declared function are the same production, and the two places to
/// forget something are exactly what the extraction above was written to remove.
/// Which tails are legal is settled in `_verify/settle_0471_fn_literal_tail.ps1`,
/// 9 rows with two controls.
fn Parser::parse_fn_literal(self : Parser, sp : @core.Span) -> @ast.Expr {
  if self.at(TLBracket) {
    self.skip_indexed()
  }
  let _ = self.parse_param_list()
  // The return annotation is DISCARDED, like the parameters: the subset has no
  // closure node, so the literal yields `EBigInt` and no lens reads either. It is
  // read so that the cursor lands on the body.
  if self.at(TArrow) {
    let _ = self.bump()
    let _ = self.return_annotation()
  }
  self.parse_raise_effect()
  let (_, _) = self.parse_block(false)
  self.note_skip(
    "anonymous function literal is outside the analyzed subset; its parameters were read but the body was not analysed",
    sp,
  )
  { span: sp, kind: @ast.EBigInt, }
}

///|
fn Parser::parse_atom(self : Parser) -> @ast.Expr {
  let sp = self.span()
  // A brace is the one atom whose reading needs a decision BEFORE the cursor moves:
  // `at_struct_literal` reads the token one past it, and `parse_block` wants the
  // brace still unconsumed. So it is settled here, once, and the bump below never
  // sees the ambiguity.
  //
  // Until 0468 every brace reached the atom's TLBrace arm, and a block
  // (`let x = { 1 }`) reached the FIELD grammar, which rejected the content and
  // reported `expected a struct literal field here` at the brace. That was the
  // first blocker on ~10 files across four corpora: five async files share the
  // identical line `let _unused : Unit = {`, plus `let n = {`, `let status = {`,
  // `let fxl : HDecoder = {` and `let y_cover : Double = {`.
  //
  // Settled in `_verify/settle_0468_let_block_rhs.ps1` (scaffolding-verified):
  // `{ 1 }`, `{ let y = 1; y + 1 }`, `{ }` and the nested `{ { 1 } }` are all
  // ACCEPTed by the toolchain, so they are blocks. `{ a }` is ALSO accepted -- as
  // a ONE-FIELD LITERAL -- which is why `at_struct_literal` was widened with
  // (TName, TRBrace) in the same increment. Deciding here without that widening
  // would have been a regression wearing a fix: the corpus counts would have
  // improved while a good struct literal silently became a block.
  if self.at(TLBrace) && !self.at_struct_literal() {
    // `true`, NOT `false`, and that is the whole difference between reading the
    // block's value and reading the file. `parse_block` marks a trailing
    // expression as `STail` only under this flag, and BOTH block lenses key off
    // `STail` -- `Infer::ty_of` returns `tail_ty` and `Interp::eval` assigns `out`
    // from it. With `false` no `EBlock` body ever contained one, so every block
    // typed `TUnknown` and evaluated `AAny`, and those two arms were dead code.
    //
    // The corpus counts could not tell: `walk_stmt` reads an `SExpr` tail exactly
    // as well as an `STail` one, so the tree was walked, the files were parsed and
    // every measured number came out the same. => 判据: a construct can be READ
    // correctly and still carry no value. Asserting the NODE is the only row that
    // sees this, and it is why the tail row is a test and not a comment.
    let (body, _) = self.parse_block(true)
    return { span: sp, kind: @ast.EBlock(body), }
  }
  match self.bump() {
    TInt(i) => { span: sp, kind: @ast.EInt(i), }
    TBigInt => { span: sp, kind: @ast.EBigInt, }
    TFloat(f) => { span: sp, kind: @ast.EFloat(f), }
    TStr(s, names) => { span: sp, kind: @ast.EStr(s, names), }
    TName("true") => { span: sp, kind: @ast.EBool(true), }
    TName("false") => { span: sp, kind: @ast.EBool(false), }
    // `if` in expression position: `let d = if a { x } else { y }`. Measured as
    // the first blocker on 10 of 111 blocked real files.
    //
    // Parsed and consumed rather than added to the Expr enum, on the same
    // grounds as `test` blocks and `const`: the AST has no conditional node,
    // adding one would mean teaching all three lenses about it, and a value we
    // cannot model is exactly the case that should not cascade. The expression
    // yields EBigInt — the opaque placeholder, not a value — and a notice;
    // the rest of the line stays readable. (It used to yield EInt(0), which
    // the type lens read as a real int and turned into an argument-type
    // mismatch on correct code — provenance.mbt:237 was the measured case.)
    //
    // This arm must sit ABOVE the `TName(n)` catch-all below, which matches
    // every TName including "if".
    TName("if") => {
      let _ = self.parse_expr()
      let (_, _) = self.parse_block(false)
      // The chain is LOOPED, not read once: `if a { x } else if b { y }`
      // arrives here as `else` then `if`, and a single `else { block }` read
      // stops at the `if` and cascades.
      let mut going = true
      while going {
        going = false
        self.skip_seps()
        if self.at_name("else") {
          let _ = self.bump()
          if self.at_name("if") {
            let _ = self.bump()
            let _ = self.parse_expr()
            let (_, _) = self.parse_block(false)
            going = true
          } else {
            let (_, _) = self.parse_block(false)
          }
        }
      }
      self.note_skip(
        "if expression is outside the analyzed subset; it was read but not analysed",
        sp,
      )
      { span: sp, kind: @ast.EBigInt, }
    }
    TName("for") | TName("while") =>
      // A loop in EXPRESSION position, which is legal MoonBit:
      //     let kind : MessageKind = for frame = self.recv_frame_header() { .. }
      // at `moonbitlang/async 0.22.4 src/websocket/conn.mbt:486`.
      //
      // These two had NO arm here, so `for` fell through to the generic TName arm
      // and became `EName("for")` -- and a keyword is not a binding, so the
      // structural walk reported `undefined name 'for'` as an ACTIONABLE finding on
      // code `moon check` compiles. `while` did the same. `match` and `if` in the
      // identical position already report honestly, which is the control for this
      // row: the defect is the two missing arms, not expression position itself.
      //
      // The construct is consumed by the SAME routines statement position uses, so
      // the token stream cannot drift between the two positions, and the body is
      // skipped whole -- the subset has no loop-valued expression. See
      // `parse_loop_as_expr`.
      self.parse_loop_as_expr(sp)
    TName("match") => {
      // A `match` expression, statement or value position alike. The subset
      // has no pattern matching and no node for the arms, so the arms are
      // skipped whole — balanced braces, whatever they hold.
      //
      // 0469: THIS ARM NOW YIELDS AN OPAQUE NODE. Until this increment it yielded
      // the SCRUTINEE, and the scrutinee is NOT the match's value. So
      //     let vok = match bd { .. }
      // bound `vok` to `bd` itself: same VALUE, same TYPE, same reads. Measured on
      // moonbit_image 0.3.7 `png.mbt:980`, which reported
      //     operand of '!' must be bool, got 'int'
      // for `!vok` because `vok` was an Int where a Bool was required. That was
      // this increment's `actionable` on moonbit_image, and it was NOT caused by
      // 0468 -- 0468 only made the file readable.
      //
      // THE DEFECT AND WHY IT SURVIVED, kept rather than deleted. The comment here
      // used to say the scrutinee "is an ordinary expression" and that yielding it
      // "drops nothing". That claim is FALSE, and it is the reason the defect lived:
      // it conflated "the expression I had to parse to keep the token stream in
      // step" with "the value this expression produces". For every other construct
      // in this file those are the same expression. For `match` they are not --
      // the value comes from the ARMS, which are exactly what gets skipped.
      //
      // Parsing the scrutinee is REQUIRED; yielding it is not. The sibling
      // `TName("fn")` arm below has precisely the same shape -- it reads a whole
      // body and drops it -- and said so honestly all along, yielding an opaque
      // node. `match` was the inconsistent one, and this arm is now consistent
      // with it.
      //
      // THE PRICE, STATED RATHER THAN DISCOVERED LATER: reads inside the scrutinee
      // leave the lens. `match f(x) { .. }` no longer counts `f` and `x` as reads,
      // so a binding used ONLY as a match subject can now report as unused. That
      // is the same trade the anonymous-`fn` arm has always made, and it is the
      // right one: the alternative is not "fewer reads", it is "the wrong type",
      // and a wrong TYPE manufactures findings on correct code while a missing READ
      // only risks missing some. The corpora were re-measured after this change
      // rather than after it was argued for -- see `_verify/release.ps1`.
      //
      // The SUBJECT may start on the NEXT LINE. `match` alone at the end of a
      // line, with the scrutinee and its arms following, is the shape wzzc-dev/
      // moui 0.1.12 writes throughout -- `views/form/form_field.mbt:42`,
      // `runtime/scroll_to_key.mbt:30`, `runtime/runtime_events.mbt:358` -- and
      // it was the largest single blocker this increment closed.
      //
      // That sentence used to read "the largest single blocker left at 0.4.30".
      // Measured wrong: `moon.mod` is `0.4.29` now and `git log ed410cd..HEAD --
      // moon.mod` is EMPTY, so the version never changed between the commit that
      // wrote the pin and HEAD. 0.4.30 never shipped; the pin pointed at a
      // version that does not exist.
      //
      // Settled with the toolchain, not inferred (`_verify/grammar_probe.ps1`,
      // one form per package with a broken canary alongside):
      //
      //   match\n    <subject> {   -- 0 errors, in BOTH statement and `let` position
      //   match\n    <subject>\n  { -- REJECTED: "missing `{` at the end of this line"
      //
      // So the newline before the SUBJECT is allowed, and the `{` must still sit
      // on the subject's last line -- which is what the existing `skip_braces`
      // already assumes. Implementing the rejected spelling as well would accept
      // something `moon check` refuses, and the `_` that second form fails on is
      // the whole point of recording both.
      // 0469. The subject is PARSED so the cursor lands after it -- that is what keeps
      // the token stream in step, so what FOLLOWS the match is analysed -- and it is
      // CARRIED rather than discarded, because it is real code whose reads are real.
      // What is NOT carried is the match's value: that comes from the arms, and the arms
      // are skipped. `EMatch(subject)` says exactly that much and nothing more.
      //
      // THE COMMENT SITS ABOVE BOTH LINES ON PURPOSE. `skip_seps` immediately before
      // `parse_expr` is what lets the subject start on the next line, and M1 of
      // `mutate_0433.ps1` removes that call as a two-line anchor. A comment wedged
      // between them breaks the adjacency without changing a single behaviour.
      self.skip_seps()
      let subject = self.parse_expr()
      self.skip_braces()
      self.note_skip(
        "match expression is outside the analyzed subset; it was read but not analysed",
        sp,
      )
      { span: sp, kind: @ast.EMatch(subject), }
    }
    TName("fn") =>
      // An anonymous function literal in expression position:
      // `arr.iter(fn(x) { x + 1 })`. The subset has no closure node, so the
      // literal is read PAST — generic brackets, parameters via the shared
      // parameter parser, body via a block parse — and then discarded,
      // yielding an opaque node. Reading the body and dropping it is not a
      // waste: it keeps the token stream in step, so what FOLLOWS the
      // literal is analysed. Statement-level named functions take the
      // SLocalFunc path in `parse_block` and never reach this arm.
      self.parse_fn_literal(sp)
    TName("async") =>
      // `async fn(a, b) { .. }` — an anonymous ASYNC function literal.
      //
      // This arm existed for four of the nine files moui 0.1.12 still cannot
      // finish reading, all four stopped at the same construct and all four
      // reported it as `expected ')'`:
      //
      //     launch_async=Some(async fn(request, frame_interval_ms) { .. }),
      //
      // `expected ')'` is the complaint AFTER the argument of `Some(` failed
      // to parse; it is about the argument, not about the parenthesis. There
      // was no arm for `async` here, so it was read as an ordinary name and
      // the argument never started. The short-lambda named argument on the
      // line before parses fine, which is why the file is `PARTIAL` at line
      // 23-24 rather than unparsed at zero.
      //
      // Settled against the toolchain, not inferred
      // (`_verify/settle_0453_async_fn_expr.ps1`, 6/6 with a positive control):
      //
      //     Some(fn(a) { .. })          ACCEPT   <- already parsed, same shape
      //     Some(async fn(a) { .. })    ACCEPT
      //     the corpus declaration      ACCEPT   <- short lambda + this, together
      //     ignore(async)               REJECT(3002) "unexpected token `)`,
      //                                                 you may expect `fn`"
      //     async work()                REJECT(3002)
      //
      // The last two are why this arm is written as an `if` on `fn` rather than
      // as "an `async` starts a function". In the toolchain `async` is bound to
      // `fn` and to nothing else -- there is no `async call` production and no
      // value named `async` -- so consuming it wherever it appears would be
      // untested rather than correct. The guard is what turns that measurement
      // into a production.
      //
      // IT HAS THREE CASES, NOT TWO, and the third is this increment's second
      // regression -- caught by a corpus, not by the gate.
      //
      //   async fn(a) { .. }      a LITERAL. Read it here.
      //   async fn log(a) { .. }  a nested DECLARATION. A function literal is
      //                            ANONYMOUS, so a NAME after `fn` is always a
      //                            declaration -- and `parse_block`'s own
      //                            discriminator (`at_name("fn") && name_at(p+1)
      //                            != ""`, the 0450 fix) is false when the cursor
      //                            is on `async`, so the declaration falls
      //                            THROUGH to this arm. It must be handed back
      //                            UNCHANGED, as the name `async`, so that the next
      //                            statement still begins at `fn` and
      //                            `parse_block` declares the function.
      //   anything else           illegal; the toolchain says "you may expect
      //                            `fn`". Read past with a notice.
      //
      // The middle case is why this is not `&& name_at(...) == ""`. With the
      // `fn`-only guard, `async fn log(s) { .. }` was consumed as an anonymous
      // literal and the nested function was never declared; with the compound
      // guard it was handed to an `else` that announced
      // `async without a following fn` -- a false notice about legal code.
      // `moonbitlang/async@0.22.4` is written with that shape inside test bodies
      // (`src/all_any_test.mbt:138`, `src/fs/watch_test.mbt:50` and others), and
      // all five sites fired it.
      if self.at_name("fn") {
        if self.name_at(self.p + 1) == "" {
          let _ = self.bump()
          self.parse_fn_literal(sp)
        } else {
          // A DECLARATION, not a literal. The keyword is handed back UNCHANGED --
          // there is no bump in this branch, before or after this increment -- so
          // the next statement still begins at `fn` and `parse_block` declares the
          // function. Nothing about the cursor moves.
          //
          // READ PAST, NOT READ AS A NAME. This yielded `EName("async")`, which is
          // precisely what the branch below refuses to invent: "yielding `async`
          // as a readable binding would let the structural lens file
          // `undefined name 'async'` against a program that never meant a name."
          // The toolchain agrees -- `async` cannot be bound at all, so the finding
          // was refuted by construction rather than merely unverified. Both facts
          // are in `_verify/settle_0457_nested_async_fn.ps1`, 5/5.
          //
          // IT WAS INVISIBLE FOR AS LONG AS IT WAS because every file carrying this
          // shape was ALSO blocked by something earlier: `watch_test.mbt` died on
          // `is @async.TimeoutError` at line 389, which 0456 fixed. The file then
          // parsed whole and three sites surfaced at once, taking async's
          // actionable count from 0 to 3. A false positive that no corpus could
          // reach is not a false positive that does not exist.
          self.note_skip(
            "the `async` of an `async fn` declaration is outside the analyzed subset; it was read past",
            sp,
          )
          { span: sp, kind: @ast.EBigInt, }
        }
      } else {
        // Unreachable for code `moon check` accepts. Reached only by input the
        // toolchain refuses, and the honest response to that is to read past
        // it with a notice rather than invent a name: yielding `async` as a
        // readable binding would let the structural lens file
        // `undefined name 'async'` against a program that never meant a name.
        self.note_skip(
          "async without a following `fn` is outside the analyzed subset; it was read past",
          sp,
        )
        { span: sp, kind: @ast.EBigInt, }
      }
    TName("try") => {
      // A `try` expression. The subset has no error-handling node: the body
      // block and every `catch`/`finally` arm are skipped WHOLE, not read —
      // a handler body would introduce pattern bindings the lenses cannot
      // attribute, and reading it without those bindings manufactures
      // undefined names. Consuming the group keeps the token stream in step
      // for whatever follows it.
      if self.at(TQuestion) || self.at(TBang) {
        // `try? e` / `try! e` carry no handler block: the operand is an
        // ordinary expression whose reads are real, and only the wrapper is
        // skipped.
        let _ = self.bump()
        let _ = self.parse_expr()
      } else {
        if self.at(TLBrace) {
          self.skip_braces()
        } else {
          // A `try` without its body block — input valid MoonBit never
          // produces, so the defensive scan only runs on text `moon check`
          // itself would reject.
          self.skip_to_catch()
        }
        while self.at_name("catch") {
          let _ = self.bump()
          self.skip_pattern()
          self.skip_braces()
        }
        // `noraise { ... }` after a statement-level `try`'s catch. This is the
        // SHAPE THE CORPUS ACTUALLY WRITES -- proton `facade_identity.mbt:95`
        // and `:134`, `protocol_wbtest.mbt:5`, async `network.mbt:68` -- and it
        // is a different path from the postfix production in
        // `parse_postfix_from`. Both are real: the settle probe accepted
        // `expr catch { .. } noraise { .. }` with no `try` keyword, and proton
        // writes the `try` form.
        //
        // WITHOUT THIS LOOP the token survived the `catch` loop and was resolved
        // as an ordinary identifier: `undefined name 'noraise'`, four sites, the
        // largest single named finding left. That is a FALSE POSITIVE -- it is
        // MoonBit, and the compiler accepts all four programs.
        //
        // IT IS SKIPPED, NOT PARSED, and that is deliberate and consistent with
        // the lines above rather than a half-measure. This whole branch is the
        // un-analysed `try`: the body was skipped by `skip_to_catch` and
        // `note_skip` below already put a hole in the frame for the enclosing
        // function. Reading the `noraise` arms here would find reads in a block
        // whose sibling catch block is deliberately unread, which is the
        // arrangement that produces new findings rather than removing any. The
        // claim this line makes is narrow and true: the token is part of the
        // grammar, and it is not a name.
        while self.at_name("noraise") {
          let _ = self.bump()
          self.skip_braces()
        }
        while self.at_name("finally") {
          let _ = self.bump()
          self.skip_braces()
        }
      }
      self.note_skip(
        "try expression is outside the analyzed subset; it was read but not analysed",
        sp,
      )
      { span: sp, kind: @ast.EBigInt, }
    }
    TName(n) => { span: sp, kind: @ast.EName(n), }
    TLParen =>
      // `()` is the unit value and `(a, b)` a tuple; a parenthesized
      // GROUPING `(e)` is not a tuple and never becomes one — it yields `e`
      // itself, so precedence and spans stay honest. The comma is what makes
      // a tuple: one element with a trailing comma is still a tuple.
      if self.at(TRParen) {
        let _ = self.bump()
        { span: sp, kind: @ast.ETuple([]), }
      } else {
        let e = self.parse_expr()
        if self.at(TComma) {
          let elems : Array[@ast.Expr] = [e]
          while self.at(TComma) {
            let _ = self.bump()
            if self.at(TRParen) {
              break
            }
            elems.push(self.parse_expr())
          }
          self.expect(TRParen, "')'")
          { span: sp, kind: @ast.ETuple(elems), }
        } else {
          // `(e : T)` -- an ASCRIPTION inside the parentheses. The grouping
          // branch parsed `e` and then demanded `)`, which is where every one of
          // the six blocked files died: `expected ')'` on a line whose `:` is a
          // type marker, not a typo.
          //
          // ONLY THE GROUPING FORM IS HANDLED, and the two shapes it is easy to
          // mistake for it are both REJECTED by the toolchain. Settled one form
          // per package with a broken canary beside each
          // (`_verify/probe_sweep_0434.ps1`, canary firing):
          //   `('0' : Int)`   MOON-OK   <- the only legal form, the one here
          //   `let y = 1 : Int`   MOON-BAD  (no parentheses: rejected)
          //   `(1 : Int, 2)`      MOON-BAD  (ascription on a tuple element)
          // So there is deliberately NO branch for the bare form and NO branch
          // in the tuple branch above. Both would be unmeasured code guarding
          // syntax that does not exist.
          //
          // The type is read and DISCARDED, the same trade as a `raise` effect
          // and a parameter default: the AST has no ascription node, and adding
          // one would ripple through walk / types / infer / interp for a check
          // none of them performs. Consuming it is what makes the file readable.
          //
          // NO SUBSET-EXCLUSION NOTICE, and that is a settled decision rather
          // than an omission. `..<=` gets one for the same-looking reason -- a
          // value is read and dropped -- because inclusive end genuinely CHANGES
          // what the code does, n iterations instead of n+1. An ascription does
          // not. Settled in the same probe run:
          //
          //   `(s : Int)` where `s` is a String   MOON-BAD
          //
          // so `e : T` is an ASSERTION of a type the compiler has already
          // checked, not a coercion: it is a no-op at runtime. Discarding the
          // type therefore loses no behaviour, and announcing a subset
          // exclusion would be reporting a loss that does not happen.
          //
          // (The SELF column reads SELF-FAIL on all four probe rows because that
          // run used the wasm built before this edit. The MOON column is what
          // the run settled, and MOON does not depend on this change.)
          if self.at(TColon) {
            let _ = self.bump()
            let _ = self.type_annotation()
          }
          self.expect(TRParen, "')'")
          e
        }
      }
    TLBrace => {
      // Reached only when `at_struct_literal` said yes -- the guard above returned
      // for every other brace. A struct literal without the `Type::` prefix, in a
      // context where the type is already known. The field grammar is the same as
      // the prefixed form; the path is "" because there is none.
      let fields = self.parse_struct_fields(sp)
      { span: sp, kind: @ast.EStruct("", fields), }
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
      // Named, not bare. See `tok_desc` for why this one message was hiding
      // 90% of the corpus's coverage blockers behind a single anonymous row.
      self.err("unexpected token \{tok_desc(other)}", sp)
      ignore(other)
      { span: sp, kind: @ast.EInt(0), }
    }
  }
}

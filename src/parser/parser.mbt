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
  mut p : Int
  reports : Array[@report.Report]
  /// Messages of the deliberate subset exclusions among `reports`
  skips : Array[String]
  /// Earliest line at which the source genuinely failed to read; 0 if it read
  /// all of it. Deliberate exclusions do not move it.
  mut first_error : Int
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
    } else if kw == "struct" ||
      kw == "enum" ||
      kw == "trait" ||
      kw == "impl" ||
      kw == "derive" ||
      kw == "extend" ||
      kw == "test" {
      p.skip_decl_braced(kw, sp)
    } else if kw == "type" || kw == "const" {
      p.skip_decl_line(kw, sp)
    } else if kw == "suberror" {
      // A suberror has TWO shapes: `suberror Timeout of String` is one line,
      // while `pub suberror DecodeError { UnsupportedFormat(String) ... }` is
      // braced. Sending the braced shape to the LINE skipper stopped the skip
      // at the newline and left `{ ... }` to be parsed as an expression block,
      // so every payload type inside it was reported as an undefined name —
      // `String` four times over in riantr/moonbit_image 0.3.7's `types.mbt`.
      //
      // Same split `struct` / `enum` already get, decided by what actually
      // follows the keyword rather than by the keyword's name.
      if p.next_is_lbrace() {
        p.skip_decl_braced(kw, sp)
      } else {
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
/// what keeps the question answerable — an unbraced header (`suberror Timeout
/// of String`) must NOT be answered by a brace belonging to some later
/// declaration, and a header is never longer than a handful of tokens.
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
    if what == "enum" {
      self.harvest_ctors(open_p, self.p)
    }
  }
  self.skip(what, true, sp)
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
fn Parser::harvest_ctors(self : Parser, from : Int, to : Int) -> Unit {
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
fn Parser::after_path_marker(self : Parser, i : Int) -> Bool {
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
          }
        }
      TLParen => if enum_body && depth == 1 { paren += 1 }
      TRParen => if enum_body && depth == 1 && paren > 0 { paren -= 1 }
      TName(n) =>
        if depth == 0 && n == "using" {
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
        } else if depth == 0 && (declares_value(n) || declares_type(n)) {
          if n == "enum" {
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
  i : Int,
  tab : @core.IfaceSymTab,
) -> Int {
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
  i : Int,
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
fn ends_variant(toks : Array[@lexer.Tok], i : Int) -> Bool {
  if i >= toks.length() {
    return false
  }
  match toks[i] {
    TLParen | TComma | TRBrace | TNewline | TSemi => true
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
fn declared_name_at(toks : Array[@lexer.Tok], i : Int) -> String? {
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
  let mut out = "("
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
  // `(A) -> B` in return position is a FUNCTION TYPE, not a one-element tuple:
  // `fn f() -> (Int) -> String` returns a function. The tuple arm below accepts
  // any `(`, so this shape needs to be told apart first.
  //
  // The test is "the matching `)` is followed by `->`", found by SCANNING to the
  // matching close and counting nesting. The first attempt looked only at the
  // three tokens `(`, `)`, `->`, which is the shape of `() -> T` and nothing
  // else: `(Int) -> String` has `Int` between the brackets, so it missed and
  // the fixture failed with 4 parse errors. Real annotations have a parameter.
  let fn_type = if self.at(TLParen) {
    let mut depth = 0
    let mut j = self.p
    let mut is_fn = false
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
        TEOF => break
        _ => ()
      }
      j += 1
    }
    is_fn
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
fn Parser::parse_fn(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  let _ = self.bump() // fn
  let (name, params, retann) = self.parse_fn_signature()
  let (body, endsp) = self.parse_block()
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
  (full, params, retann)
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
      ignore(self.parse_expr())
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
  // `= "exit"` — the raw symbol in the target language. Nothing to model.
  if self.at(TAssign) {
    let _ = self.bump()
    if self.at_str() {
      let _ = self.bump()
    }
  }
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
fn Parser::parse_block(self : Parser) -> (Array[@ast.Stmt], @core.Span) {
  self.expect(TLBrace, "'{'")
  let body : Array[@ast.Stmt] = []
  while !self.at(TRBrace) && !self.at(TEOF) {
    self.skip_seps()
    if self.at(TRBrace) {
      break
    }
    if self.at_name("fn") {
      // A named function INSIDE a block: `fn add(t : Ty) { ... }`. Ordinary
      // MoonBit — this analyzer's own types.mbt defines one — so it is parsed
      // as its own statement kind instead of being rejected. Rejection used
      // to cost the whole file: the error moved first_error, and everything
      // after the local function went unread.
      let fsp = self.span()
      let _ = self.bump()
      let (fname, fparams, fret) = self.parse_fn_signature()
      let (fbody, fendsp) = self.parse_block()
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
    body.push(self.parse_stmt())
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
fn declared_name_after_kw(toks : Array[@lexer.Tok], kw_i : Int) -> String? {
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
    let (body, _) = self.parse_block()
    return { span: sp, kind: @ast.SWhile(cond, body), }
  }
  if self.at_name("for") {
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
    let (body, _) = self.parse_block()
    if names.length() == 1 {
      return { span: sp, kind: @ast.SFor(names[0], vsp, seq, body), }
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
    return { span: sp, kind: @ast.SFor("$pair", vsp, seq, body2), }
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
    let (body, _) = self.parse_block()
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
fn Parser::parse_c_for(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  let _ = self.bump() // for
  let stmts : Array[@ast.Stmt] = []
  // init may be empty: `for ; i < n; i = i + 1`
  if !self.at(TSemi) {
    stmts.push(self.parse_stmt())
  }
  self.expect(TSemi, "';'")
  // An absent condition is a constant-true loop, not a missing one.
  let mut cond : @ast.Expr = { span: sp, kind: @ast.EBool(true), }
  if !self.at(TSemi) {
    cond = self.parse_expr()
  }
  self.expect(TSemi, "';'")
  let update = if self.at(TLBrace) { None } else { Some(self.parse_stmt()) }
  let (body, _) = self.parse_block()
  let loop_body : Array[@ast.Stmt] = []
  for st in body {
    loop_body.push(st)
  }
  match update {
    Some(u) => loop_body.push(u)
    None => ()
  }
  stmts.push({ span: sp, kind: @ast.SWhile(cond, loop_body), })
  { span: sp, kind: @ast.SBlock(stmts), }
}

///|
fn Parser::parse_if(self : Parser) -> @ast.Stmt {
  let sp = self.span()
  let _ = self.bump() // if
  let cond = self.parse_expr()
  let (then, _) = self.parse_block()
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
        let (b2, _) = self.parse_block()
        elseifs.push({ cond: c2, body: b2, })
        going = true
      } else {
        let (eb, _) = self.parse_block()
        els = Some(eb)
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
/// The `is` test tier: `e is Pattern`. It sits between comparison and the
/// bitwise tiers — tighter than `<`, looser than `| ^ & << >>`, which sit
/// just above `+` — because
/// every measured use feeds a boolean operator or a negation
/// (`p.peek() is TName(tag) && tag.has_prefix("@")`, `!(m is TInt)`), and
/// no corpus line puts a comparison on an `is` result. The pattern is
/// reduced to the binding name it introduces ("" when it has none); the
/// TEXT is consumed and discarded, so no lens ever parses strings (MoonBit
/// string indexing is by byte, and pattern text would have to be re-lexed
/// to be sliced safely).
fn Parser::parse_is(self : Parser) -> @ast.Expr {
  let mut l = self.parse_bitor()
  while self.at_name("is") {
    let _ = self.bump()
    let binding = self.parse_is_pattern()
    l = { span: l.span, kind: @ast.EIs(l, binding), }
  }
  l
}

///|
/// The pattern of an `is` test, reduced to its BINDING name: the head is
/// one constructor name (`TName`, `Some`, `ABool`), an optional payload
/// follows in one paren group, and the first non-`_` name inside that
/// group is the binding — `TName(tag)` -> "tag", `TEOF` -> "",
/// `Some(_)` -> "". A name immediately followed by `(` inside the payload
/// is a nested constructor, not a binding (`Some(Some(x))` binds nothing
/// here and reports honestly at the `x` use). Unmodelled shapes stay in
/// step as far as the balanced paren and report at the first token they
/// cannot place.
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
fn Parser::parse_is_pattern(self : Parser) -> String {
  if self.peek_name() != "" {
    let _ = self.bump()
  } else {
    return ""
  }
  let mut binding = ""
  if self.at(TLParen) {
    let _ = self.bump()
    let mut depth = 1
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
      } else if depth == 1 &&
        binding == "" &&
        self.peek_name() != "" &&
        self.peek_name() != "_" &&
        !@lexer.is_moonbit_keyword(self.peek_name()) &&
        !self.at_next(TLParen) {
        let (n, _) = self.expect_name("pattern binding")
        binding = n
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
  while self.at(TPlus) || self.at(TMinus) || self.at(TRange) {
    if self.at(TRange) {
      // `a..<b` — the exclusive range, one token since the lexer learned it.
      // The right side is read at UNARY precedence on purpose: ranges occur
      // almost only in `for i in a..<b` heads, where both this reading and
      // the strict reading parse and walk identically, and `1..<n*2` reading
      // as `(1..<n)*2` costs nothing — the walk visits every operand either
      // way. A whole precedence tier for one operator would be the dearer
      // mistake.
      let _ = self.bump()
      let r = self.parse_unary()
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
      // value: const_eval must not fold a bound it never read. An open
      // START (`[:n]`) is not in the corpus and reports honestly. A list
      // literal cannot misfire here: its commas make `at(TColon)` false,
      // and colons inside string elements are inside TStr tokens.
      let first = self.parse_expr()
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
      let args = self.parse_call_args()
      self.expect(TRParen, "')'")
      match e.kind {
        @ast.EName(n) => e = { span: csp, kind: @ast.ECall(n, args), }
        // A method call. `receiver.name` was an EField up to this point; the
        // `(` is what makes it a call, and only now are the arguments known.
        @ast.EField(base, m) =>
          e = { span: csp, kind: @ast.EMethodCall(base, m, args), }
        _ => self.err("only named functions and methods can be called", csp)
      }
      continue
    }
    // `expr catch { pattern => handler }` — MoonBit's postfix error
    // handling on a call. The `catch { ... }` group is consumed and
    // discarded: the handler's body (patterns, `return`s) lives inside the
    // braces and says nothing the lenses read, while the CALL — whose
    // arguments ARE read — must survive, or every line shaped like
    // `@process.collect_output(cmd) catch { _ => return "" }` (the measured
    // Class E deaths at provenance.mbt:416 and jsoncli/main.mbt:252) dies
    // at the `catch` keyword instead of yielding its call. `catch` is a
    // keyword in MoonBit, so at_name here can never capture an identifier.
    if self.at_name("catch") {
      let _ = self.bump()
      self.skip_braces()
      continue
    }
    break
  }
  e
}

///|
/// The argument list of a call, up to but NOT including the closing `)`.
/// Shared by `f(args)` and `receiver.f(args)` so the two forms cannot drift.
fn Parser::parse_call_args(self : Parser) -> Array[@ast.Expr] {
  let args : Array[@ast.Expr] = []
  while !self.at(TRParen) && !self.at(TEOF) {
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
    // `f(x~)` — the shorthand for `f(x=x)`, settled by `moon check` (0.4.18):
    // it passes the local `x` under its own label. The label is dropped for
    // the same reason `name = value` above drops it — the call lens reads the
    // value, not the label — so an arity check counts this exactly as it
    // counts `x` positionally. Only reached after a real argument, so the
    // short-lambda branch above (which `continue`s) is unaffected.
    if self.at(TTilde) {
      let _ = self.bump()
    }
    if self.at(TComma) {
      let _ = self.bump()
    } else {
      break
    }
  }
  args
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
      let (stmts, _) = self.parse_block()
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
fn Parser::parse_atom(self : Parser) -> @ast.Expr {
  let sp = self.span()
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
      let (_, _) = self.parse_block()
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
            let (_, _) = self.parse_block()
            going = true
          } else {
            let (_, _) = self.parse_block()
          }
        }
      }
      self.note_skip(
        "if expression is outside the analyzed subset; it was read but not analysed",
        sp,
      )
      { span: sp, kind: @ast.EBigInt, }
    }
    TName("match") => {
      // A `match` expression, statement or value position alike. The subset
      // has no pattern matching and no node for the arms, so the arms are
      // skipped whole — balanced braces, whatever they hold. The SCRUTINEE
      // is read and yielded: it is an ordinary expression, and dropping it
      // would drop its reads — the same trade the comprehension's `sources`
      // made.
      let scrutinee = self.parse_expr()
      self.skip_braces()
      self.note_skip(
        "match expression is outside the analyzed subset; it was read but not analysed",
        sp,
      )
      scrutinee
    }
    TName("fn") => {
      // An anonymous function literal in expression position:
      // `arr.iter(fn(x) { x + 1 })`. The subset has no closure node, so the
      // literal is read PAST — generic brackets, parameters via the shared
      // parameter parser, body via a block parse — and then discarded,
      // yielding an opaque node. Reading the body and dropping it is not a
      // waste: it keeps the token stream in step, so what FOLLOWS the
      // literal is analysed. Statement-level named functions take the
      // SLocalFunc path in `parse_block` and never reach this arm.
      if self.at(TLBracket) {
        self.skip_indexed()
      }
      let _ = self.parse_param_list()
      let (_, _) = self.parse_block()
      self.note_skip(
        "anonymous function literal is outside the analyzed subset; its parameters were read but the body was not analysed",
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
          self.expect(TRParen, "')'")
          e
        }
      }
    TLBrace => {
      // A bare `{ ... }` in expression position — a struct literal without
      // the `Type::` prefix, in a context where the type is already known.
      // The field grammar is the same as the prefixed form; the path is ""
      // because there is none. This arm is also what a plain block in
      // expression position (`let x = { 1 }`) reaches: the field grammar
      // rejects the content and reports at the brace, which is the boundary
      // the scanner trusts.
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
      self.err("unexpected token", sp)
      ignore(other)
      { span: sp, kind: @ast.EInt(0), }
    }
  }
}

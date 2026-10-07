// Static analysis for the MoonBit toolchain's other file kinds — the
// taxonomy is recorded in the module root EXTENSIONS.md with
// docs.moonbitlang.com/en/latest as the final authority:
//   .mbt.md  literate MoonBit: extract moonbit fences, three-inspect each
//            block with REAL file line numbers (pad lines before each block)
//   .mbti    interface files: parse signature lines, audit malformed lines,
//            duplicate declarations, unknown type references
//   .mbtp    proof files: logic-side structure audit — string constants in
//            bodies (E4207-analog), banned `!`/`↔` forms, cross-package
//            calls, lemmas without proof_ensure
// Every rejection is FParse (error): these checks are frontends for other
// file kinds — a rejected shape is a parse-class defect. The core model
// (Family table, proofs) is untouched.

///|
/// Strip `\r` so CRLF inputs lex like LF (the lexer is newline-sensitive).
fn normalize(src : String) -> String {
  let buf = StringBuilder()
  for c in src {
    if c != '\r' {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// split into lines, reified to String (views do not carry our helpers)
fn split_lines(src : String) -> Array[String] {
  let out : Array[String] = []
  for v in src.split("\n") {
    let buf = StringBuilder()
    for c in v {
      buf.write_char(c)
    }
    out.push(buf.to_string())
  }
  out
}

///|
/// trim spaces and tabs from both ends
fn trim_sp(s : String) -> String {
  let chars = s.to_array()
  let mut a = 0
  let mut b = chars.length()
  while a < b && (chars[a] == ' ' || chars[a] == '\t') {
    a += 1
  }
  while b > a && (chars[b - 1] == ' ' || chars[b - 1] == '\t') {
    b -= 1
  }
  let buf = StringBuilder()
  for i in a..<b {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// StringView twin of trim_sp: reify, then trim both ends (interior
/// whitespace is significant — "fn f" must keep its space)
fn trim_sp_view(v : StringView) -> String {
  let buf = StringBuilder()
  for c in v {
    buf.write_char(c)
  }
  trim_sp(buf.to_string())
}

///|
/// plain StringView reification
fn view_str(v : StringView) -> String {
  let buf = StringBuilder()
  for c in v {
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// the part of s after the first n chars, reified ("" when short)
fn after_n(s : String, n : Int) -> String {
  if s.length() <= n {
    ""
  } else {
    let buf = StringBuilder()
    for c in s[n:] {
      buf.write_char(c)
    }
    buf.to_string()
  }
}

///|
fn count_char(s : String, c : Char) -> Int {
  let mut n = 0
  for x in s {
    if x == c {
      n += 1
    }
  }
  n
}

///|
/// '!' as an operator: not part of '!=' (which is legal in logic)
fn contains_bang(code : String) -> Bool {
  let chars = code.to_array()
  for i, c in chars {
    if c == '!' {
      let prev = if i > 0 { Some(chars[i - 1]) } else { None }
      let next = if i + 1 < chars.length() { Some(chars[i + 1]) } else { None }
      if !(prev == Some('=')) && !(next == Some('=')) {
        return true
      }
    }
  }
  false
}

///|
/// How a fenced block is meant to be treated, from its info string. The fence
/// language is the authority here, not the extension. Measured against the
/// toolchain itself (moon 0.1.20260920) by putting an unbound call in every
/// candidate fence and seeing which ones `moon check` complained about:
///
///   ```mbt check      COMPILED     ```mbt nocheck     skipped
///   ```mbt test       COMPILED     ```moonbit nocheck skipped
///   ```moonbit check  COMPILED     ```mbt             skipped
///   ```moonbit test   COMPILED     ```moonbit         skipped
///                                      (no info string) skipped
///                                      ```mbtcheck      skipped  (no space)
///                                      ```mbt Check     skipped  (2nd word is case-sensitive)
///
/// So a bare `mbt` is a DISPLAY fence, exactly like a bare `moonbit` — a second
/// word of `check` or `test` is what makes it live code. Extra words after it
/// are ignored and extra whitespace is fine.
///
/// Earlier versions of this file claimed the toolchain compiled bare `mbt`. It
/// does not; that claim came from the doc wording, not from a measurement, and
/// analysing those blocks produced findings on code the toolchain never builds.
pub(all) enum FenceMode {
  /// ` ```mbt check ` / ` ```mbt test ` (and the `moonbit` spellings) — live
  /// code: compiled, and reachable as a test
  FTest
  /// ` ```mbt nocheck ` / ` ```moonbit nocheck ` — shown only
  FNoCheck
  /// ` ```mbt ` / ` ```moonbit ` — a display fence for MoonBit source
  FDisplay
} derive(Eq, Debug)

///|
/// Classify a fence info string. Returns None for a non-MoonBit fence.
///
/// The two distinctions that matter, both documented:
///   - `nocheck` opts the block OUT of compilation and testing;
///   - a bare `moonbit` fence is display-only, while `mbt` (with or without
///     `check`) is compiled.
pub fn fence_mode(info : String) -> FenceMode? {
  let words = trim_sp_view(trim_sp_view(after_n(info, 3).view()).view())
  // The language word must be a WHOLE word. `mbtcheck` is one token, not `mbt`
  // plus `check`, and the toolchain does not compile it — a bare `has_prefix`
  // would have called it FTest. Whitespace between the words is free-form:
  // `mbt check` and `mbt  check` both compile.
  let rest = if words == "moonbit" {
    ""
  } else if words == "mbt" {
    ""
  } else if words.has_prefix("moonbit ") {
    // "moonbit" is 7 characters, so the separator puts the rest at index 8
    trim_sp_view(after_n(words, 8).view())
  } else if words.has_prefix("mbt ") {
    trim_sp_view(after_n(words, 4).view())
  } else {
    return None
  }
  if rest == "" {
    // A bare `mbt` is a DISPLAY fence, same as a bare `moonbit`: measured
    // above, neither is compiled. Only a `check` / `test` second word makes the
    // block live code.
    return Some(FDisplay)
  }
  let head = decl_name(rest)
  if head == "nocheck" {
    return Some(FNoCheck)
  }
  if head == "check" || head == "test" {
    return Some(FTest)
  }
  None
}

///|
/// Extract the moonbit fenced code blocks that are actually compiled, i.e.
/// ```mbt check and ```mbt test (and the `moonbit` spellings): returns
/// (block_source_with_line_padding, start_line) pairs. `mbt nocheck`, bare
/// `mbt` and bare `moonbit` blocks are skipped — measured, see `FenceMode`.
/// Other fences are prose and skipped too.
pub fn moonbit_fences(md : String) -> Array[(String, Int)] {
  let src = normalize(md)
  let blocks : Array[(String, Int)] = []
  let lines = split_lines(src)
  let mut i = 0
  let n = lines.length()
  while i < n {
    let line = lines[i]
    if line.has_prefix("```") {
      match fence_mode(line) {
        Some(FTest) => ()
        Some(_) | None => {
          i += 1
          continue
        }
      }
    }
    if line.has_prefix("```") {
      let start_line = i + 2
      let body = StringBuilder()
      i += 1
      while i < n && !lines[i].has_prefix("```") {
        body.write_string(lines[i])
        body.write_char('\n')
        i += 1
      }
      // pad so spans land on the .md file's real line numbers
      let pad = StringBuilder()
      for _k in 1..<start_line {
        pad.write_char('\n')
      }
      blocks.push((pad.to_string() + body.to_string(), start_line))
    }
    i += 1
  }
  blocks
}

///|
/// `(live, display)` counts of the MoonBit fences in `md`: live is what
/// `moonbit_fences` would analyse, display is what it must skip.
///
/// Counting from the document exists so a demo or a report cannot silently
/// drift away from the fence rules — the "2 compiled fences" string in
/// `src/cli` stayed wrong for a release precisely because it was hard-coded
/// while the classification underneath it changed.
pub fn fence_census(md : String) -> (Int, Int) {
  let src = normalize(md)
  let lines = split_lines(src)
  let mut live = 0
  let mut display = 0
  let mut i = 0
  let n = lines.length()
  while i < n {
    if lines[i].has_prefix("```") {
      match fence_mode(lines[i]) {
        Some(FTest) => live += 1
        Some(_) => display += 1
        None => ()
      }
      // step over the body: a ``` inside a fence is not a fence
      i += 1
      while i < n && !lines[i].has_prefix("```") {
        i += 1
      }
    }
    i += 1
  }
  (live, display)
}

///|
/// The first word of each line of a block, when it is a whole identifier.
fn line_heads(block : String) -> Array[String] {
  let out : Array[String] = []
  for raw in split_lines(block) {
    let t = trim_sp(raw)
    if t == "" || t.has_prefix("//") {
      continue
    }
    let name = decl_name(t)
    if name != "" {
      out.push(name)
    }
  }
  out
}

///|
/// The first word in `block` that the MoonBit subset deliberately leaves out
/// (see EXTENSIONS.md), or "" when the block is analyzable.
///
/// A compiled block that leaves the subset is reported ONCE. Handing it to the
/// parser instead reports the keyword as an undefined *variable* — the subset
/// lexer has no keyword table — and then a cascade of "unexpected token" behind
/// it. Measured over the 12 real .mbt.md documents in this workspace, that
/// cascade was 2335 findings, 1505 of them ParseError.
fn subset_exclusion(block : String) -> String {
  let excluded = [
    "async", "extern", "match", "pub", "priv", "mut", "struct", "enum", "trait",
    "derive", "suberror", "impl", "test", "throw",
  ]
  for h in line_heads(block) {
    if excluded.contains(h) {
      return h
    }
  }
  ""
}

///|
/// Analyze a `.mbt.md` literate document: each moonbit fence is an
/// independent snippet (literate blocks share nothing by design), run through
/// the full three-inspection pipeline; findings carry REAL line numbers.
pub fn literate(md : String, file : String) -> @pipeline.PipelineResult {
  let all : Array[@report.Report] = []
  let sigs : Array[String] = []
  let imports : Array[@ast.ImportSpec] = []
  let mut n1 = 0
  let mut n2 = 0
  let mut n3 = 0
  let mut n_parse = 0
  let mut n_subset = 0
  let reasons : Map[String, Int] = Map([])
  let mut reason = ""
  let mut reason_n = 0
  for pair in moonbit_fences(md) {
    let (block, start) = pair
    // outside the subset: one finding at the block's first line, not a cascade
    let excluded = subset_exclusion(block)
    if excluded != "" {
      all.push(@report.Report::{
        family: @core.FParse,
        lenses: [@core.LStructural],
        message: "block starts with '\{excluded}', outside the analyzer's MoonBit subset; skipped whole",
        span: @core.span_at(start, 1, excluded.length()),
        vst: [],
      })
      n1 += 1
      continue
    }
    let r = @pipeline.run(block, file)
    for rep in r.reports {
      all.push(rep)
    }
    for s in r.sigs {
      sigs.push(s)
    }
    for i in r.imports {
      imports.push(i)
    }
    n1 += r.n_structural
    n2 += r.n_type
    n3 += r.n_behavior
    // Aggregated across every fence in the document, so the literate file's
    // verdict means the same thing a `.mbt` file's does: zero means every
    // compiled fence was understood, and the reason names the most common
    // blocker across all of them.
    n_parse += r.n_parse
    n_subset += r.n_subset
    if r.n_parse > 0 {
      let c = match reasons.get(r.parse_reason) {
        Some(n) => n + r.n_parse
        None => r.n_parse
      }
      reasons.set(r.parse_reason, c)
      if c > reason_n {
        reason_n = c
        reason = r.parse_reason
      }
    }
  }
  @pipeline.PipelineResult::{
    reports: all,
    sigs,
    n_structural: n1,
    n_type: n2,
    n_behavior: n3,
    imports,
    n_parse,
    parse_reason: reason,
    n_subset,
  }
}

///|
/// identifier characters (letters, digits, underscore)
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// the first n chars of s ("" when n <= 0)
fn take_n(s : String, n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    let chars = s.to_array()
    let m = if n >= chars.length() { chars.length() } else { n }
    let buf = StringBuilder()
    let mut i = 0
    while i < m {
      buf.write_char(chars[i])
      i += 1
    }
    buf.to_string()
  }
}

///|
/// Split at the LAST occurrence of sep, returning (before, after).
fn rsplit_at(s : String, sep : String) -> (String, String)? {
  let chars = s.to_array()
  let sp = sep.to_array()
  let mut found = -1
  let mut i = 0
  while i + sp.length() <= chars.length() {
    let mut j = 0
    let mut ok = true
    while j < sp.length() {
      if chars[i + j] != sp[j] {
        ok = false
        break
      }
      j += 1
    }
    if ok {
      found = i
      i += sp.length()
    } else {
      i += 1
    }
  }
  if found < 0 {
    None
  } else {
    Some((take_n(s, found), after_n(s, found + sp.length())))
  }
}

///|
/// the identifier starting at index `from` ("" when there is none)
fn ident_from(chars : Array[Char], from : Int) -> String {
  let buf = StringBuilder()
  let mut i = from
  while i < chars.length() && is_ident_char(chars[i]) {
    buf.write_char(chars[i])
    i += 1
  }
  buf.to_string()
}

///|
/// the leading identifier of s — a declared name ("" when there is none)
fn decl_name(s : String) -> String {
  ident_from(s.to_array(), 0)
}

///|
/// Words that can appear inside a type expression without naming a type.
/// `Self` is the receiver, `raise`/`async`/`fn`/`for`/`derive` are modifiers,
/// and the visibility words are stripped but can reappear.
fn is_type_noise(w : String) -> Bool {
  is_error_modifier(w) ||
  w == "Self" ||
  w == "raise" ||
  w == "async" ||
  w == "fn" ||
  w == "for" ||
  w == "derive" ||
  w == "pub" ||
  w == "priv" ||
  w == "extern" ||
  w == "const" ||
  w == "type" ||
  w == "impl"
}

///|
/// Split on commas that sit outside (), [] and {} — so `Map[String, Int]`
/// stays one segment while `(Int, Int)` and `[A, B]` split correctly.
fn split_top_commas(s : String) -> Array[String] {
  let out : Array[String] = []
  let buf = StringBuilder()
  let mut depth = 0
  for c in s {
    if c == '(' || c == '[' || c == '{' {
      depth += 1
      buf.write_char(c)
    } else if c == ')' || c == ']' || c == '}' {
      depth -= 1
      buf.write_char(c)
    } else if c == ',' && depth == 0 {
      out.push(trim_sp(buf.to_string()))
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  out.push(trim_sp(buf.to_string()))
  out
}

///|
/// Split on the first ':' outside (), [] and {}. Returns (label, type);
/// label is "" for a positional segment. This is what keeps a labeled
/// parameter's own name out of the referenced-type set — `offset? : Int`
/// references Int, never `offset?`.
fn label_type(s : String) -> (String, String) {
  let chars = s.to_array()
  let mut depth = 0
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '(' || c == '[' || c == '{' {
      depth += 1
    } else if c == ')' || c == ']' || c == '}' {
      depth -= 1
    } else if c == ':' && depth == 0 {
      return (take_n(s, i), trim_sp(after_n(s, i + 1)))
    }
    i += 1
  }
  ("", trim_sp(s))
}

///|
/// Strip one layer of matching brackets, if present.
fn strip_outer(s : String, open : Char, close : Char) -> String {
  if s.length() >= 2 &&
    s.has_prefix(open.to_string()) &&
    s.has_suffix(close.to_string()) {
    let chars = s.to_array()
    let buf = StringBuilder()
    let mut i = 1
    while i < chars.length() - 1 {
      buf.write_char(chars[i])
      i += 1
    }
    buf.to_string()
  } else {
    s
  }
}

///|
/// Given the text starting just AFTER an opening '(', return the text up to
/// its matching ')' plus the remainder after it. Nested parens are respected,
/// so `Self, async (&Writer) -> Unit` stays whole.
fn paren_parts(tail : String) -> (String, String) {
  let chars = tail.to_array()
  let mut depth = 0
  let mut close = chars.length()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '(' {
      depth += 1
    } else if c == ')' {
      if depth == 0 {
        close = i
        break
      }
      depth -= 1
    }
    i += 1
  }
  (take_n(tail, close), after_n(tail, close + 1))
}

///|
/// If s starts with '[', split it into the bracketed list and the remainder.
fn leading_bracket(s : String) -> (String, String) {
  if !s.has_prefix("[") {
    return ("", s)
  }
  let chars = s.to_array()
  let buf = StringBuilder()
  let mut depth = 0
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    buf.write_char(c)
    if c == '[' {
      depth += 1
    } else if c == ']' {
      depth -= 1
      if depth == 0 {
        return (buf.to_string(), trim_sp(after_n(s, i + 1)))
      }
    }
    i += 1
  }
  ("", s)
}

///|
/// Bound type-parameter names from a `[A, B : Bound, C]` list.
fn bound_params(list : String) -> Array[String] {
  let out : Array[String] = []
  if list == "" {
    return out
  }
  for seg in split_top_commas(strip_outer(list, '[', ']')) {
    let (label, ty) = label_type(seg)
    // `W` is bare, `W : Writer` carries a bound — the name is the label when
    // there is one and the whole segment otherwise
    let n = decl_name(if label == "" { ty } else { label })
    if n != "" && !out.contains(n) {
      out.push(n)
    }
  }
  out
}

///|
/// Strip a visibility prefix: `pub(all) `, `pub(open) `, `pub(in "x") `, `pub `.
fn strip_visibility(t : String) -> String {
  if !t.has_prefix("pub") {
    return t
  }
  let after = trim_sp_view(after_n(t, 3).view())
  if !after.has_prefix("(") {
    return after
  }
  let chars = after.to_array()
  let mut depth = 0
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '(' {
      depth += 1
    } else if chars[i] == ')' {
      depth -= 1
      if depth == 0 {
        i += 1
        break
      }
    }
    i += 1
  }
  trim_sp(after_n(after, i))
}

///|
/// Strip leading `async ` / `extern ` / `extern "C" ` modifiers before `fn`.
fn strip_fn_modifiers(t : String) -> String {
  let mut s = trim_sp(t)
  let mut going = true
  while going {
    going = false
    if s.has_prefix("async ") {
      s = trim_sp(after_n(s, 6))
      going = true
    } else if s.has_prefix("extern ") {
      // `extern "C" fn` / `extern(js) fn` — drop the ABI token too
      let rest = trim_sp(after_n(s, 7))
      let chars = rest.to_array()
      if chars.length() > 0 && chars[0] == '"' {
        let mut i = 0
        while i < chars.length() && chars[i] != '"' {
          i += 1
        }
        if i + 1 < chars.length() && chars[i + 1] == '"' {
          s = trim_sp(after_n(rest, i + 2))
        } else {
          s = rest
        }
        going = true
      } else if chars.length() > 0 && chars[0] == '(' {
        let mut i = 0
        let mut depth = 0
        while i < chars.length() {
          if chars[i] == '(' {
            depth += 1
          } else if chars[i] == ')' {
            depth -= 1
            if depth == 0 {
              i += 1
              break
            }
          }
          i += 1
        }
        s = trim_sp(after_n(rest, i))
        going = true
      }
    }
  }
  s
}

///|
/// True for the trailing error-type modifiers of a return clause. They follow
/// the type and modify it rather than name it, so they never enter the
/// referenced-type set. `raise`/`noraise` and `cancel`/`nocancel` are the two
/// pairs, and the declaration side is `ErrorType` in the official
/// `moonbitlang/parser@0.4.3` mbti_ast.
fn is_error_modifier(w : String) -> Bool {
  w == "raise" || w == "noraise" || w == "cancel" || w == "nocancel"
}

///|
/// Base type names a type expression references. `@pkg.Name` is recorded whole
/// (external by shape) and `A::B` as written. Everything that is not an
/// identifier — brackets, `?`, `&`, `->`, `,` — contributes nothing, which is
/// why `String?`, `(Int, Int)` and `async (&Writer) -> Unit` need no cleanup.
fn type_names(s : String) -> Array[String] {
  let out : Array[String] = []
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '@' {
      let buf = StringBuilder()
      buf.write_char('@')
      i += 1
      while i < chars.length() &&
            (is_ident_char(chars[i]) || chars[i] == '.' || chars[i] == '/') {
        buf.write_char(chars[i])
        i += 1
      }
      let q = buf.to_string()
      if q.length() > 1 {
        out.push(q)
      }
      continue
    }
    if is_digit(c) {
      // a numeric literal: 10, 0x0020, 1_000. Consuming letters along with the
      // digits is what keeps the hex tail of `0x0020` from reading as a type.
      i += 1
      while i < chars.length() && is_ident_char(chars[i]) {
        i += 1
      }
      continue
    }
    if is_ident_start(c) {
      let buf = StringBuilder()
      while i < chars.length() && is_ident_char(chars[i]) {
        buf.write_char(chars[i])
        i += 1
      }
      let mut w = buf.to_string()
      if i + 2 < chars.length() &&
        chars[i] == ':' &&
        chars[i + 1] == ':' &&
        is_ident_start(chars[i + 2]) {
        let sub = ident_from(chars, i + 2)
        w = w + "::" + sub
        i += 2 + sub.length()
      }
      if w != "" && !is_type_noise(w) && !out.contains(w) {
        out.push(w)
      }
      continue
    }
    i += 1
  }
  out
}

///|
/// The shapes `moon info` actually emits for a value signature. Returns
/// (name, referenced types, bound type params) or None when the line is not
/// a signature at all:
///   pub fn f(Int) -> Int
///   pub async fn[W : Writer] T::flush(Self[W]) -> Unit
///   pub extern "C" fn put(Int) -> Unit
///   pub fn &Data::text(Self) -> String raise
///   pub const HEADER_SIZE : Int = 10
fn iface_signature(line : String) -> (String, Array[String], Array[String])? {
  let t = trim_sp(line)
  if t == "" || t.has_prefix("//") || t.has_prefix("#") {
    return None
  }
  let body = strip_visibility(t)
  // const value signature: `const NAME : Type = value`
  if body.has_prefix("const ") {
    let rest = trim_sp(after_n(body, 6))
    let (label, ty) = label_type(rest)
    let name = decl_name(label)
    if name == "" {
      return None
    }
    return Some((name, type_names(ty), []))
  }
  // `pub let NAME : T` — a value declaration (no body), emitted by moon info
  // for package-level constants and re-exports
  if body.has_prefix("let ") {
    let rest = trim_sp(after_n(body, 4))
    let (label, ty) = label_type(rest)
    let name = decl_name(label)
    if name == "" {
      return None
    }
    return Some((name, type_names(ty), []))
  }
  let rest = strip_fn_modifiers(body)
  if !(rest.has_prefix("fn ") || rest.has_prefix("fn[")) {
    return None
  }
  let after_fn = trim_sp(after_n(rest, 2))
  let (plist, after_params) = leading_bracket(after_fn)
  let bound = bound_params(plist)
  // the declared name: `Type::method`, `&Trait::method` or a plain function
  let (raw_name, tail) = match after_params.split_once("(") {
    Some((n, t2)) => (trim_sp(view_str(n)), view_str(t2))
    None => return None
  }
  let clean_name = if raw_name.has_prefix("&") {
    trim_sp(after_n(raw_name, 1))
  } else {
    raw_name
  }
  if clean_name == "" {
    return None
  }
  // parameters: strip the wrapping parens, then keep only each segment's
  // type half (a labeled parameter's name is not a type)
  let (params, ret) = paren_parts(tail)
  let types : Array[String] = []
  for seg in split_top_commas(params) {
    if seg == "" {
      continue
    }
    let (_label, ty) = label_type(seg)
    for n in type_names(ty) {
      if !types.contains(n) {
        types.push(n)
      }
    }
  }
  // return type: whatever follows the closing paren. A trailing `?`, a
  // `(A, B)` tuple and the error-type modifiers need no cleanup —
  // type_names ignores non-ident characters and the modifiers are noise.
  for n in type_names(ret) {
    if !types.contains(n) {
      types.push(n)
    }
  }
  Some((clean_name, types, bound))
}

///|
/// The type references on ONE line of a type-declaration body.
///
/// Two shapes occur, and they COLLIDE: `Constr(a, label~ : T)` is both a
/// constructor and a `label : Type` pair. So the constructor shape is tested
/// FIRST — a top-level `(` wins — and the contents are split on commas before
/// each segment is read, which is what keeps a labeled parameter's NAME out of
/// the type set. Splitting the line at its first ':' instead reports
/// `context` in `OSError(Int, context~ : String)` as a type; that version was
/// written, measured (7 false positives over 89 real interfaces) and reverted.
///
/// Returns [] for a derive list (`derive(Eq, @debug.Debug)` names TRAITS),
/// comments, attributes and the closing brace.
fn body_type_refs(line : String) -> Array[String] {
  let t = trim_sp(line)
  if t == "" || t.has_prefix("//") || t.has_prefix("#") || t.has_prefix("}") {
    return []
  }
  let out : Array[String] = []
  match top_level_paren(t) {
    Some((name, inner)) => {
      let head = decl_name(name)
      if head == "" || is_type_noise(head) {
        return []
      }
      for seg in split_top_commas(inner) {
        // per segment a labeled param is `label~ : Type`; keep the type half
        let (_label, ty) = label_type(seg)
        for n in type_names(ty) {
          if !out.contains(n) {
            out.push(n)
          }
        }
      }
    }
    None => {
      // struct field shape: `name : Type`
      let (label, ty) = label_type(t)
      if label == "" || label.has_prefix("}") {
        return []
      }
      for n in type_names(ty) {
        if !out.contains(n) {
          out.push(n)
        }
      }
    }
  }
  out
}

///|
/// Split at the first `(` at nesting depth 0, returning the text before it and
/// the text inside its matching `)`. Depth-aware so `FixedDelay(Int)` does not
/// split inside the parens and a `(` belonging to an earlier line cannot be
/// mistaken for the constructor's. Returns None when there is no such `(` or it
/// is unclosed.
fn top_level_paren(t : String) -> (String, String)? {
  let chars = t.to_array()
  let mut depth = 0
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '[' || c == '{' {
      depth += 1
    } else if c == ']' || c == '}' {
      depth -= 1
    } else if c == '(' && depth == 0 {
      let mut d = 0
      let mut j = i
      while j < chars.length() {
        if chars[j] == '(' {
          d += 1
        } else if chars[j] == ')' {
          d -= 1
          if d == 0 {
            break
          }
        }
        j += 1
      }
      if d != 0 {
        return None
      }
      let buf = StringBuilder()
      for k in (i + 1)..<j {
        buf.write_char(chars[k])
      }
      return Some((take_n(t, i), buf.to_string()))
    }
    i += 1
  }
  None
}

///|
/// Analyze a `.mbti` interface file. The line grammar is the one `moon info`
/// emits, so nothing it generates is reported as malformed:
///   comments, `#attribute` lines, `package`, `import { }` blocks,
///   `enum`/`struct`/`trait`/`type`/`suberror` declarations (bodies skipped),
///   `impl ... for T`, `const`, and `fn` signatures with visibility,
///   `async`/`extern` modifiers, type parameters and labeled parameters.
/// Findings: malformed lines, duplicate value signatures, and type names
/// referenced but neither declared in the file, builtin, a bound type
/// parameter, nor external (`@pkg.` references are external by shape).
pub fn iface(src : String, file : String) -> Array[@report.Report] {
  let _ = file
  let text = normalize(src)
  let reports : Array[@report.Report] = []
  let declared : Array[String] = []
  let type_params : Array[String] = []
  let sig_names : Array[String] = []
  let referenced : Array[(String, Int, Int)] = []
  let lines = split_lines(text)
  let mut decl_depth = 0
  let mut import_depth = 0
  for i, line in lines {
    let lineno = i + 1
    let t = trim_sp(line)
    if t == "" || t.has_prefix("//") {
      continue
    }
    // inside an `import { ... }` block
    if import_depth > 0 {
      import_depth += count_char(t, '{') - count_char(t, '}')
      continue
    }
    // inside a type declaration body: field and constructor TYPES are resolved
    // too. derive(...) lists are exempt — they name traits, not types.
    if decl_depth > 0 {
      for n in body_type_refs(t) {
        referenced.push((n, lineno, 1))
      }
      decl_depth += count_char(t, '{') - count_char(t, '}')
      continue
    }
    // attribute lines: #deprecated, #alias(new, ...), #callsite(...)
    if t.has_prefix("#") {
      continue
    }
    if t.has_prefix("package ") {
      continue
    }
    if t.has_prefix("import ") || t == "import" || t == "import{" {
      import_depth = count_char(t, '{') - count_char(t, '}')
      continue
    }
    let body = strip_visibility(t)
    // `pub using @pkg {type T as U}` — a re-export line. Everything on it is
    // either `@pkg` (external) or a name declared here.
    if body.has_prefix("using ") {
      let after = trim_sp(after_n(body, 6))
      match rsplit_at(after, "}") {
        Some((head, _)) =>
          for seg in split_top_commas(strip_outer(trim_sp(head), '{', '}')) {
            let body_seg = if seg.has_prefix("type ") {
              trim_sp(after_n(seg, 5))
            } else {
              seg
            }
            match rsplit_at(body_seg, " as ") {
              Some((_, renamed)) => {
                let a = decl_name(renamed)
                if a != "" && !declared.contains(a) {
                  declared.push(a)
                }
              }
              None => {
                let d = decl_name(body_seg)
                if d != "" && !declared.contains(d) {
                  declared.push(d)
                }
              }
            }
          }
        None => ()
      }
      continue
    }
    // `impl[Params] Trait for Type` — only the implemented type is checked;
    // the trait name needs the whole trait set, which we do not model.
    if body.has_prefix("impl ") || body.has_prefix("impl[") {
      let (plist, after_params) = leading_bracket(body)
      for p in bound_params(plist) {
        if !type_params.contains(p) {
          type_params.push(p)
        }
      }
      match rsplit_at(after_params, " for ") {
        Some((_, target)) =>
          for n in type_names(target) {
            referenced.push((n, lineno, 1))
          }
        None => ()
      }
      continue
    }
    // declarations: enum / struct / trait / type / suberror
    let kw = ["enum ", "struct ", "trait ", "type ", "suberror "]
    let mut matched = ""
    for k in kw {
      if body.has_prefix(k) {
        matched = k
      }
    }
    if matched != "" {
      let rest = trim_sp(after_n(body, matched.length()))
      let (plist, after_params) = leading_bracket(rest)
      for p in bound_params(plist) {
        if !type_params.contains(p) {
          type_params.push(p)
        }
      }
      let name = decl_name(after_params)
      if name != "" && !declared.contains(name) {
        declared.push(name)
      }
      // an alias `type Fd = Int` also references its right-hand side
      if matched == "type " {
        match after_params.split_once("=") {
          Some((_, rhs)) =>
            for n in type_names(view_str(rhs)) {
              referenced.push((n, lineno, 1))
            }
          None => ()
        }
      }
      let mut d = count_char(body, '{') - count_char(body, '}')
      if d < 0 {
        d = 0
      }
      decl_depth = d
      continue
    }
    match iface_signature(t) {
      Some((name, types, bound)) => {
        for p in bound {
          if !type_params.contains(p) {
            type_params.push(p)
          }
        }
        // receiver-qualified methods declare their receiver type
        match name.split_once("::") {
          Some((recv, _)) => {
            let recv = view_str(recv)
            if recv != "" && !declared.contains(recv) {
              declared.push(recv)
            }
          }
          None => ()
        }
        if sig_names.contains(name) {
          reports.push(@report.Report::{
            family: @core.FParse,
            lenses: [@core.LStructural],
            message: "duplicate signature '\{name}' (redeclaration)",
            span: @core.span_at(lineno, 1, t.length()),
            vst: [],
          })
        } else {
          sig_names.push(name)
        }
        for ty in types {
          referenced.push((ty, lineno, 1))
        }
      }
      None =>
        // a non-signature, non-declaration line is malformed interface text
        reports.push(@report.Report::{
          family: @core.FParse,
          lenses: [@core.LStructural],
          message: "malformed interface line (expected a signature or type declaration)",
          span: @core.span_at(lineno, 1, t.length()),
          vst: [],
        })
    }
  }
  let builtin = [
    "Int", "Int64", "UInt", "UInt64", "Double", "Bool", "Char", "String", "StringView",
    "Bytes", "BytesView", "Byte", "Unit", "Nil", "Array", "FixedArray", "ArrayView",
    "ReadOnlyArray", "Option", "Result", "Map", "Set", "StringBuilder", "Error",
    "UInt16", "Int16", "UInt8", "Float", "SourceLoc", "Json",
  ]
  for r in referenced {
    let (ty, lineno, col) = r
    // `@pkg.Name` is external by shape; so is anything path-qualified
    if ty.has_prefix("@") || ty.contains("::") {
      continue
    }
    if declared.contains(ty) || builtin.contains(ty) || type_params.contains(ty) {
      continue
    }
    reports.push(@report.Report::{
      family: @core.FParse,
      lenses: [@core.LStructural],
      message: "unknown type '\{ty}' in interface signature (not declared here, not builtin)",
      span: @core.span_at(lineno, col, ty.length()),
      vst: [],
    })
  }
  reports
}

///|
/// Render a bare report list without signatures (iface/proof audits share
/// this shape: each finding on its own line, then a one-line summary).
pub fn render_reports(reports : Array[@report.Report]) -> String {
  let buf = StringBuilder()
  for rep in reports {
    buf.write_string(rep.render())
  }
  buf.write_string("\nSummary: \{reports.length()} finding(s)\n")
  buf.to_string()
}

///|
/// Analyze a `.mbtp` proof file: the logic side rejects —
///   string constants in predicate/lemma bodies (E4207-analog: only Int/Bool
///   constants lower),
///   `!` and `↔` forms (write `== false` and one-directional `→`),
///   cross-package `@pkg.` calls (proof code stays in-package),
///   lemmas without a proof_ensure property.
pub fn proof(src : String, file : String) -> Array[@report.Report] {
  let _ = file
  let text = normalize(src)
  let reports : Array[@report.Report] = []
  let lines = split_lines(text)
  let mut in_logic = false
  let mut in_lemma = false
  let mut has_ensure = false
  let mut brace_depth = 0
  for i, line in lines {
    let lineno = i + 1
    let t = trim_sp(line)
    let code = if t.has_prefix("//") { "" } else { t }
    // track declaration state
    if code.has_prefix("predicate ") || code.has_prefix("fn ") {
      in_logic = true
      in_lemma = false
      has_ensure = false
      brace_depth = 0
    }
    if code.has_prefix("lemma ") {
      in_logic = true
      in_lemma = true
      has_ensure = false
      brace_depth = 0
    }
    if code != "" {
      brace_depth += count_char(code, '{') - count_char(code, '}')
      if in_logic {
        if code.contains("\"") {
          reports.push(@report.Report::{
            family: @core.FParse,
            lenses: [@core.LStructural],
            message: "string constant in a logic body (only Int/Bool constants lower)",
            span: @core.span_at(lineno, 1, t.length()),
            vst: [],
          })
        }
        if code.contains("↔") {
          reports.push(@report.Report::{
            family: @core.FParse,
            lenses: [@core.LStructural],
            message: "banned form '↔' in logic (write one-directional '→' or an '== ... ==' equation)",
            span: @core.span_at(lineno, 1, t.length()),
            vst: [],
          })
        }
        if contains_bang(code) {
          reports.push(@report.Report::{
            family: @core.FParse,
            lenses: [@core.LStructural],
            message: "banned form '!' in logic (write '== false')",
            span: @core.span_at(lineno, 1, t.length()),
            vst: [],
          })
        }
        // cross-package calls: words starting with '@'
        let words = StringBuilder()
        let candidates : Array[String] = []
        for ch in code {
          if ch == ' ' ||
            ch == '(' ||
            ch == ')' ||
            ch == '{' ||
            ch == '}' ||
            ch == '[' ||
            ch == ']' ||
            ch == ',' {
            let w = words.to_string()
            if w != "" {
              candidates.push(w)
            }
            words.reset()
          } else {
            words.write_char(ch)
          }
        }
        let last = words.to_string()
        if last != "" {
          candidates.push(last)
        }
        for s in candidates {
          if s.has_prefix("@") && s.length() > 1 {
            reports.push(@report.Report::{
              family: @core.FParse,
              lenses: [@core.LStructural],
              message: "cross-package call '\{s}' in a proof file (proof code stays in-package)",
              span: @core.span_at(lineno, 1, t.length()),
              vst: [],
            })
          }
        }
        if in_lemma && code.contains("proof_ensure") {
          has_ensure = true
        }
      }
    }
    // declaration ends when braces close back to zero
    if in_logic && brace_depth <= 0 && code.contains("}") {
      if in_lemma && !has_ensure {
        reports.push(@report.Report::{
          family: @core.FParse,
          lenses: [@core.LStructural],
          message: "lemma without proof_ensure (nothing to discharge)",
          span: @core.span_at(lineno, 1, t.length()),
          vst: [],
        })
      }
      in_logic = false
      in_lemma = false
    }
  }
  reports
}

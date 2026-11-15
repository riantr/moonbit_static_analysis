// 0592: THE DATALOG READER -- the deck's rule syntax, read.
//
// WHY A READER AT ALL. The deck's argument (p.8-16) is that the SAME analysis has
// an imperative form and a declarative one, and that the declarative one is
// "Readable (logic-based specification)" (p.16). A Datalog rule that is a
// function call is not a readable specification -- it is the imperative form
// wearing a hat. So the rules of this deck are read from TEXT, and the text is
// the deck's own.
//
// THE SYNTAX, AS THE DECK WRITES IT:
//
//     fact      P(a, b).
//     rule      H <- B1, B2, ...., Bn.
//     or        H <- B1; B2.            (p.44-45: `;` has a LOWER precedence
//                                         than `,`, so `H <- A, (B;C)` is
//                                         "A and (B or C)")
//     negation  H <- B1, !B2, ....      (p.46)
//     arithmetic H <- B1, x >= 18.      (p.29, p.32)
//
// AND ONE SHORTHAND THE DECK USES AND NOBODY ELSE DOES: p.15 writes a rule with
// SEVERAL HEADS and ONE body --
//
//     VarPointsTo(this, o),
//     Reachable(m),
//     CallGraph(l, m) <-
//     VCall(l, x, k),
//     VarPointsTo(x, o),
//     Dispatch(o, k, m),
//     ThisVar(m, this).
//
// -- which is three rules with the same body, written on one slide. This reader
// EXPANDS it into three rules, because that is what it means, and the engine
// has one head per rule.
//
// AND THE READING OF A TERM IS CONTEXTUAL, and it has to be: the deck's facts
// are `New(b, o1)` (p.65) and its rules are `VarPointsTo(x, o) <- New(x, o).`
// (p.70), and in BOTH the object name `o1` and the variable `x` are bare
// identifiers. A FACT's terms are all values; a RULE's bare terms are all
// variables; and a quoted string or a number is a value in either place.

///|
/// A token of the reader.
///
/// `#derive(Eq)` BECAUSE THE READER COMPARES TOKENS, and a comparison needs
/// equality: an enum with a payload does not get it by default.
#derive(Eq)
pub(all) enum DTok {
  TIdent(String)
  TNum(String)
  TStr(String)
  TLParen
  TRParen
  TComma
  TDot
  TLArrow
  TSemi
  TBang
  TOp(String)
}

///|
/// The result of reading a program.
pub(all) struct DParse {
  ok : Bool
  error : String
  program : DProgram
}

///|
/// Is this character the start of an identifier?
fn d_is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// Is this character inside an identifier?
fn d_is_ident_char(c : Char) -> Bool {
  d_is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
/// Is this character a digit?
fn d_is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// The tokens of a text, and the position the reader stopped at.
fn d_tokenize(text : String) -> (Array[DTok], Int32) {
  let out : Array[DTok] = []
  let cs = text.to_array()
  let mut i = 0
  while i < cs.length() {
    let c = cs[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i = i + 1
      continue
    }
    // A COMMENT runs to the end of the line. The deck's slides carry them and a
    // program that cannot hold one cannot hold the deck's own rules.
    if c == '/' && i + 1 < cs.length() && cs[i + 1] == '/' {
      while i < cs.length() && cs[i] != '\n' {
        i = i + 1
      }
      continue
    }
    if d_is_ident_start(c) {
      let mut j = i
      while j < cs.length() && d_is_ident_char(cs[j]) {
        j = j + 1
      }
      out.push(TIdent(text[i:j].to_owned()))
      i = j
      continue
    }
    if d_is_digit(c) {
      let mut j = i
      while j < cs.length() && d_is_digit(cs[j]) {
        j = j + 1
      }
      out.push(TNum(text[i:j].to_owned()))
      i = j
      continue
    }
    if c == '"' {
      let mut j = i + 1
      let mut s = ""
      let mut closed = false
      while j < cs.length() {
        if cs[j] == '\\' && j + 1 < cs.length() {
          s = s + cs[j + 1].to_string()
          j = j + 2
          continue
        }
        if cs[j] == '"' {
          closed = true
          j = j + 1
          break
        }
        s = s + cs[j].to_string()
        j = j + 1
      }
      if closed == false {
        return (out, i)
      }
      out.push(TStr(s))
      i = j
      continue
    }
    if c == '(' {
      out.push(TLParen)
      i = i + 1
      continue
    }
    if c == ')' {
      out.push(TRParen)
      i = i + 1
      continue
    }
    if c == ',' {
      out.push(TComma)
      i = i + 1
      continue
    }
    if c == '.' {
      out.push(TDot)
      i = i + 1
      continue
    }
    if c == ';' {
      out.push(TSemi)
      i = i + 1
      continue
    }
    if c == '!' {
      // `!=` is an operator; a lone `!` negates.
      if i + 1 < cs.length() && cs[i + 1] == '=' {
        out.push(TOp("!="))
        i = i + 2
        continue
      }
      out.push(TBang)
      i = i + 1
      continue
    }
    if c == '<' {
      if i + 1 < cs.length() && cs[i + 1] == '=' {
        out.push(TOp("<="))
        i = i + 2
        continue
      }
      if i + 1 < cs.length() && cs[i + 1] == '-' {
        out.push(TLArrow)
        i = i + 2
        continue
      }
      out.push(TOp("<"))
      i = i + 1
      continue
    }
    if c == '>' {
      if i + 1 < cs.length() && cs[i + 1] == '=' {
        out.push(TOp(">="))
        i = i + 2
        continue
      }
      out.push(TOp(">"))
      i = i + 1
      continue
    }
    if c == '=' {
      out.push(TOp("="))
      i = i + 1
      continue
    }
    return (out, i)
  }
  (out, cs.length())
}

///|
/// The reader's state: the tokens, the position, and whether the term being read
/// is a variable (a RULE's bare term) or a value (a FACT's, and anything
/// quoted or numeric).
pub(all) struct DReader {
  toks : Array[DTok]
  mut pos : Int32
  mut in_rule : Bool
}

///|
/// The token at the reader's position.
fn d_peek(r : DReader) -> DTok? {
  if r.pos < r.toks.length() {
    Some(r.toks[r.pos])
  } else {
    None
  }
}

///|
/// Take the token at the reader's position.
fn d_take(r : DReader) -> DTok? {
  if r.pos < r.toks.length() {
    let t = r.toks[r.pos]
    r.pos = r.pos + 1
    Some(t)
  } else {
    None
  }
}

///|
/// Is the next token this one?
fn d_is(r : DReader, t : DTok) -> Bool {
  match d_peek(r) {
    Some(x) => x == t
    None => false
  }
}

///|
/// The text of a token, for an error message.
fn d_tok_text(t : DTok) -> String {
  match t {
    TIdent(s) => s
    TNum(s) => s
    TStr(s) => "\"" + s + "\""
    TLParen => "("
    TRParen => ")"
    TComma => ","
    TDot => "."
    TLArrow => "<-"
    TSemi => ";"
    TBang => "!"
    TOp(s) => s
  }
}

///|
/// Read a term: a value in a fact, and a VARIABLE in a rule unless it is quoted
/// or numeric.
fn d_read_term(r : DReader) -> DTerm? {
  match d_take(r) {
    Some(TStr(s)) => Some(DConst(s))
    Some(TNum(s)) => Some(DConst(s))
    Some(TIdent(s)) => if r.in_rule { Some(DVar(s)) } else { Some(DConst(s)) }
    _ => None
  }
}

///|
/// Read a relational atom `P(X1,...,Xn)`.
fn d_read_atom(r : DReader) -> DAtom? {
  match d_take(r) {
    Some(TIdent(p)) => {
      if d_is(r, TLParen) == false {
        return None
      }
      let _ = d_take(r)
      let args : Array[DTerm] = []
      if d_is(r, TRParen) {
        let _ = d_take(r)
        return Some(DRel(p, args))
      }
      while true {
        match d_read_term(r) {
          Some(t) => args.push(t)
          None => return None
        }
        if d_is(r, TComma) {
          let _ = d_take(r)
          continue
        }
        break
      }
      if d_is(r, TRParen) == false {
        return None
      }
      let _ = d_take(r)
      Some(DRel(p, args))
    }
    _ => None
  }
}

///|
/// Read a subgoal: a negated atom, an atom, or an arithmetic comparison.
fn d_read_goal(r : DReader) -> DGoal? {
  let negated = d_is(r, TBang)
  if negated {
    let _ = d_take(r)
  }
  // AN ARITHMETIC ATOM is `term op term` (p.29), and it is told from a
  // relational one by the operator that follows the first term.
  let start = r.pos
  let first = d_read_term(r)
  match first {
    None => return None
    Some(l) =>
      match d_peek(r) {
        Some(TOp(op)) => {
          let _ = d_take(r)
          match d_read_term(r) {
            Some(right) => Some({ atom: DCmp(l, op, right), negated, })
            None => return None
          }
        }
        _ => {
          r.pos = start
          match d_read_atom(r) {
            Some(a) => Some({ atom: a, negated, })
            None => return None
          }
        }
      }
  }
}

///|
/// The alternatives of a parenthesised group: `A, (B;C)` is "A and (B or C)".
fn d_cross(
  a : Array[Array[DGoal]],
  b : Array[Array[DGoal]],
) -> Array[Array[DGoal]] {
  let out : Array[Array[DGoal]] = []
  for x in a {
    for y in b {
      let merged : Array[DGoal] = []
      for g in x {
        merged.push(g)
      }
      for g in y {
        merged.push(g)
      }
      out.push(merged)
    }
  }
  out
}

///|
/// Read one conjunction: a list of alternatives, because a parenthesised
/// disjunction inside it multiplies the alternatives.
fn d_read_conj(r : DReader) -> Array[Array[DGoal]] {
  let mut alts : Array[Array[DGoal]] = [[]]
  while true {
    if d_is(r, TRParen) || d_is(r, TSemi) || d_is(r, TDot) {
      break
    }
    if r.pos >= r.toks.length() {
      break
    }
    if d_is(r, TLParen) {
      let _ = d_take(r)
      let group = d_read_body(r)
      if d_is(r, TRParen) == false {
        break
      }
      let _ = d_take(r)
      alts = d_cross(alts, group)
    } else {
      match d_read_goal(r) {
        Some(g) =>
          for alt in alts {
            alt.push(g)
          }
        None => break
      }
    }
    if d_is(r, TComma) {
      let _ = d_take(r)
      continue
    }
    break
  }
  alts
}

///|
/// Read a body: the conjunctions joined by `;`.
fn d_read_body(r : DReader) -> Array[Array[DGoal]] {
  let alts = d_read_conj(r)
  let out = alts
  while d_is(r, TSemi) {
    let _ = d_take(r)
    let more = d_read_conj(r)
    for m in more {
      out.push(m)
    }
  }
  out
}

///|
/// READ A PROGRAM, and the result says what went wrong when it did.
///
/// THE PROGRAM IS FACTS + RULES (p.40), and a program that does not read is
/// REFUSED with the position it stopped at, because a program that reads as
/// empty would answer "nothing" and that looks exactly like a program whose
/// answer is empty.
pub fn datalog_parse(text : String) -> DParse {
  let (toks, stopped) = d_tokenize(text)
  let r = { toks, pos: 0, in_rule: false, }
  if stopped < text.length() {
    // THE READER STOPPED INSIDE THE TEXT, which is a SYNTAX error rather than
    // the end of the program: an unterminated string or an unknown character.
    let upto = text[0:stopped].to_owned()
    // A `match` AND NOT AN `if`, and the reason is the 0552 precedent: an `if`
    // used as a VALUE is outside the analysed subset, so a binding that is read
    // only inside one is a binding the analyzer believes is unused -- and the
    // false positive lands on the very binding this message is about.
    let shown = match upto.length() > 40 {
      true => upto[upto.length() - 40:].to_owned()
      false => upto
    }
    return {
      ok: false,
      error: "cannot read the program at character " +
      stopped.to_string() +
      " (near '" +
      shown +
      "')",
      program: dprog(),
    }
  }
  let facts : Array[DFact] = []
  let rules : Array[DRule] = []
  while r.pos < r.toks.length() {
    // A FACT is `P(args).` and a RULE is `H1, H2, ... <- B.` -- the heads come
    // BEFORE the arrow, which is the deck's own p.15 form.
    //
    // THE HEAD IS READ AS A RULE'S HEAD, because that is the harder case: its
    // bare terms are VARIABLES. A fact's terms are values, and a fact that
    // turns out to be a fact is CONVERTED afterwards -- so `New(b, o1)` (p.65)
    // reads its two bare identifiers as values and `VarPointsTo(x, o)` (p.70)
    // reads its two bare identifiers as variables, and the difference is the
    // CONTEXT and not the spelling.
    r.in_rule = true
    let head = d_read_atom(r)
    match head {
      None => {
        let got = match d_peek(r) {
          Some(t) => d_tok_text(t)
          None => "the end of the input"
        }
        return {
          ok: false,
          error: "expected a predicate at token " +
          r.pos.to_string() +
          ", found '" +
          got +
          "'",
          program: dprog(),
        }
      }
      Some(a) => {
        let heads : Array[DAtom] = [a]
        // THE DECK'S MULTI-HEAD SHORTHAND (p.15): `H1, H2, H3 <- B.` is three
        // rules with the same body.
        while d_is(r, TComma) {
          let _ = d_take(r)
          match d_read_atom(r) {
            Some(h2) => heads.push(h2)
            None =>
              return {
                ok: false,
                error: "expected a second head at token " + r.pos.to_string(),
                program: dprog(),
              }
          }
        }
        if d_is(r, TLArrow) {
          let _ = d_take(r)
          let body = d_read_body(r)
          r.in_rule = false
          if d_is(r, TDot) == false {
            return {
              ok: false,
              error: "expected '.' at the end of the rule at token " +
              r.pos.to_string(),
              program: dprog(),
            }
          }
          let _ = d_take(r)
          for h in heads {
            // THE WHOLE BODY, and not its first alternative: `drule` takes ONE
            // conjunction, and the deck's `;` form (p.44-45) has SEVERAL. The
            // first version of this line passed `body[0]` and the logical OR
            // was silently dropped -- one of the two alternatives was derived
            // and the other never ran.
            rules.push(drule_disj(h, body))
          }
        } else {
          // A FACT: every term is a value.
          r.in_rule = false
          match a {
            DRel(p, args) => {
              let vals : Array[String] = []
              for tm in args {
                match tm {
                  DConst(v) => vals.push(v)
                  DVar(v) => vals.push(v)
                }
              }
              facts.push(dfact(p, vals))
            }
            DCmp(_, _, _) =>
              return {
                ok: false,
                error: "a fact's head must be a predicate",
                program: dprog(),
              }
          }
          if d_is(r, TDot) == false {
            return {
              ok: false,
              error: "expected '.' at the end of the fact at token " +
              r.pos.to_string(),
              program: dprog(),
            }
          }
          let _ = d_take(r)
        }
      }
    }
  }
  { ok: true, error: "", program: { facts, rules, }, }
}

///|
/// Read ONE rule, and `None` when the text is not one.
pub fn datalog_parse_rule(text : String) -> DRule? {
  let p = datalog_parse(text)
  if p.ok == false {
    return None
  }
  if p.program.rules.length() != 1 || p.program.facts.length() != 0 {
    return None
  }
  Some(p.program.rules[0])
}

///|
/// The text of a term: a variable as its name, a value as its name.
fn d_term_text(t : DTerm) -> String {
  match t {
    DVar(v) => v
    DConst(c) => c
  }
}

///|
/// The text of an atom.
fn d_atom_text(a : DAtom) -> String {
  match a {
    DRel(p, args) => {
      let parts : Array[String] = []
      for t in args {
        parts.push(d_term_text(t))
      }
      p + "(" + parts.join(", ") + ")"
    }
    DCmp(l, op, r) => d_term_text(l) + " " + op + " " + d_term_text(r)
  }
}

///|
/// The text of a goal.
fn d_goal_text(g : DGoal) -> String {
  if g.negated {
    return "!" + d_atom_text(g.atom)
  }
  d_atom_text(g.atom)
}

///|
/// The text of a rule, in the deck's syntax.
///
/// AND THE VALUES ARE QUOTED, because a value is a value and a variable is a
/// variable, and the reader tells them apart. A rule read from the deck's own
/// text and written back out is therefore NOT byte-identical to the deck's
/// text -- the deck writes its values without quotes in some places and with
/// them in others -- and the round trip is asserted on the RULES, which are
/// what the deck's argument is about.
pub fn datalog_rule_text(r : DRule) -> String {
  let parts : Array[String] = []
  for alt in r.body {
    let gs : Array[String] = []
    for g in alt {
      gs.push(d_goal_text(g))
    }
    parts.push(gs.join(", "))
  }
  d_atom_text(r.head) + " <- " + parts.join("; ") + "."
}

///|
/// The text of a program: a fact per line, then a rule per line.
pub fn datalog_program_text(prog : DProgram) -> String {
  let lines : Array[String] = []
  for f in prog.facts {
    lines.push(f.pred + "(" + f.args.join(", ") + ").")
  }
  for r in prog.rules {
    lines.push(datalog_rule_text(r))
  }
  lines.join("\n")
}

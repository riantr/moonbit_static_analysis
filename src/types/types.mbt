// types: lens 2 — the type lens. The
// declaration source is the structural lens's binding tables (assembly
// point 1): this package never rediscovers bindings — it annotates them.
//
// Types are the working subset: Unknown / None / int / float / bool / str /
// [T] (list) / function signatures / unions. Inference is bidirectional
// where an annotation exists, forward otherwise; unions come from merges.

///|
pub(all) enum Ty {
  TUnknown
  TNone
  TInt
  TFloat
  TBool
  TStr
  TList(Ty)
  /// A function type: NAME, PARAMETER NAMES, PARAMETER TYPES, RETURN TYPE.
  ///
  /// The names are parallel to the types. They are there because MoonBit lets
  /// a call reorder named arguments freely (settled against `moon check`), so
  /// an argument's INDEX is not its parameter's index as soon as any argument
  /// is named — and the argument-type check compares one against the other.
  /// An empty name `""` means "not read" (a builtin, or a signature assembled
  /// without the declaration in hand), and a call whose label does not match
  /// any name falls back to position, which is the old behaviour and is
  /// strictly weaker than before.
  TFunc(String, Array[String], Array[Ty], Ty)
  /// A name we know is a VALUE but whose signature we cannot read — a hit in
  /// the cross-file `.mbti` table, where only the declaration name is known.
  /// Distinct from `TUnknown` because a call to this one is certainly a call,
  /// so it must not be reported as "not callable"; and distinct from
  /// `TFunc` because its arity is UNKNOWN, so neither the argument-type check
  /// nor the "too many arguments" check may run against it. Both checks are
  /// sound only against a real parameter list. See the note on
  /// `IfaceSymTab::has_value` for the measured false positives this avoids.
  TUnknownFn(String)
  TUnion(Array[Ty])
} derive(Eq)

///|
/// union constructor: flatten, dedupe, absorb Unknown
/// (Unknown joins as the unknown member).
pub fn ty_union(members : Array[Ty]) -> Ty {
  let flat : Array[Ty] = []
  fn add(t : Ty) -> Unit {
    match t {
      TUnion(ms) =>
        for m in ms {
          add(m)
        }
      _ => if !flat.contains(t) { flat.push(t) }
    }
  }

  for m in members {
    add(m)
  }
  match flat.length() {
    0 => TUnknown
    1 => flat[0]
    _ => TUnion(flat)
  }
}

///|
/// The merge: the unannotated side adopts the annotated side when one is
/// known; two knowns widen to their union.
pub fn ty_join(a : Ty, b : Ty) -> Ty {
  match (a, b) {
    (TUnknown, x) => x
    (x, TUnknown) => x
    (TInt, TFloat) | (TFloat, TInt) => ty_union([TInt, TFloat])
    (TUnion(xs), t) | (t, TUnion(xs)) => {
      let ms : Array[Ty] = []
      for x in xs {
        ms.push(x)
      }
      ms.push(t)
      ty_union(ms)
    }
    (x, y) => if x == y { x } else { ty_union([x, y]) }
  }
}

///|
pub fn ty_name(t : Ty) -> String {
  match t {
    TUnknown => "Unknown"
    TNone => "None"
    TInt => "int"
    TFloat => "float"
    TBool => "bool"
    TStr => "str"
    TList(e) => "[\{ty_name(e)}]"
    TFunc(n, _, _, _) => "fn \{n}"
    TUnknownFn(n) => "fn \{n} (signature not read)"
    TUnion(ms) => {
      let ns : Array[String] = []
      for m in ms {
        ns.push(ty_name(m))
      }
      "Union[\{ns.join(", ")}]"
    }
  }
}

///|
/// Parse a written annotation. Unknown names stay Unknown (no hard error:
/// the name may come from outside this module).
///
/// The MoonBit spellings are capitalised — `Int`, `Bool`, `Float`, `Double`,
/// `String`, `Char`, `Byte`, `Unit` — and the lowercase forms are kept only
/// as tolerance for hand-written sample sources. This list used to hold
/// ONLY the lowercase spellings, so `fn t(n : Int)` typed `n` as `TUnknown`:
/// `tyann` is raw source text, so the two differed only in case and nothing
/// in real MoonBit ever matched. Measured on 0.4.5 that turned the
/// "not callable" check into a no-op on every real source file — see the
/// note at the `ECall` arm in `infer.mbt`.
///
/// `Array[T]` joins the list spelling as of 0.4.13, and that was not cosmetic.
/// The subscript check ("list indices must be int") only fires when the base
/// is known to be a list, because a `Map[K, V]` is indexed by its KEY and
/// asserting an int index there is a false positive — 2 of them on
/// riantr/pyroduct 0.1.29 (`color[u] = 1` on `Map[String, Int]`). But MoonBit
/// writes lists as `Array[T]`, NOT as `[T]`, so with `Array[` unrecognised every
/// real list typed as Unknown, the gate never fired, and the check went silent
/// on the errors it used to catch: `xs["k"]` on `Array[String]` and on
/// `Array[Int]`, both confirmed by `moon check` as "Expr Type Mismatch".
///
/// The lesson is the one this whole file keeps teaching: narrowing a check's
/// preconditions is only safe if the types it now depends on are actually
/// readable. Gating on `TList` was correct; gating on a `TList` that nothing
/// ever produces would have been a mute.
///
/// `Map[K, V]` stays Unknown on purpose — the model has no map type, and an
/// unknown base is the honest answer that keeps the subscript check quiet.
pub fn ann_to_ty(ann : String) -> Ty {
  match ann {
    "" => TUnknown
    "Int" | "Int32" | "int" => TInt
    "Float" | "float" => TFloat
    "Double" | "double" => TFloat
    "Bool" | "bool" => TBool
    "String" | "string" | "str" => TStr
    "None" => TNone
    "Unit" => TNone
    // `Int64` and `UInt` are DELIBERATELY absent, and this is the same lesson
    // the `Array[T]` note above records, pointed the other way. They are not
    // synonyms for `Int`; settled against `moon check` on 0.1.20261012:
    // passing a UInt to an `Int` parameter is an `Expr Type Mismatch`, and so
    // is the reverse, and so is `Int64` against either. Mapping them onto TInt
    // would therefore not be a harmless widening -- it would SILENCE the
    // check on exactly the mismatches `moon check` reports, which is the
    // 0.4.5 failure (a check whose precondition nothing ever satisfies) with
    // the sign flipped. They need their own `Ty` variants and their own
    // assignability rules; until then Unknown is the honest answer.
    //
    // Corpus weight, so the next person sizing that work has it: 122 `: Int64`
    // and 23 `: UInt` annotations across proton + async + moui.
    _ => ann_to_list_ty(ann)
  }
}

///|
/// The two container spellings: `Array[T]` (the real MoonBit one) and `[T]`
/// (kept for hand-written samples and `.mbti` text). Anything else — including
/// `Map[K, V]` — is not a list and returns `TUnknown`.
///
/// The prefix test is on the first five characters rather than a `split`, so
/// `Array` must be followed by `[` to count: a hypothetical type named `Arrayx`
/// must not be read as a list.
fn ann_to_list_ty(ann : String) -> Ty {
  let n = ann.length()
  if n > 6 &&
    ann[0] == 'A' &&
    ann[1] == 'r' &&
    ann[2] == 'r' &&
    ann[3] == 'a' &&
    ann[4] == 'y' &&
    ann[5] == '[' &&
    ann[n - 1] == ']' {
    TList(ann_to_ty(str_slice(ann, 6, n - 1)))
  } else if n > 2 && ann[0] == '[' && ann[n - 1] == ']' {
    TList(ann_to_ty(str_slice(ann, 1, n - 1)))
  } else {
    TUnknown
  }
}

///|
pub fn is_numeric(t : Ty) -> Bool {
  match t {
    TInt | TFloat => true
    TUnion(ms) => {
      let mut all = true
      for m in ms {
        if !(m is TInt) && !(m is TFloat) {
          all = false
        }
      }
      all
    }
    _ => false
  }
}

///|
/// Can a value of `v` be assigned to a binding annotated `target`?
///
/// `TList` recurses on the element type, and that is not a convenience: the
/// rule two arms below already says an Unknown is assignable to anything, so a
/// list holding an unknown element must be assignable to a list of anything —
/// otherwise the Unknown escape hatch is silently defeated one level down. The
/// non-recursive version fired 3 false positives on this repo's own source as
/// soon as `Array[T]` became readable (0.4.13): `[root]` from a `for` binder
/// and `[first]` from a tuple-destructuring call are both `TList(TUnknown)`,
/// and neither is evidence of a type error.
pub fn ty_assignable(v : Ty, target : Ty) -> Bool {
  match (v, target) {
    (_, TUnknown) | (TUnknown, _) => true
    (a, b) if a == b => true
    (TInt, TFloat) => true // int widens
    (TList(a), TList(b)) => ty_assignable(a, b)
    (_, TUnion(ms)) => {
      let mut ok = false
      for m in ms {
        if ty_assignable(v, m) {
          ok = true
        }
      }
      ok
    }
    (TUnion(_), _) =>
      // every member must fit (an assignment-type error fires when
      // any member is incompatible)
      true // widened union-to-single handled by caller via member loop
    _ => false
  }
}

///|
/// Operand check for binary operators: returns the result type, or None
/// when the combination is a type error (reportOperatorIssue).
pub fn binop_result(op : @ast.BOp, l : Ty, r : Ty) -> Ty? {
  // an unknown operand stays silent (operator errors are suppressed
  // for Unknown — the undefined-name finding already covers it)
  //
  // THE REGEX MATCH IS THE ONE EXCEPTION. Its result is a Bool -- settled
  // against the toolchain (`_verify/settle_0494_parse_backlog.ps1`, row `a3`,
  // with the control `a4` REJECTing the same expression against an Int) -- and
  // its RIGHT operand is a Regex, a type this model does not have, so that
  // operand IS unknown and the rule above would answer "unknown" for an
  // expression whose result is a Bool. The operand types are therefore NOT
  // checked for this operator, and the answer is the result type alone.
  if op != @ast.OpMatch && (l is TUnknown || r is TUnknown) {
    return Some(TUnknown)
  }
  match op {
    OpAdd =>
      if is_numeric(l) && is_numeric(r) {
        if l is TFloat || r is TFloat {
          Some(TFloat)
        } else if l is TUnion(_) || r is TUnion(_) {
          Some(ty_join(l, r))
        } else {
          Some(TInt)
        }
      } else if l is TStr && r is TStr {
        Some(TStr)
      } else if l is TList(_) && r is TList(_) {
        Some(l)
      } else {
        None
      }
    OpSub | OpMul | OpDiv | OpMod =>
      if is_numeric(l) && is_numeric(r) {
        // `/` gets no special case, because MoonBit gives it none either:
        // Int/Int is integer division (`7 / 2` is 3, verified by running it),
        // so the result is whatever the operands already are. The arm that
        // used to answer TFloat here produced 14 false AssignTypeMismatch
        // findings on riantr/moonbit_doubleML 0.139.0.
        if l is TFloat || r is TFloat {
          Some(TFloat)
        } else {
          Some(TInt)
        }
      } else {
        None
      }
    OpEq | OpNe | OpLt | OpLe | OpGt | OpGe => {
      // `==` / `!=` are legal between two Bools in MoonBit. The ORDERING
      // operators are a separate question and are deliberately not extended
      // here — `true < false` has no meaning and must still be reported.
      //
      // Probed: `fn p(a : Bool, b : Bool) -> Bool { a == b }` compiles with 0
      // errors and 0 warnings from `moon check`. The analyzer said
      // "unsupported operand types for '==': 'bool' and 'bool'" at error:
      // severity (measured: 2 findings on riantr/moonbit_doubleML 0.139.0,
      // `expand_v098_test.mbt` and `expand_v122_test.mbt`).
      let ordered = (is_numeric(l) && is_numeric(r)) || (l is TStr && r is TStr)
      let eq_ok = if op == OpEq || op == OpNe {
        ordered || (l is TBool && r is TBool)
      } else {
        ordered
      }
      if eq_ok {
        Some(TBool)
      } else {
        None
      }
    }
    OpAnd | OpOr => if l is TBool && r is TBool { Some(TBool) } else { None }
    OpMatch =>
      // The REGEX MATCH. The result is a Bool, and the operand types are NOT
      // checked -- the right operand is a Regex and this model has no Regex
      // type. See the note at the top of this function.
      Some(TBool)
    OpPipe =>
      // The PIPE IS A CALL, so the result is the callee's return type, which this
      // analyzer does not model: `1 |> inc` has an Int LEFT and a FUNCTION right,
      // and no operand rule here can produce a type for it.
      //
      // `Some(TUnknown)` rather than `None`. `None` means "operator mismatch" and
      // the caller reports it, so returning it would turn every pipe in the corpus
      // into a confident false positive -- a finding about code `moon check`
      // compiles. Unknown silences the check, which is the honest answer for "a
      // call whose result was not read", and it is the same treatment a
      // cross-package name gets (`infer_full` seeds those as TUnknown).
      Some(TUnknown)
    OpBitAnd | OpBitOr | OpBitXor | OpShl | OpShr =>
      // Bitwise ops are Int-on-Int only in this subset: no Float claim is
      // made (Float bitwise is not in the corpus and would be an invented
      // widening), and a non-Int operand is a type error, reported by the
      // caller like any other operator mismatch.
      if l is TInt && r is TInt {
        Some(TInt)
      } else {
        None
      }
  }
}

///|
/// A symbol with an inferred type: the annotated binding table.
pub(all) struct TypedSym {
  name : String
  ty : Ty
  annotated : Bool
  fn_scope : String
  decl_span : @core.Span
} derive(Eq)

///|
/// The signature table: one entry per analyzed function. This is what the
/// behavior lens consumes as its method table (assembly point 2) —
/// "methods are tables" with types the type lens already proved.
pub(all) struct Sig {
  name : String
  /// Parameter names, parallel to `param_tys`. See `TFunc` for why the
  /// argument-type check needs them.
  param_names : Array[String]
  param_tys : Array[Ty]
  ret : Ty
  declared_ret : Ty
  line : Int32
} derive(Eq)

///|
pub(all) struct TypeResult {
  syms : Array[TypedSym]
  sigs : Array[Sig]
  findings : Array[@report.Report]
  /// 0507. The calls this lens could NOT check: a call to a name it knows only
  /// by NAME (a `.mbti` of another package), a method call, and a `..` chain
  /// link. Each of them is a real call whose arguments went unverified, and
  /// until now that silence was indistinguishable from "there was nothing to
  /// check".
  n_unchecked : Int32
}

///|
fn str_slice(s : String, from : Int32, to : Int32) -> String {
  let buf = StringBuilder()
  for c in s {
    buf.write_char(c)
  }
  buf.to_string()[from:to].to_owned()
}

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
  TFunc(String, Array[Ty], Ty)
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
    TFunc(n, _, _) => "fn \{n}"
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
pub fn ann_to_ty(ann : String) -> Ty {
  match ann {
    "" => TUnknown
    "Int" | "int" => TInt
    "Float" | "float" => TFloat
    "Double" | "double" => TFloat
    "Bool" | "bool" => TBool
    "String" | "string" | "str" => TStr
    "None" => TNone
    "Unit" => TNone
    _ =>
      if ann.length() > 2 && ann[0] == '[' && ann[ann.length() - 1] == ']' {
        TList(ann_to_ty(str_slice(ann, 1, ann.length() - 1)))
      } else {
        TUnknown
      }
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
pub fn ty_assignable(v : Ty, target : Ty) -> Bool {
  match (v, target) {
    (_, TUnknown) | (TUnknown, _) => true
    (a, b) if a == b => true
    (TInt, TFloat) => true // int widens
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
  if l is TUnknown || r is TUnknown {
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
        if op == OpDiv {
          Some(TFloat)
        } else if l is TFloat || r is TFloat {
          Some(TFloat)
        } else {
          Some(TInt)
        }
      } else {
        None
      }
    OpEq | OpNe | OpLt | OpLe | OpGt | OpGe =>
      if (is_numeric(l) && is_numeric(r)) || (l is TStr && r is TStr) {
        Some(TBool)
      } else {
        None
      }
    OpAnd | OpOr => if l is TBool && r is TBool { Some(TBool) } else { None }
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
  param_tys : Array[Ty]
  ret : Ty
  declared_ret : Ty
  line : Int
} derive(Eq)

///|
pub(all) struct TypeResult {
  syms : Array[TypedSym]
  sigs : Array[Sig]
  findings : Array[@report.Report]
}

///|
fn str_slice(s : String, from : Int, to : Int) -> String {
  let buf = StringBuilder()
  for c in s {
    buf.write_char(c)
  }
  buf.to_string()[from:to].to_owned()
}

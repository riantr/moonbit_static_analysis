//| 0495: THE PER-FUNCTION VIEW'S FALSE POSITIVES, ONE FAMILY AT A TIME.
//
//| THE CONTEXT. Direction 2 asked what the behavioural lens reports when it is
//| pointed at a FUNCTION rather than at a module. Re-measured after 0494, the
//| per-function view is non-zero on four of the seven pinned corpora:
//
//|     moonbit_labeler  38      moonbit_image  35
//|     async            40      proton          3
//|
//| 116 findings in all, and NOT ONE of them is a defect in the code being
//| analysed: every one of the 116 sites is in a file that `moon check`
//| accepts, and the corpora are released, published packages.
//
//| So the 116 are an INVENTORY of what is still wrong with the LENS, and this
//| file is the measurement of that inventory -- one family at a time, each
//| family with a CONTROL that must still report. A fix that silences a family
//| is worth nothing if the family was the only thing that distinguished a
//| wrong program from a right one.
//
//| THE FAMILIES, measured, not guessed. The eight below are the eight shapes
//| the 116 findings take. The count next to each is the number of findings of
//| that shape across the four corpora; the total is 116.
//
//|   A   61   a destructured name bound to the WHOLE TUPLE
//|   B   25   a `continue`/`break` that CARRIES A VALUE
//|   C    8   a statement after a loop whose body always terminates
//|   D   10   a call to an `extern`/FFI declaration
//|   E    5   a cross-package qualified associated/trait call
//|   F    4   an integer `/` typed as `float`
//|   G    2   a name bound by an `is`-pattern `as`-binding
//|   H    1   a name bound by an ITERATOR expression
//|
//| The counts are measured by `_verify/settle_0495_perfunction.ps1` and
//| reproduced by the release gate's corpus stage.

///|
/// FAMILY A: A DESTRUCTURED NAME IS AN ELEMENT, NOT THE TUPLE.
///
/// `let (a, b) = pair()` binds `a` and `b` to the two ELEMENTS. The lens
/// bound both of them to the whole tuple, so every use of a destructured name
/// carried the abstract type "Tuple" into a call whose parameter was declared
/// `Int`:
///
///     no method matching derive_label_dir_from_image_dir(Tuple)
///     no method matching lzw_read_code(Any, Tuple, Tuple, int)
///     no method matching -(Tuple, Tuple)
///
/// 61 findings on four corpora, all of them false positives.
///
/// The TYPE LENS already answers "Unknown" for a destructured name -- "tuple
/// element types are not modelled (no tuple Ty), so every destructured name
/// starts Unknown in the current frame" (`src/types/infer.mbt`) -- so the
/// behavioural lens was contradicting its own sibling on the same line.
test "0495 A: a destructured name is not the tuple it was destructured from" {
  let src = "fn pair() -> (Int, Int) {\n  (1, 2)\n}\n\nfn take(x : Int) -> Int {\n  x\n}\n\nfn caller() -> Int {\n  let (a, b) = pair()\n  take(a)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR FAMILY A: a TUPLE passed where an `Int` is declared is
/// still a type error. Without this row, a rule that silenced every call
/// whose argument came from a tuple would pass the row above -- and so would
/// a rule that silenced every call.
test "0495 A control: a tuple value against an int parameter is still an error" {
  let src = "fn take(x : Int) -> Int {\n  x\n}\n\nfn caller() -> Int {\n  take((1, 2))\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// THE OTHER CONTROL FOR FAMILY A: a destructured name that is then REASSIGNED
/// keeps the reassigned value's type, and a wrong one is still reported. This
/// is the shape the corpora use: `pos = p1` where `p1` came out of a
/// destructuring, and `p1` was an `Int` while the parameter wanted a `UInt`.
test "0495 A control: a reassigned destructured name is still checked" {
  let src = "fn take(x : Int) -> Int {\n  x\n}\n\nfn caller() -> Int {\n  let (a, b) = (1, 2)\n  a = \"not an int\"\n  take(a)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// FAMILY B: A `continue` THAT CARRIES A VALUE IS NOT UNREACHABLE CODE.
///
/// `continue p, r, c, vr` sets the loop variables and continues. The values
/// used to be parsed as SIBLING STATEMENTS -- `SBlock([SContinue, SExpr(a),
/// SExpr(b)])` -- so the interpreter read the terminator, saw the flow end,
/// and reported the first carried value as `unreachable code`:
///
///     moonbit_image  bmp.mbt:373    `continue p, r, c, vr`
///     moonbit_image  bmp.mbt:467    `continue p, r, c, vr`
///     async          conn.mbt:389   `continue received + n`
///     async          crc32.mbt:63   `continue crc, i + 8`
///
/// 25 findings on three corpora, all of them false positives.
test "0495 B: a continue that carries a value is not unreachable code" {
  let src = "fn probe(n : Int) -> Int {\n  for i = 0; i < n; i = i + 1 {\n    continue i + 1\n  }\n  0\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "Unreachable"), 0)
}

///|
/// THE SAME FOR A `break` THAT CARRIES A VALUE. `break (consumed, produced)`
/// is the gzip decoder's shape, and the tuple it carries is the break's own
/// payload rather than a statement after it.
test "0495 B: a break that carries a value is not unreachable code" {
  let src = "fn probe(n : Int) -> Int {\n  for i in 0..<n {\n    break (i, i)\n  }\n  0\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "Unreachable"), 0)
}

///|
/// THE CONTROL FOR FAMILY B: A STATEMENT AFTER A `return` IS UNREACHABLE, and
/// it is still reported. Without this row, a rule that made the carried values
/// invisible would also make every genuinely dead statement invisible -- and
/// `unreachable code` is the one family the per-function view exists to
/// produce.
test "0495 B control: a statement after a return is still unreachable" {
  let src = "fn probe() -> Int {\n  return 1\n  let x = 2\n  x\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "Unreachable"), 1)
}

///|
/// THE OTHER CONTROL FOR FAMILY B: a NAME INSIDE THE CARRIED VALUE IS STILL
/// CHECKED. `continue undefined_name` has to report -- the carried value is
/// read, not skipped.
test "0495 B control: an undefined name inside a carried value is still reported" {
  let src = "fn probe(n : Int) -> Int {\n  for i = 0; i < n; i = i + 1 {\n    continue zq_undefined\n  }\n  0\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 1)
}

///|
/// FAMILY D, PART 1: THE PIPE SUPPLIES THE ARGUMENT TO THE CALL ON ITS LEFT.
///
/// `f <| x` applies `f` to `x`, and when `f` is a CALL the right operand
/// becomes an ARGUMENT of that call. The lens evaluated the call on its own,
/// with one argument, against a two-parameter declaration:
///
///     no method matching set_timeout(int)
///
/// MEASURED, moonbitlang/async 0.22.4
/// `src/internal/event_loop/timer.js.mbt:25`:
///
///     set_timeout(duration) <| () => { .. }
///
/// SETTLED against the toolchain: `add2(1) <| 2` ACCEPTs where `add2`
/// declares two parameters, and `one(1) <| 2` REJECTs where `one` declares
/// one. See `_verify/settle_0495_perfunction.ps1`, rows `d3`.
test "0495 D: a pipe supplies the argument to the call on its left" {
  let src = "fn set_timeout(duration : Int, f : () -> Unit) -> Int {\n  0\n}\n\nfn arm(duration : Int) -> Int {\n  set_timeout(duration) <| () => {\n    ignore(1)\n  }\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR FAMILY D PART 1: the same call WITHOUT the pipe is still
/// short of an argument, and the arity check still says so. Without this row,
/// a rule that silenced every arity error would pass the row above.
test "0495 D control: a call that omits a required argument is still an error" {
  let src = "fn set_timeout(duration : Int, f : () -> Unit) -> Int {\n  0\n}\n\nfn arm(duration : Int) -> Int {\n  set_timeout(duration)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// FAMILY D, PART 2: AN OMITTABLE PARAMETER IS NOT A POSITIONAL SLOT.
///
/// A parameter a call may OMIT (`name? : T = ...`) is bound by label or left
/// at its default -- it is not filled positionally. Counting it as a slot
/// shifted every later argument one to the left, and the argument that landed
/// on it was compared against the WRONG parameter's type:
///
///     no method matching JobHandle::inotify_add_watch(Any, Any, bool)
///
/// MEASURED, moonbitlang/async 0.22.4
/// `src/internal/event_loop/thread_pool.wasm.mbt:703` -- six sites in that one
/// file.
///
/// SETTLED against the toolchain: `f(1, 2)` ACCEPTs for
/// `fn f(a : Int, b? : Int = 0, c : Int)`, and `f(1)` REJECTs because `c` is
/// required. See `_verify/settle_0495_perfunction.ps1`, rows `d4`.
test "0495 D: an omittable parameter is not a positional slot" {
  let src = "fn f(a : Int, b? : Int = 0, c : Bool) -> Int {\n  if c {\n    1\n  } else {\n    0\n  }\n}\n\nfn probe() -> Int {\n  f(1, true)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR FAMILY D PART 2: the argument that lands on `c` is still
/// checked against `c`'s type. The second argument goes to `c` -- NOT to the
/// omittable `b` -- and an Int is not a Bool.
test "0495 D control: an argument past an omittable parameter is still checked" {
  let src = "fn f(a : Int, b? : Int = 0, c : Bool) -> Int {\n  if c {\n    1\n  } else {\n    0\n  }\n}\n\nfn probe() -> Int {\n  f(1, 1)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// FAMILY D, PART 3: A NAME DECLARED TWICE HAS NO SINGLE SIGNATURE.
///
/// MoonBit allows two top-level functions of the same name, and `#cfg` is how
/// real code reaches it. The lens took one declaration's signature and
/// compared BOTH call sites against it, so one of them was always wrong:
///
///     no method matching close_ffi(Any, Any)     -- fd_util.mbt:76
///     no method matching close_ffi(Any)           -- fd_util.mbt:64
///
/// MEASURED, moonbitlang/async 0.22.4
/// `src/internal/fd_util/fd_util.mbt:58,71`.
test "0495 D: a name declared twice is not arity-checked" {
  let src = "#cfg(not(platform=\"windows\"))\nfn close_ffi(fd : Int) -> Int {\n  0\n}\n\n#cfg(platform=\"windows\")\nfn close_ffi(fd : Int, is_socket~ : Bool) -> Int {\n  0\n}\n\nfn probe(fd : Int) -> Int {\n  close_ffi(fd)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE OTHER HALF OF THE SAME THING: the call that matches the OTHER
/// declaration. One call site fits the one-parameter variant and the other
/// fits the two-parameter one, so whichever declaration the lens picked, one
/// of the two was reported.
test "0495 D: a name declared twice is not arity-checked on the other call" {
  let src = "#cfg(not(platform=\"windows\"))\nfn close_ffi(fd : Int) -> Int {\n  0\n}\n\n#cfg(platform=\"windows\")\nfn close_ffi(fd : Int, is_socket~ : Bool) -> Int {\n  0\n}\n\nfn probe(fd : Int) -> Int {\n  close_ffi(fd, is_socket=true)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR FAMILY D PART 3: a name declared ONCE is still arity-
/// checked. The ambiguity is what removes the check, not the call.
test "0495 D control: a name declared once is still arity-checked" {
  let src = "fn one(a : Int) -> Int {\n  a\n}\n\nfn probe(a : Int) -> Int {\n  one(a, a)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// FAMILY D, PART 4: AN EXTERN'S RESULT IS NOT "THE VALUE None".
///
/// An `extern` declaration has no MoonBit body to execute, so the lens has
/// nothing to say about what it returns. It said "None" -- which is a claim
/// about a value the file never mentions -- and the comparison two lines
/// later read it as such:
///
///     no method matching <(None, int)
///
/// MEASURED, moonbitlang/async 0.22.4 `src/socket/ffi.mbt:16,22`:
///
///     extern "C" fn make_tcp_socket_ffi(family : AddrFamily) -> @fd_util.Fd = "..."
///     ...
///     if sock < 0 { ... }
///
/// The declared return type is a CROSS-PACKAGE type, so the type lens cannot
/// name it, and the honest answer is "a value of unknown type" -- which the
/// operator arms already absorb.
test "0495 D: an extern's result is not the value None" {
  let src = "extern \"C\" fn make_fd_ffi(family : Int) -> @fd_util.Fd = \"make_fd\"\n\nfn make_fd(family : Int) -> @fd_util.Fd {\n  let sock = make_fd_ffi(family)\n  if sock < 0 {\n    sock\n  } else {\n    sock\n  }\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR FAMILY D PART 4: a comparison of two operands of DIFFERENT
/// types is still a method error. The extern's result is unknown; a Bool is
/// known, and a Bool is not less than an Int.
test "0495 D control: a comparison of a bool and an int is still an error" {
  let src = "fn f() -> Bool {\n  true\n}\n\nfn probe() -> Bool {\n  f() < 0\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// FAMILY E: A TRAIT'S METHOD IS A VALUE, AND THE CROSS-FILE TABLE CARRIES
/// IT.
///
/// The `.mbti` declares the method inside the trait's body:
///
///     pub(open) trait Writer {
///       async fn write(Self, &Data) -> Unit = _
///     }
///
/// and the use site writes `@io.Writer::write(self, s)`, which the table
/// resolves to `Writer::write`. Without the method in the table the call was
/// reported `undefined function '@io.Writer::write'` -- on code `moon check`
/// accepts.
///
/// MEASURED, moonbitlang/async 0.22.4, three sites: `src/http/server.mbt:155`,
/// `src/fs/file.mbt:510` and `:539`.
///
/// The reader itself is tested in `src/moonfiles/moonfiles_0495_test.mbt`; this
/// row is the seam the analyzer looks in.
test "0495 E: a trait method in the cross-file table is not an undefined function" {
  let tab = @core.IfaceSymTab::empty()
  tab.values.set("Writer::write", true)
  let src = "fn send_it(w : Int, s : String) -> Unit {\n  @io.Writer::write(w, s)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", tab)
  assert_eq(count_family(perfn, "UndefinedName"), 0)
}

///|
/// THE CONTROL FOR FAMILY E: a name the table does NOT carry is still
/// reported. The table is a LINK, not a suppression.
test "0495 E control: a trait method the table does not carry is still reported" {
  let tab = @core.IfaceSymTab::empty()
  tab.values.set("Writer::write", true)
  let src = "fn send_it(w : Int, s : String) -> Unit {\n  @io.Writer::wrtie(w, s)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", tab)
  assert_eq(count_family(perfn, "UndefinedName"), 1)
}

///|
/// FAMILY U: A LOOP WHOSE BODY MAY BREAK LEAVES THE LOOP, AND THE CODE
/// AFTER IT IS REACHED.
///
/// The joined flow cannot say whether a body could have left the loop: a body
/// whose branches end in DIFFERENT terminators joins to `FReturn`, and the
/// `break` is gone with it. The code after such a loop was reported
/// `unreachable code` -- on code `moon check` accepts.
///
/// MEASURED, moonbitlang/async 0.22.4 `src/http/cookie.mbt:88`:
///
///     if attr_end == line.length() {
///       break
///     } else {
///       continue attr_end + 1
///     }
///   }
///   { name, value, path, .. }
///
/// and moonbit_image 0.3.7 `bmp.mbt:423` and `:533`.
test "0495 U: the statement after a loop whose body may break is reachable" {
  let src = "fn probe(n : Int) -> Int {\n  for parsed = 0 {\n    if parsed >= n {\n      break\n    } else {\n      continue parsed + 1\n    }\n  }\n  42\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "Unreachable"), 0)
}

///|
/// THE CONTROL FOR FAMILY U: a loop whose body ALWAYS RETURNS leaves nothing
/// after it, and the statement there is still reported. The fix is about the
/// `break` being lost in the join, not about the check being softened.
test "0495 U control: the statement after a loop that always returns is still unreachable" {
  let src = "fn probe() -> Int {\n  for parsed = 0 {\n    return 1\n  }\n  42\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "Unreachable"), 1)
}

///|
/// FAMILY C: THE JOIN REPORTS THE TERMINATOR THE BRANCHES AGREE ON.
///
/// A loop whose condition is constantly true never ends on its own, so the
/// only way out is a `break` -- and the code after such a loop is reachable
/// exactly when the body can leave it. The join used to answer `FReturn` for
/// every branch set, which lost the difference between "the body returned" and
/// "the body left the loop".
///
/// This row is the one that pins the AGREEMENT rule: both branches here
/// CONTINUE, so the join says `FContinue`, and the loop is still live.
///
/// THE LOOP'S CONDITION IS CONSTANTLY TRUE ON PURPOSE. A `while` whose
/// condition is not constant can end on its own, so the code after it is
/// reachable whatever the join says -- and the row would not discriminate. The
/// `while true` is what makes the join the only thing that decides.
test "0495 C: the statement after a loop whose branches all continue is reachable" {
  let src = "fn probe(n : Int) -> Int {\n  let mut parsed = 0\n  while true {\n    if parsed >= n {\n      continue parsed + 1\n    } else {\n      continue parsed + 2\n    }\n  }\n  42\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "Unreachable"), 0)
}

///|
/// FAMILY F: AN INTEGER DIVISION IS AN INTEGER.
///
/// `7 / 2` is 3, not 3.5, and the lens typed every `/` as `float` -- a claim
/// about the language that was false in both directions. It survived because
/// the difference was not OBSERVABLE; it is now, and the measurement is
/// moonbit_image 0.3.7 `fim.mbt`:
///
///     let hs = h / 2              h : Int
///     fim_gray_a8(w, hs, even)    the parameter is `h : Int`
///
/// reported `no method matching fim_gray_a8(Any, float, Any)`.
test "0495 F: a division of two literals is an integer" {
  let src = "fn take(x : Int) -> Int {\n  x\n}\n\nfn probe() -> Int {\n  let hs = 7 / 2\n  take(hs)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE SAME FOR THE NON-CONSTANT CASE, which is the shape the corpus has: the
/// divisor is a literal and the dividend is a parameter, so the value is not
/// folded and the TYPE is what answers.
test "0495 F: a division by a literal is an integer" {
  let src = "fn take(x : Int) -> Int {\n  x\n}\n\nfn probe(h : Int) -> Int {\n  let hs = h / 2\n  take(hs)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR FAMILY F: A REAL FLOAT DIVISION IS STILL A FLOAT. The fix
/// is about the INTEGER case; a float operand must keep its type.
test "0495 F control: a float division is still a float" {
  let src = "fn take(x : Float) -> Float {\n  x\n}\n\nfn probe(h : Float) -> Float {\n  let hs = h / 2.0\n  take(hs)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// FAMILY G: A NAME BOUND BY AN `as`-BINDING IS BOUND.
///
/// `s is (HasReader(_) as reader)` binds `reader` inside the branch. The
/// pattern reader collected the names at DEPTH 2 -- the rule that protects an
/// or-pattern's constructors -- and the `as` binding sits at depth 1, so
/// `reader` was never bound and every use of it was reported `undefined
/// variable`.
test "0495 G: a name bound by an is-pattern as-binding is bound" {
  let src = "enum State {\n  HasReader(Int)\n  Closed\n}\n\nfn probe(s : State) -> Int {\n  if s is (HasReader(_) as reader) {\n    reader\n  } else {\n    0\n  }\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 0)
}

///|
/// FAMILY H: A COMPREHENSION BINDS ITS PATTERN.
///
/// `[ for handle in xs => handle ]` binds `handle` for the body. The
/// comprehension's names were dropped, so every read of the bound name inside
/// the body was an undefined variable.
///
/// MEASURED, moonbitlang/async 0.22.4
/// `src/internal/event_loop/event_loop.mbt:260`.
test "0495 H: a comprehension binds its pattern" {
  let src = "fn probe(xs : Array[Int]) -> Int {\n  let leaked = [\n    for handle in xs => handle\n  ]\n  [\n    for other in xs => other\n  ]\n  0\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 0)
}

///|
/// FAMILY J: A MISSING `else` STILL FALLS THROUGH WHEN EVERY BRANCH RETURNS.
///
/// THIS ROW EXISTS BECAUSE A MUTATION GATE ASKED A QUESTION NOBODY HAD ASKED.
/// 0495 replaced the `falls` flag with the branch FLOWS and `join_flow`, and
/// that change quietly made one of 0.4.25's fixtures insensitive to the
/// statement it was written to pin.
///
/// THE ARITHMETIC OF THE CHANGE. Before, the missing else was an ASSIGNMENT to
/// the flag -- `None => falls = true` -- so it OVERRODE whatever the branches
/// had said. After, it is one more entry in a list of flows, and `join_flow`
/// takes the join: fall through if ANY branch does. So after 0495 the
/// missing-else entry is REDUNDANT whenever some branch falls through -- and
/// 0.4.25's fixture for it ("a chain with no else at all falls through") has
/// exactly such a branch (`let _ = 2`).
///
/// MEASURED, not inferred. The pre-0495 tree (`git show 8449509^`) with 0.4.25's
/// M7 mutation applied killed EXACTLY ONE test --
/// "0425: a chain with no else at all falls through" -- and the same mutation on
/// the 0495 tree kills NONE. The line had stopped being observable.
///
/// It is still LOAD-BEARING, in the case no fixture covered: a chain with no
/// else where EVERY branch terminates. There the missing else is the only
/// fall-through, and without it the statement after the chain would be reported
/// `unreachable code` -- a false positive on code `moon check` accepts.
///
/// THE FIXTURE IS 0.4.25's, WITH ONE LINE CHANGED: the else-if body returns
/// instead of falling through. Everything else -- the folded outer condition
/// that routes the chain into `exec_alt`, the unfolded else-if condition that
/// enters its unknown-condition arm, the missing else -- is the same, so the
/// row below and 0.4.25's are the same program with one line apart.
test "0495 J: a chain with no else falls through even when every branch returns" {
  let src = "fn f(n : Int, s : String) -> Int {\n  if n > 0 {\n    return 1\n  } else if s == \"a\" {\n    return 2\n  }\n  return 3\n}\nlet x = f(-1, \"a\")\n"
  let r = @pipeline.run(
    src,
    "chain_no_else_all_return.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
}

///|
/// THE CONTROL FOR FAMILY J, and it is 0.4.25's own row: the SAME chain with
/// an `else` that returns is genuinely dead after it, and it is still reported.
/// Without this row the one above would also pass if the analyzer had stopped
/// reporting `unreachable code` on chains altogether.
test "0495 J control: a chain that returns everywhere is still dead after it" {
  let src = "fn f(n : Int, s : String) -> Int {\n  if n > 0 {\n    return 1\n  } else if s == \"a\" {\n    return 2\n  } else {\n    return 4\n  }\n  return 5\n}\nlet x = f(-1, \"a\")\n"
  let r = @pipeline.run(
    src,
    "chain_all_return_control.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
}

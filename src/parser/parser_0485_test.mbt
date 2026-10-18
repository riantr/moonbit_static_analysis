//| Tests for 0485 -- a BRACED STRUCT PATTERN in `is` position, `x is { "cmd": [cmd], .. }`.
//
//| THE DEFECT. `parse_is_pattern` had NO `{` BRANCH AT ALL, so a brace pattern fell to the
//| `else { return [] }` at the bottom of that function and **consumed nothing**. One missing arm,
//| and it produced two different failures rather than one -- measured with first_error AND
//| UndefinedName TOGETHER, because measuring them apart is what made the `if` row look unaffected
//| when its first_error had never been measured at all:
//
//|     caller        { "cmd": [cmd] }     { "cmd": [cmd], .. }
//|     match arm     fe=0  undef=0        fe=0  undef=0     <- correct already (skip_pattern)
//|     guard         fe=0  undef=2        fe=2  undef=0
//|     bare `is`     fe=0  undef=2        fe=2  undef=0
//|     if            fe=2  undef=0        fe=2  undef=0
//|     while         fe=2  undef=0        fe=2  undef=0
//|     let destr     fe=2  undef=0        fe=2  undef=0
//
//| *** THE QUIET HALF IS WORTH MORE THAN THE THREE FILES THAT STOP. *** `guard` and a bare `is`
//| PARSE: the leftovers happen to re-read as a BLOCK, so nothing halts, and then the names the
//| pattern was supposed to bind are reported undefined -- a FALSE POSITIVE on code `moon check`
//| compiles. It moves no parse-coverage number in either direction.
//
//| ONE READER FIXES ALL OF `guard`, `if`, `while` AND a bare `is`: the toolchain ACCEPTS the
//| braced pattern in every one of those positions, and all four reach `parse_is_pattern` through
//| `parse_is`. Measured before implementing, not after -- `_verify/settle_0485_is_struct_pattern.ps1`,
//| 16 rows / 4 controls, GATE OK:
//
//|   ACCEPT  guard / if / while / bare `is`, with and without `..`, one key or several,
//|           a plain value, a NESTED array pattern, `{ .. }` alone, `{}` alone
//!   REJECT(4028)  `{ cmd: [cmd], .. }` unquoted key on a `Json` subject
//!   REJECT(0011)  `let { "cmd": [cmd], .. } = x` -- `partial_match`, a `let` pattern must be
//!                 irrefutable. That row is left UNREAD on purpose: it is a different reader and
//!                 reading it would be a MISSED error.
//!
//| WHY EVERY ROW HERE ASSERTS THE BINDING AND NOT `first_error`: the defect this increment fixed
//! was invisible to parse coverage by construction. A row that only checked the parse would have
//! been green before the fix for the `guard` row -- which is exactly why it exists.

///|
/// Pull the `EIs` binding list out of `fn f(x : T) -> Int { <stmt>; x }`.
///
/// `raise` in the signature because this helper ASSERTS, and 4122 refuses a function-with-error
/// call from one that has no error type. Every caller is a test body, so every caller already has
/// it.
fn eis_bindings(src : String) -> Array[String] raise {
  let r = @parser.parse(src)
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    // SFunc's fourth field IS the statement array -- parse_block returns one, not an SBlock --
    // so there is no `.kind` to take here. Reaching for one is 4028.
    @ast.SFunc(_, _, _, stmts, _) =>
      match stmts[0].kind {
        @ast.SIf(cond, _, _, _) =>
          match cond.kind {
            @ast.EIs(_, b) => b
            _ => []
          }
        _ => []
      }
    _ => []
  }
}

///|
/// THE CORPUS SHAPE BINDS ITS NAME. `examples/xargs/main.mbt:49`.
test "0485: a braced pattern binds the element it names" {
  let b = eis_bindings(
    "fn f(x : J) -> Int {\n  guard x is { \"cmd\": [cmd], .. } else { return 0 }\n  cmd\n}\n",
  )
  assert_eq(b.length(), 1)
  assert_eq(b[0], "cmd")
}

///|
/// THE SAME WITHOUT THE REST, which is the row that produced the false positive: before the fix
/// this shape PARSED and reported two undefined names, so a `first_error` row alone would have
/// been green on the broken parser.
test "0485: a braced pattern binds with or without the rest" {
  let b = eis_bindings(
    "fn f(x : J) -> Int {\n  guard x is { \"cmd\": [cmd] } else { return 0 }\n  cmd\n}\n",
  )
  assert_eq(b.length(), 1)
  assert_eq(b[0], "cmd")
}

///|
/// SEVERAL KEYS, WHICH IS WHAT `examples/tcp_server_benchmark/main.mbt:98` WRITES, and the row
/// that catches a reader collecting only the FIRST field.
test "0485: every key's value binds" {
  let b = eis_bindings(
    "fn f(x : J) -> Int {\n  guard x is { \"a\": [a], \"b\": [b], .. } else { return 0 }\n  a + b\n}\n",
  )
  assert_eq(b.length(), 2)
  assert_eq(b[0], "a")
  assert_eq(b[1], "b")
}

///|
/// A PLAIN VALUE BINDS TOO, not only the one-element array the corpus happens to use. A reader
/// written only for `[v]` would pass every corpus row and silently bind nothing here.
test "0485: a plain value binds" {
  let b = eis_bindings(
    "fn f(x : J) -> Int {\n  guard x is { \"n\": n, .. } else { return 0 }\n  n\n}\n",
  )
  assert_eq(b.length(), 1)
  assert_eq(b[0], "n")
}

///|
/// A NESTED ARRAY PATTERN BINDS EVERY ELEMENT, WHICH IS THE ONLY SHAPE THAT CAN TELL NESTED
/// TRACKING FROM FLAT TRACKING.
///
/// The first draft of this row was `{ "m": [[inner]], .. }` and it was VACUOUS: with a single inner
/// name, a reader that sets `in_value = true` on `[` and clears it on the first `]` collects
/// `inner` just the same, so the row stayed green against exactly the mutation it was written for.
/// M3 survived and reported it. The evidence a row is vacuous is not that it is green -- it is
/// that you cannot say WHICH thing would make it red.
///
/// TWO sub-arrays is that shape: nested tracking binds both, flat tracking clears the flag at the
/// first `]` and loses the second. No corpus writes this either -- the corpus binds a one-element
/// list -- which is why the row has to be synthetic to exist at all.
test "0485: a nested array pattern binds every element" {
  let b = eis_bindings(
    "fn f(x : J) -> Int {\n  guard x is { \"m\": [[a, b]], .. } else { return 0 }\n  a + b\n}\n",
  )
  assert_eq(b.length(), 2)
  assert_eq(b[0], "a")
  assert_eq(b[1], "b")
}

///|
/// THE KEY IS NOT A BINDING. This is the row the whole `in_value` discipline exists for.
///
/// `{ k: [v], .. }` puts a NAME where the quoted shape puts a string. Collecting it would invent
/// a binding for a name the pattern never introduces -- a false finding manufactured out of a
/// key, in a construct whose entire purpose is to stop manufacturing findings. The toolchain
/// REJECTS this spelling anyway (4028 on a `Json` subject), so reading it at all is a recorded
/// MISSED error; what is NOT acceptable is reading it as though it bound the key.
test "0485: an unquoted key does not bind, its value does" {
  let b = eis_bindings(
    "fn f(x : J) -> Int {\n  guard x is { k: [v], .. } else { return 0 }\n  v\n}\n",
  )
  assert_eq(b.length(), 1)
  assert_eq(b[0], "v")
}

///|
/// A REST AND AN EMPTY BRACE BIND NOTHING, and say so rather than returning whatever the scan
/// happened to collect.
test "0485: a bare rest and an empty brace bind nothing" {
  assert_eq(
    eis_bindings("fn f(x : J) -> Int {\n  if x is { .. } { 1 } else { 0 }\n}\n").length(),
    0,
  )
  assert_eq(
    eis_bindings("fn f(x : J) -> Int {\n  if x is {} { 1 } else { 0 }\n}\n").length(),
    0,
  )
}

///|
/// THE DELIBERATE NON-FIX: `let { "cmd": [cmd], .. } = x` is NOT read.
///
/// `moon check` refuses it -- 0011 `partial_match`, a `let` pattern has to be irrefutable -- so
/// reading it would be a MISSED error, and it is a different reader anyway. This row exists so
/// that the choice is pinned: someone generalising the `{` arm to the destructuring reader would
/// turn this red, and would be trading a conservative refusal for accepting code the compiler
/// rejects.
test "0485: a let destructuring rest pattern is still not read" {
  let r = @parser.parse(
    "fn f(x : J) -> Int {\n  let { \"cmd\": [cmd], .. } = x\n  cmd\n}\n",
  )
  assert_true(r.first_error > 0)
}

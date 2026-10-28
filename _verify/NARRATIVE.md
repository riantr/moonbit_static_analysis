# Increment narrative

Extracted from `_verify/release.ps1` by `_verify/_split_release_narrative.ps1`.
Nothing here is executable and nothing here is an expectation: `release.ps1` does not
read this file. It is the record of what each increment was WRONG about, what it was
settled against, and what the evidence was -- the part a future reader needs and cannot
reconstruct from the diff alone.

It lived inside the release script because that was the only file being read at the
time. At 0470 the script measured 1811 lines with 262 of them code: 84% narrative, and
1270 contiguous lines of it between the corpus stage and the pin table. A release entry
point nobody can skim is not an entry point.

Newest first would need re-sorting on every increment, so this is chronological, the
order the blocks were written in. The live caveats that bear on the pin table itself
stayed in `release.ps1` next to the table.

---


## 0.4.30, 0440: a `.mbti` `suberror` body declares value constructors


ONE PREDICATE, and it was the largest single false-positive source in the
project. `parse_iface` set `in_ctor_body = matched == "enum " && d > 0`, so a
braced `suberror` body was matched and descended into -- its member types were
collected -- and its member NAMES were discarded.

proton's OWN generated interface says, at `pkg.generated.mbti:68`,

    pub(all) suberror AppConfigurationError {
      InvalidSetting(name~ : String, message~ : String)
    }

and `collect_iface_symtabs` already reads the target's own tree, the target's
root being `iface_dirs[0]` in `sa/main.mbt`. `InvalidSetting` was written down
in the file being scanned and was still reported as having no visible binding.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable 12 -> 12   parsed 227 UNCHANGED
  proton           actionable 78 -> 12   parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

80 actionable findings across the six corpora became 24. proton's drop is 66,
larger than the 58 the re-rank counted before the change, because 0439's 15
catch-body findings were the same shape -- `err => raise MalformedJson(..)` --
and were waiting on this same harvest.

WHY IT WAS INVISIBLE FOR SO LONG, which is the part worth keeping. The MAIN
PARSER already harvested suberror bodies (`Parser::skip_decl`: `what == "enum"
|| what == "suberror"`), so a variant used in the file that DECLARES it always
resolved. proton's `.mbti` files carry 30 braced suberror bodies and 0
body-less ones, so no rare spelling ever showed up as a discrepancy. Only the
CROSS-FILE path was broken, which is why the symptom was false positives on
correct code rather than unreadable files -- and why reading more files, the
move that has fixed every blocker so far, could never have fixed this one.


## 0.4.31, 0441: two top-level functions of ONE NAME shared one table


A TABLE KEYED BY A NAME THAT IS NOT UNIQUE. `WalkResult.fn_bindings` was a
`Map[String, Array[Binding]]` keyed by `f.name`, and BOTH consumers looked a
function's declarations up by that name -- the walk at pass 3 and, separately,
`Infer::run_fn` in the type lens. Two top-level functions of one name therefore
shared ONE table and the second `set` overwrote the first, so every function of
that name was analysed against the LAST one's parameters.

It is now an `Array` parallel to `fns`, indexed by position, and `run_fn` takes
its bindings as an argument because the position is the caller's to know. There
is no longer any by-name lookup to get wrong.

`#cfg` IS HOW REAL CODE REACHES THIS, AND IT IS NOT THE CAUSE. MoonBit allows
two top-level functions of one name when `#cfg` gates them per platform, and
`Lexer::lex_attribute` deliberately emits NO token for an attribute, so both
variants are analysed together -- a stated fidelity cost, not an accident. The
regression test has NO `#cfg` in it at all, because the defect is the key and
not the attribute. `#cfg` appears 689 times across 99 async files: that is how
real code reaches the defect, not what causes it.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable 12 ->  7   parsed 227 UNCHANGED
  proton           actionable 12 -> 10   parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

24 actionable across the six corpora became 17, and `parsed=` did not move on any
of them -- which is the acceptance criterion here, because this was a change to
how findings are ATTRIBUTED, and a change that lowered one corpus while raising
another would be a regression wearing a fix's clothes.

WORTH KEEPING: this gate failed its FIRST run with all four mutations KILLED.
M2 and M4 named the test that was supposed to pin `run_fn`'s own by-name lookup,
and that test did not go red -- a guard claiming coverage it did not have,
written with a source in which mistyping a parameter could not show up. The test
was rewritten rather than the claim re-anchored onto something that did go red,
and the rewrite was proved green on clean code AND red under both mutations
before the gate was re-run. The four kills are the SECOND run. The whole account
is in `mutate_0441.ps1`.


## 0.4.32, 0442: `noraise { .. }` is a handler block, not a name


FOUR FALSE POSITIVES ON CODE `moon check` ACCEPTS, and the shape of the fix was
not the one the findings suggested. proton `facade_identity.mbt:99` and `:136`,
`protocol_wbtest.mbt:5`, and async `network.mbt:68` all reported
`undefined name 'noraise'`.

THE GRAMMAR IS SETTLED BY THE COMPILER, `_verify/settle_0441_noraise.ps1`, 8/8
as predicted with the positive control green: `noraise { pattern => body }` is
a postfix handler block on a COMPLETED `try ... catch`. A `try expr noraise {..}`
with no catch is REJECTED, the arm list is `catch`'s grammar, an empty block is
rejected, and the pattern binds the base's RESULT value. Nesting the production
inside the existing `catch` arm is therefore faithful grammar rather than a
convenient placement, and it cannot swallow a user's own `noraise` function.

THERE ARE TWO PARSER PATHS AND THE FINDINGS LIVE IN THE SECOND ONE, which cost
most of the increment. `parse_postfix_from` reads the postfix `catch`; the
statement-level `try` is read by the PREFIX reader and its catch loop ends in
`skip_braces`. The first change taught the postfix path `noraise`, and the
result was a fully GREEN suite with a COMPLETELY UNCHANGED corpus -- all four
findings still present. A green suite is not evidence that a corpus finding
moved; the two are separate measurements and only the second is the claim.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  7 ->  6   parsed 227 UNCHANGED
  proton           actionable 10 ->  7   parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

17 actionable across the six corpora became 13, with `parsed=` unmoved
everywhere. The statement-level block is CONSUMED but not analysed, deliberately
and consistently with the lines above it: that branch is the un-analysed `try`,
its body is already skipped and `note_skip` already put a hole in the frame, and
reading the `noraise` arms alone would find reads in a block whose sibling
catch block is deliberately unread.


## A HARNESS DEFECT THIS GATE FOUND, WHICH AFFECTS EVERY GATE


Gate 0442 reported five of five KILLED and still reported MUST-RED MISS on all
five, naming as evidence the very tests that had gone red. The needle and the
captured name were BYTE-IDENTICAL (65 bytes each, same hex).

The cause: `mutate_lib.ps1` matched with `-like`, and PowerShell's `-like` runs
the PATTERN through escape processing, where the backtick is the escape
character. A needle containing a backtick therefore cannot match a name
containing the same backtick -- and this suite's test names are full of them,
because the doc comments are markdown. Bisected on the failing needle: a
30-character prefix with no backtick matched, 40 characters with one did not.
`-like` also treats `[` `]` as a wildcard set and throws on an unbalanced one,
so a bracketed test name could crash the harness rather than merely miss.

Rule 6 asks a SUBSTRING question and was being answered with a PATTERN matcher.
It is now an ordinal `IndexOf`, which is that question. All 27 gates were
re-checked: no gate relied on wildcard behaviour, and the one `MustRed`
containing a `?` (0430's `f(x?)`) is a literal in that test's name, so it
matches exactly.


## 0.4.33, 0443: `nobreak { .. }` is a postfix block on a LOOP


One false positive, and the smallest increment in a while: proton
`internal/bridge_admission_test/main.mbt:20` reported `undefined name
'nobreak'` on code proton 0.3.4 compiles.

SETTLED, not assumed -- `_verify/settle_0443_nobreak.ps1`, 10/10 with the
positive control green, after three corrections to the probe itself:

  - it is a postfix on a LOOP, and the compiler REJECTS `expr nobreak { .. }`
    with no loop at all, so matching the keyword loosely would accept programs
    the compiler refuses.
  - it is accepted on `while` AND `for`, so the wrap is applied to all three
    loop forms. The corpus site happens to be a `while`, so a `while`-only
    parser would have passed the corpus measurement while being wrong.
  - the body is a STATEMENT LIST: `nobreak { 1 }` is rejected 4139, a value in
    statement position cannot be dropped. A different shape from `noraise`,
    which takes an arm list.
  - an EMPTY `nobreak { }` is ACCEPTED, unlike `noraise { }`. The two are easy
    to assume identical and are not, and a parser copying `noraise`'s "at least
    one arm" rule would reject valid MoonBit.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  6 -> 6    parsed 227 UNCHANGED
  proton           actionable  7 -> 6    parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

13 actionable across the six corpora became 12. async is UNCHANGED and that is
the expected result rather than a disappointment: it carries 34 `nobreak` lines
and every one of them was already blocked or already excluded. A census number
is not a finding count -- the same lesson `noraise` taught at 4x the size.

THE NODE NEEDS FOUR ARMS AND THE FIRST DRAFT HAD ONE. `walk_stmt` learned
`SNoBreak`, and the suite's two `for` tests then failed with `no visible
binding for 'x'` and `no visible binding for 'i'` -- the FOR BINDERS, not
`nobreak`. There are two binding collectors, not one: `collect_fn_bindings` for
a function's own declarations and `collect_top` for the module frame, and both
have a `_ => ()` catch-all, so the compiler said nothing about the missing arms.
A top-level `for` executes at module level and so puts its binder there. M4 and
M5 pin the two collectors separately.


## 0.4.34, 0444: a bare LOWERCASE `is` pattern head is a BINDING


Six actionable findings, async 6 -> 1 and proton 6 -> 5, `parsed=` unchanged on
all six. Twelve across the six corpora became six.

SETTLED, not assumed -- `_verify/settle_0444_is_head.ps1`, 9/9 with BOTH the
positive control and a deliberately-broken canary green:

  - `if probe() is err && err != 0 { err }` COMPILES: a lowercase head BINDS,
    so it is not a constructor test and must have a binding.
  - `if opt() is Some && Some != 0` is REJECTED. Uppercase is a constructor
    test, and "a function compared with an integer" is the only reading that
    explains the rejection. So case is not a heuristic, it is the grammar.
  - an unused head binding AND an unused payload binding are both LEGAL, and `_`
    binds nothing. `is St::Shutdown` binds nothing either.

THE PROBE'S FIRST DRAFT WAS WRONG IN A WAY THAT WOULD HAVE BEEN MISREAD. It
used an `Int` base with `Some`/`Err`, so three cases failed 4014 for a plain
Int-vs-Option mismatch and would have read as "uppercase is rejected". The fix
was a second `opt() -> Option[Int]`, NOT a revised expectation. A failing
positive control means fix the prelude, never the expectation.

THE CORPUS SYMPTOM AND THE ISOLATED SYMPTOM WERE TWO BUGS' FINGERPRINTS FOR ONE
CAUSE. 0444 reported `unsupported operand types for '!=': 'fn err (signature
not read)' and 'int'` in async schannel.mbt -- NOT `undefined name 'err'` --
because something else named `err` is in scope in that package and wins. An
isolated reproduction reports `undefined name 'err'`. Two symptoms, one cause,
and only the isolated form points at the parser. The shape-based re-rank would
have filed 0444 under the TYPE lens, and the type lens was already correct.

BINDING THE HEAD INTRODUCED A NEW FALSE POSITIVE THAT THE SETTLE CAUGHT.
`Walker::bind` puts the name on the audit list, so an unused `is` head binding
reported `local variable 'err' assigned but may not be used` -- a false
positive, `b_lower_unused` ACCEPTED. `EIs` therefore uses `bind_pattern`, which
never touches `self.orders[fi]`. That also fixes the PRE-EXISTING payload half
(`is Some(v)` with `v` unread), so the fix is strictly an improvement on both
halves rather than a trade between them.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  6 -> 1    parsed 227 UNCHANGED
  proton           actionable  6 -> 5    parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

GATE 0444: 2 KILLED (M1 the parse, M3 the walk), 3 declared SURVIVED with a
measured argument -- M2/M4/M5 are green because `bind_pattern` never reaches
the audit list (so no `UnusedLocal` can appear) and `Infer::EIs` seeds a
spurious name as `TUnknown`, i.e. resolved-and-unknown rather than unresolved,
which can only SUPPRESS a type finding. Both mutations are quieter; a
suppressed finding is not observable in this tool's output. Declared honestly
as expressing the settled grammar while NOT being load-bearing against today's
lenses -- they would become so the moment a lens began auditing `is` bindings.

AND THE SAME ARGUMENT, ONE SCALE UP: 0444 COST FOUR PINS THAT WERE STILL
LOAD-BEARING. This is the part that must not be buried in a gate log.

Moving `EIs` from `bind` to `bind_pattern` closes the unused-local audit for `is`
bindings: `bind` appends to `self.orders[fi]`, `bind_pattern` never touches it.
Every guard inside `pattern_binding_at` was observable ONLY through that audit,
because the phantom names each one prevents -- `true`, `Os`, `core`/`Role`/
`Checkbox`, `Gone`/`PageUnavailable` -- are never READ anywhere. A name that binds
but is never read resolves (no `UndefinedName`), and `Infer::EIs` seeds it `TUnknown`,
which can only suppress a type finding. So four pins that had been load-bearing
since 0.4.19/0.4.21 stopped being load-bearing:

    0419 M1  is-pattern keyword test          646/646 green
    0421 M6  qualified-path rule removed      646/646 green
    0421 M7  nested-constructor rule removed  646/646 green
    0421 M8  or-pattern depth rule removed    646/646 green

The move itself is REQUIRED, not a trade: the settle measured 9/9 that an unread
`is` head or payload binding is legal MoonBit, so auditing them would be a false
positive on correct code. All four guards remain in the source and remain
semantically right; none of them is load-bearing against today's lenses.

WHAT PROVES IT IS THE CHANNEL AND NOT A STALE ANCHOR: gate 0421 M5 anchors on the
SAME `depth >= 2` expression, survives the same parser change, and still KILLS,
because its symptom is `UndefinedName` -- it leaves `error` unbound in
`is Some(Os(error))` where `error + 1` reads it. Same file, same change,
different channel, opposite outcome.

GATE 0436 ALSO BROKE, for the ordinary reason, and is re-anchored rather than
retired. 0444 added `qualified = true` inside the `::` consumption loop and a new
block between `let binding` and `if self.at(TLParen)`, so all four Find strings went
absent and the preflight aborted before a suite ran. M1 and M4 additionally stopped
being VALID mutations: they deleted that loop, and the loop now sets a variable the
head-binding decision reads, so deleting it no longer compiled at all (COMPILE-ERR,
no `Total tests:` line -- a mutation that cannot build measures the compiler, not
the guard). Both now point the loop condition at a token a qualified head never
sits on: same broken behaviour, still builds. Anchors shortened to the two lines
carrying `qualified = true`, unique to this one of the three qualified-path readers,
which is the point -- the previous anchors named surrounding prose and that is what
0444's growth invalidated. 0436 is back to 3 KILLED + 1 declared survivor.

GATE 0436 M4 IS DUPLICATE M1 UNDER A SECOND NAME, which predates 0.4.34 and is
recorded rather than quietly rewritten: both mutations stop the `::` loop from
running, and they differ only in which named test they pin. The "consumed AFTER
the payload test" in its title is not what its Find/Repl pair expresses -- a real
ordering mutation would MOVE the loop below the `TLParen` branch. Both still KILL,
so nothing is unprotected today; the duplication is a genuine weakness.


## 0.4.35, 0445: the builtin-method table could not see GENERIC methods


The defect was in the GENERATOR, not in the analyzer. `tools/gen_builtin_methods.ps1`
extracted methods with a pattern demanding the name come straight after `fn`:

    (?m)^\s*(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)

MoonBit's generated interfaces put type parameters there --
`pub fn[K : Eq] Set::add(Self[K], K) -> Unit` -- so every generic method of every
builtin type was invisible. Measured against the toolchain in hand the old pattern
produced ZERO hits on `<core>/set/pkg.generated.mbti`, which alone declares 32 of
them, and missed 445 names across the tree.

WHY IT STAYED INVISIBLE. `Array::add` was never reported on any corpus only
because real MoonBit writes the METHOD form `a.add(x)`; the qualified form
`Array::add(a, x)` is mostly used for constructors. That is the shape the one
finding had: `Set::from_array`, async 0.22.4 `src/http/send.mbt:37`, reported
`undefined function` on code `moon check` accepts.

AND IT IS NOT A DECLARED `fn` AT ALL. `#alias(from_array)` sits above
`type Set[K]`, so the DIRECTIVE is where the name is written. The generator now
carries pending aliases to whatever declaration follows, and keeps only
identifier-shaped ones -- `#alias("_[_:_]")` is a quoted operator and is not a
qualified name this table can hold. 140 such names; 1265 in the table against 656
before, VERIFIED A STRICT SUPERSET with none lost.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  1 -> 0    parsed 227 UNCHANGED
  proton           actionable  5 -> 5    parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

Six actionable across the six corpora became five. proton is UNCHANGED and that is
the expected result, not a disappointment: its remaining five are `undefined name`
and `undefined function` on names that are not builtin methods at all
(`CookieWaiting`, `@async.CondVar::Cond`), so no amount of table can move them.

THE 18 `T::to_json` NAMES, AND A HYPOTHESIS THAT WAS WRONG. Those names appear in
NO `pkg.generated.mbti` in the tree, and the table had been generated at
moon 0.1.20260920 against a toolchain that is no longer installed, so the reading
was "stale, drop it". They are not stale: `Bool::to_json(true)` COMPILES today.
They are intrinsic members, the same category as `Array::make`, which is why the
generator carries a hand-settled intrinsic list. They are listed there now, and
gate 0445's M3 exists so that dropping them again is a red suite.

The sweep that "confirmed" it was worse. Calling `T::to_json(1)` for all 45 bare
types reported 35 as nonexistent, and every one of those was a TYPE mismatch,
because `1` is not a `Bool`. A probe wrong about its own prelude produces a
clean, confident, entirely false answer; the settle survived it only because a
correctly-typed case sat beside the malformed one. Second time this repository
has been caught by it, and both times the fix was the PRELUDE.

NOT ESTABLISHED, and deliberately claimed nowhere: whether the `.mbti` fn-head
FORMAT changed between those two toolchains, or whether the generator was always
blind to generic heads. The old toolchain is not installed. The claim here is the
gap against the toolchain in hand, and nothing earlier.

GATE 0445: 4/4 KILLED, every named test confirmed, every restore byte-identical.
M1 generic head, M2 alias of a type constructor, M3 name no interface declares,
M4 alias of a METHOD. M4 is pinned on table MEMBERSHIP rather than behaviourally,
because `Array::clone` is a deprecated alias of a deprecated spelling that no
corpus writes -- a behavioural test for it would have meant inventing a call site
no measurement produced.

## 0.4.36, 0446: a `#|` closer is a BLANK one, and the lexer was eating it


Three of the five remaining actionable findings were ONE predicate, and the cause was not
a missing declaration. proton 0.3.4 `facade_types.mbt` declares `CookieWaiting` and
`CookieCompleted` at lines 589-594, but the scanner read that file only to line 246.
`region_line` is `first_error_line`, so a file that hit an error was cut at the error and
contributed NOTHING to the cross-file symtab -- and the sibling that USES those names was
told they were undefined. Three findings, three files, one predicate.

WHY THE FILE WAS CUT. `lex_block_string` demanded a `#|` with only whitespace BEFORE it
on its line. The CLOSER is a `#|` with nothing AFTER it, so it satisfied that demand and
was consumed as content; the block never closed and the lexer went on reading it as code.

THE RULE, SETTLED BY VALUE, not by acceptance. `moon check` accepts EVERY shape -- all
nine probes passed it -- so it measures nothing here and was not used to settle it.
`moon run`'s printed string settles it, in `_verify/settle_0446_block_string.ps1` (9/9,
positive control green). A closer is a LINE-LEADING `#|` whose rest of line is blank;
trailing spaces are fine and it may be indented. Every other `#|` is a content segment.
Segments are trimmed and joined by a SINGLE SPACE, and the closer contributes an empty
final segment, hence the trailing space. End of input also closes, with no trailing empty
segment, and is still reported. A non-blank line without `#|` ends the block as CODE with
no unterminated report; a blank line does not.

THE OLD HEADER WAS WRONG, AND IT IS RECORDED RATHER THAN DELETED. It claimed the closer
needs whitespace BEFORE it, and listed `#|AAA\n#|BBB trailing -> "AAA\nBBB trailing"` as a
measurement. Both are false: trailing text is CONTENT, and the join is a space, not a
newline. Its one correct claim -- that the closer may be indented -- had NO test of its
own and survived only because an unrelated test happened to indent one.

  moui             actionable  0 -> 0    parsed 590 -> 591
  moonbit_labeler  actionable  0 -> 0    parsed  25 ->  26
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  0 -> 0    parsed 227 -> 253
  proton           actionable  5 -> 2    parsed 103 -> 106
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

Five actionable across the six corpora became two, and 31 more files parse fully -- the
sum of those `parsed` deltas -- with none lost anywhere. NOT A GENERAL TRUNCATION FIX:
178 other truncated files across the corpora have other causes. The
`unterminated block string literal` report itself fired on only 4 files, and that is NOT
the same count as the 31 extra parses; a file cut here can stop short without ever
producing that report. This note does not claim the two sets are identical.

GATE 0446: 5/5 KILLED, every named test confirmed, every restore byte-identical. M1/M3
first came back COMPILE-ERR -- they removed a binding still read later (`j`), or made
`cur` an unused `let mut` -- so what they were measuring was the COMPILER. Both were
corrected to compile, with the failure recorded in their `Prove`.

M2 is the one worth reading. It indents the closer, and no test had ever done that: seven
tests for this construct all put the closer at column 0 because they were copied from each
other, so the rule was pinned only by an UNRELATED test that happened to indent. Two tests
were added and M2 re-pointed at them.

WHAT IS LEFT, and it is not this predicate: proton `facade_notification.mbt:12,14`,
`undefined function '@async.CondVar::Cond'` twice -- a qualified path through
`pub using @cond_var {type Cond as CondVar}` in async's `pkg.generated.mbti`.

WHAT THE RELEASE GATE CAUGHT IN 0446, AND IT WAS IN 0446'S OWN CODE. The first
run of this file failed at stage 2 with four `0020` deprecation warnings: the new
`lex_block_string` wrote `cur.to_string().trim().to_string()`, and `StringView::to_string`
is deprecated in favour of `to_owned`. `--deny-warn` turns those into errors, so the
suite stopped before a single mutation gate ran. All four sites now say `to_owned()`.

A GREEN TEST TALLY IS NOT `--deny-warn` CLEAN, and the reverse is also true.
During development this same code reported `moon test --target wasm` at 655/655;
under this suite the same package exits 1 and prints NO tally at all. The cause
of THAT discrepancy is NOT ESTABLISHED and is not claimed here.

0.4.37 supplied the cleaner half of the same point, in the OPPOSITE direction: a
`local` binding in a new test file left `moon test --target wasm` reporting
662/662 PASSED while `moon check --deny-warn` failed it -- `local` is a MoonBit
reserved keyword and the test runner does not treat that as fatal. Neither stage
is a substitute for the other in either direction, which is the actual reason
this suite runs both. A suite running only the tests would have shipped four
deprecation warnings; a suite running only the linter would have shipped a
reserved-keyword binding inside the test that guards the re-export link.

Counted as shipped: wasm 657/657 (the two tests M2 forced into existence are in that
657), js 585/585, wasm-gc 585/585. js and wasm-gc run fewer because `src/sa` needs the
async runtime and degrades off wasm. GATE 0446: 5/5 KILLED.


## 0.4.37, 0447: a RE-EXPORTED type carried its name but not its MEMBERS


These were the last 2 actionable findings in existence across the six corpora.
proton 0.3.4 `facade_notification.mbt:12,14` writes

    gate: @async.CondVar::Cond(),

and was reported `undefined function '@async.CondVar::Cond'` on both lines, on
code the toolchain accepts. async 0.22.4 re-exports the type under that name --
`pub using @cond_var {type Cond as CondVar}`, `src/pkg.generated.mbti:111` -- and
`@cond_var/pkg.generated.mbti` declares `type Cond` with `pub fn Cond::Cond() -> Self`.

BOTH HALVES WERE ALREADY IN THE TABLE. The re-exported NAME, because the `using`
branch pushed it into `declared`; and `Cond::Cond`, because `@cond_var`'s own
interface is read and its signatures are bare. Nothing CONNECTED them.
`has_value` tried the exact key and then `unqualified`, so `@async.CondVar::Cond`
became `CondVar::Cond`, found nothing, and reported a name written down two files
away. It looked like a missing declaration and was a missing LINK.

THE RULE, settled WITH THE TOOLCHAIN in `_verify/settle_0447_condvar_alias.ps1`
(6/6, three negative controls firing). A constructor IS callable through an
aliased type re-export, CROSS-PACKAGE -- and a name that does not exist is STILL
rejected through it: `[4029]` for a missing member, `[4032]` for a missing type.

THAT SECOND HALF IS THE POINT, and it is why this is a link and not a
suppression. An earlier version of this fix -- silence every `@mod.X::m` that
reaches a re-exported name -- ALSO takes these two findings to zero, on all six
corpora, with a green suite and nothing whatever to tell the two apart. Gate
0447's M2 is that version, and the control test is what kills it. The settle
exists because the corpus cannot make that distinction and the test can.

  moui             actionable  0 -> 0    parsed 591 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  26 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  0 -> 0    parsed 253 UNCHANGED
  proton           actionable  2 -> 0    parsed 106 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

TOTAL actionable across the six corpora is ZERO, and `parsed=` did not move on
any of them -- so this is a false positive removed, not a corpus traded. notices,
unreliable and withheld are identical on all six too; only proton's `total`
falls, by exactly the 2 findings that were wrong.

TWO LIMITS, recorded because they are limits and not because they were reached.
The alias key is the BARE re-exported name, since `collect_iface_names` reads
interface text and is not told which module it came from -- two modules
re-exporting different types under one name would collide, first-one-wins. And
only the FIRST alias on a re-export line is recorded, because later segments have
already lost their package qualifier to the `{`-strip. The whole table is flat in
exactly this way, so neither is a new shape of limit; neither is a claim that the
mapping is sound, and no corpus here exercises either.

The settle also records two SCAFFOLD facts that cost a wasted run each: `moon.mod`
must declare `source = "src"` or the build plan fails and every case reads ACCEPT,
and a package cannot import its OWN root package. Its first version reported all
three negative controls as ACCEPT for the first reason, and its second did so for
the third -- it normalised the toolchain's output with `replace '\s+', ' '` before
matching `(?m)^Error:`, which destroys the line boundaries the pattern needs. Four
malformed probes in four days now, each of which would have reported the right
answer for the wrong reason.

GATE 0447: 4 KILLED + 1 declared SURVIVED (M5, the redundant bare form: both
callers apply `unqualified` to every candidate and `unqualified("@cond_var.Cond::Cond")`
IS `Cond::Cond`, so the extra entry cannot be reached). wasm 662/662, js and
wasm-gc 590/590 (up 5 on each — the five 0447 tests live in `moonfiles`, which is
not a `src/sa` package, so they run on every target). Self-scan 88/88 actionable 0,
up one file and six notices over 0.4.36: the new test file.

## 0.4.38, 0449: an EXTERNAL fn binding, and a TUPLE STRUCT that read the next declaration's brace


TWO DEFECTS IN ONE INCREMENT, because fixing the first one found the second.

DEFECT A. `fn f() -> T = "module" "symbol"` -- a `fn` whose body lives in another
language is DECLARED, not defined. The parser finished the signature, found `=`
where it wanted `{`, and reported `expected '{'`: the parser naming a token that
was never the problem. That report is the file's `first_error`, so the file went
NOTPARSE and everything after the declaration went unread. Settled with the
toolchain in `_verify/settle_0449_ffi_decl.ps1`, 7/7 with BOTH negative controls
firing; all three shapes (no parameters, single-line list, multi-line list) are
ACCEPTed by `moon check`. Cost on moui 0.1.12: FOUR of the seventeen files
`_verify/diagnose_moui_truncations.ps1` reports, the largest single shape there.

DEFECT B. `struct Name(T)` -- a tuple struct has no body, so the braced skipper
scanned forward for the `{` that opens one and took the NEXT declaration's brace.
On async 0.22.4 `src/process/cancellation.mbt` that brace belongs to an `if`, so
the `let` and the `if` went with it and `else` / `SIGTERM` were reported as
undefined variables -- two false positives on correct code. Settled in
`_verify/settle_0449b_tuple_struct.ps1`, 8/8 with three negative controls.

THREE HYPOTHESES WERE FALSIFIED before that one, and the record is worth more
than the fix: the `is` pattern, a qualified receiver, and a cross-package
`@pkg.field` receiver each looked like the cause, and each probe varied the `if`.
The cause was never in the `if`. It was that what came BEFORE the `if` had no
`{` to stop at.

TWO CLAIMS IN THE OLD GATE PROSE WERE FALSIFIED BY MEASUREMENT, and both are
corrected in place in `_verify/mutate_0449.ps1` rather than quietly dropped.

  1. `extern_fns` does NOT suppress `undefined function`. It is consumed at
     exactly one place, `walk.mbt:1170`, guarding `audit_frame` -- so what the
     registration buys is `UnusedParam = 0` on a header-only fn whose body was
     never read. Dropping it leaves undefined-function findings untouched and
     takes a clean external fn from no findings to `UnusedParam = 1`. That is
     the whole trade the fix refuses: without it, four unread files would have
     become four files with a false positive each.
  2. Consuming only the FIRST of the two strings is unobservable. Nine fixtures
     -- an external binding followed by a `fn`, a `let`, a braced struct, a tuple
     struct, a second external binding, with no blank line, plus two controls --
     give byte-identical findings, because a leftover string literal is a
     well-formed top-level expression statement. M2 is now a declared SURVIVED.

AND ONE FIXTURE WAS WRONG IN A WAY WORTH KEEPING. The M4 fixture had a struct
with ONE field, which absorbs the leftover line without ever reporting a name, so
the named test stayed green while the suite was red. Two fields is what makes it
discriminating. Separately, a fixture putting a `fn` after the tuple struct was
rejected by rule 6 and named the test that had actually gone red: `skip_decl_braced`
breaks at a top-level `fn` (`parser.mbt:802`), so a following FUNCTION is never
swallowed. The damage needs a `let ... = if` between the struct and the brace --
which is what the corpus writes.

  moui             actionable  0 -> 0    parsed 591 -> 595 (+4, exactly the FFI files)
                         unreliable 244 -> 144, notices 4120 -> 4123, total 4364 -> 4267
  async            actionable  0 -> 0    parsed 253 -> 274 (+21)
                         unreliable 2208 -> 1193, notices 1081 -> 1234, total 3289 -> 2427
  the other FOUR corpora byte-identical.

The async actionable=0 is the load-bearing line and it was NOT free. The FFI fix
alone took it 0 -> 2, both false positives revealed by 21 newly-readable files
rather than introduced by the change. "Pre-existing defect merely revealed" is a
real distinction and still not a shippable one, so the tuple-struct defect went in
the same increment instead of leaving actionable above zero.

GATE 0449: 5 KILLED + 1 declared SURVIVED (M2, above), every named test confirmed
red, every restore byte-identical, baseline 600/600.

## 0.4.39, 0450: a `fn` in STATEMENT position is two different things


A lambda whose value is a branch:

    paint: if disabled {
      fn(_ctx) { { commands: 1 } }
    } else {
      fn(_ctx) { plan0() }
    }

`parse_block` routed EVERY `fn` to the declaration path, so the lambda fell into
`parse_fn_signature`, which asks for a name, found `(`, and reported
`expected function name` -- at a token that is neither unexpected nor unnamed, so
the message sent a reader hunting a malformed function header that does not
exist. That is moui 0.1.12 `modifier_env.mbt` cut at `fn(_ctx) {`.

ONE CONDITION, and the token after `fn` is the whole discriminator: a NAME means a
local function declaration, `(` means a lambda expression. It only ever surfaced
in a BRANCH because expression position always worked -- `let f = fn(x) { .. }`
reaches `parse_primary`'s lambda branch -- and a lambda that is the tail of an
`if` branch is a block STATEMENT, the one place the two forms share a token and a
cursor.

Settled in `_verify/settle_0450_shapes.ps1`, 10/10 with THREE positive controls,
two of which exist because malformed preludes built first: a wrong field type made
nine agreeing REJECT(4014) rows, and the corpus's QUOTED keys reject against a
struct too. Fix the prelude, never the expectation.

  moui     parsed 595 -> 596 (+1, exactly modifier_env.mbt)  unreliable 144 -> 131
  async    parsed 274 UNCHANGED                              unreliable 1193 -> 1201
  proton   parsed 106 UNCHANGED                              unreliable 1077 -> 1103
  the other three corpora byte-identical.  actionable 0 on all six.

THE UNRELIABLE RISE IS NOT NEW FINDINGS, and saying so required a measurement
rather than an argument. `_verify/measure_0450_unreliable.ps1` diffs the scan of
both corpora before and after the fix. Every differing line is a CONTROL line:

    async  task_group.mbt      read up to line 50, 35 after -> 47 after
    async  process/redirect.mbt                     57 after -> 32 after
    async  io/data.mbt                              6 after ->  4 after
    proton six files, +2 to +9 lines each

Six files per corpus now read FURTHER, so more of an already-unread tail is seen,
and the extra findings land in NOTPARSE files where they are already unreliable or
withheld. NOT ONE new finding message appears anywhere. The defect's own
signature is gone: `1x expected function name` leaves async's withheld tally, and
proton's `2x unexpected token ')'` with it.

THAT DIFF HAD TO BE REWRITTEN ONCE, because the first version compared only the
printed `LINE:COL - error:` lines and reported added=0 removed=0 on both corpora
-- while the SUMMARY beside it said `unreliable` had moved 1193 -> 1201 and
1077 -> 1103. Byte-identical lists and a moving count cannot both be true. The
findings that moved are printed as control lines (PARTIAL read-depth, the withheld
tally), not one line per finding. A probe that engages its instrument and prints a
confident zero is worse than one that prints nothing, and that is the whole
hazard: `actionable = 0` on its own would have "confirmed" this change while
measuring nothing about it.

GATE 0450: 3/3 KILLED (M1 the original, M2 the inversion, M3 the condition
deleted outright), every named test confirmed red, every restore byte-identical.
M2 and M3 turn the same test red for different reasons, and only M3 tells "I
flipped it" from "I removed it".

GATE 0452: the three remaining `{`-cut moui files. The cause was NOT a brace.
`parse_struct_fields` reads a braced list and keys every entry by the identifier
before the colon; a map literal with a QUOTED key has no identifier there, so
`peek_name()` returned "" and the whole literal was abandoned. The fix reads a
string key in that position and requires the colon that follows it, because
`{ "a" }` is rejected by the toolchain and must not parse.

THE TWO FORMS CANNOT BE MERGED, and `_verify/settle_0452_quoted_key_map.ps1`
(5/5, with a positive control) is what establishes it. `{ "a": 1 }` as
`Map[String,Int]` ACCEPTS; `{ a: 1 }` as Map REJECTS (4033, 4028); `{ a: 1 }`
as a struct literal ACCEPTS; the corpus declaration verbatim ACCEPTS. So the
quoted form is a map, the unquoted form is a struct, and a fix that let a
string key pass WITHOUT a colon would have silently taught the parser to accept
a program the toolchain rejects.

  moui     parsed 596 -> 599 (+3, exactly the three `{`-cut files)  unreliable 131 -> 105
  labeler  parsed  26 ->  28 (+2)                                  unreliable 319 -> 309
  proton   parsed 106 -> 108 (+2)                                  unreliable 1103 -> 1082
  async    parsed 274 UNCHANGED                                    unreliable 1201 -> 1189
  moonbit_image and proton_contract byte-identical.  actionable 0 on all six.

async is the interesting row: `parsed` did not move, yet 12 findings left the
unreliable bucket and 7 joined notices. Both are expected of this fix and both
are reported here so that neither can later be mistaken for corpus noise -- a
map literal previously read as a struct literal contributed a bogus control
line, and reading it correctly replaces that with real findings on a now-parsed
file. Across all six corpora: parsed +7, unreliable -69, total findings -30.

GATE 0452: 4/4 KILLED (M1 the branch removed, M2 no colon demanded, M3 the value
expression discarded, M4 the string-vs-name discrimination dropped), every named
test confirmed red, every restore byte-identical. Two of the four had to be
re-aimed before they could distinguish anything: M2 was asserted on a failure
COUNT, and under the mutation the fixture still produced two failures, only the
second one different -- so it now asserts the MESSAGE `expected ':'`. M4's
MustRed points at an existing test in another file, because the mutation
destroys the field KEY while `{ a: a }` still parses as a value.
GATE 0453: an anonymous ASYNC function literal in expression position.
After 0452 moui still could not finish reading 9 files, and the largest by-reason
bucket was `4x expected ')'`. That label is about the ARGUMENT of a call, not the
parenthesis -- the parser is downstream of the real failure, which is why the first
reading sent the search towards brackets. Three of the four are one construct:

    launch_async=Some(async fn(request, frame_interval_ms) { .. }),

`parse_atom` had an arm for `TName("fn")` and none for `async`. The short-lambda
named argument on the line ABOVE it parses, which is why those files were PARTIAL
at line 23-24 rather than unparsed at zero.

Settled in `_verify/settle_0453_async_fn_expr.ps1`, 6/6 with a positive control:

    Some(fn(a) { .. })        ACCEPT   <- already read, identical shape
    Some(async fn(a) { .. })  ACCEPT
    the corpus declaration    ACCEPT
    ignore(async)             REJECT(3002) "you may expect `fn`"
    async work()              REJECT(3002)

  moui     parsed 599 -> 602 (+3)   unreliable 105 -> 46   notices 4150 -> 4203
  image and proton_contract byte-identical; actionable 0 on all six.
  The `expected ')'` bucket is GONE from the by-reason grouping, and the
  `unexpected token ','` bucket is 4 -- the three files that were in it, plus
  runtime/app_builder.mbt, which has a SECOND defect behind the first and only
  now shows its own.

THE THREE OTHER CORPORA MOVED AND NOBODY ASKED THEM TO. proton unreliable
1082 -> 1112, withheld 309 -> 321; async notices 1234 -> 1241; labeler withheld
134 -> 136. `parsed=` is UNCHANGED on all three, which is the signature of
"reading further", not of a regression -- and it was checked rather than argued:
proton carries 25 `async fn(` literal sites and async carries 45, so a file that
used to stop at one of them now stops at whatever comes NEXT and has more of its
tail seen. That is the same mechanism 0450 documented, and it is the reason
`unreliable` can rise while `parsed=` holds.

TWO REGRESSIONS OF MY OWN WERE CAUGHT BY THOSE CORPORA, NOT BY THE GATE:

  1. A `fn`-only guard consumed `async fn log(s) { .. }` -- a NESTED
     DECLARATION -- as an anonymous literal, so `parse_block` never declared it.
     labeler withheld 134 -> 136, two files that had parsed became PARTIAL.
  2. The compound guard `at_name("fn") && name_at(p+1) == ""` sent that same
     nested declaration to the `else`, which announced `async without a following
     fn` -- a FALSE notice about legal code. async hit it on all five of its
     nested sites. `else` fires 0 times in all six corpora now.

Neither was visible to `_verify/mutate_0453.ps1`, and the reason is worth
recording rather than fixing: no fixture in the 0453 file contains a nested async
declaration, and a mutation gate cannot see a corpus it was not given. The corpus
is the instrument for that, which is why all six SUMMARY lines are pinned.

GATE 0453: 5/5 KILLED (M1 the arm never fires, M2 the `fn` not consumed, M3 the
body skipped, M4 the `fn` guard dropped, M5 the nested declaration announced).
M3's MustRed was RENAMED TWICE before it could discriminate, and both attempts
were structurally incapable: `UnusedParam` on the literal's own parameters (they
are `let _ =`-discarded, never bound) and a defect inside the body (`parse_block`
returns statements that are thrown away, so nothing inside a function literal
reaches a lens -- for a plain `fn` exactly as much as for an async one). What
works is what reading the body DISCOVERS: a `match` inside it is announced.
GATE 0454: `label?=value` in a call argument -- the member the shorthand family
was missing. After 0453 moui could not finish reading 6 files and the largest
by-reason bucket was `unexpected token `,``:

    let normal = @views.new_control_state_style(
      foreground=@core.Color::black(),
      border?=normal_border,
      radius=0.0,
    )

The complaint named a COMMA, three tokens from the cause. `parse_call_args`
handles two shorthands, both AFTER the argument is parsed -- `f(x~)` at the
`TTilde` test and `f(x?)` at the `TQuestion` test -- and neither is followed by
an `=`. So for `border?=normal_border` the `TAssign` test was FALSE (the next
token is `?`), `p` was restored, `border` was read as a positional name, the
`TQuestion` shorthand consumed the `?` as if the argument ENDED, the comma test
found the `=` that the first test skipped over, and the loop broke.

The `?` CARRIES MEANING, so this is not sugar for `=`. Settled in
`_verify/settle_0454_label_qmark_eq.ps1`, 9/9 with a positive control:

    border?=v   against  border? : Int   ACCEPT
    border?=v   against  border~ : Int   REJECT(4141) "not declared with border? : _"
    border?=                      REJECT(3002)
    border?v                      REJECT(3002)

A `name? : T` parameter has type `T?` -- measured as REJECT(4014) "wanted Int?"
with a bare `7` -- so dropping the `?` would read illegal code as legal. The last
row is what licenses the two-token lookahead: `?` either ends an argument or starts
`?=`, and never prefixes an expression.

  moui     parsed 602 -> 605 (+3)   unreliable 46 -> 23   notices 4203 -> 4209
  proton   parsed 108 -> 109 (+1)   unreliable 1112 -> 1032   notices 1344 -> 1374
  the other four byte-identical. actionable 0 on all six.

proton moved too, and it was CHECKED rather than waved at: it uses `label?=value`
17 times across four files (`facade_builders.mbt` 5, `facade_native_types.mbt` 7,
`facade_runtime.mbt` 4, `facade_event_loop.mbt` 1). `facade_builders.mbt` is also
the file that held the `async fn(context) {` literal 0453 fixed, so it had two
stacked defects and only now resolves. The -80 unreliable is that file's.

The `unexpected token `,`` bucket is GONE from moui and the three files that
resolved are exactly the three `?=` ones. What remains is three files and three
DIFFERENT causes, one each -- the shape a tail of this kind is supposed to have:

    1x  expected ')'             runtime/app_builder.mbt:47
    1x  unexpected end of line   runtime/input_dispatch_result.mbt:13
    1x  unexpected token `:`     backend/macos/macos_services.mbt:406

GATE 0454: 5/5 KILLED (M1 the branch removed, M2 the `=` not required, M3 the
value consumed but not analysed, M4 the `?` dropped from the label, M5 the
lookahead widened to any `?`).

M4's MustRed MOVED FILES and that is the finding. It SURVIVED the first version of
this gate: every 0454 test was written through `@pipeline.run`, asserting findings,
and nothing on the pipeline path READS the label -- `parse_call_args` returns
`(args, labels)`, the labels go into `ECall`, and neither lens consults them for any
finding these fixtures trigger. A blank label changed no count; 623/623 stayed
green. That is a property of the ANALYZER, not of the parser, so the assertion
moved to `src/parser/parser_0454_test.mbt` and reads `ECall`'s third field directly,
the way `parser_0430_test.mbt` already does for `x~` and `x?`. Asserting "the call
parses" passes; asserting a finding count passes; neither is evidence about a label.
0.4.xx -- newline suppression after the BITWISE-OR token. `unexpected end of line`
is 0 occurrences across all six corpora; it was 1 in moui.

ONE TOKEN WAS MISSING. `newline_suppressed_after` listed TPlus, TAmp, TCaret,
TAndAnd, TOrOr, TShl, TShr and every comparison operator, and did not list TBar. So
the lexer emitted TNewline after `|`, `parse_bitor` bumped the `|` correctly, and
the operand parse landed on TNewline and `parse_primary` raised "unexpected end of
line" (parser.mbt:4664).

THE EVIDENCE KEPT POINTING ELSEWHERE, which is the part worth keeping. A sweep for
"trailing binary operators" reports 178 corpus files and 2296 sites and would have
ranked this as the largest available lever; 103 of those are moui files and only 3
moui files fail to parse at all, because `+`, `&` and `||` already continue. And
`input_dispatch_result.mbt` had been carried for several rounds as "a parenthesised
`if` as an operand", which is false -- a parenthesised `if` parses fine. A token's
role is whatever the CONSUMER does with it, and `TBar`'s own comment still said "the
parser never sees one" after `parse_bitor` had started consuming it.

  moui             parsed 605 -> 606 (+1)   actionable 0 -> 0
  moonbit_labeler  parsed  28 ->  28        unreliable 311 -> 294
  moonbit_image    parsed   2 ->   2        unreliable 294 -> 285
  async            parsed 274 -> 274        unreliable 1188 -> 1175
  proton           parsed 109 -> 109        byte-identical
  proton_contract  parsed   4 ->   4        byte-identical

THE 42 FINDINGS THAT LEFT `unreliable` ARE NOT A COVERAGE LOSS, and it was verified
rather than assumed: both builds came from the same tree, one with TBar in the set
and one without, and the per-file comparison found ZERO files read less, one newly
complete (`input_dispatch_result.mbt`) and one read further (labeler). `actionable`
and `notices` are unchanged in every corpus, so what vanished was exactly the class
the analyzer itself flags as "this file was not fully understood".

GATE 0455, 4/4 KILLED with named tests. M4 is the row worth noting: it deletes the
OTHER conjunct of the same `if` -- `closer_ahead` -- and it SURVIVED the first run,
which is how the repository learned that the newline-before-a-closing-bracket rule
had no test pinning it anywhere. That test now exists.

GATES 0456 + 0457, shipped together because 0456 alone breaks the invariant this
file exists to protect.

0456 consumed the `.Type` of a package-qualified `is` head (`@pkg.Type::Ctor`, four
tokens, parser.mbt:3033). moui 606 -> 607; `backend/macos/macos_services.mbt` parses
whole. It also corrects the pin on `parser_0436_test.mbt` that recorded the WRONG
mechanism: it said `peek_name()` is `""` for an `@` head, which is false -- it returns
`"@pkg"`. Both stories predict the same symptom and a different repair, which is the
only reason the disagreement was worth chasing.

0456 BROKE async actionable 0 -> 3 by unblocking `src/fs/watch_test.mbt`, which had
been dying at line 389 on `is @async.TimeoutError`. The file then parsed whole and
three `undefined name 'async'` sites surfaced at once -- a false positive 0457 removed.
So `actionable` could not be pinned between the two increments, which is why they ship
as one commit: a visible parse failure traded for invisible wrong findings is worse
than either alone.

WHY async's `unreliable` ROSE 1175 -> 1248 while `actionable` fell to 0. Honest
re-classification, verified rather than argued. 46 read-past `async fn` sites now mark
their region unreliable instead of silently binding a name. A move that size cannot be
pinned on inference, so `_verify/ab_0456_0457_coverage.ps1` builds BOTH parsers from ONE
tree and diffs how far the scanner reads in EVERY file of all six corpora:

    files in HEAD map 1223 / fixed map 1223
    unchanged 1220   read further 3   READ LESS 0

    async/src/fs/watch_test.mbt          389 -> EOF     (0456 unblocked it)
    async/src/websocket/server.mbt   NOLINE -> PARTIAL 34
    moui/backend/macos/macos_services.mbt 406 -> EOF     (0456)

`watch_test.mbt` moving FROM 389 is the cross-check: 389 is the `is @async.TimeoutError`
line the 0457 comment names as the blocker, so the A/B confirms the comment's own claim
by a different instrument.

THE REACH METRIC, and why it had to be built rather than reused. `FOUND` lines look like
the per-file record and cover only 183 of async's 419 files -- a fully-read clean file
prints `CLEAN`, and one that failed at its FIRST construct prints nothing at all. Keying
the diff on `FOUND` would have dropped 56% of the corpus silently, and every clean file
would have read as "absent" rather than "unchanged". So reach is one state per file:
EOF / a line number / NOLINE, with NOLINE made explicit precisely because it is the
state most likely to MOVE. The map is checked for totality against the files on disk,
and it validates itself twice against the scanner's own accounting:
EOF == `parsed` (275) and PARTIAL + NOLINE == `NOTPARSE` (83 + 61 = 144).

`pins.ps1` exists because these six numbers were once measured by an ad-hoc loop that
returned `files=3675 parsed=2831 actionable=125` for moonbit_labeler and then returned
the IDENTICAL line for moonbit_image. Two corpora cannot agree exactly, so that was a
stale file being read -- and it was caught only by the coincidence of the match. Every
corpus now asserts its TARGET line and its file count against disk before the number is
printed, and any two identical summaries abort the run.

GATE 0457, 3 KILLED / 1 declared survivor. M4 (adding the `bump` the branch deliberately
does not have) was declared KILLED in the first run so the suite could decide; it
survived 643/643, and structurally so -- `parse_block` tests the token at the cursor, and
after this branch that token is `fn` either way, so both variants build the same tree.

639 -> 643 tests: `pipeline_0457_test.mbt` is new, and none of its four cases existed
before. 0453 pinned that a nested async declaration is not mistaken for a literal, via
`parse_failures == 0` plus the absence of a false notice -- and both hold while the branch
still binds a bogus name, because a notice is not a failure. Only a lens that resolves
names separates the two, which is what the new file asserts.

GATE 0458 -- and this one closes the corpus.

    PARSED 608/608 files understood (100.0%); 0 more read only up to their
    first parse error

moui is no longer "607 of 608". `runtime/app_builder.mbt` was the last file it
could not finish, and `unreliable` went 9 -> 0 with it: every file in that corpus
is now UNDERSTOOD rather than read-until-some-error, which is a stronger statement
than "no file is blocked".

The blocker was one missing head in `fn_type_annotation`. After the `(` it handed
`async` to `type_annotation()` as an ordinary type NAME; the parameter loop then
broke on the `(` that followed rather than on a comma, and `expect(TRParen)`
reported `expected ')'` at line 47.

THE GRAMMAR IS NOT WHAT THE SOURCE LOOKS LIKE, settled 7/7 with two controls that
can fail (`_verify/settle_0458_async_fn_type.ps1`). The trailing `?` makes the
RETURN type optional; it does not lift the group into a nullable function:

    fn build(f? : ((Int) -> Unit)? = None)                          ACCEPT
    fn build(f? : ((Int) -> Unit)  = None)                          REJECT(4014)
    fn build(launch_async? : (async (Int, Int) -> Unit)? = None)    ACCEPT

Three fixtures had to be corrected before any grammar was measured, and each
correction first looked like a verdict ABOUT the grammar: two were call sites given
the wrong return shape, one confused an optional PARAMETER (`x?`) with a nullable
TYPE (`T?`) -- and the corpus line carries both. When a probe about the language
disagrees with you, suspect the probe's fixture first; it was wrong three times here.

M4 IS THE ROW WORTH READING. Dropping `at_name("async")` from the head and keying on
the bracket alone SURVIVED the first 648-test run -- which is exactly enough evidence
to write "unobservable by construction" into a `Prove`, and it would have been wrong.
`fn f(g : (((Int)) -> Unit)) -> Unit` is valid MoonBit (ACCEPT, zero errors), and after
the outer `(` is bumped the cursor is on `(` with the next token also `(`. The
plain-function-type control cannot see it, because there the cursor lands on
`String`. So: "no test covers this" and "no program can reach this" are different
claims, and a survivor verdict is a claim about the second while the evidence on hand
only ever supports the first.

M5 IS A SURVIVOR WHOSE CLAIM IS MEASURED RATHER THAN ARGUED. Two end-to-end tests in
this increment's first draft asserted the RENDERED annotation and were deleted: the
string is consumed inside the parser and handed to `ann_to_ty`, and it is not part of
the pipeline result, so no end-to-end assertion can reach it (the same trap
`pipeline_0413_test.mbt:83` describes). `src/types/types_0458_test.mbt` then answers
the real question -- are the two renderings indistinguishable DOWNSTREAM -- by
asserting `ann_to_ty("async (Int, Int) -> Unit?")` is `TUnknown` beside a control
showing `ann_to_ty` does distinguish types. Teach it the `async` head and that test
goes red on purpose, at which point M5 must become KILLED. A survivor with no
tripwire is an untested guard with a footnote.

Tests 643 -> 651: `pipeline_0458_test.mbt` and `types_0458_test.mbt`, eight cases.
Re-pinned after 0464 (the pipe operators, `errdefer`, and a lambda as a pipe's
right operand). Two corpora moved, both in the direction that means more files are
understood rather than merely more opinions:

    async   parsed 302 -> 325   unreliable 916 -> 733   notices 1406 -> 1550
    proton  parsed 115 (same)   unreliable 922 -> 921   total    2406 -> 2405

`unreliable` is the number that carries the meaning: it counts files read only up
to a parse error, so async's 23 newly-parsed files are now read whole. The
`notices` rise on async is the same trade 0459 made and is worth reading rather
than waving at -- a file that parses reports the deliberate exclusions inside it
(mostly skipped lambda bodies), so more files understood means more notices as
well as fewer unreachable ones.

proton moved by ONE finding: the `errdefer` arm reads its argument rather than
skipping it, so a name in an already-understood file is now read at all.
`notices` there is unchanged, so nothing new was merely noticed -- something that
could not have been seen before is now seen.

MEASURED TWICE, because the first pin was wrong and nothing noticed until the
gate ran. The 312 in an earlier draft of this block was taken BEFORE the
lambda-as-pipe-right-operand fix landed; that fix is worth 13 more async files on
its own (312 -> 325). The pin now records the FINAL source state, re-measured by
`_verify/scan_0427.ps1` independently of this gate and agreeing with it.

=> 判据: a pin is a claim about a source state, so it must be measured against
the state that ships. A number copied from a scan taken mid-increment is not a
stale baseline, it is a wrong one -- and the release gate is the only thing in
this repository positioned to catch it.
Tests 795 -> 820: `parser_0467_test.mbt` (13 cases) and `pipeline_0467_test.mbt`
(12 cases). Re-pinned after 0467 and 0467b. TWO corpora moved, and async moved a long
way -- the largest single-increment gain since the pipe:

    async   parsed 337 -> 352   unreliable 614 -> 373   withheld 189 -> 115
    proton  parsed 116 -> 121   unreliable 727 -> 575   withheld  59 ->  53

async's `unreliable` fell 241 and proton's 152. `unreliable` is the count that carries
meaning: those files are now read whole instead of stopping at a parse error. `withheld`
counts the notices the analyzer deliberately does not make inside a partially-read file,
so a drop there is reach rather than silence.

0467 THE ASYNC FUNCTION TYPE. One construct, THREE spellings, and until this increment
exactly one of them parsed:

    (async (A, B) -> R)?      a parenthesised annotation   -- parsed=1 (0458)
    async (A, B) -> R         a bare parameter annotation  -- parsed=0
    -> async (A, B) -> R      a bare return annotation    -- parsed=0

Measured by running the analyzer over one file per shape, NOT by reading the code. The
cause was an ORDERING fact rather than a missing keyword: the `async` lookahead in
`fn_type_annotation` sat AFTER its `bump() // (`, so it could only ever see `async` when
something had already put a `(` in front of it. The body is now shared
(`fn_type_body`) behind three thin entry arms, so the spellings cannot drift again.

The grammar is settled in `_verify/settle_0467_async_param_type.ps1`, 17 rows, and two
parts of it are not guessable from the symbol. The toolchain's own diagnostic for a bare
`async` is the whole first argument --

    Parse error, unexpected token `)`, you may expect `(`.

-- so the parenthesised list is REQUIRED and `lparen_at` is a discriminator rather than
a guard. And `g : bogus (Int) -> Unit` REJECTs with 3002, so the head is a KEYWORD and
not any name followed by a parenthesised list; that is what makes gate 0467's M3
killable rather than a survivor.

0467b THE BINDING COLLECTOR, WHICH WAS NOT IN THE RANKING AT ALL. Reaching
`moonbitlang/async 0.22.4 src/fs/dir.mbt` produced two ACTIONABLE false positives on
code `moon check` compiles: `49:26 no visible binding for 'last_path_sep_index'` and
`55:13 no visible binding for 'parent'`. Both are bound by a `let` INSIDE A CATCH ARM.
`collect_fn_bindings` descends into `SIf`/`SFor`/`SWhile`/`SBlock`, but `catch` is an
EXPRESSION, so no arm ever scanned one -- and `walk_stmt`'s `SLet` never binds anything
itself, so the pre-pass is the only thing that fills the frame.

THAT IS THE 0464b SHAPE FOR THE FOURTH TIME, and gate 0443 had already written the same
sentence one level up for `SNoBreak`: "walk_stmt was taught `SNoBreak` and the COLLECTOR
was not, and the compiler is silent about a missing arm in a match that has a catch-all".
Nobody noticed for years because `Walker::resolve` is gated on `!self.partial`, and
every file containing a catch arm was unread.

=> 判据: a false positive nobody can reach is not a false positive that does not exist.
It is a finding whose file has not been read yet, and the only way to tell the two apart
is to unblock the corpus and look. The reach was legitimate, so the GAP was fixed rather
than the reach given back.

## 0468: a BLOCK in the RHS of a `let`, and TWO THINGS IT IS NOT ONE OF


Until this increment every `{` in expression position reached the atom's TLBrace arm and
went to the FIELD grammar, which rejected the content and reported `expected a struct
literal field here` at the brace. A block -- `{ let y = 1; y + 1 }`, whose value is its
TAIL -- was unreadable.

  moui             actionable  0 -> 0   parsed 608 UNCHANGED
  moonbit_labeler  actionable  0 -> 1   parsed  32 -> 33
  moonbit_image    actionable  0 -> 1   parsed  15 -> 17
  async            actionable  0 -> 0   parsed 352 -> 390
  proton           actionable  0 -> 0   parsed 121 -> 122
  proton_contract  actionable  0 -> 0   parsed   4 UNCHANGED

moui and proton_contract are the CONTROL and they are the reason the other four can be
read as gain: both were ALREADY complete (608/608 and 4/4) and so cannot have
contributed a single parse.

*** ACTIONABLE IS 1 ON TWO CORPORA AND NOT 0, AND NEITHER IS CAUSED BY THE BLOCK. ***

Both are PRE-EXISTING defects that 0468 made REACHABLE by reading more files -- the
standing 判据 that a false positive nobody can reach is not a false positive that does not
exist. They are pinned HERE rather than quietly, and they are the reason the pin moves UP:

  moonbit_image 0.3.7 png.mbt:980          `operand of '!' must be bool, got 'int'`
  moonbit_labeler 0.2.13 app_moui/rasterizer.mbt:1218
                                          `argument 2 to 'blend_pixel' has incompatible
                                           type 'float'; expected 'int'`

The image one is ROOT-CAUSED and the fix is one line, deliberately NOT in this increment:
parser.mbt's `TName("match")` arm reads the scrutinee and YIELDS IT, so
`let vok = match bd { .. }` binds `vok` to `bd` itself -- same value, same type. The
sibling `TName("fn")` arm does the same kind of skip and correctly yields an OPAQUE node;
`match` is the inconsistent one. That changes parser semantics for an existing construct,
so it is its own increment with its own guard test, not a line borrowed into 0468.
The comment at that arm asserted the opposite ("the scrutinee is an ordinary expression")
and has been corrected in place.

The labeler one is LOCATED, and the two hypotheses above are both FALSIFIED. Measured on a
four-case probe (`moon check` ACCEPTs all of it), an `if` body, a `while` body, a `for` body
and a bare block ALL leak identically:

  fn s3(n : Int) -> Unit {
    for i = 0; i < n; i = i + 1 {
      let x : Double = 1.0
      ignore(x)
    }
    for x = 0; x <= 1; x = x + 1 { take(x) }   <- take's Int param
  }

reports `argument 1 to 'take' has incompatible type 'float'; expected 'int'`. The control is
the same function with the inner `let x` renamed: it reports NOTHING.

So it is neither an argument-index bug nor a single-line `for`-header bug. It is a BINDING
SCOPE LEAK: `collect_stmt_bindings` descends into a nested statement list with the SAME
binding array, so an inner binding outlives the construct and SHADOWS a later binder of the
same name.

THIS IS THE MIRROR IMAGE OF A KNOWN FALSE NEGATIVE ALREADY PINNED, not a second bug. 0468
measured that a block's bindings do NOT scope -- `let y` inside a block stayed visible
afterwards, where `moon check` reports [4021] unbound. That is the same missing scope seen
from the side that loses findings; labeler:1218 is the same missing scope seen from the side
that MANUFACTURES one. A leaked name only becomes a false positive when something later
binds the same name.
=> 判据: one mechanism, two directions. A class of findings is not a list of defects.

NOT FIXED HERE. Every nested body in every corpus shares that frame, so the fix moves the
finding count corpus-wide and is its own increment.

A SECOND PIN MOVED INSIDE 0468 THAT NEVER SHOWED IN ANY SUMMARY: `parse_block` was called
with `false`, so no `EBlock` body ever contained a `STail`, `Infer::ty_of` returned
`TUnknown` for EVERY block and `Interp::eval` returned `AAny`. Both arms were dead code
and every corpus number above is the same with and without them, because `walk_stmt` reads
an `SExpr` tail exactly as well as an `STail` one.
=> 判据: a construct can be READ correctly and still carry no value. Only a row that
counts what the tree CARRIES sees this -- `0468: the tail's TYPE reaches the operator
below` -- and it is M4 of `mutate_0468.ps1`. The flag is now named `value_block`, because
"this is a function body" was the name that let the bug read as a decision.

GATE 0468: 11/11 KILLED, no declared survivors, every restore byte-identical. Two of the
eleven had to be REWRITTEN rather than re-anchored, and both rewrites are in the gate:
M5's named row was the wrong one (a third lens already reports that name), and M11's first
form mutated to `AAny`, which this behavior lens absorbs BY DESIGN -- interp.mbt:1076 has
`AAny => true` in `numeric` and :1094 short-circuits the whole operator arm on it.
=> 判据: a survivor is not always an untested property. Sometimes it is a mutation whose
RESULT is unobservable, and the two want opposite responses.


## 0469: a `match`'s value is the ARMS, not the subject


`parser.mbt`'s `TName("match")` arm used to read the subject and YIELD IT. That is the
one place in the parser where "the expression I had to parse to keep the token stream in
step" and "the value this expression produces" are different things: a `match`'s value is
the join of its arms, and the arms are what this analyzer skips.

  moui             actionable 0 -> 0   UNCHANGED, byte for byte
  moonbit_labeler  actionable 1 -> 1   total 803 -> 801
  moonbit_image    actionable 1 -> 0   total 231 -> 230
  async            actionable 0 -> 0   UNCHANGED, byte for byte
  proton           actionable 0 -> 0   UNCHANGED, byte for byte
  proton_contract  actionable 0 -> 0   UNCHANGED, byte for byte

FOUR OF SIX ARE BYTE-IDENTICAL, and that is the result being claimed: a fix that moved
every corpus would be a fix whose scope nobody measured. moonbit_image's actionable goes
to ZERO -- that is the whole increment. labeler's stays at 1 because its finding is the
unrelated `for`-header/argument-index defect 0468 made reachable.

THE OBVIOUS FIX WAS WRONG, WAS WRITTEN FIRST, AND WAS MEASURED BEFORE IT WAS KEPT.
Yielding the bare `EBigInt` the anonymous-`fn` arm uses fixes the type and LOSES THE
SUBJECT'S READS, turning two TRUE positives in `pipeline_0433_test.mbt` into false
negatives. It passed this corpus stage and failed two unit tests.
=> 判据: "the fix removed the finding" is not the same claim as "the fix removed the
defect". A trade of one true positive for the absence of a false one is not a trade.
`EMatch(subject)` carries the subject and says nothing about the value: `walk_expr`
descends, `ty_of` answers Unknown, `eval` runs the subject for its effects and yields
`ABottom` rather than `AAny` (which every operator arm absorbs).

IT CANNOT BE FOLDED INTO `ECatch` DESPITE THE IDENTICAL SHAPE. `ECatch` TYPES as its
base because `expr catch { .. }` really does produce the base's value when no arm
matches. A `match` does not -- its value comes from the arms. Same shape, opposite
answer, and that difference is the entire argument for a new variant.

A TEST WAS CORRECTED IN PLACE RATHER THAN LEFT: it was named "a match expression is
skipped whole and yields its scrutinee" and asserted `@ast.EName("e")`. That was not a
description of the construct, it was a PIN ON THE DEFECT.

AND TWO ROWS WERE FOUND VACUOUS BY THE GATE. `UnusedParam == 0` for a parameter read
only inside a match subject cannot fail, because a `match` silences `UnusedParam` for its
whole enclosing function by design. M2 measured it: deleting the walk arm reddens three
rows and not that one. It is recorded in place rather than deleted.
=> 判据: before keeping a negative row, ask whether ANY mutation can turn it red.

GATE 0469: 4/4 KILLED, no declared survivors, every restore byte-identical.


## DIRECTION 2: THE BEHAVIOR LENS IS UNOBSERVABLE ON EVERY PINNED CORPUS


This is a VERIFICATION gap, not a correctness gap, and the distinction decides what to do
about it. Measured by `_verify/dir2_behavior_reach.ps1`, which carries its own POSITIVE
CONTROL -- a fixture the scanner really does tag `[behavior]` -- so its zeros cannot be an
artefact of a broken reader:

  ALL SIX CORPORA      7493 findings      0 carrying the behavior lens
    moui                4152              0
    async               1677              0
    proton               959              0
    moonbit_labeler      469              0
    moonbit_image        202              0
    proton_contract        34              0

THE MECHANISM, CONFIRMED CAUSALLY RATHER THAN BY CORRELATION. `interp.mbt` executes
top-level statements and whatever they reach; a function nothing calls is never executed.
Appending ONE top-level call to a copy of proton_contract 0.3.4 -- changing no other byte
-- takes that corpus from 0 findings to 1, and that 1 is `[behavior]` ALONE:

    322:18 - error: no method matching application_route() (MethodError) [behavior]

So the lens is neither broken nor silent for want of defects. It has nothing to run: all
six pinned corpora are libraries, and not one contains a `main()`.

=> WHAT THIS COSTS. Roughly a thousand lines of `interp.mbt` are unexercised by every
corpus, so the SIX SUMMARY lines this gate pins -- its primary defence -- carry ZERO signal
about the behavior lens. Any regression there leaves all six pins green. Every interp
mutation is catchable ONLY by a unit test, which is why `mutate_0426`'s M1/M2, `mutate_0443`
and `mutate_0469`'s M11 all name interp tests explicitly rather than relying on a drift.

=> 判据: a pin is a claim about a source state, and a pin that cannot distinguish two
states is not a pin. Six corpus lines that stay identical whatever `interp.mbt` does are
the same confident zero as a broken reader, and the only defence against both is a
control that proves the counter can see a thing it is reporting as absent.

MEASURED 2026-10-21, AFTER `moonbit_core` WAS PINNED (see the 0494 section below). The six
older corpora carry 7798 findings and NOT ONE is tagged `behavior`; core carries 7960 and
FIVE are. The seven carry 15758 in all. So the statement above is now true of six corpora
and no longer true of the pin table as a whole:

    corpus             findings   behaviour-tagged   files with a `fn main`
    moui                  4152              0                   0
    moonbit_labeler        510              0                   1
    moonbit_image          213              0                   0
    async                 1827              0                   0
    proton                1062              0                   1
    proton_contract         34              0                   0
    moonbit_core          7960              5                   0

The five are all consequences of the reader gaps the new corpus exposes -- three
`undefined variable 'N'`, one `undefined variable 'declare'`, one
`F6A8885A308CA8A54` -- and none of them is a behaviour-lens finding about a BEHAVIOUR: the
lens reports the name it could not resolve. So the honest statement is not "the lens is
now covered" but "the lens now contributes 5 findings to a pin, and 5 is thin". The
`fn main` column is the reason the lens is reached at all in core: a library with no
entry point still has TOP-LEVEL STATEMENTS, and core's bigint package has them.

NOT CHANGED HERE. Making the lens analyze every function rather than only main-reachable
ones is a SEMANTIC change to what the third lens means, and it is a decision rather than
a defect fix: the honest options are to give it per-function entry, to say plainly that
it only analyses programs, or to keep it and state the coverage it does not have.

GATE 0470: the C-style `for` INIT CLAUSE is a DECLARATION. 5/5 KILLED, no declared
survivors, every restore byte-identical.

The clause carries no `let`, so the ordinary statement reader built an `SAssign`. That is
the wrong node twice over: the clause DECLARES rather than assigns, and the name does not
outlive the loop. `Infer::assign_check` REPORTS a mismatch but does not rebind, so an
`x : Double` leaked from an enclosing body survived and the loop's own `x` never replaced
it -- moonbit_labeler 0.2.13 app_moui/rasterizer.mbt:1218, the last `actionable` on any
corpus.

THE TOOLCHAIN STATES THE INCREMENT IN ONE LINE, and the settle gates it as claim 4:

    Unknown binder n in the for-loop steps. Binders in the steps must be declared in the
    initialization block of the for-loop.                      [4106]

An assignment reading cannot produce that message, because there would be nothing to
"declare in the initialization block". The settle's RECORDed row is the second half: an
enclosing `let x : Int`, then `for x = 0; ..`, then `ignore(x)` after the loop ACCEPTs --
the clause SHADOWS the enclosing binding and the enclosing one survives, which only a
declaration does.

=> THE PIN MOVED ON EXACTLY ONE CORPUS. labeler actionable 1 -> 0, total 801 -> 800. moui
4225, image 230, async 1971, proton 2189 and contract 34 are BYTE-IDENTICAL to the pins
above. Five of six unchanged is the control that makes the sixth meaningful: a parser
change that moved every number everywhere would be a different parser change, and one that
moved nothing would have cleared nothing.

=> THE FIRST VERSION OF THE FIX WAS INERT AND NOTHING REPORTED IT. It unwrapped an `EBin`
out of the right-hand side -- which is the shape the COMPOUND branch produces, while the
plain `=` branch stores the value DIRECTLY -- so it matched nothing and handed every
statement back. `moon check --deny-warn` was 0 and all 857 tests stayed green while the
corpus finding it was written to clear stayed. M2 of the gate IS that inert version, and
it is killed by the row that asserts the node KIND rather than a count.

=> 判据: before keeping a negative row, ask whether ANY mutation can turn it red. The 0470
pipeline rows were first written against the family `ArgumentTypeMismatch`, which does not
exist -- it is `ArgTypeMismatch`. Four rows asserting `== 0` on a family that cannot occur
are vacuous and passed 868/868; only the one `== 1` row caught it, by failing. M5 pins the
inert mutation on the pipeline row specifically so that vacuity cannot come back silently.

=> 判据: a token-level test and a node-shape test are not interchangeable. `for i = j + 1`
is a plain `=` whose value is legitimately an `EBin`, and `x += 1` wraps its value in one,
so the shape cannot tell a declaration from a compound assignment. The discriminator is
`TName(_)` followed by `TAssign`, which excludes `TPlusEq` and its siblings for free.
## 0471: an anonymous `fn`'s TAIL between `)` and `{`

`parse_fn_literal` went from `parse_param_list()` straight to `parse_block()`. A literal
carrying `-> Type` or `raise`/`noraise` therefore left the cursor on the tail token, and
`parse_block` -- looking for `{` -- reported `expected '{'`. A complaint about a brace that
was never the problem, which is the same shape as the DECLARED-fn `-> T raise E` clause
whose absence once cost 24.5% of moui's 608 files.

THE FIX IS NOT A THIRD READER. A declared `fn` already reads this tail with two calls, and
the literal was making neither:

    if self.at(TArrow) { retann = self.return_annotation() }
    self.parse_raise_effect()

`return_annotation` already knows both spellings of a function-type return (settle_0427_retfn)
and `parse_raise_effect` already knows `raise E`, `!`, `noraise` and `nocancel`. A literal and
a declared function are the same production, and `parse_fn_literal` exists precisely so the
two literal arms (`fn` and `async fn`) share one reader -- which is why adding the two calls
in one place was the whole fix.

=> THE POSITION WAS RULED OUT BY MEASUREMENT, and this is the part worth keeping. The
obvious reading -- "literals only work as call arguments" -- is wrong in BOTH directions:

    let h = fn(x : Int) { x }          ACCEPTED
    g(fn(x) { x })                     ACCEPTED
    let h = fn(x : Int) -> Int { x }   PARSE ERROR
    g(fn(x) -> Int { x })              PARSE ERROR

so the variable is the RETURN ANNOTATION and not where the literal sits. Had the first
draft's fixture used a call argument -- which is what the proton blockers look like -- the
increment would have been filed as "literals work as arguments but not as values", a
different defect with a different fix.

REACH, per-FILE first blocker, measured on the tree at 0470:

    corpus          parsed        unreliable        notices
    moonbit_labeler  33 -> 35 (+2)  89 -> 55  (-34)   711 -> 738 (+27)
    proton          122 -> 131 (+9) 544 -> 187(-357) 1645 -> 1881 (+236)
    moui / image / async / contract      BYTE-IDENTICAL

`unreliable` is the number that carries the meaning: it counts files read only up to a parse
error, so proton's 357 is files now read whole. The `notices` rise is the same trade 0459,
0464 and 0467 made -- a file that parses reports the deliberate exclusions inside it. proton's
`withheld` fell 35 -> 6 for the same reason: fewer partial reads means fewer notices withheld
from files the analyzer could not trust.

`actionable` stayed 0 on both. Nine more proton files became readable and not one manufactured
a finding, which is the number that makes the rest mean anything -- more reach is also more
opportunity to invent something.

THE GRAMMAR IS SETTLED, 9 rows with two controls (`_verify/settle_0471_fn_literal_tail.ps1`).
Four of its seven claims failed on the first run and every failure was the FIXTURE, not the
grammar: a one-line `if x < 0 { raise Boom } x` inside a body is rejected by the toolchain
with `unexpected token id`, calling a `raise`-annotated literal from a non-raising function
is [4122], and `raise` with no error type needs a bare-`raise` CALLER or the toolchain asks
for a specific error [4118]. None of those say anything about the tail, and all three read
like a grammar rejection if you do not check the error code.

=> 判据: GATE 0471: 5/5 KILLED, no declared survivors, every restore byte-identical. M4 is the
mutation worth reading -- it removes the `if self.at(TArrow)` GUARD, so `return_annotation()`
runs on an untailed literal and eats the BODY's first token as a type. Every "a literal with
a tail parses" row stays green; only the untailed row and the corpus numbers move. A fix
that guards its new reader badly is worse than no reader, and no row that only asks "does the
new form parse" would have caught it.

M2's anchor is `self.parse_raise_effect()` PLUS its next line, because that call appears
THREE times in `parser.mbt` (1605, 2039, 5128) and a bare anchor mutates whichever comes
first -- a different function entirely. The pre-flight counts occurrences and would have
warned; anchoring correctly was cheaper than reading the warning.

TWO ROWS IN `pipeline_0471_test.mbt` PLACE THEIR PROBE ON THE FAR SIDE OF THE LITERAL, and
they are the ones this increment really turns on. A tail read with the wrong extent
swallows the token after the literal: `parsed` goes UP on every affected corpus, every
SUMMARY line looks like progress, and the analyzer has quietly stopped reading the code
that follows. The six pins cannot see that, and neither can a parse-shape assertion.

One row asserts `ArgTypeMismatch == 0` because the literal yields `EBigInt` and is
therefore deliberately opaque to the type lens whatever its annotation says. The first draft
asserted `== 1` for `g(fn(c : Char) -> Char { c })` and it came back 0, which is CORRECT --
`-> T` is read to keep the token stream in step and nothing reads it. Asserting a finding
the analyzer never makes is not a strong row, it is a false one written in the test rather
than in the product.
ONE OLDER GATE HAD TO BE RE-ANCHORED, and the pre-flight is what caught it rather than a red
test. `mutate_0453`'s M3 ("the body is skipped, not read") anchored on the two ADJACENT lines
`let _ = self.parse_param_list()` and `let (_, _) = self.parse_block(false)`, because before
0471 the literal went straight from one to the other. Putting the tail between them broke the
two-line pattern, and the gate ABORTED at pre-flight with `PREFLIGHT MISS` rather than running
a suite it could not honestly report.

The mutation was RE-ANCHORED, not retired, because the thing it mutates did not change shape --
it only grew. The new anchor is the `parse_raise_effect()` / `parse_block(false)` pair, which
is UNIQUE in the file; the bare `let (_, _) = self.parse_block(false)` is not, and anchoring on
that alone would have mutated `parse_c_for` or `parse_if` instead. Gate 0453 is 5/5 KILLED
after the move, every restore byte-identical.

=> 判据: a PREFLIGHT MISS is not a gate failure to be worked around, it is the harness doing
the one job it cannot do any other way -- telling you that a mutation's anchor no longer
points at the thing it was written to mutate. The alternative -- inventing a nearby anchor
until the pre-flight is quiet -- is how a gate ends up testing a function nobody changed. The
re-anchor was only safe because the mutation's MEANING was unchanged and that could be
checked by reading the two versions of the function side by side; a re-anchor of a pattern
whose intent had drifted would have been a silent weakening, so the reasoning is recorded
here rather than left in the diff.
## 0472: the C-style `for`'s initializer LIST, and a `continue` that CARRIES VALUES

Two gaps, both located by asking the scanner for `read up to line N` and then reading line N
of THAT FILE. That is worth a note of its own, because `_verify/rank_0468_first_blocker.ps1`
prints a header line and then the blocker source line, and the lines are laid out loosely
enough that reading them as PAIRS produced a shape count that was wrong in both directions --
attributing a `for` to a file whose blocker was a destructuring `let`. => 判据: a ranking is
a REPORT. Deriving structure from a report's formatting is how the report gets wrong.

THE HEADER. Three async files stop on a comma-separated initializer list:

    async/src/websocket/utils.mbt:49        for i = 0, remaining = remaining; i < data.length(); {
    async/src/internal/gzip_internal/crc32.mbt:53     for crc = current, i = 0; i + 8 <= len; {
    async/src/socket/addr_utils.mbt:262     for i = 0, zero_group_start = 0; i < 8; i = i + 1 {

`c_for_init` read exactly ONE initializer and `parse_c_for` pushed one statement. The list
reader calls `c_for_init` per entry rather than re-implementing it, so the token test from
0470 stays in one place.

THE VALUE. Two of those three then stopped on the NEXT line, because `continue` bumped the
keyword and returned, leaving its values in the stream:

    async/src/socket/addr_utils.mbt:267                continue i + 1, i + 1
    async/src/internal/gzip_internal/crc32.mbt:63     continue crc, i + 8

AND THIS IS THE HALF THAT REMOVES FINDINGS. `walk.mbt` and `infer.mbt` both treat `SContinue`
as a no-op (`SBreak | SContinue => ()`), so before this increment the names in
`continue p, r, c, vr` were read by NOTHING -- and an unread binding is exactly what
`UnusedLocal` reports. moonbit_image's bmp.mbt carries `continue p, r, c, vr` eight times.

THE VALUES ARE READ AND NOT ASSIGNED, and that is the deliberate choice. `continue a, b` means
"set loop variable one to a, loop variable two to b", and those variables are named by the
header, four frames away. Synthesising `SAssign(EName(loopvar_i), v_i)` would have the type
lens check an assignment nobody wrote against a target that may not exist -- a plausible
fabrication that would manufacture findings. Gate M5 is that fabrication, and it is killed.

NO `skip_seps()` BEFORE LOOKING FOR A VALUE, and the first draft had it. A bare `continue` is
followed by a `TNewline` and then the NEXT STATEMENT, so skipping separators reads that
statement's head as the value and swallows the rest of the body -- the file would still parse
and `parsed` would still go UP, so no corpus number could see it. Gate M4 inverts the guard
and the row that kills it puts a name after the continue.

REACH, measured on the tree at 0471:

    async   parsed 390 -> 392   unreliable 285 -> 264   notices 1686 -> 1690   actionable 0
    labeler / proton / moui / contract   BYTE-IDENTICAL

THE SETTLE'S FIRST RUN SAID "REJECT" FOUR TIMES OUT OF EIGHT CLAIMS AND WAS WRONG EVERY TIME
-- the fixtures, not the grammar. A loop variable is NOT MUTABLE: `for i = 0, total = 0;
i < n; i = i + 1 { total = total + i }` is [4087] "The variable total is not mutable", and
the body has to go through `continue`. The header those two rows were written to test is
fine -- A3 and A4, which put the update in the `continue`, ACCEPT, and so does the corpus.
=> 判据: when a settle row fails, read the ERROR CODE before deciding which of you is wrong.
4122 (calling a raising fn from a non-raising one) and 4118 (a bare `raise` needing a
bare-`raise` caller) both look exactly like a grammar refusal in the output.

=> ONE CORPUS NUMBER MOVED AND IT IS NOT EVIDENCE. moonbit_image `unreliable` 23 -> 15, total
230 -> 222, with `notices` 207 UNCHANGED and `actionable` 0. `unreliable` is defined in
`src/sa/main.mbt` as the findings at or after a file's FIRST READ FAILURE -- "derived from an
already-wrong tree, so reported only as a count, never as results". bmp.mbt's failure is
line 117, a multi-line C-style header, and reading `continue a, b` correctly CHANGES that
already-wrong tree.

Checked rather than waved through, in three steps: the count is stable across four runs of
the same wasm (so it is not the flakiness this project has seen elsewhere); reverting ONLY
the `continue` arm and keeping the header list reproduces HEAD's 23 exactly, so the header
change did not touch image at all; and on a COPY of bmp.mbt with the line-117 header repaired
so the whole file parses, `notices` is 14 vs 14 and every shown finding is byte-identical,
with only the suppressed remainder moving 14 -> 6. No evidence-bearing number moved anywhere,
and the whole investigation cost about an hour of not shipping a mystery.

Gate 0472: 5/5 KILLED, no declared survivors, every restore byte-identical.

## 0473: the `for` HEADER is one grammar, not two

THE DEFECT. `Parser::is_c_style_for` decided which of the two `for` forms it was looking at by
scanning forward for whichever of `;` and `{` arrived FIRST at depth 0. The header is variable
length, so that question has no right answer, and it was wrong in BOTH directions:

    for n = step() { break n + 1 }              no `;` before `{`, so read as a BINDER and
                                                died on `expected 'in'`.
                                                async/src/websocket/conn.mbt:486

    for p in ps; len = 0 { .. }                 a `;` before `{`, so read as C-STYLE;
                                                `c_for_init` only converts `TName` + `TAssign`
                                                and cannot read `p in ps`, so `expect(TSemi)`
                                                failed. async/src/io/reader.mbt:176

The second half is NOT FIXED here and must not be read as fixed. The binder head now routes
CORRECTLY, to the binder reader, and that reader stops at the `;`. The error moved from
`expected ';'` to `expected 'in'` and reader.mbt is still unread. Moving an error is not
removing it, and `parser_0473_test.mbt` pins the failure so a later reader cannot mistake the
improvement for the fix. That is 0474 and it is a different increment, because it needs an AST
decision rather than a discriminator.

THE SECOND DEFECT. `parse_c_for` carried two unconditional `expect(TSemi)`. They were not
describing the grammar, they were REJECTING LEGAL HEADERS -- which is why they also stood in the
way of `for ; n > 0 { .. }`, the optional-third-clause note that has been sitting on the todo
list since 0470. Every `;` now only says that a further clause FOLLOWS; none of them terminates
the list. That old item is closed by this increment.

SETTLED, NOT INFERRED. `_verify/settle_0473_for_header_forms.ps1`, 6 gated rows (2 controls, 4
claims) and 3 recorded, against `moon check`:

    ctl_c_for_three_clause            ACCEPT       <- the form 0470 settled
    ctl_binder_plain                  ACCEPT       <- the form 0470's control protects
    C1_single_clause_no_semicolons    ACCEPT
    C2_binder_then_one_clause         ACCEPT
    C3_binder_then_two_clauses        ACCEPT
    C4_two_binders_then_clause        ACCEPT
    record_binder_empty_clauses       ACCEPT       <- `for x in xs; ; {` is legal
    record_empty_single_clause        REJECT(4014,3002)  <- but `for ; {` is not
    record_field_named_in             REJECT(3002,4041,4091)

THE LAST ROW REMOVED CODE. The first draft of the new discriminator also required the token
before `in` to be able to end a pattern, so that `for i = some.in; ..` would not be read as a
binder head. `in` is a RESERVED word, so a struct field cannot be named it, and the settle says
so in the toolchain's own words. Every input that guard would have rejected is a program the
toolchain refuses anyway, so the predicate was unreachable and was deleted rather than kept as
decoration. A bare `in` at depth 0 in a header IS the binder keyword by definition.

THE SAME ARGUMENT IS WHY THERE IS NO MUTATION FOR THE DEPTH GUARD. `in` and `;` are reserved and
cannot appear inside a group as names, so no token that can flip an arm of this scan sits at
depth > 0 in a `for` header. A mutation that cannot fail tests nothing, and the gate says so
rather than inventing one.

MEASURED. Four of six corpora are byte-identical -- moui, moonbit_labeler, proton and
proton_contract did not move by a single field. `actionable` is 0 on all six.

    async           parsed 392 -> 394, notices 1690 -> 1698, unreliable 264 -> 243
    moonbit_image   parsed 17 unchanged, notices 207 unchanged, unreliable 15 -> 13

and both movements were ATTRIBUTED rather than waved through. Every C1-shaped header in async
was enumerated across the tree, and the scanner's own PARTIAL lines were diffed against a
`git worktree` build of HEAD:

    io/buffered_reader.mbt       blocked at 57  -> PARSES          `for searched = 0 {`
    internal/event_loop/io.mbt   blocked at 202 -> blocked at 364  `for rest = .., produced = 0 {`
    bmp.mbt (moonbit_image)      blocked at 117 -> blocked at 118

Nothing else moved in either corpus. bmp.mbt's header is the semicolon-less multi-line form at
lines 117-119, which `moon check` REJECTS [3002], so the analyzer's refusal is correct and what
changed is only WHERE it refuses: `expected ';'` at 117 became `expected '{'` at 118, because
the header reader no longer demands the `;`.

THE SECOND `+1` IS AN INFERENCE AND IS LABELLED AS ONE. Unparsed went 27 -> 25 while
blocked-with-findings went 22 -> 21, so one file moved out of the unparsed set without ever
printing a PARTIAL line -- it failed at HEAD with no findings. `http/utils.mbt`
(`for input = input {`, `for rest = start {`) is the only candidate in that class. That is
arithmetic, not measurement, and the pin comment in `release.ps1` says so in the same words.

Gate 0473: 7/7 KILLED, no declared survivors, every restore byte-identical. 913 tests.

AND A NOTE FOR ANYONE READING A GATE LOG. The test total is TARGET dependent: 899 on wasm and
827 on js, so gates `0.4.23` onward report `of 827 red` and a mid-run drop from 899 to 827 is
that, not a suite quietly losing 8% of its tests while reporting green.

## 0474: a loop in EXPRESSION position was dispatched to the WRONG reader

THE DEFECT. `parse_atom` matches on `self.bump()`, so the loop keyword is consumed as the match
SCRUTINEE and the cursor has already moved past it by the time the arm's body runs.
`parse_loop_as_expr` then chose between `parse_while_stmt` and `parse_for_stmt` by RE-TESTING
`at_name("while")` -- against that already-moved cursor. The re-test was therefore false for
EVERY loop expression, and all of them went to `parse_for_stmt`, which bumped the token after the
keyword as if it were `for`.

Isolated by a temporary trace, added, measured, then reverted:

    TRACE atom enter    p=13 cur=`while`
    TRACE atom dispatch p=14 cur=`a`
    TRACE as_expr       p=14 cur=`a` at_while=false

THE MEASURED TRIGGER, one fixture per row, all `let k = <loop> { 1 }`:

    while a { 1 }          parsed   nothing after the keyword to misread
    while a > 0 { 1 }      `unexpected token `>``
    while a + 0 { 1 }      `unexpected token `+``
    while 1 < 2 { 1 }      `unexpected token `<``
    while g(a) > 0 { 1 }   parses   a CALL head survives the misroute
    any of the above in STATEMENT position: parses

Two rows in that table are why this survived so long. The call head shows the OPERATOR is not the
trigger -- the misroute is, and a call happens to survive it. And `if a { while a > 0 { 1 } } else
{ 2 }` parses too, which is a FALSE PASS: the `TName("if")` arm skips the branch whole, so nothing
inside it was ever parsed. An `if` branch is not evidence about its contents, and a call head is
not evidence that the head was handled.

THE FIX restores the cursor before dispatching, so every downstream reader sees exactly the state
its own comments describe -- `parse_while_stmt` opens with `bump()`, `is_c_style_for` scans from
`self.p + 1`, `parse_c_for` opens with `bump() // for`. One line, in TWO EXPLICIT ARMS rather than
one `TName("for") | TName("while")`: written as an or-pattern with the comment above it, `moon fmt`
lays the comment out BETWEEN the alternatives and the result reads like a half-finished pattern.

=> 判据: a helper that RE-DERIVES which construct it is handling, from a cursor its caller has
already moved, cannot be correct by construction. The caller already knows which arm it matched.
Reading the code says the code is correct here -- `peek()` is the CURRENT token -- so this one
cannot be found by reading.

SETTLED. `_verify/settle_0474_loop_expr.ps1`, 7 gated rows (2 controls, 5 claims) and 1 recorded,
all ACCEPT against `moon check`. Tests: `parser_0474_test.mbt` 8 rows, `pipeline_0474_test.mbt` 3.

WHAT IT BUYS IS EXACTLY "THE FILE PARSES", AND NOT ONE FINDING MORE. `parse_loop_as_expr` consumes
the loop through the statement-position readers and then DISCARDS the statement, returning an
opaque `EBigInt`, so the loop body is parsed and thrown away. `pipeline_0474_test.mbt` pins that in
both directions: an undefined name inside a loop expression's body is NOT reported, while the same
name in a statement-position loop IS. A gain in `parsed` is a gain in COVERAGE, not in analysis,
and the two are not the same claim.

MEASURED. Five of six corpora are byte-identical -- moui, moonbit_labeler, moonbit_image, proton and
proton_contract did not move by a single field. `actionable` is 0 on all six.

    async    parsed 394 -> 396, notices 1698 -> 1728, unreliable 243 -> 203,
             withheld 40 -> 31, total 1941 -> 1931

`notices` +30 with `unreliable` -40 is ONE event, not two: the two files that recovered used to be
counted rather than reported, so they now report real notices. Attributed against a `git worktree`
build of HEAD:

    websocket/conn.mbt           blocked at 486 -> PARSES   `let kind = for frame = .. {`
    internal/event_loop/io.mbt   blocked at 364 -> PARSES   a `while` expression
    http/parser.mbt              blocked at  80 -> blocked at 440

Nothing else moved; blocked-with-findings 21 -> 20.

### The mutation that CANNOT fail, and why it was kept anyway

Gate 0474 is 3 KILLED and 1 declared SURVIVED, and the survivor is the interesting part.

M3 turns the restore `self.p -= 1` into `self.p += 1`. The obvious move is to go looking for the
row that kills it. That is the wrong question, because "which test catches this" and "can ANY test
catch this" have different answers and different verdicts. So the second one was measured instead
(`_verify/measure_0474_m3.ps1`, both trees built and scanned in one session, changing only that
line):

    correct   924/924 green   files=419 parsed=396 actionable=0 notices=1728 unreliable=203
                               withheld=31 total=1931    20 PARTIAL (blocked-file) lines
    mutated   924/924 green   files=419 parsed=396 actionable=0 notices=1728 unreliable=203
                               withheld=31 total=1931    20 PARTIAL (blocked-file) lines

and the two blocked-file lists are IDENTICAL NAME FOR NAME, not merely equal in length -- the count
alone would have hidden a file trading places with another. A 419-file corpus containing the very
loop-expression sites this increment is about moves not one bit.

The mechanism is one line of the increment's own code: `let _ = self.parse_for_stmt(sp)`. M3 sends
the header to `parse_c_for` instead, which builds a perfectly well-formed `SBlock`+`SWhile` -- and
it is thrown away. Both readers consume the identical token range. That is the worst shape a
mutation can have: it does not crash, does not error, and is wrong.

WHAT WOULD KILL IT was stated as a real change rather than a missing fixture: analysing the
loop-expression body. **That prediction was WRONG, and 0475 killed M3 without it.** 0475 added
rows on a header the misroute cannot swallow -- `for p in ps; len = 0 { .. }` -- and M3 now
fails them with `3 != 0`, because stepping the cursor forward sends the binder scan past the
`in`, `is_c_style_for` returns true, and `parse_c_for` cannot read `p in ps` as an initializer.
The two rows that kill it are `0475: the corpus loop-expression shape is read` and the inverted
`0473: a binder head followed by a C-style clause is now READ`.

Every binder head that existed at 0474 was a PLAIN one, and those survive the misroute. So M3
was never harmless -- it was silent on the headers that happened to be written.

=> 判据: this project has already used "a mutation that cannot fail tests nothing" to DELETE a
mutation. This is the same sentence pointing the other way, and both halves are needed: a green run
is compatible with "untested" and with "unobservable", and only one of them is acceptable to leave
behind. Reach PAST the suite before declaring a survivor -- the corpus is a measurement the test
suite structurally cannot make, because a discarded subtree cannot fail an assertion and cannot
move a finding count either.

AND THE HALF THAT WAS MISSED: a declared survivor is a claim about the CURRENT suite and it
EXPIRES THE MOMENT A ROW IS ADDED. The 0474 measurement was sound; the conclusion drawn from it
was still wrong, because "no test covers this" and "nothing can distinguish this" were separated
by evidence that did not yet exist. So the 58-gate run caught `mutate_0474` reporting M3 as
KILLED where the gate file said SURVIVED -- neither of the two files had changed, and only the
full run was looking. A `Prove` is an argument, not a constant, and the harness is what tells you
when to write a new one.

Gate 0474 at 0475: **4 KILLED, 0 survivors**, every restore byte-identical, 933 tests.

### The release gate caught a gate lying to itself, and that is the better story

The first full run after this increment FAILED, at `mutate_0465` M6 -- a gate three increments
old, whose row belongs to the very arms this increment rewrote:

    SURVIVED  M6 `for` and `while` in expression position report as undefined names
    GATE FAILED: 0465  (named test did not go red)

M6's anchor was the single line `TName("for") | TName("while") =>`. 0474 split that or-pattern
into two explicit arms, and afterwards the string existed in the file in exactly ONE place --
inside the comment this increment wrote to explain why the arm had been split.

So the mutation rewrote the PROSE. The text edit applied cleanly. The pre-flight reported the
anchor "present and UNIQUE", which was true. 852/852 stayed green. And the gate reported a
SURVIVED for a mutation that had changed no code at all.

It failed only because M6 is declared KILLED. Had it been a declared survivor -- which, by rule
5, is exactly the verdict a `--=`-turned-`+=` row invites when someone cannot find a test -- it
would have passed silently and nobody would ever have looked again.

FOUR things came out of it, and the third is the one that outlives the increment:

1. M6 is RE-ANCHORED onto the two real arms, keeping its meaning exactly: both keywords are
   renamed in one edit, because they are now two arms and the row is about both.

2. The parser comment was REWORDED so it cannot satisfy an anchor again. This is the part that
   feels like tidying and is not: a comment that quotes an anchor-shaped string is a live
   tripwire for every future gate, and this one was live for exactly one run.

3. `mutate_lib.ps1` GAINED RULE 8: an anchor must not be satisfiable by prose. The pre-flight
   already counted occurrences and reported uniqueness, and NEITHER property can distinguish
   code from a comment that quotes it. It now also tests whether every line the match spans
   begins with `//`, and ABORTS if so. A match on a line the compiler never reads is not a
   match on code.

4. The near-miss is recorded here rather than only in the gate that fixed it, because the
   general shape is not about parsers. An anchor is a POINTER to the line that decides
   behaviour. Presence says the text exists; uniqueness says it is alone; neither says it is
   the line that matters. A gate that verifies a pointer has found its target is a different
   thing from a gate that verifies the pointer's label appears once.

=> 判据: a mutation that changed nothing and a mutation that changed the wrong thing produce
the SAME green suite. The harness already had a rule for the first (NO-OP IS A FAILURE, added
when an absent anchor was read as a clean run). It had nothing for the second, and the second
is the more dangerous one, because an absent anchor aborts loudly while a prose-satisfied one
does not.

AND THE ORDER MATTERS, because it is the reason this was caught at all. `mutate_0474` was run
ALONE first and was green; had the 57-gate run been the only check, the failure would still
have surfaced -- but the 0474 anchor split and the 0465 anchor were made in the SAME increment,
and the gate that noticed was the older one. A new gate does not test the increment that added
it. Only the gates that already existed can notice that adding it broke something.

## 0475: a BINDER head carrying ONE declaration -- and the `nobreak` it turned up

THE DEFECT is the one 0473 refused to claim as fixed. `for p in ps; len = 0 { .. }` is legal
MoonBit; 0473 made the head route CORRECTLY to `parse_for_stmt`'s binder branch, and that
branch stopped at the `;`, so the error moved from `expected ';'` to `expected 'in'` and five
sites stayed unread. Moving an error is not removing it, which is why `parser_0473_test.mbt`
pinned the failure as a FAILING test. That pin is now INVERTED, which is the only honest
thing to do with it once the shape is read.

THE GRAMMAR IS NOT THE C-STYLE ONE, and this is the part a "just reuse the list reader" fix
gets wrong. `_verify/settle_0475_binder_clauses.ps1`, 2 controls and 9 rows, GATE OK:

    for p in ps; len = 0 { .. }              ACCEPT
    the declaration is readable in the body  ACCEPT
    for p in ps; len = 0; n = 1 { .. }       REJECT(4106)  a second `;`-clause is STEPS
    for p in ps; len = 0; len > 0 { .. }     REJECT(3002)  no condition after a binder head
    for p in ps; n = p.length() { .. }       REJECT(4021)  the binder is NOT in scope here
    for p in ps; len = 0 { .. } ignore(len)  REJECT(4021)  it does NOT outlive the loop
    for k, v in m; n = 0 { .. }              ACCEPT

The settle's FIRST DRAFT was wrong and aborted on it. It assumed the C-style variable-length
clause list carries across the binder head, and two of three claims flipped. What the compiler
volunteered is the sentence that settled it:

    Unknown binder n in the for-loop steps.
    Binders in the steps must be declared in the initialization block of the for-loop.

4106 is a SEMANTIC error, which means the text parsed and was then refused. The initialization
block after a binder head takes exactly ONE declaration; a second `;` introduces for-loop
STEPS, which this increment does not model and records as a known limit.

=> NO NEW NODE, and two REJECT(4021) rows are what say so. The declaration cannot see the
binder, so it is evaluated OUTSIDE the binder's scope, and hoisting it BEFORE the loop is
correct by construction rather than by argument. It does not outlive the loop either -- the
same scoping 0470 measured for the C-style init clause -- so `c_for_init`'s conversion is
reused unchanged. The desugar is the shape `parse_c_for` already builds.

### `actionable` went 0 -> 4 and back, which is the part worth reading twice

With the reader in place and `async` rescanned, the corpus reported **actionable 0 -> 4**:

    undefined name 'nobreak'   x3   async/src/process/{unix,windows}.mbt
    undefined name 'acc'            async/src/process/windows.mbt

Both are FALSE POSITIVES on code `moon check` compiles, and the cause is a PRE-EXISTING defect
this increment REVEALED rather than created. The multi-binder path never called
`maybe_nobreak`; `nobreak` is a postfix on a loop and is legal on all three forms (settle_0443),
so the multi-binder head is a loop like any other. Without the call the keyword stayed on the
cursor and the next statement reader took `nobreak { acc }` as an ordinary expression plus a
block -- and `acc` IS the loop binder, so reporting it out of scope there is the resolver being
correct about a block that had stopped being the loop's body. The second finding is a knock-on
of the first, not a separate defect.

They were invisible while the header itself failed to parse. Reading the header revealed them,
which is the same lesson 0464b and 0474 both turned on: UNBLOCKING A FILE DOES NOT CREATE
FINDINGS, IT REVEALS ONES WHOSE REACH WAS BLOCKED, and the honest response is to fix the gap
rather than give the reach back.

`mutate_0475` M4 is this regression with a corpus number attached -- applied, `actionable` goes
back to 4 and `parsed` 399 -> 396. That is the row that will catch it if it ever returns.

MEASURED. Five of six corpora byte-identical; `actionable` 0 on all six.

    async    parsed 396 -> 399, notices 1728 -> 1752, unreliable 203 -> 161,
             withheld 31 unchanged, total 1941 -> 1913

`notices` +24 with `unreliable` -42 is ONE event, not two: files that used to be counted
rather than reported now report. And not everything recovered -- `io/reader.mbt`'s header at
line 176 IS read now, and the file still stops, later, at line 186. That file is the next
blocker, not this one.

Gate 0475: 5/5 KILLED, no declared survivors, every restore byte-identical. 933 tests.

AND THIS INCREMENT ALSO EXPIRED A SURVIVOR DECLARED BY THE LAST ONE. The full 58-gate run
reported `mutate_0474` M3 as KILLED where 0474 had declared it SURVIVED with a measured proof,
and neither file had changed. 0475 added rows on the one header the misroute cannot swallow, so
M3 now fails them with `3 != 0`. The `Expect` is gone and a `MustRed` names the row; the proof
stays in the gate as the record of what was true when it was written. The full account is in the
0474 section above, and the lesson is the general one: A DECLARED SURVIVOR IS A CLAIM ABOUT THE
CURRENT SUITE, NOT A CONSTANT, and the harness is what tells you when it has expired.

TWO ROWS IN THE TEST FILE HAVE NO MUTATION, and the gate says so rather than implying coverage.
They are the negative rows -- a condition after a binder head, and a second declaration clause
-- and nothing in this increment can turn them red, because the refusal is not produced by a
guard here: the reader takes the one declaration and hands the cursor to `parse_block`, which
finds a `;` where it wants `{`. They are kept as a NAMED FUTURE RISK against an edit that
hands the tail to `c_for_inits`, which would accept headers the toolchain refuses.

=> 判据: a corpus number moving the WRONG way is the most informative reading this project
gets, and it only arrives because `actionable` is pinned to 0 rather than merely recorded. A
pin that only ever moves in one direction is not measuring anything. The same applies to the
mechanism: 0475 did not create a false positive, it removed a wall in front of one, and the
correct response was to fix the false positive -- not to leave the wall.

## 0476: the STEP, and a settle that had to be overturned by the corpus

0475 left a measured blocker -- `io/reader.mbt` read past line 176 and stopped at 186 -- and
line 186 is:

    for prefix in prefix_list; len = 0; len = len + prefix.length() { .. }

0475'S SETTLE SAID THIS CLASS OF HEADER IS REJECT. Its C3 row answered REJECT(4106) for
`for p in ps; len = 0; n = 1 { .. }` and the increment generalised "a second `;`-clause is
steps". The corpus disagreed, and the settle was the thing that had to give.

THE REASON IS IN THE COMPILER'S OWN SENTENCE, WHICH NEITHER HAND-WRITTEN PROGRAM SAID OUTRIGHT:

    Unknown binder n in the for-loop steps.
    Binders in the steps must be declared in the initialization block of the for-loop.

4106 was never about the NUMBER OF CLAUSES. It was about WHERE THE BINDER WAS DECLARED. `n`
is declared nowhere; `len` is declared two tokens earlier. `reader.mbt:186` was already
settled by any compiler run -- 0475 generalised a grammar from one convenient fixture, and the
corpus was carrying the verdict the whole time.

SETTLED, `_verify/settle_0476_for_steps.ps1`, 2 controls + 7 rows, GATE OK:

    for p in ps; len = 0; len = len + p.length() { .. }  ACCEPT   the corpus shape
    for p in ps; len = 0; len = p.length() { .. }         ACCEPT   the LOOP BINDER is in scope
    a step declaring a binder the init block does not declare REJECT(4106)
    a bare expression in a step                           REJECT(3002)
    two steps                                             REJECT
    a step with no initialization clause                  REJECT(4021, 4018)
    `;` immediately followed by `{` (an empty step list)  ACCEPT

=> NO NEW NODE AGAIN. A step runs at the END of each iteration, which is where `parse_c_for`
already puts the C-style update clause, so the step is APPENDED to the loop body -- and
appending before the multi-binder path builds its `$pair` destructuring is what puts the step
after it, which is the order that path needs.

TWO THINGS THE GATE CAUGHT IN ME, both of which were about writing the reader honestly:

1. **The first draft was too PERMISSIVE, and 0475's negative rows said so.** It accepted
   `n = 1` and `len > 0`, both of which the toolchain REJECTs. Those two rows were kept at 0475
   with the written admission that no mutation in that gate could turn them red -- this was the
   risk they were naming, arriving one increment later. The fix went in the READER, not the
   tests: a step must match the token shape AND assign the declared binder, and when either
   fails the cursor is deliberately left for `parse_block` to report. Weakening the rows would
   have bought a green suite and a false negative.

2. **A MUTATION SURVIVED AND THE COMMENT WAS LYING.** The reader carried an explicit
   `!self.at(TLBrace)` guard and a comment claiming it prevented the body's brace from being
   read as a step. M1 showed the mutation SURVIVED: `peek_name` returns `""` for a brace, so
   the `target != ""` test already does that, and the two conditions are equivalent. The guard
   was decoration and was deleted rather than kept with a proof it did not need -- the same call
   0473 made on an unreachable predicate, and the same one rule 8 makes about prose.

MEASURED. Five of six corpora byte-identical; `actionable` 0 on all six.

    async    parsed 399 -> 400, notices 1752 -> 1754, unreliable 161 -> 158,
             withheld 31 unchanged, total 1913 -> 1912

`io/reader.mbt` PARSES, with zero defects and nine notices. The increment is one file and one
grammar clause, which is the honest size of what was wrong.

Gate 0476: 4/4 KILLED, no declared survivors, every restore byte-identical. 938 tests.

RECORDED, NOT WORKED AROUND: `for p in ps; len = len + p.length() { .. }` is REJECT(4021, 4018)
by the toolchain -- the right-hand side names a binder that is not yet declared -- and the
analyzer reads that single clause as the initialization declaration and accepts it. That is a
consequence of the ALREADY-FILED scoping limitation rather than a decision taken here, and it
is recorded against that increment.

=> 判据: a settle row that passes BECAUSE the toolchain refused the fixture is evidence only
about the fixture. 0475's C3 used `n = 1`, which nothing declares, and generalised from one
program to a rule about clause COUNT. The rows that decide a grammar are the ones the corpus
ALREADY WRITES -- and when a corpus file and a settle disagree, the corpus is the one carrying a
compiler's verdict on real code. The cheapest possible check would have been to write the
corpus line as a settle row from the start; it was four lines away in the same repository.
## 0477 -- the PATTERN on the left of a `let`

`async/src/os_error/error.mbt` reported one line and nothing else:

    1x  expected '='

Line 79 is `let OSError(errno, context~) = self`, and the reason is not a near miss. There is
no pattern reader in the parser at all: a binding was read as a NAME followed by `=`, so
`OSError` was consumed as the bound VARIABLE and the reader then met `(` where it wanted `=`.
21 such sites in that corpus -- os_error, pipe, js_async, process/redirect -- and each one
cost its whole file.

**THE READER ALREADY EXISTED.** `parse_is_pattern` has read constructor patterns for `is`
since 0444, including the payload loop that collects every binding at every depth, and its
sub-features were settled against the toolchain for exactly what this shape uses: a lowercase
head binds while an uppercase one is a constructor TEST (settle_0444, 9/9), and `.. rest`
binds in an array (settle_0466b). So 0477 is a CALL SITE, not a second pattern reader. Two
readers would be two sets of rules for one grammar, and the corpus would be what found the
difference.

Settled in `_verify/settle_0477_let_pattern.ps1`, 2 controls + 9 rows, GATE OK:

    ACCEPT   positional / labeled / `..` rest / nested / tuple
    ACCEPT   a label BINDS the name (`let Circle(label~) = s`, then reading `label`)
    REJECT(4080, 3007)   anything after `..`        NOT this reader's check
    REJECT(4080, 4085)   an unknown label             NOT this reader's check
    REJECT(4080)         too many positionals         NOT this reader's check
    REJECT(0011)         a refutable pattern          NOT this reader's check

**THE SCAFFOLD WAS WRONG TWICE, and the controls caught both.** Declaring the fixture as a
`struct` made BOTH controls reject with 4199 -- *The type OSError does not declare a custom
constructor* -- because a struct declares no constructor, and `let OSError(..) = e` was never
a struct pattern. The corpus agrees; `pkg.generated.mbti:22` has `suberror OSError {
OSError(Int, context~ : String) }`. Then `Square(Int, side : Int)` was a parse error: inside a
variant the fields are POSITIONAL (`Int`) or LABELLED (`name~ : Type`), never `name : Type`.
Both faults were in the PRELUDE, and both were fixed by changing the fixture until the
toolchain agreed rather than by relaxing an expectation the compiler rejects.

**AND ONE OF MY OWN ROWS WAS LYING ABOUT ITSELF.** S7 is labelled "nested constructor" and as
first written it was a byte-for-byte copy of S9, so it duplicated the irrefutability question
instead of asking its own. Caught on re-read, replaced, and the answer moved: nested
constructors are ACCEPT.

=> NO NEW NODE. `SLetDestruct(Array[String], Expr)` is already the node for a `let` that binds
several names at once -- it is what `let (a, b) = pair` produces, and walk, infer and interp
already bind every name in it and evaluate the initialiser once. The four REJECTs are TYPE
questions and the parser is type-blind; refusing them here would mean refusing the corpus on a
check this reader is not equipped to make.

**THE BINDING IS THE CLAIM, AND THE CORPUS FILE COULD NOT PROVE IT.** `error.mbt:79` sits in
an `impl` body, and impl bodies are outside the analyzed subset, so the file proves the PARSE
and leaves the binding untested. A file that parses while binding nothing is the worst outcome
available: it converts a coverage blocker into a confident false positive against code the
compiler accepts, which is what 0460's comment records happening when an array pattern was read
as expressions. So the rows that matter are at the FINDING level, and every positive row has a
canary beside it -- because a row asserting `UndefinedName == 0` passes just as well on a lens
that has stopped resolving names altogether.

MEASURED. `actionable` 0 on all six corpora; ZERO `undefined name` findings anywhere in async.

    async    parsed 400 -> 403, unreliable 158 -> 120, notices 1754 -> 1776,
             withheld 31 unchanged, total 1912 -> 1896
    proton   unreliable 187 -> 186, total 2068 -> 2067; parsed, notices, withheld UNCHANGED

`parsed +3` is exactly the three files the backlog named. `unreliable -38` against `parsed +3`
is the expected PAIR and not two events: unblocking a file reveals findings whose reach was
blocked, it does not create them.

**PROTON'S -1, ATTRIBUTED -- AND MY FIRST ATTRIBUTION WAS WRONG TWICE.** The whole 2198-line
scan output differs on exactly one line: `facade_session.mbt ... 91 after it not shown`, where
HEAD said 92. `notices` is 128 in both and the region boundary is 1548 in both, so one finding
moved from after the boundary to before it. The mechanism is `facade_session.mbt:1664`,
`let Open(id, completion) = command` -- the single constructor-pattern site in that corpus.
At HEAD that line was the file's first parse error; 0477 reads past it, so the first failure
moves later and one fewer finding sits in the untrusted zone. The file is still blocked, by the
`<?` log payload, which is the next backlog item.

Two wrong turns are worth recording because both would have shipped a confident story:

1. I concluded 1664 "cannot matter" because the file reports `read up to line 1548`. That number
   is the ANALYSIS REGION boundary, not the parse cut. The arithmetic (`total = actionable +
   notices + unreliable`, with total findings fixed at 128) is what actually pins the move.
2. The first `git worktree` A/B was CONFOUNDED. It reported HEAD 187 vs mine 186 -- the right
   answer for entirely the wrong reason: the two runs sat in different directories, and
   `auto_fetch_deps` materialises a target's imports with `moon fetch` into a path that is
   RELATIVE to the process CWD (`sa/main.mbt:483`, `let base = ".repos/" + mod`), so the two
   runs indexed different interface trees. The right answer re-measured from one CWD still
   stands. => an A/B that does not verify its own inputs agrees with a broken one by
   coincidence, and the coincidence is indistinguishable from the result.

   **CORRECTED 2026-10-18: `--extern-iface-dir` is NOT ignored, and the sentence above that
   said so was wrong.** It was wrong because the run passed the flag AND sat next to the tree
   it names, so the flag and the CWD agreed and neither could be blamed. Measured directly, same
   binary, same CWD, proton 0.3.4:

                        IFACE types   values        dirs   actionable
       with the flag        1490      11315            2           0
       without it             205       1755            1          36

   `sa/main.mbt:239-243` starts the list at `[root]` and PUSHES each `--extern-iface-dir` onto
   it, so the flag is honoured and `dirs` reports exactly what it added. The CWD sensitivity is
   real but it comes from `auto_fetch_deps`, not from the flag being skipped. And there is no
   `Info:` line: the instrument that settles this is the `IFACE types=/values=/dirs=` triple
   the scan prints at `sa/main.mbt:244-248`. => a claim about a flag's being ignored needs its
   own run with the flag REMOVED; without that, "ignored" and "agreed by coincidence" are the
   same observation.

**AND A NAVIGATION TRAP THAT MADE ALL FIVE OF MY OWN TESTS FAIL, CONTROLS INCLUDED.** A
function body is wrapped in `SBlock` only when it is a SINGLE statement. `parser_0476`
navigates `body[0].kind -> SBlock(stmts)` because its fixture is one `for` loop;
`parser_0432` goes direct because its fixture is two statements. Both are right. My fixtures
have two or three statements and I navigated through `SBlock` anyway. Five failures including
both controls is the signature of a wrong NAVIGATION rather than a wrong reader -- and the
corpus scan had already measured the reader working.

Gate 0477: 4/4 KILLED, no declared survivors, every restore byte-identical. M2 is the mutation
the increment exists for: it binds one INVENTED name instead of the pattern's, parses clean,
and is invisible to `first_error` -- visible only as `undefined name` on the next line.

**AND A DECLARED SURVIVOR FROM 0.4.34 EXPIRED UNDER THIS INCREMENT.** The full 60-gate run came
back red on gate **0421**, not on 0477: `M7 nested-constructor rule removed` was declared
`Expect = 'SURVIVED'` with a `Prove` argument that it had become UNREACHABLE rather than merely
unobserved -- with the rule removed, `Some(Os(error))` binds both `Os` and `error`, nothing is
undefined and nothing is audited, so the mutated source reads CLEANER than the original. That
argument was TRUE, and true about a particular OBSERVATION SURFACE.

0477 is what ended it. The new row asserts `names.length()` at the AST, so removing the rule
makes `One` bind alongside `inner` and the assertion reports `2 != 1`. Applied by hand the
mutation turns exactly ONE test red and it is that one -- which is also why the gate's own
summary line, "1 of 948 red", was not enough on its own to NAME it. `Expect` is now `MustRed`,
and the 0.4.34 reasoning is left in place rather than quietly rewritten: it was checked and
found wanting, not forgotten.

=> 判据: a declared survivor is a claim about the CURRENT suite, not a constant -- and it was
also a claim about a current OBSERVATION SURFACE. "No lens can disagree with this rule" stayed
true; an AST assertion is not a lens. The risk a survivor names is the risk that the next
increment buys a different instrument, and this one did. The failure mode to watch is the
opposite one: a gate that reads "KILLED" and moves on has told you the suite grew, and a gate
that reads "SURVIVED" and leaves the note alone has told you nothing has.

## 0478 -- the `<?` PAYLOAD

26 sites across 7 files in proton 0.3.4, and four of those files were unreadable because of it:

    @xlog.error(category="proton.command") <?
      { "message": "command dispatch failed", "detail": detail }

MEASURED, and it is the largest single drop in the backlog:

    proton   parsed 131 -> 135, unreliable 186 -> 37, notices 1881 -> 2023,
             withheld 6 unchanged, actionable 0 -> 0, total 2067 -> 2060

`unreliable -149` against `parsed +4` is the expected PAIR and not two events: unblocking a file
reveals findings whose reach was blocked, it does not create them. `actionable` staying at 0
matters more than either -- this reader makes four whole files analysable and invents nothing
against code the compiler accepts.

**THE SHAPE WAS READ FROM THE INTERFACE, NOT PROBED.** `@xlog` 0.4.2's `pkg.generated.mbti`:

    pub fn error(category? : String, loc~ : SourceLoc) -> Event?
    type Event
    pub fn Event::write_object_begin(Self) -> Unit
    pub fn[T : ToJson] Event::write_object_field(Self, String, T) -> Unit
    pub fn Event::write_object_end(Self) -> Unit

so the payload is a JSON object literal DESUGARED TO METHOD CALLS ON THE RECEIVER -- `{` is
`write_object_begin`, each `"key": value` is `write_object_field`, `}` is `write_object_end`.
The receiver is an `Event?`, an OPTIONAL, and the subset has no `Event` to hang fields on.
That is why this reader has no NODE: there is nothing in the analyzed subset for it to be.

Settled in `_verify/settle_0478_log_payload.ps1`, 2 controls + 5 rows, GATE OK:

    ACCEPT              the corpus shape
    ACCEPT              a value may be an EXPRESSION (`"detail": detail`)
    ACCEPT              a TRAILING COMMA is legal here, unlike a struct field (3800)
    ACCEPT              `<? { }` with no field at all
    REJECT(3002)        the KEY must be a string literal
    REJECT(3002, 3002)  AT MOST ONE payload

The last row is the one that shapes the reader rather than bounding it: a LOOP would consume
the second `{` of `x <? {..} <? {..}` and carry on, so `had_payload` exists to stop at the
closing brace and leave the rest for the statement reader to report.

**MY OWN GATE WAS 4/4 KILLED AND THE RELEASE GATE STILL FOUND A REAL BUG.** M1 brace-not-required,
M2 the flag never set, M3 the key not required to be a string literal, M4 the payload braces left
in the stream -- 4/4 KILLED, every restore byte-identical, no declared survivors. All four
mutations are correct questions and all four pass on synthetic fixtures. None of them can see
that the corpus does not spell the brace where my lookahead expects it:

    same-line brace : 12
    next-line brace : 14

The first version asked for `TLBrace` at `self.p + 2`. That refuses 14 of the corpus's own 26
sites. The damage looked small because only the files whose FIRST error is a next-line brace go
unparsed -- 5 of the 7 open that way -- and with the fix reverted the run came back with
`3x unexpected token '?'`: three files gave back the ground 0478 had just gained for them, and
every count that mattered moved the wrong way. A fix that is right in spirit and wrong in
SPELLING, invisible to a gate that asks "does this rule still discriminate?" and answered only
by a gate that asks "does this still read the corpus?".

**AND THEN THE RELEASE GATE CAUGHT THE OPPOSITE ERROR, WHICH WAS NOT MYSELF.** With the lookahead
fixed the run came back red on the proton pin: 2060 pinned, 2066 actual, `actionable` 0 -> 2.

    NOW: SUMMARY  files=137 parsed=135 actionable=0 notices=2023 unreliable=37 withheld=6 total=2060

The first version parsed the payload's values and then DISCARDED them. The corpus does not care --
it parses either way -- but the walker never visited a value it was not handed, and a parameter
used only inside a payload is then indistinguishable from an unused one:

    facade_runtime.mbt:136    parameter `error`
    facade_session.mbt:3413   parameter `detail`

Two FALSE `UnusedParam` findings against code the compiler accepts. Worse, `actionable` 0 -> 2 is
the direction that 0475 was investigated for and not accepted, so the run refused to pin.

**AND THEY WERE INVISIBLE, WHICH IS A HARNESS FACT AND NOT A LUCK ONE.** `findings_shown_per_file
= 40` in `sa/main.mbt` truncates both files -- 23 and 215 notices -- so the scan that changed the
pin printed a summary whose two changed numbers were not on the screen. Raising the limit to 400
is what made them visible; it was restored to 40 and the diff left clean. A truncation setting
that hides the two lines a run failed on is a silent amplifier, and the pin is the only reason
this was caught at all.

**AND THEN THE GATE'S OWN ANCHORS ROTTED, WHICH MEANS THE "4/4 KILLED" ABOVE WAS TRUE AND WAS
ABOUT CODE THAT NO LONGER EXISTS.** Gate 0478 first stood up 4/4 KILLED. Two fixes landed after
that measurement, and each moved an anchor:

- the newline fix replaced the inline `self.toks[self.p + 2] == TLBrace` with a call to
  `at_log_payload_brace`, so M1 was pointing at a line that had been deleted;
- making the function RETURN the values it keeps turned `_ => return` into `_ => return kept`
  (M3) and a bare `self.skip_log_payload()` into `let kept = self.skip_log_payload()` (M4).

The next full release said all of that in one second: `ABORT: 3 pattern(s) absent. No suite was
run.` None of the three was retired -- retiring a mutation because its anchor moved is precisely
how a rule stops being checked while the gate keeps reading OK -- and all three are re-anchored
at the CURRENT spelling of the SAME three questions: the brace is still required (M1), the key is
still required to be a string literal (M3), the payload is still consumed (M4). Re-measured from
scratch: 4/4 KILLED, every kill naming its test, every restore byte-identical.

=> PARSED IS NOT READ. A value consumed by the reader and dropped is syntactically accounted
for and semantically invisible, and every lens that reports on USE will call its names dead. The
fix is `@ast.ETuple([e] + kept)` -- not a payload node, but the receiver and the values in one
tuple, so the walker visits what the program actually says. `skip_log_payload` now returns
`Array[@ast.Expr]` and nothing is thrown away.

=> 判据: the two instruments answered two different questions and only one of them had the corpus
in it. A mutation gate asks whether a rule still DISCRIMINATES, on fixtures I wrote; the release
gate asks whether the reader still AGREES with 26 sites of code I did not. Four mutations killed
and a newline in the wrong place is not a contradiction -- it is the reason the release gate
exists, and the reason "4/4 KILLED" was never going to be the sentence that ends an increment.

The corollary cuts the other way too: `actionable` 0 -> 2 on a corpus the release gate had pinned
is the pin WORKING, not the reader regressing. Pin it or do not ship it, and read the two changed
numbers even when the screen truncates them.

And the third instrument is the one I keep under-using. A mutation verdict is a CLAIM ABOUT A
SPELLING, and two fixes later that spelling is gone. Pre-flight is not bureaucracy before the
real work -- it is the only stage that notices when a number I already banked has stopped
describing the code, and in this increment it fired on three mutations I would otherwise have
reported as passing.

## 0480 -- the UNBRACED escape, `'\uXXXX'`

`character literal must hold exactly one character` -- one line, in two corpora, and the reason
was a spelling 0459 had already settled the other side of.

    proton  internal/native/configuration.mbt:4        c < '\u007f'
    labeler extensions/labeler/labeler.mbt:2741        buf.write_char('\u000C')

0459's guard required `\u` to be followed by `{`, so the unbraced spelling fell through to
`other => other`, which wrote the letter `u`, and the four hex digits were appended by the
ordinary character path. The payload became `u007f` -- five characters -- and the length check
refused it. **A FALSE REFUSAL**: the corpus writes this form and the compiler accepts it.

**IT IS NOT TWO FILES.** A sweep of every `.mbt` under `.repos` for single-quoted literals
holding an unbraced escape finds the form in `moonbitlang/core` `builtin/char.mbt` about a
hundred and fifty times, in `char/predicate_reference_test.mbt` as many again, and through
`x/json5`, `x/unicode`, `svg` and `sqlite3`. The standard library's own source uses the
spelling, which is what makes this a grammar clause rather than a local quirk.

MEASURED.

    moonbit_labeler  parsed 35 -> 36, unreliable 55 -> 16, notices 738 -> 776,
                    withheld 16 unchanged, actionable 0 -> 0, total 793 -> 792
    proton           parsed 135 -> 136, unreliable 37 -> 31, notices 2023 -> 2029,
                    withheld 6 -> 0, actionable 0 -> 0, total 2060 unchanged

`unreliable -39` and `-6` against `parsed +1` each is the expected PAIR: unblocking a file
reveals findings whose reach was blocked. proton's `withheld 6 -> 0` is the whole increment in
one number -- those six findings were being withheld because the file could not be read at all,
and now every one of them is analysed.

Settled in `_verify/settle_0480_unbraced_unicode_escape.ps1`, 3 controls + 6 rows, GATE OK:

    ACCEPT        `'\u007f'`  the proton shape       ACCEPT  `'\u000C'`  the labeler shape
    ACCEPT        `'\u{1F600}'`  the braced form, and the ONLY spelling for astral
    REJECT(3001)  `'\u07f'`     three digits           REJECT(3001)  `'\u01F600'`  six, astral
    REJECT(3001)  `'\u00007f'`  six, BMP               REJECT(3001)  `b'\u000C'`   the byte form

**M2 IS A REAL BUG THE GATE FOUND, AND IT IS WHY THE READER TAKES A FLAG.** The first
implementation widened the escape guard without a context flag, and `b'\u000C'` then lexed
cleanly -- while the toolchain calls it REJECT(3001) with `b'\x0C'` ACCEPTing beside it. The
byte-literal branch routes `b'...'` into the SAME reader, so a guard widened in one place is
widened in both, and the file still parses. The test row caught it (`0 != 1`) before a corpus
was scanned. Two literals, one reader, one flag.

**AND TWO OF MY OWN TEST ROWS COULD NOT SEE THE MUTATIONS THEY WERE WRITTEN FOR.** Both were
caught by `MustRed` rather than by reading them, which is the argument for that field existing:

1. The six-digit row used `'\u01F600'`, which is ASTRAL. With the fourth-digit check removed
   that literal lexes to U+01F600, whose LENGTH through this token is measured by the string
   builder's astral handling -- so both the correct and the broken reader report one finding.
   The fixture is now `'\u00007f'`: same six digits, BMP value, and the broken reader produces
   one character and NO report. 0459's test file says this in its own words, and I repeated it
   a hundred lines below the place it was written down.
2. No row observed the VALUE. With `braced` reverted to `e == 'u'`, the branch consumes the
   first hex digit as though it were a brace and `'\u1234'` becomes U+0234 -- one character,
   zero reports, length correct. The corpus would never have found it: nothing in this project
   compares characters.

**M3 SURVIVES BY PROOF, and the proof is about the CURRENT guard.** Dropping the first two
digit checks cannot change any well-formed literal, because the digit loop already stops at the
first non-hex and writes nothing when it consumed none -- so an escape admitted by a weakened
guard contributes no character, and the one-character check refuses the literal either way.
That is stated in the gate rather than left implicit, and it expires the moment the guard is
rewritten: if a future increment makes the escape write a character at `digits == 0`, the proof
stops being true and has to be re-argued rather than inherited.

Gate 0480: 3 killed, 1 declared survivor, every restore byte-identical. 962 tests.

=> 判据: a rule can be right and a test can still be blind, and "both readers report one
finding" is not agreement. The two blind rows failed for the same underlying reason -- each
asserted a COUNT where the failure was in a VALUE -- and one shared fix: assert the thing the
rule is actually about. `'\u1234'` is one character with or without the bug, so the row has to
compare it to `"\u{1234}"` or it is a comment with an assertion in it. The general shape:
a mutation that survives is either a rule that is not load-bearing, which is worth knowing and
worth writing down, or an instrument that is not measuring -- and the difference between those
two is exactly one question, which is whether ANY input makes the two readers disagree.

## 0479 -- U+FEFF, the BYTE-ORDER MARK

One line, one file, and a refusal of code the toolchain accepts.

    unexpected character '<U+FEFF>'
    e.g. riantr/moonbit_labeler/0.2.13/app_moui/labeler_ui_test.mbt   (first three bytes EF BB BF)

A sweep of every `.mbt` under `.repos` finds this is the ONLY file in the corpus that starts
with a byte-order mark. One file is a reason to fix it rather than to skip it, because a
refusal of valid code is never coverage and always wrong.

MEASURED, and it is the whole corpus:

    moonbit_labeler  parsed 36 -> 37, unreliable 16 -> 0, withheld 16 -> 0,
                    notices 776 -> 791, actionable 0 -> 0, total 792 -> 791

37/37 files parse and `unreliable` is 0 for the first time in this corpus: nothing sits in the
quarantine. `actionable` staying at 0 is the number that matters, and the unblocked file
reports 15 notices and zero defects.

**THE ROW THAT DECIDED THE SIZE OF THE FIX IS S4, AND IT ACCEPTED.**

    ACCEPT  the corpus's first three lines, byte for byte including the mark
    ACCEPT  a mark before a declaration / before a `///|` / on an empty file
    ACCEPT  a mark MIDFILE           `1 <mark> + 2` is `1 + 2`
    ACCEPT  a mark inside a string literal

So this is NOT a "strip a three-byte preamble" change. U+FEFF is legal wherever it appears, the
lexer has to skip the character, and the fix reaches every position. A preamble-only fix would
have passed every ACCEPT control, unblocked the one file anyone had seen fail, and left the
rule wrong for every file a mark turns up in later -- the 0475 shape, and 0459's `b'\x00'`
before it. `Lexer::run` skips it beside space, tab and carriage return, and nothing else.

**STRING CONTENTS ARE UNAFFECTED BY WHERE THE SKIP LIVES, NOT BY A SECOND GUARD.** `run`
dispatches to `lex_string` on `"` and that reader consumes the whole literal, so a mark inside
one is never offered to the skip. A second guard would be a way to change a string's value by
accident, and the test asserts the payload LENGTH for exactly that reason: if the skip ever
moved inside `lex_string`, `"a<mark>b"` would lose a character and every program comparing
that string would silently disagree with the compiler.

**THE CONTROL IS THE CHARACTER IMMEDIATELY BESIDE IT.** The settle licenses exactly one
character, so the nearest miss is the right probe: U+FFFE, one code point away, which a guard
written as a range or one reaching for "the byte-order marks" swallows. `\u{FFFF}` is not used
-- it is not adjacent to anything this change touches, so it would pass against a guard that
widened to a whole block.

Gate 0479: 4/4 KILLED, no declared survivors, every restore byte-identical -- and the first
gate in three increments to pass on its first run, after 0478 and 0480 both arrived with
anchors that two fixes had already moved. 967 tests.

RECORDED, NOT SETTLED: the skip advances `col` like a space does, so a token after a midfile
mark is reported one column further right than it appears. Whether the compiler does the same
is not observable through `moon check` -- it reports line and column for its own diagnostics,
not for a character it skips -- so there was nothing to settle and this is a judgement call.
It affects only the COLUMN of findings that follow a midfile mark, of which the corpus has one.

=> 判据: the corpus names one file at a time, and a fix sized to the file that was reported is
a fix verified by its own symptom. The settle's job is to say how big the rule is, and here it
said bigger than the defect: one file refused a PREAMBLE-shaped problem, and the grammar says
the character is legal everywhere. The row that decides this is never the row about the
reported case -- it is the one about a case nobody reported, and it is the row that costs
nothing to write and everything to skip.

## 0481 -- a NESTED optional type, and the last file in proton

    unexpected token ':'
    e.g. proton 0.3.4/internal/native/types.mbt   read up to line 1351, 31 after it not shown

Line 1351 is `pub fn RuntimeEvent::notification_click(self : RuntimeEvent) -> String?? {`, and
`String??` is `Option[Option[String]]`. The reader folded ONE `?` into the type and left the
second in the stream, so the function reader met a `?` where it wanted a body.

**THE REPORTED TOKEN WAS EIGHT TOKENS EARLIER THAN THE DEFECT.** `self : RuntimeEvent` holds
the only colon on that line, and it is perfectly ordinary -- labelled parameters, which work,
and which the settle's `ctl_labelled_param` row now pins with a name instead of my assuming
it. Chasing the reported token would have meant rewriting labelled parameters, which is a
class of change this project has already made and reversed twice. The report was not wrong
about where it stopped; it was wrong about what stopped it.

MEASURED, and it closes a corpus.

    proton  parsed 136 -> 137, unreliable 31 -> 0, withheld 0, notices 2029 -> 2131,
            actionable 0 -> 0, total 2060 -> 2131

137/137 with an empty quarantine. Four of the six pinned corpora now parse every file:
moui 608/608, moonbit_labeler 37/37, proton 137/137, proton_contract 4/4.

Settled in `_verify/settle_0481_nested_optional_type.ps1`, 3 controls + 6 rows, GATE OK:

    ACCEPT  `-> String?`   `-> String??`   `(x : String??)`   `let x : String??`
    ACCEPT  `-> String???`      the nesting is UNBOUNDED
    ACCEPT  `self : String`     so the reported `:` was a red herring

**S5 IS WHY THIS IS A LOOP AND NOT A SECOND BUMP.** `-> String???` is ACCEPT beside
`-> String??`, so the grammar has no cap and a two-bump fix would be right by luck: it would
pass S1, S2 and the corpus -- which has exactly one doubly-optional type in it -- and would
refuse the third for no reason the toolchain shares. The settle says UNBOUNDED and the reader
is now a `while`.

There is no ternary to confuse this with. A type annotation is not an expression, and the
optional-ARGUMENT shorthand `?` is written before the parameter name, never after a type.

**M2 IS "PARSED IS NOT READ" ONE LAYER DOWN, AND IT IS THE MUTATION THE CORPUS COULD NOT HAVE
FOUND.** Dropping `n = n + "?"` leaves the loop eating every mark: the parse succeeds, nothing
is reported, and the annotation comes back `String` for a program that says `String??`. The
text of the type is simply lost. Nothing here renders annotations back out and nothing reports
a type mismatch, so no scan of any corpus would ever have seen it -- the tests assert on the
RENDERED annotation precisely because "the file parses" is not evidence about it.

**AND ONE OF MY OWN MUTATIONS TESTED NOTHING, WHICH THE GATE SAID IN ONE LINE.** M3's first
draft appended the extra `?` AFTER the loop's closing brace, so the function's value had
already been produced by the `n` above it and the result was a type mismatch, not a mutation.
The gate reported COMPILE-ERR and named the line. A mutation that fails to compile is not a
mutation; it is a check that the code has a particular shape, and reading the compile error
rather than the verdict is what told me which.

Gate 0481: 3/3 KILLED, no declared survivors, every restore byte-identical. M3 kills 49 tests,
which is the plain-type control turning out to be load-bearing far past this file. 973 tests.

=> 判据: a reported token is a claim about where the reader STOPPED, not about what stopped it,
and the two came eight tokens apart here. The corpus names a line; the grammar is wider than
the line; and the difference between fixing the line and fixing the grammar is whether anyone
asked a question outside the corpus before writing the fix. Both of this increment's surprises
came from that: the UNBOUNDED nesting, and the error message pointing at a working feature. The
settle row that is about the reported case will agree with you either way -- S2 would have
passed against a two-bump reader. The rows that disagree are the ones about shapes nobody has
written yet, and those are the only ones with any information in them.

## 0482 -- a `for` HEADER SEPARATED BY LINE BREAKS, and the last file in moonbit_image

    expected '{'
    e.g. moonbit_image 0.3.7/bmp.mbt   read up to line 118, 13 after it not shown

Lines 117-119 are a three-clause C-style `for` header with not one semicolon:

    for i = 0
        i < num_colors && i * 4 + palette_offset + 3 < self.data.length()
        i = i + 1 {

`parse_c_for` gated the condition and the update behind a single `if self.at(TSemi)`, so a
header with no semicolon skipped the whole clause list, and the cursor -- sitting on the
condition -- went to `parse_block`, which reported `expected '{'`.

**`region_line` 118 RATHER THAN 117 IS THE RECEIPT THAT DECIDED WHERE THE FIX BELONGS.** 118
is the condition token; 117 is the `for`. The head was READ and only the separator was missing,
so this was a gate and not a head. Same shape as 0481, whose report landed eight tokens before
its defect: a reported token is a claim about where the reader stopped, not about what stopped
it. Third increment running, third time the reported position and the defect have been
different things.

MEASURED, and it closes a corpus.

    moonbit_image  parsed 17 -> 18, unreliable 13 -> 0, withheld 0, notices 207 -> 218,
                   actionable 0 -> 0, total 220 -> 218

18/18 with an empty quarantine. FIVE of the six pinned corpora now parse every file: moui
608/608, moonbit_labeler 37/37, moonbit_image 18/18, proton 137/137, proton_contract 4/4. Only
async is short, at 403/419, and it is unchanged -- its five `expected '{'` files are a DIFFERENT
construct, which is worth knowing because two increments' worth of ranking would otherwise have
sent the next one after this one twice. Distinct NOTPARSE reasons across the whole backlog: 14
-> 9. async's `unreliable` moved 120 -> 122 with `parsed` unchanged at 403: two files now read
FARTHER before their boundary, so this is the boundary moving and not a new failure.

Settled in `_verify/settle_0482_for_header_no_semicolons.ps1`, 3 controls + 3 claims + 6
recorded, GATE OK:

    ACCEPT  three clauses on three lines with no `;`
    ACCEPT  init + condition, no update
    ACCEPT  a `&&`/`<` chain spanning two comparisons
    REJECT(3002)      all on ONE line
    REJECT(3002)      a `;` before the condition and a line break before the update
    REJECT(3002,4021) the head on the line after the `for`

**THE NEWLINES ARE LOAD-BEARING, AND THAT IS THE ROW THAT SIZED THE FIX.** `for i = 0 i < n i =
i + 1 {` on one line is REJECTed, and both mixed-separator rows REJECT too: it is all `;` or all
line breaks, never a mixture. So the separator is not optional punctuation and the rule is not
"be liberal about `;`".

**THE NATURAL FIX DID NOT WORK, AND THE REASON IS A COUPLING THREE FUNCTIONS AWAY.** Gate on
"is the cursor on a `;` or a `TNewline`" -- `at_sep` -- is the direct reading of the settle and
it does not fire, because `parse_is` (parser.mbt:3779) consumes trailing newlines
UNCONDITIONALLY before testing for its own `is` continuation, so that

    guard (a, b, c)
      is (x, y, z) && ...

keeps working -- a 15-finding fix on `embedded_runtime_backend.mbt`. Every full expression ends
there. By the time any clause reader looks, a newline-separated clause is INDISTINGUISHABLE
from an adjacent one, and there is no separator token left to ask about. I found this by
printing the cursor at four points rather than by reading, which is the third time this round
that reading the code would have produced a confident wrong answer.

**SO THE CLAUSE LIST IS POSITIONAL.** "Another clause exists" is asked of the TOKEN -- can this
begin the body? -- and the two `at(TSemi)` bumps are what keep the slots aligned when a
separator is spelled. The coupling is real and falsifiable, and it is written into `parse_c_for`
rather than left to be inferred from a chain that looks like it should be testing `TNewline`: if
`parse_is` ever stops eating newlines, every row in `parser_0482_test.mbt` goes red and this
becomes a rewrite.

**THE SECOND DRAFT BROKE A PASSING ROW, AND THAT IS M4.** `skip_seps` instead of one separator
at a time collapses `for i = (0, 1); ; i = i + 1 {` -- 0472's `ctl_tuple_comma`, an ACCEPTed
program whose MIDDLE slot is empty -- and shifts the update into the condition slot. One line of
this increment turned that row red before the draft was replaced. An empty clause is legal; the
`at(TSemi)` guard on the condition is the only thing holding it in place, and it looks redundant
next to the `{` guard.

Gate 0482: 4/4 KILLED, no declared survivors, every restore byte-identical. 980 tests.

**AND ONE OF MY OWN MUTATIONS TESTED NOTHING AGAIN, IN THE SAME PLACE.** M2's first draft
replaced the condition clause with `let _ = cond`, which leaves `cond` declared `mut` and never
assigned, and `moon test --deny-warn` rejects the unused mutability as Error [0015]. COMPILE-ERR
is a shape check, not a mutation. 0481's M3 failed to compile for a different reason and 0482's
M2 for this one, which is twice in three increments -- worth remembering as a habit rather than a
fluke: check that the mutated code still ASSIGNS what it declares before reading the verdict.

**M3 IS THE MUTATION NO CORPUS SCAN COULD FIND, AND IT IS WHY THE TESTS ASSERT ON THE BODY.**
The update clause is parsed, consumed, and then dropped on the floor: the file still parses,
`parsed` stays 18/18, `actionable` stays 0, and the loop body is one statement shorter in every
loop that has a step. "Parsed is not read" again, and the row that catches it asserts on the
RENDERED loop body rather than on `first_error`.

**A CLAIM I HAVE BEEN CARRYING SINCE 0470 WAS WRONG, AND 0482 IS WHY IT MATTERED.** Both
`mutate_0470.ps1` and `parser_0470_test.mbt` justified a defensive step by saying "the lexer
emits no whitespace token between `for` and its first name". It does -- `TNewline` is emitted
there like everywhere else, which is why the step exists at all. The real reason the step is
unreachable is narrower and is now measured: MoonBit requires the head on the `for` line
(settle C4, REJECT 3002/4021). The decision stood; the reason did not, and believing it would
have pointed 0482 away from `parse_is` -- exactly where the bug was. Both files carry the
correction now, and the settle row that measures it was added rather than left to be found
later. The same lesson as the falsified `--extern-iface-dir` claim in 0477, and the second time
the argument itself was the defect.

RECORDED, NOT ENFORCED: four shapes the toolchain REFUSES are now read -- the one-line header,
both mixed-separator spellings, and a skipped clause. They are MISSED errors, not false
positives, and the direction that matters is closed. Enforcing the rest needs a rule this
increment has not measured (whether a wrapped `for i = 0;\n  i < n;` counts as a mixed
separator), and a false error on legal code is the worse of the two. The one-line case is
asserted in `parser_0482_test.mbt` as a known over-permissiveness rather than left in prose,
because a comment does not fail when the behaviour changes. `parser_0470_test.mbt` recorded the
same species for `for let` in prose only, because it had no measured toolchain row to point at;
there is one here, so the bar is different.

=> 判据: THE ROW ABOUT THE REPORTED CASE CANNOT TELL YOU HOW BIG THE RULE IS. C1 is the corpus
line and C1 would have passed against almost any permissive fix -- including `skip_seps`, which
is the draft that broke a passing row two steps later. The rows that carried the information
were `record_all_on_one_line` (the separator is load-bearing, not optional) and the two mixed
rows (all-or-nothing), and both of them are about a program nobody reported. 0479 said the same
thing about a preamble, 0481 about a third `?`, and 0482 about a line break: three increments,
three rules that turned out wider than the file that named them, and in all three cases the
settle row that disagreed was free to write and easy to skip. The corpus tells you where to
look; only a question outside it tells you how far to reach.

## 0483 -- a PACKAGE-QUALIFIED HOLDER, `@pkg.Type::method`, and the last three async files

    tls/transport.mbt:36      read up to line 36, 6 after it not shown
    http/parser.mbt:440       read up to line 440, 3 after it not shown
    process/redirect.mbt:156  read up to line 156, 31 after it not shown

All three stop on one line:

    fn @io.ReaderBuffer::repr(buf : Self) -> @io_buffer.Buffer = "%identity"

**THE LINE NAMES TWO CONSTRUCTS AND ONLY ONE OF THEM IS BROKEN.** It reads like a missing
foreign-function body -- a `= "string"` where a `{ }` would go. A nine-case probe against this
analyzer's OWN parser, not inference:

    fn Buf::repr(b : Buf) -> Int = "%identity"       0   <- the body is already read
    fn Buf::repr(b : Buf) -> Int { 1 }               0
    extern "C" fn exit(code : Int) = "exit"          0
    type @pkg.Buf                                   0   <- @pkg is fine in a TYPE
    fn @pkg.Buf::repr(b : Buf) -> Int = "%identity"  2   <- HERE
    fn @pkg.Buf::repr(b : Buf) -> Int { 1 }          2
    fn @pkg.Buf::repr(b : Buf)                       2
    extern "C" fn @pkg.Buf::repr(...) = "x"          2

The body form is IRRELEVANT and the `@pkg.` is decisive. This is the THIRD boundary line in three
increments carrying a construct that already worked, and the fourth time the reported line was
read as the defect: 0481's `unexpected token ':'` named `self : RuntimeEvent`, eight tokens early;
0482's `expected '{'` named a missing brace when the header was missing a separator rule. => 判据:
the reported line is a place, and three places in a row have been a place that contained a
working feature beside the broken one. Probe the neighbourhood before believing the address.

`gzip/decoder.mbt:19` carries the IDENTICAL line and is not blocked -- it is platform-gated and
outside the scanned source set, so "that file parses" could never have settled it either way.

MEASURED.

    async  parsed 403 -> 406, unreliable 122 -> 100, withheld 31 -> 25, notices 1776 -> 1783,
           actionable 0 -> 0, total 1896 -> 1883

Two files closed outright and `redirect.mbt` moved from line 156 to **229** -- it read 73 more
lines and stopped at the next construct, `pub fn &ProcessInput::close(self : &ProcessInput)`.
That is the `&Type::method` holder, which the ranking had measured at ONE file; it is now two,
which is the ranking paying off without being re-derived. `actionable` stays 0, which is the
number that says the fix did not trade a parse failure for a false positive.

Settled in `_verify/settle_0483_pkg_qualified_holder.ps1`, 9 rows / 3 controls, GATE OK:

    ACCEPT  `fn @other.Buf::m(...) = "%identity"` / `{ ... }` / `(self : @other.Buf)` / `async`
    REJECT(4059)  `pub fn @other.Buf::m(...)`   "Cannot define method for foreign type"
    REJECT(4156)  `extern "C" fn @other.Buf::m(...)`

**`pub` IS NOT PART OF THIS GRAMMAR.** The analyzer reads it anyway, which is a MISSED error in
the same direction as the `for let` and the one-line header, and it is recorded rather than
fixed because the corpus has no instance and the corpus is what this project measures with.

**THE FIX IS TWO EDITS AND ONLY ONE OF THEM WAS THE OBVIOUS ONE.** `parse_fn_signature` folds
the path into the AST name; `declared_name_at` folds the same path to HARVEST it. Fixing the
first alone is the worst outcome available -- the file PARSES, so `parsed` goes UP and a corpus
scan calls it a fix, while the harvest still carries `@other` and every resolution of
`@other.Buf::repr` misses. That is a loud failure traded for a quiet false positive.

The shape of the token is worth recording because it cost a look: `@` is INSIDE the name. The
lexer starts a name at `@`, so `@other` is ONE `TName("@other")` and the `.` is a separate
`TDot`. There is no `TAt` in the token enum at all, and an earlier reading of that enum did not
find the arm -- which would have sent the fix looking for a token that does not exist.

**A POSITIVE ROW CAN BE VACUOUS, AND THIS IS THE SHARPEST VERSION OF THAT.** The first draft
asserted that `b.repr()` on a foreign type is not reported as an undefined name. It passed. It
would have passed on a harvest that named nothing whatsoever: a method call resolves through the
type's interface table, and that table is EMPTY for a type from another package, so the
structural lens never had a candidate to report. The second draft moved the same claim into the
pipeline, which changed the LENS and not the question, and was equally vacuous. M1 and M4 both
survived both drafts.

What answers it is `collect_declared_names`, which is `pub` and returns an `IfaceSymTab`: ask the
harvest what it contains instead of inferring it from whether a finding turned up downstream.
=> 判据: a row is only as good as the mechanism that makes it red. 0470's rule was about NEGATIVE
rows -- ask whether any mutation can turn it red. This is the same failure wearing the opposite
sign: a POSITIVE row that passes because the thing it names is unreachable rather than correct,
which no pre-flight can catch and which survives until a mutation is written that disagrees with
it. The evidence that a row is vacuous is not that it is green. It is that you cannot say WHICH
thing would make it red.

**THE SCAFFOLD COST THREE DRAFTS AND EVERY ONE WAS CAUGHT BY A CONTROL, NOT BY A CLAIM.** A
fixture that needs a second package must give it its OWN `moon.pkg` -- a directory with only a
`.mbt` file in it is not a package -- and the import goes in `moon.pkg`, not in the source, and
its path is `<module>/<dir relative to source>` and NOT `<module>/src/<dir>`. Each of the three
failures reported itself in the shape of a grammar refusal: *"Cannot define method ... is
undefined"*, *"Cannot find import"*, *"Package not found in the loaded packages"*. That is the
`no work to do` lesson one level up, and it is why the header lists all three: a settle whose
controls are red is measuring its fixture.

Gate 0483: 4/4 KILLED, no declared survivors, every restore byte-identical. 990 tests. The 66-gate
release PASSED with 6/6 pins MATCH.

=> 判据: TWO READERS OF ONE GRAMMAR IS THE DEFAULT, NOT THE EXCEPTION. Reading is not harvesting,
naming is not binding, and a fix to one of a pair can leave the file BETTER off than it found it
-- parsed, counted as coverage, and wrong in the only place anyone was relying on. The corpus
number that catches this does not exist, because the number moves the right way.

## 0484 -- `fn &Trait::method`, a trait default method whose receiver is a reference

`pub fn &Data::binary(self : &Data) -> Bytes` sits at `io/data.mbt:77` and
`process/redirect.mbt:229`, and `expect_name` was called with the cursor on a `TAmp`.
`process/redirect.mbt` ARRIVED here during 0483 -- it stopped on `@fs.CreateMode::to_int` at line
156, was fixed, read 73 more lines, and stopped again on the `&` holder 73 lines later. That is the
second time a boundary line named more than one construct and only one of them was broken.

A ten-case probe against this analyzer's own parser, not inference:

    fn Data::binary(self : Data)            -> Bytes { }        first_error = 0  <- already works
    impl Data with fn binary(_)             { }                  first_error = 0  <- already works
    type Ref = &Data                                             first_error = 0  <- `&` is fine
    fn @other.Buf::repr(b : @other.Buf)     -> Int = "%identity" first_error = 0  <- 0483 control
    fn &Data::binary(self : &Data)          -> Bytes { }        first_error = 2  <- HERE
    pub fn &Data::binary(self : &Data)      -> Bytes { }        first_error = 2
    pub fn &Data::text(self : &Data)        -> String raise { } first_error = 2
    fn &Data::binary(self : &Data)          -> Bytes = "%id"     first_error = 2
    extern "C" fn &Data::binary(...)        = "x"                first_error = 2
    fn &&Data::binary(self : &&Data)        -> Bytes { }        first_error = 2

The body is IRRELEVANT and the `&` IN FRONT OF THE HOLDER is decisive. Same shape as 0483: reading
the boundary line would have built an extern-body production for a body this parser already reads.

**THE FIRST FRAMING OF THIS CONSTRUCT WAS WRONG, AND `moon check` SAID SO IN ONE LINE.** The obvious
reading of `fn &Type::method` is "a method on Type, declared through a reference". It is a TRAIT's
default method whose receiver is a reference. Both fixture drafts declared `Data` as a STRUCT and
every row came back `4100 The type Data is not a trait`, at the holder AND at the `self : &Data`
annotation. The corpus said so all along:

    io/data.mbt:23            trait Data {
    io/data.mbt:77            pub fn &Data::binary(self : &Data) -> Bytes
    process/redirect.mbt:212  trait ProcessInput {
    process/redirect.mbt:229  pub fn &ProcessInput::close(self : &ProcessInput) -> Unit

A reader that got the tokens right and the meaning wrong would have passed every corpus number,
because the number does not know what a trait is.

**THE TOKEN SHAPE IS NOT 0483's, AND GETTING IT WRONG IS SILENT.** `Lexer::run` starts a name at
`is_letter(c) || c == '@'`, so `@` glues INTO the name and `@other` is ONE `TName`. `&` is not a
name-start character at all: it falls through to `lex_op`, which maps `'&' => TAmp`. So the `&`
here is a STANDALONE token in front of an ordinary `TName`. Copying 0483's shape would have produced
a fix that compiled, passed every existing test, and changed nothing.

**TWO READERS AGAIN, AND THE QUIET ONE IS THE HARVEST.** `declared_name_after_kw` handed a `TAmp` to
`declared_name_at`, which did not match `TName` and returned `None`. Nothing goes red: the sibling
table is simply missing an entry, and the cost lands later as `undefined name 'Trait::m'` at a call
site -- ACTIONABLE, on code `moon check` compiles. M1 is the only mutation here that no corpus
number in either direction could have found.

`_verify/settle_0484_ref_holder.ps1`, 19 rows / 3 controls, GATE OK:

    ACCEPT  fn &Trait::m(self : &Trait)   with and without `pub`, with a `raise` tail
    ACCEPT  called as `d.m()` through a `&Trait`   so `m` IS a method of the trait
    ACCEPT  `= "%identity"` body, `async fn &Trait::m`, and `fn &@other.Trait::m`
    REJECT(4100)  the same declaration on a STRUCT   <- the control that makes `trait` measured
    REJECT(4032)  EVERY unqualified spelling         <- forces the `&` out of the AST name
    REJECT(4099)  `Trait::m(x)` -- a trait is not a type, so there is no by-path call form
    REJECT(4074)  `fn &&Trait::m`
    REJECT(4156)  `extern "C" fn &Trait::m`

`&` IS DROPPED FROM THE RECORDED NAME, and that is a decision with a falsification condition rather
than a convenience. Two settled facts force it: there is no `Trait::m` declaration to collide with,
and there is no `Trait::m(x)` call form either, so `m()` is the only spelling on BOTH sides and
`&Data::binary` would be a name nothing could ever look up. What identifies the TYPE stays in the
name; what describes the RECEIVER is already in `self : &Data`, which `parse_param_list` reads
either way. Falsified if either call form ever settles ACCEPT. M3 is the mutation that would do it.

`fn &@other.Trait::m` is the row with NO corpus instance anywhere: 0483 settled `@other.T::m` and
this settles `&Trait::m`, and the two are adjacent in the source but on OPPOSITE sides of the
reader's cursor -- the `&` is consumed before the name is read, the `@` lives inside the name token.
Asserted on both readers, because a disagreement between them is neither a parse error nor a finding.

**TWO OF MY OWN MUTATIONS WERE WRONG AND THE GATE REPORTED BOTH THE SAME WAY.** M3's first draft
introduced `amp_prefix` and then still built the name from `name` -- a mutation that changes nothing,
which is indistinguishable from a test that cannot fail. M5's first draft widened the `if` to a
`while` over `TAmp`, on the assumption that `&&` lexes as two of them; it lexes as ONE `TAndAnd`, so
no number of `TAmp` bumps can ever reach it.

**AND THAT SECOND ONE EXPOSED A VACUOUS GUARD ROW, WHICH IS THE 0483 LESSON POINTED THE OTHER WAY.**
The guard was `fn &&Data::deep(self : &&Data)`, carrying `&&` in TWO places. Widening the holder to
the logical-and token left the suite green -- because the PARAMETER TYPE `&&Data` fails on its own
whether or not the holder was read. The row was green for a reason that had nothing to do with what
it claimed to guard. The parameter is `Int` now, so the only `&&` in the fixture is the one the row
is about.

=> 判据: a GUARD row is vacuous in exactly the way a positive row is -- not when it is green, but
when it cannot be RED for a reason of its own. The evidence is the same question both times: which
thing, specifically, would have to change? A mutation that "survived" may be reporting a broken
mutation, a wrong lexing assumption, or a fixture that fails twice over, and those three are
distinguishable only by reading what the mutation was supposed to do.

Measured: async `parsed 406 -> 408`, `unreliable 100 -> 72`, `withheld 25 -> 25`,
`notices 1783 -> 1807`, `actionable 0 -> 0`, `total 1883 -> 1879`. Two files closed outright --
exactly the two the ranking predicted, having been made by looking at what is ON each boundary line
rather than at the scanner's grouped message tally.

Gate 0484: 5/5 KILLED, no declared survivors, every restore byte-identical. 998 tests.

## 0485 -- a BRACED STRUCT PATTERN in `is` position, and the FALSE POSITIVE the ranking missed

Three files stop on

    guard matches.values is { "cmd": [cmd], .. } else { fail("no command specified") }

at `examples/xargs/main.mbt:49`, `examples/curl/main.mbt:53` and
`examples/tcp_server_benchmark/main.mbt:98`. The boundary line named two constructs AGAIN, and the
second one was the expensive one: `is` on the next line reads fine (`first_error = 0`), and the
3-vs-2 code difference in the first probe was a CONSEQUENCE of the rest failing, not a second
defect.

Measured with first_error AND UndefinedName TOGETHER, because measuring them apart is what made
the `if` row look unaffected when its first_error had never been measured at all:

    caller        { "cmd": [cmd] }     { "cmd": [cmd], .. }
    match arm     fe=0  undef=0        fe=0  undef=0     <- ALREADY CORRECT
    guard         fe=0  undef=2        fe=2  undef=0
    bare `is`     fe=0  undef=2        fe=2  undef=0
    if            fe=2  undef=0        fe=2  undef=0
    while         fe=2  undef=0        fe=2  undef=0
    let destr     fe=2  undef=0        fe=2  undef=0

**TWO DISTINCT OUTCOMES, AND THE QUIET ONE IS WORTH MORE THAN THE THREE FILES THAT STOP.** `guard`
and a bare `is` PARSE: the leftovers happen to re-read as a BLOCK, so nothing halts, and then the
names the pattern was supposed to bind are reported undefined -- a FALSE POSITIVE on code
`moon check` compiles. It moves no parse-coverage number in either direction, which is why it had
to be found by a binding count and could not be found by the ranking.

**MECHANISM, read from source rather than inferred.** `parse_is_pattern` has branches for a `(`
tuple, a `[` array, a name head and literals -- and NO `{` BRANCH AT ALL. A brace pattern fell to
`else { return [] }`, which CONSUMES NOTHING. The match-arm path reads arms through `skip_pattern`,
a different reader that already handles `..`, which is why one caller was correct and four were
not.

`_verify/settle_0485_is_struct_pattern.ps1`, 16 rows / 4 controls, GATE OK:

    ACCEPT  guard / if / while / bare `is`, with and without `..`, one key or several,
            a plain value, a NESTED array pattern, `{ .. }` alone, `{}` alone
    REJECT(4028)  `{ cmd: [cmd], .. }` -- unquoted key on a `Json` subject
    REJECT(0011)  `let { "cmd": [cmd], .. } = x` -- `partial_match`, a `let` pattern must be
                 irrefutable. Left UNREAD on purpose; a test pins the choice.

ONE reader fixes all four callers, because all four reach `parse_is_pattern` through `parse_is`.
Measured before implementing, not after.

**WHY VALUE POSITION IS TRACKED RATHER THAN "EVERY NAME":** in `{ "cmd": [cmd] }` the key is a
STRING and cannot be mistaken for a binding, but in the unquoted spelling it is a `TName`, and
collecting it would INVENT a binding the pattern never introduces -- a false finding manufactured
out of a key, in a construct whose whole purpose is to stop manufacturing findings.

**A SETTLE THAT COULD NOT FAIL.** The first draft of this settle printed six MISMATCH rows and
still ended `GATE OK`, because the `$fail++` was dropped in a restructure. A settle that cannot
fail is worse than no settle: it reports the same verdict whether the grammar is legal or not. The
abort path now has to be exercised, not merely present.

**AND M3 FOUND A REAL GAP IN THE READER, NOT JUST A WEAK ROW.** The `TColon`/`TComma` guards
tested `depth == 1` but not `bracket == 0`, so a comma INSIDE a nested `[ a, b ]` cleared the
value flag and `{ "m": [[a, b]], .. }` bound only `a`. Nothing in six corpora writes a two-element
nested list, so no corpus number moved and only a synthetic row could see it. The guards moved to
`depth == 1 && bracket == 0` and the fixture moved to `[[a, b]]`.

=> 判据: `first_error` measures only whether the reader STOPPED. It says nothing about whether the
tree is right. A construct is handled when a BINDING survives, and for half of this defect nothing
else would ever have shown. Measure `first_error` and the finding count in the SAME run, and never
compare one against the other across different fixtures -- that is how the `if` row looked
unaffected when it had never been measured on the axis that mattered.

Measured: async `parsed 408 -> 411`, `unreliable 72 -> 65`, `notices 1807 -> 1812`,
`total 1879 -> 1877`, `actionable 0 -> 0`. Three files closed outright, exactly the three the
ranking predicted. The other FIVE corpora are UNCHANGED -- moui 4225, moonbit_labeler 791,
moonbit_image 218, proton 2131, proton_contract 34 -- which is itself the finding: a grammar this
general that moves exactly one corpus is not over-reaching.

Gate 0485: 5/5 KILLED, no declared survivors, every restore byte-identical. 1006 tests.

## 0486 -- a `+`-JOINED EFFECT clause, `-> T noraise + nocancel`

Re-ranking the async backlog by MEASUREMENT rather than by the list carried between increments
found the list had decayed: it named four files, the real backlog was EIGHT, and the two that read
ZERO lines were not among them. The ranked boundary line was wrong too -- but that turned out to
be the smaller of the two errors.

    src/internal/coroutine/async_primitive.mbt:16   async fn[T] async_suspend(cb : ...) -> T
                                                        noraise + nocancel = "%async.suspend"
    examples/http_file_server/main.mbt:24            conn <+ with the operand on the NEXT line

Construct A is this one. `parse_raise_effect` consumed `noraise` and returned, leaving
`+ nocancel` to be read as code.

*** THE CLAUSE IS NOT `noraise + nocancel`. IT IS `<any effect> + nocancel`. *** That correction
came from a mutation that SURVIVED, which is the useful kind:

    M2  accept ANY name after the `+`
        SURVIVED

M2 did not survive because the reader was wrong. It survived because the GUARD ROW was half
vacuous: it used `raise + noraise`, which the `noraise`-first test rejects BEFORE the operand's
name is ever examined. So the row pinned half the guard and was structurally unable to see the
other half. Settling what nobody had asked changed the grammar:

    ACCEPT       fn f() -> Unit noraise + nocancel { () }
    REJECT(3002) fn f() -> Unit noraise + raise { () }
    REJECT(3002) fn f() -> Unit noraise + whatever { () }
    REJECT(3002) fn f() -> Unit raise + noraise { () }
    ACCEPT       fn f() -> Unit raise + nocancel { () }      <- NOT READ. A missing construct.
    REJECT(4074) fn f() noraise + nocancel { () }           -- the clause needs an annotation

`_verify/settle_0486_append_nextline_and_effects.ps1`, 16 rows / 5 controls, GATE OK.

`raise + nocancel` is recorded as gate 0486's DECLARED SURVIVOR rather than quietly retrofitted
onto this gate: it is a different shape of clause, and half-implementing it on the back of a
mutation gate is how the two drift. It is the next increment, with its own settle rows.

One fix covers THREE call sites (parser.mbt:1633, :2127, :5875) -- a signature, a function type and
a parameter position all route here, so there is one grammar and one reader.

Measured: async `parsed 411 -> 413`, `unreliable 65 -> 41`, `withheld 25 -> 17`,
`notices 1812 -> 1821`, `total 1877 -> 1862`, `actionable 0 -> 0`. TWO files closed, not one --
`internal/coroutine/coroutine.mbt` and `async_primitive.mbt` -- which is the third time the
carried list named the right construct and under-counted the sites.

=> 判据: A ROW CAN BE HALF VACUOUS. `raise + noraise` is rejected by a guard one step EARLIER than
the one the row was written to check, so the row passes without ever exercising the thing it
names. The evidence is the same question as everywhere else -- which thing, specifically, would
make it red -- and "which half" is part of the answer.

*** COLLATERAL: gate 0466's M1 and M4 anchors, broken and re-anchored. ***

The first 69-gate release FAILED on `mutate:0466` with PREFLIGHT MISS on exactly two mutations.
0486-A had put its explanatory comment block INSIDE the arm, between the `if` and the `bump`:

    0486-A shape                    what 0466 M1/M4 `Find`
    if ... at_name("noraise") ... {   if ... at_name("noraise") ... {
      // 19 lines of comment    <--     let _ = self.bump()
      let was_noraise = ...          return
      let _ = self.bump()         }
      return
    }

Both anchors `Find` that block as ONE string, so inserting a line between the `if` and the
`bump` made the string vanish. Same class as 0484's gate 0418 collateral, and it cost a second
full release cycle.

The fix is not a re-anchor in the narrow sense -- it is moving the comment ABOVE the `if`, so
the arm is contiguous and comment-free:

    // 0486 A `+`-JOINED EFFECT ... (the whole note, above the `if`)
    if ... at_name("noraise") ... {
      let was_noraise = ...
      let _ = self.bump()
      ...

Re-anchored afterwards: 0466 M1 spans the whole current arm, M4 spans `if` / `was_noraise` /
`bump`. 0466 is GATE OK again, 3 KILLED / 3 declared survivors, and its M1 kill count rose
from 6 to 10 red tests because the arm it deletes is now the 0486 clause as well.

=> 判据: AN ANCHOR IS WRITTEN AGAINST A CODE SHAPE, AND A COMMENT IS PART OF THAT SHAPE. The
question to ask before inserting an explanatory block between two pinned-adjacent lines is not
"does this comment belong here logically" but "does it belong between these two lines". When it
does not have to, it goes above the region. A gate that reports PREFLIGHT MISS is telling the
truth about the shape, not about the logic.

Gate 0486: 3 KILLED, 1 declared survivor with a Prove, every restore byte-identical. 1013 tests.
(That survivor is RETIRED by 0487 below -- not because it was wrong, but because it turned out to
be observable.)

## 0487 -- the WHOLE `+`-joined effect clause, and a survivor that turned out to be observable

0486 shipped ONE spelling and declared `raise + nocancel` a survivor with a Prove: *"no legal
MoonBit pair starts with a bare `nocancel`"*. That is the sentence that had to die.

`_verify/settle_0487_combined_effect_order.ps1`, 21 rows / 6 controls, GATE OK:

    ACCEPT    -> T noraise + nocancel        <- 0486's spelling
    ACCEPT    -> T raise + nocancel          <- 0486's declared survivor
    ACCEPT    -> T raise MyErr + nocancel
    ACCEPT    -> T nocancel + noraise        <- 0486 REFUSED THIS LEGAL PROGRAM
    ACCEPT    -> T nocancel + raise
    ACCEPT    -> T nocancel + raise MyErr

    REJECT 3002  -> T ! + nocancel
    REJECT 3002  -> T noraise + raise MyErr
    REJECT 3002  -> T raise MyErr + raise MyErr2
    REJECT 3002  -> T noraise + nocancel + noraise    <- exactly two, never a chain
    REJECT 4074  fn f() noraise + nocancel { () }     <- still needs an annotation

=> THE GRAMMAR IS: EXACTLY TWO EFFECTS, EXACTLY ONE OF WHICH IS `nocancel`, THE OTHER BEING
`noraise` OR `raise [E]`, IN EITHER ORDER.

So 0486 was not merely incomplete, it was **refusing programs the toolchain accepts**. `mutate_0487`
M3 is 0486's M4 -- the `was_noraise` test, forced false -- and it is now **KILLED** by
`0487: nocancel + noraise reads`. 0486's M4 is `Retired`, with the reason recorded, rather than
re-anchored: a retired row is not a weaker claim here, it is a claim that has been SUPERSEDED by a
stronger pin, exactly as 0458's M4 was.

*** THE ORDER IS A RULE AND THE ARITY BELONGS TO THE ORDER, NOT TO THE WORD. *** `noraise + raise
MyErr` is REJECT 3002 and `nocancel + raise MyErr` is ACCEPT, differing by one token. Both failure
directions are SILENT: reading an illegal program removes no blocker from any corpus, and skipping
a legal error type parses it as code.

`left_was_nocancel && right == "raise"` therefore had a conjunct that turned out to be REDUNDANT --
`joins` can only be true with `right == "raise"` when the left operand was `nocancel`, because the
else branch admits `"nocancel"` and nothing else. It is gone, the order is enforced in one place,
and the reason is recorded in the source rather than tidied away.

`0487: the error type belongs to the order, not the word` asserts the UNTYPED and the TYPED form
together, and that pairing is load-bearing: the typed assertion alone PASSES on a reader whose
arity is wrong and whose join is right, because the `MyErr` is never reached. Only the untyped one
catches the join being widened. That was found by a mutation reporting `KILLED` with no
`[named test confirmed]` -- a green kill that was green for the wrong reason.

**MEASURED: NOT ONE PIN MOVED.** All six corpora are byte-identical to 0486 -- moui 4225, labeler
791, image 218, async 1821/41/17, proton 2131, contract 34. Five of the six were already fully
parsed and could not move; async has 6 files still unread and none of them is blocked on this
clause.

That is the finding, and it is the third time the same thing has shown up: **a correctness defect
can be real, measured, and invisible to every number this repository pins.** Nothing in any pinned
corpus writes `nocancel + <effect>`. So the instrument here is the settle and the rows -- a corpus
would have reported this increment as a no-op, and correctly so.

Gate 0487: 7 KILLED, 0 declared survivors, every restore byte-identical. Gate 0486: 3 KILLED, 1
RETIRED (superseded by 0487 M3). Gate 0466: 3 KILLED / 3 declared survivors, re-anchored. 1024 tests.

## 0488 -- `<+` across a newline, the `$|...` template string, and a false positive the inventory had been hiding

The backlog was re-derived from the scanner rather than taken from the list carried between
increments, because that list has been wrong three separate ways. Every unread file's BOUNDARY LINE
was read directly:

    src/http/utils.mbt:23                    for-header with a NON-EMPTY update clause
    examples/http_file_server/main.mbt:24     `conn <+` , operand NEXT line      <- read ZERO
    src/http/request.mbt:59                  `host =~ (re"^" + ...)`, regex literals
    src/fs/watch_kqueue.mbt:240               `let { identity, .. } = ...`
    src/socket/addr_utils.mbt:297             `logger <+` , operand NEXT line
    src/fs/watch_windows.mbt:320              `>..` range, `break path[:i]`

Ranked by measured REACH rather than depth, `<+` wins: **TWO** files, one of them reading zero lines.
And `addr_utils.mbt:297` is a SECOND SITE for the same construct that the carried list never named --
the same "named the construct, under-counted the sites" failure as 0486, on that settle's other half.

*** THREE DEFECTS THAT LOOK LIKE ONE CONSTRUCT IN THE SOURCE. *** `settle_0488_append_nextline.ps1`,
20 rows / 4 controls, GATE OK.

    ACCEPT   sb <+ NEWLINE "x"           REJECT 4139  a NEWLINE + b   /  - b  /  * b  /  == b
    ACCEPT   let x = $|<a>  /  a + $|<b> REJECT 3002  let x = $| NEWLINE <a> NEWLINE $|</a>
    ACCEPT   sb <+ $|<h1>\{name}</h1>

    A. `newline_suppressed_after` did not list `TAppendPlus`. ONE LINE.
    B. `$|...` had NO lexer production at all -- the `$` fell to lex_op's catch-all. It is a GENERAL
       expression, not a slot only `<+` can fill, which is why the fix belongs in the expression
       grammar rather than in `parse_pipe`.
    C. `copy_interp` flushed a LABEL as a name READ.

=> THE BREAK IS LEGAL *AFTER* THE OPERATOR AND NOT BEFORE IT. The obvious "be helpful" fix is a
general rule letting expressions continue across line breaks. That would accept four programs the
toolchain REJECTs. Suppression looks only at the PRECEDING token, so listing `TAppendPlus` grants
`sb <+` NEWLINE `"x"` and leaves `a` NEWLINE `+ b` refused. mutate_0488 M2 pins that narrowness by
swapping `TStar` in for `TAppendPlus`.

*** READING A FILE FOR THE FIRST TIME IS A FALSE-POSITIVE DISCOVERY EVENT. *** `addr_utils.mbt` used
to stop at line 297, and findings on a PARTIAL file are WITHHELD rather than reported -- so the
inventory said `actionable=0` while a defect sat inside the file. The moment the append fix let it be
read whole, `no visible binding for 'radix'` appeared at `addr_utils.mbt:291`, and async went 0 -> 1
actionable on an increment whose stated job was to add no findings at all.

It is a false positive: `value.to_string(radix=16)` supplies 16 to the parameter named `radix`, which
is MoonBit's labelled-argument call syntax -- the counterpart of the `protocol~ : Protocol`
declaration this same corpus writes at `http/request.mbt:56`. `copy_interp` had no notion of a label,
so it recorded one as a READ. Fixed in this increment rather than the next, because pinning
`actionable=1` would have asserted the finding correct. The carve-out is settled, not guessed:
`==` and `=>` are still reads (rows F3/F4, both ACCEPT).

*** TWO ROWS I WROTE WERE WRONG AND ARE NOT IN THE TREE. *** `"a" NEWLINE `"+ b"` asserted
`first_error > 0`; it is 0 and that is CORRECT -- `first_error` measures whether the reader STOPPED,
and `+ b` is a second statement, so nothing fails to parse. The toolchain rejects the program too,
but with 4139 "its value cannot be implicitly ignored", a TYPE error at `a`. There is no
`first_error` observable for a token-stream question, so M1/M2 pin it by mutating the SET.

*** AND A POSITIVE CONTROL TOOK TWO ATTEMPTS, BOTH WRONG IN AN INSTRUCTIVE WAY. *** M6 treats every
`=` as a label. It SURVIVED against `\{a == b}` -- because `b` is still read -- and then against
`\{a == 1}` -- because the SPACE flushed `a` before the `=` arrived. Only the UNSPACED `\{a==1}`
leaves the identifier pending when the operator comes, which is exactly the shape the defect lives
in. Spacing is not cosmetic: it decides whether the identifier reaches the guard under test at all.

*** TWO GATE RUNS HUNG, AND BOTH WERE MY MUTATIONS, NOT THE READER. *** M3 replaced `break` with
`continue` where the cursor step sits BELOW the branch; M4 deleted only the body of the dispatch
branch, leaving a bare `continue`. `run()` advances `pos` inside each branch's lexer call, so neither
mutation ever moved it. A hung mutation produces no `Total tests:` line and is indistinguishable
from a slow one, and the harness does NOT restore the file when a run is killed.

Gate 0488: 6 KILLED, 0 declared survivors, every restore byte-identical. 1032 tests.

=> 判据: A MUTATION'S `Repl` IS A PROGRAM, NOT A DELETION. What it compiles to has to TERMINATE, and
the two shapes to check first are `break` -> `continue` inside a cursor loop and a branch reduced to
a bare `continue`. Before killing a gate that has run long past its siblings, work out WHY it is slow
-- and after killing one, read the mutated region back. `git diff --stat` will not tell you: the
mutation had replaced five lines with three and the file still read as clean.

=> 判据: THE SAME ARM WAS RE-ANCHORED IN THREE GATES ACROSS TWO INCREMENTS, AND THE SECOND TIME
IT WAS NOT MY FAULT. `parse_raise_effect`'s `noraise` / `nocancel` arm is a SHARED INTERFACE: gate
0466 pins the effect SLOT, 0486 and 0487 pin the JOIN inside it, and each pins a contiguous SHAPE.
So an edit there is never local -- it is a coordinated change across gates, and the two that break
are always 0466's M1 and M4 because they are the two that SPAN the arm. Both times the symptom was
PREFLIGHT MISS on exactly those two while 67 other gates passed, which reads like a one-gate flake
and is not one. Budget the re-anchor, and prefer changes that leave the arm's line count and order
alone.

*** AND GATE 0423 IS THE MORE DANGEROUS VERSION OF THE SAME THING, SO IT IS WORTH ITS OWN NOTE. ***
`eat_joined_effect` introduced a SECOND `type_head` guard with the same four lines as the one in
`parse_raise_effect`. 0423's M6 anchored the type read followed IMMEDIATELY by the closing `}` --
that adjacency died when `eat_joined_effect(false)` was added after the type, and M6 PREFLIGHT-MISSED.
Loud, and therefore harmless.

M7 and M8 anchored the guard's four lines alone. Those did not MISS -- they became AMBIGUOUS, which
the harness only WARNS about, because it removes the FIRST match and that match had just moved
into the new helper. So M7 and M8 would have reported clean kills for mutations applied to the
WRONG SITE: green, meaningless, and invisible in every number this repository pins. `if
!type_head` is what distinguishes the two guards (`if type_head` in the helper), and including it
makes both anchors unique again. 0423 is GATE OK, 9/9 KILLED, no ambiguity warning.

=> 判据: A PREFLIGHT MISS IS THE LUckY OUTCOME. An anchor that STOPS MATCHING aborts the gate and
tells you. An anchor that starts matching TWICE is warned about and then used anyway, on whichever
site comes first -- so when a change introduces a second copy of a shape, the question is not "did
my anchors survive" but "did any of them become AMBIGUOUS, and does the first match still point at
the code I meant". `grep` the whole `_verify` tree for every shape you duplicated before
believing a green gate.


*** AND THE RELEASE GATE FAILED ON THE GRAMMAR-PROBE CONTROL, AND THE FAILURE WAS IN THE
CONTROL'S OWN PLANTED-ROW DERIVATION. ***

The 0488 release run stopped at `grammar-probe-control`. The control's planted row is not
hand-written: it is DERIVED at run time from a file in the pinned corpora that this frontend
genuinely cannot read, because the row has been moved four times as increments closed it. The
derivation returned NOTHING, and its log was:

    async     PARTIAL files = 4
    async     skip file   MOON-BAD    src/http/utils.mbt:23

ONE skip line for FOUR files. The other three were dropped by a `continue` that carried no log
line, so the log read like "one file was tried" when in fact three had vanished without a trace.
That is the same defect the control exists to catch, wearing the control's own clothes: a search
that stops looking and leaves no mark.

AND THE ONE THAT WAS TRIED FAILED FOR A REASON THE OLD METHOD COULD NOT SEE. The whole file
mentions `BadRequest`, which is defined in a SIBLING file of the same package, so the file is not
a legal standalone program and `moon check` rejects it. The file-level candidate was rejected for
a reason that has nothing to do with the gap inside it -- the unreadable for-header with a
non-empty update clause, at `src/http/utils.mbt:23`, inside `fn encode_int`.

THE METHOD IS NOW A DESCENT, NOT A CHOICE. The old code PICKED one granularity by a textual test
(`import` or `@pkg`? take the item, else take the file) and never tried the other. The new code
walks the units that CONTAIN the blocker and tries each on its own merits: the whole file, the
enclosing top-level item, a definition NESTED inside that item lifted to column 0, then the other
top-level items -- after the blocker first, because a PARTIAL file means the reader STOPPED there
and everything past it is an UNVERIFIED region that may still hold a gap once the enclosing item
is fixed.

=> MEASURED YIELD PER LAYER, on all 107 candidates in the four unreadable `async` files, every
one scored MOON-OK AND SELF-FAIL:

    file  --  0 usable of   4
    item  --  1 usable of  56      src/http/utils.mbt:16-31, fn encode_int
    sub   --  0 usable of  47

So the layer that pays is the ENCLOSING ITEM, and the reason is the same in every file: the
unreadable construct lives in an item that happens to be self-contained, inside a file that is
not. The `sub` layer -- "plant from a self-contained sub-item even when the enclosing item is
not" -- is implemented because it is the only layer that can find a gap in an item that references
an external package, and it contributes nothing today. That is a MEASUREMENT, not an assumption:
a nested definition lifted to column 0 refers to the enclosing item's locals, so it is never a
legal standalone program on its own.

=> 判据: A CANDIDATE IS REJECTED ON ITS OWN MERITS, AND EVERY REJECTION IS LOGGED. A skip that
prints nothing is indistinguishable from a candidate that was never generated. The log now
carries one line per candidate with its reason (HAS-AT / HAS-IMPORT / MOON-BAD / SELF-OK), and
the 0488 run's own log is the proof that this was needed: it showed 14 candidates where the
failing run had shown 1.

AND A LATENT WRONG-UNIT BUG CAME OUT OF THE SAME MEASUREMENT. The item-opener pattern did not
match `async fn`, so `pub async fn request(` at `async 0.22.4 src/http/request.mbt:84` was not
recognised as an item opener at all. The item enclosing the blocker at line 59 was therefore
computed as lines 55-212 -- everything to the end of the file -- instead of 55-72. It changed
nothing today, because `resolve_host` mentions `@string` either way, but an item extent that runs
to the end of the file is exactly the kind of unit whose "@-test" ends up answering a question
nobody asked.

THE CONTROL'S FIVE ASSERTIONS ARE UNCHANGED. Same five checks, same strings, and the
`-SimulateExhaustion` branch still FAILS with exit 1, which is the honest endpoint: when the
derivation finds nothing, the control says so rather than falling back to a hardcoded row. The
planted row is now `async:src/http/utils.mbt:23`, unit `fn encode_int` -- real corpus code, and
the construct in it is the for-header with a non-empty update clause, which is one of the four
gaps left in the backlog.


## 0489: the BEHAVIORAL LENS ENTERS AT EACH FUNCTION, and it turns out it was WRONG

(NO VERSION PREFIX, and the reason is that the prefix was already taken: this file's counter reached
`0.4.39` at 0450 and was dropped there, so every section from 0468 on is headed by its increment
number alone. A `0.4.30, 0489:` header would have been a SECOND `0.4.30` in one file -- `0.4.30,
0440:` is already there -- and a version label that means two different increments. The package
version and this file's counter are not the same number either: the package is at `0.4.29`.)


DIRECTION 2, AND THE QUESTION IT ASKED WAS "IS THE LENS OBSERVABLE AT ALL -- AND IF IT IS, WHAT
DOES IT SAY?" The answer is: it was not observable, and once it was, it said several things that
were wrong.

THE LENS NEVER EXECUTED A FUNCTION BODY. `Interp::run_top` SKIPS `SFunc` items:

    for s in m.body {
      match s.kind {
        SFunc(_, _, _, _, _) => ()
        _ => { ...exec_stmt(s, self.globals)... }
      }
    }

so a body ran only if something CALLED it from a top-level statement. A library module does not
call its own functions at top level, so on every pinned corpus the lens executed ZERO bodies:

    moui             4152 findings, ALL tagged `structural`
    proton           1062 findings, ALL tagged `structural`
    async            1820 findings, ALL tagged `structural`

not one tagged `behavior`. MEASURED, the gap was the ENTRY and nothing else -- the same defect, in
the same body, three ways:

    top     -- a top-level statement        -> [type+behavior]
    incall  -- in a function CALLED at top  -> [type+behavior]
    uncall  -- in a function NEVER called   -> [type]      <- behavior GONE

for every defect kind tried. `Unreachable` is the family the tests pin with, because it is the
one NO OTHER LENS SEES: the structural and type lenses both walk the body and find nothing there,
so a merged report carrying `behavior` is unambiguous evidence that the behavioral lens -- and
only it -- executed the body.

THE NEW ENTRY. `Interp::analyze_functions` binds each parameter to a fresh abstract value of its
DECLARED type and executes the body. `Interp::setup_interp` is now SHARED by the two entries, so
they cannot drift about which names exist; `PipelineResult::run_functions` is the pipeline-level
door, and the scanner reaches it with `--per-function`.

THE DECLARED TYPE IS THE ONLY SOUND CHOICE FOR AN ENTRY POINT: the parameter's runtime value is
unknown, so the lens must assume the declared type and nothing more. An UNANNOTATED parameter
becomes `AAny`, which every operation accepts -- an unannotated parameter must not manufacture a
finding, and there is a row for that, with its opposite (a declared `Int` used as a condition IS
a defect) as the control.

*** AND THE ENTRY UNCOVERED FOUR LATENT DEFECTS IN THE LENS, WHICH IS THE PART THAT WAS WORTH
THE INCREMENT. *** Each is a case where the lens INVENTED a finding the other two lenses
contradicted -- the shape this lens has been corrected for before.

  M2  AN ENUM CONSTRUCTOR was `undefined variable`. The lens never received
      `ParseResult::enum_ctors` -- the list the structural and type lenses BOTH get. MEASURED on
      the first corpus the entry touched: `proton_contract 0.3.4 contract.mbt:261`,
      `ContractRoute::{ scope: Application, name, }` -> `undefined variable 'Application'`, an
      ERROR, on code `moon check` accepts. `Application` is a constructor of the `ContractScope`
      enum, whose BRACED body this frontend SKIPS -- so the name arrives in `enum_ctors` and the
      lens simply never asked.
  M3  A QUALIFIED CONSTRUCTOR (`PixelFormat::RGBA8`) was `undefined variable`. The STRUCTURAL
      lens has the TAIL rule -- `walk.mbt`: "a qualified path whose TAIL is bound is a real name:
      `Layer::ReLU` is a unit enum variant, and the harvest binds `ReLU` but not the whole path" --
      and this lens had none. 200+ of these on moui alone.
  M4  A CALL TO A FUNCTION-TYPED PARAMETER was `undefined function`. `Interp::call` dispatched
      only through the top-level method table and never consulted the frame the parameter is
      bound in, so `cb()` on a `cb : () -> Unit` parameter was an ERROR.
  M5  and the fresh value IGNORED the declared type, which is M5 in the gate.

MEASURED, THE FALSE POSITIVES FELL FROM 629 TO 265 ON moui, and the remaining classes are
different ones: a `#cfg` duplicate-name method table (the walk fixed this in 0441 and the
interp's table is still keyed by name), a `Unit`/`None` conflation, and arity mismatches.

=> 判据: A BLANKET RULE IS NOT A RULE. The first attempt at M3 was "any qualified name is
unresolvable, so stay silent" -- and it broke ELEVEN pinned tests, including `Array::mkae` (a
builtin type with a method that does not exist) and `ZzMissing::nope` (an unknown head), which the
repository pins ON PURPOSE. The precise rule is the TAIL rule the structural lens already uses,
and it leaves both of those reported because the tail of each is not bound. Every blanket rule
this lens has ever grown was one of these: `StringBuilder()`, `Int::max`, `Builder()` -- each one
a table, never a shape.

=> 判据: THE ENTRY AND THE DEFECT ARE SEPARATE, AND THE ENTRY IS WHAT MAKES THE DEFECT VISIBLE.
Every one of the four defects above was in the lens, not in the entry, and every one of them was
invisible because the lens never ran. The same is recorded at 0.4.16 -> 0.4.17, where a rule
about qualified builtin calls was reverted as "unobservable" -- and the reason it was
unobservable was THIS: the probe copied a function DEFINITION without ever calling it, so
nothing ran. The 0.4.17 comment says so in as many words, and the fix was to restore the CALL.
The per-function entry is the general form of that fix.

MEASURED, AND THE DEFAULT VIEW DID NOT MOVE: the module entry's numbers are byte-identical to the
0488 pins on all six corpora -- moui 4225, labeler 791, image 218, async 1829/23/0/1852, proton
2131, contract 34. The per-function view is a SEPARATE, OPT-IN view (`--per-function`), so the
pins measure what they measured.

  corpus             module view (the pins)          per-function view
  moui             actionable 0, notices 4225          actionable 265, notices 4225
  moonbit_labeler  actionable 0, notices  791          actionable  95, notices  791
  moonbit_image    actionable 0, notices  218          actionable  94, notices  218
  async            actionable 0, notices 1829          actionable 279, notices 1829
  proton           actionable 0, notices 2131          actionable 136, notices 2131
  proton_contract  actionable 0, notices   34          actionable   0, notices   34

THE PER-FUNCTION VIEW IS NOT YET SOUND, and the counts above are the reason it is opt-in. 265
actionable on a corpus `moon check` accepts is not a finding rate, it is an inventory of what is
still wrong with the lens. The remaining classes are named in the source and the next increment
has them.

GATE 0489: 6 KILLED, 0 declared survivors, every restore byte-identical. 1042 tests.


## 0490: FIVE LENS DEFECTS THE PER-FUNCTION VIEW MADE VISIBLE, AND A RENAME THE TOOLCHAIN DID

0489 shipped the per-function entry and left the view reporting 265 actionable findings on moui
0.1.12 where the module view reports 0. That 265 was never 265 defects in the analysed code. It
was an INVENTORY of what was still wrong with the BEHAVIORAL LENS, and this increment is the
measurement of five of those classes -- each one a defect the lens INVENTED, on code `moon check`
accepts, and each one with a minimal repro fixture that stands on its own.

THE INVENTORY WAS TAKEN BEFORE ANY FIX, by grouping the actionable findings by family and by
message, and the groups were the diagnosis: a group of ~20 rows that all said "no method matching
<fn>(List, ...)", a group that said "no method matching <fn>(Any, Any, Any)" against functions that
declare seven parameters, and a group that said "no method matching +/</>=(None, ...)".

  M1  A LIST VALUE AGAINST A LIST PARAMETER. The TYPE lens writes a list type as `[int]`
      (`ty_name`); the BEHAVIORAL lens writes a list VALUE as `List` (`abs_of`); and `vmatches`
      compares a value name against a type name. So "List" was NEVER equal to "[int]", and every
      call passing a list was reported `no method matching take(List)`.
  M2/M3  THE ARITY RULE. The check compared the argument count against the DECLARED count, so a
      call that omitted an omittable parameter was reported. Measured on moui: `control_state`
      declares SEVEN parameters (`foreground~`, `background~`, and five `?` ones) and is called
      with THREE arguments throughout the corpus -- eleven sites, every one reported.
  M4  A FUNCTION WHOSE BODY IS AN `if` RETURNED "None". The `SIf` arm ran the branch, and the
      branch's trailing expression was an `SExpr`, whose value the `SExpr` arm DISCARDED. So
      `ret_vals` stayed empty, `join_vals([])` answered "None", and every operator applied to that
      result was reported `no method matching +(None, int)`. `clamp_double` is an `if` body, and
      every call site of it inherited the "None".
  M5  A STRING CONCATENATION WAS THE TYPE "int". `bin_widen` had arms for `float`, for `Any`, and
      the `int` fallback -- and none for two strings, so `"a" + "b"` evaluated to "int". The
      consequence was a false positive on the OUTER `+`: `("a" + "b") + "c"` has an "int" left
      operand and a "str" right one, and the operator check reported `no method matching
      +(int, str)`. Measured on moui `render/common/provider_shell.mbt:10`.
  M6  A STRING COMPARISON WAS A METHOD ERROR. The comparison operators accepted only
      `numeric(l) && numeric(r)`, and `<=` on two Strings is legal MoonBit.

THE OMITTABLE SPELLINGS ARE TWO, AND BOTH ARE SETTLED AGAINST THE TOOLCHAIN (`moon check`
0.1.20261012, and RE-SETTLED on 0.1.20261016 -- see the toolchain-upgrade section below), not
inferred:

    ACCEPT   `fn opt(x : Int, y? : Int)` called as `opt(1)`
    ACCEPT   `fn labelled_default(x : Int, y~ : Int = 0)` called as `labelled_default(1)`
    REJECT 4080   `required()` against `fn required(x : Int)` -- omitting a REQUIRED parameter
    REJECT 3010   `fn f(y : Int = 0)` -- "Only labelled arguments can have default value", so the
                  default spelling is only legal on a `~`

The third row is the one that makes the rule a RANGE and not a blanket: `declared - omittable
<= arguments <= declared`. The floor is the REQUIRED count and the ceiling is the DECLARED count,
and a rule with either half missing is wrong in a different direction. M2 and M3 are the two
mutations that remove them, and each is killed by a CONTROL row rather than by a positive one.

MEASURED, the per-function view, before and after:

    corpus             0489                    0490
    moui             actionable 265      ->    actionable  58
    proton           actionable 136      ->    actionable  92
    moonbit_image    actionable  94      ->    actionable  68
    moonbit_labeler  actionable  95      ->    actionable  48

AND THE PINS DID NOT MOVE. The module view's numbers are byte-identical to the 0488 pins on all
six corpora -- moui 4225, labeler 791, image 218, async 1829/23/0/1852, proton 2131, contract 34
-- because every fix above is in the BEHAVIORAL lens and the module entry does not execute a
function body. That is the property the 0489 split was built for, and this increment is the
first thing that has exercised it: a change of this size in the lens, and the pinned numbers did
not move.

WHAT IS LEFT, and it is ONE class now rather than five. On moui, 35 of the remaining 58 are
`undefined variable 'Constant'` -- an enum VARIANT of `DeclarationChannel` used in a SIBLING file
of the same package -- and the rest are the same shape: `MoveEnd`, `MoveStart`, `Up`,
`FIM_HEADER_BYTES`, `QOI_OP_RGB`, `Rect`, `proton_err_buffer_too_small`. These are the SAME-PACKAGE
CROSS-FILE resolution gap, and the per-file `enum_ctors` limitation that the repository has
recorded since 0432. The behavioral lens is single-file, exactly as the other two lenses are, and a
library package is where that shows.

AND A COLLATERAL DEFECT, and it is one 0489 SHIPPED: the four `pkg.generated.mbti` files were
STALE. 0489 changed the public signature of `analyze_module` and `analyzed_sigs` (they take the
`enum_ctors` list now) and of `scan` (it takes the `per_function` flag), and added
`analyze_functions` and `run_functions` -- and did not regenerate the interface files that
DECLARE those signatures. `src/interp/pkg.generated.mbti` still said `analyze_module(...,
@core.IfaceSymTab)` with five parameters, and `src/sa/pkg.generated.mbti` still said `scan(String,
Array[String], Array[String], Bool, String)`. The header of each file says "Generated using
`moon info`, DON'T EDIT IT", and the repository's own history shows them being regenerated with
the source (0468 and 0469 each touched `src/ast/pkg.generated.mbti`). So the published interface
of four packages did not match their own source.

The cost of the staleness is small but the class is not: the scanner reads a `.mbti` for the
NAMES it declares, and a package whose interface is stale is a package that describes itself
wrongly to every consumer. Regenerated with `moon info` in `src/ast`, `src/interp`, `src/pipeline`
and `src/sa`.

GATE 0490 (the five lens defects): 7 KILLED, 0 declared survivors, every restore byte-identical. 1055 tests.

=> 判据: TWO LENSES SPELL THE SAME THING DIFFERENTLY, AND A COMPARISON BETWEEN THEM IS A
COMPARISON BETWEEN VOCABULARIES. `vmatches` compares a VALUE name against a TYPE name, and the
two lenses do not share a spelling for a list: `[int]` on one side, `List` on the other. The
defect was invisible because a list against a list is a MATCH in every language the lens speaks,
so the mismatch could only ever be found by a call. The fix is not a third spelling -- it is the
one place that has to know about both (`is_list_name`), and the element type is deliberately not
compared, because this lens models no list element types at all.

=> 判据: A LENS THAT HAS NEVER RUN IS NOT A LENS, IT IS A HYPOTHESIS. Four of these five defects
(`bin_widen`'s missing string arm, the comparison arm, the `if` value, the arity rule) were in
place since before the behavioral lens existed, and the corpus never showed them because the
module entry does not execute a function body. The per-function entry did not find them by being
smarter -- it found them by RUNNING, and every one of them is a false positive on code the
toolchain accepts. An instrument that has never been exercised is not an instrument.

=> 判据: A MEASUREMENT NEEDS A CONTROL, OR IT IS A NUMBER. "The list rule is gone" and "the list
rule was replaced by a blanket that silences every call whose parameter is a list" are the same
observation. Every row in `pipeline_0490_test.mbt` is paired with one that must STILL report: a
non-list value against a list parameter, a call that omits a REQUIRED parameter, a call that
passes too MANY arguments, a function whose body's last statement is a `let` (which returns
UNIT, and using that as a number IS an error), an `Int` added to a `String`, and an `Int`
compared with a `String`.

THE RELEASE GATE THEN FOUND THREE ANCHORS THAT 0490 HAD MADE STALE, and it found them LOUDLY
rather than silently -- which is the only reason the next paragraph exists at all.

    GATE FAILED: 0.4.25 mutation gate   PREFLIGHT MISS: M7 exec_alt missing else stops falling
    GATE FAILED: 0.4.26 mutation gate   PREFLIGHT MISS: M1 the tail value is not recorded
                                        PREFLIGHT MISS: M2 the tail pushes Bottom instead of the value
    GATE FAILED: 0431                   PREFLIGHT MISS: M4 an ORDINARY default value is not consumed

All three are the same shape, and the shape is the thing worth recording: 0490 changed the CODE
AROUND a decision, not the decision.

  0.4.25 M7  `exec_alt`'s unknown-condition arm grew two lines, because 0490 gave the else-if
              chain a VALUE (`val = vjoin(val, self.last_value)`) and published it
              (`self.last_value = val`). The decision under test -- `None => falls = true` -- is
              unchanged.
  0.4.26 M1/M2  the `STail` arm became a three-line block, because 0490 gave the interpreter a
              `last_value` and the tail's value now has TWO homes. The decision under test --
              "is the tail's value recorded, and is it the value that is pushed?" -- is unchanged.
  0431 M4  the pushed `Param` grew a field (`omittable`), so the anchor's LAST line stopped
              matching. The decision under test -- `ignore(self.parse_expr())` on the ordinary
              default path -- is unchanged.

A PREFLIGHT MISS IS THE LUCKY OUT. The harness had three ways to answer an anchor that no longer
matches: abort loudly (what it did), mutate the FIRST of several matches (what it would have
done with a short anchor that happened to occur twice), or retire the row. All three of these
anchors were ABSENT rather than AMBIGUOUS -- the pre-flight counts occurrences and reports the
two cases separately -- so the abort was the only thing that could happen. What the abort bought is
the time to notice that the decision under test had not moved. The alternative, a short anchor
that silently matched a different site, would have reported a clean kill for a question nobody
asked.

THE REPAIR IS A RE-ANCHOR, NOT A RETIREMENT, and the difference is worth spelling out because the
repository has already made this repair twice: 0449 re-anchored 0.4.26 M7 after a line was
inserted between two adjacent lines, and 0468 re-pointed 0.4.26 M3/M4 after a RENAME. A
retirement deletes a question; a re-anchor re-points the question at the same decision in the new
shape. What must NOT happen is the third option: inventing an anchor that merely MATCHES --
pointing M7 at some other `match els` because it also happens to contain the word `falls` -- and
that is how a gate ends up green while meaning nothing.

MEASURED, the three re-anchored gates, standalone, on the same tree:

    0.4.25   8 KILLED, 0 survivors   (M7 among them)
    0.4.26   7 KILLED, 0 survivors   (M1 and M2 among them)
    0431     3 KILLED, 1 declared survivor with its proof   (M4 among them)

Every restore byte-identical, every baseline green.

=> 判据: A PREFLIGHT MISS ASKS "DID THE CODE CHANGE SHAPE?" BEFORE IT ASKS "DID THE TEXT CHANGE?".
Get that order wrong and a RENAME looks like a DELETION -- which is exactly what `mutate_lib.ps1`'s
literal `IndexOf` matching did to 0443's M4 in 0467, where a DEDENT was indistinguishable from a
deletion. The text moved here and the code did not, and the honest repair is the one that KEEPS
ASKING: a re-anchor, and the prose in the gate script saying WHICH decision it still asks.

THE TOOLCHAIN WAS UPGRADED IN THE MIDDLE OF THE RELEASE GATE, and it is the second thing the gate
found, and the more interesting one.

The second run of the 73-gate release gate failed THIRTY gates -- 0459 through 0487 -- and every
one of them failed the same way, at one second each, with a message that was not about the code at
all:

    GATE FAILED: 0465
      ABORT: baseline did not run (no `Total tests:` line). The suite does not compile.
        what moon test actually printed:
          | moon.exe : Error: Failed to resolve the module dependency graph
          | Caused by:
          |     Cannot inject the standard library `moonbitlang/core`: Cannot load the core file

and, in another of them:

    Error: Sys_error("C:\\Users\\31379\\.moon\\lib\\core\\_build\\wasm\\release\\bundle\\prelude\\prelude.mi:
    No such file or directory")

The CAUSE was not in this repository. `C:\Users\31379\.moon\lib\core` and `...\bin` were REWRITTEN
at 2026-10-20 00:54:16, and the whole standard library was rebuilt between 00:54:32 and 00:54:38
-- while the gate was running. The toolchain went from **0.1.20261012** to **0.1.20261016** in the
middle of the run. The gates that failed are exactly the ones that happened to be executing during
that window, and the ones after it -- 0488, 0489, 0490 -- passed, because the standard library was
whole again by then.

Nothing in this repository asked for that upgrade. The registry index was refreshed at 00:52:29 and
`riantr/moonbit_doubleML 0.163.9` was cached at 00:45:12, so another project on this machine was
installing from mooncakes.io at the same time, and the toolchain went with it.

AND THE UPGRADE HAD TWO CONSEQUENCES FOR THE WORK, one mechanical and one substantive.

THE MECHANICAL ONE: THE TOOLCHAIN NOW REGENERATES THE `.mbti` INTERFACE FILES ITSELF. Under
0.1.20261012 `moon check` and `moon fmt` left `src/*/pkg.generated.mbti` alone, which is why 0490
had to regenerate four of them by hand and why this repository's own history notes the header
"Generated using `moon info`, DON'T EDIT IT". Under 0.1.20261016 the build writes them, and FIVE
MORE changed on their own -- `core`, `lexer`, `moonfiles`, `types`, `walk` -- every one of them the
same shape:

    -  pub fn pos(Int, Int) -> Pos
    +  pub fn pos(Int32, Int32) -> Pos
    -  line : Int
    +  line : Int32

That is the SAME defect 0490 fixed in four files, in the five files 0490 did not touch: 0.1.20261012
renamed the default integer type, `moon fmt` rewrote this repository's SOURCE to `Int32`, and the
committed interface files kept the old spelling. They were stale, and the new toolchain noticed.
Measured, not assumed: `_verify/_mbti_regen_probe.ps1` restores `src/core/pkg.generated.mbti` from
`HEAD` (the `Int` spelling) and runs `moon check` -- and the file comes back with `Int32`. The
toolchain regenerates it.

THE SUBSTANTIVE ONE: **A SETTLED FACT IS A CLAIM ABOUT A TOOLCHAIN VERSION, AND ONE OF 0490's WAS
INVERTED.** 0490's `n_omittable` comment said:

    the toolchain settles that: `fn f(x~ : Int)` called as `f(1)` is accepted, but `f(x=1)` is
    rejected with 4085, "This function has no parameter with label x~"

That is WRONG ON BOTH HALVES, and the toolchain says the opposite:

    ACCEPT         `fn f(x~ : Int)` called as `f(x=1)`   -- BY LABEL
    REJECT 4086   `fn f(x~ : Int)` called as `f()`       -- "The labels x~ are required by this
                                                          function, but not supplied."
    REJECT 4086   `fn f(x~ : Int)` called as `f(1)`     -- a POSITIONAL pass fails too, with 4080
                                                          as well: "requires 0 positional arguments,
                                                          but is given 1"
    REJECT 4085   `fn f(x : Int)` called as `f(x=1)`     -- and 4085 belongs to THIS row: a label
                                                          on a POSITIONAL parameter, not on a `~` one

The CONCLUSION the wrong evidence was offered for -- "`~` alone does not make a parameter
omittable" -- was RIGHT, and so was the CODE, because the parser sets `omittable` only for `?` and
for a default value. So this was a false STATEMENT in a comment, not a false rule in the analyzer.
The `omittable` flag is set for exactly the two spellings the toolchain allows to be omitted, and
the arity floor is exactly the required count.

WHAT MAKES IT WORTH THE SPACE is that the repository ALREADY HAD THE CORRECT VERSION OF IT, in a
different file, written earlier: `src/lexer/lexer.mbt`'s `TTilde` note (0.4.18) says a `~`
parameter "must be supplied BY LABEL" and that the compiler "rejects a positional pass with 'The
labels f~ are required by this function, but not supplied.'" That is EXACTLY right, and it was
there before 0490. So the defect was not a missing measurement -- it was a SECOND, contradictory
copy of a measurement the repository already held, and a reader who went to the lexer would have
found the truth.

THE RE-SETTLE that caught it is `_verify/_settle_0490_resettle.ps1`: EIGHTEEN rows, ONE PACKAGE
EACH, on the installed toolchain. One package per row because a single package cannot hold two
rows -- one row's error would mask another's -- and the whole point of a settle is to see each
verdict separately. All eighteen agree with 0490's conclusions, and the two the old comment got
backwards are among them.

And the settle script itself had a bug worth recording, because it produced four false REJECTs on
its first run: **`moon.mod` IS NOT JSON.** It is `key = "value"`, and a JSON body is a PARSE ERROR
-- "unexpected token { at line 1, column 1" -- which the toolchain reports as "Failed to calculate
build plan". A build failure that looks like a settle verdict is neither. The four rows that came
back REJECT for the wrong reason were exactly the four that were supposed to be ACCEPT.

=> 判据: A SETTLED FACT IS A CLAIM ABOUT A TOOLCHAIN, AND THE CLAIM HAS TO NAME THE VERSION. Every
fact 0490 settled cited `moon check` 0.1.20261012 by number, and the toolchain moved to
0.1.20261016 in the middle of the release gate -- so every one of them had to be re-checked against
what is actually installed, and one was found INVERTED. The number in the citation is not
decoration: it is what makes the claim checkable. And a fact that is settled ONCE and then quoted
in a second file is a fact with two copies and no owner, and the second copy is where the
inversion went.

THE THIRD RUN OF THE GATE FAILED ON THE SELF-SCAN, and it is the most interesting of the three
failures, because what it found was not a lens defect at all. It was a TOOLCHAIN RENAME that the
analyzer's own tables had not followed.

    GATE FAILED: self-scan (own source)
      files=159 parsed=159 actionable=37 notices=1749 unreliable=0 withheld=0 total=1786
      FAIL: actionable is not 0.

Thirty-seven findings, and EVERY ONE of them was the same line:

    unknown type 'Int32' in interface signature (not declared here, not builtin, not in any scanned interface)

-- in the analyzer's OWN `src/*/pkg.generated.mbti` files, the ones the new toolchain had just
rewritten. The `.mbti` frontend resolves a signature's type names against the ambient list, and the
ambient list carried `Int` and not `Int32`.

THE TOOLCHAIN CHANGED THE CANONICAL SPELLING OF TWO BUILTIN TYPES, and the version that did it is
**0.1.20261012**, not the 0.1.20261016 this section first blamed. The repository ALREADY SAID SO, in
THREE places -- and all three are in ONE commit, `1c6de6e5` ("Match named arguments by NAME, and
read Int32 as Int", 2026-10-12), whose `moon.mod` reads `version = "0.4.22"`:

    src/types/types_0422_test.mbt:20       0.1.20261012 renamed the default integer type to `Int32`.
    src/pipeline/pipeline_0422_test.mbt:6   `Int32` reads as `Int` (0.1.20261012 renamed the default
                                            integer type)
    src/pipeline/pipeline_0422_test.mbt:492  0.1.20261012 renamed the default integer type. The
                                            formatter rewrote this

AND 0490 SAID IT BOTH WAYS IN ITS OWN COMMIT. `6138f34` wrote the RIGHT version into this same
file, in the toolchain-upgrade section above, at line 3390:

    That is the SAME defect 0490 fixed in four files, in the five files 0490 did not touch: 0.1.20261012
    renamed the default integer type, `moon fmt` rewrote this repository's SOURCE to `Int32`, and the
    committed interface files kept the old spelling. They were stale, and the new toolchain noticed.

-- and the WRONG version right here. The same commit, the same file, both numbers, seventy-three lines
below it in that commit. The file was not uniformly wrong, and that is exactly why the error
survived: a reader who checks the claim finds a correct answer and stops looking.

So the version was settled in 0.4.22 and written down THREE times, and 0490 wrote it EIGHT more
times -- SEVEN wrong, in seven files, and ONE right, in one of those same seven files:

    _verify/NARRATIVE.md                      src/core/builtins.mbt
    _verify/mutate_0490.ps1                   src/moonfiles/moonfiles_0490_test.mbt
    _verify/settle_0490_int32.ps1             src/pipeline/pipeline_0490_test.mbt
    tools/gen_builtin_methods.ps1

That is the same defect this section records about the `~` marker a few paragraphs up: a fact
settled once and then quoted in a second file is a fact with two copies and no owner, and the
second copy is where the inversion goes. When the second copy lands in the SAME FILE as the first,
the inversion is invisible to the reader who checks.

THE OFFICIAL DOCUMENTATION SETTLES WHAT CHANGED, and it is not quite a RENAME. From MoonBit's own
Language Fundamentals page (https://docs.moonbitlang.com/en/latest/language/fundamentals.html):

    Int and UInt remain accepted as aliases of Int32 and UInt32. The formatter uses the
    explicit-width names Int32 and UInt32.

and the type table on the same page lists `Int16`, `Int32`, `Int64`, `UInt16`, `UInt32`, `UInt64`,
`Double`, `Float` and `BigInt` -- `Int` and `UInt` are no longer IN the table, only mentioned as
aliases. So:

  - the TYPE did not change. `Int` is still `Int`, as an ALIAS. Both spellings compile, and
    `moon check` accepts either in either position -- which is what 0490's settle measured.
  - the CANONICAL SPELLING did change, to the explicit-width name, and `moon fmt` enforces it.
  - the DECLARATION moved. The `moonbitlang/core` library used to declare the integer type in its
    own `int` and `uint` packages -- now `#deprecated` -- and the new toolchain declares it in
    `builtin` under the new names.

Measured on the installed core, `builtin/pkg.generated.mbti` carries 76 `Int32::`/`UInt32::`
declarations and ZERO `Int::`/`UInt::`, and `int/pkg.generated.mbti` says
`pub const MAX_VALUE : Int32 = 2147483647` where the September copy said `pub const MAX_VALUE : Int
= 2147483647`. The core library's own commit history says the same thing in its subject line, on
every package at once: `Update for moon 0.1.20261012 (Int32/UInt32, new deprecations)`, Oct 13 2026.

SO THE TWO VERSIONS DID TWO DIFFERENT THINGS, and 0490's first account merged them:

  0.1.20261012 (Oct 13)  renamed the default integer type. From that day the analyzer's ambient
                         type list and its method table were BOTH stale: the `.mbti` frontend
                         reported `unknown type 'Int32'` on any interface the toolchain generated,
                         and the behavioral lens reported `undefined function 'Int32::popcnt'` on a
                         call that compiles. The repository's TYPE lens had been taught in 0.4.22
                         (`ann_to_ty`'s `"Int32"` arm); the other two places were never taught, and
                         the corpus is frozen at the old toolchain, so nothing else would have
                         shown it.
  0.1.20261016 (Oct 16)  started REWRITING this repository's own `src/*/pkg.generated.mbti`, which
                         is what put the stale `Int` spelling in front of the analyzer's self-scan
                         and turned a seven-day-old defect into a RED GATE. It also removed the
                         deprecated `Bool::to_int16` (`chore(builtin): remove deprecated
                         Bool::to_int16 (#4409)`, Oct 16) -- measured: that name is in the September
                         copy of `builtin/pkg.generated.mbti` and gone from the installed one, and
                         it is one of the 33 DEAD names the regenerated table dropped.

The defect window is therefore 0.1.20261012 -> 0490, and every user on a toolchain from Oct 13 was
getting both false positives. The upgrade did not CAUSE it; it EXPOSED it, in our own tree.

`Int16` and `UInt16` were NOT renamed -- the change is of the UNSUFFIXED names only, which is what
makes it a change of canonical spelling rather than a widening. And the change is not confined to
the interfaces: the toolchain declares ALL FORTY-FOUR of the integer type's methods under `Int32::`
and NONE under `Int::`,

    44   Int32::abs, Int32::add, Int32::asr, ... Int32::unsafe_to_char
    0    Int::...                                   <- the same forty-four, under the old name

-- so the defect has TWO faces, and the second is the more expensive one:

  M8  THE AMBIENT TYPE LIST did not learn the new names, so every interface the new toolchain
      generates reported `unknown type 'Int32' in interface signature`. Thirty-seven findings on
      this repository's own files -- and in the DEFAULT view, so every user on the new toolchain
      was getting them too.
  M9  THE METHOD TABLE did not learn them either. `Int32::popcnt(x)` is legal MoonBit -- and it is
      what `moon fmt` rewrites `Int::popcnt(x)` into, because the new spelling is the toolchain's
      canonical form -- and it was reported `undefined function 'Int32::popcnt'`.

BOTH SPELLINGS ARE KEPT, and the reason is that they are the SAME type. Settled with the toolchain,
one package per row, with a control module that must be rejected
(`_verify/settle_0490_int32.ps1`, NINETEEN rows):

    ACCEPT   `let x : Int32 = 1`            ACCEPT   `let x : Int = 1`
    ACCEPT   `fn f(x : Int32) -> Int`       ACCEPT   `fn f(x : Int) -> Int32`
    ACCEPT   `Array[Int32]`, `Map[String, Int32]`, `type MyInt = Int32`
    REJECT 4032   a type that cannot exist                  <- the CONTROL

and `_verify/settle_0490_intrinsic.ps1`, TEN rows, for the names NO interface declares -- the
`T::to_json` family and `unsafe_to_char`, which the generator keeps in a HAND-WRITTEN list and which
therefore no extraction can reach and no carrying-forward can supply:

    ACCEPT   Int32::to_json      ACCEPT   UInt32::to_json      ACCEPT   Int32::unsafe_to_char
    REJECT 4015  UInt32::unsafe_to_char     REJECT 4015  Int32::to_jsonnope    <- the CONTROL

A PROBE THAT DECLARES THE WRONG RETURN TYPE LOOKS EXACTLY LIKE A MISSING METHOD. `T::to_json`
returns `Json`, not `String`, and a probe that says `-> String` gets 4014 "Expr Type Mismatch" --
which reads as "the method does not exist" and is a PROBE BUG, not a toolchain fact. It cost one
round of settling and it is worth recording, because the wrong reading would have removed eighteen
LIVE names from the table.

THE TABLE IS A SUPERSET, AND THE SPELLING CHANGE IS WHY THAT RULE HAD TO BE WRITTEN DOWN. The
generator's own header already said "It can never invent a false alarm, because the table only ever
suppresses" -- and the spelling change is the case that sentence did not cover. Running the
generator on the new toolchain produced 1163 names against the committed 1265: 102 LOST, 0 gained,
because the new interfaces no longer declare the old spellings.

AND THE 102 SPLIT CLEANLY ONCE IT WAS MEASURED, into two different upgrades:

    84   the SPELLING CHANGE of 0.1.20261012 -- `Int::abs` is now `Int32::abs`, and the
         `UInt::` family is now `UInt32::`. The same declarations, under the explicit-width
         names, moved from the (now deprecated) `int` and `uint` packages into `builtin`.
    18   0.1.20261016's own changes -- the `Buffer::write` family was renamed
         (`Buffer::write` is `Buffer::write_bytes` and friends), the deprecated `Bool::to_int16`
         was removed (`#4409`, measured: present in the September copy of
         `builtin/pkg.generated.mbti`, gone from the installed one), and a few more.

Those 102 are NOT all dropped names. One module per name, with a control module that must be
rejected (`_verify/_settle_0490_builtins_alive.ps1`): 33 are DEAD -- the call is rejected, so
reporting it would be CORRECT -- and 69 are ALIVE, the call is accepted, and dropping them turns
valid code into `undefined function`. Measured on the analyzer itself, in the per-function view:
`Int::popcnt`, `Int::next_power_of_two`, `UInt::trunc_double`, `Int::reinterpret_as_uint`,
`Int::to_char`, `Int::to_byte` and `UInt::add` all became REPORTS on code `moon check` accepts, and
the last two are CALLED by moui 0.1.12.

    keeping a name the toolchain has DROPPED  -> a MISSED report   (accepted)
    dropping a name the toolchain still HAS    -> a FALSE POSITIVE (not accepted)

AND THE SIX PINS STILL MATCHED WITH THE REGENERATED TABLE, which is worth a sentence of its own
because it is what a pin that cannot distinguish two states looks like. The pins are measured in the
MODULE view, which never executes a function body, and the false positives live in the per-function
view -- so the table could have been wrong and the pins could not have said so.

THE REPAIR IS THE UNION, and it is the same repair the generator already applies to its intrinsic
list. The previous table is read back and unioned in, so the table is the union of what the current
interfaces declare, what the intrinsics add, and what the previous table held. Measured on
0.1.20261016 with the committed table in place:

    declared in .mbti         1143
    carried forward            102      <- the names the new interfaces dropped
    intrinsics                  32      (12 of them are ALSO declared in an interface)
    total                      1265      <- the committed count, with NOTHING lost

and with the rename applied -- "Int32" and "UInt32" added to the bare type list, so the extraction
picks up the new spellings -- the table is 1344 names across 40 heads, carrying BOTH spellings of
every renamed method.

A SECOND COUNT WAS ALSO WRONG. The header said `$declared + $intrinsic.Count`, which double-counts
the intrinsics an interface ALSO declares -- twelve of the thirty-two, so every version of the file
was 12 too high (1277 against 1265). The overlap is now COMPUTED rather than assumed, and the
header counts the set.

GATE 0490, IN FULL: 9 KILLED, 0 declared survivors, every restore byte-identical. 1061 tests. The
self-scan is 0 actionable, and the six corpus pins are byte-identical to the 0488 numbers on all
six corpora -- moui 4225, labeler 791, image 218, async 1829/23/0/1852, proton 2131, contract 34.

=> 判据: A TOOLCHAIN RENAME IS A CHANGE TO THE ANALYZER'S TABLES, AND NO AMOUNT OF READING THE
ANALYZER'S OWN SOURCE WILL FIND IT. Every one of these tables is a list of names the TOOLCHAIN
publishes, and the analyzer is the only thing that knows they can change. The self-scan found it in
twelve seconds, because the analyzer's OWN regenerated interfaces were among the files it scanned.
The corpus -- frozen at the old toolchain, and green on all six -- would never have shown it. A
green corpus is not a green analyzer.

=> 判据: A TABLE THAT ONLY SUPPRESSES HAS ASYMMETRIC FAILURE DIRECTIONS, AND THE ASYMMETRY IS THE
RULE. "The table is a MIRROR of the toolchain" and "the table is a SUPERSET of the toolchain" look
like the same sentence until the toolchain renames something. Then one of them loses sixty-nine
live names and the other loses nothing. The direction the repository already accepted -- a missed
report is cheaper than a false positive -- was written into the generator's header as a warning, and
the rename is what turned the warning into a rule.


## 0491: THE CROSS-FILE NAME THE BEHAVIORAL LENS REFUSED TO RESOLVE

0490 took the per-function view's moui count from 265 to 58, and the 58 were CLASSIFIED before any
fix was written -- the classes were the diagnosis:

    A = 51  CROSS-FILE NAMES
    B =  1  an `is`-pattern binding scope (`anchor`)
    C =  4  `None`-receiver method errors
    D =  1  a cross-file constructor arity
    +   1  `unreachable code`

This increment is class A, and it is the only one of the four that was a defect in the ANALYZER
rather than in the analysed code: all 51 were findings on code `moon check` accepts, and every one
of them was produced by a lens that had been asking the WRONG QUESTION in one place and the RIGHT
question everywhere else.

THE DEFECT IS ONE LINE, and the evidence for it is three places in the source that already
disagreed with each other:

    the STRUCTURAL lens's "no visible binding" gate   walk.mbt:363-371   asks the table
    the TYPE lens                                       infer.mbt:100-113  asks the table
    the BEHAVIORAL lens's CALL path                    interp.mbt:1663    asks the table
    the BEHAVIORAL lens's READ path                     interp.mbt:1025    DID NOT

And the call path's own comment says what the read path should have said:

    the alternative is reporting the name as undefined, which CONTRADICTS the structural and
    type lenses (both of which consult the same table and stay silent)

Two lenses, one line, opposite answers.

THE READ PATH IS THE `EName` ARM of `Interp::eval`, and it consults, in order: the environment, the
globals, the local function table, the method table, the ambient table, the constructor table --
and then, before this increment, the cross-file table was simply ABSENT. So a name bound in a
SIBLING FILE of the same package, or in a dependency, was reported `undefined variable` by the
behavioral lens while the other two stayed silent on the same line.

MEASURED, moui 0.1.12, the per-function view: 51 findings of this shape, of which 35 are
`undefined variable 'Constant'` -- an enum variant of `pub(all) enum DeclarationChannel` in
`core/declaration.mbt`, read bare in `core/modifier_paint.mbt`. The rest are the same shape: the
unit variants of a `priv enum` in a sibling file (`MoveLeft`, `MoveRight`, `MoveStart`, `MoveEnd`),
`Up`, `view_size_key`, `DeclarationKey::double`, and the package-private `dispatch_web_open_url`,
`dispatch_web_settings`, `dispatch_web_clipboard_write_text`, `web_active_app`,
`clone_semantics_issue` and `macos_perf_now_ms`.

AND THE COUNT IS 51, NOT THE 49 the printed scan showed, and the difference is worth a paragraph
because it is the SECOND time this repository's own print path has hidden findings from a
measurement. `sa/main.mbt:317` truncates the PRINTED findings per file at `findings_shown_per_file`
while `aggregate` counts them all -- so a file whose actionable count passes the cap prints fewer
findings than it has, and the SUMMARY line is right while the transcript is short. MEASURED on the
two scans this increment produced:

    0490   58 actionable   56 printed   2 hidden   (core/modifier_paint.mbt,
                                                      runtime/semantics.mbt)
    0491    7 actionable    7 printed   0 hidden

Both hidden ones were cross-file names, so the class-A count is 51 and not the 49 the printed set
showed.

=> 判据: A COUNT READ OFF A TRANSCRIPT IS A COUNT OF WHAT WAS PRINTED, AND THE PRINTER HAS A CAP.
The SUMMARY line counts what the analyzer FOUND. A diff of two transcripts measures what the
printer SHOWED. When the two disagree by 2, the 2 are not a rounding error -- they are findings, and
here they were findings of the very shape being fixed.

SETTLED WITH THE TOOLCHAIN, `_verify/settle_0491_crossfile.ps1`, TWELVE rows on the installed
toolchain, because the claim being settled is the TOOLCHAIN's and not the analyzer's: does MoonBit
ACCEPT these shapes? Every ACCEPT row is code the toolchain must accept, and every REJECT row is a
control the toolchain must REFUSE, so that "the analyzer must stay silent" cannot be satisfied by
silencing everything.

    ACCEPT   a bare unit variant of a `pub(all)` enum, read in a SIBLING file
    ACCEPT   a bare unit variant of a `priv` enum, read in a SIBLING file
    ACCEPT   a package-private `fn`, CALLED from a sibling file
    ACCEPT   a package-private `let`, READ bare from a sibling file
    ACCEPT   a `pub const`, READ bare from a sibling file
    ACCEPT   a qualified `pub fn`, CALLED from a sibling file
    ACCEPT   all of them, together, in ONE sibling file
    REJECT   a package-private `fn` from ANOTHER package
    REJECT   a bare variant of ANOTHER package's enum
    ACCEPT   the same names, QUALIFIED, from another package
    REJECT   a name that exists NOWHERE   <- the control the analyzer must keep reporting

A PACKAGE IS A DIRECTORY, and that is the rule the analyzer's per-package private table encodes. The
rows are built as a TWO-PACKAGE project -- `src/pa` declares, `src/pb` is a different package that
imports it -- and one package per row because a single package cannot hold two rows: one row's error
would mask another's, and the whole point of a settle is to see each verdict separately.

THE FIX IS ONE BRANCH, in the `EName` read chain, and it asks the same two questions the call path
asks:

    } else if self.extern_iface.has_value(n) ||
      self.extern_iface.has_type(n) {
      AAny
    }

`AAny` -- "a value of unknown type" -- because the table says a name IS bound and says nothing about
what it IS. `has_value` cannot tell a function from a constant: the table records that difference in
a flag (`is_const`) this lens has no reason to read. Claiming `AType("Function")` would claim more
than the table knows, and mutation M3 below is what that costs.

BOTH HALVES ARE KEPT, and the reason is the one 0490 wrote down about the builtin method table: the
structural lens's gate asks `!has_type(name) && !has_value(name)`, so a lens that asked only one of
the two would still contradict it. A MISSED report is accepted; a FALSE POSITIVE is not.

MEASURED, the per-function view, before and after:

    corpus             0489                    0490                    0491
    moui             actionable 265      ->    actionable  58      ->    actionable   7
    proton           actionable 136      ->    actionable  92      ->    actionable   5
    moonbit_image    actionable  94      ->    actionable  68      ->    actionable  44
    moonbit_labeler  actionable  95      ->    actionable  48      ->    actionable  40

AND THE SIX MODULE-VIEW PINS DID NOT MOVE: moui 4225, labeler 791, image 218, async 1829/23/0/1852,
proton 2131, contract 34 -- byte-identical to the 0488 numbers, because the module entry never
executes a function body and so never reached the read path this fix touches. The self-scan is 161/161
parsed, actionable 0, notices 1761.

AND THE FIRST DRAFT OF THAT SENTENCE SAID 160/160 AND 1755, WHICH ARE THE **0490** NUMBERS. They were
measured on a tree that did not yet contain this increment's own test file: the 0491 run measured 161
files and 1761 notices (`_verify/release_0491_run.txt`), and the 160/1755 pair is the earlier
`-SkipMutations` run, from before that file existed. A number quoted from a run that PREDATES the
increment it describes is the same defect as a fact quoted into a second file -- the copy has no
owner, and the OLDER copy is the one that was true.

THE SEVEN THAT REMAIN on moui are the other classes, and they are named here so that the next
increment does not have to rediscover them:

    undefined variable 'anchor'                             (UndefinedName) -- class B
    no method matching clamp_int(None, int, Any)            (MethodError)    -- class C
    no method matching web_string_append_char(None, Any)    (MethodError)    -- class C
    no method matching web_finish_create_string(None)       (MethodError)    -- class C
    no method matching >(None, float)                       (MethodError)    -- class C
    no method matching RouteHistoryState::from_routes(...)  (MethodError)    -- class D
    unreachable code                                        (Unreachable)

GATE 0491, IN FULL: 4 KILLED, 0 declared survivors, every restore byte-identical. 1067 tests. The
gate had to be REGISTERED in `release.ps1`'s gate list to run at all -- the list ended at '0490', and
a gate that is not in the list is a gate that is not run, which is the same shape as a gate that
reports a result it never produced.

AND THE TWO MUTATIONS THAT HAD TO BE FIXED BEFORE THE GATE COULD SAY THAT are worth the space,
because both of them were gates that LOOKED fine.

THE FIRST VERSION OF M3 SURVIVED, for the most embarrassing reason imaginable: the assertion was on a
family this lens never emits. `Interp::binop`'s fallback arm reports `FMethodError` -- "no method
matching +(...)" -- and `FOpMismatch` is the TYPE lens's family. The row asserted
`count_family(perfn, "OperatorMismatch") == 0`, which stayed 0 while the mutant answered
`AType("Function")` and produced a real `MethodError`.

The two families SHARE A MERGE GROUP -- `Family::merge_group` puts `FArgType | FMethodError |
FOpMismatch` under "arg-type" -- and a merge group is not a family, so a count BY FAMILY cannot see
the other one. MEASURED under the mutation: exactly ONE `MethodError`, from the behavioral lens, at
`pipeline_0491_test.mbt:153`.

=> 判据: TWO FAMILIES THAT SHARE A MERGE GROUP ARE STILL TWO FAMILIES. Asserting the wrong one is
not a weak assertion -- it is an assertion about a finding this lens never emits, and it is green
forever.

THE FIRST VERSION OF M4 WAS KILLED BY THE WRONG TEST. The blanket -- the branch firing for every
name -- was killed by a pre-existing merge test, `merge: one defect, three lenses, ONE finding`, and
NOT by the control row that was written to kill it.

The reason is the MERGE. BOTH lenses report the unbound name -- the structural lens says "no visible
binding for 'helper'", the behavioral lens says "undefined variable 'helper'" -- at the SAME span,
so the two collapse into ONE finding whose lens list is the union. `count_family(perfn,
"UndefinedName") == 1` is therefore satisfied by the STRUCTURAL lens ALONE, and a blanket that
silenced only the BEHAVIORAL lens still passes it.

The control row now counts `count_family_in(perfn, "UndefinedName", @core.LBehavior)`, and under the
blanket it goes red at `pipeline_0491_test.mbt:91`. The row is now a control OF THE LENS IT IS ABOUT.

=> 判据: A MERGED FINDING IS COUNTED BY FAMILY, BUT A CLAIM ABOUT ONE LENS'S DECISION HAS TO BE
COUNTED BY LENS, OR THE OTHER LENS ANSWERS FOR IT.

AND THE STRUCTURAL LENS'S OWN COMMENT ALREADY SAID IT. The whole defect -- a lens that asks the
cross-file table in one place and not in another -- was ANSWERED IN THE SOURCE, in the sibling
branch, in a comment that explains WHY the table must be asked. The read path did not get the same
treatment, and the difference is 51 false positives on code `moon check` accepts.

=> 判据: A LENS THAT ASKS A QUESTION IN ONE PLACE HAS TO ASK IT EVERYWHERE, AND THE PROOF THAT IT
DOES NOT IS A COMMENT IN THE BRANCH THAT DOES.


## 0.4.30 POST-PUBLISH: THE GATE THAT SAID "OK" WITHOUT READING ANYTHING

(The release was published and verified. This is the defect the verification ITSELF found, and it is
a defect in the CHECK rather than in the analyzer -- which is the only kind of defect a release
verification can still find once the release is out.)

THE PUBLISHED-PACKAGE SELF-SCAN reported

    GATE OK: the published 0.4.30 scans its own shipped source clean.

on a scan that had read NOTHING AT ALL.

The 2026-10-20 run of `_verify/selfscan_published.ps1` asked the registry for
`riantr/moonbit_static_analysis@0.4.30`. The download from `download.mooncakes.io` TIMED OUT.
`moonx` created the package directory anyway, EMPTY, and the scanner -- pointed at an empty
directory -- printed a perfectly well-formed report:

    SCANNED  0 files under .repos/riantr/moonbit_static_analysis/0.4.30
    SKIP     .repos/riantr/moonbit_static_analysis/0.4.30/moon.mod unreadable: OSError(...)
    PARSED   0/0 files understood (0.0%)
    SUMMARY  files=0 parsed=0 actionable=0 notices=0 unreliable=0 withheld=0 total=0

EVERY CHECK IN THE SCRIPT PASSED, because every check was a TRUE STATEMENT ABOUT NOTHING:
`actionable=0` is true of a tree with no files in it, `parsed=0/0` is true of a tree with no files
in it, and there was no non-ParseError error line to object to. The sum of true statements about
nothing is GATE OK.

The script's own header had already warned about a version of this -- "EMPTY OUTPUT IS A FAILURE,
NOT A ZERO. Six 0-byte dumps once printed a line per corpus and read as a clean result." That guard
catches a scan that printed NOTHING. The missing guard was ONE LEVEL DOWN: it catches a scan that
printed a SUMMARY and read nothing at all.

THE FIX IS TWO ASSERTIONS, both on the SCANNER's own output rather than on `moonx`'s wording:

  * the scanned file count must be GREATER THAN ZERO;
  * the package's own `moon.mod` must not appear in a `SKIP` line.

The second one is the stronger of the two, and it is worth saying why: the `SKIP` line for the
package's OWN `moon.mod` is the fingerprint of an empty tree. A tree that was really fetched has a
readable `moon.mod`, and the scanner reads it -- it needs it to resolve the package's imports, which
is why the healthy capture carries a `FETCH 1 import(s) from moon.mod` line right after the
`SCANNED` line.

=> 判据: A GREEN GATE THAT NEVER READ THE ARTIFACT IS A GREEN GATE ABOUT NOTHING. "THE SCAN WAS
CLEAN" AND "THE SCAN WAS OF SOMETHING" ARE TWO DIFFERENT CLAIMS, AND ONLY THE SECOND ONE IS WORTH
ANYTHING.

AND THE PROOF THAT THE GUARD IS LOAD-BEARING HAS THREE PARTS, because a guard that has never been
shown to go red is a comment.

THE FIRST PART -- THE GUARD FIRES. Both captures are REAL, and they are committed rather than
regenerated, because a fixture written to make a guard look good is worth nothing:

    _verify\fixtures\selfscan_empty_tree_0430.out   719 bytes   the timed-out 0.4.30 download
    _verify\fixtures\selfscan_healthy_0429.out      93 KB      the published 0.4.29 tree

Replaying the empty-tree capture now FAILS, with EXACTLY TWO checks failed -- the zero-file
assertion and the `moon.mod` SKIP assertion, and nothing else. The count matters: if a third check
also fired, the capture would be failing for some other reason and this evidence would be about that
reason instead.

Replaying the healthy capture still PASSES: 68 files, parsed 68/68, actionable=0, 823 notices. The
guard does not fire on a real tree.

THE SECOND PART -- THE GUARD IS THE CAUSE, NOT A PASSENGER. `selfscan_published.ps1` grew a
`-SelfTestNoTreeGuard` switch, and it is honoured ONLY in replay mode, so the live gate can never be
disarmed by a stray flag. With the guard disarmed, the SAME empty-tree capture PASSES and reports
the empty tree as clean -- which is the 2026-10-20 behaviour, reproduced on demand. That is what
makes the first part mean something: without it, a gate that was red for some other reason (a
changed version assertion, a reworded message) would look exactly like a working guard.

THE THIRD PART -- THE CONTROL ON THE OLD CODE. The script as it stood at `825c506` was run against
the same capture, with the network call removed and the capture substituted for its output, and with
nothing else changed. It printed:

    GATE OK: the published 0.4.30 scans its own shipped source clean.

exit 0. The vacuous pass is not a story about what the old script "might" have done; it is what the
old script did, on the bytes in the repository.

=> 判据: A GUARD THAT WAS NEVER SEEN TO GO RED IS A COMMENT, AND A GUARD THAT GOES RED FOR THE
WRONG REASON IS A COMMENT WITH A LOUDER VOICE. THE PROOF IS THE CAPTURE, THE CONTROL, AND THE
CAUSE -- IN THAT ORDER.

THE SELF-TEST IS A STAGE NOW, not a thing I did once. `release.ps1` runs
`_verify/selftest_selfscan_published.ps1` as stage 5a, BEFORE the live stage 5b that uses the gate
under test. It is FAST and OFFLINE -- it fetches nothing -- so it does not add a second dependency
on a registry that has already timed out twice in one afternoon.

THE LIVE RE-RUN, once the download worked, is the other half of the story:

    scanned 143 files under .repos/riantr/moonbit_static_analysis/0.4.30
      ok  the tree scanned is 0.4.30
      ok  parsed 143/143 files
      SUMMARY  files=143 parsed=143 actionable=0 notices=1421 unreliable=0 withheld=0 total=1421
    GATE OK: the published 0.4.30 scans its own shipped source clean.

143 is not a number to be pleased about; it is a number to be CHECKED, and it checks out exactly.
Tag `v0.4.30` contains 126 `.mbt` + 16 `.mbti` + 1 `.mbtp` = 143 files, and the scanner read
143 of them and parsed 143 of them. The published package is therefore COMPLETE -- nothing tracked is
missing from the artifact, and nothing untracked leaked into it.

The 18 files in the repository that the package does NOT contain are accounted for, and every one of
them is a file that was never meant to be shipped: 17 `_verify\_work_*.mbt` scratch copies of source
files, and `src/lexer/lexer_0488_test.mbt`, which is deliberately untracked. The repository-wide
scan reads 161 files -- the same 161 it read before any of this -- and the two committed fixtures
are invisible to it, because the scanner only reads the toolchain's own file kinds.

THE 68 -> 143 IS NOT A PACKAGING CHANGE, and it is worth saying so before someone asks: 0.4.29
shipped 51 `.mbt` and 0.4.30 ships 126, because the increments 0470-0491 added the test files for
the 19 new grammar forms. The 0.4.29 tree had 22 non-test `.mbt` files and so does 0.4.30; what
grew is the test suite around them.

=> 判据: A FILE COUNT IN A PASSING GATE IS A CLAIM ABOUT A PACKAGE, NOT A NUMBER TO BE PLEASED
ABOUT. "143 FILES READ" IS ONLY WORTH SAYING ALONGSIDE "143 FILES EXIST", OR IT IS A NUMBER THAT
COULD HAVE COME FROM ANY TREE.

AND ONE THING THIS DOES NOT CHANGE, stated plainly: `_verify\` IS NOT PUBLISHED. The package
contains only the toolchain's file kinds, so this fix changes the GATE and not the ARTIFACT. The
shipped 0.4.30 is exactly the 0.4.30 that was tagged, and it does not need to be re-published --
but the gate that would have told us so was, until this commit, one that could not tell us anything
at all.


## 0492: THE PARAMETER THAT WAS RE-BOUND AND FORGOT ITS TYPE

(IT WAS FOUND BY AUDITING A GATE, and the chain is worth recording, because every step of it was a
measurement and not a guess. The audit was for Direction 1's remainder -- "13 gates still carry their
own copy; mutate_0412/0413 lack pre-flight and SHA256".)

DIRECTION 1'S REMAINDER IS ALREADY DONE, and the goal's note about it is STALE. MEASURED: all 74
numbered gates `require` `mutate_lib.ps1` and ZERO carry their own copy of the runner; and 0412 and
0413 both print `Pre-flight: all 4 live patterns present and UNIQUE.` and `all 6 live patterns
present, 1 AMBIGUOUS`, both run a baseline (`1067/1067 passed, 0 failed.`), and both end with
`every restore verified byte-identical`. The harness has no opt-out switch -- `Invoke-MutationGate`
takes no pre-flight or SHA256 parameter at all -- so a gate that calls it gets all of it. The
historical table in `mutate_lib.ps1`'s header is the 2026-10-13 measurement of the DEFECT, and it
reads as a statement of the present.

BUT GATE 0413 SAYS SOMETHING ELSE. Its N1 anchor is `if bt is TList(_) && !(it is TInt) &&
!(it is TUnknown) {` -- and that text appears TWICE in `src/types/infer.mbt`: line 400, the READ
arm of the subscript base-type gate, and line 608, the WRITE arm. The pre-flight says so:

    PREFLIGHT AMBIGUOUS x2: N1 subscript gate (read arm)  (src\types\infer.mbt)
      the FIRST occurrence is the one that will be mutated -- check that
      it is the one the mutation names.

and the harness only WARNS on an ambiguous anchor and mutates the first match. 0413's own retired
row N2 admits the consequence in writing: "the write arm is not separately covered by any
mutation".

SO THE WRITE ARM HAD NEVER BEEN MUTATION-VERIFIED, and the question is what it does. MEASURED, by
mutating the SECOND occurrence and running the suite:

    WRITE-ARM MUTANT: Total tests: 1067, passed: 1067, failed: 0  -> 0 red

THE WRITE ARM'S GUARD WAS DEAD CODE. Removing it changed NOTHING.

AND THEN THE PART THAT MADE IT WORTH AN INCREMENT. The write arm cannot fire even when it is
reached, because of what happened EARLIER, and that took a diagnostic probe to see. The probe
printed the type lens's own frame at the moment the body was walked:

    fn h(xs : Array[String]) -> Unit { xs["k"] = "v" }   DIAGFRAME fn=h xs : Unknown
    fn h(xs : Array[String]) -> String { xs["k"] }        DIAGFRAME fn=h xs : [str]
    fn h() -> Unit { let xs = ["a"]  xs["k"] = "v" }      DIAGFRAME fn=h xs : Unknown

SAME PARAMETER, SAME ANNOTATION, TWO DIFFERENT FRAME CONTENTS. The parameter's type was `Unknown`
whenever the body ASSIGNED to it, and `[str]` when the body only READ it.

THE MECHANISM, and it is in the WALK's table. `Infer::run_fn` seeds a function's frame from the
structural lens's binding table, and that table lists the function's PARAMETERS first and its BODY
BINDINGS after -- because the walk records an assignment `xs["k"] = "v"` as a RE-BINDING of the
base name `xs`. So the table carried `xs` TWICE, and the body binding -- which carries no type of
its own -- was declared LAST and OVERWROTE the parameter's annotation. The parameter's type was
then gone for the WHOLE function body, and "unknown" matches nothing and is assignable to
anything, so EVERY check on that name degraded to silence.

SETTLED WITH THE TOOLCHAIN, `_verify/settle_0492_param_type.ps1`, 9 rows. THE POSITIVE CONTROLS
COME FIRST AND MUST REJECT, and that is not decoration: an earlier version of this probe reported
EVERY row ACCEPTED -- including `let x : Int = "s"` -- because its project was not a project the
toolchain would check, so `moon check` printed "no work to do" and exited 0. A settle that cannot
reject is not a settle, and the first draft of it was worthless:

    read_string_index          REJECT   the analyzer already reported this one
    write_string_index         REJECT   the analyzer was SILENT here
    write_list_local           REJECT   the analyzer already reported this one
    param_reassigned_wrong_type REJECT   the analyzer was SILENT here
    write_int_index            ACCEPT   correct code
    write_map_key              ACCEPT   correct code

THE TOOLCHAIN REJECTS BOTH FORMS. The type lens has a gate for exactly this shape -- "list indices
must be int" -- and the READ form of the same code IS reported, while the WRITE form is not. The
source says the two arms must agree: "Both arms must agree -- a check that fires on read and not on
write is a claim about syntax, not about types." It was a claim about syntax.

THE FIX IS THE ORDER OF TWO LOOPS, in `Infer::run_fn`: the body bindings are declared first and the
PARAMETERS last, so a parameter's annotation is written over any re-binding of the same name.
Among the body bindings themselves the LAST still wins, and that is load-bearing -- the walk's
table is FLAT across nested scopes and lists the INNER binding first, so "last wins" is what keeps
the 0468/0469 binding-scope leak fixed.

GATE 0492: 4 KILLED, 0 declared survivors, every restore byte-identical. The four mutations are the
four ways this can be wrong -- the order reverted, the parameter's TYPE dropped, its ANNOTATED flag
dropped, and the OTHER HALF OF THE PAIR: the write arm's own base-type condition, which was
UNOBSERVABLE while the arm was dead and is observable now. M4 is the one worth noting: it drops
`bt is TList(_)` and the `Map`-indexed-by-its-key control goes red, so the arm is not just reachable
but RESPONSIBLE.

THE SIX CORPUS PINS DID NOT MOVE -- moui 4225, labeler 791, image 218, async 1829/23/0/1852, proton
2131, contract 34, all byte-identical. That is the false-positive control for a fix that makes
strictly MORE names resolve to their annotated types, over the same 1081 `.mbt` files. The
self-scan is 161/161 parsed, actionable 0, notices 1761.

AND A FALSIFIED COMMENT, CORRECTED IN PLACE. `walk.mbt` said, of the very mechanism this increment
changed: "`Infer::run_fn` seeds its frame 0 from that table (infer.mbt:816-819) and `declare_sym`
is guarded on `frame.contains`, so the FIRST binding for a name wins". BOTH CLAIMS WERE FALSE, and
they were false WHEN WRITTEN: `Infer::declare_sym` has no guard -- it overwrites -- and
`git log -S 'frame.contains' -- src/types/infer.mbt` finds no such guard anywhere in the file's
history. `run_fn` does not seed frame 0 either: it PUSHES a frame and seeds the top one. The
comment is corrected where it stands, naming the old text.

The same block also called the labeler:1218 false positive a defect "NOT YET FIXED", and it is not in
the scan any more: moonbit_labeler 0.2.13 scans 37 files with actionable=0 and not one line
mentions `blend_pixel` or `incompatible type`. The CODE is exactly as that block describes it
(rasterizer.mbt:1196 writes `let x : Double` inside a `for i` body, 1217 binds `x` as a `for`
header over an `Int`, 1218 passes it to an `Int` parameter), so the finding is absent because the
type lens's OWN statement walk re-declares each binding as it walks the body that owns it. The
FALSE NEGATIVE half of that block -- a `let` inside a block staying visible after the block -- is
STILL OPEN, and 0468's pinned row is still the pin.

=> 判据: A PARAMETER'S ANNOTATION IS A FACT ABOUT THE VARIABLE. A RE-BINDING OF THAT VARIABLE IS
NOT A NEW DECLARATION, AND IT MUST NOT ERASE THE FACT.

=> 判据: A GATE THAT CANNOT FIRE IS NOT A GATE. The write arm's guard was unreachable in the only
case it was written for, and nothing said so -- because the arm it belonged to was never the one
that answered.

=> 判据: A MUTATION THAT TARGETS A BRANCH CANNOT KILL IT IF THE BRANCH IS NEVER REACHED. "THE
MUTATION SURVIVED" AND "THE MUTATION WAS NEVER EXERCISED" LOOK THE SAME FROM THE OUTSIDE, AND
ONLY A SECOND MEASUREMENT -- HERE, THE FRAME DUMP -- TOLD THEM APART.


## 0493: FOUR CLAIMS THE LENS MADE ABOUT PROGRAMS THE TOOLCHAIN ACCEPTS

0489 gave the behavioral lens a per-function entry, 0490 and 0491 fixed five of the classes it made
visible, and what was LEFT on wzzc-dev/moui 0.1.12 was SEVEN actionable findings. They were not
seven defects in the analysed code. They were an INVENTORY of four claims the lens made about
programs the toolchain accepts, and every one of them was a CLAIM -- a statement about what the
code means -- rather than a finding.

MEASURED, the per-function view on moui 0.1.12, BEFORE this increment:

    views/text/text_area_control.mbt:426     undefined variable 'anchor'
    views/text/text_input_editing.mbt:42     no method matching clamp_int(None, int, Any)
    views/navigation/navigation_routing.mbt:157
                                              no method matching RouteHistoryState::from_routes(Any, str, str)
    core/unicode/grapheme_cluster.mbt:428    unreachable code
    backend/web/web_host.mbt:357             no method matching web_string_append_char(None, Any)
    backend/web/web_host.mbt:359             no method matching web_finish_create_string(None)
    backend/linux/linux_services.mbt:183      no method matching >(None, float)

AFTER it: ZERO. The per-function view reports `actionable=0 notices=4225`, and the notices count
did not MOVE -- so nothing was traded away to get there.

### CLASS B -- THE `is` BINDING IN AN `else if` CONDITION

    } else if event.phase == @core.PointerPhase::Move &&
      ctx.text_control.text_selection_anchor is Some(anchor) {
      ...
      if hit.offset != anchor || hit.offset != ctx.text_control.caret {

`anchor` is bound by the `is` pattern and read twelve lines later, and the lens reported
`undefined variable 'anchor'` on the READ.

THE CAUSE IS A SINGLE LINE THAT WAS NOT EXECUTED. The `else if` conditions are evaluated in the
constant-condition path of `exec_alt` and in NOBODY ELSE: the unknown-condition path in the `if`
arm walked the `elseif` BODIES and never touched their conditions. So the `is` pattern in a
condition never bound, and the name it introduces was unbound in the branch that uses it.

THE SAME OMISSION HIDES A FALSE NEGATIVE IN THE SAME LINE. A name read in an `else if` condition
was never checked, so a genuinely undefined name went unreported. Fixing the binding without
evaluating the condition would have left that in place, so the fix evaluates the condition -- and
the direction of the change is not neutral: it makes the lens report MORE in that position and
less in the other.

MEASURED, and the mechanism was bisected with one-file probes before a line of it was written.
The binding in a plain `if` condition worked and the binding in an `else if` condition did not,
and the difference was exactly the unevaluated condition. A `match` inside a branch, an `is` in an
`&&`, and a `match` in the `then` branch were each measured separately.

### CLASS C -- "None", WHICH IS A CLAIM ABOUT A RETURN TYPE

Four of the seven, and the same answer in all four: the type "None". "None" is the lens's spelling
of UNIT, and it was the answer for a function whose body produced NO VALUE. That is false in two
situations, and both of them are in the corpus:

  - an EXTERN function. `extern "C" fn linux_accessibility_text_scale() -> Double = "moui_..."`
    has no body here -- the body is written in another language -- so there is nothing to execute,
    and the DECLARED return type is the only statement about what it returns that the file makes.
  - a body whose last statement is an `if` whose branch value is not modelled. A `match` inside a
    branch has no value this lens can name; "no value" is not "the value None".

The second one has a sharper form than it looks. The branch is only taken when the condition is
CONSTANTLY false -- and at a CALL SITE the condition is a literal. Analysed as an entry point the
condition is unknown, both branches are explored, and the join is the other branch's value. So the
defect only ever showed at a call site, and it showed as the CALLER's argument being "None" --
`no method matching clamp_int(None, int, Any)`, which reads like a claim about `clamp_int` and is
a claim about the callee two frames up.

THE FIX IS THE DECLARED RETURN TYPE, and it is used only when the declaration says something
concrete. A function with no return annotation keeps the "None" answer, because "it returns Unit"
is the only claim an unannotated body makes, and `cycle_ret` is `AAny` for exactly that case.

### CLASS D -- THE LABELS DECIDE THE BINDING, NOT THE POSITIONS

    RouteHistoryState::from_routes(routes=snapshot.routes, title~, source~)

The callee declares FOUR parameters -- `routes~`, `cursor?`, `title?`, `source?` -- and the call
supplies three, by label, omitting the optional `cursor?`. The dispatch compared arguments
POSITIONALLY, so the second argument (`title~`, a string) was checked against the second parameter
(`cursor?`, an Int) and the call was rejected.

THE LABELS WERE IN THE AST THE WHOLE TIME. `ECall`'s third field is the label list, parallel to
the arguments, and it was written for exactly this -- the AST comment says "MoonBit lets a call
reorder named arguments freely, settled against `moon check`". The TYPE LENS was fixed for this in
0.4.5 ("Without the labels the type lens compared `args[3]` against `params[3]`"). This lens never
was, and the same mistake showed up in the same file with the other lens silent.

The fix maps each argument to its parameter BY LABEL, and the values are then put back in
PARAMETER order before the callee's body runs -- a callee reads its arguments by name, so without
that the body would have read the wrong values.

### CLASS E -- A LOOP MAY RUN ZERO TIMES

    while cursor >= 0 {
      ...
      return saw_linker && fallback_codepoint_is_indic_conjunct_consonant(codepoint)
    }
    false

The body always returns, so the lens reported the `false` as unreachable. But `cursor` is
`index - 1`, so `cursor` is `-1` when `index` is `0`, the loop runs ZERO times, and the `false` IS
the function's value on that path. The reachability rule was "the statement after a TERMINATOR is
unreachable", and it was applied to a loop, which is not a terminator.

THE TOOLCHAIN DOES NOT SETTLE REACHABILITY, and that is measured rather than assumed: MoonBit
ACCEPTS code after a `return` (settle row `e3_control_code_after_a_return`, which ACCEPTED), so
the `Unreachable` family is a lint the toolchain does not share. A settle built on accept/reject
cannot tell the analyzer's claim from the truth here, because the toolchain accepts BOTH a
reachable and an unreachable statement.

WHAT SETTLES IT IS RUNNING THE PROGRAM. The execution section of the settle prints 42 for the
statement after the `while`, and 1 for the same program with a `return` in place of the loop. The
two are distinguished by the OUTPUT, and neither is distinguished by the exit code.

### THE SETTLE, AND WHERE MY OWN EXPECTATION WAS WRONG

`_verify/settle_0493_lens_values.ps1`, 21 rows with NINE that REJECT, plus two EXECUTION rows. The
controls are what make the ACCEPT rows mean something: a blanket "stay silent" would pass them
too.

THREE OF MY OWN EXPECTATIONS WERE WRONG, and the toolchain was right in all three. They are
recorded here because a settle that only ever confirms what the author expected is not measuring
anything.

  - `c3_extern_result_is_used` REJECTED with 4156, "extern \"C\" is unsupported in wasm backend".
    That is a fact about the BACKEND, not about the type, and the row is now settled on the native
    target. The first draft of the row was wrong in a way that would have read as "the toolchain
    rejects extern functions".
  - `d6_control_positional_omits_a_labelled_param` REJECTED with 4086 and 4080. A `~` parameter
    must be supplied BY LABEL: a positional pass is rejected. The expectation said ACCEPT.
  - `e3_control_code_after_a_return` ACCEPTED. MoonBit accepts unreachable code, so the row could
    not be the control the author wanted it to be, and the EXECUTION section replaced it.

### THE FIX, THE PINS, AND THE GATE

  - the `else if` conditions are EVALUATED, in both paths that reach an `else if` body, and the
    binding an `is` introduces is in scope for the body that follows it;
  - a function whose body yields no value answers with its DECLARED return type, when the
    declaration is concrete;
  - a labelled call maps its arguments to the parameters BY LABEL, and the values reach the callee
    in parameter order;
  - a `while` leaves the flow ORDINARY unless the condition is constantly true, and a `break` or a
    `continue` leaves it ordinary in every case.

THE SIX CORPUS PINS DID NOT MOVE -- moui 4225, labeler 791, image 218, async 1829/23/0/1852, proton
2131, contract 34, all byte-identical. That is the false-positive control for a fix that removes
seven findings: the MODULE view, which is what the pins measure, is untouched. The self-scan reads
163 files, 163 parsed, actionable 0, notices 1779.

THE TESTS ARE 1013 js / 1085 wasm / 1013 wasm-gc, up from 1001 / 1073 / 1001, and the twelve new
rows are in `src/pipeline/pipeline_0493_test.mbt`. Every class has a row that says "the analyzer
must still report this" next to the row that says "the analyzer must NOT report this": a real type
mismatch is still a method error, a labelled argument of the wrong type is still a method error, a
labelled call that omits a required parameter is still a method error, a label the callee does not
have is still a method error, and the statement after a `return` is still unreachable.

GATE 0493: 5 KILLED, 0 declared survivors, every restore byte-identical, every named test
confirmed. The five are the four classes plus M5, which attacks the OTHER half of class E -- the
`Unreachable` report itself -- so the control row that says "code after a `return` is still
unreachable" is pinned and not merely present.

THE M4 MUTATION OF GATE 0490 BECAME UNOBSERVABLE, and the argument for that took three
measurements and one correction before it was true.

The first argument was the toolchain's 4074: a function with NO return annotation whose tail is an
`if` is rejected, so every if-tailed function the toolchain accepts carries an annotation. It is
INCOMPLETE, and the way that was found is that the corner was probed rather than assumed. A
function declared `-> Int64` whose tail is an `if` is ACCEPTED by the toolchain (settle row
`c9_unreadable_declared_type_is_accepted`), and `ann_to_ty` maps `Int64` to TUnknown, so
`cycle_ret` is AAny and 0493's declared-return-type fallback does NOT fire there. 4074 covers the
UNANNOTATED case only.

The corner is real. It is also unobservable, and that is a measurement rather than an argument. A
five-program battery was scanned with the M4 mutation applied and with it absent. Exactly ONE
program changes its verdict, and it passes an Int64 where an Int is expected -- which the
toolchain REJECTS with 4014, Expr Type Mismatch (settle row
`c10_control_int64_into_an_int_param`). The four programs the toolchain accepts show no
difference at all. The reason is structural: the lens reports a method error only where it can
read the PARAMETER's type, and the toolchain's nominal typing forbids the one widening that would
separate an unreadable declared type from a readable parameter.

And on the whole measured surface the mutation changes NOTHING. With it applied the mutant
reproduces all six corpus pins byte-identically -- moui 608/608 notices 4225, labeler 37/37
notices 791, image 18/18 notices 218, async 415/419 notices 1829 unreliable 23 total 1852, proton
137/137 notices 2131, contract 4/4 notices 34 -- the moui PER-FUNCTION view (608/608 actionable 0
notices 4225) and the own-source scan (144/144 actionable 0 notices 1439).

So M4 is declared `Expect = 'SURVIVED'` with that argument attached, and the other eight mutations
of the gate are unchanged: 8 killed, 1 declared survivor, every restore byte-identical, every
named test confirmed.

=> 判据: A PROOF THAT IS NOT MEASURED IS A CLAIM, AND THE FIRST DRAFT OF THIS ONE WAS WRONG. It
said 4074, and 4074 covers only the unannotated case. The corner is real, the argument has to say
so, and what settles it -- a battery in which the single differing program is invalid code -- is
what makes the declaration true rather than convenient.

=> 判据: "None" IS A CLAIM, AND IT WAS FALSE FOUR TIMES. A function whose body yields no value was
reported as returning Unit, and the four places that showed up are four programs the toolchain
accepts. "We do not know" and "it is Unit" are different answers, and only one of them is a
statement about the code.

=> 判据: A LOOP MAY RUN ZERO TIMES. The reachability rule was "the statement after a terminator is
unreachable", and it was applied to a loop, which is not a terminator.

=> 判据: THE LABELS DECIDE THE BINDING, NOT THE POSITIONS. One lens was fixed for that in 0.4.5
and the other was not, and the defect that survived was the one the fixed lens had already ruled
out.

=> 判据: A SETTLE THAT ONLY CONFIRMS WHAT ITS AUTHOR EXPECTED IS NOT MEASURING ANYTHING. Three of
the twenty-one expectations in this one were wrong, and the toolchain was right in all three. A
settle whose rows are all ACCEPTED on the first run has told you nothing about the analyzer. The
settle now carries 25 rows and 11 controls that REJECT.

## DIRECTION 4: THE ONE RELEASE ENTRY POINT, AND WHAT THE README DID NOT SAY

The question was whether this repository has more than one way in, and whether the release path
covers the gates. It was measured rather than assumed, and the answer is that the single entry
point has existed all along -- what was missing was the DOCUMENTATION of it.

MEASURED. `_verify/` holds 247 `.ps1` scripts. 76 of them are mutation gates --
`mutate_<NNNN>.ps1`, one per increment that pinned a defect. `release.ps1` carries a `$gates`
list of 76 four-digit numbers, and the two sets are EQUAL IN BOTH DIRECTIONS: no mutation gate
is outside the release path, and no entry in the list names a script that does not exist. The
other 171 scripts are one-off settles, probes and evidence, plus four authoring tools
(`mutate_lib.ps1`, `named_claims.ps1`, `prove_mustred.ps1`, `preflight_compile.ps1`) and the
three scripts the release path drives as stages rather than as gates
(`grammar_probe_control.ps1`, `selfscan_published.ps1`, `selftest_selfscan_published.ps1`).

So the gap was never "a gate is outside the release path". It was that the README never NAMED
the entry point: a search for `release.ps1` in README.md had no matches, while LOOP.md named
it. A reader of the README would find the CI floor -- fmt, check, one test target, one build
-- and nothing above it, and the CI floor is not the gate.

THE README'S VERIFICATION COUNTS WERE STALE BY THREE RELEASES. It said `683/683 on wasm;
611/611 on js and wasm-gc`, a line last touched by commit 9163955 and still stale in the
0.4.30 release commit 825c506, against an actual 1085 / 1013 / 1013. A count three releases out
of date is not a stale detail; it is a claim about the project that is false, and the README is
where a reader looks to check one.

THE README'S PUBLISHING SECTION SAID `moon publish`, which is wrong in the direction that costs
the most. The publish is driven by the GitHub TAG push: `.github/workflows/publish.yml` triggers
on `v*`, resolves the registry index (`moon update`), checks that `moon.mod`'s version equals
the tag and that the repository holds exactly one `moon.mod`, runs the gate, runs `moon publish`
with the `MOONCAKES_RIANTR_TOKEN` secret, and creates the GitHub Release. A reader who believed
the README would publish from a local checkout -- with the wrong credential shape, because the
secret's VALUE is the whole contents of `~/.moon/credentials.json` and not a bare token -- and
would publish a tag that CI then publishes AGAIN.

The README now names the entry point, states its coverage and its two switches
(`-SkipMutations`, `-SelfTest`), carries the current counts, and records the release order the
CI-driven publish implies: dependencies up first, the gate green under the NEW dependency, then
the version bump and the README sync, and only then the tag.

=> 判据: A GATE IS NOT A GATE IF NOBODY CAN FIND IT. The single entry point existed and covered
every mutation gate from the first increment; what was missing was a README that named it, and a
README that claimed "the" verification numbers while carrying numbers three releases old.

## 0494: THE FOUR SHAPES THAT STOPPED THE ASYNC CORPUS, AND THE FIFTH THE FIX EXPOSED

Direction 5 is the standing ParseError backlog: the async corpus was 415/419 readable, and the
four files it could not read each stopped on a shape this frontend did not read. This increment
reads all four, and the corpus is 419/419 with `actionable=0`.

THE BLOCKER LIST I STARTED FROM WAS WRONG IN ONE PLACE, and the way it was found is that the
list was MEASURED instead of trusted. The standing note named `async/src/websocket/utils.mbt:24`
as the fourth blocker -- a `for` header with a non-empty update clause. That file PARSES: it is
`FOUND`, not `PARTIAL`, and its `for i = 0; i < len; i = i + 1` is a shape 0472 had already
settled. The fourth blocker is `async/src/http/utils.mbt:23`, and it is a `for` header whose
UPDATE clause is a LIST of assignments:

    for x = value, i = len - 1; i >= 0; x = x / base, i = i - 1 {

The INITIALIZER could already be a list (0472); the UPDATE could not, and the reader took one
statement and left the comma in the token stream -- "expected '{'".

THE FOUR, as the scanner reports them:

    async 0.22.4 src/http/request.mbt:59       expected ')'        re"..." AND `=~`
    async 0.22.4 src/http/utils.mbt:23          expected '{'        a `for` UPDATE LIST
    async 0.22.4 src/fs/watch_kqueue.mbt:240    expected binding name  let { identity, .. } = x
    async 0.22.4 src/fs/watch_windows.mbt:320   unexpected token `.`  `>..` AND `break <value>`

TWO OF THEM ARE TWO CONSTRUCTS EACH, which is what a per-file blocker list cannot show. The
regex file needs the LITERAL and the OPERATOR; the windows file needs the DESCENDING RANGE and a
`break` that CARRIES A VALUE. Settling one of each pair would have left the file unreadable for
a second reason, and the second reason would have looked like a new blocker.

THE SETTLE CAME FIRST: `_verify/settle_0494_parse_backlog.ps1`, 22 rows with TEN that REJECT.
And TWO OF MY OWN EXPECTATIONS WERE WRONG, and the toolchain was right in both:

  - `break path[:i]` was expected to be ACCEPTed and it was REJECTed with 4014, "Expr Type
    Mismatch": the corpus's `path` is a StringView, and `path[:i]` on a String is a StringView.
    The row now says StringView, and the row beside it REJECTs the same program with a String.
  - `re"[0-9]+"` was written as a CONTROL that must be REJECTed, and it was ACCEPTed -- because
    it is a perfectly good regex. That was a bad expectation rather than a toolchain
    disagreement, and the row is now an ACCEPT row.

THE KEYED `let` PATTERN IS STILL REFUSED, and that is a choice rather than an oversight. The
toolchain REJECTs `let { "cmd": [cmd], .. } = x` (0011, a `let` pattern must be irrefutable),
and 0485 pinned that refusal on purpose, in the row "0485: a let destructuring rest pattern is
still not read". So the two spellings are TOLD APART before the pattern is read -- a shorthand
field is a bare name, a key is a string or a name followed by a colon -- and the keyed one still
reports. The 0485 row is still green, and 0494 states the pair beside each other: the shorthand
IS read, and the keyed one is NOT.

THE FIRST VERSION OF THIS INCREMENT PRODUCED A FALSE POSITIVE, and it is worth recording in
full because reading a file is not the same as reading it CORRECTLY. With the regex literal and
the operator in place, `async/src/http/request.mbt` became readable -- and reported:

    66:34 - error: undefined name 'port_str' (UndefinedName)

`port_str` is bound by `(re"[0-9]+" as port_str)`: a REGEX CAPTURE, the fifth shape, and the
one the first version did not know about. The parser read the `as` as a CAST, so the name was
consumed as a TYPE and the binding was lost. The fix is a node of its own -- `EAsBind` -- and
the name is bound in the WALK's frame, the TYPE lens's frame and the INTERPRETER's environment,
exactly as an `is` binding is. The capture is told from a cast by its OPERAND: a capture's
operand is a regex literal, and a cast's is not.

=> 判据: READING A FILE IS NOT THE SAME AS READING IT CORRECTLY. The corpus went from 415/419 to
419/419 and the FIRST number that moved was a new actionable finding -- one false positive on
code `moon check` compiles. A parse-coverage number is a coverage number and nothing else.

=> 判据: A SETTLE THAT ONLY CONFIRMS WHAT ITS AUTHOR EXPECTED IS NOT MEASURING ANYTHING. Twice
over now: two of the twenty-two rows in this settle were wrong, and in both the toolchain was
right. One of them was not even a disagreement about the toolchain -- it was a bad control I had
written, and the toolchain accepting the program was the honest answer to a broken question.

=> 判据: A BLOCKER LIST IS A HYPOTHESIS. The standing note named the wrong file for one of the
four, and the error it named -- a `for` header with a non-empty update clause -- was a shape that
had been settled and working since 0472. What the corpus actually reported was a list of
PARTIAL files, and the reader that named them was the scanner, not the note.

THE CORPUS, after: async 419/419 parsed, `actionable=0`, `notices` 1829 -> 1836, `unreliable`
23 -> 0. The other five pins did not move -- moui 4225, labeler 791, image 218, proton 2131,
contract 34 -- and the moui PER-FUNCTION view is unchanged at 4225. The 23 findings that were
`unreliable` are GONE rather than restated: they were the readings of the four files this
increment could not read.

GATE 0494: 6 KILLED, 0 declared survivors, every restore byte-identical, every named test
confirmed. One mutation per shape -- the regex literal, the descending range, the update list,
the shorthand pattern, the break value, the capture.

THE ELEVEN NEW ROWS are in `src/parser/parser_0494_test.mbt`, and every one of them asserts the
NODE and not merely that the file parses: the operator is `OpMatch` and the literal is an
`ERegex`, the capture is an `EAsBind` carrying the name, the descending range is an `ERange`
and not a comparison, the shorthand pattern binds `identity`, the update list puts BOTH
assignments in the loop body, and the break's value is in the tree beside the break. The
controls are the other half: a bare `re` is a NAME, the KEYED `let` pattern is still refused, a
bare `..` is still not a range, and a bare `break` is still a bare break.

## 0494b: THE CONTROL THAT SAID "NO WITNESS LEFT", AND THE CORPUS THAT STILL HAD ONE

The full release gate on the 0494 tree FAILED, and it failed at stage 3b -- the grammar
probe control -- with its own designed message:

    grammar probe control: FAIL
      - no corpus file is both legal MoonBit and unread by this frontend, so there is
        no row left that can prove the REAL GAP tally fires.

That is not a bug in the increment. It is the control doing the one thing it exists to
do. `derive_planted_gap.ps1` derives the planted gap at RUN TIME from the pinned
corpora, and 0494 made all six of them fully readable: async reached 419/419, and the
other five had no PARTIAL file at all. The derivation searched them and found nothing,
and the control refused to invent something.

The control's own header names the two honest options, and this section takes the FIRST
one -- "pin a NEW corpus that still contains a gap this frontend cannot read". It must
never take the second without writing it down, and it must never weaken the assertions or
hardcode a replacement row.

**THE SWEEP.** Every package under `.repos/` was scanned for PARTIAL files, so the choice
of corpus was made on a measurement and not on a guess. Twenty owner/name directories,
every version fetched in each:

    moonbitlang/core            74 PARTIAL files      actionable 48
    moonbitlang/x               24 PARTIAL files      actionable  2   (12 in each of 0.5.1, 0.5.5)
    wzzc-dev/window              5 PARTIAL files      actionable  8
    moonbit-community/sqlite3    2 PARTIAL files      actionable  0
    mizchi/svg                   1 PARTIAL file       actionable  0
    moonbitlang/lexer            1 PARTIAL file       actionable  0
    everything else (11 dirs)    0 PARTIAL files

`moonbitlang/pdf2md` scanned 0 files -- its source could not be materialised here -- so it
is not evidence of anything either way.

**THE THREE CLEAN CORPORA WERE TRIED FIRST, AND THEY YIELD NOTHING.** The three with
`actionable=0` are the ones a reader would pick, so the derivation was run over exactly
them and every candidate's rejection was read. Not one usable row:

    lexer   whole file           HAS-AT      the file mentions an external package
    lexer   item 1360-1519       MOON-BAD    `scan_interpolation_source` names
                                                      `interpolation_write_view`, `env`
    lexer   item 2-4             SELF-OK     a `let` of a Bool -- this frontend reads it
    svg     item 17-4284         HAS-AT      `wpt_svg_cases` mentions `@svg`
    svg     item 6-16            SELF-OK     `struct WptCase` -- read
    sqlite3 item 74-88           HAS-AT      `@lexbuf.StringScanner::{ ... }`
    sqlite3 item 11-13           SELF-OK     `const SQLITE_NOMEM = 7` -- read

Every one of them was rejected on its own merits, and the log says which. Not one gap
survived, and the control would have gone on failing.

**THE CHOSEN CORPUS.** `moonbitlang/core` 0.1.20260920+7d59c7ec9 -- the MoonBit standard
library, pinned by a BUILD-STAMPED version, so it cannot drift under you the way
`@latest` would. Its 74 PARTIAL files yield a usable row on the SECOND candidate:

    core   PARTIAL files = 74
    core   skip file  whole file               HAS-AT     string/quickcheck_test.mbt:138
    core   USE  item  item 135-141 let qc_boundary_chars : Array[Char] = [  MOON-OK/SELF-FAIL

The witness is REAL corpus code, and it is a `let` of nothing but char literals:

    let qc_boundary_chars : Array[Char] = [
      '@', 'A', 'B', ..., '\u{7F}', ..., '\u{FFFE}', '\u{FFFF}',
      '\u{10000}', '\u{1F600}', '\u{10FFFF}',
    ]

`moon check` calls it legal MoonBit with 0 errors. The frontend cannot read it.

**THE GAP IS PRECISE, AND IT WAS MEASURED ON THE CONSTRUCT.** Not inferred from the
file -- eight single-literal programs, each one its own probe package, each one `moon
check`ed and then scanned:

    '\u{7F}'      (2 hex digits)  read
    '\u{FFFF}'    (4 hex digits)  read
    '\u{FFFE}'    (4 hex digits)  read
    '\u{10000}'   (5 hex digits)  NOT read -> "character literal must hold exactly one character"
    '\u{1F600}'   (5 hex digits)  NOT read
    '\u{10FFFF}'  (6 hex digits)  NOT read
    '\u{1FFFF}'   (5 hex digits)  NOT read
    '\u{20000}'   (5 hex digits)  NOT read

So the escape reader takes at most FOUR hex digits, which is exactly the BMP. A
supplementary-plane escape -- U+10000 and above, the range that needs a surrogate pair
in UTF-16 -- is past the end of what it reads. `moon check` accepts every one of them.

**THE OBSERVATION WAS RIGHT AND THE EXPLANATION WAS WRONG, AND 0496 IS THE INCREMENT THAT
SAID SO. The sentence above says the reader "takes at most FOUR hex digits". It does
not: it took AS MANY hex digits as the literal had, so `'\u{1F600}'` was read as
U+1F600 and was never truncated. The refusal came from a COUNT, and the count was a
UTF-16 one -- `s.length()`. MoonBit's `String::length()` counts UTF-16 CODE UNITS, the
lexer builds its buffer by CODE POINTS, and an astral character is two code units, so
the check `s.length() != 1` refused a literal that holds exactly one character.

The difference is not cosmetic, and it is the difference between a fix and a boundary
that moved. A fix written from "at most FOUR hex digits" would have BOUNDED THE DIGITS
to four and still refused `'\u{10000}'` -- it would have changed where the reader stops
rather than why it stops. 0496 replaced the count with a counter of the characters
actually written, and the whole escape grammar came with it.

THE SAME COUNT REFUSED THE ASTRAL CHARACTER LITERAL WRITTEN DIRECTLY, WITH NO ESCAPE AT
ALL. `moonbitlang/core` `builtin/string_methods.mbt:117` is `c == '😂'`, and that is
what stopped the file at line 117. The corpus carries BOTH forms -- the escaped one at
`string/quickcheck_test.mbt:138` and the direct one at `string_methods.mbt:117` -- and a
reader that had fixed only the escaped form would have left half of the corpus behind.
Measured on a two-literal probe with the two wasms: the pre-0496 wasm cannot even
PARSE a file containing either form, and the 0496 wasm reads it CLEAN.

=> 判据: A RIGHT OBSERVATION CAN CARRY A WRONG EXPLANATION, AND THE EXPLANATION IS THE
DANGEROUS PART. "Supplementary-plane escapes are not read" survived every check, because
it IS true, and it was carried for two increments by a paragraph that also said WHY. The
WHY was the thing to falsify, and the way to falsify it was to ask what the reader
actually did with the digits -- which took one measurement of `String::length()` against
`String::to_array().length()` to answer. A claim that cannot be broken by a measurement
is not a claim, and a claim whose explanation is wrong will send the next fix to the
wrong line.

**THE PIN.** `moonbit_core` is now the SEVENTH corpus in `_verify/release.ps1`'s pin
table, and the FIRST with a non-zero `actionable`: 48. Those 48 are not corpus defects
and not analyzer defects -- they are NAMED CONSTRUCTS THE READER DOES NOT READ, and the
accounting reconciles exactly (43 in fully-parsed files, from the per-file `defects=`
headers, which are not truncated; plus 5 pre-boundary findings in the two partial files
that have any):

    10  `undefined name 'rl'` / `'lr'`      the `is` pattern `(Node(..) as rl)` -- a
                                                REST pattern bound to a name
    10  a type mismatch                    `==` on two array-typed operands (6),
                                                `+` on 'int' and 'str' (2), `*` on a fn
                                                whose signature was not read (1), `abs`
                                                handed a 'float' (1)
    9   `undefined name 'p'` / `'p1023'` / a HEX-FLOAT literal: `0x1.0p97`, and
        `'P'` / `'F6A8885A308CA8A54'`       `0x3.243F6A8885A308CA8A54`
    7   `undefined name 'N'`               the `N` suffix on an integer literal
    4   `undefined name 'lexmatch'`        the `lexmatch` keyword
    4   `no visible binding for ...`       a package-private or associated name
    2   UnusedLocal                        `i1` / `i2` in diff/diff.mbt
    1   `undefined variable 'declare'`    the `declare` keyword
    1   `undefined name 'strconv'`         `@internal/strconv.parse_double(s)` -- an
                                                absolute package path with a `/`

Six of these families are the SAME gap this increment already half-closed: a pattern
that binds a name (`(Node(..) as rl)`) is the same shape as the regex capture
`(re"..." as port_str)`, and `EAsBind` exists for that one but not for this one.

=> 判据: A CONTROL THAT PASSES BECAUSE IT STOPPED LOOKING IS THE EXACT DEFECT THE CONTROL
EXISTS TO CATCH, WEARING THE CONTROL'S OWN CLOTHES. The control did not go quiet, and it
did not get an exemption: it FAILED, it said why, and it named the two ways forward. The
first one was taken -- a corpus that still holds a gap -- and the corpus was CHOSEN BY
MEASUREMENT (a sweep of twenty directories) rather than by hope, and the gap inside it was
then MEASURED ON THE CONSTRUCT rather than inferred from the file that contained it.

=> 判据: A BLOCKER LIST IS A HYPOTHESIS, AND SO IS "THE CLEAN CORPORA ARE THE ONES TO
USE". `actionable=0` looked like a reason to prefer `lexer`, `svg` and `sqlite3` over
`core`, and it was not: those three yield nothing, and the corpus with the most
actionable findings is the one with a real gap in it. The two properties are unrelated,
and picking by the wrong one costs a whole release-gate round trip.

## 0494c: FOUR MUTATION GATES THAT 0494's PARSER CHANGES MOVED OUT FROM UNDER

With the witness in place the gate ran again, and it failed again -- this time at FOUR
mutation gates, all of them the same way:

    PREFLIGHT MISS: M1 revert: the parser has no production for `as`  (src\parser\parser.mbt)
    ABORT: 2 pattern(s) absent. No suite was run.

`PREFLIGHT MISS` is the harness doing the right thing: the anchor text is no longer in the
file, so the mutation cannot be applied, so no suite is run and the gate says so. 0494 grew
the `as` production, the `for` update clause and the braced-pattern reader, and six anchors in
four gates pointed at the OLD shape of those three places:

    mutate_0429  M1  the whole `as` production        M5  the cast target type
    mutate_0473  M5  the clause list is mandatory     M6  the update clause
    mutate_0482  M3  the update is read and discarded
    mutate_0485  M2  every name in the braces binds

THE RULE IS ALREADY WRITTEN DOWN and it is the whole of this section: a mutation whose anchor
moved is RE-ANCHORED to the current shape, with the SAME mutation. Not retired while its
target is still live, and not replaced by an invented anchor that matches something else.
Each of the six was re-anchored to the CURRENT text, and each was MEASURED to still kill the
same thing:

    mutate_0429  4 killed, 1 declared survivor (M4), every restore byte-identical
    mutate_0473  7 killed, every one [named test confirmed]
    mutate_0482  4 killed, every one [named test confirmed]
    mutate_0485  5 killed, every one [named test confirmed]

**THE RE-ANCHORS ARE NOT MECHANICAL**, and two of them needed a measurement that would have
been wrong to reason about.

**0429 M1 -- the `as` production.** The old anchor was the whole `as` branch, and 0494 put
the REGEX CAPTURE inside it, so the branch is longer now and the anchor has to be the whole
branch again -- capture and cast both. The mutation's NAME is "the parser has no production
for `as`", and after 0494 the production IS the whole branch, so deleting all of it is the
same question: after the mutation `as` is in the token stream again and the parser reports
`undefined name 'as'`. Re-anchored on the current 35 lines.

**0473 M5 and M6, 0482 M3 -- the `for` header.** 0494 replaced the single update statement
with a LIST (`updates = self.c_for_updates()`), so three anchors that named
`update = Some(self.parse_stmt())` matched nothing. The re-anchors name the current reader.

0482 M3 needed more than that. The old mutation discarded the update at the push site
(`Some(u) => loop_body.push(u)` became `Some(_) => ()`), and the new shape has a `for` loop
over an array instead -- so "the update is read and then discarded" has to be expressed
against the array, and the expression has to be a PROGRAM rather than a deletion: a `Repl`
that leaves a variable unused is a WARNING, and `--deny-warn` turns a warning into a build
failure, which the harness scores as COMPILE-ERR rather than KILLED. The candidates were
settled against the toolchain rather than guessed:

    for _ in updates { () }      ACCEPT, no warning
    let _ = updates              ACCEPT, no warning
    let _ = updates.length()     ACCEPT, no warning

and the chosen form empties the array before the loop that pushes it, so the clause is still
READ and still CONSUMED and the statement still does not reach the tree -- which is the
defect the mutation names.

**0485 M2 -- the key that must not bind.** The old anchor was one line:
`if in_value && (self.pattern_binding_at(j) || self.rest_binding_at(j)) {`, and dropping
`in_value &&` made every name in the braces bind, key included. 0494 SPLIT that site in two
-- a value position and a shorthand field position -- so the single line is gone.

The obvious re-anchor -- drop the `in_value` gate from the new shape -- DOES NOT WORK, and
the reason is a toolchain fact that was measured rather than assumed:

    let mut flag = false
    flag = true                 =>  Warning: unused variable 'flag'  (error under --deny-warn)

MoonBit DOES warn about a `mut` variable that is assigned and never READ. So removing the
only read of `in_value` would have turned M2 into a COMPILE-ERR -- a green-looking gate that
proves nothing, which is the failure mode this repo keeps measuring. The re-anchor instead
adds `pattern_binding_at(j)` to the FIELD branch, so a KEY binds -- which is the defect M2
names -- while `in_value` stays read and the mutation stays a program that compiles.

=> 判据: A MUTATION THAT DOES NOT COMPILE IS NOT A KILL. The harness scores COMPILE-ERR as
"the suite never ran", which is the truth, but a mutation that cannot compile proves nothing
about the code it meant to break -- and the warning that causes it is a WARNING, which
`--deny-warn` promotes to an error. Two of the six re-anchors turned on a form that has to
compile clean, and both forms were settled against the toolchain rather than chosen by
taste.

=> 判据: A MOVED ANCHOR IS A FACT ABOUT THE INCREMENT, NOT A TYPO TO FIX. Six anchors moved
because 0494 changed the code they named. Re-anchoring them is not busywork: it is the record
that 0494 did not silently retire four gates' worth of protection. The alternative -- retiring
them -- would have been cheaper and would have left the four defects unguarded while the gate
still reported green.

## 0495: THE 116 FINDINGS THAT WERE AN INVENTORY OF THE LENS

Direction 2 asked what the behavioural lens reports when it is pointed at a FUNCTION rather than
at a module. Re-measured after 0494, the per-function view was non-zero on four of the seven
pinned corpora:

    moonbit_labeler  38      moonbit_image  35
    async            40      proton          3

116 findings in all. And NOT ONE of them is a defect in the code being analysed: every one of
the 116 sites is in a file `moon check` accepts, in released and published packages. So the 116
are an INVENTORY of what is still wrong with the LENS -- eight families, each one a claim the
lens made about a program the toolchain accepts.

MEASURED, the per-function view, BEFORE this increment: 116 actionable findings. AFTER it: **2**,
and the 2 are the `#doc(hidden)` limit the repo already documents (`src/core/advice.mbt:76`) --
`@locale.LocalePreferences::resolve`, which appears in NO `.mbti`, so it cannot be indexed from
the command line. The two are at proton `facade_locale.mbt:70` and `core/app_command_host.mbt:114`.

The MODULE view's pins did not move: moui notices=4225, labeler 791, image 218, async 1836,
proton 2131, contract 34. So nothing was traded away to get the per-function number down.

### THE EIGHT FAMILIES, AND THE COUNT EACH EXPLAINS

    A   61   a destructured name bound to the WHOLE TUPLE
    B   25   a `continue`/`break` that CARRIES A VALUE
    C    8   a statement after a loop whose body always terminates
    C2   5   the C-style `for`'s UPDATE clause
    D   10   a call to an `extern`/FFI declaration
    E    5   a cross-package qualified associated / trait call
    F    4   an integer `/` typed as `float`
    G    2   a name bound by an `is`-pattern `as`-binding
    H    1   a name bound by an ITERATOR expression

**A -- a destructured name is an ELEMENT, not the tuple.** `let (a, b) = pair()` binds `a` and
`b` to the two ELEMENTS. The lens bound both of them to the whole tuple, so every use of a
destructured name carried the abstract type "Tuple" into a call whose parameter was declared
`Int` -- `no method matching lzw_read_code(Any, Tuple, Tuple, int)`. The fix binds the name to
`AAny` -- the type lens's own "Unknown" answer for a destructured name (`src/types/infer.mbt`),
so the two lenses stop contradicting each other on the same line.

**B -- a `continue` that CARRIES A VALUE is not unreachable code.** `continue p, r, c, vr` sets
the loop variables and continues. The values used to be parsed as SIBLING STATEMENTS, so the
interpreter read the terminator, saw the flow end, and reported the first carried value as
`unreachable code`. The terminator's payload is now the terminator's own node.

**C and C2 -- a loop is not a terminator, and its update clause is reachable.** The `if` join
reports the terminator the branches AGREE on, and falls through if ANY branch does. The C-style
`for`'s update clause got its own AST node, emitted only when the clause exists.

**D -- FOUR defects wearing one name.** This is the part worth reading, because the count said
"10 findings about extern calls" and the reality was four unrelated causes, each isolated by its
own probe before a line of it was written:

  - **D1 the pipe.** `f <| x` applies f to x; when f is a CALL, the right operand becomes an
    ARGUMENT of that call. The arity check never saw the argument the pipe supplied, so
    `add2(1) <| 2` was rejected as one argument to a two-parameter function.
  - **D2 the omittable parameter.** A parameter a call may OMIT (`name? : T = ...`) is bound by
    label or left at its default -- it is NOT a positional slot. The corpus's own compiling code
    is the proof: `f(a, b? : Int = 0, c)` called with two arguments means `c` got the second.
  - **D3 the name declared TWICE.** A name with two declarations -- the `#cfg` pattern -- has NO
    single signature. The lens picked one of them and reported the other's call site.
  - **D4 the extern's result.** A function with no BODY and an unknown declared return type
    yields `AAny`, not "None". "None" is a claim about a value the file never mentions.

**E -- a trait's methods are VALUES.** The `.mbti` reader skipped trait bodies, so a
cross-package call to a trait method had no name to resolve against:
`undefined function '@io.Writer::write'`. The name a use site resolves to is `Trait::method`
-- the package qualifier is dropped by `unqualified` -- and the reader now harvests it.

**F -- an integer `/` is an integer.** `let hs = h / 2` with `h : Int` is an `Int`. The
constant-fold path had the same defect separately: a division of two LITERALS was folded to a
float.

**G -- the `as`-binding.** `is (HasReader(_) as reader)` binds `reader` to the WHOLE matched
value, not to the payload.

**H -- the iterator expression.** `[ for handle in xs => f(handle) ]` binds `handle` for the
body of the comprehension; the names now bind in a COPY of the environment.

### THE SETTLE, AND THE TRAP THAT MADE IT VACUOUS

`_verify/settle_0495_perfunction.ps1`: **36 check rows plus 6 execution rows**, 18 of the
check rows being CONTROLS -- shapes the toolchain must REFUSE, so that "the analyzer must stay
silent on it" cannot be satisfied by silencing everything. One row is MEASURED rather than
claimed (`Expect = '?'`): `extern "C"` is a native-backend construct, and this machine cannot
run the native target at all, so the AUTHORITY for that ACCEPT is the corpus --
moonbitlang/async 0.22.4, `src/socket/ffi.mbt:16`, in a released and published package.

**THE FIRST RUN OF THE SETTLE READ 23 OF 23 ROWS AS ACCEPT, AND EVERY ONE OF THEM WAS WRONG.**
Not one row was right: the controls, whose whole job is to be refused, all accepted. The cause
was in the HARNESS, and it is the same trap this repo has measured before:

    A PACKAGE IS A DIRECTORY. `src/<pkg>` with its own `moon.pkg`.

The runner had written `moon.pkg` into `src/` instead of into `src/<pkg>/`, so `moon check`
found no package, printed **"no work to do"**, and exited 0. A `moon check` that read NOTHING
reports success, and the settle read that success as the toolchain accepting the fixture.

A VACUOUS ACCEPT IS WORSE THAN A RED ROW, because a red row says "this shape is refused" and a
vacuous one says "this shape is accepted" -- and it says it about the compiler having read
nothing at all. Two things came out of the measurement, and both are now in the script:

  - the runner REFUSES a verdict of ACCEPT that came with "no work to do", and counts it
    separately as `vacuous`, so this trap cannot pass silently again; and
  - the row projects PIN their target (`preferred_target = "wasm"`), because one row's verdict
    IS target-dependent: an `extern` declaration is refused outright by the wasm backend (4156)
    and accepted by the js one. A row that reads "the default target" is a row that changes
    meaning when the toolchain's default changes.

TWO MORE FIXTURE FACTS, both measured, both of which had made a row wrong before it was
settled:

  - `pkgtype(kind: "executable")` belongs to the EXECUTION rows only. On a check row it adds
    "Missing main function in the main package" (4067) to every single row -- which is how a
    run reported 23 REJECTs that were all the same unrelated error.
  - `print` IS NOT A BUILTIN in a standalone project; `println` IS. And the compiler's warnings
    share stdout with the program's output, so the execution rows redirect stderr to a file of
    its own and read STDOUT ONLY.

### WHAT SETTLES REACHABILITY IS RUNNING THE PROGRAM

MoonBit ACCEPTS code after a `return` -- the settle row `c4_control_code_after_a_return_is_accepted`
ACCEPTED, and so did the row before it. The toolchain therefore does NOT settle reachability by
compiling: it accepts BOTH a reachable and an unreachable statement. A settle built on
accept/reject cannot tell the analyzer's `Unreachable` family from the truth, and the analyzer's
claim is the one under examination.

What settles it is RUNNING the program:

    x1  a `continue` in a C-style `for` RUNS THE UPDATE CLAUSE -- the program prints
        `i=0 i=1 i=2 i=3` and finishes. It could only finish if the update ran on the
        `continue`; without it `i` would stay at 1 and the loop would never end.
    x2  THE CONTROL FOR x1: the same loop with the `continue` removed also finishes, so the
        two are distinguished by WHETHER THE CONTINUE IS THERE and not by the exit code.
    x3  the statement after a loop that may run zero times IS reached -- the program prints 42.
    x4  THE CONTROL FOR x3: the statement after a `return` is NOT reached -- it prints 1.
    x5  FAMILY U: the statement after a `while true` that BREAKS is reached -- it prints 42.
    x6  THE CONTROL FOR x5: a `while true` whose body RETURNS does not reach it -- it prints 1.

x5 and x6 are the pair that settled the last of the three `Unreachable` findings. The loop's
"could the body have broken out?" question was being answered from the JOINED flow, and the
join collapses a mixed `break`/`return` into `FReturn` -- which loses the `break`. The signal
is now separate from the join: a `mut broke` flag on the interpreter, set by the `break` arm,
saved and restored around each loop body.

### THE GATE, AND THE SURVIVOR THAT WAS A DEAD RULE

`_verify/mutate_0495.ps1`: **14 mutations, all 14 KILLED, 0 survivors**, every restore
byte-identical, "GATE OK: 0495", baseline 1134/1134. Each mutation NAMES the test that must
go red, and each was confirmed `[named test confirmed]` -- a mutation that kills some other
test is not evidence, because the test named is the one that pins the rule.

M8 SURVIVED on the first run, and that is the most useful thing in this increment:

    M8 a comprehension in an expression binds no names

The mutation could not be killed because the rule it named was UNREACHABLE. The `EComp` arm
inside the `SAssign` TARGET match could never fire -- a target is a name, a field, an index or
a tuple field, never a comprehension -- so the arm was DEAD CODE, and the live rule is the
`EComp` arm of `eval` (the assignment's RIGHT-HAND side is evaluated by `self.eval(rhs, env)`).
The dead arm was DELETED, with a comment recording that gate M8's survivor is what found it.

=> 判据: A SURVIVING MUTATION OF A RULE NOBODY CAN REACH IS THE RULE BEING DEAD. The
alternative -- keeping the arm and adding a test that reaches it -- would have meant inventing a
program shape the language does not have, to guard a rule that cannot fire. The survivor was
not a coverage gap. It was a defect in the code under test, and the gate said so.

**TWO OF THE FOURTEEN SURVIVED ON THE FIRST RUN FOR A DIFFERENT REASON**, and the reason was
that the TESTS did not discriminate:

  - M11 ("a name declared twice is arity-checked") and M12 ("an extern result is the value
    None") both survived, because the tests that named them did not DISTINGUISH the wrong
    answer from the right one. The omittable-parameter test gave the omittable parameter the
    SAME type as the next one, so a rule that mixed the two up still produced the same
    observable result; and the duplicate-name test had no one-argument call to check. Both
    tests were given a case that separates the two answers, and both mutations then died.

=> 判据: A TEST THAT CANNOT TELL THE WRONG ANSWER FROM THE RIGHT ONE IS NOT A TEST OF THE
RULE. It passes with the rule broken. The fix is not to relax the mutation but to give the
test a case where the two answers DIFFER, and that is a change to the test, made in the open
where the mutation is named.

### THE COUNTS, AFTER

    per-function actionable findings   116 -> 2   (the 2 are the documented #doc(hidden) limit)
    module-view corpus pins            UNCHANGED on all seven corpora
    moon test --deny-warn              1134/1134 on wasm   (1096 at the start of this effort)
    moon check --deny-warn             exit 0
    self-scan (own source)             167/167 parsed, actionable=0
    mutation gate 0495                 14 mutations, 14 killed, 0 survivors

The remaining 2 are a DOCUMENTED LIMIT and not a blocker: fixing them would require indexing
dependency SOURCE rather than `.mbti`, which `src/core/advice.mbt:76` already names as one of
the two limits unfixable from the command line. Growing the analyzer into a source indexer to
answer them would be a different project.
## 0495b: FIVE GATES THAT 0495's OWN SOURCE CHANGES BROKE, AND WHAT THREE OF THEM WERE SAYING

The release gate went RED on its first full run, and the cause was this increment's own work:
five mutation gates failed at PREFLIGHT because 0495 moved the text they name. A preflight
failure is the harness doing its job -- it aborts in milliseconds instead of spending a full
`moon test` to learn that a pattern no longer matches -- and the five were 0425, 0466, 0472,
0489 and 0493.

**THE RULE FOR A MOVED ANCHOR** is the one 0494c wrote down, and it is not "fix the typo":
re-anchor onto the CURRENT text, keep the SAME mutation, and then MEASURE that it still kills.
Never retire a live guard, never invent an anchor that merely matches, and never let a
re-anchor be a silent weakening. All 31 anchors across the five gates are now present and
UNIQUE, checked by a preflight-only probe that reports presence, count and prose-match for every
mutation without running a suite.

**AND THEN THREE OF THEM FAILED FOR REASONS THAT HAD NOTHING TO DO WITH THE ANCHOR.** That is
the part worth writing down, because a re-anchor that ends in a green gate can hide a gate that
has stopped guarding anything.

### 0425 M7 SURVIVED, AND THE SURVIVOR WAS RIGHT

`exec_alt`'s missing else contributes a fall-through to the join, and 0495 re-anchored the
mutation onto that line: `None => flows.push(FNormal)` becomes `None => flows.push(FReturn)`.
The mutation SURVIVED -- 1054 of 1054 still green.

The reason is arithmetic, and it is worth writing out because it is the whole point of the
increment's `join_flow` change:

  BEFORE 0495 the missing else was an ASSIGNMENT to a flag -- `None => falls = true` -- so it
          OVERRODE whatever the branches had said. After, it is one more entry in a list of
          flows, and `join_flow` takes the join: fall through if ANY branch does.

So after 0495 the missing-else entry is REDUNDANT whenever some branch falls through -- and
0.4.25's fixture for it ("a chain with no else at all falls through") has exactly such a
branch (`let _ = 2`).

**MEASURED, not inferred.** The pre-0495 tree (`git archive HEAD` at 731659c) with 0.4.25's M7
mutation applied killed EXACTLY ONE test -- "0425: a chain with no else at all falls through" --
and the same mutation on the 0495 tree kills NONE. The line had stopped being observable.

It is still LOAD-BEARING, in the case no fixture covered: a chain with no else where EVERY
branch terminates. There the missing else is the only fall-through, and without it the
statement after the chain is reported `unreachable code` -- a false positive on code
`moon check` accepts. So the fix was a FIXTURE, not a re-anchor: `src/pipeline/
pipeline_0495_test.mbt` now carries "0495 J: a chain with no else falls through even when
every branch returns", which is 0.4.25's program with ONE LINE changed (the else-if body
returns instead of falling through), plus the control that a chain with an `else` really is
dead after it. M7 is killed again.

=> 判据: A FIXTURE THAT STOPS DISCRIMINATING IS A COVERAGE HOLE, AND NOBODY NOTICES EXCEPT A
MUTATION. 0.4.25's row was green before 0495 and green after it, and it meant different things
on the two sides of the change. The only instrument that could see the difference was a
mutation that killed it. A gate that is green because the thing it measures stopped being
measured is worse than a red one, because a red one is read.

### 0472 M5 IS NOT EXPRESSIBLE ANY MORE, AND THAT IS A STRONGER CLAIM

`mutate_0472.ps1`'s M5 rewrote the carried value of a `continue` from an expression into an
assignment to an invented name -- the fabrication 0472 deliberately does NOT do. It came back
**COMPILE-ERR**, and the compiler said why:

    Constr Type Mismatch(constructor SAssign)
      has type : @riantr/moonbit_static_analysis/src/ast.SKind
      wanted   : @riantr/moonbit_static_analysis/src/ast.EKind

0495 changed the carried values from SIBLING STATEMENTS to the TERMINATOR'S OWN PAYLOAD
(`SContinue(Array[Expr])`). `SAssign` is a `Stmt` kind, and `Expr` has no assignment
constructor at all -- so the mutation is not MOVED, it is IMPOSSIBLE. It is RETIRED, with the
reason printed by the harness, because a claim enforced by a TYPE is stronger than a claim
enforced by a line of code: there is no line left to mutate.

The other half of the same claim -- "the values are READ" -- is enforced by `walk.mbt` and
`infer.mbt`, and it was not guarded by anything. M6 is new and pins it: the walk does not walk
the carried values, so the names inside them are unread, and the `UnusedLocal` verdict comes
back. `UnusedLocal` is decided in `walk.mbt`'s `audit_frame` (`e.varuses == 0`), which is why
that is the site the mutation takes.

=> 判据: A MUTATION THAT NO LONGER COMPILES IS NOT A KILL, AND SOMETIMES IT IS NOT A LOSS
EITHER. "COMPILE-ERR" is the harness saying it could not measure the mutant. Reading that as
"the guard is gone" would have been wrong: the guard moved into the type system, where a
mutation cannot reach it. The honest form is `Retired = "<reason>"` plus a NEW mutation at the
site where the surviving half of the claim lives -- not a silent drop, and not an invented
anchor.

### 0493 M3's NAMED TEST STOPPED BEING THE RIGHT ONE

0493's M3 -- "the argument labels are invisible again" -- kills by making `any_label` false,
so the arguments are compared by POSITION again. It still kills, but the row it named
("a labelled call that omits an optional parameter is accepted") no longer goes red, and
rule 6 says a kill that does not redden the named test is not a kill.

The reason is 0495's D2 fix: an OMITTABLE parameter is not a positional slot, so the positional
path now SKIPS the omittable ones. The labelled call `from_routes(routes=s, title="x",
source="y")` compared by position therefore no longer produces an error either -- the row
stopped being able to tell the two mechanisms apart.

The row that DOES tell them apart is the control on the label SET: a label the callee does not
have can only be caught by READING THE LABELS. With `any_label` false the unknown label is
accepted, the expected error is not reported, and the row goes red. M3's `MustRed` now names
that row.

=> 判据: A NAMED TEST IS A CLAIM ABOUT WHICH TEST DOES THE WORKING. When a fix elsewhere makes
the named row stop discriminating, re-pointing the name at the row that still discriminates is
correct -- and RECORDING WHY is the part that matters, because the next reader will otherwise
assume the original row was redundant.
### RULE 9, ADDED BY THE FULL RELEASE GATE: A FILE THAT ANOTHER PROCESS HAS OPEN IS NOT A FAILED GATE

The full release gate -- all 78 mutation gates, the corpus pins and the self-scan -- failed on
its first run at exactly ONE gate, 0455, and with this and nothing else:

    Exception calling "WriteAllText" with "3" argument(s): "The requested operation
    cannot be performed on a file with a user-mapped section open."

M1 and M2 had already been KILLED, with their named tests confirmed, when the WRITE of the
next mutation's replacement threw. Windows refuses a write to a file that a reader has
MEMORY-MAPPED, and the reader was the compiler: `moon` had the source mapped while the gate
was between its test runs. The same gate, run alone in the same tree minutes earlier, was
GREEN, and it was GREEN again on the next run.

**WHY IT MATTERS MORE THAN IT LOOKS.** The write that threw was not necessarily the one that
APPLIES a mutation -- it could have been the RESTORE. A restore that throws leaves the target
file MUTATED, and every gate after it then measures a tree nobody intended to measure. The
tree WAS checked after the failure -- the target, `src/lexer/lexer.mbt`, was byte-identical to
HEAD -- but a check after the fact is not a guard. The next gate would have measured a mutated
file and reported a result about it.

So the I/O gets a retry, and the retry is on the TRANSIENT rather than on the VERDICT: the
mutation still has to be applied, still has to kill, and the restore still has to be proven
byte-identical by SHA256 afterwards. Nothing about the judgement changes. `mutate_lib.ps1` now
reads and writes through `Read-BytesWithRetry` / `Write-TextWithRetry` /
`Write-BytesWithRetry`, which retry an `IOException` with a growing sleep and re-throw when
the tries are spent -- a genuinely unwritable file still fails.

=> 判据: A FLAKE IS A DEFECT UNTIL IT IS MEASURED, AND A FIX THAT HIDES IT IS WORSE THAN THE
FLAKE. The tempting move is to re-run the gate and call the green run the result. That is the
one move that leaves the defect in place -- and the defect here is not "the gate is noisy", it
is "a restore can fail and leave a mutated file behind". The harness already had a retry for
one shape of machine misbehaviour (the EMPTY RUN), and `release.ps1` already had one for
another (`Read-TextWhenFree`, written for the same reason). This is the third shape, found by
running the thing rather than by reasoning about it.

## 0496: THE ESCAPE, THE LEXICAL MATCH, AND THE LAMBDA THAT BINDS INSIDE AN INTERPOLATION

The standing backlog item was the LABELLED CAPTURE -- the `after=` binding of MoonBit's
lexical match -- and the named witness was a character literal with more than four hex
digits. Both were real, and the item turned out to be THREE increments' worth of work
with a CRASH in the middle of it.

**THE SCOPE WAS RE-DERIVED, AND THE STANDING NOTE WAS WRONG ON BOTH COUNTS.** `after=`
appears on 283 lines across 22 files under `.repos`. Classified by hand, the real
construct is 84 sites in FIVE pinned `moonbitlang/core` files and ZERO in the other six
corpora:

    string/internal/regex_parser/parser.mbt     61
    diff/diff_align_test.mbt                    13
    diff/diff_word_test.mbt                      5
    internal/strconv/strconv_int.mbt             3
    debug/debug_test.mbt                         2

moui's thirteen "hits" are `let after = ...`, `receipt.after` and a comment; labeler's two
are a `let after` and a doc comment. The note said "18 sites in 3 PINNED core files", and
18 is 13 + 5 -- the two diff test files alone, with the file that holds 61 of the 84
sites left out of the count entirely.

=> 判据: A GREP IS NOT A SCOPE. It counts local variables, field accesses and comments
alongside the construct, and a count that includes those cannot be used to decide what
to fix. The construct is `lexmatch <subject> [with longest] { (re"..." as t, after=next)
=> ... }`, and it lives in five files of one corpus -- which is a different statement
from "22 files" and a different one again from "3 files".

### A -- THE CHARACTER LITERAL'S ESCAPE, AND THE CRASH UNDER IT

**THE OBSERVATION WAS RIGHT AND THE EXPLANATION WAS WRONG.** The 0494 block said the
escape reader "takes at most FOUR hex digits, which is exactly the BMP". It does not:
it took AS MANY hex digits as the literal had, so `'\u{1F600}'` was read as U+1F600 and
was never truncated. The refusal came from a COUNT, and the count was a UTF-16 one.
MoonBit's `String::length()` counts UTF-16 CODE UNITS and `String::to_array()` counts
CODE POINTS, and the lexer builds its buffer by CODE POINTS:

    "\u{1F600}".to_string().length()            -> 2
    "\u{1F600}".to_string().to_array().length() -> 1

So the check `s.length() != 1` refused a literal holding exactly one character. A fix
written from the wrong explanation would have BOUNDED THE DIGITS to four and still
refused `'\u{10000}'` -- it would have moved the boundary instead of removing it. The
correction is written in place, at the 0494 block, and the mechanism is now a counter of
the characters actually written.

**AND THE SAME COUNT REFUSED THE ASTRAL CHARACTER WRITTEN DIRECTLY, WITH NO ESCAPE AT
ALL.** `builtin/string_methods.mbt:117` is `c == '😂'`, and that is what stopped the file
at line 117. The corpus carries BOTH forms -- the escaped one at
`string/quickcheck_test.mbt:138` and the direct one at `string_methods.mbt:117` -- and a
reader that fixed only the escaped form would have left half the corpus behind.

**THE CRASH WAS WORSE THAN THE WRONG ANSWER.** `'\u{110000}'` -- a code point past the
last one -- reached `v.unsafe_to_char()`, which is not a conversion but a TRAP. The
scanner printed `RuntimeError: unreachable` and STOPPED, so every file after it in the
scan went unread. A wrong answer is one finding; a crash is the loss of the run.

**THE WHOLE GRAMMAR WAS SETTLED, NOT JUST THE NAMED CASE.** `_verify/settle_0496_unicode_escape.ps1`,
32 rows / 5 controls, GATE OK, one form per row:

    \xNN        EXACTLY two hex digits      '\x4'      REJECT(3001)
    \u{...}     ONE to SIX hex digits       '\u{}'     REJECT(3001)
    \uXXXX      EXACTLY four hex digits     '\u07f'    REJECT(3001)
    the braced form's bound is the CODE POINT's, not the digit count's:
                '\u{10FFFF}'  six digits, ACCEPT;   '\u{FFFFFF}'  six digits, REJECT(4064)
    a byte literal takes NO unicode escape:  b'\u{41}'  REJECT(3001)
    a surrogate is not a scalar value:      '\u{D800}'  REJECT(4064)

The implementation follows the grammar rather than the named case: the escape branch is
now `e == 'x' || e == 'u'` (so a MALFORMED unicode escape is reported as malformed
instead of falling through and writing the letter `u`), the braced form requires its
closer, the digit bounds are per form -- (2,2) / (1,6) / (4,4) -- and the digits past the
limit are CONSUMED but not accumulated, so a seventh digit flags a malformed escape
instead of overflowing an `Int32`. The value is then checked against
`v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)`, and there are TWO reports -- "character
literal has a malformed escape" and "character literal is not a valid Unicode code
point" -- one per literal, because the escape is the problem and the length is a
consequence of it.

**TWO OF THE MUTATIONS CANNOT BE "REMOVE THE GUARD".** A mutation that lets an
out-of-range code point through makes the SUITE DIE, and a suite that dies is
COMPILE-ERR and not a kill. So the crash guard is mutated on its BOUND: an off-by-one
still refuses the value (nothing crashes) and refuses the LAST LEGAL CODE POINT as well,
which is a red test.

### B -- `lexmatch`, READ AS A CONSTRUCT

`lexmatch` was read as an ordinary NAME, so the four corpus sites produced
`undefined name 'lexmatch'` -- on code `moon check` accepts:

    internal/strconv/strconv_int.mbt:174
    diff/diff_align_test.mbt:56 and :94
    diff/diff_word_test.mbt:33

`_verify/settle_0496_lexmatch.ps1`, 15 rows / 4 controls, GATE OK, settled the grammar:
`lexmatch s {..}` and `lexmatch s with longest {..}` ACCEPT; `lexmatch s with {..}`
REJECT(4180), because `with` needs `longest`; the same arm in a plain `match` REJECT(3002);
and `as _` REJECT(3002), because a capture's name must be an identifier.

**THE ARMS ARE SKIPPED WHOLE, EXACTLY AS A `match`'s ARE, AND THE SUBJECT IS CARRIED.**
The shape is identical to `EMatch` -- subject real, arms skipped, value from the arms,
unknown type, `ABottom` -- so the implementation reuses `@ast.EMatch(subject)` rather
than adding a variant that would have rippled through walk/types/infer/interp and the
`.mbti` for no new information. The NOTICE says `lexmatch` rather than `match`, because
that is what was read.

**THE `after=` ARM PATTERNS ARE DELIBERATELY NOT BOUND.** A binding nobody can observe
is a claim, not a feature: the arms are skipped, so binding them would change no finding
and would cost a pattern reader the subset does not otherwise have.

**TWO OF MY OWN EXPECTATIONS WERE WRONG AND WERE CORRECTED IN PLACE.** `as _` is
REJECT(3002) -- a capture's name must be an identifier -- and `after=rest` with a
`String` subject is ACCEPT when the arm does not return the binding; the 4014 I had
expected was the arm's RETURN type, not the binding.

### C -- THE FALSE POSITIVE THAT B UNCOVERED

With the `lexmatch` fix, `moonbitlang/core` `builtin/autoloc.mbt` became readable past
its old boundary -- the old parse boundary was line 74, and line 74 is where the
`lexmatch` at line 63 used to stop the reader -- and the file then reported:

    no visible binding for 'sb'    at builtin/autoloc.mbt:83

    $|{"filename":\{sb => self.filename.escape_to(sb)},...}

`sb` is the lambda's own PARAMETER. It is a binding, and a use of it is a read of the
parameter -- not a read of the enclosing frame. The root cause was in the collector: the
name is flushed at the first character that is not part of it, and in `sb => sb` that
character is the SPACE, so the `=>` had not been seen when the name was decided. The fix
is a lookahead over the whitespace to the `=>`, a per-interpolation set of BOUND names,
and a skip in the name flush. Two spellings need two paths, and both are needed:
`sb=>sb` reaches the `=` with the name still pending, and `sb => sb` reaches it with the
name already flushed.

**THE LIMIT IS STATED RATHER THAN LEFT.** The suppression runs to the end of the
interpolation, so a name that is a lambda parameter in one part of an interpolation and
an enclosing read in another part of the SAME interpolation is not reported. The corpus
has exactly ONE interpolation with a lambda in it, so nothing else can be affected; a
read BEFORE the lambda is still recorded, and two interpolations of one string are two
scopes.

**THE 0488 COMMENT WAS CORRECTED IN PLACE.** It said the shape
`\{xs.map(x => x + 1).length()}` "must still record `x`". That is now WRONG, and it was
the author's inference rather than the settle's claim: row F4 of
`settle_0488_append_nextline.ps1` is an ACCEPT row, so it says the TOOLCHAIN takes the
program and it does not pin the analyzer's name list at all. The settle is unaffected and
still passes. `x` is a lambda parameter, so it is BOUND, not READ; and `\{a == b}` still
records both names, because `==` is a comparison and a comparison READS its operands.

### THE CORPUS, THE PIN, AND THE GATE

The A/B of two wasms over the same corpus -- the pre-0496 tree (`git archive HEAD`, then
`be21ecd`) on one side, the 0496 tree on the other:

    actionable  37 -> 33        parsed     935 -> 957
    notices     9988 -> 10228   unreliable 2956 -> 2432
    withheld    552 -> 464      files      1029 -> 1029   UNCHANGED

The finding set is a STRICT SUBSET: GONE 4, NEW 0, and the four are all
`undefined name 'lexmatch'`. The other six corpora are BYTE-IDENTICAL to their pins.

The +22 parsed files reconcile file by file: nineteen moved from PARTIAL to FOUND, three
were PARTIAL with no findings (so the scan printed no row for them at all) and are FOUND
now, and two stayed PARTIAL and read FURTHER -- `builtin/string_methods.mbt` from line
117 to line 1465, and `string/internal/regex_parser/parser.mbt` with its post-boundary
findings down from 51 to 14, because its 61 `lexmatch` arms are now read-and-skipped
whole. NONE of the twenty-two carries a finding.

**THE GATE: 13 MUTATIONS, 12 KILLED, 1 SURVIVED AS DECLARED.** `_verify/mutate_0496.ps1`
names the test that must go red for each mutation, and every named test confirmed:

    M1 the escape counts UTF-16 units instead of characters      KILLED
    M2 the length check also consults the UTF-16 length           KILLED
    M3 the last code point is refused                            KILLED
    M4 a surrogate is accepted                                   KILLED
    M5 the braced form takes five digits                         KILLED
    M6 the hex escape takes three digits                         KILLED
    M7 a byte literal takes a unicode escape                     KILLED
    M8 the arrow is not recognised                               KILLED
    M9 a bound name is still recorded as a read                   KILLED
    M10 a lexmatch is read as a name                             KILLED
    M11 the with-longest clause is not consumed                  KILLED
    M12 a lexmatch says it was a match                           KILLED
    M13 the keyword list loses lexmatch                          SURVIVED (declared)

**M13 SURVIVES, AND THE PROBE MEASURED WHY IT IS A SURVIVOR RATHER THAN A HOLE.** The
mutation drops `"lexmatch"` from `is_moonbit_keyword`. Every `lexmatch` in the pinned
corpus is in EXPRESSION position, where the parser arm (M10) consumes it, so no name
ever reaches the frame and the corpus's four findings stay at four with the entry
removed. The entry is DEFENSIVE; the ARM is load-bearing.

But the survivor's falsification condition -- "a `lexmatch` ever appears in a pattern or
inside an interpolation" -- is now MEASURED rather than hypothetical. A two-name probe,
`\{lexmatch}` beside `\{notakeyword}`, scanned with the 0496 wasm: the control produces
`no visible binding for 'notakeyword'` and the `lexmatch` produces NOTHING. So in the
interpolation position the keyword entry IS the only thing standing between the word and
a finding. The survivor is therefore CORPUS-SCOPED, not universal, and it is kept as a
declared survivor because that is what it is.

=> 判据: A SURVIVOR WITH A PROVE IS A DIFFERENT THING FROM A SURVIVOR WITH NO PROVE, AND
THE PROVE HAS TO SAY WHERE IT STOPS BEING TRUE. M13's argument was that the keyword entry
is defensive while the parser arm is load-bearing, and that is exactly what the gate
measured -- 1163/1163 still green. A survivor that is merely tolerated is a hole; a
survivor that comes with the condition under which it would stop surviving is a
measurement. The condition was then MEASURED rather than left hypothetical, and what it
found is that the entry matters in a position the corpus does not contain. That is worth
more than a green gate, because the next corpus that contains one will find it.

### THE FULL RELEASE GATE FOUND THREE MORE DEFECTS, AND ALL THREE WERE IN THE HARNESS

The full gate failed at exactly one stage -- `grammar probe control` -- and the mutation
gates were skipped because of it. That control is the one that proves the grammar probe's
REAL GAP tally can fire at all, so a red there is not a nuisance: it means the probe's own
verdicts cannot be trusted.

**THE FAILURE WAS NOT A CORPUS PROBLEM, AND THE MESSAGE SAID IT WAS.** The control
printed:

    - no corpus file is both legal MoonBit and unread by this frontend, so there is
      no row left that can prove the REAL GAP tally fires.

    - pin a NEW corpus that still contains a gap this frontend cannot read, or

That message is ACTIONABLE, which is exactly why it had to be doubted first. And it was
wrong: 0496's tree still has 55 PARTIAL files in `moonbit_core`, so the corpus had not run
out of gaps. Three defects, all in the harness, and all three had been waiting for a
corpus state that could show them.

**DEFECT ONE -- THE SEARCH RAN OUT OF BUDGET, AND THE CONTROL BLAMED THE CORPUS.** The
derivation's check cap was 12, and it had been calibrated to a corpus state where the
planted gap sat at check ~4. 0496 closed the escape gap the control had been planting
(`string/quickcheck_test.mbt:138`), so the search walked on: five method-heavy unreadable
files first -- `string/internal/regex_parser/parser.mbt`, `sorted_set/set.mbt`,
`sorted_map/map.mbt`, `set/linked_hash_set.mbt`, `ref/ref.mbt` -- and reached
`range/quickcheck_test.mbt` at check **123**. The cap stopped it at 12. The log said
"stopped at the 12-check cap; unreadable files remain" TWO LINES ABOVE a message claiming
the corpus had no gaps left.

=> 判据: A MESSAGE THAT NAMES A REMEDY IS THE FIRST THING TO DOUBT. "Pin a NEW corpus"
was actionable, so it was believable, and believing it would have meant pinning a
seventh corpus to work around a number that was twelve. The gap was at 123 and the cap
was 12; the corpus was never the problem. The cap is now **500**, measured: the gap is at
123 and one check costs ~0.3s, so the whole corpus can be walked in under three minutes.

**DEFECT TWO -- THE CORPUS WAS READ WITH THE WRONG ENCODING.** `File.ReadAllLines` does
NOT read UTF-8: its default encoding is `Encoding.Default` -- the ANSI codepage of the
machine -- and it only switches to UTF-8 when the file carries a BOM. The pinned corpus
files have no BOM, so every non-ASCII byte in them was decoded as GBK on this machine and
re-encoded on the way into the probe package. The new candidate carries an em dash in a
doc comment, and the bytes that came out are not valid UTF-8:

    moon check  ->  [3001] "Could not read the file because it contains invalid UTF-8 streams"
                   -> MOON-BAD
    the scanner ->  parsed=1, CLEAN
                   -> SELF-OK

So the planted row was NEITHER a gap NOR a too-permissive row, and the control failed on a
row that had never been one -- with the corpus named as the culprit. The read is now
explicitly UTF-8.

**DEFECT THREE -- THE PROBE WROTE THE SAME WRONG BYTES.** The probe wrote each case with
`Set-Content`, which writes the ANSI codepage on Windows PowerShell 5.1. Same corruption,
on the write side. The cases are now written as UTF-8 without a BOM.

**AND THE READ HAD NO RETRY, WHICH IS THE OPEN BOARD ITEM.** `File.ReadAllLines` THROWS
when another process holds the file open, and the old code caught that and skipped the
file SILENTLY -- one more unreadable file per locked read, and a gap the search could not
reach for a reason that had nothing to do with the gap. That is rule 9, the rule the
mutation harness got after the 0455 gate failed on a memory-mapped file; it is now
applied here too, with the retry on the TRANSIENT and the verdict untouched.

**AND THE CONTROL NOW SAYS WHICH OF THE TWO FAILURES IT IS.** The derivation reports
whether it stopped on the cap, and the control's failure message branches on it: the
search ran out of budget (fixable) is a different fact from the corpus ran out of gaps
(worth recording). The second branch would have been untested code -- the very complaint
this file makes about its own `--SimulateExhaustion` switch -- so a `--SimulateCapHit`
switch exercises it. Both were run: each FAILS, and they say different things.

**THE FIVE ASSERTIONS ARE UNCHANGED.** The planted row is still derived at run time from
the pinned corpora, the control still fails when no live gap can be found, and the
control now passes on a row that is real corpus code:

    core:range/quickcheck_test.mbt:69   item 127-158
      fn anchors(min : BigInt, max : BigInt) -> Array[BigInt] { ... }
    MOON-OK (moon check: 0 errors, one `unused_value` warning)
    SELF-FAIL (the scanner: parsed=0, 13 findings withheld)

The gap is the `N` SUFFIX on an integer literal -- `0N`, `1N`, `-1N`, `2N` -- which is the
family the 0494 inventory listed as "7 `undefined name 'N'`". `moon check` accepts it.

=> 判据: A READER THAT IS WRONG IN A WAY THE DATA NEVER EXERCISES IS NOT A READER THAT
IS RIGHT. The ANSI read was wrong for every corpus file with a non-ASCII character in it,
and the corpus is full of them -- em dashes, Chinese comments, the occasional box
drawing. It was invisible because the planted rows happened to be ASCII: a top-level `let`
of char literals, then a `fn` with an `N` suffix. Nothing about those two rows was
special, and nothing about them was SAFE. A defect that only shows up on the day the data
changes shape is a defect that was always there.

=> 判据: A CONTROL THAT FAILS IS A CLAIM, AND THE CLAIM IS THE FIRST THING TO CHECK. The
control did not fail because the corpus changed; it failed because the CONTROL was
looking in a place the corpus had left. The gate caught a gate lying to itself, which is
the better story -- and the fix was to the harness, not to the corpus and not to the
assertions.

### THE GATE FOUND THREE MORE GATES THAT 0496's OWN SOURCE CHANGES BROKE

The next full run went red at three gates, and each one failed in **one second** --
which is the tell that it ABORTED rather than ran:

    0459   ABORT: 1 pattern(s) absent. No suite was run.
    0480   ABORT: 3 pattern(s) absent. No suite was run.
    0488   ABORT: 2 pattern(s) absent. No suite was run.

All three are the ESCAPE gates -- 0459 settled the braced form, 0480 the unbraced one,
0488 the interpolation collector that 0496's third fix also touched -- and all three were
broken the same way 0495 broke five: **0496 moved the text they anchor to**. A moved
anchor is not a typo to fix. It is re-anchored onto the current text with the **same**
mutation, and then MEASURED to see that it still kills.

    0459 M4   `let braced_u = e == 'u' &&`  ->  `let braced_u = !byte_form &&` + `e == 'u' &&`
    0480 M1   the fifth-character test     ->  the unbraced form's digit bound `(4, 4)`
    0480 M2   `let bare_u = !byte_form &&`  ->  `bare_u` was DELETED; the byte form is now
                                              refused by `if byte_form && e == 'u'`
    0480 M3   the first two digit checks   ->  the same `(4, 4)` bound
    0488 M5   the label branch's condition ->  the same branch, minus the `=>` carve-out
    0488 M6   the `!= '='` AND `!= '>'`     ->  the `!= '='` alone, because `=>` moved

All six were re-anchored, and all six still KILL, with the named test confirmed:

    0459   6 killed, 0 survivors
    0480   4 killed, 0 survivors      (was 3 killed + 1 declared survivor)
    0488   6 killed, 0 survivors

**AND 0480's M3 IS THE ONE THAT MATTERS MOST.** It was a declared SURVIVED, and its
proof said, in its own words, that it "expires the moment the guard is rewritten" and
that the survivor "has to be re-argued rather than inherited". 0496 REWROTE THE GUARD.

The old proof was this: dropping the first two digit checks changes nothing, because the
old digit loop stopped at the first NON-hex and wrote NOTHING when it consumed none -- so
an escape admitted by a weakened guard contributed no character, and the one-character
check refused the literal either way. That was a claim about the SHAPE of the old guard.

0496's guard does not have that shape. It counts the characters it writes, and the digit
count is a PER-FORM BOUND -- `(4, 4)` for the unbraced form -- checked against the digits
that were actually read. Lower the bound to `(2, 4)` and `'\u07f'` -- three digits, where
the toolchain REJECTs it with 3001 -- is read as U+007F: ONE character, no report. A
false ACCEPTANCE, and exactly what the row is named for.

So M3 is a KILL now, and the PROVE IS DELETED RATHER THAN REWORDED.

=> 判据: A PROOF THAT NO LONGER HOLDS IS NOT A WEAKER PROOF -- IT IS NO PROOF. The survivor
was honest about its own expiry date, and the honest thing to do on the expiry date is to
re-argue it, not to extend the lease. A reworded proof is the worst outcome available:
it keeps the green gate, keeps the word "survivor" in the table, and hides the fact that
the thing it was reasoning about no longer exists. The mutation became STRONGER, not
weaker -- the same weakening of the same guard now produces a false ACCEPTANCE instead
of a differently-refused literal -- and the gate says so.

**AND 0488's `=>` CARVE-OUT MOVED, SO A NEW MUTATION CLOSES THE TRIO.** 0496 gave the
arrow its own branch in the collector, above the label branch. 0488's M6 covered the
`==` and `=>` carve-outs together; it now covers `==` alone, and the `=>` half moved to
0496. That is not a coverage loss, because the `=>` branch was never mutation-covered at
all -- and that is a gap worth naming rather than a gap worth patching quietly:

    0496 M8    the LOOKAHEAD          -- the SPACED spelling `sb => sb`
    0496 M9    the BOUND-NAME skip    -- a USE of a bound name is not a read
    0496 M9b   the `=>` BRANCH        -- the TIGHT spelling `sb=>sb`

M8 and M9 CANNOT SEE THE `=>` BRANCH GO AWAY. Delete that branch and M8's mutation
changes nothing (the tight spelling no longer reaches the lookahead either) and M9's
mutation changes nothing (the bound name is never bound). Both would SURVIVE a deleted
branch, and a survivor that cannot see a deletion is not guarding the thing it names.
M9b sees it: the arrow's `== '>'` test becomes `== 'x'`, the branch stops firing, the
name falls through to the label branch and is dropped as a LABEL instead of being BOUND,
and the USE of it later in the same interpolation comes back as a read of the enclosing
frame.

=> 判据: TWO MUTATIONS THAT BOTH BREAK THE SAME GUARD CAN STILL BE ONE MUTATION AND ONE
GAP. M8 and M9 look like a pair because they are about the same feature, and a reader
would say the tight spelling is covered. It is not: the two mutations cover the two
SPELLINGS of one path, and the path that reaches the collector without a space -- the
one the corpus actually uses, in `builtin/autoloc.mbt:83` -- had no mutation at all
until this one. Coverage is a property of the CLAIM, not of the feature it belongs to.

### THE COUNTS, AFTER

    test suite                 1163 passed, 0 failed   (1136 before 0496; +27)
    mutation gates             79 in the release gate (78 before 0496)
    moonbit_core actionable    33   (37 before 0496)
    the other six corpora      BYTE-IDENTICAL
    0496's own gate            14 mutations: 13 KILLED, 1 declared survivor with its proof
    gates re-anchored          6 (0459 M4, 0480 M1-M3, 0488 M5-M6) -- the SAME mutations,
                               re-anchored on the current text and MEASURED to still kill
    harness defects found      3 in the grammar probe's own machinery -- its check
                               budget, the corpus read's encoding, and the probe's
                               write encoding -- and the probe's read gained the
                               rule-9 retry the board had been carrying

=> 判据: AN UNCOVERING IS NOT A REGRESSION. `builtin/autoloc.mbt`'s `no visible binding
for 'sb'` was WITHHELD behind a parse boundary, so the inventory could not see it; 0496's
`lexmatch` fix made the file readable and the withheld finding appeared. It was FIXED in
this increment rather than pinned, because pinning `actionable=1` would have frozen a
defect in the analyzer into the pin and called it a corpus fact. This is the same shape
as the 0488 `radix` finding, and the rule is the 0488 rule, written there for exactly
this reason.

=> 判据: A CRASH IS WORSE THAN A WRONG ANSWER, AND IT IS INVISIBLE UNTIL IT IS MEASURED.
One `'\u{110000}'` took the whole scan down, and the scan still reported a SUMMARY line
for the files it had managed to read -- so the failure looked like a corpus that happened
to have fewer findings. The bound check is not a refinement of the escape rule; it is the
difference between a scanner that answers and a scanner that stops.

## 0496b: THE CENSUS THAT WAS MEASURED OVER SIX CORPORA, AND THE 58 THAT WERE NEVER COUNTED

### THE CLAIM, AND WHERE IT LIVES

The 0.4.31 README says, in the `--per-function` box:

> the per-function view was measured across the pinned corpora and reported **116**
> `actionable` findings ... They were an *inventory of what is still wrong with the
> behavioral lens*, and 0.4.31 emptied it.

and, under the 0.4.31 changelog:

```
    per-function actionable findings   116 -> 2   (the 2 are the documented #doc(hidden) limit)
```

**THE CENSUS THAT PRODUCED THOSE TWO COVERED SIX CORPORA.** The script that ran it --
`_verify/_dir2_corpora.ps1`, an untracked scratch file, so no history and no pin --
lists exactly six: `moui`, `moonbit_labeler`, `moonbit_image`, `async`, `proton`,
`proton_contract`. `moonbit_core` is not in it. The README's own vocabulary calls
the corpora "the seven pinned corpora" three paragraphs above the claim, so the
sentence "measured across the pinned corpora" was read -- correctly -- as seven.

The seventh corpus carries MORE findings than all six put together. So the claim was
true of the corpora that were measured and false of the ones that were not, and the
inventory that 0.4.31 declared empty was not empty.

### THE MEASUREMENT: TWO WASMS, ONE CORPUS, TWO CENSUSES

The pre-0496 tree is `git archive HEAD` = `be21ecd` = v0.4.31. Its wasm was built
beside the 0496 one and BOTH were pointed at the same corpus with the same flags:

```
                        pre-0496 (be21ecd)        0496
    files                     1029                 1029      UNCHANGED
    parsed                     935                  957      +22
    actionable                  64                   56       -8
    notices                   9988                10228
    unreliable                3139                 2612
    withheld                   597                  513
    total                    13191                12896
```

The finding sets differ by exactly **8**, with **zero new**: all eight are
`undefined variable 'lexmatch'` -- the 0496-B false positive, at
`string/internal/regex_parser/parser.mbt:32`, `internal/strconv/strconv_bool.mbt:18`,
`internal/strconv/strconv_int.mbt:174`, `internal/strconv/strconv_number.mbt:175`,
`diff/diff_align_test.mbt:56` and `:94`, `diff/diff_word_test.mbt:33`, and
`builtin/autoloc.mbt:63`.

**SO 0496 MADE THE CENSUS BETTER, NOT WORSE: 64 -> 56 over the increment, and 66 -> 58
over the seven corpora.** The number that went UP is not a number that went up; it is a
number that had never been counted. The module view's numbers went 37 -> 33 over the
same increment, and the two views agree on `files`, `parsed` and `notices` -- which they
must, because the notices are the parse-boundary findings and the parse is the same in
both views -- and they differ on `unreliable`, `withheld` and `actionable`, which is
where the per-function entry does its extra work.

### THE TWELVE FAMILIES

`_verify/census_perfunction.ps1` -- TRACKED, so the seventh corpus cannot be dropped
again -- runs the per-function scan over all seven and puts every actionable finding
into a named family. A finding that lands in no family is printed as UNCLASSIFIED and
makes the script exit 1, because a census that silently buckets what it does not
understand cannot be compared with the next one.

```
    PER-FUNCTION CENSUS actionable = 58
      per corpus: moonbit_core=56 proton=2

    A  a hex float literal is not read                     12
    B  a BigInt literal's N suffix is not read               5
    C  == between two arrays                                 6
    D  a + the operator table does not have                  3
    E  a * on a struct                                       3
    F  a name the analyzer cannot see                        9
    G  unreachable code                                     11
    H  a local that is assigned and never read               2
    I  abs on a Double                                       1
    J  a * on two function values                            1
    K  a local call with a named argument                    3
    L  the documented #doc(hidden) limit                     2
```

Family A is twelve sites of ONE reader gap: `0x1.0p1023` is a C99 hex float, and the
lexer reads `0x1` and then an identifier, so the exponent part is reported as an
undefined name -- four times as `'p1023'`, three as `'p'`, three as `'P'`, once as the
whole mantissa `'F6A8885A308CA8A54'`. Family B is the same shape on a different
literal: `0N` and `-1N` are BigInt literals and the suffix `N` is read as a name.

Family G -- eleven `unreachable code` -- is the lens's OWN claim and it is not a
scope limit: the lens says the statement cannot be reached, and there are eleven
sites where it says so. Family H is the same: two locals assigned and never read.
Those thirteen are findings about the code; the other forty-three are the analyzer
describing its own edges.

### THE PROOF THAT NONE OF THE FIFTY-SIX IS A DEFECT IN THE ANALYSED CODE

The claim needs two halves and only one of them is visible in a number:

1. **ACCEPTED** -- `moon check` reports no diagnostic at any of the 56 sites.
2. **READ** -- `moon check` actually LOOKED at those files.

The second half is the one that cannot be shown by a count. A file with no diagnostic
is indistinguishable from a file nobody opened. So `_verify/control_perfunction_census.ps1`
OPENS the file: a deliberate type error is appended to one of the twenty-four files
that carry a finding, and the error MUST come back for THAT file. One file at a time,
because a broken package makes the toolchain stop type-checking the packages that
depend on it -- and a run that finishes suspiciously fast did not run the suite. (The
first version of this control injected into all twenty-four at once, got four errors
instead of twenty-four, and finished in **1 s** where its neighbour took 16 s.)

    files carrying an actionable finding: 24
    BASELINE   moon check --target all on an untouched COPY
               elapsed=22s  errors=1
               ERROR json/README.mbt.md:48
    the positive control
               read by moon check: 24 of 24
    after restore: errors=1  json/README.mbt.md:48

The corpus's own single error is in `json/README.mbt.md` -- a `.mbt.md` literate file,
and not one of the twenty-four. So the twenty-four carry nothing, and the control
proves they are read. The corpus is COPIED; the pinned directory is never touched.
The known error is the control FOR the control: if the corpus ever grows a real
error, the control refuses to absorb it and fails.

### FIVE FILES THAT THE JS TARGET NEVER COMPILES

The control first ran against `--target js` and **five of the twenty-four produced no
probe error** -- which reads exactly like "the file is not read", and is not.
MoonBit's per-file `targets` options in `moon.pkg` decide which files a target
compiles:

```
    bigint/bigint_default.mbt     [ "not", "js", "wasm", "native" ]   -> the wasm-gc target
    bigint/bigint_wide.mbt        [ "native", "wasm" ]
    bigint/decimal_wide.mbt       [ "native", "wasm" ]
    builtin/double_scalbn.mbt     [ "not", "js" ]
    math/algebraic_double_nonjs.mbt  [ "not", "js" ]
```

Under `--target all` all twenty-four are reported. **A FILE THAT NO TARGET COMPILES
IS NOT A FILE THE CHECKER ACCEPTED** -- it is a file the checker never saw, and the
difference between the two is exactly the difference between "accepted" and "not
read". The same five carry 8 of the 56 findings (families A, D and E), so a control
run on the wrong target would have concluded that a fifth of the corpus was unchecked.

=> 判据: A FILE WITH NO DIAGNOSTIC IS NOT EVIDENCE THAT IT WAS READ. The census's claim
that none of the 56 is a defect in the analysed code has two halves -- `moon check`
accepts the file, and `moon check` OPENED the file -- and the second half is the one a
number cannot carry. Five of the twenty-four looked unchecked under `--target js` and
were not: MoonBit's per-file `targets` options simply do not compile them there. A
control that measures the wrong target produces a confident false negative, and the
only defence is to ask the checker to demonstrate that it is looking.

### THE TWO ARTEFACTS THAT MAKE IT IMPOSSIBLE TO MISS THE SEVENTH AGAIN

- `_verify/census_perfunction.ps1` -- the census over SEVEN corpora, TRACKED, with the
  families named and an UNCLASSIFIED finding failing the run.
- `_verify/control_perfunction_census.ps1` -- the positive control that proves the
  files are read.
- `release.ps1` gained a stage for each: `per-function census vs pinned baseline`
  (per corpus, 0/0/0/0/2/0/56, total 58) and `per-function census control (the files
  are READ by moon check)`.

**THE PIN IS THE POINT.** The corpus pins in `release.ps1` are the MODULE view's
numbers, and the per-function view had none. A published number that is not gated is
a number that can go missing silently, and this one did.

=> 判据: A CENSUS OF THE CORPORA YOU HAVE IS NOT A CENSUS OF THE CORPORA YOU PIN. The
0.4.31 release emptied the inventory over six corpora and published the emptiness,
because the seventh corpus was not in the census script -- an untracked scratch file,
with no pin and no history to read. The number was true and the sentence around it was
not. The fix is not a better sentence; it is a census that is TRACKED, that names the
corpora it covers, that fails on a finding it cannot classify, and that the release
gate PINS.

### THE FULL GATE ABORTED AT A STAGE THAT CANNOT PASS BEFORE THE PUBLISH, AND THE REPO HAD SAID SO

The first full run of the release gate on this tree aborted at exactly one stage:

```
    === published package self-scan ===
    ABORT: the scan produced no output. That is not a clean scan.
```

That stage asks the registry for the version in `moon.mod` and asserts that the tree it read
IS that version. `moon.mod` had already been bumped to 0.4.32, which is not published yet, so
the registry had nothing to serve. **THE ORDER OF THE RELEASE IS THE REASON, AND THE REASON WAS
ALREADY WRITTEN DOWN** -- `_verify/release.ps1` says, in a comment that predates this
increment:

> THIS STAGE IS A POST-PUBLISH CHECK, and the ORDER of the release is what makes that true. So
> once `moon.mod` names a version that has not been published yet, this stage CANNOT pass: the
> registry has nothing to serve, `moonx` prints nothing, and the stage aborts with "moonx
> produced no output. That is not a clean scan." ... So the release order is: 1. the local gate
> -- and `-SkipMutations` runs the corpus pins and the own-source self-scan, which is what has to
> be green BEFORE the version is bumped; 2. bump `moon.mod`, sync the READMEs, commit, tag, push
> the tag -- CI publishes; 3. THIS STAGE, against the version that was just published.

This release bumped the version before the gate run, so the stage aborted on an ORDERING FACT
and not on a defect -- and because the corpus comparison is gated on `$failed`, the pins **and
the two new stages** never ran in that pass. The 79 mutation gates had all gone green in it,
and the gate was re-run with `-SkipMutations`, which is the run that measured the pins, the
census and the control. The published-package self-scan is then run against 0.4.32 after CI
publishes it, which is what stage 5b is FOR.

=> 判据: A GATE THAT CANNOT PASS YET IS NOT A RED GATE, AND THE ORDER IS PART OF THE GATE. The
stage printed "the scan produced no output", which is the line a registry that serves nothing
and a broken scan both print; only the coordinate run tells them apart. The stage was not
weakened, and the abort was not read as a regression -- it was read as what it was, an ordering
fact the release script had already documented in its own comments, and the fix was to run the
gate the way the script says to run it.

### THE COUNTS, AFTER

```
    per-function census, SEVEN corpora   66 -> 58   (core 64 -> 56; proton 2 -> 2)
    the module view                      moonbit_core 37 -> 33; the other six BYTE-IDENTICAL
    families                             12, and every one of the 58 is in a named family
    the files that carry them            24, and moon check READS 24 of 24
    the corpus's own errors              1, in json/README.mbt.md, and not one of the 24
    the census is now                    TRACKED, PINNED, and it fails on an UNCLASSIFIED finding
```


## 0497: THE ROSTER WAS HAND-KEPT, THE COUNT ROTTED, AND RULE 5 WAS NEVER ENFORCED

### THE CLAIM, AND WHERE IT LIVES

Direction 1's remainder was closed with a sentence. `_verify/mutate_lib.ps1`'s header
says, of the fourteen gates that used to carry their own copy of the runner:

> MEASURED 2026-10-20: all 74 numbered gates call `Invoke-MutationGate`, and it has
> NO pre-flight or SHA256 switch at all -- so every one of them gets the baseline, the
> pre-flight and the SHA256 restore check, and ZERO gates carry their own copy of the
> runner.

That sentence IS the closure of the direction. It is also a comment, and a number in a
comment is not checked by anything.

**MEASURED 2026-10-22: there are 79 numbered gates.** The sentence was five stale. Five
gates had been added in the two days since it was written; not one of them was wrong, and
nothing would have said so if one had been. The header's own table three lines above it
says so in advance -- "THAT TABLE IS A MEASUREMENT OF THE DEFECT, NOT OF THE PRESENT" --
which is exactly right, and also exactly the kind of statement that stops being true
without anyone noticing.

### THE ROSTER IS A LIST, AND THE LIST IS KEPT BY HAND

`_verify/release.ps1` runs the gates from `$gates = @('0412', ..., '0496')` -- 79
numbers, typed by hand, on one line.

A gate added to `_verify` and not to that list **NEVER RUNS**. It is on disk, it is
named like a gate, and a release run reports every gate green. A gate that does not run
is indistinguishable from a gate that passes.

MEASURED 2026-10-22: the two rosters agree today -- 79 on disk, 79 in the list, the
same set. So this is not a live defect; it is a defect with nothing behind it, and the
next gate added without a line in `release.ps1` would have been a silent hole.

It is worse than that, because the claim is PUBLISHED. README.md:

> **every mutation gate** -- 79 of them, and all 79 are inside the gate list in
> `release.ps1`, so no mutation gate is left out of the release path.

and README.zh.md, saying the same thing in Chinese. Both were true, and both were
maintained by hand.

### THE RULE THAT WAS DESCRIBED BUT NEVER ENFORCED

The harness's rule 5 says:

> A declared non-KILLED outcome has to carry its argument -- and that includes
> COMPILE-ERR, which is the easiest verdict to smuggle past.

The harness **printed** the argument when the field was there. It never **required** the
field. So the rule was a wish.

MEASURED 2026-10-22, over the 37 declarations in the 79 numbered gates: 35 `SURVIVED`
and 2 `COMPILE-ERR`, and **FOUR of them carried no `Prove` at all** -- one in 0418
(M11, the chain rewind), one in 0419 (M4, the over-eager return fn-type) and two in 0422
(M7, the arity gate, and M8, the method-call labels).

Three of the four had their argument written out in the comment directly above the
mutation, carefully, in the way this project writes things down. And it never travelled
with the RESULT: the gate's output said `SURVIVED` and nothing else, so the reader of
the gate log was told that a mutation was unobservable and not why.

Fixed in both places. The harness now FAILS a mutation that declares a non-KILLED outcome
without a `Prove`, and the four mutations carry the argument that was already written
above them -- carried over from the comment, not invented for the field.

### THE GATE, AND HOW IT WAS SHOWN TO GO RED

`_verify/check_gate_roster.ps1` checks four things, each of which can be wrong:

1. the roster in `release.ps1` IS the roster on disk, in BOTH directions;
2. every numbered gate uses the shared harness -- it dot-sources `mutate_lib.ps1`, it
   calls `Invoke-MutationGate` exactly once, it defines no local function of its own,
   and it passes no `--filter` (the old runners ran a SUBSET, and a filter that selects
   zero tests reports green for any mutation);
3. the shared harness still carries its guarantees -- sixteen of them, checked BY NAME,
   so deleting one fails this gate instead of quietly weakening every gate in the
   repository at once;
4. the COUNT in the harness header is the count on disk. The header is the claim; this
   is the check.

A gate that has never been shown to go red is a comment, so it has a `-SelfTest`: six
defects are injected into a COPY of `_verify` in TEMP -- a gate on disk the release
list does not name, a gate in the list that is not on disk, a gate off the harness, a
guarantee deleted from the harness, a `--filter` in the harness, a stale count in the
header -- and the copy has to fail with the right message. **All six are caught.**

The self-test earned its place immediately: it caught two bugs IN THE GATE, before the
gate had ever run on the real tree.

- The code-line filter checked for a here-string OPENER before it checked for a COMMENT.
  A header comment that quotes `@'` was read as an opener, the file was swallowed from
  there on, and **twenty-two gates were reported as "not on the shared harness"** -- a
  claim about code the filter had not read.
- The capture group was the whole `@'` instead of the quote alone, so the terminator
  was built as `@'@`, which matches nothing, and every here-string swallowed the rest
  of its file.

Both are one shape: a reader that cannot tell a comment from code, or a delimiter from
a delimiter, reports confidently on what it did not read. The second one had a silent
failure -- a file that read as four lines instead of four hundred -- which is why the
self-test asserts on a MESSAGE and not only on an exit code.

### THE COUNTS, AFTER

```
    numbered gates on disk                       79
    gates in release.ps1's list                  79   (the same set, both directions)
    gates that call Invoke-MutationGate          79   (each exactly once)
    gates that define their own function          0
    gates that pass a --filter                    0
    harness guarantees checked by name           16   (plus: the harness has no --filter)
    the count in the harness header              79   (was 74, and was five stale)
    declared non-KILLED outcomes                 37   (35 SURVIVED, 2 COMPILE-ERR)
    ... of those, carrying no argument             0   (was 4)
    injected defects the gate is shown to catch   6   (6 caught)
    the suite                                 1163/1163
```

The README's gate count is no longer pinned in the README gate either: it is COMPUTED
from the disk, so a gate added tomorrow fails the README check with the new number in
the message instead of failing with a missing literal.

## 0498: THE README, CHECKED SENTENCE BY SENTENCE, AND THE PROOF THAT WAS NOT RUNNING

### THE ASK

Check the README sentence by sentence. Not "run the link checker" -- **every claim**,
re-derived from the current tree.

Six of them were not true. One of the six was not a wording problem: it was a documented
command that had been failing for two releases, because nothing ran it.

### THE SIX, AND WHAT EACH ONE MEASURED

| the README said | measured 2026-10-22 |
|---|---|
| the largest raw-finding file on `moonbitlang/core` is "a 402-finding test file that is 402 notices and zero defects" | `builtin/int64_test.mbt` at **1022** -- all notices, no defects. The second is `builtin/extends.mbt` at 394. The *shape* was right; the number was wrong. |
| `moon check` has "a real parser and ~90 built-in warnings at 100% coverage" | the toolchain ships **no diagnostic catalogue**, so that number cannot be measured from here at all. Replaced by what can: `moon check --target all` on the same tree reports **one** error and 251 warnings of **two** kinds. |
| the release gate runs this list of stages | the list was missing two that exist: **this README's own links/anchors/versions/counts**, and **the mutation-gate roster** with its self-test. |
| every mutation gate "requires a named test to go red" | 426 live mutations; 389 expect a kill; **312** of them also NAME the test. The gate always requires *a* test to go red; it names one for 312 of the 389. |
| pyroduct's self-audit prints this block | the same run also prints four **known-design** findings, omitted above without saying so. Now said. |
| "**21/21 goals VALID** (unsat) ... each machine-checked with cvc5" | `moon prove src/core` **fails**. The measurement dates from 2026-10-03. See below. |

Both READMEs carried all six, in their own language, and `EXTENSIONS.md` carried the
"~90" one, and the root `main.mbt`'s usage comment carried a **stale `--mmd-auto` name
format** (`<label>-<version>_<stamp>.mmd`) that the code does not produce -- the code
builds `<package>_<version>_<moonbit>_<stamp>.mmd` through `scan_artifact_name`.

### THE PROOF, WHICH WAS NOT A WORDING PROBLEM

`moon prove src/core --why3-config .why3.conf` exits 1. Two INDEPENDENT breaks, and the
dates are what make them legible:

- **2026-10-09** -- two `#proof_pure` annotations were **false**: on `path_tail` and
  `unqualified`, whose bodies build a `StringBuilder`, which the prover rejects with
  error 4207. **One** false annotation stops the whole file from proving, so the package
  produced no goals at all. Both arrived in the same commit, `fae13db`.
- **2026-10-08** -- `src/core` grew `IfaceSymTab`, whose fields are `Map[String, Bool]`.
  The toolchain's proof prelude has **no `Map` theory** -- MEASURED: the prelude defines
  `t = int`, `bytes` and `readonlyarray 'a`, and `map` appears **zero** times in either
  shipped prelude. So the generated Why3 file declares `map int bool` and neither
  `moon prove` nor `why3` can load it. Supplying a prelude override through
  `MOON_PROVE_PRELUDE_OVERRIDE` makes the codegen emit the type -- but it emits it
  **after** the record that uses it, and why3 needs it before.

The 19 lemmas never touch `IfaceSymTab`. It is the **PACKAGE** that is proved, and the
package carries the type. `moon prove` is package-scoped: proving
`src/core/core_proof.mbtp` or `src/core/core.mbt` generates the SAME package MLW.

The first break is fixed: the two annotations are removed, and the six that remain are
exactly the ones the skill file records -- `pos`, `span_at`, `zero_span`, `Lens::rank`,
`Lens::lower`, `Family::severity`. The source now matches its own documentation.

The second is **not** fixed, because its fix changes this package's public API
(`@core.IfaceSymTab` is exported in `src/core/pkg.generated.mbti`). That is a
version-line decision, not a patch, so it is **stated in the README** with the reason and
the date, and it is left standing rather than papered over.

### WHAT DID NOT NOTICE ANY OF IT

**The release gate never ran `moon prove`.** A documented command that nothing runs is a
comment, and this one had been failing for two releases while the README published a
machine-checked proof result.

`_verify/check_prove_contracts.ps1` now runs it inside the gate. It FAILS on the
false-annotation class -- error 4207 -- which is checkable and can pass, and it REPORTS
the `map` limitation without failing on it, because that one is not fixable here.

It has been shown to go red: re-adding one false annotation produces **25** errors 4207
and a failed gate, and the failure names the function.

### THE VERSION IS NOW READ, NOT PINNED -- AND THE MATCHER HAD TO BE BUILT FROM THE PACKAGE'S OWN NAME

`_verify/check_readme_links.ps1` required the READMEs to name `0.4.32` **literally**. A
release then had to edit the GATE as well as the README -- and a missed edit either
blocked the release for the wrong reason or let a README naming an old version through.
The version now comes from `moon.mod`, the file the registry reads, and the failure
message says which version the README should have named. The mutation-gate count was
changed the same way in 0497, for the same reason.

Reading the version out of `moon.mod` fixed the ROT. It did not fix the MATCHER, and the
first release to use it found that out:

    FAIL: README.md must name 0.4.33 and nothing older; also found: 0.4.32

That `0.4.32` is the sentence `> (This note said **116 -> 2** until 0.4.32, ...)` -- a
**true statement about a correction that happened in 0.4.32**, and true in every release
after it. The RULE was right (a version the reader is told to install has to be current)
and the MATCHER was wrong: it matched "anything version-shaped" rather than "a reference
to THIS package".

So the matcher is built from the package's own name:

    moonbit_static_analysis@<v>       what the reader installs
    moonbit_static_analysis_<v>_      what the reader receives

A version number in PROSE is not a reference. A version number that FOLLOWS THE PACKAGE
NAME is. `CHANGELOG.md` is deliberately excluded: every release section names its own
version, and those are historical by construction.

### AND THE CHECK WAS LOOKING AT TWO OF THE THREE DOCUMENTS THAT SHIP

`SKILL.md` goes to the registry with the package (MEASURED: the published 0.4.32 tree
carries it at the top level) and it tells the reader to run

    moonx riantr/moonbit_static_analysis@0.4.32 riantr/moonbit_doubleML

That line has been maintained per release -- 0.4.30, 0.4.31, 0.4.32 -- and the version
gate looked only at the two READMEs. So a release could sync the READMEs, leave SKILL.md
behind, and publish an install instruction for the previous version with a green gate.
The gate now reads all three, and each document's install line is checked separately:
the READMEs show `moon add`, SKILL.md shows `moonx`.

Both new rules have been shown to go red:

| the defect | what the gate said |
|---|---|
| `SKILL.md`'s install line set to `0.4.31` | `FAIL: SKILL.md tells the reader to install 0.4.31; the released version is 0.4.33.` |
| `README.md`'s artifact name set to `0.4.31` | `FAIL: README.md must name 0.4.33 wherever it names THIS package; also found: 0.4.31` |

and the historical `until 0.4.32` note stayed FOUND and tripped neither.

### A WRITER THAT CORRUPTS A CHARACTER AND DOES NOT SAY SO

The Chinese changelog entry came out of the edit with **two U+FFFD** where one character
belonged, and nothing reported it. A replacement character is the one failure mode every
tool in this repository silently passes through: `moon check` does not read markdown, the
scanner does not read markdown, and the README gate only looks for whole phrases.

So the scan for it is now explicit: every file this round touched is read as UTF-8 and
searched for U+FFFD. All ten are clean, and the corrupted heading is repaired.

### THE COUNTS, AFTER

```
    the largest raw-finding file in moonbitlang/core   builtin/int64_test.mbt, 1022
    moon check --target all on the same tree            1 error, 251 warnings, 2 kinds
    live mutations                                       426
    ... of those, expecting a kill                       389
    ... of those, naming the test that must go red       312
    #proof_pure contracts in src/core                     6   (was 8; two were false)
    ... of those, false                                  0
    the self-scan                                        170 files, actionable 0
    the corpus pins                                      7 of 7 MATCH
    the per-function census                              TOTAL 58 MATCH
    the census control                                  24 of 24
    the release gate                                     96 stages, every one green
```

### THE RELEASE

`moonbitlang/async@0.22.5` was re-checked against mooncakes.io before the gate: the
registry's `latest_version` is `0.22.5`, which is what the module already pins, so there
is nothing to upgrade. The gate was then run on the final tree, the version was bumped,
and the READMEs and `SKILL.md` were synced.

=> 判据: A DOCUMENTED COMMAND THAT NOTHING RUNS IS A COMMENT. The proof was published as
21/21 machine-checked, and the command that produces it had been failing for two
releases. The claim was not wrong when it was written; it stopped being true, and the
only thing that would have noticed was something running it.

=> 判据: A READER THAT CANNOT TELL A COMMENT FROM CODE WILL CONFIDENTLY REPORT ON CODE
IT NEVER READ -- and a release document that says "21/21 goals VALID" is a CLAIM that
somebody has to check, the same way a number in a comment has to be checked. Six of this
README's sentences were not true, and five of them had been true when they were written.

=> 判据: A GATE THAT FAILS ON A TRUE STATEMENT GETS DISABLED, AND A DISABLED GATE IS A
COMMENT. "Every version in the README must be current" is right for the version a reader
INSTALLS and wrong for the version a reader is TOLD ABOUT IN PROSE -- and the gate that
could not tell the two apart was one release away from being switched off.

## 0499: THE PACKAGE SAID "FILES THAT MUST NEVER REACH THE REGISTRY", AND FOUR OF THEM DID

### THE FILE IS NOT CALLED `.mooncakesignore`

The packager's rule, from the toolchain's own release note (2026-09-21):

> Packaging now follows conventional ignore-file rules: the `.moonignore` in a folder
> -- or, if absent, `.gitignore` -- is used as the ignore file. By default, files and
> folders starting with `.` are ignored (this rule can be overridden via the ignore
> file), as is the `_build` folder (not overridable). The `exclude` and `include` fields
> in `moon.mod` will be deprecated.

MEASURED: `moon publish --help` and `moon package --help` expose no ignore flag; the
release notes and the packaging docs name only `.moonignore`; and this repository has
had a `.moonignore` since 0.3.4, whose own header already says "moon package does not
read .gitignore".

**There is no `.mooncakesignore`.** A file the packager never reads is a comment, so
the rules went into the file that IS read. Two consequences that are easy to get wrong:

- `.moonignore` **REPLACES** `.gitignore` as the ignore file -- it does not add to it.
  Every rule that matters has to be in BOTH files.
- The packager reads the **WORKING TREE**, not git. A dirty tree packages differently
  from a clean one, and the two are not the same set.

### FOUR SCRATCH FILES REACHED THE REGISTRY IN EVERY RELEASE UP TO 0.4.33

MEASURED against the published 0.4.33 tree (413 files): four of them were
`COMMIT_*.md` -- scratch commit messages, superseded by `CHANGELOG.md` since the 0497
README restructure, and referenced by nothing (`git grep` finds no mention of any of
them).

They were **TRACKED**, and a tracked file is in the checkout CI publishes from, so they
shipped in 0.4.30, 0.4.31 and 0.4.32 as well.

Thirteen files left the index: the four at the root and nine `_verify/commitmsg*.txt`.
They stay on disk (`git rm --cached`) and matching `.gitignore` rules keep them out.

### WHAT ELSE WAS EXCLUDED, AND WHY THE EVIDENCE WAS NOT

The scratch commit messages (23 on disk), the scan artifacts (24 `.mmd`), `pdf2md.zip`,
a stray file named `$null`, the gate transcripts, the remeasure dumps, the release-run
working copies, and the `_verify` working copies -- including `_verify/_work_*.mbt`,
which are mutated **source** copies.

The evidence is NOT excluded: the 79 mutation gates and their harness, the 70 settle
scripts, `_verify/NARRATIVE.md` and the roster gate all still ship.

**An ignore file that takes the evidence with it looks like a successful cleanup.**
That is why the rules were chosen backwards -- from what MUST ship -- rather than from
what looks like junk.

One file is named individually, because no shape rule can catch it without excluding
real test files: `src/lexer/lexer_0488_test.mbt` is SUPERSEDED (its rows live in
`src/parser/parser_0488_test.mbt`, because a test file lives in the package it tests
and `src/lexer` cannot see `@parser` -- Error 4020), and what is left is a comment-only
stub whose own header says "It is NOT tracked and must not be committed".

### THE PACKAGE CONTENTS ARE NOW A GATE

`.moonignore` is a list of intentions, and a list of intentions that nothing exercises
is a comment. `_verify/check_package_contents.ps1` runs `moon package --list` -- the
same command `moon publish` packages from -- and asserts BOTH directions:

- the junk is **out**: the scratch commit messages, the scan artifacts, the credential,
  the gate transcripts, the remeasure dumps, the un-committable stub;
- the evidence is **in**: the 79 mutation gates and the harness, the settle scripts, the
  narrative, the roster gate, the prove-contracts gate, the four documents a reader is
  sent to, the module manifest and the proof file;
- and **every tracked file ships**, except the six the toolchain drops by default
  (files and folders whose name starts with `.`).

It is release stage 4e.

**IT HAS BEEN SHOWN TO GO RED IN BOTH DIRECTIONS**, which is the point of asserting
both:

| the defect | what the gate said |
|---|---|
| the `COMMIT_*.md` rule commented out | `scratch commit messages (root)  23  FAIL` |
| `_verify/NARRATIVE.md` excluded | `the narrative  0  FAIL (want 1)` and `tracked but not in the package: 1  FAIL` |

### AND THE DECISION THAT WAS ASKED FOR: `IfaceSymTab`

`moon prove src/core` cannot succeed while `IfaceSymTab` is in the proven package,
because the toolchain's proof prelude has no `Map` theory. The question asked was
whether to move it.

**MEASURED, and the answer is no -- not on the 0.4.x line.** `@core.IfaceSymTab` is
named by **20 exported API lines** (MEASURED across the published `.mbti` files): ten in
`core` itself, and ten function signatures in SIX other packages -- `interp` (3),
`moonfiles` (2), `pipeline` (2), `parser`, `types` and `walk`. Moving one struct would
change the signature of ten exported functions in six packages.

And it would not fix the thing. The defect is that the proof prelude has no `Map`
theory; any package carrying a `Map` has the same wall. Moving `IfaceSymTab` only
moves the wall, and the 19 lemmas -- which are about `Lens::rank`, `Lens::lower`,
`Family::severity` and the `Span`/`Pos` helpers, and touch `IfaceSymTab` not at all --
would end up in a package that is not the one with the symbol table.

**THE CHEAPER HONEST OPTIONS, in the order they should be tried:**

1. **REPORT THE TOOLCHAIN BUG.** There is a reproduction, and it is one line long:
   `MOON_PROVE_PRELUDE_OVERRIDE` makes the codegen emit `type map 'a1 'a2`, but it emits
   it **after** the record that uses it, and why3 needs it before. That is an ordering
   bug in the proof codegen, and fixing it there helps every MoonBit user with a `Map`
   in a proven package -- this one included -- for no API change at all.
2. **IF THE PROOF MUST BE GREEN BEFORE THE TOOLCHAIN FIXES IT, RESTRUCTURE -- DO NOT
   MOVE.** The 19 lemmas prove `pos`, `span_at`, `zero_span`, `Lens::rank`, `Lens::lower`
   and `Family::severity`, and `Lens` and `Family` are plain `pub(all) enum`s with no
   `Map`. A new package holding those four types, the six `#proof_pure` functions and
   the 19 lemmas -- with `src/core` re-exporting the four names through `pub use`, the
   way it already re-exports for `.mbti` names -- would prove, and would keep
   `@core.Span` and friends working. That is **additive**. The re-export path has a
   history of its own here (0487: "a RE-EXPORTED type carried its name but not its
   MEMBERS"), which is the thing to test first.
3. **DO NOT CHANGE THE REPRESENTATION.** `IfaceSymTab` is on the hot path of every
   cross-file name resolution; replacing `Map` with an array of pairs would trade a
   toolchain limitation for an analyzer slowdown.

This is a **0.5.0** decision (a new package, a re-export layer, new prover
semantics), not a 0.4.x patch -- which is what the README now says, with the reason and
the date.

### THE COUNTS, AFTER

```
    the package, before this change             811 entries
    the package, after                          425 entries
    tracked files                               406   (was 419)
    tracked files not in the package               0   (except the 6 the toolchain drops by default)
    scratch commit messages in the package        0   (was 23 on disk, 4 of them tracked)
    scan artifacts in the package                 0   (was 24)
    the credential in the package                 0
    gate transcripts in the package               0
    mutation gates in the package                79
    the settle scripts in the package            70
    the narrative in the package                  1
    the roster gate in the package                1
    exported API lines naming @core.IfaceSymTab  20   (10 in core, 10 in six other packages)
```

=> 判据: AN IGNORE FILE THAT NOTHING EXERCISES IS A COMMENT, AND THE PACKAGE IT
DESCRIBES IS NOT THE PACKAGE THAT SHIPS. The rules existed since 0.3.4, and four scratch
files still reached the registry in three releases, because a rule that is only written
down is not a rule that is applied.

=> 判据: AN IGNORE FILE THAT TAKES THE EVIDENCE WITH IT LOOKS LIKE A SUCCESSFUL CLEANUP.
The package shrank by 386 entries and the gates, the settle scripts and the narrative
all still ship -- and the gate that checks the package asserts each of them by name.

=> 判据: MOVE THE SYMPTOM, AND THE WALL MOVES WITH IT. The proof fails because the
prelude has no `Map` theory. Moving the one `Map` out of `src/core` would have changed
the signature of ten exported functions in six packages and left the actual defect
exactly where it was.

## 0500: THE LABEL SAID `error:` ON A CONSTRUCT THE ANALYZER DID NOT READ

The question that started this increment was a line of output:

```
2:3 - error: match expression is outside the analyzed subset; it was read but not analysed (ParseError) [structural]
```

**The user's code is fine.** The finding says the analyzer read a `match` and did not
analyse it -- a declared scope limit, `src/core/advice.mbt` calls "a declared scope limit
of this analyzer, not a defect: there is nothing to fix". The `error:` is the defect: a
reader who sees it has been told their code is wrong when the analyzer is the one that did
not read it.

### FParse IS ONE FAMILY WITH TWO MEANINGS

The label was wrong because the question was asked in the wrong place. `FParse` is one
family, and two different producers make it:

| producer | what it is |
|---|---|
| `Parser::note_skip` (15 call sites) | a deliberate exclusion -- a scope limit |
| `moonfiles`' literate fence skip (1 site) | a deliberate exclusion -- a scope limit |
| the lexer's malformed-literal reports (8 sites) | a genuine defect in the file |
| `moonfiles`' malformed-interface reports (8 sites) | a genuine defect in the file |
| the parser's `err()` (1 site) | a genuine read failure |

Nineteen construction sites, two of them deliberate. The renderer asked "is this FParse?"
and the counter asked the same question, and both got the same answer for both kinds.

### MEASURED, NOT INFERRED

Every claim above is a measurement, and the measurement was taken over the WHOLE finding
set -- with `--findings-shown-per-file 1000000`, because the default cap of 40 per file
prints the first forty and the SUMMARY counts all of them, and a classification measured
over a truncated rendering is a classification of a SUBSET. That is the same mistake this
increment is about.

```
    tree                rendered ParseError lines   scope limits   genuine defects
    SELF                          1868                   1868              0
    moui                          4225                   4225              0
    moonbit_labeler                791                    791              0
    moonbit_image                  218                    218              0
    async                         1836                   1836              0
    proton                        2131                   2131              0
    proton_contract                 34                     34              0
    moonbit_core                 10228                  10228              0
                              ------                  ------          ------
    total                       23331                  23331              0
```

**23,331 rendered ParseError lines, every one of them a deliberate exclusion, and not one
of the seventeen genuine-defect producers carrying the marker.** In every corpus the
rendered ParseError count EQUALS the SUMMARY's `notices` count exactly (1868 = 1868,
4225 = 4225, 791 = 791, 218 = 218, 1836 = 1836, 2131 = 2131, 34 = 34, 10228 = 10228).

=> 判据: A LABEL THAT IS WRONG ON EVERY LINE IT APPEARS ON IS NOT A LABEL, IT IS NOISE WITH A
SEVERITY ATTACHED. The tool already had the word for this -- `notice` -- in its own counts,
its mermaid legend and its skill file. The rendered line was the only place that did not use
it.

=> 判据: TWO PREDICATES THAT AGREE ON EVERY MEASURED CASE ARE STILL NOT THE SAME PREDICATE.
"is this FParse?" and "is this a scope limit?" return the same answer on all eight trees
above, so the fix moves NO COUNT -- and that is precisely why the measurement had to come
first. A change that cannot be distinguished from no change by the numbers is only
distinguishable by the RULE, and the rule was wrong.

### THE FIX: ONE PREDICATE, ONE LABEL, AND NO NEW PUBLIC TYPE

`src/report/report.mbt` gains two functions:

- `Report::is_notice` -- the ONE definition of "this finding is a declared scope limit".
- `Report::severity_label` -- the label, used by the text renderer AND the JSON bridge.

Every consumer goes through them: `Report::render`, the SUMMARY's `notices` counter in
`src/sa/main.mbt` (two sites), the mermaid drawing's `is_notice`, and `jsoncli`'s
`to_finding`. The JSON bridge had its OWN copy of the severity mapping, which is how a
machine-readable channel ends up disagreeing with the human one about the same finding.

**`Severity` and `Family` are untouched, on purpose.** `Family::severity` is `#proof_pure`
and `severity_taxonomy_holds` is one of the nineteen lemmas in `src/core/core_proof.mbtp`,
with `type_error_family` enumerating `FParse => true`. A new `Family` variant would have
changed the proof subject for a rendering change; a `Severity::Notice` would have done the
same and worse. The proof says a ParseError is an ERROR-SEVERITY family, and that remains
true: severity is not the question. "Is this actionable?" is the question, and that is
`is_notice`.

**A field on `Report` was considered and measured out.** MoonBit has no struct field
defaults (`b : Bool = false` is a parse error, measured on the toolchain), so carrying the
flag on the struct means editing all NINETEEN construction sites plus the merge, across
nine packages -- and `Report` is `pub(all)`, so the shape would change in the published
interface file. A message is not a worse carrier: the pipeline ALREADY distinguishes a
skip from a read failure by exact message equality against the parser's own `skips` list
(`src/pipeline/pipeline.mbt:141`), so the message is where this codebase already keeps
the fact.

### THE MARKER IS A CONVENTION, SO SOMETHING HOLDS IT IN PLACE

The marker is the word `subset`: every deliberate exclusion says the construct is outside
a SUBSET of what the analyzer reads ("outside the analyzed subset" in the program
frontend, "outside the analyzer's MoonBit subset" in the literate one), and no
genuine-defect message contains it.

A convention nobody checks is a comment, so `_verify/check_notice_labels.ps1` is a new
release stage and it checks three things:

1. **The output contract.** On a real scan of this repository's own source, a message
   carrying the marker is rendered `notice:`, and `notice:` is used for nothing else. A
   count of zero fails the check.
2. **The four producer paths**, each with its own fixture, asserted against the tool's OWN
   messages rather than against literals written in the gate: the program frontend's
   deliberate exclusion and the literate frontend's are `notice:`; the literate frontend's
   malformed interface line is `error:`; the lexer's unterminated literal is never a
   notice.
3. **The source convention**, with the producers told apart BY MECHANISM and never by
   their own text -- `note_skip` is the parser's only skip mechanism (it is the only
   function that pushes to `skips`) and `subset_exclusion` is the literate frontend's
   decision. The marker is never used to decide what a producer is, so the check is not
   circular, and a new exclusion message that stops carrying the marker is CAUGHT rather
   than excused.

**Both halves have been shown to go red**, on a tree restored byte-exactly afterwards:

- labelling a scope limit `error:` again -> "FAIL: 1878 scope limit(s) labelled something
  other than notice:";
- dropping the marker from ONE skip message -> "FAIL: a note_skip message does not carry
  the marker".

=> 判据: THE RUNTIME HALF AND THE SOURCE HALF CATCH DIFFERENT FAILURES, AND BOTH ARE NEEDED.
Removing the marker from one message makes the rendered line CONSISTENT again -- it is
still a ParseError, and the label it gets follows the marker -- so only the source
convention catches it. A gate that checks the output alone would have called that tree
clean.

### THE COUNTS, AFTER

```
    the seven corpus pins                 unchanged, all seven MATCH
    actionable on every corpus             unchanged (0 / 0 / 0 / 0 / 0 / 0 / 33)
    the suite                             1094 js, 1174 wasm, 1094 wasm-gc   (+11)
    numbered mutation gates                80   (79 before 0500)
    live mutations                         430   (426 before 0500; 0500 adds 4)
    ... of those, expecting a kill         393   (389 before 0500)
    ... of those, naming the test          316   (312 before 0500)
    0500's own gate                        4 mutations, 4 KILLED, every named test confirmed
```

The corpus pins did not move, and that is the point: a LABEL fix that moved the numbers
would be a behaviour change wearing a rendering change's clothes. The eleven new tests are
the ones that pin the rule.

### THE INCREMENT THAT WAS DECIDED HERE, AND NOT DONE

The `IfaceSymTab` question from 0499 is unaffected and still open: `moon prove src/core`
cannot succeed while a `Map`-carrying public type is in the proof subject, the fix is a
0.5.0 decision, and the README says so with the reason and the date.

### THE README'S TEST COUNT IS NOW COMPUTED, NOT PINNED

0500 moved the README's test count (1163 -> 1174 on wasm, 1083 -> 1094 on js and
wasm-gc), and `_verify/check_readme_links.ps1` PINNED that count -- so the gate failed,
and the fix was to edit the pin. That is the gate working, but it is the gate working in
one direction only:

- a PINNED literal catches the README moving without the pin moving;
- it does NOT catch the SUITE moving without the README moving -- which is the direction
  that matters, because an increment that adds tests and does not update the README
  leaves a published number that is stale, and a pinned gate reads it as correct.

So the count is COMPUTED now: the gate runs the suite for wasm, js and wasm-gc and
checks the README against what the suite actually printed. It also asserts that js and
wasm-gc AGREE with each other -- they do, and they do for a structural reason: `src/sa`
needs the async runtime, so it is skipped on both, and its tests do not run there -- so
the README's one number for the two is a claim that has something behind it.

=> 判据: A PUBLISHED NUMBER THAT IS PINNED IN A GATE IS CHECKED IN THE WRONG DIRECTION. The
gate's job is to catch the world moving without the document, and a pin can only catch the
document moving without the gate. 0498 made the VERSION computed for exactly this reason;
0500 makes the TEST COUNT computed for the same one, one increment later.

### 0500's own lesson

=> 判据: MEASURE THE THING THE LABEL IS ABOUT, NOT THE THING THE LABEL IS ATTACHED TO. The
finding the user pasted was a scope limit, and the tool called it an error. Nothing about
the parser, the lexer or the subset was wrong -- the QUESTION was. Asking "is this
FParse?" where the question is "is this a scope limit?" is wrong on every line it appears
on, and no count can show it: the two questions agree on all eight trees measured.


## 0501: THE SUPPRESSION WAS PER FUNCTION, AND IT SHOULD HAVE BEEN PER BINDING

The `match` finding the user pasted in 0499/0500 was a LABEL problem, and 0500 fixed the
label. Underneath it there was a second problem, and it was not a label: when the
frontend deliberately does not analyse a construct, the analyzer switched off the
unused-local and unused-parameter checks for the WHOLE function that contained it.

    fn binop(op : Op) -> Int {
      let neg = -1
      match op { Add => 1 _ => neg }   <- the arms were never read
      neg
    }

One `match`, anywhere in the function, and the function's frame audit did not run at
all. That is the right call if the unread region could have read anything in the
function -- and it can, for `if` and `match` and `try` -- but it is ALSO right for a
binding that the region could not possibly have reached, and that is the part that was
wrong.

### WHAT IT COST, MEASURED

With the suppression switched OFF -- one line in `audit_suppressed`, and the diff
against the baseline capture -- the tool produces findings it does not produce with it
on:

| tree | UnusedLocal | UnusedParam |
|---|---:|---:|
| moui | 166 | 768 |
| moonbit_labeler | 112 | 53 |
| moonbit_image | 48 | 19 |
| async | 56 | 219 |
| proton | 54 | 267 |
| proton_contract | 0 | 0 |
| moonbit_core | 309 | 524 |
| self | 91 | 56 |
| **total** | **836** | **1,906** |

2,742 findings that the whole-function suppression was hiding.

### THE RULE, AND WHY IT IS SOUND

A region can only read a binding that was already in scope when the region began. The
region's own EXTENT is the threshold, and the END of it is the side that matters: a
region's span can cover code that WAS read -- the `if` CONDITION and the `match`
SUBJECT are parsed, and only the branches and the arms are not -- so a binding declared
inside that read part is in scope for the unread part, and the threshold cannot be the
region's START.

=> 判据: A NARROWING IS ONLY SOUND IF IT CANNOT JUDGE A BINDING THAT AN UNREAD REGION
MIGHT HAVE READ. The question "could this region have read this binding" is answered by
the region's GEOMETRY -- where it ended -- and not by a guess about what it contains,
because what it contains is exactly what nobody read.

The LAMBDA is the case that makes the end line the only sound choice. Its region's span
is the head TOKEN, one line, while its body runs on to later lines -- but a binding
declared inside that body was never walked, because the body was never read, so a
binding the walker DID walk is either before the head or after the body. Either way it
is outside the region's reach.

### AND IT RECOVERS NOTHING ON TODAY'S CORPORA. HERE IS THE NUMBER.

Every one of those 2,742 bindings is declared BEFORE its region, so the region could
still have read it, and the narrowing correctly stays silent. The rendered output is
byte-identical on all seven corpora. The only number that moves is `moonbit_core`'s
`unreliable`, 2432 -> 2448, and the reason is structural rather than accidental:
`unreliable` counts findings at or after a file's first READ FAILURE, and the frame
audit now runs for the 72 partial files, so it produces post-boundary findings that are
counted and not shown.

That is the honest result, and it is the result that redirects the work: **the
suppression is not where the findings are.** The findings are in the regions. Reading a
region is what recovers them, and the narrowing is what makes reading one pay off per
binding instead of per function.

### TWO TOOLCHAIN FACTS, MEASURED, THAT CLOSE TWO DOORS

**THERE IS NO COMPILER ORACLE FOR THIS FAMILY.** MoonBit's `moon check` has no
unused-local warning: the repository's own source has 91 `UnusedLocal` and 56
`UnusedParam` findings by the analyzer's measure and the compiler reports NONE of
them. The `0079` this repository's own `moon.mod` disables is *unused derive* --
measured by removing the line and reading the 28 diagnostics that came back, every one
of them on a `} derive(Eq)` line. And every pinned corpus sets `warn_list: ""`, so
there is no corpus to compare against either. The verdicts are the analyzer's own and
the rule has to be held by the rule's own gates.

**A MOONBIT LAMBDA CAPTURES THE ENCLOSING LOCALS.** Measured against the toolchain,
with a deliberate type error as the canary in the same file: `let f = fn() { x }`,
where `x` is a local of the enclosing function, produces NO diagnostic, while the
canary's `let bad : Int = "not an int"` comes back as `Error: [4014]`. So a skipped
lambda body CAN hide a read of the enclosing frame's bindings, and a lambda region
must keep silencing them. That closed the one lever that looked like it would recover
the most: "a lambda is a separate scope, so its region cannot read the enclosing
locals" is FALSE in MoonBit, and acting on it would have produced a false positive on
correct code.

### A MEASUREMENT THAT MEASURED NOTHING, AND HOW IT LOOKED LIKE A GREAT RESULT

The first attempt at proving that the 2,742 hidden findings are TRUE was a name
occurrence test: a local whose name occurs exactly once in its file cannot have been
read anywhere, so its finding is true whatever the holes are. It reported **836 of 836
and 1,906 of 1,906 -- one hundred per cent.**

It was wrong, and it was wrong in the most flattering way possible. The script took
the file path from the scanner's `FOUND` header by matching the rest of the line, so
the path it used was `defects=20<TAB>notices=66<TAB>C:\...` -- not a path at all. Every
file read FAILED, every occurrence count came out ZERO, and "occurs at most once"
scored zero as "provable". A measurement that could not read its subject reported a
perfect score.

The hand-check that caught it was one file and four names: `presentation.mbt` in moui
reports the parameters `native_accepted`, `anchor`, `base` and `viewport` as unused, and
`native_accepted` is READ at line 102 (`PreferNative | NativeRequired =>
!native_accepted`). The corrected measurement -- with the path taken as the LAST
tab-separated field, and a count of files that could not be read printed so a zero
cannot hide -- says: **0 of 836** `UnusedLocal` and **5 of 1,906** `UnusedParam` are
provable that way, because the other 758 mention their name elsewhere in the file.

=> 判据: A MEASUREMENT MUST ASSERT WHICH SUBJECT IT MEASURED, AND A MEASUREMENT THAT
CANNOT READ ITS SUBJECT MUST SAY SO OUT LOUD. `pins.ps1` has said this since 0480 and
the sentence cost me an increment's worth of confidence to learn twice: a script that
reads zero files and reports "occurs at most once" is not a weak measurement, it is
an inverted one. The fix is not a better test but a FAILING LOUDLY one -- and the
subject check is one line: count the headers whose path could not be read, and print
it.

### THE TWO NEGATIVE CONTROLS

A gate that has never been shown to go red is a comment, so both instruments were
shown to go red by putting the OLD rule back:

- `_verify/check_frame_audit.ps1` under the old whole-function skip: **2 of its checks
  fail**, on exactly the two fixtures the narrowing makes judgeable
  (`after_region.mbt` and `after_region_if.mbt`), and the other five stay green -- so
  the control is TARGETED, not a blanket breakage.
- the suite under the old rule: **3 of 1,184 tests go red**, the two "declared after a
  region" tests and the combined one, and the other six stay green.

Both trees were restored byte-identically (SHA256 checked).

### AND MY OWN FIXTURE WAS VACUOUS FOR A WHILE

The first version of the `if` fixture put the `if` in STATEMENT position. A
statement-position `if` is parsed into the tree and its branches are ANALYSED, so it
creates NO region at all -- the test was asserting the verdict, and the verdict was the
same with and without the narrowing. The gate caught it, because the fixture also
asserts the notice count and there was no notice to count. There is now a fixture and a
test for exactly that fact, so the `if` case cannot go back to being vacuous.

=> 判据: A FIXTURE THAT ASSERTS A VERDICT MUST ALSO ASSERT THE FACT THAT MAKES THE
VERDICT INTERESTING. "A local declared after an `if` is reported" is true of a
statement-position `if` where there is no region and no narrowing involved. The
assertion that means something is the one about what the region IS.

### THE COUNTS

    the corpus pins                 moui / labeler / image / async / proton / contract: UNMOVED
                                    moonbit_core: unreliable 2432 -> 2448, total 12693 -> 12709
    the rendered output             byte-identical on all seven corpora
    the suite                       1184/1184 wasm, 1104/1104 js, 1104/1104 wasm-gc
    the mutation gates              81 on disk, 434 live mutations, 397 expect a kill,
                                    320 name the test; 4/4 KILLED, every named test
                                    confirmed, every restore byte-identical
    the frame-audit gate            8 fixtures, all green; 2 checks red under the old rule

### THE README'S MUTATION COUNTS ARE NOW COMPUTED TOO

The README published "393 of the 430 live mutations expect a kill; 316 of them also
name the test" and NOTHING checked those numbers -- the same defect 0500 fixed for the
test count, one level down, still open. They are computed now, from the gate sources:
the number of `Name = 'M...'` declarations is the live count, the ones whose `Expect`
is not `KILLED` are counted apart, and the ones carrying a `MustRed` are the ones that
name their test. 434 / 397 / 320.

### THE FOUR NUMBERS THE README PUBLISHED, RE-MEASURED, AND NOW PINNED

The README carried four numbers that this increment had invalidated, and **not one of them
was gated**, so nothing said so. They are now MEASURED by the release gate, PINNED in one
place, and the README gate DERIVES its expectations from that place.

    the rendered ParseError lines      23,331  ->  19,215
    the own-source notice table        1,499 printed of 1,584  ->  the whole set
    the expression-level exclusions    379  ->  123
    the declaration-level exclusions   1,315  ->  1,461
    the suppression-off pair           836 / 1,906  ->  537 / 1,094

**THE NOTICE TABLE WAS COUNTED WITH THE PRINTING CAP AT 40**, so it counted 1,499 of the
1,584 notices -- 85 of them sat behind the per-file cap and the table simply did not have
them. With the cap lifted the table sums to the SUMMARY's own `notices`, and that is the
number worth publishing: a breakdown that does not add up to the total is a breakdown of a
printing cap.

**THE SUPPRESSION-OFF PAIR WAS MEASURED AGAINST THE OLD MECHANISM.** 836 and 1,906 were
measured when the suppression was PER FUNCTION. It is per binding now, and a `match` is not a
region at all, so the number describes a mechanism that no longer exists. Re-measured, with
the suppression switched OFF at its single point of control (`Walker::holes_in` -- the
unused-parameter check is gated on `holes.length() == 0` and the unused-local check on
`hole_can_reach(e, holes)`, so emptying that one array switches the whole thing off):

    moui                 83 / 353
    moonbit_labeler      93 /  23
    moonbit_image        39 /  11
    async                43 / 157
    proton               53 / 199
    proton_contract       0 /   0
    moonbit_core        186 / 341
    self                 40 /  10
    total               537 / 1,094

and the shipped build produces **one** of them: the `d_off` finding. So the suppression is
hiding 536 locals and 1,094 parameters.

=> 判据: A NUMBER THAT DESCRIBES A MECHANISM MUST BE RE-MEASURED WHEN THE MECHANISM
CHANGES, AND THE CHEAPEST WAY TO KNOW IS TO MEASURE IT IN THE SAME GATE THAT MEASURES
EVERYTHING ELSE. 0502 wrote that lesson down about the corpus numbers and then published
four more numbers that were not measured at all -- so the lesson is not a sentence, it is a
STAGE.

### THE THREE NEW GATES, AND WHAT EACH ONE IS FOR

`_verify/check_match_arms.ps1` is a new release stage: 17 fixtures plus a package directory
on the real scanner. Shown to go red twice, by injecting a defect into the analyzer's own
source, rebuilding, and running it.

`_verify/mutate_0502.ps1` is a new numbered gate: 12 mutations, 12/12 KILLED, every named
test confirmed, every restore byte-identical, every anchor unique.

`_verify/measure_suppression_off.ps1` is a new stage, and it is the one that makes the number
above a FACT rather than a recollection: it patches the analyzer's own source, rebuilds,
scans the eight trees, and puts the source back -- with the restore proven by SHA256, and
with the stage REFUSING TO START if it finds the source already patched. That refusal is the
part worth keeping: a stage that cannot tell "patched by me" from "patched by a run that was
killed" is how a tree ends up analysing with no suppression at all and nobody notices.

And two EXISTING stages grew a measurement, because the measurement was already being made
and only the COMPARISON was missing: the self-scan stage now counts its own notices by kind
and compares them with the pin, and the corpus stage now counts the rendered `ParseError`
lines of every tree, cross-checks each against that tree's SUMMARY, and sums the eight into
the number the README publishes.

### A PIN THAT IS DEFINED BELOW ITS READER IS NOT A PIN

The first release-gate run of this release FAILED, and it failed on the stage 0502 had just
added — the self-scan stage, comparing the own-source notice table with the pin:

```
FAIL: the own-source notice table drifted from the pin.
    pinned :
    actual : =0
FAIL: notice kinds that the pin does not name: anonymous function literal, const declaration,
    derive declaration, enum declaration, if expression, short lambda, struct declaration,
    test declaration, try expression
FAIL: expression-level 123 / declaration-level 1461, pinned  / .
```

The blank after `pinned :` is the whole diagnosis. The four pins had been written at the BOTTOM
of `release.ps1`, next to the other pin tables (`$PINNED`, `$PERFN`, `$CONTROL_N`), and the
stages that read them run EARLIER in the file. PowerShell runs a script top to bottom, so every
one of them was read as the EMPTY STRING.

Note what the measured values were: **expression-level 123, declaration-level 1461** — both
exactly the pins. The measurement was right and the gate was still red, because it was
comparing against nothing. The corpus stage carried the same defect and never ran at all:
`$PARSERR_TOTAL` was empty too, and the failure guard had already stopped the run before it
was reached. Two of the six pins were therefore never read in the whole run.

Two things turned a blank into a diagnosis in ONE reading of the log: the stage prints the
pinned value NEXT TO the measured one, and it prints the measured value even after the
comparison has already failed. A stage that had compared silently would have gone on to the
next stage, and the pin would have been found, if at all, by a reader.

The fix is a MOVE, not a second copy: the block went to the top of the file, above the first
stage that reads it, and the file now carries a guard that refuses to run at all if any of the
six pins is empty. The file also gained a UTF-8 BOM, because it holds non-ASCII and this
repository's convention is that a `.ps1` with non-ASCII needs one — without it PowerShell
reads the file in the ANSI code page and the `判据` lines come out as mojibake.

=> 判据: A PIN MUST BE DEFINED BEFORE THE STAGE THAT READS IT, AND A GATE THAT COMPARES
AGAINST A MISSING PIN MUST SAY SO OUT LOUD. "The number drifted" and "the pin was never read"
are the same red light, and what separates them is one blank line in the output. A pin that is
defined below its reader is not a pin; it is a comparison against nothing, and a comparison
against nothing cannot tell a wrong measurement from a right one.

=> 判据: THE FIX IS A MOVE, NOT A SECOND COPY. The tempting repair when a pin reads empty is to
put the value back where it was, or to write it down a second time somewhere it is definitely
in scope. Both make the number stop agreeing with itself. Moving the block keeps ONE place,
and the guard makes the failure impossible to misread a second time.


### THE FULL GATE ABORTED AT THE POST-PUBLISH STAGE, AGAIN, AND THE ORDER IS PART OF THE GATE

The full run of the release gate for 0.4.34 came back with exactly ONE stage red:

```
published package self-scan                                              False       7
    === published package self-scan ===
    ABORT: the scan produced no output. That is not a clean scan.
      stderr: Error: Prebuilt wasm asset does not exist
```

That stage asks the registry for `riantr/moonbit_static_analysis@0.4.34` — the version in
`moon.mod` — and there is no 0.4.34 on mooncakes.io yet, because the tag has not been pushed.
`moonx` has nothing to serve, so the scan printed nothing.

`release.ps1` says, in a comment that predates this increment:

> THIS STAGE IS A POST-PUBLISH CHECK, and the ORDER of the release is what makes that true.
> `selfscan_published.ps1` asks the registry for the version in `moon.mod` and asserts the tree
> it read IS that version — because a scan of a DIFFERENT package would still be able to print
> `actionable=0`. So once `moon.mod` names a version that has not been published yet, this stage
> CANNOT pass: the registry has nothing to serve, `moonx` prints nothing, and the stage aborts.

0.4.32 hit this exact wall and recorded it, in the section above. Nothing about it is new. What
IS new is that this time the abort was READ as what it was — an ordering fact — rather than as
a regression, and the stage was NOT weakened, re-anchored or skipped to make the gate green.

THE DIAGNOSIS IS ONE COMMAND, and the script names it. A registry that serves nothing and a
broken scan print the same line, so the only thing that tells them apart is a scan of a
version that IS published:

```
    package : riantr/moonbit_static_analysis@0.4.33
    moon.mod: 0.4.34
      scanned 152 files under .repos/riantr/moonbit_static_analysis/0.4.33
    FAIL: asked for 0.4.34, but the scan read version '0.4.33'.
      ok  parsed 152/152 files
      SUMMARY  files=152 parsed=152 actionable=0 notices=1528 ...
      ok  actionable = 0
```

The registry SERVES it: 152 files, 152/152 parsed, **actionable=0** under the 0.4.34 analyzer.
The delivery path — mooncakes compiling the artifact server-side and `moonx` running THAT — is
working, and the published tree is clean under the analyzer that is about to replace it. The
ONLY failing check is the version assertion, which is the stage doing precisely its job: it
refuses to call a scan of a different package a proof about this one.

THE TWO RUNS, AND WHAT EACH ONE MEASURES. The failure guard (`if ($failed.Count -eq 0)`) is
what makes the abort cost more than one stage: the corpus comparison, the per-function census
and the census control sit BEHIND the aborting stage, so they were skipped and never ran in
that pass. The evidence for this release is therefore TWO runs of the same gate on the same
tree, which is what 0.4.32 did:

    the full run            82 mutation gates, and every stage before the post-publish one   True
    the -SkipMutations run   the corpus pins, the census, the control, the suppression-off
                             measurement, the README gate, and every other stage             True

and the stage that is RED in the first run is the one that is required to be red before the
publish and green after it. The third run is the post-publish check itself, against 0.4.34,
once CI has published it.

=> 判据: A GATE THAT CANNOT PASS YET IS NOT A RED GATE, AND THE ORDER IS PART OF THE GATE.
What this release adds to that is the second half: a stage that aborts for an ordering reason
must be ABLE TO ABORT, and the run that aborts must still be a run whose other stages carry
their evidence. The fix is not to make the aborting stage pass; the fix is to know which run
measures what, to say so, and to run the diagnosis that separates "the registry has nothing"
from "the scan is broken".


### AND THE THIRD RUN, AGAINST THE VERSION THAT WAS ACTUALLY PUBLISHED

The last of the three runs of the documented order, and the only one that can happen after the
publish:

```
package : riantr/moonbit_static_analysis@0.4.34
moon.mod: 0.4.34

  scanned 160 files under .repos/riantr/moonbit_static_analysis/0.4.34
  ok  the tree scanned is 0.4.34
  ok  parsed 160/160 files
  SUMMARY  files=160 parsed=160 actionable=0 notices=1397 ...
  ok  actionable = 0

GATE OK: the published 0.4.34 scans its own shipped source clean.
```

The tree it read IS 0.4.34 — the stage refuses to call a scan of a different package a proof
about this one, and that refusal is the check that made the pre-publish abort DIAGNOSTICABLE
instead of merely red. 160 files, 160/160 parsed, **actionable=0**. The registry served the
package mooncakes compiled server-side and `moonx` ran THAT, so the delivery path is exercised
end to end, which no local run can do.

THE TWO PUBLISHED TREES, READ BY THE SAME ANALYZER. The published 0.4.33 tree read 152 files
and 1,528 notices under this analyzer; the published 0.4.34 tree reads 160 files and 1,397
notices. The tree GREW by eight files and the notices FELL by 131 — which is 0502 reading the
arms of the analyzer's own source, the same mechanism that removed 1,832 notices across the
seven pinned corpora.

THE CI RUNS, all green, and the one that matters is the third:

```
gate    | push | completed | success | master
gate    | push | completed | success | v0.4.34
publish | push | completed | success | v0.4.34
```

The publish job's steps include `moon.mod must agree with the tag`, `Gate`, `Publish to
Mooncakes` and `Create GitHub Release` — all success. The release is
<https://github.com/riantr/moonbit_static_analysis/releases/tag/v0.4.34>.

=> 判据: THE THREE RUNS OF A RELEASE ARE ONE RELEASE. The mutation gates and the corpus
comparison cannot be in the same pass — the failure guard stops the run at the first red
stage, and the post-publish stage is red BY DESIGN until the package exists. Reading that as
"the gate is broken" is wrong; reading it as "the gate passed" is worse. What makes a release
checkable is that each run says WHICH stage it carries, that the stage that cannot pass yet
is named as such, and that the post-publish stage closes the loop against the version the
registry actually served.


### THIS RELEASE

0.4.34. The version was bumped only after the local gate was green, and the README was
updated before the tag, so the registry never saw a README that described a different tree
than the one it was serving. `moonbitlang/async@0.22.5` was checked against mooncakes.io
first and is already the latest, so the gate ran on the current dependency set.

### WHAT IS NEXT, AND WHY IT IS 0502

The measurement points at one thing: **read the regions.** `match` is the biggest
expression-level region in every corpus except `moonbit_image` (moui 869, proton 364,
core 571, async 199, labeler 106, image 37, self 369), and `match` arms are ordinary
code that the analyzer reads past. Analysing them removes the region, and with 0501's
per-binding verdict in place, removing a region restores the verdicts for the bindings
the OTHER regions cannot reach.

That is the next increment, and it is a different kind of work: a pattern reader, the
bindings the arms introduce, and the arms' own bodies walked. The value of 0501 is that
it makes that work pay off per binding.


## 0502: A MATCH'S ARMS ARE ORDINARY CODE, AND READING THEM FOUND THIRTEEN FALSE POSITIVES

0501 narrowed the suppression from a whole function to the bindings a region could
actually have read, and it ended by pointing at the next step: **read the
regions.** `match` is the biggest expression-level region in every corpus except
`moonbit_image` (moui 869, proton 364, core 571, async 199, labeler 106, image 37,
self 369), and a `match`'s arms are ordinary code the analyzer reads past.

So 0502 reads them. The arms are parsed, the pattern's names are bound, the guard
is walked, the `with` constraint is read, and the body is walked.

### THE MEASUREMENT, AND IT IS NOT THE NUMBER THE HEADLINE SUGGESTS

A naive probe -- with the suppression switched off and nothing else changed --
produced **1,098 findings** (801 `UnusedLocal`, 297 `UnusedParam`). That is the
number the region was hiding, and it is real.

But the number that matters is the one that SURVIVES the arms being read for
real. Reading the arms for real is not a one-line change: an arm introduces
pattern bindings, so reading the body without introducing them manufactures
`no visible binding for 'x'` on correct code. The probe that survives that is a
**second** probe, and it says:

    14 candidate findings across the seven corpora
    13 of them FALSE POSITIVES, from 6 distinct mechanisms
     1 of them TRUE

=> 判据: THE NUMBER A FIX MAKES APPEAR IS NOT THE NUMBER THE FIX IS WORTH. 1,098
was the cost of the hole; 14 is what came back when the hole was filled
properly. Reporting the first without the second would have claimed 1,098
findings and delivered one.

### THE SIX MECHANISMS, AND WHERE EACH WAS MEASURED

Each of the thirteen false positives came from a different place, and every one
of them is a false positive **on code `moon check` accepts**.

| # | mechanism | corpus site |
|---|---|---|
| 1 | `as` may start a NEW LINE -- the postfix loop broke at the newline, so the `as` was read as a name | moonbitlang/async 0.22.4 `src/fs/watch.mbt:216,222,233` |
| 2 | a destructuring `let`'s INITIALISER was discarded by the collector | moonbitlang/core `internal/regex_engine/shared_types/rechar_set/rechar_set.mbt:202,214` |
| 3 | a same-package type's METHOD called unqualified (`Vector::makei`) | moonbitlang/core `immut/vector/invariants_wbtest.mbt:354,363,366` (and 227,229,230 before) |
| 4 | a struct-literal's FIELD VALUES were not collected | wzzc-dev/moui 0.1.12 `views/text/text_input_apply.mbt:166` |
| 5 | an ASSIGNMENT created a shadowing binding in a nested local `fn` | moonbitlang/async 0.22.4 `src/process/windows.mbt:105` |
| 6 | a `with` CONSTRAINT's right-hand side was read as a pattern binding | moonbitlang/core `builtin/option.mbt:50`, `builtin/result.mbt:92`, `builtin/arrayview.mbt:282,329`, `builtin/help_render.mbt:320` |

**NOT ONE OF THEM IS A 0502 DEFECT.** All six are older holes that reading the
arms EXPOSED: two of them (`as` at a newline, the destructuring initialiser) are
reachable from ordinary code with no `match` anywhere, and the other four are
defects in the collector and the reader that a `match` merely gave a way to
reach.

=> 判据: A FIX THAT MAKES A FINDING APPEAR MUST BE CHECKED AGAINST THE FINDING IT
MAKES APPEAR. Six mechanisms produced six false positives, and each one is now
pinned by a row that says the finding must NOT come back.

### THE ONE TRUE FINDING

    moonbit_labeler 0.2.13   app_moui/rasterizer.mbt:489
      local variable 'd_off' assigned but may not be used

`d_off` is computed at 489 and never read -- the code uses
`blend_pixel(buf, dst_x, dst_y, ..)` instead. It is the first `actionable`
finding this tool has published on `moonbit_labeler`, and it is on the right
side of the ledger: it was invisible while the `match` hole stood.

### WHAT IT BOUGHT

**1,832 match notices gone** across the seven PINNED corpora. That is the
CONTROLLED measurement, and it is the one the number belongs to: those seven
trees did not change between the two scans -- only the ANALYZER did.

    moui              4225 -> 3457    (-768)
    moonbit_labeler    791 ->  698    ( -93)
    moonbit_image      218 ->  186    ( -32)
    async             1836 -> 1654    (-182)
    proton            2131 -> 1799    (-332)
    proton_contract     34 ->   29    (  -5)
    moonbit_core     10228 -> 9808    (-420)
                                   ------
                                    1832

And this repository's OWN source, which is NOT a controlled measurement and is
NOT counted in that 1,832:

    self (own source) 1888 -> 1584    (-304)

The self row is quoted the way the release gate measures it -- each COMMITTED
tree scanned by its own analyzer -- and it is a WEAKER number than the seven
above, for two reasons worth stating rather than hiding. 0502 added four test
files to this repository, and they carry 37 notices of their own (7 + 12 + 12 +
6); on the 174 file paths the two trees SHARE, the count is 1888 -> 1547, a
drop of 341. And this repository's tree carries scratch copies of its own
sources under `_verify/_work_*.mbt`, whose CONTENTS changed along with the
sources they copy, so part of that 341 is the files changing rather than the
analyzer changing. 1888 -> 1584 is the only self number that is not an
interpretation.

The notices that remain are the ones that are still TRUE: a `lexmatch`'s arms,
an `if` expression, a lambda body, and a `match` whose arms hold MoonBit this
frontend cannot model.

**13 `moonbit_core` files went FOUND -> CLEAN**, because a match notice was all
they had:

    decode_js.mbt                    strconv_string_view.mbt    assert.mbt
    bitstring.mbt                    tree_utils.mbt             trig_double_sincos_non_native_or_js.mbt
    parser_globals_merge.mbt         runtime_exit.mbt           tree_slice.mbt
    decode_nonjs.mbt                 arg_action.mbt             symbolize.mbt
    tree_pop.mbt

**5 pre-existing false positives are gone**, on code that was already wrong
before 0502 read anything: three `makei` calls in
`moonbit_core/immut/vector/invariants_wbtest.mbt` (3 -> 0) and two `i1`/`i2`
in `moonbit_core/diff/diff.mbt` (2 -> 0). The `i1`/`i2` case is the same
mechanism as the `windows.mbt` one and the second independent instance of it:
`diff.mbt:494` is a nested local `fn` that reads AND assigns `i1`/`i2`, which
are declared at 489/490.

### THE COMPILER IS THE ORACLE, AND IT SETTLED ONE QUESTION

`as` MAY start a new line. Measured in `_verify/settle_0502_as.ps1`, 6/6: the
canary (a name bound nowhere) is REJECTED, and so is a cast to a trait the type
does not implement -- so the cast really is type-checked, and an ACCEPT is a
fact about the grammar rather than about a parser that stopped complaining.

A local `fn` **captures** the enclosing scope: `moon check` accepts
`fn f() -> Int { let mut x = 0  fn g() -> Unit { x = x + 1 }  g()  x }` with
zero errors. So `x` inside `g` IS the enclosing `x`, and a read there is a read
of the enclosing binding -- which is what makes mechanism 5 a defect in the
COLLECTOR and not in the walk.

### TWO GATES HAD TO BE RE-BASED, AND THAT IS WORTH RECORDING

0502 removed a construct the analyzer used to exclude, and two gates were built
on that construct:

- `_verify/check_frame_audit.ps1` used a `match` as its REGION. A `match` is no
  longer a region, so its five fixtures measured nothing. The region is now an
  **anonymous function literal** -- whose body the frontend reads but does not
  analyse -- and the `if` EXPRESSION fixture is unchanged. The lambda is not an
  arbitrary substitute: 0501's own narrative settled that a MoonBit lambda
  CAPTURES the enclosing locals, so a skipped lambda body CAN hide a read of
  them, and a lambda region must keep silencing the bindings it could have
  read.
- `_verify/check_notice_labels.ps1` used a plain `match` as the program
  frontend's DELIBERATE EXCLUSION. A plain `match` is no longer an exclusion,
  so the fixture measured a construct the tool no longer excludes. The fixture
  is now the FALLBACK -- a match whose arms hold an array spread -- which is
  the exclusion that is left, and the one 0502's own gate pins as "the fallback
  is EXACT".

=> 判据: A GATE BUILT ON A CONSTRUCT THE TOOL HAS SINCE STOPPED EXCLUDING IS A
GATE MEASURING NOTHING, and it fails LOUDLY, which is the good case. The bad
case is the gate that still passes because the construct it used happens to
produce the same numbers for a different reason.

### THE NEW GATES, AND HOW THEY WERE SHOWN TO GO RED

`_verify/check_match_arms.ps1` -- 17 fixtures on the real scanner: the output
contract, the NEGATIVE direction (a binding read only inside an arm body is
not dead), the fallback being exact, the six mechanisms, the same-package method
in its own package directory, and that every fixture was read at all.

`_verify/mutate_0502.ps1` -- 12 mutations, each naming the test that must go
red, each anchored uniquely against the post-`moon fmt` source. **12 of 12
KILLED, every named test confirmed, every restore byte-identical.**

And the stage gate was shown to go red twice, by injecting a defect into the
analyzer's own source, rebuilding, and running it:

- the arm body is not walked -> **12 checks fail**, the negative direction
  included (`live_local`, `live_param`);
- the `with` constraint is not recognised -> **2 checks fail**, naming
  `m6_with_constraint`.

Both trees were restored byte-identically (SHA256 checked), and the gate was
GREEN again after each restore.

### THREE GATES THAT 0502 BROKE, AND WHAT WAS DONE ABOUT EACH

The full release gate is the only thing that finds these, because a gate whose
anchor no longer matches ABORTS rather than passes -- and an aborting gate in
the middle of a 33-minute run is a loud, cheap failure.

**`mutate_0432` -- two patterns absent.** 0432 anchors on the newline-handling
block in `parse_postfix_from`, and 0502 put the `as` continuation INSIDE it --
`as` may start a new line, so the cast continuation is now the second thing
that block can continue on. The chain's `continue` and the block's `self.p =
save` are no longer adjacent, and both anchors stopped matching. The row now
points at the same BEHAVIOUR in the place it now lives, and M1 was made
TARGETED rather than wholesale: it makes the chain's own continuation not fire
instead of deleting the whole block, so the `as` continuation -- which gate
0502 pins separately -- is not collaterally removed.

**`mutate_0469` -- four patterns absent.** 0469 pins the `match` node, and 0502
gave the node its arms: `EMatch(subject)` is `EMatch(subject, arms)` now, in
the parser, in the walk, in the collector and in the type lens. All four rows
were re-anchored onto the current text and each still kills the test it names.

**`mutate_0492` -- M1 SURVIVED.** This is the one that is not a re-anchor, and
it is the most interesting thing 0502 did to the rest of the repository.

0492's M1 reverts the ORDER of two loops in `Infer::run_fn`: the parameters
first, the body bindings after, so a body binding of the same name overwrites
the parameter's annotation. It was a KILL. After 0502 it SURVIVED -- the
mutation applied and the whole suite stayed green.

The obvious reading is "0502 broke the rule". The A/B says otherwise. Putting
the assignment's RE-BINDING back -- the shape 0492 measured, `xs["k"] = "v"`
recorded as a second binding of `xs` -- makes the suite RED on UNMUTATED code,
on three rows, and the harness ABORTS on a red baseline (rule 1). So:

- the RE-BINDING was the only shape that put a name in the binding table
  TWICE, and 0502's fifth fix -- an assignment MUTATES a binding and does not
  CREATE one -- removed it;
- with it gone, the ORDER has nothing to decide, and M1 is unobservable;
- and the re-binding is PINNED, by gate 0502's M11 and by two rows of
  `pipeline_0502b_test.mbt`.

So the order is still in the code and still correct, and nothing measures it
now. The row is declared SURVIVED with that argument rather than quietly
dropped, because a row that used to be a kill and is now a survivor is a
CHANGE IN THE EVIDENCE, and the change deserves a reason a reader can check.

=> 判据: A MUTATION THAT USED TO BE KILLED AND IS NOT ANY MORE IS NOT A GATE
THAT BROKE. It is a change in the CODE, and the question is WHICH change. The
A/B -- put the old shape back, and see what goes red -- is what tells the two
apart, and it is cheap: one mutation, one suite run.

### THE COUNTS

    the corpus pins                 moui / image / async / proton / contract: notices down
                                    labeler: actionable 0 -> 1 (the TRUE finding)
                                    core: actionable 33 -> 28, notices 10228 -> 9808
    the per-function census         core 56 -> 47, labeler 0 -> 1, total 58 -> 50
    this repository's own source    files 174 -> 178, notices 1888 -> 1584, actionable 0
                                    (the four new test files carry 37 of the 1584)
    the suite                       1221/1221 wasm, 1135/1135 js, 1135/1135 wasm-gc
    the mutation gates              82 on disk, 446 live mutations, 408 expect a kill,
                                    331 name the test; 12/12 KILLED
    the match-arms gate             17 fixtures + a package directory, all green;
                                    12 checks red under the arm-body defect
    the three gates 0502 broke      0432 and 0469 re-anchored, 0492's M1 declared
                                    a survivor -- all three GREEN again


### TWO LESSONS, BOTH PAID FOR DURING THIS INCREMENT

**A MUTATION GATE KILLED MID-RUN LEAVES THE MUTATION APPLIED.** The harness proves
every restore byte-for-byte by SHA256 -- and that proof is defeated by killing
the process between the write and the restore. It happened here: the full
release gate was stopped during gate 0418, whose M11 replaces

    if !self.at(TDot) { self.p = save; break }

with `if false { break }`, and the file was left mutated. The evidence was
`moon check --deny-warn` reporting `Unused variable 'save'` at
`src/parser/parser.mbt:3026` -- a warning the mutation creates, pointing at
the exact line the mutation touched.

=> 判据: A GATE THAT IS KILLED HAS NOT RESTORED ANYTHING. The restore is the
last step of the mutation, not a property of the mutation, so an interrupted
gate leaves the tree dirty. LET IT FINISH. And when a gate is stopped anyway,
the check that finds the damage is `moon check`, not `git status` -- the mutated
file is a MODIFIED file, not a new one, and `git status` says nothing about it.

**A NUMBER WRITTEN DOWN TWICE WILL DISAGREE WITH ITSELF.** 0502 moved four
corpus numbers at once -- the core module's `actionable` (33 -> 28), the
per-function census total (58 -> 50), the positive control's file count (24 ->
20), and the core module's parsed count -- and `_verify/check_readme_links.ps1`
PASSED with every one of them stale in the README.

The reason is structural: the gate asked "does the README contain the string
I wrote down", and the strings it had written down were a SECOND COPY of
facts that also lived in `release.ps1`'s pin table. The pin table was
re-pinned from the measurement; the gate's literals were not; and the README
kept publishing numbers that had been true for a release and a half.

The corpus numbers now live in ONE place. `release.ps1` pins the corpus
SUMMARYs, the census total and the control's file count; the README gate
DERIVES its expectations from that table and FAILS LOUDLY if the pins are
gone rather than quietly checking against a default.

=> 判据: A PIN CHECKS THE WRONG DIRECTION WHEN THE FACT IS WRITTEN DOWN TWICE.
0500 made the test count and the mutation counts COMPUTED for exactly this
reason; 0502 found the same defect one level down, in the corpus numbers, and
fixed it the same way.

### WHAT IS NEXT

The `match` is no longer a region, and with it go 1,832 notices across the seven
pinned corpora -- so the next region to read is whatever is left. The backlog
says what that is, and it is now measured rather than remembered:

    expression-level (can suppress a frame audit) : 123
      if expression                                  103
      anonymous function literal                     17
      short lambda                                    2
      try expression                                  1
    declaration-level (cannot)                     1376

An `if` expression is the biggest of them by an order of magnitude, and it is
the same shape a `match` was: a construct the frontend reads but does not
analyse. Reading one is a bigger job than reading a `match`'s arms was -- the
branches are statements, not patterns, so there are no bindings to introduce
and the hard part is the `else` -- and the compiler is the oracle for whether
an `if` in expression position may hold a `let`, exactly as it was for `as`.
## 0503: A RETURN ANNOTATION MAY SAY `raise?` -- AND 0504: A COMPREHENSION'S CONDITION WAS BEING THROWN AWAY

Two increments, and the second one exists because the first one made more code readable.

### 0503: THE `?` MARKER, AND WHICH `?` IS LEGAL

The parser read the `?` marker of a raise clause in the FUNCTION-TYPE position
and not in the RETURN position. The parser's own comment above the first site
names this failure mode in the other direction: *"Reading the clause in one
position but not the other leaves a program that parses as `fn f() -> Int raise`
and then dies on the very next function that takes a callback."* It was fixed on
one side only.

MEASURED, on the pinned corpus, 2026-10-24:

- `-> T raise?` in a RETURN position: **162 sites in 31 files**, ALL of them in
  moonbitlang/core 0.1.20260920+7d59c7ec9. Zero in the other six corpora and
  zero in this analyzer's own source, so fixing it moves ONE corpus row and
  nothing else.
- three real core files carrying it -- `array.mbt`, `option.mbt`, `result.mbt`
  -- scanned ALONE: `PARSED 0/3 files understood (0.0%)`, with the error
  `unexpected token `?``. The analyzer stops at the `?`.
- the COMPILER ACCEPTS `fn f() -> Int raise? { 1 }` (moon check, 0.10.17).

### THE SETTLE CORRECTED ITS OWN PREMISE, AND THE CORRECTION IS THE RULE

The question is not "does the analyzer read `?`" but "**WHICH** `?` is legal",
and the first draft of the settle assumed "after any raise clause" would do.
The compiler says otherwise:

    -> Int raise?              ACCEPTED   the bare raise, marked optional
    -> Int raise MyErr?        REJECTED   4032 + 3002 -- a typed raise has
                                            no optional form
    -> Int raise + nocancel?   REJECTED   3002 "unexpected token `?`"
    -> Int noraise?            REJECTED   an optional marker on "does not
                                            raise" is meaningless
    -> Int nocancel?           REJECTED
    -> Int! ?                  REJECTED   the short form has no optional form

=> 判据: THE `?` BELONGS TO A BARE `raise` AND TO NOTHING ELSE. A reader that
accepted it after ANY clause would read programs the toolchain refuses.

**AND THE FUNCTION-TYPE POSITION DOES TWO JOBS**, which is why the first draft
of the increment narrowed the function-type `?` to "a bare raise only" and
**fourteen existing tests went red**:

    (Int) -> Int raise?      the OPTIONAL-RAISE marker
    ((Int) -> Int)?          the NULLABLE marker on a parenthesised group

The second one has **no clause in front of it at all**, so the rule has to be
asked about the CLAUSE and not about the `?`.

### 0504: THE FALSE POSITIVE THAT 0503's READABILITY EXPOSED

With 27 more core files readable, `hashset/hashset.mbt:382` reported
`undefined variable 'key'`:

    [ for entry in self.entries if entry is Some({ key, .. }) => key ]

The COMPILER ACCEPTS that line -- core is a published package that compiles --
so the finding is a FALSE POSITIVE. And the cause was not in a lens. It was in
the PARSER:

    if self.at_name("if") {
      let _ = self.bump()
      ignore(self.parse_or())          <-- the condition never reaches the AST
    }

`parse_is_pattern` was never the problem -- it does reduce `Some({ key, .. })`
to the binding `key`. The `is` node that carries that binding was built, and
then thrown away with the condition.

### THE CONDITION IS REAL CODE, AND THE COMPILER SAYS SO

`_verify/settle_0504_comp_guard.ps1`, 18 rows -- 16 with `moon check` and 2 with
`moon test`, because `moon check` cannot answer whether a condition is
*evaluated*:

- the condition is COMPILED -- an undefined name inside it is an error;
- the condition FILTERS -- it is evaluated once per element (the runtime rows);
- the `is` binding it introduces is in scope for the BODY, and for nothing else;
- the condition may read the loop variable.

**AND TWO OF THE SETTLE'S OWN ROWS WERE WRONG ON THE FIRST RUN**, and the
corrections are worth more than the rows:

1. the NO-BINDING CONTROL was written with a STRUCT head, `is Pos(_)`, and came
   out REJECTED with error 4199. The rejection had nothing to do with the
   condition: `is` matches CONSTRUCTORS, and a struct TYPE is not one. Probed:
   `is Pos(_)`, `is Pos({ name, .. })` and `is Pos({ name })` are ALL rejected
   with 4199, while `is Some(_)` is accepted. The control now uses `Some(_)`,
   and the measured fact is kept as its own row.
2. `{ key }` is not a BLOCK -- it is a one-field STRUCT LITERAL, the same
   distinction 0468 settled. The row now uses a block with a statement in it.

=> 判据: A SETTLE ROW IS NOT JUST A VERDICT; IT IS A CLAIM ABOUT WHY. The first
row was measuring the type lens and was read as measuring the grammar, and the
parser would have been narrowed to refuse a shape the language HAS.

### THE CONDITION IS CARRIED, AND THE ORDER IS THE SCOPE

`EComp` is now `EComp(vars, sources, cond, body)`. The condition sits between
the iterable and the body because that is where it sits in the source, and
because that order IS the scope: the condition READS the loop variables, and
its own `is` binding must be LIVE when the body is read. Every lens walks the
sources, then the condition, then the body.

**AND THE HALF THAT WAS STILL LATENT WAS FIXED TOO.** The condition's reads
were lost along with it, so a name read ONLY inside a condition would have been
reported as never used. That is the `ECast`/`EComp` lesson in its third form:
**the half that is not walked is the half that vanishes.**

### THE GATE FOUND TWO OF ITS OWN HOLES

`mutate_0504.ps1` has 8 mutations and all 8 are killed -- but two had to be
REWRITTEN after the first run said something the comment did not.

1. "the condition is not parsed at all" came out **COMPILE-ERR** rather than
   killed: with the assignment gone, `cond` is never mutated and MoonBit
   rejects the unnecessary `mut` outright. The compiler catches that regression
   on its own, which is worth knowing, but it made the mutation pin NOTHING
   about the analyzer -- a slot that measures the compiler instead of the rule
   is a slot spent for nothing. The slot now holds a rule the compiler cannot
   catch.
2. "the condition is evaluated in the outer environment" killed a test one step
   removed from its own name. Two undefined names on ONE line are merged into a
   single finding, so the condition's own `nosuchfn` stopped being the message
   that survived the merge -- and what the mutation really broke first is the
   LOOP VARIABLE, which only ever lived in the comprehension's environment. The
   test that pins the MECHANISM was written after that.

=> 判据: A KILL THAT LANDS ON A DIFFERENT TEST IS A QUESTION, NOT A RESULT. The
harness names the test that went red, and reading THAT name is how the scope
turned out to be the loop variable's.

### THE NUMBERS

`moonbitlang/core`, 1029 files, same machine:

| | files | parsed | actionable | per-function census |
|---|---|---|---|---|
| 0.4.34 | 1029 | 957 | 28 | 47 |
| 0.4.35 | 1029 | **984** | **28** | **47** |

Actionable is unchanged at 28, and the census is unchanged at 47 -- and that is
the point of the second increment. The false positive that 0503's extra
readability exposed WAS the 48th core finding; removing it puts the number
back where 0.4.34 had it. The 27 files that became readable contribute notices,
not findings.

### AND ONE PUBLISHED NUMBER THAT NOTHING WAS CHECKING

The README publishes the own-source file count -- "Measured on this project's
own source (178 files)" -- and the release gate MEASURED it and compared it
with nothing, while the README gate compared the README against a literal
`178` written into the gate itself. A literal inside the gate that checks the
README is a number that can only ever agree with itself, and the count moved
twice -- 178 to 179 with 0503's test file, and 179 to 181 with 0504's two --
without anything objecting.

It is a PIN in `release.ps1` now, the release gate compares against it, and the
README gate DERIVES its string from that pin instead of carrying its own.

=> 判据: A PUBLISHED NUMBER THAT IS NOT GATED CAN GO MISSING SILENTLY. This one
had a gate -- it just checked itself.


### AND THE THIRD RUN, AGAINST THE VERSION THAT WAS ACTUALLY PUBLISHED

0.4.35 is out. master and the tag v0.4.35 are on gitee and on github at `f14a6cc`, the
CI runs are green -- `gate` on master, `gate` on v0.4.35 and `publish` on v0.4.35 -- and
the publish job's steps include `moon.mod must agree with the tag`, `Gate`, `Publish to
Mooncakes` and `Create GitHub Release`.

The last of the three runs of the documented order, and the only one that can happen
after the publish:

```
package : riantr/moonbit_static_analysis@0.4.35
moon.mod: 0.4.35

  scanned 163 files under .repos/riantr/moonbit_static_analysis/0.4.35
  ok  the tree scanned is 0.4.35
  ok  parsed 163/163 files
  SUMMARY  files=163 parsed=163 actionable=0 notices=1438 ...
  ok  actionable = 0

GATE OK: the published 0.4.35 scans its own shipped source clean.
```

The tree it read IS 0.4.35 -- the stage refuses to call a scan of a different package a
proof about this one, and that refusal is the check that made the pre-publish abort
DIAGNOSTICABLE instead of merely red. 163 files, 163/163 parsed, **actionable=0**. The
registry served the package mooncakes compiled server-side and `moonx` ran THAT, so the
delivery path is exercised end to end, which no local run can do.

THE TWO PUBLISHED TREES, READ BY THE SAME ANALYZER. The published 0.4.34 tree reads 160
files and 1,397 notices under this analyzer; the published 0.4.35 tree reads 163 files
and 1,438 notices. The tree GREW by three files and the notices ROSE by 41 -- and the 41
are exactly the 41 new test declarations this increment added (24 + 8 + 9), one notice
each. The file delta is those three files and nothing else.

### NEITHER INCREMENT IS EXERCISED BY THE ANALYZER'S OWN SHIPPED SOURCE

This is the measurement that was nearly not made, and it is the one that says what the
two increments are actually WORTH. The published 0.4.34 tree contains **zero**
return-position `raise?` in code and **zero** comprehension guards with an `is` binding.
The published 0.4.35 tree contains 15 `is`-guard occurrences -- 4 in a doc comment and 11
in a string literal -- and not one of them is analysed code. The same is true of the
`raise?` sites: with the rule stated in `_verify/measure_0503_reach.ps1`, both published
trees carry **0** of them in code.

=> The two increments changed NOTHING about how the analyzer reads its own source, which
is exactly why the two published trees read the same notices per file. Their value is
proven where the constructs actually live: the CORPUS. moonbitlang/core carries the
return-position `raise?` in 33 files, and the comprehension guard with an `is` binding is
at `hashset/hashset.mbt:382`.

AND THE FALSE POSITIVE IS GONE, DIRECTLY. The core corpus, scanned with this analyzer:

```
core/hashset/hashset.mbt     FOUND   defects=0   notices=27
"undefined variable 'key'"    0 occurrences in the whole core report
hashset.mbt:382               0 occurrences in the whole core report
```

The file that carried the false positive is now read to its end with no defect, and the
finding is not moved -- it is ABSENT. The core summary is unchanged at `actionable=28`
and the per-function census is unchanged at 47, which is the point of the second
increment: the false positive that 0503's extra readability exposed WAS the 48th core
finding, and removing it puts the number back where 0.4.34 had it.

### THE SAME TREE, READ BY THE OLD ANALYZER AND THE NEW ONE

The published 0.4.34 package IS the old parser, and it can be run against any tree. So
the corpus was scanned twice, by the two PUBLISHED analyzers, over the same 1029 files:

```
0.4.34    PARSED 957/1029 files understood (93.0%);  72 more read only up to their
           first parse error
0.4.35    PARSED 984/1029 files understood (95.6%);  45 more read only up to their
           first parse error
```

And the 27 files that moved, named:

```
array/array.mbt                            builtin/array.mbt
builtin/arrayview.mbt                      builtin/bytes.mbt
builtin/linked_hash_map.mbt                builtin/option.mbt
builtin/readonlyarray.mbt                  builtin/result.mbt
builtin/string.mbt                         builtin/stringview.mbt
hashmap/utils.mbt                          hashset/hashset.mbt
immut/hashmap/HAMT.mbt                     immut/hashset/HAMT.mbt
immut/internal/sparse_array/sparse_array.mbt
immut/sorted_map/map.mbt                   immut/sorted_set/immutable_set.mbt
immut/vector/tree.mbt                      immut/vector/vector.mbt
immut/vector_map/iter.mbt                  immut/vector_map/vector_map.mbt
lazy_list/lazy_list.mbt                    list/list.mbt
prelude/prelude.mbt                        queue/queue.mbt
ref/ref.mbt                                set/linked_hash_set.mbt
```

=> 判据: +27 PARSED IS NOT A NUMBER, IT IS A LIST. "957 -> 984" could have been
twenty-seven files that STOPPED being read, and the summary line cannot tell the two
apart. The list is above, and the list is what says the increment worked on the code it
was supposed to work on.

AND SIX MORE FILES READ STRICTLY FURTHER WITHOUT BECOMING WHOLE. Thirty-three core
files carry a return-position `raise?`. Twenty-seven became whole. The other six --
`builtin/fixedarray.mbt`, `builtin/iterator.mbt`, `builtin/string_methods.mbt`,
`deque/deque.mbt`, `sorted_map/map.mbt`, `sorted_set/set.mbt` -- are still PARTIAL, but
for an UNRELATED reason: `builtin/fixedarray.mbt` is cut at line 778 by a descending
range (`self.length()>..0`), and its two `raise?` sites are at lines 776 and 777, both
of which are now read. The file count moved by 27 and the reach is 33, and the two
numbers differ because "the file is whole" and "the file is read past the thing this
increment fixed" are DIFFERENT CLAIMS.

### AND A PUBLISHED NUMBER THAT COULD NOT BE RE-DERIVED

The 0.4.35 release published "162 return-position sites in 31 files". The figure was
measured by an ad-hoc grep whose RULE WAS NOT RECORDED, and it could not be reproduced:
re-measured on 2026-10-25 with a recorded rule it is **188 sites in 33 files**, and with
a type pattern that admits no comma inside a generic it is 173 in 31. The FILE count
matched and the SITE count did not, which is the worst shape a published figure can have
-- a reader cannot tell which rule produced it, and the number is close enough to look
right.

=> 判据: A NUMBER WITHOUT A RULE IS NOT A NUMBER, IT IS A REMARK. The rule now lives
in `_verify/measure_0503_reach.ps1` -- the corpus, the `.mbt` scope, the paren-depth
definition of the RETURN position, the code-only requirement, the type pattern -- and the
figure is PINNED in `release.ps1` and checked on every release gate, with a control
fixture whose answer is known by construction. The published reach is **188 sites in 33
files**, and **0** in the other six corpora and **0** in this analyzer's own source.

### THIS RELEASE

0.4.35. The version was bumped only after the local gate was green, and the README was
updated before the tag, so the registry never saw a README that described a different
tree than the one it was serving. The mutation gates are 84 now: 464 live mutations, 425
expecting a kill, and 348 naming the test that must go red.


### WHAT IS NEXT

The backlog, measured rather than remembered, on this project's own source (181 files,
1,625 notices, 0 actionable):

```
expression-level (can suppress a frame audit) : 123
  if expression                                  103
  anonymous function literal                     17
  short lambda                                    2
  try expression                                  1
declaration-level (cannot)                     1502
```

The EXPRESSION-LEVEL half is UNCHANGED by 0503 and 0504 -- 123 before, 123 now, with `if`
still 103 of them -- so the next region to read is still the `if` expression, and the
increment that removes an expression-level exclusion is still the same one. The
DECLARATION-LEVEL half went 1,376 -> 1,502, and that is not a regression: 0503 and 0504
made 27 more core files readable, and a file that becomes readable contributes the
declarations the analyzer now SEES and declines to analyse. A blind spot that is
REPORTED costs less than a blind spot that is invisible, and that is the direction the
number moved.

AND ONE GAP WAS MEASURED, AND ITS REACH IS ZERO. The parser rejects a tuple pattern in a
`for` header: `for (k, child) in m` is read as `expected loop variable` and the file is
not parsed at all. The UNPARENTHESISED form the corpus actually uses -- `for key, _ in
obj` -- is read fine: 296 code sites across the seven pinned corpora (core 174, moui 65,
async 32, proton 23, labeler 2) and 50 in this analyzer's own source, and a fixture of it
scans CLEAN at 1/1 parsed. The parenthesised form has ONE occurrence in the seven pinned
corpora and it is inside a COMMENT (`json_traverse_test.mbt:36`), and none in code.

=> 判据: A GAP IS NOT AN INCREMENT UNTIL IT IS MEASURED. The parser gap is real, the
reach is zero, and a reach of zero is what a "next increment" looks like when it is
chosen by taste instead of by measurement. 0503 is the other half of the same rule: a
gap with no reach in the OTHER SIX corpora was still worth doing, because the reach was
measured on the corpus that HAS the construct -- 188 sites in 33 files -- and not on the
six that do not.

## 0505: A PORTING PLAN -- THREE THINGS FROM `bandit`, IN AN ORDER, AND EVERY PREMISE MEASURED FIRST

### WHAT THIS IS, AND WHAT IT IS NOT

A PLAN. It changes no source file, no published number, and no behaviour. The tree the
registry is serving for 0.4.35 is untouched by this section, and this section does not
pretend to change it. What it does is decide what gets built next on the FINDING-QUALITY
track, in what order, and against what evidence -- and it puts that decision behind a gate
that re-measures every premise, so the decision cannot quietly become wrong.

The source of the three things is PyCQA's `bandit`, read at commit `c4bfccf`
(`setup.cfg` says `author = PyCQA`). `bandit` is a SECURITY linter for PYTHON. This
analyzer is a CORRECTNESS analyzer for MOONBIT. So the question is never "what can we
copy" -- it is "which of bandit's ARCHITECTURE answers a problem this analyzer actually
has, MEASURED, and which of its answers are about Python or about security and are
therefore not ours to take". The second half of that answer is longer than the first.

### THE THREE TRANSFERS, AND WHY THE ORDER IS FORCED

1. **A PER-FINDING CONFIDENCE AXIS.** `bandit` carries `severity` AND `confidence` on
   every issue (`bandit/core/issue.py:79-106`), and `Issue.filter` needs BOTH to clear
   their thresholds (`issue.py:147-167`); the axes are genuinely independent, and an
   uncertain finding is reported at LOW confidence rather than dropped.
2. **STABLE FAMILY IDS, AND A PROFILE THAT IS CHECKED.** `bandit` keys its plugins by
   `_test_id`, and a plugin with no id is SKIPPED WITH A WARNING
   (`bandit/core/extension_loader.py:44-57`); `validate_profile` warns on an unknown id
   and RAISES on a non-exclusive include/exclude intersection
   (`extension_loader.py:86-100`).
3. **`nosec`.** `bandit` suppresses per line and per test id (`# nosec B101`) or blanket,
   and WARNS WHEN A `nosec` MATCHED NOTHING (`bandit/core/tester.py:105-118`).

The order is not a preference, and it is not "confidence first because it sounds
important":

* **3 depends on 2.** A `nosec` comment has to NAME what it suppresses. If it named a
  family by its current NAME, then transfer 2 -- whose entire point is that the name is
  not stable -- would break every suppression written the day before. The stable id is
  what a suppression must quote, so the id has to exist first.
* **2 depends on 1** in the sense that a profile is a statement about which findings a
  user trusts, and "trusts" is a confidence question before it is a membership question.
* **1 comes first** because it is the one that makes the other two ADDRESSABLE, and
  because it answers a defect this analyzer has TODAY -- one that the other two cannot
  reach at all while it is unfixed.

### FIRST: THE CONFIDENCE AXIS -- AND THE FALSE NEGATIVE THAT MOTIVATES IT

`bandit`'s confidence axis exists because a security tool has to be able to say "I think
this is a problem, but I am not certain". This analyzer has `Family::severity()`
(`src/core/core.mbt:524-530`) and no second axis at all: the machine-readable finding
record (`src/jsoncli/main.mbt:12-20`) is `line, col, severity, message, family, lenses,
vst` -- a `severity` field and NO `confidence` field. Row B4 of the settle pins that.

The reason a second axis is not a nicety here is a defect the analyzer has today, and
the defect is not a false alarm. It is a SILENCE.

#### THE MEASUREMENT

One defect -- a call with the wrong number of arguments -- under six conditions. All six
are rows of `_verify/settle_0505_finding_quality.ps1`, and every one of them is
re-measured on every run:

| row | the callee is declared | the call | what the analyzer says |
|-----|----------------------|----------|--------------------------|
| A0 | nowhere, no interface dir | 2 arguments | `no visible binding for 'Command'` (UndefinedName) |
| A1 | a `.mbti`, right arity | 1 argument | nothing, file printed CLEAN |
| A2 | a `.mbti`, WRONG arity | 2 arguments | **nothing, file printed CLEAN** |
| A3 | the SAME FILE | 2 arguments | `too many arguments to 'Command': expected 1, got 2` (ArgTypeMismatch) |
| A4 | nowhere at all | 1 argument | `no visible binding for 'nosuchfn'` (UndefinedName) |
| A5 | a SIBLING `.mbt` file | 2 arguments | **nothing, file printed CLEAN** |

Read A3 against A2: the SAME defect, in the SAME file, in the same scan, is reported in
one row and swallowed in the other. The only difference is whether the parameter list was
in the file the analyzer was reading. And read A5 against A2: the boundary is not the
package and not the interface file -- it is THE FILE. A callee declared one file over, in
a real `.mbt` with a real parameter list, is known by NAME only, and the arity check is
skipped for it exactly as it is for an interface declaration.

The mechanism is documented in the analyzer's own source: a `.mbti` gives the name and
never the parameter list, so the name is typed `TUnknownFn`
(`src/types/types.mbt:31-37`), and the arity and argument checks are deliberately not
run on it (`src/types/infer.mbt:83-113,300-312`). That is SOUND -- the analyzer invents
nothing -- and it is exactly the problem: it is sound, and it is SILENT, and "I could
not check this" and "there is no problem here" are the same output. A file whose only
defect is a wrong-arity call is printed `CLEAN`.

#### THE REACH

The measured reach, under a rule that is written down in the settle and defended by a
control fixture whose answer is known by construction:

```
    0505 the corpus reach, package-level calls   : 19843
    0505 the corpus reach, unchecked calls        : 16250
    0505 the corpus reach, files carrying them    : 657
    0505 the corpus reach, unchecked share        : 81.9
    0505 the interface population, files          : 159
    0505 the interface population, `pub fn`       : 2116
```

That is the pinned `moonbitlang/core 0.1.20260920+7d59c7ec9`, and the rule is: a
package-level call is a call to a name declared by a top-level `fn` in some `.mbt` file
of the corpus or by a `pub fn` in some `.mbti` of it; it is CHECKED when the calling
file itself declares that name, and UNCHECKED otherwise; declarations are not calls, and
comments and string and character literals are not code. **81.9% of the package-level
calls in the pinned corpus have their arity and argument types unchecked**, across 657
files. The 159 `.mbti` files carry 2,116 `pub fn` declarations, and every one of them
reaches the analyzer as a name and nothing else.

**AND THE LAST CLAUSE WAS WRONG, AND IT WAS WRONG ABOUT THE ANALYZER, NOT ABOUT THE
FORMAT.** "Reaches the analyzer as a name and nothing else" is true of the SYMBOL
TABLE and false of the `.mbti`: the parser reads the parameter list out of every one
of those declarations and the table is what drops it. The premise this section rests
on -- "a `.mbti` gives a name and never its parameter list" -- is therefore a
statement about WHERE THE INFORMATION IS DROPPED, not about what the format
carries, and the difference is the difference between "the information is not there"
and "we drop it". Measured 2026-10-28; the correction and the numbers are in the
0508 section below, and the instrument that produced them is
`_verify/measure_0508_unchecked.ps1`.

A number written down here is a number the settle re-derives, and a number the settle
re-derives is a number the narrative has to agree with: row D1 of the settle reads these
eight lines back out of THIS FILE and fails the gate if any of them disagrees with what
was just measured.

#### WHAT THE TRANSFER IS

Not "add a second severity". The axis this analyzer needs is a statement about how much
was actually CHECKED, and it has to be able to say it about a finding that is NOT there:

* every finding carries a confidence beside its severity -- `high` when the lens had the
  signature in front of it, `low` when the lens was reasoning from a name alone, and a
  third value for "this lens could not decide at all";
* and the silence stops being silent: the analyzer says how much of the tree it could
  check, per finding, instead of rounding "I did not check" down to "nothing to report".

`bandit` has the second half too, in a different shape: its `unreliable`/`withheld`
counts are FILE-granular -- everything from the first read failure on
(`src/sa/main.mbt:98-104`) -- and a finding inside that region is counted, never shown.
That is the right idea and the wrong granularity: a per-finding confidence makes the
region unnecessary for the cases it is aimed at.

=> 判据: A SOUND CHECK THAT IS SILENT IS A FALSE NEGATIVE WITH A GOOD MANNER. The
analyzer declined to check the arity of a call it could not see the signature of, and
the decline cost nothing in correctness and everything in truthfulness: the file was
printed CLEAN. The house rule that a false positive is FIXED, not catalogued, has a
mirror here, and the mirror is this -- a false NEGATIVE is not catalogued either, it is
given a confidence and reported.

### SECOND: STABLE FAMILY IDS, AND A PROFILE THAT IS CHECKED

The public vocabulary of a finding is its family, and the family is spelled with a NAME.
`Family` is a closed twelve-member enum (`src/core/core.mbt:529-542`) and its public
spelling is a hand-written `match` (`core.mbt:545-560`). The names and the enum tags are
not the same thing:

```
    0505 the family roster, families              : 12
    0505 the family roster, names that differ     : 5

AND WHEN THE ROSTER MOVES, THESE TWO NUMBERS MOVE WITH IT, and the fix is to RE-READ
this section, not to loosen the pin. A taxonomy that grew is a premise that has to be
re-examined, and the settle is what makes that happen at a RELEASE rather than at a
reading. The four corpus numbers move only when the corpus pin moves, which is the same
coupling the 0503 reach figure has always had.
```

Five of the twelve public names are not the tag with its `F` removed: `FParse` ->
`ParseError`, `FAssignType` -> `AssignTypeMismatch`, `FArgType` -> `ArgTypeMismatch`,
`FOpMismatch` -> `OperatorMismatch`, `FCondBool` -> `NonBooleanCond`. So the name is a
second, hand-maintained vocabulary that has to be kept in step with the first, and
nothing enforces that. Renaming a family changes the JSON output silently, and a
consumer that pins `"family": "ArgTypeMismatch"` in a suppression or a CI filter gets no
warning at all -- the analyzer does not know that anyone ever depended on the spelling.

The transfer, in bandit's shape and in this project's own discipline:

* every family gets a STABLE ID -- allocated, never renumbered, and quoted by anything
  that needs to refer to a family across versions;
* a PROFILE selects families by ID, and the profile is VALIDATED the way bandit
  validates its own (`extension_loader.py:86-100`): an unknown ID is a WARNING, and an
  include/exclude intersection is an ERROR, not a silent precedence rule;
* and the roster discipline this project already has for its gates is reused for its
  families -- `_verify/check_gate_roster.ps1` already refuses a gate that is not on the
  roster, and the family roster refuses a family with no ID.

The house precedent for "a thing that is written down must be checked" is already in
this repository, in two places: the gate roster, and `src/report/report.mbt:69-71`, where
`is_notice` is decided by the MESSAGE TEXT rather than by the family -- a predicate that
is right today and that says nothing about which family produced the text.

### THIRD: `nosec` -- AND THE PHILOSOPHY DECISION THAT GATES IT

`bandit`'s `nosec` is a comment on the line: `# nosec B101` suppresses one test id on
that line, a bare `# nosec` suppresses everything there
(`bandit/core/tester.py:56-58,79-94`), and -- the part that is worth taking -- a `nosec`
that MATCHED NOTHING is a WARNING (`tester.py:105-118`). A suppression that has gone
stale is itself a finding, because the code it used to silence has changed.

This analyzer has no user-facing suppression at all. What it has is the analyzer's own
region suppression, per binding since 0501 (`src/walk/walk.mbt:286-288`), and the
`extern_iface` name suppression -- both properties of the analyzer, not choices a user
makes. Row C3 of the settle pins the state: a defect on a line carrying `// nosec` is
still reported. Row C1 pins the other half: the scanner takes no config file and no
family selection, and an unknown flag is REFUSED (`ERROR unexpected extra argument`)
rather than ignored.

**AND THIS TRANSFER IS GATED ON A PHILOSOPHY DECISION THAT IS NOT MEASURED, AND THAT IS
WHY IT IS THIRD.** This project's standing rule is that a false positive is FIXED, not
catalogued -- 0504 is the precedent: the `undefined variable 'key'` on a comprehension
guard was a defect in the PARSER, and it was fixed, not suppressed. `nosec` assumes the
opposite: that the analyzer may be wrong, and that the user is entitled to say so. Both
positions are defensible; they cannot both be the policy. The decision is not made in
this section, and the part of the transfer that is NOT a philosophy question -- the
STALE-SUPPRESSION WARNING, which is the same discipline as the gate roster, applied to a
comment -- is available independently of it.

### WHAT NOT TO TAKE FROM `bandit`

The longer half of the answer, and the half that saves the work:

* **bandit's CHECKS.** `assert_used`, `hardcoded_password_string`, `shell_injection` are
  security checks for a security tool. Eight of this analyzer's eleven families are
  CORRECTNESS findings, and a correctness analyzer with a CWE column would be a costume.
  Only `src/statecheck` has an honest use for a standard vocabulary, and it has its own.
* **Python's `ast`.** Not portable, and not needed: this analyzer has a MoonBit
  frontend and a real AST (`src/ast/ast.mbt`).
* **bandit's HAND-WRITTEN BLACKLIST** (`bandit/blacklists/calls.py`, 30 KB;
  `imports.py`, 17.7 KB). This analyzer has the same need and the opposite solution: the
  ambient table is GENERATED from the toolchain's own `pkg.generated.mbti`
  (`src/core/builtins.mbt:18-29,49-58`), and because it is generated it can only ever
  cost a missed report, never invent a false alarm. A hand-written list would be 30 KB
  of things somebody has to remember to update.
* **bandit's GOLDEN COUNTS OF ITS OWN SCANNER** (`tests/functional/test_functional.py:19-24`).
  This project uses the COMPILER as the oracle -- `moon check` accepts or rejects -- and
  a count of its own scanner's output is a pin on the analyser, not on the language.
* **bandit's BLACKLIST-AS-DATA PATTERN** (`bandit/core/blacklisting.py`) is the one
  structural idea worth stealing, and it is stolen in transfer 2 as the family roster,
  where the "data" is the ID table rather than a list of qualnames.

### AND THE TRACK THIS IS NOT

The repo's own next increment is still the `if` EXPRESSION: 103 of the 123
expression-level exclusions (`_verify/backlog.ps1`), unchanged by 0503 and 0504. That is
a COVERAGE track -- read more of the language. This is a FINDING-QUALITY track -- say
more about what was found. They are not alternatives and neither replaces the other, and
the rule for how they meet is:

* reading an `if` expression ADDS findings, because more code becomes analysed, so
  transfer 1 gets MORE valuable as the coverage track succeeds, not less;
* the family IDs are ALLOCATED, NEVER RENUMBERED, so a family added by the `if` increment
  takes the next free number and every existing ID keeps meaning what it meant;
* and transfer 1 is measured on the corpus, so a coverage increment that makes more files
  readable MOVES the reach numbers in this section -- which is exactly what the settle's
  pins and row D1 are for.

### THE SETTLE

`_verify/settle_0505_finding_quality.ps1`, sixteen rows, no compiler oracle needed
because nothing here is a question about the LANGUAGE -- every row is a question about
what the analyzer DOES, and the answer is read back from the analyzer itself:

* A0..A5 -- the six conditions of the false negative, each with a control;
* A6 -- the corpus reach, with a control fixture whose answer is known by construction
  and a counter that has to agree with it before any real number is reported;
* B1, B2 -- the family roster: one distinct name per family, and the number of names
  that are not the tag with its `F` removed;
* B3, B4 -- the output surface: the rendered finding carries the NAME and no id and no
  confidence token, and the JSON `Finding` record has `severity` and no `confidence`;
* C1, C2, C3 -- no config file, no family selection, no user-facing suppression, and
  an unknown flag refused rather than ignored;
* D1 -- this section's eight numbers, read back out of THIS FILE and checked against
  the measurement.

**AND 0507 INVERTED FIVE OF THOSE ROWS, IN PLACE.** B3 and B4 now assert that the
rendered finding carries the id and the confidence and that the JSON record carries
`confidence` and `family_id`; C1 now asserts that the real spelling `--families` is
accepted AND that an unknown flag is still refused; C3 now asserts that a `// nosec`
suppresses nothing BY DEFAULT, and a new row C4 asserts that it DOES suppress with
`--honor-nosec`. The row count is still sixteen and the D1 row is unchanged except
for the roster, which moved from 11 to 12 because the stale-suppression finding is a
family of its own.

A settle that keeps asserting the absence of a thing that now exists is a settle that
has stopped measuring, so the rows moved with the state -- RE-PINNED, never loosened.
The numbers this section quotes are the numbers the settle re-derives, and that
coupling is the whole point of having a settle at all.

AND THERE IS NO MUTATION GATE FOR THIS INCREMENT, and that is a fact about WHAT THIS
INCREMENT IS rather than an omission. A mutation gate mutates SOURCE and proves that a
test goes red; this increment changes no source, so there is nothing to mutate and a
gate would be a ceremony. What stands in its place is the settle's own CONTROLS: A0, A1,
A3, A4, A5 and A6ctl are all cases where the settle FAILS if the analyzer's behaviour
changes, or if the counter's rule stops counting what it claims to count. And they have
already shown themselves -- A6ctl caught the counter counting a DECLARATION as a call,
and the corpus numbers moved because of it.

The control for A6 earned its place immediately: the first version of the counter
counted a FUNCTION DECLARATION as a call, because `fn same_file(` ends in an opening
parenthesis exactly as a call does. The control fixture caught it, the corpus numbers
moved from 21,541/16,409 to 19,843/16,250, and the pins were corrected in the same
commit. A counter that has never been shown to disagree is a counter that cannot say
anything.

=> 判据: A PLAN IS AN INCREMENT ONLY IF ITS PREMISES ARE MEASURED. 0503 shipped a
parser fix and 0504 shipped another, and both had a reach measured before they were
built. This one ships no code at all, and it is held to the same standard: the false
negative is reproduced under six conditions, the reach is measured under a recorded rule
with a control, and the numbers this section quotes are the numbers the settle
re-derives.

### WHAT IS NEXT

Not the next increment -- the next increment is still the `if` expression, and it is
measured rather than remembered. This section fixes the ORDER of the finding-quality
work and nothing else, and the order is: the confidence axis, then the family ids and
the profile, then `nosec` -- and the third one waits on a decision about policy that has
not been made.

And the first thing transfer 1 has to settle, before it settles anything else, is a
question this section has NOT answered: **what does the analyzer do about a call it
cannot check?** Silence, a low-confidence finding, or a separate "unchecked" count are
three different products, with three different costs, and they disagree about what a
`CLEAN` file means. The measurement says the problem is large -- 81.9% of the
package-level calls in the pinned corpus. It does not say which of the three answers to
build, and writing that down here would be exactly the kind of number-without-a-rule
this project keeps correcting.

**0507 ANSWERED IT, AND IT ANSWERED IT WITH THE THIRD ONE.** The separate "unchecked"
count, disclosed on the file's own verdict line and on the SUMMARY, and NOT part of the
finding count -- and the two remaining questions the plan left open (`nosec` honoured
by default or not, and the policy behind it) were answered by NOT deciding them: the
suppression is off unless it is asked for. See the 0507 section.

## 0506: THE NOTICE FLOOD -- AND WHICH NOTICE DESERVES A LINE IS A POSITION, NOT A WORDING

THE COMPLAINT WAS ABOUT VOLUME, and it was right. MEASURED on the pinned core corpus
(`moonbitlang/core` 0.1.20260920+7d59c7ec9, 1029 files), with the default per-file
printing cap and nothing else changed:

    before    9128 lines of output, 7971 of them rendered notices, 28 findings
    after     2279 lines of output, 1133 of them rendered notices, 28 findings

The output-line counts are the lines that CARRY TEXT. The renderer puts a blank
line after each finding, so `wc -l` counts the same two outputs as 17,128 and
3,441, and with the per-file cap lifted -- every one of the 10,096 notices on a
line of its own -- as 11,223.

**AND THE LINE COUNT WAS ALSO QUOTED WRONG, IN A SENTENCE RATHER THAN IN A
MEASUREMENT.** Four source files and a gate script said "on the pinned core corpus
that was 10,096 notices and 17,128 lines of output to say 28 things". 17,128 is a
REAL number, and it belongs to the OLD rendering -- as `wc -l` counts it, because the
renderer puts a blank line after each finding. The lines that carry text are 9,128,
and the rendering in which every one of the 10,096 notices is on a line of its own is
11,223 (21,348 with the blanks). So ONE output was counted two ways in two
documents, and the sentence attached the wrong one to the wrong rendering. The
correction states the convention wherever a count is quoted; no count changes.

=> 判据: A NUMBER QUOTED WITHOUT ITS CONVENTION IS A NUMBER THAT CANNOT BE
RE-DERIVED. The same output was 9,128 lines and 17,128 lines, and BOTH were true,
and a reader counting the real output had no way to tell which was which. The
convention is now stated wherever the count is quoted -- the lines that carry text
-- and the `wc -l` count is quoted with it.

The 28 findings are the SAME 28. The flood was 7,971 lines of output to say 28 things,
and 66.5% of the corpus's 10,096 notices -- 6,148 `test declaration` notices and 566
`block starts with 'test'` notices -- were about the project's own test suite.

**THE NUMBER OF NOTICES DID NOT MOVE, and that is the point of the increment.** The
SUMMARY still says `notices=10096`. The seven corpus pins are byte-identical.
`actionable=28` is unchanged. What moved is how many of the notices earn a line of the
reader's screen.

### THE RULE IS A POSITION, NOT A WORDING

A notice is worth a line only when it can HIDE a finding -- that is, only when its
region lies inside some function's extent, which is the geometry `@walk.holes_in`
already used to decide which regions are in a function's hole list. A region outside
every function's extent is in no function's list at all, so it hides nothing.

**THE SHARP CONTROL IS THE SAME MESSAGE IN BOTH POSITIONS.** MEASURED, with the
toolchain as the oracle:

    fn g() -> Int { let d = if true { 1 } else { 2 } d }   -- inside a function
    let d = if true { 1 } else { 2 }                        -- module top level

Both render the SAME notice -- "if expression is outside the analyzed subset" -- and the
first can hide a finding while the second cannot, because the second is in no
function's hole list. A rule keyed on the wording would answer both the same way, and
it would be wrong about one of them. So the classification is the analyzer's OWN
EXTENTS, carried from the walk (`@walk.span_in_extent`, `@walk.hiding_spans`) to the
renderer (`@sa.is_hiding`, `@sa.split_findings`), and the region membership test
compares the SPAN exactly: two exclusions on the same line are two different regions.

### THE OLD PROXIES WERE WRONG IN BOTH DIRECTIONS

Two scripts used to work the split out for themselves, from a list of message shapes:
`_verify/backlog.ps1` (five shapes: `match expression`, `if expression`, `try
expression`, `short lambda`, `anonymous function literal`) and `_verify/release.ps1`
("a kind whose name ends in ` declaration` is declaration-level"). On the core corpus
the proxies put 1,023 notices in the expression-level class and 9,073 in the other.
THE GEOMETRY puts 1,144 and 8,952, and it is right in BOTH directions:

  * **132 notices the proxies did not name** -- `loop expression` (95), `lexmatch
    expression` (8), `descending range direction` (19), `inclusive range end` (10).
    Every one of them is an EXPRESSION, so every one of them sits inside a function and
    can hide a finding. The proxies' lists simply did not mention them.
  * **11 notices the proxies called expression-level and the geometry calls
    hiding-nothing** -- 10 `short lambda` and 1 `anonymous function literal` at MODULE
    TOP LEVEL. They are expressions, but they are not inside any function, so they are
    in no function's hole list.

So the geometry is not a refinement of the proxies. It answers a different question, and
it answers it from the analyzer's own extents. Both scripts now READ the analyzer's
split instead of guessing at it: `release.ps1` reads the `NOTICES` table's TOTAL line,
and `backlog.ps1` reads the same line and builds its per-message breakdown from BOTH
halves -- the table's rows carry the notices that hide nothing, and the rendered notice
lines carry the ones that are printed.

### WHAT THE OUTPUT LOOKS LIKE NOW

The notices that hide nothing are counted BY SHAPE, once for the whole tree, at the end
of the scan:

```
NOTICES	TOTAL	notices=10096	printed=1144	aggregated=8952	1144 of them can hide a finding; the other 8952 cannot, and are counted by shape below
NOTICES	count=6148	test declaration is outside the analyzed subset; its body was not analyzed
```

`--show-notices` restores the whole per-line list -- the OLD rendering, exactly -- and
it changes no count. The flag is what every measurement that reads the complete list
needs, and it is what a reader looking for a specific construct wants.

**THE `printed` COUNT IS THE CLASSIFICATION AND NOT A PROMISE THAT EVERY ONE OF THOSE
LINES REACHED THE SCREEN.** The per-file printing cap still applies to them, and on
the core corpus it hides 11 of the 1,144 (one file, one `... 11 more in this file`
line). The first draft of the TOTAL line said "1144 of them ... are printed per line",
which is FALSE in the default mode, and it was corrected in place before this section
was written.

### THE RECONCILIATION

Three numbers, from three different computations, and they must agree:

    notices  == printed + aggregated == the SUMMARY's `notices`
    the rendered `ParseError` lines == printed
    the table's rows add up to `aggregated`

The last of those is the PROOF that no `ParseError`-family DEFECT exists in the tree.
A defect of that family renders `error:` and is matched by the `(ParseError)` matcher
too, so "the rendered ParseError lines are exactly the printed notices" says that every
`ParseError` in the tree is a scope limit -- which is the claim 0.4.35's label fix made
about a rendering that no longer exists.

### THE PINS THAT MOVED, AND THE ONES THAT DID NOT

The seven corpus SUMMARYs did not move at all: `notices=3457`, `698`, `186`, `1654`,
`1799`, `29`, `10096`. The `$PARSERR_TOTAL` pin did not move either -- 19,544 became
**19,569**, and the +25 is this increment's own source: 24 `test declaration` notices
from the two new test files and 1 `anonymous function literal` from `count_by_shape`'s
sort. What DID change is the MEASUREMENT that produces it: the rendered `ParseError`
lines are no longer the notice count, so the pin is read from the `NOTICES` table's
TOTAL line now, and it is a different number for the same trees.

The own-source pins moved with the source:

    $SELF_FILES        181 -> 183     the two new test files
    $SELF_NOTICES      test declaration 1359 -> 1383, if expression 103, anonymous
                       function literal 17 -> 18, the rest unchanged
    $SELF_PRINTED      (was $SELF_EXPR)  123 -> 124
    $SELF_AGGREGATED   (was $SELF_DECL) 1502 -> 1526

The +24 in the aggregated class is the 24 top-level `test` blocks of the two new test
files: they are outside every function's extent, so they hide nothing. The +1 in the
printed class is the anonymous function literal this increment's own sort adds. The
class names changed because the old names described a PROXY and the new ones describe
what the analyzer does.

### THE GATE

`_verify/settle_0506_notice_flood.ps1`, 10 rows, GATE OK: the `if` inside a function is
printed; a top-level `test` block is aggregated; **the SAME `if expression` message at
module top level is aggregated** (the sharp control); both in ONE file are told apart;
`--show-notices` prints both; the SUMMARY says the same in both modes; the aggregate
reconciles; the default prints fewer notice lines; the pinned corpus is 10,096 / 1,144
/ 8,952; the corpus SUMMARY is the same in both modes.

`_verify/mutate_0506.ps1`, 16 mutations: **15 killed with their named test confirmed**,
and ONE declared survivor with its argument attached -- the root package has no test
file, so `moon test` cannot observe the CLI's plumbing at all, and the rule is pinned by
the settle's row N5 instead. Every restore was verified byte-identical by SHA256.

`src/walk/walk_0506_test.mbt` is the FIRST test file in the `walk` package, and
`src/sa/sa_0506_test.mbt` carries the split. The suite is 1286 on wasm and 1184 on js
and wasm-gc -- the 102-test difference is the async packages, which do not run on js.

**FOUR THINGS THE GATE CAUGHT, ALL OF THEM IN THIS INCREMENT.**

  * **The settle measured a different corpus from the release gate.** It scanned
    without `--extern-iface-dir`, so its corpus numbers were `files=1018 actionable=27`
    while the gate's were `files=1029 actionable=28` -- two numbers written down twice
    that disagreed with each other, because they were two measurements. The settle now
    uses the gate's invocation, and its `WANT_CORE_FILES` pin -- which was DEAD, an
    unused variable that nothing asserted -- is now asserted, because a pin nobody
    checks is a number nobody keeps.
  * **The README gate found the stale published counts.** 85 mutation gates (not 84),
    480 live mutations (not 464), 440 expecting a kill (not 425), 363 naming the test
    (not 348), and the test counts 1286/1286 and 1184/1184. That is the gate doing its
    job: a number that is only written down cannot be wrong loudly.
  * **The roster gate found the new mutation gate missing from `release.ps1`.** A gate
    on disk but not in the list is a gate that does not run, and it looks exactly like
    a gate that passes.
  * **THE FIRST PROBE OF THE PARSER GAP BELOW REPORTED THE WRONG THING.** It printed
    CLEAN for four fixtures, three of which do not read. The reason: the scanner runs
    `moon info` in the target, which GENERATED a `pkg.generated.mbti` into the fixture
    directory, and the probe's `CLEAN` regex matched THAT file's line and not the
    fixture's. The probe was reading a different file's verdict. A probe that matches
    a line without checking WHICH file it belongs to is a probe that will lie, and it
    lied here.

### THE GAP THIS INCREMENT FOUND, AND DID NOT FIX

`moon fmt` splits a long `for` header across lines -- `for` alone on one line, the
iterator clause on the next -- and **the frontend does not read that shape.** The parser
bumps `for` and asks for the loop variable at once (`expect_name("loop variable")`), so
the newline in between is the wrong token.

MEASURED, with the toolchain as the oracle:

    moon check       ACCEPTS   for\n  x in xs {
    this analyzer    PARTIAL   "expected loop variable"

**THIS IS NOT 0482's SETTLED REJECTION.** 0482 settled the C-STYLE head on the line
after the `for` -- `for` / `i = 0;` / ... -- and the toolchain REJECTS that shape, so
the analyzer's rejection there is correct and deliberate. The shape here is the
MOONBIT-STYLE binder head, `for` / `x in xs {`, and the toolchain accepts it.

It was found by the increment itself: the first draft of the table-printing loop in
`src/sa/main.mbt` had that shape, and the self-scan went to `files=183 parsed=182`
with the boundary on the `for` line. The code was rewritten to bind the table first so
that the header stays on one line, and the gap is NOT fixed here: it is a parser
increment of its own, with its own settle, its own tests and its own mutation gate. It
is written up here so that the next increment does not have to rediscover it.

### WHAT IS NOT IN THIS INCREMENT

The `test`-block exclusion STAYS. 66.5% of the corpus's notices are about test code,
and 0506 counts them instead of printing them -- it does not ANALYSE them. Reading
test bodies is a separate coverage increment.

The shape of the aggregate is the whole message, and the README's table is the
construct name it begins with. A message this repository has no name for FAILS the
release gate rather than vanishing from the published table.

And `nosec` stays third and gated on a policy decision (0505): a false positive is
FIXED here, 0504's precedent, rather than suppressed on the assumption that the user may
be right.

### AND THE HARNESS MISREPORTED A BUSY HOST AS A COMPILE ERROR

The 0506 release gate failed on gate 0466, and the mutation was NOT the reason.
`moon test` printed the COMPILER'S OWN WARNING and exited 1 with no test summary:

    moon.exe : Warning: [0002]
      Warning (unused_value): Unused variable 'n'

The harness had no summary line, so it recorded COMPILE-ERR and blamed the mutant --
and the mutant is a DECLARED SURVIVOR, so the gate failed. MEASURED on the same tree:

    the same mutation, run standalone        SURVIVED, 1184/1184 still green
    `moon test` on the mutated tree, REBUILT  exit 0, and the summary IS printed
    a genuine compiler rejection             moon prints `Error: [0011]`

The third line is the discriminator, and it is the same one the compiler gives: a
compiler that rejects a mutant ALWAYS says why. The failure had nothing to do with
the mutation -- another session's test binary was running on the same machine, and a
starved build wears the same shape as a rejected one.

**SO THE HARNESS NOW SAYS FOUR THINGS, NOT THREE.**

    a summary line + a non-zero exit          -> KILLED
    a summary line + a zero exit              -> SURVIVED
    a COMPILER DIAGNOSTIC (`Error: [NNNN]`)   -> COMPILE-ERR
    NONE OF THE ABOVE                          -> INCONCLUSIVE

INCONCLUSIVE is not a verdict. It is a FAILED MEASUREMENT: it is retried once -- the
failure mode is fast, so the retry is cheap -- and if the retry does not rescue it,
it FAILS the gate, because a number nobody observed is not a number a document may
quote. It cannot manufacture a pass: a mutant that genuinely does not build still
prints `Error: [NNNN]` and still comes out COMPILE-ERR, which is what gates 0412 M3
and 0430 M4 declare and what they still come out as.

**AND THE NEW VERDICT PATH IS SHOWN TO GO RED**, because a verdict path that has never
been shown to go red is a comment. `_verify/mutate_lib_selftest.ps1` is a STAGE of the
release gate: it copies `_verify` into TEMP, breaks the copy's summary-line regex for
the MUTATION runs -- the BASELINE's regex is left alone, because a demonstration that
breaks the baseline proves nothing about the mutation path -- and requires the copy's
one-mutation gate to come out INCONCLUSIVE, to FAIL, and to exit non-zero.

=> 判据: A GATE THAT FAILS FOR THE WRONG REASON IS WORSE THAN NO GATE, AND THE
WRONG REASON IS THE ONE NOBODY LOOKS AT. This one was going to be read as "the 0466
mutation is not what it says it is" -- a claim about the ANALYZER, published by a
failure that was really about the machine. The fix is not to re-roll the gate until
it passes; the fix is to tell a rejected build from a run that never happened, and
to say that a run that cannot be scored is not a verdict about anything.
## 0507: THE THREE TRANSFERS, LANDED -- AND WHAT THE ANALYZER NOW SAYS ABOUT A FINDING

0505 WAS A PLAN. It named three things to port from PyCQA's `bandit` -- a per-finding
confidence axis, stable family ids with a checked profile, and `nosec` with a warning
when a suppression matched nothing -- and it MEASURED every premise the plan rested on,
so that the plan would not be built on a premise that stopped being true while nobody
was looking.

THIS SECTION IS THE PLAN, BUILT. And it is measured the same way the plan was: every
number below is re-derived by `_verify/settle_0507_bandit_transfers.ps1` against the real
scanner, with a control for each, and the settle is a stage of the release gate.

And the plan left one question open, which this increment answers: **what does the
analyzer do about a call it cannot check?** Silence, a low-confidence finding, or a
separate "unchecked" count are three different products with three different costs, and
they disagree about what a `CLEAN` file means. The answer here is the third one, and the
first thing transfer 1 has to settle.

### THE CONFIDENCE AXIS, AND WHAT IT IS NOT

The severity of a finding says how bad it is **IF IT IS REAL**. The confidence says how
much the lens **CHECKED** before it produced it, and the two are independent: a finding
can be severe and uncertain, or trivial and certain. There are exactly three values, and
they are the three situations a lens can be in:

```
    high      the lens had the declaration, the signature or the type in front of it
    low       the lens was reasoning from a NAME alone
    undecided the lens could not decide at all
```

THE RULE, and it is the 0505 plan's three situations exactly:

* a **scope limit** -- "this construct is outside the analyzed subset" -- is the lens
  saying it could not DECIDE, and is `undecided`;
* a finding whose family reasons from a **name** alone is `low`. The only one is
  `UndefinedName`: the analyzer found no binding for the name, and the binding it could
  not find may be in a file, or in a package, it was never given;
* everything else had the declaration, the signature or the type in front of the lens, and
  is `high`.

**IT IS COMPUTED, NOT A FIELD, AND THAT IS THE WHOLE ARGUMENT FOR THE SHAPE.** A `Report`
is constructed at about thirty places -- the walk, the type lens, the interpreter, the
pipeline, the literate frontend, the lexer, the parser, the state audit -- and a field
would have to be filled in at every one of them. A missed one would be a finding with the
wrong confidence and **no way to notice**: there is nothing to compare it against, because
the field is the only copy of the fact. A function has one definition and cannot drift.
`src/report/report.mbt` computes it, and the renderer, the JSON record and the per-family
counts all read that one function.

**A FINDING IS NOT DROPPED FOR BEING UNCERTAIN.** It is REPORTED at a lower confidence --
and that is the entire difference between a silence that reads as "nothing to report" and
a statement about how much was checked. The 0505 plan called this a false negative, and
the false negative was never the absence of a finding: it was the absence of a way to
tell a finding apart from a silence.

### THE STABLE FAMILY IDS, AND THE ROSTER THAT CHECKS THEM

The public vocabulary of a finding is its family, and the family is spelled with a NAME.
Five of the original eleven names are not the tag with its `F` removed: `FParse` ->
`ParseError`, `FAssignType` -> `AssignTypeMismatch`, `FArgType` -> `ArgTypeMismatch`,
`FOpMismatch` -> `OperatorMismatch`, `FCondBool` -> `NonBooleanCond`. So the name is a
second, hand-maintained vocabulary that has to be kept in step with the first, and
nothing enforced that. Renaming a family changes the JSON output silently, and a consumer
that pins `"family": "ArgTypeMismatch"` in a suppression or a CI filter gets no warning at
all.

An **id** is a contract: allocated once and **never renumbered**. `MSA-001` means the same
family in 0.4.37, the release that allocated it, and in every version after it, whatever
the family is called.

```
    MSA-001 ParseError        MSA-005 ParamChanged       MSA-009 MethodError
    MSA-002 UndefinedName     MSA-006 AssignTypeMismatch MSA-010 NonBooleanCond
    MSA-003 UnusedLocal       MSA-007 ArgTypeMismatch    MSA-011 Unreachable
    MSA-004 UnusedParam       MSA-008 OperatorMismatch   MSA-012 StaleNosec
```

**THE TABLE IS HAND-ALLOCATED ON PURPOSE.** Deriving an id from the enum's position would
renumber every family after an insertion, which is the one thing an id must never do. So
the table is written out, one line per family.

**AND TWO TABLES EXIST, AND A GATE COMPARES THEM.** `Family::id` is the forward table and
`family_by_id` is the inverse one. The compiler enforces the FIRST: a new family breaks
the build there, because the match is exhaustive over the enum. It enforces NOTHING about
the SECOND, because that match is on strings and a missing arm would simply never match --
a family whose id could not be selected in a profile and could not be named in a `nosec`,
with nothing saying so. A number written down twice will disagree with itself eventually,
and a disagreement between two tables is invisible to the reader: the analyzer would
quietly accept one spelling of an id and not the other.

`_verify/check_family_roster.ps1` compares them, and it compares them to the ENUM: one id
per family, no id used twice, the ids a **contiguous run** from `MSA-001`, and the inverse
table the exact reverse of the forward one. The contiguity is the "never renumbered"
property made checkable: a gap means a number was allocated and never used, and a family
given a number in the middle of the run means every suppression written against that
number now names a different family.

### THE PROFILE, AND THE TWO RULES THAT CHECK IT

`--families <ids>` and `--exclude-families <ids>` select families by id, and the profile
is validated **before the scan runs**:

* an id that names NO family is a **WARNING**, not an error. The reader asked for a
  family this version does not have -- one added in a later release, or a typo -- and the
  scan still runs, because the reader asked for a scan. A profile that silently ignored
  an id would read as "that family has no findings", which is a very different claim from
  "that family is not this version's".
* an id that is BOTH included and excluded is an **ERROR**, and the scan does not run at
  all. The two rules contradict each other and no reading of the profile satisfies both,
  so which one won would be decided by the order of two `if`s inside the scanner.

The filter is applied to the WHOLE report list, **before** the trusted-region split, so
`total`, `unreliable` and `notices` all describe the same findings. A filter applied after
the split would leave `total` counting findings the reader can never see.

### THE `nosec`, AND THE STALE SUPPRESSION THAT IS ALSO A FINDING

```
    // nosec              silences every family on this line
    // nosec MSA-007      silences that one family on this line
    // nosec MSA-007 MSA-002
```

The comment has to **BE** a nosec comment: it must start with `nosec`. A comment that
merely mentions the word is not one, because a suppression that can be switched on by
mentioning the word is a suppression that gets switched on by accident. The **last** `//`
on the line is the comment, so a URL in a string literal does not hide a real `nosec` and
a string that CONTAINS one does not become one.

**IT IS OFF BY DEFAULT, and the default is a decision rather than an omission.** A tool
that stops reporting a finding because of a comment in the ANALYSED source has an output
the reader cannot trust without reading that source first. The policy question -- should a
`nosec` be honoured by default? -- is NOT decided here, and the way this increment
avoids deciding it is that the default is the conservative one and the switch is
explicit.

**A `nosec` THAT SUPPRESSED NOTHING IS A FINDING OF ITS OWN.** `StaleNosec`, `MSA-012`,
severity warning, and it carries **no lens**: no lens produced it, and the rendered
bracket says so with a dash rather than pretending a lens saw it. A stale suppression is
dead weight in the source, and it is a sign that the code it referred to has changed.

**AND THE ORDER IS WHAT MAKES THE WARNING USEFUL.** The suppressions are applied FIRST
and the stale findings are produced AFTER, so a blanket `// nosec` cannot silence the
warning about its own staleness -- which would make the warning disappear exactly when
it is the one thing the reader needs.

### AND THE CALLS THAT WERE NOT CHECKED ARE COUNTED

The type lens checks a call's arity and its argument types ONLY when it has read the
callee's signature. There are three kinds of call where it never has:

```
    a name known only by NAME      the ANALYZER keeps the name and drops the parameter
                                   list the `.mbti` already gave it
    a method call                  the method's signature is not in the source at all
    a `..` chain link              a method call wearing different syntax
```

**THE FIRST LINE OF THAT BLOCK WAS CORRECTED ON 2026-10-28, AND THE MEASUREMENT THAT
CORRECTED IT IS IN THE 0508 SECTION BELOW.**

Until 0507 the tool said **nothing** about any of them, so *"I could not check this"* and
*"there is nothing to report"* were the same output -- and a file with no findings and
four hundred unchecked calls printed exactly like a clean file. The count now travels with
the pipeline result and is disclosed twice: on the file's own verdict line
(`unchecked=N`) and on the `SUMMARY`, where it is deliberately **not** part of the sum,
because an unchecked call is not a defect and adding it to `total` would break the
identity the SUMMARY prints.

**AND HERE ARE TWO NUMBERS THAT LOOK LIKE A CORRECTION AND ARE NOT.** The 0505 plan
measured **16,250** package-level calls whose signature is known by name only, out of
19,843 package-level calls. The analyzer's own count over the same seven corpora is
**23,427**. These are DIFFERENT quantities and neither corrects the other: the 0505
figure counted ONE kind of call (package-level, name-only), and the analyzer counts
three. This increment did **not** measure the analyzer's package-level subset separately,
so the two figures are not comparable, and the 0505 figure is not wrong -- it was always
about one kind of call.

### WHAT DID NOT MOVE, AND WHY THAT IS THE POINT

```
    0507 the family roster, families   : 12
    0507 the family roster, ids         : 12
    0507 the confidence axis, values     : 3
```

On all seven pinned corpora, `actionable`, `notices`, `unreliable`, `withheld` and
`total` are **UNCHANGED**. Only one field of the corpus pins moved, and it is the new
one:

| corpus | files | parsed | actionable | notices | unchecked |
|---|---:|---:|---:|---:|---:|
| moui | 608 | 608 | 0 | 3457 | 7678 |
| moonbit_labeler | 37 | 37 | 1 | 698 | 1340 |
| moonbit_image | 18 | 18 | 0 | 186 | 754 |
| async | 419 | 419 | 0 | 1654 | 2879 |
| proton | 137 | 137 | 0 | 1799 | 2897 |
| proton_contract | 4 | 4 | 0 | 29 | 12 |
| moonbit_core | 1029 | 984 | 28 | 10096 | 7867 |

**A TRANSFER THAT HAD MOVED A FINDING COUNT WOULD BE A CHANGE TO THE ANALYSIS, NOT TO
THE REPORTING**, and it would need a different justification and a different gate. What
0507 does is change what the analyzer SAYS about a finding -- how much was checked, which
family it is in a vocabulary that survives a rename, and how many calls were never
checked at all -- and that is a reporting change, so the evidence is the same numbers
plus one new one.

The two other published numbers that moved are the ones that move whenever the analyzer's
own source grows, and they moved because this increment added four files to it:

```
    the eight trees' notices          19569 -> 19603
    this repository's own files          183 ->   187
    the own-source notices            1650 ->  1684
```

### THE SETTLE

`_verify/settle_0507_bandit_transfers.ps1`, nineteen rows, no compiler oracle needed
because nothing here is a question about the LANGUAGE -- every row is a question about
what the analyzer DOES, and the answer is read back from the analyzer itself:

* T1..T4 -- the confidence axis: the three situations produce the three values, and the
  axis has exactly three of them;
* T5, T6 -- the ids: every rendered finding carries a roster id, and the JSON record
  carries `severity`, `confidence` and `family_id`;
* T7..T10 -- the profile: the include set keeps exactly its family, the exclude set
  drops exactly its family, an unknown id WARNS and the scan still runs, and an
  include/exclude overlap ERRORS and no scan runs;
* T11..T14 -- the `nosec`: off by default, on with `--honor-nosec`, a stale one is
  reported, and the stale finding is a first-class finding with an id and a confidence;
* T15..T17 -- the disclosure: the count reaches the verdict line and the SUMMARY, a
  file with nothing to check says zero, and the count is NOT a finding;
* T18, T19 -- the roster the analyzer hands out, and this section's three numbers read
  back out of THIS FILE.

### THE GATE

`_verify/mutate_0507.ps1`, fifteen mutations, and every one of them names the test that
must go red. Fourteen are killed; the fifteenth is a DECLARED SURVIVOR with its
argument attached, because the root package has no test file and the CLI's plumbing is
therefore invisible to `moon test` -- the place it IS observable is the settle, whose
rows T11 and T12 scan a fixture with and without `--honor-nosec` and assert both halves.

### WHAT THE RELEASE GATE CAUGHT IN THE GATES THIS INCREMENT TOUCHED

Two of the gates this increment touched were WRONG when the release gate ran them, and
both failures had the same cause: **a gate that PARSES the analyzer's output was still
parsing the output as it looked before 0507.**

`_verify/settle_0506_notice_flood.ps1` read a rendered finding with the pattern
`\[([a-z,]+)\]` -- a bracket that held ONE lowercase tag, the lens list. The bracket
holds THREE fields now: the lens list, the family's id (`MSA-NNN`) and the confidence,
and `MSA-007` is not `[a-z,]+`. So the pattern matched nothing, and six of the settle's
ten rows reported a MISMATCH that read like a change in the analyzer's BEHAVIOUR -- a
notice that used to be printed going missing -- and was really a change in how the gate
read the output.

**AND TWO OF THE FOUR ROWS THAT STILL PASSED PASSED FOR THE WRONG REASON.** N2 and N3
assert that a notice is printed ZERO times, and a parser that matches nothing reports
zero. They were satisfied by the broken pattern, not by the behaviour they are about: a
row that asserts "printed zero times" cannot tell "aggregated" from "not parsed". The
rows that passed for the RIGHT reason are the two that read the SUMMARY, which does not
depend on the rendered shape at all.

`_verify/settle_0505_finding_quality.ps1`'s row B3 was re-pinned by this increment to
assert that a rendered finding carries its family NAME, its id and its confidence, and
the re-pin spelled the lens tag out as `structural`. The fixture's finding comes from
the TYPE lens, so the row failed on a rendered line that was exactly right. The row is
about the SHAPE -- a lens tag, the family's id, a confidence -- and it now matches the
shape rather than pinning which lens produced it.

**A GATE THAT READS THE OUTPUT IS A GATE THAT CAN BREAK WHEN THE OUTPUT CHANGES**, and
the failure it produces points at the ANALYZER rather than at the gate. That is the
worst direction for a gate to break in: the row says "the tool stopped printing
notices", and the reader's first act is to go and look at the tool.

### WHAT IS NOT IN THIS INCREMENT

**THE POLICY DECISION IS STILL UNMADE.** Whether a `nosec` should be honoured by default
is a question about what a reader of the output is owed, and this increment does not
answer it; it only makes the conservative choice the default and leaves the switch
explicit. The 0505 section said the third transfer "waits on a decision about policy that
has not been made", and that is still true -- what changed is that the capability now
exists and the decision is a one-line change rather than an increment.

**THERE IS STILL NO CONFIG FILE.** A profile is a flag, not a file: the analyzer only
ever READS the target's tree, and a configuration file it reads from that tree would be
one more thing the reader has to trust.

**AND THE CONFIDENCE IS STILL NOT PER-CALL.** It is per FINDING, computed from the family
and the scope limit. A finding that is `high` is a finding whose family checked
something; it does not say WHICH thing was checked, and a family that checks two
different things in two different ways cannot express that in one word. That is a limit
of the three values, and the values were chosen to be three.

=> 判据: A TOOL THAT CANNOT SAY WHAT IT DID NOT CHECK SAYS NOTHING, AND A READER
WHO CANNOT TELL A SILENCE FROM A CLEAN RESULT WILL EVENTUALLY READ ONE AS THE OTHER.
The 0505 plan found the problem and left the answer open; this increment answers it,
and it answers it with the smallest thing that is true: not a new severity, not a
second report, but one word beside the finding that says how much was checked, one
stable id beside the family name that survives a rename, and one number on the verdict
line that says how many calls went unverified.
## 0508: THE THREE KINDS, MEASURED -- AND THE FIRST ONE WAS WRONG

**THIS SECTION SHIPS NO CODE.** It is a measurement, and it is here because the
0507 section it corrects asserted something that turned out to be false.

### THE PREMISE WAS FALSE, AND IT WAS FALSE ABOUT THE FORMAT

The 0505 plan rested on a premise and 0507 repeated it: "a `.mbti` gives a name and
never its parameter list". The `.mbti` DOES declare the parameters.
`iface_signature` reads the parameter list out of every `pub fn` line --
`paren_parts`, `split_top_commas`, `label_type`
(`src/moonfiles/moonfiles.mbt:917-931`) -- and keeps only the referenced type
names. What never had the parameters is the SYMBOL TABLE: `IfaceSymTab`
(`src/core/core.mbt:97`) has no slot for a signature, so the parameter list the
parser produced is dropped one line later.

So the premise is true of the TABLE and false of the FORMAT, and the difference is
the difference between "the information is not there" and "we drop it". Every
design that follows from "it is not there" is aimed at the wrong thing.

### THE MEASUREMENT

The instrument is `_verify/measure_0508_unchecked.ps1`. It patches ONE file --
`src/types/infer.mbt` -- with counters the shipped analyzer does not have, builds
the wasm, scans the eight trees, and restores the file byte-identically
(SHA256-proven) before rebuilding the binary, so the binary on disk matches the
committed source again. The counters it adds are ADDED TO the shipped ones and
never replace them, so the sum the instrument computes has to equal the shipped
`SUMMARY` on every tree. That is the control, and it is why these numbers are
trusted: a measurement that cannot reproduce the number it is explaining is not a
measurement.

The eight trees are the seven pinned corpora and this repository own source.

    0508 the unchecked calls, eight trees          : 28040
    0508   a name known only by NAME               : 2634
    0508   a method call                            : 25331
    0508   a `..` chain link                        : 75

**SO THE METHOD CALL IS NOT ONE KIND, IT IS THREE, AND ONLY ONE OF THE THREE IS
ABOUT SIGNATURES.** A method call `x.f(..)` can only be checked if the receiver
TYPE is known -- so the method can be found -- and the parameter list is in hand
-- so the arguments can be checked. The type model has no variant for a NAMED
type: `Ty` (`src/types/types.mbt:10-39`) is Unknown / None / int / float / bool /
str / list / function / union, so every struct, class and enum is `TUnknown`,
because `ann_to_ty` falls through to `TUnknown` for any name it does not
recognise (`src/types/types.mbt:161,187`).

    0508 method calls, receiver type KNOWN          : 3766
    0508 method calls, receiver type UNKNOWN        : 18322
    0508 method calls, qualifier receiver           : 3243
    0508 `..` links, receiver type UNKNOWN          : 75
    0508 `.mbti`-only callees, a plain fn           : 510
    0508 `.mbti`-only callees, a `Type::method`     : 2124

**AND THE PRIZE IS NOT WHERE THE FIRST HYPOTHESIS SAID.** The hypothesis was that
the `.mbti` bucket would be the cheapest and the largest win, because the
parameters were already parsed and thrown away. Measured, the `.mbti` bucket is
9.4% of the unchecked calls and the method-call bucket is 90.3%. So the track the
reader would pick -- read the method signatures -- is the RIGHT one; it is just not
the `.mbti` table alone.

Keeping the parameter list the `.mbti` parser already reads reaches the 3,766
method calls whose receiver type is known, the 3,243 qualified calls
(`@pkg.f(..)`, whose signature the `.mbti` carries as `pub fn pkg::f(..)`), and
the 2,634 `.mbti`-only callees -- 9,643 at most, and only for the calls whose
receiver type the analyzer can already name. The other 18,322 method calls have a
receiver whose type is a struct, a class or an enum, and `Ty` cannot represent
one, so no signature table reaches them until the TYPE MODEL grows a named-type
variant.

The `.mbti` files of the seven corpora carry 4,938 `Type::method` entries and
1,152 plain `pub fn` entries. All of them are sitting there unused.

**AND THE `..` LINKS ARE NOT A TRACK.** 75 calls, 0.3% of the total, every one of
them with an unknown receiver type: they are the method-call problem wearing
different syntax, not a separate one.

### WHAT THIS CHANGES

The next increment is not "keep the parameter list in `IfaceSymTab`". It is two
layers, and the measurement says which is bigger:

1. the SIGNATURE layer -- keep the parameter list the `.mbti` parser already reads,
   so the qualified calls and the `.mbti`-only callees become checkable. At most
   9,643 of the 28,040.
2. the TYPE layer -- a named-type variant in `Ty`, so a struct, class or enum
   receiver has a type and its methods can be found. The 18,322.

The `..` chain links are not a third item; they are the second item with different
syntax.

=> 鍒ゆ嵁: A PREMISE ABOUT WHAT A FORMAT CARRIES IS NOT A PREMISE UNTIL THE FORMAT
HAS BEEN READ. The 0505 plan and the 0507 section both said a `.mbti` gives a name
and never its parameter list, and both said it as though it were a fact about the
format. It was a fact about a symbol table, and the difference cost one increment
of aim. The measurement that corrected it is the instrument above, and its own
control is that it has to reproduce the shipped `SUMMARY` to be believed.
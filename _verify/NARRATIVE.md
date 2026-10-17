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
wasm-gc 590/590 (up 5 on each 鈥?the five 0447 tests live in `moonfiles`, which is
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
   answer for entirely the wrong reason. `--extern-iface-dir` was being IGNORED: the extern
   tree is taken from the process CWD's `.repos`, and the two runs sat in different
   directories, so the HEAD build resolved against a different interface tree. Redone from one
   CWD, with the `Info:` line confirming both runs used the same tree, the same 187-vs-186
   stands -- now for the right reason. => an A/B that does not verify its own inputs agrees
   with a broken one by coincidence, and the coincidence is indistinguishable from the result.

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

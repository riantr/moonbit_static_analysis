# Mutation gate 0616 -- the SPLIT of the unverified call sites, and the FIVE
# counters it is made of.
#
# WHAT THIS INCREMENT IS. `n_calls - n_checked` was ONE number for FIVE
# different reasons, and the sentence beside it named TWO of them -- the two
# that REPORT. The other three are SILENT, and they are the majority: MEASURED
# on the seven pinned corpora, 21,350 of the 31,058 unverified call sites are a
# METHOD call, a class the old sentence never named.
#
# THE FIX IS FIVE COUNTERS AND A ROW, and the row checks itself: its `sum` has
# to be the remainder the `calls` row prints. So there are TWO things to break,
# and this gate breaks BOTH:
#
#   THE REPORT (`src/sa/main.mbt`)  -- M1..M5. The row can lose a field, lose a
#     term of its sum, lose a counter in the aggregation, or go back to saying
#     the remainder is two classes.
#
#   THE LENS (`src/types/infer.mbt`) -- M6..M10. The five counters can be
#     attributed to the wrong class, which is the defect that a report-level
#     test CANNOT see: a report-level test builds its own verdict, so a lens
#     that counted every method call as a sig-unknown call would print a
#     perfectly self-consistent row and be wrong about every tree.
#
# EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED. A mutation that kills
# some other test is not evidence: the test named here is the one that pins the
# rule, so the kill is the rule's own. AND EACH OF THE FIVE LENS MUTATIONS
# NAMES A DIFFERENT TEST, because one test that dies for five different reasons
# cannot tell which reason died.
#
# WHY THE FIVE LENS MUTATIONS KEEP A `+= 0`. MoonBit denies the warning
# "the mutability of field 'n_unresolved' is never used" -- and `moon test`
# treats that warning as an error, so a mutation that simply DELETED a
# counter's increment would not be a mutation at all: the suite would not
# compile, the harness would score it COMPILE-ERR, and the gate would report a
# broken mutant where there was none. MEASURED 2026-11-20: the first five lens
# mutations were written that way and all five came back COMPILE-ERR.
#
# So a mutation that moves a count from one counter to another leaves the
# counter it emptied still `mut`, and the `+= 0` is what keeps the mutability
# used. It is not decoration: the lint is what makes the mutation expressible,
# and the comment above each mutation says WHICH counter was emptied.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE, and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$SA = 'src\sa\main.mbt'
$INFER = 'src\types\infer.mbt'

Invoke-MutationGate -Name '0616' -Target 'wasm' -Mutations @(

  # M1 THE SUM LOSES A REASON. The row prints a `sum` so that it can CHECK
  # itself against the remainder it splits -- and a sum that drops one term is
  # a row that checks itself against a number that is not the sum of the
  # numbers beside it.
  #
  # THE TERM DROPPED IS THE METHOD COUNT, and that is deliberate: the fixture's
  # dotdot count is ZERO, so dropping THAT term would leave the sum unchanged
  # and the mutation would survive. A mutation that survives because its
  # fixture happened to be zero is a mutation that measures the fixture.
  @{
    Name = 'M1 the split sum drops the method term'
    File = $SA
    Find = @'
  let split_sum = s.n_unknown_fn +
    s.n_not_callable +
    s.n_unresolved +
    s.n_method_call +
    s.n_dotdot_call
'@.Replace("`r`n", "`n")
    Repl = @'
  let split_sum = s.n_unknown_fn +
    s.n_not_callable +
    s.n_unresolved +
    s.n_dotdot_call
'@.Replace("`r`n", "`n")
    MustRed = '0616: the split row'
  }

  # M2 THE ROW LOSES A FIELD. The whole point of the row is that it names FIVE
  # reasons, and a row that names four is the old two-class sentence with a
  # new row's clothes on.
  #
  # THE FIELD DROPPED IS `not-callable`, and it is renamed rather than deleted:
  # a DELETED field would leave two fields adjacent, and the row would still
  # print five numbers in the wrong order -- which is a different defect and
  # one this gate does not claim to cover. The rename is the defect: the row
  # no longer names that reason, so a reader cannot find it.
  @{
    Name = 'M2 the split row loses the not-callable field'
    File = $SA
    Find = 'sig-unknown=\{s.n_unknown_fn}\tnot-callable=\{s.n_not_callable}\t'
    Repl = 'sig-unknown=\{s.n_unknown_fn}\tnot-callable-disabled=\{s.n_not_callable}\t'
    MustRed = '0616: the unverified-split row names all five reasons'
  }

  # M3 THE SENTENCE GOES BACK TO TWO CLASSES. This is the defect the increment
  # exists to fix, in the exact words the old row used. The row would still
  # carry the five numbers -- so a reader who only reads the NUMBERS would see
  # nothing wrong -- but the sentence would name two of them, and the two it
  # names are the two that REPORT, so the sentence would be describing 16.5 %
  # of the remainder as if it were all of it.
  @{
    Name = 'M3 the calls row says the remainder is two classes again'
    File = $SA
    Find = 'not-verified = the FIVE reasons the `unverified-split` row names -- MEASURED 0616, the two this line used to name are only two of the five;'
    Repl = 'not-verified = callee not callable, or name unresolved;'
    MustRed = '0616: the calls row no longer claims the remainder is two classes'
  }

  # M4 THE ROW STOPS SAYING WHICH REASONS REPORT. The row carries five
  # numbers, and a reader who has to work out from five numbers which of them
  # produce a finding is the reader this increment is for. The words are
  # lower-cased: the row still carries the same INFORMATION, and a reader
  # reading the sentence would still understand it -- but the row's own claim,
  # which is the claim the test pins, is gone.
  @{
    Name = 'M4 the split row stops saying which reasons report'
    File = $SA
    Find = 'not-callable and unresolved REPORT, the other three are SILENT;'
    Repl = 'not-callable and unresolved report, the other three are silent;'
    MustRed = '0616: the split row says which of the five reasons report'
  }

  # M5 THE AGGREGATION LOSES A COUNTER. The row is printed from an aggregate
  # over every verdict, so a counter the aggregation does not add up is a
  # counter that is zero in every tree -- and the row would still be
  # self-consistent, because a zero term contributes nothing to the sum.
  #
  # THE TERM IS REPLACED AND NOT DELETED, because a deleted term would leave
  # `let mut n_method_call = 0` never mutated, and that is a DIFFERENT
  # question for the compiler. This mutation is about the aggregation, and it
  # changes nothing but the aggregation.
  @{
    Name = 'M5 the aggregation drops the method counter'
    File = $SA
    Find = @'
    n_unknown_fn += v.n_unknown_fn
    n_not_callable += v.n_not_callable
    n_unresolved += v.n_unresolved
    n_method_call += v.n_method_call
    n_dotdot_call += v.n_dotdot_call
'@.Replace("`r`n", "`n")
    Repl = @'
    n_unknown_fn += v.n_unknown_fn
    n_not_callable += v.n_not_callable
    n_unresolved += v.n_unresolved
    n_method_call += 0
    n_dotdot_call += v.n_dotdot_call
'@.Replace("`r`n", "`n")
    MustRed = '0616: the split row'
  }

  # M6 A METHOD CALL IS COUNTED AS A SIG-UNKNOWN CALL. This is THE mutation
  # the report-level test cannot see: `src/sa/sa_0616_test.mbt` builds its own
  # verdict, so it would still pass, and the row would still be
  # self-consistent -- the numbers would just be the wrong numbers, on every
  # tree, for ever.
  #
  # AND IT IS THE DEFEAT THAT MATTERS MOST IN PRACTICE: method calls are the
  # MAJORITY of the remainder (21,350 of 31,058 across the seven corpora), so a
  # lens that filed them under sig-unknown would move the majority of the
  # remainder into a different column of the published table without changing
  # a single finding.
  @{
    Name = 'M6 a method call is counted as a sig-unknown call'
    File = $INFER
    Find = @'
        self.n_method_call += 1
'@.Replace("`r`n", "`n")
    Repl = @'
        self.n_method_call += 0
        self.n_unknown_fn += 1
'@.Replace("`r`n", "`n")
    MustRed = '0616: the method class is counted on its own'
  }

  # M7 AN UNRESOLVED NAME IS COUNTED AS NOT CALLABLE. The two classes that
  # REPORT are told apart by WHERE the name failed: a callee that resolved to
  # something that is not a function, and a name that resolved to nothing at
  # all. Folding the second into the first would keep the count and lose the
  # distinction -- and the distinction is the one a reader needs, because the
  # two produce DIFFERENT findings.
  @{
    Name = 'M7 an unresolved name is counted as not callable'
    File = $INFER
    Find = @'
        self.n_unresolved += 1
'@.Replace("`r`n", "`n")
    Repl = @'
        self.n_unresolved += 0
        self.n_not_callable += 1
'@.Replace("`r`n", "`n")
    MustRed = '0616: the unresolved class is counted on its own'
  }

  # M8 A `..` LINK IS COUNTED AS A METHOD CALL. They are different constructs
  # with different syntax, and the row names them separately, so counting one
  # as the other is the row losing a reason.
  @{
    Name = 'M8 a `..` link is counted as a method call'
    File = $INFER
    Find = @'
        self.n_dotdot_call += 1
'@.Replace("`r`n", "`n")
    Repl = @'
        self.n_dotdot_call += 0
        self.n_method_call += 1
'@.Replace("`r`n", "`n")
    MustRed = '0616: the dotdot class is counted on its own'
  }

  # M9 A SIG-UNKNOWN CALLEE IS COUNTED AS NOT CALLABLE. The two differ in
  # whether the name resolved at all: sig-unknown is a cross-file value whose
  # signature was never read, and it is SILENT, while not-callable REPORTS.
  # Folding the silent class into the reporting one would make the published
  # table claim that more of the remainder reports than does.
  @{
    Name = 'M9 a sig-unknown callee is counted as not callable'
    File = $INFER
    Find = @'
        self.n_unknown_fn += 1
'@.Replace("`r`n", "`n")
    Repl = @'
        self.n_unknown_fn += 0
        self.n_not_callable += 1
'@.Replace("`r`n", "`n")
    MustRed = '0616: the sig-unknown class is counted on its own'
  }

  # M10 A NOT-CALLABLE CALLEE IS COUNTED AS UNRESOLVED. The mirror of M9, and
  # the reason both are here: with only one of them, the other class would
  # absorb the difference and the split would still add up.
  @{
    Name = 'M10 a not-callable callee is counted as unresolved'
    File = $INFER
    Find = @'
        self.n_not_callable += 1
'@.Replace("`r`n", "`n")
    Repl = @'
        self.n_not_callable += 0
        self.n_unresolved += 1
'@.Replace("`r`n", "`n")
    MustRed = '0616: the not-callable class is counted on its own'
  }
)

# THE VERDICT, AND THE EXIT THAT CARRIES IT. These two lines are what make this
# gate ABLE TO FAIL: the harness RECORDS a failure in
# `$script:MutationGateFailures`, and without these lines that record goes
# nowhere -- the script ends normally, `powershell -File` exits 0, the
# transcript carries no `GATE FAILED` line, and `release.ps1`'s `Run-Gate`
# reports the gate as PASS.
#
# `check_gate_roster.ps1` checks that every numbered gate carries both lines,
# so this cannot rot back into a comment.
Write-MutationGateVerdict -Name '0616 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }

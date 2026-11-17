// 0602: SOUNDINESS -- the deck's three-way verdict, derived per family.
//
// The deck is `Soundiness` (Yue Li and Tian Tan, Nanjing University, 2021
// Fall), and p.14 gives the three verdicts:
//
//   A soundy analysis aims to capture all dynamic behaviors with certain hard
//   language features unsoundly handled within reason
//   A sound analysis requires to capture all dynamic behaviors
//   An unsound analysis deliberately ignores certain behaviors in its design
//   for better efficiency, precision or accessibility
//
// The rows below pin the DERIVATION and the measured counts. Every number was
// printed by the code that asserts it before it was written down here.

///|
/// THE VERDICT IS DERIVED FROM THE CAUSE, and the derivation is what the rows
/// pin: a family with no exclusion is sound, a family whose exclusions are all
/// hard features is soundy, and a family with ONE deliberate exclusion is
/// unsound however many hard features it also has.
///
/// AND THE CONTROL IS THE SAME FUNCTION: `soundiness_counts` counts the
/// verdicts the derivation produced, so a function that answered "soundy" for
/// everything would not be caught by a row that only checked one family.
test "0602: the verdict is derived from the cause, not typed per family" {
  // A family with a hard feature only.
  assert_true(@core.FParse.soundiness() == @core.Soundy)
  assert_true(@core.FUndefinedName.soundiness() == @core.Soundy)
  // A family with a DELIBERATE exclusion, and one with both.
  assert_true(@core.FArgType.soundiness() == @core.Unsound)
  assert_true(@core.FOpMismatch.soundiness() == @core.Unsound)
  assert_true(@core.FStaleNosec.soundiness() == @core.Unsound)
  // AND THE CAUSES ARE VISIBLE, so the verdict is not a mystery number.
  assert_eq(@core.FArgType.exclusions().length(), 2)
  assert_true(@core.FArgType.exclusions()[0].cause == @core.HardFeature)
  assert_true(@core.FArgType.exclusions()[1].cause == @core.Deliberate)
}

///|
/// THE MEASURED COUNTS over the roster of eighteen families.
///
/// AND THE COUNTS ARE NOT WHAT A READER WOULD GUESS: the deliberate
/// exclusions are three, and they are the three the tree's own contracts name
/// -- the named-call arity leniency, the pipe-operator exemption, and the
/// family that reports a stale `// nosec` without re-verifying what the
/// suppression silenced.
test "0602: the measured counts over the eighteen families" {
  let (sound, soundy, unsound) = @core.soundiness_counts()
  assert_eq(sound, 0)
  assert_eq(soundy, 15)
  assert_eq(unsound, 3)
}

///|
/// THE VERDICT FOR THE WHOLE ANALYSIS, which is the worst verdict any family
/// carries -- and the deck's p.6 answer, measured rather than quoted: "can we
/// achieve a fully sound analysis for real-world programs?" No, and here is
/// the count that says it.
test "0602: the analysis as a whole is unsound, because three families are" {
  assert_true(@core.soundiness_verdict() == @core.Unsound)
}

///|
/// THE UNSOUND TREATMENTS, and NOTHING ELSE: the list the deck's p.10 says is
/// omitted from papers, and it is small enough to print.
test "0602: the deliberate treatments, and only those" {
  let un = @core.unsound_treatments()
  assert_eq(un.length(), 3)
  assert_eq(un[0].id, "X-ARG-TYPE-NAMED-ARITY")
  assert_eq(un[1].id, "X-OP-PIPE-EXEMPT")
  assert_eq(un[2].id, "X-NOSEC-REALITY")
  // AND EVERY EXCLUSION ID IN THE ROSTER IS UNIQUE, so a reader can cite one.
  let all = @core.all_exclusions()
  let seen : Map[String, Bool] = Map([])
  for e in all {
    assert_true(!seen.contains(e.id))
    seen.set(e.id, true)
  }
}

///|
/// AND THE EXCLUSION'S OWN TEXT IS A QUOTE OF THE FAMILY'S CONTRACT. The
/// roster gate checks this from the SOURCE; this row checks it at RUN TIME,
/// and a test and a gate that agree are worth more than either alone.
test "0602: every exclusion's text is a quote of its family's contract" {
  for f in @core.all_families() {
    let contract = f.excluded()
    for e in f.exclusions() {
      assert_true(contract.contains(e.text))
      assert_true(e.text.length() >= 10)
    }
  }
}

///|
/// AND THE ROSTER PRINTS: every family with its verdict, then the counts, then
/// the deliberate treatments. The deck's p.10 is about a reader not being able
/// to find this, so the page has to carry it.
test "0602: the soundiness roster prints the verdicts and the counts" {
  let r = @core.soundiness_roster()
  assert_true(r.contains("soundy"))
  assert_true(r.contains("unsound"))
  assert_true(r.contains("families: sound=0  soundy=15  unsound=3"))
  assert_true(r.contains("the analysis as a whole: unsound"))
  assert_true(r.contains("X-ARG-TYPE-NAMED-ARITY"))
}

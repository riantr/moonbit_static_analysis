# Mutation gate 0495 -- THE PER-FUNCTION VIEW'S FALSE POSITIVES, EIGHT FAMILIES
# AT A TIME, AND THE FOUR THE FIX ITSELF EXPOSED.
#
# WHAT THIS INCREMENT IS. The per-function view of the behavioural lens
# reported 116 actionable findings across four pinned corpora:
#
#     moonbit_labeler  38      moonbit_image  35
#     async            40      proton          3
#
# NOT ONE of them is a defect in the code being analysed: every one of the 116
# sites is in a file `moon check` accepts, in released, published packages. So
# the 116 are an INVENTORY OF THE LENS, and this gate is the evidence that
# each fix is a fix and not a silencing.
#
# THE FAMILIES, measured, not guessed:
#
#   A   61   a destructured name bound to the WHOLE TUPLE
#   B   25   a `continue`/`break` that CARRIES A VALUE
#   C    8   a statement after a loop whose body always terminates
#   C2   5   the C-style `for`'s UPDATE clause
#   D   10   a call to an `extern`/FFI declaration -- FOUR causes
#   E    5   a cross-package qualified associated/trait call
#   F    4   an integer `/` typed as `float`
#   G    2   a name bound by an `is`-pattern `as`-binding
#   H    1   a name bound by an ITERATOR expression
#
# Family D is FOUR defects wearing one name, and that is the part worth
# reading: an extern call whose result was claimed to be "None"; a pipe whose
# argument the arity check never saw; an OMITTABLE parameter counted as a
# positional slot; and a name declared TWICE, where the two declarations
# disagree about the arity so that whichever one the lens picked, one of the
# two call sites was reported.
#
# The 116 became 2, and the 2 are the documented `#doc(hidden)` limit
# (`src/core/advice.mbt`): a `#doc(hidden)` API appears in no `.mbti` and so
# cannot be indexed from the command line.
#
# EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED. A mutation that kills
# some other test is not evidence: the test named here is the one that pins
# the rule, so the kill is the rule's own.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE, and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$INTERP = 'src\interp\interp.mbt'
$PARSER = 'src\parser\parser.mbt'
$MOONFILES = 'src\moonfiles\moonfiles.mbt'

Invoke-MutationGate -Name '0495' -Target 'wasm' -Mutations @(

  # M1 FAMILY A. A destructured name holds an ELEMENT, not the tuple. Binding
  # the whole tuple to every name carried the abstract type "Tuple" into every
  # call the name appeared in.
  @{
    Name = 'M1 a destructured name is bound to the whole tuple'
    File = $INTERP
    Find = @'
      for n in names {
        env.set(n, AAny)
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      for n in names {
        env.set(n, AType("Tuple"))
      }
'@.Replace("`r`n", "`n")
    MustRed = '0495 A: a destructured name is not the tuple'
  }

  # M2 FAMILY B. The carried values of a `break` are the TERMINATOR'S OWN
  # PAYLOAD. Dropping them makes the parser leave the value out of the node,
  # and the value is then never read.
  #
  # THE NAMED TEST is the 0494 parser row, and not a 0495 one: the mutation
  # changes the TREE, and the row that pins the tree is the one that reads
  # the value back out of the node. The first draft named a 0495 behavioural
  # row, and the gate reported the miss with the row that actually went red --
  # which is what rule 6 is for.
  @{
    Name = 'M2 a break that carries a value carries nothing'
    File = $PARSER
    Find = @'
    return { span: sp, kind: @ast.SBreak(vals), }
'@.Replace("`r`n", "`n")
    Repl = @'
    return { span: sp, kind: @ast.SBreak([]), }
'@.Replace("`r`n", "`n")
    MustRed = '0494: a break may carry a value and the value is read'
  }

  # M3 FAMILY C. The join reports the terminator the branches AGREE on. It
  # used to answer FReturn for every branch set, which lost the difference
  # between "the body returned" and "the body left the loop".
  #
  # THE MUTATION IS THE AGREEMENT ARM, not the FALL-THROUGH arm. The
  # fall-through arm is pinned by the 0425 rows, and mutating it would have
  # proved a different rule; the rule this increment changed is "when every
  # branch continues, the join says FContinue".
  @{
    Name = 'M3 the join reports FReturn where the branches agree on continue'
    File = $INTERP
    Find = @'
  if all_continue {
    return FContinue
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if all_continue {
    return FReturn
  }
'@.Replace("`r`n", "`n")
    MustRed = '0495 C: the statement after a loop whose branches all continue'
  }

  # M4 FAMILY C2. The C-style `for`'s UPDATE clause is its own node, and the
  # node carries the statements. Dropping them makes the update clause dead.
  @{
    Name = 'M4 the for update clause carries no statements'
    File = $PARSER
    Find = @'
  if updates.length() > 0 {
    loop_body.push({ span: sp, kind: @ast.SForUpdate(updates), })
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if updates.length() > 0 {
    loop_body.push({ span: sp, kind: @ast.SForUpdate([]), })
  }
'@.Replace("`r`n", "`n")
    MustRed = '0470: a compound update clause stays an SAssign'
  }

  # M5 FAMILY F, the TYPE half. `Int / Int` is `Int`. `div_type` is where the
  # answer is decided for a value that is not folded.
  @{
    Name = 'M5 an integer division is typed as a float'
    File = $INTERP
    Find = @'
fn div_type(l : AbsVal, r : AbsVal) -> String {
  let lname = val_name(l)
  let rname = val_name(r)
  if lname == "float" || rname == "float" {
    return "float"
  }
  "int"
}
'@.Replace("`r`n", "`n")
    Repl = @'
fn div_type(l : AbsVal, r : AbsVal) -> String {
  let lname = val_name(l)
  let rname = val_name(r)
  if lname == "float" || rname == "float" {
    return "float"
  }
  "float"
}
'@.Replace("`r`n", "`n")
    MustRed = '0495 F: a division by a literal is an integer'
  }

  # M6 FAMILY F, the FOLDED half. `7 / 2` is 3.
  @{
    Name = 'M6 a division of two literals is folded to a float'
    File = $INTERP
    Find = @'
        OpDiv => if j == 0 { ABottom } else { AInt(i / j) }
'@.Replace("`r`n", "`n")
    Repl = @'
        OpDiv => if j == 0 { ABottom } else { AType("float") }
'@.Replace("`r`n", "`n")
    MustRed = '0495 F: a division of two literals is an integer'
  }

  # M7 FAMILY G. The name after `as` binds WHATEVER the depth, and every other
  # name keeps the depth rule that protects an or-pattern's constructors.
  @{
    Name = 'M7 the as-binding is collected at the old depth'
    File = $PARSER
    Find = @'
          if !in_type && after_as && self.pattern_binding_at(j) {
'@.Replace("`r`n", "`n")
    Repl = @'
          if !in_type && after_as && false && self.pattern_binding_at(j) {
'@.Replace("`r`n", "`n")
    MustRed = '0495 G: a name bound by an is-pattern as-binding'
  }

  # M8 FAMILY H, the EXPRESSION arm. The comprehension's names are bound while
  # the body is evaluated.
  #
  # THERE WAS ANOTHER ARM, and the mutation gate is what found it. The
  # assignment statement's `match` is over the TARGET, and a target is a name,
  # a field, an index or a tuple field -- NEVER a comprehension, so an
  # `EComp` arm there could not fire. M8 (`a comprehension in an assignment
  # binds no names`) SURVIVED, and a surviving mutation of a rule nobody can
  # reach is the rule being dead.
  #
  # So the dead arm was DELETED rather than kept, and this slot is the one
  # that fires: the right-hand side of an assignment is evaluated by
  # `self.eval(rhs, env)`, and the `EComp` arm of `eval` binds the names.
  #
  # RE-ANCHORED, 0504. The anchor used to run from `let cenv = copy_env(env)`
  # to the `AAny` at the end of the arm. 0504 put the comprehension's
  # CONDITION between the binding and the body -- the condition is evaluated
  # in the comprehension's own environment, so its `is` binding is live for
  # the body -- and the old anchor no longer matched. A gate whose anchor does
  # not match is a gate that measures nothing, and the pre-flight would have
  # aborted on it.
  #
  # The anchor is now the BINDING BLOCK alone, which is exactly what the
  # mutation changes: `cenv.set(v, AAny)` becomes `let _ = v`, so the names
  # the comprehension binds are never put in the environment the body is
  # evaluated in. The meaning is unchanged -- the same rule, the same
  # `MustRed` test, the same kill -- and the block is unique in the file.
  @{
    Name = 'M8 a comprehension in an expression binds no names'
    File = $INTERP
    Find = @'
      for v in vars {
        cenv.set(v, AAny)
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      for v in vars {
        let _ = v
      }
'@.Replace("`r`n", "`n")
    MustRed = '0495 H: a comprehension binds its pattern'
  }

  # M9 FAMILY D, THE PIPE. `f <| x` applies f to x, and when f is a CALL the
  # right operand becomes an argument of that call. Without the argument the
  # arity check sees one argument against a two-parameter declaration.
  @{
    Name = 'M9 the pipe does not supply the argument'
    File = $INTERP
    Find = @'
            pvals.push(self.eval(b, env))
'@.Replace("`r`n", "`n")
    Repl = @'
            let _ = self.eval(b, env)
'@.Replace("`r`n", "`n")
    MustRed = '0495 D: a pipe supplies the argument'
  }

  # M10 FAMILY D, THE OMITTABLE PARAMETER. A parameter a call may omit is
  # bound by label or left at its default -- it is not a positional slot.
  @{
    Name = 'M10 an omittable parameter is a positional slot'
    File = $INTERP
    Find = @'
fn omittable_at(def : MethodDef, i : Int32) -> Bool {
  if i < 0 || i >= def.pomittable.length() {
    return false
  }
  def.pomittable[i]
}
'@.Replace("`r`n", "`n")
    Repl = @'
fn omittable_at(def : MethodDef, i : Int32) -> Bool {
  if i < 0 || i >= def.pomittable.length() {
    return false
  }
  false
}
'@.Replace("`r`n", "`n")
    MustRed = '0495 D: an omittable parameter is not a positional slot'
  }

  # M11 FAMILY D, THE NAME DECLARED TWICE. `#cfg` gives one name two
  # declarations with different signatures, and the lens cannot know which is
  # live -- so neither may be arity-checked.
  @{
    Name = 'M11 a name declared twice is arity-checked'
    File = $INTERP
    Find = @'
  for f in fns {
    match out.get(f.name) {
      Some(_) => out.set(f.name, true)
      None => out.set(f.name, false)
    }
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  for f in fns {
    match out.get(f.name) {
      Some(_) => out.set(f.name, false)
      None => out.set(f.name, false)
    }
  }
'@.Replace("`r`n", "`n")
    MustRed = '0495 D: a name declared twice is not arity-checked'
  }

  # M12 FAMILY D, THE EXTERN. A function with no body and no nameable return
  # type has a value of UNKNOWN type. "None" is a claim about a value the file
  # never mentions.
  @{
    Name = 'M12 an extern result is the value None'
    File = $INTERP
    Find = @'
  } else if def.body.length() == 0 {
    AAny
  } else {
'@.Replace("`r`n", "`n")
    Repl = @'
  } else if def.body.length() == 0 {
    AType("None")
  } else {
'@.Replace("`r`n", "`n")
    MustRed = '0495 D: an extern''s result is not the value None'
  }

  # M13 FAMILY E. A TRAIT'S METHODS ARE VALUES, and they are declared inside
  # the trait's body -- a body the `.mbti` reader skipped.
  @{
    Name = 'M13 a trait body is not read for its methods'
    File = $MOONFILES
    Find = @'
      if trait_name != "" {
'@.Replace("`r`n", "`n")
    Repl = @'
      if trait_name == "NEVER_READS" {
'@.Replace("`r`n", "`n")
    MustRed = '0495 E: a trait''s methods are values in the cross-file table'
  }

  # M14 FAMILY U. THE LOOP'S WAY OUT. The joined flow cannot say whether the
  # body could have left the loop -- a body whose branches end in DIFFERENT
  # terminators joins to FReturn, and the `break` is gone with it.
  @{
    Name = 'M14 a break does not record that the loop could be left'
    File = $INTERP
    Find = @'
      self.broke = true
      self.flow = FBreak
'@.Replace("`r`n", "`n")
    Repl = @'
      self.broke = false
      self.flow = FBreak
'@.Replace("`r`n", "`n")
    MustRed = '0495 U: the statement after a loop whose body may break'
  }
)

Write-MutationGateVerdict -Name '0495'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

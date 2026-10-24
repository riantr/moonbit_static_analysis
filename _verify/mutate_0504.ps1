# Mutation gate 0504 -- THE COMPREHENSION GUARD.
#
# WHAT THIS INCREMENT IS. A comprehension may FILTER:
#
#     [ for entry in self.entries if entry is Some({ key, .. }) => key ]
#
# and the `if` is an EXPRESSION. The parser read it and then THREW IT AWAY --
# `ignore(self.parse_or())` -- so the `is` binding it introduces never reached
# the AST, and the body's read of it had no binding to resolve. On
# `moonbitlang/core` `hashset/hashset.mbt:382` that produced
# `undefined variable 'key'`: a FALSE POSITIVE on a file the toolchain
# compiles. 0503 (the `raise?` fix) made that file readable, and 0504 is what
# the readability exposed.
#
# THE COMPILER IS THE ORACLE, and `_verify/settle_0504_comp_guard.ps1` settles
# the whole shape in 18 rows -- 16 with `moon check` and 2 with `moon test`:
#
#     the condition is COMPILED          an undefined name in it is an error
#     the condition FILTERS              it is evaluated once per element
#     the `is` binding reaches the body  and nothing else
#     the condition may read the loop variable
#
# The two RUNTIME rows are the ones `moon check` cannot answer, and they are
# what decide whether a name read only inside a condition is a real read.
#
# => THE CONDITION IS REAL CODE, SO IT IS CARRIED, AND THE ORDER IS THE SCOPE.
# The condition is the THIRD field of the node -- `EComp(vars, sources, cond,
# body)` -- because it sits between the iterable and the body in the source,
# and because it READS the loop variables while its own `is` binding must be
# LIVE when the body is read. Every lens walks the sources, then the
# condition, then the body.
#
# FOUR RULES, AND EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED:
#
#   M1, M2  the parser must CARRY the condition          (it was dropped)
#   M3      the structural lens must WALK it             (its reads are reads)
#   M4      the condition must be walked BEFORE the body (its binding is live)
#   M5      the type lens must TYPE it                   (a type error in it is found)
#   M6      the behaviour lens must EVALUATE it          (its binding reaches the body)
#   M7      the behaviour lens must evaluate it in the comprehension's OWN
#           environment                                  (and not in the outer one)
#   M8      the condition's scope ENDS with the comprehension
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified. One anchor in gate 0495 was RE-ANCHORED by this
# increment, and the reason is in that file.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$WALK   = 'src\walk\walk.mbt'
$INFER  = 'src\types\infer.mbt'
$INTERP = 'src\interp\interp.mbt'

Invoke-MutationGate -Name '0504' -Target 'wasm' -Mutations @(

  # M1 THE CONDITION IS PARSED AND THEN DROPPED. This is the defect itself, and
  # the difference between it and M2 is the whole point of the increment: the
  # condition is READ -- the tokens are consumed, the parse stays in step -- and
  # then it is not put in the node. The `is` binding it introduces therefore
  # never reaches any lens, and the body's read of it is an undefined variable.
  @{
    Name = 'M1 the condition is parsed and then dropped'
    File = $PARSER
    Find = @'
  { span: sp, kind: @ast.EComp(vars, sources, cond, body), }
'@.Replace("`r`n", "`n")
    Repl = @'
  { span: sp, kind: @ast.EComp(vars, sources, None, body), }
'@.Replace("`r`n", "`n")
    MustRed = '0504: the name the condition binds is not reported undefined'
  }

  # M2 THE CONDITION IS WALKED IN A FRAME OF ITS OWN. The condition's `is`
  # binding must be live for the BODY, so it has to be bound in the
  # comprehension's own frame -- a frame of its own is bound and then thrown
  # away, and the body never sees it.
  #
  # THIS SLOT WAS A PARSER MUTATION AND MEASURED OUT OF IT. The first version
  # here was the literal pre-0504 line -- `ignore(self.parse_or())` -- and it
  # came out COMPILE-ERR, not KILLED: with the assignment gone, `cond` is
  # never mutated, and MoonBit rejects the unnecessary `mut` outright. The
  # compiler catches that regression on its own, which is worth knowing and is
  # recorded here, but it makes the mutation pin NOTHING about the analyzer --
  # a slot that measures the compiler instead of the rule is a slot spent for
  # nothing. The rule this slot now holds is one the compiler cannot catch.
  @{
    Name = 'M2 the condition is walked in a frame of its own'
    File = $WALK
    Find = @'
      match cond {
        Some(g) => self.walk_expr(g)
        None => ()
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      match cond {
        Some(g) => {
          self.push_frame()
          self.walk_expr(g)
          self.pop_frame()
        }
        None => ()
      }
'@.Replace("`r`n", "`n")
    MustRed = '0504: the name the condition binds is not reported undefined'
  }

  # M3 THE CONDITION IS NOT WALKED. Two things are lost, and the second one is
  # the half that was still LATENT after the false positive was fixed: the
  # condition's BINDING (the body reads a name nothing binds) and the
  # condition's READS (a name read only there reads as never used).
  #
  # This is the `ECast`/`EComp` lesson in its third form: the half that is not
  # walked is the half that vanishes.
  @{
    Name = 'M3 the condition is not walked'
    File = $WALK
    Find = @'
      match cond {
        Some(g) => self.walk_expr(g)
        None => ()
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      match cond {
        Some(_) => ()
        None => ()
      }
'@.Replace("`r`n", "`n")
    MustRed = '0504: a parameter read only inside the condition is not reported unused'
  }

  # M4 THE CONDITION IS WALKED AFTER THE BODY. The order IS the scope: the
  # condition's `is` binding has to be live when the body is read, and a reader
  # that walks the body first finds the body's name unbound.
  #
  # It is a different defect from M3 and it is a different fix -- M3 loses the
  # condition entirely, M4 loses only its POSITION -- and a gate that could not
  # tell them apart would not know which of the two the code got wrong.
  @{
    Name = 'M4 the condition is walked after the body'
    File = $WALK
    Find = @'
      match cond {
        Some(g) => self.walk_expr(g)
        None => ()
      }
      self.walk_expr(body)
'@.Replace("`r`n", "`n")
    Repl = @'
      self.walk_expr(body)
      match cond {
        Some(g) => self.walk_expr(g)
        None => ()
      }
'@.Replace("`r`n", "`n")
    MustRed = '0504: the name the condition binds is not reported undefined'
  }

  # M5 THE CONDITION IS NOT TYPED. The type lens calls `ty_of` on the
  # condition, so a wrong argument type inside it is still found. Dropping that
  # call loses real checking, and every other row in this gate would still
  # pass -- which is why this mutation names the test that only it can kill.
  @{
    Name = 'M5 the condition is not typed'
    File = $INFER
    Find = @'
      match cond {
        Some(g) => {
          let _ = self.ty_of(g, TUnknown)
        }
        None => ()
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      match cond {
        Some(_) => ()
        None => ()
      }
'@.Replace("`r`n", "`n")
    MustRed = '0504: a type error inside the condition is still reported'
  }

  # M6 THE CONDITION IS NOT EVALUATED. The behaviour lens evaluates the
  # condition in the comprehension's own environment, so the `is` binding it
  # introduces is live for the body. Without the evaluation the body reads a
  # name the environment does not have -- and the STRUCTURAL lens cannot catch
  # it, because the structural lens binds it and the behaviour lens does not.
  # Two lenses, one program, one finding.
  @{
    Name = 'M6 the condition is not evaluated'
    File = $INTERP
    Find = @'
      match cond {
        Some(g) => {
          let _ = self.eval(g, cenv)
        }
        None => ()
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      match cond {
        Some(_) => ()
        None => ()
      }
'@.Replace("`r`n", "`n")
    MustRed = '0504: the name the condition binds is not reported undefined'
  }

  # M7 THE CONDITION IS EVALUATED IN THE OUTER ENVIRONMENT. The binding is then
  # real but it lands in the WRONG scope: the body is evaluated in the
  # comprehension's copy, so the body cannot see it -- and the binding leaks
  # out of the comprehension, which the toolchain does not allow (settle row C
  # is REJECTED by `moon check`).
  #
  # So this mutation breaks the scope in BOTH directions at once, and that is
  # what makes it worth a slot of its own: M6 loses the binding and M7 gives
  # it to the wrong scope.
  #
  # AND THE FIRST THING IT BREAKS IS NOT THE CONDITION'S OWN BINDING. The
  # LOOP VARIABLE only ever lived in the comprehension's environment, so moving
  # the condition's evaluation out of it puts the loop variable out of the
  # condition's scope -- and that is what the named test pins. The first run
  # of this gate named a different test here, and it went red for a reason one
  # step removed from the mutation's name: two undefined names on one line are
  # merged into a single finding, so the condition's own `nosuchfn` stopped
  # being the message that survived the merge.
  @{
    Name = 'M7 the condition is evaluated in the outer environment'
    File = $INTERP
    Find = @'
      match cond {
        Some(g) => {
          let _ = self.eval(g, cenv)
        }
        None => ()
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      match cond {
        Some(g) => {
          let _ = self.eval(g, env)
        }
        None => ()
      }
'@.Replace("`r`n", "`n")
    MustRed = '0504: the loop variable is in scope inside the condition'
  }

  # M8 THE CONDITION IS WALKED AFTER THE FRAME IS POPPED. The condition's
  # scope must END with the comprehension: the toolchain rejects a program that
  # reads the condition's binding after the comprehension closes (settle row C),
  # and a reader that lets it out invents a binding the language does not have.
  #
  # This is the one rule no other mutation in this gate breaks, and it has its
  # own test -- `0504: the name the condition binds does not escape the
  # comprehension` -- which expects the OUTER read to be undefined.
  @{
    Name = 'M8 the condition is walked after the frame is popped'
    File = $WALK
    Find = @'
      match cond {
        Some(g) => self.walk_expr(g)
        None => ()
      }
      self.walk_expr(body)
      self.pop_frame()
'@.Replace("`r`n", "`n")
    Repl = @'
      self.walk_expr(body)
      self.pop_frame()
      match cond {
        Some(g) => self.walk_expr(g)
        None => ()
      }
'@.Replace("`r`n", "`n")
    MustRed = '0504: the name the condition binds does not escape the comprehension'
  }
)

Write-MutationGateVerdict -Name '0504 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

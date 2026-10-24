# Mutation gate 0502 -- THE MATCH'S ARMS ARE READ, AND WHAT READING THEM EXPOSED.
#
# WHAT THIS INCREMENT IS. Before 0502 a `match`'s arms were consumed whole by
# `skip_braces` -- a region the frontend deliberately did not analyse. The
# region put a HOLE in the frame of the enclosing function, and 0501 had already
# established that a hole silenced the unused-local and unused-parameter
# checks for that WHOLE function. So six of the seven pinned corpora measured
# ZERO actionable findings.
#
# 0502 reads the arms: the pattern's names are parsed and bound, the guard is
# walked, the `with` constraint is read, and the body is walked. The findings
# come back -- and reading the arms also exposed SIX FALSE POSITIVES, each from
# a different mechanism, on code `moon check` accepts.
#
# THE MEASUREMENT THIS GATE EXISTS UNDER, because a rule nobody has measured is
# a guess. Reading the arms surfaced 14 candidate findings across the corpora;
# 13 of them were FALSE POSITIVES from 6 mechanisms, and exactly ONE was true:
#
#   moonbit_labeler  app_moui/rasterizer.mbt:489
#     local variable 'd_off' assigned but may not be used
#
# The six mechanisms, and where each was measured:
#
#   1. `as` MAY START A NEW LINE            async  src/fs/watch.mbt:216,222,233
#   2. A DESTRUCTURING LET'S INITIALISER    core   rechar_set.mbt:202,214
#   3. A SAME-PACKAGE TYPE'S METHOD         core   immut/vector/invariants_wbtest.mbt:354,363,366
#   4. A STRUCT LITERAL'S FIELD VALUES      moui   views/text/text_input_apply.mbt:166
#   5. AN ASSIGNMENT INTRODUCES NO BINDING  async  src/process/windows.mbt:105
#   6. A `with` CONSTRAINT READS            core   builtin/option.mbt:50
#
# EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED. A mutation that kills
# some other test is not evidence: the test named here is the one that pins the
# rule, so the kill is the rule's own.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE, and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$WALK = 'src\walk\walk.mbt'
$SA = 'src\sa\main.mbt'

Invoke-MutationGate -Name '0502' -Target 'wasm' -Mutations @(

  # M1 THE `as` CONTINUATION IS DROPPED. A cast is a POSTFIX operator and the
  # toolchain reads it across a line break -- settled with the compiler as the
  # oracle in `_verify/settle_0502_as.ps1`, 6/6, with a canary that is REJECTED
  # and a negative control that is REJECTED. Without the continuation the `as`
  # is left in the token stream and read as a NAME, and the analyzer reports
  # `no visible binding for 'as'` on code `moon check` accepts.
  @{
    Name = 'M1 the `as` continuation is dropped'
    File = $PARSER
    Find = @'
      if self.at_name("as") {
        continue
      }
      self.p = save
'@.Replace("`r`n", "`n")
    Repl = @'
      self.p = save
'@.Replace("`r`n", "`n")
    MustRed = '0502b: a cast may start a new line'
  }

  # M2 THE `with` CONSTRAINT'S RIGHT-HAND SIDE IS NOT COLLECTED AS A READ.
  # `with t = default` READS `default` and binds `t`; a reader that treats the
  # right-hand side as neither leaves the parameter with no read at all, which
  # is `parameter 'default' may not be used` on code `moon check` compiles.
  # Measured: moonbitlang/core `builtin/option.mbt:50`.
  @{
    Name = 'M2 the `with` constraint''s right-hand side is not collected'
    File = $PARSER
    Find = @'
          match self.peek() {
            TName(n) => reads.push(n)
            _ => ()
          }
          let _ = self.bump()
'@.Replace("`r`n", "`n")
    Repl = @'
          let _ = self.peek()
          let _ = self.bump()
'@.Replace("`r`n", "`n")
    MustRed = '0502b: a with constraint reads its right-hand side'
  }

  # M3 THE `with` CONSTRAINT'S LEFT-HAND SIDE IS A READ, NOT A BINDING. `with
  # t = default` BINDS `t` to the matched value; a reader that swept the whole
  # constraint up as reads would resolve a name that was never bound.
  #
  # THE ROW THIS NAMES IS NOT THE CORPUS SHAPE, and the reason is in the row:
  # the corpus shape binds `t` twice -- once by `Some(t)` and once by the
  # constraint -- so it cannot tell the two readings apart. The row uses a
  # shape where the constraint is the ONLY binder.
  @{
    Name = 'M3 the `with` constraint''s left-hand side is a read, not a binding'
    File = $PARSER
    Find = @'
        let (cn, _) = self.expect_name("constraint name")
        names.push(cn)
        self.expect(TAssign, "'='")
'@.Replace("`r`n", "`n")
    Repl = @'
        let (cn, _) = self.expect_name("constraint name")
        reads.push(cn)
        self.expect(TAssign, "'='")
'@.Replace("`r`n", "`n")
    MustRed = '0502b: a with constraint''s left-hand side is a pattern binding'
  }

  # M4 THE NOTICE COMES BACK EVEN THOUGH THE ARMS WERE READ. The notice said
  # "read but not analysed", which was TRUE when the arms were skipped and is
  # FALSE now. A match that is read and still announces itself as an
  # exclusion puts the hole back: the notice is what silences the frame audit.
  @{
    Name = 'M4 the notice comes back although the arms were read'
    File = $PARSER
    Find = @'
      } else {
        { span: sp, kind: @ast.EMatch(subject, arms), }
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      } else {
        self.note_skip(
          "match expression is outside the analyzed subset; it was read but not analysed",
          sp,
        )
        { span: sp, kind: @ast.EMatch(subject, arms), }
      }
'@.Replace("`r`n", "`n")
    MustRed = '0502: a match is no longer a deliberate exclusion'
  }

  # M5 THE ARM BODY IS NOT WALKED. This is the headline claim of the whole
  # increment: a binding read ONLY inside an arm body is not dead, because the
  # arm body is real code that reads it. Without the walk every such binding
  # is reported -- the false positive that hurts a user on correct code.
  @{
    Name = 'M5 the arm body is not walked'
    File = $WALK
    Find = @'
        }
        for st in arm.body {
          self.walk_stmt(st)
        }
      }
    }
    ETuple(elems) =>
'@.Replace("`r`n", "`n")
    Repl = @'
        }
      }
    }
    ETuple(elems) =>
'@.Replace("`r`n", "`n")
    MustRed = '0502: a local read only inside a match arm is not reported'
  }

  # M6 THE GUARD IS NOT WALKED. `pattern if cond => body` -- the condition is
  # an EXPRESSION that runs before the body, and it is real code whose reads
  # are real. A parameter read only by a guard is not dead.
  @{
    Name = 'M6 the guard is not walked'
    File = $WALK
    Find = @'
        match arm.cond {
          Some(g) => self.walk_expr(g)
          None => ()
        }
'@.Replace("`r`n", "`n")
    Repl = @'
        match arm.cond {
          Some(_) => ()
          None => ()
        }
'@.Replace("`r`n", "`n")
    MustRed = '0502: a parameter read only inside a match arm''s guard is not reported'
  }

  # M7 A PATTERN'S NAME IS BOUND AS AN ORDINARY BINDING. `bind_pattern` puts a
  # name in the frame WITHOUT putting it in the audit list, because a pattern
  # binding is not an ordinary local and a constructor head is not a variable
  # at all. Through `bind` instead, `Some(v)` would report two unused locals
  # -- `v` and `Some` -- on code `moon check` accepts.
  @{
    Name = 'M7 a pattern''s name is bound as an ordinary binding'
    File = $WALK
    Find = @'
        for b in arm.bindings {
          if b != "" {
            self.bind_pattern(b, arm.span)
          }
        }
        // A `with` CONSTRAINT READS the names of its right-hand side. Measured on
'@.Replace("`r`n", "`n")
    Repl = @'
        for b in arm.bindings {
          if b != "" {
            self.bind({ name: b, tyann: "", param: false, decl_span: arm.span, })
          }
        }
        // A `with` CONSTRAINT READS the names of its right-hand side. Measured on
'@.Replace("`r`n", "`n")
    MustRed = '0502: a pattern''s names are not reported as unused locals'
  }

  # M8 THE `with` CONSTRAINT'S READS ARE NEVER RESOLVED. The parser collects
  # the names the constraint reads; the WALK is what turns them into reads.
  # Collect without resolving leaves the parameter unread, and the other half
  # of M2 is exactly that half.
  @{
    Name = 'M8 the `with` constraint''s reads are never resolved'
    File = $WALK
    Find = @'
        for r in arm.reads {
          self.resolve(r, arm.span)
        }
'@.Replace("`r`n", "`n")
    Repl = @'
        for r in arm.reads {
          let _ = r
        }
'@.Replace("`r`n", "`n")
    MustRed = '0502b: a with constraint reads its right-hand side'
  }

  # M9 A DESTRUCTURING LET'S INITIALISER IS DISCARDED. `let (lo, l) = { let p
  # = ..; p }` -- the inner `let p` is a real binding and the tail of that
  # block reads it. The collector threw the initialiser away, so the frame
  # never learned `p`. Measured: moonbitlang/core
  # `internal/regex_engine/shared_types/rechar_set/rechar_set.mbt:202,214`.
  @{
    Name = 'M9 a destructuring let''s initialiser is discarded'
    File = $WALK
    Find = @'
      SLetDestruct(names, init) => {
        for n in names {
          bind_add(bs, { name: n, tyann: "", param: false, decl_span: s.span, })
        }
        collect_expr_bindings(bs, init)
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      SLetDestruct(names, _) => {
        for n in names {
          bind_add(bs, { name: n, tyann: "", param: false, decl_span: s.span, })
        }
      }
'@.Replace("`r`n", "`n")
    MustRed = '0502b: a destructuring let''s initialiser binds'
  }

  # M10 A STRUCT LITERAL'S FIELD VALUES ARE NOT COLLECTED. A field value is an
  # expression, and an expression can carry a binding inside it. The gap was
  # invisible until 0502 read match arms, because a match nested inside a
  # struct-literal field is the shape that puts a binding under a collector
  # that never descends. Measured: wzzc-dev/moui 0.1.12
  # `views/text/text_input_apply.mbt:166`.
  @{
    Name = 'M10 a struct literal''s field values are not collected'
    File = $WALK
    Find = @'
    EStruct(_, fields) =>
      for f in fields {
        let (_, v) = f
        collect_expr_bindings(bs, v)
      }
'@.Replace("`r`n", "`n")
    Repl = @'
    EStruct(_, fields) =>
      for f in fields {
        let (_, v) = f
        let _ = v
      }
'@.Replace("`r`n", "`n")
    MustRed = '0502b: a struct literal''s field values are collected'
  }

  # M11 AN ASSIGNMENT INTRODUCES A BINDING AGAIN. An assignment MUTATES a
  # binding; it does not create one. In the scope that DECLARED the name the
  # old arm was a no-op, so it only ever did something in the one case where
  # it was wrong: an assignment to a name bound in an ENCLOSING scope, where
  # the collector invented a shadow the language does not have. Measured:
  # moonbitlang/async 0.22.4 `src/process/windows.mbt:105`.
  @{
    Name = 'M11 an assignment introduces a binding again'
    File = $WALK
    Find = @'
      SAssign(_, rhs) => collect_expr_bindings(bs, rhs)
'@.Replace("`r`n", "`n")
    Repl = @'
      SAssign(target, rhs) => {
        match target.assigned_base() {
          Some(b) =>
            bind_add(bs, {
              name: b,
              tyann: "",
              param: false,
              decl_span: target.span,
            })
          None => ()
        }
        collect_expr_bindings(bs, rhs)
      }
'@.Replace("`r`n", "`n")
    MustRed = '0502b: a local read inside a nested local fn is not a dead local'
  }

  # M12 THE METHOD SEGMENTS ARE NEVER RECORDED. A type's method may be called
  # UNQUALIFIED inside the package that declares the type, so the METHOD
  # SEGMENT of every `Type::method` the package declares is recorded as a
  # value of that package's table. Measured: moonbitlang/core
  # `immut/vector/vector.mbt:68` declares `Vector::makei` and
  # `immut/vector/invariants_wbtest.mbt:354,363,366` calls `makei(..)`.
  @{
    Name = 'M12 the method segments are never recorded'
    File = $SA
    Find = @'
pub fn add_method_segments(tab : @core.IfaceSymTab) -> Unit {
  for seg in method_segments(tab) {
    tab.add_value(seg)
  }
}
'@.Replace("`r`n", "`n")
    Repl = @'
pub fn add_method_segments(tab : @core.IfaceSymTab) -> Unit {
  for seg in method_segments(tab) {
    let _ = seg
  }
}
'@.Replace("`r`n", "`n")
    MustRed = '0502: a method is recorded under its bare name'
  }
)

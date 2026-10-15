# Mutation gate 0447 -- a RE-EXPORTED TYPE carried its name but not its MEMBERS.
#
# On the harness: no runner of its own, all rules from `_verify/mutate_lib.ps1`.
#
# THE DEFECT, and it was the last 2 actionable findings in existence across the
# six corpora. moonbit-community/proton 0.3.4 `facade_notification.mbt:12,14`
# writes `@async.CondVar::Cond()` and was reported `undefined function
# '@async.CondVar::Cond'` on both. moonbitlang/async 0.22.4 re-exports the type
# under that name -- `pub using @cond_var {type Cond as CondVar}`,
# `src/pkg.generated.mbti:111` -- and `@cond_var/pkg.generated.mbti` declares
# `type Cond` with `pub fn Cond::Cond() -> Self`.
#
# BOTH HALVES WERE ALREADY IN THE TABLE. The re-exported NAME, because the
# `using` branch pushed it into `declared`; `Cond::Cond`, because `@cond_var`'s
# own interface is read. Nothing connected them. `has_value` tried the exact key
# and then `unqualified`, so `@async.CondVar::Cond` became `CondVar::Cond`, found
# nothing, and reported a name written down two files away.
#
# THE RULE, settled with the TOOLCHAIN in `_verify/settle_0447_condvar_alias.ps1`
# (6/6, three negative controls firing). A constructor IS callable through an
# aliased type re-export, cross-package -- and a name that does not exist is
# STILL rejected through it, `[4029]` for a member and `[4032]` for a type.
#
# THAT SECOND HALF IS THE WHOLE GATE. It is what makes this a LINK rather than a
# suppression, and M2 is the mutation that would turn it into one. A fix that
# silenced every `@mod.X::m` reaching a re-exported name would also have taken
# these two findings to zero, on all six corpora, with a green suite and nothing
# to distinguish it from this one. M2 exists to make that version red.
#
#   M1  The alias rewrite drops the MEMBER, keeping only the type it aliases.
#   M2  The link forgives ANY member -- the suppression the settle forbids.
#   M3  The re-export stops RECORDING the alias.
#   M4  `merge` drops the alias map on the way through.
#   M5  The redundant bare form is re-added. Declared SURVIVED, with the
#       measurement, because both callers apply `unqualified` to every candidate
#       and `unqualified("@cond_var.Cond::Cond")` IS `Cond::Cond`.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name 'M1..M5' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the alias rewrite keeps the type but drops the member'
    File = 'src\core\core.mbt'
    Find = @'
            let full = target + "::" + tail
'@.Replace("`r`n", "`n")
    Repl = @'
            let full = target
'@.Replace("`r`n", "`n")
    MustRed = '0447: a re-exported type''s members resolve through the re-exported name'
    Prove = @'
Rewrites `@async.CondVar::Cond` to `@cond_var.Cond`, which is a TYPE and lives in
`types`, never in `values` -- so the lookup misses and the original finding comes
back. `let full = ""` was the obvious mutation and does not compile here: an empty
string is still a valid candidate, so it would have measured something other than
this. `target` alone is the minimal statement of the same wrong idea.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M2 the link forgives any member -- the suppression the settle forbids'
    File = 'src\core\core.mbt'
    Find = @'
  for alt in self.alias_forms(name) {
    if self.values.contains(alt) || self.values.contains(unqualified(alt)) {
      return true
    }
  }
  false
}
'@.Replace("`r`n", "`n")
    Repl = @'
  for alt in self.alias_forms(name) {
    let _ = alt
    return true
  }
  false
}
'@.Replace("`r`n", "`n")
    MustRed = '0447: the alias link silences nothing that is not there'
    Prove = @'
THE ONE THAT MATTERS MOST, because it is the version of this fix that looks like
it works.

`moon check` was measured rejecting `@p0447.CondVar::Nope()` with `[4029]` and a
nonexistent type through the same re-export with `[4032]`. So the toolchain does
NOT forgive an arbitrary member through an aliased re-export, and an analyzer that
does is wrong in the other direction.

This mutation passes the corpus check. It takes proton 0.3.4 from actionable 2 to
0 exactly as the real fix does, because the two findings it silences really do
exist. Nothing in the six corpora can tell this mutation from the fix -- which is
why the control test, not the corpus, is what kills it.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M3 the re-export stops recording the alias'
    File = 'src\moonfiles\moonfiles.mbt'
    Find = @'
                if src_mod != "" && a != "" && o != "" && o != a {
'@.Replace("`r`n", "`n")
    Repl = @'
                if src_mod != "" && a != "" && o != "" && o == a {
'@.Replace("`r`n", "`n")
    MustRed = '0447: a re-exported type''s members resolve through the re-exported name'
    Prove = @'
`o == a` is false for every real re-export -- that is what "renamed" means -- so the
push never runs and the alias map stays empty. `parse_iface` then behaves exactly
as it did before this increment: the re-exported name still enters `declared`, so
`@async.CondVar` resolves as a TYPE, and nothing else does.

That half is the trap. Deleting the `declared.push` beside it would kill more tests
and teach less, because the type would then be unresolvable and the finding would
look like a different bug. The push into `declared` is correct and predates this
increment; the alias link is what was missing.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M4 merge drops the alias map on the way through'
    File = 'src\core\core.mbt'
    Find = @'
  for k, v in other.aliases {
    if !self.aliases.contains(k) {
      self.aliases.set(k, v)
    }
  }
  self
}
'@.Replace("`r`n", "`n")
    Repl = @'
  self
}
'@.Replace("`r`n", "`n")
    MustRed = '0447: the alias survives both merge and union'
    Prove = @'
`collect_iface_symtabs` in `sa/main.mbt` builds the cross-file table with `merge`,
so a table that arrives through it and loses its aliases produces the finding back
with no other change to point at. `union` is the one `collect_private_symtabs` uses
and is anchored by its own `out` return, so this mutation touches `merge` alone and
the test asserts both.

The anchor includes the closing `self`/`}` rather than the loop text, because the
same three lines appear in `union` a few lines below.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M5 the redundant bare form is re-added to alias_forms'
    File = 'src\core\core.mbt'
    Find = @'
            if !out.contains(full) {
              out.push(full)
            }
'@.Replace("`r`n", "`n")
    Repl = @'
            if !out.contains(full) {
              out.push(full)
            }
            let bare = unqualified(full)
            if bare != full && !out.contains(bare) {
              out.push(bare)
            }
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = @'
EXPECTED TO SURVIVE, and the measurement is the claim rather than an excuse.

Both callers ask `contains(alt) || contains(unqualified(alt))`. For the candidate
this re-adds, `unqualified("Cond::Cond")` IS `Cond::Cond` -- the two forms are the
same string. So the loop already returns on the FIRST candidate and the second is
never examined. The mutation adds an entry that cannot be reached, and a dead entry
cannot change an answer.

This is the shape the harness is built for: an equivalent mutant gets declared with
its proof instead of a test being invented for behaviour the code does not have.
The first draft of `alias_forms` DID return both forms, and this same mutation
against that draft is what showed the second one was dead -- so the code was
simplified to one form and the note that says why stayed.
'@.Replace("`r`n", "`n")
  }
)

Write-MutationGateVerdict -Name '0447'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

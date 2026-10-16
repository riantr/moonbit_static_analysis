# Mutation gate 0463 -- a BODY-LESS suberror's own name is a visible value.
#
# WHAT THIS PINS. `priv suberror Boom` is a complete declaration whose name is its
# only constructor, and `raise Boom` is how one raises it. Before this increment
# every such use was reported:
#
#     undefined name 'Boom'
#
# The mechanism is one line. `harvest_ctors` is reachable only from the BRACED
# branch of the `suberror` dispatch, so a body-less suberror's own name never
# entered `enum_ctors` -- and `enum_ctors` is what seeds the module frame as VALUES
# (`walk.mbt:1197`, `infer.mbt:880`).
#
# THE GRANMAR FACT, settled against the toolchain in 10/10
# (`_verify/settle_0463_suberror_bodyless.ps1`) with five failure-capable controls:
#
#     priv suberror Boom                    ACCEPT, and `raise Boom`   ACCEPT
#     priv suberror Boom derive(Debug)      ACCEPT, and `raise Boom`   ACCEPT
#     priv suberror Boom of String          REJECT [3002]
#     priv suberror Boom(String)            REJECT [3002]
#     priv suberror Boom(msg : String)      REJECT [3002]
#     raise FormatError on a BRACED suberror REJECT [4021]
#     raise InvalidBlock on a BRACED suberror ACCEPT
#
# => 判据: the last row pair is the one that makes this a RULE and not a patch. A
# body-less suberror's own name IS raisable and a braced one's is NOT, so the
# harvest is scoped by the presence of a body -- and the two rows above it are why
# "the token after the keyword" was not good enough: `suberror Boom derive(..)` and
# the three rejected payload forms mean the reader has to ask what was DECLARED.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0463' -Target 'js' -Mutations @(

  # M1 IS THE GATE. The harvest call is gone, which is the pre-0463 parser verbatim
  # and the exact state three `pipeline_0460_test.mbt` tests were failing in.
  @{
    Name = 'M1 the body-less harvest is removed entirely'
    File = $PARSER
    Find = "        p.harvest_bodyless_suberror()`n"
    Repl = ''
    MustRed = "0463: a body-less suberror's own name is a visible value"
  }

  # M2 THE HARVEST IS THERE BUT NEVER FIRES -- same verdict by a different route,
  # and the mutation that catches an edit which "simplifies" the call into
  # something equivalent-looking. This one is inert rather than absent, so the code
  # still reads as though the rule were implemented.
  @{
    Name = 'M2 the body-less harvest is inert'
    File = $PARSER
    Find = 'match declared_name_after_kw(self.toks, self.p) {'
    Repl = 'match declared_name_after_kw(self.toks, self.p + 1) {'
    MustRed = "0463: a body-less suberror's own name is a visible value"
  }

  # M3 THE RULE GROWS TO THE BRACED FORM. `raise FormatError` on a braced suberror
  # is [4021] in MoonBit, so harvesting the type name there would suppress a
  # finding that is CORRECT. This is the mutation the scope-bound test exists for,
  # and it is the one an over-eager "make suberror names uniform" edit would make.
  @{
    Name = 'M3 the harvest is applied to the braced form too'
    File = $PARSER
    Find = "      if p.next_is_lbrace() {`n        p.skip_decl_braced(kw, sp)`n      } else {"
    Repl = "      if p.next_is_lbrace() {`n        p.harvest_bodyless_suberror()`n        p.skip_decl_braced(kw, sp)`n      } else {"
    MustRed = '0463: a braced suberror''s own name is still not a constructor (bound)'
  }

  # M4 AND THE RULE GROWS TO `enum`, by hooking the shared braced branch that
  # `struct` / `enum` / `trait` / `impl` / `extend` / `test` all take. An enum's type
  # name is not a constructor -- `enum Shape { Circle }` does not make `Shape` a
  # value -- so this would suppress a real finding as surely as M3 does.
  @{
    Name = 'M4 the harvest is applied to enum declarations'
    File = $PARSER
    Find = "      p.skip_decl_braced(kw, sp)`n    } else if kw == `"type`" || kw == `"const`" || kw == `"derive`" {"
    Repl = "      p.harvest_bodyless_suberror()`n      p.skip_decl_braced(kw, sp)`n    } else if kw == `"type`" || kw == `"const`" || kw == `"derive`" {"
    MustRed = '0463: an enum''s own name is not a constructor'
  }
)

Write-MutationGateVerdict -Name '0463'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

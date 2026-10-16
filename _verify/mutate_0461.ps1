# Mutation gate 0461 -- suberror BODIES arm the sibling-table harvest, and an enum
# variant may carry a DISCRIMINANT.
#
# TWO GAPS, ONE MESSAGE. 0461 was first described as "one gap, not two" and that
# description was wrong; the corpus is what showed it. The findings were:
#
#     async  decoder.mbt   x10  no visible binding for 'InvalidBlock'
#                                      ... 'InvalidTrailer', 'NeedMoreInput'
#     proton native.mbt    x3   undefined name 'RuntimeActive'
#                                      ... 'RuntimeDestroyed', 'WindowLive'
#
#     priv suberror FormatError { InvalidBlock(String) }   <- gap 1: the BODY
#     priv enum RuntimeLifecycleState { RuntimeActive = 0 } <- gap 2: the `=`
#
# Gap 1 is an ARMING: `collect_declared_names` opened an enum body but not a
# suberror body, so the TYPE registered and its CONSTRUCTORS did not. Gap 2 is a
# TERMINATOR: `ends_variant` accepted `(`, `,`, `}`, a newline and `;` after a
# variant name -- and not `=`.
#
# THE GRAMMAR, settled 7/7 in `_verify/settle_0461_constructors.ps1` with the
# positive control AND a name that must still be refused:
#
#     enum variant used bare        ACCEPT
#     suberror constructor used bare ACCEPT
#     a name that is neither        REJECT
#     enum variant WITH a discriminant  ACCEPT   <- the `=`
#
# => 判据: a blocker MESSAGE is not a construct. "13 files report a constructor as
# undefined" is one sentence covering two defects in two different functions, one
# of which was a missing arm in a table and the other a missing case in a match.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0461' -Target 'js' -Mutations @(

  # M1 IS THE GATE. The suberror no longer arms the body harvest, which is the
  # pre-0461 `collect_declared_names` verbatim: the TYPE registers and every
  # CONSTRUCTOR does not.
  @{
    Name = 'M1 suberror bodies do not arm the sibling harvest'
    File = $PARSER
    Find = 'if n == "enum" || n == "suberror" {'
    Repl = 'if n == "enum" {'
    MustRed = '0461: a suberror constructor reaches a sibling file'
  }

  # M2 THE ARMING IS THERE BUT NEVER FIRES -- `enum_pending` is cleared on the same
  # line it is set, so the code reads as armed and is inert. This is the mutation
  # that catches an edit which restructures the arming into an equivalent-looking
  # shape.
  @{
    Name = 'M2 the sibling harvest is armed and immediately disarmed'
    File = $PARSER
    Find = "            enum_pending = true`n          }"
    Repl = "            enum_pending = false`n          }"
    MustRed = '0461: a suberror constructor reaches a sibling file'
  }

  # M3 THE DISCRIMINANT IS REFUSED AGAIN. proton declares
  # `RuntimeActive = 0` in `internal/native/types.mbt:1409` and uses the variant
  # bare in the sibling `native.mbt`, so this is three findings in a second corpus
  # hidden behind the same message as M1.
  @{
    Name = 'M3 an enum variant discriminant is refused again'
    File = $PARSER
    Find = 'TLParen | TComma | TRBrace | TNewline | TSemi | TAssign => true'
    Repl = 'TLParen | TComma | TRBrace | TNewline | TSemi => true'
    MustRed = '0461: an enum variant with a discriminant reaches a sibling file'
  }

  # M4 THE HARVEST'S OWN DEPTH GUARD IS DROPPED, so the harvest stops tracking
  # parentheses and reads a multi-line payload's TYPE as a variant. The terminator
  # rule alone cannot catch this, which is the point: `ends_variant` is consulted
  # only AFTER `paren == 0` has already been established.
  #
  # This mutation was FIRST WRITTEN as "drop the terminator entirely"
  # (`_ => true`) and SURVIVED 681/681. That is a real observation and not a
  # passing one, so it is recorded rather than quietly replaced:
  #
  #   `starts_variant` only looks BACKWARD -- at the preceding `|` / `{` / `,`, or
  #   at a line change -- and `ends_variant` is the sole FORWARD guard. On a legal
  #   enum or suberror body every name at bracket depth 1 and paren depth 0 that
  #   sits at a variant position is a variant, and a payload is always
  #   parenthesised or braced, so removing the terminator changes nothing on any
  #   input the toolchain accepts.
  #
  # OPEN, NOT ESTABLISHED: that argument is reasoning about the grammar, not a
  # measurement of it, and rule 5 is explicit that a survivor verdict must rest on
  # REACHABILITY rather than on the absence of a covering test. Settling it needs a
  # settle that enumerates legal enum-body continuations and shows each is already
  # excluded by the depth/paren guards. Until that is written, the honest status of
  # `ends_variant`'s independence is UNKNOWN -- and it is the forward guard, so
  # that matters.
  @{
    Name = 'M4 the parenthesis guard is dropped from the sibling harvest'
    File = $PARSER
    Find = 'TLParen => if enum_body && depth == 1 { paren += 1 }'
    Repl = 'TLParen => if false { paren += 1 }'
    MustRed = '0461: a multi-line payload type is not harvested as a constructor'
  }
)

Write-MutationGateVerdict -Name '0461'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0

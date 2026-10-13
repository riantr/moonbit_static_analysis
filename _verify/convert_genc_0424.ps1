# Splice mutate_0424 onto the shared harness, keeping its header verbatim.
#
# Gen C gates (0423, 0424) are FUNCTION-PER-MUTATION: no table, one
# `Invoke-Mutation 'name' 'file' 'find' 'replace' 'expect'` call each, plus their own
# copy of the runner. Converting means transposing the calls into a table -- the
# arguments are transcribed by hand, the prose header is NOT rewritten.
#
# The header is spliced out mechanically (everything before `function
# Invoke-Mutation`, minus the runner's own scaffolding lines) because retyping it
# would be transcription risk on the part of the file that carries the reasoning.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\convert_genc_0424.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$src = Join-Path $root '_verify\mutate_0424.ps1'
$dst = Join-Path $root '_verify\mutate_0424_converted.ps1'
$enc = New-Object System.Text.UTF8Encoding($false)

$lines = [System.IO.File]::ReadAllLines($src)
$fnIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^function Invoke-Mutation') { $fnIdx = $i; break }
}
if ($fnIdx -lt 0) { Write-Output 'ABORT: no Invoke-Mutation function found.'; exit 1 }

# Keep the prose; drop the scaffolding the harness now owns.
$scaffolding = '^\$ErrorActionPreference\s*=', '^\$root\s*=', '^Set-Location\s+\$root', '^\$results\s*=\s*@\(\)', '^\$failed\s*=', '^\$nl\s*='
$head = @()
for ($i = 0; $i -lt $fnIdx; $i++) {
  $skip = $false
  foreach ($s in $scaffolding) { if ($lines[$i] -match $s) { $skip = $true } }
  if (-not $skip) { $head += $lines[$i] }
}
# Trim trailing blanks left by the removals.
while ($head.Count -gt 0 -and [string]::IsNullOrWhiteSpace($head[$head.Count - 1])) { $head = $head[0..($head.Count - 2)] }

$NOTE = @'

# -----------------------------------------------------------------------------
# CONVERTED to ``_verify/mutate_lib.ps1``. Like 0.4.23's, this gate was already
# close -- its runner had the SHA256 restore, the ``Total tests:`` COMPILE-ERR
# judgement, NO-OP-as-failure and ``Expect`` support -- and was written as
# function-per-mutation rather than a table. The prose above is VERBATIM; the seven
# calls were transposed into a table, arguments unchanged.
#
# What it was missing, and what the harness adds:
#
#   - a green BASELINE, ASSERTED. The old runner went straight to the first
#     mutation. With no baseline, a suite that was already red produced seven
#     verdicts and -- because every mutation would then also be red -- seven
#     apparent kills. The same false-green shape 0.4.29 hit in the other direction.
#   - PRE-FLIGHT, so a pattern that no longer matches stops the gate before any
#     mutation is applied rather than being discovered one at a time.
#
# The original runner's line-ending handling is kept by the harness for the reason
# its comment gave: ``moon fmt`` rewrote the tree from LF to CRLF once, a literal
# multi-line pattern then matched NOTHING, and every mutation reported NO-OP. The
# harness normalises to LF and writes back in whatever style the file already used.
'@

$TABLE = @'

$PARSER = 'src\parser\parser.mbt'
$WALK   = 'src\walk\walk.mbt'
$INFER  = 'src\types\infer.mbt'
$INTERP = 'src\interp\interp.mbt'

$mutations = @(
  # M1 -- the statement dispatch. Without it `raise` falls through to the expression
  # reader; 65 findings across the corpora, 56 of them proton's.
  @{
    Name = 'M1 raise statement dispatch removed'
    File = $PARSER
    Find = 'if self.at_name("raise") {
    return self.parse_raise_stmt()
  }
'
    Repl = ''
  }

  # M2 -- `SRaise(None)` unconditionally. The error value is left at the cursor and
  # the next statement gets read as if it were the payload.
  @{
    Name = 'M2 the raise payload never parsed'
    File = $PARSER
    Find = '{ span: sp, kind: @ast.SRaise(Some(self.parse_expr())), }
}'
    Repl = '{ span: sp, kind: @ast.SRaise(None), }
}'
  }

  # M3 -- THE QUIET FAILURE. `raise` must not become the one place in the language
  # where a real defect goes unnoticed, so `raise E(nosuchfunction())` still has to
  # find `nosuchfunction`. A mutation that merely stops looking is the failure mode
  # a coverage number cannot see, which is why this is its own gate rather than
  # folded into M2.
  @{
    Name = 'M3 walk stops walking the raise payload'
    File = $WALK
    Find = 'SRaise(e) =>
      match e {
        Some(x) => self.walk_expr(x)
        None => ()
      }'
    Repl = 'SRaise(_) => ()'
  }

  # M4 -- the same quiet failure one lens down. M3 and M4 are separate because a
  # change could plausibly fix one and not the other, and only one of them would
  # fail a test that looked at findings from a single lens.
  @{
    Name = 'M4 type lens stops checking the payload'
    File = $INFER
    Find = 'SRaise(e) =>
      match e {
        Some(x) => {
          let _ = self.ty_of(x, TUnknown)
        }
        None => ()
      }'
    Repl = 'SRaise(_) => ()'
  }

  # M5 -- THE LOUD FAILURE, and the one with real corpus consequences. `SRaise`
  # exists precisely because `SReturn` would be wrong here, and the observable
  # difference is the terminator: with this arm gutted the statements after a
  # `raise` look reachable and every dead-code report after a raise disappears.
  @{
    Name = 'M5 a raise does not terminate the frame'
    File = $INTERP
    Find = 'SRaise(_) => {
      self.ret_vals.push(ABottom)
      self.flow = FReturn
    }'
    Repl = 'SRaise(_) => ()'
  }

  # M6 -- a raise produces NO value. Pushing anything else invents a return value
  # the source never had, and it lands in `ret_vals`, which is where the rendered
  # signature's return type comes from.
  @{
    Name = 'M6 a raise pushes a value'
    File = $INTERP
    Find = 'SRaise(_) => {
      self.ret_vals.push(ABottom)
      self.flow = FReturn
    }'
    Repl = 'SRaise(_) => {
      self.ret_vals.push(AAny)
      self.flow = FReturn
    }'
  }

  # M7 -- the termination-set guard. A bare `raise` with nothing after it -- on its
  # own line, or closing a block with no semicolon -- must produce `SRaise(None)`.
  # Without the guard the reader goes on to parse whatever follows as the error
  # value, which in the corpus is the next real statement.
  @{
    Name = 'M7 the bare-raise termination guard removed'
    File = $PARSER
    Find = 'if self.at(TNewline) || self.at(TSemi) || self.at(TRBrace) || self.at(TEOF) {
    return { span: sp, kind: @ast.SRaise(None), }
  }
'
    Repl = ''
  }
)

Invoke-MutationGate -Name '0.4.24' -Target 'js' -Mutations $mutations
Write-MutationGateVerdict -Name '0.4.24 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
'@

$out = @()
$out += ($head -join "`n")
$out += $NOTE
$out += "`n`$ErrorActionPreference = 'Stop'"
$out += ". (Join-Path `$PSScriptRoot 'mutate_lib.ps1')"
$out += $TABLE

$candidate = ($out -join "`n") + "`n"
$tmp = Join-Path $env:TEMP ('genc_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
[System.IO.File]::WriteAllText($tmp, $candidate, $enc)
$perr = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$null, [ref]$perr)
$bad = @($perr | Where-Object { $_ -ne $null })
if ($bad.Count -gt 0) {
  Write-Output ('ABORT: generated file does not parse -- ' + $bad[0].Message)
  exit 1
}
[System.IO.File]::WriteAllText($dst, $candidate, $enc)
Write-Output ("WROTE " + $dst)
Write-Output ("  header lines kept: " + $head.Count + " of " + $fnIdx)
Write-Output ("  parses: yes")
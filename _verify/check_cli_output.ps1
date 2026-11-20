param([switch]$SelfTest, [string]$Root = '', [string]$Doc = '')
$ErrorActionPreference = 'Continue'
# THE SHIPPED CLI EXAMPLE, as a gate.
#
# WHY THIS EXISTS. `src/cli/SKILL.md` SHIPS -- it lives inside `src/`, so it is in
# the published package -- and the README sends a reader to it. It documents what
# the CLI PRINTS, and it shows the output in two bare-fenced blocks.
#
# MEASURED 0620, and this is the defect that made this gate necessary. The
# document showed:
#
#     2:10 - error: undefined variable 'missing' (UndefinedName) [structural+type+behavior]
#
# and the tool prints:
#
#     2:10 - notice: undefined variable 'missing' (UndefinedName) [structural+type+behavior, MSA-002, low]
#
# TWO THINGS ARE WRONG IN THAT ONE LINE, and the first one is not cosmetic:
#
#   1. THE SEVERITY. The document says `error`; the tool says `notice`. And the
#      tool is right to say `notice`: an unresolved name may be a CROSS-FILE
#      VALUE, which is the very class 0616 measured and found to be 88.9 % of
#      this tree's unverified remainder. A reader who believed the document
#      would believe the analyzer reports a cross-file value as a hard error,
#      and it deliberately does not.
#   2. THE TAG. The document's tag is `[structural+type+behavior]`; the tool's
#      is `[structural+type+behavior, MSA-002, low]` -- the family id and the
#      confidence live in the tag now, and the document's own prose describes a
#      line format that no longer exists.
#
# AND THE MACHINE EXAMPLE HAS THE SAME SHAPE: the document shows ONE of the four
# findings the tool prints, with the same incomplete tag.
#
# WHY NOBODY NOTICED. 0618 fixed the ROOT `SKILL.md` -- a DIFFERENT file -- and
# the gate that derives the published numbers (`check_readme_links.ps1`) reads
# `README.md`, `README.zh.md`, `SKILL.md`, `CHANGELOG.md` and `CHANGELOG.zh.md`.
# `src/cli/SKILL.md` was read by NOTHING. A shipped document that shows the
# tool's output is a SECOND IMPLEMENTATION of what the tool prints, and a second
# implementation is a second thing that can disagree -- and this one already did.
#
# WHAT IT CHECKS, in one sentence: every line the shipped CLI skill file shows
# as TOOL OUTPUT is a line the tool actually prints.
#
# THE SCOPE IS THE BARE FENCES. The document uses ```sh for commands and
# ```moonbit for source, and the two BARE fences are the output. A command is
# not the tool's output and a source listing is not the tool's output, so only
# the bare fences are compared -- a wider rule would report failures on the
# shell commands, which are correct as written.
#
# HOW THE TOOL IS RUN. The gate runs the demo CLI from the wasm the release
# gate already builds (`moon build --target wasm` produces
# `_build\wasm\debug\build\src\cli\cli.wasm`), so the comparison is against the
# artifact this repository builds, not against a description of it. If the wasm
# is missing the gate BUILDS it with that same command -- no network, no
# fetch -- and refuses if it still cannot be run.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_cli_output.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_cli_output.ps1 -SelfTest

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$docPath = if ($Doc) { $Doc } else { Join-Path $root 'src\cli\SKILL.md' }

# --- the tool's own output ------------------------------------------------------
# RUN THE DEMO CLI. The wasm the release gate builds, run by `moonrun`, which is
# the same runner the release gate uses for every other artifact it reads.
function Get-CliOutput {
  param([string]$RootPath)
  $wasm = Join-Path $RootPath '_build\wasm\debug\build\src\cli\cli.wasm'
  $moonrun = Join-Path $env:USERPROFILE '.moon\bin\moonrun.exe'
  if (-not (Test-Path -LiteralPath $wasm)) {
    # THE BUILD IS THE SAME COMMAND THE RELEASE GATE RUNS, and it fetches
    # nothing: a gate whose result depends on the network is a gate whose
    # result depends on the network.
    $moon = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'
    if (-not (Test-Path -LiteralPath $moon)) { $moon = 'moon' }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $moon -C $RootPath build --target wasm 2>&1 | Out-Null
    $ErrorActionPreference = $prev
  }
  if (-not (Test-Path -LiteralPath $wasm)) { return $null }
  if (-not (Test-Path -LiteralPath $moonrun)) { return $null }
  # THE OUTPUT GOES TO A FILE, AND THE FILE IS READ AS UTF-8.
  #
  # MEASURED 0620, and this was a false failure that looked like a real one. A
  # DETACHED release gate has NO CONSOLE, and a PowerShell process with no
  # console decodes a native command's output with the ANSI code page -- 936 on
  # this machine -- so the CLI's UTF-8 Chinese arrived as mojibake and the
  # comparison was against mangled text. The gate reported a mismatch on a line
  # that IS a line the CLI prints.
  #
  # `Start-Process -RedirectStandardOutput` captures the BYTES: nothing decodes
  # them on the way to the file, and the file is read back as UTF-8. This is the
  # same reason the release gate's own `Scan-Tree` writes to a file.
  $dir = Join-Path $env:TEMP ('cliout_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $out = Join-Path $dir 'cli.txt'
  $err = Join-Path $dir 'cli.err'
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $proc = Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm) `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait -PassThru
  $code = $proc.ExitCode
  $ErrorActionPreference = $prev
  if ($code -ne 0) { return $null }
  # THE READ RETRIES, because `-Wait` waits for the PROCESS and not for the
  # redirected file's handle to be closed.
  $text = $null
  for ($i = 1; $i -le 20; $i++) {
    try {
      $text = [System.IO.File]::ReadAllText($out, [Text.Encoding]::UTF8)
      break
    } catch [System.IO.IOException] {
      if ($i -eq 20) { return $null }
      Start-Sleep -Milliseconds (100 * $i)
    }
  }
  if ($null -eq $text) { return $null }
  return $text
}

# A MESSAGE THAT SURVIVES THE CAPTURE. The release gate captures a DETACHED
# child's stdout through the ANSI code page, so a line that carries Chinese
# arrives mangled and cannot be grepped for. The offending line is therefore
# printed with its non-ASCII characters escaped -- the line is still exactly
# identifiable, and the message is readable on any machine's code page.
function Get-SafeText {
  param([string]$Text)
  if ($null -eq $Text) { return '' }
  if ($Text -cmatch '^[\x20-\x7E]*$') { return $Text }
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $Text.ToCharArray()) {
    $c = [int][char]$ch
    if ($c -lt 32 -or $c -gt 126) { [void]$sb.Append('\u' + $c.ToString('X4')) }
    else { [void]$sb.Append($ch) }
  }
  return $sb.ToString()
}

# --- the document's output blocks ------------------------------------------------
# THE BARE FENCES. A fence that names a language is a command or a source
# listing; a bare fence is the tool's output.
function Get-BareBlocks {
  param([string]$Text)
  $lines = $Text -split "`r?`n"
  $blocks = @()
  # THE FENCES ALTERNATE, and a fence that NAMES a language is closed by the
  # next bare fence -- so the state has to be tracked, not inferred. An earlier
  # shape of this function treated every fence line as an opening, and read the
  # CLOSING fence of a ```sh block as the OPENING of a bare one: the whole
  # command block was then compared against the tool's output, and the gate
  # reported 34 mismatches on a document with 2 wrong lines.
  $inBlock = $false
  $bare = $false
  $cur = $null
  foreach ($ln in $lines) {
    if (-not $inBlock) {
      if ($ln -match '^```(.*)$') {
        $lang = $Matches[1].Trim()
        $inBlock = $true
        $bare = ($lang -eq '')
        if ($bare) { $cur = New-Object System.Collections.Generic.List[string] }
      }
    } else {
      if ($ln -match '^```\s*$') {
        if ($bare) { $blocks += ,($cur.ToArray()) }
        $inBlock = $false
        $bare = $false
        $cur = $null
      } elseif ($bare) {
        $cur.Add($ln)
      }
    }
  }
  return $blocks
}

# THE COMPARISON. `-cnotcontains` and not `-notcontains`: PowerShell's string
# comparison is CASE-INSENSITIVE, and this is a comparison of the tool's bytes
# against the document's bytes. A case-insensitive match would pass a document
# that says `msa-002` where the tool says `MSA-002`.
function Get-MismatchedLines {
  param([string]$DocText, [string[]]$ToolLines)
  $blocks = Get-BareBlocks $DocText
  $bad = @()
  $bi = 0
  $checked = 0
  foreach ($b in $blocks) {
    $bi++
    foreach ($ln in $b) {
      $t = $ln.TrimEnd()
      if ($t.Trim() -eq '') { continue }
      $checked++
      if ($ToolLines -cnotcontains $t) {
        $bad += [pscustomobject]@{ Block = $bi; Line = $t }
      }
    }
  }
  return [pscustomobject]@{ Bad = $bad; Checked = $checked; Blocks = $blocks.Count }
}

# --- the self-test ---------------------------------------------------------------
# THE DEFECT IS IN THE DOCUMENT, so the copy that has to go red is a COPY OF THE
# DOCUMENT. The tool's output is the same in both runs -- it is the tool.
#
# THE CONTROL IS THE DOCUMENT AS IT STANDS, and it must be green: a self-test
# that only proves the gate can fail proves nothing about the gate.
if ($SelfTest) {
  Write-Output 'check the shipped CLI example -- SELF TEST'
  $bad = 0
  $checked = 0

  $toolOut = Get-CliOutput $root
  if ($null -eq $toolOut) {
    Write-Output '  FAIL: the demo CLI could not be run, so the self-test measured nothing.'
    Write-Output 'SELFTEST FAILED: 1 of 2 checks did not hold.'
    exit 1
  }
  $toolLines = @(($toolOut -split "`r?`n") | ForEach-Object { $_.TrimEnd() })

  if (-not (Test-Path -LiteralPath $docPath)) {
    Write-Output ('  FAIL: the shipped document ' + $docPath + ' does not exist.')
    Write-Output 'SELFTEST FAILED: 1 of 2 checks did not hold.'
    exit 1
  }
  $orig = [System.IO.File]::ReadAllText($docPath, [Text.Encoding]::UTF8)

  $dir = Join-Path $env:TEMP ('cliout_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $copy = Join-Path $dir 'SKILL.md'
  $enc = New-Object System.Text.UTF8Encoding($false)

  Write-Output ''
  Write-Output '--- the control: the shipped document as it stands ---'
  $ctl = Get-MismatchedLines $orig $toolLines
  $checked++
  if (($ctl.Bad.Count -eq 0) -and ($ctl.Checked -gt 0)) {
    Write-Output ('  OK: the control passes (' + $ctl.Checked + ' line(s) of output checked against the tool).')
  } else {
    Write-Output ('  FAIL: the control does NOT pass: ' + $ctl.Bad.Count + ' line(s) do not match, ' + $ctl.Checked + ' checked.')
    foreach ($m in $ctl.Bad) { Write-Output ('        block ' + $m.Block + ': ' + (Get-SafeText $m.Line)) }
    $bad++
  }

  Write-Output ''
  Write-Output '--- the defect: the document drifts from the tool ---'
  # THE MUTATION. Take a line the document shows AND the tool prints, and change
  # its severity word -- which is the shape of the real defect -- so the copy
  # says something the tool does not print.
  $mutated = $orig
  $target = ''
  foreach ($blk in (Get-BareBlocks $orig)) {
    foreach ($ln in $blk) {
      $t = $ln.TrimEnd()
      if ($t.Trim() -eq '') { continue }
      if ($toolLines -ccontains $t) { $target = $t; break }
    }
    if ($target -ne '') { break }
  }
  if ($target -eq '') {
    Write-Output '  FAIL: no line of the document is also a line of the tool, so the defect could not be injected.'
    $bad++
  } else {
    $variant = $target
    if ($variant.Contains('notice:')) { $variant = $variant.Replace('notice:', 'error:') }
    elseif ($variant.Contains('error:')) { $variant = $variant.Replace('error:', 'warning:') }
    elseif ($variant.Contains('warning:')) { $variant = $variant.Replace('warning:', 'notice:') }
    else { $variant = $variant + ' (mutated)' }
    $mutated = $orig.Replace($target, $variant)
    [System.IO.File]::WriteAllText($copy, $mutated, $enc)
    $def = Get-MismatchedLines $mutated $toolLines
    $checked++
    # THE MESSAGE IS COMPARED AS A LITERAL. `-like` reads `[` and `]` as a
    # character class, and a comparison that throws skips the check and prints
    # SELFTEST OK having checked nothing.
    $caught = $false
    try {
      $caught = ($def.Bad.Count -gt 0) -and ($def.Bad[0].Line -ceq $variant)
    } catch {
      Write-Output ('  FAIL: the check itself threw: ' + $_.Exception.Message)
      $caught = $false
    }
    if ($caught) {
      Write-Output ('  OK: the gate caught it and named the line: ' + (Get-SafeText $variant))
    } else {
      Write-Output ('  FAIL: the gate did NOT catch it (' + $def.Bad.Count + ' line(s) mismatched).')
      foreach ($m in $def.Bad) { Write-Output ('        block ' + $m.Block + ': ' + (Get-SafeText $m.Line)) }
      $bad++
    }
  }

  # AND EVERY CHECK RAN. A self-test that silently skipped one of its own checks
  # is the same green light that measured nothing.
  if ($checked -ne 2) {
    Write-Output ('  FAIL: ' + $checked + ' of 2 checks ran.')
    $bad++
  }

  Write-Output ''
  if ($bad -eq 0) {
    Write-Output 'SELFTEST OK: the control passed, and a shipped document whose example is not what the tool prints was caught.'
    exit 0
  }
  Write-Output ('SELFTEST FAILED: ' + $bad + ' of 2 checks did not hold.')
  exit 1
}

# --- the live check --------------------------------------------------------------
Write-Output '=== the shipped CLI example: every line of it is a line the CLI prints ==='
if (-not (Test-Path -LiteralPath $docPath)) {
  Write-Output ('  FAIL: the shipped document ' + $docPath + ' does not exist.')
  exit 1
}
$toolOut = Get-CliOutput $root
if ($null -eq $toolOut) {
  Write-Output '  FAIL: the demo CLI could not be run, so the shipped example cannot be checked.'
  Write-Output '        Build it with `moon build --target wasm` and run this gate again.'
  exit 1
}
$toolLines = @(($toolOut -split "`r?`n") | ForEach-Object { $_.TrimEnd() })
$docText = [System.IO.File]::ReadAllText($docPath, [Text.Encoding]::UTF8)
$res = Get-MismatchedLines $docText $toolLines
Write-Output ('  the CLI printed ' + $toolLines.Count + ' line(s); the document has ' + $res.Blocks + ' output block(s).')
if ($res.Checked -eq 0) {
  Write-Output '  FAIL: the document has no output block, so this gate checked nothing.'
  exit 1
}
$bad = 0
foreach ($m in $res.Bad) {
  Write-Output ('  FAIL: block ' + $m.Block + ' shows a line the CLI does not print: ' + (Get-SafeText $m.Line))
  $bad++
}
if ($bad -eq 0) {
  Write-Output ('  OK: every one of the ' + $res.Checked + ' line(s) the document shows as output is a line the CLI prints.')
  exit 0
}
Write-Output ('  ' + $bad + ' line(s) of the shipped example are not what the CLI prints.')
exit 1

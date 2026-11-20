param([switch]$SelfTest, [string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE URLs THE DOCUMENTS NAME, AND WHETHER THEY ANSWER.
#
# WHY THIS FILE EXISTS. 0629. A DOCUMENT IN THIS REPOSITORY NAMED A URL THAT
# DOES NOT EXIST, and nothing noticed, because a URL in prose is a COMMENT until
# somebody follows it. The file was
# `.dsh/skills/moonbit-static-analysis/SKILL.md`, at the line that tells the
# reader how to check the registry manifest before choosing a version number.
# It named:
#
#     https://mooncakes.io/api-new/v0/manifest/riantr/moonbit_static_analysis
#
# MEASURED 2026-11-20, with GET:
#
#     api-new/v0/manifest/riantr/moonbit_static_analysis   ->  404
#     api/v0/manifest/riantr/moonbit_static_analysis        ->  200
#
# The whole `api-new` family is gone; `api/v0` is the live one. And the LIVE
# one returns exactly what the surrounding prose promises: the body carries
# `latest_version`, `build_status`, and a `versions` array (68 entries when it
# was measured). So the sentence around the URL was RIGHT and the URL was WRONG,
# which is the shape of defect this gate exists to catch.
#
# TWO THINGS THIS GATE LEARNS THE HARD WAY, and both are in the code:
#
#   1. THE METHOD MATTERS. `Invoke-WebRequest -Method Head` answers 404 for the
#      LIVE url and 200 for the DEAD one is not what happens; what happens is
#      that HEAD answers 404 for BOTH -- the endpoint does not serve HEAD. A
#      probe that uses HEAD concludes that a working URL is dead. So the probe
#      here is a GET, and the body is not read (`GetResponse` returns the
#      headers), which is also why it is fast.
#   2. "DID NOT ANSWER" IS NOT "ANSWERED 404". A host that cannot be reached
#      has told us NOTHING about the URL. The house rule for the pinned corpus
#      is the same one: "a corpus that cannot be checked is not a corpus with
#      nothing wrong". So an unreachable host is a FAILURE with its own
#      message, and it is never reported as a dead URL.
#
# WHAT IS PROBED, AND WHAT IS NOT.
#
#   - THE CURRENT DOCUMENTS are probed: the two READMEs, `EXTENSIONS.md`,
#     `LOOP.md`, the root `SKILL.md`, `src/cli/SKILL.md`, and the workspace
#     skill `.dsh/skills/moonbit-static-analysis/SKILL.md`.
#   - THE DATED RECORDS ARE NOT: `_verify/NARRATIVE.md` and the two CHANGELOGs
#     describe what was true ON A DATE. A URL that has since moved is a record,
#     not a defect. (MEASURED 2026-11-20: they carry no mooncakes URL at all,
#     so the exclusion costs nothing today -- and it is still the right rule.)
#   - A URL CONTAINING `<` OR `>` IS A SHAPE, NOT A URL. The documents carry one
#     template -- the prebuild path with `<author>` and `<module>` in it -- and
#     a shape cannot be fetched. It is reported as a shape, not as a failure.
#   - THE HOST FAMILY is the one this repository depends on: `mooncakes.io` and
#     every subdomain of it, matched by SUFFIX. A URL on another host is not
#     this gate's subject -- the documents legitimately name github.com and
#     docs.moonbitlang.com. But a host INSIDE the family that does not
#     RESOLVE is this gate's subject, because "the registry is unreachable"
#     and "the URL is dead" are different claims, and a reader has to be told
#     which one it is.
#
# A POINTER AND A QUOTATION ARE DIFFERENT THINGS, AND 0630 LEARNED IT HERE.
#
# 0630 ADDED LOOP RULE 30, and that rule QUOTES the address that was dead --
# because the rule is about that address. So the rule put a dead URL back into
# a CURRENT document, and this gate -- which had just been written to catch
# exactly that -- reported its OWN rule as a defect:
#
#     FAIL: LOOP.md:836 names https://mooncakes.io/api-new/... and it answers 404
#
# The DOCUMENT was right. It says, on the next line, that the address was
# measured on 2026-11-20 and answers 404, and then gives the live one. That is
# a RECORD of a measurement, not a place to send a reader. The gate's SCOPE
# was wrong: it decided "is this document current?" per DOCUMENT, and asked
# "is this URL alive?" per URL -- and a current document may QUOTE a dead URL.
#
# => THE DISCRIMINATOR IS THE STATUS THE DOCUMENT STATES. A pointer says what a
#    URL is FOR ("check the registry manifest before choosing a number"); a
#    quotation says what the URL ANSWERED ("measured, GET: 404"). A document
#    that states a status for a URL is quoting a measurement, and the URL is
#    not a promise.
#
# => WHERE THE STATUS MAY SIT. The URL's own line, or one of the next TWO
#    lines. FORWARD ONLY, and that is deliberate: the answer to a URL FOLLOWS
#    the URL in every shape this repository uses, and a "404" that PRECEDES a
#    URL is a CONDITION, not an answer --
#
#        If the registry answers 404, the module is not published; check
#        `https://mooncakes.io/api/v0/manifest/...` first.
#
#    ... where a backward-looking window would swallow a live pointer and let a
#    dead manifest URL walk past the gate. FORWARD ONLY is the narrow side of
#    the trade: a record that states its status BEFORE the URL is reported as a
#    defect, which is SAFE (a red gate is visible) and never silent.
#
# => THE SKIP IS REPORTED, NOT HIDDEN. A gate that quietly ignores a URL has
#    become a gate that cannot see it. Every quoted address is printed with
#    the line that quotes it and the status that makes it a record, so a
#    reader can tell the difference between "probed and fine" and "not a
#    pointer".
#
# AND THE OTHER DIRECTION: a URL that ANSWERS 200 but is not what the document
# says it is, is just as wrong as a 404. The documents say the manifest returns
# the latest version plus the full version list, so a manifest URL whose body
# does not carry `latest_version` and `versions` is a FAILURE -- the reader is
# sent to a page that will not answer the question they were told it answers.
#
# The self-test injects each defect into a COPY OF THE DOCUMENTS and requires
# the copy to fail WITH THE RIGHT MESSAGE, and the documents as they stand to
# stay green.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_registry_urls.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_registry_urls.ps1 -SelfTest
$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$fail = 0

# THE CURRENT DOCUMENTS. A reader is pointed at these today.
$DOCS = @(
  'README.md',
  'README.zh.md',
  'EXTENSIONS.md',
  'LOOP.md',
  'SKILL.md',
  'src\cli\SKILL.md',
  '.dsh\skills\moonbit-static-analysis\SKILL.md'
)

# THE HOST FAMILY IS NOT A LIST. It is a SUFFIX test, applied in
# `Get-DocumentUrls`: `mooncakes.io` and every subdomain of it. The reason is
# in the header -- a host that does not RESOLVE is still in the family, and
# that is one of the cases the gate has to tell apart from a dead URL.

# THE STATUS OF ONE URL. 0 means THE HOST DID NOT ANSWER, which is not the
# same thing as 404, and the two are reported differently.
function Get-UrlStatus([string]$Url) {
  $code = 0
  # THREE ATTEMPTS, because a TRANSIENT is not a DEFECT. MEASURED 2026-11-20:
  # the same URL answered 200 in one run and "did not answer" in the next, with
  # nothing changed in between -- so a single unanswered probe would have
  # reported a defect in a document that names a perfectly good URL. The
  # document is not what failed; the network was.
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $code = Get-UrlStatusOnce $Url
    if ($code -ne 0) { return $code }
    if ($attempt -lt 3) { Start-Sleep -Seconds (2 * $attempt) }
  }
  return $code
}

function Get-UrlStatusOnce([string]$Url) {
  $code = 0
  try {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = 'GET'
    $req.Timeout = 30000
    $req.AllowAutoRedirect = $true
    $req.UserAgent = 'moonbit_static_analysis release gate'
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $resp.Close()
  } catch {
    # POWERSHELL WRAPS THE .NET EXCEPTION. `GetResponse()` raises a
    # `WebException` carrying the status in `.Response`, but PowerShell puts
    # it inside a `MethodInvocationException`, and the WRAPPER's `.Response`
    # is NULL. So the status has to be read from the INNER exception -- and
    # without that, a 404 comes out as "the host did not answer", which is a
    # DIFFERENT CLAIM about a DIFFERENT THING. (MEASURED 2026-11-20: the
    # first version of this probe reported the dead URL as unreachable,
    # because of exactly this.)
    $ex = $_.Exception
    while ($null -ne $ex -and $null -eq $ex.Response -and $null -ne $ex.InnerException) {
      $ex = $ex.InnerException
    }
    if ($null -ne $ex -and $null -ne $ex.Response) { $code = [int]$ex.Response.StatusCode }
  }
  return $code
}

# THE BODY OF ONE URL. Only the manifest URLs need it, and they are small.
function Get-UrlBody([string]$Url) {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $c = New-Object System.Net.WebClient
    $c.Headers.Add('User-Agent', 'moonbit_static_analysis release gate')
    $t = $c.DownloadString($Url)
    return $t
  } catch {
    return ''
  } finally {
    $ErrorActionPreference = $prev
  }
}

# EVERY URL THE CURRENT DOCUMENTS NAME, ONE RECORD PER URL. The record carries
# EVERY place the URL is named, and the claim is OR-ed over those places --
# because the first occurrence is not the only one that matters. (MEASURED
# 2026-11-20: a version of this that deduplicated by URL and kept only the
# FIRST occurrence let a defect through -- the URL `skills.mooncakes.io` is
# named in the README with no claim attached, and the claim lived on a LATER
# occurrence, in the workspace skill.)
function Get-DocumentUrls([string]$Root) {
  $out = @()
  $byUrl = @{}
  $order = @()
  # THE STATUS A DOCUMENT STATES FOR A URL. 404 and 410 are the two answers
  # that mean "this address is not there", and they are the answers a
  # MEASUREMENT records. (See the header for why the window is FORWARD only.)
  $statusMark = [regex]'(?i)\b(404|410)\b'
  foreach ($d in $DOCS) {
    $p = Join-Path $Root $d
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $lines = @([System.IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8))
    $prevLine = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
      foreach ($m in [regex]::Matches($lines[$i], 'https?://[^\s`"'')\]]+')) {
        $u = $m.Value.TrimEnd('.', ';', ',')
        # NOT `$host`: `$Host` is a READ-ONLY AUTOMATIC VARIABLE in PowerShell,
        # and assigning to it throws -- and a gate that collects nothing reports
        # GREEN. That is why the gate FAILS when it finds no URL at all.
        $uhost = ''
        try { $uhost = ([Uri]$u).Host } catch { $uhost = '' }
        # THE HOST FAMILY, BY SUFFIX: `mooncakes.io` and every subdomain of it.
        # A SUFFIX and not an exact list, because a host that does not RESOLVE
        # is still in the family -- and "in the family but unreachable" is the
        # case the gate has to tell apart from "in the family and dead".
        $inFamily = ($uhost -eq 'mooncakes.io') -or $uhost.EndsWith('.mooncakes.io')
        if (-not $inFamily) { continue }
        $isShape = ($u -match '[<>]')
        # A QUOTATION OR A POINTER. The document states a status for a URL on
        # the URL's own line or on one of the next TWO lines; a status there
        # means the document is quoting a measurement, so the URL is not a
        # promise. FORWARD ONLY -- see the header.
        $isRecord = $false
        for ($k = $i; $k -le ($i + 2) -and $k -lt $lines.Count; $k++) {
          if ($statusMark.IsMatch($lines[$k])) { $isRecord = $true; break }
        }
        # THE CLAIM. The document says what this URL is FOR, and the sentence
        # that introduces a URL is often the line ABOVE it. The rule that holds
        # the answer to the promise is keyed on THAT, not on the URL's own
        # path -- because a URL swapped for a different one that still answers
        # 200 would otherwise walk straight past a rule that only asks whether
        # the path says `/manifest/`.
        $claims = ($lines[$i] -match 'manifest') -or ($prevLine -match 'manifest')
        if (-not $byUrl.ContainsKey($u)) {
          $byUrl[$u] = [pscustomobject]@{ Url = $u; Shape = $isShape; ClaimsManifest = $false; Where = @(); PointerWhere = @(); RecordWhere = @() }
          $order += $u
        }
        $rec = $byUrl[$u]
        $rec.Where += ($d + ':' + ($i + 1))
        if ($isRecord) {
          $rec.RecordWhere += ($d + ':' + ($i + 1))
        } else {
          $rec.PointerWhere += ($d + ':' + ($i + 1))
          # THE CLAIM IS OR-ed OVER THE POINTERS ONLY. A quotation's claim is
          # about a past measurement; it must not put a pointer's obligation
          # on a URL that is only quoted.
          if ($claims) { $rec.ClaimsManifest = $true }
        }
      }
      $prevLine = $lines[$i]
    }
  }
  foreach ($u in $order) { $out += $byUrl[$u] }
  return $out
}

# WHAT IS WRONG WITH THE DOCUMENTS, given what the URLs answered.
function Get-UrlProblems([string]$Root) {
  $probs = @()
  $found = 0
  # THE QUOTATIONS THIS RUN SKIPPED. A URL that every current document only
  # QUOTES -- states a status for, instead of pointing at -- is not probed.
  # The list is kept so that the run can PRINT it: a skip that is not shown
  # is a skip nobody can audit.
  $script:skipped = @()
  foreach ($u in @(Get-DocumentUrls $Root)) {
    if ($u.Shape) { continue }
    # A QUOTATION, NOT A POINTER. Every place the current documents name this
    # URL states a status for it, so no reader is sent there. Skipped, and
    # reported below -- not skipped silently.
    if ($u.PointerWhere.Count -eq 0) {
      $script:skipped += ('    quoted, not pointed at: ' + $u.Url + '  (' + ($u.RecordWhere -join ', ') + ')')
      continue
    }
    $found++
    $where = ($u.PointerWhere -join ', ')
    $code = Get-UrlStatus $u.Url
    if ($code -eq 0) {
      $probs += ('FAIL: ' + $where + ' names ' + $u.Url + ', and the host DID NOT ANSWER after 3 attempts. A URL that could not be checked is not a URL that is fine.')
      continue
    }
    if ($code -ne 200) {
      $probs += ('FAIL: ' + $where + ' names ' + $u.Url + ', and it answers ' + $code + '. The document points the reader at a URL that is not there.')
      continue
    }
    # THE OTHER DIRECTION: an answer that is not what the document says. The
    # trigger is the DOCUMENT'S CLAIM (the sentence that introduces the URL
    # says what it is for) OR the URL's own path. The claim comes first
    # because a URL swapped for a different one that still answers 200 must
    # not walk past the rule.
    if ($u.ClaimsManifest -or ($u.Url -match '/manifest/')) {
      $body = Get-UrlBody $u.Url
      if ($body -notmatch '"latest_version"' -or $body -notmatch '"versions"') {
        $probs += ('FAIL: ' + $where + ' names ' + $u.Url + ', and it answers 200, but its body carries neither `latest_version` nor `versions`. The document promises the latest version plus the full version list, and this does not answer that.')
      }
    }
  }
  # A GATE THAT FOUND NOTHING IS A COMMENT. If the documents name no URL this
  # gate can probe, then it probed nothing and has proved nothing -- and
  # reporting GREEN for that is the one answer that must not be available.
  if ($found -eq 0) {
    $probs += 'FAIL: the current documents name no URL this gate can probe, so nothing was checked. A gate that checked nothing must not report success.'
  }
  return $probs
}

# ------------------------------------------------------------------- the self-test ---
if ($SelfTest) {
  Write-Output 'check the registry URLs -- SELF TEST'
  $bad = 0
  $checked = 0

  $tmp = Join-Path $env:TEMP ('registry_urls_selftest_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null

  function New-DocCopy([string]$Dest) {
    foreach ($d in $DOCS) {
      $src = Join-Path $root $d
      if (-not (Test-Path -LiteralPath $src)) { continue }
      $dst = Join-Path $Dest $d
      $dir = Split-Path -Parent $dst
      if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    return $Dest
  }

  Write-Output ''
  Write-Output '--- the control: the documents as they stand ---'
  $ctl = @(Get-UrlProblems $root)
  $checked++
  if ($ctl.Count -eq 0) {
    Write-Output '  OK: the control passes.'
  } else {
    Write-Output ('  FAIL: the control does NOT pass: ' + $ctl.Count + ' problem(s).')
    foreach ($x in $ctl) { Write-Output ('        ' + $x) }
    $bad++
  }

  $faults = @(
    [pscustomobject]@{
      N = 'a document names a URL under a family that is gone'
      Expect = 'it answers 404'
      Apply = {
        param($dir)
        $p = Join-Path $dir '.dsh\skills\moonbit-static-analysis\SKILL.md'
        if (-not (Test-Path -LiteralPath $p)) { return $false }
        $t = [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
        if ($t.IndexOf('api/v0/manifest/') -lt 0) { return $false }
        $t = $t.Replace('api/v0/manifest/', 'api-new/v0/manifest/')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
    [pscustomobject]@{
      N = 'a document names a module that does not exist'
      Expect = 'it answers 404'
      Apply = {
        param($dir)
        $p = Join-Path $dir '.dsh\skills\moonbit-static-analysis\SKILL.md'
        if (-not (Test-Path -LiteralPath $p)) { return $false }
        $t = [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
        if ($t.IndexOf('riantr/moonbit_static_analysis') -lt 0) { return $false }
        $t = $t.Replace('riantr/moonbit_static_analysis', 'riantr/moonbit_static_analysis_no_such_module')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
    [pscustomobject]@{
      N = 'the manifest URL answers, but not with a manifest'
      Expect = 'neither `latest_version` nor `versions`'
      Apply = {
        param($dir)
        $p = Join-Path $dir '.dsh\skills\moonbit-static-analysis\SKILL.md'
        if (-not (Test-Path -LiteralPath $p)) { return $false }
        $t = [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
        if ($t.IndexOf('https://mooncakes.io/api/v0/manifest/riantr/moonbit_static_analysis') -lt 0) { return $false }
        $t = $t.Replace('https://mooncakes.io/api/v0/manifest/riantr/moonbit_static_analysis', 'https://skills.mooncakes.io')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
    [pscustomobject]@{
      N = 'the host cannot be reached at all'
      Expect = 'DID NOT ANSWER'
      Apply = {
        param($dir)
        $p = Join-Path $dir '.dsh\skills\moonbit-static-analysis\SKILL.md'
        if (-not (Test-Path -LiteralPath $p)) { return $false }
        $t = [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
        if ($t.IndexOf('https://mooncakes.io/api/v0/manifest/riantr/moonbit_static_analysis') -lt 0) { return $false }
        $t = $t.Replace('https://mooncakes.io/api/v0/manifest/riantr/moonbit_static_analysis', 'https://nonexistent-subdomain-xyz.mooncakes.io/api/v0/manifest/riantr/moonbit_static_analysis')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
    # THE TWO FAULTS THAT CARRY THE NEW RULE. A rule that only ever says
    # "FAIL" is not a rule; it needs a case where the RIGHT ANSWER IS SILENCE,
    # and a case where the silence is EARNED.
    [pscustomobject]@{
      N = 'a document QUOTES a dead address as a measurement'
      Mode = 'skip'
      ExpectSkip = 'api-new/v0/manifest/riantr/moonbit_static_analysis'
      Apply = {
        param($dir)
        $p = Join-Path $dir 'README.md'
        if (-not (Test-Path -LiteralPath $p)) { return $false }
        $t = [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
        if ($t.IndexOf('api-new/v0/manifest/') -ge 0) { return $false }
        $t = $t + "`n`nMEASURED, and QUOTED rather than pointed at:`n`https://mooncakes.io/api-new/v0/manifest/riantr/moonbit_static_analysis` answers 404.`n"
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
    [pscustomobject]@{
      N = 'the QUOTATION loses its status, and the dead address becomes a pointer again'
      Expect = 'it answers 404'
      Apply = {
        param($dir)
        $p = Join-Path $dir 'LOOP.md'
        if (-not (Test-Path -LiteralPath $p)) { return $false }
        $lines = @([System.IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8))
        $idx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
          if ($lines[$i] -match 'api-new/v0/manifest/') { $idx = $i; break }
        }
        if ($idx -lt 0) { return $false }
        $hit = -1
        for ($k = $idx + 1; $k -le ($idx + 2) -and $k -lt $lines.Count; $k++) {
          if ($lines[$k] -match '\b404\b') { $hit = $k; break }
        }
        if ($hit -lt 0) { return $false }
        $lines[$hit] = [regex]::Replace($lines[$hit], '\b404\b', 'no-answer')
        [System.IO.File]::WriteAllLines($p, $lines, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
  )

  foreach ($f in $faults) {
    Write-Output ''
    Write-Output ('--- the defect: ' + $f.N + ' ---')
    $copy = Join-Path $tmp ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $copy -Force | Out-Null
    New-DocCopy $copy | Out-Null
    $applied = & $f.Apply $copy
    if ($applied -eq $false) {
      Write-Output '  MISSED  the anchor was not found -- the defect was never injected.'
      $bad++
      continue
    }
    $probs = @(Get-UrlProblems $copy)
    $checked++
    # TWO KINDS OF FAULT. One has to be CAUGHT; one has to be SILENT, because
    # the right answer for a quotation is not a failure. And a fault that did
    # not inject looks identical to a fault that was not caught -- so the
    # silent case also has to prove that the defect LANDED and that the gate
    # classified it, rather than that the gate simply never looked.
    if ($f.Mode -eq 'skip') {
      $sk = ($script:skipped -join ' | ')
      if ($probs.Count -gt 0) {
        Write-Output ('  FAIL: the gate reported a QUOTATION as a defect.')
        foreach ($pr in $probs) { Write-Output ('        ' + $pr) }
        $bad++
      } elseif ($sk -notmatch [regex]::Escape($f.ExpectSkip)) {
        Write-Output ('  FAIL: the quotation was not classified as one -- the gate did not even see it ("' + $f.ExpectSkip + '").')
        Write-Output ('        skipped: ' + $sk)
        $bad++
      } else {
        Write-Output '  OK: the gate read it as a quotation, not a pointer, and did not report it.'
      }
      continue
    }
    $hit = @($probs | Where-Object { $_ -match [regex]::Escape($f.Expect) })
    if ($hit.Count -ge 1) {
      Write-Output ('  OK: the gate caught it: ' + $hit[0])
    } else {
      Write-Output ('  FAIL: the gate did NOT catch it (expected "' + $f.Expect + '").')
      foreach ($pr in $probs) { Write-Output ('        ' + $pr) }
      $bad++
    }
  }

  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

  if ($checked -ne 7) {
    Write-Output ('  FAIL: ' + $checked + ' of 7 checks ran.')
    $bad++
  }

  Write-Output ''
  if ($bad -eq 0) {
    Write-Output ('SELFTEST OK: the control passed, and ' + $faults.Count + ' injected defects were each caught, or read as a quotation.')
    exit 0
  }
  Write-Output ('SELFTEST FAILED: ' + $bad + ' problem(s).')
  exit 1
}

# ------------------------------------------------------------------ the live check ---
Write-Output '=== the URLs the documents name, and whether they answer ==='
$urls = @(Get-DocumentUrls $root)
$shapes = @($urls | Where-Object { $_.Shape })
$pointed = @($urls | Where-Object { -not $_.Shape -and $_.PointerWhere.Count -gt 0 })
$quoted = @($urls | Where-Object { -not $_.Shape -and $_.PointerWhere.Count -eq 0 })
$distinct = @($pointed | Select-Object -ExpandProperty Url | Select-Object -Unique)
Write-Output ('  ' + $urls.Count + ' URL(s) in the current documents: ' + $distinct.Count + ' pointed at, ' + $quoted.Count + ' quoted, ' + $shapes.Count + ' shape(s)')
foreach ($s in ($shapes | Select-Object -ExpandProperty Url | Select-Object -Unique)) {
  Write-Output ('    a shape, not a URL (it cannot be fetched): ' + $s)
}
foreach ($u in $distinct) {
  $code = Get-UrlStatus $u
  Write-Output ('    ' + $code + '  ' + $u)
}

$probs = @(Get-UrlProblems $root)
foreach ($sk in $script:skipped) { Write-Output $sk }
foreach ($p in $probs) {
  Write-Output ''
  Write-Output $p
}
$fail += $probs.Count

Write-Output ''
if ($fail -eq 0) {
  Write-Output ('URLS OK: ' + $distinct.Count + ' URL(s) answered 200, and a manifest URL answered with the latest version plus the version list.')
  exit 0
}
Write-Output ('URLS FAILED: ' + $fail + ' problem(s).')
exit 1

#!/usr/bin/env pwsh
# Read-only SUPERBROWKY v4 installation and onboarding doctor.

[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)]
  [string]$Target,

  [ValidateSet("auto", "claude", "codex", "both")]
  [string]$Harness = "auto",

  [ValidateSet("core", "web-launch", "growth", "full")]
  [string]$Profile = "core"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$KitRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $KitRoot "manifests/skills.tsv"
$LockPath = Join-Path $KitRoot "versions.lock"
$ClaudeHomeExplicit = -not [string]::IsNullOrWhiteSpace($env:CLAUDE_HOME)
$CodexHomeExplicit = -not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)
$ClaudeHome = if ($ClaudeHomeExplicit) { $env:CLAUDE_HOME } else { Join-Path $HOME ".claude" }
$CodexHome = if ($CodexHomeExplicit) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$StateHome = if (-not [string]::IsNullOrWhiteSpace($env:SUPERBROWKY_STATE_HOME)) {
  $env:SUPERBROWKY_STATE_HOME
} else {
  Join-Path $HOME ".superbrowky"
}

function Write-Ok { param([string]$Message) Write-Host "[ok] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Fail { param([string]$Message) Write-Host "[x] $Message" -ForegroundColor Red }

function Test-AnyPath {
  param([string]$Path)
  return $null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

function Test-IsReparsePoint {
  param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)
  return -not [string]::IsNullOrWhiteSpace([string]$Item.LinkType) -or
    (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-RealDirectory {
  param([string]$Path)
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  return $null -ne $item -and $item.PSIsContainer -and -not (Test-IsReparsePoint -Item $item)
}

function Get-Sha256Text {
  param([AllowEmptyString()][string]$Text)
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-TreeHashCore {
  param([string]$Root, [switch]$AllowReparsePoints)
  if (-not (Test-RealDirectory $Root)) { throw "Not a real directory: $Root" }
  $entries = @()
  foreach ($item in (Get-ChildItem -LiteralPath $Root -Recurse -Force)) {
    $isLink = Test-IsReparsePoint -Item $item
    if ($isLink -and -not $AllowReparsePoints) {
      $relative = [IO.Path]::GetRelativePath($Root, $item.FullName).Replace("\", "/")
      throw "Symlink/reparse point is not allowed in managed tree: $relative"
    }
    if ($item.PSIsContainer -and -not $isLink) { continue }
    $entries += [pscustomobject]@{
      Item = $item
      Relative = [IO.Path]::GetRelativePath($Root, $item.FullName).Replace("\", "/")
      IsLink = $isLink
    }
  }
  $builder = [Text.StringBuilder]::new()
  $byRelative = @{}
  $relativeNames = [System.Collections.Generic.List[string]]::new()
  foreach ($entry in $entries) {
    $byRelative[$entry.Relative] = $entry
    $relativeNames.Add($entry.Relative)
  }
  $orderedNames = $relativeNames.ToArray()
  [Array]::Sort($orderedNames, [StringComparer]::Ordinal)
  foreach ($relativeName in $orderedNames) {
    $entry = $byRelative[$relativeName]
    if ($entry.IsLink) {
      $target = if ($entry.Item.Target -is [array]) { $entry.Item.Target -join "," } else { [string]$entry.Item.Target }
      [void]$builder.Append("L`t$($entry.Relative)`t$target`n")
    } else {
      $hash = (Get-FileHash -LiteralPath $entry.Item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      [void]$builder.Append("F`t$($entry.Relative)`t$hash`n")
    }
  }
  return Get-Sha256Text $builder.ToString()
}

function Get-TreeHash {
  param([string]$Root)
  return Get-TreeHashCore -Root $Root
}

function Get-BackupFingerprint {
  param([string]$Path)
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) { throw "backup is missing" }
  if (Test-IsReparsePoint -Item $item) {
    $target = if ($item.Target -is [array]) { $item.Target -join "," } else { [string]$item.Target }
    $linkType = if ([string]::IsNullOrWhiteSpace([string]$item.LinkType)) { "reparse" } else { [string]$item.LinkType }
    return [pscustomobject]@{
      Type = "link"
      Hash = Get-Sha256Text "L`t$linkType`t$target`n"
    }
  }
  if ($item.PSIsContainer) {
    return [pscustomobject]@{
      Type = "directory"
      Hash = Get-TreeHashCore -Root $Path -AllowReparsePoints
    }
  }
  return [pscustomobject]@{
    Type = "file"
    Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}

function Test-PathUnderRoot {
  param([string]$Path, [string]$Root)
  try {
    $pathFull = [IO.Path]::GetFullPath($Path).TrimEnd(
      [IO.Path]::DirectorySeparatorChar,
      [IO.Path]::AltDirectorySeparatorChar
    )
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd(
      [IO.Path]::DirectorySeparatorChar,
      [IO.Path]::AltDirectorySeparatorChar
    )
  } catch {
    return $false
  }
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if ($pathFull.Equals($rootFull, $comparison)) { return $false }
  return $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, $comparison)
}

function Assert-BackupBoundary {
  param([string]$Path)
  $backupRoot = Join-Path $StateHome "backups"
  if (-not (Test-PathUnderRoot -Path $Path -Root $backupRoot)) {
    throw "recorded backup escapes SUPERBROWKY_STATE_HOME/backups"
  }
  $rootFull = [IO.Path]::GetFullPath($backupRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
  )
  $current = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  while ($true) {
    if (Test-AnyPath $current) {
      $item = Get-Item -LiteralPath $current -Force
      if (-not $item.PSIsContainer -or (Test-IsReparsePoint -Item $item)) {
        throw "backup parent is not a real directory"
      }
    }
    if ($current.Equals($rootFull, $comparison)) { break }
    $next = Split-Path -Parent $current
    if ([string]::IsNullOrWhiteSpace($next) -or $next.Equals($current, $comparison)) {
      throw "could not verify backup parent boundary"
    }
    $current = $next
  }
}

function Assert-ValidBackupReceipt {
  param([hashtable]$Receipt)
  if (-not $Receipt.ContainsKey("backup") -or
      -not $Receipt.ContainsKey("backup_type") -or
      -not $Receipt.ContainsKey("backup_hash")) {
    throw "backup path/type/hash metadata is incomplete"
  }
  if ($Receipt["backup"] -eq "-") {
    if ($Receipt["backup_type"] -ne "-" -or $Receipt["backup_hash"] -ne "-") {
      throw "empty backup has inconsistent type/hash metadata"
    }
    return
  }
  $backup = $Receipt["backup"]
  $backupType = if ($Receipt.ContainsKey("backup_type")) { $Receipt["backup_type"] } else { "" }
  $backupHash = if ($Receipt.ContainsKey("backup_hash")) { $Receipt["backup_hash"] } else { "" }
  Assert-BackupBoundary -Path $backup
  if ($backupType -notin @("directory", "file", "link") -or $backupHash -notmatch "^[0-9a-f]{64}$") {
    throw "recorded backup type/hash is missing or invalid"
  }
  $actual = Get-BackupFingerprint -Path $backup
  if ($actual.Type -ne $backupType -or $actual.Hash -ne $backupHash) {
    throw "recorded backup type/hash mismatch"
  }
}

function Get-Receipt {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $result = @{}
  foreach ($line in [IO.File]::ReadAllLines($Path)) {
    $separator = $line.IndexOf("`t")
    if ($separator -gt 0) {
      $result[$line.Substring(0, $separator)] = $line.Substring($separator + 1).TrimEnd("`r")
    }
  }
  return $result
}

function Test-ProfileSelection {
  param([string]$Requested, [string]$ManifestProfile)
  if ($Requested -eq "full") { return $true }
  if ($ManifestProfile -eq "core") { return $true }
  if ($Requested -eq "web-launch" -and $ManifestProfile -eq "web-launch") { return $true }
  if ($Requested -eq "growth" -and $ManifestProfile -in @("web-launch", "growth")) { return $true }
  return $false
}

function Get-LockPin {
  param([string]$Key)
  foreach ($line in [IO.File]::ReadAllLines($LockPath)) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) { continue }
    $separator = $trimmed.IndexOf("=")
    if ($separator -gt 0 -and $trimmed.Substring(0, $separator) -eq $Key) {
      return $trimmed.Substring($separator + 1)
    }
  }
  return $null
}

function Get-SelectedSkills {
  $lines = [IO.File]::ReadAllLines($ManifestPath)
  if ($lines.Count -lt 2) { throw "Manifest is empty" }
  $skills = @()
  for ($index = 1; $index -lt $lines.Count; $index++) {
    if ([string]::IsNullOrWhiteSpace($lines[$index])) { continue }
    $fields = $lines[$index].TrimEnd("`r").Split([char]"`t", [StringSplitOptions]::None)
    if ($fields.Count -ne 9) { throw "Malformed manifest row $($index + 1)" }
    if (Test-ProfileSelection $Profile $fields[1]) {
      $skills += [pscustomobject]@{
        Name = $fields[0]
        SourceType = $fields[2]
        Repo = $fields[3]
        PinKey = $fields[4]
        ClaudeFolder = $fields[5]
        CodexFolder = $fields[6]
      }
    }
  }
  return $skills
}

function Test-SkillFrontmatter {
  param([string]$SkillMd, [string]$ExpectedName)
  $lines = [IO.File]::ReadAllLines($SkillMd)
  if ($lines.Count -lt 3 -or $lines[0].Trim() -ne "---") { return $false }
  $name = ""
  $description = ""
  for ($index = 1; $index -lt $lines.Count; $index++) {
    $line = $lines[$index]
    if ($line.Trim() -eq "---") { break }
    if ($line -match '^name:\s*["'']?([^"'']+)["'']?\s*$') { $name = $Matches[1].Trim() }
    if ($line -match '^description:\s*(.+)$') { $description = $Matches[1].Trim() }
  }
  return $name -eq $ExpectedName -and -not [string]::IsNullOrWhiteSpace($description)
}

function Get-Harnesses {
  param([string]$Value)
  switch ($Value) {
    "claude" { return @("claude") }
    "codex" { return @("codex") }
    "both" { return @("claude", "codex") }
    default { throw "Invalid harness: $Value" }
  }
}

function Resolve-AutoHarness {
  $projectClaude = Test-Path -LiteralPath (Join-Path $Target "CLAUDE.md") -PathType Leaf
  $projectCodex = Test-Path -LiteralPath (Join-Path $Target "AGENTS.md") -PathType Leaf
  $hasClaude = $projectClaude -or $ClaudeHomeExplicit -or
    (Test-Path -LiteralPath $ClaudeHome -PathType Container) -or
    $null -ne (Get-Command claude -ErrorAction SilentlyContinue)
  $hasCodex = $projectCodex -or $CodexHomeExplicit -or
    (Test-Path -LiteralPath $CodexHome -PathType Container) -or
    $null -ne (Get-Command codex -ErrorAction SilentlyContinue)
  if ($hasClaude -and $hasCodex) { return "both" }
  if ($hasClaude) { return "claude" }
  if ($hasCodex) { return "codex" }
  return $null
}

function Get-SkillsDirectory {
  param([string]$Value)
  if ($Value -eq "claude") { return Join-Path $ClaudeHome "skills" }
  return Join-Path $CodexHome "skills"
}

function Get-TemplateNames {
  $names = @("HARNESS.md", "PROJECT.md", "PRODUCT.md", "DESIGN.md", "Decision.md", "Feedback.md")
  if ($Harness -in @("claude", "both")) { $names += "CLAUDE.md" }
  if ($Harness -in @("codex", "both")) { $names += "AGENTS.md" }
  return $names
}

function Get-ProjectReceiptRows {
  param([string]$Path)
  $rows = @()
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $rows }
  foreach ($line in [IO.File]::ReadAllLines($Path)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
    $fields = $line.TrimEnd("`r").Split([char]"`t", [StringSplitOptions]::None)
    if ($fields.Count -eq 4) {
      $rows += [pscustomobject]@{ Kind = $fields[0]; Relative = $fields[1]; Hash = $fields[2]; Source = $fields[3] }
    }
  }
  return $rows
}

function Get-ExactMetadataValues {
  param([string[]]$Lines, [string]$Label)
  $prefix = "- **$Label`:** "
  return @($Lines | Where-Object {
    $_.StartsWith($prefix, [StringComparison]::Ordinal)
  } | ForEach-Object {
    $_.Substring($prefix.Length)
  })
}

function Test-NonPlaceholderMetadataValue {
  param([AllowEmptyString()][string]$Value, [switch]$DateLike)
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Contains("<") -or $Value.Contains(">")) {
    return $false
  }
  $normalized = $Value.Trim().ToUpperInvariant()
  if ($normalized -in @(
    "NONE",
    "N/A",
    "TBD",
    "UNKNOWN",
    "PLACEHOLDER",
    "NOT YET ACCEPTED",
    "NOT YET APPROVED"
  )) {
    return $false
  }
  if ($DateLike -and $Value -notmatch '^\d{4}-\d{2}-\d{2}(?:\s+\S.*)?$') {
    return $false
  }
  return $true
}

function Test-ReviewedExactToken {
  param(
    [AllowEmptyString()][string]$Text,
    [string]$Wanted
  )
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $normalized = [regex]::Replace($Text, '[`;,(){}\[\]]', ' ')
  foreach ($token in ($normalized -split '\s+')) {
    if ($token.Equals($Wanted, [StringComparison]::Ordinal)) { return $true }
  }
  return $false
}

function Get-DecisionEntries {
  param([string[]]$Lines)
  $entries = [System.Collections.Generic.List[object]]::new()
  $heading = $null
  $entryLines = $null
  foreach ($line in $Lines) {
    if ($line.StartsWith("### ", [StringComparison]::Ordinal)) {
      if ($null -ne $heading) {
        $entries.Add([pscustomobject]@{ Heading = $heading; Lines = @($entryLines) })
      }
      $heading = $line
      $entryLines = [System.Collections.Generic.List[string]]::new()
      $entryLines.Add($line)
    } elseif ($null -ne $heading) {
      $entryLines.Add($line)
    }
  }
  if ($null -ne $heading) {
    $entries.Add([pscustomobject]@{ Heading = $heading; Lines = @($entryLines) })
  }
  return @($entries)
}

function Get-ReviewedArtifactsText {
  param([string[]]$Lines)
  $prefix = "- **Reviewed artifacts:**"
  $starts = @()
  for ($index = 0; $index -lt $Lines.Count; $index++) {
    if ($Lines[$index].StartsWith($prefix, [StringComparison]::Ordinal)) {
      $starts += $index
    }
  }
  if ($starts.Count -ne 1) { return $null }
  $parts = [System.Collections.Generic.List[string]]::new()
  $first = $starts[0]
  $parts.Add($Lines[$first].Substring($prefix.Length).Trim())
  for ($index = $first + 1; $index -lt $Lines.Count; $index++) {
    $line = $Lines[$index]
    if ($line.StartsWith("### ", [StringComparison]::Ordinal) -or
        $line -match '^- \*\*[^*]+:\*\*') {
      break
    }
    if (-not [string]::IsNullOrWhiteSpace($line)) { $parts.Add($line.Trim()) }
  }
  return ($parts -join " ")
}

$blocked = 0
$partial = 0
try {
  if (-not (Test-Path -LiteralPath $Target -PathType Container)) { throw "Not a directory: $Target" }
  $Target = (Resolve-Path -LiteralPath $Target).Path
  if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
    throw "Manifest or versions.lock is missing"
  }
  if ($Harness -eq "auto") {
    $Harness = Resolve-AutoHarness
    if ([string]::IsNullOrWhiteSpace($Harness)) { throw "Could not detect Claude Code or Codex" }
  }
  $selectedSkills = @(Get-SelectedSkills)

  Write-Host "SUPERBROWKY doctor — harness=$Harness profile=$Profile"
  foreach ($forHarness in (Get-Harnesses $Harness)) {
    $skillsDirectory = Get-SkillsDirectory $forHarness
    foreach ($skill in $selectedSkills) {
      $name = $skill.Name
      $destination = Join-Path $skillsDirectory $name
      $receiptPath = Join-Path (Join-Path (Join-Path $StateHome "state") $forHarness) "$name.receipt.tsv"
      $receipt = Get-Receipt $receiptPath
      if ($null -eq $receipt) {
        Write-Fail "$forHarness/$name`: receipt missing"
        $blocked++
        continue
      }
      $expectedDestination = $destination
      if (-not $receipt.ContainsKey("name") -or $receipt["name"] -ne $name -or
          -not $receipt.ContainsKey("harness") -or $receipt["harness"] -ne $forHarness -or
          -not $receipt.ContainsKey("dest") -or $receipt["dest"] -ne $expectedDestination) {
        Write-Fail "$forHarness/$name`: receipt ownership mismatch"
        $blocked++
        continue
      }
      if (-not (Test-RealDirectory $destination)) {
        Write-Fail "$forHarness/$name`: managed directory missing or linked"
        $blocked++
        continue
      }
      if (-not $receipt.ContainsKey("tree_hash") -or
          (Get-TreeHash $destination) -ne $receipt["tree_hash"]) {
        Write-Fail "$forHarness/$name`: managed content drift"
        $blocked++
        continue
      }
      $skillMd = Join-Path $destination "SKILL.md"
      if (-not (Test-Path -LiteralPath $skillMd -PathType Leaf) -or
          -not (Test-SkillFrontmatter -SkillMd $skillMd -ExpectedName $name)) {
        Write-Fail "$forHarness/$name`: SKILL.md frontmatter name/description invalid"
        $blocked++
        continue
      }
      $folder = if ($forHarness -eq "claude") { $skill.ClaudeFolder } else { $skill.CodexFolder }
      $expectedSource = if ($skill.SourceType -eq "git") {
        "git:$($skill.Repo):$folder+third-party-safety-v1"
      } else {
        "bundled:$folder"
      }
      if ($skill.SourceType -eq "git") {
        $safetyContract = Select-String -LiteralPath $skillMd -SimpleMatch "## SUPERBROWKY third-party safety contract" -Quiet
        if (-not $safetyContract) {
          Write-Fail "$forHarness/$name`: third-party safety overlay is absent"
          $blocked++
          continue
        }
        $expectedOverlay = "third-party-safety-v1"
        if ($name -eq "impeccable") { $expectedOverlay += "+superbrowky-overlay-v1" }
        if (-not $receipt.ContainsKey("overlay") -or $receipt["overlay"] -ne $expectedOverlay) {
          Write-Warn "$forHarness/$name`: overlay provenance missing from receipt"
          $partial++
        }
        if ($name -eq "ai-seo") {
          $expectedSource += "+pinned-upstream-link-v1"
          $receiptRefForLink = if ($receipt.ContainsKey("ref")) { $receipt["ref"] } else { "" }
          $pinnedRegistry = "https://github.com/$($skill.Repo)/blob/$receiptRefForLink/tools/REGISTRY.md"
          $externalRegistry = @(Get-ChildItem -LiteralPath $destination -Recurse -File |
            Select-String -SimpleMatch "../../tools/REGISTRY.md")
          $hasPinnedRegistry = Select-String -LiteralPath $skillMd -SimpleMatch $pinnedRegistry -Quiet
          if ($externalRegistry.Count -gt 0 -or -not $hasPinnedRegistry) {
            Write-Fail "$forHarness/$name`: pinned upstream registry link is invalid"
            $blocked++
            continue
          }
        }
      }
      if ($name -eq "impeccable") {
        $expectedSource += "+superbrowky-overlay-v1"
        if ((Test-AnyPath (Join-Path $destination "scripts/cleanup-deprecated.mjs")) -or
            (Test-AnyPath (Join-Path $destination "scripts/pin.mjs"))) {
          Write-Fail "$forHarness/$name`: prohibited cleanup/pin helper is present"
          $blocked++
          continue
        }
        $portableContract = Select-String -LiteralPath $skillMd -SimpleMatch "## SUPERBROWKY portable contract" -Quiet
        $projectPath = @(Get-ChildItem -LiteralPath $destination -Recurse -File |
          Select-String -Pattern '(?:\.claude|\.agents)[\\/]skills[\\/]impeccable')
        if (-not $portableContract -or $projectPath.Count -gt 0) {
          Write-Fail "$forHarness/$name`: portable overlay/path hardening is invalid"
          $blocked++
          continue
        }
      }
      if (-not $receipt.ContainsKey("source") -or $receipt["source"] -ne $expectedSource) {
        Write-Warn "$forHarness/$name`: receipt source differs from current manifest"
        $partial++
      }
      if ($skill.SourceType -eq "git") {
        $expectedRef = Get-LockPin $skill.PinKey
        if (-not $receipt.ContainsKey("ref") -or $receipt["ref"] -ne $expectedRef) {
          Write-Warn "$forHarness/$name`: installed ref differs from versions.lock"
          $partial++
        }
      } else {
        $bundledSource = Join-Path $KitRoot $folder
        if (-not (Test-RealDirectory $bundledSource)) {
          Write-Fail "$forHarness/$name`: current bundled source is missing or linked"
          $blocked++
          continue
        }
        $bundledHash = Get-TreeHash $bundledSource
        if ($receipt["tree_hash"] -ne $bundledHash) {
          Write-Warn "$forHarness/$name`: bundled source changed since installation; review/apply a fresh plan"
          $partial++
        }
      }
      try {
        Assert-ValidBackupReceipt -Receipt $receipt
      } catch {
        Write-Fail "$forHarness/$name`: $($_.Exception.Message)"
        $blocked++
        continue
      }
      Write-Ok "$forHarness/$name"
    }
  }

  $projectReceiptPath = Join-Path (Join-Path $Target ".superbrowky") "project-receipt.tsv"
  $projectRows = @(Get-ProjectReceiptRows $projectReceiptPath)
  if ($projectRows.Count -eq 0) {
    Write-Fail "project receipt missing or empty"
    $blocked++
  }
  foreach ($name in (Get-TemplateNames)) {
    $canonical = Join-Path $Target $name
    if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
      Write-Fail "$name`: project file is missing"
      $blocked++
      continue
    }
    $template = Join-Path (Join-Path $KitRoot "template") $name
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
      Write-Fail "kit template missing: $name"
      $blocked++
      continue
    }
    $digest = (Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash.ToLowerInvariant()
    $matchingRows = @($projectRows | Where-Object { $_.Source -eq "template/$name" })
    if ($matchingRows.Count -ne 1) {
      Write-Fail "$name`: project receipt ownership requires exactly one row; found $($matchingRows.Count)"
      $blocked++
      continue
    }
    $row = $matchingRows[0]
    if ($row.Hash -notmatch '^[0-9a-f]{64}$') {
      Write-Fail "$name`: invalid project receipt hash"
      $blocked++
      continue
    }
    if ($row.Relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($row.Relative)) {
      Write-Fail "$name`: unsafe project receipt path"
      $blocked++
      continue
    }
    if ($row.Hash -ne $digest) {
      Write-Warn "$name`: kit template changed since receipt; review a fresh bootstrap plan"
      $partial++
    }
    if ($row.Kind -eq "candidate") {
      if (-not $row.Relative.StartsWith("$name.from-superbrowky-v4-", [StringComparison]::Ordinal)) {
        Write-Fail "$name`: unsafe merge-candidate receipt path"
        $blocked++
        continue
      }
      $candidate = Join-Path $Target $row.Relative
      if (Test-AnyPath $candidate) {
        Write-Warn "$name`: merge candidate is waiting for review"
        $partial++
      } else {
        $marker = "<!-- SUPERBROWKY-MERGED: template/$name sha256:$($row.Hash) -->"
        if (Select-String -LiteralPath $canonical -SimpleMatch $marker -Quiet) {
          Write-Ok "$name (merge accepted by exact marker)"
        } else {
          Write-Warn "$name`: merge candidate is missing and canonical file has no exact acceptance marker"
          $partial++
        }
      }
      continue
    }
    if ($row.Kind -notin @("installed", "observed") -or $row.Relative -ne $name) {
      Write-Fail "$name`: invalid project receipt ownership"
      $blocked++
      continue
    }
    $currentHash = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($currentHash -eq $row.Hash) {
      Write-Ok "project $name"
    } else {
      Write-Ok "project $name (project-owned content)"
    }
  }

  $projectMap = Join-Path $Target "PROJECT.md"
  if ((Test-Path -LiteralPath $projectMap -PathType Leaf) -and
      (Select-String -LiteralPath $projectMap -SimpleMatch "PLACEHOLDERS PRESENT" -Quiet)) {
    Write-Warn "PROJECT.md: repository map placeholders remain"
    $partial++
  }

  $decisionPath = Join-Path $Target "Decision.md"
  $decisionLines = if (Test-Path -LiteralPath $decisionPath -PathType Leaf) {
    [IO.File]::ReadAllLines($decisionPath)
  } else {
    @()
  }
  $decisionEntries = @(Get-DecisionEntries -Lines $decisionLines)
  foreach ($name in @("PRODUCT.md", "DESIGN.md")) {
    $path = Join-Path $Target $name
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and
        (Select-String -LiteralPath $path -SimpleMatch "PLACEHOLDERS PRESENT" -Quiet)) {
      Write-Warn "$name`: onboarding placeholders remain"
      $partial++
      continue
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $lines = [IO.File]::ReadAllLines($path)
    $authorityStatuses = @(Get-ExactMetadataValues -Lines $lines -Label "Status")
    if ($authorityStatuses.Count -ne 1 -or $authorityStatuses[0] -ne "ACCEPTED") {
      Write-Warn "$name`: authority status is not the exact ACCEPTED line"
      $partial++
    }
    $artifactIds = @(Get-ExactMetadataValues -Lines $lines -Label "Artifact ID")
    $versions = @(Get-ExactMetadataValues -Lines $lines -Label "Version")
    $decisionReferences = @(Get-ExactMetadataValues -Lines $lines -Label "Decision reference")
    $acceptedByValues = @(Get-ExactMetadataValues -Lines $lines -Label "Accepted by")
    $acceptedOnValues = @(Get-ExactMetadataValues -Lines $lines -Label "Accepted on")
    if ($artifactIds.Count -ne 1 -or
        $artifactIds[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9._:/-]*$') {
      Write-Warn "$name`: exact non-placeholder Artifact ID is missing or ambiguous"
      $partial++
      continue
    }
    if ($versions.Count -ne 1 -or
        $versions[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9._:/-]*$') {
      Write-Warn "$name`: exact non-placeholder Version is missing or ambiguous"
      $partial++
      continue
    }
    if ($decisionReferences.Count -ne 1 -or
        $decisionReferences[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9._:/-]*$') {
      Write-Warn "$name`: exact non-placeholder Decision reference is missing or ambiguous"
      $partial++
      continue
    }
    if ($acceptedByValues.Count -ne 1 -or
        -not (Test-NonPlaceholderMetadataValue $acceptedByValues[0])) {
      Write-Warn "$name`: exact non-placeholder Accepted by is missing or ambiguous"
      $partial++
      continue
    }
    if ($acceptedOnValues.Count -ne 1 -or
        -not (Test-NonPlaceholderMetadataValue $acceptedOnValues[0] -DateLike)) {
      Write-Warn "$name`: exact non-placeholder Accepted on is missing or ambiguous"
      $partial++
      continue
    }
    $artifactId = $artifactIds[0]
    $version = $versions[0]
    $decisionReference = $decisionReferences[0]
    if ($artifactId -in @("NONE", "TBD", "UNKNOWN", "PLACEHOLDER") -or
        $version -in @("NONE", "TBD", "UNKNOWN", "PLACEHOLDER") -or
        $decisionReference -in @("NONE", "TBD", "UNKNOWN", "PLACEHOLDER")) {
      Write-Warn "$name`: authority metadata still uses a placeholder value"
      $partial++
      continue
    }
    $matchingEntries = @($decisionEntries | Where-Object {
      $_.Lines -contains "- **Decision ID:** $decisionReference"
    })
    if ($matchingEntries.Count -ne 1) {
      Write-Warn "$name`: Decision reference '$decisionReference' has no exact Decision.md ID"
      $partial++
      continue
    }
    $entry = $matchingEntries[0]
    if ($entry.Heading -match '<|YYYY-MM-DD') {
      Write-Warn "$name`: Decision reference points to a placeholder ### entry"
      $partial++
      continue
    }
    $entryStatuses = @(Get-ExactMetadataValues -Lines $entry.Lines -Label "Status")
    if ($entryStatuses.Count -ne 1 -or $entryStatuses[0] -ne "ACCEPTED") {
      Write-Warn "$name`: Decision entry status is not exactly ACCEPTED"
      $partial++
      continue
    }
    $approvedByValues = @(Get-ExactMetadataValues -Lines $entry.Lines -Label "Approved by")
    $approvedOnValues = @(Get-ExactMetadataValues -Lines $entry.Lines -Label "Approved on")
    if ($approvedByValues.Count -ne 1 -or
        -not (Test-NonPlaceholderMetadataValue $approvedByValues[0])) {
      Write-Warn "$name`: Decision entry has no exact non-placeholder Approved by"
      $partial++
      continue
    }
    if ($approvedOnValues.Count -ne 1 -or
        -not (Test-NonPlaceholderMetadataValue $approvedOnValues[0] -DateLike)) {
      Write-Warn "$name`: Decision entry has no exact non-placeholder Approved on"
      $partial++
      continue
    }
    $reviewedArtifacts = Get-ReviewedArtifactsText -Lines $entry.Lines
    $currentHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $hasFile = Test-ReviewedExactToken -Text $reviewedArtifacts -Wanted $name
    $hasArtifactVersion = Test-ReviewedExactToken -Text $reviewedArtifacts -Wanted "$artifactId/$version"
    $hasHash = Test-ReviewedExactToken -Text $reviewedArtifacts -Wanted "sha256:$currentHash"
    if (-not $hasFile -or -not $hasArtifactVersion -or -not $hasHash) {
      Write-Warn "$name`: Decision entry does not review the exact current artifact ID/version/SHA-256"
      $partial++
    }
  }
  foreach ($name in @("CLAUDE.md", "AGENTS.md")) {
    if (($name -eq "CLAUDE.md" -and $Harness -notin @("claude", "both")) -or
        ($name -eq "AGENTS.md" -and $Harness -notin @("codex", "both"))) { continue }
    $path = Join-Path $Target $name
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and
        (Select-String -LiteralPath $path -SimpleMatch "<framework / language>" -Quiet)) {
      Write-Warn "$name`: adapter placeholders remain"
      $partial++
    }
  }

  $node = Get-Command node -ErrorAction SilentlyContinue
  if ($null -eq $node) {
    Write-Warn "Node.js 22+ not found; optional skill helpers cannot run"
    $partial++
  } else {
    $versionText = (& $node.Source --version 2>$null | Select-Object -First 1)
    $major = 0
    if ([string]::IsNullOrWhiteSpace($versionText) -or
        -not [int]::TryParse(($versionText.TrimStart("v") -split "\.")[0], [ref]$major) -or
        $major -lt 22) {
      Write-Warn "Node.js 22+ required by installed skill helpers; found $versionText"
      $partial++
    } else {
      Write-Ok "Node.js $versionText"
    }
  }
} catch {
  Write-Fail $_.Exception.Message
  $blocked++
}

Write-Host ""
if ($blocked -gt 0) {
  Write-Host "STATUS: BLOCKED — $blocked required check(s) failed; $partial follow-up item(s)."
  exit 1
}
if ($partial -gt 0) {
  Write-Host "STATUS: PARTIAL — installation is intact; $partial onboarding/runtime follow-up item(s)."
  exit 2
}
Write-Host "STATUS: READY — receipts, managed files, project context, and runtime checks passed."
exit 0

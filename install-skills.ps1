#!/usr/bin/env pwsh
# SUPERBROWKY v4 — native PowerShell skill installer for Claude Code and Codex.
#
# The default invocation is a read-only plan. Nothing under CLAUDE_HOME,
# CODEX_HOME, or SUPERBROWKY_STATE_HOME changes without -Apply.

[CmdletBinding()]
param(
  [ValidateSet("auto", "claude", "codex", "both")]
  [string]$Harness = "auto",

  [ValidateSet("core", "web-launch", "growth", "full")]
  [string]$Profile = "core",

  [switch]$Apply,
  [switch]$DryRun,
  [switch]$Latest,
  [switch]$CheckUpdates,
  [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$KitRoot = $PSScriptRoot
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
$script:TempRoot = $null
$script:ResolvedRefs = @{}
$script:RepoRoots = @{}

function Write-Ok {
  param([string]$Message)
  Write-Host "[ok] $Message" -ForegroundColor Green
}

function Write-Warn {
  param([string]$Message)
  Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Fail {
  param([string]$Message)
  Write-Host "[x] $Message" -ForegroundColor Red
}

function Write-Status {
  param([string]$Message)
  Write-Host "STATUS: $Message"
}

function Get-LockPin {
  param([Parameter(Mandatory)][string]$Key)
  if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) { return $null }
  foreach ($line in [System.IO.File]::ReadAllLines($LockPath)) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) { continue }
    $separator = $trimmed.IndexOf("=")
    if ($separator -lt 1) { continue }
    if ($trimmed.Substring(0, $separator) -eq $Key) {
      return $trimmed.Substring($separator + 1)
    }
  }
  return $null
}

function Test-SafeRelativePath {
  param([Parameter(Mandatory)][string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or
      [System.IO.Path]::IsPathRooted($Path) -or
      $Path.Contains("\")) {
    return $false
  }
  foreach ($segment in ($Path -split "/")) {
    if ($segment -in @("", ".", "..") -or
        $segment -notmatch "^[A-Za-z0-9._-]+$") {
      return $false
    }
  }
  return $true
}

function Get-Manifest {
  if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing manifest: $ManifestPath"
  }
  $lines = [System.IO.File]::ReadAllLines($ManifestPath)
  if ($lines.Count -lt 2) { throw "Manifest has no skill rows: $ManifestPath" }
  $expectedHeader = "name`tprofiles`tsource_type`trepo`tpin_key`tclaude_upstream_folder`tcodex_upstream_folder`tlicense`trequired"
  if ($lines[0].TrimEnd("`r") -ne $expectedHeader) {
    throw "Manifest header does not match the v4 schema"
  }

  $seen = @{}
  $rows = [System.Collections.Generic.List[object]]::new()
  for ($index = 1; $index -lt $lines.Count; $index++) {
    $line = $lines[$index].TrimEnd("`r")
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $fields = $line.Split([char]"`t", [System.StringSplitOptions]::None)
    if ($fields.Count -ne 9) { throw "Malformed manifest row $($index + 1)" }

    $row = [pscustomobject]@{
      Name = $fields[0]
      ManifestProfile = $fields[1]
      SourceType = $fields[2]
      Repo = $fields[3]
      PinKey = $fields[4]
      ClaudeFolder = $fields[5]
      CodexFolder = $fields[6]
      License = $fields[7]
      Required = $fields[8]
    }
    if ($row.Name -notmatch "^[a-z0-9]+(?:-[a-z0-9]+)*$") {
      throw "Invalid skill name in manifest: $($row.Name)"
    }
    if ($seen.ContainsKey($row.Name)) { throw "Duplicate manifest skill: $($row.Name)" }
    $seen[$row.Name] = $true
    if ($row.ManifestProfile -notin @("core", "web-launch", "growth", "full")) {
      throw "$($row.Name): invalid manifest profile '$($row.ManifestProfile)'"
    }
    if ($row.SourceType -notin @("git", "bundled")) {
      throw "$($row.Name): invalid source_type '$($row.SourceType)'"
    }
    if ($row.Required -notin @("yes", "no")) {
      throw "$($row.Name): required must be yes or no"
    }
    if ($row.SourceType -eq "git") {
      if ($row.Repo -notmatch "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") {
        throw "$($row.Name): unsafe repository slug '$($row.Repo)'"
      }
      if ([string]::IsNullOrWhiteSpace($row.PinKey)) {
        throw "$($row.Name): missing pin key"
      }
    }
    foreach ($folder in @($row.ClaudeFolder, $row.CodexFolder)) {
      if ($folder -ne "." -and -not (Test-SafeRelativePath $folder)) {
        throw "$($row.Name): unsafe source folder '$folder'"
      }
    }
    $rows.Add($row)
  }
  return @($rows)
}

function Test-ProfileSelection {
  param([string]$Requested, [string]$ManifestProfile)
  switch ("${Requested}:${ManifestProfile}") {
    "core:core" { return $true }
    "web-launch:core" { return $true }
    "web-launch:web-launch" { return $true }
    "growth:core" { return $true }
    "growth:web-launch" { return $true }
    "growth:growth" { return $true }
    default { return $Requested -eq "full" }
  }
}

function Get-SelectedSkills {
  $selected = @(Get-Manifest | Where-Object {
    Test-ProfileSelection -Requested $Profile -ManifestProfile $_.ManifestProfile
  })
  if ($selected.Count -eq 0) { throw "Profile '$Profile' selected no skills" }
  return $selected
}

function Get-Harnesses {
  param([string]$Value)
  switch ($Value) {
    "claude" { return @("claude") }
    "codex" { return @("codex") }
    "both" { return @("claude", "codex") }
    default { throw "Invalid resolved harness: $Value" }
  }
}

function Resolve-AutoHarness {
  $hasClaude = $ClaudeHomeExplicit -or
    (Test-Path -LiteralPath $ClaudeHome -PathType Container) -or
    $null -ne (Get-Command claude -ErrorAction SilentlyContinue)
  $hasCodex = $CodexHomeExplicit -or
    (Test-Path -LiteralPath $CodexHome -PathType Container) -or
    $null -ne (Get-Command codex -ErrorAction SilentlyContinue)
  if ($hasClaude -and $hasCodex) { return "both" }
  if ($hasClaude) { return "claude" }
  if ($hasCodex) { return "codex" }
  return $null
}

function Get-SkillsDirectory {
  param([string]$ForHarness)
  switch ($ForHarness) {
    "claude" { return Join-Path $ClaudeHome "skills" }
    "codex" { return Join-Path $CodexHome "skills" }
    default { throw "Invalid harness: $ForHarness" }
  }
}

function Get-ReceiptPath {
  param([string]$ForHarness, [string]$Name)
  return Join-Path (Join-Path (Join-Path $StateHome "state") $ForHarness) "$Name.receipt.tsv"
}

function Get-Receipt {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $values = @{}
  foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
    $separator = $line.IndexOf("`t")
    if ($separator -lt 1) { continue }
    $values[$line.Substring(0, $separator)] = $line.Substring($separator + 1).TrimEnd("`r")
  }
  return $values
}

function Test-AnyPath {
  param([Parameter(Mandatory)][string]$Path)
  return $null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

function Test-IsReparsePoint {
  param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)
  return -not [string]::IsNullOrWhiteSpace([string]$Item.LinkType) -or
    (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-RealDirectory {
  param([Parameter(Mandatory)][string]$Path)
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item -or -not $item.PSIsContainer) { return $false }
  return -not (Test-IsReparsePoint -Item $item)
}

function Assert-NoReparsePoints {
  param(
    [Parameter(Mandatory)][string]$Root,
    [string]$Label = $Root
  )
  if (-not (Test-RealDirectory $Root)) {
    throw "$Label`: root is missing, not a directory, or is a symlink/reparse point"
  }
  foreach ($item in (Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop)) {
    if (Test-IsReparsePoint -Item $item) {
      $relative = [System.IO.Path]::GetRelativePath($Root, $item.FullName).Replace("\", "/")
      throw "$Label`: symlink/reparse point is not allowed: $relative"
    }
  }
}

function Resolve-RealSourceDirectory {
  param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$RelativeFolder,
    [Parameter(Mandatory)][string]$Label
  )
  if ($RelativeFolder -ne "." -and -not (Test-SafeRelativePath $RelativeFolder)) {
    throw "$Label`: unsafe source folder '$RelativeFolder'"
  }
  if (-not (Test-RealDirectory $RepositoryRoot)) {
    throw "$Label`: repository root is missing, not a directory, or is a symlink/reparse point"
  }
  $current = (Get-Item -LiteralPath $RepositoryRoot -Force).FullName
  if ($RelativeFolder -eq ".") { return $current }
  foreach ($segment in ($RelativeFolder -split "/")) {
    $current = Join-Path $current $segment
    $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or -not $item.PSIsContainer -or (Test-IsReparsePoint -Item $item)) {
      throw "$Label`: source path contains a missing or linked directory at '$segment'"
    }
    $current = $item.FullName
  }
  return $current
}

function Get-Sha256Text {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-TreeHashCore {
  param(
    [Parameter(Mandatory)][string]$Root,
    [switch]$AllowReparsePoints
  )
  if (-not (Test-RealDirectory $Root)) { throw "Not a real directory: $Root" }
  $entries = [System.Collections.Generic.List[object]]::new()
  foreach ($item in (Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop)) {
    $isLink = Test-IsReparsePoint -Item $item
    if ($isLink -and -not $AllowReparsePoints) {
      $relative = [System.IO.Path]::GetRelativePath($Root, $item.FullName).Replace("\", "/")
      throw "Symlink/reparse point is not allowed in managed tree: $relative"
    }
    if ($item.PSIsContainer -and -not $isLink) { continue }
    $relative = [System.IO.Path]::GetRelativePath($Root, $item.FullName).Replace("\", "/")
    $entries.Add([pscustomobject]@{ Item = $item; Relative = $relative; IsLink = $isLink })
  }
  $byRelative = @{}
  $relativeNames = [System.Collections.Generic.List[string]]::new()
  foreach ($entry in $entries) {
    $byRelative[$entry.Relative] = $entry
    $relativeNames.Add($entry.Relative)
  }
  $orderedNames = $relativeNames.ToArray()
  [Array]::Sort($orderedNames, [StringComparer]::Ordinal)
  $builder = [System.Text.StringBuilder]::new()
  foreach ($relativeName in $orderedNames) {
    $entry = $byRelative[$relativeName]
    if ($entry.IsLink) {
      $target = if ($entry.Item.Target -is [array]) {
        ($entry.Item.Target -join ",")
      } else {
        [string]$entry.Item.Target
      }
      [void]$builder.Append("L`t$($entry.Relative)`t$target`n")
    } else {
      $hash = (Get-FileHash -LiteralPath $entry.Item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      [void]$builder.Append("F`t$($entry.Relative)`t$hash`n")
    }
  }
  return Get-Sha256Text -Text $builder.ToString()
}

function Get-TreeHash {
  param([Parameter(Mandatory)][string]$Root)
  Assert-NoReparsePoints -Root $Root -Label "managed tree"
  return Get-TreeHashCore -Root $Root
}

function Get-BackupFingerprint {
  param([Parameter(Mandatory)][string]$Path)
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) { throw "Backup path is missing: $Path" }
  if (Test-IsReparsePoint -Item $item) {
    $target = if ($item.Target -is [array]) { $item.Target -join "," } else { [string]$item.Target }
    $linkType = if ([string]::IsNullOrWhiteSpace([string]$item.LinkType)) { "reparse" } else { [string]$item.LinkType }
    return [pscustomobject]@{
      Type = "link"
      Hash = Get-Sha256Text -Text "L`t$linkType`t$target`n"
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
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Root
  )
  try {
    $pathFull = [System.IO.Path]::GetFullPath($Path).TrimEnd(
      [System.IO.Path]::DirectorySeparatorChar,
      [System.IO.Path]::AltDirectorySeparatorChar
    )
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd(
      [System.IO.Path]::DirectorySeparatorChar,
      [System.IO.Path]::AltDirectorySeparatorChar
    )
  } catch {
    return $false
  }
  $comparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
  } else {
    [System.StringComparison]::Ordinal
  }
  if ($pathFull.Equals($rootFull, $comparison)) { return $false }
  $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
  return $pathFull.StartsWith($prefix, $comparison)
}

function Assert-BackupBoundary {
  param([Parameter(Mandatory)][string]$Path)
  $backupRoot = Join-Path $StateHome "backups"
  if (-not (Test-PathUnderRoot -Path $Path -Root $backupRoot)) {
    throw "Recorded backup escapes SUPERBROWKY_STATE_HOME/backups"
  }
  $rootFull = [System.IO.Path]::GetFullPath($backupRoot).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  $current = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
  $comparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
  } else {
    [System.StringComparison]::Ordinal
  }
  while ($true) {
    if (Test-AnyPath $current) {
      $item = Get-Item -LiteralPath $current -Force
      if (-not $item.PSIsContainer -or (Test-IsReparsePoint -Item $item)) {
        throw "Backup parent is not a real directory: $current"
      }
    }
    if ($current.Equals($rootFull, $comparison)) { break }
    $next = Split-Path -Parent $current
    if ([string]::IsNullOrWhiteSpace($next) -or $next.Equals($current, $comparison)) {
      throw "Could not verify backup parent boundary"
    }
    $current = $next
  }
}

function Assert-BackupFingerprint {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$ExpectedType,
    [Parameter(Mandatory)][string]$ExpectedHash
  )
  Assert-BackupBoundary -Path $Path
  if ($ExpectedType -notin @("directory", "file", "link") -or
      $ExpectedHash -notmatch "^[0-9a-f]{64}$") {
    throw "Recorded backup metadata is missing or invalid"
  }
  $actual = Get-BackupFingerprint -Path $Path
  if ($actual.Type -ne $ExpectedType -or $actual.Hash -ne $ExpectedHash) {
    throw "Recorded backup type/hash mismatch"
  }
}

function Get-Frontmatter {
  param([Parameter(Mandatory)][string]$SkillMd)
  $lines = [System.IO.File]::ReadAllLines($SkillMd)
  if ($lines.Count -eq 0 -or $lines[0].Trim() -ne "---") { return $null }
  $end = -1
  for ($index = 1; $index -lt $lines.Count; $index++) {
    if ($lines[$index].Trim() -eq "---") { $end = $index; break }
  }
  if ($end -lt 0) { return $null }
  $values = @{}
  $index = 1
  while ($index -lt $end) {
    $line = $lines[$index]
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#") -or
        [char]::IsWhiteSpace($line[0]) -or -not $line.Contains(":")) {
      $index++
      continue
    }
    $separator = $line.IndexOf(":")
    $key = $line.Substring(0, $separator).Trim()
    $value = $line.Substring($separator + 1).Trim()
    if ($value -in @("|", ">")) {
      $block = [System.Collections.Generic.List[string]]::new()
      $fold = $value -eq ">"
      $index++
      while ($index -lt $end -and
             ([string]::IsNullOrWhiteSpace($lines[$index]) -or
              [char]::IsWhiteSpace($lines[$index][0]))) {
        $block.Add($lines[$index].Trim())
        $index++
      }
      $values[$key] = if ($fold) { $block -join " " } else { $block -join "`n" }
      continue
    }
    if ($value.Length -ge 2 -and
        (($value.StartsWith('"') -and $value.EndsWith('"')) -or
         ($value.StartsWith("'") -and $value.EndsWith("'")))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $values[$key] = $value.Trim()
    $index++
  }
  return $values
}

function Test-SkillPackage {
  param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$ExpectedName)
  $skillMd = Join-Path $Directory "SKILL.md"
  if (-not (Test-Path -LiteralPath $skillMd -PathType Leaf)) {
    Write-Fail "$ExpectedName`: missing SKILL.md"
    return $false
  }
  $frontmatter = Get-Frontmatter -SkillMd $skillMd
  if ($null -eq $frontmatter) {
    Write-Fail "$ExpectedName`: malformed or missing YAML frontmatter"
    return $false
  }
  if (-not $frontmatter.ContainsKey("name") -or $frontmatter["name"] -ne $ExpectedName) {
    $actual = if ($frontmatter.ContainsKey("name")) { $frontmatter["name"] } else { "<missing>" }
    Write-Fail "$ExpectedName`: frontmatter name is '$actual'"
    return $false
  }
  if (-not $frontmatter.ContainsKey("description") -or
      [string]::IsNullOrWhiteSpace([string]$frontmatter["description"])) {
    Write-Fail "$ExpectedName`: frontmatter description is missing"
    return $false
  }
  $textExtensions = @(".md", ".markdown", ".mjs", ".js", ".cjs", ".ts", ".tsx", ".json", ".yaml", ".yml", ".txt")
  foreach ($file in (Get-ChildItem -LiteralPath $Directory -Recurse -Force -File)) {
    if ($textExtensions -notcontains $file.Extension.ToLowerInvariant()) { continue }
    if (Select-String -LiteralPath $file.FullName -SimpleMatch "/Users/" -Quiet) {
      Write-Fail "$ExpectedName`: non-portable /Users path in $($file.FullName)"
      return $false
    }
  }
  return $true
}

function Copy-DirectoryContents {
  param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
  Assert-NoReparsePoints -Root $Source -Label "copy source"
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($item in (Get-ChildItem -LiteralPath $Source -Force)) {
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
  }
  Assert-NoReparsePoints -Root $Destination -Label "copied tree"
}

function Add-UpstreamProvenance {
  param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$SkillDirectory
  )
  foreach ($name in @("LICENSE", "LICENSE.md", "NOTICE", "NOTICE.md")) {
    $source = Join-Path $RepositoryRoot $name
    $destination = Join-Path $SkillDirectory $name
    $sourceItem = Get-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue
    if ($null -eq $sourceItem) { continue }
    if ($sourceItem.PSIsContainer -or (Test-IsReparsePoint -Item $sourceItem)) {
      throw "upstream provenance is not a regular file: $name"
    }
    if (-not (Test-AnyPath $destination)) {
      Copy-Item -LiteralPath $source -Destination $destination
    }
  }
}

function Assert-UpstreamProvenance {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$SkillDirectory
  )
  $found = $false
  foreach ($fileName in @("LICENSE", "LICENSE.md", "NOTICE", "NOTICE.md")) {
    $path = Join-Path $SkillDirectory $fileName
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { continue }
    if ($item.PSIsContainer -or (Test-IsReparsePoint -Item $item)) {
      throw "$Name`: provenance file is not a regular file: $fileName"
    }
    $found = $true
  }
  if (-not $found) {
    throw "$Name`: staged package retains no regular LICENSE/NOTICE provenance file"
  }
}

function Pin-KnownUpstreamLinks {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$SkillDirectory,
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Ref
  )
  if ($Name -ne "ai-seo") { return }
  $skillMd = Join-Path $SkillDirectory "SKILL.md"
  $original = [IO.File]::ReadAllText($skillMd)
  if (-not $original.Contains("../../tools/REGISTRY.md")) {
    throw "ai-seo: expected upstream registry link changed"
  }
  $pinnedUrl = "https://github.com/$Repo/blob/$Ref/tools/REGISTRY.md"
  $text = $original.Replace("../../tools/REGISTRY.md", $pinnedUrl)
  [IO.File]::WriteAllText($skillMd, $text, [Text.UTF8Encoding]::new($false))
  $externalRegistryLinks = @(Get-ChildItem -LiteralPath $SkillDirectory -Recurse -File |
    Select-String -SimpleMatch "../../tools/REGISTRY.md")
  if ($externalRegistryLinks.Count -gt 0) {
    throw "ai-seo: external tools registry path remains"
  }
}

function Add-MarkdownOverlayAfterFrontmatter {
  param(
    [Parameter(Mandatory)][string]$SkillMd,
    [Parameter(Mandatory)][string]$OverlayPath
  )
  if (-not (Test-Path -LiteralPath $OverlayPath -PathType Leaf)) {
    throw "Missing reviewed overlay: $OverlayPath"
  }
  if (-not (Test-Path -LiteralPath $skillMd -PathType Leaf)) {
    throw "Overlay target is missing SKILL.md"
  }
  $skillLines = ([System.IO.File]::ReadAllText($skillMd) -replace "`r`n", "`n" -replace "`r", "`n").Split("`n")
  if ($skillLines.Count -lt 3 -or $skillLines[0].Trim() -ne "---") {
    throw "impeccable overlay: malformed frontmatter"
  }
  $frontmatterEnd = -1
  for ($index = 1; $index -lt $skillLines.Count; $index++) {
    if ($skillLines[$index].Trim() -eq "---") {
      $frontmatterEnd = $index
      break
    }
  }
  if ($frontmatterEnd -lt 0) { throw "impeccable overlay: closing frontmatter delimiter missing" }
  $overlay = ([System.IO.File]::ReadAllText($overlayPath) -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n")
  $before = ($skillLines[0..$frontmatterEnd] -join "`n")
  $after = if ($frontmatterEnd + 1 -lt $skillLines.Count) {
    ($skillLines[($frontmatterEnd + 1)..($skillLines.Count - 1)] -join "`n").TrimStart("`n")
  } else {
    ""
  }
  $result = "$before`n`n$overlay"
  if (-not [string]::IsNullOrEmpty($after)) { $result += "`n`n$after" }
  $result = $result.TrimEnd("`n") + "`n"
  [System.IO.File]::WriteAllText($skillMd, $result, [System.Text.UTF8Encoding]::new($false))
}

function Add-ImpeccablePortableOverlay {
  param([Parameter(Mandatory)][string]$SkillDirectory)
  $cleanup = Join-Path $SkillDirectory "scripts/cleanup-deprecated.mjs"
  $pin = Join-Path $SkillDirectory "scripts/pin.mjs"
  if (-not (Test-AnyPath $cleanup) -or -not (Test-AnyPath $pin)) {
    throw "impeccable: expected cleanup/pin helpers changed upstream"
  }
  Remove-Item -LiteralPath $cleanup -Force
  Remove-Item -LiteralPath $pin -Force

  $skillMd = Join-Path $SkillDirectory "SKILL.md"
  $lines = ([IO.File]::ReadAllText($skillMd) -replace "`r`n", "`n" -replace "`r", "`n").Split("`n")
  $rewritten = [System.Collections.Generic.List[string]]::new()
  $inFrontmatter = $false
  $delimiterCount = 0
  $skipAllowedTools = $false
  $skipPinSection = $false
  $removedAllowedTools = $false
  $removedPinIntro = $false
  $removedPinSection = $false
  foreach ($line in $lines) {
    if ($line -eq "## Pin / Unpin") {
      $skipPinSection = $true
      $removedPinSection = $true
    }
    if ($skipPinSection) { continue }
    if ($line -match '^Plus two management commands:') {
      $removedPinIntro = $true
      continue
    }
    if ($inFrontmatter -and $line -match '^allowed-tools:') {
      $skipAllowedTools = $true
      $removedAllowedTools = $true
      continue
    }
    if ($skipAllowedTools -and $line -match '^\s') { continue }
    if ($skipAllowedTools) { $skipAllowedTools = $false }
    $rewritten.Add($line)
    if ($line -eq "---") {
      $delimiterCount++
      if ($delimiterCount -eq 1) { $inFrontmatter = $true }
      if ($delimiterCount -eq 2) { $inFrontmatter = $false }
    }
  }
  if (-not $removedPinIntro -or -not $removedPinSection) {
    throw "impeccable: expected pin sections changed upstream"
  }
  [IO.File]::WriteAllText($skillMd, (($rewritten -join "`n").TrimEnd("`n") + "`n"), [Text.UTF8Encoding]::new($false))
  if (Select-String -LiteralPath $skillMd -Pattern '^allowed-tools:' -Quiet) {
    throw "impeccable: unsafe upstream allowed-tools remains"
  }
  Add-MarkdownOverlayAfterFrontmatter -SkillMd $skillMd -OverlayPath (Join-Path $KitRoot "overlays/impeccable-portable.md")

  $markdownFiles = [System.Collections.Generic.List[string]]::new()
  foreach ($file in (Get-ChildItem -LiteralPath $SkillDirectory -Recurse -File -Filter "*.md")) {
    $markdownFiles.Add($file.FullName)
  }
  foreach ($file in $markdownFiles) {
    $text = [System.IO.File]::ReadAllText($file) -replace "`r`n", "`n" -replace "`r", "`n"
    foreach ($prefix in @(
      "~/.claude/skills/impeccable",
      "~/.agents/skills/impeccable",
      '$HOME/.claude/skills/impeccable',
      '$HOME/.agents/skills/impeccable',
      ".claude/skills/impeccable",
      ".agents/skills/impeccable",
      ".claude\skills\impeccable",
      ".agents\skills\impeccable"
    )) {
      $text = $text.Replace("$prefix/", '$SKILL_DIR/')
      $text = $text.Replace("$prefix\", '$SKILL_DIR/')
      $text = $text.Replace($prefix, '$SKILL_DIR')
    }
    [System.IO.File]::WriteAllText($file, $text, [System.Text.UTF8Encoding]::new($false))
  }
  foreach ($file in $markdownFiles) {
    if (Select-String -LiteralPath $file -Pattern '(?:\.claude|\.agents)[\\/]skills[\\/]impeccable' -Quiet) {
      throw "impeccable overlay: harness-relative skill path remains in $file"
    }
  }
  $removedHelperReferences = @(Get-ChildItem -LiteralPath $SkillDirectory -Recurse -File |
    Select-String -Pattern '(?:cleanup-deprecated|pin)\.mjs')
  if ($removedHelperReferences.Count -gt 0) {
    throw "impeccable overlay: removed cleanup/pin helpers are still referenced"
  }
}

function Add-ThirdPartySafetyOverlay {
  param([Parameter(Mandatory)][string]$SkillDirectory)
  Add-MarkdownOverlayAfterFrontmatter `
    -SkillMd (Join-Path $SkillDirectory "SKILL.md") `
    -OverlayPath (Join-Path $KitRoot "overlays/third-party-safety.md")
}

function Resolve-SourceRefs {
  param([object[]]$Selected, [switch]$AllowLatestNetwork)
  $script:ResolvedRefs = @{}
  foreach ($skill in $Selected) {
    if ($skill.SourceType -ne "git" -or $script:ResolvedRefs.ContainsKey($skill.Repo)) { continue }
    if (-not $Latest) {
      $ref = Get-LockPin -Key $skill.PinKey
      if ([string]::IsNullOrWhiteSpace($ref)) {
        throw "$($skill.Repo): no pin '$($skill.PinKey)' in versions.lock"
      }
    } elseif ($AllowLatestNetwork) {
      if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git is required to resolve -Latest safely"
      }
      $output = & git ls-remote "https://github.com/$($skill.Repo).git" HEAD 2>$null
      if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Select-Object -First 1))) {
        throw "$($skill.Repo): could not resolve HEAD"
      }
      $ref = (($output | Select-Object -First 1) -split "\s+")[0]
      if ($ref -notmatch "^[0-9a-fA-F]{40,64}$") {
        throw "$($skill.Repo): HEAD did not resolve to an exact SHA"
      }
    } else {
      $ref = "UNRESOLVED_HEAD"
    }
    $script:ResolvedRefs[$skill.Repo] = $ref
  }
}

function Get-BundledRef {
  if ($null -ne (Get-Command git -ErrorAction SilentlyContinue)) {
    $ref = & git -C $KitRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ref)) {
      return ($ref | Select-Object -First 1).Trim()
    }
  }
  return "local"
}

function Get-RemoteRepository {
  param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Ref)
  $cacheKey = "$Repo@$Ref"
  if ($script:RepoRoots.ContainsKey($cacheKey)) { return $script:RepoRoots[$cacheKey] }
  if ($null -eq (Get-Command tar -ErrorAction SilentlyContinue)) {
    throw "tar is required to extract pinned skills"
  }
  $safeKey = $cacheKey -replace "[^A-Za-z0-9_.-]", "_"
  $fetchRoot = Join-Path $script:TempRoot "fetch"
  $cache = Join-Path $fetchRoot $safeKey
  $partial = "$cache.partial"
  $archive = Join-Path $fetchRoot "$safeKey.tar.gz"
  New-Item -ItemType Directory -Path $fetchRoot -Force | Out-Null
  if (Test-AnyPath $partial) { Remove-Item -LiteralPath $partial -Recurse -Force }
  New-Item -ItemType Directory -Path $partial -Force | Out-Null
  try {
    Invoke-WebRequest -Uri "https://codeload.github.com/$Repo/tar.gz/$Ref" -OutFile $archive
    & tar -xzf $archive -C $partial
    if ($LASTEXITCODE -ne 0) { throw "tar exited with code $LASTEXITCODE" }
    Move-Item -LiteralPath $partial -Destination $cache
  } catch {
    if (Test-AnyPath $partial) { Remove-Item -LiteralPath $partial -Recurse -Force -ErrorAction SilentlyContinue }
    throw "$Repo@$Ref`: download or extraction failed: $($_.Exception.Message)"
  }
  $roots = @(Get-ChildItem -LiteralPath $cache -Directory -Force)
  if ($roots.Count -ne 1) { throw "$Repo@$Ref`: archive must contain one repository root" }
  # Repositories may intentionally contain symlinks outside the selected skill
  # folder (for example a root CLAUDE.md adapter). Selected source trees and
  # copied provenance are checked separately and remain fail-closed.
  $script:RepoRoots[$cacheKey] = $roots[0].FullName
  return $roots[0].FullName
}

function Stage-AllSkills {
  param([object[]]$Selected)
  $stageRecords = [System.Collections.Generic.List[object]]::new()
  $bundledRef = Get-BundledRef
  foreach ($forHarness in (Get-Harnesses $Harness)) {
    $stageSkills = Join-Path (Join-Path (Join-Path $script:TempRoot "stage") $forHarness) "skills"
    New-Item -ItemType Directory -Path $stageSkills -Force | Out-Null
    foreach ($skill in $Selected) {
      $folder = if ($forHarness -eq "claude") { $skill.ClaudeFolder } else { $skill.CodexFolder }
      if ($skill.SourceType -eq "git") {
        $ref = $script:ResolvedRefs[$skill.Repo]
        if ([string]::IsNullOrWhiteSpace($ref) -or $ref -eq "UNRESOLVED_HEAD") {
          throw "$($skill.Name): source ref was not resolved"
        }
        $root = Get-RemoteRepository -Repo $skill.Repo -Ref $ref
        $source = Resolve-RealSourceDirectory `
          -RepositoryRoot $root `
          -RelativeFolder $folder `
          -Label $skill.Name
        $sourceLabel = "git:$($skill.Repo):$folder"
      } else {
        $ref = $bundledRef
        $source = Resolve-RealSourceDirectory `
          -RepositoryRoot $KitRoot `
          -RelativeFolder $folder `
          -Label $skill.Name
        $sourceLabel = "bundled:$folder"
      }
      if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "$($skill.Name): source folder is missing ($sourceLabel)"
      }
      $destination = Join-Path $stageSkills $skill.Name
      Copy-DirectoryContents -Source $source -Destination $destination
      if ($skill.SourceType -eq "git") {
        Add-UpstreamProvenance -RepositoryRoot $root -SkillDirectory $destination
        Assert-UpstreamProvenance -Name $skill.Name -SkillDirectory $destination
        Pin-KnownUpstreamLinks `
          -Name $skill.Name `
          -SkillDirectory $destination `
          -Repo $skill.Repo `
          -Ref $ref
      }
      if ($skill.Name -eq "impeccable") {
        Add-ImpeccablePortableOverlay -SkillDirectory $destination
      }
      $overlay = "-"
      if ($skill.SourceType -eq "git") {
        Add-ThirdPartySafetyOverlay -SkillDirectory $destination
        $overlay = "third-party-safety-v1"
        if ($skill.Name -eq "impeccable") {
          $overlay += "+superbrowky-overlay-v1"
        }
        $sourceLabel += "+$overlay"
        if ($skill.Name -eq "ai-seo") {
          $sourceLabel += "+pinned-upstream-link-v1"
        }
      }
      if (-not (Test-SkillPackage -Directory $destination -ExpectedName $skill.Name)) {
        throw "$($skill.Name): staged package validation failed"
      }
      Assert-NoReparsePoints -Root $destination -Label "$($skill.Name) staged package"
      $hash = Get-TreeHash -Root $destination
      $stageRecords.Add([pscustomobject]@{
        Harness = $forHarness
        Name = $skill.Name
        Stage = $destination
        TreeHash = $hash
        Source = $sourceLabel
        Ref = $ref
        License = $skill.License
        Required = $skill.Required
        Overlay = $overlay
      })
      Write-Ok "staged $forHarness/$($skill.Name) ($($ref.Substring(0, [Math]::Min(12, $ref.Length))))"
    }
  }
  return @($stageRecords)
}

function Invoke-DeepValidation {
  $javascriptFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
  foreach ($forHarness in (Get-Harnesses $Harness)) {
    $stageHarness = Join-Path (Join-Path $script:TempRoot "stage") $forHarness
    foreach ($file in (Get-ChildItem -LiteralPath $stageHarness -Recurse -Force -File |
      Where-Object { $_.Extension.ToLowerInvariant() -in @(".js", ".mjs", ".cjs") } |
      Sort-Object FullName)) {
      $javascriptFiles.Add($file)
    }
  }
  if ($javascriptFiles.Count -gt 0) {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $node) {
      throw "Node.js 22+ is required to validate staged JavaScript helpers"
    }
    $versionText = (& $node.Source --version 2>$null | Select-Object -First 1)
    $major = 0
    if ([string]::IsNullOrWhiteSpace($versionText) -or
        -not [int]::TryParse(($versionText.TrimStart("v") -split "\.")[0], [ref]$major) -or
        $major -lt 22) {
      throw "Node.js 22+ is required to validate staged JavaScript helpers; found $versionText"
    }
    foreach ($file in $javascriptFiles) {
      $syntaxOutput = @(& $node.Source --check $file.FullName 2>&1)
      if ($LASTEXITCODE -ne 0) {
        $relative = [IO.Path]::GetRelativePath($script:TempRoot, $file.FullName).Replace("\", "/")
        $detail = (($syntaxOutput | ForEach-Object { [string]$_ }) -join " ").Trim()
        throw "staged JavaScript syntax check failed: $relative ($detail)"
      }
    }
    Write-Ok "Node.js syntax check passed for $($javascriptFiles.Count) staged helper(s)"
  }

  foreach ($candidate in @("python3", "python")) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($null -eq $command) { continue }
    $validator = Join-Path $KitRoot "scripts/validate-skills.py"
    if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) { break }
    foreach ($forHarness in (Get-Harnesses $Harness)) {
      $stageHarness = Join-Path (Join-Path $script:TempRoot "stage") $forHarness
      & $command.Source $validator $stageHarness
      if ($LASTEXITCODE -ne 0) { throw "$forHarness`: staged deep validation failed" }
    }
    return
  }
  Write-Warn "python validator unavailable; basic frontmatter/path validation completed"
}

function Show-InstallPlan {
  param([object[]]$Selected)
  Write-Host "SUPERBROWKY install plan — harness=$Harness profile=$Profile"
  if ($Latest) {
    Write-Warn "UNSAFE -Latest preview: each upstream HEAD was resolved to the exact SHA shown below"
  }
  $problems = 0
  $count = 0
  foreach ($forHarness in (Get-Harnesses $Harness)) {
    $skillsDirectory = Get-SkillsDirectory $forHarness
    foreach ($skill in $Selected) {
      $destination = Join-Path $skillsDirectory $skill.Name
      $receiptPath = Get-ReceiptPath -ForHarness $forHarness -Name $skill.Name
      $ref = if ($skill.SourceType -eq "git") { $script:ResolvedRefs[$skill.Repo] } else { Get-BundledRef }
      $displayRef = if ($Latest) {
        $ref
      } else {
        $ref.Substring(0, [Math]::Min(12, $ref.Length))
      }
      $receipt = Get-Receipt -Path $receiptPath
      if ($null -ne $receipt) {
        if (-not $receipt.ContainsKey("dest") -or $receipt["dest"] -ne $destination) {
          Write-Fail "$forHarness/$($skill.Name): receipt destination conflicts with the current home override"
          $problems++
        } elseif (-not (Test-RealDirectory $destination)) {
          Write-Fail "$forHarness/$($skill.Name): managed destination is missing or not a real directory"
          $problems++
        } else {
          $currentHash = Get-TreeHash -Root $destination
          if (-not $receipt.ContainsKey("tree_hash") -or $currentHash -ne $receipt["tree_hash"]) {
            Write-Fail "$forHarness/$($skill.Name): managed copy drifted; it will not be overwritten"
            $problems++
          } else {
            $backup = if ($receipt.ContainsKey("backup")) { $receipt["backup"] } else { "-" }
            if ($backup -eq "-") {
              if (-not $receipt.ContainsKey("backup_type") -or
                  -not $receipt.ContainsKey("backup_hash") -or
                  $receipt["backup_type"] -ne "-" -or
                  $receipt["backup_hash"] -ne "-") {
                Write-Fail "$forHarness/$($skill.Name): backup path/type/hash metadata is incomplete"
                $problems++
                continue
              }
            } else {
              $backupType = if ($receipt.ContainsKey("backup_type")) { $receipt["backup_type"] } else { "" }
              $backupHash = if ($receipt.ContainsKey("backup_hash")) { $receipt["backup_hash"] } else { "" }
              try {
                Assert-BackupFingerprint -Path $backup -ExpectedType $backupType -ExpectedHash $backupHash
              } catch {
                Write-Fail "$forHarness/$($skill.Name): $($_.Exception.Message)"
                $problems++
                continue
              }
            }
            Write-Host ("  UPDATE  {0,-7} {1,-30} {2} @ {3}" -f
                $forHarness, $skill.Name, "$($skill.SourceType):$($skill.Repo)",
                $displayRef)
          }
        }
      } elseif (Test-AnyPath $destination) {
        Write-Host ("  BACKUP  {0,-7} {1,-30} existing unmanaged copy; {2} @ {3}" -f
          $forHarness, $skill.Name, "$($skill.SourceType):$($skill.Repo)", $displayRef)
      } else {
        Write-Host ("  INSTALL {0,-7} {1,-30} {2} @ {3}" -f
          $forHarness, $skill.Name, "$($skill.SourceType):$($skill.Repo)",
          $displayRef)
      }
      $count++
    }
  }
  Write-Host "`nSelected operations: $count. No downloads or live writes were performed."
  if ($problems -gt 0) {
    Write-Status "BLOCKED — fix managed drift/receipt conflicts before -Apply."
    return 1
  }
  Write-Status "READY — plan only; rerun the same command with -Apply."
  return 0
}

function Get-InstallActions {
  param([object[]]$StageRecords)
  $actions = [System.Collections.Generic.List[object]]::new()
  $problems = 0
  foreach ($record in $StageRecords) {
    $destination = Join-Path (Get-SkillsDirectory $record.Harness) $record.Name
    $receiptPath = Get-ReceiptPath -ForHarness $record.Harness -Name $record.Name
    $receipt = Get-Receipt -Path $receiptPath
    $action = $null
    $backup = "-"
    $backupType = "-"
    $backupHash = "-"
    $expectedLiveHash = "-"
    if ($null -ne $receipt) {
      if (-not $receipt.ContainsKey("dest") -or $receipt["dest"] -ne $destination) {
        Write-Fail "$($record.Harness)/$($record.Name): receipt destination conflict"
        $problems++
        continue
      }
      if (-not (Test-RealDirectory $destination)) {
        Write-Fail "$($record.Harness)/$($record.Name): managed copy is missing or not a real directory"
        $problems++
        continue
      }
      $currentHash = Get-TreeHash -Root $destination
      if (-not $receipt.ContainsKey("tree_hash") -or $currentHash -ne $receipt["tree_hash"]) {
        Write-Fail "$($record.Harness)/$($record.Name): managed copy drifted; refusing overwrite"
        $problems++
        continue
      }
      $expectedLiveHash = $receipt["tree_hash"]
      if ($receipt.ContainsKey("backup") -and -not [string]::IsNullOrWhiteSpace($receipt["backup"])) {
        $backup = $receipt["backup"]
      }
      if ($backup -eq "-") {
        if (-not $receipt.ContainsKey("backup_type") -or
            -not $receipt.ContainsKey("backup_hash") -or
            $receipt["backup_type"] -ne "-" -or
            $receipt["backup_hash"] -ne "-") {
          Write-Fail "$($record.Harness)/$($record.Name): backup path/type/hash metadata is incomplete"
          $problems++
          continue
        }
      } else {
        $backupType = if ($receipt.ContainsKey("backup_type")) { $receipt["backup_type"] } else { "" }
        $backupHash = if ($receipt.ContainsKey("backup_hash")) { $receipt["backup_hash"] } else { "" }
        try {
          Assert-BackupFingerprint -Path $backup -ExpectedType $backupType -ExpectedHash $backupHash
        } catch {
          Write-Fail "$($record.Harness)/$($record.Name): $($_.Exception.Message)"
          $problems++
          continue
        }
      }
      $action = if ($currentHash -eq $record.TreeHash) { "NOOP" } else { "REPLACE" }
    } elseif (Test-AnyPath $destination) {
      $action = "BACKUP"
    } else {
      $action = "INSTALL"
    }
    $actions.Add([pscustomobject]@{
      Record = $record
      Action = $action
      Destination = $destination
      Receipt = $receiptPath
      Backup = $backup
      BackupType = $backupType
      BackupHash = $backupHash
      ExpectedLiveHash = $expectedLiveHash
    })
  }
  if ($problems -gt 0) { throw "$problems receipt or drift conflict(s)" }
  return @($actions)
}

function Write-Receipt {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][object]$Action,
    [Parameter(Mandatory)][string]$Backup,
    [Parameter(Mandatory)][string]$BackupType,
    [Parameter(Mandatory)][string]$BackupHash
  )
  $record = $Action.Record
  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  $text = @(
    "format`t2"
    "name`t$($record.Name)"
    "harness`t$($record.Harness)"
    "profile`t$Profile"
    "dest`t$($Action.Destination)"
    "source`t$($record.Source)"
    "ref`t$($record.Ref)"
    "tree_hash`t$($record.TreeHash)"
    "backup`t$Backup"
    "backup_type`t$BackupType"
    "backup_hash`t$BackupHash"
    "license`t$($record.License)"
    "overlay`t$($record.Overlay)"
    "installed_at`t$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
  ) -join "`n"
  $text += "`n"
  $partial = "$Path.partial.$PID"
  try {
    [System.IO.File]::WriteAllText($partial, $text, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($partial, $Path, $true)
  } finally {
    if (Test-AnyPath $partial) {
      Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    }
  }
}

function Invoke-InstallOne {
  param([Parameter(Mandatory)][object]$Action)
  $record = $Action.Record
  $skillsDirectory = Split-Path -Parent $Action.Destination
  $operationId = [Guid]::NewGuid().ToString("N")
  $partial = Join-Path $skillsDirectory ".$($record.Name).superbrowky.partial.$operationId"
  $previous = Join-Path $skillsDirectory ".$($record.Name).superbrowky.previous.$operationId"
  $newBackup = $Action.Backup
  $newBackupType = $Action.BackupType
  $newBackupHash = $Action.BackupHash
  New-Item -ItemType Directory -Path $skillsDirectory -Force | Out-Null
  foreach ($path in @($partial, $previous)) {
    if (Test-AnyPath $path) { throw "Unexpected operation path already exists: $path" }
  }
  Copy-DirectoryContents -Source $record.Stage -Destination $partial
  if ((Get-TreeHash -Root $partial) -ne $record.TreeHash) {
    Remove-Item -LiteralPath $partial -Recurse -Force -ErrorAction SilentlyContinue
    throw "$($record.Harness)/$($record.Name): partial copy hash mismatch"
  }

  try {
    switch ($Action.Action) {
      "NOOP" {
        if ((Get-TreeHash -Root $Action.Destination) -ne $record.TreeHash) {
          throw "$($record.Harness)/$($record.Name): managed copy changed after preflight"
        }
        Remove-Item -LiteralPath $partial -Recurse -Force
      }
      "INSTALL" {
        if (Test-AnyPath $Action.Destination) {
          throw "$($record.Harness)/$($record.Name): destination appeared after preflight"
        }
        Move-Item -LiteralPath $partial -Destination $Action.Destination
      }
      "BACKUP" {
        $originalFingerprint = Get-BackupFingerprint -Path $Action.Destination
        $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
        $newBackup = Join-Path (Join-Path (Join-Path (Join-Path $StateHome "backups") $timestamp) $record.Harness) $record.Name
        if (Test-AnyPath $newBackup) { $newBackup = "$newBackup.$operationId" }
        Assert-BackupBoundary -Path $newBackup
        New-Item -ItemType Directory -Path (Split-Path -Parent $newBackup) -Force | Out-Null
        Assert-BackupBoundary -Path $newBackup
        Move-Item -LiteralPath $Action.Destination -Destination $newBackup
        $movedFingerprint = Get-BackupFingerprint -Path $newBackup
        if ($movedFingerprint.Type -ne $originalFingerprint.Type -or
            $movedFingerprint.Hash -ne $originalFingerprint.Hash) {
          if (-not (Test-AnyPath $Action.Destination)) {
            Move-Item -LiteralPath $newBackup -Destination $Action.Destination -ErrorAction SilentlyContinue
          }
          throw "$($record.Harness)/$($record.Name): moved original changed during backup"
        }
        $newBackupType = $movedFingerprint.Type
        $newBackupHash = $movedFingerprint.Hash
        try {
          Assert-BackupFingerprint -Path $newBackup -ExpectedType $newBackupType -ExpectedHash $newBackupHash
          Move-Item -LiteralPath $partial -Destination $Action.Destination
        } catch {
          if (-not (Test-AnyPath $Action.Destination)) {
            Assert-BackupFingerprint -Path $newBackup -ExpectedType $newBackupType -ExpectedHash $newBackupHash
            Move-Item -LiteralPath $newBackup -Destination $Action.Destination -ErrorAction SilentlyContinue
          }
          throw
        }
      }
      "REPLACE" {
        if ((Get-TreeHash -Root $Action.Destination) -ne $Action.ExpectedLiveHash) {
          throw "$($record.Harness)/$($record.Name): managed copy changed after preflight"
        }
        Move-Item -LiteralPath $Action.Destination -Destination $previous
        if ((Get-TreeHash -Root $previous) -ne $Action.ExpectedLiveHash) {
          if (-not (Test-AnyPath $Action.Destination)) {
            Move-Item -LiteralPath $previous -Destination $Action.Destination -ErrorAction SilentlyContinue
          }
          throw "$($record.Harness)/$($record.Name): moved live tree failed verification"
        }
        try {
          Move-Item -LiteralPath $partial -Destination $Action.Destination
        } catch {
          if (-not (Test-AnyPath $Action.Destination) -and
              (Get-TreeHash -Root $previous) -eq $Action.ExpectedLiveHash) {
            Move-Item -LiteralPath $previous -Destination $Action.Destination -ErrorAction SilentlyContinue
          }
          throw
        }
      }
      default { throw "Unknown install action: $($Action.Action)" }
    }

    if ($Action.Action -eq "NOOP") {
      Write-Ok "$($record.Harness)/$($record.Name) (NOOP)"
      return
    }

    if ((Get-TreeHash -Root $Action.Destination) -ne $record.TreeHash) {
      throw "$($record.Harness)/$($record.Name): installed tree failed final verification"
    }
    if ($newBackup -ne "-") {
      Assert-BackupFingerprint -Path $newBackup -ExpectedType $newBackupType -ExpectedHash $newBackupHash
    }
    if ($Action.Action -eq "REPLACE" -and
        (Get-TreeHash -Root $previous) -ne $Action.ExpectedLiveHash) {
      throw "$($record.Harness)/$($record.Name): moved live tree changed before receipt write"
    }

    try {
      Write-Receipt `
        -Path $Action.Receipt `
        -Action $Action `
        -Backup $newBackup `
        -BackupType $newBackupType `
        -BackupHash $newBackupHash
    } catch {
      Write-Fail "$($record.Harness)/$($record.Name): receipt write failed; rolling back"
      $receiptError = $_.Exception.Message
      try {
        if ((Get-TreeHash -Root $Action.Destination) -ne $record.TreeHash) {
          throw "new managed tree changed; refusing rollback delete"
        }
        Remove-Item -LiteralPath $Action.Destination -Recurse -Force
        switch ($Action.Action) {
          "BACKUP" {
            Assert-BackupFingerprint -Path $newBackup -ExpectedType $newBackupType -ExpectedHash $newBackupHash
            Move-Item -LiteralPath $newBackup -Destination $Action.Destination
          }
          "REPLACE" {
            if ((Get-TreeHash -Root $previous) -ne $Action.ExpectedLiveHash) {
              throw "moved live tree changed; refusing rollback restore"
            }
            Move-Item -LiteralPath $previous -Destination $Action.Destination
          }
        }
      } catch {
        throw "receipt write failed ($receiptError); rollback blocked: $($_.Exception.Message)"
      }
      throw "receipt write failed: $receiptError"
    }
    if ($Action.Action -eq "REPLACE" -and (Test-AnyPath $previous)) {
      if ((Get-TreeHash -Root $previous) -ne $Action.ExpectedLiveHash) {
        throw "$($record.Harness)/$($record.Name): moved live tree changed before cleanup; preserved $previous"
      }
      Remove-Item -LiteralPath $previous -Recurse -Force
    }
    Write-Ok "$($record.Harness)/$($record.Name) ($($Action.Action))"
  } finally {
    if (Test-AnyPath $partial) {
      try {
        if ((Get-TreeHash -Root $partial) -eq $record.TreeHash) {
          Remove-Item -LiteralPath $partial -Recurse -Force
        } else {
          Write-Warn "$($record.Harness)/$($record.Name): preserved changed operation tree $partial"
        }
      } catch {
        Write-Warn "$($record.Harness)/$($record.Name): preserved unsafe operation tree $partial"
      }
    }
  }
}

function Invoke-ApplyInstall {
  param([object[]]$Actions)
  $changed = 0
  $failed = 0
  foreach ($action in $Actions) {
    try {
      Invoke-InstallOne -Action $action
      if ($action.Action -ne "NOOP") { $changed++ }
    } catch {
      Write-Fail "$($action.Record.Harness)/$($action.Record.Name): $($_.Exception.Message)"
      $failed++
    }
  }
  if ($failed -gt 0) {
    if ($changed -gt 0) {
      Write-Status "PARTIAL — $changed changed, $failed failed. Receipts identify managed copies."
      return 2
    } else {
      Write-Status "BLOCKED — apply failed before any skill changed."
      return 1
    }
  }
  Write-Status "READY — all selected skills are installed and receipt-verified."
  return 0
}

function Get-UninstallActions {
  $actions = [System.Collections.Generic.List[object]]::new()
  $problems = 0
  foreach ($forHarness in (Get-Harnesses $Harness)) {
    $stateDirectory = Join-Path (Join-Path $StateHome "state") $forHarness
    if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) {
      Write-Fail "$forHarness`: no receipt directory; refusing manifest-based removal"
      $problems++
      continue
    }
    $receipts = @(Get-ChildItem -LiteralPath $stateDirectory -Filter "*.receipt.tsv" -File | Sort-Object Name)
    if ($receipts.Count -eq 0) {
      Write-Fail "$forHarness`: no receipts; refusing uninstall"
      $problems++
      continue
    }
    foreach ($receiptFile in $receipts) {
      $receipt = Get-Receipt -Path $receiptFile.FullName
      $name = if ($receipt.ContainsKey("name")) { $receipt["name"] } else { "" }
      $receiptHarness = if ($receipt.ContainsKey("harness")) { $receipt["harness"] } else { "" }
      $destination = if ($receipt.ContainsKey("dest")) { $receipt["dest"] } else { "" }
      $expectedHash = if ($receipt.ContainsKey("tree_hash")) { $receipt["tree_hash"] } else { "" }
      $backup = if ($receipt.ContainsKey("backup") -and -not [string]::IsNullOrWhiteSpace($receipt["backup"])) {
        $receipt["backup"]
      } else { "-" }
      $backupType = if ($receipt.ContainsKey("backup_type")) { $receipt["backup_type"] } else { "" }
      $backupHash = if ($receipt.ContainsKey("backup_hash")) { $receipt["backup_hash"] } else { "" }
      $expectedDestination = Join-Path (Get-SkillsDirectory $forHarness) $name
      if ($name -notmatch "^[a-z0-9]+(?:-[a-z0-9]+)*$" -or
          $receiptHarness -ne $forHarness -or $destination -ne $expectedDestination) {
        Write-Fail "$forHarness/$name`: receipt ownership boundary mismatch"
        $problems++
        continue
      }
      if (-not (Test-RealDirectory $destination)) {
        Write-Fail "$forHarness/$name`: installed copy is missing or not a real directory"
        $problems++
        continue
      }
      if ([string]::IsNullOrWhiteSpace($expectedHash) -or (Get-TreeHash -Root $destination) -ne $expectedHash) {
        Write-Fail "$forHarness/$name`: installed copy drifted; leaving it untouched"
        $problems++
        continue
      }
      if ($backup -eq "-") {
        if ($backupType -ne "-" -or $backupHash -ne "-") {
          Write-Fail "$forHarness/$name`: backup path/type/hash metadata is incomplete"
          $problems++
          continue
        }
      } else {
        try {
          Assert-BackupFingerprint -Path $backup -ExpectedType $backupType -ExpectedHash $backupHash
        } catch {
          Write-Fail "$forHarness/$name`: $($_.Exception.Message)"
          $problems++
          continue
        }
      }
      $actions.Add([pscustomobject]@{
        Harness = $forHarness
        Name = $name
        Destination = $destination
        Receipt = $receiptFile.FullName
        Backup = $backup
        BackupType = if ($backup -eq "-") { "-" } else { $backupType }
        BackupHash = if ($backup -eq "-") { "-" } else { $backupHash }
        ExpectedLiveHash = $expectedHash
      })
    }
  }
  if ($actions.Count -eq 0) { $problems++ }
  if ($problems -gt 0) { throw "$problems uninstall ownership or drift problem(s)" }
  return @($actions)
}

function Invoke-UninstallOne {
  param([Parameter(Mandatory)][object]$Action)
  $previous = "$($Action.Destination).superbrowky-removing.$([Guid]::NewGuid().ToString('N'))"
  if (Test-AnyPath $previous) { throw "Unexpected uninstall operation path already exists: $previous" }
  if ((Get-TreeHash -Root $Action.Destination) -ne $Action.ExpectedLiveHash) {
    throw "managed copy changed after uninstall preflight"
  }
  Move-Item -LiteralPath $Action.Destination -Destination $previous
  try {
    if ((Get-TreeHash -Root $previous) -ne $Action.ExpectedLiveHash) {
      if (-not (Test-AnyPath $Action.Destination)) {
        Move-Item -LiteralPath $previous -Destination $Action.Destination -ErrorAction SilentlyContinue
      }
      throw "moved live tree failed verification"
    }
    if ($Action.Backup -ne "-") {
      Assert-BackupFingerprint `
        -Path $Action.Backup `
        -ExpectedType $Action.BackupType `
        -ExpectedHash $Action.BackupHash
      Move-Item -LiteralPath $Action.Backup -Destination $Action.Destination
      $restored = Get-BackupFingerprint -Path $Action.Destination
      if ($restored.Type -ne $Action.BackupType -or $restored.Hash -ne $Action.BackupHash) {
        throw "restored original failed type/hash verification"
      }
    }
    try {
      if ((Get-TreeHash -Root $previous) -ne $Action.ExpectedLiveHash) {
        throw "moved live tree changed before receipt removal"
      }
      Remove-Item -LiteralPath $Action.Receipt -Force
    } catch {
      if ($Action.Backup -ne "-" -and (Test-AnyPath $Action.Destination)) {
        $restored = Get-BackupFingerprint -Path $Action.Destination
        if ($restored.Type -ne $Action.BackupType -or $restored.Hash -ne $Action.BackupHash) {
          throw "receipt removal failed and restored original changed; refusing rollback move"
        }
        Assert-BackupBoundary -Path $Action.Backup
        Move-Item -LiteralPath $Action.Destination -Destination $Action.Backup
      }
      if (-not (Test-AnyPath $Action.Destination) -and
          (Get-TreeHash -Root $previous) -eq $Action.ExpectedLiveHash) {
        Move-Item -LiteralPath $previous -Destination $Action.Destination
      }
      throw
    }
    if ((Get-TreeHash -Root $previous) -ne $Action.ExpectedLiveHash) {
      throw "moved live tree changed before cleanup; preserved $previous"
    }
    Remove-Item -LiteralPath $previous -Recurse -Force
    if ($Action.Backup -eq "-") {
      Write-Ok "removed $($Action.Harness)/$($Action.Name)"
    } else {
      Write-Ok "restored original $($Action.Harness)/$($Action.Name)"
    }
  } catch {
    if (-not (Test-AnyPath $Action.Destination) -and (Test-AnyPath $previous)) {
      if ((Get-TreeHash -Root $previous) -eq $Action.ExpectedLiveHash) {
        Move-Item -LiteralPath $previous -Destination $Action.Destination -ErrorAction SilentlyContinue
      }
    }
    throw
  }
}

function Invoke-CheckUpdates {
  param([object[]]$Selected)
  if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Fail "git is required for -CheckUpdates"
    Write-Status "BLOCKED — cannot query upstream refs."
    return 1
  }
  Write-Host "Pinned source update check — profile=$Profile"
  $seen = @{}
  $failures = 0
  $updates = 0
  foreach ($skill in $Selected) {
    if ($skill.SourceType -ne "git" -or $seen.ContainsKey($skill.Repo)) { continue }
    $seen[$skill.Repo] = $true
    $locked = Get-LockPin -Key $skill.PinKey
    if ([string]::IsNullOrWhiteSpace($locked)) {
      Write-Fail "$($skill.Repo): missing pin '$($skill.PinKey)'"
      $failures++
      continue
    }
    $output = & git ls-remote "https://github.com/$($skill.Repo).git" HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Select-Object -First 1))) {
      Write-Warn "$($skill.Repo): upstream unreachable"
      $failures++
      continue
    }
    $latest = (($output | Select-Object -First 1) -split "\s+")[0]
    if ($latest -eq $locked) {
      Write-Ok "$($skill.Repo) ($($locked.Substring(0, [Math]::Min(12, $locked.Length))))"
    } else {
      $updates++
      Write-Warn "$($skill.Repo): $($locked.Substring(0, 12)) -> $($latest.Substring(0, 12))"
      Write-Host "  $($skill.PinKey)=$latest"
    }
  }
  if ($failures -gt 0) {
    Write-Status "PARTIAL — $failures source(s) could not be checked; nothing changed."
    return 2
  }
  Write-Status "READY — update check complete; $updates pin update(s) available."
  return 0
}

$exitCode = 0
try {
  if ($Apply -and $DryRun) { throw "-Apply and -DryRun conflict" }
  if ($Latest -and $Apply) {
    throw "-Latest is plan-only. Review and pin the exact commit before -Apply."
  }
  if ($CheckUpdates -and $Uninstall) { throw "-CheckUpdates and -Uninstall conflict" }
  if ($CheckUpdates -and $Apply) { throw "-CheckUpdates is always read-only; remove -Apply" }
  if ($Uninstall -and $Latest) { throw "-Latest does not apply to -Uninstall" }
  if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) { throw "Missing versions.lock" }

  if ($Harness -eq "auto") {
    $detected = Resolve-AutoHarness
    if ([string]::IsNullOrWhiteSpace($detected)) {
      Write-Fail "Could not detect Claude Code or Codex"
      Write-Status "BLOCKED — rerun with -Harness claude, codex, or both."
      exit 1
    }
    $Harness = $detected
    Write-Ok "auto-detected harness: $Harness"
  }

  $selected = @(Get-SelectedSkills)

  if ($CheckUpdates) {
    exit (Invoke-CheckUpdates -Selected $selected)
  }

  if ($Uninstall) {
    try {
      $uninstallActions = @(Get-UninstallActions)
    } catch {
      Write-Fail $_.Exception.Message
      Write-Status "BLOCKED — uninstall requires valid, drift-free receipts for the requested harness."
      exit 1
    }
    Write-Host "Receipt-backed uninstall plan — harness=$Harness"
    foreach ($action in $uninstallActions) {
      if ($action.Backup -eq "-") {
        Write-Host ("  REMOVE  {0,-7} {1}" -f $action.Harness, $action.Name)
      } else {
        Write-Host ("  RESTORE {0,-7} {1} (remove managed copy, restore original)" -f $action.Harness, $action.Name)
      }
    }
    Write-Host "`nOnly hash-matching receipt-owned directories are eligible."
    if (-not $Apply) {
      Write-Status "READY — uninstall plan only; rerun with -Apply."
      exit 0
    }
    $changed = 0
    $failed = 0
    foreach ($action in $uninstallActions) {
      try {
        Invoke-UninstallOne -Action $action
        $changed++
      } catch {
        Write-Fail "$($action.Harness)/$($action.Name): $($_.Exception.Message)"
        $failed++
      }
    }
    if ($failed -gt 0) {
      Write-Status "PARTIAL — $changed removed/restored, $failed failed."
      exit 2
    }
    Write-Status "READY — receipt-owned skills uninstalled; recorded originals restored."
    exit 0
  }

  if (-not $Apply) {
    if ($Latest) {
      Resolve-SourceRefs -Selected $selected -AllowLatestNetwork
    } else {
      Resolve-SourceRefs -Selected $selected
    }
    exit (Show-InstallPlan -Selected $selected)
  }

  if ($Latest) {
    Write-Warn "UNSAFE -Latest selected: unreviewed upstream HEADs may change behavior"
  }
  Resolve-SourceRefs -Selected $selected -AllowLatestNetwork
  $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("superbrowky-install-" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $script:TempRoot | Out-Null
  Write-Host "Staging every selected skill before live changes"
  try {
    $stageRecords = @(Stage-AllSkills -Selected $selected)
    Invoke-DeepValidation
  } catch {
    Write-Fail $_.Exception.Message
    Write-Status "BLOCKED — staging/validation failed; no live files changed."
    exit 1
  }
  try {
    $actions = @(Get-InstallActions -StageRecords $stageRecords)
  } catch {
    Write-Fail $_.Exception.Message
    Write-Status "BLOCKED — drift or receipt conflict detected; no live files changed."
    exit 1
  }
  Write-Host "Validated apply plan — harness=$Harness profile=$Profile"
  foreach ($action in $actions) {
    $record = $action.Record
    Write-Host ("  {0,-7} {1,-7} {2,-30} {3} @ {4}" -f
      $action.Action, $record.Harness, $record.Name, $record.Source,
      $record.Ref.Substring(0, [Math]::Min(12, $record.Ref.Length)))
  }
  Write-Host "`nAll selected skills were staged and validated before this plan."
  $exitCode = Invoke-ApplyInstall -Actions $actions
} catch {
  Write-Fail $_.Exception.Message
  Write-Status "BLOCKED — installer validation failed."
  $exitCode = 2
} finally {
  if ($null -ne $script:TempRoot -and (Test-AnyPath $script:TempRoot)) {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

exit $exitCode

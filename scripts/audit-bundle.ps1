#!/usr/bin/env pwsh
# Build a shareable, redacted SUPERBROWKY v4 installation audit.

[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)]
  [string]$Target,

  [ValidateSet("auto", "claude", "codex", "both")]
  [string]$Harness = "auto",

  [ValidateSet("core", "web-launch", "growth", "full")]
  [string]$Profile = "core",

  [string]$Output,

  [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$KitRoot = Split-Path -Parent $PSScriptRoot
$ClaudeHomeExplicit = -not [string]::IsNullOrWhiteSpace($env:CLAUDE_HOME)
$CodexHomeExplicit = -not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)
$ClaudeHome = if ($ClaudeHomeExplicit) { $env:CLAUDE_HOME } else { Join-Path $HOME ".claude" }
$CodexHome = if ($CodexHomeExplicit) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$StateHome = if (-not [string]::IsNullOrWhiteSpace($env:SUPERBROWKY_STATE_HOME)) {
  $env:SUPERBROWKY_STATE_HOME
} else {
  Join-Path $HOME ".superbrowky"
}

function Get-NormalizedPath {
  param([string]$Path)
  return [IO.Path]::GetFullPath($Path).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
  )
}

function Test-PathUnderRoot {
  param([string]$Path, [string]$Root, [switch]$AllowRoot)
  try {
    $pathFull = Get-NormalizedPath $Path
    $rootFull = Get-NormalizedPath $Root
  } catch {
    return $false
  }
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if ($pathFull.Equals($rootFull, $comparison)) { return [bool]$AllowRoot }
  return $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, $comparison)
}

function Test-SamePath {
  param([string]$Left, [string]$Right)
  try {
    $leftFull = Get-NormalizedPath $Left
    $rightFull = Get-NormalizedPath $Right
  } catch {
    return $false
  }
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  return $leftFull.Equals($rightFull, $comparison)
}

function Format-PathUnderRoot {
  param([string]$Path, [string]$Root, [string]$Label)
  $pathFull = Get-NormalizedPath $Path
  $rootFull = Get-NormalizedPath $Root
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  if ($pathFull.Equals($rootFull, $comparison)) { return $Label }
  return $Label + "/" + $pathFull.Substring($rootFull.Length + 1).Replace("\", "/")
}

function Redact-Path {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return "-" }
  try {
    if (Test-PathUnderRoot -Path $Path -Root $HOME -AllowRoot) {
      return Format-PathUnderRoot -Path $Path -Root $HOME -Label "~"
    }
    foreach ($boundary in @(
      [pscustomobject]@{ Root = $Target; Label = '$PROJECT_ROOT' },
      [pscustomobject]@{ Root = $ClaudeHome; Label = '$CLAUDE_HOME' },
      [pscustomobject]@{ Root = $CodexHome; Label = '$CODEX_HOME' },
      [pscustomobject]@{ Root = $StateHome; Label = '$SUPERBROWKY_STATE_HOME' }
    )) {
      if (-not [string]::IsNullOrWhiteSpace($boundary.Root) -and
          (Test-PathUnderRoot -Path $Path -Root $boundary.Root -AllowRoot)) {
        return Format-PathUnderRoot -Path $Path -Root $boundary.Root -Label $boundary.Label
      }
    }
  } catch {
    return '$INVALID_PATH'
  }
  return '$EXTERNAL_PATH'
}

function ConvertTo-AuditCell {
  param([AllowEmptyString()][string]$Value, [int]$MaximumLength = 200)
  if ($null -eq $Value) { return "?" }
  $safe = $Value -replace '[\x00-\x1f\x7f]', ' '
  $safe = $safe.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
  $safe = $safe.Replace("|", "¦").Replace([char]96, [char]39)
  if ($safe.Length -gt $MaximumLength) {
    $safe = $safe.Substring(0, $MaximumLength) + "…"
  }
  return $safe
}

function Get-SkillsDirectory {
  param([string]$Value)
  if ($Value -eq "claude") { return Join-Path $ClaudeHome "skills" }
  return Join-Path $CodexHome "skills"
}

function Get-AllTemplateNames {
  return @(
    "HARNESS.md",
    "PROJECT.md",
    "PRODUCT.md",
    "DESIGN.md",
    "Decision.md",
    "Feedback.md",
    "CLAUDE.md",
    "AGENTS.md"
  )
}

function Test-SafeSourceLabel {
  param([string]$Value)
  $folder = $null
  if ($Value -match '^bundled:([^+]+)(?:\+[A-Za-z0-9_.+-]+)*$') {
    $folder = $Matches[1]
  } elseif ($Value -match '^git:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+:([^+]+)(?:\+[A-Za-z0-9_.+-]+)*$') {
    $folder = $Matches[1]
  } else {
    return $false
  }
  if ($folder -eq ".") { return $true }
  if ([IO.Path]::IsPathRooted($folder) -or $folder.Contains("\")) { return $false }
  foreach ($segment in ($folder -split "/")) {
    if ([string]::IsNullOrWhiteSpace($segment) -or
        $segment -eq ".." -or
        $segment -notmatch '^[A-Za-z0-9._-]+$') {
      return $false
    }
  }
  return $true
}

function Test-SafeProjectReceiptRow {
  param([string]$Kind, [string]$Relative, [string]$Hash, [string]$Source)
  if ($Source -notmatch '^template/([^/\\]+)$') { return $false }
  $name = $Matches[1]
  if ($name -notin (Get-AllTemplateNames) -or
      $Hash -notmatch '^[0-9a-f]{64}$' -or
      [IO.Path]::IsPathRooted($Relative) -or
      $Relative -match '(^|[\\/])\.\.([\\/]|$)') {
    return $false
  }
  if ($Kind -in @("installed", "observed")) { return $Relative -eq $name }
  if ($Kind -eq "candidate") {
    return -not $Relative.Contains("/") -and
      -not $Relative.Contains("\") -and
      $Relative.StartsWith("$name.from-superbrowky-v4-", [StringComparison]::Ordinal)
  }
  return $false
}

function Test-IsReparsePoint {
  param([System.IO.FileSystemInfo]$Item)
  return -not [string]::IsNullOrWhiteSpace([string]$Item.LinkType) -or
    (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-Receipt {
  param([string]$Path)
  $values = @{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $values }
  foreach ($line in [IO.File]::ReadAllLines($Path)) {
    $separator = $line.IndexOf("`t")
    if ($separator -gt 0) {
      $values[$line.Substring(0, $separator)] = $line.Substring($separator + 1).TrimEnd("`r")
    }
  }
  return $values
}

function Get-Harnesses {
  param([string]$Value)
  if ($Value -eq "both") { return @("claude", "codex") }
  return @($Value)
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

function Get-PowerShellExecutable {
  $candidate = if ($IsWindows) { Join-Path $PSHOME "pwsh.exe" } else { Join-Path $PSHOME "pwsh" }
  if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  $command = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($null -eq $command) { throw "PowerShell 7 executable not found" }
  return $command.Source
}

if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
  Write-Host "[x] Not a directory: $(Redact-Path $Target)" -ForegroundColor Red
  exit 1
}
$Target = (Resolve-Path -LiteralPath $Target).Path
if ($Harness -eq "auto") {
  $Harness = Resolve-AutoHarness
  if ([string]::IsNullOrWhiteSpace($Harness)) {
    Write-Host "[x] Could not detect Claude Code or Codex" -ForegroundColor Red
    exit 1
  }
}

$timestampFile = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$destination = if (-not [string]::IsNullOrWhiteSpace($Output)) {
  if (-not $Output.EndsWith(".md", [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "[x] -Output must end in .md" -ForegroundColor Red
    exit 2
  }
  [IO.Path]::GetFullPath($Output)
} else {
  Join-Path (Join-Path $Target "AuditBundles") "SUPERBROWKY-Audit-$timestampFile.md"
}
if (Test-Path -LiteralPath $destination) {
  Write-Host "[x] Refusing to overwrite existing audit summary: $(Redact-Path $destination)" -ForegroundColor Red
  exit 1
}
if (-not $Apply) {
  Write-Host "SUPERBROWKY audit bundle plan"
  Write-Host "  Project: $(Redact-Path $Target)"
  Write-Host "  Harness: $Harness"
  Write-Host "  Profile: $Profile"
  Write-Host "  WRITE:   $(Redact-Path $destination)"
  Write-Host ""
  Write-Host "PLAN ONLY — no file was written. Re-run with -Apply."
  exit 0
}

$doctorPath = Join-Path $PSScriptRoot "doctor.ps1"
$pwsh = Get-PowerShellExecutable
$doctorOutput = @(& $pwsh -NoLogo -NoProfile -File $doctorPath -Target $Target -Harness $Harness -Profile $Profile 2>&1)
$doctorExit = $LASTEXITCODE
$statusLine = ($doctorOutput | ForEach-Object { [string]$_ } | Where-Object { $_ -like "STATUS:*" } | Select-Object -Last 1)
if ([string]::IsNullOrWhiteSpace($statusLine)) { $statusLine = "STATUS: BLOCKED — doctor did not return a status." }
$statusDetail = ConvertTo-AuditCell -Value ($statusLine.Substring(7).Trim()) -MaximumLength 300

$gitRef = "local"
if ($null -ne (Get-Command git -ErrorAction SilentlyContinue)) {
  $candidate = & git -C $KitRoot rev-parse HEAD 2>$null
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($candidate)) {
    $gitRef = ($candidate | Select-Object -First 1).Trim()
  }
}
if ($gitRef -notmatch '^(?:[0-9a-fA-F]{40,64}|local)$') { $gitRef = "invalid" }

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# SUPERBROWKY Audit Bundle")
$lines.Add("")
$lines.Add("- Generated: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
$lines.Add("- Kit ref: ``$(ConvertTo-AuditCell $gitRef)``")
$lines.Add("- Project: ``$(Redact-Path $Target)``")
$lines.Add("- Harness: ``$Harness``")
$lines.Add("- Profile: ``$Profile``")
$lines.Add("- Doctor: $statusDetail")
$lines.Add("")
$lines.Add("## Managed skills")
$lines.Add("")
$lines.Add("| Harness | Skill | Source | Ref | Tree hash | Destination | Backup | Backup type | Backup hash |")
$lines.Add("|---|---|---|---|---|---|---|---|---|")
foreach ($forHarness in (Get-Harnesses $Harness)) {
  $receiptDirectory = Join-Path (Join-Path $StateHome "state") $forHarness
  if (-not (Test-Path -LiteralPath $receiptDirectory -PathType Container)) {
    $lines.Add("| $forHarness | — | receipt directory missing | — | — | — | — | — | — |")
    continue
  }
  foreach ($file in @(Get-ChildItem -LiteralPath $receiptDirectory -Filter "*.receipt.tsv" -File | Sort-Object Name)) {
    $receipt = Get-Receipt $file.FullName
    $expectedName = $file.Name.Substring(0, $file.Name.Length - ".receipt.tsv".Length)
    $name = if ($receipt.ContainsKey("name") -and
                $receipt["name"] -eq $expectedName -and
                $receipt["name"] -match '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
      $receipt["name"]
    } else {
      "invalid-receipt"
    }
    $source = if ($receipt.ContainsKey("source") -and
                  (Test-SafeSourceLabel $receipt["source"])) {
      $receipt["source"]
    } else { "invalid" }
    $ref = if ($receipt.ContainsKey("ref") -and
               $receipt["ref"] -match '^(?:[0-9a-fA-F]{40,64}|local)$') {
      $receipt["ref"]
    } else { "invalid" }
    $hash = if ($receipt.ContainsKey("tree_hash") -and
                $receipt["tree_hash"] -match '^[0-9a-f]{64}$') {
      $receipt["tree_hash"]
    } else { "invalid" }
    $expectedDestination = Join-Path (Get-SkillsDirectory $forHarness) $expectedName
    $dest = if ($receipt.ContainsKey("dest") -and
                (Test-SamePath -Left $receipt["dest"] -Right $expectedDestination)) {
      Redact-Path $expectedDestination
    } else { '$INVALID_RECEIPT_PATH' }
    $backup = "-"
    $backupType = "-"
    $backupHash = "-"
    if ($receipt.ContainsKey("backup") -and $receipt["backup"] -ne "-") {
      if (Test-PathUnderRoot -Path $receipt["backup"] -Root (Join-Path $StateHome "backups")) {
        $backup = Redact-Path $receipt["backup"]
      } else {
        $backup = '$INVALID_RECEIPT_PATH'
      }
      $backupType = if ($receipt.ContainsKey("backup_type") -and
                       $receipt["backup_type"] -in @("directory", "file", "link")) {
        $receipt["backup_type"]
      } else { "invalid" }
      $backupHash = if ($receipt.ContainsKey("backup_hash") -and
                       $receipt["backup_hash"] -match '^[0-9a-f]{64}$') {
        $receipt["backup_hash"]
      } else { "invalid" }
    }
    $lines.Add(
      "| $forHarness | $(ConvertTo-AuditCell $name) | ``$(ConvertTo-AuditCell $source)`` | " +
      "``$(ConvertTo-AuditCell $ref)`` | ``$(ConvertTo-AuditCell $hash)`` | " +
      "``$(ConvertTo-AuditCell $dest)`` | ``$(ConvertTo-AuditCell $backup)`` | " +
      "``$(ConvertTo-AuditCell $backupType)`` | ``$(ConvertTo-AuditCell $backupHash)`` |"
    )
  }
}
$lines.Add("")
$lines.Add("## Project harness")
$lines.Add("")
$projectReceipt = Join-Path (Join-Path $Target ".superbrowky") "project-receipt.tsv"
if (Test-Path -LiteralPath $projectReceipt -PathType Leaf) {
  $lines.Add("| Kind | Relative path | SHA-256 | Source |")
  $lines.Add("|---|---|---|---|")
  foreach ($line in [IO.File]::ReadAllLines($projectReceipt)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
    $fields = $line.TrimEnd("`r").Split([char]"`t", [StringSplitOptions]::None)
    if ($fields.Count -eq 4 -and
        (Test-SafeProjectReceiptRow -Kind $fields[0] -Relative $fields[1] -Hash $fields[2] -Source $fields[3])) {
      $lines.Add(
        "| $(ConvertTo-AuditCell $fields[0]) | ``$(ConvertTo-AuditCell $fields[1])`` | " +
        "``$(ConvertTo-AuditCell $fields[2])`` | ``$(ConvertTo-AuditCell $fields[3])`` |"
      )
    } else {
      $lines.Add("| invalid | ``invalid`` | ``invalid`` | ``invalid project receipt metadata`` |")
    }
  }
} else {
  $lines.Add("Project receipt is missing.")
}
$lines.Add("")
$lines.Add("## Merge candidates")
$lines.Add("")
$candidates = @(Get-ChildItem -LiteralPath $Target -File -Filter "*.from-superbrowky-v4-*" -ErrorAction SilentlyContinue | Sort-Object Name)
if ($candidates.Count -eq 0) {
  $lines.Add("None.")
} else {
  foreach ($candidate in $candidates) {
    if (Test-IsReparsePoint -Item $candidate) {
      $lines.Add("- ``invalid merge-candidate reparse point``")
      continue
    }
    $hash = (Get-FileHash -LiteralPath $candidate.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $lines.Add("- ``$(ConvertTo-AuditCell $candidate.Name)`` — ``$hash``")
  }
}
$lines.Add("")
$lines.Add("## Runtime")
$lines.Add("")
$lines.Add("- PowerShell: ``$($PSVersionTable.PSVersion)``")
$node = Get-Command node -ErrorAction SilentlyContinue
if ($null -eq $node) {
  $lines.Add("- Node.js: not found (optional helpers unavailable)")
} else {
  $nodeVersion = (& $node.Source --version 2>$null | Select-Object -First 1)
  $lines.Add("- Node.js: ``$(ConvertTo-AuditCell -Value ([string]$nodeVersion) -MaximumLength 80)``")
}
$lines.Add("")
$lines.Add("## Privacy boundary")
$lines.Add("")
$lines.Add("This bundle contains installation metadata and hashes only. It excludes file contents, chat transcripts, hidden reasoning, tokens, cookies, credentials, and environment values.")

$stateDirectory = Split-Path -Parent $destination
New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
$partial = "$destination.partial.$PID"
$text = ($lines -join "`n") + "`n"
try {
  [IO.File]::WriteAllText($partial, $text, [Text.UTF8Encoding]::new($false))
  [IO.File]::Move($partial, $destination, $true)
} finally {
  if (Test-Path -LiteralPath $partial -PathType Leaf) {
    Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "[ok] wrote $(Redact-Path $destination)" -ForegroundColor Green
Write-Host $statusLine
if ($doctorExit -eq 1) { exit 1 }
if ($doctorExit -eq 2) { exit 2 }
exit 0

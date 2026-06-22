#!/usr/bin/env pwsh
# Claude Code Design Kit — machine-wide skill installer (Windows / PowerShell).
#
# PowerShell parity for install-skills.sh. Installs into $HOME\.claude\skills:
#   - the taste skills + the SEO/prose skills, from PINNED upstream snapshots
#     (fetched from source; nothing republished, each author keeps their license)
#   - the kit's own bundled skills (skills\ in this repo)
# Versions are pinned in versions.lock (shared with the bash installer).
#
#   pwsh -File install-skills.ps1                 # pinned (default)
#   pwsh -File install-skills.ps1 -Latest         # upstream HEAD (may drift)
#   pwsh -File install-skills.ps1 -DryRun         # show actions, write nothing
#   pwsh -File install-skills.ps1 -CheckUpdates   # report drift, read-only
#   pwsh -File install-skills.ps1 -Uninstall      # remove kit skills, restore backups
#
# Requires: tar (bundled with Windows 10+), git (for -CheckUpdates), Node 24+
# (for impeccable, installed per-project — not here).

[CmdletBinding()]
param(
  [switch]$Latest,
  [switch]$DryRun,
  [switch]$CheckUpdates,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$SkillsDir = Join-Path $HOME ".claude\skills"
$BackupDir = Join-Path $HOME ".claude\skills-backup"
$LockFile  = Join-Path $Here "versions.lock"

function Write-Ok   { param($m) Write-Host "[ok] $m"   -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "[!] $m"    -ForegroundColor Yellow }
function Write-Bold { param($m) Write-Host $m          -ForegroundColor White }

# Resolve a pinned value from versions.lock by key. Returns $null if absent.
function Get-LockPin {
  param([string]$Key)
  if (-not (Test-Path $LockFile)) { return $null }
  foreach ($line in Get-Content $LockFile) {
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    $eq = $t.IndexOf("=")
    if ($eq -lt 1) { continue }
    if ($t.Substring(0, $eq) -eq $Key) { return $t.Substring($eq + 1) }
  }
  return $null
}

# Manifest: each entry is repo / folder-in-repo / install name. Pin from lock.
$Manifest = @(
  @{ Repo = "emilkowalski/skill";            Folder = "skills/emil-design-eng";    Name = "emil-design-eng" }
  @{ Repo = "Leonxlnx/taste-skill";          Folder = "skills/taste-skill";        Name = "design-taste-frontend" }
  @{ Repo = "Leonxlnx/taste-skill";          Folder = "skills/soft-skill";         Name = "high-end-visual-design" }
  @{ Repo = "Leonxlnx/taste-skill";          Folder = "skills/redesign-skill";     Name = "redesign-existing-projects" }
  @{ Repo = "coreyhaines31/marketingskills"; Folder = "skills/seo-audit";          Name = "seo-audit" }
  @{ Repo = "coreyhaines31/marketingskills"; Folder = "skills/ai-seo";             Name = "ai-seo" }
  @{ Repo = "coreyhaines31/marketingskills"; Folder = "skills/schema";             Name = "schema" }
  @{ Repo = "coreyhaines31/marketingskills"; Folder = "skills/programmatic-seo";   Name = "programmatic-seo" }
  @{ Repo = "coreyhaines31/marketingskills"; Folder = "skills/site-architecture";  Name = "site-architecture" }
  @{ Repo = "coreyhaines31/marketingskills"; Folder = "skills/cro";                Name = "cro" }
  @{ Repo = "hardikpandya/stop-slop";        Folder = ".";                         Name = "stop-slop" }
)
$Bundled = @("psi-optimize", "a11y-audit", "meta-audit")

$ImpeccableVer = Get-LockPin "impeccable-cli"
$ImpeccablePkg = if ($ImpeccableVer) { "impeccable@$ImpeccableVer" } else { "impeccable" }

# --- -CheckUpdates: report drift vs versions.lock (read-only) ---
function Invoke-CheckUpdates {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Warn "git is required for -CheckUpdates."; exit 1 }
  Write-Bold "Checking upstream drift against versions.lock (read-only)"
  $drift = 0; $seen = @()
  foreach ($e in $Manifest) {
    if ($seen -contains $e.Repo) { continue }
    $seen += $e.Repo
    $locked = Get-LockPin $e.Repo
    $latest = (& git ls-remote "https://github.com/$($e.Repo).git" HEAD 2>$null) -split "\s+" | Select-Object -First 1
    if (-not $latest) { Write-Warn "$($e.Repo): couldn't reach upstream — skipped."; continue }
    if ($locked -eq $latest) { Write-Ok "$($e.Repo)  current ($($locked.Substring(0,7)))" }
    else { $drift++; Write-Warn "$($e.Repo)  stale: $($locked.Substring(0,7)) -> $($latest.Substring(0,7))"; Write-Host "    $($e.Repo)=$latest" }
  }
  $locked = Get-LockPin "impeccable-cli"
  if (Get-Command npm -ErrorAction SilentlyContinue) {
    $latest = (& npm view impeccable version 2>$null)
    if ($latest -and $latest -ne $locked) { $drift++; Write-Warn "impeccable-cli  stale: $locked -> $latest"; Write-Host "    impeccable-cli=$latest" }
    else { Write-Ok "impeccable-cli  current ($locked)" }
  } else { Write-Warn "npm not found — skipped impeccable-cli check." }
  Write-Host ""
  if ($drift -eq 0) { Write-Ok "All pins current." }
  else { Write-Bold "$drift update(s) available — paste the lines above into versions.lock, then re-run." }
}

# --- -Uninstall: remove kit skills, restore pre-kit backups ---
function Invoke-Uninstall {
  Write-Bold ("Uninstalling kit-managed skills from {0}{1}" -f $SkillsDir, $(if ($DryRun) { " (dry-run)" } else { "" }))
  $removed = 0; $restored = 0; $absent = 0
  $names = @(); foreach ($e in $Manifest) { $names += $e.Name }; $names += $Bundled
  foreach ($name in $names) {
    $dest = Join-Path $SkillsDir $name
    $backup = Join-Path $BackupDir $name
    if (-not (Test-Path $dest)) { $absent++; continue }
    if (Test-Path $backup) {
      if ($DryRun) { Write-Ok "would restore pre-kit $name from backup" }
      else { Remove-Item -Recurse -Force $dest; Move-Item $backup $dest; Write-Ok "restored pre-kit $name" }
      $restored++
    } else {
      if ($DryRun) { Write-Ok "would remove $name" } else { Remove-Item -Recurse -Force $dest; Write-Ok "removed $name" }
      $removed++
    }
  }
  Write-Host ""
  if ($DryRun) { Write-Bold "DRY RUN: $removed would be removed, $restored restored from backup, $absent not present." }
  else { Write-Ok "Done: $removed removed, $restored restored from backup, $absent not present." }
}

if ($CheckUpdates) { Invoke-CheckUpdates; exit 0 }
if ($Uninstall)    { Invoke-Uninstall;    exit 0 }

# --- download a repo@ref tarball once, return its extracted root dir ---
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ccdk-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null
function Get-Repo {
  param([string]$Repo, [string]$Ref)
  $key = ($Repo + "@" + $Ref) -replace "[/@]", "_"
  $dir = Join-Path $script:Tmp $key
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $tarball = Join-Path $script:Tmp "$key.tar.gz"
    try {
      Invoke-WebRequest -Uri "https://codeload.github.com/$Repo/tar.gz/$Ref" -OutFile $tarball -UseBasicParsing
      & tar -xzf $tarball -C $dir
      if ($LASTEXITCODE -ne 0) { throw "tar failed" }
    } catch {
      Write-Warn "Couldn't download $Repo@$Ref — $($_.Exception.Message)"
      Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
      return $null
    }
  }
  return (Get-ChildItem -Path $dir -Directory | Select-Object -First 1).FullName
}

function Install-SkillFolder {
  param([string]$Src, [string]$Name, [string]$Origin)
  if (-not (Test-Path (Join-Path $Src "SKILL.md"))) {
    Write-Warn "${Origin}: no SKILL.md at $Src (layout changed?) — skipping $Name."
    return $false
  }
  $dest = Join-Path $SkillsDir $Name
  if (Test-Path $dest) {
    $backup = Join-Path $BackupDir $Name
    if (-not (Test-Path $backup)) {
      New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
      Move-Item $dest $backup
      Write-Warn "$Name already existed — original kept at ~\.claude\skills-backup\$Name"
    } else {
      Remove-Item -Recurse -Force $dest
    }
  }
  Copy-Item -Recurse -Force $Src $dest
  Write-Ok "$Name  ($Origin)"
  return $true
}

$installed = 0; $failed = 0; $failedNames = @()

if (-not (Get-Command tar -ErrorAction SilentlyContinue)) { Write-Warn "tar is required but not found (Windows 10+ ships it)."; exit 1 }
if (-not $DryRun) { New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null }

if ($DryRun) { Write-Bold "DRY RUN — resolving versions only; nothing is downloaded or written" }
$refMode = if ($Latest) { "latest" } else { "pinned" }
Write-Bold "Installing design + SEO skills into $SkillsDir ($refMode versions)"

foreach ($e in $Manifest) {
  if ($Latest) { $ref = "HEAD" }
  else {
    $ref = Get-LockPin $e.Repo
    if (-not $ref) { Write-Warn "No pin for $($e.Repo) in versions.lock — skipping $($e.Name)."; $failed++; $failedNames += $e.Name; continue }
  }
  if ($DryRun) { Write-Ok "would install $($e.Name)  ($($e.Repo) @ $($ref.Substring(0,[Math]::Min(7,$ref.Length))), $($e.Folder))"; $installed++; continue }
  $root = Get-Repo $e.Repo $ref
  if (-not $root) { $failed++; $failedNames += $e.Name; continue }
  $src = if ($e.Folder -eq ".") { $root } else { Join-Path $root $e.Folder }
  if (Install-SkillFolder $src $e.Name "$($e.Repo) @ $($ref.Substring(0,[Math]::Min(7,$ref.Length)))") { $installed++ } else { $failed++; $failedNames += $e.Name }
}

foreach ($name in $Bundled) {
  $src = Join-Path $Here "skills\$name"
  if ($DryRun) {
    if (Test-Path (Join-Path $src "SKILL.md")) { Write-Ok "would install $name  (bundled with this kit)"; $installed++ }
    else { Write-Warn "bundled skill $name missing SKILL.md"; $failed++; $failedNames += $name }
    continue
  }
  if (Install-SkillFolder $src $name "bundled with this kit") { $installed++ } else { $failed++; $failedNames += $name }
}

Remove-Item -Recurse -Force $script:Tmp -ErrorAction SilentlyContinue

Write-Host ""
if ($DryRun) {
  if ($failed -gt 0) { Write-Warn "DRY RUN: $installed would install, problems with: $($failedNames -join ' ')"; exit 1 }
  Write-Ok "DRY RUN: $installed machine-wide skills would install. Re-run without -DryRun to apply."
  exit 0
} elseif ($installed -eq 0) {
  Write-Warn "Nothing was installed — every skill failed (network?). Fix the issue and re-run."; exit 1
} elseif ($failed -gt 0) {
  Write-Warn "Installed $installed skills, but these failed: $($failedNames -join ' '). Re-run to retry."
} else {
  Write-Ok "All $installed machine-wide skills installed."
}

Write-Host ""
Write-Bold "Per-project skill (impeccable):"
Write-Host "  cd your-project; npx -y $ImpeccablePkg skills install --yes   (needs Node 24+)"
Write-Host ""
Write-Bold "Process skills (superpowers): in Claude Code run /plugin -> claude-plugins-official -> superpowers"

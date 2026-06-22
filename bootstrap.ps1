#!/usr/bin/env pwsh
# Claude Code Design Kit — one-command setup (Windows / PowerShell).
#
# PowerShell parity for bootstrap.sh. Does all three layers:
#   1. the kit's templates into YOUR project root
#   2. machine-wide skills (install-skills.ps1, pinned)
#   3. impeccable into YOUR project (its official installer)
#
#   pwsh -File bootstrap.ps1 C:\path\to\your-project
#   pwsh -File bootstrap.ps1 C:\path\to\your-project -Latest
#   pwsh -File bootstrap.ps1 C:\path\to\your-project -DryRun
#   pwsh -File bootstrap.ps1 C:\path\to\your-project -Check
#
# Never clobbers an existing CLAUDE.md / PRODUCT.md / DESIGN.md — drops the
# template next to it as <name>.from-design-kit instead.

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Target,
  [switch]$Latest,
  [switch]$DryRun,
  [switch]$Check
)

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$LockFile = Join-Path $Here "versions.lock"

function Write-Ok   { param($m) Write-Host "[ok] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "[!] $m"  -ForegroundColor Yellow }
function Write-Bold { param($m) Write-Host $m         -ForegroundColor White }

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

# Expected skill names — parsed from install-skills.ps1 so this never drifts.
function Get-ExpectedSkills {
  $ps = Join-Path $Here "install-skills.ps1"
  $names = @()
  foreach ($m in (Select-String -Path $ps -Pattern 'Name\s*=\s*"([^"]+)"' -AllMatches).Matches) {
    $names += $m.Groups[1].Value
  }
  $b = Select-String -Path $ps -Pattern '^\$Bundled\s*=\s*@\((.+)\)' | Select-Object -First 1
  if ($b) {
    foreach ($q in [regex]::Matches($b.Matches[0].Groups[1].Value, '"([^"]+)"')) { $names += $q.Groups[1].Value }
  }
  return $names
}

if (-not (Test-Path (Join-Path $Here "install-skills.ps1")) -or -not (Test-Path (Join-Path $Here "template"))) {
  Write-Warn "bootstrap.ps1 must run from a full clone of the kit:"
  Write-Warn "  git clone https://github.com/michaelbrowk/SUPERBROWKY.git"
  exit 1
}
if (-not $Target) {
  Write-Host "Usage: pwsh -File bootstrap.ps1 <project> [-Latest] [-DryRun] [-Check]"
  exit 1
}
if (-not (Test-Path $Target -PathType Container)) { Write-Warn "Not a directory: $Target"; exit 1 }
$Target = (Resolve-Path $Target).Path

$ImpeccableVer = Get-LockPin "impeccable-cli"
$ImpeccablePkg = if ($Latest) { "impeccable" } elseif ($ImpeccableVer) { "impeccable@$ImpeccableVer" } else { "impeccable" }

# --- doctor (-Check) ---
if ($Check) {
  $fails = 0
  Write-Bold "Checking kit setup for $Target"
  foreach ($f in @("CLAUDE.md", "PRODUCT.md", "DESIGN.md")) {
    if (Test-Path (Join-Path $Target $f)) { Write-Ok "template $f" } else { Write-Warn "missing template $f"; $fails++ }
  }
  $skillsDir = Join-Path $HOME ".claude\skills"
  foreach ($name in (Get-ExpectedSkills)) {
    if (Test-Path (Join-Path $skillsDir "$name\SKILL.md")) { Write-Ok "skill $name" } else { Write-Warn "missing machine skill $name"; $fails++ }
  }
  $imp = Join-Path $Target ".claude\skills\impeccable\SKILL.md"
  if ((Test-Path $imp) -or (Get-ChildItem -Path (Join-Path $Target ".claude\skills") -Filter "*impeccable*" -ErrorAction SilentlyContinue)) {
    Write-Ok "impeccable (project-level)"
  } else { Write-Warn "impeccable not found in $Target\.claude\skills\"; $fails++ }
  if (Get-Command node -ErrorAction SilentlyContinue) { Write-Ok "node $(& node -v)" } else { Write-Warn "node not found (impeccable needs Node 24+)"; $fails++ }
  Write-Host ""
  if ($fails -eq 0) { Write-Ok "All checks passed." } else { Write-Warn "$fails check(s) failed — re-run bootstrap.ps1 to fix."; exit 1 }
  exit 0
}

if ($DryRun) { Write-Bold "DRY RUN — showing actions only; nothing is copied, downloaded, or installed" }

Write-Bold "1/3 - Wiring templates into $Target"
foreach ($f in @("CLAUDE.md", "PRODUCT.md", "DESIGN.md")) {
  $dst = Join-Path $Target $f
  if ($DryRun) {
    if (Test-Path $dst) { Write-Ok "would write $f.from-design-kit ($f already exists)" } else { Write-Ok "would copy $f -> $Target" }
    continue
  }
  $src = Join-Path $Here "template\$f"
  if (Test-Path $dst) {
    Copy-Item $src (Join-Path $Target "$f.from-design-kit") -Force
    Write-Warn "$f already exists — wrote $f.from-design-kit instead. Merge it in by hand."
  } else {
    Copy-Item $src $dst
    Write-Ok "copied $f -> $Target"
  }
}

Write-Host ""
Write-Bold "2/3 - Installing machine-wide design skills"
$installArgs = @()
if ($Latest) { $installArgs += "-Latest" }
if ($DryRun) { $installArgs += "-DryRun" }
& (Join-Path $Here "install-skills.ps1") @installArgs

Write-Host ""
Write-Bold "3/3 - Installing impeccable into $Target"
if ($DryRun) {
  Write-Ok "would run: cd $Target; npx -y $ImpeccablePkg skills install --yes"
} elseif (Get-Command npx -ErrorAction SilentlyContinue) {
  Push-Location $Target
  try {
    & npx -y $ImpeccablePkg skills install --yes
    if ($LASTEXITCODE -eq 0) { Write-Ok "impeccable installed (project-level, .claude\skills\)" }
    else { Write-Warn "impeccable installer failed — run it yourself: cd $Target; npx -y $ImpeccablePkg skills install --yes" }
  } finally { Pop-Location }
} else {
  Write-Warn "Node.js/npx not found — impeccable needs Node 24+. Install from https://nodejs.org, then:"
  Write-Warn "  cd $Target; npx -y $ImpeccablePkg skills install --yes"
}

if ($DryRun) {
  Write-Host ""
  Write-Ok "DRY RUN complete — re-run without -DryRun to apply. Verify later: pwsh -File bootstrap.ps1 $Target -Check"
  exit 0
}

Write-Host ""
Write-Bold "Done. Three steps left (the human ones):"
Write-Host @"
  1. In Claude Code run /plugin -> marketplace "claude-plugins-official" -> install "superpowers".
  2. Start a FRESH Claude Code session so the new skills load.
  3. Fill PRODUCT.md (who/why/brand) and DESIGN.md (exact values), or run
     /impeccable init and merge its output into the kit's template sections.

  Verify the install any time:  pwsh -File bootstrap.ps1 $Target -Check
"@

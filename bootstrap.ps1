#!/usr/bin/env pwsh
# SUPERBROWKY v4 — safe native PowerShell bootstrap for Claude Code and Codex.
#
# The default invocation is a read-only plan. Add -Apply only after reviewing
# the harness, profile, destinations, conflicts, and remote sources.

[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)]
  [string]$Target,

  [ValidateSet("auto", "claude", "codex", "both")]
  [string]$Harness = "auto",

  [ValidateSet("core", "web-launch", "growth", "full")]
  [string]$Profile = "core",

  [switch]$Apply,
  [switch]$DryRun,
  [switch]$Latest,
  [switch]$Check,
  [switch]$AuditBundle,
  [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$KitRoot = $PSScriptRoot
$TemplateRoot = Join-Path $KitRoot "template"
$KitVersion = "4"
$ClaudeHomeExplicit = -not [string]::IsNullOrWhiteSpace($env:CLAUDE_HOME)
$CodexHomeExplicit = -not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)
$ClaudeHome = if ($ClaudeHomeExplicit) { $env:CLAUDE_HOME } else { Join-Path $HOME ".claude" }
$CodexHome = if ($CodexHomeExplicit) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$script:TempRoot = $null

function Write-Ok { param([string]$Message) Write-Host "[ok] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Fail { param([string]$Message) Write-Host "[x] $Message" -ForegroundColor Red }

function Test-AnyPath {
  param([string]$Path)
  return $null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

function Get-PowerShellExecutable {
  $candidate = if ($IsWindows) { Join-Path $PSHOME "pwsh.exe" } else { Join-Path $PSHOME "pwsh" }
  if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  $command = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($null -eq $command) { throw "PowerShell 7 executable not found" }
  return $command.Source
}

function Invoke-PowerShellScript {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Arguments)
  $pwsh = Get-PowerShellExecutable
  & $pwsh -NoLogo -NoProfile -File $Path @Arguments | Out-Host
  return $LASTEXITCODE
}

function Invoke-DoctorResult {
  $pwsh = Get-PowerShellExecutable
  $doctorPath = Join-Path $KitRoot "scripts/doctor.ps1"
  $output = @(& $pwsh -NoLogo -NoProfile -File $doctorPath -Target $Target -Harness $Harness -Profile $Profile 2>&1)
  $code = $LASTEXITCODE
  foreach ($line in $output) { Write-Host ([string]$line) }
  $status = ($output | ForEach-Object { [string]$_ } | Where-Object { $_ -like "STATUS:*" } | Select-Object -Last 1)
  if ([string]::IsNullOrWhiteSpace($status)) { $status = "STATUS: BLOCKED — doctor did not return a status." }
  return [pscustomobject]@{ ExitCode = $code; Status = $status }
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

function Get-TemplateNames {
  $names = @("HARNESS.md", "PROJECT.md", "PRODUCT.md", "DESIGN.md", "Decision.md", "Feedback.md")
  if ($Harness -in @("claude", "both")) { $names += "CLAUDE.md" }
  if ($Harness -in @("codex", "both")) { $names += "AGENTS.md" }
  return $names
}

function Get-FileDigest {
  param([string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-CandidatePath {
  param([string]$Name, [string]$Digest)
  return Join-Path $Target "$Name.from-superbrowky-v$KitVersion-$($Digest.Substring(0, 12))"
}

function Get-MergeMarker {
  param([string]$Name, [string]$Digest)
  return "<!-- SUPERBROWKY-MERGED: template/$Name sha256:$Digest -->"
}

function Test-MergeAccepted {
  param([string]$Path, [string]$Name, [string]$Digest)
  return (Test-Path -LiteralPath $Path -PathType Leaf) -and
    (Select-String -LiteralPath $Path -SimpleMatch (Get-MergeMarker -Name $Name -Digest $Digest) -Quiet)
}

function Test-SafeProjectReceiptRow {
  param([Parameter(Mandatory)][object]$Row, [Parameter(Mandatory)][string]$Name)
  if ($Name -notin (Get-AllTemplateNames) -or
      $Row.Source -ne "template/$Name" -or
      $Row.Hash -notmatch "^[0-9a-f]{64}$" -or
      [IO.Path]::IsPathRooted($Row.Relative) -or
      $Row.Relative -match '(^|[\\/])\.\.([\\/]|$)') {
    return $false
  }
  if ($Row.Kind -in @("installed", "observed")) {
    return $Row.Relative -eq $Name
  }
  if ($Row.Kind -eq "candidate") {
    return -not $Row.Relative.Contains("/") -and
      -not $Row.Relative.Contains("\") -and
      $Row.Relative.StartsWith("$Name.from-superbrowky-v$KitVersion-", [StringComparison]::Ordinal)
  }
  return $false
}

function Get-ProjectReceiptRows {
  $path = Join-Path (Join-Path $Target ".superbrowky") "project-receipt.tsv"
  $rows = @()
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $rows }
  foreach ($line in [IO.File]::ReadAllLines($path)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
    $fields = $line.TrimEnd("`r").Split([char]"`t", [StringSplitOptions]::None)
    if ($fields.Count -eq 4) {
      $rows += [pscustomobject]@{ Kind = $fields[0]; Relative = $fields[1]; Hash = $fields[2]; Source = $fields[3] }
    }
  }
  return $rows
}

function Show-TemplatePlan {
  Write-Host "Project harness"
  $oldRows = @(Get-ProjectReceiptRows)
  foreach ($name in (Get-TemplateNames)) {
    $source = Join-Path $TemplateRoot $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      throw "Missing kit template: $source"
    }
    $destination = Join-Path $Target $name
    $digest = Get-FileDigest $source
    if (-not (Test-AnyPath $destination)) {
      Write-Host "  INSTALL    $name"
    } elseif ((Test-Path -LiteralPath $destination -PathType Leaf) -and
              (Get-FileDigest $destination) -eq $digest) {
      Write-Host "  CURRENT    $name"
    } else {
      $previousRows = @($oldRows | Where-Object { $_.Source -eq "template/$name" })
      $previous = if ($previousRows.Count -eq 1) { $previousRows[0] } else { $null }
      if ($null -ne $previous -and
          (Test-SafeProjectReceiptRow -Row $previous -Name $name) -and
          $previous.Kind -eq "candidate" -and
          $previous.Hash -eq $digest -and
          -not (Test-AnyPath (Join-Path $Target $previous.Relative)) -and
          (Test-MergeAccepted -Path $destination -Name $name -Digest $digest)) {
        Write-Host "  ACCEPTED   $name (recorded merge marker)"
      } else {
        $candidate = if ($null -ne $previous -and
                        (Test-SafeProjectReceiptRow -Row $previous -Name $name) -and
                        $previous.Kind -eq "candidate" -and
                        $previous.Hash -eq $digest) {
          Join-Path $Target $previous.Relative
        } else {
          Get-CandidatePath -Name $name -Digest $digest
        }
        Write-Host "  MERGE      $name exists; write $(Split-Path -Leaf $candidate)"
      }
    }
  }
}

function Install-Templates {
  $script:TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("superbrowky-templates-" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $script:TempRoot | Out-Null
  $oldRows = @(Get-ProjectReceiptRows)
  $created = [System.Collections.Generic.List[object]]::new()
  $targetPartials = [System.Collections.Generic.List[object]]::new()
  $receiptRows = [System.Collections.Generic.List[object]]::new()
  $stateDirectory = Join-Path $Target ".superbrowky"
  $receipt = Join-Path $stateDirectory "project-receipt.tsv"
  $receiptExisted = Test-Path -LiteralPath $receipt -PathType Leaf
  $receiptSnapshot = Join-Path $script:TempRoot "project-receipt.before.tsv"
  if ($receiptExisted) {
    Copy-Item -LiteralPath $receipt -Destination $receiptSnapshot
  }
  $receiptCommitted = $false
  $committedReceiptHash = $null

  foreach ($name in (Get-TemplateNames)) {
    $source = Join-Path $TemplateRoot $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing kit template: $source" }
    $staged = Join-Path $script:TempRoot $name
    Copy-Item -LiteralPath $source -Destination $staged
    if ((Get-FileDigest $source) -ne (Get-FileDigest $staged)) {
      throw "Template staging verification failed: $name"
    }
  }

  try {
    foreach ($name in (Get-TemplateNames)) {
      $staged = Join-Path $script:TempRoot $name
      $destination = Join-Path $Target $name
      $digest = Get-FileDigest $staged
      $relative = $name
      $kind = $null
      $previousRows = @($oldRows | Where-Object { $_.Source -eq "template/$name" })
      if ($previousRows.Count -gt 1) {
        throw "Duplicate prior project receipt rows for template/$name"
      }
      $previous = if ($previousRows.Count -eq 1) { $previousRows[0] } else { $null }
      if ($null -ne $previous -and -not (Test-SafeProjectReceiptRow -Row $previous -Name $name)) {
        throw "Unsafe prior project receipt row for template/$name"
      }

      if (-not (Test-AnyPath $destination)) {
        $partial = "$destination.superbrowky-partial.$PID"
        $targetPartials.Add([pscustomobject]@{ Path = $partial; Hash = $digest })
        Copy-Item -LiteralPath $staged -Destination $partial
        Move-Item -LiteralPath $partial -Destination $destination
        $created.Add([pscustomobject]@{ Path = $destination; Hash = $digest })
        $kind = "installed"
        Write-Ok "installed $name"
      } elseif ((Test-Path -LiteralPath $destination -PathType Leaf) -and
                (Get-FileDigest $destination) -eq $digest) {
        $kind = if ($null -ne $previous -and $previous.Kind -eq "installed") { "installed" } else { "observed" }
        Write-Ok "$name already current"
      } elseif ($null -ne $previous -and
                $previous.Kind -eq "candidate" -and
                $previous.Hash -eq $digest -and
                -not (Test-AnyPath (Join-Path $Target $previous.Relative)) -and
                (Test-MergeAccepted -Path $destination -Name $name -Digest $digest)) {
        $relative = $previous.Relative
        $kind = "candidate"
        Write-Ok "$name merge accepted by exact marker"
      } else {
        $candidate = if ($null -ne $previous -and
                        $previous.Kind -eq "candidate" -and
                        $previous.Hash -eq $digest) {
          Join-Path $Target $previous.Relative
        } else {
          Get-CandidatePath -Name $name -Digest $digest
        }
        if (Test-AnyPath $candidate) {
          if (-not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
              (Get-FileDigest $candidate) -ne $digest) {
            $candidate = "$candidate-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
          }
        }
        if (-not (Test-AnyPath $candidate)) {
          $partial = "$candidate.superbrowky-partial.$PID"
          $targetPartials.Add([pscustomobject]@{ Path = $partial; Hash = $digest })
          Copy-Item -LiteralPath $staged -Destination $partial
          Move-Item -LiteralPath $partial -Destination $candidate
          $created.Add([pscustomobject]@{ Path = $candidate; Hash = $digest })
          Write-Warn "$name preserved; merge candidate: $(Split-Path -Leaf $candidate)"
        } else {
          Write-Ok "merge candidate already current: $(Split-Path -Leaf $candidate)"
        }
        $relative = Split-Path -Leaf $candidate
        $kind = "candidate"
      }
      $receiptRows.Add([pscustomobject]@{
        Kind = $kind
        Relative = $relative
        Hash = $digest
        Source = "template/$name"
      })
    }

    $selectedSources = @{}
    foreach ($name in (Get-TemplateNames)) { $selectedSources["template/$name"] = $true }
    foreach ($adapter in @("CLAUDE.md", "AGENTS.md")) {
      $source = "template/$adapter"
      if ($selectedSources.ContainsKey($source)) { continue }
      $adapterRows = @($oldRows | Where-Object { $_.Source -eq $source })
      if ($adapterRows.Count -gt 1) {
        throw "Duplicate prior project receipt rows for $source"
      }
      if ($adapterRows.Count -eq 1) {
        if (-not (Test-SafeProjectReceiptRow -Row $adapterRows[0] -Name $adapter)) {
          throw "Unsafe prior project receipt row for $source"
        }
        $receiptRows.Add($adapterRows[0])
        Write-Ok "preserved prior $adapter receipt ownership"
      }
    }

    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $partialReceipt = "$receipt.partial.$PID"
    $lines = @(
      "# SUPERBROWKY project receipt v$KitVersion"
      "# harness=$Harness"
      "# profile=$Profile"
      "# kind`trelative_path`tsha256`tsource"
    )
    foreach ($row in $receiptRows) {
      $lines += "$($row.Kind)`t$($row.Relative)`t$($row.Hash)`t$($row.Source)"
    }
    [IO.File]::WriteAllText($partialReceipt, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($partialReceipt, $receipt, $true)
    $receiptCommitted = $true
    $committedReceiptHash = Get-FileDigest $receipt
  } catch {
    $failure = $_
    for ($index = $created.Count - 1; $index -ge 0; $index--) {
      $entry = $created[$index]
      if (-not (Test-AnyPath $entry.Path)) { continue }
      if ((Test-Path -LiteralPath $entry.Path -PathType Leaf) -and
          (Get-FileDigest $entry.Path) -eq $entry.Hash) {
        Remove-Item -LiteralPath $entry.Path -Force -ErrorAction SilentlyContinue
      } else {
        Write-Warn "rollback preserved changed project path: $($entry.Path)"
      }
    }
    if ($receiptCommitted) {
      if ($receiptExisted) {
        $restorePartial = "$receipt.rollback.$PID"
        Copy-Item -LiteralPath $receiptSnapshot -Destination $restorePartial
        [IO.File]::Move($restorePartial, $receipt, $true)
      } elseif ((Test-Path -LiteralPath $receipt -PathType Leaf) -and
                (Get-FileDigest $receipt) -eq $committedReceiptHash) {
        Remove-Item -LiteralPath $receipt -Force
      }
    }
    foreach ($entry in $targetPartials) {
      if ((Test-Path -LiteralPath $entry.Path -PathType Leaf) -and
          (Get-FileDigest $entry.Path) -eq $entry.Hash) {
        Remove-Item -LiteralPath $entry.Path -Force -ErrorAction SilentlyContinue
      }
    }
    throw $failure
  }
}

function Uninstall-Project {
  $receipt = Join-Path (Join-Path $Target ".superbrowky") "project-receipt.tsv"
  if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
    Write-Fail "BLOCKED: no project receipt; refusing to remove unowned files"
    return 1
  }
  $rows = @(Get-ProjectReceiptRows)
  if ($rows.Count -eq 0) {
    Write-Fail "BLOCKED: project receipt is empty"
    return 1
  }
  $actions = @()
  $problems = 0
  Write-Host "Project harness removal $(if ($Apply) { 'apply' } else { 'plan only' })"
  foreach ($row in $rows) {
    $ownedName = if ($row.Source.StartsWith("template/", [StringComparison]::Ordinal)) {
      $row.Source.Substring("template/".Length)
    } else {
      ""
    }
    if ([string]::IsNullOrWhiteSpace($ownedName) -or
        -not (Test-SafeProjectReceiptRow -Row $row -Name $ownedName)) {
      Write-Fail "unsafe project receipt ownership: $($row.Source) -> $($row.Relative)"
      $problems++
      continue
    }
    $path = Join-Path $Target $row.Relative
    switch ($row.Kind) {
      { $_ -in @("installed", "candidate") } {
        if (-not (Test-AnyPath $path)) {
          Write-Host "  ABSENT     $($row.Relative)"
        } elseif (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
          Write-Warn "preserved non-file path: $($row.Relative)"
          $problems++
        } elseif ((Get-FileDigest $path) -ne $row.Hash) {
          Write-Warn "preserved modified file: $($row.Relative)"
          $problems++
        } else {
          $actions += [pscustomobject]@{
            Path = $path
            Relative = $row.Relative
            Hash = $row.Hash
          }
          Write-Host "  REMOVE     $($row.Relative)"
        }
      }
      "observed" { Write-Host "  PRESERVE   $($row.Relative) (pre-existing)" }
      default {
        Write-Warn "unknown receipt entry $($row.Kind): $($row.Relative)"
        $problems++
      }
    }
  }
  if ($problems -gt 0) {
    Write-Host "STATUS: PARTIAL — $problems modified or unsafe file(s) were preserved."
    return 2
  }
  if (-not $Apply) {
    Write-Host "PLAN ONLY — re-run with -Apply to remove the listed unchanged files."
    return 0
  }
  $failures = 0
  foreach ($action in $actions) {
    try {
      if (-not (Test-Path -LiteralPath $action.Path -PathType Leaf) -or
          (Get-FileDigest $action.Path) -ne $action.Hash) {
        throw "file changed after uninstall preflight"
      }
      Remove-Item -LiteralPath $action.Path -Force
      Write-Ok "removed $($action.Relative)"
    } catch {
      Write-Warn "preserved $($action.Relative): $($_.Exception.Message)"
      $failures++
    }
  }
  if ($failures -gt 0) {
    Write-Host "STATUS: PARTIAL — $failures project file(s) changed or could not be removed; receipt preserved."
    return 2
  }
  Remove-Item -LiteralPath $receipt -Force
  $stateDirectory = Split-Path -Parent $receipt
  if (@(Get-ChildItem -LiteralPath $stateDirectory -Force -ErrorAction SilentlyContinue).Count -eq 0) {
    Remove-Item -LiteralPath $stateDirectory -Force -ErrorAction SilentlyContinue
  }
  Write-Ok "project harness removal complete; global skills were not touched"
  return 0
}

$exitCode = 0
try {
  if ($Apply -and $DryRun) { throw "-Apply and -DryRun conflict" }
  if ($Latest -and $Apply) { throw "-Latest is plan-only. Review and pin the exact commit before -Apply." }
  $modeCount = @($Check, $AuditBundle, $Uninstall | Where-Object { $_ }).Count
  if ($modeCount -gt 1) { throw "-Check, -AuditBundle, and -Uninstall are mutually exclusive" }
  if ($Check -and $Apply) { throw "-Check is read-only; remove -Apply" }
  if (-not (Test-Path -LiteralPath $Target -PathType Container)) { throw "Not a directory: $Target" }
  if (-not (Test-Path -LiteralPath (Join-Path $KitRoot "install-skills.ps1") -PathType Leaf) -or
      -not (Test-Path -LiteralPath $TemplateRoot -PathType Container)) {
    throw "bootstrap.ps1 must run from a full SUPERBROWKY clone"
  }
  $Target = (Resolve-Path -LiteralPath $Target).Path
  if ($Harness -eq "auto") {
    $Harness = Resolve-AutoHarness
    if ([string]::IsNullOrWhiteSpace($Harness)) {
      throw "BLOCKED: no Claude Code or Codex installation detected; pass -Harness explicitly"
    }
    Write-Ok "auto-detected harness: $Harness"
  }

  if ($Check) {
    $arguments = @("-Target", $Target, "-Harness", $Harness, "-Profile", $Profile)
    exit (Invoke-PowerShellScript -Path (Join-Path $KitRoot "scripts/doctor.ps1") -Arguments $arguments)
  }
  if ($AuditBundle) {
    $arguments = @("-Target", $Target, "-Harness", $Harness, "-Profile", $Profile)
    if ($Apply) { $arguments += "-Apply" }
    exit (Invoke-PowerShellScript -Path (Join-Path $KitRoot "scripts/audit-bundle.ps1") -Arguments $arguments)
  }
  if ($Uninstall) {
    exit (Uninstall-Project)
  }

  Write-Host "SUPERBROWKY v$KitVersion — $(if ($Apply) { 'apply' } else { 'plan only' })"
  Write-Host "  Project:  $Target"
  Write-Host "  Harness:  $Harness"
  Write-Host "  Profile:  $Profile"
  Write-Host ""
  Show-TemplatePlan
  Write-Host ""

  $installerArguments = @("-Harness", $Harness, "-Profile", $Profile)
  if ($Latest) { $installerArguments += "-Latest" }
  if ($Apply) { $installerArguments += "-Apply" }
  $installerExit = Invoke-PowerShellScript -Path (Join-Path $KitRoot "install-skills.ps1") -Arguments $installerArguments
  if ($installerExit -ne 0) { exit $installerExit }

  if (-not $Apply) {
    Write-Host ""
    Write-Host "PLAN ONLY — no downloads or writes were performed."
    Write-Host "Review the paths, conflicts, and sources above, then re-run with -Apply."
    exit 0
  }

  Write-Host ""
  Write-Host "Installing project harness"
  Install-Templates

  Write-Host ""
  Write-Host "Verification"
  $doctorResult = Invoke-DoctorResult
  if ($doctorResult.Status -like "STATUS: READY*") {
    Write-Ok "READY — open a fresh $Harness session in the project."
  } elseif ($doctorResult.Status -like "STATUS: PARTIAL*") {
      Write-Warn "PARTIAL — installation is intact, but onboarding or an optional runtime check remains."
      Write-Warn "Fill PROJECT.md, PRODUCT.md, DESIGN.md, and adapter placeholders in a fresh session."
  } else {
    Write-Fail "BLOCKED — doctor found an installation problem."
    exit $(if ($doctorResult.ExitCode -eq 0) { 1 } else { $doctorResult.ExitCode })
  }
  Write-Host ""
  Write-Host "Generate a shareable install report when needed:"
  Write-Host "  pwsh -File `"$PSCommandPath`" `"$Target`" -Harness $Harness -Profile $Profile -AuditBundle -Apply"
} catch {
  Write-Fail $_.Exception.Message
  $exitCode = 2
} finally {
  if ($null -ne $script:TempRoot -and (Test-AnyPath $script:TempRoot)) {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

exit $exitCode

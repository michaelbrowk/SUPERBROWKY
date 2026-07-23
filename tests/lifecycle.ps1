#!/usr/bin/env pwsh
# End-to-end PowerShell safety lifecycle in an isolated fake home.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Profile = if ([string]::IsNullOrWhiteSpace($env:SUPERBROWKY_TEST_PROFILE)) {
  "core"
} else {
  $env:SUPERBROWKY_TEST_PROFILE
}
if ($Profile -notin @("core", "web-launch", "growth", "full")) {
  throw "Invalid SUPERBROWKY_TEST_PROFILE: $Profile"
}
$ExpectedSkills = @(
  "impeccable", "emil-design-eng", "design-taste-frontend", "stop-slop",
  "psi-optimize", "a11y-audit", "meta-audit"
)
if ($Profile -in @("web-launch", "growth", "full")) {
  $ExpectedSkills += @("seo-audit", "schema", "site-architecture")
}
if ($Profile -in @("growth", "full")) {
  $ExpectedSkills += @("ai-seo", "programmatic-seo", "cro")
}
if ($Profile -eq "full") {
  $ExpectedSkills += @("high-end-visual-design", "redesign-existing-projects")
}
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ("superbrowky-ps-lifecycle-" + [Guid]::NewGuid().ToString("N"))
$LogRoot = Join-Path ([IO.Path]::GetTempPath()) ("superbrowky-ps-lifecycle-logs-" + [Guid]::NewGuid().ToString("N"))
$TestHome = Join-Path $TestRoot "home"
$ClaudeHome = Join-Path $TestHome ".claude"
$CodexHome = Join-Path $TestHome ".codex"
$StateHome = Join-Path $TestHome ".superbrowky"
$Project = Join-Path $TestHome "work/example"
$Pwsh = if ($IsWindows) { Join-Path $PSHOME "pwsh.exe" } else { Join-Path $PSHOME "pwsh" }
$Succeeded = $false
$Failure = $null

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "FAIL: $Message" }
}

function Assert-File {
  param([string]$Path)
  Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
}

function Assert-Directory {
  param([string]$Path)
  Assert-True (Test-Path -LiteralPath $Path -PathType Container) "missing directory: $Path"
}

function Assert-Absent {
  param([string]$Path)
  Assert-True ($null -eq (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) "expected absent: $Path"
}

function Assert-Provenance {
  param([string]$Path)
  foreach ($name in @("LICENSE", "LICENSE.md", "NOTICE", "NOTICE.md")) {
    $candidate = Join-Path $Path $name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return }
  }
  throw "FAIL: missing third-party license/notice: $Path"
}

function Get-Digest {
  param([string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Text {
  param([string]$Path, [string]$Text)
  New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
  [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Invoke-Logged {
  param([string]$LogName, [string]$Script, [string[]]$Arguments)
  $output = @(& $Pwsh -NoLogo -NoProfile -File $Script @Arguments 2>&1)
  $code = $LASTEXITCODE
  $log = Join-Path $LogRoot $LogName
  [IO.File]::WriteAllText(
    $log,
    (($output | ForEach-Object { [string]$_ }) -join "`n") + "`n",
    [Text.UTF8Encoding]::new($false)
  )
  return [pscustomobject]@{ Code = $code; Output = @($output | ForEach-Object { [string]$_ }); Log = $log }
}

try {
  New-Item -ItemType Directory -Path $TestRoot, $LogRoot, $Project | Out-Null
  $env:HOME = $TestHome
  $env:USERPROFILE = $TestHome
  $env:CLAUDE_HOME = $ClaudeHome
  $env:CODEX_HOME = $CodexHome
  $env:SUPERBROWKY_STATE_HOME = $StateHome
  $env:SUPER_SECRET_DO_NOT_CAPTURE = "lifecycle-secret-marker"

  Write-Text (Join-Path $ClaudeHome "skills/impeccable/USER_MARKER.txt") "original claude skill`n"
  Write-Text (Join-Path $CodexHome "skills/impeccable/USER_MARKER.txt") "original codex skill`n"
  Write-Text (Join-Path $Project "CLAUDE.md") "original claude adapter`n"
  Write-Text (Join-Path $Project "AGENTS.md") "original codex adapter`n"

  Write-Host "1/9 plan is read-only"
  $plan = Invoke-Logged "plan.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile
  )
  Assert-True ($plan.Code -eq 0) "plan returned $($plan.Code)"
  Assert-File (Join-Path $ClaudeHome "skills/impeccable/USER_MARKER.txt")
  Assert-File (Join-Path $CodexHome "skills/impeccable/USER_MARKER.txt")
  Assert-Absent (Join-Path $StateHome "state")
  Assert-Absent (Join-Path $Project "HARNESS.md")
  Assert-True (($plan.Output -join "`n") -match "PLAN ONLY") "plan did not identify itself"

  Write-Host "2/9 apply, receipts, adapters, and overlays"
  $apply = Invoke-Logged "apply.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Apply"
  )
  Assert-True ($apply.Code -eq 0) "apply returned $($apply.Code)"
  foreach ($forHarness in @("claude", "codex")) {
    $harnessHome = if ($forHarness -eq "claude") { $ClaudeHome } else { $CodexHome }
    foreach ($skill in $ExpectedSkills) {
      Assert-File (Join-Path $harnessHome "skills/$skill/SKILL.md")
      Assert-File (Join-Path $StateHome "state/$forHarness/$skill.receipt.tsv")
      if ($skill -notin @("psi-optimize", "a11y-audit", "meta-audit")) {
        Assert-Provenance (Join-Path $harnessHome "skills/$skill")
      }
    }
    foreach ($skill in @("impeccable", "emil-design-eng", "design-taste-frontend", "stop-slop")) {
      $skillMd = Join-Path $harnessHome "skills/$skill/SKILL.md"
      Assert-True (Select-String -LiteralPath $skillMd -SimpleMatch "SUPERBROWKY third-party safety" -Quiet) "common overlay missing: $forHarness/$skill"
    }
    $impeccable = Join-Path $harnessHome "skills/impeccable"
    Assert-True (Select-String -LiteralPath (Join-Path $impeccable "SKILL.md") -SimpleMatch "SUPERBROWKY portable contract" -Quiet) "portable overlay missing: $forHarness"
    Assert-Absent (Join-Path $impeccable "scripts/cleanup-deprecated.mjs")
    Assert-Absent (Join-Path $impeccable "scripts/pin.mjs")
    Assert-File (Join-Path $impeccable "LICENSE")
  }
  foreach ($file in @("HARNESS.md", "PROJECT.md", "PRODUCT.md", "DESIGN.md", "Decision.md", "Feedback.md")) {
    Assert-File (Join-Path $Project $file)
  }
  Assert-True (([IO.File]::ReadAllText((Join-Path $Project "CLAUDE.md"))) -match "original claude adapter") "CLAUDE.md overwritten"
  Assert-True (([IO.File]::ReadAllText((Join-Path $Project "AGENTS.md"))) -match "original codex adapter") "AGENTS.md overwritten"
  Assert-True (@(Get-ChildItem -LiteralPath $Project -File -Filter "CLAUDE.md.from-superbrowky-v4-*").Count -eq 1) "Claude candidate missing/duplicated"
  Assert-True (@(Get-ChildItem -LiteralPath $Project -File -Filter "AGENTS.md.from-superbrowky-v4-*").Count -eq 1) "Codex candidate missing/duplicated"
  $unsafe = @(Get-ChildItem -LiteralPath (Join-Path $ClaudeHome "skills/impeccable"), (Join-Path $CodexHome "skills/impeccable") -Recurse -File |
    Select-String -Pattern 'allowed-tools:.*Bash\(npx impeccable|(?:\.claude|\.agents)[\\/]skills[\\/]impeccable')
  Assert-True ($unsafe.Count -eq 0) "unsafe Impeccable command/path remains"

  Write-Host "3/9 doctor reports honest onboarding state"
  $projectReceipt = Join-Path $Project ".superbrowky/project-receipt.tsv"
  $cleanProjectReceipt = [IO.File]::ReadAllBytes($projectReceipt)
  $duplicateRow = [IO.File]::ReadAllLines($projectReceipt) |
    Where-Object { $_.EndsWith("template/HARNESS.md", [StringComparison]::Ordinal) } |
    Select-Object -First 1
  Assert-True (-not [string]::IsNullOrWhiteSpace($duplicateRow)) "HARNESS project receipt row missing"
  [IO.File]::AppendAllText($projectReceipt, "$duplicateRow`n", [Text.UTF8Encoding]::new($false))
  $duplicateReceipt = Invoke-Logged "doctor-duplicate-receipt.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Check"
  )
  Assert-True ($duplicateReceipt.Code -eq 1) "duplicate project receipt should return BLOCKED exit 1, got $($duplicateReceipt.Code)"
  Assert-True (($duplicateReceipt.Output -join "`n") -match "(?m)^STATUS: BLOCKED") "duplicate project receipt did not report BLOCKED"
  [IO.File]::WriteAllBytes($projectReceipt, $cleanProjectReceipt)
  $doctor = Invoke-Logged "doctor.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Check"
  )
  Assert-True ($doctor.Code -eq 2) "expected PARTIAL doctor exit 2, got $($doctor.Code)"
  Assert-True (($doctor.Output -join "`n") -match "(?m)^STATUS: PARTIAL") "doctor did not report PARTIAL"

  Write-Host "4/9 audit plan is read-only, apply is redacted"
  $auditPlan = Invoke-Logged "audit-plan.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-AuditBundle"
  )
  Assert-True ($auditPlan.Code -eq 0) "audit plan returned $($auditPlan.Code)"
  Assert-Absent (Join-Path $Project "AuditBundles")
  $auditApply = Invoke-Logged "audit-apply.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-AuditBundle", "-Apply"
  )
  Assert-True ($auditApply.Code -eq 2) "expected audit to preserve PARTIAL exit 2, got $($auditApply.Code)"
  $auditFiles = @(Get-ChildItem -LiteralPath (Join-Path $Project "AuditBundles") -File -Filter "SUPERBROWKY-Audit-*.md")
  Assert-True ($auditFiles.Count -eq 1) "audit bundle missing or duplicated"
  $auditText = [IO.File]::ReadAllText($auditFiles[0].FullName)
  Assert-True (-not $auditText.Contains($env:SUPER_SECRET_DO_NOT_CAPTURE)) "audit captured an environment secret"
  Assert-True (-not $auditText.Contains($TestHome)) "audit exposed the fake HOME path"
  Assert-True ($auditText.Contains('Project: `~/work/example`')) "audit did not redact project path"
  Assert-True ($auditText.Contains("template/PROJECT.md")) "audit omitted PROJECT.md receipt evidence"
  Assert-True ($auditText -match '[0-9a-f]{64}') "audit omitted receipt hashes"

  Write-Host "5/9 reinstall is idempotent"
  $backupCountBefore = if (Test-Path -LiteralPath (Join-Path $StateHome "backups")) {
    @(Get-ChildItem -LiteralPath (Join-Path $StateHome "backups") -Recurse -Directory).Count
  } else { 0 }
  $receiptPath = Join-Path $StateHome "state/claude/impeccable.receipt.tsv"
  $receiptHashBefore = Get-Digest $receiptPath
  $reapply = Invoke-Logged "reapply.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Apply"
  )
  Assert-True ($reapply.Code -eq 0) "reapply returned $($reapply.Code)"
  $backupCountAfter = @(Get-ChildItem -LiteralPath (Join-Path $StateHome "backups") -Recurse -Directory).Count
  Assert-True ($backupCountBefore -eq $backupCountAfter) "NOOP reinstall created another backup"
  Assert-True ($receiptHashBefore -eq (Get-Digest $receiptPath)) "NOOP reinstall rewrote receipt"
  $claudeOnly = Invoke-Logged "reapply-claude-only.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "claude", "-Profile", $Profile, "-Apply"
  )
  Assert-True ($claudeOnly.Code -eq 0) "both → claude reapply returned $($claudeOnly.Code)"
  Assert-True (
    (Select-String -LiteralPath (Join-Path $Project ".superbrowky/project-receipt.tsv") -SimpleMatch "template/AGENTS.md" -Quiet)
  ) "switching both → claude dropped prior Codex adapter ownership"

  Write-Host "6/9 drift blocks replacement and removal"
  $driftFile = Join-Path $ClaudeHome "skills/a11y-audit/SKILL.md"
  $driftOriginal = [IO.File]::ReadAllBytes($driftFile)
  [IO.File]::AppendAllText($driftFile, "`nlocal user edit`n", [Text.UTF8Encoding]::new($false))
  $guard = Join-Path $CodexHome "skills/psi-optimize/SKILL.md"
  $guardBefore = Get-Digest $guard
  $driftApply = Invoke-Logged "drift-apply.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Apply"
  )
  Assert-True ($driftApply.Code -ne 0) "reinstall accepted drift"
  Assert-True (([IO.File]::ReadAllText($driftFile)) -match "local user edit") "drift was overwritten"
  Assert-True ($guardBefore -eq (Get-Digest $guard)) "another skill changed after drift preflight"
  $driftUninstall = Invoke-Logged "drift-uninstall.txt" (Join-Path $Root "install-skills.ps1") @(
    "-Harness", "both", "-Uninstall", "-Apply"
  )
  Assert-True ($driftUninstall.Code -ne 0) "uninstall accepted drift"
  Assert-Directory (Join-Path $CodexHome "skills/psi-optimize")
  [IO.File]::WriteAllBytes($driftFile, $driftOriginal)

  Write-Host "7/9 completed onboarding can become READY"
  Write-Text (Join-Path $Project "PROJECT.md") "# Project map`n`n## Runtime`n`n- **Stack:** static test fixture`n- **Test command:** pwsh -File tests/lifecycle.ps1`n`n## Surface map`n`n| Surface | Code paths | Product context | Design context | Verification |`n|---|---|---|---|---|`n| fixture | ``tests/`` | ``PRODUCT.md`` | ``DESIGN.md`` | lifecycle |`n"
  Write-Text (Join-Path $Project "PRODUCT.md") "# Product`n`n## Authority`n`n- **Artifact ID:** PRODUCT-v1`n- **Version:** 1.0`n- **Status:** ACCEPTED`n- **Accepted by:** Test Human`n- **Accepted on:** 2026-07-23`n- **Decision reference:** DEC-TEST-001`n`nReal product context.`n"
  Write-Text (Join-Path $Project "DESIGN.md") "# Design System`n`n## Authority`n`n- **Artifact ID:** DESIGN-v1`n- **Version:** 1.0`n- **Status:** ACCEPTED`n- **Accepted by:** Test Human`n- **Accepted on:** 2026-07-23`n- **Decision reference:** DEC-TEST-001`n`nAccepted project-owned design context.`n"
  $productHash = Get-Digest (Join-Path $Project "PRODUCT.md")
  $designHash = Get-Digest (Join-Path $Project "DESIGN.md")
  Write-Text (Join-Path $Project "Decision.md") "# Decisions`n`n### 2026-07-23 — Accept test context`n`n- **Decision ID:** DEC-TEST-001`n- **Status:** ACCEPTED`n- **Type:** CONTEXT`n- **Scope:** lifecycle fixture`n- **Decision:** accept PRODUCT-v1 and DESIGN-v1`n- **Basis:** deterministic fixture`n- **Reviewed artifacts:** ``PRODUCT.md`` PRODUCT-v1/1.0 sha256:$productHash; ``DESIGN.md`` DESIGN-v1/1.0 sha256:$designHash`n- **Approved by:** Test Human`n- **Approved on:** 2026-07-23 Europe/Moscow`n- **Authorizes:** lifecycle verification`n- **Does not authorize:** production work`n- **Gate transition:** context draft → accepted`n- **Replaces:** none`n"
  Write-Text (Join-Path $Project "CLAUDE.md") "original claude adapter`nRead HARNESS.md.`n"
  Write-Text (Join-Path $Project "AGENTS.md") "original codex adapter`nRead HARNESS.md.`n"
  foreach ($candidate in @(Get-ChildItem -LiteralPath $Project -File -Filter "*.md.from-superbrowky-v4-*")) {
    $markerAt = $candidate.Name.IndexOf(".from-superbrowky-v4-", [StringComparison]::Ordinal)
    $canonicalName = $candidate.Name.Substring(0, $markerAt)
    $candidateHash = Get-Digest $candidate.FullName
    [IO.File]::AppendAllText(
      (Join-Path $Project $canonicalName),
      "`n<!-- SUPERBROWKY-MERGED: template/$canonicalName sha256:$candidateHash -->`n",
      [Text.UTF8Encoding]::new($false)
    )
    Remove-Item -LiteralPath $candidate.FullName -Force
  }
  $ready = Invoke-Logged "doctor-ready.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Check"
  )
  Assert-True ($ready.Code -eq 0) "completed onboarding did not reach READY"
  Assert-True (($ready.Output -join "`n") -match "(?m)^STATUS: READY") "completed onboarding did not report READY"
  $driftKit = Join-Path $TestRoot "kit-drift"
  New-Item -ItemType Directory -Path $driftKit | Out-Null
  foreach ($item in @(Get-ChildItem -LiteralPath $Root -Force)) {
    Copy-Item -LiteralPath $item.FullName -Destination $driftKit -Recurse -Force
  }
  [IO.File]::AppendAllText(
    (Join-Path $driftKit "template/AGENTS.md"),
    "`n<!-- test template revision -->`n",
    [Text.UTF8Encoding]::new($false)
  )
  $templateDrift = Invoke-Logged "doctor-template-drift.txt" (Join-Path $driftKit "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Check"
  )
  Assert-True ($templateDrift.Code -eq 2) "new kit adapter template should return PARTIAL exit 2, got $($templateDrift.Code)"
  Assert-True (($templateDrift.Output -join "`n") -match "(?m)^STATUS: PARTIAL") "new kit adapter template did not report PARTIAL"
  Copy-Item -LiteralPath (Join-Path $Root "template/AGENTS.md") -Destination (Join-Path $driftKit "template/AGENTS.md") -Force
  [IO.File]::AppendAllText(
    (Join-Path $driftKit "skills/a11y-audit/SKILL.md"),
    "`n<!-- test bundled revision -->`n",
    [Text.UTF8Encoding]::new($false)
  )
  $bundledDrift = Invoke-Logged "doctor-bundled-drift.txt" (Join-Path $driftKit "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Check"
  )
  Assert-True ($bundledDrift.Code -eq 2) "new bundled skill source should return PARTIAL exit 2, got $($bundledDrift.Code)"
  Assert-True (($bundledDrift.Output -join "`n") -match "(?m)^STATUS: PARTIAL") "new bundled skill source did not report PARTIAL"
  $driftManifest = Join-Path $driftKit "manifests/skills.tsv"
  $cleanDriftManifest = [IO.File]::ReadAllBytes($driftManifest)
  $linkedSkills = Join-Path $driftKit "linked-skills"
  if ($IsWindows) {
    New-Item -ItemType Junction -Path $linkedSkills -Target (Join-Path $driftKit "skills") | Out-Null
  } else {
    New-Item -ItemType SymbolicLink -Path $linkedSkills -Target (Join-Path $driftKit "skills") | Out-Null
  }
  $manifestHeader = [IO.File]::ReadAllLines($driftManifest)[0]
  Write-Text $driftManifest (
    $manifestHeader + "`n" +
    "psi-optimize`tcore`tbundled`t.`t-`tlinked-skills/psi-optimize`tlinked-skills/psi-optimize`tMIT`tyes`n"
  )
  $linkedSource = Invoke-Logged "linked-source-path.txt" (Join-Path $driftKit "install-skills.ps1") @(
    "-Harness", "both", "-Profile", "core", "-Apply"
  )
  Assert-True ($linkedSource.Code -ne 0) "installer accepted a linked intermediate source directory"
  Assert-True (
    ($linkedSource.Output -join "`n") -match "source path contains a missing or linked directory"
  ) "linked intermediate source did not fail closed"
  [IO.File]::WriteAllBytes($driftManifest, $cleanDriftManifest)
  $acceptedDecision = [IO.File]::ReadAllText((Join-Path $Project "Decision.md"))
  $badHash = "0" * 64
  Write-Text (Join-Path $Project "Decision.md") ($acceptedDecision.Replace($productHash, $badHash))
  $wrongHash = Invoke-Logged "doctor-wrong-decision-hash.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Check"
  )
  Assert-True ($wrongHash.Code -eq 2) "wrong accepted artifact hash should return PARTIAL exit 2, got $($wrongHash.Code)"
  Assert-True (($wrongHash.Output -join "`n") -match "(?m)^STATUS: PARTIAL") "wrong accepted artifact hash did not report PARTIAL"
  Write-Text (Join-Path $Project "Decision.md") $acceptedDecision
  $ambiguousEvidence = $acceptedDecision.Replace(
    "PRODUCT-v1/1.0 sha256:$productHash",
    "PRODUCT-v1/9.9; OTHER/1.0; junk${productHash}suffix"
  )
  Write-Text (Join-Path $Project "Decision.md") $ambiguousEvidence
  $ambiguousDecision = Invoke-Logged "doctor-ambiguous-decision-evidence.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Check"
  )
  Assert-True ($ambiguousDecision.Code -eq 2) "ambiguous artifact evidence should return PARTIAL exit 2, got $($ambiguousDecision.Code)"
  Assert-True (($ambiguousDecision.Output -join "`n") -match "(?m)^STATUS: PARTIAL") "ambiguous artifact evidence did not report PARTIAL"
  Write-Text (Join-Path $Project "Decision.md") $acceptedDecision
  Write-Text (Join-Path $Project "Decision.md") ($acceptedDecision.Replace(
    "- **Approved by:** Test Human",
    "- **Approved by:** <human name>"
  ))
  $missingHuman = Invoke-Logged "doctor-missing-human-link.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Check"
  )
  Assert-True ($missingHuman.Code -eq 2) "placeholder human approval should return PARTIAL exit 2, got $($missingHuman.Code)"
  Assert-True (($missingHuman.Output -join "`n") -match "(?m)^STATUS: PARTIAL") "placeholder human approval did not report PARTIAL"
  Write-Text (Join-Path $Project "Decision.md") $acceptedDecision
  [IO.File]::AppendAllText(
    (Join-Path $Project "Decision.md"),
    "`n" + $acceptedDecision.Substring($acceptedDecision.IndexOf("### ", [StringComparison]::Ordinal)),
    [Text.UTF8Encoding]::new($false)
  )
  $duplicateDecision = Invoke-Logged "doctor-duplicate-decision.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Check"
  )
  Assert-True ($duplicateDecision.Code -eq 2) "duplicate Decision ID should return PARTIAL exit 2, got $($duplicateDecision.Code)"
  Assert-True (($duplicateDecision.Output -join "`n") -match "(?m)^STATUS: PARTIAL") "duplicate Decision ID did not report PARTIAL"
  Write-Text (Join-Path $Project "Decision.md") $acceptedDecision
  $readyProject = Join-Path $LogRoot "PROJECT.ready.md"
  Move-Item -LiteralPath (Join-Path $Project "PROJECT.md") -Destination $readyProject
  $missingProject = Invoke-Logged "doctor-missing-project.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Check"
  )
  Assert-True ($missingProject.Code -eq 1) "missing PROJECT.md should return BLOCKED exit 1, got $($missingProject.Code)"
  Assert-True (($missingProject.Output -join "`n") -match "(?m)^STATUS: BLOCKED") "missing PROJECT.md did not report BLOCKED"
  Move-Item -LiteralPath $readyProject -Destination (Join-Path $Project "PROJECT.md")
  foreach ($templateName in @("PROJECT.md", "PRODUCT.md", "DESIGN.md", "Decision.md")) {
    Copy-Item -LiteralPath (Join-Path $Root "template/$templateName") -Destination (Join-Path $Project $templateName) -Force
  }

  Write-Host "8/9 global uninstall restores recorded originals"
  $uninstallPlan = Invoke-Logged "uninstall-plan.txt" (Join-Path $Root "install-skills.ps1") @(
    "-Harness", "both", "-Uninstall"
  )
  Assert-True ($uninstallPlan.Code -eq 0) "uninstall plan failed"
  Assert-Directory (Join-Path $ClaudeHome "skills/a11y-audit")
  $uninstallApply = Invoke-Logged "uninstall-apply.txt" (Join-Path $Root "install-skills.ps1") @(
    "-Harness", "both", "-Uninstall", "-Apply"
  )
  Assert-True ($uninstallApply.Code -eq 0) "uninstall apply failed"
  Assert-File (Join-Path $ClaudeHome "skills/impeccable/USER_MARKER.txt")
  Assert-File (Join-Path $CodexHome "skills/impeccable/USER_MARKER.txt")
  foreach ($harnessHome in @($ClaudeHome, $CodexHome)) {
    foreach ($skill in $ExpectedSkills) {
      if ($skill -eq "impeccable") { continue }
      Assert-Absent (Join-Path $harnessHome "skills/$skill")
    }
  }

  Write-Host "9/9 project uninstall preserves user adapters"
  $projectBeforeDrift = [IO.File]::ReadAllBytes((Join-Path $Project "PROJECT.md"))
  [IO.File]::AppendAllText((Join-Path $Project "PROJECT.md"), "`nlocal project edit`n", [Text.UTF8Encoding]::new($false))
  $projectDrift = Invoke-Logged "project-drift-uninstall.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Uninstall", "-Apply"
  )
  Assert-True ($projectDrift.Code -ne 0) "project uninstall accepted a changed owned file"
  Assert-True (([IO.File]::ReadAllText((Join-Path $Project "PROJECT.md"))) -match "local project edit") "changed project file was removed"
  Assert-File (Join-Path $Project "HARNESS.md")
  [IO.File]::WriteAllBytes((Join-Path $Project "PROJECT.md"), $projectBeforeDrift)
  $projectPlan = Invoke-Logged "project-uninstall-plan.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Uninstall"
  )
  Assert-True ($projectPlan.Code -eq 0) "project uninstall plan failed"
  Assert-File (Join-Path $Project "HARNESS.md")
  $projectApply = Invoke-Logged "project-uninstall-apply.txt" (Join-Path $Root "bootstrap.ps1") @(
    $Project, "-Harness", "both", "-Profile", $Profile, "-Uninstall", "-Apply"
  )
  Assert-True ($projectApply.Code -eq 0) "project uninstall apply failed"
  foreach ($file in @("HARNESS.md", "PROJECT.md", "PRODUCT.md", "DESIGN.md", "Decision.md", "Feedback.md")) {
    Assert-Absent (Join-Path $Project $file)
  }
  Assert-File (Join-Path $Project "CLAUDE.md")
  Assert-File (Join-Path $Project "AGENTS.md")
  Assert-True (([IO.File]::ReadAllText((Join-Path $Project "CLAUDE.md"))) -match "original claude adapter") "Claude adapter changed"
  Assert-True (([IO.File]::ReadAllText((Join-Path $Project "AGENTS.md"))) -match "original codex adapter") "Codex adapter changed"

  $Succeeded = $true
  Write-Host "PASS: isolated plan/apply/doctor/audit/drift/onboarding/uninstall lifecycle"
} catch {
  $Failure = $_
} finally {
  if ($Succeeded -and $env:KEEP_TEST_ARTIFACTS -ne "1") {
    Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $LogRoot -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Host "Test artifacts preserved:`n  state: $TestRoot`n  logs:  $LogRoot" -ForegroundColor Yellow
  }
}

if ($null -ne $Failure) {
  Write-Error $Failure
  exit 1
}
exit 0

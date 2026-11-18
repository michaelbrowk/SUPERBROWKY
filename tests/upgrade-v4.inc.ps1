# Dot-sourced by lifecycle.ps1 after its normal uninstall. Reuses only that
# runner's disposable directories and environment. Baseline: v4 at 7cabe54.

function Get-UpgradeReceiptField {
  param([string]$Path, [string]$Key)
  foreach ($line in [IO.File]::ReadAllLines($Path)) {
    $parts = $line.Split("`t", 2)
    if ($parts.Length -eq 2 -and $parts[0] -eq $Key) { return $parts[1] }
  }
  return ""
}

function Write-UpgradeSnapshot {
  param([string]$Path)
  $rows = @(Get-ChildItem -LiteralPath $ClaudeHome, $CodexHome, $StateHome, $UpgradeProject -Recurse -File -Force |
    Sort-Object FullName | ForEach-Object { "$($_.FullName)`t$(Get-Digest $_.FullName)" })
  Write-Text $Path (($rows -join "`n") + "`n")
}

function Assert-UpgradeLedger {
  param([object[]]$Ledger)
  foreach ($entry in $Ledger) {
    Assert-File $entry.Path
    Assert-True ((Get-Digest $entry.Path) -eq $entry.Hash) "upgrade changed preserved file: $($entry.Path)"
  }
}

Write-Host "10/10 upgrade real v4 full installation to v4.1"
$BaselineKit = $env:SUPERBROWKY_TEST_BASELINE_KIT
Assert-True ([IO.Path]::IsPathFullyQualified($BaselineKit)) "SUPERBROWKY_TEST_BASELINE_KIT must be absolute"
Assert-True ($BaselineKit -ne $Root) "upgrade baseline must differ from current kit"
Assert-File (Join-Path $BaselineKit "bootstrap.ps1")
Assert-File (Join-Path $BaselineKit "versions.lock")
Assert-True (
  Select-String -LiteralPath (Join-Path $BaselineKit "versions.lock") `
    -Pattern '^pbakaus/impeccable=e587004ee42883dad40d14cd0f5e1b21ae1933df$' -Quiet
) "baseline is not the reviewed v4 source"

$UpgradeProject = Join-Path $TestRoot "home/work/upgrade"
New-Item -ItemType Directory -Path $UpgradeProject | Out-Null
Write-Text (Join-Path $UpgradeProject "CLAUDE.md") "existing upgrade claude adapter`n"
Write-Text (Join-Path $UpgradeProject "AGENTS.md") "existing upgrade codex adapter`n"
foreach ($harnessHome in @($ClaudeHome, $CodexHome)) {
  Assert-File (Join-Path $harnessHome "skills/impeccable/USER_MARKER.txt")
  Write-Text (Join-Path $harnessHome "skills/high-end-visual-design/USER_MARKER.txt") "original retired skill`n"
}
$baselineApply = Invoke-Logged "upgrade-baseline-apply.txt" (Join-Path $BaselineKit "bootstrap.ps1") @(
  $UpgradeProject, "-Harness", "both", "-Profile", "full", "-Apply"
)
Assert-True ($baselineApply.Code -eq 0) "baseline full install failed: $($baselineApply.Code)"
[IO.File]::AppendAllText(
  (Join-Path $UpgradeProject "PRODUCT.md"),
  "`nAccepted project-specific wording to preserve.`n",
  [Text.UTF8Encoding]::new($false)
)
$upgradeTemplateNames = @("HARNESS.md", "PROJECT.md", "PRODUCT.md", "DESIGN.md", "Decision.md", "Feedback.md", "CLAUDE.md", "AGENTS.md")
$upgradeCanonical = @($upgradeTemplateNames | ForEach-Object {
  $path = Join-Path $UpgradeProject $_
  [pscustomobject]@{ Path = $path; Hash = (Get-Digest $path) }
})
$upgradeOldCandidates = @(Get-ChildItem -LiteralPath $UpgradeProject -File -Filter "*.from-superbrowky-v4-*" |
  ForEach-Object { [pscustomobject]@{ Path = $_.FullName; Hash = (Get-Digest $_.FullName) } })
Assert-True ($upgradeOldCandidates.Count -gt 0) "baseline created no merge candidates"

$upgradeBackups = @()
$upgradeRetired = @()
$upgradeOldTreeHashes = @{}
foreach ($forHarness in @("claude", "codex")) {
  $harnessHome = if ($forHarness -eq "claude") { $ClaudeHome } else { $CodexHome }
  $receipt = Join-Path $StateHome "state/$forHarness/impeccable.receipt.tsv"
  Assert-True (
    (Get-UpgradeReceiptField $receipt "ref") -eq "e587004ee42883dad40d14cd0f5e1b21ae1933df"
  ) "baseline did not install pinned v4 Impeccable"
  $upgradeOldTreeHashes[$forHarness] = Get-UpgradeReceiptField $receipt "tree_hash"
  foreach ($skill in @("impeccable", "high-end-visual-design")) {
    $receipt = Join-Path $StateHome "state/$forHarness/$skill.receipt.tsv"
    $upgradeBackups += [pscustomobject]@{
      Receipt = $receipt
      Backup = (Get-UpgradeReceiptField $receipt "backup")
      Type = (Get-UpgradeReceiptField $receipt "backup_type")
      Hash = (Get-UpgradeReceiptField $receipt "backup_hash")
    }
  }
  foreach ($skill in @("high-end-visual-design", "redesign-existing-projects")) {
    $receipt = Join-Path $StateHome "state/$forHarness/$skill.receipt.tsv"
    $upgradeRetired += [pscustomobject]@{ Path = $receipt; Hash = (Get-Digest $receipt) }
    $upgradeRetired += @(Get-ChildItem -LiteralPath (Join-Path $harnessHome "skills/$skill") -Recurse -File -Force |
      ForEach-Object { [pscustomobject]@{ Path = $_.FullName; Hash = (Get-Digest $_.FullName) } })
  }
}

# Verify preflight across versions, including all live receipts and backups.
$upgradeDriftFile = Join-Path $ClaudeHome "skills/emil-design-eng/SKILL.md"
$upgradeDriftOriginal = [IO.File]::ReadAllBytes($upgradeDriftFile)
[IO.File]::AppendAllText($upgradeDriftFile, "`nUser edit made on v4 before upgrade.`n", [Text.UTF8Encoding]::new($false))
$upgradeBefore = Join-Path $LogRoot "upgrade-refusal-before.tsv"
$upgradeAfter = Join-Path $LogRoot "upgrade-refusal-after.tsv"
Write-UpgradeSnapshot $upgradeBefore
$upgradeRefusal = Invoke-Logged "upgrade-refusal.txt" (Join-Path $Root "bootstrap.ps1") @(
  $UpgradeProject, "-Harness", "both", "-Profile", "full", "-Apply"
)
Assert-True ($upgradeRefusal.Code -ne 0) "v4.1 overwrote a user-edited v4 skill"
Assert-True (($upgradeRefusal.Output -join "`n") -match "managed copy drifted") "upgrade did not reach drift check"
Write-UpgradeSnapshot $upgradeAfter
Assert-True ((Get-Digest $upgradeBefore) -eq (Get-Digest $upgradeAfter)) "failed upgrade changed live files or receipts"
[IO.File]::WriteAllBytes($upgradeDriftFile, $upgradeDriftOriginal)

$upgradeApply = Invoke-Logged "upgrade-apply.txt" (Join-Path $Root "bootstrap.ps1") @(
  $UpgradeProject, "-Harness", "both", "-Profile", "full", "-Apply"
)
Assert-True ($upgradeApply.Code -eq 0) "upgrade apply failed: $($upgradeApply.Code)"
Assert-UpgradeLedger $upgradeCanonical
Assert-UpgradeLedger $upgradeOldCandidates
Assert-UpgradeLedger $upgradeRetired
foreach ($entry in $upgradeBackups) {
  Assert-True (
    (Get-UpgradeReceiptField $entry.Receipt "backup") -eq $entry.Backup -and
    (Get-UpgradeReceiptField $entry.Receipt "backup_type") -eq $entry.Type -and
    (Get-UpgradeReceiptField $entry.Receipt "backup_hash") -eq $entry.Hash
  ) "upgrade replaced original backup provenance"
  Assert-File (Join-Path $entry.Backup "USER_MARKER.txt")
}

$upgradePins = @{}
foreach ($line in [IO.File]::ReadAllLines((Join-Path $Root "versions.lock"))) {
  if ($line -match '^([^#=]+)=([0-9a-f]{40})$') { $upgradePins[$Matches[1]] = $Matches[2] }
}
$upgradeManifest = @(Import-Csv -LiteralPath (Join-Path $Root "manifests/skills.tsv") -Delimiter "`t")
foreach ($forHarness in @("claude", "codex")) {
  $harnessHome = if ($forHarness -eq "claude") { $ClaudeHome } else { $CodexHome }
  foreach ($entry in $upgradeManifest) {
    if ($entry.source_type -ne "git") { continue }
    $receipt = Join-Path $StateHome "state/$forHarness/$($entry.name).receipt.tsv"
    Assert-True (
      (Get-UpgradeReceiptField $receipt "ref") -eq $upgradePins[$entry.pin_key]
    ) "upgrade did not install the new pin: $forHarness/$($entry.name)"
  }
  $receipt = Join-Path $StateHome "state/$forHarness/impeccable.receipt.tsv"
  Assert-True (
    (Get-UpgradeReceiptField $receipt "tree_hash") -ne $upgradeOldTreeHashes[$forHarness]
  ) "upgrade retained old Impeccable tree"
  Assert-Absent (Join-Path $harnessHome "skills/impeccable/scripts/impeccable")
}

$newCandidateCount = 0
$upgradeProjectReceipt = Join-Path $UpgradeProject ".superbrowky/project-receipt.tsv"
foreach ($name in $upgradeTemplateNames) {
  $digest = Get-Digest (Join-Path $Root "template/$name")
  if ((Get-Digest (Join-Path $UpgradeProject $name)) -eq $digest) { continue }
  $candidateName = "$name.from-superbrowky-v4-$($digest.Substring(0, 12))"
  $candidatePath = Join-Path $UpgradeProject $candidateName
  Assert-File $candidatePath
  Assert-True ((Get-Digest $candidatePath) -eq $digest) "new candidate has wrong hash"
  $expectedRow = "candidate`t$candidateName`t$digest`ttemplate/$name"
  Assert-True ([IO.File]::ReadAllLines($upgradeProjectReceipt) -contains $expectedRow) "new candidate missing from receipt"
  $newCandidateCount++
}
Assert-True ($newCandidateCount -gt 0) "upgrade did not exercise changed templates"
$upgradeDoctor = Invoke-Logged "upgrade-doctor.txt" (Join-Path $Root "bootstrap.ps1") @(
  $UpgradeProject, "-Harness", "both", "-Profile", "full", "-Check"
)
Assert-True ($upgradeDoctor.Code -eq 2) "unmerged upgrade must report PARTIAL"
foreach ($skill in @("high-end-visual-design", "redesign-existing-projects")) {
  Assert-True (($upgradeDoctor.Output -join "`n").Contains($skill)) "doctor hid a retired installed skill"
}

$upgradeBefore = Join-Path $LogRoot "upgrade-reapply-before.tsv"
$upgradeAfter = Join-Path $LogRoot "upgrade-reapply-after.tsv"
Write-UpgradeSnapshot $upgradeBefore
$upgradeReapply = Invoke-Logged "upgrade-reapply.txt" (Join-Path $Root "bootstrap.ps1") @(
  $UpgradeProject, "-Harness", "both", "-Profile", "full", "-Apply"
)
Assert-True ($upgradeReapply.Code -eq 0) "upgrade reapply failed: $($upgradeReapply.Code)"
Write-UpgradeSnapshot $upgradeAfter
Assert-True (
  (Get-Digest $upgradeBefore) -eq (Get-Digest $upgradeAfter)
) "repeated upgrade changed receipts, backups, or candidates"

# A retired entry is still receipt-owned: edited copies block all removals.
$retiredDrift = Join-Path $CodexHome "skills/redesign-existing-projects/SKILL.md"
$retiredOriginal = [IO.File]::ReadAllBytes($retiredDrift)
[IO.File]::AppendAllText($retiredDrift, "`nUser edit in a retired skill.`n", [Text.UTF8Encoding]::new($false))
$upgradeBefore = Join-Path $LogRoot "upgrade-uninstall-refusal-before.tsv"
$upgradeAfter = Join-Path $LogRoot "upgrade-uninstall-refusal-after.tsv"
Write-UpgradeSnapshot $upgradeBefore
$retiredRefusal = Invoke-Logged "upgrade-retired-uninstall-refusal.txt" (Join-Path $Root "install-skills.ps1") @(
  "-Harness", "both", "-Uninstall", "-Apply"
)
Assert-True ($retiredRefusal.Code -ne 0) "uninstall removed a modified retired skill"
Assert-True (($retiredRefusal.Output -join "`n") -match "installed copy drifted") "retired uninstall did not reach drift check"
Write-UpgradeSnapshot $upgradeAfter
Assert-True ((Get-Digest $upgradeBefore) -eq (Get-Digest $upgradeAfter)) "refused uninstall changed live files"
[IO.File]::WriteAllBytes($retiredDrift, $retiredOriginal)
$upgradeUninstall = Invoke-Logged "upgrade-uninstall.txt" (Join-Path $Root "install-skills.ps1") @(
  "-Harness", "both", "-Uninstall", "-Apply"
)
Assert-True ($upgradeUninstall.Code -eq 0) "upgrade uninstall failed: $($upgradeUninstall.Code)"
foreach ($harnessHome in @($ClaudeHome, $CodexHome)) {
  Assert-File (Join-Path $harnessHome "skills/impeccable/USER_MARKER.txt")
  Assert-File (Join-Path $harnessHome "skills/high-end-visual-design/USER_MARKER.txt")
  Assert-Absent (Join-Path $harnessHome "skills/high-end-visual-design/SKILL.md")
  Assert-Absent (Join-Path $harnessHome "skills/redesign-existing-projects")
  foreach ($entry in $upgradeManifest) {
    if ($entry.name -eq "impeccable") { continue }
    Assert-Absent (Join-Path $harnessHome "skills/$($entry.name)")
  }
}
foreach ($forHarness in @("claude", "codex")) {
  Assert-True (
    @(Get-ChildItem -LiteralPath (Join-Path $StateHome "state/$forHarness") -File -Filter "*.receipt.tsv").Count -eq 0
  ) "uninstall left selected or retired receipts"
}
Assert-UpgradeLedger $upgradeCanonical
Assert-UpgradeLedger $upgradeOldCandidates
Write-Host "PASS: v4 -> v4.1 upgrade preserves edits, contexts, candidates, backups, and retired ownership"

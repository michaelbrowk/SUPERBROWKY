#!/usr/bin/env bash
# Sourced by lifecycle.sh after its normal uninstall. Every destination below
# belongs to that runner's disposable test root. Baseline: v4 at 7cabe54.

upgrade_receipt_field() {
  awk -F '\t' -v key="$2" '$1 == key { print $2; exit }' "$1"
}

upgrade_snapshot() {
  local file
  find "$CLAUDE_HOME" "$CODEX_HOME" "$SUPERBROWKY_STATE_HOME" "$UPGRADE_PROJECT" \
    -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      printf '%s\t%s\n' "$file" "$(hash_file "$file")"
    done
}

upgrade_assert_ledger() {
  local file expected
  while IFS="$(printf '\t')" read -r file expected; do
    assert_file "$file"
    [ "$(hash_file "$file")" = "$expected" ] || fail "upgrade changed preserved file: $file"
  done < "$1"
}

printf '10/10 upgrade real v4 full installation to v4.1\n'
BASELINE_KIT="${SUPERBROWKY_TEST_BASELINE_KIT}"
case "$BASELINE_KIT" in /*) ;; *) fail "SUPERBROWKY_TEST_BASELINE_KIT must be absolute" ;; esac
[ "$BASELINE_KIT" != "$ROOT" ] || fail "upgrade baseline must differ from the current kit"
assert_file "${BASELINE_KIT}/bootstrap.sh"
assert_file "${BASELINE_KIT}/versions.lock"
grep -q '^pbakaus/impeccable=e587004ee42883dad40d14cd0f5e1b21ae1933df$' \
  "${BASELINE_KIT}/versions.lock" || fail "baseline is not the reviewed v4 source"

UPGRADE_PROJECT="${TEST_ROOT}/home/work/upgrade"
mkdir -p "$UPGRADE_PROJECT"
printf 'existing upgrade claude adapter\n' > "${UPGRADE_PROJECT}/CLAUDE.md"
printf 'existing upgrade codex adapter\n' > "${UPGRADE_PROJECT}/AGENTS.md"
for harness_home in "$CLAUDE_HOME" "$CODEX_HOME"; do
  assert_file "${harness_home}/skills/impeccable/USER_MARKER.txt"
  mkdir -p "${harness_home}/skills/high-end-visual-design"
  printf 'original retired skill\n' > "${harness_home}/skills/high-end-visual-design/USER_MARKER.txt"
done
bash "${BASELINE_KIT}/bootstrap.sh" "$UPGRADE_PROJECT" --harness both --profile full --apply \
  > "${LOG_ROOT}/upgrade-baseline-apply.txt" 2>&1
# Simulate real project context written since the original installation.
printf '\nAccepted project-specific wording to preserve.\n' >> "${UPGRADE_PROJECT}/PRODUCT.md"
: > "${LOG_ROOT}/upgrade-canonical.tsv"
for name in HARNESS.md PROJECT.md PRODUCT.md DESIGN.md Decision.md Feedback.md CLAUDE.md AGENTS.md; do
  printf '%s\t%s\n' "${UPGRADE_PROJECT}/${name}" "$(hash_file "${UPGRADE_PROJECT}/${name}")" \
    >> "${LOG_ROOT}/upgrade-canonical.tsv"
done
find "$UPGRADE_PROJECT" -maxdepth 1 -type f -name '*.from-superbrowky-v4-*' -print \
  | LC_ALL=C sort | while IFS= read -r candidate; do
    printf '%s\t%s\n' "$candidate" "$(hash_file "$candidate")"
  done > "${LOG_ROOT}/upgrade-old-candidates.tsv"
[ -s "${LOG_ROOT}/upgrade-old-candidates.tsv" ] || fail "baseline created no merge candidates"

: > "${LOG_ROOT}/upgrade-backups.tsv"
: > "${LOG_ROOT}/upgrade-retired.tsv"
for harness in claude codex; do
  case "$harness" in claude) harness_home="$CLAUDE_HOME" ;; codex) harness_home="$CODEX_HOME" ;; esac
  receipt="${SUPERBROWKY_STATE_HOME}/state/${harness}/impeccable.receipt.tsv"
  [ "$(upgrade_receipt_field "$receipt" ref)" = 'e587004ee42883dad40d14cd0f5e1b21ae1933df' ] \
    || fail "baseline did not install pinned v4 Impeccable"
  cp "$receipt" "${LOG_ROOT}/upgrade-old-${harness}-impeccable.receipt.tsv"
  for skill in impeccable high-end-visual-design; do
    receipt="${SUPERBROWKY_STATE_HOME}/state/${harness}/${skill}.receipt.tsv"
    printf '%s\t%s\t%s\t%s\n' "$receipt" \
      "$(upgrade_receipt_field "$receipt" backup)" \
      "$(upgrade_receipt_field "$receipt" backup_type)" \
      "$(upgrade_receipt_field "$receipt" backup_hash)" >> "${LOG_ROOT}/upgrade-backups.tsv"
  done
  for skill in high-end-visual-design redesign-existing-projects; do
    receipt="${SUPERBROWKY_STATE_HOME}/state/${harness}/${skill}.receipt.tsv"
    printf '%s\t%s\n' "$receipt" "$(hash_file "$receipt")" >> "${LOG_ROOT}/upgrade-retired.tsv"
    find "${harness_home}/skills/${skill}" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      printf '%s\t%s\n' "$file" "$(hash_file "$file")"
    done >> "${LOG_ROOT}/upgrade-retired.tsv"
  done
done

# A changed user skill must block the cross-version upgrade before any other
# skill, receipt, backup, or project file changes.
upgrade_drift_file="${CLAUDE_HOME}/skills/emil-design-eng/SKILL.md"
cp "$upgrade_drift_file" "${LOG_ROOT}/upgrade-drift-original.md"
printf '\nUser edit made on v4 before upgrade.\n' >> "$upgrade_drift_file"
upgrade_snapshot > "${LOG_ROOT}/upgrade-refusal-before.tsv"
upgrade_drift_rc=0
bash "${ROOT}/bootstrap.sh" "$UPGRADE_PROJECT" --harness both --profile full --apply \
  > "${LOG_ROOT}/upgrade-refusal.txt" 2>&1 || upgrade_drift_rc=$?
[ "$upgrade_drift_rc" -ne 0 ] || fail "v4.1 overwrote a user-edited v4 skill"
grep -q 'managed copy drifted' "${LOG_ROOT}/upgrade-refusal.txt" \
  || fail "cross-version upgrade did not reach the drift check"
upgrade_snapshot > "${LOG_ROOT}/upgrade-refusal-after.tsv"
cmp -s "${LOG_ROOT}/upgrade-refusal-before.tsv" "${LOG_ROOT}/upgrade-refusal-after.tsv" \
  || fail "failed upgrade changed live files or receipts"
cp "${LOG_ROOT}/upgrade-drift-original.md" "$upgrade_drift_file"

bash "${ROOT}/bootstrap.sh" "$UPGRADE_PROJECT" --harness both --profile full --apply \
  > "${LOG_ROOT}/upgrade-apply.txt" 2>&1
upgrade_assert_ledger "${LOG_ROOT}/upgrade-canonical.tsv"
upgrade_assert_ledger "${LOG_ROOT}/upgrade-old-candidates.tsv"
upgrade_assert_ledger "${LOG_ROOT}/upgrade-retired.tsv"
while IFS="$(printf '\t')" read -r receipt backup backup_type backup_hash; do
  [ "$(upgrade_receipt_field "$receipt" backup)" = "$backup" ] &&
    [ "$(upgrade_receipt_field "$receipt" backup_type)" = "$backup_type" ] &&
    [ "$(upgrade_receipt_field "$receipt" backup_hash)" = "$backup_hash" ] \
    || fail "upgrade replaced the original backup provenance"
  assert_file "${backup}/USER_MARKER.txt"
done < "${LOG_ROOT}/upgrade-backups.tsv"

for harness in claude codex; do
  case "$harness" in claude) harness_home="$CLAUDE_HOME" ;; codex) harness_home="$CODEX_HOME" ;; esac
  while IFS="$(printf '\t')" read -r name profiles source_type repo pin_key unused; do
    : "$profiles" "$repo" "$unused"
    [ "$source_type" = git ] || continue
    expected_ref="$(awk -F '=' -v key="$pin_key" '$1 == key { print $2; exit }' "${ROOT}/versions.lock")"
    receipt="${SUPERBROWKY_STATE_HOME}/state/${harness}/${name}.receipt.tsv"
    [ "$(upgrade_receipt_field "$receipt" ref)" = "$expected_ref" ] \
      || fail "upgrade did not update ${harness}/${name} to the new pin"
  done < "${ROOT}/manifests/skills.tsv"
  receipt="${SUPERBROWKY_STATE_HOME}/state/${harness}/impeccable.receipt.tsv"
  [ "$(upgrade_receipt_field "$receipt" tree_hash)" != \
    "$(upgrade_receipt_field "${LOG_ROOT}/upgrade-old-${harness}-impeccable.receipt.tsv" tree_hash)" ] \
    || fail "upgrade retained the old Impeccable tree"
  assert_absent "${harness_home}/skills/impeccable/scripts/impeccable"
done

new_candidate_count=0
for name in HARNESS.md PROJECT.md PRODUCT.md DESIGN.md Decision.md Feedback.md CLAUDE.md AGENTS.md; do
  digest="$(hash_file "${ROOT}/template/${name}")"
  if [ "$(hash_file "${UPGRADE_PROJECT}/${name}")" != "$digest" ]; then
    candidate_name="${name}.from-superbrowky-v4-$(printf '%s' "$digest" | cut -c1-12)"
    assert_file "${UPGRADE_PROJECT}/${candidate_name}"
    [ "$(hash_file "${UPGRADE_PROJECT}/${candidate_name}")" = "$digest" ] \
      || fail "new merge candidate has the wrong hash"
    awk -F '\t' -v file="$candidate_name" -v digest="$digest" -v source="template/${name}" \
      '$1 == "candidate" && $2 == file && $3 == digest && $4 == source { found=1 } END { exit !found }' \
      "${UPGRADE_PROJECT}/.superbrowky/project-receipt.tsv" \
      || fail "new candidate is not recorded in the project receipt"
    new_candidate_count=$((new_candidate_count + 1))
  fi
done
[ "$new_candidate_count" -gt 0 ] || fail "upgrade did not exercise changed templates"
upgrade_doctor_rc=0
bash "${ROOT}/bootstrap.sh" "$UPGRADE_PROJECT" --harness both --profile full --check \
  > "${LOG_ROOT}/upgrade-doctor.txt" 2>&1 || upgrade_doctor_rc=$?
[ "$upgrade_doctor_rc" -eq 2 ] || fail "unmerged upgrade must report PARTIAL"
for skill in high-end-visual-design redesign-existing-projects; do
  grep -q "$skill" "${LOG_ROOT}/upgrade-doctor.txt" || fail "doctor hid a retired installed skill"
done

upgrade_snapshot > "${LOG_ROOT}/upgrade-reapply-before.tsv"
bash "${ROOT}/bootstrap.sh" "$UPGRADE_PROJECT" --harness both --profile full --apply \
  > "${LOG_ROOT}/upgrade-reapply.txt" 2>&1
upgrade_snapshot > "${LOG_ROOT}/upgrade-reapply-after.tsv"
cmp -s "${LOG_ROOT}/upgrade-reapply-before.tsv" "${LOG_ROOT}/upgrade-reapply-after.tsv" \
  || fail "repeating upgrade changed receipts, backups, or merge candidates"

# The removed manifest entries remain owned by receipts. A user edit to one
# must block even an explicit uninstall, before any selected skill is removed.
retired_drift="${CODEX_HOME}/skills/redesign-existing-projects/SKILL.md"
cp "$retired_drift" "${LOG_ROOT}/upgrade-retired-original.md"
printf '\nUser edit in a retired skill.\n' >> "$retired_drift"
upgrade_snapshot > "${LOG_ROOT}/upgrade-uninstall-refusal-before.tsv"
retired_uninstall_rc=0
bash "${ROOT}/install-skills.sh" --harness both --uninstall --apply \
  > "${LOG_ROOT}/upgrade-retired-uninstall-refusal.txt" 2>&1 || retired_uninstall_rc=$?
[ "$retired_uninstall_rc" -ne 0 ] || fail "uninstall removed a modified retired skill"
grep -q 'installed copy drifted' "${LOG_ROOT}/upgrade-retired-uninstall-refusal.txt" \
  || fail "retired uninstall did not reach the drift check"
upgrade_snapshot > "${LOG_ROOT}/upgrade-uninstall-refusal-after.tsv"
cmp -s "${LOG_ROOT}/upgrade-uninstall-refusal-before.tsv" "${LOG_ROOT}/upgrade-uninstall-refusal-after.tsv" \
  || fail "refused retired uninstall changed live files"
cp "${LOG_ROOT}/upgrade-retired-original.md" "$retired_drift"
bash "${ROOT}/install-skills.sh" --harness both --uninstall --apply \
  > "${LOG_ROOT}/upgrade-uninstall.txt" 2>&1
for harness_home in "$CLAUDE_HOME" "$CODEX_HOME"; do
  assert_file "${harness_home}/skills/impeccable/USER_MARKER.txt"
  assert_file "${harness_home}/skills/high-end-visual-design/USER_MARKER.txt"
  assert_absent "${harness_home}/skills/high-end-visual-design/SKILL.md"
  assert_absent "${harness_home}/skills/redesign-existing-projects"
  for skill in $(awk -F '\t' 'NR > 1 { print $1 }' "${ROOT}/manifests/skills.tsv"); do
    [ "$skill" = impeccable ] && continue
    assert_absent "${harness_home}/skills/${skill}"
  done
done
for harness in claude codex; do
  [ -z "$(find "${SUPERBROWKY_STATE_HOME}/state/${harness}" -type f -name '*.receipt.tsv' -print)" ] \
    || fail "uninstall left selected or retired receipts"
done
upgrade_assert_ledger "${LOG_ROOT}/upgrade-canonical.tsv"
upgrade_assert_ledger "${LOG_ROOT}/upgrade-old-candidates.tsv"
printf 'PASS: v4 → v4.1 upgrade preserves edits, contexts, candidates, backups, and retired ownership\n'

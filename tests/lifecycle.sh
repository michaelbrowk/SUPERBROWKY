#!/usr/bin/env bash
# End-to-end safety test in an isolated HOME. Network is used only to fetch the
# exact commits in versions.lock.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${SUPERBROWKY_TEST_PROFILE:-core}"
EXPECTED_SKILLS="impeccable emil-design-eng design-taste-frontend stop-slop psi-optimize a11y-audit meta-audit"
case "$PROFILE" in
  core) ;;
  web-launch)
    EXPECTED_SKILLS="${EXPECTED_SKILLS} seo-audit schema site-architecture"
    ;;
  growth)
    EXPECTED_SKILLS="${EXPECTED_SKILLS} seo-audit schema site-architecture ai-seo programmatic-seo cro"
    ;;
  full)
    EXPECTED_SKILLS="${EXPECTED_SKILLS} seo-audit schema site-architecture ai-seo programmatic-seo cro high-end-visual-design redesign-existing-projects"
    ;;
  *) printf 'Invalid SUPERBROWKY_TEST_PROFILE: %s\n' "$PROFILE" >&2; exit 2 ;;
esac
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/superbrowky-lifecycle.XXXXXX")"
LOG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/superbrowky-lifecycle-logs.XXXXXX")"

cleanup() {
  result=$?
  trap - EXIT
  if [ "$result" -ne 0 ] || [ "${KEEP_TEST_ARTIFACTS:-0}" = "1" ]; then
    printf 'Test artifacts preserved:\n  state: %s\n  logs:  %s\n' \
      "$TEST_ROOT" "$LOG_ROOT" >&2
  else
    case "$TEST_ROOT" in
      */superbrowky-lifecycle.*) rm -rf "$TEST_ROOT" ;;
    esac
    case "$LOG_ROOT" in
      */superbrowky-lifecycle-logs.*) rm -rf "$LOG_ROOT" ;;
    esac
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_dir() {
  [ -d "$1" ] || fail "missing directory: $1"
}

assert_absent() {
  [ ! -e "$1" ] && [ ! -L "$1" ] || fail "expected absent: $1"
}

assert_provenance() {
  for name in LICENSE LICENSE.md NOTICE NOTICE.md; do
    if [ -f "$1/$name" ] && [ ! -L "$1/$name" ]; then
      return 0
    fi
  done
  fail "missing third-party license/notice: $1"
}

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

HOME="${TEST_ROOT}/home"
CLAUDE_HOME="${HOME}/.claude"
CODEX_HOME="${HOME}/.codex"
SUPERBROWKY_STATE_HOME="${HOME}/.superbrowky"
PROJECT="${HOME}/work/example"
export HOME CLAUDE_HOME CODEX_HOME SUPERBROWKY_STATE_HOME
export SUPER_SECRET_DO_NOT_CAPTURE="lifecycle-secret-marker"

mkdir -p \
  "${CLAUDE_HOME}/skills/impeccable" \
  "${CODEX_HOME}/skills/impeccable" \
  "$PROJECT"
printf 'original claude skill\n' > "${CLAUDE_HOME}/skills/impeccable/USER_MARKER.txt"
printf 'original codex skill\n' > "${CODEX_HOME}/skills/impeccable/USER_MARKER.txt"
printf 'original claude adapter\n' > "${PROJECT}/CLAUDE.md"
printf 'original codex adapter\n' > "${PROJECT}/AGENTS.md"

printf '1/9 plan is read-only\n'
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" > "${LOG_ROOT}/plan.txt" 2>&1
assert_file "${CLAUDE_HOME}/skills/impeccable/USER_MARKER.txt"
assert_file "${CODEX_HOME}/skills/impeccable/USER_MARKER.txt"
assert_absent "${SUPERBROWKY_STATE_HOME}/state"
assert_absent "${PROJECT}/HARNESS.md"
[ "$(find "$PROJECT" -maxdepth 1 -type f | wc -l | tr -d ' ')" = "2" ] \
  || fail "plan wrote project files"
grep -q 'PLAN ONLY' "${LOG_ROOT}/plan.txt" || fail "plan did not identify itself"
plan_apply_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --plan --apply \
  > "${LOG_ROOT}/plan-with-apply.txt" 2>&1 || plan_apply_rc=$?
[ "$plan_apply_rc" -ne 0 ] || fail "--plan --apply was accepted"
assert_absent "${SUPERBROWKY_STATE_HOME}/state"
assert_absent "${PROJECT}/HARNESS.md"

printf '2/9 apply, receipts, adapters, and overlays\n'
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --apply > "${LOG_ROOT}/apply.txt" 2>&1

for harness in claude codex; do
  case "$harness" in
    claude) harness_home="$CLAUDE_HOME" ;;
    codex) harness_home="$CODEX_HOME" ;;
  esac
  for skill in $EXPECTED_SKILLS; do
    assert_file "${harness_home}/skills/${skill}/SKILL.md"
    assert_file "${SUPERBROWKY_STATE_HOME}/state/${harness}/${skill}.receipt.tsv"
    case "$skill" in
      psi-optimize|a11y-audit|meta-audit) ;;
      *) assert_provenance "${harness_home}/skills/${skill}" ;;
    esac
  done
  for skill in impeccable emil-design-eng design-taste-frontend stop-slop; do
    grep -q 'SUPERBROWKY third-party safety' \
      "${harness_home}/skills/${skill}/SKILL.md" \
      || fail "common overlay missing from ${harness}/${skill}"
  done
  grep -q 'SUPERBROWKY portable contract' \
    "${harness_home}/skills/impeccable/SKILL.md" \
    || fail "Impeccable overlay missing from ${harness}"
  assert_absent "${harness_home}/skills/impeccable/scripts/cleanup-deprecated.mjs"
  assert_absent "${harness_home}/skills/impeccable/scripts/pin.mjs"
  assert_file "${harness_home}/skills/impeccable/LICENSE"
done

assert_file "${PROJECT}/HARNESS.md"
assert_file "${PROJECT}/PROJECT.md"
assert_file "${PROJECT}/PRODUCT.md"
assert_file "${PROJECT}/DESIGN.md"
assert_file "${PROJECT}/Decision.md"
assert_file "${PROJECT}/Feedback.md"
grep -q 'original claude adapter' "${PROJECT}/CLAUDE.md" \
  || fail "pre-existing CLAUDE.md was overwritten"
grep -q 'original codex adapter' "${PROJECT}/AGENTS.md" \
  || fail "pre-existing AGENTS.md was overwritten"
[ "$(find "$PROJECT" -maxdepth 1 -type f -name 'CLAUDE.md.from-superbrowky-v4-*' | wc -l | tr -d ' ')" = "1" ] \
  || fail "Claude merge candidate missing or duplicated"
[ "$(find "$PROJECT" -maxdepth 1 -type f -name 'AGENTS.md.from-superbrowky-v4-*' | wc -l | tr -d ' ')" = "1" ] \
  || fail "Codex merge candidate missing or duplicated"

if grep -R -n -E 'allowed-tools:.*Bash\(npx impeccable|\.claude/skills/impeccable|\.agents/skills/impeccable' \
    "${CLAUDE_HOME}/skills/impeccable" "${CODEX_HOME}/skills/impeccable" \
    > "${LOG_ROOT}/unsafe-impeccable-paths.txt"; then
  fail "unsafe Impeccable commands or harness-relative paths remain"
fi

printf '3/9 doctor reports honest onboarding state\n'
project_receipt="${PROJECT}/.superbrowky/project-receipt.tsv"
cp "$project_receipt" "${LOG_ROOT}/project-receipt.clean.tsv"
duplicate_row="$(awk -F '\t' '$4 == "template/HARNESS.md" { print; exit }' "$project_receipt")"
[ -n "$duplicate_row" ] || fail "HARNESS project receipt row missing"
printf '%s\n' "$duplicate_row" >> "$project_receipt"
duplicate_receipt_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --check > "${LOG_ROOT}/doctor-duplicate-receipt.txt" 2>&1 \
  || duplicate_receipt_rc=$?
[ "$duplicate_receipt_rc" -eq 1 ] \
  || fail "duplicate project receipt should return BLOCKED exit 1, got ${duplicate_receipt_rc}"
grep -q '^STATUS: BLOCKED' "${LOG_ROOT}/doctor-duplicate-receipt.txt" \
  || fail "duplicate project receipt did not report BLOCKED"
cp "${LOG_ROOT}/project-receipt.clean.tsv" "$project_receipt"
doctor_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --check > "${LOG_ROOT}/doctor.txt" 2>&1 \
  || doctor_rc=$?
[ "$doctor_rc" -eq 2 ] || fail "expected PARTIAL doctor exit 2, got ${doctor_rc}"
grep -q '^STATUS: PARTIAL' "${LOG_ROOT}/doctor.txt" \
  || fail "doctor did not report PARTIAL"

printf '4/9 audit plan is read-only, apply is redacted\n'
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --audit-bundle > "${LOG_ROOT}/audit-plan.txt" 2>&1
assert_absent "${PROJECT}/AuditBundles"
audit_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --audit-bundle --apply \
  > "${LOG_ROOT}/audit-apply.txt" 2>&1 || audit_rc=$?
[ "$audit_rc" -eq 2 ] || fail "expected audit to preserve PARTIAL exit 2, got ${audit_rc}"
audit_file="$(find "${PROJECT}/AuditBundles" -type f -name 'SUPERBROWKY-Audit-*.md' -print | head -n 1)"
[ -n "$audit_file" ] || fail "audit bundle was not created"
if grep -q "$SUPER_SECRET_DO_NOT_CAPTURE" "$audit_file"; then
  fail "audit bundle captured an environment secret"
fi
if grep -q "$HOME" "$audit_file"; then
  fail "audit bundle exposed the absolute HOME path"
fi
grep -q 'Project: `~/work/example`' "$audit_file" \
  || fail "audit bundle did not redact the project path"
grep -q '| `PROJECT.md` |' "$audit_file" \
  || fail "audit bundle omitted PROJECT.md"
grep -Eq '`[0-9a-f]{64}`' "$audit_file" \
  || fail "audit bundle omitted receipt hashes"

printf '5/9 reinstall is idempotent\n'
backup_count_before="$(find "${SUPERBROWKY_STATE_HOME}/backups" -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
receipt_hash_before="$(hash_file "${SUPERBROWKY_STATE_HOME}/state/claude/impeccable.receipt.tsv")"
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --apply > "${LOG_ROOT}/reapply.txt" 2>&1
backup_count_after="$(find "${SUPERBROWKY_STATE_HOME}/backups" -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
receipt_hash_after="$(hash_file "${SUPERBROWKY_STATE_HOME}/state/claude/impeccable.receipt.tsv")"
[ "$backup_count_before" = "$backup_count_after" ] \
  || fail "idempotent reinstall created another backup"
[ "$receipt_hash_before" = "$receipt_hash_after" ] \
  || fail "idempotent reinstall rewrote its receipt"
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness claude --profile "$PROFILE" --apply > "${LOG_ROOT}/reapply-claude-only.txt" 2>&1
grep -q 'template/AGENTS.md$' "${PROJECT}/.superbrowky/project-receipt.tsv" \
  || fail "switching both → claude dropped prior Codex adapter ownership"

printf '6/9 drift blocks all live replacement and removal\n'
drift_file="${CLAUDE_HOME}/skills/a11y-audit/SKILL.md"
drift_original="${LOG_ROOT}/a11y-original.md"
cp "$drift_file" "$drift_original"
printf '\nlocal user edit\n' >> "$drift_file"
guard_before="$(hash_file "${CODEX_HOME}/skills/psi-optimize/SKILL.md")"
drift_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --apply > "${LOG_ROOT}/drift-apply.txt" 2>&1 \
  || drift_rc=$?
[ "$drift_rc" -ne 0 ] || fail "reinstall accepted a drifted managed skill"
grep -q 'local user edit' "$drift_file" || fail "drifted skill was overwritten"
[ "$guard_before" = "$(hash_file "${CODEX_HOME}/skills/psi-optimize/SKILL.md")" ] \
  || fail "another skill changed after drift preflight failed"

drift_uninstall_rc=0
bash "${ROOT}/install-skills.sh" --harness both --uninstall --apply \
  > "${LOG_ROOT}/drift-uninstall.txt" 2>&1 || drift_uninstall_rc=$?
[ "$drift_uninstall_rc" -ne 0 ] || fail "uninstall accepted a drifted managed skill"
assert_dir "${CODEX_HOME}/skills/psi-optimize"
cp "$drift_original" "$drift_file"

printf '7/9 completed onboarding can become READY\n'
printf '# Project map\n\n## Runtime\n\n- **Stack:** static test fixture\n- **Test command:** bash tests/lifecycle.sh\n\n## Surface map\n\n| Surface | Code paths | Product context | Design context | Verification |\n|---|---|---|---|---|\n| fixture | `tests/` | `PRODUCT.md` | `DESIGN.md` | lifecycle |\n' > "${PROJECT}/PROJECT.md"
printf '# Product\n\n## Authority\n\n- **Artifact ID:** PRODUCT-v1\n- **Version:** 1.0\n- **Status:** ACCEPTED\n- **Accepted by:** Test Human\n- **Accepted on:** 2026-07-23\n- **Decision reference:** DEC-TEST-001\n\nReal product context.\n' > "${PROJECT}/PRODUCT.md"
printf '# Design System\n\n## Authority\n\n- **Artifact ID:** DESIGN-v1\n- **Version:** 1.0\n- **Status:** ACCEPTED\n- **Accepted by:** Test Human\n- **Accepted on:** 2026-07-23\n- **Decision reference:** DEC-TEST-001\n\nAccepted project-owned design context.\n' > "${PROJECT}/DESIGN.md"
product_hash="$(hash_file "${PROJECT}/PRODUCT.md")"
design_hash="$(hash_file "${PROJECT}/DESIGN.md")"
printf '# Decisions\n\n### 2026-07-23 — Accept test context\n\n- **Decision ID:** DEC-TEST-001\n- **Status:** ACCEPTED\n- **Type:** CONTEXT\n- **Scope:** lifecycle fixture\n- **Decision:** accept PRODUCT-v1 and DESIGN-v1\n- **Basis:** deterministic fixture\n- **Reviewed artifacts:** `PRODUCT.md` PRODUCT-v1/1.0 sha256:%s; `DESIGN.md` DESIGN-v1/1.0 sha256:%s\n- **Approved by:** Test Human\n- **Approved on:** 2026-07-23 Europe/Moscow\n- **Authorizes:** lifecycle verification\n- **Does not authorize:** production work\n- **Gate transition:** context draft → accepted\n- **Replaces:** none\n' \
  "$product_hash" "$design_hash" > "${PROJECT}/Decision.md"
printf 'original claude adapter\nRead HARNESS.md.\n' > "${PROJECT}/CLAUDE.md"
printf 'original codex adapter\nRead HARNESS.md.\n' > "${PROJECT}/AGENTS.md"
for candidate in \
  "${PROJECT}"/CLAUDE.md.from-superbrowky-v4-* \
  "${PROJECT}"/AGENTS.md.from-superbrowky-v4-*; do
  [ -e "$candidate" ] || [ -L "$candidate" ] || continue
  candidate_name="$(basename "$candidate")"
  canonical_name="${candidate_name%%.from-superbrowky-v4-*}"
  candidate_hash="$(hash_file "$candidate")"
  printf '\n<!-- SUPERBROWKY-MERGED: template/%s sha256:%s -->\n' \
    "$canonical_name" "$candidate_hash" >> "${PROJECT}/${canonical_name}"
  rm "$candidate"
done
ready_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --check > "${LOG_ROOT}/doctor-ready.txt" 2>&1 \
  || ready_rc=$?
[ "$ready_rc" -eq 0 ] || fail "completed onboarding did not reach READY"
grep -q '^STATUS: READY' "${LOG_ROOT}/doctor-ready.txt" \
  || fail "completed onboarding did not report READY"
drift_kit="${TEST_ROOT}/kit-drift"
mkdir -p "$drift_kit"
cp -R "${ROOT}/." "$drift_kit/"
printf '\n<!-- test template revision -->\n' >> "${drift_kit}/template/AGENTS.md"
template_drift_rc=0
bash "${drift_kit}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --check > "${LOG_ROOT}/doctor-template-drift.txt" 2>&1 \
  || template_drift_rc=$?
[ "$template_drift_rc" -eq 2 ] \
  || fail "new kit adapter template should return PARTIAL exit 2, got ${template_drift_rc}"
grep -q '^STATUS: PARTIAL' "${LOG_ROOT}/doctor-template-drift.txt" \
  || fail "new kit adapter template did not report PARTIAL"
cp "${ROOT}/template/AGENTS.md" "${drift_kit}/template/AGENTS.md"
printf '\n<!-- test bundled revision -->\n' >> "${drift_kit}/skills/a11y-audit/SKILL.md"
bundled_drift_rc=0
bash "${drift_kit}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --check > "${LOG_ROOT}/doctor-bundled-drift.txt" 2>&1 \
  || bundled_drift_rc=$?
[ "$bundled_drift_rc" -eq 2 ] \
  || fail "new bundled skill source should return PARTIAL exit 2, got ${bundled_drift_rc}"
grep -q '^STATUS: PARTIAL' "${LOG_ROOT}/doctor-bundled-drift.txt" \
  || fail "new bundled skill source did not report PARTIAL"
cp "${drift_kit}/manifests/skills.tsv" "${LOG_ROOT}/skills-manifest.clean.tsv"
ln -s "${drift_kit}/skills" "${drift_kit}/linked-skills"
{
  sed -n '1p' "${LOG_ROOT}/skills-manifest.clean.tsv"
  printf 'psi-optimize\tcore\tbundled\t.\t-\tlinked-skills/psi-optimize\tlinked-skills/psi-optimize\tMIT\tyes\n'
} > "${drift_kit}/manifests/skills.tsv"
linked_source_rc=0
bash "${drift_kit}/install-skills.sh" --harness both --profile core --apply \
  > "${LOG_ROOT}/linked-source-path.txt" 2>&1 || linked_source_rc=$?
[ "$linked_source_rc" -ne 0 ] \
  || fail "installer accepted a symlinked intermediate source directory"
grep -q 'source path contains a missing or linked directory' "${LOG_ROOT}/linked-source-path.txt" \
  || fail "linked intermediate source did not fail closed"
cp "${LOG_ROOT}/skills-manifest.clean.tsv" "${drift_kit}/manifests/skills.tsv"
cp "${PROJECT}/Decision.md" "${LOG_ROOT}/Decision.ready.md"
bad_hash='0000000000000000000000000000000000000000000000000000000000000000'
sed "s/${product_hash}/${bad_hash}/" "${LOG_ROOT}/Decision.ready.md" \
  > "${PROJECT}/Decision.md"
wrong_hash_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --check > "${LOG_ROOT}/doctor-wrong-decision-hash.txt" 2>&1 \
  || wrong_hash_rc=$?
[ "$wrong_hash_rc" -eq 2 ] \
  || fail "wrong accepted artifact hash should return PARTIAL exit 2, got ${wrong_hash_rc}"
grep -q '^STATUS: PARTIAL' "${LOG_ROOT}/doctor-wrong-decision-hash.txt" \
  || fail "wrong accepted artifact hash did not report PARTIAL"
cp "${LOG_ROOT}/Decision.ready.md" "${PROJECT}/Decision.md"
sed "s@PRODUCT-v1/1.0 sha256:${product_hash}@PRODUCT-v1/9.9; OTHER/1.0; junk${product_hash}suffix@" \
  "${LOG_ROOT}/Decision.ready.md" > "${PROJECT}/Decision.md"
ambiguous_decision_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --check > "${LOG_ROOT}/doctor-ambiguous-decision-evidence.txt" 2>&1 \
  || ambiguous_decision_rc=$?
[ "$ambiguous_decision_rc" -eq 2 ] \
  || fail "ambiguous artifact evidence should return PARTIAL exit 2, got ${ambiguous_decision_rc}"
grep -q '^STATUS: PARTIAL' "${LOG_ROOT}/doctor-ambiguous-decision-evidence.txt" \
  || fail "ambiguous artifact evidence did not report PARTIAL"
cp "${LOG_ROOT}/Decision.ready.md" "${PROJECT}/Decision.md"
sed 's/- \*\*Approved by:\*\* Test Human/- **Approved by:** <human name>/' \
  "${LOG_ROOT}/Decision.ready.md" > "${PROJECT}/Decision.md"
missing_human_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --check > "${LOG_ROOT}/doctor-missing-human-link.txt" 2>&1 \
  || missing_human_rc=$?
[ "$missing_human_rc" -eq 2 ] \
  || fail "placeholder human approval should return PARTIAL exit 2, got ${missing_human_rc}"
grep -q '^STATUS: PARTIAL' "${LOG_ROOT}/doctor-missing-human-link.txt" \
  || fail "placeholder human approval did not report PARTIAL"
cp "${LOG_ROOT}/Decision.ready.md" "${PROJECT}/Decision.md"
printf '\n%s\n' "$(sed -n '/^### /,$p' "${LOG_ROOT}/Decision.ready.md")" \
  >> "${PROJECT}/Decision.md"
duplicate_decision_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --check > "${LOG_ROOT}/doctor-duplicate-decision.txt" 2>&1 \
  || duplicate_decision_rc=$?
[ "$duplicate_decision_rc" -eq 2 ] \
  || fail "duplicate Decision ID should return PARTIAL exit 2, got ${duplicate_decision_rc}"
grep -q '^STATUS: PARTIAL' "${LOG_ROOT}/doctor-duplicate-decision.txt" \
  || fail "duplicate Decision ID did not report PARTIAL"
cp "${LOG_ROOT}/Decision.ready.md" "${PROJECT}/Decision.md"
mv "${PROJECT}/PROJECT.md" "${LOG_ROOT}/PROJECT.ready.md"
missing_project_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --check > "${LOG_ROOT}/doctor-missing-project.txt" 2>&1 \
  || missing_project_rc=$?
[ "$missing_project_rc" -eq 1 ] \
  || fail "missing PROJECT.md should return BLOCKED exit 1, got ${missing_project_rc}"
grep -q '^STATUS: BLOCKED' "${LOG_ROOT}/doctor-missing-project.txt" \
  || fail "missing PROJECT.md did not report BLOCKED"
mv "${LOG_ROOT}/PROJECT.ready.md" "${PROJECT}/PROJECT.md"
# Restore installer-owned templates so the clean project-uninstall branch can
# be verified independently; user-modified files are covered by drift tests.
for template_name in PROJECT.md PRODUCT.md DESIGN.md Decision.md; do
  cp "${ROOT}/template/${template_name}" "${PROJECT}/${template_name}"
done

printf '8/9 global uninstall restores only recorded originals\n'
bash "${ROOT}/install-skills.sh" --harness both --uninstall \
  > "${LOG_ROOT}/uninstall-plan.txt" 2>&1
assert_dir "${CLAUDE_HOME}/skills/a11y-audit"
bash "${ROOT}/install-skills.sh" --harness both --uninstall --apply \
  > "${LOG_ROOT}/uninstall-apply.txt" 2>&1
assert_file "${CLAUDE_HOME}/skills/impeccable/USER_MARKER.txt"
assert_file "${CODEX_HOME}/skills/impeccable/USER_MARKER.txt"
for harness_home in "$CLAUDE_HOME" "$CODEX_HOME"; do
  for skill in $EXPECTED_SKILLS; do
    [ "$skill" = "impeccable" ] && continue
    assert_absent "${harness_home}/skills/${skill}"
  done
done

printf '9/9 project uninstall preserves user adapters\n'
cp "${PROJECT}/PROJECT.md" "${LOG_ROOT}/PROJECT.before-project-drift.md"
printf '\nlocal project edit\n' >> "${PROJECT}/PROJECT.md"
project_drift_rc=0
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --uninstall --apply \
  > "${LOG_ROOT}/project-drift-uninstall.txt" 2>&1 || project_drift_rc=$?
[ "$project_drift_rc" -ne 0 ] || fail "project uninstall accepted a changed owned file"
grep -q 'local project edit' "${PROJECT}/PROJECT.md" \
  || fail "project uninstall removed the changed project file"
assert_file "${PROJECT}/HARNESS.md"
cp "${LOG_ROOT}/PROJECT.before-project-drift.md" "${PROJECT}/PROJECT.md"
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --uninstall > "${LOG_ROOT}/project-uninstall-plan.txt" 2>&1
assert_file "${PROJECT}/HARNESS.md"
bash "${ROOT}/bootstrap.sh" "$PROJECT" \
  --harness both --profile "$PROFILE" --uninstall --apply \
  > "${LOG_ROOT}/project-uninstall-apply.txt" 2>&1
assert_absent "${PROJECT}/HARNESS.md"
assert_absent "${PROJECT}/PROJECT.md"
assert_absent "${PROJECT}/PRODUCT.md"
assert_absent "${PROJECT}/DESIGN.md"
assert_absent "${PROJECT}/Decision.md"
assert_absent "${PROJECT}/Feedback.md"
assert_file "${PROJECT}/CLAUDE.md"
assert_file "${PROJECT}/AGENTS.md"
grep -q 'original claude adapter' "${PROJECT}/CLAUDE.md"
grep -q 'original codex adapter' "${PROJECT}/AGENTS.md"

printf 'PASS: isolated plan/apply/doctor/audit/drift/onboarding/uninstall lifecycle\n'

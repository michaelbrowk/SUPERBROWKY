#!/usr/bin/env bash
# Read-only health check for SUPERBROWKY skills and optional project adapters.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "${SCRIPT_DIR}/lib.sh"

SB_CLAUDE_HOME_EXPLICIT=0
SB_CODEX_HOME_EXPLICIT=0
[ -n "${CLAUDE_HOME:-}" ] && SB_CLAUDE_HOME_EXPLICIT=1
[ -n "${CODEX_HOME:-}" ] && SB_CODEX_HOME_EXPLICIT=1
CLAUDE_HOME="${CLAUDE_HOME:-"$HOME/.claude"}"
CODEX_HOME="${CODEX_HOME:-"$HOME/.codex"}"
SUPERBROWKY_STATE_HOME="${SUPERBROWKY_STATE_HOME:-"$HOME/.superbrowky"}"
export CLAUDE_HOME CODEX_HOME SUPERBROWKY_STATE_HOME
export SB_CLAUDE_HOME_EXPLICIT SB_CODEX_HOME_EXPLICIT

MANIFEST="${ROOT}/manifests/skills.tsv"
LOCK_FILE="${ROOT}/versions.lock"
HARNESS="auto"
PROFILE="core"
TARGET=""
BLOCKED=0
WARNINGS=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/doctor.sh [options]

Options:
  --harness auto|claude|codex|both
  --profile core|web-launch|growth|full
  --target /path/to/project     also verify project adapters/templates
  -h, --help

This command is read-only.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --harness)
      [ "$#" -ge 2 ] || { sb_error "--harness needs a value"; exit 2; }
      HARNESS="$2"
      shift
      ;;
    --harness=*) HARNESS="${1#--harness=}" ;;
    --profile)
      [ "$#" -ge 2 ] || { sb_error "--profile needs a value"; exit 2; }
      PROFILE="$2"
      shift
      ;;
    --profile=*) PROFILE="${1#--profile=}" ;;
    --target)
      [ "$#" -ge 2 ] || { sb_error "--target needs a path"; exit 2; }
      TARGET="$2"
      shift
      ;;
    --target=*) TARGET="${1#--target=}" ;;
    -h|--help) usage; exit 0 ;;
    *) sb_error "Unknown argument: $1"; usage; exit 2 ;;
  esac
  shift
done

case "$HARNESS" in auto|claude|codex|both) ;; *)
  sb_error "Invalid harness: $HARNESS"
  exit 2
esac
case "$PROFILE" in core|web-launch|growth|full) ;; *)
  sb_error "Invalid profile: $PROFILE"
  exit 2
esac
if [ "$HARNESS" = "auto" ]; then
  if ! HARNESS="$(sb_detect_harness "$TARGET")"; then
    sb_error "Could not detect Claude Code or Codex."
    sb_status "BLOCKED — pass --harness claude, codex, or both."
    exit 1
  fi
  sb_ok "auto-detected harness: $HARNESS"
fi
if [ ! -f "$MANIFEST" ] || [ ! -f "$LOCK_FILE" ]; then
  sb_error "Manifest or versions.lock is missing"
  sb_status "BLOCKED — repository is incomplete."
  exit 1
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/superbrowky-doctor.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
SELECTED="${TMP_ROOT}/selected.tsv"

build_selection() {
  local first=1 line name profiles source_type repo pin_key claude_folder codex_folder license _required
  : > "$SELECTED"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" -eq 1 ]; then first=0; continue; fi
    [ -n "$line" ] || continue
    IFS="$(printf '\t')" read -r name profiles source_type repo pin_key claude_folder codex_folder license _required <<EOF
$line
EOF
    if sb_profile_selects "$PROFILE" "$profiles"; then
      printf '%s\n' "$line" >> "$SELECTED"
    fi
  done < "$MANIFEST"
  [ -s "$SELECTED" ]
}

build_selection || {
  sb_error "Profile selected no manifest entries"
  sb_status "BLOCKED — manifest/profile invalid."
  exit 1
}

check_node() {
  local version major
  if ! command -v node >/dev/null 2>&1; then
    sb_warn "Node is absent. Skills are installed, but JavaScript helpers require Node 22+."
    WARNINGS=$((WARNINGS + 1))
    return
  fi
  version="$(node --version 2>/dev/null)"
  major="$(printf '%s' "$version" | sed 's/^v//' | cut -d. -f1)"
  case "$major" in ''|*[!0-9]*)
    sb_warn "Could not parse Node version '$version'"
    WARNINGS=$((WARNINGS + 1))
    ;;
    *)
      if [ "$major" -lt 22 ]; then
        sb_warn "Node $version is older than the JavaScript helper baseline (22+)."
        WARNINGS=$((WARNINGS + 1))
      else
        sb_ok "Node $version (JavaScript helpers available)"
      fi
      ;;
  esac
}

check_skill() {
  # Manifest row fields plus harness.
  local harness="$1" name="$2" source_type="$3" repo="$4" pin_key="$5"
  local claude_folder="$6" codex_folder="$7" license="$8"
  local folder skills_dir dest receipt receipt_name receipt_harness receipt_dest
  local receipt_source receipt_ref receipt_hash receipt_backup receipt_backup_type receipt_backup_hash
  local receipt_overlay current_hash expected_source expected_ref actual_type actual_hash backup_root
  local bundled_src bundled_hash

  if [ "$harness" = "claude" ]; then folder="$claude_folder"; else folder="$codex_folder"; fi
  skills_dir="$(sb_skills_dir "$harness")"
  dest="${skills_dir}/${name}"
  receipt="$(sb_receipt_path "$SUPERBROWKY_STATE_HOME" "$harness" "$name")"
  if [ ! -f "$receipt" ] || [ -L "$receipt" ]; then
    sb_error "$harness/$name: receipt missing"
    BLOCKED=$((BLOCKED + 1))
    return
  fi
  receipt_name="$(sb_receipt_get "$receipt" name)"
  receipt_harness="$(sb_receipt_get "$receipt" harness)"
  receipt_dest="$(sb_receipt_get "$receipt" dest)"
  receipt_source="$(sb_receipt_get "$receipt" source)"
  receipt_ref="$(sb_receipt_get "$receipt" ref)"
  receipt_hash="$(sb_receipt_get "$receipt" tree_hash)"
  receipt_backup="$(sb_receipt_get "$receipt" backup)"
  receipt_backup_type="$(sb_receipt_get "$receipt" backup_type)"
  receipt_backup_hash="$(sb_receipt_get "$receipt" backup_hash)"
  receipt_overlay="$(sb_receipt_get "$receipt" overlay)"
  backup_root="${SUPERBROWKY_STATE_HOME}/backups"

  if [ "$receipt_name" != "$name" ] || [ "$receipt_harness" != "$harness" ] || [ "$receipt_dest" != "$dest" ]; then
    sb_error "$harness/$name: receipt ownership fields do not match"
    BLOCKED=$((BLOCKED + 1))
    return
  fi
  if [ ! -d "$dest" ] || [ -L "$dest" ]; then
    sb_error "$harness/$name: managed skill is missing or not a real directory"
    BLOCKED=$((BLOCKED + 1))
    return
  fi
  if ! sb_validate_no_symlinks "$dest"; then
    sb_error "$harness/$name: managed skill tree contains a prohibited symlink"
    BLOCKED=$((BLOCKED + 1))
    return
  fi
  if ! sb_validate_skill_basic "$dest" "$name"; then
    BLOCKED=$((BLOCKED + 1))
    return
  fi
  current_hash="$(sb_tree_hash "$dest")" || current_hash=""
  if [ -z "$receipt_hash" ] || [ "$current_hash" != "$receipt_hash" ]; then
    sb_error "$harness/$name: tree hash differs from its receipt"
    BLOCKED=$((BLOCKED + 1))
    return
  fi
  if [ "$source_type" = "git" ]; then
    expected_source="git:${repo}:${folder}+third-party-safety-v1"
    expected_ref="$(sb_lock_pin "$LOCK_FILE" "$pin_key")"
    if ! LC_ALL=C grep -q '^## SUPERBROWKY third-party safety contract$' "${dest}/SKILL.md"; then
      sb_error "$harness/$name: reviewed third-party safety overlay is absent"
      BLOCKED=$((BLOCKED + 1))
      return
    fi
    if [ "$receipt_overlay" != "third-party-safety-v1" ] && [ "$name" != "impeccable" ]; then
      sb_warn "$harness/$name: safety overlay provenance is missing from receipt"
      WARNINGS=$((WARNINGS + 1))
    fi
    if [ "$name" = "ai-seo" ]; then
      expected_source="${expected_source}+pinned-upstream-link-v1"
      if LC_ALL=C grep -R -n '../../tools/REGISTRY\.md' "$dest" >/dev/null 2>&1; then
        sb_error "$harness/$name: external tools registry path remains"
        BLOCKED=$((BLOCKED + 1))
        return
      fi
      if ! LC_ALL=C grep -F -q \
          "https://github.com/${repo}/blob/${receipt_ref}/tools/REGISTRY.md" \
          "${dest}/SKILL.md"; then
        sb_error "$harness/$name: exact pinned tools registry link is missing"
        BLOCKED=$((BLOCKED + 1))
        return
      fi
    fi
  else
    expected_source="bundled:${folder}"
    expected_ref=""
    bundled_src="${ROOT}/${folder}"
    if [ ! -d "$bundled_src" ] || [ -L "$bundled_src" ] ||
        ! sb_validate_no_symlinks "$bundled_src" ||
        ! sb_validate_skill_basic "$bundled_src" "$name"; then
      sb_error "$harness/$name: current bundled source is missing or unsafe"
      BLOCKED=$((BLOCKED + 1))
      return
    fi
    bundled_hash="$(sb_tree_hash "$bundled_src")" || bundled_hash=""
    if [ -z "$bundled_hash" ]; then
      sb_error "$harness/$name: current bundled source could not be hashed"
      BLOCKED=$((BLOCKED + 1))
      return
    fi
    if [ "$bundled_hash" != "$receipt_hash" ]; then
      sb_warn "$harness/$name: installed bundled copy differs from the current kit source; review a fresh apply"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
  if [ "$name" = "impeccable" ]; then
    expected_source="git:${repo}:${folder}+third-party-safety-v1+superbrowky-overlay-v1"
    if [ "$receipt_overlay" != "third-party-safety-v1+superbrowky-overlay-v1" ]; then
      sb_warn "$harness/$name: portable overlay provenance is missing from receipt"
      WARNINGS=$((WARNINGS + 1))
    fi
    if [ -e "${dest}/scripts/cleanup-deprecated.mjs" ] || [ -e "${dest}/scripts/pin.mjs" ]; then
      sb_error "$harness/$name: prohibited global cleanup/pin helper is present"
      BLOCKED=$((BLOCKED + 1))
      return
    fi
    if LC_ALL=C grep -R -n -e '\.claude/skills/impeccable' -e '\.agents/skills/impeccable' "$dest" >/dev/null 2>&1; then
      sb_error "$harness/$name: project-local helper path remains in global package"
      BLOCKED=$((BLOCKED + 1))
      return
    fi
    if ! LC_ALL=C grep -q '^## SUPERBROWKY portable contract$' "${dest}/SKILL.md"; then
      sb_error "$harness/$name: reviewed portable overlay is absent"
      BLOCKED=$((BLOCKED + 1))
      return
    fi
  fi
  if [ "$receipt_source" != "$expected_source" ]; then
    sb_warn "$harness/$name: receipt source differs from the current manifest"
    WARNINGS=$((WARNINGS + 1))
  fi
  if [ "$source_type" = "git" ] && [ -n "$expected_ref" ] && [ "$receipt_ref" != "$expected_ref" ]; then
    sb_warn "$harness/$name: installed ref $(sb_short_ref "$receipt_ref") differs from pin $(sb_short_ref "$expected_ref")"
    WARNINGS=$((WARNINGS + 1))
  fi
  [ -n "$receipt_backup" ] || receipt_backup="-"
  if [ "$receipt_backup" != "-" ]; then
    if [ -L "$backup_root" ]; then
      sb_error "$harness/$name: backups root must not be a symlink"
      BLOCKED=$((BLOCKED + 1))
      return
    fi
    if [ -z "$receipt_backup_type" ] || [ -z "$receipt_backup_hash" ] ||
        [ "$receipt_backup_type" = "-" ] || [ "$receipt_backup_hash" = "-" ]; then
      sb_error "$harness/$name: recorded backup lacks type/hash metadata"
      BLOCKED=$((BLOCKED + 1))
      return
    fi
    if ! sb_path_is_within "$receipt_backup" "$backup_root"; then
      sb_error "$harness/$name: recorded backup escapes SUPERBROWKY_STATE_HOME/backups"
      BLOCKED=$((BLOCKED + 1))
      return
    fi
    actual_type="$(sb_path_type "$receipt_backup")" || actual_type=""
    actual_hash="$(sb_path_hash "$receipt_backup" "$actual_type")" || actual_hash=""
    if [ "$actual_type" != "$receipt_backup_type" ] || [ -z "$actual_hash" ] ||
        [ "$actual_hash" != "$receipt_backup_hash" ]; then
      sb_error "$harness/$name: recorded backup type/hash mismatch"
      BLOCKED=$((BLOCKED + 1))
      return
    fi
  fi
  sb_ok "$harness/$name ($(sb_short_ref "$receipt_ref"), hash $(sb_short_ref "$current_hash"))"
}

check_inventory() {
  local harness line name profiles source_type repo pin_key claude_folder codex_folder license _required
  sb_bold "Managed skill inventory — harness=$HARNESS profile=$PROFILE"
  for harness in $(sb_harnesses "$HARNESS"); do
    while IFS= read -r line || [ -n "$line" ]; do
      IFS="$(printf '\t')" read -r name profiles source_type repo pin_key claude_folder codex_folder license _required <<EOF
$line
EOF
      check_skill "$harness" "$name" "$source_type" "$repo" "$pin_key" \
        "$claude_folder" "$codex_folder" "$license"
    done < "$SELECTED"
  done
}

extract_decision_entry() {
  # $1=Decision.md, $2=exact decision ID, $3=output file.
  # Entries are bounded by Markdown ### headings; do not let evidence from a
  # neighboring or duplicate decision satisfy the selected entry.
  awk -v wanted="$2" '
    function finish_entry() {
      if (in_entry && entry_matches > 0) selected=block
    }
    /^### / {
      finish_entry()
      in_entry=1
      entry_matches=0
      block=$0 ORS
      next
    }
    in_entry {
      block=block $0 ORS
      if ($0 == "- **Decision ID:** " wanted) {
        entry_matches++
        total_matches++
      }
    }
    END {
      finish_entry()
      if (total_matches == 1) printf "%s", selected
    }
  ' "$1" > "$3"
  [ -s "$3" ]
}

single_metadata_value() {
  # $1=file, $2=field label. Prints a value only when the field occurs exactly
  # once, so contradictory or duplicate authority metadata cannot pass.
  awk -v prefix="- **$2:** " '
    index($0, prefix) == 1 {
      count++
      value=substr($0, length(prefix) + 1)
    }
    END {
      if (count == 1) print value
      else exit 1
    }
  ' "$1"
}

reviewed_has_exact_token() {
  # Markdown punctuation may wrap evidence tokens, but prefixes/suffixes do not
  # count as the exact filename, artifact/version, or sha256 token.
  printf '%s\n' "$1" | awk -v wanted="$2" '
    {
      gsub(/[`;,(){}]/, " ")
      gsub(/\[/, " ")
      gsub(/\]/, " ")
      for (i=1; i<=NF; i++) {
        if ($i == wanted) found=1
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

is_nonplaceholder_human() {
  local value="$1" lower
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    ''|*'<'*|*'>'*|none|'n/a'|unknown|tbd|'not yet accepted'|'not yet approved')
      return 1
      ;;
  esac
  return 0
}

contains_iso_date() {
  printf '%s\n' "$1" |
    LC_ALL=C grep -E '(^|[^0-9])[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[01])([^0-9]|$)' \
      >/dev/null 2>&1
}

single_project_receipt_row() {
  # $1=project receipt, $2=exact template source. The ownership boundary is
  # valid only when exactly one well-formed four-field row claims that source.
  awk -F '\t' -v wanted="$2" '
    $1 !~ /^#/ && $4 == wanted {
      count++
      if (NF == 4) row=$1 "\t" $2 "\t" $3
      else malformed=1
    }
    END {
      if (count == 1 && !malformed) print row
      else exit 1
    }
  ' "$1"
}

check_project() {
  local file project_files adapter project_receipt row kind rel recorded_hash path
  local current_hash template_hash marker decision_ref artifact_id artifact_version authority_status
  local accepted_by accepted_on approved_by approved_on entry_heading
  local entry_file reviewed evidence_ok entry_id entry_status
  [ -n "$TARGET" ] || return
  if [ ! -d "$TARGET" ]; then
    sb_error "Project target is not a directory: $TARGET"
    BLOCKED=$((BLOCKED + 1))
    return
  fi
  sb_bold "Project harness — $(sb_redact_home "$TARGET")"
  project_files="HARNESS.md PROJECT.md PRODUCT.md DESIGN.md Decision.md Feedback.md"
  case "$HARNESS" in
    claude) project_files="${project_files} CLAUDE.md" ;;
    codex) project_files="${project_files} AGENTS.md" ;;
    both) project_files="${project_files} CLAUDE.md AGENTS.md" ;;
  esac
  project_receipt="${TARGET}/.superbrowky/project-receipt.tsv"
  if [ ! -f "$project_receipt" ] || [ -L "$project_receipt" ]; then
    sb_error "project receipt is missing"
    BLOCKED=$((BLOCKED + 1))
    return
  fi
  for file in $project_files; do
    if [ ! -f "${TARGET}/${file}" ] || [ -L "${TARGET}/${file}" ]; then
      sb_error "missing project file: $file"
      BLOCKED=$((BLOCKED + 1))
      continue
    fi
    row=""
    if ! row="$(single_project_receipt_row "$project_receipt" "template/${file}")"; then
      sb_error "$file: project receipt must contain exactly one well-formed ownership row"
      BLOCKED=$((BLOCKED + 1))
      continue
    fi
    IFS="$(printf '\t')" read -r kind rel recorded_hash <<EOF
$row
EOF
    case "$recorded_hash" in
      ''|*[!0-9a-f]*)
        sb_error "$file: invalid project receipt hash"
        BLOCKED=$((BLOCKED + 1))
        continue
        ;;
    esac
    if [ "${#recorded_hash}" -ne 64 ]; then
      sb_error "$file: invalid project receipt hash length"
      BLOCKED=$((BLOCKED + 1))
      continue
    fi
    case "$kind" in
      installed|observed)
        if [ "$rel" != "$file" ]; then
          sb_error "$file: unsafe project receipt path"
          BLOCKED=$((BLOCKED + 1))
          continue
        fi
        ;;
      candidate)
        case "$rel" in
          "$file".from-superbrowky-v4-*) ;;
          *)
            sb_error "$file: unsafe merge-candidate receipt path"
            BLOCKED=$((BLOCKED + 1))
            continue
            ;;
        esac
        template_hash="$(sb_sha256_file "${ROOT}/template/${file}")"
        if [ "$recorded_hash" != "$template_hash" ]; then
          sb_warn "$file: kit template changed after the recorded merge candidate; review a fresh plan"
          WARNINGS=$((WARNINGS + 1))
          continue
        fi
        path="${TARGET}/${rel}"
        if [ -e "$path" ] || [ -L "$path" ]; then
          sb_warn "$file: merge candidate is waiting for review"
          WARNINGS=$((WARNINGS + 1))
        else
          marker="<!-- SUPERBROWKY-MERGED: template/${file} sha256:${recorded_hash} -->"
          if LC_ALL=C grep -F -x -- "$marker" "${TARGET}/${file}" >/dev/null 2>&1; then
            sb_ok "$file (merge marker verified)"
          else
            sb_warn "$file: merge candidate is absent without an exact merge marker"
            WARNINGS=$((WARNINGS + 1))
          fi
        fi
        continue
        ;;
      *)
        sb_error "$file: unknown project receipt kind '$kind'"
        BLOCKED=$((BLOCKED + 1))
        continue
        ;;
    esac

    path="${TARGET}/${rel}"
    if [ ! -f "$path" ]; then
      sb_error "$file: recorded project file is missing"
      BLOCKED=$((BLOCKED + 1))
      continue
    fi
    current_hash="$(sb_sha256_file "$path")"
    template_hash="$(sb_sha256_file "${ROOT}/template/${file}")"
    if [ "$current_hash" = "$recorded_hash" ] && [ "$recorded_hash" != "$template_hash" ]; then
      sb_warn "$file: kit template changed since installation; review a fresh plan"
      WARNINGS=$((WARNINGS + 1))
    elif [ "$current_hash" = "$recorded_hash" ]; then
      sb_ok "$file"
    else
      sb_ok "$file (project-owned content)"
    fi
  done

  if [ -f "${TARGET}/PROJECT.md" ] &&
      LC_ALL=C grep -q 'PLACEHOLDERS PRESENT' "${TARGET}/PROJECT.md"; then
    sb_warn "PROJECT.md: repository map placeholders remain"
    WARNINGS=$((WARNINGS + 1))
  fi
  for file in PRODUCT.md DESIGN.md; do
    if [ -f "${TARGET}/${file}" ] &&
        LC_ALL=C grep -q 'PLACEHOLDERS PRESENT' "${TARGET}/${file}"; then
      sb_warn "$file: onboarding placeholders remain"
      WARNINGS=$((WARNINGS + 1))
    elif [ -f "${TARGET}/${file}" ]; then
      authority_status=""
      decision_ref=""
      artifact_id=""
      artifact_version=""
      accepted_by=""
      accepted_on=""
      if ! authority_status="$(single_metadata_value "${TARGET}/${file}" "Status")" ||
          [ "$authority_status" != "ACCEPTED" ]; then
        sb_warn "$file: authority status must occur exactly once and equal ACCEPTED"
        WARNINGS=$((WARNINGS + 1))
        continue
      fi
      if ! decision_ref="$(single_metadata_value "${TARGET}/${file}" "Decision reference")" ||
          ! artifact_id="$(single_metadata_value "${TARGET}/${file}" "Artifact ID")" ||
          ! artifact_version="$(single_metadata_value "${TARGET}/${file}" "Version")" ||
          ! accepted_by="$(single_metadata_value "${TARGET}/${file}" "Accepted by")" ||
          ! accepted_on="$(single_metadata_value "${TARGET}/${file}" "Accepted on")"; then
        sb_warn "$file: authority metadata is missing, duplicated, or contradictory"
        WARNINGS=$((WARNINGS + 1))
        continue
      fi
      if ! is_nonplaceholder_human "$accepted_by" ||
          ! contains_iso_date "$accepted_on"; then
        sb_warn "$file: Accepted by/on must identify a human and an ISO YYYY-MM-DD date"
        WARNINGS=$((WARNINGS + 1))
        continue
      fi
      case "${decision_ref}:${artifact_id}:${artifact_version}" in
        :*|*::*|*:|*'<'*|*'>'*|*' '*)
          sb_warn "$file: authority decision reference is missing or still a placeholder"
          WARNINGS=$((WARNINGS + 1))
          ;;
        *)
          entry_file="${TMP_ROOT}/decision-entry-${file}.txt"
          if ! extract_decision_entry "${TARGET}/Decision.md" "${decision_ref}" "${entry_file}"; then
            sb_warn "$file: Decision.md must contain exactly one bounded entry for ${decision_ref}"
            WARNINGS=$((WARNINGS + 1))
            continue
          fi
          entry_id=""
          entry_status=""
          approved_by=""
          approved_on=""
          entry_heading="$(sed -n '1p' "${entry_file}")"
          case "$entry_heading" in
            ''|*'<'*|*'YYYY-MM-DD'*)
              sb_warn "$file: decision ${decision_ref} heading is still a placeholder"
              WARNINGS=$((WARNINGS + 1))
              continue
              ;;
          esac
          if ! contains_iso_date "$entry_heading"; then
            sb_warn "$file: decision ${decision_ref} heading has no ISO YYYY-MM-DD date"
            WARNINGS=$((WARNINGS + 1))
            continue
          fi
          if ! entry_id="$(single_metadata_value "${entry_file}" "Decision ID")" ||
              [ "$entry_id" != "$decision_ref" ] ||
              ! entry_status="$(single_metadata_value "${entry_file}" "Status")" ||
              [ "$entry_status" != "ACCEPTED" ] ||
              ! approved_by="$(single_metadata_value "${entry_file}" "Approved by")" ||
              ! approved_on="$(single_metadata_value "${entry_file}" "Approved on")"; then
            sb_warn "$file: decision ${decision_ref} metadata is ambiguous or not ACCEPTED"
            WARNINGS=$((WARNINGS + 1))
            continue
          fi
          if ! is_nonplaceholder_human "$approved_by" ||
              ! contains_iso_date "$approved_on"; then
            sb_warn "$file: decision ${decision_ref} Approved by/on lacks a human or ISO date"
            WARNINGS=$((WARNINGS + 1))
            continue
          fi
          current_hash="$(sb_sha256_file "${TARGET}/${file}")"
          reviewed=""
          if ! reviewed="$(single_metadata_value "${entry_file}" "Reviewed artifacts")"; then
            sb_warn "$file: decision ${decision_ref} has ambiguous reviewed-artifact evidence"
            WARNINGS=$((WARNINGS + 1))
            continue
          fi
          evidence_ok=1
          reviewed_has_exact_token "$reviewed" "$file" || evidence_ok=0
          reviewed_has_exact_token "$reviewed" "$artifact_id/$artifact_version" || evidence_ok=0
          reviewed_has_exact_token "$reviewed" "sha256:$current_hash" || evidence_ok=0
          if [ "$evidence_ok" -ne 1 ]; then
            sb_warn "$file: decision ${decision_ref} lacks exact current artifact ID/version/hash evidence"
            WARNINGS=$((WARNINGS + 1))
          fi
          ;;
      esac
    fi
  done
  for adapter in CLAUDE.md AGENTS.md; do
    case "$HARNESS:$adapter" in
      claude:AGENTS.md|codex:CLAUDE.md) continue ;;
    esac
    [ -f "${TARGET}/${adapter}" ] || continue
    if LC_ALL=C grep -q '<framework / language>' "${TARGET}/${adapter}"; then
      sb_warn "$adapter: adapter placeholders remain"
      WARNINGS=$((WARNINGS + 1))
    fi
    if ! LC_ALL=C grep -q 'HARNESS.md' "${TARGET}/${adapter}"; then
      sb_warn "$adapter does not route to canonical HARNESS.md"
      WARNINGS=$((WARNINGS + 1))
    fi
  done
}

check_inventory
check_node
check_project

printf '\n'
if [ "$BLOCKED" -gt 0 ]; then
  sb_status "BLOCKED — $BLOCKED required check(s) failed; $WARNINGS warning(s)."
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  sb_status "PARTIAL — required inventory is intact, with $WARNINGS warning(s)."
  exit 2
else
  sb_status "READY — selected skills, receipts, hashes, and requested project files are valid."
  exit 0
fi

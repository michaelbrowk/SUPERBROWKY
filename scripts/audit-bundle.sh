#!/usr/bin/env bash
# Explicit, allowlisted audit summary. It never captures chat or environment
# dumps and redacts HOME from paths.
# Markdown table/backtick strings are literal printf formats.
# shellcheck disable=SC2016

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
HARNESS="auto"
PROFILE="core"
TARGET=""
OUTPUT=""
APPLY=0

audit_cell() {
  # Keep Markdown valid even if a local path or tampered receipt contains
  # control/markup characters. Do not echo arbitrary multi-line metadata.
  printf '%s' "$1" \
    | LC_ALL=C tr '\r\n\t' '   ' \
    | sed 's/[|`<>]/_/g' \
    | cut -c1-200
}

usage() {
  cat <<'EOF'
Usage:
  bash scripts/audit-bundle.sh [options]

Options:
  --apply                         write the summary; otherwise show the plan
  --harness auto|claude|codex|both
  --profile core|web-launch|growth|full
  --target /path/to/project
  --output /path/to/summary.md
  -h, --help

The default is a read-only plan. --apply explicitly creates one Markdown summary.
It records only allowlisted health metadata, never chat, tokens, or credentials.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
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
    --output)
      [ "$#" -ge 2 ] || { sb_error "--output needs a path"; exit 2; }
      OUTPUT="$2"
      shift
      ;;
    --output=*) OUTPUT="${1#--output=}" ;;
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
  if ! HARNESS="$(sb_detect_harness)"; then
    sb_error "Could not detect a harness; pass --harness explicitly."
    exit 1
  fi
fi
if [ ! -f "$MANIFEST" ]; then
  sb_error "Missing manifest: $MANIFEST"
  exit 1
fi
if [ -n "$TARGET" ] && [ ! -d "$TARGET" ]; then
  sb_error "Project target is not a directory: $TARGET"
  exit 1
fi

timestamp_file="$(date -u '+%Y%m%dT%H%M%SZ')"
timestamp_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if [ -z "$OUTPUT" ]; then
  if [ -n "$TARGET" ]; then
    OUTPUT="${TARGET}/AuditBundles/SUPERBROWKY-Audit-${timestamp_file}.md"
  else
    OUTPUT="${PWD}/AuditBundles/SUPERBROWKY-Audit-${timestamp_file}.md"
  fi
fi
case "$OUTPUT" in
  *.md) ;;
  *) sb_error "--output must end in .md"; exit 2 ;;
esac
if [ -e "$OUTPUT" ] || [ -L "$OUTPUT" ]; then
  sb_error "Refusing to overwrite existing audit summary: $(sb_redact_home "$OUTPUT")"
  exit 1
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/superbrowky-audit.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
SELECTED="${TMP_ROOT}/selected.tsv"
DOCTOR_OUT="${TMP_ROOT}/doctor.txt"
OUT_PARTIAL="${TMP_ROOT}/summary.md"

first=1
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$first" -eq 1 ]; then first=0; continue; fi
  [ -n "$line" ] || continue
  IFS="$(printf '\t')" read -r name profiles _source_type _repo _pin_key _claude_folder _codex_folder _license _required <<EOF
$line
EOF
  if sb_profile_selects "$PROFILE" "$profiles"; then
    printf '%s\n' "$line" >> "$SELECTED"
  fi
done < "$MANIFEST"

if [ -n "$TARGET" ]; then
  bash "${SCRIPT_DIR}/doctor.sh" --harness "$HARNESS" --profile "$PROFILE" --target "$TARGET" > "$DOCTOR_OUT" 2>&1
  doctor_rc=$?
else
  bash "${SCRIPT_DIR}/doctor.sh" --harness "$HARNESS" --profile "$PROFILE" > "$DOCTOR_OUT" 2>&1
  doctor_rc=$?
fi
doctor_status="$(awk '/^STATUS: / { line=$0 } END { print line }' "$DOCTOR_OUT")"
[ -n "$doctor_status" ] || doctor_status="STATUS: BLOCKED — doctor did not return a status."

if [ "$APPLY" -eq 0 ]; then
  sb_bold "SUPERBROWKY audit summary plan"
  printf '  Output:  %s\n' "$(sb_redact_home "$OUTPUT")"
  printf '  Harness: %s\n' "$HARNESS"
  printf '  Profile: %s\n' "$PROFILE"
  [ -n "$TARGET" ] && printf '  Project: %s\n' "$(sb_redact_home "$TARGET")"
  printf '  Doctor:  %s\n' "${doctor_status#STATUS: }"
  printf '\nNo summary file was written.\n'
  sb_status "READY — plan only; rerun with --apply to create the Markdown summary."
  exit 0
fi

kit_ref="unknown"
if command -v git >/dev/null 2>&1; then
  kit_ref="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
fi

{
  printf '# SUPERBROWKY Audit Bundle\n\n'
  printf -- '- Generated: `%s`\n' "$timestamp_iso"
  printf -- '- Kit ref: `%s`\n' "$(sb_short_ref "$kit_ref")"
  printf -- '- Harness: `%s`\n' "$HARNESS"
  printf -- '- Profile: `%s`\n' "$PROFILE"
  printf -- '- Doctor: **%s**\n' "${doctor_status#STATUS: }"
  if [ -n "$TARGET" ]; then
    printf -- '- Project: `%s`\n' "$(audit_cell "$(sb_redact_home "$TARGET")")"
  fi
  printf '\nThis file contains allowlisted health metadata only. It does not contain chat, prompts, environment dumps, tokens, cookies, or credentials.\n\n'
  printf '## Managed skill inventory\n\n'
  printf '| Harness | Skill | Receipt | Live tree | Source | Ref | Tree hash | Backup | Backup hash |\n'
  printf '|---|---|---|---|---|---|---|---|---|\n'
  for harness in $(sb_harnesses "$HARNESS"); do
    while IFS= read -r line || [ -n "$line" ]; do
      IFS="$(printf '\t')" read -r name profiles _source_type _repo _pin_key _claude_folder _codex_folder _license _required <<EOF
$line
EOF
      dest="$(sb_skills_dir "$harness")/${name}"
      receipt="$(sb_receipt_path "$SUPERBROWKY_STATE_HOME" "$harness" "$name")"
      receipt_state="missing"
      live_state="missing"
      source="-"
      ref="-"
      expected_hash="-"
      backup="-"
      backup_hash="-"
      if [ -f "$receipt" ]; then
        receipt_state="present"
        source="$(sb_receipt_get "$receipt" source)"
        ref="$(sb_receipt_get "$receipt" ref)"
        if ! printf '%s\n' "$source" | LC_ALL=C grep -Eq \
          '^(bundled:[A-Za-z0-9._/-]+|git:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+:[A-Za-z0-9._/-]+)(\+[A-Za-z0-9_.+-]+)*$'; then
          source="invalid"
        fi
        if ! printf '%s\n' "$ref" | LC_ALL=C grep -Eq '^([0-9a-fA-F]{40,64}|local)$'; then
          ref="invalid"
        fi
        expected_hash="$(sb_receipt_get "$receipt" tree_hash)"
        if ! printf '%s\n' "$expected_hash" | LC_ALL=C grep -Eq '^[0-9a-f]{64}$'; then
          expected_hash="invalid"
        fi
        receipt_backup="$(sb_receipt_get "$receipt" backup)"
        receipt_backup_hash="$(sb_receipt_get "$receipt" backup_hash)"
        if [ -n "$receipt_backup" ] && [ "$receipt_backup" != "-" ]; then
          if sb_path_is_within "$receipt_backup" "${SUPERBROWKY_STATE_HOME}/backups"; then
            backup="$(audit_cell "$(sb_redact_home "$receipt_backup")")"
          else
            backup="invalid"
          fi
          if [ "$backup" != "invalid" ] &&
              printf '%s\n' "$receipt_backup_hash" | LC_ALL=C grep -Eq '^[0-9a-f]{64}$'; then
            backup_hash="$receipt_backup_hash"
          else
            backup_hash="invalid"
          fi
        fi
        receipt_dest="$(sb_receipt_get "$receipt" dest)"
        if [ "$receipt_dest" != "$dest" ]; then
          live_state="ownership mismatch"
        elif [ -d "$dest" ] && [ ! -L "$dest" ]; then
          current_hash="$(sb_tree_hash "$dest" 2>/dev/null || printf '')"
          if [ -n "$expected_hash" ] && [ "$current_hash" = "$expected_hash" ]; then
            live_state="verified"
          else
            live_state="drifted"
          fi
        fi
      elif [ -e "$dest" ] || [ -L "$dest" ]; then
        live_state="unmanaged"
      fi
      printf '| `%s` | `%s` | %s | %s | `%s` | `%s` | `%s` | `%s` | `%s` |\n' \
        "$harness" "$name" "$receipt_state" "$live_state" "$source" \
        "$(sb_short_ref "$ref")" "$expected_hash" "$backup" "$backup_hash"
    done < "$SELECTED"
  done

  if [ -n "$TARGET" ]; then
    printf '\n## Project receipt\n\n'
    project_receipt="${TARGET}/.superbrowky/project-receipt.tsv"
    if [ -f "$project_receipt" ] && [ ! -L "$project_receipt" ]; then
      printf '| Kind | Relative path | SHA-256 | Source |\n'
      printf '|---|---|---|---|\n'
      while IFS="$(printf '\t')" read -r receipt_kind receipt_rel receipt_hash receipt_source; do
        case "$receipt_kind" in ""|\#*) continue ;; esac
        if printf '%s\n' "$receipt_hash" | LC_ALL=C grep -Eq '^[0-9a-f]{64}$'; then
          printf '| `%s` | `%s` | `%s` | `%s` |\n' \
            "$(audit_cell "$receipt_kind")" "$(audit_cell "$receipt_rel")" \
            "$receipt_hash" "$(audit_cell "$receipt_source")"
        else
          printf '| invalid | `invalid` | `invalid` | `invalid project receipt metadata` |\n'
        fi
      done < "$project_receipt"
    else
      printf 'Project receipt is missing.\n'
    fi

    printf '\n## Project files\n\n'
    printf '| File | Present | Placeholder markers |\n'
    printf '|---|---:|---:|\n'
    project_files="HARNESS.md PROJECT.md PRODUCT.md DESIGN.md Decision.md Feedback.md"
    case "$HARNESS" in
      claude) project_files="${project_files} CLAUDE.md" ;;
      codex) project_files="${project_files} AGENTS.md" ;;
      both) project_files="${project_files} CLAUDE.md AGENTS.md" ;;
    esac
    for file in $project_files; do
      if [ -f "${TARGET}/${file}" ]; then
        present="yes"
        placeholder_count="$(LC_ALL=C grep -E -c '<[^>]+>' "${TARGET}/${file}" 2>/dev/null || true)"
        [ -n "$placeholder_count" ] || placeholder_count=0
      else
        present="no"
        placeholder_count="-"
      fi
      printf '| `%s` | %s | %s |\n' "$file" "$present" "$placeholder_count"
    done
  fi

  printf '\n## Interpretation\n\n'
  case "$doctor_status" in
    "STATUS: READY"*) printf 'The selected installation and requested project harness passed all checks.\n' ;;
    "STATUS: PARTIAL"*) printf 'The required installation is intact, but the doctor found warnings that should be reviewed.\n' ;;
    *) printf 'The doctor found a blocking mismatch or missing required item. Do not treat this bundle as a ready handoff.\n' ;;
  esac
} > "$OUT_PARTIAL"

mkdir -p "$(dirname "$OUTPUT")" || exit 1
if ! mv "$OUT_PARTIAL" "$OUTPUT"; then
  sb_error "Could not write audit summary"
  exit 1
fi

sb_ok "Audit summary: $(sb_redact_home "$OUTPUT")"
printf '%s\n' "$doctor_status"
exit "$doctor_rc"

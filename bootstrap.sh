#!/usr/bin/env bash
#
# SUPERBROWKY v4 — safe project bootstrap for Claude Code and Codex.
#
# The default invocation is a read-only plan. Add --apply only after the user
# has reviewed the harness, profile, destinations, conflicts, and remote
# sources.

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="${HERE}/template"
KIT_VERSION="4"

ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1" >&2; }
fail() { printf '\033[0;31m✗ %s\033[0m\n' "$1" >&2; }
bold() { printf '\033[1m%s\033[0m\n' "$1"; }

usage() {
  cat <<'EOS'
Usage:
  bash bootstrap.sh <project> [--harness auto|claude|codex|both]
                    [--profile core|web-launch|growth|full] [--apply]

Modes:
  (default)        read-only plan; no downloads and no writes
  --apply          apply the reviewed plan
  --check          run doctor and print READY, PARTIAL, or BLOCKED
  --audit-bundle   preview a shareable local installation audit
  --audit-bundle --apply
                   write the audit after reviewing its destination
  --uninstall      plan removal of project harness files
  --uninstall --apply
                   remove only unchanged project files recorded as managed

Compatibility:
  --dry-run        alias for the default read-only plan

Global skills are removed separately:
  bash install-skills.sh --uninstall --harness <...> --apply
EOS
}

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    fail "shasum or sha256sum is required"
    return 1
  fi
}

contains_harness() {
  case "$1" in
    both) return 0 ;;
    "$2") return 0 ;;
    *) return 1 ;;
  esac
}

detect_harness() {
  local target="$1" has_claude=0 has_codex=0

  [ -f "${target}/CLAUDE.md" ] && has_claude=1
  [ -f "${target}/AGENTS.md" ] && has_codex=1

  if command -v claude >/dev/null 2>&1 || [ -d "${CLAUDE_HOME:-${HOME}/.claude}" ]; then
    has_claude=1
  fi
  if command -v codex >/dev/null 2>&1 || [ -d "${CODEX_HOME:-${HOME}/.codex}" ]; then
    has_codex=1
  fi

  if [ "${has_claude}" -eq 1 ] && [ "${has_codex}" -eq 1 ]; then
    printf 'both'
  elif [ "${has_claude}" -eq 1 ]; then
    printf 'claude'
  elif [ "${has_codex}" -eq 1 ]; then
    printf 'codex'
  else
    return 1
  fi
}

template_names() {
  printf '%s\n' HARNESS.md PROJECT.md PRODUCT.md DESIGN.md Decision.md Feedback.md
  contains_harness "${HARNESS}" claude && printf '%s\n' CLAUDE.md
  contains_harness "${HARNESS}" codex && printf '%s\n' AGENTS.md
}

candidate_path() {
  local target="$1" name="$2" digest="$3"
  printf '%s/%s.from-superbrowky-v%s-%s' \
    "${target}" "${name}" "${KIT_VERSION}" "$(printf '%s' "${digest}" | cut -c1-12)"
}

plan_templates() {
  local name src dst digest candidate
  bold "Project harness"
  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    src="${TEMPLATE_DIR}/${name}"
    dst="${TARGET}/${name}"
    if [ ! -f "${src}" ]; then
      fail "missing kit template: ${src}"
      return 1
    fi
    digest="$(hash_file "${src}")"
    if [ ! -e "${dst}" ] && [ ! -L "${dst}" ]; then
      printf '  INSTALL    %s\n' "${name}"
    elif [ -f "${dst}" ] && [ "$(hash_file "${dst}")" = "${digest}" ]; then
      printf '  CURRENT    %s\n' "${name}"
    else
      candidate="$(candidate_path "${TARGET}" "${name}" "${digest}")"
      printf '  MERGE      %s exists; write %s\n' "${name}" "$(basename "${candidate}")"
    fi
  done <<EOF
$(template_names)
EOF
}

previous_kind() {
  local rel="$1" source="$2" receipt="${TARGET}/.superbrowky/project-receipt.tsv"
  [ -f "${receipt}" ] || return 0
  awk -F '\t' -v wanted_rel="${rel}" -v wanted_source="${source}" '
    $1 !~ /^#/ && $2 == wanted_rel && $4 == wanted_source {
      count++
      if (NF == 4) kind=$1
      else malformed=1
    }
    END {
      if (count == 0) exit
      if (count == 1 && !malformed) print kind
      else exit 1
    }
  ' "${receipt}"
}

template_is_selected() {
  case "$1" in
    CLAUDE.md) contains_harness "${HARNESS}" claude ;;
    AGENTS.md) contains_harness "${HARNESS}" codex ;;
    *) return 0 ;;
  esac
}

preserve_unselected_adapter_rows() {
  local old_receipt="$1" new_receipt="$2" name row kind rel digest source extra
  [ -f "${old_receipt}" ] && [ ! -L "${old_receipt}" ] || return 0
  for name in CLAUDE.md AGENTS.md; do
    if template_is_selected "${name}"; then
      continue
    fi
    row=""
    if ! row="$(awk -F '\t' -v wanted="template/${name}" '
      $1 !~ /^#/ && $4 == wanted {
        count++
        if (NF == 4) row=$0
        else malformed=1
      }
      END {
        if (count == 0) exit
        if (count == 1 && !malformed) print row
        else exit 1
      }
    ' "${old_receipt}")"; then
      fail "${name}: ambiguous preserved adapter receipt rows"
      return 1
    fi
    [ -n "${row}" ] || continue
    IFS="$(printf '\t')" read -r kind rel digest source extra <<EOF
${row}
EOF
    if [ -n "${extra:-}" ] || [ "${source}" != "template/${name}" ]; then
      fail "${name}: malformed preserved adapter receipt row"
      return 1
    fi
    case "${digest}" in ''|*[!0-9a-f]*) fail "${name}: unsafe preserved adapter hash"; return 1 ;; esac
    [ "${#digest}" -eq 64 ] || { fail "${name}: unsafe preserved adapter hash"; return 1; }
    case "${kind}" in
      installed|observed)
        [ "${rel}" = "${name}" ] || {
          fail "${name}: unsafe preserved adapter path"
          return 1
        }
        ;;
      candidate)
        case "${rel}" in
          "${name}".from-superbrowky-v4-*) ;;
          *) fail "${name}: unsafe preserved candidate path"; return 1 ;;
        esac
        ;;
      *)
        fail "${name}: unsafe preserved adapter kind"
        return 1
        ;;
    esac
    printf '%s\n' "${row}" >> "${new_receipt}" || return 1
  done
}

rollback_created_templates() {
  local created_list="$1" path digest current
  [ -f "${created_list}" ] || return 0
  while IFS="$(printf '\t')" read -r path digest; do
    case "${path}" in
      "${TARGET}"/*) ;;
      *) warn "rollback preserved unsafe recorded path: ${path}"; continue ;;
    esac
    [ -e "${path}" ] || [ -L "${path}" ] || continue
    if [ -f "${path}" ] && [ ! -L "${path}" ]; then
      current="$(hash_file "${path}")" || current=""
      if [ -n "${current}" ] && [ "${current}" = "${digest}" ]; then
        rm -f "${path}" || warn "rollback could not remove ${path}"
      else
        warn "rollback preserved changed file: ${path}"
      fi
    else
      warn "rollback preserved non-file path: ${path}"
    fi
  done < "${created_list}"
}

abort_template_install() {
  local stage_dir="$1" receipt_tmp="$2" created_list="$3" state_dir="$4" state_created="$5"
  rollback_created_templates "${created_list}"
  [ -n "${receipt_tmp}" ] && rm -f "${receipt_tmp}" 2>/dev/null || true
  rm -rf "${stage_dir}"
  if [ "${state_created}" -eq 1 ]; then
    rmdir "${state_dir}" 2>/dev/null || true
  fi
}

install_templates() {
  local state_dir receipt receipt_tmp name src dst digest candidate rel kind old_kind partial
  local stage_dir created_list state_created=0

  stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/superbrowky-templates.XXXXXX")" || return 1
  created_list="${stage_dir}/created.tsv"
  : > "${created_list}" || { rm -rf "${stage_dir}"; return 1; }
  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    src="${TEMPLATE_DIR}/${name}"
    if [ ! -f "${src}" ] || [ -L "${src}" ]; then
      fail "missing or unsafe kit template: ${src}"
      abort_template_install "${stage_dir}" "" "${created_list}" "" 0
      return 1
    fi
    if ! cp "${src}" "${stage_dir}/${name}"; then
      abort_template_install "${stage_dir}" "" "${created_list}" "" 0
      return 1
    fi
    [ "$(hash_file "${src}")" = "$(hash_file "${stage_dir}/${name}")" ] || {
      fail "staging verification failed for ${name}"
      abort_template_install "${stage_dir}" "" "${created_list}" "" 0
      return 1
    }
  done <<EOF
$(template_names)
EOF

  state_dir="${TARGET}/.superbrowky"
  [ -d "${state_dir}" ] || state_created=1
  if ! mkdir -p "${state_dir}" || [ -L "${state_dir}" ] || [ ! -d "${state_dir}" ]; then
    fail "unsafe or unwritable project state directory: ${state_dir}"
    abort_template_install "${stage_dir}" "" "${created_list}" "${state_dir}" "${state_created}"
    return 1
  fi
  receipt="${state_dir}/project-receipt.tsv"
  if [ -L "${receipt}" ] || { [ -e "${receipt}" ] && [ ! -f "${receipt}" ]; }; then
    fail "unsafe project receipt path: ${receipt}"
    abort_template_install "${stage_dir}" "" "${created_list}" "${state_dir}" "${state_created}"
    return 1
  fi
  receipt_tmp="${state_dir}/project-receipt.tsv.partial.$$"
  if [ -e "${receipt_tmp}" ] || [ -L "${receipt_tmp}" ]; then
    fail "temporary project receipt already exists"
    abort_template_install "${stage_dir}" "" "${created_list}" "${state_dir}" "${state_created}"
    return 1
  fi
  if ! {
    printf '# SUPERBROWKY project receipt v%s\n' "${KIT_VERSION}"
    printf '# harness=%s\n' "${HARNESS}"
    printf '# profile=%s\n' "${PROFILE}"
    printf '# kind\trelative_path\tsha256\tsource\n'
  } > "${receipt_tmp}"; then
    abort_template_install "${stage_dir}" "${receipt_tmp}" "${created_list}" "${state_dir}" "${state_created}"
    return 1
  fi

  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    src="${stage_dir}/${name}"
    dst="${TARGET}/${name}"
    digest="$(hash_file "${src}")"
    rel="${name}"
    kind=""

    if [ ! -e "${dst}" ] && [ ! -L "${dst}" ]; then
      partial="${dst}.superbrowky-partial.$$"
      if [ -e "${partial}" ] || [ -L "${partial}" ] ||
          ! cp "${src}" "${partial}" ||
          [ "$(hash_file "${partial}")" != "${digest}" ] ||
          [ -e "${dst}" ] || [ -L "${dst}" ] ||
          ! mv "${partial}" "${dst}" ||
          [ ! -f "${dst}" ] || [ -L "${dst}" ] ||
          [ "$(hash_file "${dst}")" != "${digest}" ]; then
        rm -f "${partial}" 2>/dev/null || true
        fail "transactional install failed for ${name}"
        abort_template_install "${stage_dir}" "${receipt_tmp}" "${created_list}" "${state_dir}" "${state_created}"
        return 1
      fi
      printf '%s\t%s\n' "${dst}" "${digest}" >> "${created_list}" || {
        abort_template_install "${stage_dir}" "${receipt_tmp}" "${created_list}" "${state_dir}" "${state_created}"
        return 1
      }
      kind="installed"
      ok "installed ${name}"
    elif [ -f "${dst}" ] && [ ! -L "${dst}" ] && [ "$(hash_file "${dst}")" = "${digest}" ]; then
      old_kind=""
      if ! old_kind="$(previous_kind "${rel}" "template/${name}")"; then
        fail "${name}: ambiguous previous ownership rows"
        abort_template_install "${stage_dir}" "${receipt_tmp}" "${created_list}" "${state_dir}" "${state_created}"
        return 1
      fi
      case "${old_kind}" in installed) kind="installed" ;; *) kind="observed" ;; esac
      ok "${name} already current"
    else
      candidate="$(candidate_path "${TARGET}" "${name}" "${digest}")"
      if { [ -e "${candidate}" ] || [ -L "${candidate}" ]; } && {
        [ ! -f "${candidate}" ] || [ "$(hash_file "${candidate}")" != "${digest}" ]
      }; then
        candidate="${candidate}-$(date +%Y%m%d%H%M%S)-$$"
      fi
      if [ ! -e "${candidate}" ] && [ ! -L "${candidate}" ]; then
        partial="${candidate}.superbrowky-partial.$$"
        if [ -e "${partial}" ] || [ -L "${partial}" ] ||
            ! cp "${src}" "${partial}" ||
            [ "$(hash_file "${partial}")" != "${digest}" ] ||
            [ -e "${candidate}" ] || [ -L "${candidate}" ] ||
            ! mv "${partial}" "${candidate}" ||
            [ ! -f "${candidate}" ] || [ -L "${candidate}" ] ||
            [ "$(hash_file "${candidate}")" != "${digest}" ]; then
          rm -f "${partial}" 2>/dev/null || true
          fail "transactional candidate install failed for ${name}"
          abort_template_install "${stage_dir}" "${receipt_tmp}" "${created_list}" "${state_dir}" "${state_created}"
          return 1
        fi
        printf '%s\t%s\n' "${candidate}" "${digest}" >> "${created_list}" || {
          abort_template_install "${stage_dir}" "${receipt_tmp}" "${created_list}" "${state_dir}" "${state_created}"
          return 1
        }
        warn "${name} preserved; merge candidate: $(basename "${candidate}")"
      else
        ok "merge candidate already current: $(basename "${candidate}")"
      fi
      rel="$(basename "${candidate}")"
      old_kind=""
      if ! old_kind="$(previous_kind "${rel}" "template/${name}")"; then
        fail "${name}: ambiguous previous candidate ownership rows"
        abort_template_install "${stage_dir}" "${receipt_tmp}" "${created_list}" "${state_dir}" "${state_created}"
        return 1
      fi
      case "${old_kind}" in candidate) kind="candidate" ;; *) kind="candidate" ;; esac
    fi

    printf '%s\t%s\t%s\t%s\n' "${kind}" "${rel}" "${digest}" "template/${name}" \
      >> "${receipt_tmp}" || {
        abort_template_install "${stage_dir}" "${receipt_tmp}" "${created_list}" "${state_dir}" "${state_created}"
        return 1
      }
  done <<EOF
$(template_names)
EOF

  if ! preserve_unselected_adapter_rows "${receipt}" "${receipt_tmp}"; then
    abort_template_install "${stage_dir}" "${receipt_tmp}" "${created_list}" "${state_dir}" "${state_created}"
    return 1
  fi
  if ! mv "${receipt_tmp}" "${receipt}" ||
      [ ! -f "${receipt}" ] || [ -L "${receipt}" ]; then
    fail "project receipt install failed; rolling back newly created templates"
    abort_template_install "${stage_dir}" "${receipt_tmp}" "${created_list}" "${state_dir}" "${state_created}"
    return 1
  fi
  rm -rf "${stage_dir}"
  return 0
}

uninstall_project() {
  local receipt="${TARGET}/.superbrowky/project-receipt.tsv"
  local kind rel digest source path current removing action
  local failures=0 actions
  if [ ! -f "${receipt}" ] || [ -L "${receipt}" ]; then
    fail "BLOCKED: no project receipt; refusing to remove unowned files"
    return 1
  fi

  bold "Project harness removal ${APPLY_TEXT}"
  actions="$(mktemp "${TMPDIR:-/tmp}/superbrowky-project-uninstall.XXXXXX")" || return 1

  # Validate every receipt-owned path before changing any project file. One
  # known drift blocks the entire apply rather than partially uninstalling the
  # otherwise-clean files that happened to appear earlier in the receipt.
  while IFS="$(printf '\t')" read -r kind rel digest source; do
    case "${kind}" in \#*|'') continue ;; esac
    case "${rel}" in
      /*|../*|*/../*|*'/..') fail "unsafe receipt path: ${rel}"; failures=$((failures + 1)); continue ;;
    esac
    case "${digest}" in
      ''|*[!0-9a-f]*)
        fail "unsafe receipt hash: ${rel}"
        failures=$((failures + 1))
        continue
        ;;
    esac
    if [ "${#digest}" -ne 64 ]; then
      fail "unsafe receipt hash length: ${rel}"
      failures=$((failures + 1))
      continue
    fi
    case "${source}" in
      template/*.md) ;;
      *)
        fail "unsafe receipt source: ${source}"
        failures=$((failures + 1))
        continue
        ;;
    esac
    path="${TARGET}/${rel}"
    case "${kind}" in
      installed|candidate)
        if [ ! -e "${path}" ] && [ ! -L "${path}" ]; then
          printf 'ABSENT\t%s\t%s\t%s\n' "${rel}" "${digest}" "${path}" >> "${actions}"
          continue
        fi
        if [ ! -f "${path}" ]; then
          warn "preserved non-file path: ${rel}"
          failures=$((failures + 1))
          continue
        fi
        current="$(hash_file "${path}")"
        if [ "${current}" != "${digest}" ]; then
          warn "preserved modified file: ${rel}"
          failures=$((failures + 1))
        else
          printf 'REMOVE\t%s\t%s\t%s\n' "${rel}" "${digest}" "${path}" >> "${actions}"
        fi
        ;;
      observed)
        printf 'PRESERVE\t%s\t%s\t%s\n' "${rel}" "${digest}" "${path}" >> "${actions}"
        ;;
      *)
        warn "unknown receipt entry ${kind}: ${rel}"
        failures=$((failures + 1))
        ;;
    esac
  done < "${receipt}"

  if [ "${failures}" -gt 0 ]; then
    rm -f "${actions}"
    fail "BLOCKED: ${failures} modified or unsafe file(s) were preserved; no project files changed"
    return 1
  fi

  if [ "${APPLY}" -eq 0 ]; then
    while IFS="$(printf '\t')" read -r action rel digest path; do
      : "${digest}" "${path}"
      case "${action}" in
        ABSENT) printf '  ABSENT     %s\n' "${rel}" ;;
        REMOVE) printf '  REMOVE     %s\n' "${rel}" ;;
        PRESERVE) printf '  PRESERVE   %s (pre-existing)\n' "${rel}" ;;
      esac
    done < "${actions}"
    rm -f "${actions}"
    bold "PLAN ONLY — re-run with --apply to remove the listed unchanged files"
    return 0
  fi

  while IFS="$(printf '\t')" read -r action rel digest path; do
    case "${action}" in
      ABSENT|PRESERVE) continue ;;
      REMOVE)
        removing="${path}.superbrowky-removing.$$"
        if [ -e "${removing}" ] || [ -L "${removing}" ]; then
          warn "temporary removal path exists: ${rel}"
          failures=$((failures + 1))
          continue
        fi
        if ! mv "${path}" "${removing}"; then
          warn "could not isolate project file: ${rel}"
          failures=$((failures + 1))
          continue
        fi
        if [ ! -f "${removing}" ] || [ -L "${removing}" ] ||
            [ "$(hash_file "${removing}")" != "${digest}" ]; then
          warn "project file changed after preflight: ${rel}"
          if [ ! -e "${path}" ] && [ ! -L "${path}" ]; then
            mv "${removing}" "${path}" 2>/dev/null || true
          fi
          failures=$((failures + 1))
          continue
        fi
        if [ "$(hash_file "${removing}")" != "${digest}" ] ||
            ! rm -f "${removing}"; then
          warn "project file changed before deletion: ${rel}"
          if [ -e "${removing}" ] || [ -L "${removing}" ]; then
            if [ ! -e "${path}" ] && [ ! -L "${path}" ]; then
              mv "${removing}" "${path}" 2>/dev/null || true
            fi
          fi
          failures=$((failures + 1))
          continue
        fi
        ok "removed ${rel}"
        ;;
    esac
  done < "${actions}"
  rm -f "${actions}"

  if [ "${failures}" -gt 0 ]; then
    fail "PARTIAL: ${failures} path(s) changed during apply and were preserved"
    return 1
  fi
  rm "${receipt}"
  rmdir "${TARGET}/.superbrowky" 2>/dev/null || true
  ok "project harness removal complete; global skills were not touched"
}

TARGET=""
HARNESS="auto"
PROFILE="core"
MODE="install"
MODE_SEEN=0
APPLY=0
APPLY_SEEN=0
DRY_SEEN=0

select_mode() {
  if [ "${MODE_SEEN}" -eq 1 ]; then
    fail "choose only one of --plan/--dry-run, --check, --audit-bundle, or --uninstall"
    exit 1
  fi
  MODE="$1"
  MODE_SEEN=1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --harness)
      [ "$#" -ge 2 ] || { fail "--harness needs a value"; exit 1; }
      HARNESS="$2"; shift 2 ;;
    --profile)
      [ "$#" -ge 2 ] || { fail "--profile needs a value"; exit 1; }
      PROFILE="$2"; shift 2 ;;
    --apply) APPLY=1; APPLY_SEEN=1; shift ;;
    --plan) select_mode "plan"; DRY_SEEN=1; shift ;;
    --dry-run) select_mode "plan"; DRY_SEEN=1; shift ;;
    --check) select_mode "check"; shift ;;
    --audit-bundle) select_mode "audit"; shift ;;
    --uninstall) select_mode "uninstall"; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) fail "unknown flag: $1"; usage; exit 1 ;;
    *)
      if [ -z "${TARGET}" ]; then TARGET="$1"; shift
      else fail "unexpected argument: $1"; usage; exit 1
      fi
      ;;
  esac
done

if [ "${APPLY_SEEN}" -eq 1 ] && [ "${DRY_SEEN}" -eq 1 ]; then
  fail "--apply conflicts with explicit --plan/--dry-run"
  exit 1
fi
if [ "${MODE}" = "check" ] && [ "${APPLY}" -eq 1 ]; then
  fail "--check is read-only; remove --apply"
  exit 1
fi

[ -n "${TARGET}" ] || { usage; exit 1; }
[ -d "${TARGET}" ] || { fail "not a directory: ${TARGET}"; exit 1; }
TARGET="$(cd "${TARGET}" && pwd)"

case "${HARNESS}" in auto|claude|codex|both) ;; *) fail "invalid harness: ${HARNESS}"; exit 1 ;; esac
case "${PROFILE}" in core|web-launch|growth|full) ;; *) fail "invalid profile: ${PROFILE}"; exit 1 ;; esac

if [ "${HARNESS}" = "auto" ]; then
  if ! HARNESS="$(detect_harness "${TARGET}")"; then
    fail "BLOCKED: no Claude Code or Codex installation detected"
    fail "Re-run with --harness claude, --harness codex, or --harness both."
    exit 1
  fi
fi

APPLY_TEXT="plan only"
[ "${APPLY}" -eq 1 ] && APPLY_TEXT="apply"

case "${MODE}" in
  check)
    exec bash "${HERE}/scripts/doctor.sh" \
      --target "${TARGET}" --harness "${HARNESS}" --profile "${PROFILE}"
    ;;
  audit)
    if [ "${APPLY}" -eq 1 ]; then
      exec bash "${HERE}/scripts/audit-bundle.sh" \
        --target "${TARGET}" --harness "${HARNESS}" --profile "${PROFILE}" --apply
    fi
    exec bash "${HERE}/scripts/audit-bundle.sh" \
      --target "${TARGET}" --harness "${HARNESS}" --profile "${PROFILE}"
    ;;
  uninstall)
    uninstall_project
    exit $?
    ;;
esac

bold "SUPERBROWKY v${KIT_VERSION} — ${APPLY_TEXT}"
printf '  Project:  %s\n' "${TARGET}"
printf '  Harness:  %s\n' "${HARNESS}"
printf '  Profile:  %s\n\n' "${PROFILE}"

plan_templates
printf '\n'

if [ "${APPLY}" -eq 0 ]; then
  bash "${HERE}/install-skills.sh" --harness "${HARNESS}" --profile "${PROFILE}"
  printf '\n'
  bold "PLAN ONLY — no downloads or writes were performed."
  printf 'Review the paths, conflicts, and sources above, then re-run with --apply.\n'
  exit 0
fi

# Skills stage and validate all remote content before changing live directories.
bash "${HERE}/install-skills.sh" \
  --harness "${HARNESS}" --profile "${PROFILE}" --apply

printf '\n'
bold "Installing project harness"
if ! install_templates; then
  fail "BLOCKED — project templates were not committed; newly created files were rolled back."
  exit 1
fi

printf '\n'
bold "Verification"
doctor_status=0
bash "${HERE}/scripts/doctor.sh" \
  --target "${TARGET}" --harness "${HARNESS}" --profile "${PROFILE}" || doctor_status=$?

case "${doctor_status}" in
  0) ok "READY — open a fresh ${HARNESS} session in the project." ;;
  2)
    warn "PARTIAL — installation is intact, but onboarding or a local runtime check remains."
    warn "Fill PRODUCT.md, DESIGN.md, and adapter placeholders in a fresh session."
    ;;
  *)
    fail "BLOCKED — doctor found an installation problem."
    exit "${doctor_status}"
    ;;
esac

printf '\nGenerate a shareable install report when needed:\n'
printf '  bash %s %s --harness %s --profile %s --audit-bundle --apply\n' \
  "${HERE}/bootstrap.sh" "${TARGET}" "${HARNESS}" "${PROFILE}"

#!/usr/bin/env bash
# SUPERBROWKY v4 — deterministic, receipt-backed skill installer.
#
# The default invocation is a read-only plan. Nothing under CLAUDE_HOME,
# CODEX_HOME, or SUPERBROWKY_STATE_HOME changes without --apply.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${HERE}/scripts/lib.sh"
MANIFEST="${HERE}/manifests/skills.tsv"
LOCK_FILE="${HERE}/versions.lock"

if [ ! -f "$LIB" ]; then
  printf 'BLOCKED: missing %s\n' "$LIB" >&2
  exit 1
fi
# shellcheck source=scripts/lib.sh
. "$LIB"

SB_CLAUDE_HOME_EXPLICIT=0
SB_CODEX_HOME_EXPLICIT=0
[ -n "${CLAUDE_HOME:-}" ] && SB_CLAUDE_HOME_EXPLICIT=1
[ -n "${CODEX_HOME:-}" ] && SB_CODEX_HOME_EXPLICIT=1
CLAUDE_HOME="${CLAUDE_HOME:-"$HOME/.claude"}"
CODEX_HOME="${CODEX_HOME:-"$HOME/.codex"}"
SUPERBROWKY_STATE_HOME="${SUPERBROWKY_STATE_HOME:-"$HOME/.superbrowky"}"
export CLAUDE_HOME CODEX_HOME SUPERBROWKY_STATE_HOME
export SB_CLAUDE_HOME_EXPLICIT SB_CODEX_HOME_EXPLICIT

MODE="install"
APPLY=0
APPLY_SEEN=0
DRY_SEEN=0
REF_MODE="pinned"
HARNESS="auto"
PROFILE="core"

usage() {
  cat <<'EOF'
Usage:
  bash install-skills.sh [options]

Default: show a read-only install plan. Add --apply to make changes.

Options:
  --apply                         execute the displayed plan
  --dry-run                       alias for the default read-only plan
  --harness auto|claude|codex|both
  --profile core|web-launch|growth|full
  --latest                        resolve and preview exact upstream HEAD SHAs;
                                  read-only and cannot be combined with --apply
  --check-updates                 compare pinned refs with upstream (read-only)
  --uninstall                     plan receipt-backed uninstall; add --apply
                                  to execute it
  -h, --help

Overrides:
  CLAUDE_HOME, CODEX_HOME, SUPERBROWKY_STATE_HOME
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      APPLY=1
      APPLY_SEEN=1
      ;;
    --dry-run)
      DRY_SEEN=1
      ;;
    --latest)
      REF_MODE="latest"
      ;;
    --check-updates)
      [ "$MODE" = "install" ] || {
        sb_error "--check-updates cannot be combined with --uninstall"
        exit 2
      }
      MODE="check-updates"
      ;;
    --uninstall)
      [ "$MODE" = "install" ] || {
        sb_error "--uninstall cannot be combined with --check-updates"
        exit 2
      }
      MODE="uninstall"
      ;;
    --harness)
      [ "$#" -ge 2 ] || { sb_error "--harness needs a value"; exit 2; }
      HARNESS="$2"
      shift
      ;;
    --harness=*)
      HARNESS="${1#--harness=}"
      ;;
    --profile)
      [ "$#" -ge 2 ] || { sb_error "--profile needs a value"; exit 2; }
      PROFILE="$2"
      shift
      ;;
    --profile=*)
      PROFILE="${1#--profile=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      sb_error "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
  shift
done

if [ "$APPLY_SEEN" -eq 1 ] && [ "$DRY_SEEN" -eq 1 ]; then
  sb_error "--apply and --dry-run conflict"
  exit 2
fi
if [ "$DRY_SEEN" -eq 1 ]; then
  APPLY=0
fi
if [ "$MODE" = "check-updates" ] && [ "$APPLY" -eq 1 ]; then
  sb_error "--check-updates is always read-only; remove --apply"
  exit 2
fi
if [ "$MODE" = "uninstall" ] && [ "$REF_MODE" = "latest" ]; then
  sb_error "--latest does not apply to --uninstall"
  exit 2
fi
if [ "$APPLY" -eq 1 ] && [ "$REF_MODE" = "latest" ]; then
  sb_error "--latest is preview-only and cannot be combined with --apply"
  sb_error "Use --check-updates, review the exact SHAs, then pin versions.lock."
  exit 2
fi

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
    sb_error "Could not detect Claude Code or Codex."
    sb_status "BLOCKED — rerun with --harness claude, codex, or both."
    exit 1
  fi
  sb_ok "auto-detected harness: $HARNESS"
fi

[ -f "$MANIFEST" ] || {
  sb_error "Missing manifest: $MANIFEST"
  sb_status "BLOCKED — repository is incomplete."
  exit 1
}
[ -f "$LOCK_FILE" ] || {
  sb_error "Missing versions.lock"
  sb_status "BLOCKED — pinned sources cannot be resolved."
  exit 1
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/superbrowky-install.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
SELECTED="${TMP_ROOT}/selected.tsv"
REFS="${TMP_ROOT}/refs.tsv"
ACTIONS="${TMP_ROOT}/actions.tsv"

build_selection() {
  local first=1 line name profiles source_type repo pin_key claude_folder codex_folder license required extra
  local seen=" " count=0
  : > "$SELECTED"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" -eq 1 ]; then
      first=0
      continue
    fi
    [ -n "$line" ] || continue
    IFS="$(printf '\t')" read -r name profiles source_type repo pin_key claude_folder codex_folder license required extra <<EOF
$line
EOF
    if [ -n "${extra:-}" ] || [ -z "${required:-}" ]; then
      sb_error "Malformed manifest row: $line"
      return 1
    fi
    case "$name" in
      ''|*[!a-z0-9-]*) sb_error "Invalid skill name in manifest: $name"; return 1 ;;
    esac
    case "$source_type" in git|bundled) ;; *)
      sb_error "$name: invalid source_type '$source_type'"
      return 1
    esac
    case "$required" in yes|no) ;; *)
      sb_error "$name: required must be yes or no"
      return 1
    esac
    case "$profiles" in core|web-launch|growth|full) ;; *)
      sb_error "$name: invalid manifest profile '$profiles'"
      return 1
    esac
    if ! sb_safe_source_folder "$claude_folder" || ! sb_safe_source_folder "$codex_folder"; then
      sb_error "$name: unsafe source folder in manifest"
      return 1
    fi
    case "$seen" in
      *" $name "*) sb_error "Duplicate manifest skill: $name"; return 1 ;;
    esac
    seen="${seen}${name} "
    if sb_profile_selects "$PROFILE" "$profiles"; then
      printf '%s\n' "$line" >> "$SELECTED"
      count=$((count + 1))
    fi
  done < "$MANIFEST"
  if [ "$count" -eq 0 ]; then
    sb_error "Profile '$PROFILE' selected no skills"
    return 1
  fi
  return 0
}

build_selection || {
  sb_status "BLOCKED — manifest validation failed."
  exit 1
}

bundled_ref() {
  if command -v git >/dev/null 2>&1; then
    git -C "$HERE" rev-parse HEAD 2>/dev/null || printf 'local\n'
  else
    printf 'local\n'
  fi
}

is_exact_git_sha() {
  case "$1" in
    ''|*[!0-9a-fA-F]*) return 1 ;;
  esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}

resolve_refs() {
  # $1=allow network resolution for --latest (yes/no)
  local resolve_latest="$1" line name profiles source_type repo pin_key claude_folder codex_folder license required
  local seen=" " ref latest
  : > "$REFS"
  while IFS= read -r line || [ -n "$line" ]; do
    IFS="$(printf '\t')" read -r name profiles source_type repo pin_key claude_folder codex_folder license required <<EOF
$line
EOF
    if [ "$source_type" = "bundled" ]; then
      continue
    fi
    case "$seen" in *" $repo "*) continue ;; esac
    seen="${seen}${repo} "
    if [ "$REF_MODE" = "pinned" ]; then
      ref="$(sb_lock_pin "$LOCK_FILE" "$pin_key")"
      if [ -z "$ref" ]; then
        sb_error "$repo: no pin '$pin_key' in versions.lock"
        return 1
      fi
    elif [ "$resolve_latest" = "yes" ]; then
      command -v git >/dev/null 2>&1 || {
        sb_error "git is required to resolve --latest safely"
        return 1
      }
      latest="$(git ls-remote "https://github.com/${repo}.git" HEAD 2>/dev/null | awk 'NR == 1 { print $1 }')"
      if is_exact_git_sha "$latest"; then
        ref="$latest"
      else
        sb_error "$repo: could not resolve HEAD to an exact SHA"
        return 1
      fi
    else
      ref="UNRESOLVED_HEAD"
    fi
    printf '%s\t%s\n' "$repo" "$ref" >> "$REFS"
  done < "$SELECTED"
  return 0
}

ref_for_repo() {
  awk -F '\t' -v wanted="$1" '$1 == wanted { print $2; exit }' "$REFS"
}

fetch_repo() {
  # $1=owner/repo, $2=exact ref. Prints extracted repository root.
  local repo="$1" ref="$2" key cache archive root
  key="$(printf '%s@%s' "$repo" "$ref" | tr '/:@' '____')"
  cache="${TMP_ROOT}/fetch/${key}"
  archive="${TMP_ROOT}/fetch/${key}.tar.gz"
  if [ ! -d "$cache" ]; then
    command -v curl >/dev/null 2>&1 || {
      sb_error "curl is required to fetch pinned skills"
      return 1
    }
    command -v tar >/dev/null 2>&1 || {
      sb_error "tar is required to extract pinned skills"
      return 1
    }
    mkdir -p "${TMP_ROOT}/fetch" "${cache}.partial"
    if ! curl -fsSL "https://codeload.github.com/${repo}/tar.gz/${ref}" -o "$archive"; then
      sb_error "$repo@$ref: download failed"
      rm -rf "${cache}.partial"
      return 1
    fi
    if ! tar -xzf "$archive" -C "${cache}.partial"; then
      sb_error "$repo@$ref: archive extraction failed"
      rm -rf "${cache}.partial"
      return 1
    fi
    mv "${cache}.partial" "$cache"
  fi
  root="$(find "$cache" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [ -n "$root" ] || {
    sb_error "$repo@$ref: archive has no repository root"
    return 1
  }
  printf '%s\n' "$root"
}

copy_root_provenance() {
  # $1=repository root, $2=staged skill. Never overwrite skill-local notices.
  local root="$1" dest="$2" file
  for file in LICENSE LICENSE.md NOTICE NOTICE.md; do
    if [ -L "${root}/${file}" ]; then
      sb_error "${dest##*/}: upstream ${file} is a prohibited symlink"
      return 1
    fi
    if [ -f "${root}/${file}" ] && [ ! -e "${dest}/${file}" ] && [ ! -L "${dest}/${file}" ]; then
      cp "${root}/${file}" "${dest}/${file}" || return 1
    fi
  done
  return 0
}

validate_staged_provenance() {
  # Every fetched skill must retain at least one regular license/notice file in
  # the staged package; a symlink never counts as retained provenance.
  local dest="$1" file
  for file in LICENSE LICENSE.md NOTICE NOTICE.md; do
    if [ -f "${dest}/${file}" ] && [ ! -L "${dest}/${file}" ]; then
      return 0
    fi
  done
  sb_error "${dest##*/}: no regular staged LICENSE/NOTICE provenance file"
  return 1
}

harden_impeccable() {
  # Remove automatic global cleanup/pinning from the upstream derivative and
  # insert our reviewed portable contract immediately after YAML frontmatter.
  local dest="$1" overlay="${HERE}/overlays/impeccable-portable.md"
  local cleanup="${dest}/scripts/cleanup-deprecated.mjs"
  local pin="${dest}/scripts/pin.mjs"
  local rewritten="${dest}/SKILL.md.superbrowky-overlay" file portable
  if [ ! -f "$overlay" ]; then
    sb_error "impeccable: missing reviewed overlay $overlay"
    return 1
  fi
  if [ ! -f "$cleanup" ] || [ ! -f "$pin" ]; then
    sb_error "impeccable: expected cleanup/pin helpers changed upstream; refusing derivative"
    return 1
  fi
  rm -f "$cleanup" "$pin" || return 1
  if ! awk -v overlay="$overlay" '
    {
      if ($0 == "## Pin / Unpin") {
        removed_pin_section=1
        skip_pin_section=1
      }
      if (skip_pin_section) next
      if ($0 ~ /^Plus two management commands:/) {
        removed_pin_intro=1
        next
      }
      if (in_frontmatter && $0 ~ /^allowed-tools:/) {
        skipping_allowed_tools=1
        removed_allowed_tools=1
        next
      }
      if (skipping_allowed_tools && $0 ~ /^[[:space:]]/) next
      if (skipping_allowed_tools) skipping_allowed_tools=0
      print
      if ($0 == "---") {
        delimiters++
        if (delimiters == 1) in_frontmatter=1
        if (delimiters == 2) {
          in_frontmatter=0
          print ""
          while ((getline line < overlay) > 0) print line
          close(overlay)
          inserted=1
        }
      }
    }
    END { if (!inserted || !removed_pin_intro || !removed_pin_section) exit 42 }
  ' "${dest}/SKILL.md" > "$rewritten"; then
    rm -f "$rewritten"
    sb_error "impeccable: could not insert portable overlay after frontmatter"
    return 1
  fi
  mv "$rewritten" "${dest}/SKILL.md"
  if LC_ALL=C grep -q '^allowed-tools:' "${dest}/SKILL.md"; then
    sb_error "impeccable: unsafe upstream allowed-tools remains"
    return 1
  fi

  # Upstream examples assume a project-local install. This package is global,
  # so every Markdown helper path resolves through the skill's own directory.
  while IFS= read -r file; do
    portable="${file}.superbrowky-paths"
    if ! sed \
        -e "s#\\.claude/skills/impeccable/#\$SKILL_DIR/#g" \
        -e "s#\\.agents/skills/impeccable/#\$SKILL_DIR/#g" \
        "$file" > "$portable"; then
      rm -f "$portable"
      return 1
    fi
    mv "$portable" "$file"
  done <<EOF
$(find "$dest" -type f -name '*.md' -print)
EOF
  if LC_ALL=C grep -R -n -e '\.claude/skills/impeccable' -e '\.agents/skills/impeccable' "$dest" >/dev/null 2>&1; then
    sb_error "impeccable: project-local harness paths remain after hardening"
    return 1
  fi
  if LC_ALL=C grep -R -n -e 'cleanup-deprecated\.mjs' -e 'pin\.mjs' "$dest" >/dev/null 2>&1; then
    sb_error "impeccable: removed global cleanup/pin helpers are still referenced"
    return 1
  fi
  return 0
}

apply_third_party_safety_overlay() {
  # $1=staged skill directory. Every fetched skill receives the same reviewed
  # authority boundary because global skills are visible outside one project.
  local dest="$1" overlay="${HERE}/overlays/third-party-safety.md"
  local rewritten="${dest}/SKILL.md.superbrowky-safety"
  if [ ! -f "$overlay" ]; then
    sb_error "${dest##*/}: missing reviewed third-party safety overlay"
    return 1
  fi
  if ! awk -v overlay="$overlay" '
    {
      print
      if ($0 == "---") {
        delimiters++
        if (delimiters == 2) {
          print ""
          while ((getline line < overlay) > 0) print line
          close(overlay)
          inserted=1
        }
      }
    }
    END { if (!inserted) exit 42 }
  ' "${dest}/SKILL.md" > "$rewritten"; then
    rm -f "$rewritten"
    sb_error "${dest##*/}: could not insert third-party safety overlay"
    return 1
  fi
  mv "$rewritten" "${dest}/SKILL.md"
  return 0
}

close_known_git_dependencies() {
  # Some upstream skills link outside their own package. Rewrite those links to
  # their exact pinned source rather than writing shared files above the skill.
  # $1=name $2=repo $3=exact ref $4=staged skill directory
  local name="$1" repo="$2" ref="$3" dest="$4" rewritten pinned_url
  case "$name" in
    ai-seo)
      rewritten="${dest}/SKILL.md.superbrowky-deps"
      pinned_url="https://github.com/${repo}/blob/${ref}/tools/REGISTRY.md"
      if ! sed \
          -e "s#../../tools/REGISTRY\\.md#${pinned_url}#g" \
          "${dest}/SKILL.md" > "$rewritten"; then
        rm -f "$rewritten"
        return 1
      fi
      mv "$rewritten" "${dest}/SKILL.md"
      if LC_ALL=C grep -R -n '../../tools/REGISTRY\.md' "$dest" >/dev/null 2>&1; then
        sb_error "ai-seo: external registry path remains after dependency closure"
        return 1
      fi
      if ! LC_ALL=C grep -F -q "$pinned_url" "${dest}/SKILL.md"; then
        sb_error "ai-seo: exact pinned registry link was not inserted"
        return 1
      fi
      ;;
  esac
  return 0
}

stage_all() {
  local harness line name profiles source_type repo pin_key claude_folder codex_folder license required
  local folder ref root src dest hash source overlay
  local failed=0
  : > "${TMP_ROOT}/stage-hashes.tsv"
  for harness in $(sb_harnesses "$HARNESS"); do
    mkdir -p "${TMP_ROOT}/stage/${harness}/skills"
    while IFS= read -r line || [ -n "$line" ]; do
      IFS="$(printf '\t')" read -r name profiles source_type repo pin_key claude_folder codex_folder license required <<EOF
$line
EOF
      if [ "$harness" = "claude" ]; then folder="$claude_folder"; else folder="$codex_folder"; fi
      if [ "$source_type" = "git" ]; then
        ref="$(ref_for_repo "$repo")"
        if [ -z "$ref" ] || [ "$ref" = "UNRESOLVED_HEAD" ]; then
          sb_error "$name: source ref was not resolved"
          failed=$((failed + 1))
          continue
        fi
        if ! root="$(fetch_repo "$repo" "$ref")"; then
          failed=$((failed + 1))
          continue
        fi
        if ! sb_validate_source_path_chain "$root" "$folder"; then
          sb_error "$name: source path contains a missing or linked directory (${repo}:${folder})"
          failed=$((failed + 1))
          continue
        fi
        if [ "$folder" = "." ]; then src="$root"; else src="${root}/${folder}"; fi
        source="git:${repo}:${folder}"
      else
        ref="$(bundled_ref)"
        if ! sb_validate_source_path_chain "$HERE" "$folder"; then
          sb_error "$name: bundled source path contains a missing or linked directory (${folder})"
          failed=$((failed + 1))
          continue
        fi
        if [ "$folder" = "." ]; then src="$HERE"; else src="${HERE}/${folder}"; fi
        source="bundled:${folder}"
      fi
      if [ ! -d "$src" ] || [ -L "$src" ]; then
        sb_error "$name: source folder is missing (${source})"
        failed=$((failed + 1))
        continue
      fi
      if ! sb_validate_no_symlinks "$src"; then
        sb_error "$name: source tree contains a prohibited symlink"
        failed=$((failed + 1))
        continue
      fi
      dest="${TMP_ROOT}/stage/${harness}/skills/${name}"
      mkdir -p "$dest"
      if ! cp -R "${src}/." "${dest}/"; then
        sb_error "$name: staging copy failed"
        failed=$((failed + 1))
        continue
      fi
      if ! sb_validate_no_symlinks "$dest"; then
        sb_error "$name: staged tree contains a prohibited symlink"
        failed=$((failed + 1))
        continue
      fi
      overlay="-"
      if [ "$source_type" = "git" ]; then
        if ! copy_root_provenance "$root" "$dest"; then
          sb_error "$name: could not preserve upstream LICENSE/NOTICE"
          failed=$((failed + 1))
          continue
        fi
        if ! validate_staged_provenance "$dest"; then
          failed=$((failed + 1))
          continue
        fi
        if ! close_known_git_dependencies "$name" "$repo" "$ref" "$dest"; then
          failed=$((failed + 1))
          continue
        fi
      fi
      if [ "$name" = "impeccable" ]; then
        if ! harden_impeccable "$dest"; then
          failed=$((failed + 1))
          continue
        fi
      fi
      if [ "$source_type" = "git" ]; then
        if ! apply_third_party_safety_overlay "$dest"; then
          failed=$((failed + 1))
          continue
        fi
        overlay="third-party-safety-v1"
        if [ "$name" = "impeccable" ]; then
          overlay="${overlay}+superbrowky-overlay-v1"
        fi
        source="${source}+${overlay}"
        if [ "$name" = "ai-seo" ]; then
          source="${source}+pinned-upstream-link-v1"
        fi
      fi
      if ! sb_validate_skill_basic "$dest" "$name"; then
        failed=$((failed + 1))
        continue
      fi
      if ! sb_validate_no_symlinks "$dest"; then
        sb_error "$name: transformed stage contains a prohibited symlink"
        failed=$((failed + 1))
        continue
      fi
      hash="$(sb_tree_hash "$dest")" || {
        sb_error "$name: could not hash staged tree"
        failed=$((failed + 1))
        continue
      }
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$harness" "$name" "$hash" "$source" "$ref" "$license" "$required" "$overlay" \
        >> "${TMP_ROOT}/stage-hashes.tsv"
      sb_ok "staged ${harness}/${name} ($(sb_short_ref "$ref"))"
    done < "$SELECTED"
  done
  if [ "$failed" -gt 0 ]; then
    return 1
  fi
  return 0
}

validate_stages_deep() {
  local harness
  if command -v python3 >/dev/null 2>&1 && [ -f "${HERE}/scripts/validate-skills.py" ]; then
    for harness in $(sb_harnesses "$HARNESS"); do
      if ! python3 "${HERE}/scripts/validate-skills.py" \
          --skills-dir "${TMP_ROOT}/stage/${harness}/skills"; then
        sb_error "$harness: staged skill package validation failed"
        return 1
      fi
    done
  else
    sb_warn "python3 validator unavailable; basic frontmatter/path validation completed."
  fi
  if ! validate_staged_javascript; then
    return 1
  fi
  return 0
}

validate_staged_javascript() {
  local harness skills_root list unsorted file version major found=0
  for harness in $(sb_harnesses "$HARNESS"); do
    skills_root="${TMP_ROOT}/stage/${harness}/skills"
    list="${TMP_ROOT}/javascript-${harness}.txt"
    unsorted="${list}.unsorted"
    if ! find "$skills_root" -type f \
        \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -print > "$unsorted" ||
        ! LC_ALL=C sort "$unsorted" > "$list"; then
      sb_error "$harness: could not enumerate staged JavaScript helpers"
      rm -f "$unsorted"
      return 1
    fi
    rm -f "$unsorted"
    [ -s "$list" ] || continue
    found=1
  done
  [ "$found" -eq 1 ] || return 0

  if ! command -v node >/dev/null 2>&1; then
    sb_error "node 22+ is required by staged JavaScript helpers"
    return 1
  fi
  version="$(node --version 2>/dev/null)" || version=""
  major="${version#v}"
  major="${major%%.*}"
  case "$major" in
    ''|*[!0-9]*)
      sb_error "could not parse Node version '$version' for staged JavaScript validation"
      return 1
      ;;
  esac
  if [ "$major" -lt 22 ]; then
    sb_error "node $version is too old for staged JavaScript helpers (need 22+)"
    return 1
  fi

  for harness in $(sb_harnesses "$HARNESS"); do
    skills_root="${TMP_ROOT}/stage/${harness}/skills"
    list="${TMP_ROOT}/javascript-${harness}.txt"
    [ -s "$list" ] || continue
    while IFS= read -r file; do
      if ! node --check "$file"; then
        sb_error "$harness: JavaScript syntax check failed for ${file#"$skills_root"/}"
        return 1
      fi
    done < "$list"
  done
  sb_ok "staged JavaScript helpers passed node --check (node $version)"
  return 0
}

stage_hash_for() {
  awk -F '\t' -v harness="$1" -v name="$2" \
    '$1 == harness && $2 == name { print $3; exit }' \
    "${TMP_ROOT}/stage-hashes.tsv"
}

stage_field_for() {
  # $1=harness, $2=name, $3=field number
  awk -F '\t' -v harness="$1" -v name="$2" -v field="$3" \
    '$1 == harness && $2 == name { print $field; exit }' \
    "${TMP_ROOT}/stage-hashes.tsv"
}

plan_install_without_stage() {
  local harness line name profiles source_type repo pin_key claude_folder codex_folder license required
  local skills_dir dest receipt receipt_dest expected_hash current_hash ref problems=0 count=0
  sb_bold "SUPERBROWKY install plan — harness=$HARNESS profile=$PROFILE"
  case "$HARNESS" in
    claude|both) printf '  Claude skills: %s\n' "$(sb_redact_home "$(sb_skills_dir claude)")" ;;
  esac
  case "$HARNESS" in
    codex|both) printf '  Codex skills:  %s\n' "$(sb_redact_home "$(sb_skills_dir codex)")" ;;
  esac
  printf '  Receipts:     %s\n\n' "$(sb_redact_home "${SUPERBROWKY_STATE_HOME}/state")"
  if [ "$REF_MODE" = "latest" ]; then
    sb_warn "UNSAFE --latest preview: exact HEAD SHAs were resolved, but their contents were not downloaded or validated."
  fi
  for harness in $(sb_harnesses "$HARNESS"); do
    skills_dir="$(sb_skills_dir "$harness")"
    while IFS= read -r line || [ -n "$line" ]; do
      IFS="$(printf '\t')" read -r name profiles source_type repo pin_key claude_folder codex_folder license required <<EOF
$line
EOF
      dest="${skills_dir}/${name}"
      receipt="$(sb_receipt_path "$SUPERBROWKY_STATE_HOME" "$harness" "$name")"
      if [ "$source_type" = "git" ]; then
        ref="$(ref_for_repo "$repo")"
      else
        ref="$(bundled_ref)"
      fi
      if [ -f "$receipt" ]; then
        receipt_dest="$(sb_receipt_get "$receipt" dest)"
        expected_hash="$(sb_receipt_get "$receipt" tree_hash)"
        if [ "$receipt_dest" != "$dest" ]; then
          sb_error "$harness/$name: receipt destination does not match current home override"
          problems=$((problems + 1))
        elif [ ! -d "$dest" ] || [ -L "$dest" ]; then
          sb_error "$harness/$name: managed destination is missing or is no longer a real directory"
          problems=$((problems + 1))
        else
          current_hash="$(sb_tree_hash "$dest")" || current_hash=""
          if [ -z "$expected_hash" ] || [ "$current_hash" != "$expected_hash" ]; then
            sb_error "$harness/$name: managed copy drifted; it will not be overwritten"
            problems=$((problems + 1))
          else
            if [ "$REF_MODE" = "latest" ]; then
              printf '  PREVIEW %-7s %-30s %s @ %s\n' "$harness" "$name" "$source_type:$repo" "$ref"
            else
              printf '  UPDATE  %-7s %-30s %s @ %s\n' "$harness" "$name" "$source_type:$repo" "$(sb_short_ref "$ref")"
            fi
          fi
        fi
      elif [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ "$REF_MODE" = "latest" ]; then
          printf '  PREVIEW %-7s %-30s backup unmanaged copy; source @ %s\n' "$harness" "$name" "$ref"
        else
          printf '  BACKUP  %-7s %-30s existing unmanaged copy, then install\n' "$harness" "$name"
        fi
      else
        if [ "$REF_MODE" = "latest" ]; then
          printf '  PREVIEW %-7s %-30s %s @ %s\n' "$harness" "$name" "$source_type:$repo" "$ref"
        else
          printf '  INSTALL %-7s %-30s %s @ %s\n' "$harness" "$name" "$source_type:$repo" "$(sb_short_ref "$ref")"
        fi
      fi
      count=$((count + 1))
    done < "$SELECTED"
  done
  printf '\nSelected operations: %s. No live files were changed.\n' "$count"
  if [ "$problems" -gt 0 ]; then
    sb_status "BLOCKED — fix managed drift/receipt conflicts before --apply."
    return 1
  fi
  if [ "$REF_MODE" = "latest" ]; then
    sb_status "PREVIEW — resolved HEADs only; review and pin exact SHAs in versions.lock before --apply."
  else
    sb_status "READY — plan only; rerun the same command with --apply."
  fi
  return 0
}

preflight_install() {
  local harness line name profiles source_type repo pin_key claude_folder codex_folder license required
  local skills_dir dest receipt receipt_dest expected_hash current_hash staged_hash action backup
  local live_type live_hash backup_type backup_hash actual_type actual_hash backup_root
  local problems=0
  : > "$ACTIONS"
  backup_root="${SUPERBROWKY_STATE_HOME}/backups"
  for harness in $(sb_harnesses "$HARNESS"); do
    skills_dir="$(sb_skills_dir "$harness")"
    while IFS= read -r line || [ -n "$line" ]; do
      IFS="$(printf '\t')" read -r name profiles source_type repo pin_key claude_folder codex_folder license required <<EOF
$line
EOF
      dest="${skills_dir}/${name}"
      receipt="$(sb_receipt_path "$SUPERBROWKY_STATE_HOME" "$harness" "$name")"
      staged_hash="$(stage_hash_for "$harness" "$name")"
      action=""
      backup="-"
      live_type="-"
      live_hash="-"
      backup_type="-"
      backup_hash="-"
      if [ -z "$staged_hash" ]; then
        sb_error "$harness/$name: staged hash missing"
        problems=$((problems + 1))
        continue
      fi
      if [ -L "$receipt" ]; then
        sb_error "$harness/$name: receipt must not be a symlink"
        problems=$((problems + 1))
        continue
      elif [ -f "$receipt" ]; then
        receipt_dest="$(sb_receipt_get "$receipt" dest)"
        expected_hash="$(sb_receipt_get "$receipt" tree_hash)"
        backup="$(sb_receipt_get "$receipt" backup)"
        backup_type="$(sb_receipt_get "$receipt" backup_type)"
        backup_hash="$(sb_receipt_get "$receipt" backup_hash)"
        [ -n "$backup" ] || backup="-"
        if [ "$receipt_dest" != "$dest" ]; then
          sb_error "$harness/$name: receipt destination conflict"
          problems=$((problems + 1))
          continue
        fi
        if [ ! -d "$dest" ] || [ -L "$dest" ]; then
          sb_error "$harness/$name: managed copy is missing or not a real directory"
          problems=$((problems + 1))
          continue
        fi
        current_hash="$(sb_tree_hash "$dest")" || current_hash=""
        if [ -z "$expected_hash" ] || [ "$current_hash" != "$expected_hash" ]; then
          sb_error "$harness/$name: managed copy drifted; refusing overwrite"
          problems=$((problems + 1))
          continue
        fi
        live_type="directory"
        live_hash="$current_hash"
        if [ "$backup" != "-" ]; then
          if [ -L "$backup_root" ]; then
            sb_error "$harness/$name: backups root must not be a symlink"
            problems=$((problems + 1))
            continue
          fi
          if [ -z "$backup_type" ] || [ -z "$backup_hash" ] ||
              [ "$backup_type" = "-" ] || [ "$backup_hash" = "-" ]; then
            sb_error "$harness/$name: recorded backup lacks type/hash metadata"
            problems=$((problems + 1))
            continue
          fi
          if ! sb_path_is_within "$backup" "$backup_root"; then
            sb_error "$harness/$name: recorded backup escapes SUPERBROWKY_STATE_HOME/backups"
            problems=$((problems + 1))
            continue
          fi
          actual_type="$(sb_path_type "$backup")" || actual_type=""
          actual_hash="$(sb_path_hash "$backup" "$actual_type")" || actual_hash=""
          if [ "$actual_type" != "$backup_type" ] || [ -z "$actual_hash" ] ||
              [ "$actual_hash" != "$backup_hash" ]; then
            sb_error "$harness/$name: recorded original backup type/hash mismatch"
            problems=$((problems + 1))
            continue
          fi
        else
          backup_type="-"
          backup_hash="-"
        fi
        if [ "$current_hash" = "$staged_hash" ]; then action="NOOP"; else action="REPLACE"; fi
      elif [ -e "$dest" ] || [ -L "$dest" ]; then
        action="BACKUP"
        live_type="$(sb_path_type "$dest")" || live_type=""
        live_hash="$(sb_path_hash "$dest" "$live_type")" || live_hash=""
        if [ -z "$live_type" ] || [ -z "$live_hash" ]; then
          sb_error "$harness/$name: unmanaged destination type cannot be backed up safely"
          problems=$((problems + 1))
          continue
        fi
      else
        action="INSTALL"
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$harness" "$name" "$action" "$dest" "$receipt" "$backup" \
        "$live_type" "$live_hash" "$backup_type" "$backup_hash" >> "$ACTIONS"
    done < "$SELECTED"
  done
  [ "$problems" -eq 0 ]
}

print_apply_plan() {
  local harness name action dest receipt backup live_type live_hash backup_type backup_hash ref source
  sb_bold "Validated apply plan — harness=$HARNESS profile=$PROFILE"
  case "$HARNESS" in
    claude|both) printf '  Claude skills: %s\n' "$(sb_redact_home "$(sb_skills_dir claude)")" ;;
  esac
  case "$HARNESS" in
    codex|both) printf '  Codex skills:  %s\n' "$(sb_redact_home "$(sb_skills_dir codex)")" ;;
  esac
  printf '  Receipts:     %s\n\n' "$(sb_redact_home "${SUPERBROWKY_STATE_HOME}/state")"
  while IFS="$(printf '\t')" read -r harness name action dest receipt backup \
      live_type live_hash backup_type backup_hash; do
    : "$dest" "$receipt" "$backup" "$live_type" "$live_hash" "$backup_type" "$backup_hash"
    ref="$(stage_field_for "$harness" "$name" 5)"
    source="$(stage_field_for "$harness" "$name" 4)"
    printf '  %-7s %-7s %-30s %s @ %s\n' "$action" "$harness" "$name" "$source" "$(sb_short_ref "$ref")"
  done < "$ACTIONS"
  printf '\nAll selected skills were staged and validated before this plan.\n'
}

write_receipt() {
  # $1=receipt $2=name $3=harness $4=dest $5=source $6=ref
  # $7=tree hash $8=backup $9=backup type $10=backup hash
  # $11=license $12=overlay
  local receipt="$1" name="$2" harness="$3" dest="$4" source="$5" ref="$6"
  local tree_hash="$7" backup="$8" backup_type="$9" backup_hash="${10}"
  local license="${11}" overlay="${12}" tmp
  mkdir -p "$(dirname "$receipt")" || return 1
  tmp="${receipt}.partial.$$"
  if [ -e "$tmp" ] || [ -L "$tmp" ]; then
    sb_error "$harness/$name: temporary receipt path already exists"
    return 1
  fi
  {
    printf 'format\t2\n'
    printf 'name\t%s\n' "$name"
    printf 'harness\t%s\n' "$harness"
    printf 'profile\t%s\n' "$PROFILE"
    printf 'dest\t%s\n' "$dest"
    printf 'source\t%s\n' "$source"
    printf 'ref\t%s\n' "$ref"
    printf 'tree_hash\t%s\n' "$tree_hash"
    printf 'backup\t%s\n' "$backup"
    printf 'backup_type\t%s\n' "$backup_type"
    printf 'backup_hash\t%s\n' "$backup_hash"
    printf 'license\t%s\n' "$license"
    printf 'overlay\t%s\n' "$overlay"
    printf 'installed_at\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if ! mv "$tmp" "$receipt"; then
    rm -f "$tmp"
    return 1
  fi
  [ -f "$receipt" ] && [ ! -L "$receipt" ]
}

managed_tree_matches() {
  local path="$1" expected="$2" actual
  [ -d "$path" ] && [ ! -L "$path" ] || return 1
  actual="$(sb_tree_hash "$path")" || return 1
  [ "$actual" = "$expected" ]
}

path_metadata_matches() {
  local path="$1" expected_type="$2" expected_hash="$3" actual_type actual_hash
  actual_type="$(sb_path_type "$path")" || return 1
  [ "$actual_type" = "$expected_type" ] || return 1
  actual_hash="$(sb_path_hash "$path" "$actual_type")" || return 1
  [ "$actual_hash" = "$expected_hash" ]
}

install_one() {
  # $1..$6=harness/name/action/dest/receipt/existing backup
  # $7..$10=preflight live type/hash and backup type/hash
  local harness="$1" name="$2" action="$3" dest="$4" receipt="$5" backup="$6"
  local live_type="$7" live_hash="$8" backup_type="$9" backup_hash="${10}"
  local skills_dir stage staged_hash source ref license overlay partial previous
  local new_backup new_backup_type new_backup_hash timestamp backup_root
  skills_dir="$(dirname "$dest")"
  stage="${TMP_ROOT}/stage/${harness}/skills/${name}"
  staged_hash="$(stage_hash_for "$harness" "$name")"
  source="$(stage_field_for "$harness" "$name" 4)"
  ref="$(stage_field_for "$harness" "$name" 5)"
  license="$(stage_field_for "$harness" "$name" 6)"
  overlay="$(stage_field_for "$harness" "$name" 8)"
  partial="${skills_dir}/.${name}.superbrowky.partial.$$"
  previous="${skills_dir}/.${name}.superbrowky.previous.$$"
  new_backup="$backup"
  new_backup_type="$backup_type"
  new_backup_hash="$backup_hash"
  backup_root="${SUPERBROWKY_STATE_HOME}/backups"

  # Recheck even a NOOP so a live tree cannot change after preflight and still
  # be reported as verified.
  if [ "$action" = "NOOP" ]; then
    if ! managed_tree_matches "$dest" "$live_hash" ||
        [ "$live_hash" != "$staged_hash" ]; then
      sb_error "$harness/$name: live tree changed after preflight"
      return 1
    fi
    sb_ok "${harness}/${name} (NOOP)"
    return 0
  fi

  mkdir -p "$skills_dir" || return 1
  if [ -e "$partial" ] || [ -L "$partial" ] ||
      [ -e "$previous" ] || [ -L "$previous" ]; then
    sb_error "$harness/$name: temporary apply path already exists"
    return 1
  fi
  mkdir -p "$partial" || return 1
  cp -R "${stage}/." "${partial}/" || {
    rm -rf "$partial"
    return 1
  }
  if [ "$(sb_tree_hash "$partial")" != "$staged_hash" ]; then
    sb_error "$harness/$name: partial copy hash mismatch"
    rm -rf "$partial"
    return 1
  fi

  case "$action" in
    INSTALL)
      if [ -e "$dest" ] || [ -L "$dest" ]; then
        sb_error "$harness/$name: destination appeared after preflight"
        rm -rf "$partial"
        return 1
      fi
      if ! mv "$partial" "$dest"; then
        rm -rf "$partial"
        return 1
      fi
      if ! managed_tree_matches "$dest" "$staged_hash"; then
        sb_error "$harness/$name: installed tree changed during move"
        return 1
      fi
      ;;
    BACKUP)
      timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
      mkdir -p "$backup_root" || {
        rm -rf "$partial"
        return 1
      }
      if [ -L "$backup_root" ]; then
        sb_error "$harness/$name: backups root must not be a symlink"
        rm -rf "$partial"
        return 1
      fi
      new_backup="${backup_root}/${timestamp}/${harness}/${name}"
      if [ -e "$new_backup" ] || [ -L "$new_backup" ]; then
        new_backup="${new_backup}.$$"
      fi
      if [ -e "$new_backup" ] || [ -L "$new_backup" ]; then
        sb_error "$harness/$name: unique backup destination already exists"
        rm -rf "$partial"
        return 1
      fi
      mkdir -p "$(dirname "$new_backup")" || {
        rm -rf "$partial"
        return 1
      }
      if ! sb_path_is_within "$new_backup" "$backup_root"; then
        sb_error "$harness/$name: generated backup path escaped backups root"
        rm -rf "$partial"
        return 1
      fi
      if ! mv "$dest" "$new_backup"; then
        rm -rf "$partial"
        return 1
      fi
      if ! path_metadata_matches "$new_backup" "$live_type" "$live_hash"; then
        sb_error "$harness/$name: live destination changed after preflight"
        if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
          mv "$new_backup" "$dest" 2>/dev/null || true
        fi
        rm -rf "$partial"
        return 1
      fi
      new_backup_type="$live_type"
      new_backup_hash="$live_hash"
      if ! mv "$partial" "$dest"; then
        mv "$new_backup" "$dest" 2>/dev/null || true
        rm -rf "$partial"
        return 1
      fi
      if ! managed_tree_matches "$dest" "$staged_hash"; then
        sb_error "$harness/$name: replacement tree changed during move"
        return 1
      fi
      ;;
    REPLACE)
      if ! mv "$dest" "$previous"; then
        rm -rf "$partial"
        return 1
      fi
      if ! managed_tree_matches "$previous" "$live_hash"; then
        sb_error "$harness/$name: live managed tree changed after preflight"
        if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
          mv "$previous" "$dest" 2>/dev/null || true
        fi
        rm -rf "$partial"
        return 1
      fi
      if ! mv "$partial" "$dest"; then
        mv "$previous" "$dest" 2>/dev/null || true
        rm -rf "$partial"
        return 1
      fi
      if ! managed_tree_matches "$dest" "$staged_hash"; then
        sb_error "$harness/$name: replacement tree changed during move"
        return 1
      fi
      ;;
    *)
      sb_error "$harness/$name: unknown action $action"
      rm -rf "$partial"
      return 1
      ;;
  esac

  if ! write_receipt "$receipt" "$name" "$harness" "$dest" "$source" "$ref" \
      "$staged_hash" "$new_backup" "$new_backup_type" "$new_backup_hash" \
      "$license" "$overlay"; then
    sb_error "$harness/$name: could not write receipt; rolling back"
    case "$action" in
      INSTALL)
        if managed_tree_matches "$dest" "$staged_hash"; then
          rm -rf "$dest"
        else
          sb_error "$harness/$name: rollback preserved a changed destination"
        fi
        ;;
      BACKUP)
        if managed_tree_matches "$dest" "$staged_hash" &&
            path_metadata_matches "$new_backup" "$new_backup_type" "$new_backup_hash"; then
          rm -rf "$dest"
          mv "$new_backup" "$dest" 2>/dev/null || true
        else
          sb_error "$harness/$name: rollback preserved changed live/backup data"
        fi
        ;;
      REPLACE)
        if managed_tree_matches "$dest" "$staged_hash" &&
            managed_tree_matches "$previous" "$live_hash"; then
          rm -rf "$dest"
          mv "$previous" "$dest" 2>/dev/null || true
        else
          sb_error "$harness/$name: rollback preserved changed live/previous data"
        fi
        ;;
    esac
    return 1
  fi
  if [ "$action" = "REPLACE" ]; then
    if ! managed_tree_matches "$previous" "$live_hash"; then
      sb_error "$harness/$name: previous tree changed before cleanup; preserved at $previous"
      return 1
    fi
    rm -rf "$previous"
  fi
  sb_ok "${harness}/${name} (${action})"
  return 0
}

apply_install() {
  local harness name action dest receipt backup live_type live_hash backup_type backup_hash
  local changed=0 failed=0
  while IFS="$(printf '\t')" read -r harness name action dest receipt backup \
      live_type live_hash backup_type backup_hash; do
    if install_one "$harness" "$name" "$action" "$dest" "$receipt" "$backup" \
        "$live_type" "$live_hash" "$backup_type" "$backup_hash"; then
      [ "$action" = "NOOP" ] || changed=$((changed + 1))
    else
      sb_error "$harness/$name: apply failed"
      failed=$((failed + 1))
    fi
  done < "$ACTIONS"
  if [ "$failed" -gt 0 ]; then
    if [ "$changed" -gt 0 ]; then
      sb_status "PARTIAL — $changed changed, $failed failed. Receipts identify managed copies."
    else
      sb_status "BLOCKED — apply failed before any skill changed."
    fi
    return 1
  fi
  sb_status "READY — all selected skills are installed and receipt-verified."
  return 0
}

collect_uninstall_actions() {
  local harness state_dir receipt name receipt_harness dest expected_dest expected_hash current_hash backup
  local backup_type backup_hash actual_type actual_hash backup_root
  local found=0 problems=0
  : > "$ACTIONS"
  backup_root="${SUPERBROWKY_STATE_HOME}/backups"
  for harness in $(sb_harnesses "$HARNESS"); do
    state_dir="${SUPERBROWKY_STATE_HOME}/state/${harness}"
    if [ ! -d "$state_dir" ]; then
      sb_error "$harness: no receipt directory; refusing manifest-based removal"
      problems=$((problems + 1))
      continue
    fi
    : > "${TMP_ROOT}/receipts-${harness}.txt"
    find "$state_dir" -maxdepth 1 -type f -name '*.receipt.tsv' -print | LC_ALL=C sort > "${TMP_ROOT}/receipts-${harness}.txt"
    if [ ! -s "${TMP_ROOT}/receipts-${harness}.txt" ]; then
      sb_error "$harness: no receipts; refusing uninstall"
      problems=$((problems + 1))
      continue
    fi
    while IFS= read -r receipt; do
      if [ -L "$receipt" ]; then
        sb_error "$receipt: receipt must not be a symlink"
        problems=$((problems + 1))
        continue
      fi
      name="$(sb_receipt_get "$receipt" name)"
      receipt_harness="$(sb_receipt_get "$receipt" harness)"
      dest="$(sb_receipt_get "$receipt" dest)"
      expected_hash="$(sb_receipt_get "$receipt" tree_hash)"
      backup="$(sb_receipt_get "$receipt" backup)"
      backup_type="$(sb_receipt_get "$receipt" backup_type)"
      backup_hash="$(sb_receipt_get "$receipt" backup_hash)"
      expected_dest="$(sb_skills_dir "$harness")/${name}"
      case "$name" in
        ''|*[!a-z0-9-]*)
          sb_error "$receipt: unsafe/missing skill name"
          problems=$((problems + 1))
          continue
          ;;
      esac
      if [ "$receipt_harness" != "$harness" ] || [ "$dest" != "$expected_dest" ]; then
        sb_error "$harness/$name: receipt ownership boundary mismatch"
        problems=$((problems + 1))
        continue
      fi
      if [ ! -d "$dest" ] || [ -L "$dest" ]; then
        sb_error "$harness/$name: installed copy is missing or not a real directory"
        problems=$((problems + 1))
        continue
      fi
      current_hash="$(sb_tree_hash "$dest")" || current_hash=""
      if [ -z "$expected_hash" ] || [ "$current_hash" != "$expected_hash" ]; then
        sb_error "$harness/$name: installed copy drifted; leaving it untouched"
        problems=$((problems + 1))
        continue
      fi
      [ -n "$backup" ] || backup="-"
      if [ "$backup" != "-" ]; then
        if [ -L "$backup_root" ]; then
          sb_error "$harness/$name: backups root must not be a symlink"
          problems=$((problems + 1))
          continue
        fi
        if [ -z "$backup_type" ] || [ -z "$backup_hash" ] ||
            [ "$backup_type" = "-" ] || [ "$backup_hash" = "-" ]; then
          sb_error "$harness/$name: recorded backup lacks type/hash metadata"
          problems=$((problems + 1))
          continue
        fi
        if ! sb_path_is_within "$backup" "$backup_root"; then
          sb_error "$harness/$name: recorded backup escapes SUPERBROWKY_STATE_HOME/backups"
          problems=$((problems + 1))
          continue
        fi
        actual_type="$(sb_path_type "$backup")" || actual_type=""
        actual_hash="$(sb_path_hash "$backup" "$actual_type")" || actual_hash=""
        if [ "$actual_type" != "$backup_type" ] || [ -z "$actual_hash" ] ||
            [ "$actual_hash" != "$backup_hash" ]; then
          sb_error "$harness/$name: recorded backup type/hash mismatch"
          problems=$((problems + 1))
          continue
        fi
      else
        backup_type="-"
        backup_hash="-"
      fi
      printf '%s\t%s\tUNINSTALL\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$harness" "$name" "$dest" "$receipt" "$backup" "$backup_type" \
        "$backup_hash" "$expected_hash" >> "$ACTIONS"
      found=$((found + 1))
    done < "${TMP_ROOT}/receipts-${harness}.txt"
  done
  if [ "$found" -eq 0 ]; then
    problems=$((problems + 1))
  fi
  [ "$problems" -eq 0 ]
}

print_uninstall_plan() {
  local harness name action dest receipt backup backup_type backup_hash expected_hash
  sb_bold "Receipt-backed uninstall plan — harness=$HARNESS"
  while IFS="$(printf '\t')" read -r harness name action dest receipt backup \
      backup_type backup_hash expected_hash; do
    : "$action" "$dest" "$receipt" "$backup_type" "$backup_hash" "$expected_hash"
    if [ "$backup" = "-" ]; then
      printf '  REMOVE  %-7s %s\n' "$harness" "$name"
    else
      printf '  RESTORE %-7s %s (remove managed copy, restore original)\n' "$harness" "$name"
    fi
  done < "$ACTIONS"
  printf '\nOnly hash-matching receipt-owned directories are eligible.\n'
}

uninstall_one() {
  local harness="$1" name="$2" dest="$3" receipt="$4" backup="$5"
  local backup_type="$6" backup_hash="$7" expected_hash="$8"
  local previous="${dest}.superbrowky-removing.$$"
  local backup_root="${SUPERBROWKY_STATE_HOME}/backups"
  if [ -e "$previous" ] || [ -L "$previous" ]; then
    sb_error "$harness/$name: temporary uninstall path already exists"
    return 1
  fi
  if ! mv "$dest" "$previous"; then
    return 1
  fi
  if ! managed_tree_matches "$previous" "$expected_hash"; then
    sb_error "$harness/$name: managed tree changed after uninstall preflight"
    if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
      mv "$previous" "$dest" 2>/dev/null || true
    fi
    return 1
  fi
  if [ "$backup" != "-" ]; then
    if ! sb_path_is_within "$backup" "$backup_root" ||
        ! path_metadata_matches "$backup" "$backup_type" "$backup_hash"; then
      sb_error "$harness/$name: backup changed before restore"
      mv "$previous" "$dest" 2>/dev/null || true
      return 1
    fi
    if ! mv "$backup" "$dest"; then
      mv "$previous" "$dest" 2>/dev/null || true
      return 1
    fi
    if ! path_metadata_matches "$dest" "$backup_type" "$backup_hash"; then
      sb_error "$harness/$name: restored backup type/hash mismatch"
      if [ ! -e "$backup" ] && [ ! -L "$backup" ]; then
        mv "$dest" "$backup" 2>/dev/null || true
      fi
      if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
        mv "$previous" "$dest" 2>/dev/null || true
      fi
      return 1
    fi
  fi
  if ! rm -f "$receipt"; then
    if [ "$backup" != "-" ]; then
      if path_metadata_matches "$dest" "$backup_type" "$backup_hash"; then
        mv "$dest" "$backup" 2>/dev/null || true
      fi
    fi
    if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
      mv "$previous" "$dest" 2>/dev/null || true
    fi
    return 1
  fi
  if ! managed_tree_matches "$previous" "$expected_hash"; then
    sb_error "$harness/$name: removed tree changed before final deletion; preserved at $previous"
    return 1
  fi
  rm -rf "$previous"
  if [ "$backup" = "-" ]; then
    sb_ok "removed ${harness}/${name}"
  else
    sb_ok "restored original ${harness}/${name}"
  fi
  return 0
}

apply_uninstall() {
  local harness name action dest receipt backup backup_type backup_hash expected_hash
  local changed=0 failed=0
  while IFS="$(printf '\t')" read -r harness name action dest receipt backup \
      backup_type backup_hash expected_hash; do
    : "$action"
    if uninstall_one "$harness" "$name" "$dest" "$receipt" "$backup" \
        "$backup_type" "$backup_hash" "$expected_hash"; then
      changed=$((changed + 1))
    else
      sb_error "$harness/$name: uninstall failed"
      failed=$((failed + 1))
    fi
  done < "$ACTIONS"
  if [ "$failed" -gt 0 ]; then
    sb_status "PARTIAL — $changed removed/restored, $failed failed."
    return 1
  fi
  sb_status "READY — receipt-owned skills uninstalled; recorded originals restored."
  return 0
}

check_updates() {
  local line name profiles source_type repo pin_key claude_folder codex_folder license required
  local seen=" " locked latest failures=0 updates=0
  command -v git >/dev/null 2>&1 || {
    sb_error "git is required for --check-updates"
    sb_status "BLOCKED — cannot query upstream refs."
    return 1
  }
  sb_bold "Pinned source update check — profile=$PROFILE"
  while IFS= read -r line || [ -n "$line" ]; do
    IFS="$(printf '\t')" read -r name profiles source_type repo pin_key claude_folder codex_folder license required <<EOF
$line
EOF
    [ "$source_type" = "git" ] || continue
    case "$seen" in *" $repo "*) continue ;; esac
    seen="${seen}${repo} "
    locked="$(sb_lock_pin "$LOCK_FILE" "$pin_key")"
    if [ -z "$locked" ]; then
      sb_error "$repo: missing pin '$pin_key'"
      failures=$((failures + 1))
      continue
    fi
    latest="$(git ls-remote "https://github.com/${repo}.git" HEAD 2>/dev/null | awk 'NR == 1 { print $1 }')"
    if ! is_exact_git_sha "$latest"; then
      sb_warn "$repo: upstream unreachable or returned a non-exact HEAD"
      failures=$((failures + 1))
    elif [ "$latest" = "$locked" ]; then
      sb_ok "$repo ($(sb_short_ref "$locked"))"
    else
      updates=$((updates + 1))
      sb_warn "$repo: $(sb_short_ref "$locked") -> $(sb_short_ref "$latest")"
      printf '  %s=%s\n' "$pin_key" "$latest"
    fi
  done < "$SELECTED"
  if [ "$failures" -gt 0 ]; then
    sb_status "PARTIAL — $failures source(s) could not be checked; nothing changed."
    return 1
  fi
  sb_status "READY — update check complete; $updates pin update(s) available."
  return 0
}

case "$MODE" in
  check-updates)
    check_updates
    exit $?
    ;;
  uninstall)
    if ! collect_uninstall_actions; then
      sb_status "BLOCKED — uninstall requires valid, drift-free receipts for the requested harness."
      exit 1
    fi
    print_uninstall_plan
    if [ "$APPLY" -eq 0 ]; then
      sb_status "READY — uninstall plan only; rerun with --apply."
      exit 0
    fi
    apply_uninstall
    exit $?
    ;;
esac

if [ "$REF_MODE" = "latest" ]; then
  sb_warn "UNSAFE --latest preview selected: upstream HEADs are unreviewed and may change behavior."
fi

if [ "$APPLY" -eq 0 ]; then
  resolve_latest="no"
  [ "$REF_MODE" = "latest" ] && resolve_latest="yes"
  if ! resolve_refs "$resolve_latest"; then
    sb_status "BLOCKED — source refs are incomplete."
    exit 1
  fi
  plan_install_without_stage
  exit $?
fi

if ! resolve_refs "yes"; then
  sb_status "BLOCKED — source refs could not be resolved; no live files changed."
  exit 1
fi
sb_bold "Staging every selected skill before live changes"
if ! stage_all || ! validate_stages_deep; then
  sb_status "BLOCKED — staging/validation failed; no live files changed."
  exit 1
fi
if ! preflight_install; then
  sb_status "BLOCKED — drift or receipt conflict detected; no live files changed."
  exit 1
fi
print_apply_plan
apply_install
exit $?

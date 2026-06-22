#!/usr/bin/env bash
#
# Claude Code Design Kit — one-command setup.
#
# Does all three layers in one go:
#   1. the kit's templates into YOUR project root   (local, can't fail)
#   2. machine-wide taste skills                    (install-skills.sh, pinned)
#   3. impeccable into YOUR project                 (its official installer)
#
#   bash bootstrap.sh /path/to/your-project
#   bash bootstrap.sh /path/to/your-project --latest    # un-pinned upstream
#   bash bootstrap.sh /path/to/your-project --dry-run   # show actions, write nothing
#   bash bootstrap.sh /path/to/your-project --check     # verify an existing setup
#
# Safe: it never clobbers an existing CLAUDE.md / PRODUCT.md / DESIGN.md in
# your project — if one is there, it drops the template next to it as
# `<name>.from-design-kit` for you to merge by hand.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LOCK_FILE="${HERE}/versions.lock"

ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1" >&2; }
bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# Resolve a pinned value from versions.lock by key. Echoes the value or nothing.
lock_pin() { # $1=key
  [ -f "${LOCK_FILE}" ] || return 0
  local k v
  while IFS='=' read -r k v; do
    case "${k}" in \#*|'') continue ;; esac
    if [ "${k}" = "$1" ]; then printf '%s' "${v}"; return 0; fi
  done < "${LOCK_FILE}"
}

usage() {
  cat <<EOS
Usage: bash bootstrap.sh /path/to/your-project [--latest] [--dry-run] [--check]
  --latest    install upstream HEAD instead of the versions.lock pins
  --dry-run   print every action; copy, download, and install nothing
  --check     verify an existing setup (templates, skills, impeccable, node)
EOS
}

# The skill names the kit installs — parsed from install-skills.sh so this stays
# in sync with the manifest automatically (no second list to maintain).
expected_skills() {
  sed -n '/^MANIFEST=(/,/^)/p' "${HERE}/install-skills.sh" | sed -n 's/.*|\([a-z0-9-]*\)".*/\1/p'
  sed -n '/^BUNDLED=(/,/^)/p'  "${HERE}/install-skills.sh" | sed -n 's/^[[:space:]]*"\([a-z0-9-]*\)".*/\1/p'
}

# --- args ---
TARGET=""
LATEST_FLAG=""
DRY=0
MODE="install"
for arg in "$@"; do
  case "${arg}" in
    --latest)  LATEST_FLAG="--latest" ;;
    --dry-run) DRY=1 ;;
    --check)   MODE="check" ;;
    -h|--help) usage; exit 0 ;;
    --*) warn "unknown flag: ${arg}"; usage; exit 1 ;;
    *) if [ -z "${TARGET}" ]; then TARGET="${arg}"; else warn "unexpected argument: ${arg}"; usage; exit 1; fi ;;
  esac
done

if [ ! -f "${HERE}/install-skills.sh" ] || [ ! -d "${HERE}/template" ]; then
  warn "bootstrap.sh must run from a full clone of the kit:"
  warn "  git clone https://github.com/michaelbrowk/SUPERBROWKY.git"
  exit 1
fi
if [ -z "${TARGET}" ]; then usage; exit 1; fi
if [ ! -d "${TARGET}" ]; then warn "Not a directory: ${TARGET}"; exit 1; fi
TARGET="$(cd "${TARGET}" && pwd)"

IMPECCABLE_VER="$(lock_pin impeccable-cli)"
IMPECCABLE_PKG="impeccable${IMPECCABLE_VER:+@${IMPECCABLE_VER}}"
[ -n "${LATEST_FLAG}" ] && IMPECCABLE_PKG="impeccable"

# --- doctor (--check) ---
if [ "${MODE}" = "check" ]; then
  fails=0
  bold "Checking kit setup for ${TARGET}"
  for f in CLAUDE.md PRODUCT.md DESIGN.md; do
    if [ -f "${TARGET}/${f}" ]; then ok "template ${f}"; else warn "missing template ${f}"; fails=$((fails+1)); fi
  done
  SKILLS_DIR="${HOME}/.claude/skills"
  while read -r name; do
    [ -z "${name}" ] && continue
    if [ -f "${SKILLS_DIR}/${name}/SKILL.md" ]; then ok "skill ${name}"; else warn "missing machine skill ${name}"; fails=$((fails+1)); fi
  done <<< "$(expected_skills)"
  if [ -f "${TARGET}/.claude/skills/impeccable/SKILL.md" ] || ls "${TARGET}/.claude/skills/"*impeccable*/SKILL.md >/dev/null 2>&1; then
    ok "impeccable (project-level)"
  else
    warn "impeccable not found in ${TARGET}/.claude/skills/"; fails=$((fails+1))
  fi
  if command -v node >/dev/null 2>&1; then ok "node $(node -v)"; else warn "node not found (impeccable needs Node 24+)"; fails=$((fails+1)); fi
  echo
  if [ "${fails}" -eq 0 ]; then ok "All checks passed."; else warn "${fails} check(s) failed — re-run bootstrap.sh to fix."; exit 1; fi
  exit 0
fi

[ "${DRY}" -eq 1 ] && bold "DRY RUN — showing actions only; nothing is copied, downloaded, or installed"

bold "1/3 · Wiring templates into ${TARGET}"
for f in CLAUDE.md PRODUCT.md DESIGN.md; do
  dst="${TARGET}/${f}"
  if [ "${DRY}" -eq 1 ]; then
    if [ -e "${dst}" ]; then ok "would write ${f}.from-design-kit (${f} already exists)"; else ok "would copy ${f} → ${TARGET}"; fi
    continue
  fi
  src="${HERE}/template/${f}"
  if [ -e "${dst}" ]; then
    cp "${src}" "${TARGET}/${f}.from-design-kit"
    warn "${f} already exists — wrote ${f}.from-design-kit instead. Merge it in by hand."
  else
    cp "${src}" "${dst}"
    ok "copied ${f} → ${TARGET}"
  fi
done

echo
bold "2/3 · Installing machine-wide design skills"
INSTALL_ARGS=()
[ -n "${LATEST_FLAG}" ] && INSTALL_ARGS+=("${LATEST_FLAG}")
[ "${DRY}" -eq 1 ] && INSTALL_ARGS+=("--dry-run")
if [ "${#INSTALL_ARGS[@]}" -gt 0 ]; then
  bash "${HERE}/install-skills.sh" "${INSTALL_ARGS[@]}"
else
  bash "${HERE}/install-skills.sh"
fi

echo
bold "3/3 · Installing impeccable into ${TARGET}"
if [ "${DRY}" -eq 1 ]; then
  ok "would run: cd ${TARGET} && npx -y ${IMPECCABLE_PKG} skills install --yes"
elif command -v npx >/dev/null 2>&1; then
  if (cd "${TARGET}" && npx -y "${IMPECCABLE_PKG}" skills install --yes); then
    ok "impeccable installed (project-level, .claude/skills/)"
  else
    warn "impeccable installer failed — run it yourself later:"
    warn "  cd ${TARGET} && npx -y ${IMPECCABLE_PKG} skills install --yes"
  fi
else
  warn "Node.js/npx not found — impeccable needs Node 24+ (skill + context scripts)."
  warn "Install Node (https://nodejs.org), then run:"
  warn "  cd ${TARGET} && npx -y ${IMPECCABLE_PKG} skills install --yes"
fi

if [ "${DRY}" -eq 1 ]; then
  echo
  ok "DRY RUN complete — re-run without --dry-run to apply. Verify later with: bash bootstrap.sh ${TARGET} --check"
  exit 0
fi

echo
bold "Done. Three steps left (the human ones):"
cat <<EOS
  1. In Claude Code run /plugin → marketplace "claude-plugins-official" →
     install "superpowers" (one minute, can't be scripted).
  2. Start a FRESH Claude Code session in your project, so the new skills load.
  3. Fill the templates — PRODUCT.md (who/why/brand) and DESIGN.md (the exact
     values). Vague input here is the #1 cause of generic output. Easiest way,
     in that fresh session: run  /impeccable init  — it interviews you, writes
     PRODUCT.md and offers DESIGN.md (say yes), then MERGE its output into the
     kit's template sections (keep Atmosphere / Voice / Banned patterns — the
     design-lint pass checks them). Then verify: ask "Which design skills do
     you have? Read PRODUCT.md and DESIGN.md and tell me what's still a
     placeholder." Fix what it lists.

  Verify the install any time:  bash bootstrap.sh ${TARGET} --check
EOS

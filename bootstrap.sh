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
#   bash bootstrap.sh /path/to/your-project --latest   # un-pinned upstream
#
# Safe: it never clobbers an existing CLAUDE.md / PRODUCT.md / DESIGN.md in
# your project — if one is there, it drops the template next to it as
# `<name>.from-design-kit` for you to merge by hand.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LOCK_FILE="${HERE}/versions.lock"
TARGET="${1:-}"
LATEST_FLAG=""
[ "${2:-}" = "--latest" ] && LATEST_FLAG="--latest"

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

if [ ! -f "${HERE}/install-skills.sh" ] || [ ! -d "${HERE}/template" ]; then
  warn "bootstrap.sh must run from a full clone of the kit:"
  warn "  git clone https://github.com/michaelbrowk/SUPERBROWKY.git"
  exit 1
fi
if [ -z "${TARGET}" ]; then
  echo "Usage: bash bootstrap.sh /path/to/your-project [--latest]"
  exit 1
fi
if [ ! -d "${TARGET}" ]; then
  warn "Not a directory: ${TARGET}"
  exit 1
fi
TARGET="$(cd "${TARGET}" && pwd)"

bold "1/3 · Wiring templates into ${TARGET}"
for f in CLAUDE.md PRODUCT.md DESIGN.md; do
  src="${HERE}/template/${f}"
  dst="${TARGET}/${f}"
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
bash "${HERE}/install-skills.sh" ${LATEST_FLAG:+"${LATEST_FLAG}"}

echo
bold "3/3 · Installing impeccable into ${TARGET}"
IMPECCABLE_VER="$(lock_pin impeccable-cli)"
IMPECCABLE_PKG="impeccable${IMPECCABLE_VER:+@${IMPECCABLE_VER}}"
[ -n "${LATEST_FLAG}" ] && IMPECCABLE_PKG="impeccable"
if command -v npx >/dev/null 2>&1; then
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
EOS

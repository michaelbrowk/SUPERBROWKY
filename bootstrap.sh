#!/usr/bin/env bash
#
# Claude Code Design Kit — one-command setup.
#
# Installs the design skills (via install-skills.sh) AND wires the templates
# into your project, in one go.
#
#   bash bootstrap.sh /path/to/your-project
#
# Safe: it never clobbers an existing CLAUDE.md / .impeccable.md in your
# project — if one is there, it drops the template next to it as
# `<name>.from-design-kit` for you to merge by hand.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-}"

ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
bold() { printf '\033[1m%s\033[0m\n' "$1"; }

if [ -z "${TARGET}" ]; then
  echo "Usage: bash bootstrap.sh /path/to/your-project"
  exit 1
fi
if [ ! -d "${TARGET}" ]; then
  warn "Not a directory: ${TARGET}"
  exit 1
fi
TARGET="$(cd "${TARGET}" && pwd)"

bold "1/2 · Installing design + process skills"
bash "${HERE}/install-skills.sh"

echo
bold "2/2 · Wiring templates into ${TARGET}"
for f in CLAUDE.md .impeccable.md; do
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
ok "Done. Next: fill the placeholders in ${TARGET}/CLAUDE.md and ${TARGET}/.impeccable.md"
echo "       (or just run /impeccable teach in Claude Code and answer the questions)."

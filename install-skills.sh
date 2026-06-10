#!/usr/bin/env bash
#
# Claude Code Design Kit — skill installer.
#
# Installs the DESIGN ENGINE (skills) the kit's templates rely on, by cloning
# the upstream repos into your own ~/.claude/skills/. It does NOT bundle or
# republish anyone's skills — it fetches them from source, so each author keeps
# their license + attribution.
#
# Run once per machine:
#   bash install-skills.sh
#
# Idempotent. Re-running re-syncs the skills to the latest upstream.

set -euo pipefail

SKILLS_DIR="${HOME}/.claude/skills"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }

# Upstream design-skill repos (authoritative sources). Each is cloned and every
# SKILL.md-bearing folder inside it is copied into ~/.claude/skills/.
#   repo URL                                    | what it gives you
REPOS=(
  "https://github.com/pbakaus/impeccable.git"     # impeccable, polish, + the taste suite (Apache 2.0)
  "https://github.com/emilkowalski/skill.git"     # emil-design-eng — motion & polish
  "https://github.com/Leonxlnx/taste-skill.git"   # design-taste-frontend, high-end-visual-design, redesign
)

command -v git >/dev/null 2>&1 || { warn "git is required but not found. Install git and re-run."; exit 1; }
mkdir -p "${SKILLS_DIR}"

bold "Installing design skills into ${SKILLS_DIR}"
for repo in "${REPOS[@]}"; do
  name="$(basename "${repo}" .git)"
  printf '  → %s\n' "${repo}"
  if ! git clone --depth 1 --quiet "${repo}" "${TMP}/${name}" 2>/dev/null; then
    warn "Couldn't clone ${repo} — skipping. (Check the URL / your network and re-run.)"
    continue
  fi
  # Copy every folder that contains a SKILL.md (robust to per-repo layout).
  while IFS= read -r skillmd; do
    folder="$(dirname "${skillmd}")"
    dest="${SKILLS_DIR}/$(basename "${folder}")"
    rm -rf "${dest}"
    cp -R "${folder}" "${dest}"
    ok "$(basename "${folder}")"
  done < <(find "${TMP}/${name}" -name SKILL.md -not -path '*/.git/*')
done

echo
bold "Process skills (superpowers plugin) — one manual step:"
cat <<'EOS'
  In Claude Code, run:   /plugin
  Add the marketplace:   claude-plugins-official   (Anthropic's official marketplace)
  Install:               superpowers
  (Gives you brainstorming, writing-plans, subagent-driven-development — the
   "design before code" + planning discipline the kit's CLAUDE.md leans on.)
EOS

echo
bold "Optional extras (not auto-installed — find + add if you want them):"
cat <<'EOS'
  • stop-slop      — strips AI tells from prose. MIT, Hardik Pandya (hvpandya.com).
  • design-system  — token architecture (primitive→semantic→component). MIT, claudekit.
  • brand          — brand voice / visual identity. claudekit.
EOS

echo
ok "Skills installed. Next: copy template/CLAUDE.md and template/.impeccable.md into your project root."

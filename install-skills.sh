#!/usr/bin/env bash
#
# Claude Code Design Kit — machine-wide skill installer.
#
# Installs into ~/.claude/skills/:
#   • the taste skills the kit's templates rely on — from PINNED, known-good
#     upstream snapshots (fetched from source; nothing is republished, each
#     author keeps their license + attribution)
#   • the SEO skills (seo-audit, ai-seo, schema) — from Corey Haines'
#     MIT-licensed marketingskills repo, same pinning
#   • the kit's own bundled skills (skills/ in this repo — psi-optimize)
#
# NOTE: `impeccable` is NOT installed here. It installs per-project via its
# own official installer — bootstrap.sh runs it for you, or do it yourself:
#   cd your-project && npx -y impeccable@2.3.2 skills install --yes
#
# Run once per machine:
#   bash install-skills.sh             # pinned, verified versions (default)
#   bash install-skills.sh --latest    # live upstream HEAD (may drift/break)
#
# Idempotent. If a skill with the same name already exists, your ORIGINAL copy
# is preserved at ~/.claude/skills-backup/<name> (outside the skills dir, so it
# can't confuse skill routing). Only the first backup is kept — that's your
# pre-kit state; later re-runs just replace the kit-managed copy.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="${HOME}/.claude/skills"
BACKUP_DIR="${HOME}/.claude/skills-backup"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1" >&2; }

REF_MODE="pinned"
if [ "${1:-}" = "--latest" ]; then REF_MODE="latest"; fi

# Manifest: repo | pinned ref | folder in repo | install name (skill frontmatter name)
#
# This is an explicit ALLOWLIST. The upstream repos ship more folders (builds
# for other editors, GPT/Stitch variants, style packs, ~40 marketing skills,
# an output-behavior override) — we install only the skills the kit documents.
# See README "Optional extras" if you want the rest.
MANIFEST=(
  "emilkowalski/skill|ecf66bbd1fb33c25332b6b0e454d08049978284c|skills/emil-design-eng|emil-design-eng"
  "Leonxlnx/taste-skill|1a6dc0a5ac5d0152120938bf66ed67ea2ec8e552|skills/taste-skill|design-taste-frontend"
  "Leonxlnx/taste-skill|1a6dc0a5ac5d0152120938bf66ed67ea2ec8e552|skills/soft-skill|high-end-visual-design"
  "Leonxlnx/taste-skill|1a6dc0a5ac5d0152120938bf66ed67ea2ec8e552|skills/redesign-skill|redesign-existing-projects"
  "coreyhaines31/marketingskills|7f4af1ea8e7809e0142c55bf19243a706f539c25|skills/seo-audit|seo-audit"
  "coreyhaines31/marketingskills|7f4af1ea8e7809e0142c55bf19243a706f539c25|skills/ai-seo|ai-seo"
  "coreyhaines31/marketingskills|7f4af1ea8e7809e0142c55bf19243a706f539c25|skills/schema|schema"
)

# Skills bundled in this repo (the kit author's own work, MIT like the kit).
BUNDLED=(
  "psi-optimize"
)

command -v curl >/dev/null 2>&1 || { warn "curl is required but not found."; exit 1; }
command -v tar  >/dev/null 2>&1 || { warn "tar is required but not found."; exit 1; }
mkdir -p "${SKILLS_DIR}"

INSTALLED=0
FAILED=0
FAILED_NAMES=""

# Copy a skill folder into SKILLS_DIR under $2, preserving any pre-kit
# original at BACKUP_DIR (first backup wins).
install_skill_folder() { # $1=src dir  $2=install name  $3=origin label
  local src="$1" name="$2" origin="$3"
  local dest="${SKILLS_DIR}/${name}"
  if [ ! -f "${src}/SKILL.md" ]; then
    warn "${origin}: no SKILL.md at ${src} (layout changed?) — skipping ${name}."
    warn "  Try '--latest', or report it: https://github.com/michaelbrowk/SUPERBROWKY/issues"
    return 1
  fi
  if [ -e "${dest}" ] || [ -L "${dest}" ]; then
    if [ -L "${dest}" ]; then
      warn "${name} was a symlink to $(readlink "${dest}") — replacing with a real folder; the link target is untouched."
    fi
    if [ ! -e "${BACKUP_DIR}/${name}" ]; then
      mkdir -p "${BACKUP_DIR}"
      mv "${dest}" "${BACKUP_DIR}/${name}"
      warn "${name} already existed — original kept at ~/.claude/skills-backup/${name}"
    else
      rm -rf "${dest}"
    fi
  fi
  cp -R "${src}" "${dest}"
  ok "${name}  (${origin})"
}

# Download each unique repo@ref tarball once, extract to ${TMP}/<key>/<repo-ref>/
# Atomic: extracts to <key>.partial first, so a failed download never leaves a
# poisoned cache dir for the next manifest entry from the same repo.
fetch_repo() { # $1=owner/repo  $2=ref   → echoes extracted root dir
  local repo="$1" ref="$2"
  local key; key="$(printf '%s@%s' "${repo}" "${ref}" | tr '/@' '__')"
  local dir="${TMP}/${key}"
  if [ ! -d "${dir}" ]; then
    rm -rf "${dir}.partial"
    mkdir -p "${dir}.partial"
    if ! curl -fsSL "https://codeload.github.com/${repo}/tar.gz/${ref}" | tar -xz -C "${dir}.partial"; then
      warn "Couldn't download ${repo}@${ref} — check the URL / your network."
      rm -rf "${dir}.partial"
      return 1
    fi
    mv "${dir}.partial" "${dir}"
  fi
  # The tarball extracts to a single top-level folder; find it.
  find "${dir}" -mindepth 1 -maxdepth 1 -type d | head -n 1
}

bold "Installing design + SEO skills into ${SKILLS_DIR} (${REF_MODE} versions)"
for entry in "${MANIFEST[@]}"; do
  IFS='|' read -r repo pin folder name <<< "${entry}"
  ref="${pin}"
  if [ "${REF_MODE}" = "latest" ]; then ref="HEAD"; fi
  if ! root="$(fetch_repo "${repo}" "${ref}")" || [ -z "${root}" ]; then
    FAILED=$((FAILED+1)); FAILED_NAMES="${FAILED_NAMES} ${name}"
    continue
  fi
  if install_skill_folder "${root}/${folder}" "${name}" "${repo} @ ${ref:0:7}"; then
    INSTALLED=$((INSTALLED+1))
  else
    FAILED=$((FAILED+1)); FAILED_NAMES="${FAILED_NAMES} ${name}"
  fi
done

for name in "${BUNDLED[@]}"; do
  if install_skill_folder "${HERE}/skills/${name}" "${name}" "bundled with this kit"; then
    INSTALLED=$((INSTALLED+1))
  else
    FAILED=$((FAILED+1)); FAILED_NAMES="${FAILED_NAMES} ${name}"
  fi
done

echo
if [ "${INSTALLED}" -eq 0 ]; then
  warn "Nothing was installed — every skill failed (network?). Fix the issue and re-run."
  exit 1
elif [ "${FAILED}" -gt 0 ]; then
  warn "Installed ${INSTALLED} skills, but these failed:${FAILED_NAMES}. Re-run to retry."
else
  ok "All ${INSTALLED} machine-wide skills installed."
fi

echo
bold "Per-project skill (impeccable) — the taste engine's core:"
cat <<'EOS'
  Installed into EACH project (not machine-wide) by its official installer:
    cd /path/to/your-project && npx -y impeccable@2.3.2 skills install --yes
  bootstrap.sh does this for you. Requires Node.js 24+ (it also powers the
  skill's context scripts). Alternative, inside Claude Code:
    /plugin marketplace add pbakaus/impeccable
EOS

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
bold "Optional extras (not auto-installed — see README for the full list):"
cat <<'EOS'
  • stop-slop                 — strips AI tells from prose. MIT, Hardik Pandya,
                                github.com/hardikpandya/stop-slop
  • programmatic-seo,         — more from Corey Haines' MIT marketingskills
    site-architecture, cro      repo (add the folders to the manifest)
  • minimalist-ui /           — opinionated style packs from Leonxlnx/taste-skill
    industrial-brutalist-ui     (re-run with the folders added to the manifest)
  • gstack design suite       — /design-review, /design-shotgun. MIT, Garry Tan.
EOS

echo
bold "Next (if you're doing the manual path):"
echo "  cd /path/to/your-project && npx -y impeccable@2.3.2 skills install --yes"
echo "  then copy the three templates from template/ into your project root."
echo "  (Or just run: bash bootstrap.sh /path/to/your-project — it does both.)"

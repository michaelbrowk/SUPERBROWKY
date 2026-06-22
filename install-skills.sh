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
# own official installer — bootstrap.sh runs it for you, or do it yourself
# (version pinned in versions.lock as impeccable-cli):
#   cd your-project && npx -y impeccable@<version> skills install --yes
#
# Versions are pinned in `versions.lock` (one place to edit). This script
# resolves each skill's commit and the impeccable CLI version from there.
#
# Run once per machine:
#   bash install-skills.sh             # pinned, verified versions (default)
#   bash install-skills.sh --latest    # live upstream HEAD (may drift/break)
#   bash install-skills.sh --check-updates  # report upstream drift, edit nothing
#
# Idempotent. If a skill with the same name already exists, your ORIGINAL copy
# is preserved at ~/.claude/skills-backup/<name> (outside the skills dir, so it
# can't confuse skill routing). Only the first backup is kept — that's your
# pre-kit state; later re-runs just replace the kit-managed copy.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="${HOME}/.claude/skills"
BACKUP_DIR="${HOME}/.claude/skills-backup"
LOCK_FILE="${HERE}/versions.lock"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1" >&2; }

# Resolve a pinned value from versions.lock by key (e.g. owner/repo, or
# impeccable-cli). Echoes the value, or nothing if the key is absent.
lock_pin() { # $1=key
  [ -f "${LOCK_FILE}" ] || return 0
  local k v
  while IFS='=' read -r k v; do
    case "${k}" in \#*|'') continue ;; esac
    if [ "${k}" = "$1" ]; then printf '%s' "${v}"; return 0; fi
  done < "${LOCK_FILE}"
}

REF_MODE="pinned"
MODE="install"
case "${1:-}" in
  --latest)        REF_MODE="latest" ;;
  --check-updates) MODE="check-updates" ;;
esac

IMPECCABLE_VER="$(lock_pin impeccable-cli)"
IMPECCABLE_PKG="impeccable${IMPECCABLE_VER:+@${IMPECCABLE_VER}}"

# Manifest: repo | folder in repo | install name (skill frontmatter name)
# The pinned commit for each repo is resolved from versions.lock at runtime.
#
# This is an explicit ALLOWLIST. The upstream repos ship more folders (builds
# for other editors, GPT/Stitch variants, style packs, ~40 marketing skills,
# an output-behavior override) — we install only the skills the kit documents.
# See README "Optional extras" if you want the rest.
MANIFEST=(
  # Taste engine
  "emilkowalski/skill|skills/emil-design-eng|emil-design-eng"
  "Leonxlnx/taste-skill|skills/taste-skill|design-taste-frontend"
  "Leonxlnx/taste-skill|skills/soft-skill|high-end-visual-design"
  "Leonxlnx/taste-skill|skills/redesign-skill|redesign-existing-projects"
  # Ship-clean — findability (SEO) + prose
  "coreyhaines31/marketingskills|skills/seo-audit|seo-audit"
  "coreyhaines31/marketingskills|skills/ai-seo|ai-seo"
  "coreyhaines31/marketingskills|skills/schema|schema"
  "coreyhaines31/marketingskills|skills/programmatic-seo|programmatic-seo"
  "coreyhaines31/marketingskills|skills/site-architecture|site-architecture"
  "coreyhaines31/marketingskills|skills/cro|cro"
  "hardikpandya/stop-slop|.|stop-slop"
)

# Skills bundled in this repo (the kit author's own work, MIT like the kit).
# Ship-clean — performance, accessibility, pre-ship meta.
BUNDLED=(
  "psi-optimize"
  "a11y-audit"
  "meta-audit"
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

# Report upstream drift vs versions.lock. Read-only: prints the lines to paste
# into versions.lock, changes nothing. Uses git ls-remote (no token, no jq).
check_updates() {
  command -v git >/dev/null 2>&1 || { warn "git is required for --check-updates."; exit 1; }
  bold "Checking upstream drift against versions.lock (read-only)"
  local drift=0 seen="" repo locked latest
  for entry in "${MANIFEST[@]}"; do
    IFS='|' read -r repo _ _ <<< "${entry}"
    case " ${seen} " in *" ${repo} "*) continue ;; esac
    seen="${seen} ${repo}"
    locked="$(lock_pin "${repo}")"
    latest="$(git ls-remote "https://github.com/${repo}.git" HEAD 2>/dev/null | awk 'NR==1{print $1}')"
    if [ -z "${latest}" ]; then warn "${repo}: couldn't reach upstream — skipped."; continue; fi
    if [ "${locked}" = "${latest}" ]; then
      ok "${repo}  current (${locked:0:7})"
    else
      drift=$((drift+1))
      warn "${repo}  stale: ${locked:0:7} → ${latest:0:7}"
      printf '    %s=%s\n' "${repo}" "${latest}"
    fi
  done
  locked="$(lock_pin impeccable-cli)"
  if command -v npm >/dev/null 2>&1; then
    latest="$(npm view impeccable version 2>/dev/null)"
    if [ -n "${latest}" ] && [ "${latest}" != "${locked}" ]; then
      drift=$((drift+1))
      warn "impeccable-cli  stale: ${locked} → ${latest}"
      printf '    impeccable-cli=%s\n' "${latest}"
    else
      ok "impeccable-cli  current (${locked})"
    fi
  else
    warn "npm not found — skipped impeccable-cli check."
  fi
  echo
  if [ "${drift}" -eq 0 ]; then
    ok "All pins current."
  else
    bold "${drift} update(s) available — paste the lines above into versions.lock, then re-run install-skills.sh."
  fi
}

if [ "${MODE}" = "check-updates" ]; then check_updates; exit 0; fi

bold "Installing design + SEO skills into ${SKILLS_DIR} (${REF_MODE} versions)"
for entry in "${MANIFEST[@]}"; do
  IFS='|' read -r repo folder name <<< "${entry}"
  if [ "${REF_MODE}" = "latest" ]; then
    ref="HEAD"
  else
    ref="$(lock_pin "${repo}")"
    if [ -z "${ref}" ]; then
      warn "No pin for ${repo} in versions.lock — skipping ${name}. Add it, or use --latest."
      FAILED=$((FAILED+1)); FAILED_NAMES="${FAILED_NAMES} ${name}"
      continue
    fi
  fi
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
cat <<EOS
  Installed into EACH project (not machine-wide) by its official installer:
    cd /path/to/your-project && npx -y ${IMPECCABLE_PKG} skills install --yes
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
  • minimalist-ui /           — opinionated style packs from Leonxlnx/taste-skill
    industrial-brutalist-ui     (re-run with the folders added to the manifest)
  • gstack design suite       — /design-review, /design-shotgun. MIT, Garry Tan.
EOS

echo
bold "Next (if you're doing the manual path):"
echo "  cd /path/to/your-project && npx -y ${IMPECCABLE_PKG} skills install --yes"
echo "  then copy the three templates from template/ into your project root."
echo "  (Or just run: bash bootstrap.sh /path/to/your-project — it does both.)"

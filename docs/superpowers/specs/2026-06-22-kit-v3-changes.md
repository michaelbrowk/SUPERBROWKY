# Kit v3 — harden the installer + expand ship-clean

**Author:** Misha (with Claude). **Date:** 2026-06-22.

Five improvements to the v2 kit. Context: the kit worked but had rough edges
(scattered pins, no preview/verify, no CI) and the ship-clean layer only
covered perf + SEO.

## Decisions

1. **`versions.lock` is the single source of truth.** Pins were inline in the
   manifest and hard-coded across heredocs. Now one `KEY=VALUE` file; both
   scripts resolve at runtime via a small `lock_pin()` (no jq). Keys are repo
   slugs + `impeccable-cli`. `--latest` still overrides to HEAD.

2. **`--check-updates`** (install-skills.sh): read-only drift report via
   `git ls-remote` (no token/jq) + `npm view impeccable`. Prints the exact
   lines to paste. Pins are deliberate — never auto-bump (an impeccable rewrite
   once broke the kit; `--check-updates` already shows 2.3.2 → 3.x as drift).

3. **`--dry-run`** (both scripts) and **`bootstrap.sh --check`** doctor.
   Arg parsing refactored to a flag loop. Dry-run touches nothing; doctor
   verifies templates + machine skills + project impeccable + node. Doctor's
   expected-skills list is **parsed from the manifest** so it can't drift.

4. **Ship-clean expanded from 2 pillars to 4.** Decided: a page can be
   beautiful, fast, and found and still fail if unusable or its share preview is
   blank.
   - Two new **bundled** skills (kit's own, MIT, psi-optimize shape): `a11y-audit`
     (WCAG 2.1 AA audit+fix, ships `contrast-check.mjs`) and `meta-audit`
     (pre-ship `<head>` + robots/sitemap check, ships `meta-scan.mjs`). Both
     scripts are pure Node, zero deps, non-zero exit on failure (CI-gateable).
   - **Graduated** into the core manifest from "optional extras": `stop-slop`
     (prose; SKILL.md at repo root → folder `.`) and the marketingskills
     `programmatic-seo` / `site-architecture` / `cro` (reuse the existing pin).
   - Manifest is now 11 upstream + 3 bundled = 14 machine-wide.

5. **`CONTRIBUTING.md` + CI.** `.github/workflows/ci.yml`: shellcheck + syntax
   + offline dry-run smoke (the gate) + an informational real-install job
   (continue-on-error — upstream-dependent). CONTRIBUTING documents the dev
   loop, pin bumps, adding skills, and the routing-curation rule. Deferred ideas
   tracked as GitHub issues.

## Non-goals / honest notes

- Still no Windows/PowerShell parity (Git Bash/WSL only) — filed as an issue.
- Routing collision risk grows with the manifest; mitigated by keeping domains
  distinct and `impeccable` declared primary (noted in README + CONTRIBUTING).
- Licensing rule unchanged: upstream skills are installed from source, never
  vendored or relicensed.

# Contributing

This is a small, opinionated kit. The point is taste and discipline, not size —
keep additions curated. PRs welcome; the bar is "does this make the default
output better without bloating the install."

## Dev loop

Never commit to `main` directly.

```bash
git checkout -b feat/<short-name>
# ... change ...
bash -n bootstrap.sh install-skills.sh        # syntax
bash install-skills.sh --dry-run              # preview, downloads nothing
git commit -m "feat: <what changed and why>"
git push -u origin feat/<short-name>
gh pr create --fill
gh pr merge <num> --merge --delete-branch     # merge-commit style
```

CI (`.github/workflows/ci.yml`) runs shellcheck + syntax + a dry-run smoke on
every push; the real-install job is informational (it depends on third-party
upstreams, so it never blocks a merge).

## Bumping a pinned version

All pins live in **`versions.lock`** — one place. Don't hard-code versions in
the scripts.

```bash
bash install-skills.sh --check-updates   # prints the exact lines to paste
```

It compares each locked commit against upstream `HEAD` (`git ls-remote`) and the
`impeccable-cli` value against npm, then prints the new `versions.lock` lines.
Paste the ones you want — and **re-run a real install to confirm the new commit
still has the expected folder layout** before committing the bump. Pins exist
because upstream repos change shape (an `impeccable` rewrite once silently broke
the kit); bump deliberately, not reflexively.

## Adding an upstream skill to the core install

1. Add a pin for the repo in `versions.lock` (if it's a new repo):
   `owner/name=<commit-sha>`.
2. Add a row to `MANIFEST` in `install-skills.sh`:
   `"owner/name|<folder-in-repo>|<install-name>"`. The install name should match
   the skill's frontmatter `name`. If `SKILL.md` is at the repo root, use `.`
   as the folder.
3. Add a row to the skills table in `README.md` (with source + license) and a
   trigger row in `template/CLAUDE.md`.
4. Verify: `bash install-skills.sh --dry-run` lists it, then a real install into
   a scratch `HOME` lands its `SKILL.md`.

**Licensing:** the kit installs upstream skills from source — it never bundles
or relicenses them. Only add repos with a clear license, or no license but
fetched-from-source (credit stays with the author). Don't vendor third-party
skill content into this repo.

## Adding a bundled skill (the kit's own work, MIT)

1. Create `skills/<name>/SKILL.md` with frontmatter
   (`name`, `description`, `user-invocable`, `argument-hint`) — match the shape
   of `skills/psi-optimize/SKILL.md`. Put longer material in
   `references/` and any tooling in `scripts/` (pure Node, zero deps, with a
   `--dry`/preview mode and a non-zero exit on failure so CI can gate on it).
2. Add `"<name>"` to the `BUNDLED` array in `install-skills.sh`.
3. Add it to the `README.md` skills table and `template/CLAUDE.md` trigger table.
4. The `--check` doctor and the CI install job pick it up automatically (they
   parse the manifest), so no extra wiring.

## Curation discipline

Skills route by description matching. Don't stack many general-purpose design
engines — `impeccable` is the primary; the others sharpen it. New skills should
own a **distinct domain** (a11y, meta, perf, SEO, prose) or refine an existing
one, not compete for the same triggers. If two skills overlap, say which is
primary in `template/CLAUDE.md`.

## Cross-platform parity

The kit ships bash (`*.sh`) and PowerShell (`*.ps1`) installers with the same
flags and the same `versions.lock`. **Any change to a `.sh` script must be
mirrored in its `.ps1` twin** (manifest rows, flags, behavior). CI parses the
`.ps1` files and runs their dry-run on `windows-latest`, so a missing mirror or
a PowerShell syntax error fails the build. When you add a skill, add it to both
`install-skills.sh`'s `MANIFEST`/`BUNDLED` and `install-skills.ps1`'s
`$Manifest`/`$Bundled`.

## House conventions

- UI/microcopy in the templates: no trailing periods on headings or
  single-sentence subheads; prefer tokens/components over raw values (the kit
  preaches this — practice it).
- Commit messages and PR text in English; explain the *why*, not just the what.

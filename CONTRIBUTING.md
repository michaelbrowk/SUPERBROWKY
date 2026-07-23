# Contributing

SUPERBROWKY stays useful by remaining small, deterministic, and honest. A new
skill or rule must improve a representative task without widening permissions
or creating routing conflicts.

## Branch and local checks

```bash
git switch -c feat/<short-name>

bash -n bootstrap.sh install-skills.sh scripts/*.sh
shellcheck bootstrap.sh install-skills.sh scripts/*.sh
python3 scripts/validate-manifest.py
python3 scripts/validate-skills.py
for file in skills/*/scripts/*.mjs; do node --check "$file"; done
git diff --check
```

Run a read-only smoke test:

```bash
project="$(mktemp -d)"
bash bootstrap.sh "$project" --harness both --profile core
test -z "$(find "$project" -mindepth 1 -print -quit)"
```

The lifecycle tests create their own temporary fake home and never target your
real harness directories:

```bash
bash tests/lifecycle.sh
pwsh -File tests/lifecycle.ps1
```

They intentionally replace and remove files only inside that generated test
home. Never override their environment to point at real `~/.claude`,
`~/.codex`, or `~/.superbrowky` directories.

## Single sources of truth

- `manifests/skills.tsv` — allowlist, profiles, source folders, license status;
- `versions.lock` — exact upstream commits;
- `template/HARNESS.md` — platform-neutral operating contract;
- `template/CLAUDE.md` and `template/AGENTS.md` — thin adapters only;
- receipts — installed ownership and content hashes.

Do not add a second hard-coded skill list to a shell, PowerShell, doctor, or
README file.

## Adding or updating a third-party skill

1. Choose a release or exact 40-character commit.
2. Inspect the selected directory and every bundled script.
3. Check:
   - `SKILL.md` frontmatter and activation scope;
   - local links and required files;
   - hard-coded harness paths and unsupported tools;
   - network, package-install, credential, destructive, publish, and spend
     instructions;
   - license and attribution;
   - overlap with the primary UI engine.
4. Add it to the narrowest optional profile. A broad design engine does not
   belong in `core` without evidence.
5. Update `versions.lock`, `manifests/skills.tsv`, and
   `THIRD_PARTY_SKILLS.md` together.
6. Run install → doctor → reinstall → drift refusal → uninstall → backup
   restoration in an isolated home.

Never point an installed skill at an unpinned `main` branch. `--latest` is for
read-only inspection, not application.

## Modifying an upstream skill

Make local adaptation visible:

- keep the upstream source and commit in the manifest/receipt;
- retain the upstream license and notice inside the installed package;
- place reviewed text under `overlays/`;
- version the overlay;
- hash the transformed tree, not the pre-transform download;
- describe the changes in `THIRD_PARTY_SKILLS.md`.

Do not present a derivative as byte-identical upstream content or as upstream
endorsement.

## Harness rules

State each shared rule once in `HARNESS.md`. Keep the adapters short. A rule
that encodes one person's feedback needs an Evolve proposal and a before/after
evaluation before it becomes global.

Automated reviewers may return `READY_FOR_HUMAN_REVIEW`; only a human can
accept direction or release.

## Pull-request evidence

Include:

- the user problem and smallest intended change;
- files and profiles affected;
- isolated test commands and results;
- migration or uninstall impact;
- any third-party source, license, or behavior change;
- remaining platform caveats.

Green syntax alone is not enough for installer changes.

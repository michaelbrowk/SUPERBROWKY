# Migrating from v3 to v4

v4 intentionally changes the safety model. Nothing is migrated or deleted at
session start.

## What you will notice

- Running `bootstrap` without `--apply` now prints a plan and writes nothing.
- The default `core` profile is smaller than the old all-in install.
- Codex uses `AGENTS.md` and `~/.codex/skills`; Claude Code uses `CLAUDE.md`
  and `~/.claude/skills`.
- `HARNESS.md` is the shared operating contract; `PROJECT.md` maps runtime
  commands, implementation sources, and any explicitly scoped contexts.
- `impeccable` comes from a pinned Git commit instead of a live npm installer.
- v4 records exact ownership receipts under `~/.superbrowky` and the project
  `.superbrowky` directory.

## First v4 plan

```bash
bash bootstrap.sh /path/to/project --harness claude --profile core
```

Existing v3 skills have no v4 receipt, so the plan reports them as
pre-existing conflicts. Review the source and destination paths. If you apply,
v4 makes a timestamped backup before installing the pinned copy and records
that backup in the receipt.

Existing project files are never overwritten. v4 writes content-addressed
`.from-superbrowky-v4-*` merge candidates beside them.

## Removal

The v4 uninstaller refuses to remove a directory without a v4 receipt. This is
deliberate: it cannot prove that a legacy same-named skill belongs to the kit.

Old `~/.claude/skills-backup/` content is left untouched. Review and remove it
manually only when you are certain it is no longer needed.

## Context migration

Use `PRODUCT.md` and `DESIGN.md` as the default canonical contexts. If a
monorepo truly needs a different context for a surface, name and map it
explicitly in `PROJECT.md`; keep only the differences in that scoped file.
Merge accepted local rules from the old `CLAUDE.md` into `HARNESS.md`,
`PROJECT.md`, `PRODUCT.md`, or `DESIGN.md` according to their role. Raw
corrections belong in `Feedback.md`; accepted project decisions belong in
`Decision.md`.

Do not promote old lessons into the shared harness automatically. Propose the
exact diff and obtain human approval first.

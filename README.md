# SUPERBROWKY

[![CI](https://github.com/michaelbrowk/SUPERBROWKY/actions/workflows/ci.yml/badge.svg)](https://github.com/michaelbrowk/SUPERBROWKY/actions/workflows/ci.yml)

A portable product UI and web-design harness for **Claude Code and Codex**. It
gives both tools the same project context, one primary UI engine, a small set
of specialist skills, human approval boundaries, and verifiable installation
state.

Start with [START-HERE.md](START-HERE.md) if you only need the commands.

## What changed in v4

The installer now behaves like a careful teammate:

- its default action is a read-only plan;
- `--apply` / `-Apply` is required for downloads or writes;
- Claude Code, Codex, or both can use one shared project harness;
- the default profile is deliberately small;
- external skills come from exact pinned commits, including `impeccable`;
- every managed skill has a receipt with its source, commit, hash, and backup;
- reinstall refuses to overwrite a managed skill that the user changed;
- uninstall removes only unchanged files proved to be owned by SUPERBROWKY;
- doctor returns `READY`, `PARTIAL`, or `BLOCKED`;
- a shareable audit bundle can be generated without chat history or
  secrets.

There is no live `npx -y` installer in the bootstrap path.
Existing users: see [Migrating from v3 to v4](docs/MIGRATION-v3-v4.md).

## Quick start — macOS / Linux

```bash
git clone https://github.com/michaelbrowk/SUPERBROWKY.git
cd SUPERBROWKY

# 1. Read-only plan: no downloads, no writes
bash bootstrap.sh /path/to/project --harness auto --profile core

# 2. Apply only after reviewing that plan
bash bootstrap.sh /path/to/project --harness auto --profile core --apply

# 3. Re-check at any time
bash bootstrap.sh /path/to/project --harness auto --profile core --check
```

Then open a **fresh Claude Code session or Codex task** in the project so it
rediscovers the new skills. Fill the remaining `PROJECT.md`, `PRODUCT.md`,
`DESIGN.md`, and adapter placeholders with the agent. Product and design
context remains `DRAFT_PROPOSAL` until the human accepts the exact versions
and the matching decision is recorded.

## Quick start — Windows PowerShell

```powershell
git clone https://github.com/michaelbrowk/SUPERBROWKY.git
cd SUPERBROWKY

# Plan
pwsh -File bootstrap.ps1 C:\path\to\project -Harness auto -Profile core

# Apply
pwsh -File bootstrap.ps1 C:\path\to\project -Harness auto -Profile core -Apply

# Check
pwsh -File bootstrap.ps1 C:\path\to\project -Harness auto -Profile core -Check
```

PowerShell 7+ is required for the native Windows path. Git Bash or WSL users
may use the Bash commands.

## If you are Claude Code or Codex

When a user asks you to install this repository:

1. Clone it into a temporary folder.
2. Run `bootstrap` **without** `--apply`.
3. Show the user:
   - detected harnesses;
   - chosen profile;
   - project and global destination paths;
   - existing-file conflicts;
   - remote sources and pinned commits.
4. Ask for confirmation.
5. Run the same command with `--apply` only after confirmation.
6. Run `--check` and report its exact status.
7. Ask the user to open a fresh session/task.

Do not interpret “install this” as permission to add unrelated plugins, MCP
servers, packages, agents, or credentials.

## Profiles

Profiles are cumulative. Start with `core`; add more only when the work needs
it.

| Profile | Adds | Intended use |
|---|---|---|
| `core` | `impeccable`, `design-taste-frontend`, `emil-design-eng`, `stop-slop`, `a11y-audit`, `psi-optimize`, `meta-audit` | Product UI and normal web work |
| `web-launch` | core + `seo-audit`, `schema`, `site-architecture` | A public site approaching launch |
| `growth` | core + web-launch + `ai-seo`, `programmatic-seo`, `cro` | An explicit acquisition/growth task |
| `full` | everything above + `high-end-visual-design`, `redesign-existing-projects` | Experimental opt-in; not a sensible default |

`impeccable` is the primary UI engine. Other skills own distinct jobs or act
as explicit lenses; they do not vote on, approve, or replace the human's
direction.

## Harness selection

Use `--harness auto`, `claude`, `codex`, or `both`.

- Claude skills: `${CLAUDE_HOME:-~/.claude}/skills`
- Codex skills: `${CODEX_HOME:-~/.codex}/skills`
- Installer state: `${SUPERBROWKY_STATE_HOME:-~/.superbrowky}`

When `auto` cannot detect either runtime, it stops and asks for an explicit
choice. It never guesses by creating both global directories.

## Project files

The platform-neutral core is:

- `HARNESS.md` — workflow, action boundaries, skill routing, review semantics;
- `PROJECT.md` — runtime commands, implementation sources, surfaces, and
  scoped context mapping;
- `PRODUCT.md` — versioned audience, purpose, personality, and principles;
- `DESIGN.md` — versioned tokens, type, components, motion, and constraints;
- `Decision.md` — accepted project decisions and authorization boundaries;
- `Feedback.md` — literal human corrections and local lessons.

Thin adapters keep the core portable:

- `CLAUDE.md` for Claude Code;
- `AGENTS.md` for Codex.

If a destination already exists, SUPERBROWKY preserves it and writes a
content-addressed merge candidate such as
`AGENTS.md.from-superbrowky-v4-1a2b3c4d5e6f`. It never overwrites an earlier
candidate.

After the human accepts the exact merge, record the candidate filename and
SHA-256 in `Decision.md`. Merge its content into the canonical file, append:

```text
<!-- SUPERBROWKY-MERGED: template/AGENTS.md sha256:<full candidate hash> -->
```

Then remove that candidate and run `--check`. A missing candidate without the
matching marker remains `PARTIAL`; deletion alone is never treated as a
successful merge. The marker proves which package was merged, but does not
replace the human decision.

## Status and audit

```bash
# Installation + project-context doctor
bash bootstrap.sh /path/to/project --harness both --profile core --check

# Write a shareable report under AuditBundles/
# Preview first, then create it explicitly
bash bootstrap.sh /path/to/project --harness both --profile core --audit-bundle
bash bootstrap.sh /path/to/project --harness both --profile core --audit-bundle --apply
```

- `READY` — managed skills match receipts, merge candidates are resolved, and
  required project context has human-linked `ACCEPTED` status.
- `PARTIAL` — install is intact, but onboarding, Node helpers, a merge, or
  another non-destructive follow-up remains.
- `BLOCKED` — a required skill/file is absent, invalid, or differs from managed
  state in a way the installer cannot safely resolve.

The generated `SUPERBROWKY-Audit-*.md` includes versions, hashes, conflicts,
and doctor status. It does not include the full chat, hidden reasoning, tokens,
cookies, credentials, or file contents.

## Safe update and removal

Preview upstream drift:

```bash
bash install-skills.sh --check-updates
```

Update only after reviewing the changed skill directory and bumping its exact
commit in `versions.lock`. The repository intentionally does not auto-update
skills at session start.

Remove a project harness:

```bash
# Plan first
bash bootstrap.sh /path/to/project --harness both --profile core --uninstall

# Apply
bash bootstrap.sh /path/to/project --harness both --profile core --uninstall --apply
```

This does **not** remove global skills because other projects may use them.
Remove global skills separately:

```bash
bash install-skills.sh --uninstall --harness both
bash install-skills.sh --uninstall --harness both --apply
```

No receipt means no removal. If a managed file was edited after installation,
uninstall preserves it and returns `PARTIAL`.

## Requirements

- `git`, `curl`, `tar`;
- a SHA-256 command available on the OS;
- Node.js 22+ is required when applying a profile that contains JavaScript
  helpers, including `core`; it is not required to preview the plan;
- PowerShell 7+ for native Windows installation.

Optional Claude Code plugins such as `superpowers` may improve planning, but
the fallback flow in `HARNESS.md` works without them. The bootstrap never
installs optional plugins or MCP servers.

## Security and reproducibility

`manifests/skills.tsv` is the single allowlist for Bash and PowerShell.
`versions.lock` contains exact upstream commits. Before any live replacement,
the installer downloads into staging, validates the selected skill packages,
adds the reviewed third-party safety overlay, computes transformed tree
hashes, and then performs the managed swap.

The receipt is the ownership boundary. It prevents these failure modes:

- a future manifest silently deleting an old user skill;
- reinstall overwriting a locally edited skill;
- partial downloads being presented as success;
- an uninstaller removing a same-named directory it never installed.

See [THIRD_PARTY_SKILLS.md](THIRD_PARTY_SKILLS.md) for provenance, licenses,
review boundaries, and the pin-update procedure.

## Why the harness is separate from skills

Skills provide craft knowledge. They do not know the user's brand, current
scope, accepted direction, or authorization boundaries. The shared harness
supplies that missing operating system:

```text
context → evidence → options → human direction → implementation
        → rendered verification → human release decision
```

Automated reviewers return `READY_FOR_HUMAN_REVIEW` or `NOT_READY`. Passing
tests, a clean screenshot, or successful generation is evidence, never final
approval.

## Development

Run the local checks before proposing a change:

```bash
bash -n bootstrap.sh install-skills.sh scripts/*.sh
python3 scripts/validate-manifest.py
python3 scripts/validate-skills.py
for file in skills/*/scripts/*.mjs; do node --check "$file"; done
git diff --check
```

CI also exercises plan mode, isolated fake-home installation, reinstall,
doctor, collision handling, safe uninstall, and PowerShell parity.

## License

SUPERBROWKY's own scripts, templates, bundled skills, and documentation are
MIT — see [LICENSE](LICENSE). Downloaded skills retain their upstream
licenses and attribution.

# Start here

SUPERBROWKY v4.1 installs a small, reviewed design-skill profile and the same
project harness for Claude Code and Codex.

## If you are an AI agent

1. Clone this repository to a temporary folder.
2. Run a read-only plan:

   ```bash
   bash bootstrap.sh /path/to/project --harness auto --profile core
   ```

3. Show the user the detected harnesses, skill profile, destination paths,
   conflicts, and remote sources.
4. Check whether existing user authorization covers that scope and those
   destinations. Ask only for approval that is still missing.
5. Within that authorization, run the same command with `--apply`.
6. Run `--check`, report `READY`, `PARTIAL`, or `BLOCKED`, then ask the user to
   start a fresh Claude Code session or Codex task.

Never turn the plan into writes without applicable user authorization.

## If you are installing it yourself

```bash
git clone https://github.com/michaelbrowk/SUPERBROWKY.git
cd SUPERBROWKY

# Preview: no downloads and no writes
bash bootstrap.sh /path/to/project --harness auto --profile core

# Apply the exact plan
bash bootstrap.sh /path/to/project --harness auto --profile core --apply
```

Then open a fresh AI session in the project and fill the remaining
`PROJECT.md`, `PRODUCT.md`, `DESIGN.md`, and adapter placeholders with the
agent. Product and design context stays `DRAFT_PROPOSAL` until you accept the
exact versions and the agent records the matching decision.

Existing v4 users: [v4.1 migration](docs/MIGRATION-v4-v4.1.md). The four surface
modes are Operate, Read, Persuade, and Experience; map them in `PROJECT.md`.
Impeccable's craft guides work without its optional native runtime, which this
package does not install. A narrow edit can use existing project evidence
without starting an onboarding interview.

Full commands, profiles, safety model, updates, and removal:
[README.md](README.md).

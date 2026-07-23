# Start here

SUPERBROWKY installs a small, reviewed design-skill profile and the same
project harness for Claude Code and Codex.

## If you are an AI agent

1. Clone this repository to a temporary folder.
2. Run a read-only plan:

   ```bash
   bash bootstrap.sh /path/to/project --harness auto --profile core
   ```

3. Show the user the detected harnesses, skill profile, destination paths,
   conflicts, and remote sources.
4. Ask for confirmation.
5. Only after confirmation, run the same command with `--apply`.
6. Run `--check`, report `READY`, `PARTIAL`, or `BLOCKED`, then ask the user to
   start a fresh Claude Code session or Codex task.

Never turn the plan into writes without the user's confirmation.

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

Full commands, profiles, safety model, updates, and removal:
[README.md](README.md).

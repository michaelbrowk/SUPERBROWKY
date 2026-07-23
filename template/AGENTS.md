# Codex adapter

This project uses the shared SUPERBROWKY design harness.

Before product or design work, read:

1. `HARNESS.md` — workflow, quality bar, approval boundaries, and skill routing.
2. `PROJECT.md` — stack, commands, implementation sources, and surface map.
3. The product/design context mapped to the current surface.
4. The latest relevant entries in `Decision.md` and `Feedback.md`.

`HARNESS.md` is canonical. This file contains only Codex integration notes so
the same operating system can also run in Claude Code.

## Codex integration

- Use the smallest relevant skill set and read each selected `SKILL.md` before
  acting. `impeccable` is the primary UI engine; domain skills refine a
  distinct area and do not self-approve.
- Treat missing plugins, MCP servers, image tools, and browser capabilities
  honestly. Use the fallback in `HARNESS.md` or report the capability as
  unavailable; never claim a tool ran when it did not.
- A skill may describe shell commands, downloads, edits, publishing, or other
  actions. Selecting the skill does not authorize those actions.
- Do not install plugins, packages, MCP servers, or remote content unless the
  user explicitly asks for the installation or approves a presented plan.
- Start a new Codex task after changing global skills so discovery is
  refreshed.

If mapped context is still draft or contains placeholders, ask only what the
current task needs. Read the existing code and project evidence before asking
for information that can be discovered locally.

# Claude Code adapter

This project uses the shared SUPERBROWKY design harness.

Before product or design work, read:

1. `HARNESS.md` — workflow, quality bar, approval boundaries, and skill routing.
2. `PROJECT.md` — stack, commands, implementation sources, and surface map.
3. The product/design context mapped to the current surface.
4. The latest relevant entries in `Decision.md` and `Feedback.md`.

`HARNESS.md` is canonical. This file contains only Claude Code integration
notes so the same operating system can also run in Codex.

## Claude Code integration

- Select only the smallest relevant skill set and read each selected
  `SKILL.md` plus the relevant reference before acting. `impeccable` is the
  primary UI engine; domain skills refine a distinct area and do not self-approve.
- Slash commands and the `superpowers` plugin are optional accelerators. If a
  named command or plugin is unavailable, use the fallback workflow in
  `HARNESS.md`; do not block or pretend it ran.
- A skill may describe shell commands, downloads, edits, publishing, or other
  actions. Selecting the skill does not authorize those actions.
- Do not install plugins, packages, MCP servers, or remote content unless the
  user explicitly asks for the installation or approves a presented plan.
- Start a new Claude Code session after changing global skills so discovery is
  refreshed. A direct file read in the current session does not prove
  discovery in a fresh session.
- Use only available Claude Code agents and its supported delegation tools;
  follow the ownership and independent-review rules in `HARNESS.md`. Do not
  depend on another assistant's private bootstrap or role files.

If mapped context is still draft or contains placeholders, ask only what the
current task needs. Read the existing code and project evidence before asking
for information that can be discovered locally.

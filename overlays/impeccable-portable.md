## SUPERBROWKY portable contract

This reviewed overlay narrows the upstream workflow for a portable Claude
Code/Codex install. It takes precedence over conflicting setup or mutation
instructions later in this skill.

- Resolve `SKILL_DIR` to the absolute directory containing this `SKILL.md`.
  Run bundled helpers only as `node "$SKILL_DIR/scripts/<name>.mjs"`; never
  assume a project-relative or harness-specific install path.
- Selecting this skill grants no permission to edit. Critique, audit, and shape
  are read-only. Build, fix, refine, document, and extract may write only when
  the user's request clearly asks for those changes.
- Missing or placeholder `PRODUCT.md` does not block a read-only critique or
  audit. State the gap and use repository evidence. For mutating work, offer a
  context interview and wait; never create, rename, migrate, or overwrite
  context files as hidden setup.
- `live` is explicit-only and local-development-only. Before its first run,
  disclose any helper process, temporary script injection, project writes, and
  recovery state; obtain confirmation. Never attach it to public, shared,
  staging, or production URLs.
- Global cleanup, deprecated-skill migration, `pin`, and `unpin` are not part
  of this package. The SUPERBROWKY installer owns installation state.
- Browser, Figma, image, and Product Design integrations are optional. Check
  live availability only when the task needs them. Do not install,
  authenticate, or claim use of a missing integration.
- A generated variant, automated score, or successful helper run is evidence,
  not human approval of a direction or release.

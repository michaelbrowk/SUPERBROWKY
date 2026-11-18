# Migrating from v4 to v4.1

v4.1 updates the pinned skills, shared workflow, and context templates. It keeps
the v4 ownership receipts and `.from-superbrowky-v4-*` merge-candidate format.
No migration runs at session start, and no accepted project context is replaced
automatically.

## Plan and apply

Use a checkout of v4.1 and the harness/profile already chosen for the project:

```bash
# Preview destinations, exact source pins, and conflicts
bash bootstrap.sh /path/to/project --harness both --profile core

# Apply within the user's authorization for that scope
bash bootstrap.sh /path/to/project --harness both --profile core --apply

# Check installation, pending merges, and context status
bash bootstrap.sh /path/to/project --harness both --profile core --check
```

PowerShell uses the same flow with `-Harness`, `-Profile`, `-Apply`, and `-Check`.
Use `claude` or `codex` instead of `both` if only that runtime is intended.
Do not change profiles just because an upgrade is available.

An unchanged, receipt-owned skill can be updated to the reviewed pin. A
locally modified skill is preserved and blocks replacement; inspect the diff
and reconcile deliberately. Do not delete receipts or force an overwrite to
make the check green. A preview is evidence for the installation plan, not a
test of the installed skills.

## Merge project context deliberately

Existing canonical files remain in place. v4.1 writes content-addressed
candidates beside them when the new templates differ. Review only applicable
changes against the latest accepted project decisions:

1. Preserve the existing brand, product facts, components, and explicit task
   boundaries. The templates are proposals, not replacement project truth.
2. Add each surface's **Operate**, **Read**, **Persuade**, or **Experience** mode
   to the `PROJECT.md` surface map. An old `brand`/`product` register does not
   determine every surface's mode; keep shared product purpose in `PRODUCT.md`.
3. Merge the team and verification rules into `HARNESS.md`. Keep platform
   adapters thin. A clear brief permits reversible local craft decisions;
   missing `PRODUCT.md` alone is not a reason to stop a narrow existing-code fix.
4. Once the exact merge is accepted, record the candidate filename and SHA-256
   in `Decision.md`, merge its content into the canonical file, and append the
   `SUPERBROWKY-MERGED` marker shown in the README. Then remove that candidate.
   The marker identifies the reviewed package; it is not approval by itself.
5. If accepted product/design context changes, update its artifact version and
   matching acceptance decision. Do not preserve an old acceptance hash for
   newly edited content. Run `--check` again; unresolved work remains `PARTIAL`.

## Impeccable compatibility

The reviewed Impeccable 4.9.2 package contains craft guidance and Markdown
references. Ordinary design, critique, and audit work reads existing project
context directly. The optional native launcher, automatic executable download,
live-browser runtime, hooks, and pin/unpin are not part of this portable
package. Do not invoke missing commands or install the upstream runtime as
hidden setup. Any separately requested runtime integration needs its own
review and authorization.

Taste uses compatible snapshot
`85fc47e4a1355fc2e047f8447171389c993855c9` from September 28, 2026, which is
newer than the v4 pin and remains a composition reference lens without
hooks/runtime. The newer upstream 2.5.1 engine is deferred, not adapted or
installed by v4.1. Read the guidance inside the existing brief and design
system; do not copy an upstream preset over an accepted project identity.
The review boundary is recorded in
[THIRD_PARTY_SKILLS.md](../THIRD_PARTY_SKILLS.md).

## Retired Taste lenses

Newer upstream releases removed the source folders used for
`high-end-visual-design` and `redesign-existing-projects`. v4.1 retires those
legacy entries instead of substituting unrelated skills. `full` remains
accepted and installs the same 13 skills as `growth`.

Previously installed copies of the two retired skills are not deleted during
an update. If they remain in a runtime's catalog, remove any old routing rule
that treats them as a default authority. The receipt-backed global uninstall
can remove unchanged owned skills, including retired entries, but it removes
all owned global skills for the selected harness. Review its plan before
using it, then reinstall the desired profile if a clean set is needed. Locally
edited copies are preserved and reported for manual reconciliation.

## Verify the intended runtime

After installation and merge checks, open a fresh Claude Code session or Codex
task. Verify that it discovers the updated skill and can complete a small,
representative authorized task using the actual project context. Inspect the
result and relevant behavior. Static validation, an installer `READY` result,
and a direct read of a skill file do not prove fresh-session behavior.

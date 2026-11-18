# Third-party skill provenance

SUPERBROWKY downloads the allowlisted directories in `manifests/skills.tsv`
at exact commits in `versions.lock`. Receipts record source, commit, adaptation
version and the hash of the installed derivative. No skill may approve its own
output or override the project's authority. Review date: **2026-11-18**.

## Reviewed sources for v4.1

| Source | Pin | License | Use |
|---|---|---|---|
| [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | `d41d9860b0094dcb68030657da63461212835aaa` | Apache-2.0 | Impeccable 4.9.2: selected craft references with a portable manual workflow |
| [emilkowalski/skills](https://github.com/emilkowalski/skills) | `64eb3deb9a5fbfa041faf783e0bc3fd635872e9c` | MIT | Motion and interaction craft |
| [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | `85fc47e4a1355fc2e047f8447171389c993855c9` | MIT | Compatible composition lens, reviewed revision from 2026-09-28 |
| [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) | `73573e94a06a39965978b3fa1f9c1eace8cebc7c` | MIT | Optional launch and growth profiles |
| [hardikpandya/stop-slop](https://github.com/hardikpandya/stop-slop) | `8da1f030185bdfe8471220585162991eaeb970e9` | MIT | Copy cleanup; upstream unchanged at review |

### Taste compatibility exception

Taste is newer than v4's June pin, but deliberately not the November HEAD
`f6b76575f949707b4e3c37cd86cb44b0b98643e8`. That distribution adds automatic
Stop hooks, its own build/browser gate, scripts and a large stock-asset system.
It needs a separate integration review before it can coexist with the primary
UI workflow. The selected September directory is a single contextual,
brief-first `SKILL.md`, without those runtime dependencies. It remains an
explicit composition lens; its stylistic defaults never replace a real brand.

The two broad experimental lenses `high-end-visual-design` and
`redesign-existing-projects` are retired from the profiles. `full` remains an
accepted alias of `growth`. Existing managed copies and receipts are preserved,
reported by doctor as `PARTIAL`, and removable only by an explicit
receipt-backed uninstall. Their names are recorded once in
`manifests/retired-skills.txt`.

## Review boundary

Reviewed: selected package structure, activation scope, local references,
licenses/notices, commands and automatic side effects, and conflicts with the
shared harness. Marketing packages contain no executable helpers in the six
selected directories. Their time-sensitive examples and external claims are
not verified facts for a future task: consult current primary sources when
using them. References to optional sibling skills do not install those skills.

Upstream changes do not authorize installs, publishing, outreach, spend,
credentials access or hidden context writes. Existing project context and
accepted decisions outrank a skill's own context-file convention. A narrow
refinement can use existing code when Markdown context is missing.

Before changing a pin:

1. Compare the selected directories, references and scripts.
2. Validate frontmatter, local links, paths, licenses and script syntax.
3. Review runtime and permission changes, not only version numbers.
4. Run isolated install → doctor → reinstall → drift refusal → uninstall →
   backup restoration, plus an upgrade from v4.
5. Update provenance, exact pins and visible adaptations together.

Never auto-update third-party skills at session start. `--latest` remains a
read-only preview, not permission to apply an unreviewed distribution.

## Visible local adaptations

Every downloaded skill receives `overlays/third-party-safety.md` immediately
after frontmatter. Receipts identify it as **third-party-safety-v2**. It
preserves scope, prior authorization, the latest correction and existing brand;
requires actual tool availability; limits browser automation to authorized QA;
and separates local, preview, deployed and live-verified evidence.

### Impeccable 4.9.2 portable guidance

Bash and PowerShell call the same `scripts/adapt-impeccable.mjs` on staging.
Both use the same portability rules; retained references preserve upstream
platform-specific wording, so their installed tree hashes need not match.
It accepts only the reviewed source pin/version, validates the entire staged
tree against symlinks, then prepares the full transform before pruning files.
It installs:

- a narrow, portable `SKILL.md` from `overlays/impeccable-portable.md`;
- `PORTABLE.md` from `overlays/impeccable-workflow.md` for new work, critique,
  audit, detail, final verification and context documentation;
- 22 selected upstream craft references for modes, hierarchy, accessibility,
  responsive/native adaptation, copy, edge cases and visual refinement;
- upstream LICENSE and NOTICE files without alteration.

Local links to omitted operational playbooks are explicitly routed to the
portable workflow. A new unreviewed local dependency or engine command in a
retained guide aborts staging instead of shipping a broken link. The source
pin and version remain visible; this is a derivative, not byte-identical
upstream content or an upstream endorsement.

**Not shipped or run:** the native engine, shell/Windows launchers, runtime
scripts, live/generate browser sessions, automatic detectors, hooks, pin/unpin,
engine doctor, foundations wizard, engine-gated comp workflows, storage helpers
or upstream agent definitions. Ordinary scoped design uses the manual workflow
and actually available tools. An omitted mode is reported unavailable; the
agent must not download a replacement engine, invoke one elsewhere on PATH or
invent runtime receipts. Browser and integration behavior still requires its
own authorized real verification.

Receipts label this adaptation **superbrowky-overlay-v2**, and hashes cover the
transformed tree. Doctor checks that runtime/agent directories are absent and
that the portable workflow exists.

### Marketing dependency closure

The `ai-seo` tools-registry link is rewritten from either the legacy relative
path or upstream's floating `main` URL to the exact pinned GitHub blob. Its
receipt retains **pinned-upstream-link-v1**. The kit does not fetch or execute
the registry's third-party tools.

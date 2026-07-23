# Third-party skill provenance

SUPERBROWKY downloads only the allowlisted directories in
`manifests/skills.tsv`, at commits pinned in `versions.lock`. Installed
receipts record the resolved commit and content hash. No third-party skill may
approve its own output or override the project harness.

## Sources

| Source | Pin | License | Use |
|---|---|---|---|
| [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | `e587004ee42883dad40d14cd0f5e1b21ae1933df` | Apache-2.0 | Primary UI engine; harness-specific source plus the reviewed portable overlay |
| [emilkowalski/skills](https://github.com/emilkowalski/skills) | `e695d13cb298db0f46d5ef05be2ad13fa12908a6` | MIT | Motion and interaction craft |
| [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | `1a6dc0a5ac5d0152120938bf66ed67ea2ec8e552` | MIT | Explicit composition and experimental visual lenses |
| [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) | `7f4af1ea8e7809e0142c55bf19243a706f539c25` | MIT | Optional launch and growth profiles |
| [hardikpandya/stop-slop](https://github.com/hardikpandya/stop-slop) | `8da1f030185bdfe8471220585162991eaeb970e9` | MIT | Copy cleanup |

## Review boundary

Pinning makes the downloaded source repeatable; it does not make every
instruction universally correct. The shared `HARNESS.md` establishes:

- one primary design engine;
- read-only audit defaults;
- explicit approval for network installs, publishing, spend, and destructive
  actions;
- human-only direction and release approval;
- `PROJECT.md` as the explicit surface map and its mapped `PRODUCT.md` /
  `DESIGN.md` files as the only product/design context sources.

Before changing a pin:

1. Compare the old and new directories, including scripts and referenced files.
2. Validate frontmatter, local links, paths, licenses, and script syntax.
3. Run the fake-home lifecycle tests.
4. Update this file and `versions.lock` in the same review.
5. Never auto-update third-party skills at session start.

## Local adaptation

Every downloaded skill is a visible derivative of its pinned upstream
directory. During staging, the installer inserts
`overlays/third-party-safety.md` after frontmatter so that globally discovered
skills keep the same write, authority, and human-approval boundaries even
outside a SUPERBROWKY-enabled project.

Impeccable receives an additional provider-specific adaptation. The installer:

- inserts `overlays/impeccable-portable.md` after the upstream frontmatter;
- removes the global cleanup and pin helpers because SUPERBROWKY owns install
  state;
- carries the upstream license/notice into the installed directory;
- validates and hashes the resulting tree.

Receipts label every applied adaptation; installed trees are not represented
as byte-identical upstream content or as an upstream endorsement.

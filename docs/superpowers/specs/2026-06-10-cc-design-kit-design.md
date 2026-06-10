# Claude Code Design Kit — Design

**Goal:** A shareable, public repo that any colleague/friend can apply to their project so Claude Code produces great code with no design slop, follows the design system they build, uses the design skills correctly, and stays grounded in their brand — driven by clear operating postulates rather than vague "make it nice" prompts.

**Author:** Misha. **Date:** 2026-06-10.

---

## The core insight (why this shape)

Quality comes from **three layers**, not one file:

1. **Skills = the taste engine** (machine-level, `~/.claude/skills/`). The design skills (`impeccable`, `design-taste-frontend`, `emil-design-eng`, `stop-slop`, `design-system`, `brand`, `polish`) encode taste as *enforceable rules* (anti-slop bans, the AI Slop Test, the Design Context protocol, token architecture). The process skills (superpowers: `brainstorming`, `writing-plans`, `subagent-driven-development`) enforce *design-before-code* + planning discipline.
2. **The design-system-first mandate** (project-level, `CLAUDE.md`). Forces "consult design system → tokens → existing components, never raw hex/spacing/px."
3. **Brand/design context captured up front** (project-level, `.impeccable.md`). The "understand the brand first" artifact the skills read.

A single self-contained file can carry layers 2–3 but **cannot replicate layer 1** — so the kit ships both: a one-command skill install + the two project files. This is the explicit, approved scope.

**Non-goals:** the user's personal `~/.claude/CLAUDE.md` (contains secrets/infra — never shared), the `team/` agent personas, marketing/CRO skills.

---

## Architecture

```
cc-design-kit/                       (public GitHub repo)
├── README.md                        what it is, why, 3-step setup, copy-paste kickoff prompt, skills table
├── LICENSE                          MIT — covers the kit's OWN files only
├── install-skills.sh                fetches the design skills from upstream → ~/.claude/skills/
└── template/                        drop into YOUR project root
    ├── CLAUDE.md                    operating postulates + design-system-first mandate + skill triggers
    └── .impeccable.md              brand / design-context capture (impeccable auto-reads this exact filename)
```

**Skill distribution = REFERENCE, not bundle (decided after a licensing check).**
The design skills are third-party with mixed/absent licenses (impeccable: Apache
2.0; stop-slop/design-system: MIT; design-taste-frontend, emil-design-eng, brand,
polish: no stated license). Republishing unlicensed third-party work in a public
repo is a copyright violation, so the kit does NOT bundle skills. `install-skills.sh`
clones the authoritative upstream repos (from `~/.agents/.skill-lock.json`) and
copies their skills into the user's own `~/.claude/skills/`:
- `pbakaus/impeccable` → impeccable, polish + the taste suite (Apache 2.0)
- `emilkowalski/skill` → emil-design-eng
- `Leonxlnx/taste-skill` → design-taste-frontend, high-end-visual-design, redesign
`stop-slop` / `design-system` / `brand` are listed as optional extras with author
credit (not in the lock file → no authoritative URL to point at). Process skills
(`superpowers`) install via the `claude-plugins-official` marketplace.

**Two layers, two install moments:**
- **Machine (once per machine):** run `install-skills.sh` → fetches design skills from upstream + prompts for the superpowers plugin.
- **Project (per repo):** copy `template/CLAUDE.md` and `template/.impeccable.md` into the project root, fill the placeholders.

Stack-agnostic: postulates + the design-system-first mandate are identical for web and mobile; worked examples are shown in CSS/Tailwind (the design skills lean web), with a note that the principle ("tokens/components, never raw values") transfers to SwiftUI/etc.

---

## Components

### 1. `install-skills.sh`
- Clones each authoritative upstream repo (`pbakaus/impeccable`, `emilkowalski/skill`, `Leonxlnx/taste-skill`) shallowly to a temp dir, then copies every `SKILL.md`-bearing folder into `~/.claude/skills/` (robust to per-repo layout). Cleans up the temp dir.
- Prints the manual one-step for the superpowers plugin (`/plugin` → `claude-plugins-official` → `superpowers`) and lists the optional extras (`stop-slop`, `design-system`, `brand`) with author credit.
- Idempotent; safe to re-run (re-syncs to latest upstream). `set -euo pipefail`, guards on `git`, handles clone failures gracefully. Pure bash, macOS + Linux.

### 2. `template/CLAUDE.md` — the heart (the "postulates + coherent prompt")
Sections:
- **Operating postulates** (the load-bearing core): design-system-first; never raw hex / spacing / `px`; **brainstorm-before-build** (design + approval before any implementation); **no-slop** (run the AI Slop Test before shipping any UI); **adversarial review before merge**; **verify-before-done** (build/test/demonstrate, don't claim success on an unverified diff).
- **Three-skill design rule:** before ANY visual code, consult (1) the design system / Figma, (2) design tokens, (3) existing components — in that order.
- **Skill triggers:** when to invoke `impeccable` (any UI build / needs project context), `design-taste-frontend` (landing/portfolio/redesign), `emil-design-eng` (motion/polish), `stop-slop` (any prose), `polish` (pre-ship pass), `brand` (branded content), `design-system` (token work); and `brainstorming` → `writing-plans` for any non-trivial feature.
- **Project placeholders** (TO FILL): stack/framework, where design tokens live, where components live, design-system source (Figma file / token file), test command, conventions.
- **Brand pointer:** "Brand + design context live in `.impeccable.md` — read it before any design."

### 3. `template/.impeccable.md` — brand / design-context capture (the "understand your brand")
Matches the exact filename + `## Design Context` structure `impeccable` auto-reads, so the skill consumes it without prompting. Fields (with guiding prompts, not blanks): **Users** (who + context + job-to-be-done), **Brand personality** (3 words + emotional goal), **Aesthetic direction** (tone, light/dark + why, references), **Anti-references** ("what it should explicitly NOT look like"), **Brand constants** (exact palette hex, type pairing, spacing/radius scale, logo/assets), **Accessibility**. Includes a one-line "how to (re)generate this: run `/impeccable teach`."

### 4. `README.md`
- One-paragraph "what + why" (the three layers, plainly).
- **3-step setup:** (1) `bash install-skills.sh`; (2) copy `template/*` into your project root; (3) fill `.impeccable.md` (or run `/impeccable teach`).
- **Copy-paste kickoff prompt** — a strong starter message a user pastes to begin: states the brand is in `.impeccable.md`, asks Claude to brainstorm-before-build, follow the design system, run the slop test.
- A short "what each skill does" table + the honest note: skills are the engine; the templates alone won't replicate the quality.
- License (MIT) + "this is a starter; fork and adapt."

---

## Compatibility decision (load-bearing)
The brand file is named **`.impeccable.md`** (not `BRAND.md`) — the exact filename + `## Design Context` header the `impeccable` skill searches for in the project root. A differently-named file would not be auto-consumed, defeating "skills actually used by design." `CLAUDE.md` references it by name.

## Success criteria
- A colleague with zero prior setup can: run one script, copy two files, fill the brand doc, and get design-system-compliant, non-slop output on their first real feature.
- The skills are actually invoked (impeccable reads `.impeccable.md`; CLAUDE.md triggers fire).
- No secrets/personal infra anywhere in the repo.
- Stack-agnostic (works for a web or a mobile project).

## Build order
1. Scaffold repo + `.gitignore` + MIT `LICENSE`.
2. Resolve authoritative skill sources from `~/.agents/.skill-lock.json` (done — see decision above). No skills bundled.
3. Write `template/CLAUDE.md`.
4. Write `template/.impeccable.md`.
5. Write `install-skills.sh` (clone-from-upstream; `chmod +x`).
6. Write `README.md` (incl. kickoff prompt + skills/license table).
7. Sanitization pass: grep the whole repo for personal paths / secrets; verify clean (the kit ships no third-party skill content, so the surface is just the templates + script).
8. User reviews; then optionally push as a public GitHub repo.

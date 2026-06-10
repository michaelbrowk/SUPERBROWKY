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
├── README.md                        what it is, why, 3-step setup, copy-paste kickoff prompt
├── install-skills.sh                copies design skills → ~/.claude/skills/, installs superpowers plugin
├── skills/                          bundled, sanitized design skills (verbatim copies)
│   ├── impeccable/
│   ├── design-taste-frontend/
│   ├── emil-design-eng/
│   ├── stop-slop/
│   ├── design-system/
│   ├── brand/
│   └── polish/
└── template/                        drop into YOUR project root
    ├── CLAUDE.md                    operating postulates + design-system-first mandate + skill triggers
    └── .impeccable.md              brand / design-context capture (impeccable auto-reads this exact filename)
```

**Two layers, two install moments:**
- **Machine (once per machine):** run `install-skills.sh` → design skills + the superpowers process plugin.
- **Project (per repo):** copy `template/CLAUDE.md` and `template/.impeccable.md` into the project root, fill the placeholders.

Stack-agnostic: postulates + the design-system-first mandate are identical for web and mobile; worked examples are shown in CSS/Tailwind (the design skills lean web), with a note that the principle ("tokens/components, never raw values") transfers to SwiftUI/etc.

---

## Components

### 1. `install-skills.sh`
- Copies each `skills/<name>/` to `~/.claude/skills/<name>/` (creates the dir, does not overwrite without a prompt; prints what it did).
- Installs the superpowers plugin (the process skills) via the Claude Code plugin marketplace — or, if non-interactive, prints the exact `claude` command + marketplace URL to run.
- Idempotent; safe to re-run. Prints a final "next: copy template/ into your project" pointer.
- Pure bash, no deps beyond `cp`/`mkdir`. Works on macOS + Linux.

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
2. Copy the 7 design skills into `skills/` (verbatim; scan for any personal references and strip).
3. Write `template/CLAUDE.md`.
4. Write `template/.impeccable.md`.
5. Write `install-skills.sh` (+ chmod +x).
6. Write `README.md` (incl. kickoff prompt).
7. Sanitization pass: grep the whole repo for personal paths / secrets / project-specific names; verify clean.
8. Optional: push as a public GitHub repo.

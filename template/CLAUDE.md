# <PROJECT NAME> — Engineering & Design Notes

> Drop this file at your project root. Claude Code reads it automatically every
> session. Fill the `<PLACEHOLDERS>` and delete this quote block.
>
> Brand + design context live in **`.impeccable.md`** (same folder) — Claude
> reads it before any design work. Keep it current.

## What this is
<PROJECT NAME> is a <one line: what the product does, for whom>.
Stack: <framework / language>. Design system: <Figma file / token file location>.

---

## Operating postulates (non-negotiable)

These override convenience. They are why the output is good, not generic.

1. **Design-system-first.** Before ANY visual code, consult — in order — (1) the
   design system / Figma, (2) the design **tokens**, (3) the existing
   **components**. Reuse before you create.
2. **Never raw values.** No hand-typed hex, no `rgb()`, no magic spacing/`px`,
   no one-off font sizes. Everything comes from tokens. A raw value is a bug.
3. **Brainstorm before build.** For anything non-trivial (3+ steps or a design
   decision): use the `brainstorming` skill — present a design, get approval —
   *before* writing code. No surprise implementations.
4. **No slop.** Run the AI Slop Test (`impeccable`) on any UI before shipping:
   "if I said an AI made this, would they believe me instantly?" If yes, redo
   it. Strip AI tells from prose with `stop-slop`.
5. **Verify before done.** Build it, test it, demonstrate it. Never claim
   success on an unverified diff. Tests stay green: `<test command>`.
6. **Review before merge.** Self-review the diff for raw values / slop / scope
   creep. For shared components or risky changes, get an adversarial review
   first.
7. **Minimal impact.** Touch only what the task needs. No drive-by refactors,
   no speculative abstractions. Find root causes, not band-aids.

---

## The three-skill design rule
Before writing visual code, consult **all three**, in order:
1. **Design system / Figma** — the source of truth for layout, color, type.
2. **Design tokens** — `<where your tokens live, e.g. theme.ts / tokens.json / Tailwind config / a Swift theme file>`.
3. **Existing components** — `<where your components live>`. New shared surface
   goes into the component library, not into a page/screen file.

If a token or component is missing, that's a design-system gap to raise — not a
license to hardcode.

---

## Skills — when to reach for which
(Install once via the kit's `install-skills.sh`.)

| Situation | Skill |
|---|---|
| Building any UI / needs project + brand context | `impeccable` (auto-reads `.impeccable.md`) |
| Landing page, portfolio, marketing site, redesign | `design-taste-frontend` |
| Motion, transitions, the "feels great" polish | `emil-design-eng` |
| Final pre-ship pass (alignment, spacing, micro-detail) | `polish` |
| Any user-facing prose (copy, errors, empty states) | `stop-slop` |
| Token architecture / a design system from scratch | `design-system` |
| Brand voice / visual identity / style guide | `brand` |
| Any non-trivial feature | `brainstorming` → `writing-plans` |

Process rule: **`brainstorming` (design + approval) → `writing-plans` (plan) →
implement.** Don't skip to code.

---

## Project specifics (fill these in)
- **Tokens:** `<path>`
- **Components:** `<path>`
- **Design source:** `<Figma file key / link>`
- **Stack / framework:** `<...>`
- **Test command:** `<...>`
- **Build / run command:** `<...>`
- **Conventions:** `<naming, file structure, commit style, anything load-bearing>`

## Don't do
- Don't hardcode brand colors — verify exact values in the design system / ask.
- Don't replace provided image assets with emoji/placeholders without asking.
- Don't default to dark-mode-with-glowing-accents, purple gradients, three
  equal feature cards, or other AI-design tells (see `impeccable`).
- Don't ship a UI you haven't run the AI Slop Test against.

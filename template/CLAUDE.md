# <PROJECT NAME> — Engineering & Design Notes

> Drop this file at your project root. Claude Code reads it automatically every
> session. Fill the `<PLACEHOLDERS>` and delete this quote block.
>
> Strategy + brand live in **`PRODUCT.md`**; the visual system (exact colors,
> type, spacing, motion, banned patterns) lives in **`DESIGN.md`** — both in
> this folder. Read both before any design work. Keep them current.

## What this is
<PROJECT NAME> is a <one line: what the product does, for whom>.
Stack: <framework / language>. Design source: <Figma file / token file location>.

---

## Operating postulates (non-negotiable)

These override convenience. They are why the output is good, not generic.

1. **Design-system-first, in this order.** Before ANY visual code consult:
   (1) **existing components** — if one covers ~80% of the need, adopt it,
   don't rebuild; (2) the **design tokens**; (3) the **mock / design source**.
   A missing token or component is a design-system gap to raise — flag it,
   never guess a value or invent a one-off.
2. **Never raw values — anywhere.** No hand-typed hex, no magic spacing/`px`,
   no one-off font sizes. Also banned: overriding a design-system component at
   the call site (`h-8 text-xs` on a shared button — fix it centrally instead),
   and reaching for platform defaults (system icons, stock sheets/dialogs) when
   the project has its own. A raw value is a bug.
3. **The mock is ground truth.** When working from Figma or any mock: pull the
   rendered **screenshot**, not just extracted code/values (extraction silently
   drops elements). Fetch the node for each surface **right before** building
   that surface — never from memory of a sibling, never from platform
   conventions. If the user says the mock changed, re-fetch before deciding.
4. **Brainstorm before build — anchored on references.** For anything
   non-trivial: use the `brainstorming` skill, present a design, get approval
   *before* code. Ask for 2–3 concrete references and *what specifically* the
   user likes in each; "full creative freedom" reliably produces generic slop.
   For taste decisions, build 2–3 variants and show them side by side.
5. **Skills actually fire.** At the first design output of a session, invoke
   the design skills that match the task (table below) — *loaded in context ≠
   invoked*. Announce it in one line ("Running impeccable + emil-design-eng")
   so the human can audit. Later outputs may cite that invocation; re-invoke on
   a major context shift. When a domain skill exists (motion, prose), invoke it
   at the FIRST mention of its domain — and never quote a skill's rule from
   memory: re-read it at the moment you cite it.
6. **No slop.** The test: *"if I told someone an AI made this, would they
   believe me instantly?"* If yes, redo it — the goal is "how was this made?",
   not "which AI made this?". `DESIGN.md` has the banned-pattern list; check
   the diff against it. Strip AI tells from prose (keep the voice exceptions
   listed in `DESIGN.md`).
7. **Verify before done — with your eyes.** Static greps miss layout bugs.
   Open it in a real browser/simulator and eyeball top to bottom. Check
   **375 / 768 / 1280** widths, **light AND dark** appearance, and motion in
   its settled state. The human approves a **screenshot**, not a description.
   Tests stay green: `<test command>`.
8. **Review before merge.** Self-check: "is every value from tokens, every
   component from the system?" Then run the design-lint pass (below). For
   shared components or risky changes, get an adversarial review first.
9. **Capture the lesson.** After any correction from the user, append it to
   *Lessons* (bottom of this file): the rule, the literal correction that
   caused it, how to apply it next time. Same mistake twice = the entry wasn't
   specific enough.
10. **Minimal impact.** Touch only what the task needs. No drive-by refactors,
    no speculative abstractions. Find root causes, not band-aids.

---

## Skills — when to reach for which
(Taste skills are installed machine-wide by the kit, except `impeccable`,
which lives in this project's `.claude/skills/`. `brainstorming` /
`writing-plans` come from the `superpowers` plugin — if `/plugin` wasn't run
yet, install it before any non-trivial feature. `stop-slop` is an optional
extra.)

| Situation | Skill |
|---|---|
| Any UI work — context, craft, audits | `/impeccable` (reads `PRODUCT.md` + `DESIGN.md`) |
| Landing page, portfolio, marketing site, redesign | `design-taste-frontend` |
| Premium/agency-grade visual bar, expensive feel | `high-end-visual-design` |
| Motion, transitions, the "feels great" details | `emil-design-eng` |
| Final pre-ship pass (alignment, spacing, micro-detail) | `/impeccable polish` |
| Upgrading an existing UI without breaking it | `redesign-existing-projects` |
| Any user-facing prose (copy, errors, empty states) | `stop-slop` (if installed) |
| Slow page, Lighthouse/PSI score, Core Web Vitals, heavy images | `psi-optimize` |
| Technical / on-page SEO: meta, indexing, internal links | `seo-audit` |
| Being cited by AI answers (ChatGPT, Perplexity, AI Overviews) | `ai-seo` |
| Structured data / rich snippets | `schema` |
| Any non-trivial feature | `brainstorming` → `writing-plans` |

Process rule: **`brainstorming` (design + approval) → `writing-plans` (plan) →
implement.** Don't skip to code. If several general design skills could claim a
task, `impeccable` is the primary engine; the others sharpen it.

Ship rule: before a **public** page goes live, run `psi-optimize` (perf) and
`seo-audit` once — beautiful but slow or invisible still fails the bar.

## Design-lint pass (after every UI change)

Spawn a read-only subagent with the diff and `DESIGN.md`:

> Read DESIGN.md, then this diff. Flag, with file:line — raw hex / non-token
> spacing or sizes; call-site overrides of design-system components;
> platform-default components or icons where the project has its own; new
> typography not in the registers table; banned patterns from DESIGN.md (if
> that section is missing, use common AI-slop tells: purple gradients, three
> equal cards, icon-in-colored-square, fake counters); off-voice copy.
> ≤250 words. End with VERDICT: clean | issues.

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
- Don't hardcode brand colors — verify exact values in `DESIGN.md` / the design
  source / ask. Never infer a palette from the product's *name*.
- Don't replace provided image assets with emoji/placeholders without asking.
- Don't ship UI checked only on desktop, only in one color scheme, or only as
  a passing build — see postulate 7.
- The full banned-pattern list lives in `DESIGN.md` — it's part of every
  design review.

## Lessons

> One entry per correction. Format: **rule** — *the literal correction that
> caused it* — how to apply. Newest on top.

- <empty — first lesson goes here>

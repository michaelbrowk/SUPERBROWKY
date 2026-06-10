# Claude Code Design Kit

A small starter kit that makes Claude Code produce **production-grade code with
no design slop** — output that follows the design system you build and stays
grounded in your brand, driven by clear postulates instead of "make it nice."

It's not magic and it's not one file. Quality comes from **three layers**:

1. **Skills — the taste engine.** Design skills (`impeccable`,
   `design-taste-frontend`, `emil-design-eng`, `polish`) encode taste as
   *enforceable rules*: anti-slop bans, the "AI Slop Test", a brand-context
   protocol, token discipline. Process skills (`superpowers`) enforce
   *design-before-code* + planning. **These do the heavy lifting** — templates
   alone won't replicate the quality.
2. **The design-system-first mandate** — in `template/CLAUDE.md`. Forces
   "consult system → tokens → components, never raw hex/spacing."
3. **Brand captured up front** — in `template/.impeccable.md`. The "understand
   the brand first" brief the skills read automatically.

This kit ships layers 2–3 (your files) and a one-command installer for layer 1
(it fetches the skills from their upstream authors — it does **not** republish
anyone's work).

---

## Setup (3 steps)

```bash
# 1. Install the design + process skills into ~/.claude/skills (once per machine)
bash install-skills.sh
#    …then in Claude Code: /plugin → marketplace "claude-plugins-official" → install "superpowers"

# 2. Copy the two templates into YOUR project root
cp template/CLAUDE.md       /path/to/your-project/CLAUDE.md
cp template/.impeccable.md  /path/to/your-project/.impeccable.md

# 3. Fill them in
#    - CLAUDE.md   → project specifics (stack, where tokens/components live, test cmd)
#    - .impeccable.md → your brand  (or just run /impeccable teach and answer the questions)
```

That's it. Open Claude Code in your project and start with the kickoff prompt below.

---

## Kickoff prompt (copy-paste to start a feature)

> My brand + design context are in `.impeccable.md` and my project rules are in
> `CLAUDE.md` — read both first. I want to build **<feature>**. Don't jump to
> code: use the brainstorming skill to propose a design and get my approval,
> then plan it, then implement. Follow the design-system-first rule (tokens and
> existing components, never raw values), and run the AI Slop Test before you
> call any UI done.

---

## How it works / FAQ

### The mechanism
- **`CLAUDE.md` loads into context every session.** The postulates are
  always-on instructions, not a one-off prompt — design-system-first,
  brainstorm-before-build, and "no slop" govern every turn.
- **Skills fire when relevant.** Their descriptions + the trigger table in
  `CLAUDE.md` + the brainstorm-before-code habit make Claude reach for them: any
  UI → `impeccable` runs the AI Slop Test and the three-skill rule blocks raw
  values; `emil-design-eng` for motion; `polish` for the final pass.
- **`.impeccable.md` is read automatically** by impeccable's context-gathering
  protocol, so designs are grounded in *your* brand, not generic defaults.
- **Flow is design → plan → build:** `brainstorming` (propose + approve) →
  `writing-plans` → implement. Not a jump to code.

### FAQ

**Do I have to run `install-skills.sh`?** Yes, for the full effect — the skills
are the engine. Copying only the templates gives you the postulates (better than
nothing) but not the taste skills.

**Why is `superpowers` a manual step?** Plugins install through Claude Code's
`/plugin` UI, not a shell script. One minute: `/plugin` →
`claude-plugins-official` → `superpowers`.

**The output is still generic.** Almost always an empty or vague
`.impeccable.md`. Garbage in, generic out — fill it properly, or run
`/impeccable teach` and answer the questions.

**It jumped straight to code instead of brainstorming.** Use the kickoff prompt
— it nudges the design-first flow. `CLAUDE.md` pushes it too, but a bare
"build X" gives Claude less to anchor on.

**My project has no design tokens yet.** Then step zero is building the design
system (the `design-system` skill, or `impeccable` from your brand). The kit
enforces "use tokens/components" — it doesn't invent your system for you.

**How do I update the skills?** Re-run `install-skills.sh` — it re-syncs to the
latest upstream. It overwrites same-named skills, so keep local customizations
elsewhere.

**Does it work for mobile / non-web?** The postulates and the system-first rule
are stack-agnostic. The design skills lean web, but "tokens/components, never
raw values" transfers to SwiftUI, Flutter, etc.

---

## What each skill does

| Skill | Does | Source · License |
|---|---|---|
| `impeccable` | Anti-slop frontend; the AI Slop Test; reads `.impeccable.md` for brand context | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) · Apache 2.0 |
| `polish` | Final pre-ship pass: alignment, spacing, micro-detail | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) · Apache 2.0 |
| `emil-design-eng` | Motion & the invisible details that make UI feel great (Emil Kowalski) | [emilkowalski/skill](https://github.com/emilkowalski/skill) |
| `design-taste-frontend` | Reads the brief, picks a direction, ships non-templated landing/portfolio | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) |
| `high-end-visual-design`, `redesign-existing-projects` | Agency-grade visuals; upgrade existing UIs | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) |
| `superpowers` (brainstorming, writing-plans, …) | Design-before-code + planning discipline | `claude-plugins-official` marketplace |

**Optional extras** (not auto-installed — add if you want them): `stop-slop`
(strip AI tells from prose · MIT, [Hardik Pandya](https://hvpandya.com)),
`design-system` (token architecture · MIT, claudekit), `brand` (brand voice ·
claudekit). Search GitHub or use your own source.

---

## Honest notes

- **The skills belong to their authors.** This kit links to and installs them
  from source; it doesn't bundle or relicense them. Credit and licenses stay
  with the upstream repos above. If you fork this kit, keep it that way.
- **Stack-agnostic.** The postulates and the design-system-first rule are
  identical for web or mobile; the design skills lean web, but
  "tokens/components, never raw values" transfers to SwiftUI, Flutter, etc.
- **The templates are a starting point.** Fork them, make them yours. The point
  is the *discipline* — brand first, system first, design before code, no slop.

## License
The kit's own files (`README.md`, `install-skills.sh`, `template/*`) are MIT —
see [LICENSE](LICENSE). Installed skills retain their own licenses.

# Claude Code Design Kit

[![CI](https://github.com/michaelbrowk/SUPERBROWKY/actions/workflows/ci.yml/badge.svg)](https://github.com/michaelbrowk/SUPERBROWKY/actions/workflows/ci.yml)

A small starter kit that makes Claude Code produce **production-grade code with
no design slop** — output that follows the design system you build and stays
grounded in your brand, driven by clear postulates instead of "make it nice."

It's not magic and it's not one file. Quality comes from **three layers**:

1. **Skills — the taste engine** (`impeccable`, `emil-design-eng`, the taste
   suite, `superpowers` for process), plus a four-pillar ship-clean layer:
   performance (`psi-optimize`), findability (`seo-audit`, `ai-seo`, `schema`,
   `programmatic-seo`, `site-architecture`, `cro`), accessibility
   (`a11y-audit`), and pre-ship metadata + prose (`meta-audit`, `stop-slop`).
   These do the heavy lifting — templates alone won't replicate the quality.
2. **Always-on rules** — `template/CLAUDE.md`: components → tokens → mock,
   never raw values, verify with your eyes, capture every lesson.
3. **Your brand, captured up front** — `template/PRODUCT.md` (who it's for,
   what it must feel like) and `template/DESIGN.md` (the exact values + banned
   patterns). The `impeccable` skill reads both.

This kit ships layers 2–3 (your files) and a one-command installer for layer 1
(it fetches the skills from their upstream authors — it does **not** republish
anyone's work).

**Requirements:** git, curl, Node 24+ (for `impeccable`). On Windows, run the
commands in Git Bash or WSL.

---

## 🤖 If you're Claude Code (someone pasted you this link)

A user pointed you here and asked to set it up. **Do it for them — don't make
them run shell commands.** Steps:

1. **Clone the kit** to a scratch dir:
   `KIT=$(mktemp -d) && git clone https://github.com/michaelbrowk/SUPERBROWKY.git "$KIT"`
2. **Run the bootstrap:** `bash "$KIT/bootstrap.sh" <their-project-root>`
   (copies the three templates, installs the taste skills machine-wide at
   pinned versions, installs `impeccable` into their project via
   `npx -y impeccable@2.3.2 skills install --yes`; it won't clobber existing
   files).
3. **Tell them to install the process plugin** — this is the one thing you
   can't do for them: in Claude Code run `/plugin` → marketplace
   `claude-plugins-official` → install `superpowers`.
4. **Capture their brand.** Interview them (audience, register, three brand
   words, anti-references, exact palette + fonts, voice keep/ban) and fill
   `PRODUCT.md` + `DESIGN.md` in their project. **Don't leave placeholders** —
   empty brand = generic output. (`/impeccable init` can do this too, but only
   in a fresh session, after the skills load — that's the next step.)
5. **Tell them to start a fresh Claude Code session** so the newly installed
   skills load, then fill any remaining `<PLACEHOLDERS>` in `CLAUDE.md`
   (stack, where tokens/components live, test command).
6. **Verify:** run `bash "$KIT/bootstrap.sh" <their-project-root> --check` (the
   doctor — confirms templates, every machine skill, project impeccable, node).
   Then in the fresh session they ask *"Which design skills do you have? Read
   PRODUCT.md and DESIGN.md and tell me what's still a placeholder."* —
   expected: the five taste skills (`impeccable`, `emil-design-eng`,
   `design-taste-frontend`, `high-end-visual-design`,
   `redesign-existing-projects`), the ship-clean set (`psi-optimize`,
   `a11y-audit`, `meta-audit`, `seo-audit`, `ai-seo`, `schema`,
   `programmatic-seo`, `site-architecture`, `cro`, `stop-slop`), plus a list of
   gaps to fill.

After that, the postulates in `CLAUDE.md` and the skills do the rest. The human
walkthrough below is the same thing, by hand.

---

## Setup

**One command** — installs the skills and wires the templates into your project:

```bash
git clone https://github.com/michaelbrowk/SUPERBROWKY.git && cd SUPERBROWKY
bash bootstrap.sh /path/to/your-project
#   …then in Claude Code: /plugin → "claude-plugins-official" → install "superpowers"
```

Preview before you commit, and verify after:

```bash
bash bootstrap.sh /path/to/your-project --dry-run   # show every action, write nothing
bash bootstrap.sh /path/to/your-project --check     # doctor: did the setup land?
bash install-skills.sh --check-updates              # any upstream drift vs versions.lock?
```

…or **step by step** if you prefer:

```bash
# 1. Machine-wide taste skills (once per machine; pinned known-good versions)
bash install-skills.sh

# 2. The core engine, into YOUR project (its official installer; needs Node 24+)
cd /path/to/your-project && npx -y impeccable@2.3.2 skills install --yes

# 3. The three templates, into YOUR project root (-n = never overwrite;
#    if you already have a CLAUDE.md, merge by hand — or use bootstrap.sh,
#    which safely writes <name>.from-design-kit next to existing files)
cp -n template/CLAUDE.md template/PRODUCT.md template/DESIGN.md /path/to/your-project/

# 4. In Claude Code: /plugin → "claude-plugins-official" → install "superpowers"
```

Then, in a **fresh** Claude Code session, **fill them in:** `PRODUCT.md` →
brand + audience, `DESIGN.md` → the exact values, `CLAUDE.md` → project
specifics (stack, token/component paths, test command). Shortcut: run
`/impeccable init` — it interviews you, writes `PRODUCT.md` and offers
`DESIGN.md` (say yes) — then merge its output into the kit's template
sections; keep *Atmosphere / Voice / Banned patterns*, the design-lint pass
checks them.

**Verify it worked:** run `bash bootstrap.sh /path/to/your-project --check`
(the doctor). Then in that fresh session ask: *"Which design skills do you
have? Read PRODUCT.md and DESIGN.md and tell me what's still a placeholder."*
You should see the five taste skills (`impeccable`, `emil-design-eng`,
`design-taste-frontend`, `high-end-visual-design`,
`redesign-existing-projects`), the ship-clean set (`psi-optimize`,
`a11y-audit`, `meta-audit`, `seo-audit`, `ai-seo`, `schema`,
`programmatic-seo`, `site-architecture`, `cro`, `stop-slop`), and a list of
gaps to fill. A good first task: something small and visual — one screen, one
component — using the kickoff prompt below.

---

## Kickoff prompt (copy-paste to start a feature)

> My brand is in `PRODUCT.md`, the visual system in `DESIGN.md`, project rules
> in `CLAUDE.md` — read all three first. I want to build **<feature>**. Here
> are 2–3 references and what I like about each: **<links + the specific
> thing>**. Don't jump to code: use the brainstorming skill to propose a
> design and get my approval, then plan it, then implement. Tokens and
> existing components only — never raw values. Before you call it done: run
> the AI Slop Test, check 375/768/1280 widths and light+dark, and show me a
> screenshot.

(The references matter. "Full creative freedom" reliably produces generic
output — annotated references reliably don't.)

---

## How it works / FAQ

### The mechanism
- **`CLAUDE.md` loads into context every session.** The postulates are
  always-on instructions, not a one-off prompt — design-system-first,
  mock-is-ground-truth, brainstorm-before-build, and "no slop" govern every
  turn.
- **`PRODUCT.md` + `DESIGN.md` are read before design work** — by `CLAUDE.md`
  mandate *and* natively by the `impeccable` skill's context protocol — so
  designs are grounded in *your* brand and *your* exact values, not generic
  defaults.
- **Skills fire on a defined cadence.** The trigger table + the invocation
  rule in `CLAUDE.md` (invoke at first design output, announce, cite after,
  re-invoke on context shift) make the skills actually run instead of
  depending on Claude remembering.
- **Flow is design → plan → build:** `brainstorming` (propose + approve) →
  `writing-plans` → implement → verify with eyes + screenshot. Not a jump to
  code.

### FAQ

**Do I have to run the installer?** Yes, for the full effect — the skills are
the engine. Copying only the templates gives you the postulates (better than
nothing) but not the taste skills.

**Why is `superpowers` a manual step?** Plugins install through Claude Code's
`/plugin` UI, not a shell script. One minute: `/plugin` →
`claude-plugins-official` → `superpowers`.

**The output is still generic.** Almost always placeholder-y `PRODUCT.md` /
`DESIGN.md`. Garbage in, generic out — fill them properly, or run
`/impeccable init` and answer the questions. Second cause: no references in
your prompt — see the kickoff prompt.

**It jumped straight to code instead of brainstorming.** Use the kickoff
prompt — it nudges the design-first flow. `CLAUDE.md` pushes it too, but a
bare "build X" gives Claude less to anchor on.

**My project has no design tokens yet.** Run `/impeccable init` (it interviews
you, writes `PRODUCT.md`, and offers `DESIGN.md` — say yes), merge the result
into the kit's `DESIGN.md` sections, then have Claude build the token files
from it. The kit enforces "use tokens/components" — `DESIGN.md` is where your
system gets defined first.

**I used an older version of this kit (`.impeccable.md`).** Upstream
`impeccable` replaced that file with `PRODUCT.md` + `DESIGN.md` (its current
context flow). Move your brand brief content over
(Users/Personality/Anti-references → `PRODUCT.md`; palette/type/spacing →
`DESIGN.md`) and delete `.impeccable.md`.

**Where's the `polish` skill?** It's a sub-command now: `/impeccable polish`.
Same for audits: `/impeccable audit`.

**How do I update the skills?** First see what's drifted:
`bash install-skills.sh --check-updates` (read-only; prints the exact
`versions.lock` lines to paste). Bump the pins you want, then re-run
`install-skills.sh` (or pass `--latest` to ride upstream HEAD — may drift). It
keeps your original pre-kit copy of any same-named skill at
`~/.claude/skills-backup/`. For the project-level engine, `impeccable` manages
its own updates: `npx impeccable skills update`.

**Does it work for mobile / non-web?** The postulates and the system-first
rule are stack-agnostic. The design skills lean web, but "tokens/components,
never raw values" transfers to SwiftUI, Flutter, etc.

---

## What each skill does

| Skill | Does | Source · License |
|---|---|---|
| `impeccable` | The core engine: project context (`PRODUCT.md`+`DESIGN.md`), `/impeccable craft / polish / audit / init / document`, anti-slop detection | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) · Apache 2.0 · skill content served live from impeccable.style by its installer |
| `emil-design-eng` | Motion & the invisible details that make UI feel great (Emil Kowalski) | [emilkowalski/skill](https://github.com/emilkowalski/skill) · no stated license (fetched from source, never redistributed) |
| `design-taste-frontend` | Reads the brief, picks a direction, ships non-templated landing/portfolio | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) · no stated license (fetched from source) |
| `high-end-visual-design` | Agency-grade visual bar — the exact fonts/spacing/shadows that read "expensive" | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) · no stated license (fetched from source) |
| `redesign-existing-projects` | Upgrade an existing UI to premium without breaking it | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) · no stated license (fetched from source) |
| `psi-optimize` | PageSpeed/Lighthouse audit + fix loop: image compression (WebP), LCP preload, lazy-loading, render-blocking fixes | ships with this kit (`skills/`) · MIT |
| `a11y-audit` | WCAG 2.1 AA audit + fix loop: contrast, alt/accessible names, focus, labels, structure, keyboard + screen-reader verify. Ships a pure-Node contrast checker | ships with this kit (`skills/`) · MIT |
| `meta-audit` | Pre-ship public-page check: title/description, canonical, OG + Twitter cards, favicons, viewport, lang, robots, sitemap. Ships a `<head>` scanner | ships with this kit (`skills/`) · MIT |
| `seo-audit` | Technical + on-page SEO diagnosis: meta, indexing, internal links | [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) · MIT |
| `ai-seo` | Get cited by AI answers (AI Overviews, ChatGPT, Perplexity) | [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) · MIT |
| `schema` | Structured data / rich snippets done right | [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) · MIT |
| `programmatic-seo` | SEO pages at scale from templates + data | [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) · MIT |
| `site-architecture` | Page hierarchy, navigation, URL + internal-link planning | [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) · MIT |
| `cro` | Conversion-rate optimization for marketing pages + forms | [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) · MIT |
| `stop-slop` | Strips AI tells from prose; pairs with the voice keep/ban list in `DESIGN.md` | [hardikpandya/stop-slop](https://github.com/hardikpandya/stop-slop) · MIT |
| `superpowers` (brainstorming, writing-plans, …) | Design-before-code + planning discipline | `claude-plugins-official` marketplace |

`install-skills.sh` installs the **fourteen machine-wide rows** above (eleven
from upstream, pinned in `versions.lock` to verified commits with an explicit
folder allowlist — upstream repos contain more: builds for other editors, style
packs, ~40 marketing skills, GPT variants, deliberately not installed; plus
three bundled with this kit). `impeccable` installs per-project via
`npx -y impeccable@<pinned> skills install --yes`, and `superpowers` via
`/plugin`.

Why perf / a11y / meta / SEO live in a *design* kit: a page can be beautiful and
still fail if it loads in six seconds, can't be operated by keyboard, has a
blank share preview, or never gets found. The four ship-clean pillars —
performance (`psi-optimize`), accessibility (`a11y-audit`), pre-ship metadata +
prose (`meta-audit`, `stop-slop`), and findability (the SEO set) — are the
"ship clean" half of the same discipline. `CLAUDE.md` runs them before any
public page goes live.

### Optional extras (not auto-installed — add if you want them)

- **`minimalist-ui`**, **`industrial-brutalist-ui`** — opinionated style packs
  from the same `Leonxlnx/taste-skill` repo, for when the brand genuinely is
  that.
- **gstack design suite** (`/design-review`, `/design-shotgun`) — live visual
  QA with screenshots, and N-variant comparison boards. MIT,
  [garrytan/gstack](https://github.com/garrytan/gstack).
- **`frontend-design`** — Anthropic's official anti-slop plugin
  (`claude-plugins-official`). Overlaps with `impeccable`; if you install
  both, declare one as primary in `CLAUDE.md` or they'll fight over triggers.
- **MCP servers worth wiring:** the official **Figma MCP** (pull real tokens
  and node screenshots instead of guessing brand values) and **Mobbin MCP**
  (reference screens for the brainstorm phase).

One warning: skills route by description matching. Don't stack five
general-purpose design engines — curate a small set and declare a primary, or
output becomes whichever skill won the routing lottery.

### Avoiding skill routing conflicts

Skills fire when their `description` matches the task. Two engines that both
claim "any UI work" — most commonly `impeccable` and Anthropic's
`frontend-design` — will compete, and you get whichever won the match, not the
one you wanted. Same risk if you add another broad taste skill.

The fix is to **declare a primary in your `CLAUDE.md`** so the choice is
explicit, not luck. The kit's template already names `impeccable` as primary;
if you install an overlapping engine, make the boundary concrete:

```md
## Skill precedence (resolve routing conflicts)
- **Primary design engine: `impeccable`.** It owns project context
  (PRODUCT.md + DESIGN.md), craft, polish, and audits. Always invoke it for UI.
- `frontend-design` (if installed): do NOT use for general UI — it overlaps
  with impeccable. Reserve it for <one specific case, or remove it>.
- `emil-design-eng` / `high-end-visual-design` *sharpen* impeccable's output
  (motion, premium polish) — they don't replace it.
```

Rule of thumb: one primary engine; everything else either owns a **distinct
domain** (a11y, meta, perf, SEO, prose) or is explicitly a *refiner* of the
primary. If two skills still fight, narrow or remove one — don't hope.

---

## Honest notes

- **The skills belong to their authors.** This kit links to and installs them
  from source; it doesn't bundle or relicense them. Credit and licenses stay
  with the upstream repos above. If you fork this kit, keep it that way.
- **Versions are pinned on purpose.** Upstream skill repos change shape (an
  `impeccable` rewrite once silently broke this kit's core mechanism). Every pin
  — skill commits and the `impeccable` CLI — lives in `versions.lock` (one
  place to edit); `bash install-skills.sh --check-updates` reports drift,
  `--latest` rides HEAD. One honest caveat: `impeccable`'s skill *content* is
  downloaded live from impeccable.style by its own installer — the kit pins the
  CLI, not that bundle.
- **Stack-agnostic.** The postulates and the design-system-first rule are
  identical for web or mobile; the design skills lean web, but
  "tokens/components, never raw values" transfers to SwiftUI, Flutter, etc.
- **The kit solves design quality, not demand.** A beautiful product can still
  fail; ship, measure, and let evidence kill or keep ideas.
- **The templates are a starting point.** Fork them, make them yours. The
  point is the *discipline* — brand first, system first, design before code,
  verify with eyes, no slop.

## License
The kit's own files (`README.md`, the scripts, `template/*`, the bundled
`skills/*`) are MIT — see [LICENSE](LICENSE). Skills installed from upstream
retain their own licenses.

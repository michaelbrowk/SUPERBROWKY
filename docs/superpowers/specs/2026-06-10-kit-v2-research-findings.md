# Kit v2 — what the research found (and what changed)

**Date:** 2026-06-10. **Method:** mined four real production projects built
with this workflow (two iOS apps, a SaaS, a portfolio) — their design
infrastructure plus ~350MB of Claude Code session transcripts — for the
patterns that *actually* produced non-generic design. Cross-checked the kit's
claims against live upstream skill repos.

## Why v2 was necessary (breaking changes upstream)

1. **Current `impeccable` no longer reads `.impeccable.md`.** It now runs a
   context script that reads **`PRODUCT.md`** (strategy/brand) and
   **`DESIGN.md`** (visual system, optional — printed when present), and
   hard-stops without `PRODUCT.md`. The kit's core mechanism was silently
   broken for fresh installs. → Templates replaced with
   `PRODUCT.md` + `DESIGN.md`; `CLAUDE.md` also mandates reading them directly,
   so the kit no longer depends on any skill's internals.
2. **`polish` is no longer a standalone skill** — it's `/impeccable polish`.
3. **The old installer copied every `SKILL.md` folder** from upstream repos:
   13 editor-specific duplicates of impeccable (last-one-wins by filesystem
   order — could install the Kiro build, broken for Claude Code) and 13
   taste-skill folders including GPT/Stitch variants and a global
   output-behavior override the README never mentioned. → Explicit per-folder
   allowlist, install under frontmatter names, pinned commits with `--latest`
   escape hatch, pre-kit originals preserved in `~/.claude/skills-backup/`
   instead of silent `rm -rf`, and `impeccable` installed per-project via its
   own official `npx` installer (pinned CLI version, `--yes` for non-TTY runs).

## The patterns that made design good (now in the templates)

Each of these earned its place by recurring across at least two of the four
projects, usually born from a real correction:

- **Skill invocation cadence.** "Use the design skills" decays into either
  skipping (slop returns) or per-tweak re-invocation (ritual noise). The
  battle-tested rule: invoke all three at the first design output of a
  session, *announce it in one line* so the human can audit, cite afterwards,
  re-invoke on context shift; domain skill (motion, prose) at first mention of
  its domain; never paraphrase a skill rule from memory — one project shipped
  a soft-hallucinated motion value that the skill text actually bans.
- **The mock is ground truth, fetched fresh.** The three most expensive
  failures in the archive were: trusting extracted design-context code
  (silently dropped a visible button), speccing a surface from platform
  conventions instead of fetching its node (5 wrong values, hours of rework),
  and not re-fetching after the user updated the mock. → postulate 3.
- **Source ordering with an adoption threshold.** Components first (≥80% fit →
  adopt, don't rebuild), then tokens, then mock — born from re-designing a
  button that already existed in the project's design system.
- **Never platform defaults when the project has its own.** The single most
  repeated correction class across both iOS projects (system icons, stock
  sheets, ad-hoc text fields). Same family: no call-site overrides of
  design-system components — fix centrally.
- **An enumerated banned-pattern list beats "avoid AI slop".** Naming the
  tells (purple gradients, three equal cards, icon-in-colored-square, fake
  counters, "Elevate" copy, scale(0) entrances…) made the slop test checkable.
  Plus the named rescue pattern: a boring repetitive list gets an *editorial*
  fix (strip chrome, dividers, meta column), not a brighter re-skin.
- **Quantified atmosphere.** "Density 3/10, Motion 7/10" calibrates better
  than adjectives; references with *roles* ("Vercel structurally, Linear for
  density") beat reference name-drops.
- **Falsifiable brand principles.** "One accent. Earn it." is testable against
  a diff; "feel premium" is not. Also: the naming caveat ("the product is
  called Pinky; the brand is navy — the name lies") pre-empts the model's most
  likely wrong inference.
- **Verification with eyes, enumerated.** Real browser/device pass top to
  bottom; 375/768/1280; light AND dark (two shipped bugs were invisible in the
  default appearance); the human approves a *screenshot*, not a description.
- **Design-lint subagent.** Written bans decay (7 system icons shipped despite
  a written ban); a cheap read-only lint pass over every UI diff is the
  enforcement layer.
- **Anti-slop needs voice exceptions.** A blanket em-dash ban sanded off a
  real author's voice — `DESIGN.md` carries keep/ban lists.
- **Capture the lesson.** Every project that compounded quality did it through
  a correction→written-rule loop; the same mistake twice means the rule wasn't
  specific enough.
- **Reference-anchored brainstorms.** Annotated references produced usable
  direction every time; "полная свобода / full creative freedom" redesigns
  were all reverted.

## Deliberately left out (scope discipline)

Multi-agent team personas, marketing/CRO skills, image-generation pipelines,
visual-regression harnesses (frozen baselines + pixel diff), Figma-specific
double-fetch mechanics beyond one postulate line — all real, all valuable,
all too project-specific or too heavy for a starter kit whose audience pastes
one link into Claude Code. Candidates for a v3 "advanced" doc.

## One honest data point

The best-designed project in the research set was still mothballed, per its
pre-set kill criterion. The kit solves design quality, not demand — the README
now says so.

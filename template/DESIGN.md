# Design System

> ⚠ PLACEHOLDERS PRESENT — this file has not been filled in yet. For mutating
> visual work, fill the relevant sections with the user or extract a proposal
> from existing code. A read-only audit may continue if it clearly states the
> missing context.
>
> This becomes the accepted visual system after human review. Before that,
> generated values are proposals, not rules. Concrete values belong in token
> definitions; feature code consumes those tokens. If this file, code, and the
> current design source disagree, record `CONFLICT` and resolve it instead of
> silently choosing a winner. Delete this quote block when the file is real.

## Authority

- **Artifact ID:** <stable ID, e.g. DESIGN-v1>
- **Version:** <version, e.g. 1.0>
- **Status:** DRAFT_PROPOSAL | ACCEPTED | SUPERSEDED
- **Accepted by:** <human name, or not yet accepted>
- **Accepted on:** <YYYY-MM-DD, or not yet accepted>
- **Decision reference:** <Decision.md entry, or none>

Only a human decision may set `Status` to `ACCEPTED`. Until then, values below
are proposals and may be used for explicitly authorized exploration, not as
canonical rules.

## Atmosphere

Quantified personality — a number the model can calibrate against, instead of
guessing what "minimal-ish" means.

- **Density:** <N>/10 — <e.g. 3/10 "art-gallery airy" / 8/10 "trading-terminal dense">
- **Loudness:** <N>/10 — <how much the UI is allowed to shout; what earns emphasis>
- **Motion:** <N>/10 — <e.g. 2/10 "almost still" / 7/10 "fluid springs everywhere">
- **Supported appearance:** <light, dark, or both, and WHY — derived from the
  audience + viewing context rather than a generic default>
- **References with roles:** <2–3 products and what each contributes — e.g.
  "Vercel structurally, Linear for density, Raycast grants permission for hero
  moments". Roles beat vibes.>
- **The one memorable thing:** <what should someone remember? what makes it
  "how was this made?", not "which AI made this?">

## Color

Canonical runtime values live in:
`<path — e.g. tokens.css / theme.ts / Theme.swift>`.
This file defines accepted roles, intent, and constraints; it does not keep a
second hand-maintained copy of runtime hex values. Any accepted color change
updates the token source and this role map in the same reviewed change.

| Role | Token | Intent | Constraints |
|---|---|---|---|
| Background | <token> | <visual role> | <e.g. avoid pure black/white unless intentional> |
| Surface / card | <token> | <visual role> | |
| Text primary | <token> | <visual role> | <contrast target> |
| Text muted | <token> | <visual role> | <contrast target> |
| Accent | <token> | <intended emphasis> | <where it may appear> |
| Destructive / status | <token> | state communication | functional only |

Rules:
- **Accent policy:** <one restrained accent, a committed brand color, a full
  palette, or another accepted strategy; state where each role may appear>.
- **Functional colors communicate state, never ornament.** Red/green/amber may
  only appear when something IS in that state; a resting screen is neutral.
- **Never hide an invented hex in feature code.** If no token fits, propose a
  token-system change and get it accepted before implementation.
- **Gradients:** <policy — e.g. "one gradient, one purpose: the primary CTA.
  When the gradient is scarce, it's valuable." Or "none.">

## Typography

Fonts: <display + body pairing, chosen for the product, language coverage,
performance, licensing, and brand rather than novelty alone.> Weights allowed:
<a deliberate set — e.g. 400 / 510 / 590. Explain how emphasis works.>

The registers — a **closed set**. Adding one is a design decision, not a
styling shortcut:

| Register | Size | Weight | Line-height | Tracking | Used in |
|---|---|---|---|---|---|
| Display | <…> | <…> | <…> | <…> | <hero only> |
| Heading | <…> | <…> | <…> | <…> | |
| Body | <…> | <…> | <…> | <…> | |
| Caption | <…> | <…> | <…> | <…> | <one muted color, everywhere the same> |
| Mono | <…> | <…> | <…> | <…> | <numbers, timecodes, code> |

## Spacing & radii

- **Spacing scale:** <e.g. 4pt scale: 4/8/12/16/24/32/48/64 — nothing between>
- **Radius scale:** <e.g. 4/8/16/24; children always use a strictly smaller
  radius than their parent>
- **Shadows:** <one or two named shadows max, one shadow color token>

## Motion

Numbers, not adjectives — "fluid" is unactionable.

- **Durations:** <e.g. 120ms micro / 200ms standard / 300ms large. Nothing over ~400ms>
- **Easing:** <named tokens — e.g. ease-out entrances, custom cubic-bezier(...) — never `linear`, never `ease-in` on entry>
- **Springs (if used):** <exact params — e.g. response 0.35, damping 0.5>
- **Banned:** bounce on UI chrome, scale-from-0 entrances, `transition: all`,
  decorative motion on every interaction.
- **Delight budget:** celebration effects only for enumerated moments:
  <list them — e.g. "first publish, streak unlocked" — never routine actions>.
- **Reduced motion:** every animation has a `prefers-reduced-motion` fallback
  (<e.g. 0.2s ease-out fade>). Non-negotiable.

## Components

Components live in: `<path>`. New shared surface goes into the component
library, not into a page/screen file — every new screen is born on-system.

| Design name | Code | Notes |
|---|---|---|
| <Button / Primary> | <file/component> | <variant intent — when to use which> |
| <Sheet / Modal> | <…> | <e.g. "all popups enter bottom-up, like every sheet"> |
| <…> | <…> | |

- **Sacred components:** <the ones that must never be redesigned or re-skinned
  per-context — e.g. the primary button>.
- **Icons:** <source — project set / library. If the project has its own set,
  platform-default icons (SF Symbols, stock lucide) are banned.>

## Voice

- **Keep (author's voice — exempt from anti-slop passes):** <e.g. "em-dashes —
  they're how I write">
- **Ban:** <AI tells in YOUR copy — e.g. semicolons, "Elevate/Seamless/Unleash",
  "Oops!", exclamation-point enthusiasm, emoji in UI copy>
- **Honest copy:** state facts, not vibes. ✅ "<right example>" ❌ "<wrong example>"

## Banned patterns

Candidate failure patterns to review with the human. They become binding only
after this file is accepted. Delete anything the brand intentionally uses and
add category-specific traps:

- Purple/cyan gradients on dark; gradient text; glassmorphism as decoration
- Three equal feature cards in a row (use asymmetric layouts); icon-in-colored-
  square feature lists; left-border accent stripes
- Centered card on a radial-gradient void; curved SVG section dividers
- "Welcome back!" / "Elevate your workflow" copy; fake counters ("1,000+ users");
  "John Doe" placeholders; sparkles ✨ as decoration
- People-at-laptops stock illustration; emoji as icons or image placeholders
- scale(0)→1 entrances, `ease-in` on enter, circular spinner as the only
  loading state, floating-label inputs
- When a list of 3+ similar items feels busy or boring: the fix is editorial —
  strip card chrome, one container, dividers, a meta column — NOT another
  card re-skin with brighter colors
- <your brand's specific traps — what would make this look like every other
  AI-generated product in your category?>

## Evolution

Append-only log of accepted changes (what + why + date). It supersedes older
plans, memories, and screenshots. If code and this file disagree, record the
conflict and resolve it deliberately rather than silently forking either
source.

- <date> — initial system.

# Design System

> ⚠ PLACEHOLDERS PRESENT — Claude: if you can read this line, this file hasn't
> been filled in yet. STOP and fill it with the user (or run
> `/impeccable document` to harvest values from existing code) before any
> visual work.
>
> The visual constitution: exact values, hard caps, banned patterns. Claude
> reads it before any visual code; the `impeccable` skill reads it too.
> **If a value isn't in here (or in the token files it points to), it doesn't
> exist — never invent a hex.** `/impeccable document` can draft the values
> from existing code, but it proposes a different (Stitch) section layout —
> MERGE its values into the sections below; never let it replace this file.
> Atmosphere / Voice / Banned patterns are what the design-lint pass checks.
> Keep this file and the code tokens in lockstep — when they disagree,
> reconcile immediately; two sources of truth WILL drift. Delete this quote
> block when the file is real.

## Atmosphere

Quantified personality — a number the model can calibrate against, instead of
guessing what "minimal-ish" means.

- **Density:** <N>/10 — <e.g. 3/10 "art-gallery airy" / 8/10 "trading-terminal dense">
- **Loudness:** <N>/10 — <how much the UI is allowed to shout; what earns emphasis>
- **Motion:** <N>/10 — <e.g. 2/10 "almost still" / 7/10 "fluid springs everywhere">
- **Light or dark:** <which, and WHY — derived from the audience + viewing
  context ("used courtside at night → dark only"), not a default>
- **References with roles:** <2–3 products and what each contributes — e.g.
  "Vercel structurally, Linear for density, Raycast grants permission for hero
  moments". Roles beat vibes.>
- **The one memorable thing:** <what should someone remember? what makes it
  "how was this made?", not "which AI made this?">

## Color

Tokens live in: `<path — e.g. tokens.css / theme.ts / Theme.swift>`. Roles, not
hexes, in code; this table is the only place hex values are written by hand.

| Role | Token | Value | Notes |
|---|---|---|---|
| Background | <token> | <hex> | <never pure #000 / #fff unless the brand says so> |
| Surface / card | <token> | <hex> | |
| Text primary | <token> | <hex> | |
| Text muted | <token> | <hex> | |
| Accent | <token> | <hex> | ~10% of visual weight, by design |
| Destructive / status | <token> | <hex> | functional ONLY — see rule below |

Rules:
- **One accent per screen.** The accent appears on the primary action and
  earned moments — never for polish or decoration.
- **Functional colors communicate state, never ornament.** Red/green/amber may
  only appear when something IS in that state; a resting screen is neutral.
- **Never invent a hex.** If nothing in the table fits, the design is wrong —
  flag it, don't improvise.
- **Gradients:** <policy — e.g. "one gradient, one purpose: the primary CTA.
  When the gradient is scarce, it's valuable." Or "none.">

## Typography

Fonts: <display + body pairing. Avoid the AI defaults (Inter, Space Grotesk,
Fraunces, Syne…) unless the brand genuinely chose them.> Weights allowed:
<a strict, small set — e.g. 400 / 510 / 590. Emphasis via size or color, NEVER
by escalating weight.>

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

The AI Slop Test, operationalized. Check every diff against this list; add the
tells you keep catching. Starter set — **delete what your brand actually wants**:

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

Append-only log of deliberate changes (what + why + date). This file outranks
older plans, memories, and screenshots — if code and this file disagree,
reconcile here, don't fork.

- <date> — initial system.

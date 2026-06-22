# a11y fixes catalog

Recipes for the findings in `SKILL.md`. Each entry: the symptom, the WCAG
criterion, and the concrete fix. Prefer native semantics; reach for ARIA only
when no native element fits.

## contrast {#contrast}

**WCAG 1.4.3 (AA).** Text needs ≥ 4.5:1 against its background; large text
(≥ 24px, or ≥ 18.66px bold) needs ≥ 3:1. UI component boundaries and meaningful
graphics need ≥ 3:1 (1.4.11).

- Measure first: `scripts/contrast-check.mjs "<fg>:<bg>"`. Don't guess.
- Fix the **token**, not the instance. If `--text-muted` fails on
  `--surface`, darken the token in `DESIGN.md` / the token file so every use is
  fixed at once.
- Common offenders: placeholder text (`::placeholder` often inherits a too-light
  grey), disabled text (exempt from 1.4.3, but if it must be read, keep it
  legible), text over images/gradients (add a scrim layer, not a text-shadow),
  light brand color used as text (e.g. a bright accent that only works as a
  fill, never as type).
- Never "fix" contrast with `text-shadow`/`-webkit-text-stroke` — scanners and
  real low-vision users both see through it.

## accessible names {#names}

**WCAG 1.1.1, 4.1.2.** Every operable control and meaningful image needs a
name.

```html
<!-- icon-only button: name it -->
<button aria-label="Close dialog"><svg aria-hidden="true">…</svg></button>

<!-- icon + text: the text IS the name; hide the icon from AT -->
<button><svg aria-hidden="true">…</svg> Save</button>

<!-- meaningful image: describe the meaning, not "image of" -->
<img src="chart.png" alt="Revenue up 30% quarter over quarter">

<!-- decorative image: empty alt (present, not missing) -->
<img src="divider.svg" alt="">

<!-- icon-only link -->
<a href="/cart" aria-label="Cart, 3 items"><svg aria-hidden="true">…</svg></a>
```

Rules: mark decorative SVGs `aria-hidden="true"` (or `role="img"` +
`aria-label` if meaningful). Don't put the same text in both visible label and
`aria-label` (the aria-label wins and overrides the visible one — confusing for
voice-control users who say what they see).

## forms {#forms}

**WCAG 1.3.1, 3.3.2.** Every input needs a programmatically-associated label.

```html
<!-- explicit association — preferred -->
<label for="email">Email</label>
<input id="email" type="email" name="email">

<!-- placeholder is NOT a label (vanishes on input, often low-contrast) -->

<!-- group related controls -->
<fieldset><legend>Notification frequency</legend> …radios… </fieldset>
```

Errors (3.3.1): tie the message to the field with `aria-describedby`, set
`aria-invalid="true"`, and move focus to the first error on submit. Don't rely
on color alone to signal the error (1.4.1) — add an icon or text.

## focus {#focus}

**WCAG 2.4.7.** Keyboard focus must be visible. If you reset the outline, you
**must** restore a visible indicator.

```css
/* never ship this alone */
:focus { outline: none; }

/* do this: ring only for keyboard users, not mouse clicks */
:focus-visible {
  outline: 2px solid var(--focus-ring, #2563eb);
  outline-offset: 2px;
}
```

The ring must itself meet 3:1 against adjacent colors. For custom widgets,
manage focus order with `tabindex="0"` (never positive values) and roving
tabindex for composite widgets (menus, tabs, grids).

## structure {#structure}

**WCAG 1.3.1, 2.4.1, 2.4.6.**

- Exactly one `<h1>` per page; don't skip levels (h2 → h4). Headings describe
  structure, not styling — never pick a heading level for its font size.
- Wrap content in landmarks: `<header>`, `<nav>`, `<main>` (one, the primary
  content), `<footer>`. Everything meaningful lives inside a landmark.
- Skip link as the first focusable element:
  ```html
  <a href="#main" class="sr-only focus:not-sr-only">Skip to content</a>
  …
  <main id="main">…</main>
  ```
- Reading/DOM order matches visual order (don't reorder with CSS in a way that
  breaks tab sequence).

## lang {#lang}

**WCAG 3.1.1.** `<html lang="en">` (the actual language). Mark inline language
switches with `lang` on the element. Screen readers pick the wrong voice/pron-
unciation without it.

## aria {#aria}

**WCAG 4.1.2.** First rule of ARIA: don't use ARIA if a native element does the
job. When you must:

- Use a real role + its required states (`role="dialog"` needs
  `aria-modal="true"` + a labelled name; `role="tab"` needs `aria-selected` and
  `aria-controls`).
- Don't put interactive roles on non-interactive parents, or `aria-hidden="true"`
  on anything focusable.
- For dynamic updates (toasts, validation, async results) use a live region:
  `aria-live="polite"` (or `assertive` for urgent), present in the DOM **before**
  the content changes.
- Prefer a vetted headless library (Radix, React Aria, Headless UI) for complex
  widgets over hand-rolling ARIA — they encode the keyboard + state contracts.

## motion {#motion}

**WCAG 2.3.3 (AAA) + good practice.** Respect the OS "reduce motion" setting for
non-essential animation; never auto-play motion that can trigger vestibular
issues.

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

In JS/React, gate spring/scroll animations on
`window.matchMedia("(prefers-reduced-motion: reduce)").matches` and offer a
static end-state. Auto-advancing carousels need a visible pause control (2.2.2).

## targets & spacing {#targets}

**WCAG 2.5.8 (AA, 2.1).** Interactive targets ≥ 24×24px (or adequate spacing).
Don't pack icon buttons edge to edge; give touch targets ~44px where the design
allows. Increase the hit area with padding, not a bigger glyph.

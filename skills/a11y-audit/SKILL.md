---
name: a11y-audit
description: Audit web accessibility against WCAG 2.1 AA and fix the findings end-to-end. Runs axe-core / Lighthouse / pa11y, then fixes the common failures — missing alt text and accessible names, contrast below 4.5:1, no visible focus, unlabelled form controls, broken heading order, missing lang, no skip link, motion that ignores prefers-reduced-motion, keyboard traps. Use when the user mentions accessibility, a11y, WCAG, axe, screen reader, keyboard navigation, focus, contrast, aria, alt text, "is this accessible", or an accessibility audit/lawsuit/VPAT.
user-invocable: true
argument-hint: "[url]"
---

# a11y-audit — WCAG compliance + fix loop

The accessibility half of "ship clean". A page can be beautiful, fast, and
found and still fail the bar if a keyboard user can't operate it or a
screen-reader user can't parse it. Same discipline as `psi-optimize`: measure,
fix one category at a time, re-measure. Don't theorize about edge cases — the
top eight failures cover ~90% of real findings.

## Philosophy

Most a11y bugs are **boring and mechanical**, and a handful dominate every
audit (axe's own data, year after year):

1. **Text contrast** below 4.5:1 — grey-on-white body copy, placeholder labels.
2. **Images without alt** / **controls without an accessible name** (icon
   buttons, icon-only links).
3. **Form inputs not associated with a label.**
4. **No visible focus indicator** (someone removed the outline and never
   replaced it).
5. **Wrong/duplicate landmark or heading structure** (multiple `h1`, skipped
   levels).

Fix those five and you clear the majority of the score. The long tail (ARIA
misuse, live regions, complex widgets) matters but comes after.

**Never claim "accessible" from a passing automated scan alone.** axe catches
~30–40% of WCAG issues. The keyboard pass and one screen-reader pass below are
not optional — they catch what no scanner can.

## Workflow

### 1. Measure

```bash
# axe-core CLI — the standard. No install needed via npx.
npx -y @axe-core/cli <URL> --tags wcag2a,wcag2aa

# Lighthouse accessibility category (also gives a single score)
npx -y lighthouse <URL> --only-categories=accessibility --output=json \
  --output-path=/tmp/a11y.json --quiet \
  && node -e 'const a=require("/tmp/a11y.json").audits;Object.values(a).filter(x=>x.score!==null&&x.score<1).forEach(x=>console.log(x.score,x.id))'

# pa11y — fallback, uses HTML CodeSniffer ruleset
npx -y pa11y --standard WCAG2AA <URL>
```

If the project is a component library or there's no running URL, scan source
directly (see "Static scan" below) and reason from the markup.

### 2. Diagnose — map findings to fixes

| axe / Lighthouse finding | Root cause | Fix recipe |
|---|---|---|
| `color-contrast` | fg/bg ratio < 4.5:1 (3:1 large) | `references/fixes-catalog.md#contrast` + `scripts/contrast-check.mjs` |
| `image-alt`, `input-image-alt` | `<img>` / image input with no `alt` | `references/fixes-catalog.md#names` |
| `button-name`, `link-name` | icon-only control, no text or `aria-label` | `references/fixes-catalog.md#names` |
| `label`, `form-field-multiple-labels` | input not tied to a `<label for>` | `references/fixes-catalog.md#forms` |
| `focus`/missing outline (manual) | `outline:none` with no `:focus-visible` | `references/fixes-catalog.md#focus` |
| `heading-order`, `page-has-heading-one` | skipped levels / no/many `h1` | `references/fixes-catalog.md#structure` |
| `html-has-lang`, `valid-lang` | missing/wrong `<html lang>` | `references/fixes-catalog.md#lang` |
| `aria-*` (allowed-attr, required-attr, roles) | hand-rolled widget, misused ARIA | `references/fixes-catalog.md#aria` |
| `region`, `landmark-*` | content outside any landmark | `references/fixes-catalog.md#structure` |
| motion (manual) | animation ignores `prefers-reduced-motion` | `references/fixes-catalog.md#motion` |

### 3. Fix — one category per pass

Apply the recipe from `references/fixes-catalog.md`. Keep it to one category per
PR — easier to re-scan the delta. **Prefer native semantics over ARIA**: a real
`<button>`/`<a>`/`<label>` is correct by default; ARIA is a patch for when you
can't use the right element, and wrong ARIA is worse than none.

### 4. Verify — the part scanners can't do

Three checks, every time, before claiming done:

1. **Keyboard.** Unplug the mouse. `Tab` through the whole page: every
   interactive element reachable, in a sensible order, with a **visible** focus
   ring; `Enter`/`Space` activate; `Esc` closes overlays; focus is **trapped**
   inside open modals and **returns** to the trigger on close; no keyboard trap.
2. **Screen reader, one pass.** VoiceOver (`Cmd+F5` on macOS) or NVDA. Tab
   through controls — each announces a clear name + role. Images convey meaning
   or are silent if decorative. Form errors are announced.
3. **Zoom + reflow.** 200% browser zoom and a 320px-wide viewport: no content
   lost, no horizontal scroll on body text (WCAG 1.4.10).

Re-run the scanner after fixes; the targeted findings should be gone.

## Contrast — the most common single failure

Use the bundled checker (pure Node, no deps) before hand-picking any color:

```bash
# explicit foreground:background pairs
node ~/.claude/skills/a11y-audit/scripts/contrast-check.mjs "#6b7280:#ffffff" "#111827:#fff"

# scan a token file — pairs every --text-*/--fg-* against every --bg-*/--surface-*
node ~/.claude/skills/a11y-audit/scripts/contrast-check.mjs --css app/globals.css

# large text (≥24px, or ≥19px bold) uses the 3:1 line
node ~/.claude/skills/a11y-audit/scripts/contrast-check.mjs --large "#9ca3af:#fff"
```

It prints the real ratio + AA/AAA verdict and **exits non-zero on any AA
failure**, so you can gate CI on it. Thresholds: 4.5:1 normal text, 3:1 large
text (AA); 7:1 / 4.5:1 (AAA). The fix is never "add a text-shadow" — adjust the
token so the ratio passes, and fix it in `DESIGN.md`, not at the call site.

## Static scan (no running URL)

Grep the source for the cheap wins before any browser run:

```bash
# <img> without alt (flag for review — some may be legit decorative)
grep -rnE '<img(?![^>]*\balt=)' src --include=*.tsx --include=*.jsx --include=*.html

# outline:none / outline:0 — must be paired with a :focus-visible style
grep -rnE 'outline:\s*(none|0)' src

# icon-only buttons/links with no aria-label (heuristic — review hits)
grep -rnE '<(button|a)[^>]*>\s*<(svg|Icon|i)\b' src
```

These are leads, not verdicts — confirm in the rendered DOM.

## What NOT to chase

- **`aria-hidden` on focusable content** is a real bug, but don't sprinkle
  `aria-*` to silence a scanner — fix the underlying semantics instead.
- **Decorative images** correctly take `alt=""` (empty, not missing) — that's a
  pass, not a finding.
- **Third-party embeds** (maps, payment iframes, chat widgets) you can't edit:
  note them, route to the vendor, don't fake a fix.
- **AAA everywhere.** AA is the ship bar. Pursue AAA only where the brand or
  audience demands it; chasing 7:1 on every label distorts the palette.

## Verification before claiming done

- axe/Lighthouse re-run: the targeted findings are gone (record before/after
  counts + the a11y score).
- Keyboard pass completed top to bottom, focus visible throughout.
- One screen-reader pass: names + roles announced, errors announced.
- `contrast-check.mjs` exits 0 on the token set.

## Output format for reports

Markdown table: finding · WCAG criterion · file:line · fix · status. Lead with
the score before/after and the keyboard/SR verdict — those are the real signal,
not the automated count.

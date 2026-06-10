---
name: psi-optimize
description: Audit PageSpeed Insights / Lighthouse findings and fix them end-to-end. Compresses oversized images (sharp — re-encode to WebP, resize to display dimensions), wires LCP preload + fetchpriority, adds preconnect hints for third-party origins, converts below-fold <img> to lazy, defers non-critical JS, and applies framework-specific patterns (Next.js, Vite/SvelteKit, Astro, plain HTML). Use when user mentions PageSpeed Insights, PSI, Lighthouse, Core Web Vitals, LCP, FCP, CLS, TBT, INP, slow page, performance audit, image compression, or "why is my site slow".
user-invocable: true
argument-hint: "[url]"
---

# PSI-Optimize — PageSpeed compliance + image compression

Web perf audit-and-fix workflow focused on what PSI actually measures and what will actually move the score. Opinionated. Hands-on. Measured.

## Philosophy

Most PSI fixes are **boring and mechanical**. Don't theorize — measure, diagnose, fix one finding at a time, re-measure. The gap between a 40 and a 90 on mobile is almost always:

1. One oversized LCP image that isn't preloaded  
2. A blocking script or font  
3. Render-blocking CSS  
4. Layout shift from un-dimensioned images or late-mounting components

The hero LCP image alone is typically 70% of the problem. Start there.

**Never guess at savings.** Use real PSI data or run Lighthouse locally. A fix only counts if PSI measures the improvement.

## Workflow

### 1. Measure

```bash
# Ideal: PSI API with your own key (no quota issues)
curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=<URL>&strategy=mobile&category=performance&key=<KEY>" | jq '.lighthouseResult'

# Fallback: unauthenticated (shared daily quota, often exhausted)
curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=<URL>&strategy=mobile&category=performance" | jq .

# Fallback #2: local Lighthouse (install once: `pnpm -g add lighthouse`)
lighthouse <URL> --preset=mobile --only-categories=performance --output=json --output-path=/tmp/lh.json --quiet && jq '.audits | to_entries | map(select(.value.score != null and .value.score < 1)) | map({id: .key, score: .value.score, savings: .value.details.overallSavingsBytes})' /tmp/lh.json
```

If the user shows you a PSI screenshot instead, read **Est Savings** per finding and tackle them in descending order.

### 2. Diagnose — map findings to fixes

Common PSI findings and the files/patterns to target. For detail per finding, read `references/fixes-catalog.md`.

| PSI finding | Root cause to look for | See |
|---|---|---|
| Improve image delivery | Oversized PNG/JPG, raw `<video poster>`, non-optimized hero | `references/images.md` |
| LCP request discovery | Missing `fetchpriority=high`, missing `<link rel=preload>` | `references/fixes-catalog.md#lcp-discovery` |
| Render blocking requests | Fonts without `font-display: swap`, non-inlined critical CSS, blocking scripts | `references/fixes-catalog.md#render-blocking` |
| Avoid chaining critical requests | Missing preconnect to third-party origins | `references/fixes-catalog.md#preconnect` |
| Efficient cache lifetimes | Short `Cache-Control max-age` on static assets | `references/fixes-catalog.md#cache` |
| Unused JavaScript | Unsplit bundles, vendor chunks loaded everywhere | `references/framework-nextjs.md` (dynamic imports, route-level splits) |
| Forced reflow | `offsetWidth`/`getBoundingClientRect` reads after DOM writes | Requires Chrome DevTools profiling — no one-shot fix |
| CLS / Layout shift | `<img>` without width/height, late-mounting fonts, web-font swap flash | `references/fixes-catalog.md#cls` |

### 3. Fix — per category

For each finding, apply the recipe from the reference files. **One category per PR** — easier to measure the delta.

### 4. Verify

Re-run PSI after each fix lands. The delta should match the "Est Savings" from the finding, within ~15%. If not, the fix didn't land correctly (wrong path, cache miss, CDN not invalidated).

## Image compression — the big one

Almost every slow page has one or more oversized raster images. The fixes, in order of impact:

1. **Resize to display dimensions × 2 (for DPR).** Image intrinsic should not exceed ~2× display size. Anything bigger is wasted bandwidth — the browser scales down on paint.
2. **Re-encode to WebP or AVIF.** PNG is 2–5× larger than WebP q85 for photos. AVIF is ~20% smaller than WebP but has slower encode/decode; for LCP hero WebP is the safer bet.
3. **For lossy-acceptable content (photography, UGC):** quality 82–88 is the sweet spot. Human eye doesn't distinguish from q100, file is 40–60% smaller.
4. **For hard lossless requirement (logos, icons, UI):** SVG if possible. Otherwise PNG with strict-lossless compression (sharp's built-in, or `oxipng` for more).
5. **`<video poster>` attribute bypasses `next/image`.** If your framework auto-optimises `<img>` but a raw `<video poster="…">` points to a PNG, that PNG ships as-is. Re-encode the poster manually.

### Compress script — use this

The skill ships with `scripts/compress-images.mjs` — a reusable sharp-based walker. Run from a project that has `sharp` installed (or install it first: `pnpm add -D sharp`).

```bash
# Dry-run audit — shows every file and predicted savings, writes nothing
node ~/.claude/skills/psi-optimize/scripts/compress-images.mjs --dry apps/web/public/assets

# Apply in place — backs up nothing; run on a clean git tree so you can revert
node ~/.claude/skills/psi-optimize/scripts/compress-images.mjs apps/web/public/assets

# Narrow to one file, custom quality/size
node ~/.claude/skills/psi-optimize/scripts/compress-images.mjs --quality 88 --max-width 1440 path/to/hero.png

# Convert PNG/JPG to .webp sibling (keeps original)
node ~/.claude/skills/psi-optimize/scripts/compress-images.mjs --emit-webp path/to/hero.png
```

Rules the script enforces:
- Never replaces a file if the new encode is larger
- Skips assets under 20KB (noise, not worth it)
- Honors `--dry` strictly — no writes
- Reports bytes before/after and percent per file
- On replace, preserves mtime and permissions

### When to convert `<video poster>`

If PSI flags the LCP as a video poster and it's a PNG:

1. Re-encode poster to WebP at display × 2 dimensions (e.g., 512px display → 1024×1024)
2. Swap the poster URL in code
3. Add `<link rel="preload" as="image" href="<poster>.webp" fetchPriority="high">` in the page head — browser starts fetching at HTML parse, not when it discovers `<video>` downstream

See `references/framework-nextjs.md#video-poster-lcp` for the Next.js App Router pattern.

## LCP checklist

Before you touch anything else, the LCP element must:

- [ ] Be present in the initial HTML (not injected by JS later)
- [ ] Not have `loading="lazy"` (lazy-load kills LCP)
- [ ] Have `fetchpriority="high"` on the `<img>` (or preload link for `<video poster>`)
- [ ] Be preloaded via `<link rel="preload" as="image">` in the head for non-`<img>` LCPs (video posters, CSS backgrounds)
- [ ] Have dimensions or a `sizes` attribute matching its actual display size (no 3840w srcSet entry fetched for a 600px display)
- [ ] Be served as WebP or AVIF (runtime via `next/image` or pre-encoded)
- [ ] Be < 100KB after optimisation in 90% of cases

If the LCP is a `<video>`: either switch the above-fold media to a static `<img>` (LCP is always the poster anyway, not the video itself) or preload the poster as above.

## Gallery / carousel UX — preload via stacking

Symptom: user clicks a thumbnail, waits 1–2 s for the new main image to appear. PSI doesn't flag this (no real-user metric for it), but it's one of the most common user-felt perf complaints on ecom PDPs.

Cause: typical gallery renders **only** the active slot (`{activeSlot?.kind === "image" ? <Image/> : null}`). Each click mounts a new `<Image>`, triggering a fresh network fetch.

Fix: render **all** image slots up-front and toggle visibility via `opacity`. Browser preloads all images on initial render, thumbnail clicks become instant. Example (Next.js App Router):

```tsx
{slots.map((slot, i) =>
  slot.kind === "image" ? (
    <Image
      key={slot.src}
      src={slot.src}
      alt={i === activeIdx ? `${product} — ${variant}` : ""}
      fill
      priority={i === 0}
      loading={i === 0 ? undefined : "eager"}
      sizes="(max-width: 768px) 100vw, 50vw"
      className={cn(
        "absolute inset-0 object-contain transition-opacity duration-200",
        i === activeIdx ? "opacity-100" : "opacity-0"
      )}
      aria-hidden={i !== activeIdx}
    />
  ) : null
)}
```

Rules:
- First slot keeps `priority` (Next emits preload link + fetchpriority=high).
- Others get `loading="eager"` to override Next's default lazy.
- Videos stay mount-on-demand — stacking `<video autoplay>` wastes bandwidth and muddles audio policy.
- For huge galleries (>10 images), fall back to prefetching the next/previous slot on thumbnail hover instead of stacking all.
- Also set `aria-label` on each thumbnail button (otherwise axe + PSI flag "buttons without accessible name").

## Hydration errors that also hurt PSI (React #418, Vue SSR mismatch)

PSI console error audit flags `Minified React error #418` — hydration mismatch. Minified stack is useless. To diagnose:

1. Reproduce in `pnpm dev` (non-minified)
2. Common sources of non-deterministic render:
   - `new Date()` / `Date.now()` / `Math.random()` / `crypto.randomUUID()` in render (use `useEffect` or a stable id prop)
   - `typeof window` branches that skip SSR
   - Locale-dependent `toLocaleString` / `Intl.*` — server and client may run in different locales
   - Client-only state hydrated from `localStorage` / cookies without `suppressHydrationWarning`
3. Hydration errors **do** cost perf: React discards the server HTML and re-renders on the client, delaying TTI.

## Framework-specific patterns

- **Next.js 13+ App Router:** `references/framework-nextjs.md`
- **Vite / SvelteKit / Astro:** `references/framework-vite.md`
- **Plain HTML / Webflow / WordPress:** apply generic recipes from `references/fixes-catalog.md`

## What NOT to optimise

- **Tools outside your control.** MS Clarity, GA4, GTM, Facebook Pixel — their cache/compression is upstream. PSI will keep flagging them; accept the score hit or remove the tracker.
- **Forced reflow from third-party scripts.** Profile first. If it's a vendor script, there's no fix short of removing it.
- **Hyper-micro-optimisations.** A 1KB font variant or 30ms script when LCP is 6 seconds is noise. Always fix the biggest number first.

## Verification before claiming done

Every fix needs a PSI (or Lighthouse) run **before and after** on the same URL. Record:

- PSI score (mobile + desktop)
- LCP, CLS, TBT values
- The specific finding you targeted and its "Est Savings"

If the post-fix measurement doesn't show the expected delta, the fix didn't land. Don't move on.

## Output format for reports

When summarising what you did for a user, use a markdown table with before/after/saving columns. Example in `references/report-template.md`.

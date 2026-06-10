# PSI finding → fix catalog

One-liner mapping from PSI audit name to the concrete recipe. Read the section that matches the finding you're targeting; ignore the rest.

## Improve image delivery (usually the biggest win)

Root causes:
- Raster served at intrinsic size much bigger than display
- PNG/JPG for content that should be WebP/AVIF
- `<video poster>` PNG — bypasses framework image-optim
- Static assets served without content-negotiation to modern formats

Fixes:
- Resize to ~2× display (covers DPR). PSI tells you intrinsic vs display.
- JPG → mozjpeg q85–90 (visually lossless).
- PNG with photo content → WebP q85–90.
- PNG with flat UI → strict-lossless PNG (zlib effort 10), or WebP lossless.
- `<video poster>` → pre-encode a small WebP; swap URL; preload in head.
- See `references/images.md` for detail.

## LCP request discovery

PSI complaints:
- "fetchpriority=high should be applied" — add it on the LCP `<img>` (or `<Image priority>` in Next.js).
- "lazy load applied" on LCP — remove `loading="lazy"`; Next `<Image priority>` handles this.
- LCP not discoverable in initial HTML — SSR the page, or preload with `<link rel="preload" as="image">`.

For `<video poster>` LCP: the `<video>` tag itself doesn't support `fetchpriority`. Preload the poster URL in page head instead:

```html
<link rel="preload" as="image" href="/path/to/poster.webp" fetchpriority="high" />
```

In Next.js App Router, render this as plain `<link>` inside the page component — React 19 + Next 15 hoist resource-hint links to `<head>` automatically. Or use `ReactDOM.preload("/path", { as: "image", fetchPriority: "high" })` from a server component.

## Render blocking requests

Main offenders:
- `<link rel="stylesheet">` without `media`/`disabled`/`print` trickery
- `<script>` without `async`/`defer`
- Web fonts without `font-display: swap`

Fixes:
- Scripts: default to `<script defer>` or `<script type="module">` (always deferred). Third-party: use `next/script` with `strategy="afterInteractive"` or `lazyOnload`.
- Fonts: `next/font` handles this automatically (preload + display: swap). For non-next projects, self-host + `@font-face { font-display: swap }` + preload the critical weight only.
- CSS: can't easily defer framework CSS. Options in priority order:
  1. Audit component-imported CSS — dynamic imports for route-specific stylesheets only.
  2. Remove unused CSS (Tailwind does this automatically; PurgeCSS for others).
  3. **Last resort:** Next.js `experimental: { optimizeCss: true }` — inlines critical CSS via `critters`. **Known to break Next 15 setups** (CSS modules, Storybook integrations, font-family cascades). Only enable if you can dedicate time to regression-testing every route. Usually not worth the savings.

Don't chase render-blocking savings under 200 ms. Not worth the risk of CSS regressions.

If PSI shows a tiny (0.5–1 KiB) CSS chunk with a huge duration (1500+ ms), that's almost always CDN cold-start or serverless cold boot — **not** a CSS issue. Confirm by re-running PSI after the first real visit has warmed the cache. If it persists, look at origin/CDN warming instead of the CSS file.

## Avoid chaining critical requests (preconnect)

If PSI shows a chain of third-party requests for the LCP, add preconnect hints. Common origins:

```html
<link rel="preconnect" href="https://cdn.shopify.com" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
```

Rules:
- Max 3–4 preconnects. More hurts.
- Only for **critical-path** origins (blocks LCP or first paint).
- `crossorigin` attribute needed for fonts (CORS).
- Next.js `next/font` handles this for its declared fonts.

## Efficient cache lifetimes

Static assets should have `Cache-Control: public, max-age=31536000, immutable` (one year). Framework-emitted `_next/static/*`, `dist/assets/*`, `build/static/*` all get immutable URLs, so long-cache is safe.

For user-content images or non-hashed paths, use a shorter `max-age=86400` (one day).

Nginx config snippet:
```nginx
location /_next/static/ {
    add_header Cache-Control "public, max-age=31536000, immutable" always;
}
location /assets/ {
    add_header Cache-Control "public, max-age=86400" always;
}
```

Third-party scripts (Clarity, GA, GTM) have their own cache TTLs — accept the PSI complaint or remove the tracker.

## Forced reflow

PSI shows total forced reflow time and attributes it to a script, or marks `[unattributed]`.

- Attributed: open the offending file, look for `offsetWidth`, `offsetHeight`, `getBoundingClientRect`, `offsetTop` etc. that happen **after** a DOM mutation or style change. Batch reads before writes.
- Unattributed: open Chrome DevTools → Performance tab → Record page load → look for the purple "Layout" bars right after "Recalc Style" — the Call Stack shows where.

Not worth fixing if the total is under 100 ms on mobile.

## Cumulative Layout Shift (CLS)

Leading causes:
- `<img>` without `width`/`height` attributes (or CSS aspect-ratio)
- Web fonts swapping in and reflowing (use `size-adjust` in `@font-face` or framework font API)
- Late-mounted components that push content (skeleton placeholders help)
- Ads/embeds without reserved space

Next.js `<Image>` handles dimensions automatically. For regular `<img>`:
```html
<img src="..." width="800" height="600" alt="...">
```

CSS fallback:
```css
.hero-img { aspect-ratio: 4 / 3; width: 100%; height: auto; }
```

## Unused JavaScript

Framework-specific. Usually means:
- Vendor bundle loaded on every route
- Client-only heavy library loaded in SSR bundle
- Polyfills for browsers you don't support

Fixes:
- Dynamic import for route-specific code
- Mark client-only components as such and lazy-load
- Check `transpilePackages` / bundling config
- For Next.js: use `next/dynamic` with `ssr: false` for client-only chunks

## Legacy JavaScript (polyfill bundle)

PSI "Legacy JavaScript" = bundler emitting polyfills for browsers you don't actually target. Next.js/SWC default includes IE11-era shims.

Fix (Next.js): add a modern `browserslist` to the app's `package.json`:

```json
"browserslist": [
  "chrome >= 90",
  "safari >= 14",
  "firefox >= 88",
  "edge >= 90"
]
```

These cover >96% of global users and ~99% of mobile users in most geos. SWC reads browserslist and skips the legacy polyfill chunk (~10–40 KiB saved, depending on app size).

For Vite/Webpack: set the same list. For Vite: `@vitejs/plugin-legacy` can be removed entirely if you don't need IE/old-Safari support.

Before shipping: confirm your actual user base with analytics. If you have >1% old-Safari-14 traffic (rare in 2026), raise the floor.

## INP (Interaction to Next Paint)

PSI successor to FID. Fired when users interact with heavy-JS pages.

Fixes:
- Break long tasks with `requestIdleCallback` or `scheduler.postTask`
- Debounce input handlers
- Move heavy work to Web Workers
- Audit third-party scripts — they often block the main thread

Fix ONLY if PSI shows INP > 200 ms. Under that, chasing it is waste.

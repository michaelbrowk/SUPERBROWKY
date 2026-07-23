---
name: meta-audit
description: Run a read-only pre-ship metadata audit for a public web page, and fix findings only when the user asks. Checks title, description, canonical, Open Graph and Twitter tags, favicons, viewport, language, robots directives, robots.txt, and sitemap.xml. Use for OG tags, social or link previews, meta tags, favicon, sitemap, robots.txt, canonical URLs, broken share images, or a public-page pre-launch check.
---

# meta-audit — pre-ship public-page metadata

## Portable safety contract

- Resolve `SKILL_DIR` to the directory containing this `SKILL.md`; run the
  bundled scanner as `node "$SKILL_DIR/scripts/meta-scan.mjs"`.
- A scan is read-only but makes network requests to the supplied URL. Do not
  send private URLs, credentials, cookies, or tokens to it.
- Edit metadata or publish only when the user explicitly asks for those
  actions. A clean scan is evidence, not release approval.

The cheap, high-embarrassment-avoidance half of "ship clean". None of this
affects how the page looks — it affects how it's **shared, found, and saved**.
A beautiful page whose Slack/iMessage preview is blank, whose tab has the
default globe icon, or that ships a `noindex` left over from staging still
fails the launch bar. This is a 60-second check that prevents a whole class of
"how did we miss that" bugs.

## Philosophy

These are binary, mechanical checks — present or not, in-spec or not. Don't
agonize; run the scanner, fix the reds, glance at the yellows. Run it on the
**production-like build** (the meta is often generated, not static) right before
launch, and again after any framework/SEO config change.

## Workflow

### 1. Scan

```bash
node "$SKILL_DIR/scripts/meta-scan.mjs" https://your-url
# machine-readable / CI:
node "$SKILL_DIR/scripts/meta-scan.mjs" --json https://your-url
```

The script fetches the page, parses `<head>`, and reports each check as
✓ / ⚠ / ✗. It **exits non-zero on any ERROR**, so gate launch/CI on it. ERRORs
are the ones that visibly break (no title, no description, no `og:image`/
`og:title`, no favicon, no viewport, no `lang`); WARNs are best-practice gaps.

For a page that needs auth or isn't deployed yet, run it against the local dev
server URL, or read the generated `<head>` from the framework's metadata config
directly (see "Where it's set" below).

### 2. Fix — what each finding means

| Check | Why it matters | Fix |
|---|---|---|
| **title** (10–60 chars) | The SERP + browser-tab headline | unique per page, front-load the keyword, no boilerplate suffix bloat |
| **description** (50–160) | The SERP snippet (not a ranking factor, but the click) | one compelling sentence per page; don't auto-dup across pages |
| **canonical** | Dedupes URL variants, consolidates ranking | absolute self-referential URL on each page |
| **viewport** | Mobile layout + Lighthouse | `<meta name="viewport" content="width=device-width, initial-scale=1">` |
| **lang** | Screen readers + translation + SEO | `<html lang="…">` with the real language |
| **robots** | Accidental `noindex` from staging is the classic launch killer | ensure prod is indexable; only `noindex` what should be hidden |
| **og:title / og:image** (ERROR) | The social/chat link preview — blank if absent | `og:image` ≥ 1200×630, absolute URL, < 8MB, real card |
| **og:description / og:url / og:type** | Completes the preview | set `og:type=website`/`article`, absolute `og:url` |
| **twitter:card** | X/Twitter preview style | `summary_large_image` for a hero image |
| **favicon** (ERROR) | The browser-tab + bookmark icon | `<link rel="icon">` (svg or .ico) |
| **apple-touch-icon** | iOS home-screen icon | 180×180 PNG `<link rel="apple-touch-icon">` |
| **robots.txt / sitemap.xml** | Crawl directives + discovery | serve both at the origin; reference the sitemap from robots.txt |

### 3. Verify the preview for real

The scanner confirms tags **exist**; it can't confirm the card **renders**.
Before calling it done, paste the URL into the live validators:

- Facebook/Meta Sharing Debugger, LinkedIn Post Inspector, and X Card Validator
  — or just paste the link into a Slack/iMessage DM to yourself and look.
- `og:image` must be an **absolute** URL and publicly reachable (relative paths
  and auth-walled images render blank). Re-scrape after fixing — caches are
  sticky.

## Where it's set (framework cheat-sheet)

- **Next.js (App Router):** the `metadata` export / `generateMetadata` in
  `layout.tsx` / `page.tsx`; `app/icon.png` + `app/apple-icon.png`;
  `app/robots.ts` + `app/sitemap.ts`.
- **Astro:** per-page front-matter into a `<SEO>` component in the layout
  `<head>`; `public/robots.txt`; `@astrojs/sitemap`.
- **SvelteKit:** `<svelte:head>` per route; `static/robots.txt`; a
  `sitemap.xml/+server.ts` endpoint.
- **Plain HTML:** literal tags in each `<head>`; hand-written `robots.txt` +
  `sitemap.xml`.

## What NOT to chase

- **Keyword-stuffed titles/descriptions** — write for the human clicking, not
  the crawler.
- **Per-page Twitter tags** when OG already covers it — Twitter falls back to
  OG; only add `twitter:*` to override.
- **`og:image` micro-optimization** — one good 1200×630 card per page beats a
  bespoke image per route nobody maintains.
- Deep technical SEO (indexing strategy, structured data, internal links) — that
  belongs to `seo-audit`, `schema`, and `ai-seo`. This skill is the pre-ship
  presence check, not the SEO program.

## Verification before claiming done

- `meta-scan.mjs` exits 0 (no ERRORs) on the production URL.
- The link preview actually renders in one real validator or a Slack/iMessage DM.
- Favicon shows in the browser tab; `og:image` loads at its absolute URL.
- Prod is **not** `noindex`; `robots.txt` + `sitemap.xml` resolve.

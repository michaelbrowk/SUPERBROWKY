# Vite, SvelteKit, and Astro performance patterns

These frameworks share Vite's build pipeline, but their rendering defaults are
different. Confirm whether the affected page is server-rendered, pre-rendered,
or client-only before applying a recipe.

## Images

Static imports let Vite fingerprint an asset, but they do not automatically
create responsive variants. Generate the variants deliberately and give the
browser `srcset`, `sizes`, width, and height:

```html
<img
  src="/images/hero-1280.webp"
  srcset="/images/hero-640.webp 640w, /images/hero-1280.webp 1280w"
  sizes="(max-width: 720px) 100vw, 60vw"
  width="1280"
  height="800"
  fetchpriority="high"
  alt="Product overview"
>
```

Do not lazy-load the LCP image. Lazy-load below-fold images only after
confirming they are outside the initial viewport at supported breakpoints.

## Resource hints

Put a preload in the document head only for a confirmed critical resource:

```html
<link rel="preload" as="image" href="/images/hero-1280.webp">
<link rel="preconnect" href="https://cdn.example.com" crossorigin>
```

The preload must match the URL the element requests. Responsive images may need
`imagesrcset` and `imagesizes`; otherwise the preload can fetch one candidate
while the `<img>` fetches another.

## Vite bundle splits

Use dynamic `import()` around route-specific or interaction-only features:

```ts
async function openEditor() {
  const { mountEditor } = await import("./editor");
  return mountEditor();
}
```

Before adding manual chunks, inspect the production build and a bundle
visualizer. Large shared chunks can be healthy when they are cached and used on
every route; splitting them can add request overhead.

Avoid a broad `optimizeDeps.include` list as a production fix.
`optimizeDeps` primarily affects the development server.

## SvelteKit

- Keep page data in server `load` functions when the browser does not need the
  fetching code.
- Use `ssr = false` only for routes that truly cannot render on the server.
  Disabling SSR removes initial HTML and can delay LCP.
- Lazy-load heavy browser-only components after the triggering interaction.
- Put site-wide resource hints in the app template and route-specific hints in
  the route head.

Reserve dimensions for images and components that appear after hydration.
Hydration mismatch fixes must preserve meaningful server HTML, not hide the
warning.

## Astro

Astro sends no component JavaScript unless a hydration directive asks for it.
Choose the least eager directive that satisfies the interaction:

- `client:load` for immediately interactive UI;
- `client:idle` for non-critical widgets;
- `client:visible` for below-fold islands;
- no client directive for static content.

Do not hydrate a wrapper only because one small child is interactive. Move the
interactive boundary down to that child.

Use Astro's image pipeline when it matches the deployment adapter. Inspect the
built output to confirm dimensions, formats, and `srcset`; the source component
alone is not proof.

## Plain Vite SPA caveat

A client-only SPA may leave crawlers and slow devices with an empty shell until
JavaScript runs. If the landing page needs fast first content, consider
pre-rendering or an SSR-capable framework before micro-optimizing individual
chunks. Treat that as an architecture decision, not an automatic audit fix.

## Cache headers

Vite's production assets normally include content hashes and can use:

```text
Cache-Control: public, max-age=31536000, immutable
```

Do not apply the same rule to `index.html`; it needs revalidation so it can
point to a new set of hashed assets after deployment.

## Verification

1. Test a production build, not the Vite development server.
2. Confirm the LCP element exists in initial HTML when SSR or pre-rendering is
   expected.
3. Inspect the Network panel for selected image candidates and duplicate
   preloads.
4. Confirm optional chunks do not load before their route or interaction.
5. Re-run the same Lighthouse profile and record the metric delta.

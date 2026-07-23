# Image delivery

Use this playbook when Lighthouse or PageSpeed reports **Improve image
delivery**, **Properly size images**, **Efficiently encode images**, or when an
image is the Largest Contentful Paint element.

## Start with evidence

Record these values before changing the asset:

- rendered CSS dimensions at the tested viewport;
- intrinsic pixel dimensions;
- transferred bytes and response `Content-Type`;
- whether the URL is selected through `srcset`;
- whether the image is the LCP element;
- Lighthouse estimated byte savings.

Do not infer the downloaded candidate from the source file alone. Confirm it in
the browser Network panel or Lighthouse request details.

## Choose the fix

| Content | Preferred delivery | Notes |
|---|---|---|
| Photo or gradient-heavy art | AVIF or WebP | Keep a fallback if the target browser matrix requires one |
| LCP photo | WebP is the conservative default | Compare AVIF decode time on target devices before switching |
| Flat UI art with transparency | SVG, lossless WebP, or optimized PNG | Inspect edges and alpha after conversion |
| Logo or icon | SVG | Keep text converted to paths only when font availability is uncertain |
| Screenshot with small text | WebP or optimized PNG | Review at 100% and 200%; lossy artifacts can hurt legibility |
| Animated media | Video where appropriate | Do not replace an accessible still image with autoplaying motion |

Resize raster sources to the largest rendered width multiplied by the maximum
supported device-pixel ratio. Do not upscale a small original.

## Responsive HTML

Give the browser accurate candidates and an accurate `sizes` value:

```html
<img
  src="/images/hero-1280.webp"
  srcset="
    /images/hero-640.webp 640w,
    /images/hero-960.webp 960w,
    /images/hero-1280.webp 1280w
  "
  sizes="(max-width: 720px) 100vw, 50vw"
  width="1280"
  height="960"
  alt=""
>
```

The empty `alt` is correct only for a decorative image. Meaningful images need
concise alternative text. The `width` and `height` attributes reserve aspect
ratio and help prevent layout shift; CSS can still make the image fluid.

For a `<picture>`, put the most efficient supported format first and retain one
widely supported fallback:

```html
<picture>
  <source type="image/avif" srcset="/images/card.avif">
  <source type="image/webp" srcset="/images/card.webp">
  <img src="/images/card.jpg" width="800" height="600" alt="Product detail">
</picture>
```

## LCP image rules

- Include the LCP resource in initial HTML.
- Do not set `loading="lazy"` on it.
- Use `fetchpriority="high"` on a plain LCP `<img>`.
- Preload a CSS background or video poster because the browser discovers it
  later than a normal `<img>`.
- Do not mark several images as high priority; that makes them compete.
- Give the browser a truthful `sizes` value so it does not fetch an oversized
  candidate.

```html
<link
  rel="preload"
  as="image"
  href="/images/hero.webp"
  fetchpriority="high"
>
```

## Use the bundled compressor safely

Run it from a project where `sharp` is installed. Start with an audit:

```bash
node "$SKILL_DIR/scripts/compress-images.mjs" public/images
```

Then make one intentional conversion or resize round on a clean Git worktree:

```bash
node "$SKILL_DIR/scripts/compress-images.mjs" \
  --apply --emit-webp --quality 85 --max-width 1600 public/images
```

The script refuses candidates that are larger than the input. That protects
file size, not visual quality. Review crops, transparency, small type, gradients,
and dark-mode assets before changing application references.

## Verify

1. Reload without cache and confirm the intended URL, format, and candidate.
2. Test the smallest and largest supported viewports.
3. Confirm there is no crop, alpha, or color-profile regression.
4. Re-run the same Lighthouse profile used for the baseline.
5. Record transferred bytes and LCP before and after.

If Lighthouse still reports the old file, check the rendered URL, service
worker, CDN cache, and deployed build rather than compressing the source again.

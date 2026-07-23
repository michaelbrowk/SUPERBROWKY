# Next.js performance patterns

Use these recipes after confirming the affected component and request in a
Lighthouse trace or browser Network panel. They target the App Router, but most
image and script principles also apply to the Pages Router.

## LCP with `next/image`

Keep the LCP image in the server-rendered tree, give it stable dimensions, and
set a truthful `sizes` value:

```tsx
import Image from "next/image";

export function Hero() {
  return (
    <Image
      src="/hero.webp"
      alt="Product dashboard"
      width={1600}
      height={1000}
      sizes="(max-width: 768px) 100vw, 60vw"
      priority
    />
  );
}
```

Use `priority` only for the image that is expected to become LCP. Confirm the
HTML and Network priority rather than assuming framework configuration emitted
the intended preload.

For a `fill` image, the parent needs a stable size or aspect ratio. Without it,
the page can still shift even though `Image` is used.

## Video poster LCP

`<video poster>` does not get `next/image` optimization. Pre-encode the poster,
use its final public URL, and preload that exact URL:

```tsx
export default function HeroVideo() {
  return (
    <>
      <link
        rel="preload"
        as="image"
        href="/media/hero-poster.webp"
        fetchPriority="high"
      />
      <video
        poster="/media/hero-poster.webp"
        width={1600}
        height={900}
        muted
        playsInline
      >
        <source src="/media/hero.mp4" type="video/mp4" />
      </video>
    </>
  );
}
```

Verify that the preload URL and poster URL are byte-for-byte identical. A
different query string or transformed CDN URL can cause a duplicate request.
If motion is not essential above the fold, a static `Image` is usually a
simpler LCP resource.

## Unused JavaScript and route-level splits

First identify the heavy module in a bundle analyzer or coverage trace. Split
features that are optional, route-specific, or opened after interaction:

```tsx
import dynamic from "next/dynamic";

const ChartEditor = dynamic(() => import("./ChartEditor"), {
  loading: () => <div aria-busy="true">Loading editor…</div>,
});
```

Do not dynamically import a small above-the-fold component merely to improve a
bundle report; the added request can delay useful paint.

Keep Server Components as the default. Add `"use client"` at the narrowest
interactive boundary so server-only dependencies and data shaping do not enter
the client bundle.

For browser-only libraries, isolate the library in a Client Component. Use
`ssr: false` only when the dependency genuinely cannot render on the server;
otherwise it removes useful initial HTML.

## Third-party scripts

Load scripts according to when the user needs them:

```tsx
import Script from "next/script";

<Script
  src="https://example.com/widget.js"
  strategy="lazyOnload"
/>
```

- `beforeInteractive`: only for code required before hydration.
- `afterInteractive`: for integrations needed soon after the page becomes
  interactive.
- `lazyOnload`: for non-critical analytics and support widgets.

Measure main-thread time as well as transfer bytes. Moving a script later can
improve LCP while leaving Interaction to Next Paint unchanged.

## Fonts

Prefer `next/font` and request only the weights and subsets used by the product:

```tsx
import { Inter } from "next/font/google";

const inter = Inter({
  subsets: ["latin"],
  weight: ["400", "600"],
  display: "swap",
});
```

Avoid importing the same family through both `next/font` and a CSS
`@import`. Confirm that the emitted preload matches the font used above the
fold.

## Remote images and cache behavior

Declare only required remote hosts in `next.config.*`. Give remote content
truthful dimensions and review the generated `_next/image` request in the
deployed environment.

Framework-generated hashed assets can use long immutable caching. User-managed
public paths without content hashes need invalidation or versioned filenames;
do not apply `immutable` to a URL whose bytes may change.

## Verification

1. Run the production build; development mode has different bundles and image
   behavior.
2. Inspect initial HTML for the LCP element or preload.
3. Confirm the selected image candidate and request priority.
4. Check that dynamic chunks load only on the expected route or interaction.
5. Compare Lighthouse using the same URL, viewport, and throttling profile.

# Project map

> ⚠ PLACEHOLDERS PRESENT — map the current repository before relying on this
> file. Read existing manifests, scripts, and folders first; do not ask for
> information that can be discovered locally. Delete this quote block when the
> map is real.

## Runtime

- **Stack:** <frameworks and languages>
- **Package manager:** <npm / pnpm / yarn / bun / other>
- **Install command:** <command>
- **Development command:** <command>
- **Test command:** <command>
- **Build command:** <command>

## Shared implementation sources

- **Tokens:** <path>
- **Components:** <path>
- **Assets:** <path>
- **Design source:** <Figma link, screenshots, or design files>

## Surface map

Use one row per independently designed surface. The default context is
`PRODUCT.md` + `DESIGN.md`. A scoped context is allowed only when this table
declares it; it inherits the default and contains differences only.

| Surface | Code paths | Product context | Design context | Verification |
|---|---|---|---|---|
| <app / marketing / admin / etc.> | <paths> | `PRODUCT.md` | `DESIGN.md` | <URL, preview, tests, sizes> |

Do not create hidden or competing briefs. If a monorepo genuinely needs
different contexts, use explicit names such as `PRODUCT.marketing.md` and
`DESIGN.app.md`, map them above, and keep shared rules in the default files.

## Constraints

- **Supported platforms:** <web / iOS / Android / desktop>
- **Required themes:** <light / dark / both>
- **Required sizes and states:** <breakpoints, empty/error/loading, permissions>
- **Accessibility target:** <target and assistive behavior>
- **Performance budget:** <relevant limits>

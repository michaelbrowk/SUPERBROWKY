# Performance report template

Keep the report tied to observable evidence. Do not call a change successful
only because code compiled or a Lighthouse recommendation disappeared.

## Scope

- URL or route:
- Environment and build:
- Test date:
- Device/profile:
- Tool and version:
- Targeted finding:

## Result

| Metric or finding | Before | After | Change | Evidence |
|---|---:|---:|---:|---|
| Performance score | — | — | — | report link or file |
| LCP | — | — | — | report link or file |
| CLS | — | — | — | report link or file |
| TBT or INP | — | — | — | report link or file |
| Transferred bytes | — | — | — | request or audit detail |

Use the same URL, viewport, throttling profile, and cache state for before and
after measurements. If conditions differ, label the comparison
**non-comparable**.

## Changes

| File or configuration | Change | Why |
|---|---|---|
| `path/to/file` | concise description | finding and evidence |

## Verification

- [ ] Production build completed.
- [ ] Intended asset or chunk is present in the deployed response.
- [ ] LCP request URL and priority were inspected.
- [ ] Supported viewport extremes were checked.
- [ ] No crop, layout shift, hydration, keyboard, or contrast regression was
      observed.
- [ ] Before and after reports are attached or linked.

## Remaining issues

List unresolved findings, third-party limits, cache uncertainty, and any
measurement variance. Separate these states:

- **Verified improvement:** comparable measurement moved as expected.
- **Implemented, awaiting deployment:** code exists but the live URL is old.
- **Deployed, awaiting stable measurement:** new response is live but results
  vary too much to claim a delta.
- **Blocked:** name the missing access, environment, or decision.

## Reproduction

```bash
# Build command

# Lighthouse or PSI command
```

Never include API keys, cookies, authorization headers, or private URLs in the
report.

# Implement: split Clock into clock.mbt

1. [ ] Cut Clock section from `src/embedder.mbt` into new `src/clock.mbt` (preserve comments/docs).
2. [ ] `moon check` / `moon test` (native).
3. [ ] Grep docs + `.trellis/spec` for “Clock … embedder” and update file references.
4. [ ] Update parent research note if it still says Clock only co-located (optional accuracy).

## Validation

```bash
moon test
rg -n "Clock" docs/project/architecture.md .trellis/spec/library/
```

## Risky files

- `src/embedder.mbt`, `src/clock.mbt` (new)

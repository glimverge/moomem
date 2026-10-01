# Design: split Clock into clock.mbt

## Seam / module

- **Module:** Clock (trait + LogicalClock + FixedClock).
- **Current locality bug:** defined in `src/embedder.mbt` after Embedder.
- **Proposed:** `src/clock.mbt` in the same package; no new package **seam**.

## Compatibility

- Public symbol names unchanged.
- Same-package: no import graph change for `store.mbt` / tests.
- Do not change `Config.clock` wiring.

## Trade-off

| Do | Don't |
|----|-------|
| File move for clarity | New time API / third clock type |
| Update docs that say Clock lives only in embedder.mbt | Touch Embedder behavior |

## Rollback

Delete `clock.mbt` and restore Clock block into `embedder.mbt`.

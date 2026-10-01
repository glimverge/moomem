# Architecture deepening wave 2

## Goal

Execute the remaining deepening backlog items deferred from wave 1 (`archive/2026-10/10-01-architecture-deepening`). Host `MemoryStore` **interface** stays unchanged.

## Child map (execution order)

| Order | Child | Backlog | Notes |
|------:|-------|---------|-------|
| 1 | `10-01-narrow-index-visibility` | P1 Option B | Research MoonBit visibility; may become docs-only if package-private is unavailable |
| 2 | `10-01-extract-add-helpers` | P6 | Private helpers inside `store.mbt` **implementation** |
| 3 | `10-01-retrieval-fusion-eval-track` | P7 | Tracking/docs only — product/eval, not module split |

## Parent acceptance

- [x] All three children completed or explicitly deferred with reason in child notes.
- [x] No new public facade beside `MemoryStore`.
- [x] Wave 1 keep-as-is items still respected (trait seams, dual-slot, llm_extractor package).

## Out of scope for parent

- Direct code edits on the parent task itself (children own deliverables).

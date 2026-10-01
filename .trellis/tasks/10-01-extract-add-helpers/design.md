# Design: extract MemoryStore.add private helpers

## Module

`MemoryStore` remains the deep host **module**. This change only reshapes the **implementation** of `add`.

## Approach

Extract private helpers for stages already present in `add`:
- extraction / degrade streak handling
- per-fact dedup
- conflict judge + supersede
- embed + dual-index insert
- flush after mutation

Prefer `priv fn` / private methods on `MemoryStore` over new `pub` types.

## Compatibility

- Public `add(user_id, text) -> Result[AddSummary, MoomemError]` unchanged
- Observable AddSummary / errors / AC tests unchanged
- Tests stay at store seam

## Do not

- Second aggregate; public pipeline type for hosts; algorithm changes

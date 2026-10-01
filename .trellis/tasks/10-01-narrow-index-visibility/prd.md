# Narrow internal index visibility (P1 Option B)

**Parent:** `10-01-architecture-deepening-w2`  
**Order:** 1 of 3  
**Prior art:** Wave 1 P1 Option A already documented host vs internal in `.trellis/spec/library/`.

## Goal

If MoonBit visibility allows, narrow `pub` on internal index/dedup **modules** so they are not mistaken for host API—without breaking `MemoryStore`, black-box tests that must move to the store **seam**, or CI diagnostic helpers (`tokenize` / `cosine_similarity` / `keyword_jaccard` used by `ci/locomo/conflict_eval.mbt`).

## Requirements

- **R1.** Inventory which symbols are only used inside `src/` vs tests vs `ci/`.
- **R2.** Determine MoonBit options for package-private / file-private (evidence from language docs or compile experiments).
- **R3.** If narrowing is feasible: apply minimal visibility change; migrate tests that peeked past the store **interface** to store-level assertions where needed; keep CI diagnostics working (keep helpers `pub` or add a thin diagnostic facade).
- **R4.** If narrowing is **not** feasible: document the limitation in Trellis spec and mark Option B blocked—no fake seams.
- **R5.** Do not add a parallel host “IndexStore” API; do not break `user_id` sharding.

## Acceptance Criteria

- [x] AC1. Written decision: narrowed **or** blocked-with-reason (with MoonBit evidence).
- [x] AC2. If narrowed: `moon test` native green; `ci/locomo` still compiles for conflict_eval helpers.
- [x] AC3. `.trellis/spec/library/public-api-and-types.md` updated to match the decision.
- [x] AC4. Host `MemoryStore` method names/signatures unchanged.

## Out of scope

- P6 `add` extraction; P7 fusion tuning; changing dual-slot persistence.

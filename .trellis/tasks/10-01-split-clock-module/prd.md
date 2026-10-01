# Split Clock module into clock.mbt

**Parent:** `10-01-architecture-deepening`  
**Backlog:** P3  
**Order:** 3 of 3 — after docs/spec children preferred; mechanical code move.

## Goal

Move `Clock` / `LogicalClock` / `FixedClock` from `src/embedder.mbt` into `src/clock.mbt` so file **locality** matches **module** boundaries. Public symbols and behavior unchanged.

## Requirements

- **R1.** Create `src/clock.mbt` with Clock trait + LogicalClock + FixedClock (and their impls/extends) moved from `embedder.mbt`.
- **R2.** Leave Embedder / HashingEmbedder / `cosine_similarity` in `embedder.mbt`.
- **R3.** No renames of public symbols; no Config/API changes.
- **R4.** `moon test` (native) still green; update docs/Trellis mentions of “Clock lives in embedder.mbt” if present.

## Acceptance Criteria

- [x] AC1. `clock.mbt` exists; `embedder.mbt` no longer defines Clock types.
- [x] AC2. Public symbol names unchanged (`Clock`, `LogicalClock`, `FixedClock`).
- [x] AC3. `moon test` passes on native.
- [x] AC4. Architecture/Trellis references updated where they claimed Clock only lives under embedder file.

## Out of scope

- New time APIs; merging Clock into Config.
- P1 Option B visibility; P6 `add` extraction.

## Technical notes

Same package (`src/`); MoonBit same-package move should not need import changes. Verify with `moon check` / `moon test`.

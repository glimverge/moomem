# Sync architecture docs and guideline routing

**Parent:** `10-01-architecture-deepening`  
**Backlog:** P2 + P5  
**Order:** 1 of 3 — no dependency on other children; do this first.

## Goal

Refresh outdated architecture/handover file inventories to match moomem 0.2.2, and add a short “where to look” routing note so maintainers and AI do not confuse `docs/project/`, `spec/`, and `.trellis/spec/`.

## Requirements

- **R1.** Update `docs/project/architecture.md` §2 file tree: `moon.pkg` (not `moon.pkg.json`); include `src/llm_extractor/`, `src/cli/` LLM wiring, `ci/`, current core `*_test.mbt` names; keep algorithm chapters unchanged.
- **R2.** Update `docs/project/09-handover.md` trait/file counts (five traits including Clock; 13 non-test core `.mbt` files, or whatever the live count is after recount).
- **R3.** Add routing in `docs/README.md` (and a short pointer from `.trellis/spec/guides/index.md` if needed): narrative → `docs/project/`; feature/process AC → `spec/`; AI coding conventions → `.trellis/spec/`. Do not merge the trees.
- **R4.** Do not change product source under `src/` / `ci/` / `examples/`.

## Acceptance Criteria

- [x] AC1. Architecture §2 matches live package/file names (spot-check: no `moon.pkg.json`; mentions `llm_extractor` and `ci/`).
- [x] AC2. Handover no longer claims “11 files / four traits” incorrectly.
- [x] AC3. `docs/README.md` has an explicit where-to-look section for the three trees.
- [x] AC4. No `src/` / `ci/` / `examples/` diffs from this task.

## Out of scope

- P1/P3/P4/P6 product or Trellis library deep notes (other children).
- Rewriting BM25/RRF/persistence design chapters.
- Merging or deleting `spec/` or `.trellis/spec/`.

## Notes

Source of truth for candidates: parent `research/deepening-backlog.md` P2/P5.

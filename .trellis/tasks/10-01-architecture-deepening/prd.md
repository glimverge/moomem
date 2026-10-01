# Architecture deepening review

## Goal

Produce a codebase-design review of moomem: a module map and a ranked deepening backlog. No product source refactors in this task. Host-facing `MemoryStore` interface stays as-is unless a later task explicitly changes it.

## Background

moomem is an embedded MoonBit agent-memory library. Intended layering lives in `docs/project/architecture.md` §1.3 and `.trellis/spec/library/`. Confusion reported by the user is mainly **internal visibility, file co-location, and doc drift** — not a broken host facade.

## Confirmed facts

| Observation | Evidence | Design reading |
|-------------|----------|----------------|
| `MemoryStore` is a deep module | `src/store.mbt` (~865 lines), six primary methods + export/import/list | Host interface earns its keep; do not split |
| Index / dedup modules are fully `pub` | `index_*.mbt`, `dedup.mbt`; tests in `index_test.mbt`, `extractor_test.mbt` call them directly | Internal seams look like public interfaces |
| Helpers `tokenize` / `rrf` / `cosine_similarity` / `keyword_jaccard` are `pub` | Used by core, tests, and `ci/locomo/` | Cross-package callers turn “internal util” into real interface |
| `Embedder` and `Clock` share one file | `src/embedder.mbt` | File ≠ module; Clock is a second module |
| Persistence seam is justified | `PersistenceBackend` + `FsBackend` + `MemoryBackend` | Two adapters → keep seam |
| Trait seams are justified | Embedder / Extractor / ConflictJudge / Clock (+ LLM adapters in `src/llm_extractor/`) | Offline default + production/LLM adapters |
| FS isolation is call-site only | `src/moon.pkg` imports `moonbitlang/x/fs`; calls confined to `persist.mbt` | Convention, not package seam |
| Doc / guideline sprawl | `docs/project/`, `spec/`, `.trellis/spec/` | Wrong map → wrong edits |
| Architecture file list stale | `architecture.md` §2 still says `moon.pkg.json`, omits `llm_extractor/` / `ci/` | Narrative lag vs 0.2.2 |

## Decision (user)

- **This task is review-only.** Deliver research + design backlog. Implementation of any deepening slice is a follow-up task.

## Requirements

- **R1.** Inventory modules; classify each seam as real (≥2 adapters), hypothetical (1 adapter), or internal-only.
- **R2.** Rank deepening opportunities by leverage and risk to `MemoryStore` / AC tests; apply deletion test + dependency category.
- **R3.** Explicit keep-as-is list (`MemoryStore` host interface, persistence seam, LLM package split, dual-slot semantics).
- **R4.** Persist results under this task’s `research/` and `design.md`. Update `.trellis/spec/` only if a durable coding rule crystallizes (optional, not required for AC).
- **R5.** No product source changes; no new public facade beside `MemoryStore`.

## Acceptance Criteria

- [x] AC1. `research/module-map.md` uses glossary terms (module / interface / seam / adapter / depth / leverage / locality).
- [x] AC2. `research/deepening-backlog.md` ranks candidates with problem, current vs proposed interface, dependency category, test-surface impact, and “do not do”.
- [x] AC3. Keep-as-is items are listed in both research and `design.md`.
- [x] AC4. `design.md` + `implement.md` describe review-only execution (no refactor checklist for `src/`).
- [x] AC5. Working tree product code under `src/`, `ci/`, `examples/` unchanged by this task.

## Out of scope

- Rewriting BM25 / RRF / dual-slot persistence.
- Implementing visibility or file splits in this task.
- Frontend layout (N/A).
- Changing `MoomemError` variants or host method names.

## Acceptance mapping

| AC | Requirement |
|----|-------------|
| AC1 | R1 |
| AC2 | R2 |
| AC3 | R3 |
| AC4 | R4, Decision |
| AC5 | R5 |

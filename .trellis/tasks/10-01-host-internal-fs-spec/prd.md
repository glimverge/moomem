# Document host vs internal surface and FS locality

**Parent:** `10-01-architecture-deepening`  
**Backlog:** P1 Option A + P4  
**Order:** 2 of 3 — after `10-01-sync-docs-routing` preferred (docs routing done first); not a hard code dependency.

## Goal

Encode in `.trellis/spec/library/` that index/dedup/helpers are not the host API, and that FS isolation is call-site convention while `moon.pkg` still imports `x/fs`.

## Requirements

- **R1 (P1A).** In `public-api-and-types.md` (and briefly `directory-structure.md` if needed): host surface = `MemoryStore` (+ listed helpers); `VectorIndex` / `KeywordIndex` / `DedupIndex` / `tokenize` / `rrf` / `cosine_similarity` / `keyword_jaccard` are supported **internal / test / CI diagnostic** surfaces, not host API. Cite `ci/locomo/conflict_eval.mbt` as diagnostic caller.
- **R2 (P4).** In `persistence.md` (and/or directory-structure): core may import `moonbitlang/x/fs` in `moon.pkg`; non-test core `@fs` call sites must stay in `persist.mbt` only; `persist_test.mbt` and `src/cli/` may use `@fs`. Do not propose a single-adapter subpackage split.
- **R3.** No product source changes; no visibility/`pub` changes (Option B is out of scope).

## Acceptance Criteria

- [ ] AC1. Spec states host vs internal clearly with real symbol names.
- [ ] AC2. Spec states FS package-import vs call-site rule with allowlist exceptions.
- [ ] AC3. Indexes in `.trellis/spec/library/index.md` still accurate.
- [ ] AC4. No `src/` / `ci/` / `examples/` diffs.

## Out of scope

- Narrowing `pub` (P1 Option B).
- Moving Clock files (child `split-clock-module`).
- Dual-slot algorithm changes.

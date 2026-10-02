# Library Development Guidelines

> Coding conventions for the moomem core package (`heyq02/moomem`, `src/`).

moomem is an **embedded agent memory library** in MoonBit — not a web fullstack app.
These guidelines describe what the code actually does today.

---

## Overview

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | Package layout, module boundaries, where files / tests / examples go | Filled |
| [Public API and Types](./public-api-and-types.md) | Host `MemoryStore` surface vs internal/test/CI indexes & helpers; types; `user_id` contract | Filled |
| [Error Handling](./error-handling.md) | `MoomemError`, `Result`, no panic | Filled |
| [Persistence](./persistence.md) | Dual-slot snapshot, FS package-import vs call-site isolation, backends | Filled |
| [Trait Injection](./trait-injection.md) | Embedder / Extractor / ConflictJudge / PersistenceBackend / Clock | Filled |
| [Quality Guidelines](./quality-guidelines.md) | Testing, naming, anti-patterns, CI/release iron rules, verification commands | Filled |

---

## Pre-Development Checklist

Before changing library code:

- [ ] Failures return `Result[T, MoomemError]` — never panic/abort in library paths
- [ ] Filesystem `@fs` call sites in non-test core stay in `src/persist.mbt` only (`moon.pkg` may import `moonbitlang/x/fs`; `persist_test.mbt` is allowlisted)
- [ ] JSON encode/decode stays in `src/json_codec.mbt` only
- [ ] Core package does not import `mizchi/llm` (optional adapters live in `src/llm_extractor/`)
- [ ] Any index/search/dedup path takes an explicit `user_id` (no cross-user API)
- [ ] Host surface stays centered on `MemoryStore::open/add/recall/forget/stats/close` (+ list/export/import); indexes/dedup/`rrf` are package-private; do not treat `tokenize`/similarity helpers as host API
- [ ] Defaults remain offline/deterministic when injection points are `None`

---

## Quality Check

After implementing:

- [ ] `moon test` passes (native)
- [ ] New fallible ops use `MoomemError` variants from `src/errors.mbt`
- [ ] Black-box tests live as `src/*_test.mbt` with injectable mocks (no mock framework)
- [ ] Persistence crash / truncate cases use `MemoryBackend` when possible
- [ ] Cross-user isolation covered if touching indexes or `recall`/`add`/`forget`

---

## Hard Invariants (quick reference)

1. `Result[T, MoomemError]` for fallible ops; no panic/abort in library code.
2. FS `@fs` call sites only in `persist.mbt` among non-test core (package may import `x/fs`); JSON codec only in `json_codec.mbt`.
3. Injectable traits with offline defaults: Embedder / Extractor / ConflictJudge / PersistenceBackend / Clock.
4. `user_id` physical sharding; cross-user recall structurally impossible.
5. Dual-slot snapshot + head pointer (not append-only JSONL).
6. Host API: `MemoryStore` open/add/recall/forget/stats/close (+ export/import/list helpers). Indexes / dedup / `rrf` are package-private (Option B); `tokenize` / `cosine_similarity` / `keyword_jaccard` remain `pub` CI diagnostics only.
7. `llm_extractor` is optional; core must not depend on `mizchi/llm`.

---

**Language**: English.

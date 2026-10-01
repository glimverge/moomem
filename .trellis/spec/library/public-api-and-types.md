# Public API and Types

> Host-facing surface vs package-private indexes vs CI diagnostic helpers.

## Host surface (`MemoryStore`)

The **host API** for applications and the CLI is `MemoryStore` only (documented in `README.md` and `src/lib.mbt` / `src/store.mbt`).

| Method | Signature (conceptual) | Role |
|--------|------------------------|------|
| `open` | `MemoryStore::open(path, config?) -> Result[MemoryStore, MoomemError]` | Create or restore store |
| `add` | `add(user_id, text) -> Result[AddSummary, MoomemError]` | Extract → dedup → conflict → embed → index → flush |
| `recall` | `recall(user_id, query, top_k?) -> Result[Array[MemoryEntry], MoomemError]` | Hybrid search; Active/Unstructured only |
| `forget` | `forget(user_id, target) -> Result[Int, MoomemError]` | Soft-delete `ById` / `All` |
| `stats` | `stats() -> Result[StoreStats, MoomemError]` | Counts, bytes, truncated_recovered, extractor_mode |
| `close` | `close() -> Result[Unit, MoomemError]` | Flush + mark closed (idempotent) |

Helpers used by CLI / FR-07/08 (also on `MemoryStore` in `store.mbt`):

- `export_jsonl` / `import_jsonl`
- `list_entries(user_id, …)`

Do not invent a parallel public facade; extend `MemoryStore` only when the feature belongs to the aggregate.

## Package-private indexes (Option B — narrowed)

MoonBit: unmarked top-level defs are **package-private**; `pub` crosses packages. Black-box `*_test.mbt` sees only `pub`; white-box `*_wbtest.mbt` (and same-package code) sees everything.

These types/fns are **not** `pub`. They live inside `MemoryStore` (`priv vec_index` / `kw_index` / `dedup`). Unit coverage is in `src/index_wbtest.mbt`.

| Symbol | Location | Role |
|--------|----------|------|
| `VectorIndex` (+ methods) | `index_vector.mbt` | Per-user vector shards |
| `KeywordIndex` (+ methods) | `index_keyword.mbt` | Per-user BM25 shards |
| `DedupIndex` (+ methods) | `dedup.mbt` | Per-user content fingerprints |
| `content_fingerprint` | `dedup.mbt` | Normalized content hash for dedup |
| `BM25_K1` / `BM25_B` | `index_keyword.mbt` | BM25 constants |
| `rrf` | `ranker.mbt` | Reciprocal rank fusion (recall path) |

Do **not** re-export these as a host “IndexStore” API. Do not treat abstract type names that may still appear in tooling as a second facade.

## Supported CI / black-box diagnostic helpers (`pub`)

Cross-package callers need these; keep them `pub`:

| Symbol | Location | Role |
|--------|----------|------|
| `tokenize` | `index_keyword.mbt` | Tokenization for BM25 / diagnostics |
| `cosine_similarity` | `embedder.mbt` | Vector similarity |
| `keyword_jaccard` | `conflict.mbt` | Lexical overlap |

Diagnostic caller outside the core package: `ci/locomo/conflict_eval.mbt` (uses tokenize / cosine / jaccard — not a host product path). Black-box tests in `extractor_test.mbt` also cover these helpers.

## Core types (`src/types.mbt`)

| Symbol | Notes |
|--------|-------|
| `EntryStatus` | `Active`, `Superseded`, `Deleted`, `Unstructured` |
| `EntryKind` | `Fact`, `Preference`, `Event`, `Unstructured` |
| `MemoryEntry` | Unit of memory; `mut status` / `mut superseded_by`; `metadata : Map[String, Json]` |
| `MemoryEntry::is_recallable` | Active + Unstructured true; Superseded/Deleted false |
| `ForgetTarget` | `ById(String)` \| `All` |
| `AddSummary` | `extracted/inserted/duplicates/superseded/degraded/notes` |
| `StoreStats` | Status counts + `bytes_on_disk` + `truncated_recovered` + `extractor_mode` |
| `RecallBackfill` | `NoBackfill` \| `BackfillRecency` (default) |
| `Config` | Optional trait objects + tuning knobs; `Config::default()` |

Constants with real defaults: `DEFAULT_DIM = 256`, `DEFAULT_RRF_K = 60`, `DEFAULT_SUPERSEDE_THRESHOLD = 0.82`, `CONFLICT_CANDIDATES = 8`, `COEXIST_BAND = 0.15`, `MAX_EXTRACTION_FAILURES = 3`, `MAX_USER_ID_LEN = 64`.

## `user_id` contract

Single validator: `validate_user_id` in `types.mbt`.

Rules (enforced at every store entrance — `add` / `recall` / `forget` / `list_entries` / import):

- Non-empty, length ≤ 64
- Charset `[A-Za-z0-9_\-.]`
- Reject `"."` and `".."` (path-component references)
- Reject `/`, `\`, whitespace, control characters

Tests: `types_test.mbt`, `qa_adversarial_test.mbt` ("user_id boundaries through store entrance").

## Isolation (structural)

- `VectorIndex` / `KeywordIndex` shard by `user_id` (`Map` of shards in `index_vector.mbt` / `index_keyword.mbt`).
- `MemoryStore.by_user` and `DedupIndex` are also per-user.
- Every search takes `user_id`; there is **no** whole-store recall API (`stats` is the only global view).
- AC-02: `store_e2e_test.mbt` "zero cross-user leakage".

## State machine (as implemented)

| Transition | Trigger | Location |
|------------|---------|----------|
| → Active / Unstructured | successful `add` path | `store.add` |
| Active → Superseded | `ConflictJudge` returns `Replace` | `store.add` (sets `superseded_by`, drops indexes) |
| Active → Deleted | `forget` | soft delete; snapshot keeps row |
| Restore / revive | **not** public in current API | no revive method; `InvalidOperation` is used for closed store, bad config, missing forget target |

Invariant: `recall` only returns recallable statuses; superseded/deleted remain in snapshot for audit/export.

## Entry identity and time

- `id = "{seq:012x}-{rand4}"` via `generate_entry_id` (deterministic hash of content/seq/clock — testable).
- `seq` monotonic, restored from snapshot, never reused.
- `created_at` from injected `Clock` (`LogicalClock` default; `FixedClock` for tests).

## Anti-patterns

- Adding a global "search all users" or admin dump that skips `user_id`.
- Returning Superseded/Deleted from `recall`.
- Hard-deleting rows from the snapshot on `forget` (current semantics are soft-delete).
- Validating `user_id` only in CLI — library entrances must call `validate_user_id`.
- Changing `MOOMEM_VERSION` without aligning `moon.mod` (release pipeline owns mod version; constant is manual sync — see comment in `lib.mbt`).
- Treating package-private indexes / `rrf` / diagnostic helpers as the host API, or inventing a parallel IndexStore facade for callers.
- Re-`pub`ing `VectorIndex` / `KeywordIndex` / `DedupIndex` without a Trellis decision (Option B already narrowed them).

# Public API and Types

> Host-facing surface vs package-private indexes and diagnostics.

## Host surface (`MemoryStore`)

The **host API** for applications is `MemoryStore` only (documented in `README.md` and `src/lib.mbt` / `src/store.mbt`).

| Method | Signature (conceptual) | Role |
|--------|------------------------|------|
| `open` | `MemoryStore::open(path, config?) -> Result[MemoryStore, MoomemError]` | Create or restore store |
| `add` | `add(user_id, text) -> Result[AddSummary, MoomemError]` | Extract → dedup → conflict → embed → index → flush |
| `recall` | `recall(user_id, query, top_k?) -> Result[Array[MemoryEntry], MoomemError]` | Hybrid search; Active/Unstructured only |
| `forget` | `forget(user_id, target) -> Result[Int, MoomemError]` | Soft-delete `ById` / `All` |
| `stats` | `stats() -> Result[StoreStats, MoomemError]` | Counts, bytes, truncated_recovered, extractor_mode |
| `close` | `close() -> Result[Unit, MoomemError]` | Flush + mark closed (idempotent) |

Helpers also on `MemoryStore` in `store.mbt`:

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
| `rrf` | `ranker.mbt` | Equal-weight RRF (EqualRrf / rollback path) |
| `rrf_weighted` | `ranker.mbt` | Weighted RRF (AdaptiveLexical soft path) |
| `lexical_strong` | `ranker.mbt` | BM25-score lexical confidence gate |
| `protect_bm25_topk` | `ranker.mbt` | Adaptive recall: keep BM25 top-k membership |

Do **not** re-export these as a host “IndexStore” API. Do not treat abstract type names that may still appear in tooling as a second facade.

## Package-private diagnostics

Not host API. Same-package code and `*_wbtest.mbt` may call them. Other packages must not.

| Symbol | Location | Covered by |
|--------|----------|------------|
| `tokenize` | `index_keyword.mbt` | `src/similarity_wbtest.mbt`, `src/index_wbtest.mbt` |
| `cosine_similarity` | `embedder.mbt` | `src/similarity_wbtest.mbt` |
| `keyword_jaccard` | `conflict.mbt` | `src/similarity_wbtest.mbt` |
| snapshot codec (`entry_to_json`, `parse_snapshot_text`, …) | `json_codec.mbt` | `src/json_codec_wbtest.mbt` |
| `MemoryBackend::peek` / `set_fail_next_save` / `set_simulate_partial_write` | `persist.mbt` | tests in `src/persist.mbt` |

`ci/eval/locomo/conflict_eval.mbt` prints cos/jac from functions inside the eval package. The scored supersede check uses `MemoryStore` only.

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
| `FusionPolicy` | `EqualRrf` \| `AdaptiveLexical` (default) — Config-only; no new recall method |
| `Config` | Optional trait objects + tuning knobs; `Config::default()` |

`Config` fusion knobs (AdaptiveLexical only; validated at `open`):

| Field | Default | Constraint |
|-------|---------|------------|
| `fusion_policy` | `AdaptiveLexical` | `EqualRrf` rollback |
| `lexical_floor` | `DEFAULT_LEXICAL_FLOOR` (0.8) | `>= 0` |
| `lexical_gap` | `DEFAULT_LEXICAL_GAP` (1.1) | `>= 1` |
| `vec_weight_when_lexical` | `DEFAULT_VEC_WEIGHT_LEXICAL` (0.05) | `(0, 1]`; `≤0.05` → BM25-only when lexical-strong |
| `vec_weight_when_semantic` | `DEFAULT_VEC_WEIGHT_SEMANTIC` (0.45) | `(0, 1]` |

Adaptive recall path: score-aware `kw_hits`/`vec_hits` → `lexical_strong` → weighted/`BM25-only` → `protect_bm25_topk`. Do **not** split `MemoryStore` for fusion; tune on `ci/tools/retrieval-tuning` only (never LoCoMo scored QA).

Constants with real defaults: `DEFAULT_DIM = 256`, `DEFAULT_RRF_K = 60`, `DEFAULT_SUPERSEDE_THRESHOLD = 0.82`, `CONFLICT_CANDIDATES = 8`, `COEXIST_BAND = 0.15`, `MAX_EXTRACTION_FAILURES = 3`, `MAX_USER_ID_LEN = 64`, `DEFAULT_LEXICAL_FLOOR = 0.8`, `DEFAULT_LEXICAL_GAP = 1.1`, `DEFAULT_VEC_WEIGHT_LEXICAL = 0.05`, `DEFAULT_VEC_WEIGHT_SEMANTIC = 0.45`.

## `user_id` contract

Single validator: `validate_user_id` in `types.mbt`.

Rules (enforced at every store entrance — `add` / `recall` / `forget` / `list_entries` / import):

- Non-empty, length ≤ 64
- Charset `[A-Za-z0-9_\-.]`
- Reject `"."` and `".."` (path-component references)
- Reject `/`, `\`, whitespace, control characters

Tests: `types_test.mbt`, `adversarial_test.mbt` ("user_id boundaries through store entrance").

## Isolation (structural)

- `VectorIndex` / `KeywordIndex` shard by `user_id` (`Map` of shards in `index_vector.mbt` / `index_keyword.mbt`).
- `MemoryStore.by_user` and `DedupIndex` are also per-user.
- Every search takes `user_id`; there is **no** whole-store recall API (`stats` is the only global view).
- AC-02: `store_test.mbt` "zero cross-user leakage".

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
- Validating `user_id` only in a host wrapper — library entrances must call `validate_user_id`.
- Changing `MOOMEM_VERSION` without aligning `moon.mod` (release pipeline owns mod version; constant is manual sync — see comment in `lib.mbt`).
- Treating package-private indexes / `rrf` / `tokenize` / similarity / snapshot codec as the host API, or re-exporting them for CI.
- Re-`pub`ing `VectorIndex` / `KeywordIndex` / `DedupIndex` without a Trellis decision (Option B already narrowed them).
- Splitting `MemoryStore` or adding a second recall API to “fix” fusion — fusion is `Config` + `ranker.mbt` only.
- Tuning adaptive thresholds on LoCoMo scored QA (use `ci/tools/retrieval-tuning` independent set).

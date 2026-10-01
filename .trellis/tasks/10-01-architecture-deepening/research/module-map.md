# Module map (moomem)

Vocabulary: **module**, **interface**, **seam**, **adapter**, **depth**, **leverage**, **locality**.

Verified against live tree on 2026-10-01 (`moon.mod` 0.2.2; `src/store.mbt` = 865 lines).

## 1. System shape

```
Host / CLI / ci/*
        │  (external interface)
        ▼
   MemoryStore          ← deep orchestration module
        │
        ├── ports (real seams): Embedder, Extractor, ConflictJudge,
        │                       PersistenceBackend, Clock
        │         adapters: hashing/raw/similarity/fs|memory/logical|fixed
        │                   + LlmExtractor / LlmConflictJudge (other package)
        │                   + ApiEmbedder (ci/locomo)
        │
        └── internal modules (should be implementation detail):
              VectorIndex, KeywordIndex, DedupIndex, rrf, tokenize,
              cosine_similarity, keyword_jaccard, json_codec
```

## 2. External modules (host-facing)

| Module | Interface (what callers must know) | Implementation | Depth | Seam |
|--------|-----------------------------------|----------------|-------|------|
| `MemoryStore` (`store.mbt`) | `open/add/recall/forget/stats/close`; helpers `export_jsonl/import_jsonl/list_entries`; `Config` injection; `MoomemError`; `user_id` rules; dual-slot restore on open | add pipeline, indexes, flush, state machine | **Deep** | External |
| `Config` + domain types (`types.mbt`) | Optional trait objects + tuning knobs; `MemoryEntry` / `ForgetTarget` / summaries | defaults, `validate_user_id` | Medium | Part of store interface |
| `MoomemError` (`errors.mbt`) | Suberror variants + `message`/`kind` | Show impls | Deep-enough | Error surface of store |
| CLI (`src/cli/`) | argv subcommands, env `MOOMEM_LLM_*`, exit codes | parse → `MemoryStore` | Shallow by design (adapter) | CLI → store |
| `llm_extractor` package | `LlmExtractor` / `LlmConflictJudge` as Extractor/ConflictJudge adapters | prompts, `mizchi/llm` | Deep adapter packages | True-external (LLM) |

Deletion test: delete `MemoryStore` → every host reimplements extract→dedup→conflict→embed→index→flush. **Keep.**

## 3. Port modules (justified seams)

| Seam (trait) | Adapters (≥2) | Dependency category | Notes |
|--------------|---------------|---------------------|-------|
| `Embedder` | `HashingEmbedder`; `ApiEmbedder` in `ci/locomo/embed_api.mbt` | True external when remote; in-process default | Keep |
| `Extractor` | `RawExtractor`; `LlmExtractor` | True external (LLM) + in-process default | Keep; package split already deepens locality |
| `ConflictJudge` | `SimilarityJudge`; `LlmConflictJudge` | Same | Keep |
| `PersistenceBackend` | `FsBackend`; `MemoryBackend` | Local-substitutable | Keep; dual-slot lives in FsBackend impl |
| `Clock` | `LogicalClock`; `FixedClock` (both in `embedder.mbt` today) | In-process | Keep; file co-location with Embedder is hygiene only (P3) |

Rule check: each has ≥2 adapters → real seams, not hypothetical.

## 4. Internal modules (implementation of MemoryStore)

| Module | Current interface (all `pub`) | Callers beyond store | Depth reading |
|--------|-------------------------------|----------------------|---------------|
| `VectorIndex` (`index_vector.mbt`) | `new/upsert/remove/size/search` | `index_test.mbt` | Useful internals; **public surface is shallow** (mirrors impl) |
| `KeywordIndex` (`index_keyword.mbt`) | same + BM25 consts | `index_test.mbt` | Same |
| `tokenize` (`index_keyword.mbt`) | free function | tests (`index_test`, `extractor_test`, `persist_test`, `qa_adversarial`) + **`ci/locomo/conflict_eval.mbt`** | Cross-package → accidental public **interface** |
| `DedupIndex` + `content_fingerprint` (`dedup.mbt`) | CRUD + fingerprint | `extractor_test.mbt` | Same shallow-pub pattern |
| `rrf` (`ranker.mbt`) | free function | `index_test.mbt` | In-process helper |
| `cosine_similarity` (`embedder.mbt`) | free function | tests + **`ci/locomo/conflict_eval.mbt`** | Cross-package → accidental public interface |
| `keyword_jaccard` (`conflict.mbt`) | free function | tests + **`ci/locomo/conflict_eval.mbt`** | Same |
| `json_codec` | entry + snapshot parse/build | store, persist path, tests | Deep-enough; locality rule already documented |
| `persist` dual-slot details | behind `PersistenceBackend` | persist_test via MemoryBackend crash inject (+ some direct `@fs` in that test file) | Good locality behind the seam |

## 5. File / doc modules (human interface)

| Artifact | Role | Problem |
|----------|------|---------|
| `docs/project/architecture.md` | Intended design narrative | §2 still says `moon.pkg.json`; omits `llm_extractor/`, `ci/`, extra tests (`qa_*`, `w3_config_*`); §2 file-tree line for `embedder.mbt` lists Clock + LogicalClock only (FixedClock appears later in prose §7, not as its own file) |
| `spec/spec-feature-*.md` | Feature/process contracts | Overlaps architecture + Trellis specs |
| `.trellis/spec/library|cli/` | AI coding guidelines | Current; should stay source of “how to edit” |
| `docs/project/09-handover.md` | Human onboarding | Says “src/store.mbt 等 11 个文件” and “四个注入 trait” — live tree has **13** non-test core `.mbt` files and **five** traits (Clock missing from the count) |

## 6. Package graph

| Package | Owns | Imports |
|---------|------|---------|
| `src/` | Core library (13 non-test `.mbt`) | `core/json`, `core/math`, **`x/fs`** (non-test call sites only in `persist.mbt`) |
| `src/llm_extractor/` | LLM adapters | core + `mizchi/llm` |
| `src/cli/` | native main | core + llm_extractor + openai + env + fs |
| `ci/*` | eval/tuning | core (and helpers) as library |

FS: **locality by convention** in core product sources, not by package seam. `persist_test.mbt` and the CLI package also call `@fs` (expected; outside the core-library rule).

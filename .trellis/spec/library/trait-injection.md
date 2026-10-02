# Trait Injection

> AI and infrastructure capabilities are first-class injectable traits with offline defaults.

## Design intent

The core library must stay testable with **zero network / zero API key**. `README.md` and `MemoryStore::open` make every AI capability an injectable trait; defaults are deterministic.

## Traits and defaults

| Trait | Defined in | Default | Production replacement |
|-------|------------|---------|------------------------|
| `Embedder` | `embedder.mbt` | `HashingEmbedder` (256-d bag-of-words hash, TF + L2) | Host embedding / vcdb adapter |
| `Extractor` | `extractor.mbt` | `RawExtractor` (passthrough `Unstructured`) | Host implementation |
| `ConflictJudge` | `conflict.mbt` | `SimilarityJudge` (cosine + keyword Jaccard) | Host implementation |
| `PersistenceBackend` | `persist.mbt` | native `FsBackend` / else `MemoryBackend` | Host IndexedDB glue, etc. |
| `Clock` | `clock.mbt` | `LogicalClock` (monotonic, snapshot-resumed) | System clock; tests use `FixedClock` |

`Config` fields are `&Trait?`; `None` resolves inside `MemoryStore::open` (`types.mbt` `Config`, `store.mbt`).

## Trait method contracts (as coded)

**Embedder**

- `embed(texts) -> Result[Array[Array[Double]], MoomemError]`
- `dim() -> Int`
- Vectors must match `dim`; empty/mismatched cosine returns `0.0` without panic (`cosine_similarity`).

**Extractor**

- `extract(user_id, text) -> Result[Array[ExtractedFact], MoomemError]`
- `mode() -> String` (`"raw"` | `"llm"`) for stats/export explainability
- Empty array = chitchat → store inserts nothing
- `ExtractedFact` includes `degraded` / `degrade_reason` for LLM fallback visibility

**ConflictJudge**

- `judge(new_fact, candidates) -> Result[Array[ConflictVerdict], MoomemError]`
- Decisions: `Replace` | `Coexist` | `Ignore` (`ConflictDecision`)
- `SimilarityJudge` uses `supersede_threshold` and `coexist_band`

**PersistenceBackend** / **Clock** — see persistence and types specs.

## Host adapters

The repository does not ship a model client. A host that wants structured extraction or semantic supersede implements `Extractor` and `ConflictJudge` and passes them in `Config`. Core `src/moon.pkg` must **not** import an LLM SDK.

## Injection in tests

Prefer injecting fakes over frameworks:

- Failing extractor / always-replace judge in `store_test.mbt` (AC-04, AC-05)
- `FixedClock` for exact `created_at`
- `MemoryBackend` for restart and crash simulation

## Anti-patterns

- Hard-coding network LLM calls inside `store.mbt` or core extractors.
- Adding an LLM SDK to the core package imports.
- Changing defaults to require API keys for `moon test`.
- Implementing a second conflict/extract path that bypasses the traits.
- Silent degradation without `AddSummary.degraded`, notes, or entry metadata when LLM/extractor fails.

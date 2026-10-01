# Trait Injection

> AI and infrastructure capabilities are first-class injectable traits with offline defaults.

## Design intent

W1 must be testable with **zero network / zero API key**. Architecture (`docs/project/architecture.md` §1.2) and `README.md` make every AI capability an injectable trait; defaults are deterministic.

## Traits and defaults

| Trait | Defined in | Default | Production replacement |
|-------|------------|---------|------------------------|
| `Embedder` | `embedder.mbt` | `HashingEmbedder` (256-d bag-of-words hash, TF + L2) | Host embedding / vcdb adapter |
| `Extractor` | `extractor.mbt` | `RawExtractor` (passthrough `Unstructured`) | `src/llm_extractor` `LlmExtractor` |
| `ConflictJudge` | `conflict.mbt` | `SimilarityJudge` (cosine + keyword Jaccard) | `LlmConflictJudge` |
| `PersistenceBackend` | `persist.mbt` | native `FsBackend` / else `MemoryBackend` | Host IndexedDB glue, etc. |
| `Clock` | `embedder.mbt` | `LogicalClock` (monotonic, snapshot-resumed) | System clock; tests use `FixedClock` |

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

## Optional LLM package boundary

`src/llm_extractor/` is a **separate package**:

- Imports `heyq02/moomem/src` + `mizchi/llm`
- Implements `Extractor` / `ConflictJudge` against injected `Provider`
- Core `src/moon.pkg` must **not** import `mizchi/llm`
- Header comment in `llm_extractor.mbt` states this iron rule

Host wiring example: inject `LlmExtractor` / `LlmConflictJudge` into `Config` (see `README.md` W2 section). CLI wires the same via `src/cli/llm_wiring.mbt` (native only).

## Injection in tests

Prefer injecting fakes over frameworks:

- Failing extractor / always-replace judge in `store_e2e_test.mbt` (AC-04, AC-05)
- `FixedClock` for exact `created_at`
- `MemoryBackend` for restart and crash simulation
- Scripted `Provider` mocks inside `llm_extractor/*_test.mbt` (zero network)

## Anti-patterns

- Hard-coding network LLM calls inside `store.mbt` or core extractors.
- Adding `mizchi/llm` to the core package imports.
- Changing defaults to require API keys for `moon test`.
- Implementing a second conflict/extract path that bypasses the traits.
- Silent degradation without `AddSummary.degraded`, notes, or entry metadata when LLM/extractor fails.

# Directory Structure

> Where MoonBit packages and files live in moomem.

## Repository packages

| Path | Role | Key deps |
|------|------|----------|
| `src/` | Core library (`MemoryStore` aggregate) | `moonbitlang/x/fs`, `moonbitlang/core/json` |
| `src/llm_extractor/` | Optional LLM extract/judge adapters | `heyq02/moomem/src`, `mizchi/llm` |
| `src/cli/` | Native CLI binary (`is-main`) | core + llm_extractor + `mizchi/llm/openai` + `x/fs` + `env` |
| `ci/locomo/`, `ci/tuning/`, `ci/llm_live/` | Eval / tuning / live LLM gates | separate packages |
| `examples/` | Demos (e.g. LLM extractor with mocks) | — |
| `docs/project/` | Architecture, PRD reports | — |
| `spec/` | Feature/process specs (CI pipelines, W3/W4) — **not** Trellis coding specs | — |
| `.trellis/spec/` | AI coding guidelines (this tree) | — |

Module identity: `heyq02/moomem` at version `0.2.2` (`moon.mod`, `MOOMEM_VERSION` in `src/lib.mbt`).

## Core library file map (`src/`)

Layering matches `docs/project/architecture.md` §1.3:

| Layer | Files | Responsibility |
|-------|-------|----------------|
| Public constants | `lib.mbt` | `MOOMEM_VERSION`, `SNAPSHOT_VERSION`; documents API surface |
| Types | `types.mbt` | `MemoryEntry`, `Config`, `AddSummary`, `StoreStats`, `ForgetTarget`, `validate_user_id` |
| Errors | `errors.mbt` | `MoomemError` suberror + `message` / `kind` |
| JSON | `json_codec.mbt` | Sole entry/snapshot encode-decode |
| Traits + defaults | `embedder.mbt`, `extractor.mbt`, `conflict.mbt`, `clock.mbt` | Injectables + `HashingEmbedder` / `RawExtractor` / `SimilarityJudge` / `LogicalClock` / `FixedClock` |
| Dedup | `dedup.mbt` | Per-user content fingerprints |
| Indexes | `index_vector.mbt`, `index_keyword.mbt`, `ranker.mbt` | Per-user shards + BM25 + RRF |
| Persistence | `persist.mbt` | `PersistenceBackend`, `FsBackend`, `MemoryBackend` — **only non-test core `@fs` call site** (`moon.pkg` may still import `x/fs`) |
| Orchestration | `store.mbt` | `MemoryStore` aggregate root (host API); indexes/dedup/`rrf` are package-private; `tokenize` / similarity helpers stay `pub` for CI — see [Public API and Types](./public-api-and-types.md) |

## Tests

Black-box tests sit beside sources as `*_test.mbt`; white-box as `*_wbtest.mbt`:

- `types_test.mbt` — codec, `validate_user_id`
- `extractor_test.mbt` — injection / raw mode + pub diagnostic helpers
- `index_wbtest.mbt` — VectorIndex / KeywordIndex / DedupIndex / rrf (package-private)
- `persist_test.mbt` — dual-slot, head corruption, `MemoryBackend` crash inject
- `store_e2e_test.mbt` — AC-01..05 end-to-end
- `qa_adversarial_test.mbt`, `w3_config_test.mbt` — edge / config validation

## Package config reality

- Core `src/moon.pkg` imports `moonbitlang/x/fs` even though **call sites** must stay in `persist.mbt` (architectural isolation, not package-graph isolation). Do not invent a single-adapter persist subpackage to paper over that; see [Persistence](./persistence.md).
- Allowlisted `@fs` outside that rule: `persist_test.mbt`, `src/cli/`.
- `src/llm_extractor/moon.pkg` imports core + `mizchi/llm` only.
- `src/cli/moon.pkg` uses `targets` to compile `llm_wiring.mbt` on native and `llm_wiring_stub.mbt` on non-native.

## Where new code goes

| Change | Put it in |
|--------|-----------|
| New public type / config field | `types.mbt` (+ codec in `json_codec.mbt` if persisted) |
| New `MoomemError` variant | `errors.mbt` (update `Show`, `message`, `kind`) |
| New injectable AI / infra capability | New trait file next to `embedder` / `extractor` / `conflict` / `clock`; wire through `Config` + `MemoryStore::open` |
| Disk / crash-safety | `persist.mbt` only |
| Orchestration of add/recall flows | `store.mbt` only — keep indexes/traits stateless or rebuildable |
| LLM prompts / OpenAI client | `src/llm_extractor/` — never core |
| CLI flags / env | `src/cli/main.mbt`, `llm_wiring*.mbt` |

## Anti-patterns

- Do **not** add React/web/ORM-style folders; this repo has no frontend.
- Do **not** put `@fs.*` calls in non-test core outside `persist.mbt` (allowlist: `persist_test.mbt`, `src/cli/`).
- Do **not** put `@json.parse` / entry serializers outside `json_codec.mbt` (CLI import reuses store helpers that call the codec).
- Do **not** grow a second aggregate alongside `MemoryStore`; it is the sole stateful orchestrator.

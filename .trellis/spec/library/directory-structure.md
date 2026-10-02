# Directory Structure

> Where MoonBit packages and files live in moomem.

## Repository packages

下列路径为现行布局。测试、门禁、评测、示例的落点规则在 [Quality Guidelines](./quality-guidelines.md)。

| Path | Role | Key deps |
|------|------|----------|
| `src/` | Core library (`MemoryStore` aggregate); L0 包旁测试 | `moonbitlang/x/fs`, `moonbitlang/core/json` |
| `ci/eval/locomo/` | L3 offline LoCoMo eval harness + `data/` | separate package |
| `benchmarks/locomo/` | Release-archived LoCoMo scores (site `/benchmark`) | metrics JSON only |
| `ci/tools/retrieval-tuning/` | Offline retrieval tuning tool (U1; **not in CI**) | separate package |
| `examples/<scene>/` | E2 scene demos: `basic-store`, `conflict-supersede`, `cli-smoke` | — |
| `site/` | Public docs site; restates the host contract | — |
| `.trellis/spec/` | AI coding guidelines + CI iron rules (this tree) | — |
| `.github/workflows/` | CI / release **implementation** (living SoT for pipelines) | — |

Module identity: `heyq02/moomem`. Package version is `moon.mod` (`0.6.0`). `MOOMEM_VERSION` in `src/lib.mbt` matches it. Snapshot format version is `SNAPSHOT_VERSION` (`1`), independent of the package version.

## Core library file map (`src/`)

Core library layers:

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
| Orchestration | `store.mbt` | `MemoryStore` aggregate root (host API); indexes/dedup/`rrf`/`tokenize`/similarity/snapshot codec are package-private — see [Public API and Types](./public-api-and-types.md). `add` is a thin orchestrator over package-private stage helpers (extract/degrade, dedup, conflict/supersede, embed+index insert, flush) — not a second aggregate. |

## Tests

Black-box tests sit beside sources as `*_test.mbt`; white-box as `*_wbtest.mbt` (**T1**：包旁测试不外迁):

- `types_test.mbt` — codec, `validate_user_id`
- `extractor_test.mbt` — injection / raw mode (black-box)
- `diag_wbtest.mbt` — tokenize / cosine / jaccard / SimilarityJudge
- `json_codec_wbtest.mbt` — snapshot codec
- crash-injection tests live in `persist.mbt` (the injectors are package-private)
- `index_wbtest.mbt` — VectorIndex / KeywordIndex / DedupIndex / rrf (package-private)
- `persist_test.mbt` — dual-slot, head corruption, `MemoryBackend` crash inject
- `store_e2e_test.mbt` — AC-01..05 end-to-end
- `qa_adversarial_test.mbt`, `w3_config_test.mbt` — edge / config validation

Eval / tools are **not** package-side tests — see decision table below.

## Package config reality

- Core `src/moon.pkg` imports `moonbitlang/x/fs` even though **call sites** must stay in `persist.mbt` (architectural isolation, not package-graph isolation). Do not invent a single-adapter persist subpackage to paper over that; see [Persistence](./persistence.md).
- Allowlisted `@fs` outside that rule: `persist_test.mbt`.
- The module does not depend on an LLM SDK. Hosts implement `Extractor` / `ConflictJudge` / `Embedder` outside this repo.

## Where new code goes

| Change | Put it in |
|--------|-----------|
| New public type / config field | `types.mbt` (+ codec in `json_codec.mbt` if persisted) |
| New `MoomemError` variant | `errors.mbt` (update `Show`, `message`, `kind`) |
| New injectable AI / infra capability | New trait file next to `embedder` / `extractor` / `conflict` / `clock`; wire through `Config` + `MemoryStore::open` |
| Disk / crash-safety | `persist.mbt` only |
| Orchestration of add/recall flows | `store.mbt` only — keep indexes/traits stateless or rebuildable |
| Host model client | Host package — never core |

## Where new tests / examples / gates go

Align with [Quality Guidelines](./quality-guidelines.md).

| Need | Put it in |
|------|----------|
| Asserted offline regression (core) | Package-side `src/*_test.mbt` / `*_wbtest.mbt` (L0) |
| Benchmark / corpus eval | `ci/eval/locomo/` (L3, offline hashing); release archives → `benchmarks/locomo/` |
| Sweep / calibrate Config, not a gate | `ci/tools/retrieval-tuning/` (tool) |
| Teachable runnable demo (no AC suite) | `examples/<scene>/` (E2) |

**Forbidden**: live key paths inside examples; treating tools as default L0; stuffing eval corpora into package-side unit tests.

## Anti-patterns

- Do **not** add React/web/ORM-style folders; this repo has no frontend.
- Do **not** put `@fs.*` calls in non-test core outside `persist.mbt` (allowlist: `persist_test.mbt`).
- Do **not** put `@json.parse` / entry serializers outside `json_codec.mbt`.
- Do **not** grow a second aggregate alongside `MemoryStore`; it is the sole stateful orchestrator.
- Do **not** move package-side `*_test.mbt` out of `src/` (T1).
- Do **not** wire `retrieval-tuning` into CI by default (U1 tool).

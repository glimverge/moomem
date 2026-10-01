# Quality Guidelines

> Testing, naming, and anti-patterns for the core library.

## Naming and style (as used in tree)

- Types / enums: `PascalCase` (`MemoryStore`, `MoomemError`, `EntryStatus`)
- Functions / fields: `snake_case` (`validate_user_id`, `created_at`)
- Package-private helpers: no `pub` (`fnv1a`, `generate_entry_id`, `is_blank_text`)
- Traits: `pub(open) trait` with `self : Self` methods
- Mutable fields: sparse `mut` on aggregate/index internals (`MemoryStore`, entry status)

Align with MoonBit core style (`read_file_to_string`, etc.).

## Testing conventions

| Practice | Evidence |
|----------|----------|
| Black-box `*_test.mbt` / white-box `*_wbtest.mbt` next to sources | `store_e2e_test.mbt`, `index_wbtest.mbt`, … |
| Prefer `inspect(...)` deterministic assertions | throughout tests |
| Inject mocks; no mock framework | custom judges/extractors in e2e |
| Crash/truncate via `MemoryBackend` | `persist_test.mbt`, AC-01 e2e |
| Isolation / adversarial QA suites | `qa_adversarial_test.mbt` |
| Multi-backend | `moon test --target wasm` (native-only FS/CLI excluded) |

Architecture authority for layers, CI iron rules, and where gates/eval/tools/examples land: [`docs/project/10-testing-examples-architecture.md`](../../../docs/project/10-testing-examples-architecture.md).

### Examples vs gates vs tools

| Kind | Role | Assertions? | CI |
|------|------|-------------|-----|
| Package-side `*_test.mbt` | L0/L1 regression | Yes | push 阻塞 |
| `ci/gates/*` | L2 live LLM release gate | Live scenarios | **仅** release |
| `ci/eval/*` | L3 benchmark / corpus | Metrics | 离线 push；live 手工 |
| `ci/tools/*` | Developer tuning (U1) | Sweep / report | **不进 CI** |
| `examples/<scene>` | Teachable demos (E2) | No (smoke only) | smoke 矩阵，非 L0 |

Iron rules: L0/L1 never read `DEEPSEEK_*`; L2 never joins push CI; examples never depend on live keys.

### CI / release iron rules (durable)

Executable workflow truth: [`.github/workflows/test-pipeline.yml`](../../../.github/workflows/test-pipeline.yml) and [`release-pipeline.yml`](../../../.github/workflows/release-pipeline.yml). Long-form process specs are **archived** under [`docs/archive/process-specs/`](../../../docs/archive/process-specs/) (not living contracts).

| Rule | Meaning |
|------|---------|
| Push/PR is offline | `test-pipeline` never injects `DEEPSEEK_*` / `MOONCAKES_TOKEN`; no live LLM endpoints on the green path |
| Fail closed | Any failed check / matrix target / example smoke fails the aggregate gate |
| Four targets + smoke | native + wasm + wasm-gc + js after `moon check`; native-only FS/CLI stay cfg-gated; examples smoke on native |
| Release order | `quality` (`workflow_call` → test-pipeline) → `llm-live` (`ci/gates/live-llm`, must log `LIVE_LLM_PASS`) → publish / tag side effects |
| Dry-run still gates | `dry_run=true` skips registry / GitHub Release only; quality + llm-live still run |
| Version alignment | Publish/tag path requires git semver ↔ `moon.mod` `version` match before credentials write |
| Secret scope | `DEEPSEEK_*` only on release `llm-live`; `MOONCAKES_TOKEN` only on publish job; never cache credentials under `~/.moon` |
| Permissions | Offline quality: `contents: read`; write tokens only on the release job that needs them |

When changing CI behavior: edit the YAML first (or same PR), then keep this table + [doc 10](../../../docs/project/10-testing-examples-architecture.md) aligned. Do not revive root `spec/` process docs as a second source of truth.

### Verification commands

```bash
moon test
moon test --target wasm
moon run ci/tools/retrieval-tuning --target native   # tool（无 CI 调用）
moon run ci/eval/locomo --target native              # L3 offline eval
# NEW_VERSION=… SKIP_COMMIT=1 bash scripts/ci/run-locomo-benchmark-archive.sh  # release archive dry-run
moon run examples/basic-store --target native
moon run examples/llm-extractor --target native
moon run examples/conflict-supersede --target native
moon run examples/cli-smoke --target native
# optional local / release-only:
# moon run ci/gates/live-llm --target native         # L2 gate（需 DEEPSEEK_*）
```

## Code reuse checklist

Before adding a helper:

1. Search for existing symbols (`validate_user_id`, `content_fingerprint`, `tokenize`, `rrf`, codec helpers).
2. Prefer extending `json_codec.mbt` over new ad-hoc parsers.
3. Prefer trait injection over `#ifdef`-style business logic forks (backend `#cfg` only in persist).

## Logging

Core library has **no** logging facade. Observability channels that actually exist:

- `AddSummary.notes` / `degraded`
- `MemoryEntry.metadata` (extractor mode, degrade flags, conflict traces)
- `StoreStats.extractor_mode`, `truncated_recovered`
- `MoomemError::message` / `kind` for hosts and CLI stderr

Do not invent a parallel log subsystem unless product requirements change.

## Forbidden patterns (already avoided)

| Anti-pattern | Correct location / approach |
|--------------|----------------------------|
| `panic` / `abort` on library errors | `Result[T, MoomemError]` |
| `@fs` outside `persist.mbt` (core) | `persist.mbt` only |
| `@json.parse` / snapshot+entry codecs outside `json_codec.mbt` | `json_codec.mbt` only (`store.mbt` may set `Json::string` metadata tags) |
| Cross-user recall / unscoped index scan | always pass `user_id` |
| Core depending on `mizchi/llm` | `src/llm_extractor/` |
| Append-only JSONL persistence | dual-slot + head |
| Second stateful orchestrator | `MemoryStore` only; long `add` stages stay as package-private helpers on the same aggregate |
| “Fix” retrieval fusion by exploding / splitting the store API | Keep `MemoryStore` facade; fusion is `Config` + `ranker.mbt` (AdaptiveLexical default); tune via `ci/tools/retrieval-tuning` only |
| Frontend/ORM templates | N/A — this is a MoonBit library |
| Live keys / `DEEPSEEK_*` in L0/L1 or examples | gates only (`ci/gates/live-llm`) |
| `DEEPSEEK_*` / mooncakes secrets on push `test-pipeline` | release `llm-live` / publish jobs only |
| Default CI for retrieval-tuning | keep as `ci/tools/retrieval-tuning` (U1; not in push CI) |
| Treating archived `docs/archive/process-specs/` as living SoT | YAML + this file’s CI iron rules |

## When changing public behavior

- Update `README.md` API tables if signatures or defaults change.
- Keep `MOOMEM_VERSION` / `SNAPSHOT_VERSION` coherent with format bumps (`lib.mbt`).
- Add or extend black-box tests for AC-style guarantees (isolation, restart, degrade).
- If a new invariant is discovered, add it to `.trellis/spec/library/` — do not leave it only in chat.
- If changing test/gate/example **placement**, update doc 10 and this file’s command tables together — do not invent a second architecture narrative in 05.

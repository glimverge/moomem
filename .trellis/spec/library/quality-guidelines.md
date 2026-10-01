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

### Verification commands

```bash
moon test
moon test --target wasm
moon run ci/tools/retrieval-tuning --target native   # tool（无 CI 调用）
moon run ci/eval/locomo --target native              # L3 offline eval
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
| “Fix” retrieval fusion by exploding / splitting the store API | Keep `MemoryStore` facade; fusion is Config/eval work (P7/W5), not a module-interface deepen |
| Frontend/ORM templates | N/A — this is a MoonBit library |
| Live keys / `DEEPSEEK_*` in L0/L1 or examples | gates only (`ci/gates/live-llm`) |
| Default CI for retrieval-tuning | keep as `ci/tools/retrieval-tuning` (U1; not in push CI) |

## When changing public behavior

- Update `README.md` API tables if signatures or defaults change.
- Keep `MOOMEM_VERSION` / `SNAPSHOT_VERSION` coherent with format bumps (`lib.mbt`).
- Add or extend black-box tests for AC-style guarantees (isolation, restart, degrade).
- If a new invariant is discovered, add it to `.trellis/spec/library/` — do not leave it only in chat.
- If changing test/gate/example **placement**, update doc 10 and this file’s command tables together — do not invent a second architecture narrative in 05.

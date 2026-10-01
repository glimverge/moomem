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
| Black-box `*_test.mbt` next to sources | `store_e2e_test.mbt`, `index_test.mbt`, … |
| Prefer `inspect(...)` deterministic assertions | throughout tests |
| Inject mocks; no mock framework | custom judges/extractors in e2e |
| Crash/truncate via `MemoryBackend` | `persist_test.mbt`, AC-01 e2e |
| Isolation / adversarial QA suites | `qa_adversarial_test.mbt` |
| Multi-backend | `moon test --target wasm` (native-only FS/CLI excluded) |

Verification commands (from `README.md`):

```bash
moon test
moon test --target wasm
moon run ci/tuning --target native
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
| Second stateful orchestrator | `MemoryStore` only |
| Frontend/ORM templates | N/A — this is a MoonBit library |

## When changing public behavior

- Update `README.md` API tables if signatures or defaults change.
- Keep `MOOMEM_VERSION` / `SNAPSHOT_VERSION` coherent with format bumps (`lib.mbt`).
- Add or extend black-box tests for AC-style guarantees (isolation, restart, degrade).
- If a new invariant is discovered, add it to `.trellis/spec/library/` — do not leave it only in chat.

# moomem repository architecture notes (bootstrap)

## What this project is

- MoonBit embedded agent memory library: `heyq02/moomem` (v0.2.2).
- Not a web fullstack app. Template `frontend/` + ORM-style `backend/` scaffolding does **not** match reality.
- Primary sources of truth for conventions: `README.md`, `docs/project/architecture.md`, `src/**/*.mbt`, `spec/spec-*.md`.

## Packages / directories

| Path | Role |
|------|------|
| `src/` | Core library (`MemoryStore` aggregate); `moon.pkg` imports `moonbitlang/x/fs` |
| `src/llm_extractor/` | Optional LLM extract/judge adapters (`mizchi/llm`); core stays free of this dep |
| `src/cli/` | Native CLI binary: add/recall/list/stats/export/import |
| `ci/locomo/`, `ci/tuning/`, `ci/llm_live/` | Eval / tuning / live LLM gates |
| `examples/` | Demos |
| `scripts/ci/` | Release and CI helper shell |
| `docs/project/` | Architecture, PRD, test/eval reports |
| `spec/` | Feature/process specs (CI pipelines, W3/W4 features) |

## Hard local invariants (document these)

1. Failures return `Result[T, MoomemError]`; no panic/abort in library code (`src/errors.mbt`, `src/lib.mbt`).
2. FS I/O only in `src/persist.mbt` (`moonbitlang/x/fs`).
3. JSON codec only in `src/json_codec.mbt`.
4. AI capabilities are injectable traits: `Embedder`, `Extractor`, `ConflictJudge` (+ `PersistenceBackend`, `Clock`); defaults are deterministic/offline.
5. `user_id` physically shards indexes; cross-user recall must be structurally impossible.
6. Persistence: dual-slot snapshot + head pointer (not append-only JSONL), because x/fs has no append/rename.
7. Public API surface: `MemoryStore::open/add/recall/forget/stats/close`.

## Suggested `.trellis/spec/` reshape

Replace generic frontend/backend templates with library-aligned layers, for example:

- `.trellis/spec/library/` — directory structure, types/API, error handling, persistence, traits/injection, quality/testing
- `.trellis/spec/cli/` — CLI commands, env vars (`MOOMEM_LLM_*`), wiring stubs
- Keep `.trellis/spec/guides/` (already filled)

Delete non-applicable React/ORM template files after writing replacements. Update all `index.md` files to match.

## Verification commands (from README)

```bash
moon test
moon test --target wasm
moon run ci/tuning --target native
```

## Docs to mine for examples

- `docs/project/architecture.md`
- `README.md` (public API, CLI, tests)
- `src/store.mbt`, `src/persist.mbt`, `src/errors.mbt`, `src/types.mbt`
- `src/cli/main.mbt`, `src/llm_extractor/llm_extractor.mbt`

<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->

# moomem

Embedded agent memory library for [MoonBit](https://www.moonbitlang.com/). Module `heyq02/moomem`. It lives inside the host process: `open` / `add` / `recall` / `forget`, hybrid vector + BM25 search sharded by `user_id`, and a native dual-slot JSONL snapshot. Defaults are offline and deterministic. Hosts inject `Embedder`, `Extractor`, and `ConflictJudge` when they want real models.

Host behavior and on-disk layout: `README.md`. Coding contracts: `.trellis/spec/library/`. Read that index before editing `src/`.

`demo/` is a separate MoonBit module with its own `AGENTS.md`. The closest file wins.

## Setup

Toolchain is `moon`, not Node. `package.json` only wraps coverage scripts and pins `pnpm@12.8.1`.

Documented baseline is `moon` ≥ `0.1.20260920` (see `README.md`). CI always installs **latest**: dated CDN pins currently return 403 (`.github/actions/setup-moonbit`).

```bash
curl --fail --silent --show-error --location \
  https://cli.moonbitlang.com/install/unix.sh | bash
# ensure ~/.moon/bin is on PATH
moon version --all
moon update
moon check --target native
```

Module identity is `moon.mod` (`version`, currently `0.7.1`). `src/lib.mbt` `MOOMEM_VERSION` must match that string. `SNAPSHOT_VERSION` (`1`) is the snapshot header `v` and is independent of the package version. Do not hand-edit either version for a release; `scripts/release/bump-version.sh` writes both.

Registry dependency: `moonbitlang/x@0.5.5`.

## Layout

| Path | Role |
|------|------|
| `src/` | Core package. Black-box `*_test.mbt` and white-box `*_wbtest.mbt` stay beside sources. |
| `examples/<scene>/` | Three offline demos: `default-reopen`, `host-inject-supersede`, `isolation-forget-import`. Smoke only. |
| `benchmark/` | Offline LoCoMo eval (`moon run benchmark --target native`). |
| `demo/` | Host sample (Qwen embed + DeepSeek extract). Own module `heyq02/demo`, depends on published `heyq02/moomem`, not the working tree. |
| `.github/workflows/` | `test-pipeline.yml` (push/PR), `release-pipeline.yml` (manual). |
| `.trellis/spec/library/` | Invariants agents must follow. |

`src/` map: `lib.mbt` constants; `types.mbt` / `errors.mbt`; `json_codec.mbt` (only JSON codec); `embedder.mbt` / `extractor.mbt` / `conflict.mbt` / `clock.mbt`; `dedup.mbt`; `index_vector.mbt` / `index_keyword.mbt` / `ranker.mbt`; `persist.mbt` (only non-test `@fs` call site); `store.mbt` + `store_add.mbt` / `store_recall.mbt` / `store_records.mbt` (one `MemoryStore`).

## Development

```bash
moon check --target native
moon fmt
moon info          # refresh generated package interface; review any .mbti diff
```

Targets: `native`, `wasm`, `wasm-gc`, `js`. Native uses `FsBackend` (dual-slot files under `<path>/moomem/`). Other targets default to in-memory `MemoryBackend` and do not persist. `#cfg(target="native")` belongs in `persist.mbt` (tests may use it in `persist_test.mbt`).

Offline examples (no keys, no network):

```bash
moon run examples/default-reopen --target native
moon run examples/host-inject-supersede --target native
moon run examples/isolation-forget-import --target native
moon run benchmark --target native
```

Live host demo (needs secrets; do not commit `.env`):

```bash
cd demo
cp .env.example .env
moon run cmd/main
```

`demo/moon.mod` pins `heyq02/moomem@0.7.0`. A change in this repo's `src/` does not affect `demo/` until that dependency is bumped.

## Testing

```bash
moon test --target native              # `pnpm test` is `moon test` with no --target; pass one to match CI
moon test --target wasm
moon test --target wasm-gc
moon test --target js
moon test src/store_test.mbt           # one file
moon test -p heyq02/moomem/src         # one package
moon test -u                           # refresh expect/snapshot output
```

Coverage of `src/` must stay ≥ 90% of points. CI enforces this on push/PR native runs.

```bash
moon test --enable-coverage --target native
moon coverage report --ignore-missing-files -f summary -p heyq02/moomem/src
pnpm run cov:bisect                   # same gate; exits non-zero under 90%
```

Other report formats: `pnpm run cov:json` (Coveralls), `cov:xml`, `cov:html`. Run them only after a coverage-enabled `moon test`.

Conventions:

- Black-box tests: `src/*_test.mbt` (see `pub` only). White-box: `src/*_wbtest.mbt`.
- Assert with `inspect`. Inject traits by hand. There is no mock framework.
- Crash and partial-write cases use `MemoryBackend` (`persist.mbt` / `persist_test.mbt`).
- Package tests, examples, and the default benchmark path must not read API keys or call model endpoints.
- Native CI fails if the suite shrinks below `NATIVE_TEST_BASELINE` (76 in `test-pipeline.yml`). The floor only rises.

## Code style

MoonBit block style (`///|`). Names: types `PascalCase`, functions and fields `snake_case`, traits `pub(open) trait`. Unmarked top-level defs are package-private. Format with `moon fmt`.

Hard rules (detail in `.trellis/spec/library/`):

- Fallible library paths return `Result[T, MoomemError]`. Do not `panic` or `abort`. New variants go in `errors.mbt` and must update `Show`, `message`, and `kind`.
- `@fs` call sites in non-test core stay in `persist.mbt`. `persist_test.mbt` is the test allowlist. `src/moon.pkg` may still import `moonbitlang/x/fs`.
- Snapshot and entry JSON encode/decode stay in `json_codec.mbt`.
- Every index, search, dedup, `add`, `recall`, and `forget` path takes an explicit `user_id`. No cross-user scan.
- Host surface is `MemoryStore` (`open`, `add`, `recall`, `forget`, `stats`, `close`, plus list / export / import). Do not promote indexes, `rrf`, `tokenize`, `cosine_similarity`, or `keyword_jaccard` to a second host API.
- Core must not import an LLM SDK. Defaults stay offline when injection points are `None`.
- Persistence is a full dual-slot snapshot plus `head`, not an append-only log.
- No logging facade. Observability is `AddSummary`, entry `metadata`, `StoreStats`, and `MoomemError::message` / `kind`.

Before adding a helper, search for `validate_user_id`, `content_fingerprint`, `tokenize`, `rrf`, and the codec functions.

## Build and release

There is no Node/app build. `moon check` and `moon test` are the build. `moon package` runs in the release job.

CI (`.github/workflows/test-pipeline.yml`), on push/PR to `main`:

1. `moon check --target native`
2. `moon test` on `native` (with coverage), `wasm`, `wasm-gc`, `js`
3. Three example smokes, then `moon run benchmark --target native`
4. Coveralls upload of the native `src/` report

Push/PR jobs must stay offline: no `MOONCAKES_TOKEN`, no model endpoints. `COVERALLS_REPO_TOKEN` is only for the upload job.

Release (`.github/workflows/release-pipeline.yml`) is `workflow_dispatch` only: quality gate, then `scripts/release/bump-version.sh`, `moon publish`, tag `v<version>`. `dry_run=true` still runs the quality gate and skips publish, commit, tag, and GitHub Release. Do not cache `~/.moon/credentials.json`.

## Pull requests

Match nearby commit style. Before pushing library changes:

```bash
moon check --target native
moon test --target native
moon fmt
```

Also run the other three targets when the change is not clearly native-only. If behavior, defaults, or snapshot shape change, update `README.md` and extend a black-box test. If an invariant changes, update `.trellis/spec/library/` in the same change. Keep the CI iron-rule table in `quality-guidelines.md` aligned with the workflow YAML; do not add a second CI spec.

## Security

- Tests, examples, and the offline benchmark never contain API keys.
- `demo/.env` is local only (gitignored). `demo/memory/` is gitignored runtime state.
- `MOONCAKES_TOKEN` belongs only on the publish job.

## Troubleshooting

- `open` returns `StoreCorrupted` when snapshot `v` mismatches, a non-final line is truncated, or both slots are unusable. Only a torn **last** line is dropped (`stats().truncated_recovered`).
- wasm/js `recall` after process restart is empty unless the host injected a `PersistenceBackend`. That is the default backend, not a lost write on native.
- `demo/` behavior that disagrees with `src/` is usually the pinned mooncakes version, not the working tree.
- Native file tests that touch a real directory need `--target native`. They are `#cfg`'d out of wasm/js.

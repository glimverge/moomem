# CLI Commands and Environment

> How `src/cli/main.mbt` exposes moomem.

## Build / run

```bash
moon build src/cli --target native
BIN=_build/native/debug/build/src/cli/cli.exe
```

## Subcommands

| Command | Purpose | Required-ish flags |
|---------|---------|-------------------|
| `add` | Write memory | `--db`, `--user`, `--text`; optional `--llm`, `--llm-judge`, `--model`, `--base-url` |
| `recall` | Hybrid recall | `--db`, `--user`, `--query`, optional `--top-k` |
| `list` | List entries | `--db`, `--user`, optional `--all` |
| `stats` | Store stats | `--db` |
| `export` | JSONL to stdout | `--db` |
| `import` | JSONL from file | `--db`, `--file` |
| `help` | Usage | — |

Defaults from `default_options()`: `db=./moomem-data`, `user=default`, `top_k=5`.

Flag parsing: recursive `--key value` style in `parse_options`; boolean switches `--all`, `--llm`, `--llm-judge` do not consume a value. `--llm-judge` implies `--llm`.

## Exit / errors

- Success: exit 0
- Usage / library errors: print readable message (CLI uses `Result` / die helpers; library errors via `MoomemError::message`)
- Import file IO uses `@fs.read_file_to_string` in CLI (allowed here; still not in core outside persist)

## Environment variables

| Variable | Role |
|----------|------|
| `MOOMEM_LLM_API_KEY` | Required for `--llm` unless base URL host is exact localhost |
| `MOOMEM_LLM_BASE_URL` | OpenAI-compatible endpoint (optional) |
| `MOOMEM_LLM_MODEL` | Model id (optional; default `gpt-4o-mini` when wiring) |

Precedence for model/base URL: CLI flag > env > built-in default (see `llm_wiring.mbt`).

Related eval tooling may use other keys (`MOOMEM_EMBED_API_KEY`, `DEEPSEEK_*`) under `ci/` — those are **not** CLI flags; do not conflate them with `MOOMEM_LLM_*`.

## Relationship to library

CLI should:

1. Parse options → build `Config` (default or LLM)
2. `MemoryStore::open` / call public methods / `close`
3. Format stdout for humans

It should not reimplement indexing, conflict, or snapshot logic.

## Anti-patterns

- Silently ignoring `MoomemError` without printing `message`
- Accepting path-like `user` values that library would reject (library still validates; CLI should not invent a weaker contract)
- Adding filesystem mutation for the store directory outside what `FsBackend` already does
- Documenting flags in usage that `parse_options` does not implement

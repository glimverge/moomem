# moomem

[![Build Status](https://img.shields.io/github/actions/workflow/status/glimverge/moomem/test-pipeline.yml?style=flat-square&label=Build)](https://github.com/glimverge/moomem/actions)
[![MoonBit](https://img.shields.io/badge/MoonBit-0.2.2-black?style=flat-square)](https://www.moonbitlang.com/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square)](LICENSE)

> Embedded agent memory for MoonBit — zero deploy, crash-safe persistence, structural user isolation.

[Features](#features) • [Getting started](#getting-started) • [API](#public-api) • [CLI](#cli) • [LLM injection](#llm-injection) • [Examples](#examples) • [Docs](#documentation)

**moomem** gives your MoonBit agent long-term memory in a few lines of code: extract facts, hybrid-search them, supersede conflicts, and survive process restarts — without standing up a server.

```
moomem v0.2.2  ·  moonbitlang/x@0.5.5  ·  mizchi/llm@0.3.2 (llm_extractor / CLI --llm only)  ·  Apache-2.0
```

## Features

- **Two-line integrate** — `MemoryStore::open` + `add` / `recall`; six public methods on the aggregate root
- **Zero API key by default** — embed / extract / conflict are injectable traits with offline defaults (hash embedder, raw extract, cosine judge)
- **Hybrid retrieval** — vector + BM25, fused with RRF; indexes sharded by `user_id`
- **Crash-safe persistence** — dual-slot JSONL snapshots + `head` pointer; truncated trailing lines recovered on open
- **User isolation by structure** — every search takes `user_id`; no whole-store recall API; cross-user hits are impossible by design
- **Optional LLM path** — `src/llm_extractor` wraps OpenAI-compatible providers for structured extraction and conflict judging (core stays free of LLM deps)

## Getting started

### Prerequisites

- [moon](https://www.moonbitlang.com/) ≥ `0.1.20260920` (`moon version` to confirm)

### Install

```bash
moon add moonbitlang/x    # disk persistence (fs only; locked behind persist.mbt)
moon add mizchi/llm       # only if you use src/llm_extractor or CLI --llm
```

> [!NOTE]
> Not published to mooncakes yet. Develop against this repo as a path dependency, or vendor `src/`.

After publish, add to your `moon.mod.json`:

```json
{
  "deps": {
    "moonbitlang/x": "0.5.5",
    "heyq02/moomem": "0.2.2"
  }
}
```

### Quick start

```moonbit
fn main {
  let mem = @moomem.MemoryStore::open("./memory").unwrap()

  // After a turn: extract → dedup → conflict → embed → dual index → flush
  let summary = mem.add("user-42", "我对花生过敏").unwrap()
  println("extracted=\{summary.extracted} inserted=\{summary.inserted}")

  // Before the next LLM call: hybrid recall, this user only
  let hits = mem.recall("user-42", "花生过敏", top_k=3).unwrap()
  for e in hits {
    println("[\{e.created_at}] \{e.content}")
  }

  ignore(mem.close())
}
```

Reopen the same directory later — memories are intact and recall stays consistent.

### Try without writing code

```bash
moon build src/cli --target native
BIN=_build/native/debug/build/src/cli/cli.exe

$BIN add    --db ./mem --user user-42 --text "我对花生过敏"
$BIN recall --db ./mem --user user-42 --query "花生过敏"
$BIN list   --db ./mem --user user-42
$BIN stats  --db ./mem
$BIN export --db ./mem > backup.jsonl
$BIN import --db ./mem --file backup.jsonl
```

Optional LLM extraction (OpenAI-compatible; key from env only):

```bash
export MOOMEM_LLM_API_KEY=...
# export MOOMEM_LLM_BASE_URL=https://api.deepseek.com   # optional
# export MOOMEM_LLM_MODEL=deepseek-chat                  # optional; default gpt-4o-mini
$BIN add --db ./mem --user user-42 --text "你好！我对花生过敏" --llm
# also judge conflicts with LLM: add --llm-judge (implies --llm)
```

## Public API

| Method | Role | Returns |
|--------|------|---------|
| `open(path, config?)` | Open or create a store | `Result[MemoryStore, MoomemError]` |
| `add(user_id, text)` | Extract → dedup → conflict → index → flush | `Result[AddSummary, MoomemError]` |
| `recall(user_id, query, top_k?)` | Hybrid ranked recall (`Active` / `Unstructured` only) | `Result[Array[MemoryEntry], MoomemError]` |
| `forget(user_id, target)` | Soft-delete `ById(id)` / `All` | `Result[Int, MoomemError]` |
| `stats()` | Counts, bytes, truncate recovery, extractor mode | `Result[StoreStats, MoomemError]` |
| `close()` | Flush and close (idempotent) | `Result[Unit, MoomemError]` |

Helpers: `export_jsonl` / `import_jsonl` / `list_entries(user_id)`.

All fallible ops return `Result` — the library does not panic. `user_id` must be non-empty, ≤ 64 chars, charset `[A-Za-z0-9_\-.]` (path traversal rejected at every entrance).

### Injection points

| Trait | Default (offline) | Production swap |
|-------|-------------------|-----------------|
| `Embedder` | `HashingEmbedder` (256-d bag-of-words) | Host / vcdb embedder |
| `Extractor` | `RawExtractor` (store as unstructured) | `LlmExtractor` in `src/llm_extractor` |
| `ConflictJudge` | `SimilarityJudge` (cosine + Jaccard, threshold 0.82) | `LlmConflictJudge` |
| `PersistenceBackend` | native `FsBackend`; wasm/js `MemoryBackend` | IndexedDB glue, etc. |
| `Clock` | `LogicalClock` | System clock / `FixedClock` in tests |

```moonbit
let cfg : Config = Config::{
  ..Config::default(),
  judge : Some(MyLlmJudge::new() as &ConflictJudge),
  clock : Some(FixedClock::new(42L) as &Clock),
}
let store = MemoryStore::open("./memory", config=cfg).unwrap()
```

## LLM injection

Core `src/` stays free of third-party LLM deps. LLM capability lives in **`src/llm_extractor`** (`mizchi/llm@0.3.2`, trait layer only).

```moonbit
// Host moon.pkg.json imports:
//   "heyq02/moomem/src"  "heyq02/moomem/src/llm_extractor"  "mizchi/llm/openai"

let provider = @openai.OpenAIProvider::new(
  "sk-...",
  endpoint=OpenAIEndpoint::OpenAI,   // or Custom(base_url="https://...")
  model="gpt-4o-mini",
)
let extractor = @llm_extractor.LlmExtractor::new(provider)
let judge = @llm_extractor.LlmConflictJudge::new(provider)

let cfg : Config = Config::{
  ..Config::default(),
  extractor : Some(extractor as &Extractor),
  judge : Some(judge as &ConflictJudge),
}
let store = MemoryStore::open("./memory", config=cfg).unwrap()
```

Extraction keeps reusable facts (`fact` / `preference` / `event` + source `span`), drops chit-chat, and degrades visibly on failure (`AddSummary.degraded` / `notes` / entry metadata) instead of failing the store silently.

> [!TIP]
> Mock `Provider` yourself in the host package — `mizchi/llm`'s built-in mocks are not exported across packages. See `examples/llm-extractor` and `src/llm_extractor/*_test.mbt` for zero-network patterns.

## Persistence

On disk under `open(path)`:

```
<path>/moomem/slot0.jsonl   # snapshot slot A (header + one JSON entry per line)
<path>/moomem/slot1.jsonl   # snapshot slot B
<path>/moomem/head          # "0" or "1" — current slot
```

Each `add` / `forget` / `close` rewrites the **inactive** slot fully, then updates `head`. Mid-write crash keeps the previous slot; a damaged `head` falls back to the parseable slot with the higher generation. Trailing half-lines are dropped and counted in `stats.truncated_recovered`.

```
(empty) → Active → Superseded   (conflict Replace; superseded_by set)
                → Deleted       (forget; soft-delete, kept for audit/export)
```

`recall` never returns `Superseded` / `Deleted`.

## CLI

| Command | Purpose |
|---------|---------|
| `add` | Write memory (`--db`, `--user`, `--text`; optional `--llm`, `--llm-judge`) |
| `recall` | Hybrid recall (`--query`, optional `--top-k`) |
| `list` | List entries (optional `--all`) |
| `stats` | Store stats |
| `export` / `import` | JSONL backup / restore |
| `help` | Usage |

Env vars for LLM mode: `MOOMEM_LLM_API_KEY`, `MOOMEM_LLM_BASE_URL`, `MOOMEM_LLM_MODEL`. Flag values override env.

## Examples

All examples are mock-driven and offline:

```bash
moon run examples/basic-store --target native
moon run examples/llm-extractor --target native
moon run examples/conflict-supersede --target native
moon run examples/cli-smoke --target native
```

## Testing and eval

```bash
moon test                         # native (core + llm_extractor + cli)
moon test --target wasm           # four backends; native-only disk/CLI tests excluded
moon test --target wasm-gc
moon test --target js

moon run ci/tools/retrieval-tuning --target native   # offline param grid
moon run ci/eval/locomo --target native              # LoCoMo subset; look for LOCOMO_PASS
```

Optional live tiers (not in push CI):

```bash
moon run ci/eval/locomo --target native -- --embedder api   # needs MOOMEM_EMBED_*
moon run ci/eval/locomo --target native -- --live           # needs DEEPSEEK_*
```

LoCoMo slice licensing: see [`ci/eval/locomo/data/README.md`](ci/eval/locomo/data/README.md) (CC BY-NC 4.0). Offline hashing embedder may underperform pure BM25; the ≥15% hybrid gain target applies under `--embedder api`.

## Project structure

```
src/                 Core library (MemoryStore orchestration)
  llm_extractor/     Optional LLM Extractor + ConflictJudge adapters
  cli/               add / recall / list / stats / export / import
examples/            E2 demos (basic-store, llm-extractor, conflict-supersede, cli-smoke)
ci/
  gates/             Live LLM release gates
  eval/locomo/       L3 LoCoMo harness + data
  tools/             Offline retrieval tuning
docs/                Project docs (architecture, PRD, eval reports)
site/                Rspress docs site (GitHub Pages)
```

## Security boundaries

> [!IMPORTANT]
> **moomem does not authenticate callers.** It is an embedded library: anything that can call the API can read and write the whole store. Isolation is structural (`user_id` shards + required `user_id` on search), not a replacement for host process trust.

- `user_id` never enters filesystem paths; `/`, `\`, whitespace, and control chars are rejected
- LLM keys are injected by the host — the library never persists secrets
- Shared storage ACLs are the host's responsibility

## Known limitations

- Persistence is **full dual-slot snapshots** (intentional deviation from append-only JSONL): `moonbitlang/x/fs` has no append/rename API
- Default `HashingEmbedder` has no real semantics — inject a production embedder for synonym recall
- Default `SimilarityJudge` covers near-duplicate updates; semantic moves (e.g. city change) need `LlmConflictJudge`
- Single-writer model; no concurrent writers in v0.1
- wasm/js default to in-process `MemoryBackend` unless you inject persistence

Details and edge cases: [docs/project/07-w3.1-verification.md](docs/project/07-w3.1-verification.md), [docs/project/architecture.md](docs/project/architecture.md).

## Documentation

- [Docs index](docs/README.md) — map of project / resources / archive
- [Architecture](docs/project/architecture.md) — modules, injection, dual-slot persistence
- [PRD](docs/project/03-prd.md) — product requirements
- [Testing & examples layout](docs/project/10-testing-examples-architecture.md)
- [LoCoMo eval report](docs/project/08-w4-eval-report.md)

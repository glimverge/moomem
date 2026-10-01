# Persistence

> Dual-slot snapshots, backend traits, and FS isolation.

## Why not append-only JSONL

`moonbitlang/x/fs` provides whole-file read/write (`write_string_to_file`, `read_file_to_string`, …) with **no append / rename**. Architecture intentionally uses **dual-slot snapshot + head pointer** (`docs/project/architecture.md` §1.4, implemented in `src/persist.mbt`).

## Disk layout (`FsBackend`)

Under the host path passed to `MemoryStore::open`:

```
<path>/moomem/
  slot0.jsonl
  slot1.jsonl
  head          # content "0" or "1"
```

Flush:

1. Write the **inactive** slot completely (overwrite).
2. On success, write `head` to point at that slot.

Crash behavior:

- Crash mid-slot write → head still points at old good slot.
- Corrupt/empty head → pick the slot whose header parses and has the larger `gen`.

## Snapshot format (`json_codec.mbt` + persist)

- First line: header JSON `{"v":1,"gen":<int>,"clock":<int64>}` (`SNAPSHOT_VERSION`, `parse_snapshot_header`, `build_snapshot_text`).
- Subsequent lines: one `MemoryEntry` JSON each (`entry_to_json` / `entry_from_json`).
- Truncated trailing half-line on load is discarded and counted in `truncated_recovered` (`parse_snapshot_text`).

All JSON parsing for snapshots/entries lives in `json_codec.mbt`. Persist builds/loads strings and calls those helpers; it does not reimplement codecs.

## Trait and backends (`src/persist.mbt`)

```text
PersistenceBackend
  load() -> Result[String?, MoomemError]   # None = empty store
  save(snapshot) -> Result[Unit, MoomemError]
```

| Backend | Use |
|---------|-----|
| `FsBackend` | native disk dual-slot |
| `MemoryBackend` | in-process; default for wasm/js; crash inject via `set_simulate_partial_write` / `set_fail_next_save` |

`MemoryStore` holds a `&PersistenceBackend`; default selection happens in `open` (native → FS, non-native → memory unless injected). Backend differences stay inside `persist.mbt` (including `#cfg` where used).

## FS isolation rule (package import vs call site)

MoonBit package graph isolation is coarser than call-site isolation today:

| Layer | Rule |
|-------|------|
| **Package import** | Core `src/moon.pkg` **may** (and does) import `moonbitlang/x/fs`. That import is unavoidable for `FsBackend`; it does **not** authorize `@fs` use elsewhere in core. |
| **Non-test core call sites** | Only `src/persist.mbt` may call `@fs.*`. Enforce with review / `rg '@fs'` on non-test core sources — not by assuming the package graph prevents bleed. |
| **Allowlisted exceptions** | `persist_test.mbt` (native FS fixtures / tear-down) and `src/cli/` (e.g. reading import files) may use `@fs`. Those are test/CLI adapters, not a second production persistence path inside the core aggregate. |

Do **not** split a single-adapter `persist` subpackage solely to hide the `x/fs` import — one real consumer (`FsBackend`) does not justify the package churn. Prefer documenting and grepping call sites. A subpackage split is only worth revisiting if MoonBit gains finer isolation **and** there are multiple real FS consumers.

If `moonbitlang/x` FS APIs break, the replacement cost is intended to be this one adapter file (`persist.mbt`, RK-03).

## Store orchestration

- Entries and indexes are **in-memory**; persist only snapshots.
- `add` / `forget` / `close` trigger flush through the backend.
- Single-writer model assumed (no multi-process locking).

## Anti-patterns

- Reintroducing append-only JSONL without an FS API that supports it.
- Calling `@fs` from `store.mbt`, indexes, or `json_codec.mbt` (or any non-test core file other than `persist.mbt`).
- Treating “`moon.pkg` imports `x/fs`” as permission to call `@fs` outside `persist.mbt`.
- Introducing a single-adapter persist subpackage just to relocate the `x/fs` import.
- Writing JSON serializers inline in `persist.mbt` instead of `json_codec.mbt`.
- Relying on real disk for unit tests when `MemoryBackend` can inject the failure mode.
- Assuming `bytes_on_disk` / `last_write_at` are OS-accurate under `MemoryBackend` (they are logical).

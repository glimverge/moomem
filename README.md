# moomem

[![Version](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fglimverge%2Fmoomem%2Frefs%2Fheads%2Fmain%2Fmoon.mod&search=%5Eversion%5Cs%2A%3D%5Cs%2A%22%28%3FP%3Cversion%3E%5B%5E%22%5D%2B%29%22&replace=%24%3Cversion%3E&flags=m&label=version&logo=github)](https://github.com/glimverge/moomem/blob/main/moon.mod)
[![Coverage Status](https://coveralls.io/repos/github/glimverge/moomem/badge.svg?branch=main)](https://coveralls.io/github/glimverge/moomem?branch=main)
[![Docs](https://img.shields.io/badge/docs-mooncakes.io-green)](https://mooncakes.io/docs/heyq02/moomem/)
[![License](https://img.shields.io/github/license/glimverge/moomem)](https://github.com/glimverge/moomem/blob/main/LICENSE)

> MoonBit 嵌入式 Agent 记忆层：零部署、崩溃可恢复、按用户隔离。

Agent 进程一结束就失忆。**moomem** 嵌在宿主进程里，不用单独起服务。native 上把记忆写进本地目录，关掉再打开还能 `recall`。wasm / js 缺省只留在进程内存里。

## 能力

- `open` / `add` / `recall` / `forget`，外加导入导出和统计
- 向量 + BM25 混合检索，索引按 `user_id` 分开，没有全库召回
- native 双槽 JSONL：写入中途崩溃，下次仍从上一份完整快照恢复
- 嵌入、提取、冲突判定都可以换成宿主自己的实现；缺省全部离线，不需要 API Key

## 上手

需要 [moon](https://www.moonbitlang.com/) ≥ `0.1.20260920`。已发布包：[heyq02/moomem](https://mooncakes.io/docs/heyq02/moomem)。

```bash
moon add heyq02/moomem
```

```moonbit
fn main {
  let mem = @moomem.MemoryStore::open("./memory").unwrap()

  let summary = mem.add("user-42", "我对花生过敏").unwrap()
  println("extracted=\{summary.extracted} inserted=\{summary.inserted}")

  let hits = mem.recall("user-42", "花生过敏", top_k=3).unwrap()
  for e in hits {
    println("[\{e.created_at}] \{e.content}")
  }

  ignore(mem.close())
}
```

native 上，同一目录再次 `open`，记忆还在，`recall` 结果一致。

> [!NOTE]
> 缺省实现不访问网络。要做语义提取或真实向量，在 `open` 时注入 `Embedder`、`Extractor`、`ConflictJudge`。

[`demo/`](demo/) 就是这样接的：Qwen 做嵌入，DeepSeek 做提取。复制 `demo/.env.example` 为 `demo/.env`，填上密钥后：

```bash
cd demo
moon run cmd/main
```

它会写入几条记忆、召回，再打开同一目录确认还在。闲聊不会入库。

## 磁盘布局

`open("./memory")` 之后，native 上磁盘上是这样的（`<path>` 是你传给 `open` 的目录）：

```
<path>/moomem/head          # 一个字符，"0" 或 "1"，指向当前有效槽
<path>/moomem/slot0.jsonl   # 快照槽 A
<path>/moomem/slot1.jsonl   # 快照槽 B
```

`head` 指到哪个槽，哪个就是当前真相。写入时的顺序是**先整份覆盖写进非当前槽，成功后再拨 `head`**：

- 写槽写到一半崩溃 → `head` 还指着旧槽，数据一点不丢；
- 拨 `head` 写到一半崩溃 → `head` 损坏，此时回退到"两个槽里都能解析 header、且 `gen` 更大的那个"。

每个 `slot*.jsonl` 是 JSON Lines：第 1 行是 header，之后每行一条记忆，**按 `seq` 升序**。header 三个字段：

```json
{"v":1,"gen":4,"clock":2}
```

`v` 是快照格式版本（当前 `1`，存在 `SNAPSHOT_VERSION`），`gen` 是快照代数（每次落盘 +1），`clock` 是落盘时的逻辑时钟上界。

恢复时的容错边界很窄，这是有意的：只有**最后一行**是半行（写崩了）才会被丢弃，并计入 `stats().truncated_recovered`；任何**中部**行损坏或出现空行，`open` 直接返回 `StoreCorrupted` 报错，不静默丢数据。`v` 对不上也报 `StoreCorrupted`。

一条记忆行长这样（256 维哈希嵌入，节选）：

```json
{"id":"000000000001-6091","user_id":"user-42","content":"我对花生过敏",
 "kind":"unstructured","embedding":[0,0,...],"keywords":["我","对","我对","花","对花","..."],
 "status":"active","created_at":1,"superseded_by":null,"seq":1,
 "metadata":{"extractor":"raw"}}
```

`status` 有 `active` / `superseded` / `deleted` / `unstructured` 四种。`recall` 只返回 `active` 与 `unstructured` 这两类，被覆盖和被删除的条目**仍留在快照里**供审计。注意 `kind` 和 `status` 是两个独立字段：上面那条记忆是 `kind=unstructured`（缺省 `RawExtractor` 原样入库）配 `status=active`（还生效着）。

`metadata` 里 `extractor` 记提取器模式；若这次写入降级过，还会多出 `extraction_degraded` 或 `embedding_degraded`。

向量索引、BM25 索引和去重表都不落盘——它们是派生结构，`open` 时从快照重建。所以**快照是唯一真相**，拷走 `moomem/` 目录就等于拷走全部记忆。

> [!NOTE]
> 这是全量快照，不是追加日志：每次落盘都重写整份条目。写入量越大、单次越慢，这个库没有做过规模压测，所以不承诺具体条数上限——请按自己的数据量实测。真正需要追加写时，自己实现 `PersistenceBackend`（例如 native 侧用 extern C 做 append）。wasm / js 缺省用内存后端，根本不落盘。

## 示例

三条演示都不读密钥、不访问网络：

```bash
moon run examples/default-reopen --target native
```

| 示例 | 看什么 |
|------|--------|
| `examples/default-reopen` | 写入、召回、关掉再打开 |
| `examples/host-inject-supersede` | 注入嵌入和提取后，旧事实被覆盖 |
| `examples/isolation-forget-import` | 用户隔离、遗忘、导出再导入 |

## 项目治理

本项目的状态、路线图、变更与决策记录统一收纳在 [`docs/`](docs/)：

- 当前状态：[`docs/STATUS.md`](docs/STATUS.md)
- 路线图：[`docs/ROADMAP.md`](docs/ROADMAP.md)
- 变更记录：[`docs/CHANGELOG.md`](docs/CHANGELOG.md)
- 决策记录：[`docs/DECISIONS.md`](docs/DECISIONS.md)
- 代码布局：[`docs/CODE-LAYOUT.md`](docs/CODE-LAYOUT.md)（含 [`src/README.md`](src/README.md) 包内地图）

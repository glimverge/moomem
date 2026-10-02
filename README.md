# heyq02/moomem

[![Version](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fglimverge%2Fmoomem%2Frefs%2Fheads%2Fmain%2Fmoon.mod&search=%5Eversion%5Cs%2A%3D%5Cs%2A%22%28%3FP%3Cversion%3E%5B%5E%22%5D%2B%29%22&replace=%24%3Cversion%3E&flags=m&label=version&logo=data:image/svg+xml;charset=utf-8;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA2NCA2NCIgd2lkdGg9IjY0IiBoZWlnaHQ9IjY0IiBmaWxsPSJub25lIj4KICA8ZGVmcz4KICAgIDxtYXNrIGlkPSJjdXRvdXQiPgogICAgICA8cmVjdCB3aWR0aD0iNjQiIGhlaWdodD0iNjQiIGZpbGw9IndoaXRlIiAvPgogICAgICA8ZyB0cmFuc2Zvcm09InRyYW5zbGF0ZSgxMiAxMi41KSBzY2FsZSgxLjMyKSIgZmlsbD0iYmxhY2siPgogICAgICAgIDxwYXRoIGQ9Ik0xNC43OTE2IDM3LjQ2MjRDOC41MDEwNyAzNy40NjI0IDMuOTMzODQgMzMuODIyIDMuOTMzODQgMjkuMjY1N0MzLjkzMzg0IDI0LjcwOTUgNy4yMzM3NSAyMS4wMTU5IDE0Ljc5MTYgMjAuOTYyN0MyMi4zNDk1IDIwLjkwOTUgMjUuNzU2IDI0LjcwOTUgMjUuNzU2IDI5LjI2NTdDMjUuNzU2IDMzLjgyMiAyMC43MDk3IDM3LjQ2MjQgMTQuNzkxNiAzNy40NjI0WiIgLz4KICAgICAgICA8cGF0aCBkPSJNMTUuMTg5NyAyMS4xNzU1TDE3LjUzMTYgNS4zMTQ2MUMxNy41MzE2IDUuMzE0NjEgMTguNDM2NCAwLjc5MDQ5OCAyMi4zMjE4IDAuODQzNzI4QzI2LjIwNzIgMC44OTY5NTcgMjkuMDI4MSA2LjgwNDg4IDI5LjEzNDYgMTEuNTk1MUMyOS4wNTg0IDE3Ljc0NzggMjUuNjc1IDE1LjY3OTYgMjMuODEyMSAxMi42NTk2QzIzLjgxMjEgMTIuMjg3MSAxOS4yMzQ3IDIxLjYwMTMgMTkuMjM0NyAyMS42MDEzTDE1LjE4OTcgMjEuMTc1NVoiIC8+CiAgICAgICAgPHBhdGggZD0iTTE0LjU1MDUgMjEuMTc1NUwxMi4yMDg2IDUuMzE0NjFDMTIuMjA4NiA1LjMxNDYxIDExLjMwMzggMC43OTA0OTggNy40MTg0NiAwLjg0MzcyOEMzLjUzMzAyIDAuODk2OTU3IDAuNzEyMDkzIDYuODA0ODggMC42MDU3MTMgMTEuNTk1MUMwLjY4MTgzMyAxNy43NDc4IDQuMDY1MzIgMTUuNjc5NiA1LjkyODExIDEyLjY1OTZDNS45MjgxMSAxMi4yODcxIDEwLjUwNTUgMjEuNjAxMyAxMC41MDU1IDIxLjYwMTNMMTQuNTUwNSAyMS4xNzU1WiIgLz4KICAgICAgPC9nPgogICAgPC9tYXNrPgogIDwvZGVmcz4KICA8Y2lyY2xlIGN4PSIzMiIgY3k9IjMyIiByPSIzMCIgZmlsbD0iI0QwOEExRSIgbWFzaz0idXJsKCNjdXRvdXQpIiAvPgo8L3N2Zz4K)](https://github.com/glimverge/moomem/blob/main/moon.mod)
[![Test Status](https://img.shields.io/github/actions/workflow/status/glimverge/moomem/test-pipeline.yml?label=test_pipline&logo=github)](https://github.com/glimverge/moomem/actions)
[![Docs](https://img.shields.io/badge/docs-mooncakes.io-green)](https://glimverge.github.io/moomem/)
![GitHub License](https://img.shields.io/github/license/glimverge/moomem)
![X (formerly Twitter) Follow](https://img.shields.io/twitter/follow/heyq02)

> MoonBit 嵌入式 Agent 记忆层 —— 零部署、崩溃可恢复、按用户结构隔离。

LLM Agent 每次推理只依赖本轮上下文，进程结束即失忆。**moomem** 用几行代码加上跨会话笔记本：提取事实 → 持久化 → 混合检索召回，无需单独起服务。

**场景**：用户说「我对花生过敏」后，次日 Agent 推荐午餐前 `recall` 自动避开过敏原；说「我搬到深圳了」后，旧住址被 supersede，不再混进结果。

## 核心能力

- **两行接入** — `MemoryStore::open` + `add` / `recall`。聚合根公开方法是 `open` / `add` / `recall` / `forget` / `stats` / `close` / `export_jsonl` / `import_jsonl` / `list_entries`
- **默认零 API Key** — 嵌入 / 提取 / 冲突均为可注入 trait，缺省离线确定性实现
- **混合检索** — 向量 + BM25；缺省查询自适应融合（`AdaptiveLexical`，可回退等权 RRF）；索引按 `user_id` 物理分片
- **崩溃安全持久化** — 双槽 JSONL 快照 + `head` 指针
- **结构级用户隔离** — 检索强制带 `user_id`，无全库召回接口
- **可选 LLM 路径** — `src/llm_extractor` 对接 OpenAI 兼容端点（核心包零 LLM 依赖）

## 相对竞品 / 生态

| | moomem | OceanBase PowerMem | moon-agent BufferMemory | 跨语言 mem0 类 |
|--|--------|--------------------|-------------------------|----------------|
| 形态 | 嵌入式 MoonBit 库 | 需部署服务 | 进程内组件 | 多为服务 / 其它语言栈 |
| 持久化 | 磁盘双槽快照，重启可恢复 | 服务侧存储 | 不持久，重启即失 | 视实现而定 |
| 隔离 | `user_id` 结构级分片 | 服务侧多租户 | 进程内混用风险 | 视实现而定 |
| 后端 | native / wasm / js | 服务端 | 宿主进程 | 视实现而定 |

差异钉在：**嵌入式零部署 + 多后端 + 结构级用户隔离**。

## 证据

- [Benchmark 站内页](https://glimverge.github.io/moomem/benchmark/) — 本地归档的 LoCoMo L3 分数

## 最短上手

环境：[moon](https://www.moonbitlang.com/) ≥ `0.1.20260920`。

已发布：[heyq02/moomem](https://mooncakes.io/docs/heyq02/moomem)。在宿主工程执行：

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

次日再 `open` 同一目录：记忆完整，recall 行为一致。注入示例与完整命令见文档站。

## 快照

磁盘上的真相是双槽快照，不是索引。`open` 读出条目后重建向量索引、BM25 和去重表。格式版本是 `SNAPSHOT_VERSION = 1`，和包版本分开。

`open(path)` 使用这个目录：

```
<path>/moomem/slot0.jsonl
<path>/moomem/slot1.jsonl
<path>/moomem/head
```

`head` 的内容是 `0` 或 `1`，指向当前有效槽。每次写入先完整覆盖另一个槽，成功后再写 `head`。写槽中途崩溃时 `head` 仍指向旧槽。`head` 损坏时，选用 header 能解析且 `gen` 更大的槽。

槽文件是 JSONL。第一行是 header：

```json
{"v":1,"gen":1,"clock":1}
```

`v` 必须等于 1。之后每行一条记忆，字段为 `id`、`user_id`、`content`、`kind`（`fact` / `preference` / `event` / `unstructured`）、`embedding`、`keywords`、`status`（`active` / `superseded` / `deleted` / `unstructured`）、`created_at`、`superseded_by`（字符串或 `null`）、`seq`、`metadata`。文件尾部写了一半的行会丢掉，并计入 `stats.truncated_recovered`。中间一行损坏则这次 `open` 失败。

## 文档

| 入口 | 说明 |
|------|------|
| [文档站 Guide](https://glimverge.github.io/moomem/guide/start/introduction) | 介绍 / 上手 / 持久化 / 安全 |
| [API](https://glimverge.github.io/moomem/api/) | MemoryStore、注入点、LLM |
| [Benchmark](https://glimverge.github.io/moomem/benchmark/) | LoCoMo 归档分数与本地复跑 |

仓库速览：`src/` 核心库 · `src/llm_extractor/` 可选 LLM · `examples/` 零网络演示 · `ci/` 门禁与评测 · `site/` 文档站。

## 测试

门禁在 [`.github/workflows/test-pipeline.yml`](.github/workflows/test-pipeline.yml)：推送到 `main`、向 `main` 提 PR，或手动触发时运行。静态检查失败则不跑测试；测试失败则不跑冒烟和离线评测。冒烟与离线评测互不等待。

| 步骤 | 测什么 | 为什么 | 怎样算过 |
|------|--------|--------|----------|
| 静态检查 | `moon check --target native` | 类型和编译错误要在跑用例之前拦住 | 退出码 0 |
| 单元 / 集成 | `moon test` 在 native、wasm、wasm-gc、js 上各跑一遍。覆盖嵌入与相似度、抽取、冲突判定、编解码、崩溃恢复、存储端到端（隔离、supersede、forget、导入导出）、配置，以及可选 LLM 抽取器的降级与对抗输入 | 库宣称四个后端都能用，核心契约不能只在 native 上成立。磁盘双槽依赖本地文件系统，相关用例只在 native 编译 | 每个后端失败数为 0，且通过数等于总数。native 用例数不得低于 112，防止静默删用例 |
| 示例冒烟 | native、零网络跑四个示例：`basic-store`（写入再召回）、`llm-extractor`（mock 的 LLM，不发真实请求）、`conflict-supersede`（住址变更后旧事实被覆盖）、`cli-smoke`（库侧走一遍 add / recall / list） | 文档里的主路径要从入口跑通，且不依赖密钥或外网 | 四个 `moon run` 退出码都是 0 |
| L3 离线评测 | `moon run ci/eval/locomo --target native`。在 LoCoMo 子集上检查：近重复事实是否 supersede、重启后条目 id 是否一致、跨用户检索是否泄漏。混合检索相对 BM25 的分数会打印出来。提取精度在这一档跳过 | 前三步保证实现正确；这一步保证记忆质量没有悄悄变差。离线没有真实嵌入，整段原文入库，提取 Precision 没有意义 | 打印 `LOCOMO_PASS`。硬门槛：跨用户泄漏 0、重启一致、近重复 supersede ≥ 80% |

分数归档在 [Benchmark 页](https://glimverge.github.io/moomem/benchmark/)。2026-10-01、查询自适应融合之后：离线 hashing 混合 Recall@5 为 100/230（0.435），与纯 BM25 持平。真实嵌入（`--embedder api`）和 live 提取不进这条 CI，需要本地带密钥复跑；混合不低于 BM25 的硬门槛只在 api 档生效。

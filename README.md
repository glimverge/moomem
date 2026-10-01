# heyq02/moomem

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/glimverge/moomem/release-pipeline.yml)
![GitHub License](https://img.shields.io/github/license/glimverge/moomem)
![GitHub commit activity](https://img.shields.io/github/commit-activity/w/glimverge/moomem)

> MoonBit 嵌入式 Agent 记忆层 —— 零部署、崩溃可恢复、按用户结构隔离。

[特性](#特性) · [上手](#上手) · [公开-API](#公开-api) · [CLI](#cli) · [LLM-注入](#llm-注入) · [示例](#示例) · [文档](#文档)

**moomem** 用几行代码给 MoonBit Agent 加上长期记忆：提取事实、混合检索、冲突覆盖、进程重启后仍可恢复——无需单独起服务。

## 特性

- **两行接入** — `MemoryStore::open` + `add` / `recall`；聚合根上仅 6 个公开方法
- **默认零 API Key** — 嵌入 / 提取 / 冲突均为可注入 trait，缺省离线确定性实现
- **混合检索** — 向量 + BM25，RRF 融合；索引按 `user_id` 物理分片
- **崩溃安全持久化** — 双槽 JSONL 快照 + `head` 指针；尾部半行可恢复
- **结构级用户隔离** — 检索强制带 `user_id`，无全库召回接口，跨用户命中在结构上不可能
- **可选 LLM 路径** — `src/llm_extractor` 对接 OpenAI 兼容端点做结构化提取与冲突判定（核心包不依赖 LLM）

## 上手

### 环境

- [moon](https://www.moonbitlang.com/) ≥ `0.1.20260920`（`moon version` 确认）

### 安装

> [!NOTE]
> 尚未发布到 mooncakes。本地开发请用本仓库做 path 依赖，或把 `src/` 拷进工程。

发布后在宿主 `moon.mod.json` 中加入：

```json
{
  "deps": {
    "heyq02/moomem": "0.2.2"
  }
}
```

### 快速开始

```moonbit
fn main {
  let mem = @moomem.MemoryStore::open("./memory").unwrap()

  // 对话结束后写入：提取 → 去重 → 冲突 → 嵌入 → 双索引 → 落盘
  let summary = mem.add("user-42", "我对花生过敏").unwrap()
  println("extracted=\{summary.extracted} inserted=\{summary.inserted}")

  // LLM 调用前召回：混合检索，只返回该用户记忆
  let hits = mem.recall("user-42", "花生过敏", top_k=3).unwrap()
  for e in hits {
    println("[\{e.created_at}] \{e.content}")
  }

  ignore(mem.close())
}
```

次日再 `open` 同一目录：记忆完整，recall 行为一致。

### 免写代码的 CLI 演示

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

可选 LLM 提取（OpenAI 兼容端点；密钥只读环境变量）：

```bash
export MOOMEM_LLM_API_KEY=...
# export MOOMEM_LLM_BASE_URL=https://api.deepseek.com   # 可选
# export MOOMEM_LLM_MODEL=deepseek-chat                  # 可选，缺省 gpt-4o-mini
$BIN add --db ./mem --user user-42 --text "你好！我对花生过敏" --llm
# 同时启用 LLM 冲突判定：加 --llm-judge（隐含 --llm）
```

## 公开 API

| 方法 | 语义 | 返回 |
|------|------|------|
| `open(path, config?)` | 打开或创建记忆库 | `Result[MemoryStore, MoomemError]` |
| `add(user_id, text)` | 提取→去重→冲突→双索引→落盘 | `Result[AddSummary, MoomemError]` |
| `recall(user_id, query, top_k?)` | 混合检索（仅 `Active` / `Unstructured`） | `Result[Array[MemoryEntry], MoomemError]` |
| `forget(user_id, target)` | 软删除 `ById(id)` / `All` | `Result[Int, MoomemError]` |
| `stats()` | 计数 / 字节 / 截断恢复 / 提取模式 | `Result[StoreStats, MoomemError]` |
| `close()` | flush 后关闭（幂等） | `Result[Unit, MoomemError]` |

辅助：`export_jsonl` / `import_jsonl` / `list_entries(user_id)`。

一切可失败操作返回 `Result`，全库禁 panic。`user_id`：非空、≤64 字符、字符集 `[A-Za-z0-9_\-.]`，入口强制校验（含路径穿越拒绝）。

### 注入点

| trait | 缺省（离线） | 生产替换 |
|-------|--------------|----------|
| `Embedder` | `HashingEmbedder`（256 维词袋哈希） | 宿主 / vcdb 嵌入 |
| `Extractor` | `RawExtractor`（原文 unstructured 入库） | `src/llm_extractor` 的 `LlmExtractor` |
| `ConflictJudge` | `SimilarityJudge`（余弦 + Jaccard，阈值 0.82） | `LlmConflictJudge` |
| `PersistenceBackend` | native `FsBackend`；wasm/js `MemoryBackend` | IndexedDB 胶水等 |
| `Clock` | `LogicalClock` | 系统时钟 / 测试用 `FixedClock` |

```moonbit
let cfg : Config = Config::{
  ..Config::default(),
  judge : Some(MyLlmJudge::new() as &ConflictJudge),
  clock : Some(FixedClock::new(42L) as &Clock),
}
let store = MemoryStore::open("./memory", config=cfg).unwrap()
```

## LLM 注入

核心库默认不走 LLM；可选能力在 **`src/llm_extractor`**。

```moonbit
let provider = @openai.OpenAIProvider::new(
  "sk-...",
  endpoint=OpenAIEndpoint::OpenAI,   // 或 Custom(base_url="https://...")
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

提取保留可复用事实（`fact` / `preference` / `event` + 原文 `span`），丢弃寒暄；失败时降级可见（`AddSummary.degraded` / `notes` / 条目 metadata），不会静默吞掉。

> [!TIP]
> 请在宿主包内自行 mock `Provider`。零网络范例见 `examples/llm-extractor` 与 `src/llm_extractor/*_test.mbt`。

## 持久化

`open(path)` 目录布局：

```
<path>/moomem/slot0.jsonl   # 快照槽 A（首行 header + 每行一条 entry JSON）
<path>/moomem/slot1.jsonl   # 快照槽 B
<path>/moomem/head          # "0" 或 "1"，指向当前有效槽
```

每次 `add` / `forget` / `close` 完整重写**非当前槽**，成功后再写 `head`。写槽中途崩溃 → 旧槽仍有效；`head` 损坏 → 回退到可解析且 gen 更大的槽。尾部半行丢弃并计入 `stats.truncated_recovered`。

```
(空) → Active → Superseded   （冲突 Replace，记录 superseded_by）
             → Deleted       （forget 软删除，快照保留可审计）
```

`recall` 永不返回 `Superseded` / `Deleted`。

## CLI

| 命令 | 用途 |
|------|------|
| `add` | 写入（`--db` / `--user` / `--text`；可选 `--llm`、`--llm-judge`） |
| `recall` | 混合召回（`--query`，可选 `--top-k`） |
| `list` | 列出条目（可选 `--all`） |
| `stats` | 库统计 |
| `export` / `import` | JSONL 备份 / 恢复 |
| `help` | 用法 |

LLM 相关环境变量：`MOOMEM_LLM_API_KEY`、`MOOMEM_LLM_BASE_URL`、`MOOMEM_LLM_MODEL`。CLI 旗标优先于环境变量。

## 示例

全部为 mock 驱动、零网络：

```bash
moon run examples/basic-store --target native
moon run examples/llm-extractor --target native
moon run examples/conflict-supersede --target native
moon run examples/cli-smoke --target native
```

## 测试与评测

```bash
moon test                         # native（核心 + llm_extractor + cli）
moon test --target wasm           # 四后端；native 专属磁盘/CLI 测试除外
moon test --target wasm-gc
moon test --target js

moon run ci/tools/retrieval-tuning --target native   # 离线调参台
moon run ci/eval/locomo --target native              # LoCoMo 子集；成功日志含 LOCOMO_PASS
moon run ci/eval/locomo --target native -- --report /tmp/offline.json
```

可选 live 档（不进 push CI）：

```bash
moon run ci/eval/locomo --target native -- --embedder api   # 需 MOOMEM_EMBED_*
moon run ci/eval/locomo --target native -- --live           # 需 DEEPSEEK_*
```

正式发版成功后（非 dry-run），`benchmark-archive` job 会跑 offline + api + live，写入 `benchmarks/locomo/results/<version>.json` 并以 `chore(benchmark):` 提交。站点页：`site/docs/benchmark/`（导航 **Benchmark**）。本地试跑归档（不 push）：

```bash
set -a && source .env && set +a   # QWEN_* + DEEPSEEK_*
NEW_VERSION=0.0.0-dev SKIP_COMMIT=1 bash scripts/ci/run-locomo-benchmark-archive.sh
```

`QWEN_*` 在未设置 `MOOMEM_EMBED_*` 时会映射过去。结果 JSON 永不写入 API Key。

LoCoMo 数据许可见 [`ci/eval/locomo/data/README.md`](ci/eval/locomo/data/README.md)（CC BY-NC 4.0）。离线 hashing 嵌入可能弱于纯 BM25；≥15% 混合增益目标仅在 `--embedder api` 下评估。

## 项目结构

```
src/                 核心库（MemoryStore 编排）
  llm_extractor/     可选 LLM 提取 / 冲突判定适配
  cli/               add / recall / list / stats / export / import
examples/            E2 演示（basic-store / llm-extractor / conflict-supersede / cli-smoke）
ci/
  gates/             Live LLM 发版门禁
  eval/locomo/       L3 LoCoMo harness + 数据
  tools/             离线检索调参
benchmarks/locomo/   发版归档的 LoCoMo 分数（站点消费）
docs/                项目文档（架构 / PRD / 评测报告）
site/                Rspress 文档站（GitHub Pages）
```

## 安全边界

> [!IMPORTANT]
> **库不做角色鉴权。** moomem 是嵌入式库，信任边界在宿主进程：能调用 API 的代码即拥有该记忆库全部读写权。用户隔离是结构保证（`user_id` 分片 + 检索强制带 user_id），不能替代宿主信任模型。

- `user_id` 不进入文件系统路径；禁止 `/`、`\`、空白与控制字符
- LLM 密钥由宿主注入，库不持久化任何密钥
- 共享存储上的目录级 ACL 责任归宿主

## 已知限制

- 持久化为**双槽全量快照**（对「追加写 JSONL」的有意偏差）：当前文件系统 API 无 append/rename
- 缺省 `HashingEmbedder` 无真实语义——同义召回需注入生产级嵌入
- 缺省 `SimilarityJudge` 主要覆盖近重复更新；语义型变更（如搬家）需 `LlmConflictJudge`
- 单写者模型；v0.1 不支持并发写
- wasm/js 缺省为进程内 `MemoryBackend`，磁盘持久化需宿主注入

细节与边界场景：[docs/project/07-w3.1-verification.md](docs/project/07-w3.1-verification.md)、[docs/project/architecture.md](docs/project/architecture.md)。

## 文档

- [文档索引](docs/README.md) — 项目 / 资源 / 归档地图
- [架构设计](docs/project/architecture.md) — 模块、注入点、双槽持久化
- [PRD](docs/project/03-prd.md) — 产品需求
- [测试与示例落点](docs/project/10-testing-examples-architecture.md)
- [LoCoMo 评测报告](docs/project/08-w4-eval-report.md)

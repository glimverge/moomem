# moomem

**MoonBit 嵌入式 Agent 记忆层库** —— 给你的 Agent 一个零部署、可持久化、用户隔离的长期记忆。

- 纯 MoonBit 实现，核心库唯一外部依赖为官方 `moonbitlang/x`（仅 `fs` 子包，且全部调用被锁死在 `persist.mbt` 适配层）；LLM 能力收敛在独立适配包 `src/llm_extractor`（依赖 `mizchi/llm`，核心零第三方依赖的铁律不破）
- **零 API Key 可运行**：嵌入 / 提取 / 冲突判定全部是一等注入 trait，缺省实现确定性、离线（词袋哈希嵌入 + raw 直通提取 + 余弦规则判定）
- 向量 + BM25 双路混合检索，RRF 融合
- 双槽快照持久化 + 崩溃恢复（尾部半行截断）
- `user_id` 物理分片隔离：跨用户检索在结构上不可能发生

```
moomem v0.2.2 ｜ moonbitlang/x@0.5.5 ｜ mizchi/llm@0.3.2（仅 llm_extractor / CLI --llm）｜ Apache-2.0
```

---

## 15 分钟上手

### 0) 环境

- [moon](https://www.moonbitlang.com/) ≥ 0.1.20260920（`moon version` 确认）

### 1) 安装依赖

```bash
moon add moonbitlang/x   # moomem 依赖它做磁盘持久化（仅 fs 子包）
moon add mizchi/llm      # 仅使用 LLM 提取适配包（src/llm_extractor）时需要
```

在宿主项目 `moon.mod.json` 的 `deps` 中引入 moomem（发布到 mooncakes 后）：

```json
{
  "deps": { "moonbitlang/x": "0.5.5", "<你的用户名>/moomem": "0.1.0" }
}
```

> 当前仓库尚未发布 mooncakes；本地开发直接以本仓库为 path 依赖或将 `src/` 拷入工程即可。

### 2) 两行代码接入（场景 A 完整走通）

```moonbit
fn main {
  // ① 打开（首次创建，二次恢复）记忆库目录
  let mem = @moomem.MemoryStore::open("./memory").unwrap()

  // ② 对话结束后写入：内部完成 提取→去重→冲突→嵌入→双索引→落盘
  let summary = mem.add("user-42", "我对花生过敏").unwrap()
  println("AI 理解了什么: extracted=\{summary.extracted} inserted=\{summary.inserted}")

  // ③ LLM 调用前召回：向量+BM25 双路融合，只返回该用户自己的记忆
  let hits = mem.recall("user-42", "花生过敏", top_k=3).unwrap()
  for e in hits {
    println("[\{e.created_at}] \{e.content}")
  }

  ignore(mem.close()) // 安全关闭并刷盘
}
```

程序退出，次日重启 `open` 同一目录：记忆完整，recall 行为一致（AC-01）。

### 3) 免 API 的 CLI 演示（无需写代码）

```bash
moon build src/cli --target native
BIN=_build/native/debug/build/src/cli/cli.exe

$BIN add    --db ./mem --user user-42 --text "我对花生过敏"
$BIN recall --db ./mem --user user-42 --query "花生过敏"
$BIN list   --db ./mem --user user-42
$BIN stats  --db ./mem
$BIN export --db ./mem > backup.jsonl
$BIN import --db ./mem --file backup.jsonl

# 可选：LLM 提取（OpenAI 兼容端点；密钥只读环境变量）
# export MOOMEM_LLM_API_KEY=...
# export MOOMEM_LLM_BASE_URL=https://api.deepseek.com   # 可选
# export MOOMEM_LLM_MODEL=deepseek-chat                  # 可选，缺省 gpt-4o-mini
$BIN add --db ./mem --user user-42 --text "你好！我对花生过敏" --llm
# 同时启用 LLM 冲突判定：加 --llm-judge（隐含 --llm）
```

### 4) 运行测试

```bash
moon test                    # native 后端，全绿（核心 + llm_extractor + cli）
moon test --target wasm      # 四后端行为一致（AC-06）；native 专属的磁盘与 CLI 测试除外
moon test --target wasm-gc
moon test --target js
moon run ci/tools/retrieval-tuning --target native   # 零网络离线调参台（检索/冲突参数网格扫描）
```

### 5) L3 评测（LoCoMo 子集）

离线（零网络、零密钥；`test-pipeline` 的 `eval-locomo` job 同此命令）：

```bash
moon run ci/eval/locomo --target native
# 成功日志含 LOCOMO_PASS
```

可选档位：

```bash
# 真实嵌入 API（需 MOOMEM_EMBED_API_KEY 等；不进 push CI）
moon run ci/eval/locomo --target native -- --embedder api

# 提取 Precision（需 DEEPSEEK_*；仅 --live 时读密钥）
moon run ci/eval/locomo --target native -- --live
```

数据与许可说明见 `ci/eval/locomo/data/README.md`（LoCoMo 派生切片为 CC BY-NC 4.0）。离线 hashing 下混合检索可能低于纯 BM25（无语义嵌入）；≥15% 增益仅在 `--embedder api` 下评估（`TARGET_15PCT`）。

---

## 公开 API（6 个方法）

| 方法 | 语义 | 返回 |
|---|---|---|
| `open(path, config?)` | 打开或创建记忆库（目录不存在则创建） | `Result[MemoryStore, MoomemError]` |
| `add(user_id, text)` | 写入：提取→去重→冲突→双索引→落盘 | `Result[AddSummary, MoomemError]` |
| `recall(user_id, query, top_k?)` | 混合检索融合排序，只返回 active/unstructured | `Result[Array[MemoryEntry], MoomemError]` |
| `forget(user_id, target)` | 软删除（`ById(id)` / `All`），快照保留可审计 | `Result[Int, MoomemError]` |
| `stats()` | 条目计数 / 状态分布 / 字节数 / 恢复截断计数 | `Result[StoreStats, MoomemError]` |
| `close()` | flush 后关闭；幂等 | `Result[Unit, MoomemError]` |

辅助：`export_jsonl()` / `import_jsonl()` / `list_entries(user_id)`（FR-07/08，CLI 同源使用）。

一切可失败操作返回 `Result[T, MoomemError]`，全库禁 panic。`user_id` 契约：非空、≤64 字符、字符集 `[A-Za-z0-9_\-.]`，所有入口强制校验（含路径穿越拒绝）。

## 注入点（生产环境替换缺省实现）

| trait | 缺省实现（确定性、离线） | 生产替换 |
|---|---|---|
| `Embedder` | `HashingEmbedder`（256 维词袋哈希，TF + L2 归一） | vcdb / 宿主嵌入服务适配 |
| `Extractor` | `RawExtractor`（原文 kind=unstructured 直通，零 Key） | `src/llm_extractor` 包的 `LlmExtractor`（见下节） |
| `ConflictJudge` | `SimilarityJudge`（余弦+关键词 Jaccard，阈值 0.82，候选窗口 8） | `src/llm_extractor` 包的 `LlmConflictJudge`（见下节） |
| `PersistenceBackend` | native: `FsBackend`；wasm/js: `MemoryBackend` | 浏览器 IndexedDB 胶水等 |
| `Clock` | `LogicalClock`（快照续接的单调逻辑时钟） | 系统时钟 |

```moonbit
let cfg : Config = Config::{
  ..Config::default(),
  judge : Some(MyLlmJudge::new() as &ConflictJudge),
  clock : Some(FixedClock::new(42L) as &Clock), // 测试精确断言 created_at
}
let store = MemoryStore::open("./memory", config=cfg).unwrap()
```

## W2 LLM 注入（mizchi/llm 适配器）

核心包 `src/` 保持零第三方依赖（铁律）；LLM 能力收敛在独立适配包
**`src/llm_extractor`**（依赖 `mizchi/llm@0.3.2`，仅用其纯 trait 层，不触碰 ffi）。
缺省 `RawExtractor` 不做闲聊过滤；注入 `LlmExtractor` 后即获得 PRD 13.1 的
结构化事实提取（AC-03）。

### 用法

```moonbit
// 宿主 moon.pkg.json import:
//   "heyq02/moomem/src"  "heyq02/moomem/src/llm_extractor"  "mizchi/llm/openai"

// ① 构造 LLM 客户端（OpenAI 兼容端点：OpenAI/OpenRouter/Ollama/自建网关）
let provider = @openai.OpenAIProvider::new(
  "sk-...",
  endpoint=OpenAIEndpoint::OpenAI,   // 或 Custom(base_url="https://...")
  model="gpt-4o-mini",
)

// ② 包装为 moomem 注入点（LLM 客户端可注入 = 可 mock 测试）
let extractor = @llm_extractor.LlmExtractor::new(provider)
let judge = @llm_extractor.LlmConflictJudge::new(provider)

// ③ 注入 MemoryStore
let cfg : Config = Config::{
  ..Config::default(),
  extractor : Some(extractor as &Extractor),
  judge : Some(judge as &ConflictJudge),
}
let store = MemoryStore::open("./memory", config=cfg).unwrap()
// add("user-42", "你好！我对花生过敏") → 只入库 Fact("用户对花生过敏", span="我对花生过敏")
```

可运行示例（脚本化 mock 驱动、零网络）：`moon run examples --target native`。

### 提取契约（PRD 13.1）

- 输出结构化事实：`content` + `kind`（fact / preference / event）+ 原文依据 `span`
- 只保留可复用信息，寒暄丢弃（提取 0 条 → 不入库，`AddSummary.extracted=0`）
- 忠实原文不改写、不推断；歧义按"宁少勿错"丢弃（未知 kind 的单条事实直接丢弃）
- 容错解析：接受 markdown 代码围栏、JSON 前后夹带说明文字；单条事实上限 `max_facts`（默认 16）

### 稳定性与降级（PRD 13.3）

| 场景 | 行为 | 失败原因可见处 |
|---|---|---|
| 正常 | 单次提取 1 次 LLM 调用 | — |
| 非法 JSON | 携纠正指令重试 1 次（共 2 次，调用预算上限） | — |
| 重试仍非法 | **降级**：原文以 kind=unstructured 入库，不抛错（缺省 `ReturnRaw` 策略） | `AddSummary.degraded` / `notes` / `metadata.extraction_degraded` + `last_failure_reason()` |
| 网络/鉴权失败 | 不重试，直接降级（1 次调用；原因前缀 `transport error:`） | 同上 |
| 冲突判定失败 | `Err` → store 降级为"两条并存"，`AddSummary.degraded=true` | `AddSummary.notes`、`judge.last_failure_reason()` |

两种降级策略 `DegradePolicy`：
- `ReturnRaw`（缺省）：提取器自行降级返回原文 unstructured，`add` 永不因提取失败报错；
  降级在 `AddSummary.degraded`、`notes` 与条目 `metadata.extraction_degraded` 三处可见——不会静默；
- `PropagateError`：返回 `Err`，交给 `MemoryStore` 统一降级——同上三通道可见，并参与 PRD 第 9 章
  "连续 3 次失败熔断"（第 3 次 `add` 返回 `ExtractionFailure`）。

观测 API：`LlmExtractor::llm_call_count()` / `last_failure_reason()`、
`LlmConflictJudge::llm_call_count()` / `last_failure_reason()`；
条目 `metadata.extractor == "llm"`，`stats().extractor_mode == "llm"`（12.3 可解释）。

### 注意事项

- `mizchi/llm` 主包的 `MockProvider` / `BoxedProvider` 的 `Provider` 实现未导出
  （跨包不可见）：宿主 mock 请在自己包内 `impl @llm.Provider for MyMock`，
  18 个无网络黑盒测试（`src/llm_extractor/llm_extractor_test.mbt`）即此范例
- 真实 HTTP 走 `mizchi/llm/openai`（或 `anthropic`）子包，由 mizchi/llm 的 ffi 层
  按后端（native/js/wasm）分发；moomem 核心与 `src/llm_extractor` 包本身不依赖 ffi，
  四后端测试均零网络

## 持久化与崩溃恢复

磁盘布局（`open(path)` 目录下）：

```
<path>/moomem/slot0.jsonl   # 快照槽 A：首行 header + 每行一条 entry JSON
<path>/moomem/slot1.jsonl   # 快照槽 B
<path>/moomem/head          # "0" 或 "1"，指向当前有效槽
```

- 每次 `add` / `forget` / `close` 触发一次 **全量快照重写**：先完整写非当前槽，成功后写 head
- 写槽中途崩溃 → head 仍指旧槽，数据无损；写 head 中途崩溃 → head 损坏时回退"取能解析且 gen 更大的槽"
- 快照尾部半行（进程被杀）→ 重启时丢弃并计入 `stats.truncated_recovered`
- `created_at` 为注入 Clock 的逻辑毫秒；条目 `id = "{seq 12位hex}-{rand 4 hex}"`，seq 持久化续接永不复用

## 状态机与检索可见性

```
(空) → Active → Superseded（冲突 Replace，记录 superseded_by）
              → Deleted（forget 软删除）
```

recall 只返回 `Active` / `Unstructured`；`Superseded` / `Deleted` 物理保留于快照与导出（可审计）。所有 AI 参与环节（提取模式、降级、冲突裁决）写入条目 `metadata`，export / stats 可见。

## 性能

- 全量快照重写复杂度 O(条目数)：万级条目、单条 ~300B 时快照 ~3MB，v0.1 可接受
- 检索：向量路为内存暴力余弦 O(n·d)、BM25 为内置倒排；适合单进程万级条目
- 单写者模型：不支持并发写（v0.1 文档明示）

## 安全边界（必读）

- **库不做角色鉴权**：moomem 是嵌入式库，信任边界在宿主进程。任何能调用库 API 的代码即拥有该记忆库的全部读写权
- **用户隔离的结构保证**：索引与去重表按 `user_id` 物理分片，检索入口强制携带 user_id，无"全库检索"接口；跨用户检索在结构上不可能发生（有渗透测试覆盖）
- **user_id 不进入文件系统路径**，且禁止 `/` `\` 空白与控制字符，杜绝对持久化目录的路径穿越
- LLM 密钥由宿主注入，**库不持久化任何密钥**
- 若宿主将记忆库目录置于共享存储，目录级访问控制的隔离责任归宿主

## 已知限制

1. **持久化为双槽全量快照**（对 PRD"追加写 JSONL"的有意偏差）：`moonbitlang/x/fs` 无 append/rename API，追加日志无法实现；万级以上条目的高频写入场景建议关注 v0.2（native 侧 extern C 追加写 / x/fs 出 append API 后切回日志追加）
2. recall 在命中数不足 top_k 时会用该用户最新条目**补齐**（零命中仍返回空列表，不编造）；该策略可通过 `Config.backfill = RecallBackfill::NoBackfill` 关闭
3. 缺省 `HashingEmbedder` 无语义能力：字面无重叠的语义关联（如"午餐"↔"花生过敏"）召回不到，需注入真实嵌入模型
4. **缺省 `SimilarityJudge` 的冲突判定仅覆盖"近重复式"事实更新**（实测：`严重过敏原清单包含花生制品项` → `...海鲜制品项`，相似度 0.828，刚过 0.82 阈值）。语义型更新在缺省离线路径下**不会**触发 supersede——例如 PRD AC-04 的原始场景"我住在北京市海淀区" → "我住在深圳市南山区"，实测相似度仅 0.471（cos 0.471 / Jaccard 0.259），判定为 Ignore。**AC-04 的语义路径由注入 `LlmConflictJudge` 覆盖**（见 `ci/gates/live-llm` L2-07）；离线档位由 `ci/tools/retrieval-tuning` 语料覆盖。这也意味着 `supersede_threshold` 上调（如 0.90）会显著削弱近重复档的召回（实测 supersede 3/3 → 1/3）
5. recall 环节的嵌入失败降级为 BM25 单路，但**不**在该次结果上标记 degraded（add 环节的降级标记完整）
6. superseded / deleted 的恢复 API 未开放（v0.2 候选，`InvalidOperation` 预留）
7. `stats.bytes_on_disk` 为快照字符数（MemoryBackend 下为逻辑值），非精确磁盘字节
8. wasm/js 后端缺省为进程内 `MemoryBackend`（无本地文件系统），磁盘持久化需宿主注入 `PersistenceBackend`
9. 超长条目不做截断：缺省 `HashingEmbedder` 对内容长度无上限，本场景不会触发问题；注入生产级 Embedder 后请在 v0.2 评估长度上限与截断策略
10. **HTTP 代理拦截本地端点时，传输失败会被报成 `invalid JSON`**（实测环境变量 `HTTP_PROXY` 生效时）：上游 `mizchi/llm` 的 SSE 传输仅在 curl **非零退出** 时上报 `StreamEvent::Error`，而代理通常返回 HTTP 200 + 纯文本错误体（退出码 0），既无错误事件也无 `data:` 行，故落入 JSON 解析失败分支、并多消耗 1 次调用预算。**关闭代理后同一场景正确输出 `transport error: … curl: (7) Failed to connect`**。详见 [docs/project/07-w3.1-verification.md](docs/project/07-w3.1-verification.md) §4
11. **连续失败计数的清零条件为「成功且有 ≥1 条事实」**：提取成功但结果为空（纯闲聊）时不重置计数。因此「失败 → 闲聊 → 失败 → 闲聊 → 失败」会触发熔断，与"连续 3 次失败"的字面语义略有出入（只会提前、不会漏报）。见 07 报告 §5

## 项目结构

```
src/
├── lib.mbt           版本常量与包说明
├── types.mbt         核心类型 / user_id 校验 / id 生成
├── errors.mbt        MoomemError 统一错误
├── json_codec.mbt    唯一 JSON 编解码处
├── embedder.mbt      Embedder trait + HashingEmbedder + cosine_similarity
├── clock.mbt         Clock trait + LogicalClock / FixedClock
├── extractor.mbt     Extractor trait + RawExtractor
├── conflict.mbt      ConflictJudge trait + SimilarityJudge
├── dedup.mbt         内容指纹去重
├── index_vector.mbt  每 user 分片余弦近邻
├── index_keyword.mbt 每 user 分片 BM25（CJK 单字+二元组分词）
├── ranker.mbt        RRF 融合
├── persist.mbt       PersistenceBackend + FsBackend/MemoryBackend（唯一 fs 调用点）
├── store.mbt         MemoryStore 编排（open/add/recall/forget/stats/close）
├── *_test.mbt        黑盒测试（58 个，覆盖 AC-01/02/04/05 与崩溃恢复；其中 3 个为 native 专属）
├── llm_extractor/    W2 LLM 适配包：LlmExtractor + LlmConflictJudge（依赖 mizchi/llm，
│                     核心包不依赖；35 个零网络 mock 黑盒测试）
└── cli/              CLI 工具（add/recall/list/stats/export/import）

examples/             W2 可运行示例：moon run examples（mock 驱动，零网络）
```

## 项目文档

- [文档索引](docs/README.md)：全项目文档地图（结构对齐 FlowUs PARA：项目主体 / 调研资源 / 归档）
- [架构设计](docs/project/architecture.md)：模块划分、注入点、双槽快照持久化（含类图 / add·recall 时序图）
- [选题调研 → 竞品复核](docs/resources/README.md)（资源层）｜[PRD → 进度 → 测试 → 验证 → 评测 → 交接](docs/project/README.md)（项目层）：全生命周期编号报告 01–09

## License

Apache-2.0

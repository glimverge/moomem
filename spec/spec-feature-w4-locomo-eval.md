# W4 工程任务规格书：LoCoMo 评测闭环（Cursor 执行版）

> 目标：把 PRD 第 16 章的量化指标从「承诺」变成「可复现数字」，产出 PRD §18 的 W4 交付物
> （LoCoMo 子集评测报告 + 三后端 CI + 文档 + README）。
>
> 定位：四层测试体系中的 **L3**（见 `docs/reports/05-test-suite.md`）——离线可复现为主，
> 真实 LLM 档位随发版门禁执行，**不并入 push/PR 的 L0 门禁**（除离线部分）。
>
> 本规格书基于逐文件核实的代码事实（§1），执行者**不需要也不应**重新调研生态或 API。

---

## 0. 范围与已决议事项

| 项 | 决议 | 影响 |
|---|---|---|
| 混合检索 ≥15% 的验证通道 | **双轨**：离线 hashing 基线（默认）+ 真实嵌入 API 可选模式 | 离线档位不得伪造 15% 断言（见 §3.3） |
| LoCoMo 数据纳入方式 | **提交极小样本 fixture**（已由产品侧生成并随本次提交） | 数据资产在 `ci/locomo/data/`，含 CC BY-NC 4.0 署名 |
| 评测范围 | **PRD §16.1 四项全做** | 检索 / 提取 / 冲突 / 持久化+隔离 |
| R2 修复 | **并入 W4 作为 W4-0**，随 v0.2.2 发布 | 先修 core，再建 harness |

**交付物清单**

1. `ci/locomo/` 离线评测 harness（native main 包，零网络、零密钥可跑）
2. 真实嵌入 API 可选模式（环境变量驱动）
3. `ci/locomo` 接入 `test-pipeline`（离线门禁）
4. README / 04 进度 / 05 测试体系文档同步
5. `docs/reports/08-w4-eval-report.md` —— **由产品侧依据 harness 输出撰写**，不在本任务范围

---

## 1. 代码事实表（已逐文件核实，直接使用）

| 文件:行号 | 事实 | 用途 |
|---|---|---|
| `src/store.mbt:65` | `MemoryStore::open(path, config?)`；传真实路径 → native 缺省 `FsBackend(path)`，传 `memory://x` + 显式 `MemoryBackend` → 内存后端 | harness 两种后端用法 |
| `src/store.mbt:recall` | `recall(user_id, query, top_k?) -> Result[Array[MemoryEntry], MoomemError]`；返回**纯条目数组**，无打分字段 | 检索指标按「top-k 里是否存在命中」判定 |
| `src/store.mbt`（recall 内） | 候选数 = `recall_candidates` 或 `min(top_k*2, 50)`；`rrf([vec_ids, kw_ids], rrf_k, k)` 融合；随后 `BackfillRecency` 补齐到 top_k | 指标口径与「补齐」行为相关（见 §3.2 注意） |
| `src/embedder.mbt:7-15` | `pub(open) trait Embedder { fn embed(Array[String]) -> Result[Array[Array[Double]], MoomemError]; fn dim() -> Int }` — 可外部实现 | 假嵌入器（BM25 单路基线）+ API 嵌入器 |
| `src/embedder.mbt:56-75` | 缺省 `HashingEmbedder`：小写 → `tokenize` → FNV-1a 分桶 → L2 归一，**无任何语义能力** | 离线基线预期：混合 ≈ BM25 |
| `src/embedder.mbt:79` | `pub fn cosine_similarity(a, b)`，长度不等或为空返回 0.0 | 逐对相似度诊断 |
| `src/index_keyword.mbt:41` | `pub fn tokenize(text)`：CJK 逐字 + 相邻二元组；**拉丁字母数字串按整词（小写）** | 英文语料可用（无词干化，注意同义变形不匹配） |
| `src/index_keyword.mbt:238` | `KeywordIndex::search` 标准 BM25（k1=1.5, b=0.75），同分按 id 升序 | 单路基线即为产品内建 BM25，无需另写 |
| `src/index_vector.mbt:73` | `VectorIndex::search` 在 `qvec.length() == 0` 时**直接返回空** | 假嵌入器 → 干净的 BM25 单路 |
| `src/store.mbt:366` | `let embedding_failed = vec.length() != self.dim`；embedder 报错时 `entry.embedding = []` | 写入侧降级路径确认 |
| `src/conflict.mbt:52-65` | `SimilarityJudge::new(threshold, embedder, coexist_band?)`；`pub(open) trait ConflictJudge { fn judge(new_fact, candidates) }` | 冲突评测可注入空判定器 / LLM 判定器 |
| `src/conflict.mbt:97` | `pub fn keyword_jaccard(...)` | 逐对诊断（与 cosine 取 max 即判定相似度） |
| `src/types.mbt:261-288` | 公开常量：`DEFAULT_DIM=256`、`DEFAULT_RRF_K=60`、`DEFAULT_SUPERSEDE_THRESHOLD=0.82`、`DEFAULT_RECALL_TOP_K=5`、`MAX_RECALL_TOP_K=50`、`CONFLICT_CANDIDATES=8`、`COEXIST_BAND=0.15` | 缺省档位门禁 |
| `src/types.mbt` `MemoryEntry` | 字段含 `id / user_id / content / embedding / keywords / status / created_at / superseded_by / seq / metadata`；`is_recallable()` 公开 | 断言 supersede 状态与可见性 |
| `ci/tuning/main.mbt` | 离线 harness 完整先例：`fail()`+`abort`、`Metrics` 结构、`open_store` 注入 Config、`memory://` 后端、门禁 + `TUNING_PASS` 收尾 | **直接照搬其骨架风格** |
| `ci/llm_live/main.mbt:8-19` | `require_env(key)`（缺失即 abort）；`:22-34` `normalize_base_url` | live 档位环境变量校验 |
| `ci/llm_live/main.mbt:170-179` | `@openai.OpenAIProvider::new(key, endpoint=Custom(base_url~), model~, timeout_sec=, max_retries=)` → `&@llm.Provider` → `LlmExtractor::new(p)` | 提取评测的 LLM 接线 |
| `ci/llm_live/moon.pkg` | 包依赖写法先例（`mizchi/llm`、`mizchi/llm/openai`、`moonbitlang/core/env`） | 照抄 |
| `.mooncakes/mizchi/llm/src/ffi/pkg.generated.mbti:13` | `pub fn fetch(url, method, headers_json, body, timeout_sec, on_result, on_error)` —— 同步 curl，`on_error` 收到以 `ERROR:` 开头的串 | 真实嵌入 API 的唯一 HTTP 通道 |
| `~/.moon/lib/core/json/pkg.generated.mbti` | `parse(StringView) -> Json raise ParseError`；访问器 `as_object() -> Map[String,Json]?`、`as_array()`、`as_string()`、`as_number()`、`value(key)`、`item(i)` | JSON 解析一律用访问器，勿手写匹配 |
| `core/env` mbti | `@env.current_dir() -> String?`、`@env.args() -> Array[String]`、`@env.get_env_var(String) -> String?` | 路径解析与命令行参数 |
| `moonbitlang/x/fs` | `read_file_to_string(path) raise IOError`、`path_exists`、`create_dir`、`remove_dir/remove_file` | 读 fixture、持久化评测清理 |
| `src/persist_test.mbt:99-119` | 磁盘后端的建目录 / 清理 / `MemoryStore::open(dir)` 先例 | 持久化评测照抄 |
| `.github/workflows/test-pipeline.yml:24` | `NATIVE_TEST_BASELINE: "97"` —— **已陈旧**（现网 native 112） | W4-G 需更新 |

---

## 2. 数据资产（已落盘，勿重新生成）

| 文件 | 规模 | 用途 |
|---|---|---|
| `ci/locomo/data/locomo_subset.json` | 236 KB / 2 段对话 / 788 轮 / 301 QA（230 计分 + 71 对抗） | 检索评测 |
| `ci/locomo/data/conflict_pairs.json` | 20 组近重复 + 10 组语义 = 30 组 | 冲突评测 |
| `ci/locomo/data/extraction_gold.json` | 100 条（38 条纯闲聊 + 62 条事实，含 5 条边界） | 提取评测 |
| `ci/locomo/data/README.md` | 字段语义 + 计分约定 + **CC BY-NC 4.0 许可与署名要求** | 合规依据 |
| `scripts/locomo/make_subset.py` | 上游 commit 固定的 fixture 生成器 | 可复现性 |

**合规铁律**：`locomo_subset.json` 派生自 LoCoMo，受 **CC BY-NC 4.0（非商用）** 约束，
不适用本仓库的 Apache-2.0；**不得删除 `data/README.md` 中的署名与许可段落**，
不得把 LoCoMo 完整数据集（2.8 MB / 10 段对话）提交进仓库。

---

## 3. 任务分解

### W4-0（前置，core）R2 修复：闲聊不得中断连续失败计数的清零

**问题**（见 `docs/reports/07-w3.1-verification.md` §5）：W3.1 把计数器清零从 `Ok(fs) =>` 分支
（对所有 `Ok` 生效）移到了闲聊早返回**之后**，导致 `Ok([])`（提取成功但无事实）不再清零。

复现：`失败 → 闲聊 → 失败 → 闲聊 → 失败`，第 3 次 `add` 返回 `ExtractionFailure`，而
文档表述是「**连续** 3 次失败熔断」。

**修复**（`src/store.mbt` 闲聊分支，3 行）：

```moonbit
if facts.length() == 0 {
  // 提取成功但无事实（纯闲聊）同样属于成功，须清零连续失败计数
  self.extraction_failures = 0
  return Ok(AddSummary::{
    extracted: 0, inserted: 0, duplicates: 0, superseded: 0, degraded: false,
    notes: ["extracted 0 facts; nothing stored (chitchat filtered)"],
  })
}
```

**测试**（L1，放在 `src/llm_extractor/` 或既有 store 测试文件）：

- `TC-W40-1`：`Fail → Ok([]) → Fail` 后计数为 1（非 2），且 `add` 未报错；
- `TC-W40-2`：回归断言——`Ok([fact])` 仍清零；`Ok([degraded_fact])` 仍**不**清零（W3.1 语义不回退）。

### W4-A `ci/locomo` 包骨架 + 数据加载

新建 `ci/locomo/`：

- `moon.pkg`：
  ```moonbit
  // L3 offline LoCoMo evaluation harness. Offline path is zero-network, zero-secret.
  import {
    "heyq02/moomem/src",
    "moonbitlang/core/json",
    "moonbitlang/core/env",
    "moonbitlang/x/fs",
  }
  options("is-main": true)
  ```
  live 档位再补 `"heyq02/moomem/src/llm_extractor"`、`"mizchi/llm"`、`"mizchi/llm/openai"`，
  API 嵌入模式再补 `"mizchi/llm/ffi"`。
- `main.mbt` —— 入口与档位分派（见 §4.1）
- `loader.mbt` —— fixture 读取 + JSON 解析为内部结构
- `metrics.mbt` —— 指标累加与 Markdown 表格输出
- `retrieval_eval.mbt` / `conflict_eval.mbt` / `extraction_eval.mbt` / `persistence_eval.mbt`

**加载约定**（务必遵守，否则数据会静默失真）：

- 每个会话用**独立 user_id**（取 `sample_id`，如 `"conv-26"`）→ 天然满足隔离要求；
- 每轮 `add(user_id, turn.text)`；缺省 `extractor: None`（`RawExtractor`），因此
  **1 轮 = 1 条 entry，`entry.content` == 轮次原文**；
- 因此 provenance 只能由 harness 侧维护：`Map[String, Array[String]]`（content → dia_id 列表）。
  同一文本出现多次时 dedup 会合并，命中任一映射到的 dia_id 即算命中——**这是有意的**，
  不要为了「一 一对应」去改写轮次文本；
- `qa[].category == 5`（对抗题）**不计入检索指标**，但要统计条数并在输出中标注已排除；
- 缺失/越界证据的 QA 已在数据生成阶段剔除，加载器**不得**自行补造证据。

### W4-B 检索评测（Recall@5 / MRR@5）+ BM25 单路基线

1. **混合档（hybrid）**：缺省 Config（`HashingEmbedder`）。
2. **单路基线（bm25_only）**：`Config.embedder = Some(NullEmbedder)`，其中
   `NullEmbedder::embed` 恒返回 `Err(MoomemError::EmbeddingFailure("baseline:keyword-only"))`。
   已核实：写入侧 `embedding=[]`、查询侧 `VectorIndex::search` 返回空 → **干净的单路 BM25**。
3. **必须注入空判定器（关键）**：检索评测期间 `Config.judge = Some(NoConflictJudge)`，
   `fn judge(_, _, _) { Ok([]) }`。理由：LoCoMo 对话中存在大量近重复轮次，
   缺省 `SimilarityJudge` 会把旧轮次判为 superseded 并移出召回集，**污染检索指标**。
   这是「只测检索」的必要隔离，需在输出中打印一行说明。
4. 指标：
   - `Recall@5 = 命中题数 / 计分题数`（命中 = top-5 内存在 entry 的 content 映射到该题 `evidence` 中任一 `dia_id`）；
   - `MRR@5 = mean(1 / 首个命中所在名次)`；未命中计 0；
   - 按 `category`（1 multi-hop / 2 temporal / 3 open-domain / 4 single-hop）分组输出；
   - 两种档位各跑一遍，输出对比表与 `delta`（绝对与相对百分比）。
5. **注意 `BackfillRecency` 的影响**：命中不足 top_k 时会用该用户最新条目补齐。
   检索评测统一使用缺省档（补齐开启）以反映真实行为，但**必须在报告中标注该口径**，
   因为补齐条目可能「意外」命中证据（属于放宽而非收紧）。
   建议额外打印 `backfill=false`（`RecallBackfill::NoBackfill`）的对照组数字。

### W4-C 嵌入器双轨（离线 hashing / 真实嵌入 API）

- `--embedder hashing`（默认）：零网络、零密钥、三后端确定性。
- `--embedder api`：环境变量驱动，**仅在显式指定时读取**：
  | 变量 | 必需 | 说明 |
  |---|---|---|
  | `MOOMEM_EMBED_API_KEY` | 是 | 嵌入服务密钥 |
  | `MOOMEM_EMBED_BASE_URL` | 否 | 缺省 `https://api.openai.com/v1` |
  | `MOOMEM_EMBED_MODEL` | 否 | 缺省 `text-embedding-3-small` |
  | `MOOMEM_EMBED_BATCH` | 否 | 缺省 32 |
- 实现要点：
  1. 用 `@llm/ffi.fetch(url, "POST", headers_json, body, 60, on_result, on_error)`；
     body 形如 `{"model": m, "input": ["...","..."]}`；`on_error` 收到 `ERROR:` 前缀串时须转成 Err；
  2. **先探测维度再开库**：用一次探测调用（单条 `"probe"`）取回 `embedding.length()`，
     以此设置 `Config.dim`，再 `MemoryStore::open`——因为 `Config.dim` 与嵌入器维度必须一致
     （`store.mbt:366` 的 `embedding_failed` 判定）；
  3. 解析响应 `data[].embedding`（用 `Json::as_array` / `as_number` 访问器），
     **按 `index` 排序**后再返回，避免批量返回乱序；
  4. 失败即降级为 Err（不要 panic），并让 harness 明确报错退出，不要静默回退到 hashing
     （静默回退会让报告数字含义不明）。
- 该模式**只允许**通过 `moon run ci/locomo --target native -- --embedder api` 运行，
  需真实网络与密钥；**不得**接入 `test-pipeline`（保持 L0/L1 零密钥铁律）。

### W4-D 冲突评测（supersede 正确率）

数据：`ci/locomo/data/conflict_pairs.json`。

- **计分组 `near_duplicate`（20 组，进离线门禁）**：
  对每组用独立 user：`add(old)` → `add(new)` → 读 `list_entries` 断言
  `old.status == Superseded` 且 `new.is_recallable()`。满足记 1 分。
  口径与 `ci/tuning/main.mbt:evaluate_supersede` 一致，可直接复用其写法。
- **记录组 `semantic`（10 组，离线只记录不计分）**：
  同样跑一遍，但**期望值为 `ignore`**；逐组输出实测值：
  `cos`（`cosine_similarity`）、`jac`（`keyword_jaccard`）、最终 `status`。
  这组不计分的原因是实测边界（缺省判据只覆盖近重复式更新，见 README 已知限制第 4 条），
  **不得**为了让它通过而改语料或调阈值。
- 另需输出**全局阈值余量**：近重复组中最小相似度与 `0.82` 的差值。
  若任一组落在 `0.82 ± 0.03`，照实打印告警行（`MARGIN_WARN`），**不改语料**。

### W4-E 提取质量评测（live-only）

数据：`ci/locomo/data/extraction_gold.json`。

- **离线档：显式 SKIP**。理由：缺省 `RawExtractor` 会把原文整条入库，Precision 无意义；
  必须打印 `extraction precision: SKIPPED (requires --live; RawExtractor stores raw text)`，
  **不得**打印 `PASS` 或任何数字。
- **live 档（`--live`）**：复用 `ci/llm_live` 的接线与密钥（`DEEPSEEK_API_KEY` /
  `DEEPSEEK_BASE_URL` / `DEEPSEEK_MODEL`，**仅在 `--live` 时读取**），
  `Config.extractor = Some(LlmExtractor::new(p))`，每条用例独立 user：
  `summary = store.add(user, text)` → 读条目 content 集合。
- 计分（见数据文件 `meta.scoring`）：
  - 分母 = 实际入库事实条数；分子 = 命中 `must_extract` 的事实条数；
  - `must_not_extract` 命中或「`must_extract` 为空的用例仍入库」→ 记假阳性并逐条列出（最多 20 条）；
  - 输出 `Precision = 分子 / 分母`，以及逐条明细表。
- 门禁：`Precision >= 0.8`（PRD 目标）。低于目标**如实打印 `MISSED` 并列出假阳性条目**，
  不要调整分母口径——真阳性/假阳性的判定规则以数据文件为准。

### W4-F 持久化与隔离聚合检查

- **隔离（目标 0 渗透）**：两段对话 + gold 集用户两两交叉查询若干条，统计跨 user 命中数，
  期望 `0`。
- **持久化（目标 100%）**：`/tmp` 下建临时目录 → `MemoryStore::open(dir)` → 写入一组事实
  → `close()` → 重新 `open(dir)` → 比较两次 `recall` 返回的 id 集合是否一致；结束后用
  `@fs.remove_file`/`remove_dir` 清理（照抄 `src/persist_test.mbt:99-112`）。
  输出 `1/1` 或 `0/1`。
- 说明：崩溃注入的完整矩阵已由 L0 测试覆盖（`#cfg(native)`），本项只做端到端聚合复验，
  不重复实现注入逻辑。

### W4-G CI 接线 + 文档同步

1. `.github/workflows/test-pipeline.yml`：
   - 更新 `NATIVE_TEST_BASELINE`：`"97"` → **实际新计数**（当前 112 + W4 新增测试数）；
   - 新增 job（在 `test` 之后，`needs: test`）：
     ```yaml
     eval-locomo:
       name: L3 Eval (offline, native)
       needs: test
       runs-on: ubuntu-latest
       timeout-minutes: 10
       steps:
         - uses: actions/checkout@v4
         - uses: ./.github/actions/setup-moonbit
           with:
             version: ${{ env.MOON_VERSION }}
         - name: moon run ci/locomo (offline)
           run: moon run ci/locomo --target native
     ```
     零密钥、零网络（`ci/locomo` 离线档不得触碰任何 `*_API_KEY`）。
2. README：新增「评测」小节，说明 L3 的跑法与当前数字（数字以 harness 输出为准，不要预填）。
3. `docs/reports/04-progress-and-roadmap.md`：W4 状态行改为完成，附 harness 实际输出数字。
4. `docs/reports/05-test-suite.md`：把 L3 从「待建」改为「已实现」，补入口命令与用例 ID 表。

---

## 4. 关键实现约定

### 4.1 命令行与档位

```
moon run ci/locomo --target native [-- --fixture <path>] [--embedder hashing|api]
                                              [--live] [--limit <n>]
```

- 用 `@env.args()` 取参数（忽略程序名与未知参数；`--help` 打印用法后正常退出）；
- 缺省跑**离线全量**：检索（双档）+ 冲突 + 持久化/隔离 + 提取 SKIP。

### 4.2 fixture 路径解析（顺序）

1. `--fixture <path>`
2. `MOOMEM_LOCOMO_FIXTURE` 环境变量
3. 缺省 `ci/locomo/data/locomo_subset.json`（相对 `@env.current_dir()`）

读取失败时打印 `LOCOMO_FAIL: cannot read <abs path> (cwd=<current_dir>)` 后 abort——
**必须回显 cwd 与实际路径**，避免 CI 里排查路径问题耗时。

### 4.3 JSON 解析（只用访问器）

```moonbit
let root = @json.parse(text) catch { _ => fail("fixture is not valid JSON") }
let convs = root.value("conversations").bind(Json::as_array) ...
```

数值统一经 `as_number()` 取 `Double` 再 `.to_int()`；缺字段一律走 `Option` 分支，
不要用 `unwrap()`（fixture 由人维护，字段缺失应报错而非 panic）。

### 4.4 输出格式

- 全流程用 `println` 打印 Markdown 片段（表头 + 分隔行 + 数据行），便于直接粘进报告；
- 关键结果用固定前缀，便于 CI 与 grep：
  `LOCOMO_PASS` / `LOCOMO_FAIL` / `MARGIN_WARN` / `TARGET_15PCT: met|missed`；
- 失败一律走 `abort`（非零退出），**不要**只在日志里打印错误后正常退出。

---

## 5. 红线（违反即返工）

1. **核心包 `src/` 零 `mizchi/llm` 依赖**——W4-0 之外不得改动 `src/` 的任何行为；
   `grep -rn "mizchi/llm" src/*.mbt` 必须为空。
2. **不新增 `moon.mod` 依赖**：`moonbitlang/x`、`mizchi/llm` 已在依赖表中；
   不得引入新模块（含 Python/Node 运行时依赖——`scripts/locomo/make_subset.py` 是离线一次性工具，不进 CI）。
3. **不得改动 `ci/tuning`**：`moon run ci/tuning --target native` 必须仍输出 `TUNING_PASS`。
4. **不得修改 `ci/locomo/data/` 下任何数据文件**（含 `README.md` 的许可段落）。
   若发现语料问题，在报告中记录，不要就地改写。
5. **不得为通过门禁而调参**：`supersede_threshold` / `rrf_k` / 语料均保持缺省与原文。
   缺省档位跑不过门禁时，如实失败并输出数字。
6. **不得断言离线 15%**：离线档位只做非回归断言（§6 第 3 条）；
   `TARGET_15PCT` 仅在 `--embedder api` 档位输出。
7. **警告必须保持为 0**：`moon check --target all` 无输出警告（W2/W3 已清零，不得回退）。
8. **现有测试计数只增不减**：native / wasm 系计数不得低于当前 112 / 99。
9. **离线档位不得读取任何密钥环境变量**（`grep` 校验见 §6）。

---

## 6. 验收（DoD）

```bash
cd <repo root>

# 1. 静态检查：0 error / 0 warning（四目标）
touch src/lib.mbt && moon check --target all

# 2. 测试计数不得回退：native ≥112+新增；wasm/wasm-gc/js ≥99+新增
moon test --target native
for t in wasm wasm-gc js; do moon test --target $t; done

# 3. L3 离线 harness：通过且打印 LOCOMO_PASS
moon run ci/locomo --target native

# 4. 既有门禁不回归
moon run ci/tuning --target native        # 期望 TUNING_PASS
moon run examples --target native

# 5. 红线
grep -rn "mizchi/llm" src/*.mbt                     # 必须为空
grep -c "MOOMEM_LLM_API_KEY" ci/locomo/*.mbt        # 仅出现在 --live 分支上下文
grep -rn "DEEPSEEK_" ci/locomo/*.mbt | wc -l        # 仅 live 档位，且不在离线路径上

# 6. CLI 冒烟（既有能力不回退）
moon run src/cli --target native -- help            # 版本 0.2.2
```

**离线门禁断言（harness 内部，全部满足才 `LOCOMO_PASS`）**

| # | 断言 | 阈值来源 |
|---|---|---|
| 1 | 跨 user 渗透数 == 0 | PRD §16.1 隔离目标 |
| 2 | 持久化 reopen 一致性 == 100% | PRD §16.1 持久化目标 |
| 3 | 混合档 `Recall@5` **≥** 单路基线 `Recall@5` | 非回归（**不是** 15%，见红线 6） |
| 4 | 近重复组 supersede 正确率 ≥ 80% | PRD §16.1 冲突目标 |
| 5 | 无 panic / 无未捕获异常 / 无 SKIP 冒充通过 | 本规格 |

**报告必含数字（供产品侧撰写 08 报告）**：两种档位的 Recall@5 / MRR@5（总量 + 分 category）、
`backfill` 对照组、近重复组正确率与最小余量、语义组逐条 cos/jac、提取 Precision（live）、
持久化与隔离计数。

---

## 7. 提交规范

按任务拆分提交，每个提交可独立通过 `moon check`：

| 提交 | 内容 | 建议 message |
|---|---|---|
| 1 | W4-0 | `fix(core): keep chitchat extraction from breaking the failure streak (W4-0)` |
| 2 | W4-A + W4-B | `feat(eval): add offline LoCoMo retrieval harness with BM25-only baseline (W4-A/B)` |
| 3 | W4-C | `feat(eval): add opt-in real-embedding mode via /embeddings API (W4-C)` |
| 4 | W4-D + W4-F | `feat(eval): add conflict supersede and persistence/isolation evals (W4-D/F)` |
| 5 | W4-E | `feat(eval): add live extraction-precision eval over the 100-case gold set (W4-E)` |
| 6 | W4-G | `ci(eval): run L3 offline eval in test-pipeline and sync docs (W4-G)` |

- 一个提交一件事，不混入无关文件（尤其不要动 `.cursor/`、`release-pipeline.yml`）；
- **不要自行打 tag、不要 `moon publish`**——发版由产品侧决定；
- 完成后回报：各提交 SHA、`moon run ci/locomo --target native` 的**完整输出**、
  四后端测试计数、两条 grep 红线的结果。

---

## 8. 交付后由产品侧完成

1. 依据 harness 实际输出撰写 `docs/reports/08-w4-eval-report.md`（含指标对照 PRD §16.1 目标值、未达标项如实说明）；
2. FlowUs 云端镜像同步（PARA 结构：项目页挂评测报告）；
3. v0.2.2 发版决策与 tag（含 `DEEPSEEK_MODEL` 变量核对——旧别名 `deepseek-chat` 已于 2026-07-24 退役）；
4. 赛事申报材料中的指标引用核对。

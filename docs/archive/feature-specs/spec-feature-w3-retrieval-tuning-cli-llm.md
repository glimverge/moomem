---
title: W3 Engineering Specification - Retrieval Tuning & CLI LLM Wiring
version: 1.0
date_created: 2026-10-01
last_updated: 2026-10-01
owner: glimverge
tags: [feature, w3, retrieval, config, cli, llm, tuning, hackathon]
executor: Cursor (AI coding agent) - execute tasks in order W3-A → W3-D → W3-B → W3-C
language: MoonBit (moon toolchain, module heyq02/moomem, version 0.2.2)
---

> **历史路径注**：文中 `ci/tuning` / `ci/llm_live` / `moon run examples` 为 W3 当日路径；现行入口见 [`docs/project/10-testing-examples-architecture.md`](../../project/10-testing-examples-architecture.md)（`ci/tools/retrieval-tuning`、`ci/gates/live-llm`、`examples/<scene>`）。

# W3 工程任务规格书：混合检索调优 + CLI 接线 LLM

> 本文档是 W3 里程碑的**唯一执行依据**，面向 AI 编码代理（Cursor）。
> 阅读顺序：先通读 §8 红线，再按 §2 任务顺序执行；每个任务完成后跑 §7 验收命令再进入下一个。

## 0. 背景（为什么做 W3）

moomem v0.2.1 已完成 W1（纯工程闭环）与 W2（LLM 提取适配器）。W3 的目标来自《进度与规划》P2 条目：

1. **检索/冲突参数目前是硬编码常量**，无法在不改源码的情况下调优：
   - `CONFLICT_CANDIDATES = 8`（src/types.mbt:250，add 链路每路冲突候选窗口）
   - `COEXIST_BAND = 0.15`（src/types.mbt:254，SimilarityJudge 的 Coexist 下界间距）
   - recall 命中不足时的「补齐到 top_k」策略硬编码为"按插入序倒序补最新"（src/store.mbt:490-514），无法关闭
2. **CLI 尚无 LLM 能力**：`moomem add` 只走 RawExtractor（原文 unstructured 直通），W2 的 LlmExtractor 无法从 CLI 使用。
3. **版本常量失同步**：`src/lib.mbt` 中 `MOOMEM_VERSION = "0.1.0"`，而 `moon.mod` 已是 `0.2.2`——CLI `help` 打印的版本号是错的。

W3 **不做**的事（边界）：LoCoMo 评测（W4）、moon.mod.json→moon.mod 迁移（独立工程债）、发版与版本号 bump（release-pipeline 专属职责）。

## 1. 现状代码事实（已核实，执行前无需重新调研）

| 事实 | 位置 | 说明 |
|------|------|------|
| Config 结构 | `src/types.mbt:189-224` | 现有字段：embedder/extractor/judge/persistence/clock（5 个注入点 Option）+ dim/rrf_k/recall_candidates/supersede_threshold；`Config::default()` 逐一赋缺省 |
| open() 配置校验 | `src/store.mbt:67-85` | dim>0、rrf_k>0、recall_candidates>=0、supersede_threshold∈(0,1] |
| 冲突候选窗口使用点 | `src/store.mbt:311-324` | add 链路直接引用常量 `CONFLICT_CANDIDATES`，向量+关键词各取一路 |
| SimilarityJudge | `src/conflict.mbt:52-90` | `new(threshold, embedder)`；分档逻辑 Replace（>=threshold）/ Coexist（>=threshold-COEXIST_BAND）/ Ignore |
| recall 补齐逻辑 | `src/store.mbt:490-514` | 仅当 0 < 命中数 < top_k 时，按 by_user 插入序倒序补最新可检索条目 |
| CLI 选项解析 | `src/cli/main.mbt:16-104` | `parse_options` 递归下降；布尔开关 `--all` 前置处理模式（这是 W1 修过的 bug A，新增布尔开关必须复用该模式）；`CliOptions` struct + `default_options()` |
| CLI 包依赖 | `src/cli/moon.pkg` | import heyq02/moomem/src、core/env、core/string、x/fs；`is-main: true` |
| env API | core/env | `@env.get_env_var(String) -> String?`（CLI 已 import 该包） |
| LLM 接线完整先例 | `ci/llm_live/main.mbt:163-195` | `@openai.OpenAIProvider::new(api_key, endpoint=Custom(base_url~), model~)` → `&@llm.Provider` → `LlmExtractor::new(p)` / `LlmConflictJudge::new(p)` → 注入 Config；含 `normalize_base_url`（去尾部 `/` 与 `/v1`）实现可参考 |
| mizchi/llm/openai API | `.mooncakes/mizchi/llm/src/openai/openai.mbt` | `OpenAIProvider::new(api_key, endpoint?=OpenAI, model?="gpt-4o", max_tokens?, system_prompt?, base_url?, timeout_sec?=300, max_retries?=3)`；`OpenAIEndpoint` 枚举含 `OpenAI/OpenRouter/Ollama/Cloudflare/Custom` |
| 测试现状 | 全仓 | native 97 用例、wasm/wasm-gc/js 各 90；`moon check` 0 errors 0 warnings（**警告必须保持为 0**） |
| 四后端门控先例 | `src/qa_adversarial_test.mbt` 等 | native 专属测试用 `#cfg(target="native")`；CI wasm 目标不编译运行这些用例 |

## 2. 任务总览与执行顺序

| 任务 | 内容 | 新文件 | 改动文件 |
|------|------|--------|----------|
| W3-A | 检索/冲突参数 Config 化（backfill / conflict_candidates / coexist_band） | — | src/types.mbt、src/store.mbt、src/conflict.mbt |
| W3-D | 版本常量同步 | — | src/lib.mbt |
| W3-B | 离线调参评测台 ci/tuning | ci/tuning/moon.pkg、ci/tuning/main.mbt | — |
| W3-C | CLI 接线 LLM 提取 | src/cli/llm_wiring.mbt（native）、src/cli/llm_wiring_stub.mbt（其余目标） | src/cli/main.mbt、src/cli/moon.pkg、src/cli/cli_wbtest.mbt |

执行顺序理由：W3-A 是 W3-B 的依赖（调参台要扫 Config 字段）；W3-D 独立且 5 分钟可完成；W3-C 依赖 W3-A 完成后的稳定 Config。每完成一个任务：跑 §7 验收 → 按规范 commit → 下一个。

## 3. W3-A：检索/冲突参数 Config 化

### 3.1 类型层（src/types.mbt）

新增枚举（放在 Config 定义之前），遵循仓库现有手写 Show 惯例（参照 `ConflictDecision` 的写法，见 src/conflict.mbt:7-27）：

```moonbit
///|
/// recall 命中数不足 top_k 时的补齐策略。
pub(all) enum RecallBackfill {
  /// 不补齐：命中多少返回多少（零命中行为不受影响，恒为空列表）
  NoBackfill
  /// 按插入序倒序补最新可检索条目（v0.2.1 现行为，缺省）
  BackfillRecency
}
```

`Config` struct 新增三个字段（加注释说明缺省值与合法域）：

```moonbit
  /// add 链路冲突检测每路候选窗口，缺省 8
  conflict_candidates : Int
  /// SimilarityJudge 的 Coexist 下界间距，缺省 0.15
  coexist_band : Double
  /// recall 补齐策略，缺省 BackfillRecency
  backfill : RecallBackfill
```

`Config::default()` 对应补：`conflict_candidates: CONFLICT_CANDIDATES`、`coexist_band: COEXIST_BAND`、`backfill: BackfillRecency`。**保留既有四个常量**（DEFAULT_DIM 等），不要删除。

### 3.2 打开校验（src/store.mbt open()）

在现有校验块（行 67-85 区域）追加：

- `cfg.conflict_candidates >= 1`，否则 `Err(MoomemError::InvalidOperation("config.conflict_candidates must be >= 1"))`
- `cfg.coexist_band >= 0.0 && cfg.coexist_band < 1.0`，错误信息 `"config.coexist_band must be in [0, 1)"`

### 3.3 MemoryStore 字段与使用点（src/store.mbt）

1. `MemoryStore` struct 新增字段：`conflict_candidates : Int`、`coexist_band : Double`、`backfill : RecallBackfill`（参照现有 `supersede_threshold` 字段的注释风格）。`open()` 构造处从 cfg 传入。
2. add 链路（行 311-324）：把两处 `CONFLICT_CANDIDATES` 常量引用替换为 `self.conflict_candidates`。
3. recall 补齐块（行 490-514）：整体包一层 `match self.backfill { BackfillRecency => <现有逻辑原样保留> ; NoBackfill => () }`。**不改变 BackfillRecency 分支的任何行为**（现有测试依赖"已有命中时按最新补齐"语义）。
4. judge 构造（行 132-136）：`SimilarityJudge::new(cfg.supersede_threshold, embedder)` 改为传入 band：`SimilarityJudge::new(cfg.supersede_threshold, embedder, coexist_band=cfg.coexist_band)`。

### 3.4 SimilarityJudge（src/conflict.mbt）

构造函数追加可选参数（**非破坏式**，缺省保持现值）：

```moonbit
pub fn SimilarityJudge::new(
  threshold : Double,
  embedder : &Embedder,
  coexist_band? : Double = COEXIST_BAND,
) -> SimilarityJudge
```

struct 增加 `coexist_band : Double` 字段；`judge` 实现中 `self.threshold - COEXIST_BAND` 改为 `self.threshold - self.coexist_band`。其余分档逻辑不变。

### 3.5 测试（新增用例进现有测试文件，或新建 src/w3_config_test.mbt）

至少覆盖（全部零网络、四后端可跑）：

- TC-A1 缺省 Config 打开 store → add/recall 行为与 v0.2.1 一致（等价回归，可复用现有用例断言思路）
- TC-A2 `conflict_candidates=1` 时，冲突候选每路至多 1 个（构造 2 条高相似旧条目后 add 新事实，验证只裁决 1 个）
- TC-A3 `conflict_candidates=0` 与 `coexist_band=1.0` → open 返回 InvalidOperation
- TC-A4 `backfill=NoBackfill`：构造 5 条条目 + 查询仅命中 2 条的 top_k=5 recall，断言返回 2 条；`backfill=BackfillRecency` 时返回 5 条且后 3 条为最新插入
- TC-A5 `coexist_band=0.30`：相似度落在 [threshold-0.30, threshold-0.15) 的候选判 Coexist（可用注入 mock Embedder 精确控制向量，参照 src/llm_extractor 测试的 mock 手法）
- TC-A6 `SimilarityJudge::new` 不传 coexist_band 时行为与旧签名完全一致（band=0.15）

**约束**：现有 97/90 用例一个不许改坏。Config 新增字段有缺省，理论上现有用例无需修改即通过；若确有编译错误（如测试直接字面构造 Config），最小化修补并把原因写进 commit message。

## 4. W3-D：版本常量同步

`src/lib.mbt:15`：`MOOMEM_VERSION` 从 `"0.1.0"` 改为 `"0.2.2"`（与 moon.mod 一致）。

并在该常量注释处追加一行：`// 注意：moon.mod 版本由 release-pipeline 管理；本常量需在每次发版后手工同步`。

在 `src/cli/cli_wbtest.mbt`（或该文件所属的测试处）补一个用例：CLI usage 输出的版本号与 `MOOMEM_VERSION` 一致（若现有测试结构不便断言 stdout，可退化为断言常量不以 "0.1" 开头——优先选择前者）。

## 5. W3-B：离线调参评测台 ci/tuning

### 5.1 目标与形态

参照 `ci/llm_live/` 的先例新建 **native-only、零网络、零密钥** 的 main 包：`ci/tuning/`。它做三件事：

1. 在固定语料上以**缺省参数**跑完整 add/recall/冲突流程，断言全部预期（回归门禁，失败 exit 非 0）
2. 对参数网格做扫描（rrf_k × conflict_candidates × supersede_threshold × coexist_band），输出 Markdown 指标表
3. 打印"最优组合"建议（不落盘、不改缺省值）

### 5.2 文件与包配置

```
ci/tuning/moon.pkg:
  // Offline retrieval/conflit tuning harness. Zero network, zero secrets.
  import {
    "heyq02/moomem/src",
  }
  options(
    "is-main": true,
  )

ci/tuning/main.mbt:   // 单文件实现，风格参照 ci/llm_live/main.mbt
```

### 5.3 固定语料（写死在 main.mbt，中英混合）

至少包含（每条 (user_id, text) 或提取后直接 add 的事实语义）：

- **2 个用户**（跨用户隔离检查）
- 每用户 **12+ 条事实**：住址、过敏、饮食偏好、作息、宠物、工号、事件等（可直接用 `store.add(user, text)`——默认 RawExtractor 直通入库，正好考察检索与冲突层）
- **3 组冲突对**：如 ("我住在北京市海淀区", "我搬家了，现在住在深圳南山区")——第二句 add 后应 supersede 第一句
- **12 条查询**，每条带标注的 expected_top1 内容关键词（如 query="花生过敏" → 期望首条命中含"花生"）

### 5.4 指标

对每个参数组合输出：

- `recall@5_hit`：12 条查询中期望首条出现在 top-5 的比例
- `mrr@5`：期望首条排名倒数的均值
- `supersede_ok`：3 组冲突对中正确 supersede 的比例
- `cross_leak`：跨用户命中数（必须恒为 0，否则直接 fail）

### 5.5 扫描网格与门禁

```
rrf_k:               [10, 20, 40, 60, 100]
conflict_candidates: [4, 8, 16]
supersede_threshold: [0.75, 0.82, 0.90]
coexist_band:        [0.10, 0.15, 0.20]
```

实现方式：三层嵌套循环构造 Config（persistence 用 `@src.MemoryBackend::new()` 注入，参照 ci/llm_live 的做法）→ 逐组合重放全语料 → 收集指标。总组合 5×3×3×3=135 次，每次几十条 add/recall，native 秒级完成。

**门禁**：缺省参数组（60, 8, 0.82, 0.15）必须满足 `recall@5_hit = 12/12` 且 `supersede_ok = 3/3` 且 `cross_leak = 0`，否则 `println("TUNING_FAIL: ...")` 并 `abort`。**语料的期望标注必须以缺省参数能全过为准来编写**——若你发现缺省参数无法满足某期望，说明预期标注有误或发现了真实缺陷，停下来在最终报告中说明，**不得**通过改缺省参数或放宽断言来让门禁变绿。

输出示例：

```
=== moomem offline tuning harness ===
default gate: recall@5=12/12 mrr@5=1.000 supersede=3/3 cross_leak=0  [PASS]

| rrf_k | cc | thr | band | recall@5 | mrr@5 | supersede |
|------:|---:|----:|-----:|---------:|------:|----------:|
|    60 |   8 | 0.82 | 0.15 | 12/12 | 1.000 | 3/3 |
|   ... | ... | ... | ... | ... | ... | ... |

best combo: rrf_k=40 cc=8 thr=0.82 band=0.15 (ties broken by mrr@5)
TUNING_PASS
```

### 5.6 README 更新

在 `README.md` 的测试/运行说明合适位置追加一行运行方式：`moon run ci/tuning --target native`（零网络离线调参台）。

## 6. W3-C：CLI 接线 LLM 提取（独立评审结论已并入本节）

### 6.1 评审结论（预先锁定的设计决策，不要偏航）

| # | 决策 | 理由 |
|---|------|------|
| D1 | CLI 默认**零网络零密钥**，LLM 仅在显式传 `--llm` 时启用 | 既有 CLI 用户体验与测试铁律不破坏 |
| D2 | API key **只从环境变量读**，不提供 `--api-key` 明文参数 | 进程列表/shell history 泄密风险；与 ci/llm_live 的 env 约定一致 |
| D3 | 端点协议固定 **OpenAI 兼容**（mizchi/llm/openai），不做多协议 | OpenAI/OpenRouter/Ollama/vLLM/DeepSeek 全覆盖该协议，够用 |
| D4 | 提取失败走 **ReturnRaw** 降级（原文 unstructured 入库），不提供 PropagateError 开关 | CLI 面向交互场景，崩进程比降级更糟；AddSummary.notes 已可见降级原因 |
| D5 | LLM 冲突判定 `--llm-judge` 可选，默认关（保留 SimilarityJudge） | 单 add 至多 2 次提取调用 + 至多 2 次 judge 调用的预算可控 |
| D6 | LLM 接线代码 **native 目标专属**（moon.pkg targets 文件级门控） | ffi 层 native 用 C stub；非 native 目标不保证运行语义，四后端测试必须保持全绿 |
| D7 | `--llm` 只作用于 `add` 子命令 | recall/list/stats/export/import 与 LLM 无关 |

### 6.2 环境变量契约

| 变量 | 必需性 | 说明 |
|------|--------|------|
| `MOOMEM_LLM_API_KEY` | `--llm` 时必需（本地端点除外，见下） | 密钥 |
| `MOOMEM_LLM_BASE_URL` | 可选 | OpenAI 兼容 base_url（如 DeepSeek `https://api.deepseek.com`、Ollama `http://localhost:11434`）；缺省官方 OpenAI 端点。复用 `normalize_base_url` 的去尾斜杠/`/v1` 逻辑（从 ci/llm_live/main.mbt:22-34 复制该函数到 cli，勿跨包 import ci 代码） |
| `MOOMEM_LLM_MODEL` | 可选 | 模型 id，缺省 `gpt-4o-mini` |

本地端点例外：base_url 为 localhost/127.0.0.1 时允许无 key（对应 Ollama 场景，`OpenAIProvider::new_compat` 已支持空 key 走 Ollama 分支或 Custom）。非本地且无 key → `die("moomem: --llm requires MOOMEM_LLM_API_KEY (or a localhost MOOMEM_LLM_BASE_URL)")`。

### 6.3 新增 CLI 参数

`CliOptions` 新增：`llm : Bool`、`llm_judge : Bool`、`model : String`、`base_url : String`（缺省值在 `default_options()` 中给：`llm=false, llm_judge=false, model="", base_url=""`，空串表示"未指定，走 env/缺省"）。

`parse_options` 新增分支（注意 `--llm` 与 `--llm-judge` 是布尔开关，**必须复用 `--all` 的前置处理模式**，这是 W1 修过的 bug A 回归点；`--model`/`--base-url` 是值参数，走 `--db` 的模式）。usage 文本同步更新，含示例：

```
  moomem add --db <dir> --user <id> --text <content> [--llm] [--llm-judge] [--model <id>] [--base-url <url>]

  --llm           enable LLM fact extraction (needs MOOMEM_LLM_API_KEY unless localhost)
  --llm-judge     also use LLM conflict judging (implies --llm)
  --model <id>    LLM model id (env: MOOMEM_LLM_MODEL, default gpt-4o-mini)
  --base-url <u>  OpenAI-compatible endpoint (env: MOOMEM_LLM_BASE_URL)
```

### 6.4 接线实现（新文件 + moon.pkg 门控）

**src/cli/llm_wiring.mbt**（仅 native）：

```moonbit
// 构造带 LLM 注入的 Config；失败返回可读错误信息（die 用）。
// native 专属：ffi 层（native_stub.c）仅在此目标保证语义。
fn build_llm_config(opts : CliOptions) -> Result[Config, String] {
  // 1) 解析 base_url（CLI 参数 > 环境变量 > 缺省官方端点），normalize 复制自 ci/llm_live
  // 2) 本地端点(localhost/127.0.0.1)免 key；否则读 MOOMEM_LLM_API_KEY，缺失即 Err
  // 3) model：CLI 参数 > MOOMEM_LLM_MODEL > "gpt-4o-mini"
  // 4) let provider = @openai.OpenAIProvider::new(key, endpoint=..., model=~)
  //    —— 有 base_url 时用 Custom(base_url~)，与 ci/llm_live/main.mbt:170-176 同构
  // 5) let p : &@llm.Provider = provider
  //    extractor = @llm_extractor.LlmExtractor::new(p)   // ReturnRaw 缺省
  //    judge = opts.llm_judge 时 Some(@llm_extractor.LlmConflictJudge::new(p) as &ConflictJudge)
  // 6) 返回 Config::{ extractor: Some(...), judge: ..., 其余走缺省（..Config::default() 展开补全）}
}
```

**src/cli/llm_wiring_stub.mbt**（wasm/wasm-gc/js）：同签名函数，直接 `Err("llm wiring requires native target")`。

**src/cli/moon.pkg**：

```
import {
  "heyq02/moomem/src",
  "heyq02/moomem/src/llm_extractor",
  "mizchi/llm",
  "mizchi/llm/openai",
  "moonbitlang/core/env",
  "moonbitlang/core/string",
  "moonbitlang/x/fs",
}
options(
  "is-main": true,
  targets: {
    "llm_wiring.mbt": [ "native" ],
    "llm_wiring_stub.mbt": [ "wasm", "wasm-gc", "js" ],
  },
)
```

（注意：mizchi/llm 子包已在模块依赖里，**不需要改 moon.mod 的 import**。）

**src/cli/main.mbt** 的 `add` 分支：打开 store 前判断——

```moonbit
if opts.llm || opts.llm_judge {
  match build_llm_config(opts) {
    Err(msg) => die(msg)
    Ok(cfg) => /* MemoryStore::open(opts.db, config=Some(cfg)) */
  }
} else {
  /* 原有 MemoryStore::open(opts.db) */
}
```

`--llm-judge` 单独出现时视为 `--llm`（judge 无 extractor 无意义）。

### 6.5 W3-C 测试（L0/L1，零网络零密钥）

- TC-C1 `parse_options`：`--llm` 末尾位置可解析（bug A 模式回归）；`--llm-judge` 同理；`--model x --base-url y` 值参数；未知参数仍报错
- TC-C2（native only）：`@env.set_env_var("MOOMEM_LLM_API_KEY", "test-key")` + `MOOMEM_LLM_BASE_URL` 本地端点 → `build_llm_config` 返回 Ok，且 Config 的 extractor 注入成功（open 一个 MemoryBackend store 并 `store.add` 走 RawExtractor… 不对——注入的是 LlmExtractor；断言 `stats().extractor_mode == "llm"` 即可，**不发起任何真实网络调用**——构造 provider 不联网，add 才联网，测试里不调 add 或用 mock provider 构造）
- TC-C3（native only）：无 key + 非本地端点 → `build_llm_config` 返回 Err 且消息含 `MOOMEM_LLM_API_KEY`
- TC-C4（wasm 目标编译性）：stub 版本函数存在且返回 Err——通过 wasm 目标 `moon test` 全绿来保证（CI 已覆盖）

TC-C2 若担心 mock 依赖，可仿照 `examples/llm_extractor_demo.mbt` 的 DemoProvider 手法构造脚本化 provider 注入 `build_llm_config` 的可测变体（把 provider 构造抽成小函数便于 mock）。

## 7. 验收（Definition of Done）

每个任务完成即跑；全部任务完成后再整体跑一遍并汇总：

```bash
MOON=~/.moon/bin/moon   # 绝对路径调用，不要依赖 PATH

$MOON check                                          # 0 errors, 0 warnings
$MOON test --target native                           # ≥ 97（原 97 + 新增 TC-A*/D*/C*，只增不减）
$MOON test --target wasm                             # ≥ 90（非 native 用例只增不减）
$MOON test --target wasm-gc                          # ≥ 90
$MOON test --target js                               # ≥ 90
$MOON run ci/tuning --target native                  # 输出 TUNING_PASS
$MOON run examples --target native                   # 原有示例仍可跑
```

附加检查：

- `grep -rn "mizchi/llm" src/*.mbt` 必须为空（核心包零依赖铁律，src/cli 与 src/llm_extractor 不在此列）
- `grep -rn "CONFLICT_CANDIDATES" src/store.mbt` 必须为空（已 Config 化）
- CLI 手工冒烟（允许零网络失败路径验证）：
  - `moon run src/cli --target native -- help`（版本显示 0.2.2）
  - `moon run src/cli --target native -- add --db /tmp/mm-smoke --user t1 --text "我对花生过敏"`（成功，raw 模式）
  - 同命令加 `--llm`：无 key 环境下报 `MOOMEM_LLM_API_KEY` 错误（错误路径正确性）

## 8. 红线（违反任何一条 = 返工）

1. **核心包零依赖**：`src/` 根下的 .mbt 文件（非子包）不得 import mizchi/llm 任何子包。W3-C 的 import 只允许出现在 `src/cli/`。
2. **不新增模块依赖**：不得修改 moon.mod 的 import 块（mizchi/llm 0.3.2 与 moonbitlang/x 0.5.5 已覆盖全部需求）。
3. **零网络零密钥测试**：所有新增测试不得发起网络调用、不得读取真实密钥。`ci/tuning` 同理。
4. **警告清零保持**：`moon check` 不得出现任何 warning（v0.2.1 花了 299→0 的代价换来的）。
5. **不改存量行为语义**：缺省 Config 下 add/recall/forget 的行为与 v0.2.1 字节级等价（除 W3-D 版本号字符串）。
6. **不碰发版**：不改 moon.mod 的 version 字段；不创建 git tag；不跑 mooncakes 发布；不修改 `.github/workflows/`（工作区有未提交的 release-pipeline.yml 改动，那是主理人手上的活，绕开它）。
7. **不删不改现有测试的断言语义**（允许为编译通过做最小修补，需在 commit message 说明）。
8. **禁止 panic / abort 于库代码路径**：一切可失败操作返回 Result（ci/tuning 的门禁 abort 除外，它是 main）。

## 9. 提交规范与交付物

- 每个任务一个 commit，conventional commits 风格：
  - `feat(config): make conflict window, coexist band and recall backfill configurable (W3-A)`
  - `fix(cli): sync MOOMEM_VERSION with moon.mod (W3-D)`
  - `feat(ci): add offline tuning harness ci/tuning (W3-B)`
  - `feat(cli): wire LLM extraction behind --llm flag (W3-C)`
- README.md 更新（W3-C 的 usage 部分与 W3-B 的运行说明）可并入对应任务 commit。
- **commit 但不 push**（主理人验收后统一推送）。
- 最终在任务完成后输出一份**执行报告**（直接输出文本即可，不落盘）：每任务的变更文件清单、测试计数变化（如 97→112）、`ci/tuning` 的最优参数组合结论、遇到的偏离与原因。

## 10. 参考文档

- 架构设计：`docs/project/architecture.md`（注入点与状态机）
- PRD v1.1：`docs/project/03-prd.md`（FR/AC 编号）
- 测试体系：`docs/project/05-test-suite.md`（L0-L3 分层与门禁）
- 进度与规划：`docs/project/04-progress-and-roadmap.md` §三（本 W3 范围的出处）

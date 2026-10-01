---
title: W3.1 Patch Specification - Extraction Degrade Observability & CLI Hardening
version: 1.0
date_created: 2026-10-01
last_updated: 2026-10-01
owner: glimverge
tags: [patch, w3.1, observability, degrade, cli, hardening, qa-followup]
executor: Cursor (AI coding agent)
depends_on: docs/project/06-w3-qa-verification.md (发现 F1/F2/F3)
---

> **历史路径注**：文中 `ci/tuning` 等为补丁当日路径；现行入口见 [`docs/project/10-testing-examples-architecture.md`](../../project/10-testing-examples-architecture.md)。

# W3.1 补丁规格书：提取降级可观测性 + CLI 加固

> 起因：W3 独立验证发现三项问题（详见 [06-w3-qa-verification.md](../../project/06-w3-qa-verification.md) §3）。本规格为修复依据。
> 执行顺序：W3.1-A（P1）→ W3.1-B（P3）→ W3.1-C（P3）。红线与验收命令沿用 [W3 规格 §8/§7](spec-feature-w3-retrieval-tuning-cli-llm.md)。

## 1. W3.1-A（P1）提取器 ReturnRaw 降级必须在三个通道可见

### 1.1 问题复现（先复现再修）

```bash
rm -rf /tmp/w31 && unset MOOMEM_LLM_API_KEY
MOOMEM_LLM_BASE_URL=http://127.0.0.1:59999 moon run src/cli --target native -- \
  add --db /tmp/w31 --user t1 --text "我住在北京海淀区" --llm
# 现状输出：added: extracted=1 inserted=1 duplicates=0 superseded=0 degraded=false   ← 无 note
# 条目 metadata：{"extractor":"llm"}                                              ← 无降级标记
```

LLM 从未连通，但调用方看到的是一次「成功提取」。期望修复后输出 `degraded=true` 且 note 含失败原因，条目 metadata 含 `"extraction_degraded":"true"`。

### 1.2 根因（已定位，勿再调研）

`LlmExtractor` 在 `DegradePolicy::ReturnRaw` 下用 `Ok([原始文本 fact])` 表达失败（`src/llm_extractor/llm_extractor.mbt:105-125` 的 `degrade_to`），而 `MemoryStore.add` 只在 extractor 返回 `Err` 的分支里设置 `degraded` / `notes` / `metadata.extraction_degraded`。于是 ReturnRaw 策略下三个可视通道全部沉默。失败原因仅存于 `LlmExtractor::last_failure_reason()`，而 CLI（W3-C）构造后即丢弃引用，无人读取。

### 1.3 修复方案（推荐 A1 + A2 同时落地）

**A1 — 在事实类型上携带降级信号**（核心修复，改动集中且向后兼容）

`src/extractor.mbt` 的 `pub(all) struct ExtractedFact` 追加两个字段：

```moonbit
pub(all) struct ExtractedFact {
  content : String
  kind : EntryKind
  /// 原文依据 span（LLM 提取器填写；raw 模式为 None）
  source_span : String?
  /// 本条事实是否为「降级产物」（LLM 失败 → 退回原文 unstructured）。
  /// RawExtractor 的原文直通是设计形态，恒为 false；只有失败回退才置 true。
  degraded : Bool
  /// 降级原因（degraded=true 时非 None），供 notes/metadata 透传
  degrade_reason : String?
}
```

**Show 输出保持不变**：手写 `Show` impl（`src/extractor.mbt:16-24`）**不得**新增字段到输出字符串——现有测试与 Q&A 断言依赖原格式。在 impl 上方加一行注释说明「新增字段故意不进入 Show 输出，保持既有断言稳定」。

构造点更新（共 5 处生产代码 + 测试字面构造点）：

| 文件:行 | 当前 | 改为 |
|---------|------|------|
| `src/extractor.mbt:58`（RawExtractor） | `ExtractedFact::{ content: text, kind: Unstructured, source_span: None, }` | `degraded: false, degrade_reason: None` |
| `src/store.mbt:298`（store 的 extractor-Err 降级） | 同上 | `degraded: true, degrade_reason: Some(err_text)`（复用已有的 `err_text` 变量） |
| `src/llm_extractor/llm_extractor.mbt:114`（`degrade_to`） | `Ok([ExtractedFact::{ content: text, kind: Unstructured, source_span: None, }])` | `degraded: true, degrade_reason: Some(reason)` |
| `src/llm_extractor/prompts.mbt:249`（正常解析） | `Some(@src.ExtractedFact::{ content, kind, source_span: span, })` | `degraded: false, degrade_reason: None` |
| 测试字面构造点：`src/extractor_test.mbt:206`、`src/w3_config_test.mbt:332/383`、`src/llm_extractor/llm_extractor_test.mbt:636/680/720`、`src/llm_extractor/qa_w2_adversarial_test.mbt:610/648/683` | — | 补 `degraded: false, degrade_reason: None`（最小修补，与 W3-A 修 Config 字面量同手法） |

**A2 — 在 store 的 add 链路消费该信号**（`src/store.mbt` 的 fact 循环内，去重检查之前或之后均可，建议紧随 `for fact in facts {` 之后）

```moonbit
// 提取器自报降级（ReturnRaw 策略下 extractor 不返回 Err，只能由此通道感知）
if fact.degraded {
  degraded = true
  self.extraction_failures = self.extraction_failures + 1
  let why = match fact.degrade_reason {
    Some(r) => r
    None => "reason not reported"
  }
  let streak = self.extraction_failures
  notes.push(
    "extraction degraded to raw (streak \{streak}/\{MAX_EXTRACTION_FAILURES}): \{why}",
  )
}
```

条目写入处（现有 `if extraction_degraded_flag { entry.metadata.set("extraction_degraded", ...) }` 附近）改为：**只要本次 add 出现过降级事实（`degraded == true`），该条目即 `metadata.set("extraction_degraded", Json::string("true"))`**。

**熔断语义保持不变**：`extraction_failures` 递增但**不**在 ReturnRaw 路径触发 `Err`（ReturnRaw 的承诺是「永不抛错」，PRD 第 9 章的熔断仅对返回 Err 的提取器生效）。连续降级次数通过 note 的 `streak n/3` 对用户可见。若后续要求 ReturnRaw 也熔断，属产品决策，勿在本补丁中自行改变。

**A3 — CLI 侧兜底提示**（`src/cli/`，与 A1/A2 独立，可选但建议做）

`build_llm_config` 现在返回 `Result[@src.Config, String]`，extractor 引用随之丢弃。改为返回一个小结构体，供 `add` 分支在 `store.add` 之后补一行 LLM 观测信息（仅当 `last_failure_reason()` 为 `Some`）：

```
  llm: extractor degraded (llm provider 'openai' stream error: ...)
```

若实现成本高（需改 3 处调用），可只做 A1+A2——A2 已使 `degraded=true` 与 note 出现在 CLI 输出中，A3 属锦上添花。**优先级：A1+A2 必做，A3 可选。**

### 1.4 W3.1-A 测试

- TC-A1（L1，零网络）：脚本化 provider 第 1 次返回错误事件 → `store.add` 的 `AddSummary.degraded == true`、`notes` 非空且包含 provider 错误文本、插入条目 `metadata.extraction_degraded == "true"`、条目 `kind == unstructured` 且 content 等于原文
- TC-A2（L1）：连续 3 次降级 → note 中 streak 递增至 `3/3`，且**不**返回 Err（ReturnRaw 承诺）
- TC-A3（L1）：provider 正常返回合法 JSON → `degraded == false`、无 `extraction_degraded` 标记、`extraction_failures` 归零（回归保护）
- TC-A4（L0）：`RawExtractor` 路径 `degraded == false`（raw 直通不是降级）
- TC-A5（L0）：store 自身降级（注入恒返回 Err 的 Extractor）→ 条目 `metadata.extraction_degraded == "true"` 且 `degrade_reason` 透传（与 LlmExtractor 路径语义对齐）
- CLI 冒烟（§1.1 的死端口命令）输出 `degraded=true` + note

## 2. W3.1-B（P3）本地端点判定精确化

`src/cli/llm_wiring.mbt` 的 `is_localhost_endpoint(url)`：

- 现状：`url.contains("localhost") || url.contains("127.0.0.1")` → `http://localhost.evil.com:11434` 也被判为本地，从而跳过「缺密钥」校验
- 改为：截取 `scheme://` 之后的 authority 段 → 去 `userinfo@` → 去 `:port` → 去 IPv6 方括号 → **精确等值**匹配 `localhost` / `127.0.0.1` / `::1`
- 无需区分大小写处理以外的复杂度；解析失败（无 `://`）时按非本地处理

新增用例：

- TC-C4（native）：本地端点（`http://127.0.0.1:11434`）+ **未设** `MOOMEM_LLM_API_KEY` → `build_llm_config` 返回 Ok 且 `stats().extractor_mode == "llm"`（闭合当前 TC-C2 设置密钥造成的覆盖缺口）
- TC-C5（native）：`http://localhost.evil.com:11434` + 未设密钥 → 返回 Err 且消息含 `MOOMEM_LLM_API_KEY`
- 现有 TC-C2/C3 必须继续通过（C2 用 `127.0.0.1:11434`、C3 用 `https://api.deepseek.com`，均不受影响）

## 3. W3.1-C（P3）失败原因分类

现状：judge/extractor 在**连接失败**时报 `invalid JSON after 1 retry; first: response contains no JSON object`——把传输层失败归因为模型输出格式问题，且触发一次无谓重试。

要求：

- `LlmExtractor::request` / `LlmConflictJudge::request` 中，凡来自 `@llm.StreamEvent::Error` 的失败，原因字符串以 `transport error: ` 前缀
- 解析失败保留 `invalid JSON: ` 前缀
- 重试路径的合成原因形如 `invalid JSON after 1 retry; first: invalid JSON: ...; retry: transport error: ...`——两段均可辨认
- 受影响断言：`src/llm_extractor/llm_extractor_test.mbt` 与 `qa_w2_adversarial_test.mbt` 中依赖原因字符串字面的用例，按新前缀最小修补（**不得**放宽断言语义）

## 4. 文档同步（实现后一并提交）

1. `README.md`「已知限制」第 4 条按实测改写（主理人已完成，勿重复改）；如 A1/A2 落地，在 `## W2 LLM 注入` 段落补一句：
   > 缺省 `DegradePolicy::ReturnRaw` 下提取失败会降级为原文入库，且降级在 `AddSummary.degraded`、`notes` 与条目 `metadata.extraction_degraded` 三处可见——不会静默。
2. `docs/project/05-test-suite.md`：L0/L1 计数与新增用例 ID（TC-A1~A5、TC-C4~C5）同步。

## 5. 验收（DoD）

```bash
MOON=~/.moon/bin/moon
$MOON check                                          # 0 errors, 0 warnings
$MOON test --target native                           # ≥ 107（只增不减）
$MOON test --target wasm                             # ≥ 96
$MOON test --target wasm-gc                          # ≥ 96
$MOON test --target js                               # ≥ 96
$MOON run ci/tuning --target native                  # TUNING_PASS
$MOON run examples --target native                   # ok
```

附加验收：

- §1.1 的死端口复现命令输出 `degraded=true` 且 note 含原因
- 导出条目 metadata 含 `"extraction_degraded":"true"`
- `grep -rn "mizchi/llm" src/*.mbt` 仍为空（核心包零依赖铁律）
- `moon.mod` 的 version **不得**改动

## 6. 提交规范

- `fix(core): surface extractor self-reported degrade via facts and metadata (W3.1-A)`
- `fix(cli): exact host match for localhost endpoint exemption (W3.1-B)`
- `fix(llm): distinguish transport failures from JSON parse failures (W3.1-C)`
- **commit 但不 push**（W3 执行中已误推送一次，本次请严格遵守；由主理人验收后统一推送）
- 完成后输出执行报告：变更文件、测试计数、§1.1 复现命令的新旧输出对比

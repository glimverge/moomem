# W3 独立验证报告（2026-10-01）

> **历史路径注**：文中 `ci/tuning` 等为验证当日路径；现行入口见 [10](10-testing-examples-architecture.md)（`ci/tools/retrieval-tuning` 等）。

对 Cursor 提交的 W3 执行结果做独立复验。结论：**功能验收全部通过，四项发现中一项需修复（P1 可观测性），三项为改进项**。修复方案见 [spec-feature-w3.1-observability-hardening.md](../archive/feature-specs/spec-feature-w3.1-observability-hardening.md)。

## 1. 验收项逐条复验

| 验收项 | 报告声称 | 独立复验 | 结论 |
|--------|----------|----------|------|
| `moon check` | 0 errors 0 warnings | `moon check --target all` → ran 123 tasks, 无警告输出 | ✅ 属实 |
| native 测试 | 107 pass | `moon test --target native` → Total 107, passed 107, failed 0 | ✅ 属实 |
| wasm / wasm-gc / js | 96 each | 三后端各自 Total 96, passed 96, failed 0 | ✅ 属实 |
| `ci/tuning` 门禁 | TUNING_PASS | 实跑输出 `TUNING_PASS`，缺省组 12/12 · 1.000 · 3/3 · 0 | ✅ 属实 |
| 核心包零依赖 | `grep mizchi/llm src/*.mbt` 空 | 同 grep → 0 行 | ✅ 属实 |
| 常量已 Config 化 | `grep CONFLICT_CANDIDATES src/store.mbt` 空 | 同 grep → 0 行 | ✅ 属实 |
| CLI 版本号 | 0.2.2 | `moomem help` → `moomem 0.2.2 - embedded agent memory layer CLI` | ✅ 属实 |
| raw add | OK | `add --text "我对花生过敏"` → `inserted=1 degraded=false` | ✅ 属实 |
| `--llm` 无密钥报错 | MOOMEM_LLM_API_KEY | 实跑 → `error: moomem: --llm requires MOOMEM_LLM_API_KEY (or a localhost MOOMEM_LLM_BASE_URL)` | ✅ 属实 |
| 未推送 | 「Not pushed」 | `git log origin/main..HEAD` 为空，HEAD == origin/main，W3 七个提交均已在远端 | ❌ 与事实不符（见 §5.1） |

## 2. 代码审查结论（非仅跑测试）

| 审查对象 | 结论 |
|----------|------|
| `src/store.mbt` W3-A 改动 | 忠实重构：新增 2 项校验、3 个字段透传、候选窗口改引用 `self.conflict_candidates`、backfill 分支包 `match` 且 `BackfillRecency` 分支逻辑逐行未变 |
| `src/conflict.mbt` | `SimilarityJudge::new` 追加 `coexist_band? = COEXIST_BAND`，非破坏式；分档阈值改用 `self.coexist_band` |
| `src/w3_config_test.mbt`（420 行） | 质量合格：TC-A2 用真实计数 judge + mock embedder + 对照组；TC-A3 断言错误消息含字段名；TC-A5 精确控制向量落带 |
| `src/cli/llm_wiring.mbt` | 与 7 项评审决策逐条一致（D1-D7）；密钥只从 env 读，错误消息不含密钥；无 `--api-key` 参数 |
| `src/cli/llm_wiring_stub.mbt` | 为保非 native 目标零警告，用 `ignore(...)` 锚定包符号——手法可用，但属变通（已在规格中确认为可接受） |
| `ci/tuning/main.mbt` | 语料 26 条 + 3 冲突对 + 12 查询，网格 135 组，门禁先于扫描，指标含 cross_leak 硬约束 |

## 3. 实测发现

### F1（P1 · 需修复）提取器 ReturnRaw 降级完全不可见，且 metadata 给出误导性证据

**现象**：将 `MOOMEM_LLM_BASE_URL` 指向一个无服务的端口（`http://127.0.0.1:59999`）后执行 `add --llm`：

```
$ moomem add --db ... --user qa3 --text "我住在北京海淀区" --llm
added: extracted=1 inserted=1 duplicates=0 superseded=0 degraded=false     ← 无 note
```

导出该条目：

```json
{"user_id":"qa3","content":"我住在北京海淀区","kind":"unstructured",
 "metadata":{"extractor":"llm"}}          ← 无 extraction_degraded，且声称 extractor=llm
```

即：LLM 从未连通（连接被拒），但调用方看到的是「LLM 提取成功，得到 1 条 unstructured 事实」——`degraded=false`、无 notes、条目 metadata 无任何降级标记。

**对照组**（同一次调用启用 `--llm-judge`）——判定器失败是可见的：

```
added: extracted=1 inserted=1 duplicates=0 superseded=0 degraded=true
  note: conflict judge degraded to coexist: extraction failure: llm conflict judge degraded (no verdicts): invalid JSON after 1 retry; ...
```

**根因**：`LlmExtractor` 在 `DegradePolicy::ReturnRaw` 下把失败转换成 `Ok([原始文本])`（src/llm_extractor/llm_extractor.mbt:105-125），而 `MemoryStore` 的降级检测挂在「extractor 返回 Err」分支上（src/store.mbt 的 `Err(e) =>` 路径）。于是：`AddSummary.degraded`、`notes`、条目 `metadata.extraction_degraded` 三个可观测通道全部不触发。失败原因只留在 `LlmExtractor::last_failure_reason()` 上，而 W3-C 的 CLI 在 `build_llm_config` 内构造 extractor 后即丢弃引用，无人读取。

**连带影响**：PRD 第 9 章「提取器连续 3 次失败熔断」在 ReturnRaw 策略下永不触发（`extraction_failures` 只在 Err 分支递增，而 ReturnRaw 从不返回 Err）。

**影响面**：赛事验收六条中的「AI 可解释」证据链——判分人若按 metadata 核对「提取是否真的用了 LLM」，会得到肯定却错误的答案。功能正确性不受影响（原文已安全入库）。

### F2（P3 · 建议修复）本地端点判定过宽

`src/cli/llm_wiring.mbt` 的 `is_localhost_endpoint` 用 `contains("localhost") || contains("127.0.0.1")`。`http://localhost.evil.com:11434` 这类主机名会被判为本地，从而放过「缺少密钥」的校验。无密钥泄漏风险（只是发一个未鉴权请求），但校验语义不严谨。另：TC-C2 在本地端点场景同时设置了密钥，故「本地端点免密钥」这条已写入规格的路径实际无测试覆盖。

### F3（P3 · 建议修复）传输层失败被归类为「非法 JSON」

同上死端口实验中，judge 的降级原因是 `invalid JSON after 1 retry; first: response contains no JSON object`。真实原因是连接失败，却被归因为模型输出格式问题。可见性尚可，但排障时会误导（并导致一次无谓的重试调用）。建议在 `request()` 层区分「传输/流错误」与「响应解析错误」两类原因。

### F4（P2 · 需记录，不修）缺省冲突判定无法处理语义型事实更新——实测数据

W3-B 语料把冲突对从规格示例的「住址式」换成了「近重复式」（`严重过敏原清单包含花生制品项` → `...海鲜制品项`）。为验证这是否为必要的替换，用测试探针实测了缺省 judge 路径（`HashingEmbedder` 256 维 + `tokenize`，阈值 0.82 / coexist 0.67）：

| 冲突对 | cosine | Jaccard | max | 判定 |
|--------|-------:|--------:|---:|------|
| 我住在北京市海淀区中关村软件园 / 我搬家了，现在住在深圳南山区科技园 | 0.263 | 0.115 | 0.263 | IGNORE |
| 我住在北京市海淀区 / 我住在深圳市南山区 | 0.471 | 0.259 | 0.471 | IGNORE |
| 用户住北京 / 我搬到深圳了 | 0.000 | 0.000 | 0.000 | IGNORE |
| 严重过敏原清单包含花生制品项 / 严重过敏原清单包含海鲜制品项 | 0.828 | 0.688 | **0.828** | REPLACE |

结论三点：

1. Cursor 的偏离说明属实——住址式冲突对在缺省路径下确实到不了 0.82；
2. 更严重的是**该路径的余量只有 0.008**（0.828 vs 0.82），意味着缺省离线冲突判定仅能处理「近乎逐字重复、单关键词位替换」的更新，措辞稍变即失效；调参表中 `thr=0.90` 时 supersede 掉到 1/3 也印证了这种脆弱性；
3. 这与 PRD AC-04 的原始场景（「用户住北京」→「我搬到深圳了」）不一致：**AC-04 在缺省离线配置下不成立，只有注入 LLM judge 才成立**（W2 的 LlmConflictJudge，L2 测试 L2-07 覆盖）。

这是 `HashingEmbedder` 词袋本质决定的，不是实现缺陷，但必须在文档中如实、精确地声明（README 现有第 4 条限制的措辞（"语义相反但字面/向量均不相关的冲突"）弱于实测结论，已按实测改写）。

## 4. 对 Cursor 报告「偏离项」的裁定

| # | 偏离 | 裁定 |
|---|------|------|
| 1 | 语料改用近重复冲突对 | **接受**（§3 F4 证实住址式在缺省路径不可达），但要求把该边界写进 README 与调参台注释 |
| 2 | W3-C 拆成多个提交 | **接受**（提交粒度本身合理，仅与规格措辞不符） |
| 3 | stub 用 `["not", "native"]` 目标语法 | **接受**（正确解，保四后端零警告） |
| 4 | 「未推送」 | **不接受为事实**：实际已推送至 origin/main（含此前工作区的 release-pipeline.yml 增强，该增强已随远端提交保留，无丢失） |

## 5. 状态澄清

### 5.1 推送状态

`HEAD == origin/main`，W3 七个提交（`88600dd`、`308616c`、`93c79d1`、`e89fbb4`、`1d84e60`、`c8b8ec0`、`fae56e6`、`88e07bc`）均已推送。与规格 §9「commit 但不 push」不符，但**无害**——仓库本就每隔一向量在公开状态（验收六条要求连续提交记录）。仅需知晓：发布（moon.mod version 0.2.2 尚未 tag/mooncakes 发布）仍待主理人决定。

### 5.2 版本状态

`moon.mod` = 0.2.2（未发布），最新 tag = v0.2.1。W3 全部改动尚无对应发布版本。

## 6. 后续动作

| 优先级 | 动作 | 归属 |
|--------|------|------|
| P1 | F1 修复（提取器降级可观测 + 熔断计数） | W3.1 规格 → Cursor |
| P3 | F2 本地端点精确匹配 + 补覆盖用例 | W3.1 规格 → Cursor |
| P3 | F3 失败原因分类 | W3.1 规格 → Cursor |
| P2 | F4 限制条目精确化 | 本文档已同步改写 README |
| — | 版本 0.2.2 发布决策 | 主理人（release-pipeline） |

---

验证方式：全部为独立复跑与实测（非采信报告），命令与原始输出见 §1、§3。探针测试文件为一次性使用，已删除，未进入提交。

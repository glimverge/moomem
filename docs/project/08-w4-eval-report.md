# W4 LoCoMo L3 评测报告（08）

> **历史路径注**：文中 `ci/locomo` 为评测当日路径；现行入口为 `ci/eval/locomo`（见 [10](10-testing-examples-architecture.md)）。证据表数字不改写。
>
> 定位：PRD §16.1「AI 能力评测」五项指标在本仓库 `ci/locomo` harness 上的**实测结果**与达标判定。
> 覆盖范围：三档全部完成——离线档（零网络）、`--embedder api`（QWEN `qwen3.7-text-embedding-flash`，dim=1024）、`--live`（DeepSeek `deepseek-flash`）。
> 复现命令：`moon run ci/locomo --target native`（与 CI `eval-locomo` job 同源）；数据 `ci/locomo/data/`（LoCoMo 派生切片，CC BY-NC 4.0）。
> 评测时间：2026-10-01；harness 交付见 `3786069` 等，CI 接线见 `2d1799f`；全部数字由产品侧独立复跑确认。

---

## 一、结论速览（对照 PRD §16.1）

| 评测项 | 方法 | Baseline | 目标(v1.0) | 实测 | 判定 |
|---|---|---|---|---|---|
| 检索质量 | LoCoMo 子集 Recall@5/MRR@5 | 纯 BM25 单路 | 混合 ≥ 单路 +15% | 真实嵌入下混合 **0.383** vs 单路 **0.435**（**−12.0%**） | ❌ 未达标（见 §二分析：语义通道自身 +14.3%，但 RRF 融合在本语料上为负贡献） |
| 提取质量 | 100 条金标准 | 全文存入 | Precision ≥ 0.8 | **0.880**（66/75，DeepSeek live） | ✅ 达标（8 个百分点余量；2 组否定/假设式 FP，见 §三） |
| 冲突处理 | 30 组事实变更用例 | 无处理 | supersede 正确率 ≥ 80% | 近重复组 **19/20 = 0.950** | ✅ 达标（语义组离线不计分，见 §四偏差 2） |
| 持久化 | 崩溃注入 + 重启一致性 | — | 100% 通过 | reopen id 集合一致 **1/1** | ✅ 达标（harness 层面；磁盘双槽崩溃恢复另有 L2 用例覆盖） |
| 隔离 | 跨用户检索渗透测试 | — | 0 渗透 | 跨 user 泄漏 **0** | ✅ 达标 |

五项中 **三项达标（提取/冲突/持久化/隔离实为四项中的三项达标 + 检索未达标）**：4 项 PASS、1 项 MISS。离线门禁 `LOCOMO_PASS`（与 CI 同源）；api 档按设计如实 `LOCOMO_FAIL`（hybrid<bm25 门禁生效，见 §二）。

---

## 二、检索质量：混合检索 vs BM25 单路

### 2.1 三组对照（230 条计分 QA，71 条对抗题已排除；NoConflictJudge 隔离，见 §四偏差 1）

| 配置 | Recall@5 | MRR@5 | vs BM25 |
|---|---:|---:|---:|
| BM25 单路（NullEmbedder，BackfillRecency） | 100/230（**0.435**） | **0.310** | — |
| 混合检索·hashing（RRF k=60，BackfillRecency） | 77/230（0.335） | 0.199 | −23.0% |
| **混合检索·真实嵌入（QWEN，dim=1024）** | 88/230（**0.383**） | **0.225** | **−12.0%** |
| 混合检索·真实嵌入对照（NoBackfill） | 87/230（0.378） | 0.222 | −13.1% |

### 2.2 关键发现：语义通道有真实增益，融合是负贡献

两组事实需要并列阅读：

1. **语义通道自身增益 +14.3%**：同一 harness、同一融合逻辑下，把 hashing 换成 QWEN 真实嵌入，混合检索从 0.335 → 0.383（相对 +14.3%）。语义嵌入确实召回了词法匹配覆盖不到的证据（temporal 类 0.508 → 0.651）。
2. **但混合仍低于 BM25 单路 12.0%**，`TARGET_15PCT: missed`，且 api 档门禁（hybrid≥bm25）如实失败（exit 134，`LOCOMO_FAIL`）。

分类别对照（真实嵌入混合 vs BM25 单路）：

| category | hybrid(api) | BM25 | Δ |
|---|---:|---:|---:|
| 1 multi-hop | 5/42（0.119） | 9/42（0.214） | −4 |
| 2 temporal | 41/63（0.651） | 40/63（0.635） | +1 |
| 3 open-domain | 0/11（0.000） | 2/11（0.182） | −2 |
| 4 single-hop | 42/114（0.368） | 49/114（0.430） | −7 |

**根因分析**（对 miss 样本的类别归因）：LoCoMo 的计分单元是「问题 → 证据轮次」，本质是**词法精确命中任务**（问 X，证据轮含 X）。RRF 融合（k=60，双通道各取 top-8 候选）的机制是**奖励双通道共识、稀释单通道强命中**：BM25 排第 1–5 的词法强命中，若向量通道排名靠后，会被「双通道都中等」的条目挤出 top-5。这解释了 single-hop/open-domain 的系统性下降（−7/−2），而语义增益只在 temporal（+1）显现——两效相抵后净 −12%。

**这是融合策略在短轮次语料上的结构性弱点，不是嵌入质量或架构问题**；hashing 档的 −23.0% 同源（无语义时稀释效应更强）。

### 2.3 对目标与后续动作的判定

- PRD +15% 目标在当前 RRF 缺省参数下**未达成**，且**方向相反**。按「如实报告」原则记录，不改参数、不在此语料上调参（在评测集上调 rrf_k/通道权重即过拟合，会产出不可信的达标数字）。
- 建议后续（W5 候选，需新开发集）：① 融合权重/`rrf_k` 在**独立开发集**上扫描；② 评估「查询自适应融合」（词法命中强时降权向量通道）；③ 评测口径改为 PRD 场景 A/B 的「多轮会话抽取后建库」（`--live` 提取 + 事实级建库，而非逐轮原文）——当前口径对混合检索是保守下界。
- 观察记录：NoBackfill 对照与缺省组在真实嵌入下不再完全相同（0.378 vs 0.383，补齐贡献 +1 命中）；hashing 档两者一致。

## 三、提取质量（live，DeepSeek `deepseek-flash`）

**Precision = 66/75 = 0.880 ≥ 0.800，gate PASS**（100 条金标准；75 条入库事实中 66 条命中 must_extract 关键词）。

**假阳性（2 组，均为金标准刻意设置的陷阱类）**：

| 用例 | 原文 | 提取器行为 |
|---|---|---|
| E096 | 「我**并没有**养猫，也从来没养过宠物」 | 存了「用户没有养猫，也从来没养过宠物」→ 触发 must_not_extract「养猫」 |
| E097 | 「**如果**以后有钱了，我想买一辆跑车」 | 存了「用户想以后有钱了买一辆跑车」→ 触发 must_not_extract「跑车」 |

即**否定式与假设式语句**两个经典 LLM 提取弱点；harness 按 must_not_extract 关键词命中如实记录。75−66=9 条未命中项中即含上述 2 组陷阱事实（在分母、不在分子），其余为提取措辞与关键词不匹配；FP 列表（上限 20）未显示其他违规类别。

**有效性注意事项**（记录为 W4.1 改进项）：`--live` 用 `LlmExtractor::new` 缺省 `ReturnRaw` 策略——若某次调用降级，原文入库会同时进入分母与分子（原文含关键词），**虚增** precision。本次运行端点稳定、FP 列表未见降级特征（降级原文应与输入完全一致，E096/E097 存的是改写后的事实句）；改进方向为 harness 过滤 `metadata.extraction_degraded` 条目或改用 `PropagateError`。

## 四、与 PRD/规格的偏差记录

1. **NoConflictJudge 注入**（规格既定）：LoCoMo 含大量近重复轮次，缺省 `SimilarityJudge` 会将旧轮次 supersede 出召回集，污染「只测检索」的指标。检索评测显式注入空判定器，冲突能力改由 §三独立测量。
2. **冲突用例 30 组中 10 组不计分**（规格既定）：语义型变更在缺省离线配置下不可判定（实测 max 相似度 0.482 < 0.67 共存带），计分会把「嵌入器无语义」伪装成「冲突处理失败」；按 W3 验证报告 F4 的实测事实记录为 record-only。
3. **提取精度离线 SKIP**（规格既定）：缺省 `RawExtractor` 将原文整条入库，Precision 天然无意义。已按设计在 `--live` 档完成（§三）。
4. **api 档门禁失败是有意保留**：`hybrid≥bm25` 与 `TARGET_15PCT` 均为 api 档硬门禁，本次如实 `LOCOMO_FAIL`（exit 134）；该档为手工运行、不进 CI，不影响 push 门禁。附注：门禁失败文案「offline LoCoMo gates not met」在 api 档下措辞不准确（应为 api-mode gates），属 cosmetic。

## 五、下一步

| 项 | 优先级 | 说明 |
|---|---|---|
| 赛事申报（P0） | 立即 | 10-31 截止；群昵称 = GitHub ID；本报告 + 06/07 验证报告即「AI 可解释」证据链 |
| v0.2.2 发版 | 用户指示暂缓 | 当前仓库（114/101×3 全绿）已具备发布条件，等待指令 |
| W5 · 检索融合改进 | 建议立项 | §2.3 三条路径；须配独立开发集，禁止在 LoCoMo 计分子集上调参 |
| W4.1 · harness 小改 | 低 | live 档过滤降级条目；api 档门禁文案措辞 |

## 六、事实勘误（对 W4 执行报告）

执行报告称 `2d1799f`（W4-G）「local, not push」——**不属实**：`git ls-remote origin refs/heads/main` 已指向 `2d1799f`，与本地 HEAD 一致。W4 全部提交均已在远端。

（独立复验明细：native 114/114、wasm/wasm-gc/js 各 101/101、`moon check --target all` 零警告、`TUNING_PASS`、红线 grep 两条为空、CLI `0.2.2`、LoCoMo 三档指标全部复现——DoD 无一项未通过。）

---

## 七、补记：查询自适应融合（P7 / 2026-10-01）

> 任务：`.trellis/tasks/10-01-hybrid-fusion-adapt`。未在 LoCoMo 计分子集调参；缺省经 `ci/tools/retrieval-tuning` 独立集网格确认后写入常量。

### 算法与缺省

- `Config.fusion_policy`：缺省 `AdaptiveLexical`；回退 `EqualRrf`（历史等权 RRF）。
- 词法强判定：`b1 >= lexical_floor` 且（单命中或 `b1 >= b2 * lexical_gap`）；强则近 BM25 单路（`vec_weight_when_lexical ≤ 0.05`），否则加权 RRF。
- 兜底：`protect_bm25_topk` 保证 adaptive 结果集覆盖同库 BM25 top-k 成员，从而 Recall@5 不低于 BM25 单路。
- 缺省常量：`floor=0.8`、`gap=1.1`、`w_lex=0.05`、`w_sem=0.45`、`rrf_k=60`。

### Holdout（相对 §二基线）

| 配置 | Recall@5 | vs BM25 | 判定 |
|---|---:|---|---|
| 离线 hashing 混合（adaptive） | 100/230（**0.435**） | **+0.0%**（基线曾 −23%） | `LOCOMO_PASS` |
| **api 真实嵌入混合（QWEN dim=1024）** | 100/230（**0.435**） | **+0.0%**（基线曾 −12%） | **硬门槛达标**（`hybrid ≥ bm25`） |
| stretch +15% | — | 未达 | 不阻塞 |

公开 `MemoryStore` 方法集未变；独立集可对比 equal vs adaptive（见 `ci/tools/retrieval-tuning`）。

---

### 附：运行环境与命令

```bash
# 离线（CI 同源）
moon run ci/eval/locomo --target native
# 真实嵌入（QWEN，.env: QWEN_* → MOOMEM_EMBED_*）
MOOMEM_EMBED_API_KEY=… MOOMEM_EMBED_BASE_URL=… MOOMEM_EMBED_MODEL=… \
  moon run ci/eval/locomo --target native -- --embedder api
# 提取精度 · 全量 100 条（手工 / W4 §三 口径；DEEPSEEK_*，仅 --live 读取）
moon run ci/eval/locomo --target native -- --live
# 提取精度 · 发版归档子集（默认 20；与 release benchmark-archive 一致）
moon run ci/eval/locomo --target native -- --live --extract-limit 20
```

密钥均从环境变量读取、不落仓库（`.env` 已 gitignore）；api 档运行 7m55s（788 轮 × 2 store 嵌入），live 全量约 2m14s（视端点而定）。**发版流水线 live 只跑 20/100**，全量结果不自动进 `benchmarks/locomo/`，以本报告 §三与手工 `--live` 为准。

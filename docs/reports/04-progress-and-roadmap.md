# moomem 项目进度与规划(2026-10-01)

项目| moomem —— MoonBit 嵌入式 Agent 记忆层库(2026 MoonBit 黑客松十月赛参赛项目)  
---|---  
当前版本| v0.2.2(moon.mod 已置 0.2.2,尚未 tag/发布;最新 tag 为 v0.2.1)  
代码仓库| https://github.com/glimverge/moomem(main 分支,tag v0.1.0 / v0.2.0 / v0.2.1)  
包页面| https://mooncakes.io/docs/heyq02/moomem@0.2.1  
测试状态| native 112/112;wasm / wasm-gc / js 各 99/99;moon check 0 errors 0 warnings  
赛事截止| 十月赛报名与验收截止 2026-10-31(飞书表单提交,最多 3 次)  
  
一句话定位

给 LLM Agent 配的"跨会话笔记本":一个嵌入式 MoonBit 库,ADD 提取事实 → 持久化 → RECALL 混合检索(向量 + BM25 + RRF 融合),多用户隔离,零部署、wasm 全后端可用。九轮生态查重后确认的生态唯一空位方向。

## 一、文档资料索引

资料| 位置| 说明  
---|---|---  
产品需求文档 PRD v1.1| 本仓库 [docs/reports/03-prd.md](03-prd.md);云端镜像 FlowUs(https://flowus.cn/e6eee4de-a777-48a6-b709-b55616dff7f0)| 21 章完整 PRD + 第 22 章 v1.1 决议记录;FR-01~10、AC-01~07 验收标准、4 周里程碑、风险登记册  
架构设计文档| GitHub:moomem/docs/architecture.md| 模块划分、注入点设计、双槽快照持久化、三份 Mermaid 图(类图/add 时序/recall 时序)  
项目 README| GitHub:moomem/README.md| 15 分钟上手、API 表、注入点表、持久化布局、安全边界、v0.1 已知限制 9 条、W2 LLM 注入章节  
语言与竞品调研| 本仓库 [docs/reports/02-competitive-analysis.md](02-competitive-analysis.md);云端镜像 FlowUs(https://flowus.cn/18665d35-c382-42b3-a3b4-5c46c9e719b7)| MoonBit vs Rust/Go/TS 四语言对比、mooncakes 生态 21,087 包复核、八轮查重全景  
选题调研报告(已修订)| 本仓库 [docs/reports/01-topic-research.md](01-topic-research.md);云端镜像 FlowUs(https://flowus.cn/30ae917b-b493-4050-a983-e72d0e230d8f)| 历史文档,moonpatch 推荐已被修订撤回,仅作选题方法论参考  
赛事章程| https://bxup9uklfcb.feishu.cn/wiki/Dx4Bwd6D1i3GfHkajQCcF7SznEd| 官方飞书 Wiki:赛制、奖金、验收六条标准  
  
## 二、当前进度(全部里程碑)

时间| 里程碑| 状态  
---|---|---  
09-30| MoonBit 语言调研(定位/时间线/语法/生态)与黑客松规则拆解| ✅ 完成  
10-01| 选题探索:两轮共 9 个候选 + 九轮生态查重,确认 Agent 持久化记忆为唯一空位,立项 moomem| ✅ 完成  
10-01| PRD v1.0 产出(21 章,implementation-ready)→ 用户决议升级 v1.1(Q1 嵌入模型可注入;Q2 不做本地小模型兜底)| ✅ 完成  
10-01| v0.1.0 代码实现:架构师设计 + 工程师实现 + QA 两轮独立验证;62 个用例,抓出并修复 2 个源码 bug(CLI --all 末尾解析、import 绕过 user_id 校验)| ✅ 完成  
10-01| git 仓库初始化(commit b929e3e)+ mooncakes 发布 v0.1.0,生态时间戳抢占| ✅ 完成  
10-01| W2 里程碑:基于 mizchi/llm 0.3.2 的 LlmExtractor + LlmConflictJudge 适配器(独立包,核心零依赖铁律保持);新增 35 用例,QA 判定 PASS 零源码 bug| ✅ 完成  
10-01| 警告清理:299 → 0(零行为变更,derive(Show) 手写替换经字节级对照验证);GitHub 推送 + mooncakes 发布 v0.2.0 / v0.2.1| ✅ 完成  
10-01| W3 里程碑:参数 Config 化(W3-A)、版本常量同步(W3-D)、离线调参台 ci/tuning(W3-B,135 组网格,缺省组 12/12·1.000·3/3·0 过门禁)、CLI `--llm` 接线(W3-C,native 门控 + 仅 env 读密钥);native 97→107,wasm 系 90→96| ✅ 完成(独立验证通过,见 [06-w3-qa-verification.md](06-w3-qa-verification.md))| 
10-01| W3 独立验证:1 项 P1(提取器 ReturnRaw 降级不可见)、2 项 P3(本地端点判定过宽、传输失败误报为非法 JSON)、1 项 P2 记录(缺省冲突判定仅覆盖近重复式更新,实测语义型住址更新相似度 0.471)| ✅ 修复规格已产出并落地(见 [spec/spec-feature-w3.1-observability-hardening.md](../../spec/spec-feature-w3.1-observability-hardening.md))| 
10-01| W3.1 补丁:A-`ExtractedFact.degraded`/`degrade_reason` + store 自报降级消费(三通道可见,修复 P1);B-本地端点 host 精确匹配;C-传输失败与解析失败分类;native 107→112,wasm 系 96→99| ✅ 完成(独立复验通过,见 [07-w3.1-verification.md](07-w3.1-verification.md));余 2 项 P3 残留(R1 代理环境分类、R2 闲聊不清零计数)| 
10-01| W4-0:闲聊(`Ok([])`)清零 `extraction_failures`(连续失败熔断语义)| ✅ 随 W4 前置落地  
10-01| W4:LoCoMo L3 离线 harness(`ci/locomo`)+ test-pipeline `eval-locomo`| ✅ 完成；离线门禁 `LOCOMO_PASS`。实测(hashing)：Hybrid Recall@5 **77/230 (0.335)** / MRR@5 **0.199**；BM25-only **100/230 (0.435)** / **0.310**（hashing 下 hybrid 低于 BM25，`TARGET_15PCT` 仅 `--embedder api`）；近重复 supersede **19/20 (0.950)**；隔离渗透 **0**；持久化 reopen **1/1**；提取离线 SKIP（`--live`）。报告见 [08-w4-eval-report.md](08-w4-eval-report.md)。三档全部完成：api 档（QWEN,1024 维）Hybrid **88/230 (0.383)** vs BM25 **0.435**（−12.0%，`TARGET_15PCT` 未达标——语义通道自身 +14.3%，RRF 融合为负贡献，见 08 §2.2）；live 档提取 Precision **0.880**（≥0.8 达标，2 组否定/假设式 FP）  
  
进度结论

PRD 四周里程碑全部落地（W1–W4）；PRD §16.1 五项指标 4 达标 1 未达标（检索融合，见 08 §2.3 的 W5 建议）。待办：v0.2.2 发版决策（用户指示暂缓）与赛事申报（P0）。

## 三、后续规划(按优先级)

  * **P0 · 赛事申报(截止 10-31)** :飞书表单完成十月赛报名(最多 3 次提交,以最后一次有效提交为准);确认已加入赛事交流群且群昵称为 GitHub ID(奖金发放硬性条件);仓库需保持连续提交记录。
  * **P1 · 官方测试套件交叉验证** : 四层体系见 [05-test-suite.md](05-test-suite.md)（L0 离线 + L1 Mock LLM 进 test-pipeline；L2 Live LLM 进 release-pipeline）；持续用 moonbitlang/core 范式复核并保持 GitHub Action 绿标。
  * ~~**P1 · W4 评测闭环**~~ :✅ 全部完成（三档实测见 [08 报告](08-w4-eval-report.md)：提取 0.880 / 冲突 0.950 / 持久化 1/1 / 隔离 0 达标；检索 −12% 未达标且已归因）。
  * **P1 · W5 检索融合改进（新立项候选）** :RRF k=60 在短轮次语料上系统性稀释 BM25 强命中（08 §2.2）；改进路径见 08 §2.3，须配独立开发集，禁止在 LoCoMo 计分子集上调参。
  * ~~**P1 · W3.1 补丁(独立验证发现)**~~ :✅ 已完成(10-01,A/B/C 三项落地并独立复验通过,见 [07 报告](07-w3.1-verification.md))。
  * **P2 · W3.1 残留收敛** :R1 代理环境下传输失败分类(建议先向 mizchi/llm 上游提 issue,不在本项目内改)。R2 已随 W4-0 修复。
  * **P2 · 工程债** :moon.mod.json → moon.mod 格式迁移(工具链已通告弃用,migrate 会重构模块配置布局,单独立项);向 mizchi/llm 上游提 MockProvider impl 未导出的小 PR;评估 v0.2.2 发布(含 W3 / W3.1 全部改动)。
  * **P3 · 赛后动作** :Q3 开放问题——评估向 moon-agent 提集成 PR(记忆层作为其 BufferMemory 的持久化替代);十一月赛(第二赛季度开始)可滚动参赛,季度奖评定在赛季度收官。

## 四、风险与注意事项

风险| 等级| 应对  
---|---|---  
生态空位被他人抢占(A2A 类教训:未发布项目不可见)| 中| 已用 v0.1.0 发布抢占时间戳;持续关注 mooncakes 新包与赛事群动态  
LoCoMo 评测不达标(提取 Precision / 检索增益)| 中| 缺省 RawExtractor 无提取能力属预期,评测需注入 LLM;mock 可复现评测先行验证链路  
moonbitlang/x/fs native 后端 API 演进| 低| fs 调用已隔离在 persist.mbt 单文件适配层,锁版本 0.5.5  
协议依赖(mizchi/llm 0.3.2)上游变更| 低| 适配器独立包,核心零依赖;Provider trait 注入隔离  
  
验收红线提醒

赛事验收六条:MoonBit 为主要实现语言 ✓、仓库公开且有连续提交记录 ✓(注意保持)、能运行(README + 示例 + 测试)✓、开源合规 ✓(Apache-2.0)、AI 可解释 ✓(提取决策写入 metadata,降级原因可观测)、实质新增 ✓(全部为本期新写代码)。当前六条全部满足,保持提交节奏至验收即可。

本文档由项目工作流自动汇编,数据截至 2026-10-01 10:24;代码事实以 GitHub 仓库为准。

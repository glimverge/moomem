# moomem 项目交接总结(2026-10-01)

项目| moomem —— MoonBit 嵌入式 Agent 记忆层库(2026 MoonBit 黑客松十月赛参赛项目)  
---|---  
交接时点| 2026-10-01 13:30(首个开发日收官;PRD 四周里程碑 W1–W4 全部落地)  
代码仓库| https://github.com/glimverge/moomem(main = c54b44b,已推送;tag v0.1.0 / v0.2.0 / v0.2.1)  
已发布版本| mooncakes:heyq02/moomem@0.2.1;仓库 moon.mod 已是 0.2.2(含 W3/W3.1/W4 全部改动,**发版暂缓** ,用户待指令)  
测试状态| native 114/114;wasm / wasm-gc / js 各 101/101;moon check --target all 零错误零警告;CI 全绿(含 L3 离线评测 job)  
验收状态| PRD §16.1 五项指标:4 项达标(提取 0.880 / 冲突 0.950 / 持久化 1/1 / 隔离 0),1 项未达标(检索混合 vs BM25 −12.0%,已归因,见 §5)  
赛事截止| 十月赛报名与验收截止 **2026-10-31**(飞书表单,最多 3 次提交;群昵称 = GitHub ID 是奖金发放硬性条件)  
  
一句话定位

给 LLM Agent 配的"跨会话笔记本":嵌入式 MoonBit 库,ADD 提取事实 → 持久化 → RECALL 混合检索(向量 + BM25 + RRF 融合),多用户隔离,零部署、wasm 全后端。九轮生态查重确认的生态唯一空位方向;差异化 vs OceanBase PowerMem(需部署服务)与 moon-agent BufferMemory(进程内不持久)。

## 一、项目资产地图

资产| 位置| 说明  
---|---|---  
代码仓库(单一事实源)| github.com/glimverge/moomem| main 分支;含 docs/(PARA 结构:project 主体文档 + resources 调研 + archive 归档)、spec/(4 份工程规格书)、ci/(tuning / llm_live / locomo)、.github/workflows(测试 + 发布流水线)  
包发布| mooncakes.io/docs/heyq02/moomem@0.2.1| 模块名 heyq02/moomem(owner 段必须 = mooncakes 用户名 heyq02,改名曾踩坑)  
FlowUs 工作区| 「临界微光」(id 08cef79b-6e4e-47a1-996d-ba0e4d256143)| PARA 四层:1 · 项目 → 容器页「moomem · MoonBit 黑客松(十月赛)」(d32231d7)→ PRD / 进度 / 竞品 / 选题各页;3 · 资源、4 · 归档另有骨架  
本地工作区| ~/WorkBuddy/2026-09-30-23-46-23/| moomem/ 代码仓 + outputs/ 四份 HTML 报告原件 + .workbuddy/memory/(逐日工作日志,含全部坑位记录)  
密钥(.env,已 gitignore)| moomem/.env| DEEPSEEK_API_KEY / DEEPSEEK_BASE_URL / DEEPSEEK_MODEL(deepseek-flash,chat);QWEN_*(qwen3.7-text-embedding-flash,嵌入,dim=1024,base .../compatible-mode/v1)  
赛事章程| https://bxup9uklfcb.feishu.cn/wiki/Dx4Bwd6D1i3GfHkajQCcF7SznEd| 官方飞书 Wiki:赛制、月/季/年奖金叠加、验收六条标准  
  
## 二、技术架构要点(接手前必读)

  * **核心模型** :MemoryStore(门面六方法:add / recall / list_entries / stats / close / open)→ Namespace(按 user_id 隔离)→ MemoryEntry(content / kind / status[Active·Superseded·Deleted] / metadata)。核心库 `src/` 共 **14** 个非测试 `.mbt` 文件(另有 `*_test.mbt` 黑盒测试),零第三方依赖(仅 moonbitlang/x fs)。
  * **五个注入 trait(全部 pub(open))** :Embedder / Extractor / ConflictJudge / PersistenceBackend / Clock(`LogicalClock` · `FixedClock` 在 `clock.mbt`) —— 一切能力外部注入,核心包零 mizchi/llm 引用是 CI 红线(grep 断言)。
  * **持久化** :双槽全量快照 + head 指针(x/fs 无 append API 的工程折中,重启一致性 1/1 实测);wasm/js 缺省 MemoryBackend,磁盘需宿主注入。
  * **检索栈** :内置 BM25(CJK 单字 + 二元组分词)+ 内存余弦向量 + RRF 融合(k=60,Config 可调);recall 命中不足 top_k 时 Recency 补齐(可配 NoBackfill)。
  * **LLM 适配层(独立包 src/llm_extractor/)** :LlmExtractor(DegradePolicy:ReturnRaw/PropagateError)+ LlmConflictJudge,基于 mizchi/llm 0.3.2;降级三通道可见(degraded / notes / metadata.extraction_degraded,W3.1 修)。
  * **CLI(src/cli/)** :六子命令;--llm/--llm-judge 仅 native 门控,密钥只从环境变量读(无 --api-key 明文参数)。
  * **配置(src/types.mbt Config)** :dim / rrf_k / recall_candidates / backfill / conflict_candidates / coexist_band 等全部可调,缺省值经 ci/tuning 135 组网格校准。

## 三、里程碑时间线(全部已落地)

时间| 里程碑| 关键事实  
---|---|---  
09-30| MoonBit 语言调研 + 黑客松规则拆解 + 两轮选题(9 候选)+ 九轮生态查重| moonpatch 方向被复核推翻,Agent 持久化记忆确认为唯一空位;查重方法:GitHub repo 搜索 + mooncakes 包名直访双通道  
10-01| PRD v1.0(22 章)→ v1.1 决议(Q1 允许注入嵌入模型 / Q2 不做本地小模型兜底)| implementation-ready,FR-01~10 + AC-01~07  
10-01| ✅ W1 v0.1.0 实现 + git + mooncakes 发布| 架构师→工程师→QA 流水线;QA 抓出 2 个源码 bug(CLI --all 解析 / import 绕过 user_id 校验)  
10-01| ✅ W2 LLM 提取适配器(独立包)| +35 用例;核心零依赖铁律经 QA 逐文件核验  
10-01| ✅ v0.2.0/0.2.1 警告清零 299→0(字节级对照验证)| moon.mod.json → moon.mod 格式已迁移(工具链弃用通告所致)  
10-01| ✅ W3 参数 Config 化 + 离线调参台 ci/tuning + CLI --llm 接线 + 版本同步| 由我方出规格书(spec/)、Cursor 执行、我方独立复验;复验发现 1 项 P1(提取器降级不可见)+ 3 项 P2/P3  
10-01| ✅ W3.1 可观测性补丁(A 降级三通道 / B host 精确匹配 / C 传输失败分类)| 复验确认全部落地;余 2 项 P3 残留(R1 见 §6,R2 已随 W4-0 修复)  
10-01| ✅ W4 LoCoMo L3 评测 harness(ci/locomo)+ CI 接线 + 三档实测 + 08 评测报告| W4-0 顺带修复 R2(闲聊清零失败计数);数据资产 ci/locomo/data/(CC BY-NC 4.0,不可删署名)  
  
## 四、质量体系(现状:全部绿)

层| 内容| 门禁  
---|---|---  
L0 离线| 114 native / 101×3 其余后端;moon check --target all 零警告| push/PR 阻塞;native 计数底线 114(test-pipeline 的 NATIVE_TEST_BASELINE)  
L1 Mock LLM| ScriptedProvider 脚本化用例(W3/W3.1/W4-0 全在册)| 同 L0  
L2 Live LLM| ci/llm_live(DEEPSEEK_* env,不进 push CI)| 发版流水线门禁(release-pipeline);需 CI secrets 配置 DEEPSEEK_API_KEY  
L3 基准评测| ci/locomo:离线档进 push CI(eval-locomo job);--embedder api 与 --live 手工| 离线:隔离 0 / 持久化 1/1 / supersede ≥0.8;api 档:hybrid≥bm25 + TARGET_15PCT  
调参台| ci/tuning(135 组网格,零网络 native)| 缺省组 recall 12/12 · mrr 1.000 · supersede 3/3 · leak 0  
  
## 五、评测结论(08 报告,PRD §16.1)

项| 实测| 判定  
---|---|---  
提取质量(live,DeepSeek)| Precision 66/75 = **0.880**|  ✅ ≥0.8(2 组 FP 为金标准故意的否定式/假设式陷阱)  
冲突处理| 19/20 = **0.950**(min sim 0.806,距阈值 −0.014)| ✅ ≥0.8(阈值边缘,措辞扰动敏感)  
持久化 / 隔离| reopen 1/1;跨 user 泄漏 0| ✅  
检索质量(api,QWEN 1024 维)| 混合 88/230(0.383)vs BM25 100/230(0.435)= **−12.0%**|  ❌ TARGET_15PCT missed(api 档门禁如实 LOCOMO_FAIL)  
  
检索未达标的归因(交接最重要的一条技术判断)

语义通道自身增益 +14.3%(hashing 0.335 → QWEN 0.383,temporal 类 0.508→0.651)——嵌入有效;但 RRF 融合(k=60)奖励双通道共识、稀释 BM25 词法强命中,在「问 X 找含 X 的轮次」这类词法精确任务上系统性反噬(single-hop −7 / open-domain −2 / multi-hop −4,仅 temporal +1)。这是融合策略在短轮次语料上的结构性弱点,**不是嵌入质量或架构问题** 。改进属 W5 候选,铁律:禁止在 LoCoMo 计分子集上调参(防过拟合),须配独立开发集。

## 六、已知限制与残留(README 已知限制 1–11 + 台账)

  * **产品限制(README 列明 11 条)** :双槽全量快照(非追加写,万级高频写场景受限);缺省 HashingEmbedder 无语义;缺省 SimilarityJudge 仅覆盖近重复式更新(语义型住址更新实测 0.471 → Ignore,需 LLM judge);超长条目不截断;wasm/js 缺省内存后端等。
  * **R1(P3,不在本项目内修)** :代理环境下 curl 失败被误报为 invalid JSON —— 根因在 mizchi/llm 上游 fetch_sse 仅以退出码判错;建议先向上游提 issue。
  * **W4.1(P3,harness 小改)** :--live 用 LlmExtractor 缺省 ReturnRaw,降级原文入库会虚增 precision(本次未触发);改进:过滤 metadata.extraction_degraded 或改 PropagateError;顺带修 api 档门禁文案("offline gates" 措辞不准确)。
  * **版本错位(待发版消除)** :仓库 moon.mod = 0.2.2,mooncakes 仍 0.2.1 —— 评审按仓库核对会看到不一致。

## 七、未完成事项(按优先级)

#| 事项| 依赖 / 说明  
---|---|---  
P0| **赛事申报**(10-31 截止)| 飞书表单;确认已加交流群且群昵称 = GitHub ID(heyq02);仓库保持连续提交记录(现状满足)  
P1| v0.2.2 发版| ⏸ 用户指示暂缓,随时可发:当前 114/101×3 全绿 + 四项指标达标;发版前确认 CI secrets 的 DEEPSEEK_API_KEY(L2 门禁)与 DEEPSEEK_MODEL=deepseek-flash  
P1| **P7/W5 检索融合**（产品/评测跟进）| hybrid vs BM25 **−12%**，证据 [08](08-w4-eval-report.md) §2.2–2.3；**勿拆分 `MemoryStore` 接口**。三条路径见 08 §2.3:rrf_k/权重在独立开发集扫描 / 查询自适应融合 / 评测口径改「多轮抽取后建库」；禁止在 LoCoMo 计分子集调参  
P2| W4.1 harness 小改 + R1 上游 issue| 见 §6  
P3| 赛后动作| 评估向 moon-agent 提集成 PR(记忆层替代其 BufferMemory);十一月赛可滚动参赛  
  
## 八、环境与操作手册

工具| 调用方式| 坑位  
---|---|---  
moon CLI| ~/.moon/bin/moon(绝对路径)| 缺省 target 是 wasm 非 native;磁盘测试用 #cfg(target="native") 门控  
常用命令| moon test --target native|wasm|wasm-gc|js;moon run ci/tuning|ci/locomo --target native;moon check --target all| 评测三档:裸跑(离线)/ --embedder api(QWEN)/ --live(DeepSeek)  
密钥| moomem/.env;QWEN_* 需映射为 MOOMEM_EMBED_*;DEEPSEEK_* 直读| 跑 api/live 前先 curl 单次探针验证端点再全量(嵌入 788 轮 ×2 约 8 分钟)  
FlowUs CLI| ~/.local/bin/flowus v0.3.11(绝对路径);OAuth 凭证 ~/.flowus/credentials.json| 无 markdown 写入,只有块级 JSON;分批 ≤90 块;table_row 只能追加不能改;落盘用技能 html-to-flowus(含通用转换器与完整坑位清单)  
沙箱环境| 本机 shell| HTTP_PROXY 生效(死端口测试会被代理拦截返回 200,须 env -u 或 NO_PROXY='*');grep 对部分 UTF-8 文件行为异常,优先用专用检索工具  
  
## 九、协作模式与文档体系(交接对象的行事规则)

  * **分工** :产品/规格/验证/文档归本席(AI 助手侧,产出 spec/ 与 docs/);编码执行归 Cursor(按 spec/ 规格书)。三份规格书(spec-feature-w3 / w3.1 / w4)是这一模式的完整范本:§1 行号级代码事实表 + 红线 + DoD 命令 + grep 断言。
  * **验证文化** :执行方报告一律不采信,逐条独立复跑;三份独立验证报告(06/07/08)即证据链,也是赛事「AI 可解释」验收标准的材料。
  * **单一事实源** :仓库 docs/(PARA:project 主体 + resources 资源 + archive 归档,README 总索引);FlowUs 是云端镜像(PARA:1 · 项目下);两处数字以仓库为准,改动先改仓库再同步 FlowUs。
  * **提交纪律** :文档与代码分离提交;commit message 用 conventional 前缀(docs(spec)/fix(core)/ci(eval) 等);不混入无关改动(工作区曾出现 release-pipeline.yml 遗留改动,单独处理)。
  * **许可红线** :仓库 Apache-2.0;ci/locomo/data/ 的 LoCoMo 派生切片是 CC BY-NC 4.0 —— 不可删 data/README.md 署名段、不可提交完整数据集。

交接结论

项目处于「可申报、可发版、可继续」状态:测试与 CI 全绿,PRD 四周里程碑全部落地,评测 4/5 达标且未达标项已有根因与改进路径。接手者最优先做的一件事是 **P0 赛事申报**(10-31 截止);其次是等用户指令发 v0.2.2;若追求更高名次,W5 检索融合改进是唯一有实测依据的技术加分方向。

交接文档版本 v1.0 ｜ 2026-10-01 13:30 ｜ 数字截至 commit c54b44b ｜ 云端镜像:FlowUs「临界微光」/ 1 · 项目 / moomem 容器页

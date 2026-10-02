# 收紧内部 pub 并改评测与黑盒测试

父任务：`10-02-core-logic-chain`。父任务决议 D4 划定了公开契约。本任务只把契约之外、今天仍是 `pub` 的符号收回包内，并改掉因此编不过的调用。不改 `MemoryStore` 的九个方法，不改快照格式，不改检索行为。

## Goal

宿主和其它包只能依赖 D4 的契约。分词、相似度、融合、索引、快照编解码、崩溃注入不再是库的公开面。评测包和黑盒测试改为走契约，或改成同包白盒测试。

## Confirmed facts

D4 的契约是：`MemoryStore` 九个方法；`Config`、`MemoryEntry`、`AddSummary`、`StoreStats`、`ForgetTarget`、`MoomemError` 及条目状态/种类；五个注入 trait 与缺省适配器；`MOOMEM_VERSION`、`SNAPSHOT_VERSION` 以及 `Config` 缺省常量。`ci/eval`、`ci/gates`、`ci/tools` 使用这些类型、trait 和 `MemoryBackend::new` 是在契约内。

契约外、且已有包外或黑盒调用的符号（2026-10-02）：

| 符号 | 调用方 |
|------|--------|
| `cosine_similarity`、`keyword_jaccard`、`tokenize` | `ci/eval/locomo/conflict_eval.mbt`；`src/extractor_test.mbt`；`src/persist_test.mbt`、`src/qa_adversarial_test.mbt` 也调用 `tokenize` |
| `entry_to_json`、`entry_from_json`、`parse_snapshot_text` | `src/types_test.mbt`、`src/qa_adversarial_test.mbt`、`src/persist_test.mbt` |
| `MemoryBackend::set_fail_next_save` | `src/persist_test.mbt` |

`src/*_test.mbt` 是黑盒测试，只能看见 `pub`。同包 `*_wbtest.mbt` 可以看见包内符号。因此收紧 `pub` 会同时打断评测包和这些黑盒测试，不只是 `conflict_eval.mbt`。

`MemoryBackend::set_simulate_partial_write` 与 `peek` 目前没有测试调用，但同样是崩溃注入，不属于契约。

## Requirements

- R1. 下列符号对其它包不可见：`tokenize`、`cosine_similarity`、`keyword_jaccard`、RRF 函数、`VectorIndex`、`KeywordIndex`、去重索引、快照行解析与 `entry_to_json` / `entry_from_json`、`MemoryBackend` 的 `peek` / `set_simulate_partial_write` / `set_fail_next_save`。
- R2. `ci/eval/locomo/conflict_eval.mbt` 不再调用上述符号。冲突评测仍通过 `MemoryStore::add` / 条目状态判断近重复是否 supersede。若它需要离线相似度数字，计算放在评测包内部，不从核心库再导出。
- R3. 黑盒测试改为只走契约，或把对内部符号的断言挪到 `*_wbtest.mbt`。不为了测试方便新增公开包装函数。
- R4. `MemoryStore` 九个方法、五个 trait、缺省适配器类型、快照字节布局保持不变。

## Acceptance Criteria

- [ ] `ci/` 与 `examples/` 不再引用 R1 列出的符号。
- [ ] `moon test` 在 native 上失败数为 0。黑盒测试不再依赖 R1 的符号。
- [ ] 宿主 README 上的九个方法签名不变。

## Out of scope

- 不改融合策略、不改 `SNAPSHOT_VERSION`、不改 `add` 内 supersede。
- 父任务已完成的版本号与 README 快照节不在本任务重写。

## Open questions

- 无。实现前仍要补 `design.md`：黑盒用例是改成白盒，还是改成只经 `MemoryStore` 断言。这是实现选择，不改变上面的验收。

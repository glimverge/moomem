# 收紧内部 pub

## 选择

直接断言分词、余弦、Jaccard、快照编解码的测试，从 `*_test.mbt` 挪到 `*_wbtest.mbt`。`MemoryBackend` 的崩溃注入只在 `persist.mbt` 的测试里调用，这样 `moon check` 不会把它们当成未使用函数。这些断言看的是实现，不是宿主契约。

仍在测宿主行为的黑盒测试留在 `*_test.mbt`。`qa_adversarial_test.mbt` 里导入用例改为手写 README 已公开的 JSON 字段，不再调用 `entry_to_json` / `tokenize`。

`ci/eval/locomo/conflict_eval.mbt` 的计分仍只看 `MemoryStore` 里旧条目是否 `Superseded`。打印用的 cos/jac 在评测包内计算，不从核心库导出。计分不依赖这份本地拷贝。

## 收回 `pub` 的符号

- `tokenize`、`cosine_similarity`、`keyword_jaccard`
- `entry_to_json`、`entry_from_json`、`parse_json_line`、`parse_snapshot_header`、`build_snapshot_text`、`parse_snapshot_text`、`SnapshotParseResult`
- `MemoryBackend::peek`、`set_simulate_partial_write`、`set_fail_next_save`

`VectorIndex`、`KeywordIndex`、`DedupIndex`、`rrf` 已经是包内符号，不动。

`MemoryBackend::new`、五个 trait、缺省适配器、`MemoryStore` 九个方法保持 `pub`。

# examples

零网络演示，不读 API Key。每条是一个可执行包，在 native 上跑：

```bash
moon run examples/<scene> --target native
```

数据写在 `/tmp/moomem-demo-*`。重跑会先清掉对应目录。

| 目录 | 用途 |
|------|------|
| `default-reopen` | 缺省配置：写入、召回、关掉再打开 |
| `host-inject-supersede` | 宿主注入嵌入和提取后，旧事实被覆盖 |
| `isolation-forget-import` | 用户隔离、遗忘、导出再导入 |

## default-reopen

不注入 `Embedder`、`Extractor`、`ConflictJudge`、`Clock`、`PersistenceBackend`。`MemoryStore::open(path)` 在 native 上使用 `FsBackend`，提取走 `RawExtractor`（条目 kind 为 `Unstructured`，`stats.extractor_mode` 为 `raw`）。

写入两条事实，再写一次相同内容，第二次记入 `duplicates`。`close` 之后用同一目录重新 `open`，召回结果还在。

## host-inject-supersede

宿主实现 `Embedder` 和 `Extractor`。`ConflictJudge` 留空，走缺省 `SimilarityJudge`。主题嵌入把「住 / 搬到」映到同一向量，余弦达到覆盖阈值后，旧住址变成 `Superseded`。

`recall` 只返回仍有效的条目。`list_entries` 仍能看到被覆盖的旧住址，供审计。`stats.extractor_mode` 为宿主提取器声明的 `host`。

## isolation-forget-import

两个用户各自 `add`。`recall` 只返回当前 `user_id` 的条目，不会带出另一个用户的记忆。

`forget(ById)` 把一条记忆标成 `Deleted`，`list_entries` 仍能列出它。`export_jsonl` 含这条已删除记录。导入到另一份存储后，再次导入会跳过已存在的行；已删除的内容不能被 `recall`，仍有效的内容可以。`forget(All)` 清掉某个用户全部可检索条目。

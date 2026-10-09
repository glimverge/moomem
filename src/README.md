# src/ — 核心库（包 `heyq02/moomem`）

本目录是 moomem 的核心实现包。**实现与测试同目录**，遵循 MoonBit 惯例：
测试文件与源文件放在同一个包里，`moon test` 扫描包内的 `*_test.mbt`（黑盒）与
`*_wbtest.mbt`（白盒）。这不是"测试乱放"，而是语言约定——测试必须和被测代码同包才能访问包内符号。

## 实现文件（17 个）

按职责分组：

### 基础定义
| 文件 | 职责 |
|------|------|
| `lib.mbt` | 常量：`MOOMEM_VERSION`、`SNAPSHOT_VERSION`、默认 `DEFAULT_DIM` 等版本与魔术值 |
| `types.mbt` | 核心类型：`MemoryEntry`、`Config`(L230)、`AddSummary`、`StoreStats`、`ConflictVerdict`、`MemoryStore` 内部状态 |
| `errors.mbt` | `MoomemError` 及 `Show` / `message` / `kind`，所有失败路径的统一错误类型 |

### 编解码
| 文件 | 职责 |
|------|------|
| `json_codec.mbt` | 快照 JSON 编码/解码、header 解析（全包唯一的 JSON 编解码入口） |

### 算法组件（trait + 缺省实现，可被宿主注入替换）
| 文件 | 职责 |
|------|------|
| `embedder.mbt` | `Embedder` trait + 缺省 `HashingEmbedder`（FNV-1a，确定性 256 维） |
| `extractor.mbt` | `Extractor` trait + 缺省 `RawExtractor`（原样入库） |
| `conflict.mbt` | `ConflictJudge` trait + 缺省 `SimilarityJudge`（余弦阈值 + 关键词 Jaccard） |
| `clock.mbt` | 逻辑时钟：`LogicalClock`（跨重启续接）、`FixedClock`（恒定） |

### 索引与检索
| 文件 | 职责 |
|------|------|
| `index_vector.mbt` | `VectorIndex`：按 `user_id` 分片的向量索引 |
| `index_keyword.mbt` | `KeywordIndex` + 分词（BM25 侧） |
| `ranker.mbt` | 检索融合：`EqualRrf`、`AdaptiveLexical`（词法强时偏向 BM25）、词法强命中判定 |
| `dedup.mbt` | `DedupIndex`：归一化内容指纹 + 按 `user_id` 分片去重 |

### 持久化
| 文件 | 职责 |
|------|------|
| `persist.mbt` | `#cfg(target="native")` 落 `FsBackend`（双槽 JSONL + `head` 崩溃恢复）；其它目标用 `MemoryBackend`（不落盘）。`default_backend` 按编译目标选择 |

### 存储入口（同一个 `MemoryStore`，按方法组拆成 4 个文件）
| 文件 | 职责 |
|------|------|
| `store.mbt` | `MemoryStore` 主结构、`open` / `close` / `stats` 入口与生命周期 |
| `store_add.mbt` | `add`：提取 → 去重 → 冲突裁决 → 覆盖/插入 |
| `store_recall.mbt` | `recall`：向量 + BM25 混合检索与融合排序 |
| `store_records.mbt` | 记录级操作：`forget` / `export_jsonl` / `import_jsonl` / `list_entries` |

`store*` 四个文件编译后仍是同一个 `MemoryStore` 类型，拆分只是为了按职责边界切分文件长度，不是独立模块。

## 测试文件（9 黑盒 + 8 白盒 = 17 个）

> **约定**：**黑盒** `*_test.mbt` 只通过 `pub` 契约验证行为；**白盒** `*_wbtest.mbt`
> 直接构造内部类型、调用包内私有 `fn`，覆盖实现细节。两者均与源文件同目录。

### 黑盒 `*_test.mbt`（验证宿主可见契约）
| 文件 | 测什么 | 对应实现 |
|------|--------|----------|
| `types_test.mbt` | 类型 `Show` / `is_recallable`、黑盒可构造的 `AddSummary` / `StoreStats` | `types.mbt` |
| `errors_test.mbt` | `MoomemError` 的 `message` / `kind` 分类 | `errors.mbt` |
| `clock_test.mbt` | `LogicalClock` 跨重启续接、`FixedClock` 恒定 | `clock.mbt` |
| `embedder_test.mbt` | `HashingEmbedder` 确定性、维度 | `embedder.mbt` |
| `extractor_test.mbt` | `RawExtractor` 原样直通、空白文本不入库 | `extractor.mbt` |
| `persist_test.mbt` | 双槽快照写/恢复、崩溃恢复边界（用 `MemoryBackend` 模拟，非真磁盘 IO） | `persist.mbt` |
| `config_test.mbt` | 缺省 `Config` 下的 add/recall、冲突候选窗口大小、检索/冲突参数 | `types.mbt` 里的 `Config`（无独立 `config.mbt`） |
| `store_test.mbt` | `MemoryStore` 主契约：add/recall 基础、supersede、用户隔离 | `store*.mbt` |
| `adversarial_test.mbt` | 黑盒补充：边缘/边界/状态机不变量（空库、top_k 边界、supersede 链、forget 重写、超长条目、去重分片、零命中不补齐、配置校验、时钟、user_id 边界、导入容错、close 后拒绝） | `store*.mbt` 补充 |

### 白盒 `*_wbtest.mbt`（验证内部符号，非宿主契约）
| 文件 | 测什么 | 对应实现 |
|------|--------|----------|
| `types_wbtest.mbt` | `Show` / `is_recallable`、黑盒不可构造的内部类型 | `types.mbt` |
| `embedder_wbtest.mbt` | `HashingEmbedder` 与余弦细节 | `embedder.mbt` |
| `index_keyword_wbtest.mbt` | 分词与 `KeywordIndex` | `index_keyword.mbt` |
| `index_vector_wbtest.mbt` | `VectorIndex` 分片隔离（跨用户不泄漏的索引层基础） | `index_vector.mbt` |
| `ranker_wbtest.mbt` | `Rrf` 融合、自适应 `AdaptiveLexical`、词法强命中 | `ranker.mbt` |
| `dedup_wbtest.mbt` | `DedupIndex` 归一化/分片 | `dedup.mbt` |
| `json_codec_wbtest.mbt` | JSON 编解码与快照解析内部路径 | `json_codec.mbt` |
| `conflict_wbtest.mbt` | `SimilarityJudge` 与关键词 Jaccard | `conflict.mbt` |

## 命名约定与"看似无对应实现"的解释

- 多数测试按「被测模块名 + `_test` / `_wbtest`」镜像命名。
- 两类**主题性**测试例外（没有同名实现文件，因为它们覆盖的是跨模块主题，而非单一模块）：
  - `config_test.mbt`：测 `Config`（检索/冲突参数），`Config` 是 `types.mbt` 里的一个 `pub(all) struct`，不单独成文件。
  - `adversarial_test.mbt`：测边界值与状态机不变量，是对 `store*.mbt` 契约的补充覆盖，不是独立模块。
- 测试辅助 struct 带前缀（`Adversarial*`、`Config*`、`Store*`）以避免同包符号冲突。

## 质量门

- `src/` 覆盖率须 ≥ 90%（CI 强制，`pnpm run cov:bisect` 低于即非零退出）。
- `moon test` 四后端（native ≥ 76 用例、wasm、wasm-gc、js）须全绿。

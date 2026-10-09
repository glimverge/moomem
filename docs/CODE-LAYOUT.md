# 代码布局（CODE-LAYOUT）

本文件说明整个仓库"哪里放什么"，重点澄清核心包 `src/` 的**实现与测试归属**。
包内细节见 [`src/README.md`](../src/README.md)。

## 顶层目录语义

| 目录 | 角色 | 实现 / 测试归属 |
|------|------|----------------|
| `src/` | **核心库**（包 `heyq02/moomem`）：实现 + 测试同目录 | 见 [`src/README.md`](../src/README.md) |
| `benchmark/` | 离线评测（LoCoMo 切片上的检索 / 冲突 / 提取 / 持久化评测） | 独立包；`main.mbt` 入口，`*_eval.mbt` 四类评测，`loader*.mbt` 数据加载，`report.mbt` / `util.mbt` 工具，`data/` 数据集。**不读 API Key、不调模型** |
| `examples/` | 三条零网络冒烟示例（各自 `moon.pkg`） | `default-reopen`（写入/召回/重开）、`host-inject-supersede`（注入后旧事实被覆盖）、`isolation-forget-import`（隔离/遗忘/导入导出） |
| `demo/` | **独立 MoonBit 模块**（`heyq02/demo`），依赖已发布到 mooncakes 的 `moomem`，**不是工作树** | 演示真实模型注入：Qwen 嵌入 + DeepSeek 提取；含 `demo_test.mbt` / `demo_wbtest.mbt` |
| `scripts/` | 发布脚本（如 `bump-version.sh` 同步版本号） | 非源码，CI 使用 |
| `docs/` | 项目治理与文档（本文件、STATUS / ROADMAP / CHANGELOG / DECISIONS、申报书） | 文档，非代码 |

## 核心包 `src/` 速览

- **实现文件 17 个**，按「基础 / 编解码 / 算法组件 / 索引检索 / 持久化 / 存储入口」分组。
- **测试文件 17 个**：9 黑盒（`*_test.mbt`，只测 `pub` 契约）+ 8 白盒（`*_wbtest.mbt`，测内部符号）。
- **测试与实现同目录**是 MoonBit 语言惯例（`moon test` 扫描包内测试文件），不是把测试"随便放"。
- 详细地图、每个测试文件测什么、命名约定见 [`src/README.md`](../src/README.md)。

## 常见困惑点

- `config_test.mbt` / `adversarial_test.mbt` **没有同名实现文件**——它们是**主题性测试**
  （`Config` 定义在 `types.mbt`；`adversarial` 是边界/不变量补充），不是漏了实现。
- `store` 拆成 `store` / `store_add` / `store_recall` / `store_records` 四个文件，是按
  `MemoryStore` 的方法组（生命周期 / 写入 / 检索 / 记录操作）拆分，编译后仍是同一个 `MemoryStore`。
- `benchmark/` 与 `demo/` 是**独立 MoonBit 包/模块**，不编译进 `src/`；改动 `src/` 不会自动影响 `demo/`（需先发版再更新依赖）。

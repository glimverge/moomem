# 快速上手

## 环境

- [moon](https://www.moonbitlang.com/) ≥ `0.1.20260920`（`moon version` 确认）

## 安装

已发布：[heyq02/moomem](https://mooncakes.io/docs/heyq02/moomem)。在宿主工程执行：

```bash
moon add heyq02/moomem
```
## 最短代码

```moonbit
fn main {
  let mem = @moomem.MemoryStore::open("./memory").unwrap()

  // 对话结束后写入：提取 → 去重 → 冲突 → 嵌入 → 双索引 → 落盘
  let summary = mem.add("user-42", "我对花生过敏").unwrap()
  println("extracted=\{summary.extracted} inserted=\{summary.inserted}")

  // LLM 调用前召回：混合检索，只返回该用户记忆
  let hits = mem.recall("user-42", "花生过敏", top_k=3).unwrap()
  for e in hits {
    println("[\{e.created_at}] \{e.content}")
  }

  ignore(mem.close())
}
```

次日再 `open` 同一目录：记忆完整，recall 行为一致。可选 LLM 提取见 [LLM 注入](/api/llm)。

## 零网络示例

```bash
moon run examples/basic-store --target native
moon run examples/llm-extractor --target native
moon run examples/conflict-supersede --target native
moon run examples/cli-smoke --target native
```

## 下一步

- [持久化](/guide/start/persistence) — 目录布局与条目状态
- [安全与限制](/guide/start/security)
- [公开 API](/api/) — MemoryStore 六方法与注入点
- [LLM 注入](/api/llm)
- [Benchmark](/benchmark/) — 评测分数与本地复跑

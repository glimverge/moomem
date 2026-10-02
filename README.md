# moomem

[![Version](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fglimverge%2Fmoomem%2Frefs%2Fheads%2Fmain%2Fmoon.mod&search=%5Eversion%5Cs%2A%3D%5Cs%2A%22%28%3FP%3Cversion%3E%5B%5E%22%5D%2B%29%22&replace=%24%3Cversion%3E&flags=m&label=version&logo=github)](https://github.com/glimverge/moomem/blob/main/moon.mod)
[![Coverage Status](https://coveralls.io/repos/github/glimverge/moomem/badge.svg?branch=main)](https://coveralls.io/github/glimverge/moomem?branch=main)
[![Docs](https://img.shields.io/badge/docs-mooncakes.io-green)](https://glimverge.github.io/moomem/)
[![License](https://img.shields.io/github/license/glimverge/moomem)](https://github.com/glimverge/moomem/blob/main/LICENSE)

> MoonBit 嵌入式 Agent 记忆层：零部署、崩溃可恢复、按用户隔离。

Agent 进程一结束就失忆。**moomem** 嵌在宿主进程里，不用单独起服务。native 上把记忆写进本地目录，关掉再打开还能 `recall`。wasm / js 缺省只留在进程内存里。

## 能力

- `open` / `add` / `recall` / `forget`，外加导入导出和统计
- 向量 + BM25 混合检索，索引按 `user_id` 分开，没有全库召回
- native 双槽 JSONL：写入中途崩溃，下次仍从上一份完整快照恢复
- 嵌入、提取、冲突判定都可以换成宿主自己的实现；缺省全部离线，不需要 API Key

## 上手

需要 [moon](https://www.moonbitlang.com/) ≥ `0.1.20260920`。已发布包：[heyq02/moomem](https://mooncakes.io/docs/heyq02/moomem)。

```bash
moon add heyq02/moomem
```

```moonbit
fn main {
  let mem = @moomem.MemoryStore::open("./memory").unwrap()

  let summary = mem.add("user-42", "我对花生过敏").unwrap()
  println("extracted=\{summary.extracted} inserted=\{summary.inserted}")

  let hits = mem.recall("user-42", "花生过敏", top_k=3).unwrap()
  for e in hits {
    println("[\{e.created_at}] \{e.content}")
  }

  ignore(mem.close())
}
```

native 上，同一目录再次 `open`，记忆还在，`recall` 结果一致。

> [!NOTE]
> 缺省实现不访问网络。要做语义提取或真实向量，在 `open` 时注入 `Embedder`、`Extractor`、`ConflictJudge`。

[`demo/`](demo/) 就是这样接的：Qwen 做嵌入，DeepSeek 做提取。复制 `demo/.env.example` 为 `demo/.env`，填上密钥后：

```bash
cd demo
moon run cmd/main
```

它会写入几条记忆、召回，再打开同一目录确认还在。闲聊不会入库。

## 示例

三条演示都不读密钥、不访问网络：

```bash
moon run examples/default-reopen --target native
```

| 示例 | 看什么 |
|------|--------|
| `examples/default-reopen` | 写入、召回、关掉再打开 |
| `examples/host-inject-supersede` | 注入嵌入和提取后，旧事实被覆盖 |
| `examples/isolation-forget-import` | 用户隔离、遗忘、导出再导入 |

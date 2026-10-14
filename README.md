# moomem

<p>
  <a href="https://github.com/glimverge/moomem/blob/main/moon.mod"><img src="https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fglimverge%2Fmoomem%2Frefs%2Fheads%2Fmain%2Fmoon.mod&search=%5Eversion%5Cs%2A%3D%5Cs%2A%22%28%3FP%3Cversion%3E%5B%5E%22%5D%2B%29%22&replace=%24%3Cversion%3E&flags=m&label=version&style=flat-square&colorA=564341&colorB=EDED91" alt="version" /></a>
  <a href="https://coveralls.io/github/glimverge/moomem?branch=main"><img src="https://img.shields.io/coverallsCoverage/github/glimverge/moomem?branch=main&style=flat-square&colorA=564341&colorB=EDED91" alt="coverage" /></a>
  <a href="https://mooncakes.io/docs/heyq02/moomem/"><img src="https://img.shields.io/badge/docs-mooncakes.io-EDED91?style=flat-square&colorA=564341&colorB=EDED91" alt="docs" /></a>
  <a href="https://github.com/glimverge/moomem/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square&colorA=564341&colorB=EDED91" alt="license" /></a>
</p>

MoonBit 嵌入式 Agent 记忆层。嵌在宿主进程里，按 `user_id` 做向量 + BM25 检索。native 上写入双槽 JSONL，崩溃后仍从上一份完整快照恢复。缺省离线，不需要 API Key。

## 上手

需要 [moon](https://www.moonbitlang.com/) ≥ `0.1.20260920`。

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

同一目录再次 `open`，记忆还在。wasm / js 缺省只留在进程内存里。要换真实模型，在 `open` 时注入 `Embedder`、`Extractor`、`ConflictJudge`。[`playground/`](playground/) 用 Qwen 做嵌入、DeepSeek 做提取。

native 上 `open("./memory")` 会写成 `<path>/moomem/head` 加两个 `slot*.jsonl`。先把整份快照写入非当前槽，成功后再拨 `head`。索引不落盘，`open` 时从快照重建。

## 示例

都不读密钥、不访问网络：

```bash
moon run examples/default-reopen --target native
moon run examples/host-inject-supersede --target native
moon run examples/isolation-forget-import --target native
```

## 开发

```bash
moon check --target native
moon test --target native
pnpm run format
pnpm release
```

`pnpm release` 用 [`bumpp`](https://github.com/antfu-collective/bumpp) 同步 `package.json`、`moon.mod` 和 `MOOMEM_VERSION`，打 `v*` 标签后由 [release.yaml](.github/workflows/release.yaml) 发布到 mooncakes.io。代码布局见 [`src/README.md`](src/README.md)。

## License

<!-- automd:contributors license=MIT author="heyq02" github="glimverge/moomem" -->

Published under the [MIT](https://github.com/glimverge/moomem/blob/main/LICENSE) license.
Made by [@heyq02](https://github.com/heyq02) and [community](https://github.com/glimverge/moomem/graphs/contributors) 💛
<br><br>
<a href="https://github.com/glimverge/moomem/graphs/contributors">
<img src="https://contrib.rocks/image?repo=glimverge/moomem" />
</a>

<!-- /automd -->

<!-- automd:with-automd -->

---

_🤖 auto updated with [automd](https://automd.unjs.io)_

<!-- /automd -->

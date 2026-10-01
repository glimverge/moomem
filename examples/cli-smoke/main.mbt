// moomem E2 示例：库用法对齐常见 CLI 场景（add / recall / list / stats / forget）。
//
// 运行（零网络，MemoryBackend；不启动 CLI 二进制、无密钥）：
//   moon run examples/cli-smoke --target native
//
// 断言以 `src/cli/cli_wbtest` 为准；本包偏可读教学编排。

///|
fn default_cfg(backend : &@src.PersistenceBackend) -> @src.Config {
  @src.Config::{
    embedder: None,
    extractor: None,
    judge: None,
    persistence: Some(backend),
    clock: None,
    dim: @src.DEFAULT_DIM,
    rrf_k: @src.DEFAULT_RRF_K,
    recall_candidates: 0,
    supersede_threshold: @src.DEFAULT_SUPERSEDE_THRESHOLD,
    conflict_candidates: @src.CONFLICT_CANDIDATES,
    coexist_band: @src.COEXIST_BAND,
    backfill: @src.RecallBackfill::BackfillRecency,
  }
}

///|
fn main {
  println("=== moomem E2: cli-smoke（库侧镜像 CLI 流程，零网络） ===")
  println("")
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  // 等价：moomem add --db … --user user-42 --text …
  let store = match @src.MemoryStore::open(
    "memory://cli-smoke",
    config=default_cfg(backend),
  ) {
    Ok(s) => s
    Err(e) => {
      println("open failed: \{e.message()}")
      return
    }
  }
  println("# moomem add --user user-42 --text '我对花生过敏'")
  match store.add("user-42", "我对花生过敏") {
    Ok(s) => println("  inserted=\{s.inserted}")
    Err(e) => println("  error: \{e.message()}")
  }
  println("# moomem add --user user-42 --text '我喜欢清淡的粤菜'")
  match store.add("user-42", "我喜欢清淡的粤菜") {
    Ok(s) => println("  inserted=\{s.inserted}")
    Err(e) => println("  error: \{e.message()}")
  }
  // 等价：moomem recall --user user-42 --query …
  println("# moomem recall --user user-42 --query '花生过敏'")
  match store.recall("user-42", "花生过敏", top_k=5) {
    Ok(hits) =>
      for h in hits {
        println("  [\{h.kind}] \{h.content}")
      }
    Err(e) => println("  error: \{e.message()}")
  }
  // 等价：moomem list --user user-42 --all
  println("# moomem list --user user-42 --all")
  match store.list_entries("user-42") {
    Ok(entries) =>
      for e in entries {
        println("  [\{e.status}] \{e.id} | \{e.content}")
      }
    Err(e) => println("  error: \{e.message()}")
  }
  // 等价：moomem stats --db …
  println("# moomem stats")
  match store.stats() {
    Ok(st) =>
      println(
        "  total=\{st.total} active=\{st.active} deleted=\{st.deleted} extractor=\{st.extractor_mode}",
      )
    Err(e) => println("  error: \{e.message()}")
  }
  // 等价：按 id forget（教学：删第一条）
  match store.list_entries("user-42") {
    Ok(entries) =>
      if entries.length() > 0 {
        let id = entries[0].id
        println("# forget ById(\{id})")
        match store.forget("user-42", @src.ForgetTarget::ById(id)) {
          Ok(n) => println("  removed=\{n}")
          Err(e) => println("  error: \{e.message()}")
        }
      }
    Err(_) => ()
  }
  println("# moomem list --user user-42 --all（forget 后）")
  match store.list_entries("user-42") {
    Ok(entries) =>
      for e in entries {
        println("  [\{e.status}] \{e.id} | \{e.content}")
      }
    Err(e) => println("  error: \{e.message()}")
  }
  ignore(store.close())
  println("")
  println("=== 演示结束（断言见 cli_wbtest） ===")
}

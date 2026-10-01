// moomem E2 示例：无 LLM 主路径（open → add → recall → forget → export）。
//
// 运行（零网络，MemoryBackend）：
//   moon run examples/basic-store --target native

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
  println("=== moomem E2: basic-store（缺省 raw 提取，零网络） ===")
  println("")
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let store = match @src.MemoryStore::open(
    "memory://basic-store",
    config=default_cfg(backend),
  ) {
    Ok(s) => s
    Err(e) => {
      println("open failed: \{e.message()}")
      return
    }
  }
  // 1) add
  println("[add] 我对花生过敏")
  match store.add("user-42", "我对花生过敏") {
    Ok(s) =>
      println(
        "  -> extracted=\{s.extracted} inserted=\{s.inserted} degraded=\{s.degraded}",
      )
    Err(e) => println("  -> error: \{e.message()}")
  }
  println("[add] 我喜欢清淡的粤菜")
  match store.add("user-42", "我喜欢清淡的粤菜") {
    Ok(s) => println("  -> extracted=\{s.extracted} inserted=\{s.inserted}")
    Err(e) => println("  -> error: \{e.message()}")
  }
  // 2) recall
  println("[recall] 查询「花生过敏」")
  match store.recall("user-42", "花生过敏") {
    Ok(hits) =>
      for h in hits {
        println("  -> [\{h.status}] \{h.content}")
      }
    Err(e) => println("  -> error: \{e.message()}")
  }
  // 3) forget by id（软删除第一条命中）
  match store.list_entries("user-42") {
    Ok(entries) =>
      if entries.length() > 0 {
        let target = entries[0].id
        println("[forget] ById(\{target})")
        match store.forget("user-42", @src.ForgetTarget::ById(target)) {
          Ok(n) => println("  -> removed=\{n}")
          Err(e) => println("  -> error: \{e.message()}")
        }
      }
    Err(e) => println("[list] error: \{e.message()}")
  }
  // 4) export
  println("[export] JSONL 预览")
  match store.export_jsonl() {
    Ok(text) => {
      let mut lines = 0
      for line in text.split("\n") {
        if line.trim().length() > 0 {
          lines = lines + 1
          if lines <= 2 {
            println("  \{line}")
          }
        }
      }
      println("  -> \{lines} line(s)")
    }
    Err(e) => println("  -> error: \{e.message()}")
  }
  ignore(store.close())
  println("")
  println("=== 演示结束 ===")
}

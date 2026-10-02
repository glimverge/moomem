// moomem E2 示例：库侧走一遍 add / recall / list / stats / forget。
//
// 运行（零网络，MemoryBackend；无密钥）：
//   moon run examples/cli-smoke --target native

///|
fn default_cfg(backend : &@src.PersistenceBackend) -> @src.Config {
  @src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
  }
}

///|
fn main {
  println("=== moomem E2: cli-smoke（add / recall / list，零网络） ===")
  println("")
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  // add --user user-42
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
  println("# add user-42: 我对花生过敏")
  match store.add("user-42", "我对花生过敏") {
    Ok(s) => println("  inserted=\{s.inserted}")
    Err(e) => println("  error: \{e.message()}")
  }
  println("# add user-42: 我喜欢清淡的粤菜")
  match store.add("user-42", "我喜欢清淡的粤菜") {
    Ok(s) => println("  inserted=\{s.inserted}")
    Err(e) => println("  error: \{e.message()}")
  }
  println("# recall user-42: 花生过敏")
  match store.recall("user-42", "花生过敏", top_k=5) {
    Ok(hits) =>
      for h in hits {
        println("  [\{h.kind}] \{h.content}")
      }
    Err(e) => println("  error: \{e.message()}")
  }
  println("# list user-42")
  match store.list_entries("user-42") {
    Ok(entries) =>
      for e in entries {
        println("  [\{e.status}] \{e.id} | \{e.content}")
      }
    Err(e) => println("  error: \{e.message()}")
  }
  println("# stats")
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
  println("# list user-42（forget 后）")
  match store.list_entries("user-42") {
    Ok(entries) =>
      for e in entries {
        println("  [\{e.status}] \{e.id} | \{e.content}")
      }
    Err(e) => println("  error: \{e.message()}")
  }
  ignore(store.close())
  println("")
  println("=== 演示结束 ===")
}

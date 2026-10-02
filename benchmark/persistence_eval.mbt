// Persistence reopen consistency + cross-user isolation aggregate checks.

///|
fn run_isolation_eval(data : LocomoSubset) -> Int {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let judge : &@src.ConflictJudge = NoConflictJudge::{ }
  let cfg = @src.Config::{
    ..@src.Config::default(),
    judge: Some(judge),
    persistence: Some(backend),
  }
  let store = match @src.MemoryStore::open("memory://locomo-iso", config=cfg) {
    Ok(s) => s
    Err(e) => fail("open iso store: \{e.message()}")
  }
  for conv in data.conversations {
    for t in conv.turns {
      ignore(store.add(conv.sample_id, t.text))
    }
  }
  let mut leaks = 0
  if data.conversations.length() >= 2 {
    let a = data.conversations[0]
    let b = data.conversations[1]
    let mut n = 0
    for q in a.qa {
      if q.category != 5 && n < 8 {
        n = n + 1
        let hits = match store.recall(a.sample_id, q.question, top_k=5) {
          Ok(h) => h
          Err(e) => fail("iso recall a: \{e.message()}")
        }
        for h in hits {
          if h.user_id != a.sample_id {
            leaks = leaks + 1
          }
        }
      }
    }
    n = 0
    for q in b.qa {
      if q.category != 5 && n < 8 {
        n = n + 1
        let hits = match store.recall(b.sample_id, q.question, top_k=5) {
          Ok(h) => h
          Err(e) => fail("iso recall b: \{e.message()}")
        }
        for h in hits {
          if h.user_id != b.sample_id {
            leaks = leaks + 1
          }
        }
      }
    }
  }
  ignore(store.close())
  println("### Isolation")
  println("")
  println("| metric | value |")
  println("|---|---|")
  println("| cross-user leaks | \{leaks} |")
  println("")
  leaks
}

///|
fn cleanup_dir(dir : String) -> Unit {
  if @fs.path_exists(dir) {
    @fs.remove_file("\{dir}/moomem/slot0.jsonl") catch { _ => () }
    @fs.remove_file("\{dir}/moomem/slot1.jsonl") catch { _ => () }
    @fs.remove_file("\{dir}/moomem/head") catch { _ => () }
    @fs.remove_dir("\{dir}/moomem") catch { _ => () }
    @fs.remove_dir(dir) catch { _ => () }
  }
}

///|
fn run_persistence_eval() -> Int {
  let dir = "tmp_moomem_locomo_persist"
  cleanup_dir(dir)
  let facts = [
    "我对花生过敏",
    "我住在北京海淀区",
    "偏好清淡粤菜",
  ]
  let store1 = match @src.MemoryStore::open(dir) {
    Ok(s) => s
    Err(e) => fail("persist open1: \{e.message()}")
  }
  for f in facts {
    ignore(store1.add("persist-user", f))
  }
  let before = match store1.recall("persist-user", "花生过敏", top_k=5) {
    Ok(h) => h
    Err(e) => fail("persist recall1: \{e.message()}")
  }
  let ids1 : Array[String] = []
  for e in before {
    ids1.push(e.id)
  }
  ignore(store1.close())
  let store2 = match @src.MemoryStore::open(dir) {
    Ok(s) => s
    Err(e) => fail("persist open2: \{e.message()}")
  }
  let after = match store2.recall("persist-user", "花生过敏", top_k=5) {
    Ok(h) => h
    Err(e) => fail("persist recall2: \{e.message()}")
  }
  let ids2 : Array[String] = []
  for e in after {
    ids2.push(e.id)
  }
  ignore(store2.close())
  cleanup_dir(dir)
  let mut ok = 1
  if ids1.length() != ids2.length() {
    ok = 0
  } else {
    for id in ids1 {
      if !ids2.contains(id) {
        ok = 0
      }
    }
  }
  println("### Persistence reopen")
  println("")
  println("| metric | value |")
  println("|---|---|")
  println("| reopen id-set consistent | \{ok}/1 |")
  println("")
  ok
}

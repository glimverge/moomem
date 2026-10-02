// 缺省宿主路径：不注入 Embedder / Extractor / ConflictJudge / Clock / PersistenceBackend。
// native 上 open(path) 使用 FsBackend。关掉再打开同一目录，召回结果还在。
//
//   moon run examples/default-reopen --target native

///|
fn reset_dir(dir : String) -> Unit {
  if @fs.path_exists(dir) {
    @fs.remove_file("\{dir}/moomem/slot0.jsonl") catch { _ => () }
    @fs.remove_file("\{dir}/moomem/slot1.jsonl") catch { _ => () }
    @fs.remove_file("\{dir}/moomem/head") catch { _ => () }
    @fs.remove_dir("\{dir}/moomem") catch { _ => () }
    @fs.remove_dir(dir) catch { _ => () }
  }
}

///|
fn open_store(dir : String) -> @src.MemoryStore {
  match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(e) => {
      println("open failed: \{e.message()}")
      abort("open failed")
    }
  }
}

///|
fn add_text(store : @src.MemoryStore, text : String) -> @src.AddSummary {
  println("[add] \{text}")
  match store.add("user-42", text) {
    Ok(summary) => {
      println(
        "  extracted=\{summary.extracted} inserted=\{summary.inserted} duplicates=\{summary.duplicates} superseded=\{summary.superseded} degraded=\{summary.degraded}",
      )
      summary
    }
    Err(e) => {
      println("  error: \{e.message()}")
      abort("add failed")
    }
  }
}

///|
fn print_recall(store : @src.MemoryStore, query : String) -> Unit {
  println("[recall] \{query}")
  match store.recall("user-42", query, top_k=3) {
    Ok(hits) =>
      for hit in hits {
        println("  [\{hit.status}] \{hit.kind} \{hit.content}")
      }
    Err(e) => {
      println("  error: \{e.message()}")
      abort("recall failed")
    }
  }
}

///|
fn main {
  println(
    "=== default-reopen  moomem \{@src.MOOMEM_VERSION}  snapshot \{@src.SNAPSHOT_VERSION} ===",
  )
  println("缺省 Config：RawExtractor + HashingEmbedder + SimilarityJudge + FsBackend")
  println("")
  let dir = "/tmp/moomem-demo-default-reopen"
  reset_dir(dir)
  let store = open_store(dir)
  let first = add_text(store, "我对花生过敏")
  if first.inserted != 1 {
    abort("expected the first fact to insert")
  }
  ignore(add_text(store, "我喜欢清淡的粤菜"))
  let again = add_text(store, "我对花生过敏")
  if again.duplicates != 1 {
    abort("expected the repeated fact to count as a duplicate")
  }
  print_recall(store, "花生过敏")
  match store.stats() {
    Ok(stats) =>
      println(
        "[stats] total=\{stats.total} active=\{stats.active} extractor=\{stats.extractor_mode}",
      )
    Err(e) => {
      println("[stats] error: \{e.message()}")
      abort("stats failed")
    }
  }
  match store.close() {
    Ok(_) => ()
    Err(e) => {
      println("close failed: \{e.message()}")
      abort("close failed")
    }
  }
  println("[reopen] \{dir}")
  let restored = open_store(dir)
  print_recall(restored, "花生过敏")
  ignore(restored.close())
  println("")
  println("=== 演示结束 ===")
}

// 同一聚合根上的隔离、遗忘、导出、导入。
// recall / list / forget 都带 user_id；导出含 Deleted，导入后召回仍跳过它。
//
//   moon run examples/isolation-forget-import --target native

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
fn print_recall(store : @src.MemoryStore, user_id : String, query : String) -> Unit {
  println("[recall] \{user_id} / \{query}")
  match store.recall(user_id, query, top_k=3) {
    Ok(hits) => {
      if hits.length() == 0 {
        println("  (无命中)")
      }
      for hit in hits {
        if hit.user_id != user_id {
          abort("recall leaked another user's entry")
        }
        println("  \{hit.user_id} [\{hit.status}] \{hit.content}")
      }
    }
    Err(e) => {
      println("  error: \{e.message()}")
      abort("recall failed")
    }
  }
}

///|
fn main {
  println("=== isolation-forget-import  用户隔离 / forget / export_jsonl / import_jsonl ===")
  println("")
  let source_dir = "/tmp/moomem-demo-isolation-forget-import"
  let copy_dir = "/tmp/moomem-demo-isolation-forget-import-copy"
  reset_dir(source_dir)
  reset_dir(copy_dir)
  let store = open_store(source_dir)
  match store.add("user-42", "我对花生过敏") {
    Ok(_) => println("[add] user-42 我对花生过敏")
    Err(e) => {
      println("add failed: \{e.message()}")
      abort("add failed")
    }
  }
  match store.add("user-42", "我喜欢清淡的粤菜") {
    Ok(_) => println("[add] user-42 我喜欢清淡的粤菜")
    Err(e) => {
      println("add failed: \{e.message()}")
      abort("add failed")
    }
  }
  match store.add("user-7", "我住在上海") {
    Ok(_) => println("[add] user-7 我住在上海")
    Err(e) => {
      println("add failed: \{e.message()}")
      abort("add failed")
    }
  }
  print_recall(store, "user-42", "花生")
  print_recall(store, "user-7", "花生")
  let allergy_id = match store.list_entries("user-42") {
    Ok(entries) => {
      let mut found = ""
      for entry in entries {
        if entry.content.contains("花生") {
          found = entry.id
        }
      }
      if found.length() == 0 {
        abort("missing allergy entry")
      }
      found
    }
    Err(e) => {
      println("list failed: \{e.message()}")
      abort("list failed")
    }
  }
  println("[forget] ById(\{allergy_id})")
  match store.forget("user-42", @src.ForgetTarget::ById(allergy_id)) {
    Ok(removed) => println("  removed=\{removed}")
    Err(e) => {
      println("  error: \{e.message()}")
      abort("forget failed")
    }
  }
  println("[list] user-42（Deleted 仍在）")
  match store.list_entries("user-42") {
    Ok(entries) =>
      for entry in entries {
        println("  [\{entry.status}] \{entry.content}")
      }
    Err(e) => {
      println("  error: \{e.message()}")
      abort("list failed")
    }
  }
  let exported = match store.export_jsonl() {
    Ok(text) => {
      let mut lines = 0
      for line in text.split("\n") {
        if line.trim().length() > 0 {
          lines = lines + 1
        }
      }
      println("[export] \{lines} JSONL line(s), including Deleted")
      text
    }
    Err(e) => {
      println("export failed: \{e.message()}")
      abort("export failed")
    }
  }
  ignore(store.close())
  let copy = open_store(copy_dir)
  match copy.import_jsonl(exported) {
    Ok((imported, skipped)) => println("[import] imported=\{imported} skipped=\{skipped}")
    Err(e) => {
      println("import failed: \{e.message()}")
      abort("import failed")
    }
  }
  match copy.import_jsonl(exported) {
    Ok((imported, skipped)) =>
      println("[import] again imported=\{imported} skipped=\{skipped}")
    Err(e) => {
      println("import failed: \{e.message()}")
      abort("import failed")
    }
  }
  println("[recall] copy / user-42 / 粤菜（导入后仍可召回）")
  match copy.recall("user-42", "粤菜", top_k=3) {
    Ok(hits) => {
      let mut found = false
      for hit in hits {
        if hit.content.contains("花生") {
          abort("deleted allergy was recalled")
        }
        if hit.content.contains("粤菜") {
          found = true
        }
        println("  [\{hit.status}] \{hit.content}")
      }
      if !found {
        abort("imported active fact was not recalled")
      }
    }
    Err(e) => {
      println("  error: \{e.message()}")
      abort("recall failed")
    }
  }
  println("[forget] user-7 All")
  match copy.forget("user-7", @src.ForgetTarget::All) {
    Ok(removed) => println("  removed=\{removed}")
    Err(e) => {
      println("  error: \{e.message()}")
      abort("forget all failed")
    }
  }
  match copy.stats() {
    Ok(stats) =>
      println(
        "[stats] total=\{stats.total} active=\{stats.active} deleted=\{stats.deleted}",
      )
    Err(e) => {
      println("[stats] error: \{e.message()}")
      abort("stats failed")
    }
  }
  ignore(copy.close())
  println("")
  println("=== 演示结束 ===")
}

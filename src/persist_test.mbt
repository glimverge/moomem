// 黑盒测试：双槽快照、崩溃恢复、后端抽象。
// 崩溃注入优先用 MemoryBackend；
// native 下的 FsBackend 走真实磁盘，用 #cfg(target="native") 隔离
//（wasm/js 缺省后端为 MemoryBackend，无本地文件系统）。

///|
test "MemoryBackend: save / load roundtrip" {
  let backend = @src.MemoryBackend::new()
  // 空库
  let empty = match backend.load() {
    Ok(v) => v
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(empty == None, content="true")
  // 保存后可读回
  let save_ok = match backend.save("{\"v\":1,\"gen\":1,\"clock\":0}") {
    Ok(_) => true
    Err(_) => false
  }
  inspect(save_ok, content="true")
  let loaded = match backend.load() {
    Ok(v) => v
    Err(_) => {
      inspect("load failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(loaded == Some("{\"v\":1,\"gen\":1,\"clock\":0}"), content="true")
}

///|
#cfg(target="native")
test "FsBackend via store: write, reopen, consistent" {
  let dir = "tmp_moomem_persist_test/db-basic"
  let cleanup = fn() {
    if @fs.path_exists(dir) {
      @fs.remove_file("\{dir}/moomem/slot0.jsonl") catch {
        _ => ()
      }
      @fs.remove_file("\{dir}/moomem/slot1.jsonl") catch {
        _ => ()
      }
      @fs.remove_file("\{dir}/moomem/head") catch {
        _ => ()
      }
      @fs.remove_dir("\{dir}/moomem") catch {
        _ => ()
      }
      @fs.remove_dir(dir) catch {
        _ => ()
      }
    }
  }
  cleanup()
  // 第一次打开：目录不存在则创建
  let store1 = match @src.MemoryStore::open(dir) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let s1 = match store1.add("user-42", "我对花生过敏") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s1.inserted, content="1")
  let close_ok = match store1.close() {
    Ok(_) => true
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      false
    }
  }
  inspect(close_ok, content="true")
  // 快照文件与 head 已落盘
  inspect(@fs.path_exists("\{dir}/moomem/head"), content="true")
  // 重新打开同一目录：记忆完整恢复
  let store2 = match @src.MemoryStore::open(dir) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let recalled = match store2.recall("user-42", "花生过敏") {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(recalled.length(), content="1")
  inspect(recalled[0].content, content="我对花生过敏")
  let st = match store2.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="1")
  ignore(store2.close())
  cleanup()
}

///|
#cfg(target="native")
test "FsBackend: corrupted head falls back to larger-gen slot" {
  let dir = "tmp_moomem_persist_test/db-head"
  let cleanup = fn() {
    if @fs.path_exists(dir) {
      @fs.remove_file("\{dir}/moomem/slot0.jsonl") catch {
        _ => ()
      }
      @fs.remove_file("\{dir}/moomem/slot1.jsonl") catch {
        _ => ()
      }
      @fs.remove_file("\{dir}/moomem/head") catch {
        _ => ()
      }
      @fs.remove_dir("\{dir}/moomem") catch {
        _ => ()
      }
      @fs.remove_dir(dir) catch {
        _ => ()
      }
    }
  }
  cleanup()
  // 写入两代快照：v1 只有 entry-a；v2 有 entry-a + entry-b
  let store1 = match @src.MemoryStore::open(dir) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store1.add("user-42", "第一代记忆"))
  ignore(store1.close())
  let store2 = match @src.MemoryStore::open(dir) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store2.add("user-42", "第二代新记忆"))
  ignore(store2.close())
  // 破坏 head（模拟写 head 中途崩溃）
  @fs.write_string_to_file("\{dir}/moomem/head", "")
  // 重新打开：head 损坏 → 取能解析且 gen 更大的槽 → 两代记忆都在
  let store3 = match @src.MemoryStore::open(dir) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let st = match store3.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="2")
  let recalled = match store3.recall("user-42", "第二代新记忆") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(recalled.length() >= 1, content="true")
  inspect(recalled[0].content, content="第二代新记忆")
  ignore(store3.close())
  cleanup()
}

///|
#cfg(target="native")
test "FsBackend: snapshot tail corruption recovered on reopen" {
  let dir = "tmp_moomem_persist_test/db-truncate"
  let cleanup = fn() {
    if @fs.path_exists(dir) {
      @fs.remove_file("\{dir}/moomem/slot0.jsonl") catch {
        _ => ()
      }
      @fs.remove_file("\{dir}/moomem/slot1.jsonl") catch {
        _ => ()
      }
      @fs.remove_file("\{dir}/moomem/head") catch {
        _ => ()
      }
      @fs.remove_dir("\{dir}/moomem") catch {
        _ => ()
      }
      @fs.remove_dir(dir) catch {
        _ => ()
      }
    }
  }
  cleanup()
  let store1 = match @src.MemoryStore::open(dir) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store1.add("user-42", "完整记忆一"))
  ignore(store1.add("user-42", "完整记忆二"))
  ignore(store1.add("user-42", "将被截断的记忆"))
  ignore(store1.close())
  // 找到 head 指向的槽并截断尾部（模拟进程被杀的半写）
  let head = @fs.read_file_to_string("\{dir}/moomem/head")
  let slot_file = "\{dir}/moomem/slot\{head}.jsonl"
  let content = @fs.read_file_to_string(slot_file)
  @fs.write_string_to_file(
    slot_file,
    content[:content.length() - 12].to_owned(),
  )
  // 重新打开：尾部半行丢弃并计数
  let store2 = match @src.MemoryStore::open(dir) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let st = match store2.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.truncated_recovered, content="1")
  inspect(st.total, content="2")
  ignore(store2.close())
  cleanup()
}

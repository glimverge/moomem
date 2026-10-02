// MemoryStore 的 forget、导出、导入、列举。仍是同一个聚合根上的方法。

// ---------------------------------------------------------------------------
// forget：软删除
// ---------------------------------------------------------------------------

///|
/// 软删除：状态置 Deleted，索引摘除，快照保留标记。
/// ById 返回 1/0（目标不存在或不可检索时报 InvalidOperation / 0）；
/// All 删除该 user 全部可检索条目并返回条数。
pub fn MemoryStore::forget(
  self : MemoryStore,
  user_id : String,
  target : ForgetTarget,
) -> Result[Int, MoomemError] {
  if self.closed {
    return Err(MoomemError::InvalidOperation("store is closed"))
  }
  match validate_user_id(user_id) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let mut removed = 0
  match target {
    ById(id) =>
      match self.entries.get(id) {
        Some(e) => {
          if e.user_id != user_id {
            return Err(
              MoomemError::InvalidOperation(
                "entry '\{id}' does not belong to user '\{user_id}'",
              ),
            )
          }
          if e.is_recallable() {
            self.deindex_entry(e)
            e.status = Deleted
            removed = 1
          }
        }
        None =>
          return Err(MoomemError::InvalidOperation("no such entry '\{id}'"))
      }
    All =>
      match self.by_user.get(user_id) {
        Some(ids) =>
          for id in ids {
            match self.entries.get(id) {
              Some(e) =>
                if e.is_recallable() {
                  self.deindex_entry(e)
                  e.status = Deleted
                  removed = removed + 1
                }
              None => ()
            }
          }
        None => ()
      }
  }
  if removed > 0 {
    match self.flush() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  Ok(removed)
}

// ---------------------------------------------------------------------------
// 导入导出
// ---------------------------------------------------------------------------

///|
/// 全量导出为 JSONL 文本：每行一条 entry 的 JSON，含全部状态（可审计）。
/// 按 seq 升序；不包含快照 header。
pub fn MemoryStore::export_jsonl(
  self : MemoryStore,
) -> Result[String, MoomemError] {
  if self.closed {
    return Err(MoomemError::InvalidOperation("store is closed"))
  }
  let all : Array[MemoryEntry] = []
  for kv in self.entries.iter() {
    all.push(kv.1)
  }
  all.sort_by((a, b) => a.seq - b.seq)
  let buf = StringBuilder()
  for e in all {
    buf.write_string(entry_to_json(e).stringify())
    buf.write_char('\n')
  }
  Ok(buf.to_string())
}

///|
/// 从 JSONL 文本导入。导出再导入后，可召回内容等价。
/// 跳过 id 已存在或同 user 内容指纹重复的条目；返回 (导入数, 跳过数)。
/// 恢复条目的状态、双索引与计数器均按导出时语义重建。
pub fn MemoryStore::import_jsonl(
  self : MemoryStore,
  jsonl : String,
) -> Result[(Int, Int), MoomemError] {
  if self.closed {
    return Err(MoomemError::InvalidOperation("store is closed"))
  }
  let imported : Array[MemoryEntry] = []
  let mut skipped = 0
  for raw in jsonl.split("\n") {
    let line = raw.trim().to_owned()
    if line.length() == 0 {
      continue
    }
    match parse_json_line(line) {
      Ok(j) =>
        match entry_from_json(j) {
          Ok(e) =>
            // user_id 校验是所有入库入口的强制关卡，
            // 导入也不例外——非法 user_id（路径穿越/空串/超长/非法字符）的
            // 条目不得进入记忆库，逐行跳过并计入 skipped（导入容错语义）。
            match validate_user_id(e.user_id) {
              Err(_) => skipped = skipped + 1
              Ok(_) =>
                if self.entries.contains(e.id) {
                  skipped = skipped + 1
                } else {
                  match self.dedup.lookup(e.user_id, e.content) {
                    Some(_) => skipped = skipped + 1
                    None => imported.push(e)
                  }
                }
            }
          Err(_) => skipped = skipped + 1 // 损坏行跳过（导入容错）
        }
      Err(_) => skipped = skipped + 1
    }
  }
  for e in imported {
    self.entries.set(e.id, e)
    match self.by_user.get(e.user_id) {
      Some(arr) => arr.push(e.id)
      None => self.by_user.set(e.user_id, [e.id])
    }
    if e.is_recallable() {
      self.index_entry(e)
    }
    if e.seq >= self.next_seq {
      self.next_seq = e.seq + 1
    }
    if e.created_at > self.clock_high {
      self.clock_high = e.created_at
    }
  }
  if imported.length() > 0 {
    match self.flush() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  Ok((imported.length(), skipped))
}

// ---------------------------------------------------------------------------
// list（仅枚举指定 user 的条目，保持隔离不变量）
// ---------------------------------------------------------------------------

///|
/// 枚举某 user 的全部条目（含 Superseded / Deleted，供审计）。
pub fn MemoryStore::list_entries(
  self : MemoryStore,
  user_id : String,
) -> Result[Array[MemoryEntry], MoomemError] {
  if self.closed {
    return Err(MoomemError::InvalidOperation("store is closed"))
  }
  match validate_user_id(user_id) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let out : Array[MemoryEntry] = []
  match self.by_user.get(user_id) {
    Some(ids) =>
      for id in ids {
        match self.entries.get(id) {
          Some(e) => out.push(e)
          None => ()
        }
      }
    None => ()
  }
  Ok(out)
}

// MemoryStore::add。仍是同一个聚合根上的方法。

// ---------------------------------------------------------------------------
// add：编排薄壳，阶段助手仍挂在同一个聚合根上
// ---------------------------------------------------------------------------

///|
/// 提取阶段结果：facts + Err 路径降级标记（notes 由助手写入）。
priv struct AddExtractOutcome {
  facts : Array[ExtractedFact]
  extraction_failed : Bool
  degraded : Bool
}

///|
/// 提取（失败降级：原文 unstructured；连续 MAX_EXTRACTION_FAILURES 次报错）。
fn MemoryStore::extract_for_add(
  self : MemoryStore,
  user_id : String,
  text : String,
  notes : Array[String],
) -> Result[AddExtractOutcome, MoomemError] {
  match self.extractor.extract(user_id, text) {
    Ok(fs) =>
      Ok(
        AddExtractOutcome::{
          facts: fs,
          extraction_failed: false,
          degraded: false,
        },
      )
    Err(e) => {
      self.extraction_failures = self.extraction_failures + 1
      let failures = self.extraction_failures
      let err_text = e.message()
      if failures >= MAX_EXTRACTION_FAILURES {
        return Err(
          MoomemError::ExtractionFailure(
            "extractor failed \{failures} times in a row; last error: \{err_text}",
          ),
        )
      }
      notes.push(
        "extraction degraded to raw unstructured (failure \{failures}/\{MAX_EXTRACTION_FAILURES}): \{err_text}",
      )
      Ok(
        AddExtractOutcome::{
          facts: [
            ExtractedFact::{
              content: text,
              kind: Unstructured,
              source_span: None,
              degraded: true,
              degrade_reason: Some(err_text),
            },
          ],
          extraction_failed: true,
          degraded: true,
        },
      )
    }
  }
}

///|
/// 成功且无自报降级时清零连续失败计数（ReturnRaw 自报降级不得清零）。
fn MemoryStore::clear_extraction_streak_if_clean(
  self : MemoryStore,
  facts : Array[ExtractedFact],
  extraction_failed : Bool,
) -> Unit {
  if extraction_failed {
    return
  }
  let mut any_self_degrade = false
  for f in facts {
    if f.degraded {
      any_self_degrade = true
    }
  }
  if !any_self_degrade {
    self.extraction_failures = 0
  }
}

///|
/// 记录提取器自报降级（ReturnRaw）；Err 路径已计数，避免双重递增。
/// 返回是否因本 fact 标记 degraded。
fn MemoryStore::note_fact_self_degrade(
  self : MemoryStore,
  fact : ExtractedFact,
  extraction_failed : Bool,
  notes : Array[String],
) -> Bool {
  if !(fact.degraded && !extraction_failed) {
    return false
  }
  self.extraction_failures = self.extraction_failures + 1
  let why = match fact.degrade_reason {
    Some(r) => r
    None => "reason not reported"
  }
  let streak = self.extraction_failures
  notes.push(
    "extraction degraded to raw (streak \{streak}/\{MAX_EXTRACTION_FAILURES}): \{why}",
  )
  true
}

///|
/// 精确去重：同 user 内容指纹命中则记 note，返回 true 表示应跳过。
fn MemoryStore::skip_if_duplicate(
  self : MemoryStore,
  user_id : String,
  content : String,
  notes : Array[String],
) -> Bool {
  match self.dedup.lookup(user_id, content) {
    Some(existing_id) => {
      notes.push("duplicate of \{existing_id}; skipped")
      true
    }
    None => false
  }
}

///|
/// 嵌入（失败降级：空向量 → 仅 BM25）。返回 (vec, embedding_failed, degraded)。
fn MemoryStore::embed_for_add(
  self : MemoryStore,
  content : String,
  notes : Array[String],
) -> (Array[Double], Bool, Bool) {
  let vec : Array[Double] = match self.embedder.embed([content]) {
    Ok(vs) => if vs.length() > 0 { vs[0] } else { [] }
    Err(e) => {
      notes.push("embedding degraded to keyword-only: \{e.message()}")
      return ([], true, true)
    }
  }
  let embedding_failed = vec.length() != self.dim
  (vec, embedding_failed, false)
}

///|
/// 冲突候选：向量 + 关键词各取 conflict_candidates，仅本 user 可检索条目。
fn MemoryStore::collect_conflict_candidates(
  self : MemoryStore,
  user_id : String,
  content : String,
  vec : Array[Double],
) -> Array[MemoryEntry] {
  let candidate_ids : Array[String] = []
  if vec.length() == self.dim {
    for pair in self.vector_index.search(user_id, vec, self.conflict_candidates) {
      if !candidate_ids.contains(pair.0) {
        candidate_ids.push(pair.0)
      }
    }
  }
  for pair in self.keyword_index.search(
    user_id,
    content,
    self.conflict_candidates,
  ) {
    if !candidate_ids.contains(pair.0) {
      candidate_ids.push(pair.0)
    }
  }
  let candidates : Array[MemoryEntry] = []
  for cid in candidate_ids {
    match self.entries.get(cid) {
      Some(e) =>
        if e.user_id == user_id && e.is_recallable() {
          candidates.push(e)
        }
      None => ()
    }
  }
  candidates
}

///|
/// 冲突判定（失败降级：空裁决 → 两条并存）。返回 (verdicts, degraded)。
fn MemoryStore::judge_for_add(
  self : MemoryStore,
  fact : ExtractedFact,
  candidates : Array[MemoryEntry],
  notes : Array[String],
) -> (Array[ConflictVerdict], Bool) {
  match self.judge.judge(fact, candidates) {
    Ok(vs) => (vs, false)
    Err(e) => {
      notes.push("conflict judge degraded to coexist: \{e.message()}")
      ([], true)
    }
  }
}

///|
/// 构造条目、入库、双索引；返回新条目。
fn MemoryStore::insert_fact_entry(
  self : MemoryStore,
  user_id : String,
  fact : ExtractedFact,
  vec : Array[Double],
  extraction_degraded_flag : Bool,
  embedding_failed : Bool,
) -> MemoryEntry {
  let seq = self.next_seq
  self.next_seq = self.next_seq + 1
  let created_at = self.clock.now_ms()
  if created_at > self.clock_high {
    self.clock_high = created_at
  }
  let id = generate_entry_id(seq, fact.content, created_at)
  let keywords = tokenize(fact.content)
  let entry = MemoryEntry::{
    id,
    user_id,
    content: fact.content,
    kind: fact.kind,
    embedding: vec,
    keywords,
    status: Active,
    created_at,
    superseded_by: None,
    seq,
    metadata: Map([]),
  }
  entry.metadata.set("extractor", Json::string(self.extractor.mode()))
  if extraction_degraded_flag || fact.degraded {
    entry.metadata.set("extraction_degraded", Json::string("true"))
  }
  if embedding_failed {
    entry.metadata.set("embedding_degraded", Json::string("true"))
  }
  self.entries.set(id, entry)
  match self.by_user.get(user_id) {
    Some(arr) => arr.push(id)
    None => self.by_user.set(user_id, [id])
  }
  self.index_entry(entry)
  entry
}

///|
/// 应用冲突裁决（Active→Superseded）；返回 supersede 次数。
fn MemoryStore::apply_conflict_verdicts(
  self : MemoryStore,
  entry : MemoryEntry,
  verdicts : Array[ConflictVerdict],
  notes : Array[String],
) -> Int {
  let mut superseded = 0
  let id = entry.id
  for v in verdicts {
    match v.decision {
      Replace => {
        let old = v.existing
        let threshold = self.supersede_threshold
        old.status = Superseded
        old.superseded_by = Some(id)
        self.deindex_entry(old)
        superseded = superseded + 1
        notes.push(
          "superseded \{old.id} (\"\{old.content}\") by similarity >= \{threshold}",
        )
        entry.metadata.set("conflict_decision", Json::string("replace"))
        entry.metadata.set("conflict_with", Json::string(old.id))
      }
      Coexist => {
        entry.metadata.set("conflict_decision", Json::string("coexist"))
        entry.metadata.set("conflict_with", Json::string(v.existing.id))
        notes.push(
          "coexists with \{v.existing.id} (\"\{v.existing.content}\")",
        )
      }
      Ignore => ()
    }
  }
  superseded
}

///|
/// 有状态变更才落盘。
fn MemoryStore::flush_after_add_mutation(
  self : MemoryStore,
  inserted : Int,
  superseded : Int,
) -> Result[Unit, MoomemError] {
  if inserted > 0 || superseded > 0 {
    self.flush()
  } else {
    Ok(())
  }
}

///|
/// 写入记忆：校验 → 提取 → 去重 → 冲突 → 嵌入 → 双索引 → supersede → 落盘。
pub fn MemoryStore::add(
  self : MemoryStore,
  user_id : String,
  text : String,
) -> Result[AddSummary, MoomemError] {
  if self.closed {
    return Err(MoomemError::InvalidOperation("store is closed"))
  }
  match validate_user_id(user_id) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let notes : Array[String] = []
  let outcome = match self.extract_for_add(user_id, text, notes) {
    Ok(o) => o
    Err(e) => return Err(e)
  }
  let facts = outcome.facts
  let extraction_failed = outcome.extraction_failed
  let mut degraded = outcome.degraded
  if facts.length() == 0 {
    // 提取成功但无事实（纯闲聊）同样属于成功，须清零连续失败计数
    self.extraction_failures = 0
    return Ok(AddSummary::{
      extracted: 0,
      inserted: 0,
      duplicates: 0,
      superseded: 0,
      degraded: false,
      notes: ["extracted 0 facts; nothing stored (chitchat filtered)"],
    })
  }
  self.clear_extraction_streak_if_clean(facts, extraction_failed)
  let extraction_degraded_flag = extraction_failed
  let mut inserted = 0
  let mut duplicates = 0
  let mut superseded = 0
  for fact in facts {
    if self.note_fact_self_degrade(fact, extraction_failed, notes) {
      degraded = true
    }
    if self.skip_if_duplicate(user_id, fact.content, notes) {
      duplicates = duplicates + 1
      continue
    }
    let (vec, embedding_failed, embed_degraded) = self.embed_for_add(
      fact.content,
      notes,
    )
    if embed_degraded {
      degraded = true
    }
    let candidates = self.collect_conflict_candidates(
      user_id,
      fact.content,
      vec,
    )
    let (verdicts, judge_degraded) = self.judge_for_add(
      fact,
      candidates,
      notes,
    )
    if judge_degraded {
      degraded = true
    }
    let entry = self.insert_fact_entry(
      user_id,
      fact,
      vec,
      extraction_degraded_flag,
      embedding_failed,
    )
    inserted = inserted + 1
    superseded = superseded +
      self.apply_conflict_verdicts(entry, verdicts, notes)
  }
  match self.flush_after_add_mutation(inserted, superseded) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  Ok(AddSummary::{
    extracted: facts.length(),
    inserted,
    duplicates,
    superseded,
    degraded,
    notes,
  })
}

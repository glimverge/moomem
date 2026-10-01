// MemoryStore —— 唯一有状态编排者（聚合根）。
// 公开六方法：open / add / recall / forget / stats / close
// 辅助方法：export_jsonl / import_jsonl / list_entries（CLI 与 FR-07/08 所需）。
//
// 状态机（架构文档 3.3）：
//   (空)→Active          add 提取/直通成功
//   Active→Superseded    judge 判定 Replace（置 superseded_by，双索引摘除）
//   Active→Deleted       forget（软删除，快照保留可审计）
//   其余迁移 v0.1 不开放（恢复 API 为 v0.2 候选）
// 不变量：recall 只返回 Active / Unstructured；Superseded/Deleted 物理保留。

///|
/// 记忆库聚合根：索引、条目表常驻内存；持久化仅负责快照落盘（单写者模型）。
pub struct MemoryStore {
  /// 记忆库根目录（MemoryBackend 下仅作标识）
  path : String
  /// 注入点（open 时解析为具体实现，此后不再变更）
  embedder : &Embedder
  extractor : &Extractor
  judge : &ConflictJudge
  persistence : &PersistenceBackend
  clock : &Clock
  dim : Int
  rrf_k : Int
  recall_candidates : Int
  supersede_threshold : Double
  /// add 链路冲突检测每路候选窗口
  conflict_candidates : Int
  /// SimilarityJudge Coexist 下界间距（仅在缺省 judge 构造时消费）
  coexist_band : Double
  /// recall 命中不足 top_k 时的补齐策略
  backfill : RecallBackfill
  /// 全部条目（含 Superseded / Deleted，审计与导出可见）
  entries : Map[String, MemoryEntry]
  /// 每 user 的 entry id 插入序（含全部状态）
  by_user : Map[String, Array[String]]
  vec_index : VectorIndex
  kw_index : KeywordIndex
  dedup : DedupIndex
  /// 逻辑时钟上界（快照 header.clock 来源）
  mut clock_high : Int64
  /// 下一个逻辑序号（持久化恢复续接，永不复用）
  mut next_seq : Int
  /// 快照代数
  mut gen : Int
  /// 启动恢复时截断的尾部半行数
  truncated_recovered : Int
  /// 提取器连续失败计数（PRD 第 9 章：连续 3 次返回错误）
  mut extraction_failures : Int
  /// 最近一次成功落盘的逻辑时钟
  mut last_write_at : Int64
  mut ever_flushed : Bool
  /// 最近一次快照字节数（stats 的 bytes_on_disk 逻辑值）
  mut snapshot_bytes : Int64
  mut closed : Bool
}

// ---------------------------------------------------------------------------
// open / 恢复（架构文档 4.3）
// ---------------------------------------------------------------------------

///|
/// 打开或创建记忆库。
/// 目录不存在则创建；存在则加载快照并重建索引与计数器（FR-01）。
pub fn MemoryStore::open(
  path : String,
  config? : Config,
) -> Result[MemoryStore, MoomemError] {
  let cfg = match config {
    Some(c) => c
    None => Config::default()
  }
  // 配置校验
  if cfg.dim <= 0 {
    return Err(MoomemError::InvalidOperation("config.dim must be positive"))
  }
  if cfg.rrf_k <= 0 {
    return Err(MoomemError::InvalidOperation("config.rrf_k must be positive"))
  }
  if cfg.recall_candidates < 0 {
    return Err(
      MoomemError::InvalidOperation("config.recall_candidates must be >= 0"),
    )
  }
  if cfg.supersede_threshold <= 0.0 || cfg.supersede_threshold > 1.0 {
    return Err(
      MoomemError::InvalidOperation(
        "config.supersede_threshold must be in (0, 1]",
      ),
    )
  }
  if cfg.conflict_candidates < 1 {
    return Err(
      MoomemError::InvalidOperation(
        "config.conflict_candidates must be >= 1",
      ),
    )
  }
  if cfg.coexist_band < 0.0 || cfg.coexist_band >= 1.0 {
    return Err(
      MoomemError::InvalidOperation("config.coexist_band must be in [0, 1)"),
    )
  }
  // 解析持久化后端
  let persistence : &PersistenceBackend = match cfg.persistence {
    Some(p) => p
    None =>
      match default_backend(path) {
        Ok(b) => b
        Err(e) => return Err(e)
      }
  }
  // 加载快照（None = 空库）
  let loaded : String? = match persistence.load() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let restored_entries : Array[MemoryEntry] = []
  let mut restored_gen = 0
  let mut restored_clock = 0L
  let mut truncated = 0
  match loaded {
    Some(text) =>
      match parse_snapshot_text(text) {
        Ok(parsed) => {
          restored_gen = parsed.gen
          restored_clock = parsed.clock
          truncated = parsed.truncated_recovered
          for e in parsed.entries {
            restored_entries.push(e)
          }
        }
        Err(e) => return Err(e)
      }
    None => ()
  }
  // 解析注入点（缺省全部确定性、离线）
  let embedder : &Embedder = match cfg.embedder {
    Some(e) => e
    None =>
      match HashingEmbedder::new(cfg.dim) {
        Ok(h) => h as &Embedder
        Err(e) => return Err(e)
      }
  }
  let extractor : &Extractor = match cfg.extractor {
    Some(x) => x
    None => RawExtractor::new() as &Extractor
  }
  let judge : &ConflictJudge = match cfg.judge {
    Some(j) => j
    None =>
      SimilarityJudge::new(
        cfg.supersede_threshold,
        embedder,
        coexist_band=cfg.coexist_band,
      ) as &ConflictJudge
  }
  let clock : &Clock = match cfg.clock {
    Some(c) => c
    None => LogicalClock::new(start=restored_clock) as &Clock
  }
  // 构造 store 并重放恢复条目
  let store = MemoryStore::{
    path,
    embedder,
    extractor,
    judge,
    persistence,
    clock,
    dim: cfg.dim,
    rrf_k: cfg.rrf_k,
    recall_candidates: cfg.recall_candidates,
    supersede_threshold: cfg.supersede_threshold,
    conflict_candidates: cfg.conflict_candidates,
    coexist_band: cfg.coexist_band,
    backfill: cfg.backfill,
    entries: Map([]),
    by_user: Map([]),
    vec_index: VectorIndex::new(),
    kw_index: KeywordIndex::new(),
    dedup: DedupIndex::new(),
    clock_high: restored_clock,
    next_seq: 1,
    gen: restored_gen,
    truncated_recovered: truncated,
    extraction_failures: 0,
    // 从快照恢复时：已有落盘历史（header.clock 即上次成功落盘的逻辑时钟）
    last_write_at: restored_clock,
    ever_flushed: match loaded {
      Some(_) => true
      None => false
    },
    snapshot_bytes: match loaded {
      Some(t) => t.length().to_int64()
      None => 0L
    },
    closed: false,
  }
  store.restore_entries(restored_entries)
  Ok(store)
}

///|
/// 重放恢复的条目：重建 entries/by_user/双索引/去重表/计数器。
/// Active / Unstructured 入索引；Superseded / Deleted 不入（架构文档 4.3）。
fn MemoryStore::restore_entries(
  self : MemoryStore,
  restored : Array[MemoryEntry],
) -> Unit {
  let mut max_seq = 0
  let mut max_created = 0L
  for e in restored {
    self.entries.set(e.id, e)
    match self.by_user.get(e.user_id) {
      Some(arr) => arr.push(e.id)
      None => self.by_user.set(e.user_id, [e.id])
    }
    if e.seq > max_seq {
      max_seq = e.seq
    }
    if e.created_at > max_created {
      max_created = e.created_at
    }
    if e.is_recallable() {
      self.index_entry(e)
    }
  }
  self.next_seq = max_seq + 1
  if max_created > self.clock_high {
    self.clock_high = max_created
  }
}

///|
/// 将可检索条目写入双索引与去重表。
fn MemoryStore::index_entry(self : MemoryStore, e : MemoryEntry) -> Unit {
  // 嵌入维度与当前配置不符（配置变更后恢复）时仅入关键词索引
  if e.embedding.length() == self.dim {
    self.vec_index.upsert(e.user_id, e.id, e.embedding)
  }
  self.kw_index.upsert(e.user_id, e.id, e.keywords)
  self.dedup.register(e.user_id, e.content, e.id)
}

///|
/// 将条目从双索引与去重表摘除（supersede / forget 共用）。
fn MemoryStore::deindex_entry(self : MemoryStore, e : MemoryEntry) -> Unit {
  self.vec_index.remove(e.user_id, e.id)
  self.kw_index.remove(e.user_id, e.id)
  self.dedup.unregister(e.user_id, e.content)
}

// ---------------------------------------------------------------------------
// add（架构文档 4.1 全链路）
// ---------------------------------------------------------------------------

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
  let mut degraded = false
  // ---- 提取（失败降级：原文 unstructured；连续 MAX_EXTRACTION_FAILURES 次报错）----
  let mut extraction_failed = false
  let facts : Array[ExtractedFact] = match
    self.extractor.extract(user_id, text) {
    Ok(fs) => fs
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
      degraded = true
      extraction_failed = true
      notes.push(
        "extraction degraded to raw unstructured (failure \{failures}/\{MAX_EXTRACTION_FAILURES}): \{err_text}",
      )
      [
        ExtractedFact::{
          content: text,
          kind: Unstructured,
          source_span: None,
          degraded: true,
          degrade_reason: Some(err_text),
        },
      ]
    }
  }
  if facts.length() == 0 {
    // 提取成功但无事实（纯闲聊）同样属于成功，须清零连续失败计数（W4-0）
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
  // 成功且无自报降级 → 清零连续失败计数（ReturnRaw 自报降级不得清零）
  if !extraction_failed {
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
  let extraction_degraded_flag = extraction_failed
  let mut inserted = 0
  let mut duplicates = 0
  let mut superseded = 0
  for fact in facts {
    // 提取器自报降级（ReturnRaw：extractor 不返回 Err，只能由此通道感知）
    // Err 路径已在上方计数/记 note，避免双重递增
    if fact.degraded && !extraction_failed {
      degraded = true
      self.extraction_failures = self.extraction_failures + 1
      let why = match fact.degrade_reason {
        Some(r) => r
        None => "reason not reported"
      }
      let streak = self.extraction_failures
      notes.push(
        "extraction degraded to raw (streak \{streak}/\{MAX_EXTRACTION_FAILURES}): \{why}",
      )
    }
    // ---- 精确去重（同 user 内容指纹）----
    match self.dedup.lookup(user_id, fact.content) {
      Some(existing_id) => {
        duplicates = duplicates + 1
        notes.push("duplicate of \{existing_id}; skipped")
        continue
      }
      None => ()
    }
    // ---- 嵌入（失败降级：仅 BM25 单路，条目 metadata 标记）----
    let vec : Array[Double] = match self.embedder.embed([fact.content]) {
      Ok(vs) => if vs.length() > 0 { vs[0] } else { [] }
      Err(e) => {
        degraded = true
        notes.push("embedding degraded to keyword-only: \{e.message()}")
        []
      }
    }
    let embedding_failed = vec.length() != self.dim
    // ---- 冲突候选（向量 + 关键词各取 conflict_candidates，仅本 user 分片）----
    let candidate_ids : Array[String] = []
    if vec.length() == self.dim {
      for pair in self.vec_index.search(
        user_id,
        vec,
        self.conflict_candidates,
      ) {
        if !candidate_ids.contains(pair.0) {
          candidate_ids.push(pair.0)
        }
      }
    }
    for pair in self.kw_index.search(
      user_id,
      fact.content,
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
    // ---- 冲突判定（失败降级：不产生裁决，两条并存）----
    let verdicts : Array[ConflictVerdict] = match
      self.judge.judge(fact, candidates) {
      Ok(vs) => vs
      Err(e) => {
        degraded = true
        notes.push("conflict judge degraded to coexist: \{e.message()}")
        []
      }
    }
    // ---- 构造条目 ----
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
    // ---- 入库 + 双索引 ----
    self.entries.set(id, entry)
    match self.by_user.get(user_id) {
      Some(arr) => arr.push(id)
      None => self.by_user.set(user_id, [id])
    }
    self.index_entry(entry)
    inserted = inserted + 1
    // ---- 应用裁决（状态机 Active→Superseded）----
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
  }
  // ---- 落盘（有状态变更才写）----
  if inserted > 0 || superseded > 0 {
    match self.flush() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
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

// ---------------------------------------------------------------------------
// recall（架构文档 4.2）
// ---------------------------------------------------------------------------

///|
/// 混合检索：向量 + BM25 双路 → RRF 融合 → 只返回 Active/Unstructured。
/// 嵌入失败时仅 BM25 单路。无结果返回空列表（不编造）。
pub fn MemoryStore::recall(
  self : MemoryStore,
  user_id : String,
  query : String,
  top_k? : Int,
) -> Result[Array[MemoryEntry], MoomemError] {
  if self.closed {
    return Err(MoomemError::InvalidOperation("store is closed"))
  }
  match validate_user_id(user_id) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let k = match top_k {
    Some(v) =>
      if v < 1 {
        DEFAULT_RECALL_TOP_K
      } else if v > MAX_RECALL_TOP_K {
        MAX_RECALL_TOP_K
      } else {
        v
      }
    None => DEFAULT_RECALL_TOP_K
  }
  let candidates_n = if self.recall_candidates > 0 {
    self.recall_candidates
  } else {
    let auto = k * 2
    if auto > MAX_RECALL_TOP_K {
      MAX_RECALL_TOP_K
    } else {
      auto
    }
  }
  let candidates_n = if candidates_n < k { k } else { candidates_n }
  // 嵌入查询（失败 → 单路 BM25）
  let qvec : Array[Double] = match self.embedder.embed([query]) {
    Ok(vs) => if vs.length() > 0 { vs[0] } else { [] }
    Err(_) => []
  }
  let vec_ids : Array[String] = self.vec_index
    .search(user_id, qvec, candidates_n)
    .map(p => p.0)
  let kw_ids : Array[String] = self.kw_index
    .search(user_id, query, candidates_n)
    .map(p => p.0)
  let fused = rrf([vec_ids, kw_ids], self.rrf_k, k)
  let results : Array[MemoryEntry] = []
  for id in fused {
    match self.entries.get(id) {
      Some(e) =>
        if e.user_id == user_id && e.is_recallable() {
          results.push(e)
        }
      None => ()
    }
  }
  // 补齐到 top_k（仅当已有命中；零命中返回空列表，不编造）
  match self.backfill {
    BackfillRecency =>
      if results.length() > 0 && results.length() < k {
        let in_results : Map[String, Bool] = Map([])
        for e in results {
          in_results.set(e.id, true)
        }
        match self.by_user.get(user_id) {
          Some(ids) => {
            // 最新优先（插入序倒序）
            let mut i = ids.length() - 1
            while i >= 0 && results.length() < k {
              match self.entries.get(ids[i]) {
                Some(e) =>
                  if e.is_recallable() && !in_results.contains(e.id) {
                    in_results.set(e.id, true)
                    results.push(e)
                  }
                None => ()
              }
              i = i - 1
            }
          }
          None => ()
        }
      }
    NoBackfill => ()
  }
  Ok(results)
}

// ---------------------------------------------------------------------------
// forget（FR-06 软删除）
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
// stats（FR-10）
// ---------------------------------------------------------------------------

///|
/// 运行统计：各状态条目数、快照字节数（逻辑值）、最近写入、恢复截断计数。
pub fn MemoryStore::stats(
  self : MemoryStore,
) -> Result[StoreStats, MoomemError] {
  if self.closed {
    return Err(MoomemError::InvalidOperation("store is closed"))
  }
  let mut total = 0
  let mut active = 0
  let mut superseded = 0
  let mut deleted = 0
  let mut unstructured = 0
  for kv in self.entries.iter() {
    let e = kv.1
    total = total + 1
    match e.status {
      Active => active = active + 1
      Superseded => superseded = superseded + 1
      Deleted => deleted = deleted + 1
      Unstructured => unstructured = unstructured + 1
    }
  }
  Ok(StoreStats::{
    total,
    active,
    superseded,
    deleted,
    unstructured,
    bytes_on_disk: self.snapshot_bytes,
    last_write_at: if self.ever_flushed {
      Some(self.last_write_at)
    } else {
      None
    },
    truncated_recovered: self.truncated_recovered,
    extractor_mode: self.extractor.mode(),
  })
}

// ---------------------------------------------------------------------------
// close（FR-01 / 单写者模型）
// ---------------------------------------------------------------------------

///|
/// 安全关闭：flush 后拒绝一切后续操作。重复 close 为幂等 Ok。
pub fn MemoryStore::close(self : MemoryStore) -> Result[Unit, MoomemError] {
  if self.closed {
    return Ok(())
  }
  // 空库且从未落盘时不产生文件
  if self.entries.length() > 0 || self.ever_flushed {
    match self.flush() {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  self.closed = true
  Ok(())
}

// ---------------------------------------------------------------------------
// flush（双槽快照全量重写）
// ---------------------------------------------------------------------------

///|
fn MemoryStore::flush(self : MemoryStore) -> Result[Unit, MoomemError] {
  let all : Array[MemoryEntry] = []
  for kv in self.entries.iter() {
    all.push(kv.1)
  }
  all.sort_by((a, b) => a.seq - b.seq)
  let text = build_snapshot_text(self.gen + 1, self.clock_high, all)
  match self.persistence.save(text) {
    Ok(_) => {
      self.gen = self.gen + 1
      self.last_write_at = self.clock_high
      self.ever_flushed = true
      self.snapshot_bytes = text.length().to_int64()
      Ok(())
    }
    Err(e) => Err(e)
  }
}

// ---------------------------------------------------------------------------
// 导入导出（FR-08；CLI 复用）
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
/// 从 JSONL 文本导入（FR-08：导出再导入，记忆等价）。
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
            // 架构 7.4 / PRD 15 章：user_id 校验是所有入库入口的强制关卡，
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
// list（FR-07 CLI 所需；仅枚举指定 user 的条目，保持隔离不变量）
// ---------------------------------------------------------------------------

///|
/// 枚举某 user 的全部条目（含 Superseded / Deleted，供 CLI list / 审计）。
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

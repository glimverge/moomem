// MemoryStore —— 唯一有状态编排者（聚合根）。
// 本文件：类型、open、索引维护、stats、close、flush。
// add 在 store_add.mbt，recall 在 store_recall.mbt，
// forget / export / import / list 在 store_records.mbt。
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
  /// 混合检索融合策略
  fusion_policy : FusionPolicy
  lexical_floor : Double
  lexical_gap : Double
  vector_weight_when_lexical : Double
  vector_weight_when_semantic : Double
  /// 全部条目（含 Superseded / Deleted，审计与导出可见）
  entries : Map[String, MemoryEntry]
  /// 每 user 的 entry id 插入序（含全部状态）
  by_user : Map[String, Array[String]]
  /// Package-private indexes (not host API)
  priv vector_index : VectorIndex
  priv keyword_index : KeywordIndex
  priv dedup : DedupIndex
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
  if cfg.lexical_floor < 0.0 {
    return Err(
      MoomemError::InvalidOperation("config.lexical_floor must be >= 0"),
    )
  }
  if cfg.lexical_gap < 1.0 {
    return Err(
      MoomemError::InvalidOperation("config.lexical_gap must be >= 1"),
    )
  }
  if cfg.vector_weight_when_lexical <= 0.0 || cfg.vector_weight_when_lexical > 1.0 {
    return Err(
      MoomemError::InvalidOperation(
        "config.vector_weight_when_lexical must be in (0, 1]",
      ),
    )
  }
  if cfg.vector_weight_when_semantic <= 0.0 ||
    cfg.vector_weight_when_semantic > 1.0 {
    return Err(
      MoomemError::InvalidOperation(
        "config.vector_weight_when_semantic must be in (0, 1]",
      ),
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
    fusion_policy: cfg.fusion_policy,
    lexical_floor: cfg.lexical_floor,
    lexical_gap: cfg.lexical_gap,
    vector_weight_when_lexical: cfg.vector_weight_when_lexical,
    vector_weight_when_semantic: cfg.vector_weight_when_semantic,
    entries: Map([]),
    by_user: Map([]),
    vector_index: VectorIndex::new(),
    keyword_index: KeywordIndex::new(),
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
    self.vector_index.upsert(e.user_id, e.id, e.embedding)
  }
  self.keyword_index.upsert(e.user_id, e.id, e.keywords)
  self.dedup.register(e.user_id, e.content, e.id)
}

///|
/// 将条目从双索引与去重表摘除（supersede / forget 共用）。
fn MemoryStore::deindex_entry(self : MemoryStore, e : MemoryEntry) -> Unit {
  self.vector_index.remove(e.user_id, e.id)
  self.keyword_index.remove(e.user_id, e.id)
  self.dedup.unregister(e.user_id, e.content)
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

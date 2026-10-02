// Config 检索与冲突参数（零网络、四后端可跑）。

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

///|
/// 记录 judge 收到的候选数（不产生裁决，便于断言窗口大小）。
struct ConfigCountingJudge {
  mut last_count : Int
}

///|
impl ConflictJudge for ConfigCountingJudge with fn judge(self, _, candidates) {
  self.last_count = candidates.length()
  Ok([])
}

///|
/// 恒 Replace，用于对比不同 conflict_candidates 下的 supersede 数。
struct ConfigAlwaysReplaceJudge {}

///|
impl ConflictJudge for ConfigAlwaysReplaceJudge with fn judge(_, _, candidates) {
  Ok(
    candidates.map(c => @src.ConflictVerdict::{
      existing: c,
      decision: Replace,
    }),
  )
}

///|
/// 住址主题嵌入（与 store_test 同构，避免跨文件符号冲突）。
struct ConfigResidenceEmbedder {}

///|
fn config_residence_vector(text : String) -> Array[Double] {
  let v = Array::make(@src.DEFAULT_DIM, 0.0)
  if text.contains("住") || text.contains("搬") {
    v[0] = 1.0
  } else {
    v[1] = 1.0
  }
  v
}

///|
impl Embedder for ConfigResidenceEmbedder with fn embed(_self, texts) {
  Ok(texts.map(t => config_residence_vector(t)))
}

///|
impl Embedder for ConfigResidenceEmbedder with fn dim(_self) {
  @src.DEFAULT_DIM
}

///|
/// 固定向量嵌入：按文本精确映射，用于精确控制 SimilarityJudge 相似度。
struct ConfigFixedEmbedder {
  table : Map[String, Array[Double]]
  fallback : Array[Double]
}

///|
impl Embedder for ConfigFixedEmbedder with fn embed(self, texts) {
  Ok(
    texts.map(t => {
      match self.table.get(t) {
        Some(v) => v
        None => self.fallback
      }
    }),
  )
}

///|
impl Embedder for ConfigFixedEmbedder with fn dim(_self) {
  @src.DEFAULT_DIM
}

///|
fn config_unit_vector(i : Int, scale : Double) -> Array[Double] {
  let v = Array::make(@src.DEFAULT_DIM, 0.0)
  v[i] = scale
  v
}

///|
fn config_open(
  config : @src.Config,
) -> Result[@src.MemoryStore, @src.MoomemError] {
  @src.MemoryStore::open("memory://config", config=config)
}

///|
fn config_base(
  backend : &@src.PersistenceBackend,
) -> @src.Config {
  @src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
  }
}

// ---------------------------------------------------------------------------
// TC-A1 缺省行为回归
// ---------------------------------------------------------------------------

///|
test "default config add/recall matches prior behavior" {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let store = match config_open(config_base(backend)) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("w3-a1", "我对花生过敏"))
  ignore(store.add("w3-a1", "我喜欢清淡的粤菜"))
  let hits = match store.recall("w3-a1", "花生过敏") {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(hits.length() > 0, content="true")
  inspect(hits[0].content, content="我对花生过敏")
  // 缺省 BackfillRecency：部分命中后可补齐到 top_k=5
  inspect(hits.length(), content="2")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// TC-A2 conflict_candidates 窗口
// ---------------------------------------------------------------------------

///|
test "conflict_candidates=1 limits candidates to at most one per path" {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let judge = ConfigCountingJudge::{ last_count: -1 }
  let embedder : &@src.Embedder = ConfigResidenceEmbedder::{ }
  let cfg = @src.Config::{
    ..config_base(backend),
    embedder: Some(embedder),
    judge: Some(judge as &@src.ConflictJudge),
    conflict_candidates: 1,
  }
  let store = match config_open(cfg) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("w3-a2", "我住在北京市海淀区甲"))
  ignore(store.add("w3-a2", "我住在北京市海淀区乙"))
  ignore(store.add("w3-a2", "我搬家了现在住在深圳南山区"))
  // 两路各至多 1 → 合并后候选 ≤ 2；对比缺省窗口应更小
  inspect(judge.last_count <= 2, content="true")
  inspect(judge.last_count >= 1, content="true")
  ignore(store.close())

  // 对照：AlwaysReplace + conflict_candidates=1 → 至多 supersede 2；
  // conflict_candidates=8 + 两条旧事实 → supersede 恰好 2
  let backend2 : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let embedder2 : &@src.Embedder = ConfigResidenceEmbedder::{ }
  let judge2 : &@src.ConflictJudge = ConfigAlwaysReplaceJudge::{ }
  let cfg_narrow = @src.Config::{
    ..config_base(backend2),
    embedder: Some(embedder2),
    judge: Some(judge2),
    conflict_candidates: 1,
  }
  let store2 = match config_open(cfg_narrow) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store2.add("w3-a2b", "我住在北京市海淀区甲"))
  ignore(store2.add("w3-a2b", "我住在北京市海淀区乙"))
  let s_narrow = match store2.add("w3-a2b", "我搬家了现在住在深圳南山区") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 每路 1 → 合并唯一后至多 2 条裁决
  inspect(s_narrow.superseded <= 2, content="true")
  inspect(s_narrow.superseded >= 1, content="true")
  ignore(store2.close())
}

// ---------------------------------------------------------------------------
// TC-A3 非法配置拒绝
// ---------------------------------------------------------------------------

///|
test "conflict_candidates=0 and coexist_band=1.0 rejected" {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let bad_cc = @src.Config::{
    ..config_base(backend),
    conflict_candidates: 0,
  }
  let rejected_cc = match config_open(bad_cc) {
    Err(InvalidOperation(msg)) => msg.contains("conflict_candidates")
    _ => false
  }
  inspect(rejected_cc, content="true")
  let bad_band = @src.Config::{
    ..config_base(backend),
    coexist_band: 1.0,
  }
  let rejected_band = match config_open(bad_band) {
    Err(InvalidOperation(msg)) => msg.contains("coexist_band")
    _ => false
  }
  inspect(rejected_band, content="true")
  let bad_gap = @src.Config::{
    ..config_base(backend),
    lexical_gap: 0.9,
  }
  let rejected_gap = match config_open(bad_gap) {
    Err(InvalidOperation(msg)) => msg.contains("lexical_gap")
    _ => false
  }
  inspect(rejected_gap, content="true")
  let bad_wv = @src.Config::{
    ..config_base(backend),
    vector_weight_when_lexical: 0.0,
  }
  let rejected_wv = match config_open(bad_wv) {
    Err(InvalidOperation(msg)) => msg.contains("vector_weight_when_lexical")
    _ => false
  }
  inspect(rejected_wv, content="true")
}

// ---------------------------------------------------------------------------
// TC-A4 backfill 策略
// ---------------------------------------------------------------------------

///|
test "NoBackfill vs BackfillRecency" {
  let texts = [
    "w3alpha peanut allergy unique1",
    "w3alpha peanut allergy unique2",
    "w3beta unrelated filler3",
    "w3beta unrelated filler4",
    "w3beta unrelated filler5",
  ]
  // NoBackfill：仅返回真实命中
  let backend_nb : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg_nb = @src.Config::{
    ..config_base(backend_nb),
    backfill: @src.RecallBackfill::NoBackfill,
  }
  let store_nb = match config_open(cfg_nb) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  for t in texts {
    ignore(store_nb.add("w3-a4", t))
  }
  let nb = match store_nb.recall("w3-a4", "w3alpha peanut", top_k=5) {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(nb.length(), content="2")
  ignore(store_nb.close())

  // BackfillRecency：补齐到 5，后 3 条为最新插入
  let backend_br : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg_br = @src.Config::{
    ..config_base(backend_br),
    backfill: @src.RecallBackfill::BackfillRecency,
  }
  let store_br = match config_open(cfg_br) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  for t in texts {
    ignore(store_br.add("w3-a4", t))
  }
  let br = match store_br.recall("w3-a4", "w3alpha peanut", top_k=5) {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(br.length(), content="5")
  // 后 3 条按插入序倒序补最新
  inspect(br[2].content, content="w3beta unrelated filler5")
  inspect(br[3].content, content="w3beta unrelated filler4")
  inspect(br[4].content, content="w3beta unrelated filler3")
  ignore(store_br.close())
}

// ---------------------------------------------------------------------------
// TC-A5 / TC-A6 SimilarityJudge coexist_band
// ---------------------------------------------------------------------------

///|
test "coexist_band=0.30 expands Coexist window" {
  // threshold=0.82；sim=0.60 ∈ [0.52, 0.82) → band=0.30 判 Coexist；
  // band=0.15 时落在 [0.67, 0.82) 之外 → Ignore（无裁决）
  let new_key = "w3-new-fact"
  let old_key = "w3-old-fact"
  let table : Map[String, Array[Double]] = Map([])
  // unit_x · (0.6 u_x + 0.8 u_y) = 0.6
  let new_vec = config_unit_vector(0, 1.0)
  let old_vec = Array::make(@src.DEFAULT_DIM, 0.0)
  old_vec[0] = 0.6
  old_vec[1] = 0.8
  table.set(new_key, new_vec)
  table.set(old_key, old_vec)
  let embedder = ConfigFixedEmbedder::{
    table,
    fallback: config_unit_vector(2, 1.0),
  }
  let e : &@src.Embedder = embedder
  let cand = @src.MemoryEntry::{
    id: "cand-w3",
    user_id: "u",
    content: old_key,
    kind: @src.EntryKind::Fact,
    embedding: old_vec,
    keywords: [],
    status: @src.EntryStatus::Active,
    created_at: 0L,
    superseded_by: None,
    seq: 1,
    metadata: Map([]),
  }
  let fact = @src.ExtractedFact::{
    content: new_key,
    kind: @src.EntryKind::Fact,
    source_span: None,
    degraded: false,
    degrade_reason: None,
  }
  let wide = @src.SimilarityJudge::new(0.82, e, coexist_band=0.30)
  let wide_j : &@src.ConflictJudge = wide
  let wide_vs = match wide_j.judge(fact, [cand]) {
    Ok(vs) => vs
    Err(_) => {
      inspect("wide judge failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(wide_vs.length(), content="1")
  inspect(
    wide_vs[0].decision == @src.ConflictDecision::Coexist,
    content="true",
  )

  let narrow = @src.SimilarityJudge::new(0.82, e, coexist_band=0.15)
  let narrow_j : &@src.ConflictJudge = narrow
  let narrow_vs = match narrow_j.judge(fact, [cand]) {
    Ok(vs) => vs
    Err(_) => {
      inspect("narrow judge failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(narrow_vs.length(), content="0")
}

///|
test "SimilarityJudge::new default coexist_band is 0.15" {
  let new_key = "w3-a6-new"
  let old_key = "w3-a6-old"
  let table : Map[String, Array[Double]] = Map([])
  let new_vec = config_unit_vector(0, 1.0)
  let old_vec = Array::make(@src.DEFAULT_DIM, 0.0)
  old_vec[0] = 0.6
  old_vec[1] = 0.8
  table.set(new_key, new_vec)
  table.set(old_key, old_vec)
  let embedder = ConfigFixedEmbedder::{
    table,
    fallback: config_unit_vector(2, 1.0),
  }
  let e : &@src.Embedder = embedder
  // 不传 coexist_band → 缺省 0.15；sim=0.60 → Ignore
  let judge = @src.SimilarityJudge::new(0.82, e)
  let j : &@src.ConflictJudge = judge
  let fact = @src.ExtractedFact::{
    content: new_key,
    kind: @src.EntryKind::Fact,
    source_span: None,
    degraded: false,
    degrade_reason: None,
  }
  let cand = @src.MemoryEntry::{
    id: "cand-a6",
    user_id: "u",
    content: old_key,
    kind: @src.EntryKind::Fact,
    embedding: old_vec,
    keywords: [],
    status: @src.EntryStatus::Active,
    created_at: 0L,
    superseded_by: None,
    seq: 1,
    metadata: Map([]),
  }
  let vs = match j.judge(fact, [cand]) {
    Ok(v) => v
    Err(_) => {
      inspect("judge failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(vs.length(), content="0")
  // 显式 0.15 应与缺省完全一致
  let explicit = @src.SimilarityJudge::new(0.82, e, coexist_band=0.15)
  let ej : &@src.ConflictJudge = explicit
  let vs2 = match ej.judge(fact, [cand]) {
    Ok(v) => v
    Err(_) => {
      inspect("explicit judge failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(vs2.length(), content="0")
}

// ---------------------------------------------------------------------------
// TC-A7 自适应融合：强词法贴近 BM25；弱词法保留向量
// ---------------------------------------------------------------------------

///|
test "adaptive fusion favors BM25 on strong lexical query" {
  // 向量故意把「无关」文档排前；词法强命中时应仍返回过敏事实。
  let table : Map[String, Array[Double]] = Map([])
  table.set("我对花生过敏非常严重", config_unit_vector(0, 1.0))
  table.set("我喜欢清淡粤菜少油少盐", config_unit_vector(1, 1.0))
  // 查询向量偏向粤菜文档
  table.set("花生过敏", config_unit_vector(1, 1.0))
  // 释义查询：无共享表面词，但向量指向过敏文档
  table.set("hypersensitivity to groundnuts", config_unit_vector(0, 1.0))
  let embedder : &@src.Embedder = ConfigFixedEmbedder::{
    table,
    fallback: config_unit_vector(2, 1.0),
  }
  let judge : &@src.ConflictJudge = ConfigCountingJudge::{ last_count: -1 }
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg = @src.Config::{
    ..config_base(backend),
    embedder: Some(embedder),
    judge: Some(judge),
    fusion_policy: @src.FusionPolicy::AdaptiveLexical,
    lexical_floor: 0.5,
    lexical_gap: 1.05,
    vector_weight_when_lexical: 0.10,
    vector_weight_when_semantic: 0.55,
    backfill: @src.RecallBackfill::NoBackfill,
  }
  let store = match config_open(cfg) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("w3-a7", "我对花生过敏非常严重"))
  ignore(store.add("w3-a7", "我喜欢清淡粤菜少油少盐"))
  let lexical = match store.recall("w3-a7", "花生过敏", top_k=2) {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(lexical.length() >= 1, content="true")
  inspect(lexical[0].content.contains("花生过敏"), content="true")

  let semantic = match store.recall(
    "w3-a7",
    "hypersensitivity to groundnuts",
    top_k=2,
  ) {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(semantic.length() >= 1, content="true")
  inspect(semantic[0].content.contains("花生过敏"), content="true")
  ignore(store.close())
}

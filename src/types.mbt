// moomem 核心类型：条目 / 状态 / 配置 / 统计 / 摘要。
// 共享约定（架构文档第 7 章）在此落地：
//   - user_id 契约校验唯一实现 validate_user_id
//   - id = "{seq 12位hex}-{rand 4 hex}"，seq 持久化恢复续接
//   - created_at 为注入 Clock 的逻辑毫秒

///|
/// 条目生命周期状态（状态机见架构文档 3.3 节）。
/// Active / Unstructured 参与检索；Superseded / Deleted 保留于快照可审计但不可检索。
pub(all) enum EntryStatus {
  Active
  Superseded
  Deleted
  Unstructured
} derive(Eq)

///|
pub impl Show for EntryStatus with fn output(self, logger) {
  match self {
    Active => logger.write_string("Active")
    Superseded => logger.write_string("Superseded")
    Deleted => logger.write_string("Deleted")
    Unstructured => logger.write_string("Unstructured")
  }
}

///|
pub extend EntryStatus with Show::{to_string, output}

///|
pub extend EntryStatus with Eq::{not_equal, equal}

///|
/// 条目语义类型（由 Extractor 产出）。
pub(all) enum EntryKind {
  Fact
  Preference
  Event
  Unstructured
} derive(Eq)

///|
pub impl Show for EntryKind with fn output(self, logger) {
  match self {
    Fact => logger.write_string("Fact")
    Preference => logger.write_string("Preference")
    Event => logger.write_string("Event")
    Unstructured => logger.write_string("Unstructured")
  }
}

///|
pub extend EntryKind with Show::{to_string, output}

///|
pub extend EntryKind with Eq::{not_equal, equal}

///|
/// 最小记忆单元：一条可复用事实。
pub(all) struct MemoryEntry {
  /// "{seq 12位hex}-{rand 4 hex}"，全局唯一，不含 user 信息
  id : String
  user_id : String
  content : String
  kind : EntryKind
  /// 嵌入向量，长度 = config.dim；嵌入失败时为空数组（仅 BM25 检索）
  embedding : Array[Double]
  /// BM25 分词结果（写入时即分好，恢复时不必重算）
  keywords : Array[String]
  /// 生命周期状态（add→Active；supersede/forget 就地迁移）
  mut status : EntryStatus
  /// 逻辑时钟毫秒（注入 Clock），导出可见
  created_at : Int64
  /// 覆盖者 id（状态机：Active→Superseded 时写入）
  mut superseded_by : String?
  /// 逻辑序号，持久化恢复计数器，永不复用
  seq : Int
  /// AI 痕迹元数据（extractor / degraded / conflict_decision 等，满足可解释验收）
  metadata : Map[String, Json]
}

///|
/// 条目是否可被 recall 返回（Active 与 Unstructured；Superseded/Deleted 不可见）。
pub fn MemoryEntry::is_recallable(self : MemoryEntry) -> Bool {
  match self.status {
    Active => true
    Unstructured => true
    Superseded => false
    Deleted => false
  }
}

///|
/// 简要展示（Show 输出不含 embedding 全量，避免噪音）。
pub impl Show for MemoryEntry with fn output(self, logger) {
  let kind = self.kind.to_string()
  let status = self.status.to_string()
  let superseded_by = match self.superseded_by {
    Some(id) => id
    None => "none"
  }
  let kw_len = self.keywords.length()
  let emb_len = self.embedding.length()
  let text = "MemoryEntry::{ id: \{self.id}, user_id: \{self.user_id}, content: \{self.content}, kind: \{kind}, status: \{status}, created_at: \{self.created_at}, superseded_by: \{superseded_by}, seq: \{self.seq}, keywords: \{kw_len}, embedding_dim: \{emb_len} }"
  logger.write_string(text)
}

///|
pub extend MemoryEntry with Show::{to_string, output}

///|
/// forget 的目标选择：按 id 或清空该 user 全部可检索条目。
pub(all) enum ForgetTarget {
  ById(String)
  All
}

///|
pub impl Show for ForgetTarget with fn output(self, logger) {
  match self {
    ById(id) => logger.write_string("ById(\{id})")
    All => logger.write_string("All")
  }
}

///|
pub extend ForgetTarget with Show::{to_string, output}

///|
/// add 的返回摘要：让开发者看见"AI 理解了什么"（PRD 12.3）。
pub struct AddSummary {
  /// 提取器产出的事实条数
  extracted : Int
  /// 实际新入库条数
  inserted : Int
  /// 与既有条目内容指纹重复而跳过的条数
  duplicates : Int
  /// 被 Replace 裁决覆盖（置 Superseded）的旧条目数
  superseded : Int
  /// 本次 add 是否发生降级（提取失败→raw / 嵌入失败→仅 BM25）
  degraded : Bool
  /// 人类可读备注（重复 id、冲突判定、降级原因等）
  notes : Array[String]
}

///|
/// 手写 Show（原 derive(Show) 输出格式保持不变：字段名: 值，逗号分隔）。
pub impl Show for AddSummary with fn output(self, logger) {
  logger.write_string(
    "{extracted: \{self.extracted}, inserted: \{self.inserted}, duplicates: \{self.duplicates}, superseded: \{self.superseded}, degraded: \{self.degraded}, notes: \{show_string_array(self.notes)}}",
  )
}

///|
pub extend AddSummary with Show::{to_string, output}

///|
/// stats 的返回结构（PRD FR-10）。
pub struct StoreStats {
  total : Int
  active : Int
  superseded : Int
  deleted : Int
  /// status == Unstructured 的条目数（降级入库，待重提取）
  unstructured : Int
  /// 快照逻辑字节数（MemoryBackend 下为逻辑值）
  bytes_on_disk : Int64
  /// 最近一次成功落盘的逻辑时钟；从未写盘为 None
  last_write_at : Int64?
  /// 启动恢复时截断的尾部半行数（PRD 第 15 章）
  truncated_recovered : Int
  /// 当前提取器模式（"raw" | "llm"），AI 可解释验收
  extractor_mode : String
}

///|
/// 手写 Show（原 derive(Show) 输出格式保持不变：字段名: 值，逗号分隔）。
pub impl Show for StoreStats with fn output(self, logger) {
  logger.write_string(
    "{total: \{self.total}, active: \{self.active}, superseded: \{self.superseded}, deleted: \{self.deleted}, unstructured: \{self.unstructured}, bytes_on_disk: \{self.bytes_on_disk}, last_write_at: \{show_int64_opt(self.last_write_at)}, truncated_recovered: \{self.truncated_recovered}, extractor_mode: \{self.extractor_mode}}",
  )
}

///|
pub extend StoreStats with Show::{to_string, output}

///|
/// recall 命中数不足 top_k 时的补齐策略。
pub(all) enum RecallBackfill {
  /// 不补齐：命中多少返回多少（零命中行为不受影响，恒为空列表）
  NoBackfill
  /// 按插入序倒序补最新可检索条目（v0.2.1 现行为，缺省）
  BackfillRecency
}

///|
/// 手写 Show（构造器名，与 ConflictDecision 惯例一致）。
pub impl Show for RecallBackfill with fn output(self, logger) {
  match self {
    NoBackfill => logger.write_string("NoBackfill")
    BackfillRecency => logger.write_string("BackfillRecency")
  }
}

///|
pub extend RecallBackfill with Show::{to_string, output}

///|
/// 混合检索融合策略。
pub(all) enum FusionPolicy {
  /// 等权 RRF（历史缺省；回退用）
  EqualRrf
  /// 查询自适应：词法强命中时降权向量通道
  AdaptiveLexical
}

///|
pub impl Show for FusionPolicy with fn output(self, logger) {
  match self {
    EqualRrf => logger.write_string("EqualRrf")
    AdaptiveLexical => logger.write_string("AdaptiveLexical")
  }
}

///|
pub extend FusionPolicy with Show::{to_string, output}

///|
/// 打开 MemoryStore 的配置。所有注入点均为 Option，None 时使用缺省确定性实现。
pub(all) struct Config {
  /// None → HashingEmbedder(dim)
  embedder : &Embedder?
  /// None → RawExtractor（raw 直通，kind=unstructured）
  extractor : &Extractor?
  /// None → SimilarityJudge(supersede_threshold, embedder)
  judge : &ConflictJudge?
  /// None → native: FsBackend(path)；wasm/js: MemoryBackend
  persistence : &PersistenceBackend?
  /// None → LogicalClock（从快照 header.clock 续接）
  clock : &Clock?
  /// 嵌入维度，缺省 256
  dim : Int
  /// RRF 融合常数 k，缺省 60
  rrf_k : Int
  /// 每路召回候选数；0 = 自动（min(top_k*2, 50)）
  recall_candidates : Int
  /// 冲突判定 Replace 阈值，缺省 0.82
  supersede_threshold : Double
  /// add 链路冲突检测每路候选窗口，缺省 8（合法域 >= 1）
  conflict_candidates : Int
  /// SimilarityJudge 的 Coexist 下界间距，缺省 0.15（合法域 [0, 1)）
  coexist_band : Double
  /// recall 补齐策略，缺省 BackfillRecency
  backfill : RecallBackfill
  /// 混合检索融合策略，缺省 AdaptiveLexical
  fusion_policy : FusionPolicy
  /// adaptive：BM25 top1 下限（>=0）
  lexical_floor : Double
  /// adaptive：top1/top2 倍差（>=1）
  lexical_gap : Double
  /// adaptive：词法强时向量权重，∈(0,1]
  vec_weight_when_lexical : Double
  /// adaptive：词法弱时向量权重，∈(0,1]
  vec_weight_when_semantic : Double
}

///|
/// 缺省配置（全部注入点走确定性缺省实现）。
pub fn Config::default() -> Config {
  Config::{
    embedder: None,
    extractor: None,
    judge: None,
    persistence: None,
    clock: None,
    dim: DEFAULT_DIM,
    rrf_k: DEFAULT_RRF_K,
    recall_candidates: 0,
    supersede_threshold: DEFAULT_SUPERSEDE_THRESHOLD,
    conflict_candidates: CONFLICT_CANDIDATES,
    coexist_band: COEXIST_BAND,
    backfill: BackfillRecency,
    fusion_policy: FusionPolicy::AdaptiveLexical,
    lexical_floor: DEFAULT_LEXICAL_FLOOR,
    lexical_gap: DEFAULT_LEXICAL_GAP,
    vec_weight_when_lexical: DEFAULT_VEC_WEIGHT_LEXICAL,
    vec_weight_when_semantic: DEFAULT_VEC_WEIGHT_SEMANTIC,
  }
}

// ---------------------------------------------------------------------------
// 常量
// ---------------------------------------------------------------------------

///|
pub const DEFAULT_DIM : Int = 256

///|
pub const DEFAULT_RRF_K : Int = 60

///|
pub const DEFAULT_SUPERSEDE_THRESHOLD : Double = 0.82

///|
pub const DEFAULT_RECALL_TOP_K : Int = 5

///|
pub const MAX_RECALL_TOP_K : Int = 50

///|
pub const MAX_USER_ID_LEN : Int = 64

///|
/// add 链路冲突检测的每路候选窗口
pub const CONFLICT_CANDIDATES : Int = 8

///|
/// SimilarityJudge 的 Coexist 下界间距：[threshold-0.15, threshold)
pub const COEXIST_BAND : Double = 0.15

///|
/// 提取器连续失败降级上限（PRD 第 9 章）
pub const MAX_EXTRACTION_FAILURES : Int = 3

///|
/// adaptive 词法强判定：BM25 top1 下限（独立开发集校准；偏低以覆盖短轮次）
pub const DEFAULT_LEXICAL_FLOOR : Double = 0.5

///|
/// adaptive 词法强判定：top1 ≥ top2 × gap
pub const DEFAULT_LEXICAL_GAP : Double = 1.05

///|
/// adaptive：词法强时向量通道权重（≤0.05 时 recall 走 BM25 单路）
pub const DEFAULT_VEC_WEIGHT_LEXICAL : Double = 0.05

///|
/// adaptive：词法弱时向量通道权重（略偏 BM25，减少弱词法稀释）
pub const DEFAULT_VEC_WEIGHT_SEMANTIC : Double = 0.35

// ---------------------------------------------------------------------------
// user_id 契约（架构文档 7.4：唯一实现，所有入口调用）
// ---------------------------------------------------------------------------

///|
/// 校验 user_id：非空、≤64 字符、字符集 [A-Za-z0-9_\-.]，且不为 "." / ".."。
pub fn validate_user_id(user_id : String) -> Result[Unit, MoomemError] {
  if user_id.length() == 0 {
    return Err(MoomemError::InvalidUserId("must not be empty"))
  }
  if user_id.length() > MAX_USER_ID_LEN {
    return Err(
      MoomemError::InvalidUserId(
        "must not exceed \{MAX_USER_ID_LEN} characters (got \{user_id.length()})",
      ),
    )
  }
  for c in user_id.iter() {
    if !is_valid_user_id_char(c) {
      return Err(
        MoomemError::InvalidUserId(
          "illegal character '\{c}' (allowed set: [A-Za-z0-9_-.]) in '\{user_id}'",
        ),
      )
    }
  }
  if user_id == "." || user_id == ".." {
    return Err(
      MoomemError::InvalidUserId(
        "must not be path component reference '\{user_id}'",
      ),
    )
  }
  Ok(())
}

///|
fn is_valid_user_id_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '-' ||
  c == '.'
}

// ---------------------------------------------------------------------------
// 包内工具：稳定哈希 / 十六进制 / 条目 id 生成
// ---------------------------------------------------------------------------

///|
/// Array[String] 的展示格式（与原 derive(Show) 一致：[a, b, c]）。
fn show_string_array(arr : Array[String]) -> String {
  let buf = StringBuilder()
  buf.write_char('[')
  for i, s in arr {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(s)
  }
  buf.write_char(']')
  buf.to_string()
}

///|
/// Int64? 的展示格式（与原 derive(Show) 一致：Some(v) / None）。
fn show_int64_opt(v : Int64?) -> String {
  match v {
    Some(x) => "Some(\{x})"
    None => "None"
  }
}

///|
/// FNV-1a 32bit 稳定哈希（三后端确定性一致，用于嵌入分桶与内容指纹）。
fn fnv1a(s : String) -> Int {
  let mut h : Int = 0x0811c9dc5
  for c in s.iter() {
    h = (h ^ c.to_int()) * 0x01000193
  }
  h
}

///|
/// 非负整数的十六进制小写串，左侧补零至 width 位。
fn to_hex_padded(value : Int, width : Int) -> String {
  let mut s = value.to_string(radix=16)
  while s.length() < width {
    s = "0" + s
  }
  s
}

///|
/// 条目 id："{seq 12位hex}-{rand 4 hex}"。
/// rand 部分由 (content, seq, created_at) 哈希派生——确定性且三后端一致，
/// 测试可精确断言；seq 保证全局唯一与恢复续接。
fn generate_entry_id(seq : Int, content : String, created_at : Int64) -> String {
  let seq_hex = to_hex_padded(seq, 12)
  let seed = fnv1a("\{content}:\{seq}:\{created_at.to_string()}") & 0xFFFF
  let rand_hex = to_hex_padded(seed, 4)
  "\{seq_hex}-\{rand_hex}"
}

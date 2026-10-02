// 黑盒补充：边缘场景、边界值、状态机不变量。
// 断言写的是契约。和实现冲突时，先当实现有问题。

// ---------------------------------------------------------------------------
// 测试辅助(前缀 adversarial_，与同包其它测试符号分开)
// ---------------------------------------------------------------------------

///|
/// 恒 Replace 裁决。与 store_test 里的 StoreAlwaysReplaceJudge 分开定义。
struct AdversarialAlwaysReplaceJudge {}

///|
impl ConflictJudge for AdversarialAlwaysReplaceJudge with fn judge(_, _, candidates) {
  Ok(
    candidates.map(c => @src.ConflictVerdict::{
      existing: c,
      decision: Replace,
    }),
  )
}

///|
/// 单热点嵌入器:一切文本映射到同一单位向量(构造确定性 supersede 链)
struct AdversarialOneHotEmbedder {}

///|
fn adversarial_onehot_vector() -> Array[Double] {
  let v = Array::make(@src.DEFAULT_DIM, 0.0)
  v[0] = 1.0
  v
}

///|
impl Embedder for AdversarialOneHotEmbedder with fn embed(_self, texts) {
  Ok(texts.map(_ => adversarial_onehot_vector()))
}

///|
impl Embedder for AdversarialOneHotEmbedder with fn dim(_self) {
  @src.DEFAULT_DIM
}

///|
/// 唯一维度嵌入器:按文本末尾数字 N 映射到第 (N mod 256) 维 one-hot。
/// 规模测试注入用:规避 HashingEmbedder 256 桶生日碰撞(约 6 对/55 token,
/// 碰撞对 cos=1.0 会触发缺省 judge 的合法 supersede,干扰"全部 active"前提)。
struct AdversarialUniqueEmbedder {}

///|
fn adversarial_trailing_number(text : String) -> Int {
  let mut acc = 0
  for c in text.iter() {
    if c >= '0' && c <= '9' {
      acc = acc * 10 + (c.to_int() - 48)
    } else {
      acc = 0
    }
  }
  acc
}

///|
fn adversarial_unique_vector(text : String) -> Array[Double] {
  let v = Array::make(@src.DEFAULT_DIM, 0.0)
  v[adversarial_trailing_number(text) % @src.DEFAULT_DIM] = 1.0
  v
}

///|
impl Embedder for AdversarialUniqueEmbedder with fn embed(_self, texts) {
  Ok(texts.map(t => adversarial_unique_vector(t)))
}

///|
impl Embedder for AdversarialUniqueEmbedder with fn dim(_self) {
  @src.DEFAULT_DIM
}

///|
fn adversarial_open(
  backend : &@src.PersistenceBackend,
  judge : &@src.ConflictJudge?,
  extractor : &@src.Extractor?,
  clock : &@src.Clock?,
  embedder : &@src.Embedder?,
) -> Result[@src.MemoryStore, @src.MoomemError] {
  let cfg : @src.Config = @src.Config::{
    ..@src.Config::default(),
    embedder,
    extractor,
    judge,
    persistence: Some(backend),
    clock,
  }
  @src.MemoryStore::open("memory://adversarial", config=cfg)
}

///|
fn adversarial_open_default(
  backend : &@src.PersistenceBackend,
) -> Result[@src.MemoryStore, @src.MoomemError] {
  adversarial_open(backend, None, None, None, None)
}

///|
/// 两位零填充序号(01..99)
fn adversarial_padded_number(n : Int) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
/// 一行快照条目 JSON。字段与 README 快照节一致，不调用包内编解码。
fn adversarial_entry_line(
  id : String,
  user_id : String,
  content : String,
  embedding : Array[Double],
  keywords : Array[String],
  created_at : Int,
  seq : Int,
) -> String {
  let obj : Map[String, Json] = Map([])
  obj.set("id", Json::string(id))
  obj.set("user_id", Json::string(user_id))
  obj.set("content", Json::string(content))
  obj.set("kind", Json::string("unstructured"))
  obj.set("embedding", Json::array(embedding.map(v => Json::number(v))))
  obj.set("keywords", Json::array(keywords.map(k => Json::string(k))))
  obj.set("status", Json::string("active"))
  obj.set("created_at", Json::number(created_at.to_double()))
  obj.set("superseded_by", Json::null())
  obj.set("seq", Json::number(seq.to_double()))
  obj.set("metadata", Json::object(Map([])))
  Json::object(obj).stringify()
}

// ---------------------------------------------------------------------------
// 空库与未知用户
// ---------------------------------------------------------------------------

///|
test "empty store recall returns empty; unknown user returns empty" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 空库:任意查询确定性返回空列表(不编造)
  let none = match store.recall("qa-x", "任何查询") {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(none.length(), content="0")
  let st0 = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st0.total, content="0")
  inspect(st0.last_write_at == None, content="true")
  inspect(st0.bytes_on_disk == 0L, content="true")
  // 有其他用户数据后,未知用户仍返回空(分片隔离)
  let ok = match store.add("qa-y", "有内容的记忆条目") {
    Ok(_) => true
    Err(_) => false
  }
  inspect(ok, content="true")
  let stranger = match store.recall("qa-x", "有内容") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(stranger.length(), content="0")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// top_k 边界
// ---------------------------------------------------------------------------

///|
test "top_k boundaries (0 / negative / 3 / default / 51)" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  for i = 1; i <= 7; i = i + 1 {
    // "册NN" 方案:条目两两仅共享 1/2 token(cos=0.5 < 阈值-0.15),
    // 避免误触发缺省 SimilarityJudge 的合法 supersede/Coexist 级联
    let ok = match store.add("qa-topk", "册\{adversarial_padded_number(i)}") {
      Ok(s) => s.inserted == 1
      Err(_) => false
    }
    inspect(ok, content="true")
  }
  // top_k=0 与负数:回落缺省 5
  let r0 = match store.recall("qa-topk", "册", top_k=0) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(r0.length(), content="5")
  let rneg = match store.recall("qa-topk", "册", top_k=-3) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(rneg.length(), content="5")
  // 合法区间内精确生效
  let r3 = match store.recall("qa-topk", "册", top_k=3) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(r3.length(), content="3")
  // 缺省 = 5
  let rdef = match store.recall("qa-topk", "册") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(rdef.length(), content="5")
  // 51 超上限:夹取到 MAX_RECALL_TOP_K=50,但不超过实际条目数(7)
  let r51 = match store.recall("qa-topk", "册", top_k=51) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(r51.length(), content="7")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// 同用户 55+ 条目:索引正确性 / MAX_RECALL_TOP_K / 规模下隔离
// ---------------------------------------------------------------------------

///|
test "55+ entries BM25/vector correctness, top_k cap 50, isolation at scale" {
  let backend = @src.MemoryBackend::new()
  // 注入唯一维度嵌入器,保证 55 条互不相似(全部保持 active)
  let embedder : &@src.Embedder = AdversarialUniqueEmbedder::{ }
  let store = match adversarial_open(backend, None, None, None, Some(embedder)) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 两个用户各 55 条,内容字符串相同(靠 id 分片区分)
  for i = 1; i <= 55; i = i + 1 {
    let ok1 = match store.add("qa-many", "册\{adversarial_padded_number(i)}") {
      Ok(s) => s.inserted == 1
      Err(_) => false
    }
    inspect(ok1, content="true")
    let ok2 = match store.add("qa-many2", "册\{adversarial_padded_number(i)}") {
      Ok(s) => s.inserted == 1
      Err(_) => false
    }
    inspect(ok2, content="true")
  }
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="110")
  inspect(st.active, content="110")
  // 精确命中:唯一 token "17" 应让 17 号条目排第一(top_k=1 无补齐干扰)
  for probe in [17, 42, 55] {
    let hit = match store.recall("qa-many", "\{adversarial_padded_number(probe)}", top_k=1) {
      Ok(r) => r
      Err(_) => {
        inspect("recall failed", content="SHOULD NOT REACH")
        return
      }
    }
    inspect(hit.length(), content="1")
    inspect(hit[0].content, content="册\{adversarial_padded_number(probe)}")
    inspect(hit[0].user_id, content="qa-many")
  }
  // 上限夹取:55 条可检索,但一次最多返回 50
  let capped = match store.recall("qa-many", "册", top_k=51) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(capped.length(), content="50")
  let capped60 = match store.recall("qa-many", "册", top_k=60) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(capped60.length(), content="50")
  // 无重复 id,且全部属于 qa-many 分片
  let own_ids = match store.list_entries("qa-many") {
    Ok(es) => es.map(e => e.id)
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(own_ids.length(), content="55")
  let seen : Map[String, Bool] = Map([])
  let mut dup = false
  let mut leaked = false
  for e in capped {
    if seen.contains(e.id) {
      dup = true
    }
    seen.set(e.id, true)
    if !own_ids.contains(e.id) {
      leaked = true
    }
  }
  inspect(dup, content="false")
  inspect(leaked, content="false")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// supersede 链:A→B→C,恢复后不可复活,链可延续
// ---------------------------------------------------------------------------

///|
test "supersede chain A->B->C; restore keeps superseded invisible" {
  let backend = @src.MemoryBackend::new()
  let embedder : &@src.Embedder = AdversarialOneHotEmbedder::{ }
  let judge : &@src.ConflictJudge = AdversarialAlwaysReplaceJudge::{ }
  let store = match adversarial_open(backend, Some(judge), None, None, Some(embedder)) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("qa-chain", "东城区一号老住址"))
  let s2 = match store.add("qa-chain", "西城区二号新住址") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s2.superseded, content="1")
  inspect(s2.inserted, content="1")
  let s3 = match store.add("qa-chain", "海淀区三号最新住址") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s3.superseded, content="1")
  // 链断言:A.superseded_by=B, B.superseded_by=C, C active
  let entries = match store.list_entries("qa-chain") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries.length(), content="3")
  let a_by = match entries[0].superseded_by {
    Some(id) => id
    None => "NONE"
  }
  inspect(a_by, content="\{entries[1].id}")
  let b_by = match entries[1].superseded_by {
    Some(id) => id
    None => "NONE"
  }
  inspect(b_by, content="\{entries[2].id}")
  inspect(entries[2].superseded_by == None, content="true")
  // 被覆盖者在检索中不可见(双索引已摘除)。
  // 注意:本测试注入的 AdversarialOneHotEmbedder 使任意查询与任意文档余弦恒为 1.0,
  // 向量路必然命中当前唯一 active 的链尾 C —— 因此正确判据是
  // "结果中不得出现 A / B",而非"零命中"(后者在该嵌入器下不可能成立)
  let old_hit = match store.recall("qa-chain", "东城") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  for e in old_hit {
    inspect(e.is_recallable(), content="true")
    if e.content == "东城区一号老住址" ||
      e.content == "西城区二号新住址" {
      inspect("superseded entry recalled", content="SHOULD NOT REACH")
    }
  }
  // 只有链尾可检索
  let only_tail = match store.recall("qa-chain", "住址") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(only_tail.length(), content="1")
  inspect(only_tail[0].content, content="海淀区三号最新住址")
  // stats 反映状态机
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="3")
  inspect(st.superseded, content="2")
  inspect(st.active, content="1")
  ignore(store.close())
  // "进程重启":superseded 不得复活
  let store2 = match adversarial_open(backend, None, None, None, Some(embedder)) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let after = match store2.recall("qa-chain", "住址") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(after.length(), content="1")
  inspect(after[0].content, content="海淀区三号最新住址")
  let st2 = match store2.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st2.total, content="3")
  inspect(st2.superseded, content="2")
  // 对已 superseded 条目 forget(ById):不可检索 → 0,无状态变更
  let entries2 = match store2.list_entries("qa-chain") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  let removed = match store2.forget("qa-chain", ById(entries2[0].id)) {
    Ok(n) => n
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(removed, content="0")
  // supersede 摘除去重指纹后,同内容可重新入库并延续链(覆盖当前链尾)
  let readd = match store2.add("qa-chain", "东城区一号老住址") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(readd.inserted, content="1")
  inspect(readd.duplicates, content="0")
  inspect(readd.superseded, content="1")
  let st3 = match store2.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st3.total, content="4")
  inspect(st3.superseded, content="3")
  inspect(st3.active, content="1")
  ignore(store2.close())
}

// ---------------------------------------------------------------------------
// forget 后同内容重写不被去重拦截
// ---------------------------------------------------------------------------

///|
test "forget unregisters dedup fingerprint; re-add works" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let first = match store.add("qa-rea", "唯一指纹内容XYZ") {
    Ok(s) => s
    Err(_) => {
      inspect("add failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(first.inserted, content="1")
  let entries = match store.list_entries("qa-rea") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  let removed = match store.forget("qa-rea", ById(entries[0].id)) {
    Ok(n) => n
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(removed, content="1")
  // 同内容重写:应作为新条目入库(而非误判 duplicate)
  let readd = match store.add("qa-rea", "唯一指纹内容XYZ") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(readd.inserted, content="1")
  inspect(readd.duplicates, content="0")
  let recalled = match store.recall("qa-rea", "唯一指纹", top_k=1) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(recalled.length(), content="1")
  inspect(recalled[0].content, content="唯一指纹内容XYZ")
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="2")
  inspect(st.deleted, content="1")
  inspect(st.active, content="1")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// 超长条目：内容完整保留
// ---------------------------------------------------------------------------

///|
test "very long entry stored intact, survives restart" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let sb = StringBuilder()
  sb.write_string("长文本锚点")
  for i = 0; i < 20000; i = i + 1 {
    sb.write_char('x')
  }
  let long_text = sb.to_string()
  let summary = match store.add("qa-long", long_text) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(summary.inserted, content="1")
  // 内容不丢字、不改写
  let recalled = match store.recall("qa-long", "长文本锚点", top_k=1) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(recalled.length(), content="1")
  inspect(recalled[0].content == long_text, content="true")
  // 缺省路径不截断，也不写 truncated 标记。此处记录实际行为：
  // 缺省 HashingEmbedder 无长度上限,故该场景不会触发,亦无 truncated 元数据
  inspect(recalled[0].metadata.get("truncated") == None, content="true")
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.bytes_on_disk >= 20000L, content="true")
  ignore(store.close())
  // 重启后长内容仍完整
  let store2 = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let recalled2 = match store2.recall("qa-long", "长文本锚点", top_k=1) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(recalled2.length(), content="1")
  inspect(recalled2[0].content == long_text, content="true")
  ignore(store2.close())
}

// ---------------------------------------------------------------------------
// 去重为"归一化指纹 + 按 user 分片"
// ---------------------------------------------------------------------------

///|
test "duplicate detection is normalization-based and per-user" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let s1 = match store.add("qa-dup", "Hello World 记忆") {
    Ok(s) => s
    Err(_) => {
      inspect("add failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s1.inserted, content="1")
  // 大小写归一化后视为同一指纹
  let s2 = match store.add("qa-dup", "hello world 记忆") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s2.duplicates, content="1")
  inspect(s2.inserted, content="0")
  // 跨 user 不去重(隔离)
  let s3 = match store.add("qa-dup2", "hello world 记忆") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s3.inserted, content="1")
  inspect(s3.duplicates, content="0")
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="2")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// 零命中不补齐(不变量:无结果返回空列表,不编造)
// ---------------------------------------------------------------------------

///|
test "zero-hit query returns empty even when user has entries" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  for i = 1; i <= 3; i = i + 1 {
    let ok = match store.add("qa-zero", "册\{adversarial_padded_number(i)}") {
      Ok(s) => s.inserted == 1
      Err(_) => false
    }
    inspect(ok, content="true")
  }
  // 零命中:即使该 user 有 3 条可检索记忆,也不得用它们"编造"补齐
  let none = match store.recall("qa-zero", "量子纠缠探测器") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(none.length(), content="0")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// 配置校验
// ---------------------------------------------------------------------------

///|
test "config validation rejects illegal values" {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let mk_cfg = (dim : Int, rrf_k : Int, rc : Int, thr : Double) => {
    let cfg : @src.Config = @src.Config::{
      ..@src.Config::default(),
      persistence: Some(backend),
      dim,
      rrf_k,
      recall_candidates: rc,
      supersede_threshold: thr,
    }
    cfg
  }
  let rejected = (cfg : @src.Config) => {
    match @src.MemoryStore::open("memory://adversarial", config=cfg) {
      Err(InvalidOperation(_)) => true
      _ => false
    }
  }
  inspect(rejected(mk_cfg(0, 60, 0, 0.82)), content="true")
  inspect(rejected(mk_cfg(256, 0, 0, 0.82)), content="true")
  inspect(rejected(mk_cfg(256, 60, -1, 0.82)), content="true")
  inspect(rejected(mk_cfg(256, 60, 0, 0.0)), content="true")
  inspect(rejected(mk_cfg(256, 60, 0, 1.01)), content="true")
  // 边界值 1.0 合法
  let ok_at_one = match
    @src.MemoryStore::open("memory://adversarial", config=mk_cfg(256, 60, 0, 1.0)) {
    Ok(_) => true
    Err(_) => false
  }
  inspect(ok_at_one, content="true")
}

// ---------------------------------------------------------------------------
// 时钟单调性:LogicalClock 跨重启续接;FixedClock 恒定
// ---------------------------------------------------------------------------

///|
test "LogicalClock strictly monotonic across reopen; FixedClock constant" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  for text in ["第一条记忆", "第二条记忆", "第三条记忆"] {
    let ok = match store.add("qa-clock", text) {
      Ok(_) => true
      Err(_) => false
    }
    inspect(ok, content="true")
  }
  let entries = match store.list_entries("qa-clock") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries.length(), content="3")
  inspect(entries[0].created_at, content="1")
  inspect(entries[1].created_at, content="2")
  inspect(entries[2].created_at, content="3")
  ignore(store.close())
  // 重启后时钟从快照 header 续接,不回退、不重复
  let store2 = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store2.add("qa-clock", "重启后的记忆"))
  let entries2 = match store2.list_entries("qa-clock") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries2[3].created_at, content="4")
  ignore(store2.close())
  let store3 = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store3.add("qa-clock", "再次重启后的记忆"))
  let entries3 = match store3.list_entries("qa-clock") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries3[4].created_at, content="5")
  ignore(store3.close())
  // FixedClock:恒定值;条目仍按 seq/id 唯一
  let backend2 = @src.MemoryBackend::new()
  let clock : &@src.Clock = @src.FixedClock::new(999L)
  let store4 = match adversarial_open(backend2, None, None, Some(clock), None) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store4.add("qa-fixed", "固定时钟条目甲"))
  ignore(store4.add("qa-fixed", "固定时钟条目乙"))
  let entries4 = match store4.list_entries("qa-fixed") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries4[0].created_at, content="999")
  inspect(entries4[1].created_at, content="999")
  inspect(entries4[0].id != entries4[1].id, content="true")
  ignore(store4.close())
}

// ---------------------------------------------------------------------------
// user_id 边界(经 store 入口)
// ---------------------------------------------------------------------------

///|
test "user_id boundaries through store entrance" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 64 字符:通过(上边界)
  let half = "abcdefghijklmnopqrstuvwxyzabcdef" // 32
  let id64 = half + half
  let ok64 = match store.add(id64, "六十四字符用户") {
    Ok(s) => s.inserted == 1
    Err(_) => false
  }
  inspect(ok64, content="true")
  let hit64 = match store.recall(id64, "六十四", top_k=1) {
    Ok(r) => r.length() == 1
    Err(_) => false
  }
  inspect(hit64, content="true")
  // 65 字符:所有入口一致拒绝
  let id65 = id64 + "q"
  let add65 = match store.add(id65, "x") {
    Err(InvalidUserId(_)) => true
    _ => false
  }
  inspect(add65, content="true")
  let recall65 = match store.recall(id65, "x") {
    Err(InvalidUserId(_)) => true
    _ => false
  }
  inspect(recall65, content="true")
  let list65 = match store.list_entries(id65) {
    Err(InvalidUserId(_)) => true
    _ => false
  }
  inspect(list65, content="true")
  let forget65 = match store.forget(id65, All) {
    Err(InvalidUserId(_)) => true
    _ => false
  }
  inspect(forget65, content="true")
  // 精确 "." / ".." 拒绝;空串拒绝
  for bad in [".", "..", ""] {
    let rejected = match store.add(bad, "x") {
      Err(InvalidUserId(_)) => true
      _ => false
    }
    inspect(rejected, content="true")
  }
  // 字符集允许点。只有精确 "." / ".." 被拒绝，更长的点串可以。
  let ok3dots = match store.add("...", "三连点用户") {
    Ok(s) => s.inserted == 1
    Err(_) => false
  }
  inspect(ok3dots, content="true")
  let okmid = match store.add("user..42", "点中缀用户") {
    Ok(s) => s.inserted == 1
    Err(_) => false
  }
  inspect(okmid, content="true")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// 导入容错与维度失配恢复
// ---------------------------------------------------------------------------

///|
test "import tolerates corrupted lines; dim-mismatched entry keyword-recallable" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let good1 = adversarial_entry_line(
    "000000000001-0001",
    "qa-io",
    "导入有效条目一",
    [],
    [],
    1,
    1,
  )
  let good2 = adversarial_entry_line(
    "000000000002-0002",
    "qa-io",
    "导入有效条目二",
    [],
    [],
    2,
    2,
  )
  // 中间夹一行损坏 JSON:跳过而非整体失败
  let jsonl = good1 + "\n{这不是合法的JSON!!!\n" + good2 + "\n"
  let (imported, skipped) = match store.import_jsonl(jsonl) {
    Ok(pair) => pair
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(imported, content="2")
  inspect(skipped, content="1")
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="2")
  // 嵌入维度与配置不符(如配置变更后导入):仅入关键词索引,仍可召回
  // 查询「维度锚点」的分词要能命中 keywords。字段名与 README 快照行一致。
  let odd = adversarial_entry_line(
    "000000000100-0064",
    "qa-io",
    "维度锚点记忆",
    [0.5, 0.5, 0.5],
    ["维", "度", "锚", "点", "记", "忆", "维度", "度锚", "锚点", "点记", "记忆"],
    100,
    100,
  )
  let backend2 = @src.MemoryBackend::new()
  let store2 = match adversarial_open_default(backend2) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let (imported2, skipped2) = match
    store2.import_jsonl(odd) {
    Ok(pair) => pair
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(imported2, content="1")
  inspect(skipped2, content="0")
  let hit = match store2.recall("qa-io", "维度锚点", top_k=1) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(hit.length(), content="1")
  inspect(hit[0].content, content="维度锚点记忆")
  // 再导出→再导入:维度失配条目往返不丢
  let exported = match store2.export_jsonl() {
    Ok(t) => t
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let backend3 = @src.MemoryBackend::new()
  let store3 = match adversarial_open_default(backend3) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let (imported3, _) = match store3.import_jsonl(exported) {
    Ok(pair) => pair
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(imported3, content="1")
  let hit3 = match store3.recall("qa-io", "维度锚点", top_k=1) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(hit3.length(), content="1")
  inspect(hit3[0].content, content="维度锚点记忆")
  inspect(hit3[0].embedding.length(), content="3")
  ignore(store.close())
  ignore(store2.close())
  ignore(store3.close())
}

// ---------------------------------------------------------------------------
// 导入必须拒绝非法 user_id，含路径穿越字符的条目不得入库
// ---------------------------------------------------------------------------

///|
test "import must not silently accept entries with illegal user_id" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let evil = adversarial_entry_line(
    "000000000009-00ff",
    "../evil",
    "越权条目",
    [],
    [],
    9,
    9,
  )
  // 契约:非法 user_id 的条目不得进入记忆库(逐行跳过或整体报错均可接受)
  let imported = match store.import_jsonl(evil) {
    Ok((n, _)) => n
    Err(_) => 0
  }
  inspect(imported, content="0")
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="0")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// 导出→导入与既有内容重叠:按内容指纹跳过
// ---------------------------------------------------------------------------

///|
test "export/import overlapping content skipped via dedup" {
  let backend_a = @src.MemoryBackend::new()
  let store_a = match adversarial_open_default(backend_a) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store_a.add("qa-imp", "重叠内容ABC"))
  let exported = match store_a.export_jsonl() {
    Ok(t) => t
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store_a.close())
  // 目标库已有同 user 同内容(不同 id):导入应跳过,不产生第二条
  let backend_b = @src.MemoryBackend::new()
  let store_b = match adversarial_open_default(backend_b) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store_b.add("qa-imp", "重叠内容ABC"))
  let (imported, skipped) = match store_b.import_jsonl(exported) {
    Ok(pair) => pair
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(imported, content="0")
  inspect(skipped, content="1")
  let entries = match store_b.list_entries("qa-imp") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries.length(), content="1")
  ignore(store_b.close())
}

// ---------------------------------------------------------------------------
// 空导出 / 空导入
// ---------------------------------------------------------------------------

///|
test "empty export and empty import are no-ops" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let exported = match store.export_jsonl() {
    Ok(t) => t
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(exported == "", content="true")
  let (imported, skipped) = match store.import_jsonl("") {
    Ok(pair) => pair
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(imported, content="0")
  inspect(skipped, content="0")
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="0")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// close 后一切入口拒绝(补全覆盖:forget/stats/export/import/list)
// ---------------------------------------------------------------------------

///|
test "closed store rejects forget/stats/export/import/list too" {
  let backend = @src.MemoryBackend::new()
  let store = match adversarial_open_default(backend) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("qa-closed", "关闭前的记忆"))
  ignore(store.close())
  let f1 = match store.forget("qa-closed", All) {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(f1, content="true")
  let f2 = match store.stats() {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(f2, content="true")
  let f3 = match store.export_jsonl() {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(f3, content="true")
  let f4 = match store.import_jsonl("") {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(f4, content="true")
  let f5 = match store.list_entries("qa-closed") {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(f5, content="true")
  let f6 = match store.recall("qa-closed", "记忆") {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(f6, content="true")
  let f7 = match store.add("qa-closed", "再写") {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(f7, content="true")
}

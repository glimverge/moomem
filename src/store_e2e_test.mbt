// 端到端黑盒测试：MemoryStore 六方法全链路（T04/T05 验收）。
// 覆盖：AC-01 持久化重启一致 / AC-02 跨用户零渗透 / AC-04 冲突 supersede /
//       AC-05 LLM 不可用降级 / 崩溃恢复 / user_id 非法拒绝 / 导入导出等价。

// ---------------------------------------------------------------------------
// 测试用 mock 注入（注入 mock 而非 mock 框架，架构文档 7.8）
// ---------------------------------------------------------------------------

/// 恒 Replace 裁决（AC-04：注入确定性 judge 验收状态机）
struct AlwaysReplaceJudge {}

impl ConflictJudge for AlwaysReplaceJudge with judge(_, _, candidates) {
  Ok(candidates.map(c =>
    @src.ConflictVerdict::{ existing : c, decision : Replace }
  ))
}

/// 恒失败提取器（AC-05：LLM 不可用降级）
struct FailingExtractor {}

impl Extractor for FailingExtractor with extract(_, _, _) {
  Err(@src.MoomemError::ExtractionFailure("llm service unavailable (mock)"))
}

impl Extractor for FailingExtractor with mode(_) {
  "llm"
}

/// 主题 mock 嵌入器（AC-04：模拟语义嵌入把"住址"类陈述映射到相近向量，
/// 使冲突候选检索能命中语义相关但字面不同的旧事实）
struct ResidenceTopicEmbedder {}

impl Embedder for ResidenceTopicEmbedder with embed(_self, texts) {
  Ok(texts.map(t => residence_topic_vec(t)))
}

impl Embedder for ResidenceTopicEmbedder with dim(_self) {
  @src.DEFAULT_DIM
}

fn residence_topic_vec(text : String) -> Array[Double] {
  let v = Array::make(@src.DEFAULT_DIM, 0.0)
  if text.contains("住") || text.contains("搬到") {
    v[0] = 1.0
  } else {
    v[1] = 1.0
  }
  v
}

/// 用 MemoryBackend 构造 store 的辅助（缺省确定性注入点；None 走缺省实现）
fn open_memory_store(
  backend : &@src.PersistenceBackend,
  judge : &@src.ConflictJudge?,
  extractor : &@src.Extractor?,
  clock : &@src.Clock?,
  embedder : &@src.Embedder?
) -> Result[@src.MemoryStore, @src.MoomemError] {
  let cfg : @src.Config = @src.Config::{
    embedder,
    extractor,
    judge,
    persistence : Some(backend),
    clock,
    dim : @src.DEFAULT_DIM,
    rrf_k : @src.DEFAULT_RRF_K,
    recall_candidates : 0,
    supersede_threshold : @src.DEFAULT_SUPERSEDE_THRESHOLD,
  }
  @src.MemoryStore::open("memory://test", config=cfg)
}

fn ids_of(entries : Array[@src.MemoryEntry]) -> Array[String] {
  entries.map(e => e.id)
}

// ---------------------------------------------------------------------------
// AC-01 持久化：重启后 recall 结果集一致
// ---------------------------------------------------------------------------

test "AC-01: restart consistency via MemoryBackend" {
  let backend = @src.MemoryBackend::new()
  let store1 = match open_memory_store(backend, None, None, None, None) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store1.add("user-42", "我对花生过敏"))
  ignore(store1.add("user-42", "我喜欢清淡的粤菜"))
  ignore(store1.add("user-43", "user-43 的秘密"))
  let before = match store1.recall("user-42", "花生过敏") {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 命中条目排第一（top_k 补齐可能带上该 user 的其他条目，属预期行为）
  inspect(before[0].content, content="我对花生过敏")
  let before_ids = ids_of(before)
  ignore(store1.close())
  // "进程重启"：同一后端重新 open
  let store2 = match open_memory_store(backend, None, None, None, None) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let after = match store2.recall("user-42", "花生过敏") {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(after.length(), content="\{before_ids.length()}") // 结果集与终止前一致
  inspect(ids_of(after) == before_ids, content="true")
  inspect(after[0].content, content="我对花生过敏")
  inspect(after[0].created_at, content="\{before[0].created_at}")
  // seq 恢复续接：新条目 id 不与旧 id 冲突，seq 单调
  let s = match store2.add("user-42", "重启后新增的记忆") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s.inserted, content="1")
  let st = match store2.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="4")
  ignore(store2.close())
}

// ---------------------------------------------------------------------------
// AC-02 隔离：跨用户检索零渗透
// ---------------------------------------------------------------------------

test "AC-02: zero cross-user leakage" {
  let backend = @src.MemoryBackend::new()
  let store = match open_memory_store(backend, None, None, None, None) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("user-A", "user-A 的秘密：住在上海"))
  ignore(store.add("user-A", "user-A 的偏好：喜欢爬山"))
  ignore(store.add("user-B", "user-B 的秘密：住在上海"))
  ignore(store.add("user-B", "user-B 的宠物：一只猫"))
  // 以 user-A 身份 recall 任意 query:结果中不得出现任何 user-B 条目
  let queries = [
    "住在上海", "秘密", "宠物", "猫", "爬山", "偏好", "完全无关的查询", "用户",
  ]
  // 正向命中集合:这些查询与 user-A 自身条目相关,必须召回 ≥1 条
  // (防止"recall 因回归全量返回空"时本测试仍然通过的漏洞)
  let positive = ["住在上海", "秘密", "爬山", "偏好"]
  for q in queries {
    let results = match store.recall("user-A", q) {
      Ok(r) => r
      Err(e) => {
        inspect(e.message(), content="SHOULD NOT REACH")
        return
      }
    }
    for e in results {
      inspect(e.user_id, content="user-A") // 出现即失败
    }
    // 结构性断言:召回 id 全部来自 user-A 分片
    let user_a_ids = match store.list_entries("user-A") {
      Ok(es) => ids_of(es)
      Err(_) => {
        inspect("list failed", content="SHOULD NOT REACH")
        return
      }
    }
    for e in results {
      if !user_a_ids.contains(e.id) {
        inspect(e.id, content="CROSS USER LEAK")
      }
    }
    // 正向断言:相关查询必须命中 user-A 自己的条目
    if positive.contains(q) {
      inspect(results.length() >= 1, content="true")
    }
  }
  // 内容级正向断言:相关查询的第一结果必须是 user-A 自己的条目
  let hit_a = match store.recall("user-A", "住在上海") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(hit_a.length() >= 1, content="true")
  inspect(hit_a[0].content, content="user-A 的秘密：住在上海")
  inspect(hit_a[0].user_id, content="user-A")
  // user-B 同理
  let results_b = match store.recall("user-B", "住在上海") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(results_b.length() >= 1, content="true")
  inspect(results_b[0].content, content="user-B 的秘密：住在上海")
  inspect(results_b[0].user_id, content="user-B")
  for e in results_b {
    inspect(e.user_id, content="user-B")
  }
  // 非法 user_id 拒绝（含路径穿越）
  for bad in ["../etc/passwd", "user/A", "", "user B"] {
    let rejected = match store.recall(bad, "任意") {
      Err(InvalidUserId(_)) => true
      _ => false
    }
    inspect(rejected, content="true")
    let add_rejected = match store.add(bad, "任意") {
      Err(InvalidUserId(_)) => true
      _ => false
    }
    inspect(add_rejected, content="true")
  }
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// AC-04 冲突：新事实覆盖旧事实（supersede）
// ---------------------------------------------------------------------------

test "AC-04: supersede old fact on conflict (injected deterministic judge)" {
  let backend = @src.MemoryBackend::new()
  let judge : &@src.ConflictJudge = AlwaysReplaceJudge::{}
  // 注入"语义"mock 嵌入器：使"住址"类陈述在候选检索中互相可见
  //（缺省 HashingEmbedder 下"北京/深圳"字面零重叠，语义冲突需 LLM 嵌入方可命中，
  //  此处用确定性 mock 等价模拟，验收状态机本身）
  let embedder : &@src.Embedder = ResidenceTopicEmbedder::{}
  let store = match open_memory_store(backend, Some(judge), None, None, Some(embedder)) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("user-42", "用户住北京"))
  let summary = match store.add("user-42", "我最近搬到深圳了") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 旧条目被覆盖
  inspect(summary.superseded, content="1")
  inspect(summary.inserted, content="1")
  // 北京条目状态为 superseded 且 recall 不再返回
  let entries = match store.list_entries("user-42") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries.length(), content="2")
  let beijing = entries[0]
  inspect(beijing.content, content="用户住北京")
  inspect(beijing.status == Superseded, content="true")
  let superseded_by = match beijing.superseded_by {
    Some(id) => id
    None => "NONE"
  }
  inspect(superseded_by, content="\{entries[1].id}") // 覆盖者 id 正确
  // 被覆盖的旧事实在检索中不可见（索引已摘除）
  let recall_old = match store.recall("user-42", "北京") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(recall_old.length(), content="0")
  // 新事实正常召回
  let recall_new = match store.recall("user-42", "深圳") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(recall_new.length(), content="1")
  inspect(recall_new[0].content, content="我最近搬到深圳了")
  // recall 只返回可检索状态
  let recalled = match store.recall("user-42", "住") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  for e in recalled {
    inspect(e.is_recallable(), content="true")
    if e.content == "用户住北京" {
      inspect("superseded recalled", content="SHOULD NOT REACH")
    }
  }
  // stats 反映状态机
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="2")
  inspect(st.active, content="1")
  inspect(st.superseded, content="1")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// AC-05 降级：LLM 不可用时 unstructured 入库且 recall 正常
// ---------------------------------------------------------------------------

test "AC-05: degraded mode with failing extractor" {
  let backend = @src.MemoryBackend::new()
  let extractor : &@src.Extractor = FailingExtractor::{}
  let store = match open_memory_store(backend, None, Some(extractor), None, None) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 第一次失败：降级为 unstructured 入库，不阻塞调用方
  let s1 = match store.add("user-42", "我对花生过敏") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s1.inserted, content="1")
  inspect(s1.degraded, content="true")
  let s2 = match store.add("user-42", "另外一条原文记忆") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s2.inserted, content="1")
  inspect(s2.degraded, content="true")
  // recall 正常工作（关键词路由命中降级条目；补齐可能带上同 user 其他条目）
  let recalled = match store.recall("user-42", "花生过敏") {
    Ok(r) => r
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(recalled.length() >= 1, content="true")
  inspect(recalled[0].content, content="我对花生过敏")
  inspect(recalled[0].kind == Unstructured, content="true")
  // 降级标记写入 metadata（12.3 可解释）
  let degraded_tag = match recalled[0].metadata.get("extraction_degraded") {
    Some(Json::String(s)) => s
    _ => "MISSING"
  }
  inspect(degraded_tag, content="true")
  // 连续第 3 次失败：返回错误（PRD 第 9 章）
  let third = match store.add("user-42", "第三条记忆") {
    Ok(_) => "OK"
    Err(ExtractionFailure(_)) => "EXTRACTION_FAILURE"
    Err(_) => "OTHER_ERROR"
  }
  inspect(third, content="EXTRACTION_FAILURE")
  // 既有记忆的读取不受影响（记忆可用性优先于智能化程度）
  let still = match store.recall("user-42", "花生过敏") {
    Ok(r) => r
    Err(_) => {
      inspect("recall broken", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(still.length() >= 1, content="true")
  inspect(still[0].content, content="我对花生过敏")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// 其余核心行为
// ---------------------------------------------------------------------------

test "add: chitchat (blank) extracts zero and stores nothing" {
  let backend = @src.MemoryBackend::new()
  let store = match open_memory_store(backend, None, None, None, None) {
    Ok(s) => s
    Err(_) => {
      inspect("open failed", content="SHOULD NOT REACH")
      return
    }
  }
  let summary = match store.add("user-42", "   \n  ") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(summary.extracted, content="0")
  inspect(summary.inserted, content="0")
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

test "add: exact duplicate not stored twice" {
  let backend = @src.MemoryBackend::new()
  let store = match open_memory_store(backend, None, None, None, None) {
    Ok(s) => s
    Err(_) => {
      inspect("open failed", content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("user-42", "我对花生过敏"))
  let summary = match store.add("user-42", "我对花生过敏") {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(summary.extracted, content="1")
  inspect(summary.duplicates, content="1")
  inspect(summary.inserted, content="0")
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="1")
  ignore(store.close())
}

test "forget: soft delete removes from recall, keeps in snapshot" {
  let backend = @src.MemoryBackend::new()
  let store = match open_memory_store(backend, None, None, None, None) {
    Ok(s) => s
    Err(_) => {
      inspect("open failed", content="SHOULD NOT REACH")
      return
    }
  }
  let s1 = match store.add("user-42", "我对花生过敏") {
    Ok(s) => s
    Err(_) => {
      inspect("add failed", content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("user-42", "我喜欢爬山"))
  // 拿到第一条的 id（list 按插入序）
  let entries = match store.list_entries("user-42") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries.length(), content="2")
  let target_id = entries[0].id
  inspect(s1.inserted, content="1")
  // ById 软删除
  let removed = match store.forget("user-42", ById(target_id)) {
    Ok(n) => n
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(removed, content="1")
  // recall 不再返回被删除条目（按内容断言；词袋哈希的桶碰撞
  // 可能让其他条目以极低相似度出现，但被删条目绝不可见）
  let recalled = match store.recall("user-42", "花生过敏") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  for e in recalled {
    inspect(e.id == target_id, content="false")
    inspect(e.is_recallable(), content="true")
  }
  // 快照保留（可审计）且状态为 Deleted
  let after = match store.list_entries("user-42") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(after.length(), content="2")
  inspect(after[0].status == Deleted, content="true")
  // 跨 user 的 forget 被拒绝（隔离）
  let cross = match store.forget("user-99", ById(after[1].id)) {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(cross, content="true")
  // 不存在的 id 报错
  let missing = match store.forget("user-42", ById("nonexistent-id")) {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(missing, content="true")
  // All 清空
  let removed_all = match store.forget("user-42", All) {
    Ok(n) => n
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(removed_all, content="1")
  // 全部删除后：索引已空，任何查询确定性返回空列表
  let empty_recall = match store.recall("user-42", "花生过敏") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(empty_recall.length(), content="0")
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.total, content="2")
  inspect(st.deleted, content="2")
  inspect(st.active, content="0")
  ignore(store.close())
}

test "recall: no result returns empty list, top_k respected" {
  let backend = @src.MemoryBackend::new()
  let store = match open_memory_store(backend, None, None, None, None) {
    Ok(s) => s
    Err(_) => {
      inspect("open failed", content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("user-42", "我对花生过敏"))
  // 无关查询：空列表，不编造
  let none = match store.recall("user-42", "量子计算机") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(none.length(), content="0")
  // top_k 上限
  let limited = match store.recall("user-42", "花生", top_k=1) {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(limited.length(), content="1")
  ignore(store.close())
}

test "clock: FixedClock makes created_at exactly assertable" {
  let backend = @src.MemoryBackend::new()
  let clock : &@src.Clock = @src.FixedClock::new(12345L)
  let store = match open_memory_store(backend, None, None, Some(clock), None) {
    Ok(s) => s
    Err(_) => {
      inspect("open failed", content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("user-42", "确定性的时间戳"))
  let entries = match store.list_entries("user-42") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries[0].created_at, content="12345")
  ignore(store.close())
}

test "closed store rejects all operations" {
  let backend = @src.MemoryBackend::new()
  let store = match open_memory_store(backend, None, None, None, None) {
    Ok(s) => s
    Err(_) => {
      inspect("open failed", content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("user-42", "x"))
  ignore(store.close())
  let rejected = match store.recall("user-42", "x") {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(rejected, content="true")
  let add_rejected = match store.add("user-42", "y") {
    Err(InvalidOperation(_)) => true
    _ => false
  }
  inspect(add_rejected, content="true")
  // 幂等 close
  let again = match store.close() {
    Ok(_) => true
    Err(_) => false
  }
  inspect(again, content="true")
}

// ---------------------------------------------------------------------------
// FR-08 导入导出等价
// ---------------------------------------------------------------------------

test "export / import equivalence" {
  let backend_a = @src.MemoryBackend::new()
  let store_a = match open_memory_store(backend_a, None, None, None, None) {
    Ok(s) => s
    Err(_) => {
      inspect("open failed", content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store_a.add("user-42", "我对花生过敏"))
  ignore(store_a.add("user-42", "我喜欢爬山"))
  ignore(store_a.add("user-43", "user-43 的记忆"))
  ignore(store_a.forget("user-42", All)) // 引入 deleted 状态条目
  ignore(store_a.add("user-44", "导出前最后一条"))
  let exported = match store_a.export_jsonl() {
    Ok(t) => t
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 在 close 前采集基准数据（各 user 的 id 与状态序列）
  let baseline : Map[String, Array[(String, Bool)]] = Map([])
  for user in ["user-42", "user-43", "user-44"] {
    let list_a = match store_a.list_entries(user) {
      Ok(es) => es
      Err(_) => {
        inspect("list a failed", content="SHOULD NOT REACH")
        return
      }
    }
    baseline.set(
      user,
      list_a.map(e => (e.id, e.is_recallable())),
    )
  }
  ignore(store_a.close())
  // 导出包含全部状态（可审计）
  let mut line_count = 0
  for l in exported.split("\n") {
    if l.trim().length() > 0 {
      line_count = line_count + 1
    }
  }
  inspect(line_count, content="4")
  // 导入到全新库
  let backend_b = @src.MemoryBackend::new()
  let store_b = match open_memory_store(backend_b, None, None, None, None) {
    Ok(s) => s
    Err(_) => {
      inspect("open failed", content="SHOULD NOT REACH")
      return
    }
  }
  let (imported, skipped) = match store_b.import_jsonl(exported) {
    Ok(pair) => pair
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(imported, content="4")
  inspect(skipped, content="0")
  // 记忆等价：各 user 的条目 id / 可检索状态逐一相同
  for user in ["user-42", "user-43", "user-44"] {
    let expected = match baseline.get(user) {
      Some(es) => es
      None => {
        inspect("baseline missing", content="SHOULD NOT REACH")
        return
      }
    }
    let list_b = match store_b.list_entries(user) {
      Ok(es) => es
      Err(_) => {
        inspect("list b failed", content="SHOULD NOT REACH")
        return
      }
    }
    inspect(list_b.length(), content="\{expected.length()}")
    for i = 0; i < expected.length(); i = i + 1 {
      inspect(list_b[i].id, content="\{expected[i].0}")
      inspect(list_b[i].is_recallable(), content="\{expected[i].1}")
    }
  }
  let recall_b = match store_b.recall("user-43", "记忆") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(recall_b.length(), content="1")
  inspect(recall_b[0].content, content="user-43 的记忆")
  // 重复导入：全部跳过（幂等）
  let (again_imported, again_skipped) = match store_b.import_jsonl(exported) {
    Ok(pair) => pair
    Err(_) => {
      inspect("import failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(again_imported, content="0")
  inspect(again_skipped, content="4")
  ignore(store_b.close())
}

test "stats: counts match reality including bytes and last write" {
  let backend = @src.MemoryBackend::new()
  let store = match open_memory_store(backend, None, None, None, None) {
    Ok(s) => s
    Err(_) => {
      inspect("open failed", content="SHOULD NOT REACH")
      return
    }
  }
  let st0 = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st0.total, content="0")
  inspect(st0.last_write_at == None, content="true")
  ignore(store.add("user-42", "一条记忆"))
  let st1 = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st1.total, content="1")
  inspect(st1.active, content="1")
  inspect(st1.extractor_mode, content="raw")
  inspect(st1.bytes_on_disk > 0L, content="true")
  inspect(st1.last_write_at == Some(1L), content="true") // LogicalClock 首个条目 = 1ms
  ignore(store.close())
}

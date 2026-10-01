// 黑盒测试：LLM 注入适配器（W2 验收）。
// 全部用脚本化 mock Provider 驱动，零网络可跑（架构文档 7.8：注入 mock 而非 mock 框架）。
// 覆盖：
//   - 正常事实提取 + 闲聊过滤（AC-03）/ kind 分类 / span 保留
//   - 非法 JSON → 重试 1 次 → 成功；重试仍失败 → 降级 unstructured
//   - 网络/鉴权失败 → 降级（不重试），原因可见
//   - 单次提取 LLM 调用预算 ≤ 2（PRD 13.3）
//   - LlmConflictJudge 全路径（无候选零调用 / 裁决映射 / 重试 / 降级 coexist）
//   - MemoryStore 端到端：注入后 supersede 状态机 / metadata 可解释

// ---------------------------------------------------------------------------
// 测试 mock：脚本化 Provider（模拟 mizchi/llm 客户端，零网络）
// ---------------------------------------------------------------------------

/// 单次 stream 调用的脚本化响应。
enum MockReply {
  /// 正常文本回复（模拟 LLM 输出）
  Text(String)
  /// 流错误（模拟网络/鉴权失败，mizchi/llm 以 StreamEvent::Error 上报）
  Fail(String)
}

/// 按调用次序回放脚本的 mock Provider。
struct ScriptedProvider {
  mut provider_name : String
  replies : Array[MockReply]
  mut calls : Int
}

fn ScriptedProvider::new(replies : Array[MockReply]) -> ScriptedProvider {
  ScriptedProvider::{
    provider_name : "scripted-mock",
    replies,
    calls : 0,
  }
}

impl @llm.Provider for ScriptedProvider with stream(
  self,
  _messages,
  _tools,
  handler
) {
  let idx = self.calls
  self.calls = self.calls + 1
  if idx < self.replies.length() {
    match self.replies[idx] {
      Text(t) => (handler.on_event)(@llm.StreamEvent::TextDelta(t))
      Fail(msg) => (handler.on_event)(@llm.StreamEvent::Error(msg))
    }
  }
  // 超出脚本长度：不产出任何事件（视为空回复）
}

impl @llm.Provider for ScriptedProvider with name(self) {
  self.provider_name
}

/// 智能回放 mock：提取请求按脚本回放；冲突判定请求从 prompt 中
/// 提取首个候选 id 并回放 replace 裁决（用于 store 端到端 supersede 验收）。
struct EchoJudgeProvider {
  extractions : Array[String]
  mut ext_idx : Int
  mut judge_calls : Int
}

fn EchoJudgeProvider::new(extractions : Array[String]) -> EchoJudgeProvider {
  EchoJudgeProvider::{ extractions, ext_idx : 0, judge_calls : 0 }
}

impl @llm.Provider for EchoJudgeProvider with stream(
  self,
  messages,
  _tools,
  handler
) {
  let last_text = messages[messages.length() - 1].get_text()
  if last_text.contains("既有记忆条目") {
    // 冲突判定请求：回显首个候选 id 的 replace 裁决
    self.judge_calls = self.judge_calls + 1
    let id = first_candidate_id(last_text)
    let resp = "{\"verdicts\":[{\"id\":\"\{id}\",\"decision\":\"replace\",\"reason\":\"地址更新\"}]}"
    (handler.on_event)(@llm.StreamEvent::TextDelta(resp))
  } else {
    // 提取请求：按脚本回放
    let idx = self.ext_idx
    self.ext_idx = self.ext_idx + 1
    if idx < self.extractions.length() {
      (handler.on_event)(@llm.StreamEvent::TextDelta(self.extractions[idx]))
    }
  }
}

impl @llm.Provider for EchoJudgeProvider with name(_) {
  "echo-judge-mock"
}

/// 从冲突判定 prompt 中提取首个 "- id: <id>" 的 id。
fn first_candidate_id(prompt : String) -> String {
  let marker = "- id: "
  match prompt.find(marker) {
    Some(pos) => {
      let start = pos + marker.length()
      let rest = prompt.view(start_offset=start).to_owned()
      match rest.find("\n") {
        Some(nl) => rest.view(end_offset=nl).to_owned()
        None => rest
      }
    }
    None => ""
  }
}

// ---------------------------------------------------------------------------
// 响应构造辅助
// ---------------------------------------------------------------------------

fn fact_json(content : String, kind : String, span : String) -> String {
  "{\"content\":\"\{content}\",\"kind\":\"\{kind}\",\"span\":\"\{span}\"}"
}

fn facts_response(items : Array[String]) -> String {
  "{\"facts\":[\{items.join(",")}]}"
}

fn verdict_json(id : String, decision : String) -> String {
  "{\"id\":\"\{id}\",\"decision\":\"\{decision}\",\"reason\":\"测试裁决\"}"
}

fn verdicts_response(items : Array[String]) -> String {
  "{\"verdicts\":[\{items.join(",")}]}"
}

fn mk_entry(id : String, content : String, kind : @src.EntryKind) -> @src.MemoryEntry {
  @src.MemoryEntry::{
    id,
    user_id : "user-42",
    content,
    kind,
    embedding : [],
    keywords : [],
    status : @src.EntryStatus::Active,
    created_at : 0L,
    superseded_by : None,
    seq : 1,
    metadata : Map([]),
  }
}

fn mk_store(
  extractor : &@src.Extractor,
  judge : &@src.ConflictJudge?
) -> Result[@src.MemoryStore, @src.MoomemError] {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg : @src.Config = @src.Config::{
    embedder : None,
    extractor : Some(extractor),
    judge,
    persistence : Some(backend),
    clock : None,
    dim : @src.DEFAULT_DIM,
    rrf_k : @src.DEFAULT_RRF_K,
    recall_candidates : 0,
    supersede_threshold : @src.DEFAULT_SUPERSEDE_THRESHOLD,
  }
  @src.MemoryStore::open("memory://llm-test", config=cfg)
}

// ---------------------------------------------------------------------------
// LlmExtractor：正常路径（AC-03）
// ---------------------------------------------------------------------------

test "LlmExtractor: 提取事实并过滤闲聊, kind/span 映射正确" {
  let provider = ScriptedProvider::new([
    Text(
      facts_response([
        fact_json("用户对花生过敏", "fact", "我对花生过敏"),
        fact_json("偏好清淡的粤菜", "preference", "我喜欢清淡的粤菜"),
        fact_json("上周去了杭州出差", "event", "上周去了杭州"),
      ]),
    ),
  ])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("user-42", "你好呀！我对花生过敏。对了，我喜欢清淡的粤菜。上周去了杭州出差。明天见！") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.to_string(), content="SHOULD NOT REACH")
      return
    }
  }
  // 闲聊（你好呀/明天见）不出现在事实里（AC-03）
  inspect(facts.length(), content="3")
  inspect(facts[0].content, content="用户对花生过敏")
  inspect(facts[0].kind == @src.EntryKind::Fact, content="true")
  inspect(facts[0].source_span == Some("我对花生过敏"), content="true")
  inspect(facts[1].kind == @src.EntryKind::Preference, content="true")
  inspect(facts[2].kind == @src.EntryKind::Event, content="true")
  inspect(facts[2].source_span == Some("上周去了杭州"), content="true")
  // 单次提取恰好 1 次 LLM 调用
  inspect(ext.llm_call_count(), content="1")
  inspect(ext.last_failure_reason() == None, content="true")
  inspect(e.mode(), content="llm")
}

test "LlmExtractor: 纯闲聊返回空数组(不入库信号)" {
  let provider = ScriptedProvider::new([Text("{\"facts\":[]}")])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("user-42", "今天天气不错，哈哈哈") {
    Ok(fs) => fs
    Err(_) => {
      inspect("extract failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="0")
  inspect(ext.llm_call_count(), content="1")
}

test "LlmExtractor: markdown 代码围栏包裹的 JSON 可解析" {
  let fenced = "```json\n" + facts_response([fact_json("用户养了一只猫", "fact", "养了一只猫")]) + "\n```"
  let provider = ScriptedProvider::new([Text(fenced)])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("user-42", "我养了一只猫，叫团子") {
    Ok(fs) => fs
    Err(_) => {
      inspect("extract failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="用户养了一只猫")
}

test "LlmExtractor: JSON 前后夹带说明文字可解析" {
  let noisy = "好的，以下是提取结果：\n" + facts_response([fact_json("用户不吃香菜", "preference", "不吃香菜")]) + "\n希望对你有帮助。"
  let provider = ScriptedProvider::new([Text(noisy)])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("user-42", "我不吃香菜") {
    Ok(fs) => fs
    Err(_) => {
      inspect("extract failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="用户不吃香菜")
  inspect(facts[0].kind == @src.EntryKind::Preference, content="true")
}

// ---------------------------------------------------------------------------
// LlmExtractor：稳定性（PRD 13.3）
// ---------------------------------------------------------------------------

test "LlmExtractor: 非法 JSON 重试 1 次后成功" {
  let provider = ScriptedProvider::new([
    Text("抱歉，我无法提取"), // 第 1 次：非法 JSON
    Text(facts_response([fact_json("用户会说日语", "fact", "会说日语")])), // 第 2 次：合法
  ])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("user-42", "我会说日语") {
    Ok(fs) => fs
    Err(_) => {
      inspect("extract failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="用户会说日语")
  // 调用预算：首次 + 重试 = 2（PRD 13.3 上限）
  inspect(ext.llm_call_count(), content="2")
  inspect(ext.last_failure_reason() == None, content="true")
}

test "LlmExtractor: 重试仍非法 → ReturnRaw 降级为原文 unstructured(不抛错)" {
  let provider = ScriptedProvider::new([
    Text("这不是JSON"), // 第 1 次：非法
    Text("还是不是JSON"), // 第 2 次（重试）：仍非法
  ])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p) // 默认 ReturnRaw
  let e : &@src.Extractor = ext
  let raw = "我对花生过敏"
  let facts = match e.extract("user-42", raw) {
    Ok(fs) => fs
    Err(_) => {
      inspect("should not propagate error", content="SHOULD NOT REACH")
      return
    }
  }
  // 降级：原文以 unstructured 返回，不抛错
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="我对花生过敏")
  inspect(facts[0].kind == @src.EntryKind::Unstructured, content="true")
  inspect(facts[0].source_span == None, content="true")
  // 失败原因对宿主可见
  let reason = match ext.last_failure_reason() {
    Some(r) => r
    None => {
      inspect("reason missing", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(reason.contains("invalid JSON"), content="true")
  // 恰好 2 次调用，不超预算
  inspect(ext.llm_call_count(), content="2")
}

test "LlmExtractor: 网络/鉴权失败 → 降级且不重试" {
  let provider = ScriptedProvider::new([
    Fail("connection refused (mock)"),
    Text("SHOULD NOT BE CALLED"), // 若实现错误重试会消耗此脚本并暴露
  ])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let raw = "我的常用邮箱是 a@b.c"
  let facts = match e.extract("user-42", raw) {
    Ok(fs) => fs
    Err(_) => {
      inspect("should degrade, not error", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="我的常用邮箱是 a@b.c")
  inspect(facts[0].kind == @src.EntryKind::Unstructured, content="true")
  let reason = match ext.last_failure_reason() {
    Some(r) => r
    None => {
      inspect("reason missing", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(reason.contains("stream error"), content="true")
  inspect(reason.contains("connection refused"), content="true")
  // 网络失败不重试：仅 1 次调用
  inspect(ext.llm_call_count(), content="1")
}

test "LlmExtractor: PropagateError 策略 → Err, store 降级结果可见原因" {
  // 两次失败脚本：第 1 次被下方直接调用消耗，第 2 次由 store.add 消耗
  let provider = ScriptedProvider::new([
    Fail("401 unauthorized (mock)"),
    Fail("401 unauthorized (mock)"),
  ])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p, degrade=PropagateError)
  let e : &@src.Extractor = ext
  let failed = match e.extract("user-42", "我住在深圳") {
    Err(_) => true
    Ok(_) => false
  }
  inspect(failed, content="true")
  // ---- store 层：降级结果可见（AddSummary.degraded / notes / metadata）----
  let store = match mk_store(e, None) {
    Ok(s) => s
    Err(err) => {
      inspect(err.to_string(), content="SHOULD NOT REACH")
      return
    }
  }
  let summary = match store.add("user-42", "我住在深圳") {
    Ok(s) => s
    Err(err) => {
      inspect(err.to_string(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(summary.degraded, content="true")
  inspect(summary.inserted, content="1")
  let mut note_has_reason = false
  for n in summary.notes {
    if n.contains("extraction degraded") && n.contains("401 unauthorized") {
      note_has_reason = true
    }
  }
  inspect(note_has_reason, content="true")
  let entries = match store.list_entries("user-42") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries.length(), content="1")
  inspect(entries[0].kind == @src.EntryKind::Unstructured, content="true")
  inspect(entries[0].metadata.get("extraction_degraded"), content="Some(String(true))")
  ignore(store.close())
}

test "LlmExtractor: 未知 kind 条目被丢弃, 全部不可用触发重试" {
  let provider = ScriptedProvider::new([
    // 第 1 次：唯一的 entry kind 非法 → 视为非法响应触发重试
    Text(facts_response(["{\"content\":\"用户情绪很好\",\"kind\":\"mood\"}"])),
    // 第 2 次：一条合法 + 一条非法 → 保留合法，不重试
    Text(
      facts_response([
        "{\"content\":\"用户情绪很好\",\"kind\":\"mood\"}",
        fact_json("用户每天晨跑", "event", "每天晨跑"),
      ]),
    ),
  ])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("user-42", "我今天心情不错，而且每天晨跑") {
    Ok(fs) => fs
    Err(_) => {
      inspect("extract failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="用户每天晨跑")
  inspect(facts[0].kind == @src.EntryKind::Event, content="true")
  inspect(ext.llm_call_count(), content="2")
}

test "LlmExtractor: max_facts 截断(宁少勿错)" {
  let many : Array[String] = []
  for i = 0; i < 20; i = i + 1 {
    many.push(fact_json("事实\{i}", "fact", ""))
  }
  let provider = ScriptedProvider::new([Text(facts_response(many))])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p, max_facts=5)
  let e : &@src.Extractor = ext
  let facts = match e.extract("user-42", "大量内容") {
    Ok(fs) => fs
    Err(_) => {
      inspect("extract failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="5")
  inspect(facts[0].content, content="事实0")
}

test "LlmExtractor: 空白文本零 LLM 调用" {
  let provider = ScriptedProvider::new([])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("user-42", "   \n  ") {
    Ok(fs) => fs
    Err(_) => {
      inspect("extract failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="0")
  inspect(ext.llm_call_count(), content="0")
}

test "LlmExtractor: 自定义 Provider 实现注入, provider 名出现在失败原因中" {
  // mizchi/llm 自带的 MockProvider 的 Provider impl 未导出（跨包不可见），
  // 宿主在自己包内实现 Provider trait 即可注入——本测试的 ScriptedProvider 即范例。
  // 这里额外验证：自定义 provider 名会出现在降级原因里（可解释性）。
  let provider = ScriptedProvider::new([Fail("dial tcp: timeout (mock)")])
  provider.provider_name = "my-openai-proxy"
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("user-42", "内容") {
    Ok(fs) => fs
    Err(_) => {
      inspect("should degrade", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].kind == @src.EntryKind::Unstructured, content="true")
  let reason = match ext.last_failure_reason() {
    Some(r) => r
    None => {
      inspect("reason missing", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(reason.contains("my-openai-proxy"), content="true")
}

// ---------------------------------------------------------------------------
// MemoryStore 集成（AC-03：LLM 注入后闲聊过滤验收）
// ---------------------------------------------------------------------------

test "store 集成: 闲聊不入库, 事实入库且 metadata 记录提取模式" {
  let provider = ScriptedProvider::new([
    Text("{\"facts\":[]}"), // 闲聊 → 0 条
    Text(
      facts_response([fact_json("用户对花生过敏", "fact", "我对花生过敏")]),
    ),
  ])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let store = match mk_store(e, None) {
    Ok(s) => s
    Err(err) => {
      inspect(err.to_string(), content="SHOULD NOT REACH")
      return
    }
  }
  // 闲聊：不入库
  let s1 = match store.add("user-42", "哈哈哈今天天气真好") {
    Ok(s) => s
    Err(err) => {
      inspect(err.to_string(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s1.extracted, content="0")
  inspect(s1.inserted, content="0")
  // 事实：入库, kind=Fact, metadata.extractor=llm
  let s2 = match store.add("user-42", "我对花生过敏") {
    Ok(s) => s
    Err(err) => {
      inspect(err.to_string(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(s2.extracted, content="1")
  inspect(s2.inserted, content="1")
  inspect(s2.degraded, content="false")
  let entries = match store.list_entries("user-42") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries.length(), content="1")
  inspect(entries[0].content, content="用户对花生过敏")
  inspect(entries[0].kind == @src.EntryKind::Fact, content="true")
  inspect(entries[0].metadata.get("extractor"), content="Some(String(llm))")
  // 检索命中（提取后的内容可被 recall）
  let hits = match store.recall("user-42", "花生过敏") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(hits.length() > 0, content="true")
  inspect(hits[0].content, content="用户对花生过敏")
  // stats 的提取模式可见（12.3 可解释）
  let st = match store.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.extractor_mode, content="llm")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// LlmConflictJudge
// ---------------------------------------------------------------------------

test "LlmConflictJudge: 无候选时零调用" {
  let provider = ScriptedProvider::new([])
  let p : &@llm.Provider = provider
  let judge = LlmConflictJudge::new(p)
  let j : &@src.ConflictJudge = judge
  let fact = @src.ExtractedFact::{
    content : "我搬到上海了",
    kind : @src.EntryKind::Event,
    source_span : None,
  }
  let verdicts = match j.judge(fact, []) {
    Ok(vs) => vs
    Err(_) => {
      inspect("judge failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(verdicts.length(), content="0")
  inspect(judge.llm_call_count(), content="0")
}

test "LlmConflictJudge: replace/coexist/ignore 裁决映射正确" {
  let cands = [
    mk_entry("cand-0001", "用户住在北京", @src.EntryKind::Fact),
    mk_entry("cand-0002", "用户喜欢北京烤鸭", @src.EntryKind::Preference),
    mk_entry("cand-0003", "用户上周去了北京出差", @src.EntryKind::Event),
  ]
  let provider = ScriptedProvider::new([
    Text(
      verdicts_response([
        verdict_json("cand-0001", "replace"),
        verdict_json("cand-0002", "coexist"),
        verdict_json("cand-0003", "ignore"),
        verdict_json("cand-9999", "replace"), // 未知 id → 丢弃
      ]),
    ),
  ])
  let p : &@llm.Provider = provider
  let judge = LlmConflictJudge::new(p)
  let j : &@src.ConflictJudge = judge
  let fact = @src.ExtractedFact::{
    content : "用户搬到上海了",
    kind : @src.EntryKind::Event,
    source_span : None,
  }
  let verdicts = match j.judge(fact, cands) {
    Ok(vs) => vs
    Err(_) => {
      inspect("judge failed", content="SHOULD NOT REACH")
      return
    }
  }
  // 未知 id 的裁决被丢弃：3 条有效
  inspect(verdicts.length(), content="3")
  inspect(verdicts[0].existing.id, content="cand-0001")
  inspect(verdicts[0].decision == @src.ConflictDecision::Replace, content="true")
  inspect(verdicts[1].decision == @src.ConflictDecision::Coexist, content="true")
  inspect(verdicts[2].decision == @src.ConflictDecision::Ignore, content="true")
  inspect(judge.llm_call_count(), content="1")
  inspect(judge.last_failure_reason() == None, content="true")
}

test "LlmConflictJudge: 非法 JSON 重试 1 次后成功" {
  let cands = [mk_entry("cand-0001", "用户住在北京", @src.EntryKind::Fact)]
  let provider = ScriptedProvider::new([
    Text("裁决:替换"), // 非法
    Text(verdicts_response([verdict_json("cand-0001", "replace")])), // 合法
  ])
  let p : &@llm.Provider = provider
  let judge = LlmConflictJudge::new(p)
  let j : &@src.ConflictJudge = judge
  let fact = @src.ExtractedFact::{
    content : "用户搬到上海了",
    kind : @src.EntryKind::Event,
    source_span : None,
  }
  let verdicts = match j.judge(fact, cands) {
    Ok(vs) => vs
    Err(_) => {
      inspect("judge failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(verdicts.length(), content="1")
  inspect(verdicts[0].decision == @src.ConflictDecision::Replace, content="true")
  inspect(judge.llm_call_count(), content="2")
}

test "LlmConflictJudge: 重试仍失败 → Err, store 降级为并存且原因可见" {
  let provider = ScriptedProvider::new([Text("垃圾"), Text("还是垃圾")])
  let p : &@llm.Provider = provider
  let judge = LlmConflictJudge::new(p)
  let j : &@src.ConflictJudge = judge
  // ---- extractor 正常, judge 持续失败 → store 降级为 coexist ----
  let ext_provider = ScriptedProvider::new([
    Text(facts_response([fact_json("用户住在北京", "fact", "住在北京")])),
    Text(
      facts_response([
        fact_json("用户住在上海", "fact", "住在上海"),
      ]),
    ),
  ])
  let ep : &@llm.Provider = ext_provider
  let ext = LlmExtractor::new(ep)
  let e : &@src.Extractor = ext
  let store = match mk_store(e, Some(j)) {
    Ok(s) => s
    Err(err) => {
      inspect(err.to_string(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("user-42", "我住在北京"))
  let summary = match store.add("user-42", "我住在上海") {
    Ok(s) => s
    Err(err) => {
      inspect(err.to_string(), content="SHOULD NOT REACH")
      return
    }
  }
  // judge 失败降级：不产生裁决 → 两条并存, degraded=true, notes 含原因
  inspect(summary.degraded, content="true")
  inspect(summary.superseded, content="0")
  inspect(summary.inserted, content="1")
  let mut note_has_reason = false
  for n in summary.notes {
    if n.contains("conflict judge degraded to coexist") {
      note_has_reason = true
    }
  }
  inspect(note_has_reason, content="true")
  // judge 侧：恰 2 次调用, 失败原因可见
  inspect(judge.llm_call_count(), content="2")
  inspect(judge.last_failure_reason() != None, content="true")
  ignore(store.close())
}

// ---------------------------------------------------------------------------
// 端到端：LLM 裁决驱动 supersede 状态机（AC-04 的 LLM 版）
// ---------------------------------------------------------------------------

test "端到端: LLM replace 裁决触发 supersede 状态机" {
  // EchoJudgeProvider: 两次提取 + 对首个候选回 replace 裁决
  let provider = EchoJudgeProvider::new([
    facts_response([fact_json("用户居住在北京", "fact", "居住在北京")]),
    facts_response([fact_json("用户现在居住在上海", "fact", "居住在上海")]),
  ])
  let p : &@llm.Provider = provider
  let ext = LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let judge = LlmConflictJudge::new(p)
  let j : &@src.ConflictJudge = judge
  let store = match mk_store(e, Some(j)) {
    Ok(s) => s
    Err(err) => {
      inspect(err.to_string(), content="SHOULD NOT REACH")
      return
    }
  }
  ignore(store.add("user-42", "我居住在北京"))
  let summary = match store.add("user-42", "我现在居住在上海") {
    Ok(s) => s
    Err(err) => {
      inspect(err.to_string(), content="SHOULD NOT REACH")
      return
    }
  }
  // LLM 裁决 replace：旧条目被 supersede
  inspect(summary.superseded, content="1")
  inspect(summary.inserted, content="1")
  let entries = match store.list_entries("user-42") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries.length(), content="2")
  let mut old_status : @src.EntryStatus? = None
  let mut new_id : String? = None
  for entry in entries {
    if entry.content == "用户居住在北京" {
      old_status = Some(entry.status)
      new_id = entry.superseded_by
    }
  }
  inspect(old_status == Some(@src.EntryStatus::Superseded), content="true")
  inspect(new_id != None, content="true")
  // recall 只返回 Active：上海可见, 北京不可见
  let hits = match store.recall("user-42", "居住") {
    Ok(r) => r
    Err(_) => {
      inspect("recall failed", content="SHOULD NOT REACH")
      return
    }
  }
  let mut beijing_visible = false
  for h in hits {
    if h.content == "用户居住在北京" {
      beijing_visible = true
    }
  }
  inspect(beijing_visible, content="false")
  ignore(store.close())
}

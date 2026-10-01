// QA 对抗性测试（W2 补充，黑盒）：LLM 提取/裁决适配器边缘场景。
// 独立于实现者自测编写（独立 mock 机制：按调用序回放完整 StreamEvent 序列，
// 覆盖 MessageStart/多段 TextDelta/MessageEnd/Error 交错时序）；
// 断言依据 PRD 13.1/13.2/13.3（提取契约 / 裁决契约 / 稳定性）。
// 不改断言迁就实现：预期与实现冲突时按"源码 bug"路由。
// 前缀 qa2_ 避免与本包既有测试文件符号冲突。

// ---------------------------------------------------------------------------
// 测试 mock：事件序列回放 Provider（区别于实现者的单事件 ScriptedProvider）
// ---------------------------------------------------------------------------

///|
/// 每次调用回放一段完整事件序列；超出脚本长度不产出任何事件（静默空响应）。
struct Qa2SeqProvider {
  scripts : Array[Array[@llm.StreamEvent]]
  mut calls : Int
}

///|
fn Qa2SeqProvider::new(
  scripts : Array[Array[@llm.StreamEvent]],
) -> Qa2SeqProvider {
  Qa2SeqProvider::{ scripts, calls: 0, }
}

///|
impl @llm.Provider for Qa2SeqProvider with fn stream(
  self,
  _messages,
  _tools,
  handler,
) {
  let idx = self.calls
  self.calls = self.calls + 1
  if idx < self.scripts.length() {
    for ev in self.scripts[idx] {
      (handler.on_event)(ev)
    }
  }
}

///|
impl @llm.Provider for Qa2SeqProvider with fn name(_) {
  "qa2-seq-mock"
}

///|
/// 构造一次正常文本回复的标准事件序列（MessageStart → TextDelta → MessageEnd）。
fn qa2_text_events(text : String) -> Array[@llm.StreamEvent] {
  [
    @llm.StreamEvent::MessageStart,
    @llm.StreamEvent::TextDelta(text),
    @llm.StreamEvent::MessageEnd(
      finish_reason=@llm.FinishReason::Stop,
      usage=None,
    ),
  ]
}

///|
/// 构造一次流错误回复的事件序列（MessageStart → Error）。
fn qa2_fail_events(msg : String) -> Array[@llm.StreamEvent] {
  [@llm.StreamEvent::MessageStart, @llm.StreamEvent::Error(msg)]
}

// ---------------------------------------------------------------------------
// 响应/条目构造辅助
// ---------------------------------------------------------------------------

///|
fn qa2_fact(content : String, kind : String, span : String) -> String {
  "{\"content\":\"\{content}\",\"kind\":\"\{kind}\",\"span\":\"\{span}\"}"
}

///|
fn qa2_facts(items : Array[String]) -> String {
  "{\"facts\":[\{items.join(",")}]}"
}

///|
fn qa2_verdicts(items : Array[String]) -> String {
  "{\"verdicts\":[\{items.join(",")}]}"
}

///|
fn qa2_entry(id : String, content : String) -> @src.MemoryEntry {
  @src.MemoryEntry::{
    id,
    user_id: "qa2-user",
    content,
    kind: @src.EntryKind::Fact,
    embedding: [],
    keywords: [],
    status: @src.EntryStatus::Active,
    created_at: 0L,
    superseded_by: None,
    seq: 1,
    metadata: Map([]),
  }
}

///|
fn qa2_store(
  extractor : &@src.Extractor,
  judge : &@src.ConflictJudge?,
) -> Result[@src.MemoryStore, @src.MoomemError] {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg : @src.Config = @src.Config::{
    embedder: None,
    extractor: Some(extractor),
    judge,
    persistence: Some(backend),
    clock: None,
    dim: @src.DEFAULT_DIM,
    rrf_k: @src.DEFAULT_RRF_K,
    recall_candidates: 0,
    supersede_threshold: @src.DEFAULT_SUPERSEDE_THRESHOLD,
  }
  @src.MemoryStore::open("memory://qa2", config=cfg)
}

// ---------------------------------------------------------------------------
// 提取契约：条目级过滤规则（宁少勿错）
// ---------------------------------------------------------------------------

///|
test "qa2: 50条合法facts默认截断为16条, 不触发重试" {
  let items : Array[String] = []
  for i = 0; i < 50; i = i + 1 {
    items.push("fact-\{i}")
  }
  let provider = Qa2SeqProvider::new([
    qa2_text_events(qa2_facts(items.map(i => qa2_fact(i, "fact", "s")))),
  ])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p) // 默认 max_facts=16
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "大量事实文本") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 截断到预算上限，保留前 16 条
  inspect(facts.length(), content="16")
  inspect(facts[0].content, content="fact-0")
  inspect(facts[15].content, content="fact-15")
  // 未触发重试（合法响应），无失败记录
  inspect(ext.llm_call_count(), content="1")
  inspect(ext.last_failure_reason() == None, content="true")
}

///|
test "qa2: content空串/纯空白条目被丢弃, 合法条目保留" {
  let resp = qa2_facts([
    qa2_fact("", "fact", "空content"),
    qa2_fact("   ", "fact", "空白content"),
    qa2_fact("用户在深圳工作", "fact", "在深圳工作"),
  ])
  let provider = Qa2SeqProvider::new([qa2_text_events(resp)])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "我在深圳工作") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="用户在深圳工作")
  inspect(ext.llm_call_count(), content="1")
}

///|
test "qa2: facts非空但content全为空串 → 视为非法响应触发重试" {
  // 第 1 次：两条 entry 的 content 均为空 → 全部不可用 → 非法（触发重试）
  let bad = qa2_facts([qa2_fact("", "fact", "x"), qa2_fact("", "event", "y")])
  // 第 2 次：合法
  let good = qa2_facts([
    qa2_fact("用户养了一只狗", "fact", "养了一只狗"),
  ])
  let provider = Qa2SeqProvider::new([
    qa2_text_events(bad),
    qa2_text_events(good),
  ])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "我养了一只狗") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="用户养了一只狗")
  inspect(ext.llm_call_count(), content="2")
}

///|
test "qa2: kind大小写变体/前后缀空白被丢弃, 仅精确小写接受" {
  let resp = qa2_facts([
    qa2_fact("大写F条目", "Fact", "x"),
    qa2_fact("全大写条目", "FACT", "x"),
    qa2_fact("尾随空格条目", "preference ", "x"),
    qa2_fact("前置空格条目", " event", "x"),
    qa2_fact("用户每天跑步", "event", "每天跑步"),
  ])
  let provider = Qa2SeqProvider::new([qa2_text_events(resp)])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "我每天跑步") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 契约：kind 只能是 "fact"/"preference"/"event" 精确小写
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="用户每天跑步")
  inspect(facts[0].kind == @src.EntryKind::Event, content="true")
}

///|
test "qa2: span非字符串或空串 → source_span为None但条目保留" {
  let resp = "{\"facts\":[{\"content\":\"用户喜欢爬山\",\"kind\":\"fact\",\"span\":123},{\"content\":\"用户会弹钢琴\",\"kind\":\"fact\",\"span\":\"\"}]}"
  let provider = Qa2SeqProvider::new([qa2_text_events(resp)])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "我喜欢爬山，会弹钢琴") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="2")
  inspect(facts[0].content, content="用户喜欢爬山")
  inspect(facts[0].source_span == None, content="true")
  inspect(facts[1].source_span == None, content="true")
}

///|
test "qa2: JSON含转义引号与嵌套对象字段, content/span保真解析" {
  let resp = "{\"facts\":[{\"content\":\"用户说\\\"你好\\\"\",\"kind\":\"fact\",\"span\":\"原文\\\"引用\\\"\",\"extra\":{\"nested\":{\"x\":1},\"list\":[1,2,3]}}]}"
  let provider = Qa2SeqProvider::new([qa2_text_events(resp)])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "我说\"你好\"") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="用户说\"你好\"")
  inspect(facts[0].source_span == Some("原文\"引用\""), content="true")
  inspect(facts[0].kind == @src.EntryKind::Fact, content="true")
}

// ---------------------------------------------------------------------------
// StreamEvent 交错时序（PRD 13.3 稳定性：网络失败不重试）
// ---------------------------------------------------------------------------

///|
test "qa2: 流中段TextDelta后Error → 视为失败不重试, 部分文本不作为响应" {
  let provider = Qa2SeqProvider::new([
    [
      @llm.StreamEvent::MessageStart,
      @llm.StreamEvent::TextDelta("{\"fac"), // 部分合法文本
      @llm.StreamEvent::Error("connection reset mid-stream"),
    ],
    qa2_text_events("SHOULD NOT BE CALLED"), // 若错误重试会消耗并暴露
  ])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let raw = "我的电话是 13800000000"
  let facts = match e.extract("qa2-user", raw) {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // 默认 ReturnRaw：降级为原文 unstructured，不抛错
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="我的电话是 13800000000")
  inspect(facts[0].kind == @src.EntryKind::Unstructured, content="true")
  let reason = match ext.last_failure_reason() {
    Some(r) => r
    None => {
      inspect("reason missing", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(reason.contains("connection reset mid-stream"), content="true")
  // 网络失败不重试：恰 1 次调用
  inspect(ext.llm_call_count(), content="1")
}

///|
test "qa2: 先Error后MessageEnd时序 → 错误不被正常收尾事件抹除" {
  let provider = Qa2SeqProvider::new([
    [
      @llm.StreamEvent::MessageStart,
      @llm.StreamEvent::Error("upstream 500"),
      @llm.StreamEvent::MessageEnd(
        finish_reason=@llm.FinishReason::Stop,
        usage=None,
      ),
      @llm.StreamEvent::TextDelta("{\"facts\":[]}"), // 错误后的迟到文本
    ],
  ])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "我在上海工作") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
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
  inspect(reason.contains("upstream 500"), content="true")
  inspect(ext.llm_call_count(), content="1")
}

///|
test "qa2: 多段TextDelta拼接 + MessageEnd携带usage → 正常解析" {
  let provider = Qa2SeqProvider::new([
    [
      @llm.StreamEvent::MessageStart,
      @llm.StreamEvent::TextDelta("{\"facts\":[{"),
      @llm.StreamEvent::TextDelta(
        "\"content\":\"多段拼接\",\"kind\":\"preference\"",
      ),
      @llm.StreamEvent::TextDelta(",\"span\":\"多段\"}]}"),
      @llm.StreamEvent::MessageEnd(
        finish_reason=@llm.FinishReason::Stop,
        usage=Some(@llm.Usage::{ input_tokens: 10, output_tokens: 20, }),
      ),
    ],
  ])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "我偏好多段输出") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="多段拼接")
  inspect(facts[0].kind == @src.EntryKind::Preference, content="true")
  inspect(ext.last_failure_reason() == None, content="true")
}

///|
test "qa2: provider静默空响应(零事件) → 视为非法触发重试" {
  let provider = Qa2SeqProvider::new([
    [], // 第 1 次：不产出任何事件 → 空文本 → 非法 JSON
    qa2_text_events(
      qa2_facts([qa2_fact("用户在杭州", "fact", "在杭州")]),
    ),
  ])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "我在杭州") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="用户在杭州")
  inspect(ext.llm_call_count(), content="2")
}

///|
test "qa2: facts字段非数组 → 非法响应触发重试后成功" {
  let provider = Qa2SeqProvider::new([
    qa2_text_events("{\"facts\":\"没有条目\"}"),
    qa2_text_events(
      qa2_facts([qa2_fact("用户是医生", "fact", "是医生")]),
    ),
  ])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p)
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "我是医生") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="用户是医生")
  inspect(ext.llm_call_count(), content="2")
}

// ---------------------------------------------------------------------------
// 参数边界
// ---------------------------------------------------------------------------

///|
test "qa2: max_facts=0被钳制为1(不产生空预算)" {
  let items = [
    qa2_fact("条目甲", "fact", "x"),
    qa2_fact("条目乙", "fact", "y"),
    qa2_fact("条目丙", "fact", "z"),
  ]
  let provider = Qa2SeqProvider::new([qa2_text_events(qa2_facts(items))])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p, max_facts=0)
  let e : &@src.Extractor = ext
  let facts = match e.extract("qa2-user", "多条内容") {
    Ok(fs) => fs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(facts.length(), content="1")
  inspect(facts[0].content, content="条目甲")
}

// ---------------------------------------------------------------------------
// DegradePolicy 两种策略：Err 路径与 store 层可见性差异锁定
// ---------------------------------------------------------------------------

///|
test "qa2: PropagateError下JSON重试仍失败 → Err含双重失败原因, 恰2次调用" {
  let provider = Qa2SeqProvider::new([
    qa2_text_events("第一次垃圾"),
    qa2_text_events("第二次垃圾"),
  ])
  let p : &@llm.Provider = provider
  let ext = @llm_extractor.LlmExtractor::new(p, degrade=PropagateError)
  let e : &@src.Extractor = ext
  let outcome = e.extract("qa2-user", "我在成都工作")
  let err = match outcome {
    Ok(_) => {
      inspect("should propagate error", content="SHOULD NOT REACH")
      return
    }
    Err(err) => err
  }
  let msg = err.message()
  inspect(msg.contains("llm extractor degraded"), content="true")
  inspect(msg.contains("invalid JSON from llm after 1 retry"), content="true")
  inspect(
    msg.contains("第一次垃圾") || msg.contains("invalid JSON"),
    content="true",
  )
  inspect(ext.llm_call_count(), content="2")
  inspect(ext.last_failure_reason() != None, content="true")
}

///|
test "qa2: DegradePolicy两策略在store层的可见性差异锁定" {
  // ---- A: ReturnRaw → store 视为成功提取, 降级仅通过 last_failure_reason 可见 ----
  let pa = Qa2SeqProvider::new([qa2_fail_events("mock 503 service unavailable")])
  let pa_ref : &@llm.Provider = pa
  let ext_a = @llm_extractor.LlmExtractor::new(pa_ref) // 默认 ReturnRaw
  let ea : &@src.Extractor = ext_a
  let store_a = match qa2_store(ea, None) {
    Ok(s) => s
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let sa = match store_a.add("qa2-user", "我在南京工作") {
    Ok(s) => s
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  // ReturnRaw：不抛错, store 层无降级标记（失败只能从 extractor 观测口读取）
  inspect(sa.degraded, content="false")
  inspect(sa.inserted, content="1")
  inspect(ext_a.last_failure_reason() != None, content="true")
  let reason_a = match ext_a.last_failure_reason() {
    Some(r) => r
    None => ""
  }
  inspect(reason_a.contains("mock 503"), content="true")
  let entries_a = match store_a.list_entries("qa2-user") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries_a.length(), content="1")
  inspect(entries_a[0].kind == @src.EntryKind::Unstructured, content="true")
  inspect(
    entries_a[0].metadata.get("extractor") == Some(Json::string("llm")),
    content="true",
  )
  // ReturnRaw 约定：store 层不标 extraction_degraded（设计差异点, 锁定防回归）
  inspect(
    entries_a[0].metadata.get("extraction_degraded") == None,
    content="true",
  )
  let st_a = match store_a.stats() {
    Ok(s) => s
    Err(_) => {
      inspect("stats failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st_a.extractor_mode, content="llm")
  ignore(store_a.close())
  // ---- B: PropagateError → store 统一降级, 全链路可见 ----
  let pb = Qa2SeqProvider::new([qa2_fail_events("mock 503 service unavailable")])
  let pb_ref : &@llm.Provider = pb
  let ext_b = @llm_extractor.LlmExtractor::new(pb_ref, degrade=PropagateError)
  let eb : &@src.Extractor = ext_b
  let store_b = match qa2_store(eb, None) {
    Ok(s) => s
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let sb = match store_b.add("qa2-user", "我在南京工作") {
    Ok(s) => s
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(sb.degraded, content="true")
  inspect(sb.inserted, content="1")
  let mut note_ok = false
  for n in sb.notes {
    if n.contains("extraction degraded to raw unstructured") &&
      n.contains("mock 503") {
      note_ok = true
    }
  }
  inspect(note_ok, content="true")
  let entries_b = match store_b.list_entries("qa2-user") {
    Ok(es) => es
    Err(_) => {
      inspect("list failed", content="SHOULD NOT REACH")
      return
    }
  }
  inspect(entries_b.length(), content="1")
  inspect(
    entries_b[0].metadata.get("extractor") == Some(Json::string("llm")),
    content="true",
  )
  inspect(
    entries_b[0].metadata.get("extraction_degraded") ==
    Some(Json::string("true")),
    content="true",
  )
  ignore(store_b.close())
}

// ---------------------------------------------------------------------------
// LlmConflictJudge：裁决解析边界
// ---------------------------------------------------------------------------

///|
test "qa2: judge同一id重复裁决 → 取第一个" {
  let cands = [qa2_entry("qc-0001", "用户住在广州")]
  let provider = Qa2SeqProvider::new([
    qa2_text_events(
      qa2_verdicts([
        "{\"id\":\"qc-0001\",\"decision\":\"replace\",\"reason\":\"第一份\"}",
        "{\"id\":\"qc-0001\",\"decision\":\"coexist\",\"reason\":\"重复\"}",
      ]),
    ),
  ])
  let p : &@llm.Provider = provider
  let judge = @llm_extractor.LlmConflictJudge::new(p)
  let j : &@src.ConflictJudge = judge
  let fact = @src.ExtractedFact::{
    content: "用户搬到重庆了",
    kind: @src.EntryKind::Event,
    source_span: None,
  }
  let verdicts = match j.judge(fact, cands) {
    Ok(vs) => vs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(verdicts.length(), content="1")
  inspect(verdicts[0].existing.id, content="qc-0001")
  inspect(
    verdicts[0].decision == @src.ConflictDecision::Replace,
    content="true",
  )
  inspect(judge.llm_call_count(), content="1")
}

///|
test "qa2: judge的decision大小写变体被丢弃, 部分合法保留" {
  let cands = [
    qa2_entry("qc-0001", "用户住在广州"),
    qa2_entry("qc-0002", "用户喜欢早茶"),
  ]
  let provider = Qa2SeqProvider::new([
    qa2_text_events(
      qa2_verdicts([
        "{\"id\":\"qc-0001\",\"decision\":\"Replace\",\"reason\":\"大写被丢弃\"}",
        "{\"id\":\"qc-0002\",\"decision\":\"ignore\",\"reason\":\"无关\"}",
      ]),
    ),
  ])
  let p : &@llm.Provider = provider
  let judge = @llm_extractor.LlmConflictJudge::new(p)
  let j : &@src.ConflictJudge = judge
  let fact = @src.ExtractedFact::{
    content: "用户搬到重庆了",
    kind: @src.EntryKind::Event,
    source_span: None,
  }
  let verdicts = match j.judge(fact, cands) {
    Ok(vs) => vs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(verdicts.length(), content="1")
  inspect(verdicts[0].existing.id, content="qc-0002")
  inspect(verdicts[0].decision == @src.ConflictDecision::Ignore, content="true")
}

///|
test "qa2: judge裁决全部不可用(未知id) → 触发重试后成功, 恰2次调用" {
  let cands = [qa2_entry("qc-0001", "用户住在广州")]
  let provider = Qa2SeqProvider::new([
    qa2_text_events(
      qa2_verdicts([
        "{\"id\":\"unknown-99\",\"decision\":\"replace\",\"reason\":\"未知id\"}",
      ]),
    ),
    qa2_text_events(
      qa2_verdicts([
        "{\"id\":\"qc-0001\",\"decision\":\"replace\",\"reason\":\"重试后正确\"}",
      ]),
    ),
  ])
  let p : &@llm.Provider = provider
  let judge = @llm_extractor.LlmConflictJudge::new(p)
  let j : &@src.ConflictJudge = judge
  let fact = @src.ExtractedFact::{
    content: "用户搬到重庆了",
    kind: @src.EntryKind::Event,
    source_span: None,
  }
  let verdicts = match j.judge(fact, cands) {
    Ok(vs) => vs
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(verdicts.length(), content="1")
  inspect(
    verdicts[0].decision == @src.ConflictDecision::Replace,
    content="true",
  )
  // 重试预算：首次 + 重试 = 2
  inspect(judge.llm_call_count(), content="2")
  inspect(judge.last_failure_reason() == None, content="true")
}

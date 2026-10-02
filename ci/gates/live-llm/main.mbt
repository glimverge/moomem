// 发版专用真实 LLM 门禁（DeepSeek / OpenAI 兼容端点）。
// 场景在本文件内。门禁只在发版流水线运行。
//
// 环境变量：DEEPSEEK_API_KEY / DEEPSEEK_BASE_URL / DEEPSEEK_MODEL
// 运行：moon run ci/gates/live-llm --target native

///|
fn require_env(key : String) -> String {
  match @env.get_env_var(key) {
    Some(raw) => {
      let v = raw.trim().to_owned()
      if v.is_empty() {
        abort("env \{key} is set but empty")
      }
      v
    }
    None => abort("missing required env \{key}")
  }
}

///|
fn normalize_base_url(raw : String) -> String {
  let mut u = raw.trim().to_owned()
  while u.has_suffix("/") {
    match u.strip_suffix("/") {
      Some(v) => u = v.to_owned()
      None => break
    }
  }
  match u.strip_suffix("/v1") {
    Some(v) => v.to_owned()
    None => u
  }
}

///|
fn[T] fail(msg : String) -> T {
  println("LIVE_LLM_FAIL: \{msg}")
  abort(msg)
}

///|
fn join_notes(notes : Array[String]) -> String {
  let buf = StringBuilder()
  let mut i = 0
  for n in notes {
    if i > 0 {
      buf.write_string("; ")
    }
    buf.write_string(n)
    i = i + 1
  }
  buf.to_string()
}

///|
fn section(id : String, title : String) -> Unit {
  println("")
  println("---- \{id} \{title} ----")
}

///|
fn mentions_any(text : String, keys : Array[String]) -> Bool {
  for k in keys {
    if text.contains(k) {
      return true
    }
  }
  false
}

///|
fn entries_mention(
  entries : Array[@src.MemoryEntry],
  keys : Array[String],
) -> Bool {
  for e in entries {
    if mentions_any(e.content, keys) {
      return true
    }
  }
  false
}

///|
fn active_mentioning(
  entries : Array[@src.MemoryEntry],
  keys : Array[String],
) -> Int {
  let mut n = 0
  for e in entries {
    if e.status == @src.EntryStatus::Active && mentions_any(e.content, keys) {
      n = n + 1
    }
  }
  n
}

///|
fn expect_add_ok(
  store : @src.MemoryStore,
  user : String,
  text : String,
) -> @src.AddSummary {
  match store.add(user, text) {
    Ok(s) => s
    Err(e) => fail("add(\{user}) error: \{e.message()} text=\{text}")
  }
}

///|
fn expect_no_store(s : @src.AddSummary, label : String) -> Unit {
  println(
    "  \{label}: extracted=\{s.extracted} inserted=\{s.inserted}",
  )
  if s.extracted != 0 || s.inserted != 0 {
    fail(
      "\{label}: expected no store, got extracted=\{s.extracted} inserted=\{s.inserted}",
    )
  }
}

///|
fn expect_inserted(s : @src.AddSummary, label : String) -> Unit {
  println(
    "  \{label}: extracted=\{s.extracted} inserted=\{s.inserted} dup=\{s.duplicates} superseded=\{s.superseded} degraded=\{s.degraded}",
  )
  if s.degraded {
    fail("\{label}: unexpectedly degraded: \{join_notes(s.notes)}")
  }
  if s.extracted < 1 || s.inserted < 1 {
    fail(
      "\{label}: expected extract+insert ≥1, got extracted=\{s.extracted} inserted=\{s.inserted}",
    )
  }
}

///|
fn list_user(
  store : @src.MemoryStore,
  user : String,
) -> Array[@src.MemoryEntry] {
  match store.list_entries(user) {
    Ok(es) => es
    Err(e) => fail("list_entries(\{user}): \{e.message()}")
  }
}

///|
fn recall_user(
  store : @src.MemoryStore,
  user : String,
  query : String,
  top_k : Int,
) -> Array[@src.MemoryEntry] {
  match store.recall(user, query, top_k~) {
    Ok(hits) => hits
    Err(e) => fail("recall(\{user}, \{query}): \{e.message()}")
  }
}

///|
fn main {
  println("=== moomem L2 live LLM gate (DeepSeek) ===")
  let api_key = require_env("DEEPSEEK_API_KEY")
  let base_url = normalize_base_url(require_env("DEEPSEEK_BASE_URL"))
  let model = require_env("DEEPSEEK_MODEL")
  println("endpoint=\{base_url} model=\{model}")

  let provider = @openai.OpenAIProvider::new(
    api_key,
    endpoint=@openai.OpenAIEndpoint::Custom(base_url~),
    model~,
    timeout_sec=120,
    max_retries=2,
  )
  let p : &@llm.Provider = provider
  let extractor = @llm_extractor.LlmExtractor::new(p)
  let judge = @llm_extractor.LlmConflictJudge::new(p)
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg : @src.Config = @src.Config::{
    ..@src.Config::default(),
    extractor: Some(extractor as &@src.Extractor),
    judge: Some(judge as &@src.ConflictJudge),
    persistence: Some(backend),
  }
  let store = match @src.MemoryStore::open("memory://llm-live", config=cfg) {
    Ok(s) => s
    Err(e) => fail("open failed: \{e.message()}")
  }

  // L2-01 多句纯闲聊
  section("L2-01", "chat-only filtering")
  let chats = [
    "今天天气真不错呀~",
    "你好呀",
    "哈哈哈谢谢你",
    "在吗？",
  ]
  for c in chats {
    expect_no_store(expect_add_ok(store, "user-chat", c), c)
  }

  // L2-02 空白
  section("L2-02", "blank / whitespace")
  let before_blank = extractor.llm_call_count()
  expect_no_store(expect_add_ok(store, "user-blank", "   "), "whitespace")
  let after_blank = extractor.llm_call_count()
  println("  llm_calls delta=\{after_blank - before_blank} (prefer 0)")
  // 空白允许 0 调用；若实现调用了也不入库即可（上式已保证）

  // L2-03 寒暄+事实
  section("L2-03", "mixed greeting + allergy fact")
  expect_inserted(
    expect_add_ok(
      store,
      "user-fact",
      "你好！我对花生过敏，平时喜欢清淡的粤菜。",
    ),
    "allergy+preference",
  )
  let fact_entries = list_user(store, "user-fact")
  if !entries_mention(fact_entries, ["过敏", "花生", "粤菜", "清淡"]) {
    fail("L2-03: stored content missing allergy/food keys")
  }
  for e in fact_entries {
    println("  [\{e.kind}/\{e.status}] \{e.content}")
  }

  // L2-04 偏好 / 事件
  section("L2-04", "preference + event phrasing")
  expect_inserted(
    expect_add_ok(store, "user-kinds", "我偏好晚上十点前睡觉。"),
    "preference",
  )
  expect_inserted(
    expect_add_ok(
      store,
      "user-kinds",
      "上周六我和朋友去了一次美术馆。",
    ),
    "event",
  )
  let kind_entries = list_user(store, "user-kinds")
  if kind_entries.length() < 2 {
    fail("L2-04: expected ≥2 stored entries, got \{kind_entries.length()}")
  }
  for e in kind_entries {
    println("  [\{e.kind}] \{e.content}")
  }

  // L2-05 metadata / stats
  section("L2-05", "explainability metadata + stats")
  let st = match store.stats() {
    Ok(s) => s
    Err(e) => fail("stats: \{e.message()}")
  }
  println("  extractor_mode=\{st.extractor_mode} total=\{st.total} active=\{st.active}")
  if !st.extractor_mode.contains("llm") {
    fail("L2-05: extractor_mode should mention llm, got \{st.extractor_mode}")
  }
  let mut meta_ok = false
  for e in fact_entries {
    match e.metadata.get("extractor") {
      Some(Json::String(v)) =>
        if v.contains("llm") {
          meta_ok = true
        }
      _ => ()
    }
  }
  if !meta_ok {
    fail("L2-05: expected metadata.extractor containing llm on fact entries")
  }

  // L2-06 召回
  section("L2-06", "recall allergy")
  let hits = recall_user(store, "user-fact", "花生过敏", 5)
  println("  hits=\{hits.length()}")
  if hits.length() < 1 {
    fail("L2-06: recall empty for 花生过敏")
  }
  for h in hits {
    println("  hit: [\{h.kind}] \{h.content}")
  }

  // L2-07 冲突更正（共享「深圳/住」以进入候选窗）
  section("L2-07", "conflict residence update")
  let j0 = judge.llm_call_count()
  expect_inserted(
    expect_add_ok(store, "user-conflict", "我目前住在深圳南山区。"),
    "reside-sz",
  )
  let upd = expect_add_ok(
    store,
    "user-conflict",
    "更正一下：我已经不在深圳了，现在住在杭州西湖区。",
  )
  println(
    "  update: inserted=\{upd.inserted} superseded=\{upd.superseded} degraded=\{upd.degraded} judge_delta=\{judge.llm_call_count() - j0}",
  )
  if upd.degraded {
    fail("L2-07: update degraded: \{join_notes(upd.notes)}")
  }
  if upd.inserted < 1 {
    fail("L2-07: expected new residence inserted")
  }
  let conf_entries = list_user(store, "user-conflict")
  for e in conf_entries {
    println("  [\{e.kind}/\{e.status}] \{e.content}")
  }
  let hz_hits = recall_user(store, "user-conflict", "杭州", 5)
  if hz_hits.length() < 1 &&
    active_mentioning(conf_entries, ["杭州"]) < 1 {
    fail("L2-07: neither recall nor active list mentions 杭州")
  }
  // 若发生 supersede：旧「深圳」住址不应再被 recall 为唯一现居
  if upd.superseded >= 1 {
    let sz_hits = recall_user(store, "user-conflict", "深圳南山区", 5)
    for h in sz_hits {
      if h.content.contains("目前住在深圳") ||
        (h.content.contains("住在深圳") && !h.content.contains("不在深圳")) {
        fail("L2-07: superseded old Shenzhen fact still recalled: \{h.content}")
      }
    }
  } else {
    println(
      "  note: no supersede count (LLM may coexist); 杭州 visibility already checked",
    )
  }

  // L2-08 近重复（抗 LLM 措辞漂移：指纹去重 / 未入库 / supersede 均可）
  section("L2-08", "near-duplicate suppression")
  let dup_text = "请记住：我的工号是 A1024。"
  expect_inserted(expect_add_ok(store, "user-dup", dup_text), "first-id")
  let dup2 = expect_add_ok(store, "user-dup", dup_text)
  println(
    "  second: extracted=\{dup2.extracted} inserted=\{dup2.inserted} duplicates=\{dup2.duplicates} superseded=\{dup2.superseded}",
  )
  let dup_ok = dup2.duplicates >= 1 ||
    dup2.inserted == 0 ||
    dup2.superseded >= 1
  if !dup_ok {
    fail(
      "L2-08: expected duplicate/supersede suppression, got inserted=\{dup2.inserted} duplicates=\{dup2.duplicates} superseded=\{dup2.superseded}",
    )
  }
  // 无论走指纹跳过还是 replace supersede，Active 中工号事实至多 1 条
  let active_id = active_mentioning(list_user(store, "user-dup"), ["A1024", "a1024"])
  println("  active A1024 facts=\{active_id}")
  if active_id > 1 {
    fail("L2-08: expected ≤1 active employee-id fact, got \{active_id}")
  }

  // L2-09 跨用户隔离
  section("L2-09", "cross-user isolation")
  expect_inserted(
    expect_add_ok(store, "user-a", "我对海鲜过敏。"),
    "user-a seafood",
  )
  expect_inserted(
    expect_add_ok(store, "user-b", "我养了一只名叫豆豆的猫。"),
    "user-b cat",
  )
  let a_hits = recall_user(store, "user-a", "猫 豆豆", 5)
  for h in a_hits {
    if h.content.contains("豆豆") || h.content.contains("猫") {
      fail("L2-09: user-a recall leaked user-b pet: \{h.content}")
    }
  }
  let b_hits = recall_user(store, "user-b", "海鲜过敏", 5)
  for h in b_hits {
    if h.content.contains("海鲜") || h.content.contains("过敏") {
      fail("L2-09: user-b recall leaked user-a allergy: \{h.content}")
    }
  }
  println("  isolation ok (no cross hits)")

  // L2-10 forget
  section("L2-10", "forget soft-delete")
  expect_inserted(
    expect_add_ok(store, "user-forget", "我的护照号码备忘是 P998877。"),
    "passport",
  )
  let before = list_user(store, "user-forget")
  if before.length() < 1 {
    fail("L2-10: expected entries before forget")
  }
  let victim = before[0]
  let forgotten = match store.forget(
    "user-forget",
    @src.ForgetTarget::ById(victim.id),
  ) {
    Ok(n) => n
    Err(e) => fail("forget: \{e.message()}")
  }
  println("  forgot id=\{victim.id} count=\{forgotten}")
  if forgotten < 1 {
    fail("L2-10: forget returned \{forgotten}")
  }
  let after_hits = recall_user(store, "user-forget", "护照", 5)
  for h in after_hits {
    if h.id == victim.id {
      fail("L2-10: forgotten id still recalled")
    }
  }
  let after_list = list_user(store, "user-forget")
  let mut saw_deleted = false
  for e in after_list {
    if e.id == victim.id {
      if e.status != @src.EntryStatus::Deleted {
        fail("L2-10: forgotten entry status=\{e.status}, want Deleted")
      }
      saw_deleted = true
    }
  }
  if !saw_deleted {
    fail("L2-10: forgotten entry missing from list (should remain for audit)")
  }

  // L2-11 export
  section("L2-11", "export_jsonl non-empty")
  let dumped = match store.export_jsonl() {
    Ok(s) => s
    Err(e) => fail("export_jsonl: \{e.message()}")
  }
  println("  export chars=\{dumped.length()}")
  if dumped.length() < 10 {
    fail("L2-11: export unexpectedly tiny")
  }

  // L2-12 观测
  section("L2-12", "llm call telemetry")
  let ext_calls = extractor.llm_call_count()
  let judge_calls = judge.llm_call_count()
  println("  extractor_calls=\{ext_calls} judge_calls=\{judge_calls}")
  if ext_calls < 1 {
    fail("L2-12: extractor.llm_call_count() expected ≥1")
  }
  match extractor.last_failure_reason() {
    Some(r) =>
      fail("L2-12: unexpected extractor failure residue: \{r}")
    None => ()
  }

  ignore(store.close())
  println("")
  println("LIVE_LLM_PASS")
  println("=== L2 live LLM gate ok (L2-01..L2-12) ===")
}

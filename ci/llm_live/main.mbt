// 发版专用真实 LLM 门禁（DeepSeek / OpenAI 兼容端点）。
//
// 环境变量（CI 注入；勿写入仓库）：
//   DEEPSEEK_API_KEY   — 密钥（GitHub Actions secret）
//   DEEPSEEK_BASE_URL  — 如 https://api.deepseek.com（可带或不带尾部 /v1）
//   DEEPSEEK_MODEL     — 如 deepseek-chat
//
// 本地：
//   export DEEPSEEK_API_KEY=... DEEPSEEK_BASE_URL=... DEEPSEEK_MODEL=...
//   moon run ci/llm_live --target native
//
// 失败以 abort 非零退出，阻塞发版流水线。

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
/// OpenAIProvider 会拼接 `/v1/chat/completions`，因此去掉尾斜杠与可选的 `/v1`。
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
fn main {
  println("=== moomem release gate: live LLM (DeepSeek) ===")
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
    embedder: None,
    extractor: Some(extractor as &@src.Extractor),
    judge: Some(judge as &@src.ConflictJudge),
    persistence: Some(backend),
    clock: None,
    dim: @src.DEFAULT_DIM,
    rrf_k: @src.DEFAULT_RRF_K,
    recall_candidates: 0,
    supersede_threshold: @src.DEFAULT_SUPERSEDE_THRESHOLD,
  }
  let store = match @src.MemoryStore::open("memory://llm-live", config=cfg) {
    Ok(s) => s
    Err(e) => fail("open failed: \{e.message()}")
  }

  // 1) 闲聊过滤（AC-03）
  println("[1] chat-only add")
  let chat = "今天天气真不错呀~"
  match store.add("user-live", chat) {
    Ok(s) => {
      println("  extracted=\{s.extracted} inserted=\{s.inserted}")
      if s.extracted != 0 || s.inserted != 0 {
        fail(
          "chat-only text should not be stored (extracted=\{s.extracted} inserted=\{s.inserted})",
        )
      }
    }
    Err(e) => fail("chat add error: \{e.message()}")
  }

  // 2) 结构化事实提取
  println("[2] fact-bearing add")
  let fact_text = "你好！我对花生过敏，平时喜欢清淡的粤菜。"
  match store.add("user-live", fact_text) {
    Ok(s) => {
      println(
        "  extracted=\{s.extracted} inserted=\{s.inserted} degraded=\{s.degraded}",
      )
      if s.extracted < 1 || s.inserted < 1 {
        fail(
          "expected ≥1 fact extracted/inserted, got extracted=\{s.extracted} inserted=\{s.inserted}",
        )
      }
      if s.degraded {
        fail("fact add degraded unexpectedly: \{join_notes(s.notes)}")
      }
    }
    Err(e) => fail("fact add error: \{e.message()}")
  }

  // 3) 入库内容应与过敏/花生相关
  println("[3] inspect stored entries")
  let entries = match store.list_entries("user-live") {
    Ok(es) => es
    Err(e) => fail("list_entries error: \{e.message()}")
  }
  if entries.length() < 1 {
    fail("expected stored entries after fact add")
  }
  let mut allergy_hit = false
  for e in entries {
    println("  [\{e.kind}] \{e.content}")
    if e.content.contains("过敏") ||
      e.content.contains("花生") ||
      e.content.contains("粤菜") ||
      e.content.contains("清淡") {
      allergy_hit = true
    }
  }
  if !allergy_hit {
    fail("stored facts do not mention 过敏/花生/粤菜/清淡")
  }

  // 4) 召回
  println("[4] recall 花生过敏")
  match store.recall("user-live", "花生过敏", top_k=3) {
    Ok(hits) => {
      println("  hits=\{hits.length()}")
      if hits.length() < 1 {
        fail("recall returned empty for 花生过敏")
      }
      for h in hits {
        println("  hit: [\{h.kind}] \{h.content}")
      }
    }
    Err(e) => fail("recall error: \{e.message()}")
  }

  // 5) 观测：至少发生过 LLM 调用
  let ext_calls = extractor.llm_call_count()
  let judge_calls = judge.llm_call_count()
  println("[5] llm_calls extractor=\{ext_calls} judge=\{judge_calls}")
  if ext_calls < 1 {
    fail("extractor.llm_call_count() expected ≥1")
  }
  match extractor.last_failure_reason() {
    Some(r) =>
      fail("extractor last_failure_reason unexpected after success path: \{r}")
    None => ()
  }

  ignore(store.close())
  println("LIVE_LLM_PASS")
  println("=== live LLM gate ok ===")
}

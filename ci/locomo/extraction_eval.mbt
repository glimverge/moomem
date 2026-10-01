// Extraction precision eval — offline SKIP; live uses DeepSeek via LlmExtractor.

///|
fn contains_ci(hay : String, needle : String) -> Bool {
  hay.to_lower().contains(needle.to_lower())
}

///|
fn run_extraction_offline_skip() -> Unit {
  println("### Extraction precision")
  println("")
  println(
    "extraction precision: SKIPPED (requires --live; RawExtractor stores raw text)",
  )
  println("")
}

///|
fn run_extraction_live(cases : Array[ExtractionCase]) -> Double {
  // Read DeepSeek env only in --live path
  let api_key = require_env("DEEPSEEK_API_KEY")
  let base_url = normalize_base_url(require_env("DEEPSEEK_BASE_URL"))
  let model = require_env("DEEPSEEK_MODEL")
  let provider = @openai.OpenAIProvider::new(
    api_key,
    endpoint=@openai.OpenAIEndpoint::Custom(base_url~),
    model~,
    timeout_sec=120,
    max_retries=2,
  )
  let p : &@llm.Provider = provider
  let extractor = @llm_extractor.LlmExtractor::new(p)
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let judge : &@src.ConflictJudge = NoConflictJudge::{ }
  let cfg = @src.Config::{
    ..@src.Config::default(),
    extractor: Some(extractor as &@src.Extractor),
    judge: Some(judge),
    persistence: Some(backend),
  }
  let store = match @src.MemoryStore::open("memory://locomo-extract", config=cfg) {
    Ok(s) => s
    Err(e) => fail("open extract store: \{e.message()}")
  }
  let mut hits = 0
  let mut denom = 0
  let fps : Array[String] = []
  for c in cases {
    let user = "ex-\{c.id}"
    ignore(store.add(user, c.text))
    let entries = match store.list_entries(user) {
      Ok(es) => es
      Err(e) => fail("list_entries(\{user}): \{e.message()}")
    }
    // only count active/recallable contents as extracted facts
    let contents : Array[String] = []
    for e in entries {
      if e.is_recallable() {
        contents.push(e.content)
      }
    }
    denom = denom + contents.length()
    // 分子：命中任一 must_extract 关键词的入库事实条数（W4-E）
    for content in contents {
      let mut matched = false
      for key in c.must_extract {
        if contains_ci(content, key) {
          matched = true
        }
      }
      if matched {
        hits = hits + 1
      }
    }
    // false positives
    if c.must_extract.length() == 0 && contents.length() > 0 {
      for content in contents {
        if fps.length() < 20 {
          fps.push("\{c.id}: unexpected store «\{content}»")
        }
      }
    }
    for bad in c.must_not_extract {
      for content in contents {
        if contains_ci(content, bad) {
          if fps.length() < 20 {
            fps.push("\{c.id}: must_not_extract «\{bad}» in «\{content}»")
          }
        }
      }
    }
  }
  ignore(store.close())
  let precision = if denom == 0 { 0.0 } else { hits.to_double() / denom.to_double() }
  println("### Extraction precision (live)")
  println("")
  println("| metric | value |")
  println("|---|---|")
  println("| hits (must_extract) | \{hits} |")
  println("| denom (stored facts) | \{denom} |")
  println("| Precision | \{format_mrr(precision)} |")
  println("| target | 0.800 |")
  if precision >= 0.8 {
    println("| gate | PASS |")
  } else {
    println("| gate | MISSED |")
  }
  println("")
  if fps.length() > 0 {
    println("False positives (up to 20):")
    for line in fps {
      println("- \{line}")
    }
    println("")
  }
  precision
}

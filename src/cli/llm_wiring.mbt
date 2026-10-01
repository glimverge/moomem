// native 专属：CLI LLM 接线（ffi 层仅在此目标保证语义）。
// 构造带 LlmExtractor / 可选 LlmConflictJudge 注入的 Config。

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
fn is_localhost_endpoint(url : String) -> Bool {
  url.contains("localhost") || url.contains("127.0.0.1")
}

///|
fn env_or_empty(key : String) -> String {
  match @env.get_env_var(key) {
    Some(raw) => raw.trim().to_owned()
    None => ""
  }
}

///|
/// 构造带 LLM 注入的 Config；失败返回可读错误信息（die 用）。
fn build_llm_config(opts : CliOptions) -> Result[@src.Config, String] {
  // 1) base_url：CLI > env > 缺省官方端点（空 = 官方 OpenAI）
  let raw_base = if opts.base_url.length() > 0 {
    opts.base_url
  } else {
    env_or_empty("MOOMEM_LLM_BASE_URL")
  }
  let base_url = if raw_base.length() > 0 {
    normalize_base_url(raw_base)
  } else {
    ""
  }
  let local = base_url.length() > 0 && is_localhost_endpoint(base_url)
  // 2) API key：本地端点可空；否则必需
  let api_key = env_or_empty("MOOMEM_LLM_API_KEY")
  if api_key.length() == 0 && !local {
    return Err(
      "moomem: --llm requires MOOMEM_LLM_API_KEY (or a localhost MOOMEM_LLM_BASE_URL)",
    )
  }
  // 3) model：CLI > env > gpt-4o-mini
  let model = if opts.model.length() > 0 {
    opts.model
  } else {
    let from_env = env_or_empty("MOOMEM_LLM_MODEL")
    if from_env.length() > 0 {
      from_env
    } else {
      "gpt-4o-mini"
    }
  }
  // 4) Provider
  let provider = if base_url.length() > 0 {
    @openai.OpenAIProvider::new(
      api_key,
      endpoint=@openai.OpenAIEndpoint::Custom(base_url~),
      model~,
    )
  } else {
    @openai.OpenAIProvider::new(api_key, model~)
  }
  let p : &@llm.Provider = provider
  let extractor = @llm_extractor.LlmExtractor::new(p)
  let judge : &@src.ConflictJudge? = if opts.llm_judge {
    Some(
      @llm_extractor.LlmConflictJudge::new(p) as &@src.ConflictJudge,
    )
  } else {
    None
  }
  Ok(
    @src.Config::{
      ..@src.Config::default(),
      extractor: Some(extractor as &@src.Extractor),
      judge,
    },
  )
}

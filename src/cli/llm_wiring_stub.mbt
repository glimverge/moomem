// 非 native 目标 stub：LLM 接线不可用。
// 引用 opts / LLM 包符号以在 wasm/js 下保持 moon check 零警告
// （真实接线仅 native 的 llm_wiring.mbt）。

///|
fn build_llm_config(opts : CliOptions) -> Result[@src.Config, String] {
  // 读取 CLI 字段，避免 unused_field（字段由 parse_options 写入）
  ignore(opts.model)
  ignore(opts.base_url)
  ignore(opts.llm)
  ignore(opts.llm_judge)
  // 锚定 moon.pkg 中的 LLM 依赖，避免 unused_package
  ignore(@llm_extractor.DegradePolicy::ReturnRaw)
  ignore(@openai.OpenAIEndpoint::OpenAI)
  let _p : &@llm.Provider? = None
  ignore(_p)
  Err("llm wiring requires native target")
}

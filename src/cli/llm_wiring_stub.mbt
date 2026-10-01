// 非 native 目标 stub：LLM 接线不可用。

///|
fn build_llm_config(_opts : CliOptions) -> Result[@src.Config, String] {
  Err("llm wiring requires native target")
}

// QA 对抗性测试(Edward):CLI 参数解析(白盒,访问包内 parse_options)。
// 依据:main.mbt 自身 help 文档的用法约定(FR-07)。
// native-only:CLI 为本地可执行入口;wasm/js 下 @fs/@env 链接不可用。

///|
#cfg(target="native")
test "QA cli: documented trailing --all usage must be accepted" {
  // 帮助文本原文:"moomem list --db <dir> --user <id> [--all]" —— --all 位于末尾。
  // 帮助文本展示的标准用法必须可解析。
  let ok = match parse_options(["--all"], default_options()) {
    Ok(opts) => opts.show_all
    Err(_) => false
  }
  inspect(ok, content="true")
}

///|
#cfg(target="native")
test "QA cli: --all before other options is accepted" {
  let ok = match
    parse_options(
      ["--all", "--db", "/tmp/qa-cli", "--user", "alice"],
      default_options(),
    ) {
    Ok(o) => o.show_all && o.db == "/tmp/qa-cli" && o.user == "alice"
    Err(_) => false
  }
  inspect(ok, content="true")
}

///|
#cfg(target="native")
test "QA cli: standard add/recall option sets parse" {
  let add_ok = match
    parse_options(
      ["--db", "d1", "--user", "alice", "--text", "我对花生过敏"],
      default_options(),
    ) {
    Ok(o) =>
      o.db == "d1" &&
      o.user == "alice" &&
      o.text == "我对花生过敏" &&
      o.top_k == 5 &&
      o.show_all == false &&
      o.file == None
    Err(_) => false
  }
  inspect(add_ok, content="true")
  let recall_ok = match
    parse_options(
      ["--db", "d1", "--user", "alice", "--query", "花生", "--top-k", "7"],
      default_options(),
    ) {
    Ok(o) => o.query == "花生" && o.top_k == 7
    Err(_) => false
  }
  inspect(recall_ok, content="true")
}

///|
#cfg(target="native")
test "QA cli: bad --top-k / unknown option / missing value rejected" {
  let bad_topk = match parse_options(["--top-k", "abc"], default_options()) {
    Err(_) => true
    Ok(_) => false
  }
  inspect(bad_topk, content="true")
  let unknown = match parse_options(["--nope", "x"], default_options()) {
    Err(_) => true
    Ok(_) => false
  }
  inspect(unknown, content="true")
  let missing = match parse_options(["--user"], default_options()) {
    Err(_) => true
    Ok(_) => false
  }
  inspect(missing, content="true")
}

///|
#cfg(target="native")
test "W3-D: MOOMEM_VERSION matches CLI usage and is not 0.1.x" {
  // usage 首行含版本号；与公开常量一致，且已与 moon.mod 同步到 0.2.x
  inspect(@src.MOOMEM_VERSION, content="0.2.2")
  inspect(@src.MOOMEM_VERSION.has_prefix("0.1"), content="false")
}

///|
#cfg(target="native")
test "W3-C1: --llm / --llm-judge trailing bools and value options parse" {
  let trailing = match
    parse_options(
      ["--db", "d1", "--user", "u1", "--text", "hi", "--llm"],
      default_options(),
    ) {
    Ok(o) => o.llm && !o.llm_judge
    Err(_) => false
  }
  inspect(trailing, content="true")
  let judge = match parse_options(["--llm-judge"], default_options()) {
    Ok(o) => o.llm && o.llm_judge
    Err(_) => false
  }
  inspect(judge, content="true")
  let vals = match
    parse_options(
      ["--model", "gpt-x", "--base-url", "http://127.0.0.1:11434"],
      default_options(),
    ) {
    Ok(o) => o.model == "gpt-x" && o.base_url == "http://127.0.0.1:11434"
    Err(_) => false
  }
  inspect(vals, content="true")
  let unknown = match parse_options(["--llm-nope"], default_options()) {
    Err(_) => true
    Ok(_) => false
  }
  inspect(unknown, content="true")
}

///|
#cfg(target="native")
test "W3-C2: build_llm_config ok on localhost and injects llm extractor" {
  @env.set_env_var("MOOMEM_LLM_API_KEY", "test-key")
  @env.set_env_var("MOOMEM_LLM_BASE_URL", "http://127.0.0.1:11434")
  @env.set_env_var("MOOMEM_LLM_MODEL", "test-model")
  let opts = CliOptions::{
    ..default_options(),
    llm: true,
    base_url: "http://127.0.0.1:11434",
    model: "test-model",
  }
  let cfg = match build_llm_config(opts) {
    Ok(c) => c
    Err(msg) => {
      inspect(msg, content="SHOULD NOT REACH")
      return
    }
  }
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg2 = @src.Config::{
    ..cfg,
    persistence: Some(backend),
  }
  let store = match @src.MemoryStore::open("memory://cli-llm", config=cfg2) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let st = match store.stats() {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.extractor_mode, content="llm")
  ignore(store.close())
  @env.unset_env_var("MOOMEM_LLM_API_KEY")
  @env.unset_env_var("MOOMEM_LLM_BASE_URL")
  @env.unset_env_var("MOOMEM_LLM_MODEL")
}

///|
#cfg(target="native")
test "W3-C3: build_llm_config rejects missing key on non-local endpoint" {
  @env.unset_env_var("MOOMEM_LLM_API_KEY")
  let opts = CliOptions::{
    ..default_options(),
    llm: true,
    base_url: "https://api.deepseek.com",
  }
  let err = match build_llm_config(opts) {
    Err(msg) => msg
    Ok(_) => "unexpected ok"
  }
  inspect(err.contains("MOOMEM_LLM_API_KEY"), content="true")
}

///|
#cfg(target="native")
test "W3-C4: localhost endpoint allows missing API key" {
  @env.unset_env_var("MOOMEM_LLM_API_KEY")
  @env.unset_env_var("MOOMEM_LLM_BASE_URL")
  @env.unset_env_var("MOOMEM_LLM_MODEL")
  let opts = CliOptions::{
    ..default_options(),
    llm: true,
    base_url: "http://127.0.0.1:11434",
    model: "local-model",
  }
  let cfg = match build_llm_config(opts) {
    Ok(c) => c
    Err(msg) => {
      inspect(msg, content="SHOULD NOT REACH")
      return
    }
  }
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg2 = @src.Config::{ ..cfg, persistence: Some(backend), }
  let store = match @src.MemoryStore::open("memory://cli-llm-c4", config=cfg2) {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  let st = match store.stats() {
    Ok(s) => s
    Err(e) => {
      inspect(e.message(), content="SHOULD NOT REACH")
      return
    }
  }
  inspect(st.extractor_mode, content="llm")
  ignore(store.close())
}

///|
#cfg(target="native")
test "W3-C5: localhost.evil.com is not treated as local" {
  @env.unset_env_var("MOOMEM_LLM_API_KEY")
  let opts = CliOptions::{
    ..default_options(),
    llm: true,
    base_url: "http://localhost.evil.com:11434",
  }
  let err = match build_llm_config(opts) {
    Err(msg) => msg
    Ok(_) => "unexpected ok"
  }
  inspect(err.contains("MOOMEM_LLM_API_KEY"), content="true")
}

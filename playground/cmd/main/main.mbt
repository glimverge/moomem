// 试用 heyq02/moomem：Qwen 嵌入 + DeepSeek 提取。密钥只从 .env 读取，不打印。
//
//   moon run cmd/main

///|
fn[T] block_on(work : async () -> T) -> T raise {
  let slot : Ref[Result[T, Error]?] = Ref(None)
  @async.run_async_main(async fn() {
    slot.val = Some(Ok(work()) catch { err => Err(err) })
  })
  match slot.val {
    Some(Ok(value)) => value
    Some(Err(err)) => raise err
    None => abort("async work did not finish")
  }
}

///|
struct Env {
  deepseek_key : String
  deepseek_base : String
  deepseek_model : String
  qwen_key : String
  qwen_base : String
  qwen_model : String
}

///|
fn split_once(line : String, sep : Char) -> (String, String)? {
  let mut found = false
  let key = StringBuilder()
  let value = StringBuilder()
  for c in line {
    if !found && c == sep {
      found = true
    } else if found {
      value.write_char(c)
    } else {
      key.write_char(c)
    }
  }
  if found {
    Some(
      (key.to_string().trim().to_owned(), value.to_string().trim().to_owned()),
    )
  } else {
    None
  }
}

///|
fn load_env(path : String) -> Env raise {
  let text = @fs.read_file_to_string(path)
  let table : Map[String, String] = Map([])
  for line in text.split("\n") {
    let trimmed = line.trim()
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      continue
    }
    match split_once(trimmed.to_owned(), '=') {
      Some((key, value)) => table[key] = value
      None => ()
    }
  }
  fn require(table : Map[String, String], key : String) -> String raise {
    match table.get(key) {
      Some(value) =>
        if value.length() == 0 {
          raise Failure("\{key} is empty")
        } else {
          value
        }
      None => raise Failure("missing \{key} in .env")
    }
  }
  Env::{
    deepseek_key: require(table, "DEEPSEEK_API_KEY"),
    deepseek_base: require(table, "DEEPSEEK_BASE_URL"),
    deepseek_model: require(table, "DEEPSEEK_MODEL"),
    qwen_key: require(table, "QWEN_API_KEY"),
    qwen_base: require(table, "QWEN_BASE_URL"),
    qwen_model: require(table, "QWEN_MODEL"),
  }
}

///|
fn join_url(base : String, path : String) -> String {
  if base.has_suffix("/") {
    "\{base}\{path}"
  } else {
    "\{base}/\{path}"
  }
}

///|
fn clip(text : String) -> String {
  if text.length() <= 240 {
    text
  } else {
    text[:240].to_owned()
  }
}

///|
fn post_json(url : String, api_key : String, payload : Json) -> Json raise {
  let headers : @http.Headers = Map([])
  headers["authorization"] = "Bearer \{api_key}"
  headers["content-type"] = "application/json"
  block_on(async fn() {
    let (response, body) = @http.post(url, payload.stringify(), headers~)
    if response.code < 200 || response.code >= 300 {
      let detail = body.text() catch { _ => "" }
      raise Failure("HTTP \{response.code} \{clip(detail)}")
    }
    body.json()
  })
}

///|
struct QwenEmbedder {
  api_key : String
  base_url : String
  model : String
  dim : Int32
}

///|
fn embedding_of(item : Json) -> Array[Double] raise {
  let obj = match item {
    Object(fields) => fields
    _ => raise Failure("embedding item is not an object")
  }
  match obj.get("embedding") {
    Some(Array(values)) => {
      let vector : Array[Double] = []
      for value in values {
        match value {
          Number(number, ..) => vector.push(number)
          _ => raise Failure("embedding value is not a number")
        }
      }
      vector
    }
    _ => raise Failure("embedding field missing")
  }
}

///|
pub impl @moomem.Embedder for QwenEmbedder with fn embed(self, texts) {
  if texts.length() == 0 {
    return Ok([])
  }
  let inputs = texts.map(text => Json::string(text))
  let payload : Map[String, Json] = Map([])
  payload["model"] = Json::string(self.model)
  payload["input"] = Json::array(inputs)
  let json = post_json(
    join_url(self.base_url, "embeddings"),
    self.api_key,
    Json::object(payload),
  ) catch {
    err => return Err(@moomem.MoomemError::EmbeddingFailure(err.to_string()))
  }
  let data = match json {
    Object(fields) =>
      match fields.get("data") {
        Some(Array(items)) => items
        _ =>
          return Err(
            @moomem.MoomemError::EmbeddingFailure("response has no data array"),
          )
      }
    _ =>
      return Err(
        @moomem.MoomemError::EmbeddingFailure("response is not an object"),
      )
  }
  if data.length() != texts.length() {
    return Err(
      @moomem.MoomemError::EmbeddingFailure(
        "embedding count \{data.length()} != input \{texts.length()}",
      ),
    )
  }
  let vectors : Array[Array[Double]] = []
  for item in data {
    let vector = embedding_of(item) catch {
      err => return Err(@moomem.MoomemError::EmbeddingFailure(err.to_string()))
    }
    vectors.push(vector)
  }
  Ok(vectors)
}

///|
pub impl @moomem.Embedder for QwenEmbedder with fn dim(self) {
  self.dim
}

///|
pub extend QwenEmbedder with @moomem.Embedder::{embed, dim}

///|
struct DeepSeekExtractor {
  api_key : String
  base_url : String
  model : String
}

///|
fn kind_of(name : String) -> @moomem.EntryKind {
  match name.trim().to_lower() {
    "preference" => @moomem.EntryKind::Preference
    "event" => @moomem.EntryKind::Event
    "fact" => @moomem.EntryKind::Fact
    _ => @moomem.EntryKind::Fact
  }
}

///|
fn json_object_slice(text : String) -> String {
  let mut start = -1
  let mut end = -1
  let mut index = 0
  for char in text {
    if char == '{' && start < 0 {
      start = index
    }
    if char == '}' {
      end = index
    }
    index = index + 1
  }
  if start >= 0 && end >= start {
    text[start:end + 1].to_owned()
  } else {
    text
  }
}

///|
fn facts_from_content(content : String) -> Array[@moomem.ExtractedFact] raise {
  let parsed = @json.parse(json_object_slice(content))
  let items = match parsed {
    Object(fields) =>
      match fields.get("facts") {
        Some(Array(items)) => items
        _ => raise Failure("extractor JSON has no facts array")
      }
    _ => raise Failure("extractor JSON is not an object")
  }
  let facts : Array[@moomem.ExtractedFact] = []
  for item in items {
    match item {
      Object(fields) =>
        match fields.get("content") {
          Some(String(text)) =>
            if text.trim().length() > 0 {
              let kind = match fields.get("kind") {
                Some(String(name)) => kind_of(name)
                _ => @moomem.EntryKind::Fact
              }
              facts.push(@moomem.ExtractedFact::{
                content: text.trim().to_owned(),
                kind,
                source_span: None,
                degraded: false,
                degrade_reason: None,
              })
            }
          _ => ()
        }
      _ => ()
    }
  }
  facts
}

///|
fn assistant_text(json : Json) -> String raise {
  match json {
    Object(fields) =>
      match fields.get("choices") {
        Some(Array(choices)) =>
          match choices[0] {
            Object(choice) =>
              match choice.get("message") {
                Some(Object(message)) =>
                  match message.get("content") {
                    Some(String(content)) => content
                    _ => raise Failure("message content missing")
                  }
                _ => raise Failure("message missing")
              }
            _ => raise Failure("choice is not an object")
          }
        _ => raise Failure("choices missing")
      }
    _ => raise Failure("chat response is not an object")
  }
}

///|
pub impl @moomem.Extractor for DeepSeekExtractor with fn extract(self, _, text) {
  if text.trim().length() == 0 {
    return Ok([])
  }
  let prompt = "从用户原话抽出可长期复用的事实，不要改写。纯闲聊返回空数组。只输出 JSON：{\"facts\":[{\"content\":\"...\",\"kind\":\"fact\"}]}。kind 只能是 fact、preference、event。"
  let messages = Json::array([
    Json::object({
      "role": Json::string("system"),
      "content": Json::string(prompt),
    }),
    Json::object({ "role": Json::string("user"), "content": Json::string(text) }),
  ])
  let payload : Map[String, Json] = Map([])
  payload["model"] = Json::string(self.model)
  payload["messages"] = messages
  payload["temperature"] = Json::number(0.0)
  let json = post_json(
    join_url(self.base_url, "chat/completions"),
    self.api_key,
    Json::object(payload),
  ) catch {
    err => return Err(@moomem.MoomemError::ExtractionFailure(err.to_string()))
  }
  let content = assistant_text(json) catch {
    err => return Err(@moomem.MoomemError::ExtractionFailure(err.to_string()))
  }
  let facts = facts_from_content(content) catch {
    err => return Err(@moomem.MoomemError::ExtractionFailure(err.to_string()))
  }
  Ok(facts)
}

///|
pub impl @moomem.Extractor for DeepSeekExtractor with fn mode(_) {
  "llm"
}

///|
pub extend DeepSeekExtractor with @moomem.Extractor::{extract, mode}

///|
fn reset_dir(dir : String) -> Unit {
  if @fs.path_exists(dir) {
    @fs.remove_file("\{dir}/moomem/slot0.jsonl") catch {
      _ => ()
    }
    @fs.remove_file("\{dir}/moomem/slot1.jsonl") catch {
      _ => ()
    }
    @fs.remove_file("\{dir}/moomem/head") catch {
      _ => ()
    }
    @fs.remove_dir("\{dir}/moomem") catch {
      _ => ()
    }
    @fs.remove_dir(dir) catch {
      _ => ()
    }
  }
}

///|
fn must_open(dir : String, config : @moomem.Config) -> @moomem.MemoryStore {
  match @moomem.MemoryStore::open(dir, config~) {
    Ok(store) => store
    Err(err) => {
      println("open failed: \{err.message()}")
      abort("open failed")
    }
  }
}

///|
fn print_add(
  store : @moomem.MemoryStore,
  user_id : String,
  text : String,
) -> @moomem.AddSummary {
  println("[add] \{user_id} \{text}")
  match store.add(user_id, text) {
    Ok(summary) => {
      println(
        "  extracted=\{summary.extracted} inserted=\{summary.inserted} duplicates=\{summary.duplicates} superseded=\{summary.superseded} degraded=\{summary.degraded}",
      )
      for note in summary.notes {
        println("  note: \{note}")
      }
      summary
    }
    Err(err) => {
      println("  error: \{err.message()}")
      abort("add failed")
    }
  }
}

///|
fn recall_of(
  store : @moomem.MemoryStore,
  user_id : String,
  query : String,
) -> Array[@moomem.MemoryEntry] {
  println("[recall] \{user_id} \{query}")
  match store.recall(user_id, query, top_k=3) {
    Ok(hits) => {
      if hits.length() == 0 {
        println("  (无命中)")
      } else {
        for hit in hits {
          println("  [\{hit.status}] \{hit.kind} \{hit.content}")
        }
      }
      hits
    }
    Err(err) => {
      println("  error: \{err.message()}")
      abort("recall failed")
    }
  }
}

///|
fn hits_contain(hits : Array[@moomem.MemoryEntry], needle : String) -> Bool {
  let mut found = false
  for hit in hits {
    if hit.content.contains(needle) {
      found = true
    }
  }
  found
}

///|
fn check(failures : Array[String], ok : Bool, name : String) -> Unit {
  if ok {
    println("PASS \{name}")
  } else {
    println("FAIL \{name}")
    failures.push(name)
  }
}

///|
fn main {
  let env = load_env(".env") catch {
    err => {
      println("env: \{err}")
      abort("env failed")
    }
  }
  println("models: embed=\{env.qwen_model} extract=\{env.deepseek_model}")
  let probe = QwenEmbedder::{
    api_key: env.qwen_key,
    base_url: env.qwen_base,
    model: env.qwen_model,
    dim: 0,
  }
  let dim = match probe.embed(["维度"]) {
    Ok(vectors) =>
      if vectors.length() == 0 || vectors[0].length() == 0 {
        println("embed probe returned an empty vector")
        abort("embed probe failed")
      } else {
        vectors[0].length()
      }
    Err(err) => {
      println("embed probe: \{err.message()}")
      abort("embed probe failed")
    }
  }
  println("embedding dim=\{dim}")
  let embedder : &@moomem.Embedder = QwenEmbedder::{
    api_key: env.qwen_key,
    base_url: env.qwen_base,
    model: env.qwen_model,
    dim,
  }
  let extractor : &@moomem.Extractor = DeepSeekExtractor::{
    api_key: env.deepseek_key,
    base_url: env.deepseek_base,
    model: env.deepseek_model,
  }
  let config = @moomem.Config::{
    ..@moomem.Config::default(),
    embedder: Some(embedder),
    extractor: Some(extractor),
    dim,
  }
  let dir = "./memory"
  reset_dir(dir)
  let store = must_open(dir, config)
  let failures : Array[String] = []
  let allergy = print_add(store, "user-42", "我对花生过敏")
  check(
    failures,
    allergy.extracted >= 1 && allergy.inserted >= 1 && !allergy.degraded,
    "allergy fact inserted",
  )
  let beijing = print_add(store, "user-42", "我住在北京")
  check(
    failures,
    beijing.inserted >= 1 && !beijing.degraded,
    "beijing fact inserted",
  )
  let shenzhen = print_add(store, "user-42", "我搬到深圳了")
  check(
    failures,
    !shenzhen.degraded && shenzhen.superseded == 0,
    "default judge keeps both residences",
  )
  let chat = print_add(store, "user-42", "今天天气不错")
  check(
    failures,
    chat.extracted == 0 && chat.inserted == 0,
    "chitchat stayed out of the store",
  )
  let again = print_add(store, "user-42", "我对花生过敏")
  check(
    failures,
    again.duplicates >= 1 || again.inserted == 0,
    "repeat allergy was not inserted again",
  )
  let allergy_hits = recall_of(store, "user-42", "花生过敏")
  check(
    failures,
    hits_contain(allergy_hits, "花生"),
    "recall finds the allergy",
  )
  let home_hits = recall_of(store, "user-42", "我住在哪里")
  check(
    failures,
    hits_contain(home_hits, "深圳") && hits_contain(home_hits, "北京"),
    "recall still returns both residences",
  )
  let leaked = recall_of(store, "user-7", "花生过敏")
  check(failures, leaked.length() == 0, "another user cannot see the allergy")
  match store.list_entries("user-42") {
    Ok(entries) => {
      let mut active_beijing = false
      for entry in entries {
        if entry.content.contains("北京") {
          println("  [audit] \{entry.status} \{entry.content}")
          if entry.status.to_string() == "Active" {
            active_beijing = true
          }
        }
      }
      check(failures, active_beijing, "Beijing entry stays active")
    }
    Err(err) => check(failures, false, "list entries: \{err.message()}")
  }
  match store.stats() {
    Ok(stats) => {
      println("[stats] \{stats}")
      check(failures, stats.extractor_mode == "llm", "extractor mode is llm")
      check(failures, stats.active >= 2, "at least two active memories")
      check(failures, stats.superseded == 0, "nothing was superseded")
    }
    Err(err) => check(failures, false, "stats: \{err.message()}")
  }
  ignore(store.close())
  println("[reopen]")
  let restored = must_open(dir, config)
  let restored_allergy = recall_of(restored, "user-42", "花生过敏")
  check(
    failures,
    hits_contain(restored_allergy, "花生"),
    "allergy survives reopen",
  )
  let restored_home = recall_of(restored, "user-42", "我住在哪里")
  check(
    failures,
    hits_contain(restored_home, "深圳") &&
    hits_contain(restored_home, "北京"),
    "both residences survive reopen",
  )
  match restored.list_entries("user-42") {
    Ok(entries) => {
      let mut allergy_id = ""
      for entry in entries {
        if entry.content.contains("花生") &&
          entry.status.to_string() == "Active" {
          allergy_id = entry.id
        }
      }
      check(failures, allergy_id.length() > 0, "allergy id is still active")
      if allergy_id.length() > 0 {
        match
          restored.forget("user-42", @moomem.ForgetTarget::ById(allergy_id)) {
          Ok(removed) =>
            check(failures, removed == 1, "forget removes the allergy")
          Err(err) => check(failures, false, "forget: \{err.message()}")
        }
        let after_forget = recall_of(restored, "user-42", "花生过敏")
        check(
          failures,
          !hits_contain(after_forget, "花生"),
          "forgotten allergy is not recalled",
        )
      }
    }
    Err(err) => check(failures, false, "list after reopen: \{err.message()}")
  }
  ignore(restored.close())
  if failures.length() > 0 {
    println("failed checks: \{failures.length()}")
    abort("playground verification failed")
  }
  println("all checks passed")
}

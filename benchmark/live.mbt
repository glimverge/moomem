// HTTP client, Qwen embedder, and the LoCoMo answer / judge prompts.
// Keys stay in memory and are never printed.

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
      None => raise Failure("missing \{key}")
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
  if text.length() <= 180 {
    text
  } else {
    text[:180].to_owned()
  }
}

///|
fn post_once(
  url : String,
  api_key : String,
  payload : Json,
) -> Result[Json, String] {
  let headers : @http.Headers = Map([])
  headers["authorization"] = "Bearer \{api_key}"
  headers["content-type"] = "application/json"
  let json = block_on(async fn() {
    let (response, body) = @http.post(url, payload.stringify(), headers~)
    if response.code < 200 || response.code >= 300 {
      let detail = body.text() catch { _ => "" }
      raise Failure("HTTP \{response.code} \{clip(detail)}")
    }
    body.json()
  }) catch {
    err => return Err(err.to_string())
  }
  Ok(json)
}

///|
fn post_json(url : String, api_key : String, payload : Json) -> Json raise {
  let mut last = "request failed"
  let mut attempt = 0
  while attempt < 4 {
    attempt = attempt + 1
    match post_once(url, api_key, payload) {
      Ok(json) => return json
      Err(message) => last = message
    }
  }
  raise Failure(last)
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
pub impl @src.Embedder for QwenEmbedder with fn embed(self, texts) {
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
    err => return Err(@src.MoomemError::EmbeddingFailure(err.to_string()))
  }
  let data = match json {
    Object(fields) =>
      match fields.get("data") {
        Some(Array(items)) => items
        _ =>
          return Err(
            @src.MoomemError::EmbeddingFailure("response has no data array"),
          )
      }
    _ =>
      return Err(
        @src.MoomemError::EmbeddingFailure("response is not an object"),
      )
  }
  if data.length() != texts.length() {
    return Err(
      @src.MoomemError::EmbeddingFailure(
        "embedding count \{data.length()} != input \{texts.length()}",
      ),
    )
  }
  let vectors : Array[Array[Double]] = []
  for item in data {
    let vector = embedding_of(item) catch {
      err => return Err(@src.MoomemError::EmbeddingFailure(err.to_string()))
    }
    vectors.push(vector)
  }
  Ok(vectors)
}

///|
pub impl @src.Embedder for QwenEmbedder with fn dim(self) {
  self.dim
}

///|
pub extend QwenEmbedder with @src.Embedder::{embed, dim}

///|
struct KeepAllJudge {}

///|
pub impl @src.ConflictJudge for KeepAllJudge with fn judge(_, _, _) {
  Ok([])
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
fn chat(env : Env, system : String, user : String) -> String raise {
  let messages = Json::array([
    Json::object({
      "role": Json::string("system"),
      "content": Json::string(system),
    }),
    Json::object({ "role": Json::string("user"), "content": Json::string(user) }),
  ])
  let payload : Map[String, Json] = Map([])
  payload["model"] = Json::string(env.deepseek_model)
  payload["messages"] = messages
  payload["temperature"] = Json::number(0.0)
  let json = post_json(
    join_url(env.deepseek_base, "chat/completions"),
    env.deepseek_key,
    Json::object(payload),
  )
  assistant_text(json)
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
fn after_answer(text : String) -> String {
  let mut last = text
  for part in text.split("ANSWER:") {
    last = part.to_owned()
  }
  last.trim().to_owned()
}

///|
fn gold_of(category : Int32, answer : String) -> String {
  if category != 3 {
    return answer
  }
  for part in answer.split(";") {
    return part.trim().to_owned()
  }
  answer
}

///|
fn answer_prompt(
  question : String,
  memories : Array[String],
  reference_date : String,
) -> String {
  let body = StringBuilder()
  body.write_string(
    "You answer a question using only the retrieved memories. Read every memory. Prefer specific names, dates, and numbers that appear in the memories. Do not invent any. These conversations took place around ",
  )
  body.write_string(reference_date)
  body.write_string(
    ". Calculate dates from the memory text, not from today. Memories are in chronological order.\n\n",
  )
  if memories.length() == 0 {
    body.write_string("(No relevant memories found)\n")
  } else {
    for line in memories {
      body.write_string(line)
      body.write_string("\n")
    }
  }
  body.write_string("\nQuestion: ")
  body.write_string(question)
  body.write_string(
    "\n\nWork from the memories, then give the final answer after ANSWER:.",
  )
  body.to_string()
}

///|
fn judge_prompt(question : String, gold : String, generated : String) -> String {
  let body = StringBuilder()
  body.write_string(
    "Label the generated answer as CORRECT or WRONG.\n\nRules:\n1. PARTIAL CREDIT: if the generated answer includes at least one correct item from the gold list, mark CORRECT.\n2. PARAPHRASES COUNT: the same concept in different words is CORRECT.\n3. EXTRA DETAIL IS FINE.\n4. DATE TOLERANCE: dates within 14 days match. Durations within 50% match.\n5. Mark WRONG only when the answer shares no correct item with the gold answer, or is about a different topic.\n\nQuestion: ",
  )
  body.write_string(question)
  body.write_string("\nGold answer: ")
  body.write_string(gold)
  body.write_string("\nGenerated answer: ")
  body.write_string(generated)
  body.write_string(
    "\n\nReturn JSON only: {\"reasoning\":\"...\",\"label\":\"CORRECT\"} or {\"reasoning\":\"...\",\"label\":\"WRONG\"}.",
  )
  body.to_string()
}

///|
fn judge_label(text : String) -> String {
  let parsed = @json.parse(json_object_slice(text)) catch { _ => Json::null() }
  match parsed {
    Object(fields) =>
      match fields.get("label") {
        Some(String(label)) => label.trim().to_lower().to_owned()
        _ => ""
      }
    _ => ""
  }
}

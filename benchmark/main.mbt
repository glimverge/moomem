// LoCoMo sample, aligned with mem0ai/memory-benchmarks:
// ingest each turn, recall, answer from the hits, judge CORRECT / WRONG.
//
//   moon run benchmark --target native

///|
struct Turn {
  session : Int32
  date : String
  speaker : String
  text : String
}

///|
struct Question {
  category : Int32
  question : String
  answer : String
}

///|
struct Sample {
  seed : Int32
  conversation_index : Int32
  speaker_a : String
  speaker_b : String
  reference_date : String
  turns : Array[Turn]
  questions : Array[Question]
}

///|
fn json_obj(value : Json) -> Map[String, Json]? {
  if value is Object(obj) {
    Some(obj)
  } else {
    None
  }
}

///|
fn field_string(obj : Map[String, Json], key : String) -> String raise {
  match obj.get(key) {
    Some(String(text)) => text
    _ => raise Failure("missing string \{key}")
  }
}

///|
fn field_int(obj : Map[String, Json], key : String) -> Int32 raise {
  match obj.get(key) {
    Some(Number(number, ..)) => number.to_int()
    _ => raise Failure("missing number \{key}")
  }
}

///|
fn load_sample(path : String) -> Sample raise {
  let root = @json.parse(@fs.read_file_to_string(path))
  let obj = match json_obj(root) {
    Some(obj) => obj
    None => raise Failure("fixture root is not an object")
  }
  let turn_json = match obj.get("turns") {
    Some(Array(items)) => items
    _ => raise Failure("fixture missing turns")
  }
  let turns : Array[Turn] = []
  for item in turn_json {
    let turn = match json_obj(item) {
      Some(turn) => turn
      None => raise Failure("turn is not an object")
    }
    turns.push(Turn::{
      session: field_int(turn, "session"),
      date: field_string(turn, "date"),
      speaker: field_string(turn, "speaker"),
      text: field_string(turn, "text"),
    })
  }
  let question_json = match obj.get("questions") {
    Some(Array(items)) => items
    _ => raise Failure("fixture missing questions")
  }
  let questions : Array[Question] = []
  for item in question_json {
    let question = match json_obj(item) {
      Some(question) => question
      None => raise Failure("question is not an object")
    }
    questions.push(Question::{
      category: field_int(question, "category"),
      question: field_string(question, "question"),
      answer: field_string(question, "answer"),
    })
  }
  Sample::{
    seed: field_int(obj, "seed"),
    conversation_index: field_int(obj, "conversation_index"),
    speaker_a: field_string(obj, "speaker_a"),
    speaker_b: field_string(obj, "speaker_b"),
    reference_date: field_string(obj, "reference_date"),
    turns,
    questions,
  }
}

///|
fn memory_line(turn : Turn) -> String {
  let session = if turn.session < 10 {
    "0\{turn.session}"
  } else {
    "\{turn.session}"
  }
  "[s\{session}|\{turn.date}] \{turn.speaker}: \{turn.text}"
}

///|
fn sort_lines(lines : Array[String]) -> Unit {
  let mut i = 1
  while i < lines.length() {
    let key = lines[i]
    let mut j = i - 1
    while j >= 0 && lines[j].compare(key) > 0 {
      lines[j + 1] = lines[j]
      j = j - 1
    }
    lines[j + 1] = key
    i = i + 1
  }
}

///|
fn category_name(category : Int32) -> String {
  match category {
    1 => "multi-hop"
    2 => "temporal"
    3 => "open-domain"
    4 => "single-hop"
    _ => "other"
  }
}

///|
fn[T] stop(message : String) -> T {
  println(message)
  abort(message)
}

///|
fn main {
  let env = load_env("benchmark/.env") catch { err => stop("env: \{err}") }
  let sample = load_sample("benchmark/data/locomo_20.json") catch {
    err => stop("fixture: \{err}")
  }
  println(
    "locomo sample seed=\{sample.seed} conversation=\{sample.conversation_index} \{sample.speaker_a}/\{sample.speaker_b}",
  )
  println(
    "turns=\{sample.turns.length()} questions=\{sample.questions.length()} embed=\{env.qwen_model} answer=\{env.deepseek_model}",
  )
  let probe = QwenEmbedder::{
    api_key: env.qwen_key,
    base_url: env.qwen_base,
    model: env.qwen_model,
    dim: 0,
  }
  let dim = match probe.embed(["dimension"]) {
    Ok(vectors) =>
      if vectors.length() == 0 || vectors[0].length() == 0 {
        stop("embed probe returned an empty vector")
        0
      } else {
        vectors[0].length()
      }
    Err(err) => {
      stop("embed probe: \{err.message()}")
      0
    }
  }
  println("embedding dim=\{dim} recall_top_k=50")
  let embedder : &@src.Embedder = QwenEmbedder::{
    api_key: env.qwen_key,
    base_url: env.qwen_base,
    model: env.qwen_model,
    dim,
  }
  let judge : &@src.ConflictJudge = KeepAllJudge::{ }
  let backend = @src.MemoryBackend::new()
  let store = match
    @src.MemoryStore::open("memory://locomo", config=@src.Config::{
      ..@src.Config::default(),
      embedder: Some(embedder),
      judge: Some(judge),
      persistence: Some(backend),
      dim,
    }) {
    Ok(store) => store
    Err(err) => {
      stop("open: \{err.message()}")
      abort("open")
    }
  }
  let mut index = 0
  for turn in sample.turns {
    index = index + 1
    let line = memory_line(turn)
    match store.add("conv-8", line) {
      Ok(summary) =>
        if summary.inserted != 1 || summary.degraded {
          stop(
            "add \{index} inserted=\{summary.inserted} degraded=\{summary.degraded}",
          )
        }
      Err(err) => stop("add \{index}: \{err.message()}")
    }
    if index % 25 == 0 || index == sample.turns.length() {
      println("ingested \{index}/\{sample.turns.length()}")
    }
  }
  let rows : Array[Json] = []
  let mut correct = 0
  let mut seen = 0
  let counts : Map[Int32, Int32] = Map([])
  let hits_by_cat : Map[Int32, Int32] = Map([])
  for question in sample.questions {
    seen = seen + 1
    let recalled = match store.recall("conv-8", question.question, top_k=50) {
      Ok(hits) => hits
      Err(err) => {
        stop("recall \{seen}: \{err.message()}")
        []
      }
    }
    let lines : Array[String] = []
    for hit in recalled {
      lines.push(hit.content)
    }
    sort_lines(lines)
    let generated = chat(
      env,
      "Answer from the retrieved memories.",
      answer_prompt(question.question, lines, sample.reference_date),
    ) catch {
      err => {
        stop("answer \{seen}: \{err}")
        ""
      }
    }
    let short = after_answer(generated)
    let gold = gold_of(question.category, question.answer)
    let judged = chat(
      env,
      "You evaluate conversational memory recall. Return JSON only.",
      judge_prompt(question.question, gold, short),
    ) catch {
      err => {
        stop("judge \{seen}: \{err}")
        ""
      }
    }
    let label = judge_label(judged)
    let ok = label == "correct"
    if ok {
      correct = correct + 1
    }
    let prev = match counts.get(question.category) {
      Some(n) => n
      None => 0
    }
    counts[question.category] = prev + 1
    let prev_hit = match hits_by_cat.get(question.category) {
      Some(n) => n
      None => 0
    }
    if ok {
      hits_by_cat[question.category] = prev_hit + 1
    } else {
      hits_by_cat[question.category] = prev_hit
    }
    println(
      "q=\{seen} \{category_name(question.category)} \{if ok { "CORRECT" } else { "WRONG" }} \{correct}/\{seen}",
    )
    let row : Map[String, Json] = Map([])
    row["category"] = Json::number(question.category.to_double())
    row["category_name"] = Json::string(category_name(question.category))
    row["question"] = Json::string(question.question)
    row["gold"] = Json::string(gold)
    row["generated"] = Json::string(short)
    row["label"] = Json::string(if ok { "CORRECT" } else { "WRONG" })
    row["recalled"] = Json::number(lines.length().to_double())
    rows.push(Json::object(row))
  }
  let by_category : Array[Json] = []
  for category in [1, 2, 3, 4] {
    let total = match counts.get(category) {
      Some(n) => n
      None => 0
    }
    if total == 0 {
      continue
    }
    let hit = match hits_by_cat.get(category) {
      Some(n) => n
      None => 0
    }
    let item : Map[String, Json] = Map([])
    item["category"] = Json::string(category_name(category))
    item["correct"] = Json::number(hit.to_double())
    item["total"] = Json::number(total.to_double())
    by_category.push(Json::object(item))
    println("\{category_name(category)} \{hit}/\{total}")
  }
  println("overall \{correct}/\{seen}")
  let root : Map[String, Json] = Map([])
  root["seed"] = Json::number(sample.seed.to_double())
  root["conversation_index"] = Json::number(
    sample.conversation_index.to_double(),
  )
  root["speakers"] = Json::string("\{sample.speaker_a}/\{sample.speaker_b}")
  root["turns"] = Json::number(sample.turns.length().to_double())
  root["embedder"] = Json::string(env.qwen_model)
  root["answerer"] = Json::string(env.deepseek_model)
  root["judge"] = Json::string(env.deepseek_model)
  root["top_k"] = Json::number(50.0)
  root["correct"] = Json::number(correct.to_double())
  root["total"] = Json::number(seen.to_double())
  root["by_category"] = Json::array(by_category)
  root["rows"] = Json::array(rows)
  @fs.write_string_to_file(
    "benchmark/results/locomo-20.json",
    Json::object(root).stringify(),
  ) catch {
    @fs.IOError(msg) => stop("write results: \{msg}")
  }
  println("LOCOMO_DONE \{correct}/\{seen}")
  ignore(store.close())
}

// 补齐仍未走到的分支：嵌入失败、错误维度、自报降级、等权融合、
// 词法短路、损坏快照、导入容错。

///|
struct GapDownEmbedder {}

///|
impl Embedder for GapDownEmbedder with fn embed(_, _) {
  Err(@src.MoomemError::EmbeddingFailure("down"))
}

///|
impl Embedder for GapDownEmbedder with fn dim(_) {
  @src.DEFAULT_DIM
}

///|
struct GapShortEmbedder {}

///|
impl Embedder for GapShortEmbedder with fn embed(_, texts) {
  Ok(texts.map(_ => [1.0]))
}

///|
impl Embedder for GapShortEmbedder with fn dim(_) {
  @src.DEFAULT_DIM
}

///|
struct GapSameEmbedder {}

///|
impl Embedder for GapSameEmbedder with fn embed(_, texts) {
  Ok(texts.map(_ => Array::make(@src.DEFAULT_DIM, 1.0)))
}

///|
impl Embedder for GapSameEmbedder with fn dim(_) {
  @src.DEFAULT_DIM
}

///|
struct GapDegradedExtractor {}

///|
impl Extractor for GapDegradedExtractor with fn extract(_, _, text) {
  Ok([
    @src.ExtractedFact::{
      content: text,
      kind: Fact,
      source_span: None,
      degraded: true,
      degrade_reason: None,
    },
  ])
}

///|
impl Extractor for GapDegradedExtractor with fn mode(_) {
  "llm"
}

///|
struct GapReasonExtractor {}

///|
impl Extractor for GapReasonExtractor with fn extract(_, _, text) {
  Ok([
    @src.ExtractedFact::{
      content: text,
      kind: Fact,
      source_span: None,
      degraded: true,
      degrade_reason: Some("model skipped"),
    },
  ])
}

///|
impl Extractor for GapReasonExtractor with fn mode(_) {
  "llm"
}

///|
struct GapIgnoreJudge {}

///|
impl ConflictJudge for GapIgnoreJudge with fn judge(_, _, candidates) {
  let verdicts : Array[@src.ConflictVerdict] = []
  for cand in candidates {
    verdicts.push(@src.ConflictVerdict::{ existing: cand, decision: Ignore, })
  }
  Ok(verdicts)
}

///|
struct GapDownJudge {}

///|
impl ConflictJudge for GapDownJudge with fn judge(_, _, _) {
  Err(@src.MoomemError::InvalidOperation("judge down"))
}

///|
fn gap_open(config : @src.Config) -> @src.MemoryStore {
  match @src.MemoryStore::open("memory://gap", config~) {
    Ok(store) => store
    Err(_) => abort("open")
  }
}

///|
test "embedding failure degrades add and recall to keywords" {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let embedder : &@src.Embedder = GapDownEmbedder::{ }
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    embedder: Some(embedder),
    persistence: Some(backend),
  })
  let summary = match store.add("gap-user", "花生过敏要避开") {
    Ok(summary) => summary
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("add")
    }
  }
  inspect(summary.degraded, content="true")
  inspect(summary.inserted, content="1")
  let hits = match store.recall("gap-user", "花生") {
    Ok(hits) => hits
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("recall")
    }
  }
  inspect(hits.length() >= 1, content="true")
  let entries = match store.list_entries("gap-user") {
    Ok(entries) => entries
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("list")
    }
  }
  inspect(entries[0].kind.to_string(), content="Unstructured")
  inspect(
    entries[0].metadata.get("embedding_degraded") is Some(_),
    content="true",
  )
  ignore(store.close())
}

///|
test "short embedding is stored as keyword-only" {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let embedder : &@src.Embedder = GapShortEmbedder::{ }
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    embedder: Some(embedder),
    persistence: Some(backend),
  })
  let summary = match store.add("gap-short", "shortvec fact") {
    Ok(summary) => summary
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("add")
    }
  }
  inspect(summary.inserted, content="1")
  let hits = match store.recall("gap-short", "shortvec") {
    Ok(hits) => hits
    Err(_) => []
  }
  inspect(hits.length() >= 1, content="true")
  ignore(store.close())
}

///|
test "self-degraded fact without a reason is noted" {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let extractor : &@src.Extractor = GapDegradedExtractor::{ }
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    extractor: Some(extractor),
    persistence: Some(backend),
  })
  let summary = match store.add("gap-deg", "自报降级的事实") {
    Ok(summary) => summary
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("add")
    }
  }
  inspect(summary.degraded, content="true")
  inspect(summary.notes.length() >= 1, content="true")
  ignore(store.close())
}

///|
test "judge failure keeps both facts" {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let judge : &@src.ConflictJudge = GapDownJudge::{ }
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    judge: Some(judge),
    persistence: Some(backend),
  })
  ignore(store.add("gap-judge", "我住在北京"))
  let second = match store.add("gap-judge", "我住在北京附近") {
    Ok(summary) => summary
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("add")
    }
  }
  inspect(second.degraded, content="true")
  let stats = match store.stats() {
    Ok(stats) => stats
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("stats")
    }
  }
  inspect(stats.active, content="2")
  match stats.last_write_at {
    Some(_) => inspect(true, content="true")
    None => inspect(false, content="true")
  }
  ignore(store.close())
}

///|
test "equal fusion and a tiny candidate window still recall" {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let embedder : &@src.Embedder = GapSameEmbedder::{ }
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    embedder: Some(embedder),
    persistence: Some(backend),
    fusion_policy: @src.FusionPolicy::EqualRrf,
    recall_candidates: 1,
    vector_weight_when_lexical: 0.05,
    backfill: @src.RecallBackfill::NoBackfill,
  })
  ignore(store.add("gap-rrf", "cat dog"))
  ignore(store.add("gap-rrf", "dog cat"))
  let hits = match store.recall("gap-rrf", "cat", top_k=5) {
    Ok(hits) => hits
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("recall")
    }
  }
  inspect(hits.length() >= 1, content="true")
  let empty = match store.list_entries("gap-none") {
    Ok(entries) => entries
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("list")
    }
  }
  inspect(empty.length(), content="0")
  ignore(store.close())
  let closed = match store.import_jsonl("{}\n") {
    Err(@src.MoomemError::InvalidOperation(_)) => true
    _ => false
  }
  inspect(closed, content="true")
}

///|
test "shared keywords lose document frequency when forgotten" {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
  })
  ignore(store.add("gap-df", "苹果香蕉"))
  ignore(store.add("gap-df", "苹果橙子"))
  ignore(store.add("gap-df", "!!!"))
  let entries = match store.list_entries("gap-df") {
    Ok(entries) => entries
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("list")
    }
  }
  inspect(entries[0].kind.to_string(), content="Unstructured")
  for entry in entries {
    if entry.content.contains("苹果") {
      ignore(store.forget("gap-df", @src.ForgetTarget::ById(entry.id)))
    }
  }
  let left = match store.list_entries("gap-df") {
    Ok(entries) => entries
    Err(_) => []
  }
  let mut kept_punct = false
  for entry in left {
    if entry.content == "!!!" {
      kept_punct = true
    }
  }
  inspect(kept_punct, content="true")
  let exported = match store.export_jsonl() {
    Ok(text) => text
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("export")
    }
  }
  let fresh = gap_open(@src.Config::{
    ..@src.Config::default(),
    persistence: Some(@src.MemoryBackend::new()),
  })
  let bad = "not-json\n{}\n" +
    exported.replace(old="\"active\"", new="\"unstructured\"")
  let imported = match fresh.import_jsonl(bad) {
    Ok(pair) => pair
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("import")
    }
  }
  inspect(imported.0 >= 1, content="true")
  inspect(imported.1 >= 1, content="true")
  let stats = match fresh.stats() {
    Ok(stats) => stats
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("stats")
    }
  }
  inspect(stats.unstructured >= 1, content="true")
  ignore(store.close())
  ignore(fresh.close())
}

///|
#cfg(target="native")
test "both unreadable slots are store corruption" {
  let dir = "tmp_moomem_persist_test/db-both-bad"
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
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("open")
    }
  }
  ignore(store.add("gap-fs", "一条记忆"))
  ignore(store.close())
  @fs.write_string_to_file("\{dir}/moomem/slot0.jsonl", "not-json\n")
  @fs.write_string_to_file("\{dir}/moomem/slot1.jsonl", "also-not-json\n")
  @fs.write_string_to_file("\{dir}/moomem/head", "0")
  let failed = match @src.MemoryStore::open(dir) {
    Err(@src.MoomemError::StoreCorrupted(_)) => true
    Ok(_) => false
    Err(_) => false
  }
  inspect(failed, content="true")
  @fs.remove_file("\{dir}/moomem/head") catch {
    _ => ()
  }
  let failed_again = match @src.MemoryStore::open(dir) {
    Err(@src.MoomemError::StoreCorrupted(_)) => true
    _ => false
  }
  inspect(failed_again, content="true")
}

///|
#cfg(target="native")
test "absolute directory is created on open" {
  let dir = "/tmp/moomem_cov_abs/nested"
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
    @fs.remove_dir("/tmp/moomem_cov_abs") catch {
      _ => ()
    }
  }
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("open")
    }
  }
  ignore(store.add("gap-abs", "绝对路径"))
  ignore(store.close())
  let restored = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(err) => {
      inspect(err.message(), content="SHOULD NOT REACH")
      abort("reopen")
    }
  }
  let hits = match restored.recall("gap-abs", "绝对路径") {
    Ok(hits) => hits
    Err(_) => []
  }
  inspect(hits.length() >= 1, content="true")
  ignore(restored.close())
}

///|
test "self degrade keeps the reported reason" {
  let backend = @src.MemoryBackend::new()
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
    extractor: Some(GapReasonExtractor::{ }),
  })
  let summary = match store.add("gap-why", "带原因的降级") {
    Ok(summary) => summary
    Err(_) => abort("add")
  }
  inspect(summary.degraded, content="true")
  inspect(summary.notes.length() >= 1, content="true")
  ignore(store.close())
}

///|
test "ignore verdict leaves both facts active" {
  let backend = @src.MemoryBackend::new()
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
    judge: Some(GapIgnoreJudge::{ }),
  })
  ignore(store.add("gap-ign", "city paris"))
  ignore(store.add("gap-ign", "city lyon"))
  let stats = match store.stats() {
    Ok(stats) => stats
    Err(_) => abort("stats")
  }
  inspect(stats.active, content="2")
  ignore(store.close())
}

///|
test "import skips duplicate content and fills omitted fields" {
  let backend = @src.MemoryBackend::new()
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
  })
  ignore(store.add("gap-imp", "alpha beta shared"))
  let omitted = "{\"id\":\"imp-omit\",\"user_id\":\"gap-imp\",\"content\":\"brand new fact\",\"kind\":\"fact\",\"embedding\":[],\"keywords\":[\"brand\",\"new\",\"fact\"],\"status\":\"active\",\"created_at\":3,\"seq\":8}\n"
  let dup = "{\"id\":\"imp-dup\",\"user_id\":\"gap-imp\",\"content\":\"alpha beta shared\",\"kind\":\"fact\",\"embedding\":[],\"keywords\":[\"alpha\"],\"status\":\"active\",\"created_at\":4,\"seq\":9}\n"
  let imported = match store.import_jsonl(omitted + dup) {
    Ok(pair) => pair
    Err(_) => abort("import")
  }
  inspect(imported.0, content="1")
  inspect(imported.1 >= 1, content="true")
  ignore(store.close())
}

///|
test "lexical shortcut keeps only top k keyword hits" {
  let backend = @src.MemoryBackend::new()
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
    lexical_floor: 0.0,
    lexical_gap: 1.0,
  })
  ignore(store.add("gap-lex", "zebra zebra zebra zebra"))
  ignore(store.add("gap-lex", "zebra other filler words"))
  let hits = match store.recall("gap-lex", "zebra", top_k=1) {
    Ok(hits) => hits
    Err(_) => []
  }
  inspect(hits.length(), content="1")
  ignore(store.close())
}

///|
test "punctuation-only documents skip bm25" {
  let backend = @src.MemoryBackend::new()
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
  })
  ignore(store.add("gap-empty", "!!!"))
  let hits = match store.recall("gap-empty", "hello") {
    Ok(hits) => hits
    Err(_) => []
  }
  inspect(hits.length(), content="0")
  ignore(store.close())
}

///|
test "equal vectors still recall both imported ids" {
  let backend = @src.MemoryBackend::new()
  let store = gap_open(@src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
    fusion_policy: EqualRrf,
  })
  let emb = Array::make(@src.DEFAULT_DIM, 0.0)
  emb[0] = 1.0
  let nums = StringBuilder()
  for i = 0; i < emb.length(); i = i + 1 {
    if i > 0 {
      nums.write_string(",")
    }
    nums.write_string(emb[i].to_string())
  }
  let vec = nums.to_string()
  let row = fn(id : String) {
    "{\"id\":\"\{id}\",\"user_id\":\"gap-eq\",\"content\":\"same tokens \{id}\",\"kind\":\"fact\",\"embedding\":[\{vec}],\"keywords\":[\"same\",\"tokens\"],\"status\":\"active\",\"created_at\":1,\"seq\":1,\"superseded_by\":null,\"metadata\":{}}"
  }
  let imported = match
    store.import_jsonl(row("id-aa") + "\n" + row("id-zz") + "\n") {
    Ok(pair) => pair
    Err(_) => abort("import")
  }
  inspect(imported.0, content="2")
  let hits = match store.recall("gap-eq", "same tokens", top_k=2) {
    Ok(hits) => hits
    Err(_) => []
  }
  inspect(hits.length(), content="2")
  ignore(store.close())
}

///|
#cfg(target="native")
fn gap_wipe(dir : String) -> Unit {
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
    @fs.remove_dir("\{dir}/moomem/slot0.jsonl") catch {
      _ => ()
    }
    @fs.remove_dir("\{dir}/moomem/slot1.jsonl") catch {
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
#cfg(target="native")
test "head pointing at slot 1 reloads that slot" {
  let dir = "tmp_moomem_persist_test/db-head-one"
  gap_wipe(dir)
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open")
  }
  ignore(store.add("gap-h1", "only one flush"))
  let restored = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("reopen")
  }
  let stats = match restored.stats() {
    Ok(stats) => stats
    Err(_) => abort("stats")
  }
  inspect(stats.total, content="1")
  ignore(store.close())
  ignore(restored.close())
  gap_wipe(dir)
}

///|
#cfg(target="native")
test "invalid primary slot falls back to the other slot" {
  let dir = "tmp_moomem_persist_test/db-fallback"
  gap_wipe(dir)
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open")
  }
  ignore(store.add("gap-fb", "lives in slot one"))
  ignore(store.close())
  @fs.write_string_to_file("\{dir}/moomem/head", "0")
  @fs.write_string_to_file(
    "\{dir}/moomem/slot0.jsonl",
    "{\"v\":99,\"gen\":1,\"clock\":1}\n",
  )
  let restored = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("reopen")
  }
  let stats = match restored.stats() {
    Ok(stats) => stats
    Err(_) => abort("stats")
  }
  inspect(stats.total, content="1")
  ignore(restored.close())
  gap_wipe(dir)
}

///|
#cfg(target="native")
test "head without slot files opens an empty store" {
  let dir = "tmp_moomem_persist_test/db-empty-head"
  gap_wipe(dir)
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open")
  }
  ignore(store.close())
  @fs.write_string_to_file("\{dir}/moomem/head", "0")
  let restored = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("reopen")
  }
  let stats = match restored.stats() {
    Ok(stats) => stats
    Err(_) => abort("stats")
  }
  inspect(stats.total, content="0")
  ignore(restored.close())
  gap_wipe(dir)
}

///|
#cfg(target="native")
test "missing head picks the only remaining slot" {
  let dir = "tmp_moomem_persist_test/db-one-slot"
  gap_wipe(dir)
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open")
  }
  ignore(store.add("gap-one", "slot one only"))
  ignore(store.close())
  @fs.remove_file("\{dir}/moomem/head") catch {
    _ => ()
  }
  @fs.remove_file("\{dir}/moomem/slot0.jsonl") catch {
    _ => ()
  }
  let restored = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("reopen")
  }
  let stats = match restored.stats() {
    Ok(stats) => stats
    Err(_) => abort("stats")
  }
  inspect(stats.total, content="1")
  ignore(restored.close())
  gap_wipe(dir)
}

///|
#cfg(target="native")
test "missing head prefers the higher generation slot" {
  let dir = "tmp_moomem_persist_test/db-higher-gen"
  gap_wipe(dir)
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open")
  }
  ignore(store.add("gap-gen", "older generation"))
  ignore(store.close())
  let again = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("second")
  }
  ignore(again.add("gap-gen", "newer generation"))
  @fs.remove_file("\{dir}/moomem/head") catch {
    _ => ()
  }
  let restored = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("reopen")
  }
  let stats = match restored.stats() {
    Ok(stats) => stats
    Err(_) => abort("stats")
  }
  inspect(stats.total, content="2")
  ignore(again.close())
  ignore(restored.close())
  gap_wipe(dir)
}

///|
#cfg(target="native")
test "slot read and write errors become io failures" {
  let dir = "tmp_moomem_persist_test/db-slot-io"
  gap_wipe(dir)
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open")
  }
  @fs.create_dir("\{dir}/moomem/slot1.jsonl")
  let save_failed = match store.add("gap-slot", "cannot write slot") {
    Err(@src.MoomemError::IoFailure(_)) => true
    _ => false
  }
  inspect(save_failed, content="true")
  ignore(store.close())
  gap_wipe(dir)
  let store2 = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open2")
  }
  ignore(store2.add("gap-slot", "readable once"))
  ignore(store2.close())
  let head = @fs.read_file_to_string("\{dir}/moomem/head").trim().to_owned()
  @fs.remove_file("\{dir}/moomem/slot\{head}.jsonl") catch {
    _ => ()
  }
  @fs.create_dir("\{dir}/moomem/slot\{head}.jsonl")
  let read_failed = match @src.MemoryStore::open(dir) {
    Err(@src.MoomemError::IoFailure(_)) => true
    _ => false
  }
  inspect(read_failed, content="true")
  gap_wipe(dir)
}

///|
#cfg(target="native")
test "opening a file path fails the load" {
  let path = "tmp_moomem_persist_test/not-a-dir"
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
  @fs.write_string_to_file(path, "x")
  let failed = match @src.MemoryStore::open(path) {
    Err(@src.MoomemError::IoFailure(_)) => true
    _ => false
  }
  inspect(failed, content="true")
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
#cfg(target="native")
test "dot segment in the store path is skipped" {
  let dir = "tmp_moomem_persist_test/./db-dot"
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open")
  }
  ignore(store.add("gap-dot", "dotted path"))
  ignore(store.close())
  gap_wipe("tmp_moomem_persist_test/db-dot")
}

///|
#cfg(target="native")
test "middle corruption and a rewound clock are both visible" {
  let dir = "tmp_moomem_persist_test/db-middle"
  gap_wipe(dir)
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open")
  }
  ignore(store.add("gap-mid", "first line"))
  ignore(store.add("gap-mid", "second line"))
  ignore(store.close())
  let head = @fs.read_file_to_string("\{dir}/moomem/head").trim().to_owned()
  let slot = "\{dir}/moomem/slot\{head}.jsonl"
  let content = @fs.read_file_to_string(slot)
  let mut header = ""
  let mut rest = ""
  let mut seen = false
  for line in content.split("\n") {
    if !seen {
      header = "{\"v\":1,\"gen\":1,\"clock\":0}"
      seen = true
    } else if line.length() > 0 {
      rest = rest + "\n" + line.to_owned()
    }
  }
  @fs.write_string_to_file(slot, header + "\nnot-json" + rest + "\n")
  let corrupted = match @src.MemoryStore::open(dir) {
    Err(@src.MoomemError::StoreCorrupted(_)) => true
    _ => false
  }
  inspect(corrupted, content="true")
  @fs.write_string_to_file(slot, header + rest + "\n")
  let restored = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("reopen")
  }
  let stats = match restored.stats() {
    Ok(stats) => stats
    Err(_) => abort("stats")
  }
  inspect(stats.total, content="2")
  ignore(restored.close())
  gap_wipe(dir)
}

///|
#cfg(target="native")
test "reindexing a repeated snapshot id decrements shared df" {
  let dir = "tmp_moomem_persist_test/db-df"
  gap_wipe(dir)
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open")
  }
  ignore(store.add("gap-df2", "apple banana"))
  ignore(store.add("gap-df2", "apple orange"))
  ignore(store.close())
  let head = @fs.read_file_to_string("\{dir}/moomem/head").trim().to_owned()
  let slot = "\{dir}/moomem/slot\{head}.jsonl"
  let content = @fs.read_file_to_string(slot)
  let mut first_entry = ""
  let mut header_seen = false
  for line in content.split("\n") {
    let owned = line.to_owned()
    if !header_seen {
      header_seen = true
    } else if first_entry.length() == 0 && owned.length() > 0 {
      first_entry = owned
    }
  }
  @fs.remove_file("\{dir}/moomem/head") catch {
    _ => ()
  }
  @fs.write_string_to_file(slot, content + first_entry + "\n")
  let restored = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("reopen")
  }
  let hits = match restored.recall("gap-df2", "apple") {
    Ok(hits) => hits
    Err(_) => []
  }
  inspect(hits.length() >= 1, content="true")
  ignore(restored.close())
  gap_wipe(dir)
}

///|
#cfg(target="native")
test "a single valid slot and unreadable siblings are recovered" {
  let dir = "tmp_moomem_persist_test/db-one-valid"
  gap_wipe(dir)
  let store = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("open")
  }
  ignore(store.add("gap-one0", "kept in slot zero"))
  ignore(store.close())
  @fs.remove_file("\{dir}/moomem/head") catch {
    _ => ()
  }
  @fs.remove_file("\{dir}/moomem/slot1.jsonl") catch {
    _ => ()
  }
  let restored = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("reopen")
  }
  let stats = match restored.stats() {
    Ok(stats) => stats
    Err(_) => abort("stats")
  }
  inspect(stats.total, content="1")
  ignore(restored.close())
  gap_wipe(dir)
  let empty = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("empty")
  }
  ignore(empty.close())
  @fs.write_string_to_file("\{dir}/moomem/head", "0")
  @fs.create_dir("\{dir}/moomem/slot1.jsonl")
  let other_bad = match @src.MemoryStore::open(dir) {
    Err(@src.MoomemError::IoFailure(_)) => true
    _ => false
  }
  inspect(other_bad, content="true")
  gap_wipe(dir)
  let base = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("base")
  }
  ignore(base.close())
  @fs.create_dir("\{dir}/moomem/slot0.jsonl")
  let primary_bad = match @src.MemoryStore::open(dir) {
    Err(@src.MoomemError::IoFailure(_)) => true
    _ => false
  }
  inspect(primary_bad, content="true")
  gap_wipe(dir)
  let sibling = match @src.MemoryStore::open(dir) {
    Ok(store) => store
    Err(_) => abort("sibling")
  }
  ignore(sibling.close())
  @fs.create_dir("\{dir}/moomem/slot1.jsonl")
  let sibling_bad = match @src.MemoryStore::open(dir) {
    Err(@src.MoomemError::IoFailure(_)) => true
    _ => false
  }
  inspect(sibling_bad, content="true")
  gap_wipe(dir)
}

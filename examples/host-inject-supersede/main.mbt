// 宿主注入 Embedder 与 Extractor。ConflictJudge 留空，走缺省 SimilarityJudge。
// 主题嵌入把「住 / 搬到」映到同一向量，余弦达到 supersede 阈值后旧住址被覆盖。
// recall 不再返回 Superseded；list_entries 仍能看到，供审计。
//
//   moon run examples/host-inject-supersede --target native

///|
struct ResidenceEmbedder {}

///|
pub impl @src.Embedder for ResidenceEmbedder with fn embed(_self, texts) {
  Ok(texts.map(text => residence_vector(text)))
}

///|
pub impl @src.Embedder for ResidenceEmbedder with fn dim(_self) {
  @src.DEFAULT_DIM
}

///|
pub extend ResidenceEmbedder with @src.Embedder::{ embed, dim }

///|
fn residence_vector(text : String) -> Array[Double] {
  let vector = Array::make(@src.DEFAULT_DIM, 0.0)
  if text.contains("住") || text.contains("搬到") {
    vector[0] = 1.0
  } else {
    vector[1] = 1.0
  }
  vector
}

///|
struct ResidenceExtractor {}

///|
pub impl @src.Extractor for ResidenceExtractor with fn extract(_, _, text) {
  if text.trim().length() == 0 {
    return Ok([])
  }
  Ok([
    @src.ExtractedFact::{
      content: text,
      kind: @src.EntryKind::Fact,
      source_span: None,
      degraded: false,
      degrade_reason: None,
    },
  ])
}

///|
pub impl @src.Extractor for ResidenceExtractor with fn mode(_) {
  "host"
}

///|
pub extend ResidenceExtractor with @src.Extractor::{ extract, mode }

///|
fn reset_dir(dir : String) -> Unit {
  if @fs.path_exists(dir) {
    @fs.remove_file("\{dir}/moomem/slot0.jsonl") catch { _ => () }
    @fs.remove_file("\{dir}/moomem/slot1.jsonl") catch { _ => () }
    @fs.remove_file("\{dir}/moomem/head") catch { _ => () }
    @fs.remove_dir("\{dir}/moomem") catch { _ => () }
    @fs.remove_dir(dir) catch { _ => () }
  }
}

///|
fn print_entries(store : @src.MemoryStore) -> Unit {
  match store.list_entries("user-42") {
    Ok(entries) =>
      for entry in entries {
        let replaced_by = match entry.superseded_by {
          Some(id) => id
          None => "-"
        }
        println(
          "  [\{entry.status}] \{entry.kind} superseded_by=\{replaced_by} | \{entry.content}",
        )
      }
    Err(e) => {
      println("  list error: \{e.message()}")
      abort("list failed")
    }
  }
}

///|
fn main {
  println("=== host-inject-supersede  宿主 Embedder + Extractor，缺省 SimilarityJudge ===")
  println("")
  let dir = "/tmp/moomem-demo-host-inject-supersede"
  reset_dir(dir)
  let embedder : &@src.Embedder = ResidenceEmbedder::{  }
  let extractor : &@src.Extractor = ResidenceExtractor::{  }
  let config : @src.Config = @src.Config::{
    ..@src.Config::default(),
    embedder: Some(embedder),
    extractor: Some(extractor),
  }
  let store = match @src.MemoryStore::open(dir, config=config) {
    Ok(opened) => opened
    Err(e) => {
      println("open failed: \{e.message()}")
      abort("open failed")
    }
  }
  println("[add] 用户住北京")
  match store.add("user-42", "用户住北京") {
    Ok(summary) => println("  inserted=\{summary.inserted} superseded=\{summary.superseded}")
    Err(e) => {
      println("  error: \{e.message()}")
      abort("add failed")
    }
  }
  println("[list] 覆盖前")
  print_entries(store)
  println("[add] 我最近搬到深圳了")
  match store.add("user-42", "我最近搬到深圳了") {
    Ok(summary) => {
      println("  inserted=\{summary.inserted} superseded=\{summary.superseded}")
      if summary.superseded != 1 {
        abort("expected the old address to be superseded")
      }
    }
    Err(e) => {
      println("  error: \{e.message()}")
      abort("add failed")
    }
  }
  println("[list] 覆盖后（Superseded 仍在快照里）")
  print_entries(store)
  println("[recall] 住")
  match store.recall("user-42", "住", top_k=3) {
    Ok(hits) =>
      for hit in hits {
        if hit.status != @src.EntryStatus::Active {
          abort("recall returned a non-active entry")
        }
        println("  [\{hit.status}] \{hit.content}")
      }
    Err(e) => {
      println("  error: \{e.message()}")
      abort("recall failed")
    }
  }
  match store.stats() {
    Ok(stats) =>
      println(
        "[stats] active=\{stats.active} superseded=\{stats.superseded} extractor=\{stats.extractor_mode}",
      )
    Err(e) => {
      println("[stats] error: \{e.message()}")
      abort("stats failed")
    }
  }
  ignore(store.close())
  println("")
  println("=== 演示结束 ===")
}

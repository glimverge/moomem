// moomem E2 示例：冲突判定与 supersede 可见编排。
//
// 运行（零网络；AlwaysReplace + 主题 mock 嵌入器）：
//   moon run examples/conflict-supersede --target native
//
// 断言仍在 L0 `store_e2e_test`（AC-04）；本包只做教学演示。

///|
/// 恒 Replace 裁决：凡命中候选一律 supersede（教学用确定性 judge）。
struct AlwaysReplaceJudge {}

///|
pub impl @src.ConflictJudge for AlwaysReplaceJudge with fn judge(_, _, candidates) {
  Ok(
    candidates.map(c => @src.ConflictVerdict::{
      existing: c,
      decision: @src.ConflictDecision::Replace,
    }),
  )
}

///|
pub extend AlwaysReplaceJudge with @src.ConflictJudge::{judge}

///|
/// 主题 mock 嵌入器：把「住址」类陈述映射到相近向量，使冲突候选能互相命中。
struct ResidenceTopicEmbedder {}

///|
pub impl @src.Embedder for ResidenceTopicEmbedder with fn embed(_self, texts) {
  Ok(texts.map(t => residence_topic_vec(t)))
}

///|
pub impl @src.Embedder for ResidenceTopicEmbedder with fn dim(_self) {
  @src.DEFAULT_DIM
}

///|
pub extend ResidenceTopicEmbedder with @src.Embedder::{embed, dim}

///|
fn residence_topic_vec(text : String) -> Array[Double] {
  let v = Array::make(@src.DEFAULT_DIM, 0.0)
  if text.contains("住") || text.contains("搬到") {
    v[0] = 1.0
  } else {
    v[1] = 1.0
  }
  v
}

///|
fn print_entries(store : @src.MemoryStore, user : String) -> Unit {
  match store.list_entries(user) {
    Ok(entries) =>
      for e in entries {
        let by = match e.superseded_by {
          Some(id) => id
          None => "-"
        }
        println("  [\{e.status}] id=\{e.id} superseded_by=\{by} | \{e.content}")
      }
    Err(e) => println("  list error: \{e.message()}")
  }
}

///|
fn main {
  println("=== moomem E2: conflict-supersede（AlwaysReplace，零网络） ===")
  println("")
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let judge : &@src.ConflictJudge = AlwaysReplaceJudge::{ }
  let embedder : &@src.Embedder = ResidenceTopicEmbedder::{ }
  let cfg : @src.Config = @src.Config::{
    ..@src.Config::default(),
    embedder: Some(embedder),
    judge: Some(judge),
    persistence: Some(backend),
  }
  let store = match @src.MemoryStore::open(
    "memory://conflict-supersede",
    config=cfg,
  ) {
    Ok(s) => s
    Err(e) => {
      println("open failed: \{e.message()}")
      return
    }
  }
  // 1) 旧住址入库
  println("[add] 用户住北京")
  match store.add("user-42", "用户住北京") {
    Ok(s) =>
      println(
        "  -> inserted=\{s.inserted} superseded=\{s.superseded}",
      )
    Err(e) => println("  -> error: \{e.message()}")
  }
  println("[list] 冲突前")
  print_entries(store, "user-42")
  // 2) 新住址触发 Replace → 旧条目 Superseded
  println("[add] 我最近搬到深圳了")
  match store.add("user-42", "我最近搬到深圳了") {
    Ok(s) =>
      println(
        "  -> inserted=\{s.inserted} superseded=\{s.superseded}",
      )
    Err(e) => println("  -> error: \{e.message()}")
  }
  println("[list] 冲突后（含 Superseded，可审计）")
  print_entries(store, "user-42")
  // 3) recall 只见 Active
  println("[recall] 查询「住」——仅 Active 可见")
  match store.recall("user-42", "住") {
    Ok(hits) =>
      for h in hits {
        println("  -> [\{h.status}] \{h.content}")
      }
    Err(e) => println("  -> error: \{e.message()}")
  }
  match store.stats() {
    Ok(st) =>
      println(
        "[stats] total=\{st.total} active=\{st.active} superseded=\{st.superseded}",
      )
    Err(e) => println("[stats] error: \{e.message()}")
  }
  ignore(store.close())
  println("")
  println("=== 演示结束 ===")
}

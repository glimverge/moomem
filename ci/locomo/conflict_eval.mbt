// Conflict supersede evaluation (near_duplicate scored; semantic recorded).

///|
fn open_conflict_store() -> @src.MemoryStore {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg = @src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
  }
  match @src.MemoryStore::open("memory://locomo-conflict", config=cfg) {
    Ok(s) => s
    Err(e) => fail("open conflict store: \{e.message()}")
  }
}

///|
fn pair_similarity(old_text : String, new_text : String) -> (Double, Double, Double) {
  let emb = match @src.HashingEmbedder::new(@src.DEFAULT_DIM) {
    Ok(e) => e
    Err(e) => fail("HashingEmbedder::new: \{e.message()}")
  }
  let vecs = match emb.embed([old_text, new_text]) {
    Ok(vs) => vs
    Err(e) => fail("embed conflict pair: \{e.message()}")
  }
  let cos = if vecs.length() >= 2 {
    @src.cosine_similarity(vecs[0], vecs[1])
  } else {
    0.0
  }
  let jac = @src.keyword_jaccard(old_text, @src.tokenize(new_text))
  let mx = if cos >= jac { cos } else { jac }
  (cos, jac, mx)
}

///|
fn evaluate_near_duplicate(pairs : Array[ConflictPairCase]) -> (Int, Int, Double) {
  let store = open_conflict_store()
  let mut ok = 0
  let mut min_sim = 2.0
  for p in pairs {
    let user = "nd-\{p.id}"
    ignore(store.add(user, p.old_text))
    ignore(store.add(user, p.new_text))
    let entries = match store.list_entries(user) {
      Ok(es) => es
      Err(e) => fail("list_entries(\{user}): \{e.message()}")
    }
    let mut old_superseded = false
    let mut new_active = false
    for e in entries {
      if e.content == p.old_text && e.status == @src.EntryStatus::Superseded {
        old_superseded = true
      }
      if e.content == p.new_text && e.is_recallable() {
        new_active = true
      }
    }
    if old_superseded && new_active {
      ok = ok + 1
    }
    let (_, _, mx) = pair_similarity(p.old_text, p.new_text)
    if mx < min_sim {
      min_sim = mx
    }
  }
  ignore(store.close())
  (ok, pairs.length(), min_sim)
}

///|
fn evaluate_semantic_record(pairs : Array[ConflictPairCase]) -> Unit {
  println("### Semantic pairs (record-only, expect ignore offline)")
  println("")
  println("| id | cos | jac | max | old status | expect_offline |")
  println("|---|---:|---:|---:|---|---|")
  let store = open_conflict_store()
  for p in pairs {
    let user = "sem-\{p.id}"
    ignore(store.add(user, p.old_text))
    ignore(store.add(user, p.new_text))
    let entries = match store.list_entries(user) {
      Ok(es) => es
      Err(e) => fail("list_entries(\{user}): \{e.message()}")
    }
    let mut old_status = "?"
    for e in entries {
      if e.content == p.old_text {
        old_status = e.status.to_string()
      }
    }
    let (cos, jac, mx) = pair_similarity(p.old_text, p.new_text)
    println(
      "| \{p.id} | \{format_mrr(cos)} | \{format_mrr(jac)} | \{format_mrr(mx)} | \{old_status} | ignore |",
    )
  }
  ignore(store.close())
  println("")
}

///|
fn run_conflict_eval(fx : ConflictFixture) -> Double {
  let (ok, total, min_sim) = evaluate_near_duplicate(fx.near_duplicate)
  let rate = if total == 0 { 0.0 } else { ok.to_double() / total.to_double() }
  println("### Near-duplicate supersede (scored)")
  println("")
  println("| metric | value |")
  println("|---|---|")
  println("| supersede correct | \{ok}/\{total} (\{format_mrr(rate)}) |")
  println("| min similarity (max of cos/jac) | \{format_mrr(min_sim)} |")
  let margin = min_sim - @src.DEFAULT_SUPERSEDE_THRESHOLD
  println("| margin vs 0.82 | \{format_mrr(margin)} |")
  if margin < 0.03 && margin > -0.03 {
    println("MARGIN_WARN: near-duplicate min similarity within 0.82 ± 0.03")
  }
  println("")
  evaluate_semantic_record(fx.semantic)
  rate
}

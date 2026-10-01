// Retrieval evaluation: hybrid vs BM25-only (+ optional NoBackfill control).

///|
struct RetrievalScores {
  hit : Int
  total : Int
  mrr_sum : Double
  // category 1..4
  cat_hit : Array[Int]
  cat_total : Array[Int]
  cat_mrr : Array[Double]
  adversarial_excluded : Int
}

///|
fn empty_scores() -> RetrievalScores {
  RetrievalScores::{
    hit: 0,
    total: 0,
    mrr_sum: 0.0,
    cat_hit: [0, 0, 0, 0, 0],
    cat_total: [0, 0, 0, 0, 0],
    cat_mrr: [0.0, 0.0, 0.0, 0.0, 0.0],
    adversarial_excluded: 0,
  }
}

///|
fn register_prov(
  prov : Map[String, Array[String]],
  content : String,
  dia_id : String,
) -> Unit {
  match prov.get(content) {
    Some(arr) => {
      if !arr.contains(dia_id) {
        arr.push(dia_id)
      }
    }
    None => prov.set(content, [dia_id])
  }
}

///|
fn evidence_hit(
  hits : Array[@src.MemoryEntry],
  evidence : Array[String],
  prov : Map[String, Array[String]],
) -> Int? {
  // return 1-based rank of first hit matching any evidence dia_id
  let mut rank = 1
  for h in hits {
    match prov.get(h.content) {
      Some(dias) => {
        for d in dias {
          if evidence.contains(d) {
            return Some(rank)
          }
        }
      }
      None => ()
    }
    rank = rank + 1
  }
  None
}

///|
fn open_retrieval_store(
  embedder : &@src.Embedder?,
  dim : Int,
  backfill : @src.RecallBackfill,
) -> @src.MemoryStore {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let judge : &@src.ConflictJudge = NoConflictJudge::{ }
  let cfg = @src.Config::{
    ..@src.Config::default(),
    embedder,
    judge: Some(judge),
    persistence: Some(backend),
    dim,
    backfill,
  }
  match @src.MemoryStore::open("memory://locomo-retrieval", config=cfg) {
    Ok(s) => s
    Err(e) => fail("open retrieval store: \{e.message()}")
  }
}

///|
fn ingest_conversations(
  store : @src.MemoryStore,
  data : LocomoSubset,
) -> Map[String, Array[String]] {
  let prov : Map[String, Array[String]] = Map([])
  for conv in data.conversations {
    let uid = conv.sample_id
    for t in conv.turns {
      match store.add(uid, t.text) {
        Ok(_) => register_prov(prov, t.text, t.dia_id)
        Err(e) => fail("add(\{uid}): \{e.message()}")
      }
    }
  }
  prov
}

///|
fn score_retrieval(
  store : @src.MemoryStore,
  data : LocomoSubset,
  prov : Map[String, Array[String]],
  limit : Int,
) -> RetrievalScores {
  let scores = empty_scores()
  let mut scored = 0
  for conv in data.conversations {
    for q in conv.qa {
      if q.category == 5 {
        scores.adversarial_excluded = scores.adversarial_excluded + 1
      } else if limit > 0 && scored >= limit {
        ()
      } else {
        scored = scored + 1
        scores.total = scores.total + 1
        if q.category >= 1 && q.category <= 4 {
          scores.cat_total[q.category] = scores.cat_total[q.category] + 1
        }
        let hits = match store.recall(conv.sample_id, q.question, top_k=5) {
          Ok(h) => h
          Err(e) => fail("recall(\{conv.sample_id}): \{e.message()}")
        }
        match evidence_hit(hits, q.evidence, prov) {
          Some(rank) => {
            scores.hit = scores.hit + 1
            scores.mrr_sum = scores.mrr_sum + 1.0 / rank.to_double()
            if q.category >= 1 && q.category <= 4 {
              scores.cat_hit[q.category] = scores.cat_hit[q.category] + 1
              scores.cat_mrr[q.category] = scores.cat_mrr[q.category] +
                1.0 / rank.to_double()
            }
          }
          None => ()
        }
      }
    }
  }
  scores
}

///|
fn print_retrieval_block(title : String, s : RetrievalScores) -> Unit {
  println("### \{title}")
  println("")
  println("| metric | value |")
  println("|---|---|")
  println(
    "| Recall@5 | \{s.hit}/\{s.total} (\{format_ratio(s.hit, s.total)}) |",
  )
  let mrr = if s.total == 0 { 0.0 } else { s.mrr_sum / s.total.to_double() }
  println("| MRR@5 | \{format_mrr(mrr)} |")
  println("| adversarial excluded | \{s.adversarial_excluded} |")
  println("")
  println("| category | Recall@5 | MRR@5 |")
  println("|---|---|---|")
  let names = ["", "multi-hop", "temporal", "open-domain", "single-hop"]
  for c in 1..=4 {
    let hit = s.cat_hit[c]
    let tot = s.cat_total[c]
    let cmrr = if tot == 0 { 0.0 } else { s.cat_mrr[c] / tot.to_double() }
    println(
      "| \{c} \{names[c]} | \{hit}/\{tot} (\{format_ratio(hit, tot)}) | \{format_mrr(cmrr)} |",
    )
  }
  println("")
}

///|
fn run_retrieval_eval(
  data : LocomoSubset,
  embedder_mode : String,
  api_embedder : &@src.Embedder?,
  api_dim : Int,
  limit : Int,
) -> (RetrievalScores, RetrievalScores) {
  println("note: retrieval uses NoConflictJudge so near-duplicate turns do not supersede (retrieval-only isolation).")
  println("note: primary numbers use default BackfillRecency; NoBackfill control printed separately.")
  println("")

  // ---- hybrid ----
  let hybrid_emb : &@src.Embedder? = if embedder_mode == "api" {
    api_embedder
  } else {
    None // HashingEmbedder default
  }
  let hybrid_dim = if embedder_mode == "api" { api_dim } else { @src.DEFAULT_DIM }
  let store_h = open_retrieval_store(
    hybrid_emb,
    hybrid_dim,
    @src.RecallBackfill::BackfillRecency,
  )
  let prov_h = ingest_conversations(store_h, data)
  let hybrid = score_retrieval(store_h, data, prov_h, limit)
  ignore(store_h.close())
  print_retrieval_block("Hybrid (embedder=\{embedder_mode}, backfill=Recency)", hybrid)

  // ---- bm25 only ----
  let null_e : &@src.Embedder = NullEmbedder::{ }
  let store_b = open_retrieval_store(
    Some(null_e),
    @src.DEFAULT_DIM,
    @src.RecallBackfill::BackfillRecency,
  )
  let prov_b = ingest_conversations(store_b, data)
  let bm25 = score_retrieval(store_b, data, prov_b, limit)
  ignore(store_b.close())
  print_retrieval_block("BM25-only baseline (NullEmbedder, backfill=Recency)", bm25)

  // comparison
  let h_r = if hybrid.total == 0 {
    0.0
  } else {
    hybrid.hit.to_double() / hybrid.total.to_double()
  }
  let b_r = if bm25.total == 0 {
    0.0
  } else {
    bm25.hit.to_double() / bm25.total.to_double()
  }
  let abs_delta = h_r - b_r
  let rel = if b_r == 0.0 {
    0.0
  } else {
    abs_delta / b_r
  }
  println("### Hybrid vs BM25-only")
  println("")
  println("| | Recall@5 | abs Δ | rel Δ |")
  println("|---|---|---|---|")
  println(
    "| hybrid - bm25 | \{format_mrr(h_r)} vs \{format_mrr(b_r)} | \{format_mrr(abs_delta)} | \{format_pct(rel)} |",
  )
  if embedder_mode == "api" {
    if rel + 1e-12 >= 0.15 {
      println("TARGET_15PCT: met")
    } else {
      println("TARGET_15PCT: missed")
    }
  } else {
    println("TARGET_15PCT: n/a (offline hashing; not asserted)")
  }
  println("")

  // ---- NoBackfill control (hybrid only) ----
  let store_nb = open_retrieval_store(
    hybrid_emb,
    hybrid_dim,
    @src.RecallBackfill::NoBackfill,
  )
  let prov_nb = ingest_conversations(store_nb, data)
  let nobf = score_retrieval(store_nb, data, prov_nb, limit)
  ignore(store_nb.close())
  print_retrieval_block(
    "Hybrid control (embedder=\{embedder_mode}, backfill=NoBackfill)",
    nobf,
  )

  (hybrid, bm25)
}

// LoCoMo L3 evaluation entrypoint (W4).
//
// Offline (default):
//   moon run ci/locomo --target native
// API embedder:
//   moon run ci/locomo --target native -- --embedder api
// Live extraction:
//   moon run ci/locomo --target native -- --live

///|
fn main {
  let opts = parse_args()
  if opts.help {
    print_help()
    return
  }
  println("# moomem L3 LoCoMo evaluation")
  println("")
  println(
    "mode: embedder=\{opts.embedder} live=\{opts.live} limit=\{opts.limit}",
  )
  println("")

  let fixture = resolve_fixture_path(opts)
  println("fixture: \{fixture}")
  let data = load_locomo_subset(fixture)
  println(
    "loaded conversations=\{data.conversations.length()}",
  )
  println("")

  // ---- optional API embedder (only when requested) ----
  let mut api_emb : &@src.Embedder? = None
  let mut api_dim = @src.DEFAULT_DIM
  if opts.embedder == "api" {
    let emb = ApiEmbedder::from_env()
    let d = emb.probe_dim()
    println("api embedder dim=\{d} model=\{emb.model}")
    api_dim = d
    api_emb = Some(emb as &@src.Embedder)
  }

  // ---- retrieval ----
  println("## Retrieval")
  println("")
  let (hybrid, bm25) = run_retrieval_eval(
    data,
    opts.embedder,
    api_emb,
    api_dim,
    opts.limit,
  )

  // ---- conflict ----
  println("## Conflict")
  println("")
  let conflict_path = "ci/locomo/data/conflict_pairs.json"
  let conflicts = load_conflict_fixture(conflict_path)
  let supersede_rate = run_conflict_eval(conflicts)

  // ---- persistence / isolation ----
  println("## Persistence & Isolation")
  println("")
  let leaks = run_isolation_eval(data)
  let persist_ok = run_persistence_eval()

  // ---- extraction ----
  println("## Extraction")
  println("")
  if opts.live {
    let gold = load_extraction_gold("ci/locomo/data/extraction_gold.json")
    ignore(run_extraction_live(gold))
  } else {
    run_extraction_offline_skip()
  }

  // ---- gates (offline) ----
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
  let mut ok = true
  if leaks != 0 {
    println("gate fail: cross-user leaks=\{leaks}")
    ok = false
  }
  if persist_ok != 1 {
    println("gate fail: persistence reopen inconsistent")
    ok = false
  }
  // Offline hashing has no semantics; RRF with noisy vectors can underperform
  // pure BM25. Non-regression hybrid≥bm25 is enforced only for --embedder api
  // (see TARGET_15PCT). Hashing mode still reports the comparison above.
  if opts.embedder == "api" && h_r < b_r {
    println(
      "gate fail: hybrid Recall@5 \{format_mrr(h_r)} < bm25 \{format_mrr(b_r)}",
    )
    ok = false
  } else if opts.embedder == "hashing" && h_r < b_r {
    println(
      "NON_REGRESSION: hybrid_below_bm25 under hashing (report-only; quality claim requires --embedder api)",
    )
  }
  if supersede_rate < 0.8 {
    println(
      "gate fail: near-duplicate supersede \{format_mrr(supersede_rate)} < 0.800",
    )
    ok = false
  }
  if ok {
    println("LOCOMO_PASS")
  } else {
    fail("offline LoCoMo gates not met")
  }
}

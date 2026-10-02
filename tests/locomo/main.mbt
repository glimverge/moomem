// LoCoMo L3 evaluation entrypoint (W4).
//
// Offline:
//   moon run tests/locomo --target native
// Machine-readable report:
//   moon run tests/locomo --target native -- --report /tmp/offline.json

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
    "mode: embedder=\{opts.embedder} live=\{opts.live} limit=\{opts.limit} extract_limit=\{opts.extract_limit}",
  )
  println("")

  let fixture = resolve_fixture_path(opts)
  println("fixture: \{fixture}")
  let data = load_locomo_subset(fixture)
  println(
    "loaded conversations=\{data.conversations.length()}",
  )
  println("")

  // ---- retrieval (hashing embedder only; host supplies a real Embedder) ----
  println("## Retrieval")
  println("")
  let (hybrid, bm25) = run_retrieval_eval(
    data,
    opts.embedder,
    None,
    @src.DEFAULT_DIM,
    opts.limit,
  )

  // ---- conflict ----
  println("## Conflict")
  println("")
  let conflict_path = "tests/locomo/data/conflict_pairs.json"
  let conflicts = load_conflict_fixture(conflict_path)
  let conflict = run_conflict_eval(conflicts)

  // ---- persistence / isolation ----
  println("## Persistence & Isolation")
  println("")
  let leaks = run_isolation_eval(data)
  let persist_ok = run_persistence_eval()

  // ---- extraction ----
  println("## Extraction")
  println("")
  let extraction = run_extraction_offline_skip()

  // ---- gates ----
  let h_r = recall_of(hybrid)
  let b_r = recall_of(bm25)
  let mut ok = true
  let mut gate_isolation = "pass"
  let mut gate_persistence = "pass"
  let mut gate_conflict = "pass"
  let mut gate_hybrid = "n_a"
  let mut gate_target = "n_a"
  let mut gate_extraction = if extraction.skipped { "skipped" } else { "pass" }

  if leaks != 0 {
    println("gate fail: cross-user leaks=\{leaks}")
    ok = false
    gate_isolation = "fail"
  }
  if persist_ok != 1 {
    println("gate fail: persistence reopen inconsistent")
    ok = false
    gate_persistence = "fail"
  }
  // Offline hashing has no semantics; RRF with noisy vectors can underperform
  // pure BM25. Non-regression hybrid≥bm25 is enforced only for --embedder api
  // (see TARGET_15PCT). Hashing mode still reports the comparison above.
  if opts.embedder == "api" && h_r < b_r {
    println(
      "gate fail: hybrid Recall@5 \{format_mrr(h_r)} < bm25 \{format_mrr(b_r)}",
    )
    ok = false
    gate_hybrid = "fail"
  } else if opts.embedder == "api" {
    gate_hybrid = "pass"
  } else if opts.embedder == "hashing" && h_r < b_r {
    println(
      "NON_REGRESSION: hybrid_below_bm25 under hashing (report-only; quality claim requires --embedder api)",
    )
  }
  let t15 = target_15pct_label(opts.embedder, h_r, b_r)
  // TARGET_15PCT is recorded in the report; hard fail remains hybrid≥bm25 (api).
  if opts.embedder == "api" {
    gate_target = if t15 == "met" { "pass" } else { "fail" }
  }
  if conflict.rate < 0.8 {
    println(
      "gate fail: near-duplicate supersede \{format_mrr(conflict.rate)} < 0.800",
    )
    ok = false
    gate_conflict = "fail"
  }
  // Extraction precision is recorded only (live stdout already prints PASS/MISSED).
  if !extraction.skipped {
    gate_extraction = if extraction.precision >= 0.8 { "pass" } else { "fail" }
  }

  let status = if ok { "pass" } else { "fail" }
  let gate_overall = if ok { "pass" } else { "fail" }
  let report_path = resolve_report_path(opts)
  if report_path.length() > 0 {
    let report = ModeReport::{
      mode: mode_name(opts),
      embedder: opts.embedder,
      model: "",
      dim: 0,
      extractor_model: extraction.model,
      hybrid_recall: h_r,
      hybrid_mrr: mrr_of(hybrid),
      bm25_recall: b_r,
      bm25_mrr: mrr_of(bm25),
      vs_bm25_pct: vs_bm25_pct(h_r, b_r),
      target_15pct: t15,
      conflict,
      cross_user_leaks: leaks,
      reopen_ok: persist_ok,
      extraction,
      status,
      gate_isolation,
      gate_persistence,
      gate_conflict,
      gate_hybrid_ge_bm25: gate_hybrid,
      gate_target_15pct: gate_target,
      gate_extraction,
      gate_overall,
    }
    write_mode_report(report_path, report)
  }

  if ok {
    println("LOCOMO_PASS")
  } else if opts.report_only_exit {
    println("LOCOMO_FAIL: gates not met (report-only-exit; continuing)")
  } else {
    fail("\{mode_name(opts)} LoCoMo gates not met")
  }
}

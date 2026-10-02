// Machine-readable LoCoMo report writer (--report / MOOMEM_LOCOMO_REPORT).
// Never serializes API keys — only model ids, dims, metrics, and gate statuses.

///|
struct ExtractionReport {
  skipped : Bool
  precision : Double
  hit : Int
  denom : Int
  model : String
  /// Gold cases actually scored this run (after --extract-limit).
  cases_scored : Int
  /// Full gold set size (100); 0 when skipped.
  cases_total : Int
}

///|
struct ConflictReport {
  ok : Int
  total : Int
  rate : Double
}

///|
struct ModeReport {
  mode : String // offline | api | live
  embedder : String
  model : String // "" if none
  dim : Int // 0 if none / n_a
  extractor_model : String // "" if none
  hybrid_recall : Double
  hybrid_mrr : Double
  bm25_recall : Double
  bm25_mrr : Double
  vs_bm25_pct : Double
  target_15pct : String // met | missed | n_a
  conflict : ConflictReport
  cross_user_leaks : Int
  reopen_ok : Int
  extraction : ExtractionReport
  status : String // pass | fail
  gate_isolation : String
  gate_persistence : String
  gate_conflict : String
  gate_hybrid_ge_bm25 : String
  gate_target_15pct : String
  gate_extraction : String
  gate_overall : String
}

///|
fn json_null() -> Json {
  Json::null()
}

///|
fn json_opt_string(s : String) -> Json {
  if s.length() == 0 {
    json_null()
  } else {
    Json::string(s)
  }
}

///|
fn json_opt_int(v : Int, present : Bool) -> Json {
  if present {
    Json::number(v.to_double())
  } else {
    json_null()
  }
}

///|
fn build_mode_report_json(r : ModeReport) -> Json {
  let metrics : Map[String, Json] = Map([])
  metrics["hybrid_recall_at_5"] = Json::number(r.hybrid_recall)
  metrics["hybrid_mrr_at_5"] = Json::number(r.hybrid_mrr)
  metrics["bm25_recall_at_5"] = Json::number(r.bm25_recall)
  metrics["bm25_mrr_at_5"] = Json::number(r.bm25_mrr)
  metrics["vs_bm25_pct"] = Json::number(r.vs_bm25_pct)
  metrics["target_15pct"] = Json::string(r.target_15pct)
  metrics["near_dup_supersede_rate"] = Json::number(r.conflict.rate)
  metrics["near_dup_ok"] = Json::number(r.conflict.ok.to_double())
  metrics["near_dup_total"] = Json::number(r.conflict.total.to_double())
  metrics["cross_user_leaks"] = Json::number(r.cross_user_leaks.to_double())
  metrics["reopen_ok"] = Json::number(r.reopen_ok.to_double())
  if r.extraction.skipped {
    metrics["extraction_precision"] = json_null()
    metrics["extraction_hit"] = json_null()
    metrics["extraction_denom"] = json_null()
    metrics["extraction_status"] = Json::string("skipped")
    metrics["extraction_cases_scored"] = json_null()
    metrics["extraction_cases_total"] = json_null()
  } else {
    metrics["extraction_precision"] = Json::number(r.extraction.precision)
    metrics["extraction_hit"] = Json::number(r.extraction.hit.to_double())
    metrics["extraction_denom"] = Json::number(r.extraction.denom.to_double())
    metrics["extraction_status"] = Json::string("scored")
    metrics["extraction_cases_scored"] = Json::number(
      r.extraction.cases_scored.to_double(),
    )
    metrics["extraction_cases_total"] = Json::number(
      r.extraction.cases_total.to_double(),
    )
  }

  let gates : Map[String, Json] = Map([])
  gates["isolation"] = Json::string(r.gate_isolation)
  gates["persistence"] = Json::string(r.gate_persistence)
  gates["conflict"] = Json::string(r.gate_conflict)
  gates["hybrid_ge_bm25"] = Json::string(r.gate_hybrid_ge_bm25)
  gates["target_15pct"] = Json::string(r.gate_target_15pct)
  gates["extraction_precision"] = Json::string(r.gate_extraction)
  gates["overall"] = Json::string(r.gate_overall)

  let run : Map[String, Json] = Map([])
  run["embedder"] = Json::string(r.embedder)
  run["model"] = json_opt_string(r.model)
  run["dim"] = json_opt_int(r.dim, r.dim > 0)
  run["extractor_model"] = json_opt_string(r.extractor_model)
  run["metrics"] = Json::object(metrics)
  run["gates"] = Json::object(gates)
  run["status"] = Json::string(r.status)

  let root : Map[String, Json] = Map([])
  root["schema_version"] = Json::number(1.0)
  root["mode"] = Json::string(r.mode)
  root["run"] = Json::object(run)
  Json::object(root)
}

///|
fn write_mode_report(path : String, r : ModeReport) -> Unit {
  let text = build_mode_report_json(r).stringify()
  let abs = if path.has_prefix("/") {
    path
  } else {
    let cwd = match @env.current_dir() {
      Some(d) => d
      None => "."
    }
    "\{cwd}/\{path}"
  }
  @fs.write_string_to_file(abs, text) catch {
    e => {
      let detail = match e {
        @fs.IOError(msg) => msg
      }
      fail("cannot write report \{abs}: \{detail}")
    }
  }
  println("report written: \{abs}")
}

///|
fn resolve_report_path(opts : CliOpts) -> String {
  if opts.report.length() > 0 {
    return opts.report
  }
  match @env.get_env_var("MOOMEM_LOCOMO_REPORT") {
    Some(p) => {
      let v = p.trim().to_owned()
      if v.length() > 0 {
        return v
      }
    }
    None => ()
  }
  ""
}

///|
fn recall_of(s : RetrievalScores) -> Double {
  if s.total == 0 {
    0.0
  } else {
    s.hit.to_double() / s.total.to_double()
  }
}

///|
fn mrr_of(s : RetrievalScores) -> Double {
  if s.total == 0 {
    0.0
  } else {
    s.mrr_sum / s.total.to_double()
  }
}

///|
fn vs_bm25_pct(hybrid_r : Double, bm25_r : Double) -> Double {
  if bm25_r == 0.0 {
    0.0
  } else {
    ((hybrid_r - bm25_r) / bm25_r) * 100.0
  }
}

///|
fn target_15pct_label(embedder : String, hybrid_r : Double, bm25_r : Double) -> String {
  if embedder != "api" {
    return "n_a"
  }
  let rel = if bm25_r == 0.0 {
    0.0
  } else {
    (hybrid_r - bm25_r) / bm25_r
  }
  if rel >= 0.15 {
    "met"
  } else {
    "missed"
  }
}

///|
fn mode_name(opts : CliOpts) -> String {
  if opts.live {
    "live"
  } else if opts.embedder == "api" {
    "api"
  } else {
    "offline"
  }
}

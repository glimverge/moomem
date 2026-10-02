// Shared helpers for the LoCoMo harness.

///|
fn[T] fail(msg : String) -> T {
  println("LOCOMO_FAIL: \{msg}")
  abort(msg)
}

///|
fn format_mrr(v : Double) -> String {
  let scaled = (v * 1000.0 + (if v >= 0.0 { 0.5 } else { -0.5 })).to_int()
  let sign = if scaled < 0 { "-" } else { "" }
  let absv = if scaled < 0 { -scaled } else { scaled }
  let whole = absv / 1000
  let frac = absv % 1000
  let f3 = if frac < 10 {
    "00\{frac}"
  } else if frac < 100 {
    "0\{frac}"
  } else {
    "\{frac}"
  }
  "\{sign}\{whole}.\{f3}"
}

///|
fn format_ratio(num : Int, den : Int) -> String {
  if den == 0 {
    "n/a"
  } else {
    format_mrr(num.to_double() / den.to_double())
  }
}

///|
fn format_pct(delta : Double) -> String {
  let scaled = (delta * 1000.0 + (if delta >= 0.0 { 0.5 } else { -0.5 })).to_int()
  let sign = if scaled >= 0 { "+" } else { "-" }
  let absv = if scaled >= 0 { scaled } else { -scaled }
  let whole = absv / 10
  let frac = absv % 10
  "\{sign}\{whole}.\{frac}%"
}

///|
fn parse_int_arg(raw : String, flag : String) -> Int {
  let v : Int = @string.parse_int(raw) catch {
    _ => fail("\{flag} expects integer, got \{raw}")
  }
  v
}

///|
struct CliOpts {
  fixture : String
  embedder : String // hashing | api
  live : Bool
  limit : Int // 0 = no limit (retrieval QA)
  extract_limit : Int // 0 = no limit (extraction gold cases); archive uses 20
  report : String // "" = no report file
  report_only_exit : Bool // write report then exit 0 even if gates fail
  help : Bool
}

///|
fn parse_args() -> CliOpts {
  let args = @env.args()
  let mut fixture = ""
  let mut embedder = "hashing"
  let live = false
  let mut limit = 0
  let mut extract_limit = 0
  let mut report = ""
  let mut report_only_exit = false
  let mut help = false
  let mut i = if args.length() > 0 { 1 } else { 0 }
  while i < args.length() {
    let a = args[i]
    if a == "--help" || a == "-h" {
      help = true
    } else if a == "--live" {
      fail(
        "--live is not in this harness; the host supplies Extractor and ConflictJudge",
      )
    } else if a == "--report-only-exit" {
      report_only_exit = true
    } else if a == "--fixture" {
      i = i + 1
      if i >= args.length() {
        fail("--fixture requires a path")
      }
      fixture = args[i]
    } else if a == "--embedder" {
      i = i + 1
      if i >= args.length() {
        fail("--embedder requires hashing")
      }
      embedder = args[i]
      if embedder == "api" {
        fail(
          "--embedder api is not in this harness; the host supplies Embedder",
        )
      }
      if embedder != "hashing" {
        fail("--embedder must be hashing, got \{embedder}")
      }
    } else if a == "--limit" {
      i = i + 1
      if i >= args.length() {
        fail("--limit requires an integer")
      }
      limit = parse_int_arg(args[i], "--limit")
    } else if a == "--extract-limit" {
      i = i + 1
      if i >= args.length() {
        fail("--extract-limit requires an integer")
      }
      extract_limit = parse_int_arg(args[i], "--extract-limit")
      if extract_limit < 0 {
        fail("--extract-limit must be >= 0")
      }
    } else if a == "--report" {
      i = i + 1
      if i >= args.length() {
        fail("--report requires a path")
      }
      report = args[i]
    } else {
      ()
    }
    i = i + 1
  }
  // Env override when flag omitted (archive / ops).
  if extract_limit == 0 {
    match @env.get_env_var("MOOMEM_LOCOMO_EXTRACT_LIMIT") {
      Some(raw) => {
        let t = raw.trim().to_owned()
        if t.length() > 0 {
          extract_limit = parse_int_arg(t, "MOOMEM_LOCOMO_EXTRACT_LIMIT")
          if extract_limit < 0 {
            fail("MOOMEM_LOCOMO_EXTRACT_LIMIT must be >= 0")
          }
        }
      }
      None => ()
    }
  }
  CliOpts::{
    fixture,
    embedder,
    live,
    limit,
    extract_limit,
    report,
    report_only_exit,
    help,
  }
}

///|
fn print_help() -> Unit {
  println("Usage: moon run benchmark --target native -- [options]")
  println("  --fixture <path>     locomo_subset.json path")
  println("  --embedder hashing   offline hashing embedder (default)")
  println("  --limit <n>          score at most n retrieval QA items")
  println(
    "  --extract-limit <n>  score at most n extraction gold cases (0=all 100)",
  )
  println("                       (or env MOOMEM_LOCOMO_EXTRACT_LIMIT)")
  println("  --report <path>      write machine-readable JSON for this mode")
  println("                       (or env MOOMEM_LOCOMO_REPORT)")
  println("  --report-only-exit   after writing report, exit 0 even if gates fail")
  println("                       (archive use; push offline keeps hard fail)")
  println("  --help")
}

///|
fn resolve_fixture_path(opts : CliOpts) -> String {
  if opts.fixture.length() > 0 {
    return opts.fixture
  }
  match @env.get_env_var("MOOMEM_LOCOMO_FIXTURE") {
    Some(p) => {
      let v = p.trim().to_owned()
      if v.length() > 0 {
        return v
      }
    }
    None => ()
  }
  "benchmark/data/locomo_subset.json"
}

///|
fn read_text_file(path : String) -> String {
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "(unknown)"
  }
  let abs = if path.has_prefix("/") {
    path
  } else {
    "\{cwd}/\{path}"
  }
  @fs.read_file_to_string(abs) catch {
    e => {
      let detail = match e {
        @fs.IOError(msg) => msg
      }
      fail("cannot read \{abs} (cwd=\{cwd}): \{detail}")
    }
  }
}

///|
/// Empty conflict judge: retrieval-only isolation (no supersede pollution).
struct NoConflictJudge {}

///|
pub impl @src.ConflictJudge for NoConflictJudge with fn judge(_, _, _) {
  Ok([])
}

///|
pub extend NoConflictJudge with @src.ConflictJudge::{judge}

///|
/// Null embedder: forces keyword-only BM25 baseline.
struct NullEmbedder {}

///|
pub impl @src.Embedder for NullEmbedder with fn embed(_, _) {
  Err(@src.MoomemError::EmbeddingFailure("baseline:keyword-only"))
}

///|
pub impl @src.Embedder for NullEmbedder with fn dim(_) {
  @src.DEFAULT_DIM
}

///|
pub extend NullEmbedder with @src.Embedder::{embed, dim}

// Shared helpers for the LoCoMo harness.

///|
fn[T] fail(msg : String) -> T {
  println("LOCOMO_FAIL: \{msg}")
  abort(msg)
}

///|
fn require_env(key : String) -> String {
  match @env.get_env_var(key) {
    Some(raw) => {
      let v = raw.trim().to_owned()
      if v.is_empty() {
        fail("env \{key} is set but empty")
      }
      v
    }
    None => fail("missing required env \{key}")
  }
}

///|
fn normalize_base_url(raw : String) -> String {
  let mut u = raw.trim().to_owned()
  while u.has_suffix("/") {
    match u.strip_suffix("/") {
      Some(v) => u = v.to_owned()
      None => break
    }
  }
  match u.strip_suffix("/v1") {
    Some(v) => v.to_owned()
    None => u
  }
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
  limit : Int // 0 = no limit
  report : String // "" = no report file
  report_only_exit : Bool // write report then exit 0 even if gates fail
  help : Bool
}

///|
fn parse_args() -> CliOpts {
  let args = @env.args()
  let mut fixture = ""
  let mut embedder = "hashing"
  let mut live = false
  let mut limit = 0
  let mut report = ""
  let mut report_only_exit = false
  let mut help = false
  let mut i = if args.length() > 0 { 1 } else { 0 }
  while i < args.length() {
    let a = args[i]
    if a == "--help" || a == "-h" {
      help = true
    } else if a == "--live" {
      live = true
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
        fail("--embedder requires hashing|api")
      }
      embedder = args[i]
      if embedder != "hashing" && embedder != "api" {
        fail("--embedder must be hashing|api, got \{embedder}")
      }
    } else if a == "--limit" {
      i = i + 1
      if i >= args.length() {
        fail("--limit requires an integer")
      }
      limit = parse_int_arg(args[i], "--limit")
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
  CliOpts::{ fixture, embedder, live, limit, report, report_only_exit, help, }
}

///|
fn print_help() -> Unit {
  println("Usage: moon run ci/eval/locomo --target native -- [options]")
  println("  --fixture <path>     locomo_subset.json path")
  println("  --embedder hashing|api   default hashing (offline)")
  println("  --live               run extraction precision with DeepSeek")
  println("  --limit <n>          score at most n retrieval QA items")
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
  "ci/eval/locomo/data/locomo_subset.json"
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

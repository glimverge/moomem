// moomem CLI —— 无 API 也能完整走通场景 A（PRD FR-07）。
//
// 子命令：
//   add    --db <dir> --user <id> --text <内容>              写入记忆
//   recall --db <dir> --user <id> --query <查询> [--top-k N] 召回记忆
//   list   --db <dir> --user <id> [--all]                    列出条目（--all 含已删除/被覆盖）
//   stats  --db <dir>                                        运行统计
//   export --db <dir>                                        全量 JSONL 导出到 stdout
//   import --db <dir> --file <jsonl-path>                    从 JSONL 文件导入
//   help                                                     帮助
//
// 退出码：0 成功；用法错误 / 库错误打印 error 前缀信息。

/// 命令行选项解析结果
struct CliOptions {
  db : String
  user : String
  text : String
  query : String
  top_k : Int
  show_all : Bool
  file : String?
}

fn default_options() -> CliOptions {
  CliOptions::{
    db : "./moomem-data",
    user : "default",
    text : "",
    query : "",
    top_k : 5,
    show_all : false,
    file : None,
  }
}

/// 从参数列表解析 --key value 形式的选项；--all 为布尔开关，不消费值
fn parse_options(
  args : Array[String],
  opts : CliOptions
) -> Result[CliOptions, String] {
  if args.length() == 0 {
    return Ok(opts)
  }
  let key = args[0]
  // 布尔开关 --all：可独立出现在任意位置（含参数末尾），不消费后续 token
  if key == "--all" {
    let rest : Array[String] = []
    for i = 1; i < args.length(); i = i + 1 {
      rest.push(args[i])
    }
    return parse_options(rest, CliOptions::{ ..opts, show_all : true })
  }
  if args.length() < 2 {
    return Err("missing value for option '\{key}'")
  }
  let value = args[1]
  let rest : Array[String] = []
  for i = 2; i < args.length(); i = i + 1 {
    rest.push(args[i])
  }
  match key {
    "--db" => parse_options(rest, CliOptions::{ ..opts, db : value })
    "--user" => parse_options(rest, CliOptions::{ ..opts, user : value })
    "--text" => parse_options(rest, CliOptions::{ ..opts, text : value })
    "--query" => parse_options(rest, CliOptions::{ ..opts, query : value })
    "--file" => parse_options(rest, CliOptions::{ ..opts, file : Some(value) })
    "--top-k" => {
      let parsed : Result[Int, String] = try {
        Ok(@string.parse_int(value))
      } catch {
        _ => Err("--top-k expects an integer, got '\{value}'")
      }
      match parsed {
        Ok(n) => parse_options(rest, CliOptions::{ ..opts, top_k : n })
        Err(msg) => Err(msg)
      }
    }
    _ => Err("unknown option '\{key}'")
  }
}

fn print_usage() -> Unit {
  println("moomem \{@src.MOOMEM_VERSION} - embedded agent memory layer CLI")
  println("")
  println("Usage:")
  println("  moomem add    --db <dir> --user <id> --text <content>")
  println("  moomem recall --db <dir> --user <id> --query <query> [--top-k N]")
  println("  moomem list   --db <dir> --user <id> [--all]")
  println("  moomem stats  --db <dir>")
  println("  moomem export --db <dir>")
  println("  moomem import --db <dir> --file <jsonl-path>")
  println("")
  println("Options:")
  println("  --db <dir>     memory store directory (default: ./moomem-data)")
  println("  --user <id>    user namespace (charset [A-Za-z0-9_-.], max 64)")
  println("  --text <s>     text to remember (add)")
  println("  --query <s>    retrieval query (recall)")
  println("  --top-k <n>    result count for recall (default 5, max 50)")
  println("  --all          list all statuses incl. deleted/superseded")
  println("  --file <path>  JSONL file to import")
}

fn die(msg : String) -> Unit {
  println("error: \{msg}")
  println("run 'moomem help' for usage")
}

fn is_command(s : String) -> Bool {
  s == "add" ||
  s == "recall" ||
  s == "list" ||
  s == "stats" ||
  s == "export" ||
  s == "import" ||
  s == "help" ||
  s == "--help" ||
  s == "-h"
}

/// 读取文本文件，错误转为可读消息（CLI 的 fs 调用点，见架构文档第 6 章）
fn read_text_file(path : String) -> Result[String, String] {
  try {
    Ok(@fs.read_file_to_string(path))
  } catch {
    e => {
      let detail = match e {
        @fs.IOError(msg) => msg
      }
      Err("read '\{path}' failed: \{detail}")
    }
  }
}

fn main {
  let argv = @env.args()
  // 跳过程序名（native 下 args 首元素为可执行文件路径；js 下可能没有）
  let mut start = 0
  if argv.length() > 0 && !is_command(argv[0]) {
    start = 1
  }
  if argv.length() <= start {
    print_usage()
    return
  }
  let cmd = argv[start]
  let rest : Array[String] = []
  for i = start + 1; i < argv.length(); i = i + 1 {
    rest.push(argv[i])
  }
  match cmd {
    "help" | "--help" | "-h" => print_usage()
    "add" => {
      match parse_options(rest, default_options()) {
        Err(msg) => die(msg)
        Ok(opts) =>
          match @src.MemoryStore::open(opts.db) {
            Err(e) => die(e.message())
            Ok(store) =>
              match store.add(opts.user, opts.text) {
                Err(e) => die(e.message())
                Ok(summary) => {
                  let extracted = summary.extracted
                  let inserted = summary.inserted
                  let duplicates = summary.duplicates
                  let superseded = summary.superseded
                  let degraded = summary.degraded
                  println(
                    "added: extracted=\{extracted} inserted=\{inserted} duplicates=\{duplicates} superseded=\{superseded} degraded=\{degraded}",
                  )
                  for note in summary.notes {
                    println("  note: \{note}")
                  }
                  ignore(store.close())
                }
              }
          }
      }
    }
    "recall" => {
      match parse_options(rest, default_options()) {
        Err(msg) => die(msg)
        Ok(opts) =>
          match @src.MemoryStore::open(opts.db) {
            Err(e) => die(e.message())
            Ok(store) =>
              match store.recall(opts.user, opts.query, top_k=opts.top_k) {
                Err(e) => die(e.message())
                Ok(entries) => {
                  if entries.length() == 0 {
                    println("(no memory found)")
                  }
                  for e in entries {
                    let kind = e.kind.to_string()
                    println("[\{kind}] \{e.content}")
                    println("  id: \{e.id} | created_at: \{e.created_at}")
                  }
                  ignore(store.close())
                }
              }
          }
      }
    }
    "list" => {
      match parse_options(rest, default_options()) {
        Err(msg) => die(msg)
        Ok(opts) =>
          match @src.MemoryStore::open(opts.db) {
            Err(e) => die(e.message())
            Ok(store) =>
              match store.list_entries(opts.user) {
                Err(e) => die(e.message())
                Ok(entries) => {
                  for e in entries {
                    if opts.show_all || e.is_recallable() {
                      let status = e.status.to_string()
                      let id = e.id
                      let seq = e.seq
                      println("[\{status}] \{e.content} (id: \{id}, seq: \{seq})")
                    }
                  }
                  ignore(store.close())
                }
              }
          }
      }
    }
    "stats" => {
      match parse_options(rest, default_options()) {
        Err(msg) => die(msg)
        Ok(opts) =>
          match @src.MemoryStore::open(opts.db) {
            Err(e) => die(e.message())
            Ok(store) =>
              match store.stats() {
                Err(e) => die(e.message())
                Ok(st) => {
                  println("total:         \{st.total}")
                  println("active:        \{st.active}")
                  println("superseded:    \{st.superseded}")
                  println("deleted:       \{st.deleted}")
                  println("unstructured:  \{st.unstructured}")
                  println("bytes_on_disk: \{st.bytes_on_disk}")
                  let last_write = match st.last_write_at {
                    Some(t) => "\{t}"
                    None => "(never)"
                  }
                  println("last_write_at: \{last_write}")
                  let truncated = st.truncated_recovered
                  println("truncated_recovered: \{truncated}")
                  println("extractor_mode: \{st.extractor_mode}")
                  ignore(store.close())
                }
              }
          }
      }
    }
    "export" => {
      match parse_options(rest, default_options()) {
        Err(msg) => die(msg)
        Ok(opts) =>
          match @src.MemoryStore::open(opts.db) {
            Err(e) => die(e.message())
            Ok(store) =>
              match store.export_jsonl() {
                Err(e) => die(e.message())
                Ok(jsonl) => {
                  println(jsonl)
                  ignore(store.close())
                }
              }
          }
      }
    }
    "import" => {
      match parse_options(rest, default_options()) {
        Err(msg) => die(msg)
        Ok(opts) =>
          match opts.file {
            None => die("import requires --file <jsonl-path>")
            Some(path) =>
              match read_text_file(path) {
                Err(msg) => die(msg)
                Ok(content) =>
                  match @src.MemoryStore::open(opts.db) {
                    Err(e) => die(e.message())
                    Ok(store) =>
                      match store.import_jsonl(content) {
                        Err(e) => die(e.message())
                        Ok((imported, skipped)) => {
                          println("imported: \{imported}, skipped: \{skipped}")
                          ignore(store.close())
                        }
                      }
                  }
              }
          }
      }
    }
    _ => die("unknown command '\{cmd}'")
  }
}

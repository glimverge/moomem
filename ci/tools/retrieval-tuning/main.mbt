// Offline retrieval / conflict tuning harness (W3-B + adaptive fusion).
// Zero network, zero secrets. Native main package.
//
// 1) Default-parameter gate: recall@5=12/12, supersede=3/3, cross_leak=0
// 2) Grid scan rrf_k × conflict_candidates × supersede_threshold × coexist_band
// 3) Adaptive fusion: lexical vs paraphrase cases; equal_rrf vs adaptive compare
// 4) Small grid over adaptive hyperparams (independent set only — never LoCoMo)
//
// Run: moon run ci/tools/retrieval-tuning --target native

///|
fn fail(msg : String) -> Unit {
  println("TUNING_FAIL: \{msg}")
  abort(msg)
}

///|
struct QueryCase {
  user : String
  query : String
  /// 期望 top-1（及 top-5 命中判定）内容关键词
  expect_key : String
}

///|
struct ConflictPair {
  user : String
  old_text : String
  new_text : String
}

///|
struct Metrics {
  mut recall_hit : Int
  recall_total : Int
  mut mrr_sum : Double
  mut supersede_ok : Int
  supersede_total : Int
  mut cross_leak : Int
}

///|
fn metrics_empty(recall_total : Int, supersede_total : Int) -> Metrics {
  Metrics::{
    recall_hit: 0,
    recall_total,
    mrr_sum: 0.0,
    supersede_ok: 0,
    supersede_total,
    cross_leak: 0,
  }
}

///|
fn format_mrr(v : Double) -> String {
  // 三位小数，便于 Markdown 表对齐
  let scaled = (v * 1000.0 + 0.5).to_int()
  let whole = scaled / 1000
  let frac = scaled % 1000
  let f3 = if frac < 10 {
    "00\{frac}"
  } else if frac < 100 {
    "0\{frac}"
  } else {
    "\{frac}"
  }
  "\{whole}.\{f3}"
}

///|
fn alice_facts() -> Array[String] {
  [
    // 冲突对旧值（随后被 supersede）
    "严重过敏原清单包含花生制品项",
    "宠物是一只橘色的猫叫豆豆",
    "睡眠习惯晚上十一点准时睡觉",
    // 稳定事实（检索语料）
    "我住在北京市海淀区中关村软件园",
    "饮食偏好清淡粤菜少油少盐",
    "工号是 JD-ALICE-2048 在北京研发中心",
    "养了一缸热带鱼叫霓虹灯",
    "每周三晚上去朝阳大悦城看电影",
    "常喝无糖美式咖啡加一份燕麦奶",
    "身份证尾号 8899 办过北京社保卡",
    "出差首选东方航空经济舱",
    "书柜里有一套三体全三册签注本",
    // 冲突对更新值
    "严重过敏原清单包含海鲜制品项",
    "宠物是一只橘色的狗叫豆豆",
    "睡眠习惯晚上十二点准时睡觉",
  ]
}

///|
fn bob_facts() -> Array[String] {
  [
    "Bob 住在上海市浦东新区陆家嘴环路",
    "Bob 对乳糖不耐受只喝燕麦拿铁",
    "Bob 养了一只柯基叫土豆泥",
    "Bob 工号是 JD-BOB-4096 在上海产品部",
    "Bob 每周五晚上去静安嘉里中心健身",
    "Bob 偏好麻辣火锅加毛肚黄喉",
    "Bob 通勤骑共享单车过陆家嘴隧道",
    "Bob 护照号尾号 3344 办过上海居住证",
    "Bob 出差首选南方航空商务舱",
    "Bob 书柜里有一套沙丘全系列精装本",
    "Bob 睡眠习惯早上六点半起床跑步",
    "Bob 紧急联系人是王五手机 13900002222",
  ]
}

///|
fn conflict_pairs() -> Array[ConflictPair] {
  [
    ConflictPair::{
      user: "alice",
      old_text: "严重过敏原清单包含花生制品项",
      new_text: "严重过敏原清单包含海鲜制品项",
    },
    ConflictPair::{
      user: "alice",
      old_text: "宠物是一只橘色的猫叫豆豆",
      new_text: "宠物是一只橘色的狗叫豆豆",
    },
    ConflictPair::{
      user: "alice",
      old_text: "睡眠习惯晚上十一点准时睡觉",
      new_text: "睡眠习惯晚上十二点准时睡觉",
    },
  ]
}

///|
fn query_cases() -> Array[QueryCase] {
  [
    QueryCase::{
      user: "alice", query: "海鲜制品过敏原清单", expect_key: "海鲜制品",
    },
    QueryCase::{ user: "alice", query: "橘色的狗叫豆豆", expect_key: "狗叫豆豆", },
    QueryCase::{
      user: "alice", query: "十二点准时睡觉", expect_key: "十二点",
    },
    QueryCase::{
      user: "alice", query: "海淀区中关村软件园", expect_key: "海淀区",
    },
    QueryCase::{ user: "alice", query: "清淡粤菜少油", expect_key: "粤菜", },
    QueryCase::{
      user: "alice", query: "JD-ALICE-2048", expect_key: "JD-ALICE-2048",
    },
    QueryCase::{ user: "alice", query: "热带鱼霓虹灯", expect_key: "霓虹灯", },
    QueryCase::{
      user: "alice", query: "朝阳大悦城电影", expect_key: "大悦城",
    },
    QueryCase::{ user: "alice", query: "无糖美式燕麦奶", expect_key: "燕麦奶", },
    QueryCase::{
      user: "alice", query: "北京社保卡8899", expect_key: "8899",
    },
    QueryCase::{
      user: "alice", query: "东方航空经济舱", expect_key: "东方航空",
    },
    QueryCase::{ user: "alice", query: "三体全三册", expect_key: "三体", },
  ]
}

///|
/// 词法向：共享表面词，BM25 应强命中。
fn lexical_query_cases() -> Array[QueryCase] {
  [
    QueryCase::{
      user: "alice", query: "海淀区中关村软件园", expect_key: "海淀区",
    },
    QueryCase::{
      user: "alice", query: "JD-ALICE-2048", expect_key: "JD-ALICE-2048",
    },
    QueryCase::{
      user: "alice", query: "朝阳大悦城电影", expect_key: "大悦城",
    },
    QueryCase::{
      user: "alice", query: "北京社保卡8899", expect_key: "8899",
    },
    QueryCase::{
      user: "alice", query: "东方航空经济舱", expect_key: "东方航空",
    },
    QueryCase::{ user: "alice", query: "三体全三册", expect_key: "三体", },
  ]
}

///|
/// 释义向：尽量少共享表面词，依赖语义通道。
fn paraphrase_query_cases() -> Array[QueryCase] {
  [
    QueryCase::{
      user: "alice",
      query: "residence near Zhongguancun software park",
      expect_key: "海淀区",
    },
    QueryCase::{
      user: "alice",
      query: "employee badge number for Beijing R&D",
      expect_key: "JD-ALICE-2048",
    },
    QueryCase::{
      user: "alice",
      query: "Wednesday cinema at Chaoyang mall",
      expect_key: "大悦城",
    },
    QueryCase::{
      user: "alice",
      query: "social security card ending 8899",
      expect_key: "8899",
    },
    QueryCase::{
      user: "alice",
      query: "preferred China Eastern economy flights",
      expect_key: "东方航空",
    },
    QueryCase::{
      user: "alice",
      query: "signed Three-Body Problem trilogy",
      expect_key: "三体",
    },
  ]
}

///|
fn open_store(
  rrf_k : Int,
  conflict_candidates : Int,
  supersede_threshold : Double,
  coexist_band : Double,
  fusion_policy : @src.FusionPolicy,
  lexical_floor : Double,
  lexical_gap : Double,
  vec_weight_when_lexical : Double,
  vec_weight_when_semantic : Double,
) -> @src.MemoryStore {
  let backend : &@src.PersistenceBackend = @src.MemoryBackend::new()
  let cfg = @src.Config::{
    ..@src.Config::default(),
    persistence: Some(backend),
    rrf_k,
    conflict_candidates,
    supersede_threshold,
    coexist_band,
    fusion_policy,
    lexical_floor,
    lexical_gap,
    vec_weight_when_lexical,
    vec_weight_when_semantic,
  }
  match @src.MemoryStore::open("memory://tuning", config=cfg) {
    Ok(s) => s
    Err(e) => {
      fail("open failed: \{e.message()}")
      abort("unreachable")
    }
  }
}

///|
fn add_all(store : @src.MemoryStore, user : String, texts : Array[String]) -> Unit {
  for t in texts {
    match store.add(user, t) {
      Ok(_) => ()
      Err(e) => fail("add(\{user}, \{t}): \{e.message()}")
    }
  }
}

///|
fn entry_mentions(e : @src.MemoryEntry, key : String) -> Bool {
  e.content.contains(key)
}

///|
fn rank_of_key(hits : Array[@src.MemoryEntry], key : String) -> Int? {
  let mut i = 0
  while i < hits.length() {
    if entry_mentions(hits[i], key) {
      return Some(i + 1)
    }
    i = i + 1
  }
  None
}

///|
fn evaluate_supersede(store : @src.MemoryStore, pairs : Array[ConflictPair]) -> Int {
  let mut ok = 0
  for p in pairs {
    let entries = match store.list_entries(p.user) {
      Ok(es) => es
      Err(e) => {
        fail("list_entries(\{p.user}): \{e.message()}")
        []
      }
    }
    let mut old_superseded = false
    let mut new_active = false
    for e in entries {
      if e.content == p.old_text {
        if e.status == @src.EntryStatus::Superseded {
          old_superseded = true
        }
      }
      if e.content == p.new_text {
        if e.is_recallable() {
          new_active = true
        }
      }
    }
    if old_superseded && new_active {
      ok = ok + 1
    }
  }
  ok
}

///|
fn evaluate_cross_leak(store : @src.MemoryStore) -> Int {
  // alice 查询不应命中 Bob 专属内容；bob 查询不应命中 alice 专属内容
  let mut leaks = 0
  let alice_hits = match store.recall("alice", "陆家嘴环路柯基土豆泥", top_k=5) {
    Ok(h) => h
    Err(e) => {
      fail("cross recall alice: \{e.message()}")
      []
    }
  }
  for e in alice_hits {
    if e.content.contains("Bob") || e.content.contains("陆家嘴") ||
      e.content.contains("土豆泥") {
      leaks = leaks + 1
    }
  }
  let bob_hits = match store.recall("bob", "海淀区中关村霓虹灯", top_k=5) {
    Ok(h) => h
    Err(e) => {
      fail("cross recall bob: \{e.message()}")
      []
    }
  }
  for e in bob_hits {
    if e.content.contains("海淀") || e.content.contains("霓虹灯") ||
      e.content.contains("粤菜") {
      leaks = leaks + 1
    }
  }
  leaks
}

///|
fn score_queries(store : @src.MemoryStore, queries : Array[QueryCase], m : Metrics) -> Unit {
  for q in queries {
    let hits = match store.recall(q.user, q.query, top_k=5) {
      Ok(h) => h
      Err(e) => {
        fail("recall(\{q.user}, \{q.query}): \{e.message()}")
        []
      }
    }
    match rank_of_key(hits, q.expect_key) {
      Some(rank) => {
        m.recall_hit = m.recall_hit + 1
        m.mrr_sum = m.mrr_sum + 1.0 / rank.to_double()
      }
      None => ()
    }
  }
}

///|
fn run_once(
  rrf_k : Int,
  conflict_candidates : Int,
  supersede_threshold : Double,
  coexist_band : Double,
) -> Metrics {
  let queries = query_cases()
  let pairs = conflict_pairs()
  let m = metrics_empty(queries.length(), pairs.length())
  let store = open_store(
    rrf_k,
    conflict_candidates,
    supersede_threshold,
    coexist_band,
    @src.FusionPolicy::AdaptiveLexical,
    @src.DEFAULT_LEXICAL_FLOOR,
    @src.DEFAULT_LEXICAL_GAP,
    @src.DEFAULT_VEC_WEIGHT_LEXICAL,
    @src.DEFAULT_VEC_WEIGHT_SEMANTIC,
  )
  add_all(store, "alice", alice_facts())
  add_all(store, "bob", bob_facts())
  m.supersede_ok = evaluate_supersede(store, pairs)
  m.cross_leak = evaluate_cross_leak(store)
  score_queries(store, queries, m)
  ignore(store.close())
  m
}

///|
fn run_fusion_once(
  policy : @src.FusionPolicy,
  floor : Double,
  gap : Double,
  w_lex : Double,
  w_sem : Double,
  queries : Array[QueryCase],
) -> Metrics {
  let m = metrics_empty(queries.length(), 0)
  let store = open_store(
    @src.DEFAULT_RRF_K,
    @src.CONFLICT_CANDIDATES,
    @src.DEFAULT_SUPERSEDE_THRESHOLD,
    @src.COEXIST_BAND,
    policy,
    floor,
    gap,
    w_lex,
    w_sem,
  )
  add_all(store, "alice", alice_facts())
  add_all(store, "bob", bob_facts())
  m.cross_leak = evaluate_cross_leak(store)
  score_queries(store, queries, m)
  ignore(store.close())
  m
}

///|
fn mrr_mean(m : Metrics) -> Double {
  if m.recall_total == 0 {
    0.0
  } else {
    m.mrr_sum / m.recall_total.to_double()
  }
}

///|
fn better_than(a : Metrics, b : Metrics) -> Bool {
  // 主排序：recall_hit；次：mrr；再次：supersede_ok
  if a.recall_hit != b.recall_hit {
    return a.recall_hit > b.recall_hit
  }
  let am = mrr_mean(a)
  let bm = mrr_mean(b)
  if am != bm {
    return am > bm
  }
  a.supersede_ok > b.supersede_ok
}

///|
fn print_metrics_line(
  rrf_k : Int,
  cc : Int,
  thr : Double,
  band : Double,
  m : Metrics,
) -> Unit {
  let thr_s = format_mrr(thr)
  let band_s = format_mrr(band)
  let mrr_s = format_mrr(mrr_mean(m))
  println(
    "| \{rrf_k} | \{cc} | \{thr_s} | \{band_s} | \{m.recall_hit}/\{m.recall_total} | \{mrr_s} | \{m.supersede_ok}/\{m.supersede_total} |",
  )
}

///|
fn fusion_label(p : @src.FusionPolicy) -> String {
  match p {
    EqualRrf => "equal_rrf"
    AdaptiveLexical => "adaptive"
  }
}

///|
fn print_fusion_line(
  label : String,
  subset : String,
  m : Metrics,
) -> Unit {
  let mrr_s = format_mrr(mrr_mean(m))
  println(
    "| \{label} | \{subset} | \{m.recall_hit}/\{m.recall_total} | \{mrr_s} |",
  )
}

///|
fn main {
  println("=== moomem offline tuning harness ===")
  let def_rrf = @src.DEFAULT_RRF_K
  let def_cc = @src.CONFLICT_CANDIDATES
  let def_thr = @src.DEFAULT_SUPERSEDE_THRESHOLD
  let def_band = @src.COEXIST_BAND
  let gate = run_once(def_rrf, def_cc, def_thr, def_band)
  let gate_mrr = format_mrr(mrr_mean(gate))
  let gate_ok = gate.recall_hit == gate.recall_total &&
    gate.supersede_ok == gate.supersede_total &&
    gate.cross_leak == 0
  let gate_tag = if gate_ok { "PASS" } else { "FAIL" }
  println(
    "default gate: recall@5=\{gate.recall_hit}/\{gate.recall_total} mrr@5=\{gate_mrr} supersede=\{gate.supersede_ok}/\{gate.supersede_total} cross_leak=\{gate.cross_leak}  [\{gate_tag}]",
  )
  if !gate_ok {
    fail(
      "default params (\{def_rrf},\{def_cc},\{def_thr},\{def_band}) failed gate",
    )
  }

  let rrf_grid = [10, 20, 40, 60, 100]
  let cc_grid = [4, 8, 16]
  let thr_grid = [0.75, 0.82, 0.90]
  let band_grid = [0.10, 0.15, 0.20]

  println("")
  println(
    "| rrf_k | cc | thr | band | recall@5 | mrr@5 | supersede |",
  )
  println("|------:|---:|----:|-----:|---------:|------:|----------:|")

  let mut best_m = gate
  let mut best_rrf = def_rrf
  let mut best_cc = def_cc
  let mut best_thr = def_thr
  let mut best_band = def_band

  for rrf_k in rrf_grid {
    for cc in cc_grid {
      for thr in thr_grid {
        for band in band_grid {
          let m = if rrf_k == def_rrf &&
            cc == def_cc &&
            thr == def_thr &&
            band == def_band {
            gate
          } else {
            run_once(rrf_k, cc, thr, band)
          }
          if m.cross_leak != 0 {
            fail(
              "cross_leak=\{m.cross_leak} at rrf_k=\{rrf_k} cc=\{cc} thr=\{thr} band=\{band}",
            )
          }
          print_metrics_line(rrf_k, cc, thr, band, m)
          if better_than(m, best_m) {
            best_m = m
            best_rrf = rrf_k
            best_cc = cc
            best_thr = thr
            best_band = band
          }
        }
      }
    }
  }

  let best_mrr = format_mrr(mrr_mean(best_m))
  println("")
  println(
    "best combo: rrf_k=\{best_rrf} cc=\{best_cc} thr=\{best_thr} band=\{best_band} (ties broken by mrr@5; mrr=\{best_mrr} recall=\{best_m.recall_hit}/\{best_m.recall_total} supersede=\{best_m.supersede_ok}/\{best_m.supersede_total})",
  )

  // --- Adaptive fusion compare (independent set; no LoCoMo) ---
  println("")
  println("=== adaptive fusion compare (independent set) ===")
  let floor0 = @src.DEFAULT_LEXICAL_FLOOR
  let gap0 = @src.DEFAULT_LEXICAL_GAP
  let wlex0 = @src.DEFAULT_VEC_WEIGHT_LEXICAL
  let wsem0 = @src.DEFAULT_VEC_WEIGHT_SEMANTIC
  let lex_cases = lexical_query_cases()
  let para_cases = paraphrase_query_cases()
  let all_fusion = query_cases()
  println("| policy | subset | recall@5 | mrr@5 |")
  println("|--------|--------|---------:|------:|")
  let eq_all = run_fusion_once(
    @src.FusionPolicy::EqualRrf, floor0, gap0, wlex0, wsem0, all_fusion,
  )
  let ad_all = run_fusion_once(
    @src.FusionPolicy::AdaptiveLexical, floor0, gap0, wlex0, wsem0, all_fusion,
  )
  let eq_lex = run_fusion_once(
    @src.FusionPolicy::EqualRrf, floor0, gap0, wlex0, wsem0, lex_cases,
  )
  let ad_lex = run_fusion_once(
    @src.FusionPolicy::AdaptiveLexical, floor0, gap0, wlex0, wsem0, lex_cases,
  )
  let eq_para = run_fusion_once(
    @src.FusionPolicy::EqualRrf, floor0, gap0, wlex0, wsem0, para_cases,
  )
  let ad_para = run_fusion_once(
    @src.FusionPolicy::AdaptiveLexical, floor0, gap0, wlex0, wsem0, para_cases,
  )
  print_fusion_line("equal_rrf", "all", eq_all)
  print_fusion_line("adaptive", "all", ad_all)
  print_fusion_line("equal_rrf", "lexical", eq_lex)
  print_fusion_line("adaptive", "lexical", ad_lex)
  print_fusion_line("equal_rrf", "paraphrase", eq_para)
  print_fusion_line("adaptive", "paraphrase", ad_para)

  // Small adaptive hyperparam grid
  println("")
  println("=== adaptive hyperparam grid (independent set) ===")
  let floors = [0.8, 1.5, 2.5]
  let gaps = [1.1, 1.2, 1.5]
  let w_lexs = [0.05, 0.15, 0.25]
  let w_sems = [0.35, 0.45, 0.55]
  println("| floor | gap | w_lex | w_sem | all@5 | lex@5 | para@5 | mrr_all |")
  println("|------:|----:|------:|------:|------:|------:|-------:|--------:|")
  let mut sug_floor = floor0
  let mut sug_gap = gap0
  let mut sug_wlex = wlex0
  let mut sug_wsem = wsem0
  let mut sug_score = ad_all.recall_hit * 1000 +
    ad_lex.recall_hit * 100 +
    ad_para.recall_hit * 10
  let mut sug_mrr = mrr_mean(ad_all)
  for floor in floors {
    for gap in gaps {
      for w_lex in w_lexs {
        for w_sem in w_sems {
          let m_all = run_fusion_once(
            @src.FusionPolicy::AdaptiveLexical, floor, gap, w_lex, w_sem, all_fusion,
          )
          let m_lex = run_fusion_once(
            @src.FusionPolicy::AdaptiveLexical, floor, gap, w_lex, w_sem, lex_cases,
          )
          let m_para = run_fusion_once(
            @src.FusionPolicy::AdaptiveLexical, floor, gap, w_lex, w_sem, para_cases,
          )
          if m_all.cross_leak != 0 {
            fail("cross_leak in adaptive grid")
          }
          let mrr_s = format_mrr(mrr_mean(m_all))
          println(
            "| \{format_mrr(floor)} | \{format_mrr(gap)} | \{format_mrr(w_lex)} | \{format_mrr(w_sem)} | \{m_all.recall_hit}/\{m_all.recall_total} | \{m_lex.recall_hit}/\{m_lex.recall_total} | \{m_para.recall_hit}/\{m_para.recall_total} | \{mrr_s} |",
          )
          // Prefer: all recall, then lexical, then paraphrase, then mrr
          let score = m_all.recall_hit * 1000 +
            m_lex.recall_hit * 100 +
            m_para.recall_hit * 10
          let mm = mrr_mean(m_all)
          if score > sug_score || (score == sug_score && mm > sug_mrr) {
            sug_score = score
            sug_mrr = mm
            sug_floor = floor
            sug_gap = gap
            sug_wlex = w_lex
            sug_wsem = w_sem
          }
        }
      }
    }
  }
  println("")
  println(
    "suggested adaptive defaults: floor=\{format_mrr(sug_floor)} gap=\{format_mrr(sug_gap)} w_lex=\{format_mrr(sug_wlex)} w_sem=\{format_mrr(sug_wsem)} (compare to constants DEFAULT_LEXICAL_FLOOR=\{format_mrr(floor0)} DEFAULT_LEXICAL_GAP=\{format_mrr(gap0)} DEFAULT_VEC_WEIGHT_LEXICAL=\{format_mrr(wlex0)} DEFAULT_VEC_WEIGHT_SEMANTIC=\{format_mrr(wsem0)})",
  )
  println(
    "fusion note: \{fusion_label(@src.FusionPolicy::AdaptiveLexical)} is Config default; EqualRrf remains rollback.",
  )
  println("TUNING_PASS")
}

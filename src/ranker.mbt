// RRF 融合器（Reciprocal Rank Fusion）：将两路召回的 id 列表融合重排。
// score(id) = Σ_lists 1 / (k + rank)，rank 为该 id 在对应列表中的 1 基名次。

///|
/// RRF 融合：lists 为各路召回的 id 有序列表（已按相关性降序）；
/// k 为平滑常数（缺省 60），top_k 为截断长度。
/// 排序确定性：融合分降序，相同分按 id 升序。
pub fn rrf(lists : Array[Array[String]], k : Int, top_k : Int) -> Array[String] {
  if k <= 0 {
    return []
  }
  let scores : Map[String, Double] = Map([])
  for list in lists {
    for i = 0; i < list.length(); i = i + 1 {
      let id = list[i]
      let rank = i + 1
      let contribution = 1.0 / (k.to_double() + rank.to_double())
      let cur = match scores.get(id) {
        Some(v) => v
        None => 0.0
      }
      scores.set(id, cur + contribution)
    }
  }
  let ranked : Array[(String, Double)] = []
  for kv in scores.iter() {
    ranked.push(kv)
  }
  ranked.sort_by((a, b) => {
    if a.1 > b.1 {
      -1
    } else if a.1 < b.1 {
      1
    } else if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  let out : Array[String] = []
  let limit = if top_k < ranked.length() { top_k } else { ranked.length() }
  for i = 0; i < limit; i = i + 1 {
    out.push(ranked[i].0)
  }
  out
}

// 注入点三：ConflictJudge（PRD 13.2 冲突判定契约）。
// 缺省实现 SimilarityJudge：嵌入余弦 + 关键词 Jaccard 的确定性规则判定。
// 生产环境注入 LLM 版 judge（replace/merge/ignore + 判定依据写入 metadata）。

/// 冲突裁决：Replace 触发 supersede；Coexist 并存并标记；Ignore 无裁决。
pub(all) enum ConflictDecision {
  Replace
  Coexist
  Ignore
} derive(Eq)

/// 手写 Show（原 derive(Show) 输出格式保持不变：构造器名）。
pub impl Show for ConflictDecision with fn output(self, logger) {
  match self {
    Replace => logger.write_string("Replace")
    Coexist => logger.write_string("Coexist")
    Ignore => logger.write_string("Ignore")
  }
}

pub extend ConflictDecision with Show::{to_string, output}
pub extend ConflictDecision with Eq::{not_equal, equal}

/// 单个候选条目的裁决。
pub(all) struct ConflictVerdict {
  existing : MemoryEntry
  decision : ConflictDecision
}

/// 冲突判定抽象。仅对判定为 Replace / Coexist 的候选返回裁决。
pub(open) trait ConflictJudge {
  judge(
    self : Self,
    new_fact : ExtractedFact,
    candidates : Array[MemoryEntry]
  ) -> Result[Array[ConflictVerdict], MoomemError]
}

/// 缺省判定器：对每个 candidate 计算
///   sim = max(cosine(new_fact 嵌入, candidate 嵌入), 关键词 Jaccard)
///   sim >= threshold              → Replace
///   [threshold - 0.15, threshold) → Coexist
///   否则                           → Ignore（不产生裁决）
pub struct SimilarityJudge {
  threshold : Double
  embedder : &Embedder
}

pub fn SimilarityJudge::new(
  threshold : Double,
  embedder : &Embedder
) -> SimilarityJudge {
  SimilarityJudge::{ threshold, embedder }
}

pub impl ConflictJudge for SimilarityJudge with judge(self, new_fact, candidates) {
  let verdicts : Array[ConflictVerdict] = []
  let new_vec = match self.embedder.embed([new_fact.content]) {
    Ok(vecs) => if vecs.length() > 0 { vecs[0] } else { [] }
    Err(_) => []
  }
  for cand in candidates {
    let cos = cosine_similarity(new_vec, cand.embedding)
    let jac = keyword_jaccard(new_fact.content, cand.keywords)
    let sim = if cos > jac { cos } else { jac }
    if sim >= self.threshold {
      verdicts.push(
        ConflictVerdict::{ existing : cand, decision : Replace },
      )
    } else if sim >= self.threshold - COEXIST_BAND {
      verdicts.push(
        ConflictVerdict::{ existing : cand, decision : Coexist },
      )
    }
  }
  Ok(verdicts)
}

pub extend SimilarityJudge with ConflictJudge::{judge}

/// 关键词 Jaccard 重叠度：|token(new) ∩ keywords(cand)| / |并集|。
/// 两侧均空时返回 0.0。
pub fn keyword_jaccard(new_content : String, cand_keywords : Array[String]) -> Double {
  let new_tokens = tokenize(new_content)
  let set_a : Map[String, Bool] = Map([])
  for t in new_tokens {
    set_a.set(t, true)
  }
  let set_b : Map[String, Bool] = Map([])
  for t in cand_keywords {
    set_b.set(t, true)
  }
  if set_a.length() == 0 || set_b.length() == 0 {
    return 0.0
  }
  let mut intersection = 0
  for t in set_a.keys() {
    if set_b.contains(t) {
      intersection = intersection + 1
    }
  }
  let union = set_a.length() + set_b.length() - intersection
  if union == 0 {
    return 0.0
  }
  intersection.to_double() / union.to_double()
}

// Extraction precision is not scored offline: RawExtractor stores the raw turn.

///|
fn run_extraction_offline_skip() -> ExtractionReport {
  println("### Extraction precision")
  println("")
  println(
    "extraction precision: SKIPPED (RawExtractor stores raw text; the host supplies Extractor)",
  )
  println("")
  ExtractionReport::{
    skipped: true,
    precision: 0.0,
    hit: 0,
    denom: 0,
    model: "",
    cases_scored: 0,
    cases_total: 0,
  }
}

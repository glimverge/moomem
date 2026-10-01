#!/usr/bin/env python3
"""Generate the LoCoMo subset fixture used by ci/locomo (W4 retrieval eval).

LoCoMo is released under CC BY-NC 4.0 (non-commercial). The upstream data file
is NOT redistributed in full; this script derives a small, faithful subset that
is committed to the repository for offline, reproducible evaluation.

Provenance:
  source repo : https://github.com/snap-research/locomo
  data file   : data/locomo10.json
  pinned sha  : cbfbc1dba6bc53d00625212a0f22d55ffee7c1fc (2024-08-10)
  license     : CC BY-NC 4.0 (Attribution-NonCommercial 4.0 International)

Usage:
  python3 scripts/locomo/make_subset.py [--input locomo10.json] [--out ci/locomo/data/locomo_subset.json]

If --input is omitted the upstream file is downloaded to a temporary path.
The output is deterministic for a given upstream revision (key order preserved
by explicit construction, no timestamps embedded).
"""
from __future__ import annotations

import argparse
import json
import pathlib
import urllib.request

SOURCE_URL = "https://raw.githubusercontent.com/snap-research/locomo/cbfbc1dba6bc53d00625212a0f22d55ffee7c1fc/data/locomo10.json"
PINNED_SHA = "cbfbc1dba6bc53d00625212a0f22d55ffee7c1fc"
# Two conversations: enough distractor mass for a meaningful top-5 retrieval task,
# small enough to keep the repository light.
SELECTED_SAMPLE_IDS = ["conv-26", "conv-30"]

HEADER = {
    "dataset": "LoCoMo (subset)",
    "source_repo": "https://github.com/snap-research/locomo",
    "source_file": "data/locomo10.json",
    "source_commit": PINNED_SHA,
    "license": "CC BY-NC 4.0",
    "license_url": "https://creativecommons.org/licenses/by-nc/4.0/",
    "citation": (
        "Maharana et al. Evaluating Very Long-Term Conversational Memory of LLM "
        "Agents. ACL 2024. arXiv:2402.17753"
    ),
    "redistribution": (
        "Subset derived for non-commercial evaluation only. Image fields "
        "(img_url/blip_caption/query) removed. Full dataset not redistributed."
    ),
    "eval_note": (
        "Retrieval evaluation corpus: turns are indexed as memory; each QA "
        "carries the dia_id evidence turns that contain the answer. "
        "category 5 = adversarial (no answer in dialogue) and is excluded from "
        "the retrieval metric."
    ),
    "category_map": {
        "1": "multi-hop",
        "2": "temporal",
        "3": "open-domain",
        "4": "single-hop",
        "5": "adversarial",
    },
}


def build(raw: list[dict], selected: list[str]) -> dict:
    conversations = []
    for sample in raw:
        if sample["sample_id"] not in selected:
            continue
        conv = sample["conversation"]
        sess_keys = sorted(
            (k for k in conv if k.startswith("session_") and not k.endswith("_date_time")),
            key=lambda k: int(k.split("_")[1]),
        )
        sessions = []
        available: set[str] = set()
        for key in sess_keys:
            num = int(key.split("_")[1])
            turns = []
            for t in conv[key]:
                turns.append(
                    {
                        "dia_id": t["dia_id"],
                        "speaker": t["speaker"],
                        "text": t["text"],
                    }
                )
                available.add(t["dia_id"])
            sessions.append(
                {
                    "session": num,
                    "date_time": conv.get(f"{key}_date_time", ""),
                    "turns": turns,
                }
            )
        qa = []
        for q in sample["qa"]:
            evidence = [d for d in q.get("evidence", []) if d in available]
            if not evidence:
                # evidence missing or outside the retained sessions: drop, do not invent
                continue
            entry = {
                "question": q["question"],
                "category": q["category"],
                "evidence": evidence,
            }
            if q["category"] == 5:
                entry["adversarial_answer"] = q.get("adversarial_answer", "")
            else:
                entry["answer"] = q.get("answer", "")
            qa.append(entry)
        conversations.append(
            {
                "sample_id": sample["sample_id"],
                "speaker_a": conv.get("speaker_a", ""),
                "speaker_b": conv.get("speaker_b", ""),
                "sessions": sessions,
                "qa": qa,
            }
        )
    return {"meta": HEADER, "conversations": conversations}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=None, help="local locomo10.json (skips download)")
    ap.add_argument("--out", default="ci/locomo/data/locomo_subset.json")
    args = ap.parse_args()

    if args.input:
        raw = json.loads(pathlib.Path(args.input).read_text(encoding="utf-8"))
    else:
        with urllib.request.urlopen(SOURCE_URL, timeout=120) as resp:
            raw = json.loads(resp.read().decode("utf-8"))

    subset = build(raw, SELECTED_SAMPLE_IDS)
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(subset, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    turns = sum(len(s["turns"]) for c in subset["conversations"] for s in c["sessions"])
    scored = sum(1 for c in subset["conversations"] for q in c["qa"] if q["category"] != 5)
    adv = sum(1 for c in subset["conversations"] for q in c["qa"] if q["category"] == 5)
    print(f"wrote {out} ({out.stat().st_size} bytes)")
    print(f"conversations={len(subset['conversations'])} turns={turns} scored_qa={scored} adversarial={adv}")


if __name__ == "__main__":
    main()

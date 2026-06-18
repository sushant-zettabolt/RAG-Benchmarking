"""Re-run LLM-as-a-judge on existing metrics JSONL without re-running the
full benchmark.  Reads metrics_baseline.jsonl and metrics_zendnn.jsonl from
RESULTS_DIR, calls the judge for every record, updates judge fields in-place,
rewrites the files, then regenerates the A/B report.

Usage (inside the harness container):
    python rejudge.py
"""
import os
import json
import time

import common as C

JUDGE_MODEL  = os.environ.get("JUDGE_MODEL", "chat-model")
JUDGE_THRESH = C.envf("JUDGE_THRESHOLD", 0.5)
JOB_A = os.environ.get("JOB_A", "baseline")
JOB_B = os.environ.get("JOB_B", "zendnn")


def rejudge_file(path):
    records = [json.loads(line) for line in open(path) if line.strip()]
    print(f"[rejudge] {os.path.basename(path)}: {len(records)} records")
    for i, rec in enumerate(records, 1):
        if not rec.get("ok") or not rec.get("answer"):
            rec["judge_score"] = None
            rec["judge_verdict"] = "skipped"
            rec["match"] = False
            print(f"  {i}/{len(records)} skipped (no answer)")
            continue
        j = C.judge_answer(rec["question"], rec["references"], rec["answer"], JUDGE_MODEL)
        rec["judge_score"] = j["score"]
        rec["judge_verdict"] = j["verdict"]
        rec["judge_reason"] = j["reason"]
        if j["verdict"] in ("unparsed", "error"):
            rec["judge_raw"] = j.get("raw")
        rec["match"] = (j["score"] is not None and j["score"] >= JUDGE_THRESH)
        sc = f"{j['score']:.2f}" if isinstance(j["score"], float) else "n/a"
        print(f"  {i}/{len(records)} score={sc} verdict={j['verdict']} match={rec['match']}")
    with open(path, "w") as fh:
        for rec in records:
            fh.write(json.dumps(rec) + "\n")
    n_match = sum(1 for r in records if r.get("match"))
    print(f"[rejudge] {os.path.basename(path)}: {n_match}/{len(records)} matched")


def main():
    C.ensure_dirs()
    t0 = time.time()
    for job in (JOB_A, JOB_B):
        path = os.path.join(C.RESULTS_DIR, f"metrics_{job}.jsonl")
        if not os.path.exists(path):
            print(f"[rejudge] WARNING: {path} not found, skipping")
            continue
        rejudge_file(path)
    print(f"\n[rejudge] judging done in {time.time()-t0:.1f}s, regenerating report ...")
    import report_ab
    report_ab.main()
    print("[rejudge] done.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Regression watchdog for the ZenDNN llama.cpp backend.

Reads a fresh A/B report (data/results/report_ab.json) produced by run_ab.sh,
extracts ONLY the `zendnn` numbers, and compares them against the *previous*
ZenDNN run recorded in the history file. This is a STRICTLY zendnn-to-zendnn
comparison ACROSS TIME — the baseline column in each report is ignored here;
its only job within a run is the in-run A/B. The point of this script is to
catch the case where a fresh `git pull` + rebuild of llama.cpp / ZenDNN made the
ZenDNN backend slower (or faster) than it was last week.

Verdict per metric (and overall): SPEEDUP / NEUTRAL / DEGRADE, decided on the
headline throughput metrics (prefill_tps, decode_tps) against a percentage
threshold. Latency metrics are reported for context but do not gate the verdict.

Outputs:
  - <out_dir>/verdict.md    human-readable comparison table
  - <out_dir>/verdict.txt   single machine-readable line (e.g. "DEGRADE prefill_tps -8.3%")
  - appends one JSON line to <history>/zendnn_history.jsonl

Exit code is 0 unless --fail-on-degrade is passed and the verdict is DEGRADE.
"""
import argparse
import json
import os
import sys

# Higher-is-better throughput metrics. These decide the overall verdict.
HEADLINE = ["prefill_tps", "decode_tps"]
# Lower-is-better latency metrics, reported for context (do not gate).
LATENCY = ["total_s", "ttft_s", "prefill_s", "decode_s", "llm_s"]
# Quality metrics, reported for context (a rebuild can change numerics).
QUALITY = ["match_rate", "contains_ref", "mean_judge_score"]

LOWER_IS_BETTER = set(LATENCY)


def pct_good(prev, curr, metric):
    """Percent change in the *beneficial* direction (positive = better)."""
    if prev in (None, 0) or curr is None:
        return None
    if metric in LOWER_IS_BETTER:
        return (prev - curr) / prev * 100.0
    return (curr - prev) / prev * 100.0


def classify(good_pct, threshold):
    if good_pct is None:
        return "n/a"
    if good_pct >= threshold:
        return "SPEEDUP"
    if good_pct <= -threshold:
        return "DEGRADE"
    return "NEUTRAL"


def fmt_pct(p):
    if p is None:
        return "   n/a"
    return f"{p:+.1f}%"


def fmt_val(v):
    if v is None:
        return "n/a"
    if isinstance(v, float):
        return f"{v:.3f}"
    return str(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", required=True, help="path to report_ab.json")
    ap.add_argument("--history", required=True, help="dir holding zendnn_history.jsonl")
    ap.add_argument("--out", required=True, help="output dir for verdict.md / verdict.txt")
    ap.add_argument("--threshold", type=float,
                    default=float(os.environ.get("CI_CMP_THRESHOLD_PCT", "5.0")),
                    help="percent change (in the good direction) to call SPEEDUP/DEGRADE")
    ap.add_argument("--timestamp", default=os.environ.get("CI_RUN_TS", ""),
                    help="run timestamp label (the shell passes one in)")
    ap.add_argument("--build-sha", default="", help="llama.cpp commit the zendnn image was built from")
    ap.add_argument("--eval-n", default=os.environ.get("EVAL_N", ""), help="EVAL_N used for this run")
    ap.add_argument("--fail-on-degrade", action="store_true",
                    help="exit non-zero when the verdict is DEGRADE")
    args = ap.parse_args()

    with open(args.report) as f:
        report = json.load(f)
    try:
        cur = report["comparison"]["zendnn"]
    except (KeyError, TypeError):
        sys.exit(f"ERROR: {args.report} has no comparison.zendnn block")

    os.makedirs(args.history, exist_ok=True)
    os.makedirs(args.out, exist_ok=True)
    hist_path = os.path.join(args.history, "zendnn_history.jsonl")

    # Previous = last recorded zendnn run (before we append the current one).
    prev_rec = None
    if os.path.exists(hist_path):
        with open(hist_path) as f:
            lines = [ln for ln in f if ln.strip()]
        if lines:
            prev_rec = json.loads(lines[-1])
    prev = (prev_rec or {}).get("metrics", {})

    all_metrics = HEADLINE + LATENCY + QUALITY
    rows = []
    headline_verdicts = []
    for m in all_metrics:
        c = cur.get(m)
        p = prev.get(m)
        gp = pct_good(p, c, m) if prev_rec else None
        v = classify(gp, args.threshold) if prev_rec else "BASELINE"
        rows.append((m, p, c, gp, v))
        if m in HEADLINE and prev_rec:
            headline_verdicts.append((m, gp, v))

    # Overall verdict: degrade wins (conservative watchdog).
    if not prev_rec:
        overall = "BASELINE"
        headline_note = "no prior ZenDNN run on record — this run is the new baseline"
    elif any(v == "DEGRADE" for _, _, v in headline_verdicts):
        overall = "DEGRADE"
    elif any(v == "SPEEDUP" for _, _, v in headline_verdicts):
        overall = "SPEEDUP"
    else:
        overall = "NEUTRAL"

    # ── verdict.txt (one line, machine-readable) ──────────────────────────────
    if prev_rec:
        worst = min(headline_verdicts, key=lambda x: (x[1] if x[1] is not None else 0))
        best = max(headline_verdicts, key=lambda x: (x[1] if x[1] is not None else 0))
        driver = worst if overall == "DEGRADE" else (best if overall == "SPEEDUP" else worst)
        summary = f"{overall} {driver[0]} {fmt_pct(driver[1])}"
    else:
        summary = "BASELINE first-run"
    with open(os.path.join(args.out, "verdict.txt"), "w") as f:
        f.write(summary + "\n")

    # ── verdict.md (human-readable) ───────────────────────────────────────────
    badge = {"SPEEDUP": "🟢 SPEEDUP", "DEGRADE": "🔴 DEGRADE",
             "NEUTRAL": "⚪ NEUTRAL", "BASELINE": "🔵 BASELINE"}[overall]
    md = []
    md.append(f"# ZenDNN regression watch — {badge}\n")
    md.append(f"- Run: `{args.timestamp or 'n/a'}`  ·  EVAL_N: `{args.eval_n or '?'}`  ·  threshold: ±{args.threshold:.1f}%")
    if args.build_sha:
        md.append(f"- llama.cpp commit (zendnn image): `{args.build_sha}`")
    if prev_rec:
        md.append(f"- Compared against previous ZenDNN run: `{prev_rec.get('timestamp', '?')}`"
                  + (f" (commit `{prev_rec.get('build_sha')}`)" if prev_rec.get("build_sha") else ""))
    else:
        md.append("- " + headline_note)
    md.append("")
    md.append("Comparison is **strictly ZenDNN→ZenDNN across time** (the baseline column of each A/B report is not used here).\n")

    def table(title, metrics):
        md.append(f"### {title}")
        md.append("| metric | previous | current | Δ (good=+) | verdict |")
        md.append("|---|---:|---:|---:|---|")
        for m, p, c, gp, v in rows:
            if m not in metrics:
                continue
            md.append(f"| {m} | {fmt_val(p)} | {fmt_val(c)} | {fmt_pct(gp)} | {v} |")
        md.append("")

    table("Throughput (headline — gates the verdict)", HEADLINE)
    table("Latency (context)", LATENCY)
    table("Quality (context)", QUALITY)
    with open(os.path.join(args.out, "verdict.md"), "w") as f:
        f.write("\n".join(md))

    # ── append current run to history ─────────────────────────────────────────
    rec = {
        "timestamp": args.timestamp,
        "build_sha": args.build_sha,
        "eval_n": args.eval_n,
        "verdict": overall,
        "summary": summary,
        "metrics": {m: cur.get(m) for m in all_metrics},
    }
    with open(hist_path, "a") as f:
        f.write(json.dumps(rec) + "\n")

    # ── console output ────────────────────────────────────────────────────────
    print("=" * 64)
    print(f"  ZenDNN regression verdict: {badge}")
    print(f"  {summary}")
    print("=" * 64)
    for m, p, c, gp, v in rows:
        if m in HEADLINE:
            print(f"  {m:14s} prev={fmt_val(p):>10s}  curr={fmt_val(c):>10s}  Δ={fmt_pct(gp):>7s}  {v}")
    print(f"  full table: {os.path.join(args.out, 'verdict.md')}")
    print(f"  history:    {hist_path}")

    if args.fail_on_degrade and overall == "DEGRADE":
        sys.exit(2)


if __name__ == "__main__":
    main()

"""A/B reporting: compare two evaluation runs (baseline vs zendnn) and emit the
ZenDNN-vs-baseline comparison — per-stage latency, inference throughput, and
speedup ratios — as Markdown + JSON, mirroring the main-branch benchmark report.

Reads results/metrics_<JOB_A>.jsonl and results/metrics_<JOB_B>.jsonl (written by
evaluate.py with JOB set). Defaults: JOB_A=baseline, JOB_B=zendnn.
"""
import os
import json
import statistics

import common as C

JOB_A = os.environ.get("JOB_A", "baseline")
JOB_B = os.environ.get("JOB_B", "zendnn")


def load(job):
    path = os.path.join(C.RESULTS_DIR, f"metrics_{job}.jsonl")
    if not os.path.exists(path):
        raise SystemExit(f"{path} not found — run: evaluate.py with JOB={job} first.")
    return [json.loads(l) for l in open(path) if l.strip()]


def mean(rows, key):
    vals = [r.get(key) for r in rows if isinstance(r.get(key), (int, float))]
    return statistics.mean(vals) if vals else None


def f(x, d=2):
    return "n/a" if x is None else (f"{x:.{d}f}" if isinstance(x, float) else str(x))


def agg(rows):
    ok = [r for r in rows if r.get("ok")]
    return {
        "n": len(rows),
        "n_ok": len(ok),
        "match_rate": (sum(1 for r in rows if r.get("match")) / len(rows)) if rows else None,
        "mean_judge_score": mean(ok, "judge_score"),
        "total_s": mean(ok, "total_s"),
        "ttft_s": mean(ok, "ttft_s"),
        "embed_s": mean(ok, "embed_s"),
        "retrieval_s": mean(ok, "retrieval_s"),
        "prefill_s": mean(ok, "prefill_s"),
        "decode_s": mean(ok, "decode_s"),
        "llm_s": mean(ok, "llm_s"),
        "prefill_tps": mean(ok, "prefill_tps"),
        "decode_tps": mean(ok, "decode_tps"),
        "prompt_tokens": mean(ok, "prompt_tokens"),
        "completion_tokens": mean(ok, "completion_tokens"),
    }


def speedup(a, b, lower_better=False):
    """b vs a. lower_better → a/b (latency); else b/a (throughput)."""
    if a is None or b is None or a == 0 or b == 0:
        return None
    return (a / b) if lower_better else (b / a)


def md(a, b, meta_a, meta_b):
    o = [f"# ZenDNN A/B Report — {JOB_A} vs {JOB_B}\n"]
    o.append(f"_Same RAG pipeline (AnythingLLM + Google NQ), identical model and "
             f"queries; only the llama.cpp chat backend differs. "
             f"`{JOB_A}` vs `{JOB_B}`, run sequentially (no CPU contention)._\n")

    o.append("## Per-stage mean latency\n")
    o.append(f"| Stage | {JOB_A} (s) | {JOB_B} (s) | speedup |")
    o.append("|---|---|---|---|")
    for label, key in [
        ("Query embedding", "embed_s"),
        ("Retrieval + overhead", "retrieval_s"),
        ("Prompt processing (prefill)", "prefill_s"),
        ("Generation (decode)", "decode_s"),
        ("LLM total (prefill+decode)", "llm_s"),
        ("Time to first token", "ttft_s"),
        ("End-to-end (total)", "total_s"),
    ]:
        sp = speedup(a[key], b[key], lower_better=True)
        sp_s = f"{sp:.2f}x faster" if sp else "n/a"
        o.append(f"| {label} | {f(a[key],3)} | {f(b[key],3)} | {sp_s} |")

    o.append("\n## Inference throughput (tokens/sec, mean)\n")
    o.append(f"| Metric | {JOB_A} | {JOB_B} | speedup |")
    o.append("|---|---|---|---|")
    for label, key in [("Prefill (prompt) t/s", "prefill_tps"),
                       ("Decode (generation) t/s", "decode_tps")]:
        sp = speedup(a[key], b[key])
        sp_s = f"{sp:.2f}x" if sp else "n/a"
        o.append(f"| {label} | {f(a[key],1)} | {f(b[key],1)} | {sp_s} |")

    o.append("\n## Token sizes & quality (sanity — should be ~equal across jobs)\n")
    o.append(f"| Metric | {JOB_A} | {JOB_B} |")
    o.append("|---|---|---|")
    o.append(f"| Prompt tokens (mean) | {f(a['prompt_tokens'],1)} | {f(b['prompt_tokens'],1)} |")
    o.append(f"| Completion tokens (mean) | {f(a['completion_tokens'],1)} | {f(b['completion_tokens'],1)} |")
    o.append(f"| Match rate (LLM judge) | {f((a['match_rate'] or 0)*100,1)}% | {f((b['match_rate'] or 0)*100,1)}% |")
    o.append(f"| Mean judge score | {f(a['mean_judge_score'],3)} | {f(b['mean_judge_score'],3)} |")
    o.append(f"| Queries ok | {a['n_ok']}/{a['n']} | {b['n_ok']}/{b['n']} |")

    o.append("\n## Summary\n")
    pf = speedup(a["prefill_tps"], b["prefill_tps"])
    dc = speedup(a["decode_tps"], b["decode_tps"])
    llm = speedup(a["llm_s"], b["llm_s"], lower_better=True)
    e2e = speedup(a["total_s"], b["total_s"], lower_better=True)
    o.append(f"- Prefill throughput: **{f(pf)}x**  ({f(a['prefill_tps'],1)} → {f(b['prefill_tps'],1)} t/s)")
    o.append(f"- Decode throughput:  **{f(dc)}x**  ({f(a['decode_tps'],1)} → {f(b['decode_tps'],1)} t/s)")
    o.append(f"- LLM inference latency: **{f(llm)}x faster**")
    o.append(f"- End-to-end latency: **{f(e2e)}x faster**  "
             f"({f(a['total_s'])}s → {f(b['total_s'])}s)")
    o.append(f"\n_Embedding ({f(a['embed_s'],3)}s / {f(b['embed_s'],3)}s) and retrieval "
             f"should be ~equal across jobs — large drift signals CPU contention or "
             f"contamination. ZenDNN accelerates matmul-bound prefill more than "
             f"bandwidth-bound decode, as expected._")
    o.append("\n---\n_Generated by report_ab.py._")
    return "\n".join(o)


def main():
    rows_a, rows_b = load(JOB_A), load(JOB_B)
    a, b = agg(rows_a), agg(rows_b)

    meta_a = _results_meta(JOB_A)
    meta_b = _results_meta(JOB_B)

    out_json = {JOB_A: a, JOB_B: b, "meta": {JOB_A: meta_a, JOB_B: meta_b}}
    with open(os.path.join(C.RESULTS_DIR, "report_ab.json"), "w") as fp:
        json.dump(out_json, fp, indent=2)

    text = md(a, b, meta_a, meta_b)
    with open(os.path.join(C.RESULTS_DIR, "report_ab.md"), "w") as fp:
        fp.write(text)
    print(text)
    print(f"\n[report_ab] wrote {C.RESULTS_DIR}/report_ab.md and report_ab.json")


def _results_meta(job):
    p = os.path.join(C.RESULTS_DIR, f"results_{job}.json")
    if os.path.exists(p):
        return json.load(open(p)).get("summary", {})
    return {}


if __name__ == "__main__":
    main()

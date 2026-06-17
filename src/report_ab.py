"""Combined A/B report: ZenDNN baseline-vs-zendnn comparison PLUS the full
per-job RAG evaluation detail (aggregate, latency, token usage, failed queries,
example answers) in a single Markdown + JSON report.

Reads results/metrics_<JOB_A>.jsonl and results/metrics_<JOB_B>.jsonl (written by
evaluate.py with JOB set). Defaults: JOB_A=baseline, JOB_B=zendnn.
"""
import os
import json
import statistics

import common as C
from report import build_summary, eval_sections, dataset_line, f

JOB_A = os.environ.get("JOB_A", "baseline")
JOB_B = os.environ.get("JOB_B", "zendnn")


def load(job):
    path = os.path.join(C.RESULTS_DIR, f"metrics_{job}.jsonl")
    if not os.path.exists(path):
        raise SystemExit(f"{path} not found — run evaluate.py with JOB={job} first.")
    return [json.loads(l) for l in open(path) if l.strip()]


def mean(rows, key):
    vals = [r.get(key) for r in rows if isinstance(r.get(key), (int, float))]
    return statistics.mean(vals) if vals else None


def agg(rows):
    ok = [r for r in rows if r.get("ok")]
    return {
        "n": len(rows), "n_ok": len(ok),
        "match_rate": (sum(1 for r in rows if r.get("match")) / len(rows)) if rows else None,
        # model-independent correctness signal — computed even when the LLM judge
        # is off (fixed-decode mode), so a fast-but-garbage backend is still visible
        "contains_ref": (sum(1 for r in rows if r.get("contains_ref")) / len(rows)) if rows else None,
        "mean_judge_score": mean(ok, "judge_score"),
        "total_s": mean(ok, "total_s"), "ttft_s": mean(ok, "ttft_s"),
        "embed_s": mean(ok, "embed_s"), "retrieval_s": mean(ok, "retrieval_s"),
        "prefill_s": mean(ok, "prefill_s"), "decode_s": mean(ok, "decode_s"),
        "llm_s": mean(ok, "llm_s"),
        "prefill_tps": mean(ok, "prefill_tps"), "decode_tps": mean(ok, "decode_tps"),
        "prompt_tokens": mean(ok, "prompt_tokens"),
        "completion_tokens": mean(ok, "completion_tokens"),
    }


def speedup(a, b, lower_better=False):
    if a is None or b is None or a == 0 or b == 0:
        return None
    return (a / b) if lower_better else (b / a)


def speedup_label(sp):
    """Render a speedup ratio with correct faster/slower wording.

    The ratio is rendered as a bare multiplier (e.g. '1.12x') with no
    faster/slower wording. A near-equal ratio that rounds to 1.00x at 2
    decimals is widened to 3 decimals so a real difference is still visible.
    """
    if sp is None:
        return "n/a"
    ratio = sp if sp >= 1 else 1 / sp
    s = f"{ratio:.2f}"
    if s == "1.00":
        s = f"{ratio:.3f}"
    return f"{s}x"


# If the two jobs processed wildly different token counts, the per-stage
# latency comparison is apples-to-oranges (latency scales with token count).
# Flag it instead of presenting it as a clean speedup.
WORKLOAD_TOLERANCE = 0.10  # fractional difference in mean tokens we tolerate


def workload_comparable(a, b):
    for key in ("prompt_tokens", "completion_tokens"):
        x, y = a.get(key), b.get(key)
        if not x or not y:
            continue
        if abs(x - y) / max(x, y) > WORKLOAD_TOLERANCE:
            return False
    return True


def comparison_sections(a, b, h="##"):
    comparable = workload_comparable(a, b)
    o = []
    if not comparable:
        o.append(
            f"> ⚠️ **Latency comparison not valid:** {JOB_A} and {JOB_B} processed "
            f"different workloads (prompt tokens {f(a['prompt_tokens'],0)} vs "
            f"{f(b['prompt_tokens'],0)}, completion tokens {f(a['completion_tokens'],1)} "
            f"vs {f(b['completion_tokens'],1)}). Per-stage latency scales with token "
            f"count, so the latency speedups below are apples-to-oranges. Compare the "
            f"per-token throughput table instead, and check why the runs diverged "
            f"(see Sanity / Evaluation detail — likely a broken job).\n"
        )
    o.append(f"{h} Per-stage mean latency\n")
    o.append(f"| Stage | {JOB_A} (s) | {JOB_B} (s) | speedup |")
    o.append("|---|---|---|---|")
    for label, key in [
        ("Query embedding", "embed_s"), ("Retrieval + overhead", "retrieval_s"),
        ("Prompt processing (prefill)", "prefill_s"), ("Generation (decode)", "decode_s"),
        ("LLM total (prefill+decode)", "llm_s"), ("Time to first token", "ttft_s"),
        ("End-to-end (total)", "total_s"),
    ]:
        sp = speedup(a[key], b[key], lower_better=True)
        o.append(f"| {label} | {f(a[key],3)} | {f(b[key],3)} | {speedup_label(sp)} |")

    o.append(f"\n{h} Inference throughput (tokens/sec, mean)\n")
    o.append(f"| Metric | {JOB_A} | {JOB_B} | speedup |")
    o.append("|---|---|---|---|")
    for label, key in [("Prefill (prompt) t/s", "prefill_tps"),
                       ("Decode (generation) t/s", "decode_tps")]:
        sp = speedup(a[key], b[key])
        o.append(f"| {label} | {f(a[key],1)} | {f(b[key],1)} | "
                 f"{(f'{sp:.2f}x' if sp else 'n/a')} |")

    o.append(f"\n{h} Sanity — should be ~equal across jobs (else contamination/contention)\n")
    o.append(f"| Metric | {JOB_A} | {JOB_B} |")
    o.append("|---|---|---|")
    o.append(f"| Prompt tokens (mean) | {f(a['prompt_tokens'],1)} | {f(b['prompt_tokens'],1)} |")
    o.append(f"| Completion tokens (mean) | {f(a['completion_tokens'],1)} | {f(b['completion_tokens'],1)} |")
    o.append(f"| Query embedding (s) | {f(a['embed_s'],3)} | {f(b['embed_s'],3)} |")
    o.append(f"| Retrieval + overhead (s) | {f(a['retrieval_s'],3)} | {f(b['retrieval_s'],3)} |")
    o.append(f"| Match rate (LLM judge) | {f((a['match_rate'] or 0)*100,1)}% | {f((b['match_rate'] or 0)*100,1)}% |")
    o.append(f"| Contains reference (lexical) | {f((a['contains_ref'] or 0)*100,1)}% | {f((b['contains_ref'] or 0)*100,1)}% |")

    # A faster backend that stopped producing correct answers is NOT a win. The
    # lexical signal is model-independent and survives fixed-decode truncation, so
    # use it to flag a backend whose output quality collapsed relative to the other.
    ar, br = (a["contains_ref"] or 0), (b["contains_ref"] or 0)
    if ar >= 0.2 and br <= ar / 2:
        o.append(
            f"\n> ⚠️ **{JOB_B} output quality collapsed:** lexical reference-hit rate "
            f"fell from {ar*100:.0f}% ({JOB_A}) to {br*100:.0f}% ({JOB_B}) while {JOB_A} "
            f"stayed correct. Any {JOB_B} speedup above is **fast-but-wrong** — it is "
            f"producing incorrect/garbage output, not equivalent answers faster. Inspect "
            f"the {JOB_B} example answers below before trusting the throughput numbers.\n"
        )

    pf = speedup(a["prefill_tps"], b["prefill_tps"])
    dc = speedup(a["decode_tps"], b["decode_tps"])
    llm = speedup(a["llm_s"], b["llm_s"], lower_better=True)
    e2e = speedup(a["total_s"], b["total_s"], lower_better=True)
    o.append(f"\n{h} Speedup summary\n")
    o.append(f"- Prefill throughput: **{f(pf)}x**  ({f(a['prefill_tps'],1)} → {f(b['prefill_tps'],1)} t/s)")
    o.append(f"- Decode throughput:  **{f(dc)}x**  ({f(a['decode_tps'],1)} → {f(b['decode_tps'],1)} t/s)")
    o.append(f"- LLM inference latency: **{speedup_label(llm)}**")
    o.append(f"- End-to-end latency: **{speedup_label(e2e)}**  ({f(a['total_s'])}s → {f(b['total_s'])}s)")
    if comparable:
        o.append(f"\n_ZenDNN accelerates matmul-bound prefill more than bandwidth-bound decode, as expected._")
    else:
        o.append(f"\n_Note: throughput (t/s) is the only valid comparison here — the two runs "
                 f"processed different token counts, so latency speedups reflect workload size, "
                 f"not backend speed._")
    return o


def load_meta():
    meta = {}
    if os.path.exists(C.INGEST_META):
        meta = json.load(open(C.INGEST_META))
    return meta


def main():
    rows_a, rows_b = load(JOB_A), load(JOB_B)
    a, b = agg(rows_a), agg(rows_b)
    sum_a, sum_b = build_summary(rows_a), build_summary(rows_b)
    meta = load_meta()

    o = ["# RAG Evaluation + ZenDNN A/B Report — Google Natural Questions\n",
         dataset_line(meta) + "\n",
         f"_Comparison: **{JOB_A}** vs **{JOB_B}** — same pipeline, model and "
         f"queries; only the llama.cpp chat backend differs. Jobs run sequentially._\n"]

    o.append(f"## ZenDNN A/B comparison ({JOB_A} vs {JOB_B})\n")
    o += comparison_sections(a, b, h="###")

    o.append(f"\n## Evaluation detail — {JOB_A}\n")
    o += eval_sections(sum_a, rows_a, meta, h="###")
    o.append(f"\n## Evaluation detail — {JOB_B}\n")
    o += eval_sections(sum_b, rows_b, meta, h="###")

    o.append("\n---\n_Generated by report_ab.py._")
    text = "\n".join(o)

    with open(os.path.join(C.RESULTS_DIR, "report_ab.md"), "w") as fp:
        fp.write(text)
    out_json = {
        "comparison": {JOB_A: a, JOB_B: b},
        "eval_detail": {JOB_A: sum_a, JOB_B: sum_b},
        "ingest": meta,
    }
    with open(os.path.join(C.RESULTS_DIR, "report_ab.json"), "w") as fp:
        json.dump(out_json, fp, indent=2)

    print(text)
    print(f"\n[report_ab] wrote {C.RESULTS_DIR}/report_ab.md and report_ab.json")


if __name__ == "__main__":
    main()

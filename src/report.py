"""Reporting: read the per-query eval results and emit a summary report as both
JSON and Markdown — aggregate metrics, failed queries, and example answers.
"""
import os
import json
import statistics

import common as C


def pct(vals, p):
    if not vals:
        return None
    s = sorted(vals)
    k = max(0, min(len(s) - 1, int(round((p / 100.0) * len(s) + 0.5)) - 1))
    return s[k]


def stats(vals):
    vals = [v for v in vals if isinstance(v, (int, float))]
    if not vals:
        return {"n": 0, "mean": None, "p50": None, "p95": None, "min": None, "max": None}
    return {
        "n": len(vals),
        "mean": statistics.mean(vals),
        "p50": pct(vals, 50),
        "p95": pct(vals, 95),
        "min": min(vals),
        "max": max(vals),
    }


def f(x, d=2):
    return "n/a" if x is None else (f"{x:.{d}f}" if isinstance(x, float) else str(x))


def load_records():
    path = os.path.join(C.RESULTS_DIR, "metrics.jsonl")
    if not os.path.exists(path):
        raise SystemExit(f"{path} not found — run evaluate.py first.")
    return [json.loads(l) for l in open(path) if l.strip()]


def build_summary(recs):
    n = len(recs)
    ok = [r for r in recs if r["ok"]]
    matched = [r for r in recs if r.get("match")]
    judged = [r for r in ok if isinstance(r.get("judge_score"), (int, float))]

    def col(key):
        return stats([r.get(key) for r in ok])

    scores = [r["judge_score"] for r in judged]
    contains = [r for r in ok if r.get("contains_ref")]
    return {
        "n_queries": n,
        "n_ok": len(ok),
        "n_error": n - len(ok),
        "n_matched": len(matched),
        "match_rate": (len(matched) / n) if n else None,
        "n_contains_ref": len(contains),
        "contains_ref_rate": (len(contains) / n) if n else None,
        "mean_judge_score": statistics.mean(scores) if scores else None,
        "verdicts": _verdict_counts(recs),
        "tokens": {
            "prompt": col("prompt_tokens"),
            "completion": col("completion_tokens"),
            "total": col("total_tokens"),
            "sum_total": sum(r.get("total_tokens") or 0 for r in ok),
        },
        "latency_s": {
            "total": col("total_s"),
            "ttft": col("ttft_s"),
            "embed": col("embed_s"),
            "retrieval": col("retrieval_s"),
            "prefill": col("prefill_s"),
            "decode": col("decode_s"),
            "llm": col("llm_s"),
        },
        "chunks": col("n_sources"),
    }


def _verdict_counts(recs):
    out = {}
    for r in recs:
        v = r.get("judge_verdict") or "none"
        out[v] = out.get(v, 0) + 1
    return out


def latency_table(lat):
    rows = [
        ("End-to-end (total)", "total"),
        ("Time to first token", "ttft"),
        ("Query embedding", "embed"),
        ("Retrieval + overhead", "retrieval"),
        ("Prompt processing (prefill)", "prefill"),
        ("Generation (decode)", "decode"),
        ("LLM total (prefill+decode)", "llm"),
    ]
    out = ["| Stage | mean (s) | p50 (s) | p95 (s) | min | max |",
           "|---|---|---|---|---|---|"]
    for label, key in rows:
        s = lat[key]
        out.append(f"| {label} | {f(s['mean'],3)} | {f(s['p50'],3)} | {f(s['p95'],3)} "
                   f"| {f(s['min'],3)} | {f(s['max'],3)} |")
    return out


def eval_sections(summary, recs, meta, h="##"):
    """Detailed evaluation sections (aggregate, latency, tokens, failures,
    examples) as a list of markdown lines. `h` sets the heading level so these
    can be embedded standalone (##) or nested under another report (###/####)."""
    hh = h + "#"
    o = []
    tt = summary["tokens"]
    o.append(f"{h} Aggregate\n")
    o.append("| Metric | Value |")
    o.append("|---|---|")
    o.append(f"| Queries | {summary['n_queries']} |")
    o.append(f"| Succeeded | {summary['n_ok']} |")
    o.append(f"| Errored | {summary['n_error']} |")
    o.append(f"| **Matched (LLM judge)** | **{summary['n_matched']} "
             f"({f((summary['match_rate'] or 0)*100,1)}%)** |")
    o.append(f"| Mean judge score | {f(summary['mean_judge_score'],3)} |")
    o.append(f"| Contains reference (lexical) | {summary['n_contains_ref']} "
             f"({f((summary['contains_ref_rate'] or 0)*100,1)}%) |")
    o.append(f"| Verdicts | {', '.join(f'{k}={v}' for k,v in summary['verdicts'].items())} |")
    o.append(f"| Documents ingested | {meta.get('docs_uploaded_ok','?')}"
             f"/{meta.get('docs_written','?')} |")
    o.append(f"| Answerable questions (corpus) | {meta.get('answerable_questions','?')} |")
    o.append(f"| Total tokens (sum) | {summary['tokens']['sum_total']} |")
    o.append(f"| Tokens/query (prompt / completion) | "
             f"{f(tt['prompt']['mean'],1)} / {f(tt['completion']['mean'],1)} |")

    o.append(f"\n{h} Latency by stage (successful queries)\n")
    o += latency_table(summary["latency_s"])

    o.append(f"\n{h} Token usage (successful queries)\n")
    o.append("| | mean | p50 | p95 | min | max |")
    o.append("|---|---|---|---|---|---|")
    for label, key in [("Prompt tokens", "prompt"), ("Completion tokens", "completion"),
                       ("Total tokens", "total")]:
        s = tt[key]
        o.append(f"| {label} | {f(s['mean'],1)} | {f(s['p50'],0)} | {f(s['p95'],0)} "
                 f"| {f(s['min'],0)} | {f(s['max'],0)} |")

    # failed queries
    failed = [r for r in recs if not r["ok"] or not r.get("match")]
    o.append(f"\n{h} Failed / incorrect queries ({len(failed)})\n")
    if failed:
        o.append("| Q# | question | verdict | reason |")
        o.append("|---|---|---|---|")
        for r in failed[:30]:
            reason = (r.get("judge_reason") or r.get("error") or "")[:80].replace("|", "\\|")
            o.append(f"| {r['id']} | {_clip(r['question'])} | "
                     f"{r.get('judge_verdict')} | {reason} |")
        if len(failed) > 30:
            o.append(f"\n_…and {len(failed)-30} more (see the JSON report)._")
    else:
        o.append("_None — all queries matched._")

    # examples
    correct = [r for r in recs if r.get("match")][:3]
    wrong = [r for r in recs if r["ok"] and not r.get("match")][:3]
    o.append(f"\n{h} Example answers\n")
    o.append(f"{hh} Correct\n")
    for r in correct:
        o += _example_block(r)
    if not correct:
        o.append("_No correct examples._\n")
    o.append(f"{hh} Incorrect\n")
    for r in wrong:
        o += _example_block(r)
    if not wrong:
        o.append("_No incorrect examples._\n")
    return o


def dataset_line(meta):
    return (f"_Dataset: **{meta.get('eval_dataset','?')}** (questions) + "
            f"**{meta.get('corpus_dataset','?')}** (documents) · "
            f"workspace `{meta.get('workspace_slug','?')}`_")


def md_report(summary, recs, meta):
    o = ["# RAG Evaluation Report — Google Natural Questions\n", dataset_line(meta) + "\n"]
    o += eval_sections(summary, recs, meta, h="##")
    o.append("\n---\n_Generated by report.py from `results/metrics.jsonl`._")
    return "\n".join(o)


def _clip(s, n=70):
    s = (s or "").replace("\n", " ").replace("|", "\\|")
    return s if len(s) <= n else s[:n] + "…"


def _example_block(r):
    refs = " | ".join(r.get("references") or [])
    return [
        f"**Q{r['id']}: {r['question']}**  ",
        f"- expected: _{refs}_  ",
        f"- got: {r.get('answer') or '(empty)'}  ",
        f"- score: {f(r.get('judge_score'),2)} ({r.get('judge_verdict')}) — "
        f"{r.get('judge_reason') or ''}\n",
    ]


def main():
    recs = load_records()
    meta = {}
    if os.path.exists(C.INGEST_META):
        meta = json.load(open(C.INGEST_META))
    res_path = os.path.join(C.RESULTS_DIR, "results.json")
    if os.path.exists(res_path):
        meta.update(json.load(open(res_path)).get("summary", {}))

    summary = build_summary(recs)

    json_out = {"summary": summary, "ingest": meta, "n_records": len(recs)}
    with open(os.path.join(C.RESULTS_DIR, "report.json"), "w") as fp:
        json.dump(json_out, fp, indent=2)

    md = md_report(summary, recs, meta)
    with open(os.path.join(C.RESULTS_DIR, "report.md"), "w") as fp:
        fp.write(md)

    print(md)
    print(f"\n[report] wrote {C.RESULTS_DIR}/report.md and report.json")


if __name__ == "__main__":
    main()

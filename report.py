import os, re, json, glob, statistics

BASE  = os.environ["BASE"]
STAMP = os.environ.get("STAMP", "run")
# leading measured queries to drop from stats as still-warmup-polluted (on top of
# the harness warmup pass). DROP_FIRST=1 excludes Q1.
DROP_FIRST = int(os.environ.get("DROP_FIRST", 0))
# results directory to read/write (relative to BASE). Override to report on an
# archived run dir, e.g. RESULTS=results_old.
RESULTS = os.environ.get("RESULTS", "results")
RDIR = f"{BASE}/{RESULTS}"


def harness(job):
    d = json.load(open(f"{RDIR}/harness_{job}.json"))
    rows = [x for x in d["per_query"] if x["ok"]]
    return rows   # list of {i, sec, ttft_sec, ok}


def val(series, model):
    for s in series:
        m = s.get("metric", {})
        if m.get("requested_model") == model or m.get("model") == model:
            return float(s["value"][1])
    return sum(float(s["value"][1]) for s in series) if series else 0.0


def prom_delta(job, sum_m, cnt_m, model):
    try:
        a = json.load(open(f"{RDIR}/prom_{job}_start.json"))
        b = json.load(open(f"{RDIR}/prom_{job}_end.json"))
    except Exception:
        return None
    ds = val(b.get(sum_m, []), model) - val(a.get(sum_m, []), model)
    dc = val(b.get(cnt_m, []), model) - val(a.get(cnt_m, []), model)
    return (ds / dc) if dc > 0 else None


def loglines_per_query(job):
    """Parse llama-server log in order; return one tuple per completed request.
    Uses the STAMP-matched log if STAMP is set, otherwise the most recently modified one."""
    cand_names = [f"{RDIR}/chat_{job}_{STAMP}.log", f"{RDIR}/chat_{job}_run_{STAMP}.log"]
    stamped = next((p for p in cand_names if STAMP != "run" and os.path.exists(p)), None)
    if stamped:
        candidates = [stamped]
    else:
        all_logs = glob.glob(f"{RDIR}/chat_{job}_*.log")
        candidates = [max(all_logs, key=os.path.getmtime)] if all_logs else []

    entries = []
    pending = None
    for fp in candidates:
        for ln in open(fp, errors="ignore"):
            pf = re.search(
                r"prompt eval time\s*=\s*([\d.]+)\s*ms\s*/\s*(\d+)\s*tokens.*?([\d.]+)\s*tokens per second",
                ln,
            )
            if pf:
                # (pf_ms, pf_tokens, pf_tps)
                pending = (float(pf.group(1)), int(pf.group(2)), float(pf.group(3)))
                continue
            if pending and "prompt eval time" not in ln:
                dc = re.search(
                    r"\beval time\s*=\s*([\d.]+)\s*ms\s*/\s*(\d+)\s*tokens.*?([\d.]+)\s*tokens per second",
                    ln,
                )
                if dc:
                    # (pf_ms, pf_tokens, pf_tps, dc_ms, dc_tokens, dc_tps)
                    entries.append((*pending, float(dc.group(1)), int(dc.group(2)), float(dc.group(3))))
                    pending = None
    return entries  # [(pf_ms, pf_tok, pf_tps, dc_ms, dc_tok, dc_tps), ...]


def mean_or_none(v):
    return statistics.mean(v) if v else None


def fmt(x, dec=2):
    if x is None:
        return "n/a"
    if isinstance(x, float):
        return f"{x:.{dec}f}"
    return str(x)


out = ["# RAG Pipeline Benchmark — Per-Stage Timing (ZenDNN A/B)\n"]

# ── source legend ──────────────────────────────────────────────────────────────
out.append("## Measurement sources\n")
out.append("| Stage | Instrument |")
out.append("|---|---|")
out.append("| Retrieved chunks | harness.py: length of AnythingLLM SSE `sources` array (context chunks fed to the LLM) |")
out.append("| Query embedding | LiteLLM Prometheus `litellm_request_total_latency_metric` (requested_model=embed-model) — delta sum÷count over job |")
out.append("| Retrieval+augment residual | wall_mean − embed_mean − llm_mean (derived; includes vector search, doc fetch, AnythingLLM prompt build, network) |")
out.append("| LLM inference (prefill+decode) | llama-server log `prompt eval time` + `eval time` per request, matched in order |")
out.append("| TTFT — client | harness.py: `time.time()` from request send to first non-empty SSE `textResponse` chunk |")
out.append("| TTFT — LiteLLM | Prometheus `litellm_llm_api_time_to_first_token_metric` delta sum÷count over job (requires streaming path) |")
out.append("| End-to-end | harness.py wall-clock to SSE `close` event |")

# ── per-job data ───────────────────────────────────────────────────────────────
all_rows = []
for job in ["baseline", "zendnn"]:
    h_rows   = harness(job)
    log_q    = loglines_per_query(job)
    # the chat log also contains the warmup request(s) run before measurement;
    # the measured queries are the LAST len(h_rows) timing entries, in order
    if len(log_q) >= len(h_rows):
        log_q = log_q[len(log_q) - len(h_rows):]
    emb      = prom_delta(job,
                          "litellm_request_total_latency_metric_sum",
                          "litellm_request_total_latency_metric_count",
                          "embed-model")
    ttft_p   = prom_delta(job,
                          "litellm_llm_api_time_to_first_token_metric_sum",
                          "litellm_llm_api_time_to_first_token_metric_count",
                          "chat-model")

    per_q = []
    for qi, row in enumerate(h_rows):
        if qi < len(log_q):
            pf_ms, pf_tok, pf_tps, dc_ms, dc_tok, dc_tps = log_q[qi]
            llm_s = (pf_ms + dc_ms) / 1000.0
        else:
            pf_ms = pf_tok = pf_tps = dc_ms = dc_tok = dc_tps = llm_s = None
        per_q.append({
            "qi": qi,
            "wall":        row["sec"],
            "ttft_client": row.get("ttft_sec"),
            "n_sources":   row.get("n_sources"),
            "pf_ms":   pf_ms,   "pf_tok":  pf_tok,   "pf_tps":  pf_tps,
            "dc_ms":   dc_ms,   "dc_tok":  dc_tok,   "dc_tps":  dc_tps,
            "llm_s":   llm_s,
        })

    # harness already ran a warmup pass; optionally drop more leading measured
    # queries that remain warmup-polluted (DROP_FIRST)
    warm = per_q[DROP_FIRST:] if len(per_q) > DROP_FIRST else per_q
    wall_mean    = mean_or_none([x["wall"]        for x in warm])
    llm_mean     = mean_or_none([x["llm_s"]       for x in warm if x["llm_s"]       is not None])
    ttft_c_mean  = mean_or_none([x["ttft_client"]  for x in warm if x["ttft_client"] is not None])
    pf_tps_mean  = mean_or_none([x["pf_tps"]      for x in warm if x["pf_tps"]      is not None])
    dc_tps_mean  = mean_or_none([x["dc_tps"]      for x in warm if x["dc_tps"]      is not None])
    pf_tok_mean  = mean_or_none([x["pf_tok"]      for x in warm if x["pf_tok"]      is not None])
    dc_tok_mean  = mean_or_none([x["dc_tok"]      for x in warm if x["dc_tok"]      is not None])
    chunks_mean  = mean_or_none([x["n_sources"]   for x in warm if x["n_sources"]   is not None])
    pf_ms_mean   = mean_or_none([x["pf_ms"]       for x in warm if x["pf_ms"]       is not None])
    dc_ms_mean   = mean_or_none([x["dc_ms"]       for x in warm if x["dc_ms"]       is not None])
    # time-per-token (ms) = mean(stage ms) / mean(stage tokens)
    pf_ms_per_tok = (pf_ms_mean / pf_tok_mean) if (pf_ms_mean and pf_tok_mean) else None
    dc_ms_per_tok = (dc_ms_mean / dc_tok_mean) if (dc_ms_mean and dc_tok_mean) else None
    resid = ((wall_mean - (emb or 0.0) - llm_mean)
             if (emb is not None and llm_mean is not None and wall_mean is not None) else None)

    all_rows.append(dict(
        job=job, per_q=per_q, emb=emb, ttft_p=ttft_p,
        wall_mean=wall_mean, llm_mean=llm_mean, resid=resid,
        ttft_c_mean=ttft_c_mean, pf_tps_mean=pf_tps_mean, dc_tps_mean=dc_tps_mean,
        pf_tok_mean=pf_tok_mean, dc_tok_mean=dc_tok_mean, chunks_mean=chunks_mean,
        pf_ms_mean=pf_ms_mean, dc_ms_mean=dc_ms_mean,
        pf_ms_per_tok=pf_ms_per_tok, dc_ms_per_tok=dc_ms_per_tok,
    ))

# ── Table 1: per-query breakdown ───────────────────────────────────────────────
for r in all_rows:
    n = len(r["per_q"])
    out.append(f"\n## Per-query breakdown — {r['job']}\n")
    out.append("| Q | chunks | prompt tok | gen tok | wall (s) | client TTFT (s) | prefill (s) | decode (s) | LLM total (s) | residual (s) | prefill t/s | decode t/s |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for pq in r["per_q"]:
        note = " ⚠warmup (excluded)" if pq["qi"] < DROP_FIRST else ""
        pf_s   = pq["pf_ms"] / 1000.0 if pq["pf_ms"] is not None else None
        dc_s   = pq["dc_ms"] / 1000.0 if pq["dc_ms"] is not None else None
        residq = (pq["wall"] - pq["llm_s"]) if pq["llm_s"] is not None else None
        out.append(
            f"| Q{pq['qi']+1}{note} | {fmt(pq['n_sources'],0)} | {fmt(pq['pf_tok'],0)} | {fmt(pq['dc_tok'],0)} "
            f"| {fmt(pq['wall'])} | {fmt(pq['ttft_client'])} "
            f"| {fmt(pf_s)} | {fmt(dc_s)} | {fmt(pq['llm_s'])} "
            f"| {fmt(residq)} | {fmt(pq['pf_tps'],0)} | {fmt(pq['dc_tps'],0)} |"
        )
    out.append(
        f"| **mean Q{DROP_FIRST+1}–Q{n}** | **{fmt(r['chunks_mean'],1)}** | **{fmt(r['pf_tok_mean'],0)}** | **{fmt(r['dc_tok_mean'],0)}** "
        f"| **{fmt(r['wall_mean'])}** | **{fmt(r['ttft_c_mean'])}** "
        f"| **{fmt((r['pf_ms_mean'] or 0)/1000.0)}** | **{fmt((r['dc_ms_mean'] or 0)/1000.0)}** | **{fmt(r['llm_mean'])}** | — "
        f"| **{fmt(r['pf_tps_mean'],0)}** | **{fmt(r['dc_tps_mean'],0)}** |"
    )

# ── Table 2: stage summary ─────────────────────────────────────────────────────
b, z = all_rows[0], all_rows[1]
out.append(f"\n## Per-stage mean latency — measured runs (harness warmup + first {DROP_FIRST} query excluded)\n")
out.append("| Stage | baseline (s) | zendnn (s) | source |")
out.append("|---|---|---|---|")
out.append(f"| Query embedding | {fmt(b['emb'],3)} | {fmt(z['emb'],3)} | LiteLLM Prometheus (job-level mean) |")
out.append(f"| Retrieval+augment residual | {fmt(b['resid'],3)} | {fmt(z['resid'],3)} | wall − embed − llm |")
out.append(f"| LLM inference (prefill+decode) | {fmt(b['llm_mean'],3)} | {fmt(z['llm_mean'],3)} | llama-server log |")
out.append(f"| TTFT — client-side | {fmt(b['ttft_c_mean'],3)} | {fmt(z['ttft_c_mean'],3)} | harness SSE first chunk |")
out.append(f"| TTFT — LiteLLM/Prometheus | {fmt(b['ttft_p'],3)} | {fmt(z['ttft_p'],3)} | litellm_llm_api_time_to_first_token_metric |")
out.append(f"| End-to-end (wall) | {fmt(b['wall_mean'],3)} | {fmt(z['wall_mean'],3)} | harness wall-clock |")

# ── Table 3: throughput ────────────────────────────────────────────────────────
out.append("\n## Inference throughput & token sizes (llama-server log, mean of measured runs)\n")
out.append("| Job | Prompt tok | Gen tok | Prefill t/s | Decode t/s | Prefill ms/tok | Decode ms/tok |")
out.append("|---|---|---|---|---|---|---|")
for r in all_rows:
    out.append(
        f"| {r['job']} | {fmt(r['pf_tok_mean'],0)} | {fmt(r['dc_tok_mean'],0)} "
        f"| {fmt(r['pf_tps_mean'],1)} | {fmt(r['dc_tps_mean'],1)} "
        f"| {fmt(r['pf_ms_per_tok'],2)} | {fmt(r['dc_ms_per_tok'],2)} |"
    )

# ── Table 4: speedups ─────────────────────────────────────────────────────────
out.append("\n## ZenDNN speedup (Job B / Job A)\n")

def spd(bv, zv, lower_better=False):
    if bv is None or zv is None or bv == 0:
        return "n/a"
    ratio = bv / zv if lower_better else zv / bv
    direction = "faster" if lower_better else "higher t/s"
    return f"{ratio:.2f}x {direction}"

out.append(f"- Prefill throughput: **{spd(b['pf_tps_mean'], z['pf_tps_mean'])}**")
out.append(f"- Decode throughput:  **{spd(b['dc_tps_mean'], z['dc_tps_mean'])}**")
out.append(f"- LLM inference latency: **{spd(b['llm_mean'], z['llm_mean'], lower_better=True)}**")
out.append(f"- Client TTFT: **{spd(b['ttft_c_mean'], z['ttft_c_mean'], lower_better=True)}**")
out.append(f"- End-to-end: baseline {fmt(b['wall_mean'])}s → zendnn {fmt(z['wall_mean'])}s  "
           f"(**{spd(b['wall_mean'], z['wall_mean'], lower_better=True)}**)")
out.append(f"\n_Embedding ({fmt(b['emb'],3)}s / {fmt(z['emb'],3)}s) and residual should be ~equal "
           f"across jobs; large drift = contamination._")
if DROP_FIRST:
    out.append(f"\n_Note: 'Query embedding' and 'TTFT — LiteLLM/Prometheus' are job-aggregate "
               f"Prometheus deltas (snapshot taken before Q1), so they still include the "
               f"{DROP_FIRST} excluded query. All per-query-derived rows (wall, client TTFT, LLM, "
               f"throughput, residual) exclude it._")

rp = f"{RDIR}/REPORT_{STAMP}.md"
open(rp, "w").write("\n".join(out))
print("Wrote", rp)
print("\n".join(out))

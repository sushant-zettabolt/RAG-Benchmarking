"""Evaluation: run each NQ question against AnythingLLM, capture the answer,
grade it with an LLM judge, and record per-stage timing + token usage.

Per query we snapshot llama.cpp /metrics on the chat and embed servers BEFORE
and AFTER the AnythingLLM call (queries run serially, so the deltas are clean),
then judge the answer AFTER the snapshot so the judge call never pollutes the
measured token/timing counters.

Captured per query:
  total_s         end-to-end wall (request -> SSE close)
  ttft_s          client time-to-first-token
  embed_s         query-embedding time   (llama-embed prompt_seconds delta)
  prefill_s       prompt processing time (llama-chat prompt_seconds delta)
  decode_s        generation time        (llama-chat predicted_seconds delta)
  retrieval_s     derived: max(0, ttft - embed - prefill) = vector search + overhead
  prompt_tokens / completion_tokens / total_tokens   (llama-chat counter deltas)
  match score / verdict   (LLM judge)
"""
import os
import json
import time

import common as C

QUERY_MODE     = os.environ.get("QUERY_MODE", "query")
JUDGE_MODEL    = os.environ.get("JUDGE_MODEL", "chat-model")
JUDGE_THRESH   = C.envf("JUDGE_THRESHOLD", 0.5)
WARMUP         = C.envi("WARMUP", 1)
EVAL_LIMIT     = C.envi("EVAL_LIMIT", 0)

# llama.cpp counter names (Prometheus text exposition)
M_PROMPT_TOK   = "llamacpp:prompt_tokens_total"
M_GEN_TOK      = "llamacpp:tokens_predicted_total"
M_PROMPT_SEC   = "llamacpp:prompt_seconds_total"
M_GEN_SEC      = "llamacpp:tokens_predicted_seconds_total"


def load_questions():
    rows = [json.loads(l) for l in open(C.EVAL_FILE)]
    if EVAL_LIMIT > 0:
        rows = rows[:EVAL_LIMIT]
    return rows


def run_one(q, do_judge=True):
    chat_before = C.scrape_metrics(C.CHAT_METRICS_URL)
    emb_sum_b, emb_cnt_b = C.scrape_litellm_latency("embed-model")

    res = C.allm_stream_chat(q["question"], mode=QUERY_MODE)

    chat_after = C.scrape_metrics(C.CHAT_METRICS_URL)
    emb_sum_a, emb_cnt_a = C.scrape_litellm_latency("embed-model")

    prefill_s = C.metric_delta(chat_after, chat_before, M_PROMPT_SEC)
    decode_s  = C.metric_delta(chat_after, chat_before, M_GEN_SEC)
    p_tok     = C.metric_delta(chat_after, chat_before, M_PROMPT_TOK)
    g_tok     = C.metric_delta(chat_after, chat_before, M_GEN_TOK)
    # embedding latency from LiteLLM (one embed request per query → count delta 1)
    embed_s = None
    if None not in (emb_sum_a, emb_sum_b, emb_cnt_a, emb_cnt_b) and (emb_cnt_a - emb_cnt_b) > 0:
        embed_s = (emb_sum_a - emb_sum_b) / (emb_cnt_a - emb_cnt_b)

    ttft = res["ttft_s"]
    retrieval_s = None
    if ttft is not None:
        retrieval_s = max(0.0, ttft - (embed_s or 0.0) - (prefill_s or 0.0))

    rec = {
        "id": q["id"],
        "question": q["question"],
        "references": q["answers"],
        "answerable": q.get("answerable"),
        "answer": res["answer"],
        "ok": res["ok"],
        "error": res["error"],
        "n_sources": res["n_sources"],
        "contains_ref": C.contains_reference(res["answer"], q["answers"]),
        "total_s": res["wall_s"],
        "ttft_s": ttft,
        "embed_s": embed_s,
        "retrieval_s": retrieval_s,
        "prefill_s": prefill_s,
        "decode_s": decode_s,
        "llm_s": (prefill_s + decode_s) if (prefill_s is not None and decode_s is not None) else None,
        "prompt_tokens": int(p_tok) if p_tok is not None else None,
        "completion_tokens": int(g_tok) if g_tok is not None else None,
        "total_tokens": int((p_tok or 0) + (g_tok or 0)) if (p_tok is not None or g_tok is not None) else None,
    }

    if do_judge and res["ok"]:
        j = C.judge_answer(q["question"], q["answers"], res["answer"], JUDGE_MODEL)
        rec["judge_score"]   = j["score"]
        rec["judge_verdict"] = j["verdict"]
        rec["judge_reason"]  = j["reason"]
        rec["match"] = (j["score"] is not None and j["score"] >= JUDGE_THRESH)
    else:
        rec["judge_score"] = None
        rec["judge_verdict"] = "skipped" if not res["ok"] else None
        rec["judge_reason"] = res["error"]
        rec["match"] = False
    return rec


def main():
    C.ensure_dirs()
    if not C.ALLM_KEY:
        raise SystemExit("ALLM_KEY is empty — run ./setup.sh first.")
    if not os.path.exists(C.EVAL_FILE):
        raise SystemExit(f"{C.EVAL_FILE} not found — run ingest.py first.")

    questions = load_questions()
    print(f"[eval] {len(questions)} questions, mode={QUERY_MODE}, judge={JUDGE_MODEL}, warmup={WARMUP}")

    # warmup — excluded from results (absorbs model-load / cache-fill)
    for w in range(min(WARMUP, len(questions))):
        r = run_one(questions[w], do_judge=False)
        print(f"[eval] warmup {w+1}/{WARMUP}  total={r['total_s']:.2f}s  ok={r['ok']}")

    t_job = time.time()
    records = []
    with open(os.path.join(C.RESULTS_DIR, "metrics.jsonl"), "w") as fh:
        for i, q in enumerate(questions, 1):
            rec = run_one(q)
            records.append(rec)
            fh.write(json.dumps(rec) + "\n")
            fh.flush()
            sc = rec["judge_score"]
            sc_s = f"{sc:.2f}" if isinstance(sc, float) else "n/a"
            ttft = rec["ttft_s"]
            ttft_s = f"{ttft:.2f}s" if isinstance(ttft, float) else "n/a"
            print(f"[eval] {i}/{len(questions)}  total={rec['total_s']:.2f}s  ttft={ttft_s}  "
                  f"tok={rec['total_tokens']}  chunks={rec['n_sources']}  "
                  f"score={sc_s}  match={rec['match']}  ok={rec['ok']}")
    job_wall = time.time() - t_job

    summary = {
        "timestamp": time.time(),
        "n_queries": len(records),
        "job_wall_s": job_wall,
        "query_mode": QUERY_MODE,
        "judge_model": JUDGE_MODEL,
        "judge_threshold": JUDGE_THRESH,
        "warmup": WARMUP,
    }
    with open(os.path.join(C.RESULTS_DIR, "results.json"), "w") as f:
        json.dump({"summary": summary, "records": records}, f, indent=2)

    n_ok = sum(1 for r in records if r["ok"])
    n_match = sum(1 for r in records if r["match"])
    print(f"\n[eval] done in {job_wall:.1f}s  ok={n_ok}/{len(records)}  "
          f"matched={n_match}/{len(records)}")
    print(f"[eval] per-query metrics -> {C.RESULTS_DIR}/metrics.jsonl")
    print(f"[eval] raw results       -> {C.RESULTS_DIR}/results.json")


if __name__ == "__main__":
    main()

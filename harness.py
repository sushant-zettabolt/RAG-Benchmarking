import os, sys, json, time, requests, statistics

BASE = os.environ["BASE"]
KEY  = os.environ["ALLM_KEY"]
SLUG = os.environ["SLUG"]
JOB  = sys.argv[1]   # "baseline" or "zendnn"
U    = os.environ.get("ALLM_URL", "http://127.0.0.1:3001")
PROM = os.environ.get("PROM_URL", "http://127.0.0.1:9090") + "/api/v1/query"
H    = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
queries = [json.loads(l)["q"] for l in open(f"{BASE}/data/queries.jsonl")]
_n = int(os.environ.get("QUERIES_N", 0))
if _n > 0:
    queries = queries[:_n]

# number of leading warmup queries — executed before the metrics snapshot and
# excluded from all stats (absorbs model-load / cache-fill cost)
WARMUP = int(os.environ.get("WARMUP", 0))

def run_query(q):
    """Send one query via stream-chat; return (wall_sec, ttft_sec_or_None, n_sources, ok)."""
    t0 = time.time()
    t_close = None
    ttft_sec = None
    n_sources = None
    ok = False
    try:
        # stream-chat causes AnythingLLM to stream to LiteLLM, populating TTFT metrics
        with requests.post(
            f"{U}/api/v1/workspace/{SLUG}/stream-chat",
            headers=H,
            json={"message": q, "mode": "query"},
            stream=True,
            timeout=600,
        ) as resp:
            ok = resp.status_code == 200
            for raw in resp.iter_lines():
                if not raw:
                    continue
                line = raw.decode("utf-8") if isinstance(raw, bytes) else raw
                if not line.startswith("data: "):
                    continue
                try:
                    ev = json.loads(line[6:])
                except Exception:
                    continue
                if ev.get("error"):
                    print(f"  ALLM error: {ev.get('error')}")
                    ok = False
                # AnythingLLM emits the retrieved context chunks in a `sources`
                # array on the FINAL event, which arrives after the first
                # close=true chunk — so don't break on close; record the close
                # time and keep reading until the server ends the stream.
                if isinstance(ev.get("sources"), list) and ev["sources"]:
                    n_sources = len(ev["sources"])
                if ttft_sec is None and ev.get("textResponse"):
                    ttft_sec = time.time() - t0
                if ev.get("close") and t_close is None:
                    t_close = time.time()
    except Exception as e:
        ok = False
        print(f"  ERROR: {e}")
    return (t_close or time.time()) - t0, ttft_sec, n_sources, ok

def snap(tag):
    out = {}
    for m in [
        "litellm_request_total_latency_metric_sum",
        "litellm_request_total_latency_metric_count",
        "litellm_llm_api_time_to_first_token_metric_sum",
        "litellm_llm_api_time_to_first_token_metric_count",
        "litellm_proxy_total_requests_metric_total",
    ]:
        try:
            out[m] = requests.get(PROM, params={"query": m}, timeout=5).json()["data"]["result"]
        except Exception:
            out[m] = []
    json.dump(out, open(f"{BASE}/results/prom_{JOB}_{tag}.json", "w"))

# warmup pass — runs before snap("start") so model-load cost is excluded from
# both the per-query stats and the Prometheus deltas
for w in range(WARMUP):
    dt, ttft_sec, n_src, ok = run_query(queries[w % len(queries)])
    tag = f"wall={dt:.2f}s  ttft={ttft_sec:.2f}s" if ttft_sec else f"wall={dt:.2f}s  ttft=n/a"
    print(f"[{JOB}] warmup {w+1}/{WARMUP}  {tag}  chunks={n_src}  ok={ok}")

totals = []
snap("start")
t_job = time.time()

for i, q in enumerate(queries):
    dt, ttft_sec, n_src, ok = run_query(q)
    totals.append({"i": i, "sec": dt, "ttft_sec": ttft_sec, "n_sources": n_src, "ok": ok})
    tag = f"wall={dt:.2f}s  ttft={ttft_sec:.2f}s" if ttft_sec else f"wall={dt:.2f}s  ttft=n/a"
    print(f"[{JOB}] {i+1}/{len(queries)}  {tag}  chunks={n_src}  ok={ok}")

job_wall = time.time() - t_job
snap("end")
json.dump(
    {"job": JOB, "queries": len(queries), "job_wall_sec": job_wall, "per_query": totals},
    open(f"{BASE}/results/harness_{JOB}.json", "w"),
)
g = [x["sec"] for x in totals if x["ok"]]
t = [x["ttft_sec"] for x in totals if x["ok"] and x.get("ttft_sec") is not None]
if g:
    ttft_str = f"ttft mean={statistics.mean(t):.2f}s" if t else "ttft=n/a"
    print(f"\n[{JOB}] wall mean={statistics.mean(g):.2f}s  p95={sorted(g)[int(0.95*len(g))-1]:.2f}s  "
          f"{ttft_str}  n_ok={len(g)}/{len(queries)}")
else:
    print(f"\n[{JOB}] ALL QUERIES FAILED  n_ok=0/{len(queries)}")

#!/usr/bin/env bash
# ZenDNN A/B benchmark for the embedding server only.
# Swaps llama-embed between baseline and ZenDNN builds and measures
# per-request embedding latency directly — no chat server, no full RAG pipeline.
#   ./run_embed_ab.sh
set -euo pipefail
cd "$(dirname "$0")"

DC_BASE="docker compose"
DC_AB="docker compose -f docker-compose.yml -f docker-compose.ab.yml"

env_get() { local v; v="$(grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*//' | xargs)"; [ -z "$v" ] && echo "$2" || echo "$v"; }
log() { echo "[embed_ab] $*"; }
die() { echo "[embed_ab] ERROR: $*" >&2; exit 1; }

[ -f .env ] || die "no .env — run ./setup.sh first"
EMBED_PORT="$(env_get EMBED_PORT 8082)"
# Build-from-source IMAGES (built by `make build-llama`); the job swaps the
# llama-embed image. No host binaries / bindirs.
LLAMA_BASELINE_IMAGE="$(env_get LLAMA_BASELINE_IMAGE "nqrag-llama:baseline")"
LLAMA_ZENDNN_IMAGE="$(env_get LLAMA_ZENDNN_IMAGE "nqrag-llama:zendnn")"
AB_ZENDNN_ALGO="$(env_get AB_ZENDNN_ALGO "1")"
N_WARMUP="${EMBED_WARMUP:-3}"
N_REQUESTS="${EMBED_N:-20}"

have_image() { docker image inspect "$1" >/dev/null 2>&1; }
if ! have_image "$LLAMA_BASELINE_IMAGE" || ! have_image "$LLAMA_ZENDNN_IMAGE"; then
    log "building missing llama images ($LLAMA_BASELINE_IMAGE / $LLAMA_ZENDNN_IMAGE) ..."
    ./scripts/build_llama.sh
fi
have_image "$LLAMA_BASELINE_IMAGE" || die "baseline image $LLAMA_BASELINE_IMAGE missing — build it: make build-llama"
have_image "$LLAMA_ZENDNN_IMAGE"   || die "zendnn image $LLAMA_ZENDNN_IMAGE missing — build it: make build-llama"

wait_for() {
    echo -n "[embed_ab] waiting for $1 "
    for _ in $(seq 1 "${3:-120}"); do
        if curl -fsS -m 5 "$2" >/dev/null 2>&1; then echo " up"; return 0; fi
        echo -n "."; sleep 5
    done
    echo " TIMEOUT"; return 1
}

run_embed_job() {  # job image algo
    local job="$1" image="$2" algo="$3"
    log "════ job '$job': swapping embed backend (image=$image algo=${algo:-unset}) ════"
    # Keep chat server as-is (not part of this benchmark); only swap embed.
    EMBED_IMAGE="$image" \
        ZENDNNL_MATMUL_ALGO="$algo" AB_JOB="$job" \
        $DC_AB up -d --force-recreate --no-deps llama-embed
    wait_for "embed ($job)" "http://localhost:${EMBED_PORT}/health" 120 \
        || { $DC_AB logs --tail 40 llama-embed; die "embed server ($job) did not come up"; }
    log "running embed benchmark for job '$job' (warmup=$N_WARMUP requests=$N_REQUESTS) ..."
    $DC_BASE run --rm \
        -e JOB="$job" \
        -e WARMUP="$N_WARMUP" \
        -e EMBED_N="$N_REQUESTS" \
        -e EMBED_URL="http://llama-embed:8080" \
        harness python bench_embed.py
}

log "ensuring base services are up ..."
$DC_BASE up -d llama-embed litellm prometheus anythingllm >/dev/null

run_embed_job "baseline" "$LLAMA_BASELINE_IMAGE" ""
run_embed_job "zendnn"   "$LLAMA_ZENDNN_IMAGE"   "$AB_ZENDNN_ALGO"

log "════ Embed A/B results ════"
python3 - <<'EOF'
import json, statistics, glob

for job in ("baseline", "zendnn"):
    path = f"data/results/metrics_embed_{job}.jsonl"
    try:
        rows = [json.loads(l) for l in open(path) if l.strip()]
    except FileNotFoundError:
        print(f"{job}: no results file"); continue
    lats = [r["latency_s"] for r in rows]
    mean = statistics.mean(lats)*1000
    p50  = statistics.median(lats)*1000
    p95  = sorted(lats)[int(len(lats)*0.95)]*1000
    tps  = 1.0/statistics.mean(lats)
    print(f"{job:10s}  mean={mean:.1f}ms  p50={p50:.1f}ms  p95={p95:.1f}ms  {tps:.1f} req/s")

# Speedup
try:
    b = [json.loads(l) for l in open("data/results/metrics_embed_baseline.jsonl") if l.strip()]
    z = [json.loads(l) for l in open("data/results/metrics_embed_zendnn.jsonl")   if l.strip()]
    speedup = statistics.mean(r["latency_s"] for r in b) / statistics.mean(r["latency_s"] for r in z)
    print(f"\nSpeedup (baseline/zendnn mean latency): {speedup:.2f}x")
except Exception:
    pass
EOF

log "✅ done. Results in data/results/metrics_embed_baseline.jsonl + metrics_embed_zendnn.jsonl"

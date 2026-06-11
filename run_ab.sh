#!/usr/bin/env bash
# ZenDNN A/B benchmark: evaluate the SAME RAG pipeline with a baseline llama.cpp
# chat backend, then with the ZenDNN build, then emit a comparison report.
#
#   ./run_ab.sh
#
# Jobs run STRICTLY SEQUENTIALLY (one chat server at a time) so they never
# compete for CPU — clean, comparable numbers. Requires the stack to be up and
# documents ingested first:  ./setup.sh  &&  make ingest
set -euo pipefail
cd "$(dirname "$0")"

DC_BASE="docker compose"
DC_AB="docker compose -f docker-compose.yml -f docker-compose.ab.yml"

env_get() { local v; v="$(grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2-)"; [ -z "$v" ] && echo "$2" || echo "$v"; }
log() { echo "[run_ab] $*"; }
die() { echo "[run_ab] ERROR: $*" >&2; exit 1; }

[ -f .env ] || die "no .env — run ./setup.sh first"
CHAT_PORT="$(env_get CHAT_PORT 8081)"
ALLM_KEY="$(env_get ALLM_KEY '')"
CHAT_MODEL_PATH="$(env_get CHAT_MODEL_PATH '')"

# A/B knobs (override in .env). Default to main's two build trees in ./llama.cpp.
AB_BASELINE_BINDIR="$(env_get AB_BASELINE_BINDIR "$PWD/llama.cpp/build/bin")"
AB_ZENDNN_BINDIR="$(env_get AB_ZENDNN_BINDIR "$PWD/llama.cpp/build_zendnn/bin")"
AB_ZENDNN_LIBDIR="$(env_get AB_ZENDNN_LIBDIR "/home/zettabolt/internal_zendnn/ZenDNN/build/install/zendnnl/lib")"
AB_ZENDNN_ALGO="$(env_get AB_ZENDNN_ALGO "1")"
JOB_A="${JOB_A:-baseline}"
JOB_B="${JOB_B:-zendnn}"

# ── preconditions ────────────────────────────────────────────────────────────
[ -n "$ALLM_KEY" ] || die "ALLM_KEY empty — run ./setup.sh first"
[ -n "$CHAT_MODEL_PATH" ] || die "CHAT_MODEL_PATH must point at a local GGUF for the A/B (set it in .env)"
[ -x "$AB_BASELINE_BINDIR/llama-server" ] || die "baseline binary not found: $AB_BASELINE_BINDIR/llama-server"
[ -x "$AB_ZENDNN_BINDIR/llama-server" ]   || die "zendnn binary not found: $AB_ZENDNN_BINDIR/llama-server"
if [ -n "$AB_ZENDNN_LIBDIR" ] && [ ! -e "$AB_ZENDNN_LIBDIR/libzendnnl.so" ]; then
    die "libzendnnl.so not found in AB_ZENDNN_LIBDIR=$AB_ZENDNN_LIBDIR (the zendnn binary links it at load time)"
fi

log "ensuring base services are up (embed/litellm/prometheus/anythingllm) ..."
$DC_BASE up -d llama-embed litellm prometheus anythingllm >/dev/null
[ -f data/ingest_metadata.json ] || die "no ingested data — run: make ingest"

wait_for() {  # name url tries
    echo -n "[run_ab] waiting for $1 "
    for _ in $(seq 1 "${3:-120}"); do
        if curl -fsS -m 5 "$2" >/dev/null 2>&1; then echo " up"; return 0; fi
        echo -n "."; sleep 5
    done
    echo " TIMEOUT"; return 1
}

run_job() {  # job bindir libdir algo
    local job="$1" bindir="$2" libdir="$3" algo="$4"
    log "════ job '$job': swapping chat backend (bindir=$bindir algo=${algo:-unset}) ════"
    CHAT_BINDIR="$bindir" CHAT_LIBDIR="${libdir:-$bindir}" \
        ZENDNNL_MATMUL_ALGO="$algo" AB_JOB="$job" \
        $DC_AB up -d --force-recreate --no-deps llama-chat
    wait_for "chat ($job)" "http://localhost:${CHAT_PORT}/health" 120 \
        || { $DC_AB logs --tail 40 llama-chat; die "chat server ($job) did not come up"; }
    docker logs nqrag-llama-chat 2>&1 | grep -iE 'zendnn|backend' | head -3 || true
    log "evaluating job '$job' ..."
    $DC_BASE run --rm -e JOB="$job" harness python evaluate.py
}

run_job "$JOB_A" "$AB_BASELINE_BINDIR" "$AB_BASELINE_BINDIR" ""
run_job "$JOB_B" "$AB_ZENDNN_BINDIR"   "$AB_ZENDNN_LIBDIR"   "$AB_ZENDNN_ALGO"

log "generating comparison report ..."
$DC_BASE run --rm -e JOB_A="$JOB_A" -e JOB_B="$JOB_B" harness python report_ab.py

log "✅ done. Report: data/results/report_ab.md (+ report_ab.json)"

#!/usr/bin/env bash
# Bulk-ingest driver with DATA-PARALLEL embedding.
#
#   ./run_ingest.sh        (or: make ingest)
#
# The embedding model (nomic, 137M) is tiny and does NOT scale well inside a
# single llama.cpp process past ~16-32 threads. Measured on this 2x96-core EPYC:
#   1 inst x 96 thr (node0)      ~11 emb/s
#   8-16 inst x 16-24 thr (both  ~35 emb/s   <- ~3x, uses all 192 physical cores
#       NUMA nodes, NUMA-local)
#   ...x SMT siblings            ~30 emb/s   <- SMT HURTS (compute-bound), avoid
# So for ingest we spin up N short-lived embed instances spread across BOTH NUMA
# nodes (NUMA-local, physical cores only), shard the corpus across them, then tear
# them down. The persistent `llama-embed` (retrieve, single-slot, bounded) is left
# UNTOUCHED — no reconfigure/restore dance.
set -euo pipefail
cd "$(dirname "$0")"

DC="docker compose"
env_get() { local v; v="$(grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2-)"; [ -z "$v" ] && echo "$2" || echo "$v"; }
log() { echo "[ingest] $*"; }
die() { echo "[ingest] ERROR: $*" >&2; exit 1; }

[ -f .env ] || die "no .env — run ./setup.sh first"
PROJECT="$(env_get COMPOSE_PROJECT_NAME nq-rag-eval)"
NET="${PROJECT}_default"
IMAGE="$(env_get LLAMA_BASELINE_IMAGE nqrag-llama:baseline)"
MODELS_DIR="$(env_get MODELS_DIR ./models)"
EMBED_MODEL_PATH="$(env_get EMBED_MODEL_PATH '')"
EMBED_CTX="$(env_get EMBED_CTX 2048)"
EMBED_INGEST_BATCH="$(env_get EMBED_INGEST_BATCH 4096)"

# Data-parallel layout. INSTANCES split evenly across the 2 NUMA nodes; each gets
# THREADS_PER consecutive PHYSICAL cores (node0 = 0-95, node1 = 96-191; SMT
# siblings 192-383 are intentionally avoided). Need (INSTANCES/2)*THREADS_PER <= 96.
INSTANCES="$(env_get EMBED_INGEST_INSTANCES 12)"
THREADS_PER="$(env_get EMBED_INGEST_THREADS_PER 16)"
CORES_PER_NODE="$(env_get NUMA_CORES_PER_NODE 96)"   # physical cores per socket

[ -n "$EMBED_MODEL_PATH" ] || die "EMBED_MODEL_PATH not set in .env"
[ "$IMAGE" ] || die "no baseline image"
case "$INSTANCES" in ''|*[!0-9]*) die "EMBED_INGEST_INSTANCES must be an integer";; esac
[ $((INSTANCES % 2)) -eq 0 ] || die "EMBED_INGEST_INSTANCES must be even (split across 2 NUMA nodes)"
PER_NODE=$((INSTANCES / 2))
[ $((PER_NODE * THREADS_PER)) -le "$CORES_PER_NODE" ] \
  || die "(INSTANCES/2)*THREADS_PER = $((PER_NODE*THREADS_PER)) exceeds $CORES_PER_NODE cores/node — lower EMBED_INGEST_INSTANCES or THREADS_PER"

NAME_PREFIX="${PROJECT}-eingest"
INSTANCE_NAMES=()

cleanup() {
    log "tearing down ${#INSTANCE_NAMES[@]} ingest embed instances ..."
    for n in "${INSTANCE_NAMES[@]:-}"; do [ -n "$n" ] && docker rm -f "$n" >/dev/null 2>&1 || true; done
}
trap cleanup EXIT INT TERM

wait_up() {  # name
    for _ in $(seq 1 120); do
        docker run --rm --network "$NET" curlimages/curl -fsS -m2 "http://$1:8080/health" >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

launch_instance() {  # name cpuset membind
    docker run -d --rm --name "$1" --network "$NET" --cpuset-cpus "$2" --cap-add SYS_NICE \
        -v "${MODELS_DIR}:/models:ro" --entrypoint /bin/bash "$IMAGE" -c \
        "export OMP_PROC_BIND=close OMP_PLACES=cores; \
         numactl --physcpubind=$2 --membind=$3 /app/llama-server \
           --host 0.0.0.0 --port 8080 --embedding --ctx-size ${EMBED_CTX} \
           --batch-size ${EMBED_INGEST_BATCH} --ubatch-size ${EMBED_INGEST_BATCH} \
           --threads $4 --parallel 1 --metrics --alias embed-model \
           --model ${EMBED_MODEL_PATH}" >/dev/null 2>&1
}

log "launching $INSTANCES data-parallel embed instances ($PER_NODE/node x $THREADS_PER threads) on physical cores ..."
urls=""; i=0
for node in 0 1; do
    base=$((node * CORES_PER_NODE))
    for j in $(seq 0 $((PER_NODE - 1))); do
        start=$((base + j * THREADS_PER)); end=$((start + THREADS_PER - 1))
        name="${NAME_PREFIX}-${i}"
        launch_instance "$name" "${start}-${end}" "$node" "$THREADS_PER"
        INSTANCE_NAMES+=("$name"); urls="${urls},http://${name}:8080/v1"
        i=$((i + 1))
    done
done
urls="${urls#,}"

log "waiting for instances to load the model ..."
for n in "${INSTANCE_NAMES[@]}"; do wait_up "$n" || { docker logs "$n" 2>&1 | tail -20; die "instance $n failed to come up"; }; done
log "all $INSTANCES instances healthy."

# Client concurrency = 2 in-flight batches per instance so none starve.
CONC=$((INSTANCES * 2))
log "running corpus ingest (bulk embed across $INSTANCES instances -> LanceDB; concurrency=$CONC) ..."
$DC run --rm -e EMBED_URLS="$urls" -e EMBED_CONCURRENCY="$CONC" harness python ingest.py

log "ingest complete."
# cleanup() removes the ingest instances via the EXIT trap.

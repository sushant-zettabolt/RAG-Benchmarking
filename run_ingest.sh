#!/usr/bin/env bash
# Bulk-ingest driver with DATA-PARALLEL embedding.
#
#   ./run_ingest.sh        (or: make ingest)
#
# The embedding model (nomic, 137M) is tiny and does NOT scale well inside a
# single llama.cpp process past ~16-32 threads. So for the one-time corpus ingest
# we spin up N short-lived embed instances, each PINNED to its own block of
# EMBED_INGEST_THREADS_PER CPUs, spread NUMA-locally across both sockets; shard the
# corpus across them (bulk_ingest round-robins request batches over every
# instance), then tear them down. The persistent `llama-embed` used for retrieval
# is left UNTOUCHED — no reconfigure/restore dance.
#
# CPU layout (this 2-socket EPYC 9R14, 96 physical cores + 96 SMT siblings/socket):
#   node0 logical CPUs = 0-95,192-287   node1 logical CPUs = 96-191,288-383
# Each node's FULL logical CPU list is carved into consecutive THREADS_PER-sized
# blocks, one per instance. So EMBED_INGEST_INSTANCES=32 x EMBED_INGEST_THREADS_PER=12
# = 384 = every logical CPU (16 instances/node), SMT siblings included. Set
# EMBED_INGEST_PHYSICAL_ONLY=1 to restrict to physical cores only (no SMT) — note
# embedding is compute-bound, so SMT can help throughput when oversubscribed but
# hurt it when each block already owns whole physical cores; measure on your box.
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

# Data-parallel layout. INSTANCES are split evenly across the NUMA nodes; each
# instance gets THREADS_PER consecutive logical CPUs carved from its node's CPU
# list, with memory bound to that node.
INSTANCES="$(env_get EMBED_INGEST_INSTANCES 32)"
THREADS_PER="$(env_get EMBED_INGEST_THREADS_PER 12)"
PHYSICAL_ONLY="$(env_get EMBED_INGEST_PHYSICAL_ONLY 0)"
CORES_PER_NODE="$(env_get NUMA_CORES_PER_NODE 96)"   # physical cores per socket (PHYSICAL_ONLY)

[ -n "$EMBED_MODEL_PATH" ] || die "EMBED_MODEL_PATH not set in .env"
[ "$IMAGE" ] || die "no baseline image"
case "$INSTANCES"   in ''|*[!0-9]*) die "EMBED_INGEST_INSTANCES must be an integer";; esac
case "$THREADS_PER" in ''|*[!0-9]*) die "EMBED_INGEST_THREADS_PER must be an integer";; esac

# ── NUMA topology ────────────────────────────────────────────────────────────
# NUMA_NODES overrides autodetection (space-separated node ids). Otherwise read
# the kernel's view from /sys.
NUMA_NODES="$(env_get NUMA_NODES '')"
if [ -z "$NUMA_NODES" ]; then
    NUMA_NODES="$(ls -d /sys/devices/system/node/node[0-9]* 2>/dev/null \
                  | sed 's#.*/node##' | sort -n | tr '\n' ' ')"
fi
[ -n "$NUMA_NODES" ] || NUMA_NODES="0"
read -ra NODE_ARR <<< "$NUMA_NODES"
NUM_NODES=${#NODE_ARR[@]}

[ $((INSTANCES % NUM_NODES)) -eq 0 ] \
    || die "EMBED_INGEST_INSTANCES ($INSTANCES) must be divisible by NUMA node count ($NUM_NODES)"
PER_NODE=$((INSTANCES / NUM_NODES))

expand_cpulist() {  # "0-95,192-287" -> "0 1 ... 95 192 ... 287"
    local spec="$1" part lo hi c; local out=(); local parts=()
    IFS=',' read -ra parts <<< "$spec"     # IFS scoped to this read only (no leak)
    for part in "${parts[@]}"; do
        if [[ "$part" == *-* ]]; then
            lo=${part%-*}; hi=${part#*-}
            for ((c = lo; c <= hi; c++)); do out+=("$c"); done
        else
            out+=("$part")
        fi
    done
    echo "${out[*]}"                        # default IFS -> space-joined
}

node_cpus() {  # node -> space-separated logical CPU ids (physical-only if requested)
    local node="$1" list
    list="$(cat "/sys/devices/system/node/node${node}/cpulist" 2>/dev/null || true)"
    [ -n "$list" ] || die "could not read CPU list for NUMA node $node"
    local cpus=( $(expand_cpulist "$list") )
    if [ "$PHYSICAL_ONLY" = "1" ]; then
        cpus=( "${cpus[@]:0:$CORES_PER_NODE}" )   # physical cores come first on this box
    fi
    echo "${cpus[*]}"
}

NAME_PREFIX="${PROJECT}-eingest"
INSTANCE_NAMES=()

# Remove EVERY ingest embed instance matching our name prefix — not just the ones
# this run tracked. A previous run that crashed leaves stale containers holding
# the names, and `docker run --name <existing>` then fails with Error 125.
purge_instances() {  # quiet?
    local stale
    stale="$(docker ps -aq --filter "name=^/${NAME_PREFIX}-" 2>/dev/null)"
    [ -n "$stale" ] || return 0
    [ "${1:-}" = quiet ] || log "removing stale ingest embed instances ..."
    docker rm -f $stale >/dev/null 2>&1 || true
}

cleanup() {
    log "tearing down ${#INSTANCE_NAMES[@]} ingest embed instances ..."
    for n in "${INSTANCE_NAMES[@]:-}"; do [ -n "$n" ] && docker rm -f "$n" >/dev/null 2>&1 || true; done
    purge_instances quiet   # sweep any the array missed
}
trap cleanup EXIT INT TERM

# Pre-flight: clear stale instances from a prior crashed run so name-collisions
# (Error 125) can't happen on launch.
purge_instances

wait_up() {  # name
    for _ in $(seq 1 180); do
        docker run --rm --network "$NET" curlimages/curl -fsS -m2 "http://$1:8080/health" >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

launch_instance() {  # name cpuset_list node threads
    # docker --cpuset-cpus is the hard per-instance boundary (cgroup); numactl
    # --membind keeps memory node-local and --physcpubind mirrors the cpuset.
    # NOTE on threads: llama.cpp links libgomp, so it spawns a large idle OpenMP
    # pool that parks on the master core — `cat /proc/PID/task/*/status` will show
    # most threads pinned to the first cpu of the slice. That is EXPECTED and
    # harmless: the active ggml compute threads spread across the whole slice
    # (verified: all assigned cpus hit ~92% under load). Don't "fix" it.
    docker run -d --rm --name "$1" --network "$NET" --cpuset-cpus "$2" --cap-add SYS_NICE \
        -v "${MODELS_DIR}:/models:ro" --entrypoint /bin/bash "$IMAGE" -c \
        "export OMP_PROC_BIND=close OMP_PLACES=cores; \
         numactl --physcpubind=$2 --membind=$3 /app/llama-server \
           --host 0.0.0.0 --port 8080 --embedding --ctx-size ${EMBED_CTX} \
           --batch-size ${EMBED_INGEST_BATCH} --ubatch-size ${EMBED_INGEST_BATCH} \
           --threads $4 --parallel 1 --metrics --alias embed-model \
           --model ${EMBED_MODEL_PATH}" >/dev/null 2>&1
}

log "launching $INSTANCES data-parallel embed instances ($PER_NODE/node x $THREADS_PER CPUs; physical_only=$PHYSICAL_ONLY) ..."
urls=""; i=0
for node in "${NODE_ARR[@]}"; do
    cpus=( $(node_cpus "$node") )
    navail=${#cpus[@]}
    need=$((PER_NODE * THREADS_PER))
    [ "$need" -le "$navail" ] \
        || die "node $node: PER_NODE*THREADS_PER = $need exceeds $navail available CPUs — lower EMBED_INGEST_INSTANCES/THREADS_PER or unset EMBED_INGEST_PHYSICAL_ONLY"
    for j in $(seq 0 $((PER_NODE - 1))); do
        slice=( "${cpus[@]:$((j * THREADS_PER)):$THREADS_PER}" )
        cpuset="$(IFS=,; echo "${slice[*]}")"
        name="${NAME_PREFIX}-${i}"
        launch_instance "$name" "$cpuset" "$node" "$THREADS_PER"
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

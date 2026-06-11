#!/usr/bin/env bash
# Start (or swap) the embedding llama-server for one job.
# usage: scripts/start_embed.sh <baseline|zendnn> [logfile]
set -eo pipefail
. "$(dirname "$0")/lib.sh"

BUILD="$1"
LOG="${2:-$RESULTS_DIR/embed_${BUILD}.log}"
PID_FILE="$RESULTS_DIR/embed.pid"

case "$BUILD" in
    baseline)
        BIN="$LLAMA_BUILD_BASELINE/bin/llama-server"
        LIBPATH="$LLAMA_BUILD_BASELINE/bin"
        JOB_ENV=()
        ;;
    zendnn)
        BIN="$LLAMA_BUILD_ZENDNN/bin/llama-server"
        LIBPATH="$LLAMA_BUILD_ZENDNN/bin:$ZENDNN_LIB"
        JOB_ENV=($ZENDNN_ENV)
        ;;
    *) die "usage: start_embed.sh <baseline|zendnn> [logfile]" ;;
esac
[ -x "$BIN" ] || die "$BIN not found — run scripts/build_llama.sh first"
[ -f "$EMBED_MODEL" ] || die "EMBED_MODEL not found: $EMBED_MODEL"

kill_pidfile "$PID_FILE"
sleep 2

NUMA=()
if [ -n "$EMBED_CPUS" ]; then
    NUMA=(numactl --physcpubind="$EMBED_CPUS")
    if [ -n "$EMBED_MEMBIND" ]; then NUMA+=(--membind="$EMBED_MEMBIND"); fi
fi

env "${JOB_ENV[@]}" LD_LIBRARY_PATH="$LIBPATH" \
    "${NUMA[@]}" "$BIN" \
    --model "$EMBED_MODEL" \
    --embedding \
    --port "$EMBED_PORT" --host 127.0.0.1 \
    -t "$THREADS" -c "$EMBED_CTX" -b "$EMBED_BATCH" -ub "$EMBED_UBATCH" \
    $EXTRA_LLAMA_FLAGS \
    > "$LOG" 2>&1 &
echo $! > "$PID_FILE"

# poll a real embedding request until the model is loaded (up to 120s)
for i in $(seq 1 24); do
    sleep 5
    if curl -s -m 15 "http://127.0.0.1:$EMBED_PORT/v1/embeddings" \
         -H 'Content-Type: application/json' \
         -d '{"input":"hello","model":"local-embed"}' 2>/dev/null \
         | grep -q '"embedding"'; then
        log "embed server ($BUILD) up after $((i*5))s  [$(basename "$EMBED_MODEL")]"
        exit 0
    fi
done
echo "EMBED SERVER DOWN"; tail -30 "$LOG"; exit 1

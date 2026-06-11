#!/usr/bin/env bash
# Start (or swap) the chat llama-server for one job.
# usage: scripts/start_chat.sh <baseline|zendnn> [logfile]
set -eo pipefail
. "$(dirname "$0")/lib.sh"

BUILD="$1"
LOG="${2:-$RESULTS_DIR/chat_${BUILD}.log}"
PID_FILE="$RESULTS_DIR/chat.pid"

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
    *) die "usage: start_chat.sh <baseline|zendnn> [logfile]" ;;
esac
[ -x "$BIN" ] || die "$BIN not found — run scripts/build_llama.sh first"
[ -f "$CHAT_MODEL" ] || die "CHAT_MODEL not found: $CHAT_MODEL"

kill_pidfile "$PID_FILE"
sleep 2

NUMA=()
if [ -n "$CHAT_CPUS" ]; then
    NUMA=(numactl --physcpubind="$CHAT_CPUS")
    if [ -n "$CHAT_MEMBIND" ]; then NUMA+=(--membind="$CHAT_MEMBIND"); fi
fi

env "${JOB_ENV[@]}" LD_LIBRARY_PATH="$LIBPATH" \
    "${NUMA[@]}" "$BIN" \
    --model "$CHAT_MODEL" \
    --port "$CHAT_PORT" --host 127.0.0.1 \
    -t "$THREADS" -c "$CHAT_CTX" -b "$CHAT_BATCH" -ub "$CHAT_UBATCH" \
    $EXTRA_LLAMA_FLAGS \
    > "$LOG" 2>&1 &
echo $! > "$PID_FILE"

# poll a real completion, not /v1/models (which answers before weights load);
# up to 300s — large BF16 models (e.g. Mixtral 87GB with --no-mmap) load slowly
for i in $(seq 1 60); do
    sleep 5
    if curl -s -m 30 "http://127.0.0.1:$CHAT_PORT/v1/chat/completions" \
         -H 'Content-Type: application/json' \
         -d '{"model":"local-chat","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' 2>/dev/null \
         | grep -q '"choices"'; then
        log "chat server ($BUILD) up after $((i*5))s  [$(basename "$CHAT_MODEL")]"
        exit 0
    fi
done
echo "CHAT SERVER DOWN"; tail -50 "$LOG"; exit 1

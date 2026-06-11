#!/usr/bin/env bash
# Start the LiteLLM proxy (routes chat-model/embed-model to llama-servers,
# emits Prometheus metrics). Backends should be up first or the health
# check below will fail.
# usage: scripts/start_litellm.sh
set -eo pipefail
. "$(dirname "$0")/lib.sh"

PID_FILE="$RESULTS_DIR/litellm.pid"
LOG="$RESULTS_DIR/litellm.log"

command -v "$LITELLM_BIN" >/dev/null || die "litellm not found ($LITELLM_BIN) — pip install 'litellm[proxy]'"

render_conf
kill_pidfile "$PID_FILE"
sleep 1

"$LITELLM_BIN" --config "$BASE/conf/litellm.yaml" --port "$LITELLM_PORT" > "$LOG" 2>&1 &
echo $! > "$PID_FILE"

# both models must be healthy — embed-model unhealthy silently breaks RAG
# (AnythingLLM returns textResponse=None)
for i in $(seq 1 12); do
    sleep 5
    H=$(curl -s -m 10 "http://127.0.0.1:$LITELLM_PORT/health" \
            -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null) || continue
    if echo "$H" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ok = len(d.get('healthy_endpoints', [])) >= 2 and not d.get('unhealthy_endpoints')
sys.exit(0 if ok else 1)" 2>/dev/null; then
        log "litellm up after $((i*5))s — both models healthy"
        exit 0
    fi
done
echo "LITELLM UNHEALTHY"; curl -s "http://127.0.0.1:$LITELLM_PORT/health" -H "Authorization: Bearer $LITELLM_MASTER_KEY"; tail -30 "$LOG"; exit 1

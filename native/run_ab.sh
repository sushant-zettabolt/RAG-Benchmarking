#!/usr/bin/env bash
# Native ZenDNN A/B: evaluate the SAME pipeline with the baseline chat build, then
# the ZenDNN build, then emit report_ab. Mirrors the Docker run_ab.sh but swaps the
# chat llama-server PROCESS (baseline binary <-> build_zendnn binary) instead of a
# container image. Jobs run strictly sequentially — one chat server at a time.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$NATIVE/services.sh"

is_running anythingllm || die "stack not up — run: native/up.sh"
[ -f "$DATA/eval.jsonl" ] || die "no ingested data — run: native/ingest.sh"
[ -x "$LLAMA_ZENDNN_BIN" ] || die "zendnn build missing: $LLAMA_ZENDNN_BIN"

JOB_A="${JOB_A:-baseline}"; JOB_B="${JOB_B:-zendnn}"
FIXED="${AB_FIXED_DECODE:-}"

gen_configs   # litellm chat-model-bench carries n_predict=$AB_FIXED_DECODE

# Fixed-decode mode: point AnythingLLM at the chat-model-bench route so both
# backends emit exactly N decode tokens (directly comparable prefill/decode).
if [ -n "$FIXED" ]; then
    log "fixed-decode ON ($FIXED tokens/query) — re-seeding allm → chat-model-bench"
    stop_bg litellm; start_litellm
    wait_http litellm "http://127.0.0.1:${LITELLM_PORT}/health/readiness" 90
    seed_allm chat-model-bench
    stop_bg anythingllm; start_anythingllm chat-model-bench
    wait_http anythingllm "http://127.0.0.1:${ALLM_PORT}/api/ping" 120
fi

WARMUP_PROMPT="$(printf 'The quick brown fox jumps over the lazy dog. %.0s' $(seq 1 80))"
warmup_chat() {
    log "warming up chat server ..."
    for _ in 1 2 3; do
        curl -fsS -m 300 "http://127.0.0.1:${CHAT_PORT}/v1/chat/completions" \
            -H 'Content-Type: application/json' \
            -d "{\"model\":\"chat-model\",\"messages\":[{\"role\":\"user\",\"content\":\"$WARMUP_PROMPT\"}],\"max_tokens\":16,\"temperature\":0}" \
            >/dev/null 2>&1 || true
    done
}
warmup_embed() {
    for _ in 1 2; do
        curl -fsS -m 30 "http://127.0.0.1:${EMBED_PORT}/v1/embeddings" -H 'Content-Type: application/json' \
            -d '{"input":"Warmup query for embedding server.","model":"embed-model"}' >/dev/null 2>&1 || true
    done
}

run_job() {  # job binary algo
    local job="$1" bin="$2" algo="$3"
    log "════ job '$job' (binary=$bin algo=${algo:-none}) ════"
    stop_bg llama-chat
    start_chat "$bin" "$algo"
    wait_http "chat ($job)" "http://127.0.0.1:${CHAT_PORT}/health" 240 \
        || { tail -30 "$(logfile llama-chat)"; die "chat ($job) did not come up"; }
    grep -iE 'zendnn|backend|load_tensors' "$(logfile llama-chat)" | head -3 || true
    warmup_chat
    export_harness_env
    ( cd "$BASE/src" && JOB="$job" "$HARNESS_PY" evaluate.py )
}

warmup_embed
run_job "$JOB_A" "$LLAMA_BASELINE_BIN" ""
run_job "$JOB_B" "$LLAMA_ZENDNN_BIN"   "$ZENDNNL_MATMUL_ALGO"

log "generating comparison report ..."
export_harness_env
( cd "$BASE/src" && JOB_A="$JOB_A" JOB_B="$JOB_B" "$HARNESS_PY" report_ab.py )
log "✅ A/B done → ${DATA#$BASE/}/results/report_ab.md (+ report_ab.json)"

# Restore chat to baseline (and the natural model route if we changed it).
log "restoring baseline chat server ..."
stop_bg llama-chat; start_chat
if [ -n "$FIXED" ]; then
    seed_allm chat-model
    stop_bg anythingllm; start_anythingllm chat-model
    wait_http anythingllm "http://127.0.0.1:${ALLM_PORT}/api/ping" 120 || true
fi

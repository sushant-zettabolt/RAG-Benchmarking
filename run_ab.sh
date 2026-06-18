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

env_get() { local v; v="$(grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*//' | xargs)"; [ -z "$v" ] && echo "$2" || echo "$v"; }
log() { echo "[run_ab] $*"; }
die() { echo "[run_ab] ERROR: $*" >&2; exit 1; }

[ -f .env ] || die "no .env — run ./setup.sh first"
CHAT_PORT="$(env_get CHAT_PORT 8081)"
EMBED_PORT="$(env_get EMBED_PORT 8082)"
ALLM_PORT="$(env_get ALLM_PORT 3001)"
LITELLM_PORT="$(env_get LITELLM_PORT 4000)"
PUSHGW_PORT="$(env_get PUSHGW_PORT 9091)"
SLUG="$(env_get SLUG nq-bench)"
ALLM_KEY="$(env_get ALLM_KEY '')"
CHAT_MODEL_PATH="$(env_get CHAT_MODEL_PATH '')"

# A/B knobs (override in .env). Default to the two build trees produced by
# scripts/build_llama.sh under ./llama.cpp — no machine-specific paths.
AB_BASELINE_BINDIR="$(env_get AB_BASELINE_BINDIR "$PWD/llama.cpp/build/bin")"
AB_ZENDNN_BINDIR="$(env_get AB_ZENDNN_BINDIR "$PWD/llama.cpp/build_zendnn/bin")"
# ZenDNN runtime lib dir. Leave empty (default) to auto-discover it from the
# zendnn binary's own linkage (its RPATH already points at libzendnnl.so), so
# nothing has to be hand-configured. Only set this if the .so isn't on the
# binary's RPATH and isn't in the system linker cache.
AB_ZENDNN_LIBDIR="$(env_get AB_ZENDNN_LIBDIR "")"
AB_ZENDNN_ALGO="$(env_get AB_ZENDNN_ALGO "1")"
# Fixed-decode mode: set AB_FIXED_DECODE=<N> (in .env or env) to force EVERY query
# to emit exactly N decode tokens on BOTH backends (ignore_eos + n_predict=N),
# so prefill+decode work is identical and latency is directly comparable. Empty =
# off (natural generation, quality-meaningful). Quality judging is skipped when on.
AB_FIXED_DECODE="$(env_get AB_FIXED_DECODE "")"
LITELLM_YAML="conf/litellm.yaml"
JOB_A="${JOB_A:-baseline}"
JOB_B="${JOB_B:-zendnn}"

# ── preconditions ────────────────────────────────────────────────────────────
[ -n "$ALLM_KEY" ] || die "ALLM_KEY empty — run ./setup.sh first"
[ -n "$CHAT_MODEL_PATH" ] || die "CHAT_MODEL_PATH must point at a local GGUF for the A/B (set it in .env)"
if [ ! -x "$AB_BASELINE_BINDIR/llama-server" ] || [ ! -x "$AB_ZENDNN_BINDIR/llama-server" ]; then
    die "llama-server binaries not found under ./llama.cpp — build them first: scripts/build_llama.sh"
fi
# Auto-discover the ZenDNN runtime lib dir from the zendnn binary itself (its
# RPATH already resolves libzendnnl.so), so no path needs to be hand-configured.
if [ -z "$AB_ZENDNN_LIBDIR" ]; then
    AB_ZENDNN_LIBDIR="$(ldd "$AB_ZENDNN_BINDIR/llama-server" 2>/dev/null \
        | awk '/libzendnnl/ {print $3}' | head -1 | xargs -r dirname || true)"
    [ -n "$AB_ZENDNN_LIBDIR" ] && log "auto-discovered ZenDNN lib dir: $AB_ZENDNN_LIBDIR"
fi
if [ -n "$AB_ZENDNN_LIBDIR" ] && [ ! -e "$AB_ZENDNN_LIBDIR/libzendnnl.so" ]; then
    die "libzendnnl.so not found in AB_ZENDNN_LIBDIR=$AB_ZENDNN_LIBDIR (the zendnn binary links it at load time)"
fi

wait_for() {  # name url tries
    echo -n "[run_ab] waiting for $1 "
    for _ in $(seq 1 "${3:-120}"); do
        if curl -fsS -m 5 "$2" >/dev/null 2>&1; then echo " up"; return 0; fi
        echo -n "."; sleep 5
    done
    echo " TIMEOUT"; return 1
}

log "ensuring all services are up (chat + embed + support) ..."
$DC_BASE up -d llama-chat llama-embed litellm prometheus pushgateway anythingllm >/dev/null 2>&1
[ -f data/ingest_metadata.json ] || die "no ingested data — run: make ingest"

wait_for "llama-chat"  "http://localhost:${CHAT_PORT}/health"  240
wait_for "llama-embed" "http://localhost:${EMBED_PORT}/health" 120
wait_for "litellm"     "http://localhost:${LITELLM_PORT}/health/readiness" 60
wait_for "anythingllm" "http://localhost:${ALLM_PORT}/api/ping" 60

# Self-heal: sync ALLM_KEY from the DB in case it drifted (e.g. after a volume
# wipe + re-setup). docker restart in allm_set_model also triggers key drift.
db_key=$(docker exec nqrag-anythingllm python3 -c "
import sqlite3
conn = sqlite3.connect('/app/server/storage/anythingllm.db')
row = conn.execute('SELECT secret FROM api_keys LIMIT 1').fetchone()
print(row[0] if row else '')
conn.close()
" 2>/dev/null || true)
if [ -n "$db_key" ] && [ "$db_key" != "$ALLM_KEY" ]; then
    log "ALLM_KEY drift detected — syncing .env and reloading ($ALLM_KEY → $db_key)"
    sed -i "s|^ALLM_KEY=.*|ALLM_KEY=${db_key}|" .env
    ALLM_KEY="$db_key"
fi

log "all services healthy — embed server stays up for the entire run"

# ── fixed-decode mode ────────────────────────────────────────────────────────
# Point AnythingLLM at the `chat-model-bench` LiteLLM model (ignore_eos +
# n_predict=N) so both backends emit exactly N decode tokens. Restored on exit.
DOJUDGE_ARGS=""
BENCH_ACTIVE=0
AB_KEEP_RUNNING="${AB_KEEP_RUNNING:-0}"
restore_and_stop() {
    if [ "$BENCH_ACTIVE" = "1" ]; then
        log "restoring litellm.yaml ..."
        [ -f "$LITELLM_YAML.abbak" ] && mv -f "$LITELLM_YAML.abbak" "$LITELLM_YAML"
        BENCH_ACTIVE=0
    fi
    if [ "$AB_KEEP_RUNNING" = "1" ]; then
        log "AB_KEEP_RUNNING=1 — leaving containers up for next model."
    else
        log "stopping all containers ..."
        $DC_AB down >/dev/null 2>&1 || true
        $DC_BASE down >/dev/null 2>&1 || true
        log "all containers stopped."
    fi
}
trap restore_and_stop EXIT INT TERM

allm_set_model() {  # model_name — update AnythingLLM's LLM model preference in its DB
    docker exec nqrag-anythingllm python3 -c "
import sqlite3
conn = sqlite3.connect('/app/server/storage/anythingllm.db')
for label in ('GenericOpenAiModelPref', 'LLMPreference'):
    conn.execute('UPDATE system_settings SET value=? WHERE label=?', ('$1', label))
conn.commit(); conn.close(); print('allm model →', '$1')
"
    docker restart nqrag-anythingllm >/dev/null 2>&1
    wait_for "anythingllm" "http://localhost:${ALLM_PORT}/api/ping" 60
}

enable_fixed_decode() {  # N
    local n="$1"
    case "$n" in ''|*[!0-9]*) die "AB_FIXED_DECODE must be a positive integer, got '$n'";; esac
    [ "$n" -gt 0 ] || die "AB_FIXED_DECODE must be > 0"
    log "════ fixed-decode mode ON: forcing exactly $n decode tokens/query on both backends ════"
    cp -f "$LITELLM_YAML" "$LITELLM_YAML.abbak"
    BENCH_ACTIVE=1
    sed -i -E "s/^([[:space:]]*n_predict:[[:space:]]*)[0-9]+/\1$n/" "$LITELLM_YAML"
    $DC_BASE restart litellm >/dev/null 2>&1
    wait_for "litellm" "http://localhost:${LITELLM_PORT}/health/readiness" 30 || true
    allm_set_model "chat-model-bench"
    DOJUDGE_ARGS=""   # judge runs even in fixed-decode mode
}

# Direct warmup: send a 512+ token prompt straight to llama-server (bypasses the
# RAG pipeline) so ZenDNN JIT-compiles its kernels before any measured work.
# Repeats WARMUP_ROUNDS times to stabilise. Prompt is ~600 tokens of filler.
WARMUP_ROUNDS="${WARMUP_ROUNDS:-3}"
WARMUP_PROMPT="$(printf 'The quick brown fox jumps over the lazy dog. %.0s' $(seq 1 80))"
warmup_chat() {  # job
    local job="$1"
    log "warming up chat server ($job) — $WARMUP_ROUNDS rounds, ~600 tokens each ..."
    for i in $(seq 1 "$WARMUP_ROUNDS"); do
        local t0=$(date +%s%N)
        curl -fsS -m 300 "http://localhost:${CHAT_PORT}/v1/chat/completions" \
            -H 'Content-Type: application/json' \
            -d "{\"model\":\"chat-model\",\"messages\":[{\"role\":\"user\",\"content\":\"$WARMUP_PROMPT\"}],\"max_tokens\":16,\"temperature\":0}" >/dev/null 2>&1
        local t1=$(date +%s%N)
        local ms=$(( (t1 - t0) / 1000000 ))
        log "  warmup $i/$WARMUP_ROUNDS done (${ms}ms)"
    done
}

# Push the current backend name to Pushgateway so Grafana can display it.
push_backend() {  # name   (e.g. "baseline", "zendnn", "idle")
    printf 'ab_backend_active{backend="%s"} 1\n' "$1" \
        | curl -fsS -m 5 --data-binary @- \
          "http://localhost:${PUSHGW_PORT}/metrics/job/ab_bench" 2>/dev/null || true
}

# Verify the prompt cache is actually disabled for the freshly-swapped backend
# BEFORE spending ~15 min on the eval. Sends the SAME question twice through the
# real eval path (AnythingLLM stream-chat) and compares the chat server's
# prompt_tokens_total delta. With cache_prompt:false honored end-to-end both
# deltas are ~equal (full reprocess each time). If the 2nd delta collapses, the
# slot KV is being reused → the per-query prefill numbers would be inflated and
# prompt_tokens would diverge from the other job (the bug we are guarding).
chat_ptok() { curl -fsS -m 10 "http://localhost:${CHAT_PORT}/metrics" 2>/dev/null \
    | awk '/^llamacpp:prompt_tokens_total/{print $2}'; }
verify_cache_disabled() {  # job
    local job="$1" q='When was the last time anyone was on the moon?' b1 a1 b2 a2 d1 d2
    # Use a FRESH AnythingLLM session per call so neither request carries chat
    # history — both then send an identical prompt to llama-server, isolating the
    # server-side KV-cache-reuse signal we're probing (history carryover would
    # otherwise change call 2's prompt and confound the delta comparison).
    local s1="cacheprobe-${job}-$$-a" s2="cacheprobe-${job}-$$-b"
    b1="$(chat_ptok)"
    curl -fsS -m 600 "http://localhost:${ALLM_PORT}/api/v1/workspace/${SLUG}/stream-chat" \
        -H "Authorization: Bearer ${ALLM_KEY}" -H 'Content-Type: application/json' \
        -d "{\"message\":\"$q\",\"mode\":\"query\",\"sessionId\":\"$s1\"}" >/dev/null 2>&1 || true
    a1="$(chat_ptok)"
    b2="$(chat_ptok)"
    curl -fsS -m 600 "http://localhost:${ALLM_PORT}/api/v1/workspace/${SLUG}/stream-chat" \
        -H "Authorization: Bearer ${ALLM_KEY}" -H 'Content-Type: application/json' \
        -d "{\"message\":\"$q\",\"mode\":\"query\",\"sessionId\":\"$s2\"}" >/dev/null 2>&1 || true
    a2="$(chat_ptok)"
    d1=$(awk "BEGIN{print $a1-$b1}"); d2=$(awk "BEGIN{print $a2-$b2}")
    # ratio of the smaller to larger delta; ~1.0 = cache disabled, ~0 = reuse
    local ratio; ratio=$(awk "BEGIN{lo=($d1<$d2?$d1:$d2); hi=($d1>$d2?$d1:$d2); print (hi>0)?lo/hi:0}")
    log "cache-probe '$job': prompt_tokens delta call1=$d1 call2=$d2 (ratio=$ratio)"
    awk "BEGIN{exit !($ratio>0.9)}" \
        || log "⚠️  WARNING: prompt cache appears ACTIVE for '$job' (2nd request reprocessed far fewer tokens). prompt_tokens/prefill numbers may be inflated and will NOT match the other job."
}

run_job() {  # job bindir libdir algo
    local job="$1" bindir="$2" libdir="$3" algo="$4"
    log "════ job '$job': swapping chat backend (bindir=$bindir algo=${algo:-unset}) ════"
    # Only recreate llama-chat. The embed server stays untouched (always baseline
    # binary, started by the $DC_BASE up earlier) — avoids the 501 race where a
    # restarting embed server briefly rejects embedding requests.
    # EMBED_BINDIR is passed for compose-file validation only; embed is NOT recreated.
    CHAT_BINDIR="$bindir" CHAT_LIBDIR="${libdir:-$bindir}" \
        EMBED_BINDIR="$AB_BASELINE_BINDIR" EMBED_LIBDIR="$AB_BASELINE_BINDIR" \
        ZENDNNL_MATMUL_ALGO="$algo" AB_JOB="$job" \
        $DC_AB up -d --force-recreate --no-deps llama-chat >/dev/null 2>&1
    wait_for "chat ($job)" "http://localhost:${CHAT_PORT}/health" 120 \
        || { $DC_AB logs --tail 40 llama-chat; die "chat server ($job) did not come up"; }
    docker logs nqrag-llama-chat 2>&1 | grep -iE 'zendnn|backend' | head -3 || true
    warmup_chat "$job"
    verify_cache_disabled "$job"
    push_backend "$job"
    log "evaluating job '$job' ..."
    $DC_BASE run --rm -e JOB="$job" $DOJUDGE_ARGS harness python evaluate.py
    push_backend "idle"
}

[ -n "$AB_FIXED_DECODE" ] && enable_fixed_decode "$AB_FIXED_DECODE"

run_job "$JOB_A" "$AB_BASELINE_BINDIR" "$AB_BASELINE_BINDIR" ""
run_job "$JOB_B" "$AB_ZENDNN_BINDIR"   "$AB_ZENDNN_LIBDIR"   "$AB_ZENDNN_ALGO"

log "generating comparison report ..."
$DC_BASE run --rm -e JOB_A="$JOB_A" -e JOB_B="$JOB_B" harness python report_ab.py

log "✅ done. Report: data/results/report_ab.md (+ report_ab.json)"

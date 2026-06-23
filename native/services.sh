#!/usr/bin/env bash
# Service definitions for the native stack: how each process is launched, the
# localhost config files they need (generated from config.env), AnythingLLM
# seeding, and the start/stop/health orchestration. Sourced after lib.sh.

ALLM_DIR="${RUNTIME}/anythingllm"
CONF_GEN="${RUNTIME}/conf"

# ── generated localhost configs ──────────────────────────────────────────────
gen_configs() {
    mkdir -p "$CONF_GEN" "$CONF_GEN/grafana-provisioning/datasources" \
             "$CONF_GEN/grafana-provisioning/dashboards"

    # LiteLLM: same model routes as conf/litellm.yaml but api_base -> localhost.
    cat > "$CONF_GEN/litellm.yaml" <<EOF
model_list:
  - model_name: chat-model
    litellm_params:
      model: openai/chat-model
      api_base: http://127.0.0.1:${CHAT_PORT}/v1
      api_key: "sk-noauth"
      extra_body:
        cache_prompt: false
  - model_name: chat-model-bench
    litellm_params:
      model: openai/chat-model
      api_base: http://127.0.0.1:${CHAT_PORT}/v1
      api_key: "sk-noauth"
      extra_body:
        cache_prompt: false
        ignore_eos: true
        n_predict: ${AB_FIXED_DECODE:-128}
  - model_name: judge-model
    litellm_params:
      model: openai/chat-model
      api_base: http://127.0.0.1:${CHAT_PORT}/v1
      api_key: "sk-noauth"
  - model_name: embed-model
    litellm_params:
      model: openai/embed-model
      api_base: http://127.0.0.1:${EMBED_PORT}/v1
      api_key: "sk-noauth"
    model_info:
      mode: embedding

litellm_settings:
  callbacks: ["prometheus"]
  drop_params: true
  require_auth_for_metrics_endpoint: false

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
EOF

    # Prometheus: scrape the localhost services.
    cat > "$CONF_GEN/prometheus.yml" <<EOF
global:
  scrape_interval: 5s
scrape_configs:
  - job_name: litellm
    metrics_path: /metrics/
    authorization:
      credentials: ${LITELLM_MASTER_KEY}
    static_configs:
      - targets: ['127.0.0.1:${LITELLM_PORT}']
  - job_name: llamacpp_chat
    static_configs:
      - targets: ['127.0.0.1:${CHAT_PORT}']
  - job_name: llamacpp_embed
    static_configs:
      - targets: ['127.0.0.1:${EMBED_PORT}']
  - job_name: pushgateway
    honor_labels: true
    static_configs:
      - targets: ['127.0.0.1:${PUSHGW_PORT}']
EOF

    # Grafana provisioning: datasource -> localhost Prometheus; dashboards from repo.
    cat > "$CONF_GEN/grafana-provisioning/datasources/ds.yaml" <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:${PROM_PORT}
    isDefault: true
    editable: true
    jsonData:
      timeInterval: 5s
EOF
    cat > "$CONF_GEN/grafana-provisioning/dashboards/dash.yaml" <<EOF
apiVersion: 1
providers:
  - name: rag
    type: file
    allowUiUpdates: true
    options:
      path: ${BASE}/conf/grafana/dashboards
EOF
}

# ── per-service launchers ────────────────────────────────────────────────────
start_chat() {  # [binary] [algo]   defaults: baseline, no algo
    local bin="${1:-$LLAMA_BASELINE_BIN}" algo="${2:-}"
    [ -x "$bin" ] || die "chat llama-server binary not found/executable: $bin"
    [ -f "$CHAT_MODEL_PATH" ] || die "CHAT_MODEL_PATH missing: $CHAT_MODEL_PATH"
    local env="OMP_PROC_BIND=close OMP_PLACES=cores"
    [ -n "$ZENDNN_LIB" ] && env="$env LD_LIBRARY_PATH='$ZENDNN_LIB':\${LD_LIBRARY_PATH:-}"
    [ -n "$algo" ]       && env="$env ZENDNNL_MATMUL_ALGO=$algo"
    local pre; pre="$(numa_prefix "$CHAT_CPUS" "$CHAT_MEMBIND")"
    start_bg llama-chat \
        "exec env $env $pre '$bin' --host 127.0.0.1 --port $CHAT_PORT \
         --ctx-size $CHAT_CTX --n-gpu-layers $CHAT_NGL --parallel 1 --metrics \
         --alias chat-model --model '$CHAT_MODEL_PATH' --threads $CHAT_THREADS $CHAT_EXTRA_FLAGS"
}

start_embed() {
    [ -x "$LLAMA_BASELINE_BIN" ] || die "embed llama-server binary not found: $LLAMA_BASELINE_BIN"
    [ -f "$EMBED_MODEL_PATH" ] || die "EMBED_MODEL_PATH missing: $EMBED_MODEL_PATH"
    local pre; pre="$(numa_prefix "$EMBED_CPUS" "$EMBED_MEMBIND")"
    start_bg llama-embed \
        "exec env OMP_PROC_BIND=close OMP_PLACES=cores $pre '$LLAMA_BASELINE_BIN' \
         --host 127.0.0.1 --port $EMBED_PORT --embedding --ctx-size $EMBED_CTX \
         --batch-size $EMBED_BATCH --ubatch-size $EMBED_UBATCH --n-gpu-layers 0 --metrics \
         --alias embed-model --model '$EMBED_MODEL_PATH' --threads $EMBED_THREADS $EMBED_EXTRA_FLAGS"
}

start_litellm() {
    command -v litellm >/dev/null || die "litellm not on PATH (pip install --user litellm[proxy])"
    start_bg litellm \
        "exec env LITELLM_MASTER_KEY='$LITELLM_MASTER_KEY' litellm \
         --config '$CONF_GEN/litellm.yaml' --port $LITELLM_PORT --host 127.0.0.1"
}

start_anythingllm() {  # model_pref defaults to chat-model
    local pref="${1:-chat-model}"
    [ -f "$ALLM_DIR/server/index.js" ] || die "AnythingLLM not built — run native/setup.sh"
    local storage="$ALLM_DIR/server/storage"; mkdir -p "$storage"
    start_bg anythingllm \
        "cd '$ALLM_DIR/server' && exec env NODE_ENV=production STORAGE_DIR='$storage' \
         SERVER_PORT=$ALLM_PORT DISABLE_TELEMETRY=true VECTOR_DB=lancedb \
         JWT_SECRET='${ALLM_JWT:-bench-jwt-secret-change-me}' \
         SIG_KEY='${ALLM_SIG_KEY:-bench-sig-key-please-change-me-32}' \
         SIG_SALT='${ALLM_SIG_SALT:-bench-sig-salt-please-change-me-32}' \
         LLM_PROVIDER=generic-openai \
         GENERIC_OPEN_AI_BASE_PATH='http://127.0.0.1:$LITELLM_PORT/v1' \
         GENERIC_OPEN_AI_API_KEY='$LITELLM_MASTER_KEY' \
         GENERIC_OPEN_AI_MODEL_PREF='$pref' GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT=$CHAT_CTX \
         EMBEDDING_ENGINE=generic-openai EMBEDDING_BASE_PATH='http://127.0.0.1:$LITELLM_PORT/v1' \
         GENERIC_OPEN_AI_EMBEDDING_API_KEY='$LITELLM_MASTER_KEY' EMBEDDING_MODEL_PREF=embed-model \
         EMBEDDING_MODEL_MAX_CHUNK_LENGTH=$EMBED_MAX_CHUNK_CHARS \
         COLLECTOR_PORT=$ALLM_COLLECTOR_PORT node index.js"
}

start_collector() {
    [ -f "$ALLM_DIR/collector/index.js" ] || die "AnythingLLM collector not built"
    start_bg collector \
        "cd '$ALLM_DIR/collector' && exec env NODE_ENV=production STORAGE_DIR='$ALLM_DIR/server/storage' \
         SERVER_PORT=$ALLM_COLLECTOR_PORT node index.js"
}

start_prometheus() {
    [ -x "$RUNTIME/prometheus/prometheus" ] || { log "prometheus not installed — skipping (viz only)"; return 0; }
    start_bg prometheus \
        "exec '$RUNTIME/prometheus/prometheus' --config.file='$CONF_GEN/prometheus.yml' \
         --storage.tsdb.path='$RUNTIME/promdata' --web.listen-address=127.0.0.1:$PROM_PORT"
}

start_pushgateway() {
    [ -x "$RUNTIME/pushgateway/pushgateway" ] || { log "pushgateway not installed — skipping"; return 0; }
    start_bg pushgateway \
        "exec '$RUNTIME/pushgateway/pushgateway' --web.listen-address=127.0.0.1:$PUSHGW_PORT"
}

start_grafana() {
    [ -x "$RUNTIME/grafana/bin/grafana" ] || { log "grafana not installed — skipping (viz only)"; return 0; }
    start_bg grafana \
        "cd '$RUNTIME/grafana' && exec env \
         GF_SERVER_HTTP_ADDR=127.0.0.1 GF_SERVER_HTTP_PORT=$GRAFANA_PORT \
         GF_PATHS_DATA='$RUNTIME/grafana-data' GF_PATHS_LOGS='$LOGS' \
         GF_PATHS_PROVISIONING='$CONF_GEN/grafana-provisioning' \
         GF_AUTH_ANONYMOUS_ENABLED=true GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
         GF_SECURITY_ADMIN_PASSWORD=admin GF_USERS_DEFAULT_THEME=light \
         GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH='$BASE/conf/grafana/dashboards/rag-flow.json' \
         ./bin/grafana server --homepath '$RUNTIME/grafana'"
}

# ── AnythingLLM seeding (API key + provider/chunk settings into the SQLite DB) ─
seed_allm() {  # model_pref defaults to chat-model
    local pref="${1:-chat-model}"
    [ -f "$ALLM_DB" ] || die "AnythingLLM DB not found at $ALLM_DB (setup must run prisma migrate)"
    ALLM_DB="$ALLM_DB" ALLM_KEY="$ALLM_KEY" LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" \
    CHAT_CTX="$CHAT_CTX" EMBED_CHUNK_WORDS="$EMBED_CHUNK_WORDS" \
    EMBED_CHUNK_OVERLAP_WORDS="$EMBED_CHUNK_OVERLAP_WORDS" \
    ALLM_LITELLM_BASE="http://127.0.0.1:${LITELLM_PORT}/v1" \
    ALLM_MODEL_PREF="$pref" \
    "$HARNESS_PY" "$BASE/scripts/seed_anythingllm.py"
}

# Sync retrieval topN / similarity threshold into the workspace (matches run_ab.sh).
sync_retrieval() {
    curl -fsS -m 30 "http://127.0.0.1:${ALLM_PORT}/api/v1/workspace/${SLUG}/update" \
        -H "Authorization: Bearer ${ALLM_KEY}" -H 'Content-Type: application/json' \
        -d "{\"topN\":${RETRIEVAL_TOPN},\"similarityThreshold\":${RETRIEVAL_SIM_THRESHOLD}}" \
        >/dev/null 2>&1 && log "synced retrieval topN=$RETRIEVAL_TOPN" \
        || log "WARNING: could not sync retrieval settings (workspace may not exist yet)"
}

# ── health waits ─────────────────────────────────────────────────────────────
wait_core() {
    wait_http "llama-chat"  "http://127.0.0.1:${CHAT_PORT}/health"  240 || return 1
    wait_http "llama-embed" "http://127.0.0.1:${EMBED_PORT}/health" 120 || return 1
    wait_http "litellm"     "http://127.0.0.1:${LITELLM_PORT}/health/readiness" 90 || return 1
    wait_http "anythingllm" "http://127.0.0.1:${ALLM_PORT}/api/ping" 120 || return 1
}

stop_all() {
    for s in grafana prometheus pushgateway collector anythingllm litellm llama-embed llama-chat; do
        stop_bg "$s"
    done
}

# ── harness env (the src/*.py tools read everything from env, same as Docker) ──
export_harness_env() {
    export ALLM_URL="http://127.0.0.1:${ALLM_PORT}"
    export LITELLM_URL="http://127.0.0.1:${LITELLM_PORT}"
    export PROM_URL="http://127.0.0.1:${PROM_PORT}"
    export CHAT_METRICS_URL="http://127.0.0.1:${CHAT_PORT}/metrics"
    export EMBED_METRICS_URL="http://127.0.0.1:${EMBED_PORT}/metrics"
    export ALLM_KEY LITELLM_MASTER_KEY SLUG EVAL_DATASET CORPUS_DATASET
    export DOC_N EVAL_N CORPUS_SCAN QUERY_MODE JUDGE_MODEL JUDGE_THRESHOLD
    export JUDGE_BASE_URL JUDGE_API_KEY WARMUP EVAL_LIMIT DOC_TARGET_TOKENS
    export RETRIEVAL_TOPN RETRIEVAL_SIM_THRESHOLD
    export DATA_DIR="$DATA" HF_HOME="${HF_HOME:-$DATA/hf-cache}"
    # bulk ingest: write vectors straight into AnythingLLM's LanceDB (same user,
    # so no permission dance). Uses the persistent embed server by default.
    export BULK_INGEST=1 ALLM_STORAGE="$ALLM_STORAGE"
    export EMBED_URL="http://127.0.0.1:${EMBED_PORT}/v1" EMBED_MODEL_NAME="embed-model"
    export EMBED_REQ_BATCH="${EMBED_REQ_BATCH:-64}" EMBED_CONCURRENCY="${EMBED_CONCURRENCY:-8}"
    export EMBED_CHUNK_WORDS EMBED_CHUNK_OVERLAP_WORDS EMBED_MAX_CHUNK_CHARS
}

# Run a harness tool (src/*.py) with the harness env, from the src dir, using the
# isolated venv python (pinned deps) — never the host's site-packages.
run_harness() {  # script.py [args...]
    export_harness_env
    ( cd "$BASE/src" && "$HARNESS_PY" "$@" )
}

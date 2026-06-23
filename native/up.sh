#!/usr/bin/env bash
# Bring the entire native stack up (no Docker): the two llama servers, LiteLLM,
# AnythingLLM (+collector), and the observability trio — each as a plain process.
# Then seed AnythingLLM and wait until the core path is healthy.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$NATIVE/services.sh"

[ -f "$ALLM_DIR/server/index.js" ] || die "AnythingLLM not built — run: native/setup.sh"

log "generating localhost configs ..."
gen_configs

log "starting services ..."
start_chat                 # baseline build (A/B swaps this; see run_ab.sh)
start_embed
start_litellm
start_anythingllm
start_collector
start_prometheus
start_pushgateway
start_grafana

wait_core || { log "core service health check FAILED — inspect $LOGS/*.log"; exit 1; }

log "seeding AnythingLLM (api key + provider/chunk settings) ..."
seed_allm
sync_retrieval   # best-effort; the workspace is created on first ingest

cat <<EOF

[native] ✅ stack UP (all processes, zero Docker)
  AnythingLLM : http://127.0.0.1:${ALLM_PORT}
  LiteLLM     : http://127.0.0.1:${LITELLM_PORT}
  chat /embed : http://127.0.0.1:${CHAT_PORT} / ${EMBED_PORT}
  Prometheus  : http://127.0.0.1:${PROM_PORT}
  Grafana     : http://127.0.0.1:${GRAFANA_PORT}  (admin/admin)
  logs        : ${LOGS}/    pids: ${RUN}/

Next:  native/ingest.sh   then   native/evaluate.sh && native/report.sh
       (or:  make -C native all)
EOF

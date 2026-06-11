#!/usr/bin/env bash
# Bring up the full benchmark stack for one build:
#   embed llama-server -> chat llama-server -> LiteLLM -> Prometheus -> AnythingLLM
# usage: ./start_services.sh <baseline|zendnn>
set -eo pipefail
. "$(dirname "$0")/scripts/lib.sh"

BUILD="${1:-baseline}"
case "$BUILD" in baseline|zendnn) ;; *) die "usage: start_services.sh <baseline|zendnn>" ;; esac

log "=== bringing up stack ($BUILD) ==="
"$BASE/scripts/start_embed.sh"  "$BUILD"
"$BASE/scripts/start_chat.sh"   "$BUILD"
"$BASE/scripts/start_litellm.sh"          # after backends — health check needs them
"$BASE/scripts/start_prometheus.sh"
"$BASE/scripts/start_anythingllm.sh"

echo
log "=== stack up ==="
printf '  %-22s :%s\n' \
    "embed llama-server"  "$EMBED_PORT" \
    "chat llama-server"   "$CHAT_PORT" \
    "litellm proxy"       "$LITELLM_PORT" \
    "prometheus"          "$PROM_PORT" \
    "anythingllm"         "$ALLM_PORT"

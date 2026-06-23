#!/usr/bin/env bash
# Show which native services are running + a quick health probe of each.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$NATIVE/services.sh"

probe() { curl -fsS -m 3 "$1" >/dev/null 2>&1 && echo "healthy" || echo "-"; }

declare -A URL=(
  [llama-chat]="http://127.0.0.1:${CHAT_PORT}/health"
  [llama-embed]="http://127.0.0.1:${EMBED_PORT}/health"
  [litellm]="http://127.0.0.1:${LITELLM_PORT}/health/readiness"
  [anythingllm]="http://127.0.0.1:${ALLM_PORT}/api/ping"
  [prometheus]="http://127.0.0.1:${PROM_PORT}/-/ready"
  [pushgateway]="http://127.0.0.1:${PUSHGW_PORT}/-/ready"
  [grafana]="http://127.0.0.1:${GRAFANA_PORT}/api/health"
)
printf "%-13s %-10s %-9s %s\n" SERVICE STATE HEALTH PID
for s in llama-chat llama-embed litellm anythingllm collector prometheus pushgateway grafana; do
  if is_running "$s"; then state=RUNNING; pid="$(cat "$(pidfile "$s")")"; else state=stopped; pid="-"; fi
  health="${URL[$s]:+$(probe "${URL[$s]}")}"; health="${health:-n/a}"
  [ "$state" = stopped ] && health="-"
  printf "%-13s %-10s %-9s %s\n" "$s" "$state" "$health" "$pid"
done

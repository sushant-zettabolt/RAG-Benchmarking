#!/usr/bin/env bash
# Start Prometheus (docker, host network) scraping LiteLLM + both llama-servers.
# usage: scripts/start_prometheus.sh
set -eo pipefail
. "$(dirname "$0")/lib.sh"

render_conf
docker rm -f "$PROM_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$PROM_CONTAINER" --network host \
    -v "$BASE/conf/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
    "$PROM_IMAGE" \
    --config.file=/etc/prometheus/prometheus.yml \
    --web.listen-address=":$PROM_PORT" >/dev/null

wait_http "http://127.0.0.1:$PROM_PORT/-/ready" 60 || { echo "PROMETHEUS DOWN"; docker logs --tail 20 "$PROM_CONTAINER"; exit 1; }
log "prometheus up on :$PROM_PORT"
curl -s "http://127.0.0.1:$PROM_PORT/api/v1/targets" | python3 -c "
import sys, json
for t in json.load(sys.stdin)['data']['activeTargets']:
    print(' ', t['labels']['job'], '->', t['health'])" 2>/dev/null || true

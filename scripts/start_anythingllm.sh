#!/usr/bin/env bash
# Start AnythingLLM (docker, host network). If the container is already
# running it is left alone — its LanceDB vectors and SQLite settings live in
# allm_storage/ and must persist across benchmark jobs.
# usage: scripts/start_anythingllm.sh [--recreate]
set -eo pipefail
. "$(dirname "$0")/lib.sh"

if [ "${1:-}" != "--recreate" ] && docker ps --format '{{.Names}}' | grep -qx "$ALLM_CONTAINER"; then
    log "anythingllm already running — leaving it (use --recreate to force)"
    exit 0
fi

render_conf
mkdir -p "$BASE/allm_storage"
# container runs as uid 1000 and needs write access to the bind mount
chmod -R a+rwX "$BASE/allm_storage" 2>/dev/null || \
    docker run --rm -v "$BASE/allm_storage:/fix" alpine sh -c "chmod -R 777 /fix && chown -R 1000:1000 /fix"

docker rm -f "$ALLM_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$ALLM_CONTAINER" --network host \
    --cap-add SYS_ADMIN \
    --env-file "$BASE/conf/anythingllm.env" \
    -v "$BASE/allm_storage:/app/server/storage" \
    "$ALLM_IMAGE" >/dev/null

wait_http "http://127.0.0.1:$ALLM_PORT/api/ping" 120 || { echo "ANYTHINGLLM DOWN"; docker logs --tail 30 "$ALLM_CONTAINER"; exit 1; }
log "anythingllm up on :$ALLM_PORT"

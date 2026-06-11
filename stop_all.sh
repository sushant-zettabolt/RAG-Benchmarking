#!/usr/bin/env bash
# Stop every benchmark service (llama-servers, LiteLLM, docker containers).
# allm_storage/ and results/ are left intact.
. "$(dirname "$0")/scripts/lib.sh"

for p in chat embed litellm; do
    if [ -f "$RESULTS_DIR/$p.pid" ]; then
        kill "$(cat "$RESULTS_DIR/$p.pid")" 2>/dev/null && echo "stopped $p" || true
        rm -f "$RESULTS_DIR/$p.pid"
    fi
done
docker rm -f "$PROM_CONTAINER" "$ALLM_CONTAINER" 2>/dev/null || true
echo "teardown complete"

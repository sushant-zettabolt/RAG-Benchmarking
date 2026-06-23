#!/usr/bin/env bash
# Stop every native service (kills each process group tracked in native/run/).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$NATIVE/services.sh"
log "stopping native stack ..."
stop_all
log "native stack stopped."
